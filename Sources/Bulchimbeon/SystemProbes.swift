import BulchimbeonCore
import Foundation
import Darwin
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
    static func agents(custom: [String] = []) -> [AgentKind: Int] {
        AgentCatalog.count(ProcessScanner.snapshots(), kinds: AgentCatalog.builtIn + AgentCatalog.customKinds(custom))
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

/// libproc 기반 프로세스 수집.
///
/// 보안·이식성:
/// - `ps` 출력 파싱 대신 시스템 API 를 직접 쓴다 (출력 형식·잘림·로케일 영향 없음)
/// - 현재 사용자(UID) 프로세스만 본다 — 다른 사용자·root 프로세스의 명령줄은 읽지 않는다
/// - argv 는 러너(node 등)일 때만 앞 8개, 그 외엔 argv[0] 만. 환경변수 영역은 파싱하지 않고 버퍼는 즉시 0 으로 지운다
/// - 결과는 메모리에서 판별에만 쓰고 저장·기록하지 않는다
enum ProcessScanner {
    /// `Bulchimbeon --diagnose`: 감지 결과와 근거를 출력한다. 명령줄 인자는 출력하지 않는다.
    static func diagnose(custom: [String]) -> String {
        let kinds = AgentCatalog.builtIn + AgentCatalog.customKinds(custom)
        let processes = snapshots()
        var lines = ["불침번 에이전트 감지 진단 (UID \(getuid()) 프로세스 \(processes.count)개 검사)", ""]
        for process in processes {
            guard let (kind, reason) = AgentCatalog.match(process, kinds: kinds) else { continue }
            lines.append("  ✔ \(kind.displayName)  pid \(process.pid)  근거: \(reason.rawValue)")
            lines.append("      실행 파일: \(process.executablePath)")
        }
        if lines.count == 2 { lines.append("  감지된 에이전트 없음") }
        lines += ["", "사용자 지정 에이전트: \(custom.isEmpty ? "없음" : custom.joined(separator: ", "))",
                  "추가: defaults write io.github.s3onghyun.bulchimbeon customAgents -array <실행 파일 이름>"]
        return lines.joined(separator: "\n")
    }

    static func snapshots() -> [ProcessSnapshot] {
        let uid = getuid()
        let byteCount = proc_listpids(UInt32(PROC_UID_ONLY), uid, nil, 0)
        guard byteCount > 0 else { return [] }

        var pids = [pid_t](repeating: 0, count: Int(byteCount) / MemoryLayout<pid_t>.stride + 64)
        let filled = pids.withUnsafeMutableBytes {
            proc_listpids(UInt32(PROC_UID_ONLY), uid, $0.baseAddress, Int32($0.count))
        }
        return pids.prefix(Int(filled) / MemoryLayout<pid_t>.stride)
            .filter { $0 > 0 }
            .compactMap(snapshot)
    }

    private static func snapshot(_ pid: pid_t) -> ProcessSnapshot? {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4) // PROC_PIDPATHINFO_MAXSIZE
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
        let path = String(cString: buffer)
        let limit = AgentCatalog.needsFullArguments(executablePath: path) ? 8 : 1
        return ProcessSnapshot(pid: pid, executablePath: path, arguments: arguments(pid, limit: limit))
    }

    private static func arguments(_ pid: pid_t, limit: Int) -> [String] {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > 0 else { return [] }
        var bytes = [UInt8](repeating: 0, count: size)
        defer { bytes.withUnsafeMutableBytes { _ = memset_s($0.baseAddress, $0.count, 0, $0.count) } }
        guard sysctl(&mib, 3, &bytes, &size, nil, 0) == 0 else { return [] }
        return ProcArgs.parse(Array(bytes.prefix(size)), limit: limit)
    }
}
