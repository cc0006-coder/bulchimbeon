import AppKit
import BulchimbeonCore

/// `--demo`: 홍보 영상 녹화용 연출. 실제 에이전트 상태와 무관하게 정해진 순서로 진행하고 종료한다.
/// 녹화 영역에만 밤하늘 배경을 깔아 뒤의 업무 화면이 찍히지 않게 한다.
@MainActor
enum DemoDirector {
    static let width: CGFloat = 1000
    static let height: CGFloat = 170

    /// `--demo-scale N` (2…6, 기본 3): 정사각형·세로 영상용으로 이등병을 더 크게
    private static var demoScale: Int {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--demo-scale"), i + 1 < args.count,
              let value = Int(args[i + 1]), (2...6).contains(value) else { return 3 }
        return value
    }

    static func run() {
        guard let screen = NSScreen.screens.first else { return }
        // 메뉴바 바로 아래, 화면 오른쪽 (알림 배너 위치 포함)
        let rect = NSRect(x: screen.frame.maxX - width, y: screen.visibleFrame.maxY - height,
                          width: width, height: height)
        let backdrop = makeBackdrop(rect)
        backdrop.orderFrontRegardless()

        // screencapture -R 은 좌상단 원점 좌표
        let topLeftY = screen.frame.maxY - rect.maxY
        print("DEMO_RECT \(Int(rect.minX)),\(Int(topLeftY)),\(Int(rect.width)),\(Int(rect.height))")
        fflush(stdout)

        Task { @MainActor in
            let duty = DutyController.shared
            let patrol = PatrolController.shared
            let originalScale = patrol.scale
            patrol.scale = demoScale // 홍보용으로 크게, 끝나면 사용자 설정 복원
            try? await Task.sleep(for: .seconds(2))   // 녹화 시작 여유
            await duty.playDemo()
            try? await Task.sleep(for: .seconds(2)) // 녹화가 끝날 때까지 배경 유지
            backdrop.orderOut(nil)
            patrol.scale = originalScale
            NSApp.terminate(nil)
        }
    }

    private static func makeBackdrop(_ rect: NSRect) -> NSWindow {
        let window = NSWindow(contentRect: rect, styleMask: .borderless, backing: .buffered, defer: false)
        window.level = .floating // 일반 창 위, 순찰 오버레이(.statusBar)·알림 아래
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .stationary]
        window.contentView = NightSkyView()
        return window
    }
}

private final class NightSkyView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        NSGradient(starting: NSColor(red: 0.18, green: 0.22, blue: 0.42, alpha: 1),
                   ending: NSColor(red: 0.07, green: 0.10, blue: 0.22, alpha: 1))?
            .draw(in: bounds, angle: 90)
        // 고정 좌표 별 (매 프레임 같은 위치)
        NSColor.white.withAlphaComponent(0.8).setFill()
        for (x, y) in [(60, 40), (180, 110), (320, 30), (470, 90), (610, 50), (720, 120), (860, 70), (940, 20)] {
            NSRect(x: x, y: y, width: 3, height: 3).fill()
        }
    }
}
