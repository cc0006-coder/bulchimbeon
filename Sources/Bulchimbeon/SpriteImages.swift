import AppKit
import BulchimbeonCore

/// 스프라이트 → 메뉴바용 NSImage (1pt = 1픽셀, 컬러 유지)
@MainActor
enum SpriteImages {
    private static var cache: [Sprites.Pose: [NSImage]] = [:]

    static func frames(_ pose: Sprites.Pose) -> [NSImage] {
        if let cached = cache[pose] { return cached }
        let images = Sprites.frames(pose).map(image)
        cache[pose] = images
        return images
    }

    private static func image(_ sprite: PixelSprite) -> NSImage {
        let image = NSImage(size: NSSize(width: sprite.width, height: sprite.height), flipped: false) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            ctx.setShouldAntialias(false)
            sprite.draw(in: ctx, pixel: 1)
            return true
        }
        image.isTemplate = false // 템플릿이면 단색 실루엣이 된다
        return image
    }
}

/// 0.5초 간격 프레임 카운터
@MainActor
final class SpriteAnimator: ObservableObject {
    @Published private(set) var tick = 0
    private var timer: Timer?

    init() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick &+= 1 }
        }
    }
}
