import Foundation

/// 감시 대상 AI 에이전트 한 종류.
public struct AgentKind: Hashable, Sendable {
    public let id: String
    public let displayName: String
    /// 실행 파일 basename (대소문자 구분)
    let binaryNames: Set<String>
    /// node/bun/deno 로 실행될 때 스크립트 경로에 포함되는 패키지 마커
    let packageMarkers: [String]
}

public enum AgentCatalog {
    public static let all: [AgentKind] = [
        AgentKind(id: "claude-code", displayName: "Claude Code",
                  binaryNames: ["claude"], packageMarkers: ["@anthropic-ai/claude-code"]),
        AgentKind(id: "codex", displayName: "Codex",
                  binaryNames: ["codex"], packageMarkers: ["@openai/codex"]),
        AgentKind(id: "gemini-cli", displayName: "Gemini CLI",
                  binaryNames: ["gemini"], packageMarkers: ["@google/gemini-cli"]),
        AgentKind(id: "aider", displayName: "Aider",
                  binaryNames: ["aider"], packageMarkers: []),
        AgentKind(id: "opencode", displayName: "OpenCode",
                  binaryNames: ["opencode"], packageMarkers: ["opencode-ai"]),
    ]

    private static let scriptRunners: Set<String> = ["node", "bun", "deno"]
    private static let inlineEvalFlags: Set<String> = ["-e", "--eval", "-p", "--print"]

    /// `ps -o args=` 한 줄을 에이전트로 판별한다.
    /// 부분 문자열 매칭은 하지 않는다 — hook 스크립트(`node -e "...'.claude'..."`)가 오탐되기 때문.
    public static func match(commandLine: String) -> AgentKind? {
        let tokens = commandLine.split(whereSeparator: \.isWhitespace).map(String.init)
        guard let executable = tokens.first else { return nil }
        let base = basename(executable)

        if let kind = all.first(where: { $0.binaryNames.contains(base) }) {
            return kind
        }
        guard scriptRunners.contains(base), tokens.count > 1 else { return nil }
        if inlineEvalFlags.contains(tokens[1]) { return nil }

        for token in tokens.dropFirst() where !token.hasPrefix("-") {
            if let kind = all.first(where: { k in k.packageMarkers.contains { token.contains($0) } }) {
                return kind
            }
        }
        return nil
    }

    /// `ps -Axo args=` 전체 출력에서 에이전트별 프로세스 수를 센다.
    public static func count(psOutput: String) -> [AgentKind: Int] {
        var counts: [AgentKind: Int] = [:]
        for line in psOutput.split(separator: "\n") {
            if let kind = match(commandLine: String(line)) {
                counts[kind, default: 0] += 1
            }
        }
        return counts
    }

    /// 메뉴 표시용 요약: "Claude Code ×3, Codex"
    public static func summary(_ counts: [AgentKind: Int]) -> String {
        all.compactMap { kind in
            guard let n = counts[kind], n > 0 else { return nil }
            return n > 1 ? "\(kind.displayName) ×\(n)" : kind.displayName
        }.joined(separator: ", ")
    }

    private static func basename(_ path: String) -> String {
        path.split(separator: "/").last.map(String.init) ?? path
    }
}
