// 앱 아이콘(assets/AppIcon.icns)과 README 로고(docs/images/logo.png)를 다시 만든다.
// 사용법: swift scripts/make-icon.swift
// 링은 사용량 게이지, 안쪽 물결은 차오른 사용량, 물결 위 점선은 최고 수위선(tidemark)이다.
import AppKit

func rgb(_ hex: Int, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(
        srgbRed: CGFloat((hex >> 16) & 0xff) / 255,
        green: CGFloat((hex >> 8) & 0xff) / 255,
        blue: CGFloat(hex & 0xff) / 255,
        alpha: alpha
    )
}

let ringStart = rgb(0x3dd6d0)
let ringEnd = rgb(0x6e6af0)
let waterTop = rgb(0x3dd6d0)
let waterBottom = rgb(0x2a7fd4)

func mix(_ a: CGColor, _ b: CGColor, _ t: CGFloat) -> CGColor {
    let x = a.components!, y = b.components!
    return CGColor(
        srgbRed: x[0] + (y[0] - x[0]) * t,
        green: x[1] + (y[1] - x[1]) * t,
        blue: x[2] + (y[2] - x[2]) * t,
        alpha: 1
    )
}

func wavePath(level: CGFloat, amplitude: CGFloat, phase: CGFloat, left: CGFloat, right: CGFloat, bottom: CGFloat) -> CGPath {
    let path = CGMutablePath()
    path.move(to: CGPoint(x: left, y: bottom))
    let width = right - left
    var x = left
    while x <= right {
        let t = (x - left) / width
        path.addLine(to: CGPoint(x: x, y: level + amplitude * sin(t * 2 * .pi * 1.5 + phase)))
        x += 2
    }
    path.addLine(to: CGPoint(x: right, y: bottom))
    path.closeSubpath()
    return path
}

func render(pixels: Int) -> Data {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let context = CGContext(
        data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
        space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    let scale = CGFloat(pixels) / 1024
    context.scaleBy(x: scale, y: scale)

    // 바탕 타일
    let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
    let tilePath = CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil)
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -10), blur: 28, color: CGColor(gray: 0, alpha: 0.35))
    context.addPath(tilePath)
    context.setFillColor(rgb(0x121a33))
    context.fillPath()
    context.restoreGState()

    context.saveGState()
    context.addPath(tilePath)
    context.clip()
    let background = CGGradient(
        colorsSpace: space, colors: [rgb(0x23305a), rgb(0x0c1226)] as CFArray, locations: [0, 1]
    )!
    context.drawLinearGradient(background, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])
    context.restoreGState()

    let center = CGPoint(x: 512, y: 512)
    let line: CGFloat = 66
    let radius: CGFloat = 268
    let fraction: CGFloat = 0.72

    // 링 트랙
    context.saveGState()
    context.setLineWidth(line)
    context.setStrokeColor(rgb(0xffffff, 0.12))
    context.addEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
    context.strokePath()
    context.restoreGState()

    // 링 채움: 12시에서 시계 방향, 청록에서 남색으로
    let startAngle = CGFloat.pi / 2
    let sweep = 2 * CGFloat.pi * fraction
    let arc = CGMutablePath()
    arc.addArc(center: center, radius: radius, startAngle: startAngle, endAngle: startAngle - sweep, clockwise: true)
    context.saveGState()
    context.addPath(arc.copy(strokingWithWidth: line, lineCap: .round, lineJoin: .round, miterLimit: 10))
    context.clip()
    let steps = 360
    for step in 0..<steps {
        let t = CGFloat(step) / CGFloat(steps)
        let a = startAngle - t * sweep - 0.4
        let b = a - sweep / CGFloat(steps) * 1.6 - 0.02
        let wedge = CGMutablePath()
        wedge.move(to: center)
        wedge.addArc(center: center, radius: radius + line, startAngle: a + 0.4, endAngle: b + 0.4, clockwise: true)
        wedge.closeSubpath()
        context.addPath(wedge)
        context.setFillColor(mix(ringStart, ringEnd, t))
        context.fillPath()
    }
    // 시작 둥근 끝은 첫 색으로 다시 칠한다
    context.setFillColor(ringStart)
    context.fillEllipse(in: CGRect(x: center.x - line / 2, y: center.y + radius - line / 2, width: line, height: line))
    context.restoreGState()

    // 안쪽 물결
    let inner = radius - line / 2 - 30
    let innerRect = CGRect(x: center.x - inner, y: center.y - inner, width: inner * 2, height: inner * 2)
    context.saveGState()
    context.addEllipse(in: innerRect)
    context.clip()
    context.setFillColor(rgb(0xffffff, 0.04))
    context.fill(innerRect)

    let level = center.y - 30
    context.addPath(wavePath(level: level + 10, amplitude: 20, phase: 2.2, left: innerRect.minX, right: innerRect.maxX, bottom: innerRect.minY))
    context.setFillColor(mix(waterBottom, ringEnd, 0.4).copy(alpha: 0.55)!)
    context.fillPath()

    context.saveGState()
    context.addPath(wavePath(level: level, amplitude: 22, phase: 0, left: innerRect.minX, right: innerRect.maxX, bottom: innerRect.minY))
    context.clip()
    let water = CGGradient(colorsSpace: space, colors: [waterTop, waterBottom] as CFArray, locations: [0, 1])!
    context.drawLinearGradient(water, start: CGPoint(x: 512, y: level + 22), end: CGPoint(x: 512, y: innerRect.minY), options: [])
    context.restoreGState()

    // 최고 수위선
    let markY = level + 92
    let half = sqrt(inner * inner - pow(markY - center.y, 2)) - 34
    context.setLineCap(.round)
    context.setLineWidth(14)
    context.setStrokeColor(rgb(0xffffff, 0.75))
    context.setLineDash(phase: 0, lengths: [34, 26])
    context.move(to: CGPoint(x: center.x - half, y: markY))
    context.addLine(to: CGPoint(x: center.x + half, y: markY))
    context.strokePath()
    context.restoreGState()

    let image = context.makeImage()!
    let rep = NSBitmapImageRep(cgImage: image)
    return rep.representation(using: .png, properties: [:])!
}

let root = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : FileManager.default.currentDirectoryPath)
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("tidemark-\(UUID().uuidString).iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    try render(pixels: size).write(to: iconset.appendingPathComponent("icon_\(size)x\(size).png"))
    try render(pixels: size * 2).write(to: iconset.appendingPathComponent("icon_\(size)x\(size)@2x.png"))
}
try FileManager.default.createDirectory(at: root.appendingPathComponent("assets"), withIntermediateDirectories: true)
try FileManager.default.createDirectory(at: root.appendingPathComponent("docs/images"), withIntermediateDirectories: true)
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", root.appendingPathComponent("assets/AppIcon.icns").path]
try iconutil.run()
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else { fatalError("iconutil 이 실패했습니다") }
try render(pixels: 512).write(to: root.appendingPathComponent("docs/images/logo.png"))
try? FileManager.default.removeItem(at: iconset)
print("assets/AppIcon.icns, docs/images/logo.png")
