import BulchimbeonCore
import Foundation
import IOKit.ps

enum SystemProbes {
    /// 내장 배터리 상태. 데스크톱 맥이면 nil.
    static func battery() -> BatteryStatus? {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef]
        else { return nil }

        for source in sources {
            guard let info = IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue() as? [String: Any],
                  info[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                  let current = info[kIOPSCurrentCapacityKey] as? Int
            else { continue }
            let max = (info[kIOPSMaxCapacityKey] as? Int).flatMap { $0 > 0 ? $0 : nil } ?? 100
            let onBattery = info[kIOPSPowerSourceStateKey] as? String == kIOPSBatteryPowerValue
            return BatteryStatus(percent: current * 100 / max, onBattery: onBattery)
        }
        return nil
    }

    /// 현재 떠 있는 에이전트 프로세스 수.
    static func agents() -> [AgentKind: Int] {
        guard let output = run("/bin/ps", ["-Axo", "args="]) else { return [:] }
        return AgentCatalog.count(psOutput: output)
    }

    /// `pmset -g` 의 SleepDisabled (덮개 모드 전역 플래그)
    static func lidSleepDisabled() -> Bool {
        guard let output = run("/usr/bin/pmset", ["-g"]) else { return false }
        return PmsetParser.sleepDisabled(output)
    }

    /// `pmset -a disablesleep` 변경. 관리자 암호 프롬프트가 뜬다. 취소하면 false.
    ///
    /// 보안: 스크립트에 들어가는 가변 값은 Bool 에서 나온 "0"/"1" 뿐이라 셸 인젝션 여지가 없다.
    /// 프롬프트에 실행할 명령을 그대로 보여줘, 사용자가 무엇에 암호를 주는지 알 수 있게 한다.
    static func setLidSleepDisabled(_ disabled: Bool) -> Bool {
        let command = "/usr/bin/pmset -a disablesleep \(disabled ? 1 : 0)"
        let prompt = "불침번이 덮개 잠자기 설정을 바꾸려 합니다.\n실행 명령: \(command)"
        let script = "do shell script \"\(command)\" with prompt \"\(prompt)\" with administrator privileges"
        return run("/usr/bin/osascript", ["-e", script]) != nil
    }

    /// 실행 후 stdout 반환. 종료 코드가 0이 아니면 nil.
    @discardableResult
    static func run(_ path: String, _ arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        // 앱 환경(DYLD_*, 사용자 PATH 등)을 넘기지 않는다. LANG=C 로 출력 형식도 고정.
        process.environment = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "LANG": "C"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        // 파이프 버퍼가 차서 멈추지 않도록 종료 대기 전에 먼저 읽는다
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return String(decoding: data, as: UTF8.self)
    }
}
