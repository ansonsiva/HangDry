import AppKit

let size: CGFloat = 1024
let out = CommandLine.arguments[1]
let space = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
// 翻转成左上角为原点
ctx.translateBy(x: 0, y: size)
ctx.scaleBy(x: 1, y: -1)

func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor { CGColor(srgbRed: r, green: g, blue: b, alpha: a) }

// 背景：macOS 图标网格 824pt 圆角方块
let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
let tilePath = CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: 12), blur: 28, color: color(0, 0, 0, 0.28))
ctx.addPath(tilePath); ctx.setFillColor(color(1, 1, 1)); ctx.fillPath()
ctx.restoreGState()
ctx.saveGState()
ctx.addPath(tilePath); ctx.clip()
let sky = CGGradient(colorsSpace: space, colors: [color(0.53, 0.78, 0.98), color(0.98, 0.93, 0.82)] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(sky, start: CGPoint(x: 0, y: 100), end: CGPoint(x: 0, y: 924), options: [])

// 绳子
let left = CGPoint(x: 80, y: 330), right = CGPoint(x: 944, y: 330), control = CGPoint(x: 512, y: 470)
func ropeY(_ x: CGFloat) -> CGFloat {
    let t = (x - left.x) / (right.x - left.x)
    return (1 - t) * (1 - t) * left.y + 2 * (1 - t) * t * control.y + t * t * right.y
}
let rope = CGMutablePath(); rope.move(to: left); rope.addQuadCurve(to: right, control: control)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: 6), blur: 8, color: color(0, 0, 0, 0.25))
ctx.addPath(rope); ctx.setStrokeColor(color(0.55, 0.42, 0.28)); ctx.setLineWidth(20); ctx.setLineCap(.round); ctx.strokePath()
ctx.restoreGState()
ctx.addPath(rope); ctx.setStrokeColor(color(0.88, 0.78, 0.62)); ctx.setLineWidth(8); ctx.setLineDash(phase: 0, lengths: [22, 16]); ctx.strokePath()
ctx.setLineDash(phase: 0, lengths: [])

// 三件衣服：视频、音频、图片
let clothes: [(x: CGFloat, angle: CGFloat, tint: CGColor, photo: [CGColor])] = [
    (300, -6, color(0.56, 0.35, 0.86), [color(0.40, 0.30, 0.75), color(0.95, 0.55, 0.70)]),
    (512, 3, color(0.98, 0.58, 0.20), [color(0.99, 0.75, 0.35), color(0.96, 0.45, 0.30)]),
    (724, -3, color(0.28, 0.74, 0.42), [color(0.45, 0.80, 0.55), color(0.25, 0.55, 0.70)]),
]
for item in clothes {
    let top = ropeY(item.x)
    ctx.saveGState()
    ctx.translateBy(x: item.x, y: top)
    ctx.rotate(by: item.angle * .pi / 180)
    // 卡片
    let card = CGRect(x: -95, y: 18, width: 190, height: 236)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: 10), blur: 18, color: color(0, 0, 0, 0.3))
    ctx.addPath(CGPath(roundedRect: card, cornerWidth: 14, cornerHeight: 14, transform: nil))
    ctx.setFillColor(color(0.99, 0.98, 0.96)); ctx.fillPath()
    ctx.restoreGState()
    // 照片区域
    let photo = CGRect(x: -78, y: 42, width: 156, height: 150)
    ctx.saveGState()
    ctx.addPath(CGPath(roundedRect: photo, cornerWidth: 8, cornerHeight: 8, transform: nil)); ctx.clip()
    let g = CGGradient(colorsSpace: space, colors: item.photo as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(g, start: CGPoint(x: photo.minX, y: photo.minY), end: CGPoint(x: photo.maxX, y: photo.maxY), options: [])
    ctx.restoreGState()
    // 文件名横条
    ctx.addPath(CGPath(roundedRect: CGRect(x: -60, y: 208, width: 120, height: 12), cornerWidth: 6, cornerHeight: 6, transform: nil))
    ctx.setFillColor(color(0, 0, 0, 0.18)); ctx.fillPath()
    // 下摆颜色
    let hem = CGMutablePath()
    hem.addRoundedRect(in: CGRect(x: -95, y: 238, width: 190, height: 16), cornerWidth: 8, cornerHeight: 8)
    ctx.addPath(hem); ctx.setFillColor(item.tint); ctx.fillPath()
    // 衣夹
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: 4), blur: 6, color: color(0, 0, 0, 0.3))
    let pin = CGRect(x: -16, y: -24, width: 32, height: 70)
    ctx.addPath(CGPath(roundedRect: pin, cornerWidth: 7, cornerHeight: 7, transform: nil))
    ctx.setFillColor(color(0.90, 0.72, 0.48)); ctx.fillPath()
    ctx.restoreGState()
    ctx.setFillColor(color(0.62, 0.45, 0.28)); ctx.fill(CGRect(x: -16, y: 0, width: 32, height: 5))
    ctx.restoreGState()
}
ctx.restoreGState()

let image = ctx.makeImage()!
let rep = NSBitmapImageRep(cgImage: image)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
