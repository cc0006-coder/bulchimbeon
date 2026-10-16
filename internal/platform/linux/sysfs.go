//go:build linux

package linux

import (
	"os"
	"path/filepath"
	"sort"
	"strconv"
	"strings"

	"github.com/s3onghyun/bulchimbeon/internal/engine"
	"github.com/s3onghyun/bulchimbeon/internal/platform"
)

// PowerSupply reads the battery from /sys/class/power_supply.
type PowerSupply struct{ Root string }

// NewPowerSupply reads the real sysfs.
func NewPowerSupply() *PowerSupply { return &PowerSupply{Root: "/sys/class/power_supply"} }

// Battery implements platform.BatterySource. A machine without a system battery (desktop,
// mini PC) returns nil. Peripheral batteries (scope "Device": mice, headsets) are ignored.
// It is on battery when the battery discharges and no mains or USB supply is online.
func (p *PowerSupply) Battery() (*engine.BatteryStatus, error) {
	entries, err := os.ReadDir(p.Root)
	if os.IsNotExist(err) {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	names := make([]string, 0, len(entries))
	for _, e := range entries {
		names = append(names, e.Name())
	}
	sort.Strings(names)

	var battery *engine.BatteryStatus
	externalOnline := false
	for _, name := range names {
		dir := filepath.Join(p.Root, name)
		switch readTrim(dir, "type") {
		case "Battery":
			if battery != nil || readTrim(dir, "scope") == "Device" {
				continue
			}
			capacity, err := strconv.Atoi(readTrim(dir, "capacity"))
			if err != nil {
				continue
			}
			battery = &engine.BatteryStatus{Percent: min(max(capacity, 0), 100),
				OnBattery: readTrim(dir, "status") == "Discharging"}
		case "Mains", "USB", "USB_C", "USB_PD":
			if readTrim(dir, "online") == "1" {
				externalOnline = true
			}
		}
	}
	if battery != nil && externalOnline {
		battery.OnBattery = false
	}
	return battery, nil
}

// Thermal reads the CPU temperature from hwmon, or from thermal zones as a fallback.
type Thermal struct{ HwmonRoot, ZoneRoot string }

// NewThermal reads the real sysfs.
func NewThermal() *Thermal {
	return &Thermal{HwmonRoot: "/sys/class/hwmon", ZoneRoot: "/sys/class/thermal"}
}

// cpuSensors are hwmon drivers for the CPU package, best first.
var cpuSensors = []string{"coretemp", "k10temp", "zenpower", "cpu_thermal", "soc_thermal"}

// defaultCritical is used when the sensor reports no critical temperature.
const defaultCritical = 100.0

// Thermal implements platform.ThermalSource.
func (t *Thermal) Thermal() platform.ThermalReading {
	if r, ok := t.hwmon(); ok {
		return r
	}
	if r, ok := t.zone(); ok {
		return r
	}
	return platform.ThermalReading{Level: engine.HeatNormal, LevelName: engine.HeatNormal.String()}
}

func (t *Thermal) hwmon() (platform.ThermalReading, bool) {
	dirs, _ := filepath.Glob(filepath.Join(t.HwmonRoot, "hwmon*"))
	sort.Strings(dirs)
	for _, want := range cpuSensors {
		for _, dir := range dirs {
			if readTrim(dir, "name") != want {
				continue
			}
			inputs, _ := filepath.Glob(filepath.Join(dir, "temp*_input"))
			hottest, crit, found := 0.0, 0.0, false
			for _, in := range inputs {
				c, ok := milli(readTrim(filepath.Dir(in), filepath.Base(in)))
				if !ok {
					continue
				}
				if !found || c > hottest {
					hottest, found = c, true
					crit, _ = milli(readTrim(dir, strings.TrimSuffix(filepath.Base(in), "_input")+"_crit"))
				}
			}
			if found {
				return reading(want, hottest, crit), true
			}
		}
	}
	return platform.ThermalReading{}, false
}

func (t *Thermal) zone() (platform.ThermalReading, bool) {
	zones, _ := filepath.Glob(filepath.Join(t.ZoneRoot, "thermal_zone*"))
	sort.Strings(zones)
	var best platform.ThermalReading
	found := false
	for _, z := range zones {
		c, ok := milli(readTrim(z, "temp"))
		if !ok {
			continue
		}
		crit := 0.0
		trips, _ := filepath.Glob(filepath.Join(z, "trip_point_*_type"))
		for _, trip := range trips {
			if readTrim(filepath.Dir(trip), filepath.Base(trip)) == "critical" {
				crit, _ = milli(readTrim(z, strings.TrimSuffix(filepath.Base(trip), "_type")+"_temp"))
			}
		}
		r := reading(readTrim(z, "type"), c, crit)
		if !found || r.Celsius > best.Celsius {
			best, found = r, true
		}
	}
	return best, found
}

func reading(sensor string, celsius, crit float64) platform.ThermalReading {
	if crit < 40 || crit > 150 { // missing or nonsense (disabled trip points read -274 °C)
		crit = defaultCritical
	}
	level := HeatFromTemperature(celsius, crit)
	return platform.ThermalReading{Level: level, LevelName: level.String(), Sensor: sensor,
		Celsius: celsius, CritCelsius: crit, Available: true}
}

// HeatFromTemperature maps a temperature onto the heat levels by its distance to the
// critical temperature, because Linux has no thermal-state API like macOS:
// within 5 °C → alert (combat rest), 15 °C → advisory, 25 °C → caution.
func HeatFromTemperature(celsius, crit float64) engine.HeatLevel {
	switch margin := crit - celsius; {
	case margin <= 5:
		return engine.HeatAlert
	case margin <= 15:
		return engine.HeatAdvisory
	case margin <= 25:
		return engine.HeatCaution
	}
	return engine.HeatNormal
}

func milli(s string) (float64, bool) {
	v, err := strconv.ParseInt(s, 10, 64)
	if err != nil {
		return 0, false
	}
	return float64(v) / 1000, true
}

func readTrim(dir, name string) string {
	data, err := os.ReadFile(filepath.Join(dir, name))
	if err != nil {
		return ""
	}
	return strings.TrimSpace(string(data))
}
