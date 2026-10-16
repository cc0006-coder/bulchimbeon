import AppKit
import BulchimbeonCore

/// 순찰 모드: 메뉴바 바로 아래, 화면 맨 위를 이등병이 돌아다니는 투명 오버레이.
/// 클릭은 모두 통과하고, 마우스가 다가오면 반투명해져 비켜준다 (마우스 위치는 보일 때만 0.5초마다 확인).
///
/// 에너지: 걷기·프레임 교체는 Core Animation(화면 합성기)에 통째로 맡긴다.
/// 앱은 "여기서 저기까지 N초 동안 걸어" 한 번만 지시하고, 끝에 도착했을 때와 상태가 바뀔 때만 깨어난다.
/// (실측: 앱이 15fps 로 직접 위치를 옮기던 방식은 5초당 ~330회 깨어남 → 이슈 #1)
@MainActor
final class PatrolController: ObservableObject {
    static let shared = PatrolController(duty: .shared)
    static let scales = SettingsValues.patrolScales

    @Published var enabled: Bool {
        didSet { defaults.set(enabled, forKey: Keys.enabled); stateTick() }
    }
    @Published var scale: Int {
        didSet { defaults.set(scale, forKey: Keys.scale); layoutWindow(); restartMotion() }
    }

    private enum Keys {
        static let enabled = SettingsKey.patrolEnabled.rawValue
        static let scale = SettingsKey.patrolScale.rawValue
    }

    private let duty: DutyController
    private let defaults = UserDefaults.standard
    private let view = PatrolView()
    private var panel: NSPanel?
    private var stateTimer: Timer?
    private var legTimer: Timer?
    private var mouseTimer: Timer?
    private var currentPose: Sprites.Pose?
    private var facingRight = false
    private var placed = false

    private let walkSpeed: CGFloat = 45 // pt/s
    private let margin: CGFloat = 24

    private init(duty: DutyController) {
        self.duty = duty
        enabled = defaults.object(forKey: Keys.enabled) as? Bool ?? true
        let storedScale = defaults.object(forKey: Keys.scale) as? Int ?? SettingsValues.defaultPatrolScale
        scale = Self.scales.contains(storedScale) ? storedScale : SettingsValues.defaultPatrolScale
        view.theme = SpriteImages.theme
    }

    func start() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { _ in MainActor.assumeIsolated { PatrolController.shared.layoutWindow(); PatrolController.shared.restartMotion() } }

        // 포즈·말풍선·표시 여부만 1초에 한 번 확인 (애니메이션은 화면 합성기가 돌린다)
        let timer = Timer(timeInterval: 1, repeats: true) { _ in
            MainActor.assumeIsolated { PatrolController.shared.stateTick() }
        }
        timer.tolerance = 0.3
        RunLoop.main.add(timer, forMode: .common)
        stateTimer = timer

        stateTick()
    }

    // MARK: - 창

    private var spriteSize: CGFloat { CGFloat(16 * scale) }
    private var maxX: CGFloat { (panel?.frame.width ?? 0) - spriteSize - margin }
    private var cornerX: CGFloat { maxX }

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
        panel.setFrame(NSRect(x: screen.frame.minX, y: screen.visibleFrame.maxY - spriteSize,
                              width: screen.frame.width, height: spriteSize), display: true)
        view.pixel = CGFloat(scale)
    }

    private func refreshVisibility() {
        let visible = enabled && duty.pose != .sleeping
        if visible {
            if panel == nil {
                panel = makePanel()
                layoutWindow()
            }
            if !placed { view.place(at: cornerX); placed = true } // 첫 등장은 오른쪽 구석
            panel?.orderFrontRegardless()
            startMouseWatch()
        } else {
            panel?.orderOut(nil)
            currentPose = nil
            legTimer?.invalidate()
            mouseTimer?.invalidate()
            mouseTimer = nil
        }
    }

    // MARK: - 상태 (1초마다)

    private func stateTick() {
        refreshVisibility()
        guard panel?.isVisible == true else { return }
        let pose = duty.pose
        if pose != currentPose {
            currentPose = pose
            restartMotion()
        }
        view.setSpeech(duty.currentSpeech)
    }

    // MARK: - 움직임 (화면 합성기에 위임)

    private func restartMotion() {
        guard panel?.isVisible == true, let pose = currentPose else { return }
        legTimer?.invalidate()
        let x = min(max(view.currentX, margin), maxX)
        switch pose {
        case .duty:
            walk(from: x, to: facingRight ? maxX : margin)
        case .standby where abs(x - cornerX) > 1:
            walk(from: x, to: cornerX) // 대기 위치(오른쪽 구석)로 걸어간 뒤 두리번
        case .standby, .salute, .patrol, .sleeping, .heat:
            view.stand(at: x, frames: Sprites.frames(pose, theme: view.theme), interval: 0.5)
        }
    }

    private func walk(from x: CGFloat, to target: CGFloat) {
        facingRight = target > x
        let frames = Sprites.frames(.patrol, theme: view.theme).map { facingRight ? $0 : $0.mirrored() }
        let duration = max(0.1, abs(target - x) / walkSpeed)
        view.walk(from: x, to: target, duration: duration, frames: frames, interval: 0.25)
        let timer = Timer(timeInterval: duration, repeats: false) { _ in
            MainActor.assumeIsolated { PatrolController.shared.arrived() }
        }
        RunLoop.main.add(timer, forMode: .common)
        legTimer = timer
    }

    /// 군복이 바뀌면 지금 동작을 새 옷으로 다시 시작
    func redress() {
        view.theme = SpriteImages.theme
        restartMotion()
    }

    /// 끝(또는 대기 위치)에 도착: 근무 중이면 돌아서고, 대기면 두리번
    private func arrived() {
        guard let pose = currentPose else { return }
        if pose == .duty { facingRight.toggle() }
        restartMotion()
    }

    // MARK: - 마우스

    /// 이등병이 보일 때만 초당 2번 마우스 위치를 본다.
    /// (실측: 전역 mouseMoved 감시는 마우스를 쓰는 동안 이벤트가 초당 수십 번 와서 깨어남이 줄지 않았다)
    private func startMouseWatch() {
        guard mouseTimer == nil else { return }
        let timer = Timer(timeInterval: 0.5, repeats: true) { _ in
            MainActor.assumeIsolated { PatrolController.shared.fadeForMouse() }
        }
        timer.tolerance = 0.2
        RunLoop.main.add(timer, forMode: .common)
        mouseTimer = timer
    }

    private func fadeForMouse() {
        guard let panel, panel.isVisible else { return }
        let spriteRect = NSRect(x: panel.frame.minX + view.currentX, y: panel.frame.minY,
                                width: spriteSize, height: spriteSize).insetBy(dx: -24, dy: -24)
        let target: CGFloat = spriteRect.contains(NSEvent.mouseLocation) ? 0.2 : 1
        guard abs(panel.alphaValue - target) > 0.01 else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            panel.animator().alphaValue = target
        }
    }
}

/// 순찰 오버레이 뷰. 이등병은 미리 렌더링한 이미지 레이어, 걷기·프레임 교체는 Core Animation 이 돌린다.
/// 말풍선은 이등병 레이어의 하위 레이어라 함께 움직인다.
final class PatrolView: NSView {
    private let soldier = CALayer()
    private let bubble = CALayer()
    private var spriteCache: [String: CGImage] = [:]
    private var speech: String?
    /// 입은 군복. 이미지 캐시 키에 들어가므로 바뀌면 다음 프레임부터 새 옷으로 그려진다.
    var theme: UniformTheme = .default
    var pixel: CGFloat = 2 {
        didSet { soldier.bounds = CGRect(x: 0, y: 0, width: 16 * pixel, height: 16 * pixel) }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer = CALayer()
        soldier.magnificationFilter = .nearest // 픽셀아트는 보간 없이
        soldier.anchorPoint = .zero
        soldier.bounds = CGRect(x: 0, y: 0, width: 32, height: 32)
        bubble.anchorPoint = .zero
        bubble.isHidden = true
        soldier.addSublayer(bubble)
        layer?.addSublayer(soldier)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// 지금 화면에 보이는 위치 (애니메이션 중이면 진행 중인 값)
    var currentX: CGFloat { soldier.presentation()?.position.x ?? soldier.position.x }

    func place(at x: CGFloat) {
        CATransaction.begin(); CATransaction.setDisableActions(true)
        soldier.position = CGPoint(x: x, y: 0)
        CATransaction.commit()
    }

    func walk(from x: CGFloat, to target: CGFloat, duration: TimeInterval, frames: [PixelSprite], interval: TimeInterval) {
        CATransaction.begin(); CATransaction.setDisableActions(true)
        soldier.removeAnimation(forKey: "move")
        soldier.position = CGPoint(x: target, y: 0) // 최종 값
        let move = CABasicAnimation(keyPath: "position.x")
        move.fromValue = x
        move.toValue = target
        move.duration = duration
        move.timingFunction = CAMediaTimingFunction(name: .linear)
        soldier.add(move, forKey: "move")
        setFrames(frames, interval: interval)
        CATransaction.commit()
    }

    func stand(at x: CGFloat, frames: [PixelSprite], interval: TimeInterval) {
        CATransaction.begin(); CATransaction.setDisableActions(true)
        soldier.removeAnimation(forKey: "move")
        soldier.position = CGPoint(x: x, y: 0)
        setFrames(frames, interval: interval)
        CATransaction.commit()
    }

    private func setFrames(_ frames: [PixelSprite], interval: TimeInterval) {
        let images = frames.compactMap(image(for:))
        soldier.removeAnimation(forKey: "frames")
        soldier.contents = images.first
        guard images.count > 1 else { return }
        let animation = CAKeyframeAnimation(keyPath: "contents")
        animation.values = images
        animation.calculationMode = .discrete
        animation.duration = interval * Double(images.count)
        animation.repeatCount = .infinity
        soldier.add(animation, forKey: "frames")
    }

    /// 말풍선. 화면 가운데보다 오른쪽에 있으면 왼쪽에 띄운다 (말풍선이 떠 있는 동안은 방향 고정).
    func setSpeech(_ text: String?) {
        guard text != speech else { return }
        speech = text
        CATransaction.begin(); CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        guard let text else { bubble.isHidden = true; return }

        let scale = window?.backingScaleFactor ?? 2
        let onLeft = currentX > bounds.midX
        guard let rendered = Self.renderBubble(text, fontSize: max(11, pixel * 5.5), maxHeight: bounds.height - 2,
                                               scale: scale, tailOnRight: onLeft) else { return }
        let size = soldier.bounds.width
        bubble.contents = rendered.image
        bubble.contentsScale = scale
        bubble.bounds = CGRect(origin: .zero, size: rendered.size)
        bubble.position = CGPoint(x: onLeft ? -2 - rendered.size.width : size + 2,
                                  y: (soldier.bounds.height - rendered.size.height) / 2 + 2)
        bubble.isHidden = false
    }

    private func image(for sprite: PixelSprite) -> CGImage? {
        let key = theme.id + ":" + sprite.rows.joined()
        if let cached = spriteCache[key] { return cached }
        // 픽셀 1개 = 1px 로 렌더링하고, 확대는 레이어(nearest)가 맡는다
        guard let ctx = CGContext(data: nil, width: sprite.width, height: sprite.height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.setShouldAntialias(false)
        sprite.draw(in: ctx, pixel: 1, theme: theme)
        let image = ctx.makeImage()
        if spriteCache.count > 64 { spriteCache.removeAll() }
        spriteCache[key] = image
        return image
    }

    private static var bubbleCache: [String: (image: CGImage, size: CGSize)] = [:]

    /// 말풍선 이미지. 같은 문구는 캐시.
    static func renderBubble(_ text: String, fontSize: CGFloat, maxHeight: CGFloat, scale: CGFloat,
                             tailOnRight: Bool = false) -> (image: CGImage, size: CGSize)? {
        let key = "\(text)|\(fontSize)|\(maxHeight)|\(scale)|\(tailOnRight)"
        if let cached = bubbleCache[key] { return cached }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: fontSize, weight: .semibold),
            .foregroundColor: NSColor(red: 0.16, green: 0.14, blue: 0.19, alpha: 1),
        ]
        let textSize = (text as NSString).size(withAttributes: attributes)
        let tail: CGFloat = 6
        let bodyWidth = ceil(textSize.width + 16), height = ceil(min(maxHeight, textSize.height + 8))
        let size = CGSize(width: bodyWidth + tail, height: height)

        let image = NSImage(size: size, flipped: false) { _ in
            let body = NSRect(x: tailOnRight ? 0 : tail, y: 0, width: bodyWidth, height: height)
            NSColor.white.setFill()
            NSBezierPath(roundedRect: body, xRadius: height / 2, yRadius: height / 2).fill()
            let path = NSBezierPath()
            let edge = tailOnRight ? body.maxX : body.minX
            path.move(to: NSPoint(x: edge, y: body.midY + 4))
            path.line(to: NSPoint(x: tailOnRight ? edge + tail : edge - tail, y: body.midY - 2))
            path.line(to: NSPoint(x: edge, y: body.midY - 4))
            path.fill()
            (text as NSString).draw(at: NSPoint(x: body.minX + 8, y: (height - textSize.height) / 2), withAttributes: attributes)
            return true
        }
        var rect = CGRect(origin: .zero, size: CGSize(width: size.width * scale, height: size.height * scale))
        guard let cg = image.cgImage(forProposedRect: &rect, context: nil, hints: nil) else { return nil }
        if bubbleCache.count > 32 { bubbleCache.removeAll() }
        bubbleCache[key] = (cg, size)
        return (cg, size)
    }
}
