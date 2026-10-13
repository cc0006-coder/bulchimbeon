import AppKit
import BulchimbeonCore

/// 순찰 모드: 메뉴바 바로 아래, 화면 맨 위를 이등병이 돌아다니는 투명 오버레이.
/// 클릭은 모두 통과하고, 마우스가 다가오면 반투명해져 비켜준다.
@MainActor
final class PatrolController: ObservableObject {
    static let shared = PatrolController(duty: .shared)
    static let scales = [2, 3]

    @Published var enabled: Bool {
        didSet { defaults.set(enabled, forKey: Keys.enabled); refreshVisibility() }
    }
    @Published var scale: Int {
        didSet { defaults.set(scale, forKey: Keys.scale); layoutWindow() }
    }

    private enum Keys {
        static let enabled = "patrolEnabled"
        static let scale = "patrolScale"
    }

    private let duty: DutyController
    private let defaults = UserDefaults.standard
    private let view = PatrolView()
    private var panel: NSPanel?
    private var timer: Timer?
    private var lastStep = Date()
    private var clock: TimeInterval = 0
    private var x: CGFloat = -1 // 스프라이트 왼쪽 끝 (창 좌표). -1 = 아직 배치 전
    private var facingRight = false

    private let walkSpeed: CGFloat = 45 // pt/s
    private let margin: CGFloat = 24

    private init(duty: DutyController) {
        self.duty = duty
        enabled = defaults.object(forKey: Keys.enabled) as? Bool ?? true
        let storedScale = defaults.object(forKey: Keys.scale) as? Int ?? 2
        scale = Self.scales.contains(storedScale) ? storedScale : 2
    }

    func start() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { _ in MainActor.assumeIsolated { PatrolController.shared.layoutWindow() } }

        scheduleTimer(interval: Self.idleInterval)
    }

    // 보일 때만 20fps, 숨겨져 있으면 1초에 한 번만 깨어나 상태를 확인한다 (에너지)
    private static let activeInterval: TimeInterval = 1.0 / 20
    private static let idleInterval: TimeInterval = 1

    private func scheduleTimer(interval: TimeInterval) {
        guard timer?.timeInterval != interval else { return }
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in
            MainActor.assumeIsolated { PatrolController.shared.step() }
        }
        timer?.tolerance = interval * 0.2
    }

    // MARK: - 창

    private var spriteSize: CGFloat { CGFloat(16 * scale) }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.level = .statusBar
        // .fullScreenAuxiliary 를 빼서 전체화면 앱(발표·화면 공유·영상) 위에는 나타나지 않게 한다
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        panel.contentView = view
        return panel
    }

    private func layoutWindow() {
        guard let panel, let screen = NSScreen.screens.first else { return }
        // 메뉴바 바로 아래, 화면 전체 폭
        let frame = NSRect(x: screen.frame.minX, y: screen.visibleFrame.maxY - spriteSize,
                           width: screen.frame.width, height: spriteSize)
        panel.setFrame(frame, display: true)
        if x >= 0 { x = min(max(x, margin), maxX) } // 첫 배치(-1)는 refreshVisibility 가 구석으로
    }

    private var maxX: CGFloat { (panel?.frame.width ?? 0) - spriteSize - margin }
    private var cornerX: CGFloat { maxX }

    private func refreshVisibility() {
        let visible = enabled && duty.pose != .sleeping
        if visible {
            if panel == nil {
                panel = makePanel()
                layoutWindow()
            }
            if x < 0 { x = cornerX }
            panel?.orderFrontRegardless()
        } else {
            panel?.orderOut(nil)
        }
    }

    // MARK: - 애니메이션 (20fps)

    private func step() {
        let now = Date()
        let dt = min(now.timeIntervalSince(lastStep), 0.2)
        lastStep = now
        refreshVisibility()
        let visible = panel?.isVisible == true
        scheduleTimer(interval: visible ? Self.activeInterval : Self.idleInterval)
        guard visible, let panel else { return }
        clock += dt

        let sprite: PixelSprite
        switch duty.pose {
        case .duty:
            // 좌우 왕복 순찰
            x += (facingRight ? 1 : -1) * walkSpeed * CGFloat(dt)
            if x >= maxX { x = maxX; facingRight = false }
            if x <= margin { x = margin; facingRight = true }
            sprite = walkFrame()
        case .standby where abs(x - cornerX) > 1:
            // 대기 위치(오른쪽 구석)로 걸어간다
            facingRight = cornerX > x
            let move = walkSpeed * CGFloat(dt)
            x = abs(cornerX - x) <= move ? cornerX : x + (facingRight ? move : -move)
            sprite = walkFrame()
        case .standby, .salute, .patrol, .sleeping, .heat:
            sprite = frame(of: duty.pose, interval: 0.5)
        }

        view.sprite = sprite
        view.speech = duty.currentSpeech
        view.spriteX = x
        view.pixel = CGFloat(scale)
        view.needsDisplay = true

        // 마우스가 근처에 오면 반투명하게 비켜준다
        let spriteRect = NSRect(x: panel.frame.minX + x, y: panel.frame.minY,
                                width: spriteSize, height: spriteSize).insetBy(dx: -24, dy: -24)
        let target: CGFloat = spriteRect.contains(NSEvent.mouseLocation) ? 0.2 : 1
        if abs(panel.alphaValue - target) > 0.01 {
            panel.alphaValue += (target - panel.alphaValue) * 0.3
        }
    }

    private func walkFrame() -> PixelSprite {
        let sprite = frame(of: .patrol, interval: 0.25)
        return facingRight ? sprite : sprite.mirrored()
    }

    private func frame(of pose: Sprites.Pose, interval: TimeInterval) -> PixelSprite {
        let frames = Sprites.frames(pose)
        return frames[Int(clock / interval) % frames.count]
    }
}

final class PatrolView: NSView {
    var sprite: PixelSprite?
    var speech: String?
    var spriteX: CGFloat = 0
    var pixel: CGFloat = 2

    override func draw(_ dirtyRect: NSRect) {
        guard let sprite, let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.clear(bounds)
        ctx.saveGState()
        ctx.setShouldAntialias(false)
        sprite.draw(in: ctx, origin: CGPoint(x: spriteX.rounded(), y: 0), pixel: pixel)
        ctx.restoreGState()
        if let speech { drawBubble(speech, spriteWidth: CGFloat(sprite.width) * pixel) }
    }

    /// 이등병 옆 말풍선. 오른쪽 공간이 모자라면 왼쪽에 띄운다.
    private func drawBubble(_ text: String, spriteWidth: CGFloat) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: max(11, pixel * 5.5), weight: .semibold),
            .foregroundColor: NSColor(red: 0.16, green: 0.14, blue: 0.19, alpha: 1),
        ]
        let size = (text as NSString).size(withAttributes: attributes)
        let width = size.width + 16, height = min(bounds.height - 2, size.height + 8), tail: CGFloat = 6
        let onRight = spriteX + spriteWidth + tail + width < bounds.width
        let bubbleX = onRight ? spriteX + spriteWidth + tail : spriteX - tail - width
        let rect = NSRect(x: bubbleX, y: (bounds.height - height) / 2 + 2, width: width, height: height)

        NSColor.white.setFill()
        NSBezierPath(roundedRect: rect, xRadius: height / 2, yRadius: height / 2).fill()
        let tailPath = NSBezierPath()
        let edge = onRight ? rect.minX : rect.maxX
        tailPath.move(to: NSPoint(x: edge, y: rect.midY + 4))
        tailPath.line(to: NSPoint(x: onRight ? edge - tail : edge + tail, y: rect.midY - 2))
        tailPath.line(to: NSPoint(x: edge, y: rect.midY - 4))
        tailPath.fill()
        (text as NSString).draw(at: NSPoint(x: rect.minX + 8, y: rect.minY + (height - size.height) / 2),
                                withAttributes: attributes)
    }
}
