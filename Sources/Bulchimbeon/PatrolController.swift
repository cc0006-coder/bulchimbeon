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
    private static let activeInterval: TimeInterval = 1.0 / 15 // 픽셀아트엔 15fps 로 충분
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

        // 레이어 위치·내용만 바꾼다 — 화면 폭 전체를 다시 그리지 않으므로 CPU 가 거의 들지 않는다
        view.update(sprite: sprite, x: x.rounded(), speech: duty.currentSpeech, pixel: CGFloat(scale))
        fadeForMouse(panel)
    }

    private func fadeForMouse(_ panel: NSPanel) {
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

/// 순찰 오버레이 뷰. 이등병·말풍선을 미리 렌더링한 이미지 레이어로 두고 위치만 옮긴다.
/// (프로파일링 결과: 매 프레임 draw(_:) 방식은 화면 폭 전체 backing store 합성 비용이 CPU 7~9% 를 차지했다)
final class PatrolView: NSView {
    private let spriteLayer = CALayer()
    private let bubbleLayer = CALayer()
    private var spriteCache: [String: CGImage] = [:]
    private var currentSprite: PixelSprite?
    private var currentSpeech: String?
    private var currentPixel: CGFloat = 0
    private var currentX: CGFloat = -1

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer = CALayer()
        spriteLayer.magnificationFilter = .nearest // 픽셀아트는 보간 없이
        spriteLayer.anchorPoint = .zero
        bubbleLayer.anchorPoint = .zero
        layer?.addSublayer(spriteLayer)
        layer?.addSublayer(bubbleLayer)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func update(sprite: PixelSprite, x: CGFloat, speech: String?, pixel: CGFloat) {
        guard sprite != currentSprite || x != currentX || speech != currentSpeech || pixel != currentPixel else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true) // 암묵적 애니메이션 끄기

        let size = CGFloat(sprite.width) * pixel
        if sprite != currentSprite || pixel != currentPixel {
            spriteLayer.contents = image(for: sprite)
            spriteLayer.bounds = CGRect(x: 0, y: 0, width: size, height: size)
        }
        spriteLayer.position = CGPoint(x: x, y: 0)

        if let speech {
            // 오른쪽 공간이 모자라면 왼쪽에 띄우고, 꼬리는 항상 이등병 쪽을 향한다
            let fontSize = max(11, pixel * 5.5), scale = window?.backingScaleFactor ?? 2
            if let probe = Self.renderBubble(speech, fontSize: fontSize, maxHeight: bounds.height - 2, scale: scale) {
                let onRight = x + size + 2 + probe.size.width < bounds.width
                let bubble = onRight ? probe
                    : Self.renderBubble(speech, fontSize: fontSize, maxHeight: bounds.height - 2, scale: scale, tailOnRight: true) ?? probe
                bubbleLayer.contents = bubble.image
                bubbleLayer.bounds = CGRect(origin: .zero, size: bubble.size)
                bubbleLayer.position = CGPoint(x: onRight ? x + size + 2 : x - 2 - bubble.size.width,
                                               y: (bounds.height - bubble.size.height) / 2 + 2)
                bubbleLayer.isHidden = false
            }
        } else {
            bubbleLayer.isHidden = true
        }

        CATransaction.commit()
        currentSprite = sprite
        currentX = x
        currentSpeech = speech
        currentPixel = pixel
    }

    private func image(for sprite: PixelSprite) -> CGImage? {
        let key = sprite.rows.joined()
        if let cached = spriteCache[key] { return cached }
        // 픽셀 1개 = 1px 로 렌더링하고, 확대는 레이어(nearest)가 맡는다
        guard let ctx = CGContext(data: nil, width: sprite.width, height: sprite.height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.setShouldAntialias(false)
        sprite.draw(in: ctx, pixel: 1)
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
