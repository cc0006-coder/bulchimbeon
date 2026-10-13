import Foundation

/// 감시 대상 AI 에이전트 한 종류.
public struct AgentKind: Hashable, Sendable {
    public let id: String
    public let displayName: String
    /// 실행 파일·argv[0]·스크립트의 basename (대소문자 구분)
    let binaryNames: Set<String>
    /// 실행 파일 경로에 포함되는 설치 위치 마커 (예: 네이티브 설치본은 실행 파일 이름이 버전 번호)
    let pathMarkers: [String]
    /// node/bun/deno 로 실행될 때 스크립트 경로에 포함되는 패키지 마커
    let packageMarkers: [String]
}

/// 판별에 쓰는 프로세스 정보. 같은 사용자(UID)의 프로세스만 수집한다.
public struct ProcessSnapshot: Sendable {
    public let pid: Int32
    /// 실제 실행 파일 경로 (proc_pidpath)
    public let executablePath: String
    /// argv. 스크립트 러너(node 등)가 아니면 argv[0] 만 담긴다.
    public let arguments: [String]

    public init(pid: Int32 = 0, executablePath: String, arguments: [String]) {
        self.pid = pid
        self.executablePath = executablePath
        self.arguments = arguments
    }
}

public enum AgentCatalog {
    /// 판별 근거 (진단 출력용)
    public enum Reason: Sendable {
        case executableName, argv0, installPath, script

        public var label: String {
            switch self {
            case .executableName: L10n.t("실행 파일 이름", "executable name")
            case .argv0: L10n.t("실행 명령(argv[0])", "command (argv[0])")
            case .installPath: L10n.t("설치 경로", "install path")
            case .script: L10n.t("스크립트 경로", "script path")
            }
        }
    }

    public static let builtIn: [AgentKind] = [
        AgentKind(id: "claude-code", displayName: "Claude Code",
                  binaryNames: ["claude"],
                  pathMarkers: ["/.local/share/claude/versions/"], // 네이티브 설치: 실행 파일명이 "2.1.296" 같은 버전
                  packageMarkers: ["@anthropic-ai/claude-code"]),
        AgentKind(id: "codex", displayName: "Codex",
                  binaryNames: ["codex"], pathMarkers: [], packageMarkers: ["@openai/codex"]),
        AgentKind(id: "gemini-cli", displayName: "Gemini CLI",
                  binaryNames: ["gemini"], pathMarkers: [], packageMarkers: ["@google/gemini-cli"]),
        AgentKind(id: "cursor-agent", displayName: "Cursor Agent",
                  binaryNames: ["cursor-agent"], pathMarkers: [], packageMarkers: []),
        AgentKind(id: "copilot-cli", displayName: "Copilot CLI",
                  binaryNames: ["copilot"], pathMarkers: [], packageMarkers: ["@github/copilot"]),
        AgentKind(id: "aider", displayName: "Aider",
                  binaryNames: ["aider"], pathMarkers: [], packageMarkers: []),
        AgentKind(id: "opencode", displayName: "OpenCode",
                  binaryNames: ["opencode"], pathMarkers: [], packageMarkers: ["opencode-ai"]),
    ]

    private static let scriptRunners: Set<String> = ["node", "bun", "deno"]
    private static let inlineEvalFlags: Set<String> = ["-e", "--eval", "-p", "--print"]

    /// 러너일 때만 argv 전체가 필요하다. 그 외 프로세스는 argv[0] 만 읽는다 (최소 수집).
    public static func needsFullArguments(executablePath: String) -> Bool {
        scriptRunners.contains(basename(executablePath))
    }

    /// 프로세스 하나를 에이전트로 판별한다.
    /// 부분 문자열 매칭은 하지 않는다 — hook 스크립트(`node -e "...'.claude'..."`)가 오탐되기 때문.
    public static func match(_ process: ProcessSnapshot, kinds: [AgentKind] = builtIn) -> (kind: AgentKind, reason: Reason)? {
        let exeBase = basename(process.executablePath)
        let argv0Base = process.arguments.first.map(basename)

        for kind in kinds {
            if kind.binaryNames.contains(exeBase) { return (kind, .executableName) }
            if let argv0Base, kind.binaryNames.contains(argv0Base) { return (kind, .argv0) }
            if kind.pathMarkers.contains(where: process.executablePath.contains) { return (kind, .installPath) }
        }

        guard scriptRunners.contains(exeBase), process.arguments.count > 1,
              !inlineEvalFlags.contains(process.arguments[1]),
              let script = process.arguments.dropFirst().first(where: { !$0.hasPrefix("-") })
        else { return nil }

        // npm 전역 설치는 `node /opt/homebrew/bin/claude` 처럼 bin 링크 이름으로 실행된다
        let scriptBase = basename(script)
        for kind in kinds where kind.binaryNames.contains(scriptBase)
            || kind.packageMarkers.contains(where: script.contains) {
            return (kind, .script)
        }
        return nil
    }

    /// 에이전트별 프로세스 수
    public static func count(_ processes: [ProcessSnapshot], kinds: [AgentKind] = builtIn) -> [AgentKind: Int] {
        var counts: [AgentKind: Int] = [:]
        for process in processes {
            if let (kind, _) = match(process, kinds: kinds) { counts[kind, default: 0] += 1 }
        }
        return counts
    }

    /// 사용자 지정 에이전트 이름 → AgentKind. 이름 규칙에 맞지 않으면 버린다 (최대 16개).
    /// 예: `defaults write io.github.s3onghyun.bulchimbeon customAgents -array my-agent`
    public static func customKinds(_ names: [String]) -> [AgentKind] {
        var seen = Set<String>()
        var kinds: [AgentKind] = []
        for name in names where kinds.count < 16
            && name.range(of: #"^[A-Za-z0-9][A-Za-z0-9._-]{0,31}$"#, options: .regularExpression) != nil
            && seen.insert(name).inserted {
            kinds.append(AgentKind(id: "custom:\(name)", displayName: name, binaryNames: [name],
                                   pathMarkers: [], packageMarkers: []))
        }
        return kinds
    }

    /// 메뉴 표시용 요약: "Claude Code ×3, Codex"
    public static func summary(_ counts: [AgentKind: Int]) -> String {
        counts.filter { $0.value > 0 }
            .sorted { ($0.key.displayName, $0.key.id) < ($1.key.displayName, $1.key.id) }
            .map { $0.value > 1 ? "\($0.key.displayName) ×\($0.value)" : $0.key.displayName }
            .joined(separator: ", ")
    }

    static func basename(_ path: String) -> String {
        path.split(separator: "/").last.map(String.init) ?? path
    }
}

/// `sysctl(KERN_PROCARGS2)` 버퍼 파서.
/// 형식: [argc: Int32][exec_path\0][\0 패딩...][argv[0]\0 ... argv[argc-1]\0][환경변수...]
/// 환경변수 영역에는 절대 들어가지 않도록 argc·limit 에서 멈춘다.
public enum ProcArgs {
    public static func parse(_ bytes: [UInt8], limit: Int) -> [String] {
        guard bytes.count > 4, limit > 0 else { return [] }
        let argc = bytes.withUnsafeBytes { Int($0.loadUnaligned(as: Int32.self)) }
        guard argc > 0 else { return [] }

        var i = 4
        while i < bytes.count, bytes[i] != 0 { i += 1 } // exec_path
        while i < bytes.count, bytes[i] == 0 { i += 1 } // 패딩

        var args: [String] = []
        while i < bytes.count, args.count < min(argc, limit) {
            let start = i
            while i < bytes.count, bytes[i] != 0 { i += 1 }
            args.append(String(decoding: bytes[start..<i], as: UTF8.self))
            i += 1
        }
        return args
    }
}
