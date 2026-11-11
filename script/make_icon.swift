// Draws the Lull app icon: one crisp window in front of two out-of-focus ones on a
// dusk gradient. Usage: makeicon <out.png> <topHex> <bottomHex> <glowHex>
import AppKit
import CoreImage

func color(_ hex: String) -> CGColor {
  let v = UInt32(hex, radix: 16)!
  return CGColor(srgbRed: CGFloat((v >> 16) & 255) / 255, green: CGFloat((v >> 8) & 255) / 255, blue: CGFloat(v & 255) / 255, alpha: 1)
}
let args = CommandLine.arguments
let size = 1024
let space = CGColorSpace(name: CGColorSpace.sRGB)!
func context() -> CGContext {
  CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
}
func window(_ ctx: CGContext, _ rect: CGRect, radius: CGFloat, fill: CGColor) {
  ctx.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
  ctx.setFillColor(fill)
  ctx.fillPath()
}
// Background.
let bg = context()
let gradient = CGGradient(colorsSpace: space, colors: [color(args[2]), color(args[3])] as CFArray, locations: [0, 1])!
bg.drawLinearGradient(gradient, start: CGPoint(x: 0, y: size), end: CGPoint(x: 0, y: 0), options: [])
let glow = CGGradient(colorsSpace: space, colors: [color(args[4]).copy(alpha: 0.55)!, color(args[4]).copy(alpha: 0)!] as CFArray, locations: [0, 1])!
bg.drawRadialGradient(glow, startCenter: CGPoint(x: 512, y: 250), startRadius: 0, endCenter: CGPoint(x: 512, y: 250), endRadius: 620, options: [])
// Two windows further back, drawn sharp and then blurred.
let back = context()
window(back, CGRect(x: 150, y: 470, width: 480, height: 360), radius: 56, fill: CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.42))
window(back, CGRect(x: 470, y: 330, width: 430, height: 330), radius: 56, fill: CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.30))
let ci = CIContext(options: [.workingColorSpace: space])
let blurred = CIImage(cgImage: back.makeImage()!).clampedToExtent().applyingGaussianBlur(sigma: 34).cropped(to: CGRect(x: 0, y: 0, width: size, height: size))
bg.draw(ci.createCGImage(blurred, from: blurred.extent)!, in: CGRect(x: 0, y: 0, width: size, height: size))
// The window in focus.
let front = CGRect(x: 262, y: 216, width: 500, height: 390)
bg.saveGState()
bg.setShadow(offset: CGSize(width: 0, height: -18), blur: 60, color: CGColor(srgbRed: 0, green: 0, blue: 0.1, alpha: 0.35))
window(bg, front, radius: 64, fill: CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.97))
bg.restoreGState()
// A hint of a title bar.
for (i, a) in [0.30, 0.22, 0.16].enumerated() {
  bg.setFillColor(color(args[3]).copy(alpha: a)!)
  bg.fillEllipse(in: CGRect(x: 312 + CGFloat(i) * 56, y: 528, width: 34, height: 34))
}
let rep = NSBitmapImageRep(cgImage: bg.makeImage()!)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: args[1]))
