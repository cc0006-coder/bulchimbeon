// 스프라이트 → PNG 생성기. `make icons` 로 실행한다.
//   swift run IconGen <out-dir>
//   → <out-dir>/AppIcon.iconset/*.png, <out-dir>/sprites-preview.png
import BulchimbeonCore
import CoreGraphics
import Foundation
import ImageIO

let outDir = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "build-icons")
let iconset = outDir.appendingPathComponent("AppIcon.iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func writePNG(_ url: URL, width: Int, height: Int, draw: (CGContext) -> Void) {
    let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    draw(ctx)
    let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
    CGImageDestinationFinalize(dest)
}

/// macOS 앱 아이콘 규격: 1024 캔버스 안에 824 둥근 사각형 본체
func drawAppIcon(_ ctx: CGContext, size: CGFloat) {
    let inset = size * 100 / 1024
    let body = CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    let path = CGPath(roundedRect: body, cornerWidth: body.width * 0.225, cornerHeight: body.width * 0.225, transform: nil)

    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()
    // 밤하늘 그라데이션
    let colors = [CGColor(red: 0.07, green: 0.10, blue: 0.22, alpha: 1),
                  CGColor(red: 0.18, green: 0.22, blue: 0.42, alpha: 1)] as CFArray
    let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors, locations: [0, 1])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: body.maxY), end: CGPoint(x: 0, y: body.minY), options: [])

    ctx.setShouldAntialias(false)
    let scene = Sprites.appIconScene
    let pixel = body.width / CGFloat(scene.width)
    scene.draw(in: ctx, origin: body.origin, pixel: pixel)
    ctx.restoreGState()
}

let iconSizes: [(name: String, px: Int)] = [
    ("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64),
    ("128x128", 128), ("128x128@2x", 256), ("256x256", 256), ("256x256@2x", 512),
    ("512x512", 512), ("512x512@2x", 1024),
]
for (name, px) in iconSizes {
    writePNG(iconset.appendingPathComponent("icon_\(name).png"), width: px, height: px) {
        drawAppIcon($0, size: CGFloat(px))
    }
}

// 미리보기: 포즈별 한 줄, 프레임을 가로로. 흰 배경 + 메뉴바 실제 크기(1x) 도 함께.
// 그 아래 기본이 아닌 군복 테마마다 한 줄: 포즈별 첫 프레임.
let poses = Sprites.Pose.allCases
let themes = UniformTheme.all.filter { $0 != .default }
let scale: CGFloat = 12, cell = 16 * scale, gap: CGFloat = 16
let maxFrames = max(poses.map { Sprites.frames($0).count }.max()!, poses.count)
let previewW = Int(gap + CGFloat(maxFrames) * (cell + gap) + 40)
let previewH = Int(gap + CGFloat(poses.count + themes.count) * (cell + gap))
writePNG(outDir.appendingPathComponent("sprites-preview.png"), width: previewW, height: previewH) { ctx in
    ctx.setFillColor(CGColor(red: 0.93, green: 0.93, blue: 0.95, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: previewW, height: previewH))
    ctx.setShouldAntialias(false)
    for (row, pose) in poses.enumerated() {
        let y = CGFloat(previewH) - gap - CGFloat(row + 1) * (cell + gap) + gap
        for (col, frame) in Sprites.frames(pose).enumerated() {
            let x = gap + CGFloat(col) * (cell + gap)
            ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
            ctx.fill(CGRect(x: x, y: y, width: cell, height: cell))
            frame.draw(in: ctx, origin: CGPoint(x: x, y: y), pixel: scale)
        }
        // 실제 메뉴바 크기
        Sprites.frames(pose)[0].draw(in: ctx, origin: CGPoint(x: CGFloat(previewW) - 30, y: y), pixel: 1)
    }
    for (index, theme) in themes.enumerated() {
        let y = CGFloat(previewH) - gap - CGFloat(poses.count + index + 1) * (cell + gap) + gap
        for (col, pose) in poses.enumerated() {
            let x = gap + CGFloat(col) * (cell + gap)
            ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
            ctx.fill(CGRect(x: x, y: y, width: cell, height: cell))
            Sprites.frames(pose, theme: theme)[0].draw(in: ctx, origin: CGPoint(x: x, y: y), pixel: scale, theme: theme)
        }
        Sprites.frames(.standby, theme: theme)[0].draw(in: ctx, origin: CGPoint(x: CGFloat(previewW) - 30, y: y), pixel: 1, theme: theme)
    }
}

print("✅ \(iconset.path)")
print("✅ \(outDir.appendingPathComponent("sprites-preview.png").path)")
