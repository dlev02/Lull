import AppKit
import QuartzCore

/// How one overlay should look right now.
struct OverlayLook: Equatable {
  var blurRadius: Double = 0
  var scale: Double = 0.25
  var saturation: Double = 1
  var tintColor: CGColor = .black
  var tintOpacity: Double = 0
  var grainOpacity: Double = 0
  /// How far down the display the effect takes to reach full strength, as a fraction
  /// of its height. Zero is full strength everywhere (Deep); Ambient leaves the top
  /// of the screen clear and fades in below it.
  var fadeDepth: Double = 0
}

/// A click-through window covering one display. The engine slots it directly beneath
/// the focused window, so the window server blurs everything behind it and Lull does
/// no per-frame work.
final class OverlayPanel: NSPanel {
  enum Backend: String {
    case backdrop, material
  }

  enum Placement {
    /// A normal-level window the engine slots beneath the focused window. It shows
    /// everywhere except over Stage Manager's thumbnails.
    case beneathFocus
    /// Behind every app window but above the desktop. It shows only around Stage
    /// Manager's thumbnails, where the other overlay leaves a hole.
    case behindWindows
  }

  let displayID: CGDirectDisplayID
  private(set) var backend: Backend = .material
  private let placement: Placement
  private let root = CALayer()
  /// Masked by the thumbnail holes.
  private let content = CALayer()
  /// Masked by the top-to-bottom fade.
  private let fadeHost = CALayer()
  private let fadeMask = CAGradientLayer()
  private var backdrop: CALayer?
  private var material: NSVisualEffectView?
  private let tint = CALayer()
  private let grain = CALayer()
  private var look = OverlayLook()
  private var holes: [CGRect] = []
  private var isShown = false

  init(screen: NSScreen, displayID: CGDirectDisplayID, placement: Placement) {
    self.displayID = displayID
    self.placement = placement
    super.init(
      contentRect: screen.frame,
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered,
      defer: false
    )
    level = placement == .beneathFocus ? .normal : NSWindow.Level(rawValue: NSWindow.Level.normal.rawValue - 1)
    isOpaque = false
    // Not fully clear: the backdrop only samples behind a window that draws something.
    backgroundColor = NSColor.white.withAlphaComponent(0.001)
    hasShadow = false
    ignoresMouseEvents = true
    isReleasedWhenClosed = false
    hidesOnDeactivate = false
    isMovable = false
    isExcludedFromWindowsMenu = true
    animationBehavior = .none
    collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle]
    alphaValue = 0
    setAccessibilityElement(false)

    let view = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))
    view.wantsLayer = true
    view.layer = root
    view.layerContentsRedrawPolicy = .never
    contentView = view
    buildLayers(in: view)
    setFrame(screen.frame, display: false)
  }

  override var canBecomeKey: Bool { false }
  override var canBecomeMain: Bool { false }

  private func buildLayers(in view: NSView) {
    root.masksToBounds = true
    root.addSublayer(content)
    content.addSublayer(fadeHost)
    if SystemBlur.isAvailable, let layer = SystemBlur.makeBackdrop() {
      // The window is prepared after the backdrop joins its layer tree.
      fadeHost.addSublayer(layer)
      if SystemBlur.prepare(self) {
        backdrop = layer
        backend = .backdrop
      } else {
        layer.removeFromSuperlayer()
      }
    }
    if backdrop == nil {
      // Public fallback: fixed-strength system blur, with no soft fade.
      let effect = NSVisualEffectView(frame: view.bounds)
      effect.material = .fullScreenUI
      effect.blendingMode = .behindWindow
      effect.state = .active
      effect.autoresizingMask = [.width, .height]
      view.addSubview(effect, positioned: .below, relativeTo: nil)
      material = effect
    }
    grain.backgroundColor = NSColor(patternImage: OverlayPanel.grainImage).cgColor
    grain.opacity = 0
    tint.opacity = 0
    fadeHost.addSublayer(tint)
    fadeHost.addSublayer(grain)

    // Layer geometry is bottom-up, so the fade starts at y = 1, the top of the display.
    fadeMask.startPoint = CGPoint(x: 0.5, y: 1)
    fadeMask.endPoint = CGPoint(x: 0.5, y: 0)
    fadeMask.colors = [CGColor(gray: 0, alpha: 1), CGColor(gray: 0, alpha: 1)]
    fadeMask.locations = [0, 1]
    fadeHost.mask = fadeMask
    Log.info(.overlay, "overlay for display \(displayID) uses \(backend.rawValue) blur")
  }

  /// Applies a look. `holes` are rectangles, in the panel's own coordinates, where
  /// Stage Manager's thumbnails sit. Each blur samples its whole area and is only
  /// masked afterwards, which is why no seam shows where the two overlays meet.
  func apply(_ newLook: OverlayLook, holes newHoles: [CGRect], animated: Bool, duration: TimeInterval) {
    let bounds = CGRect(origin: .zero, size: frame.size)
    guard newLook != look || newHoles != holes || content.frame != bounds else { return }
    CATransaction.begin()
    CATransaction.setDisableActions(!animated)
    CATransaction.setAnimationDuration(duration)

    if newHoles != holes || content.frame != bounds {
      for layer in [content, fadeHost, fadeMask] {
        layer.frame = bounds
      }
      // The behind-windows panel only needs to blur around the holes it shows through.
      var area = bounds
      if placement == .behindWindows, let first = newHoles.first {
        area = newHoles.dropFirst().reduce(first) { $0.union($1) }.insetBy(dx: -140, dy: -140).intersection(bounds)
      }
      for layer in [backdrop, tint, grain].compactMap({ $0 }) {
        layer.frame = area
      }
      material?.frame = area
      content.mask = makeHoleMask(newHoles, in: bounds)
    }

    // Clear at the top of the display, full strength from `fadeDepth` down.
    let clear = CGColor(gray: 0, alpha: 0)
    let solid = CGColor(gray: 0, alpha: 1)
    fadeMask.colors = newLook.fadeDepth > 0 ? [clear, solid] : [solid, solid]
    fadeMask.locations = [0, NSNumber(value: max(newLook.fadeDepth, 0.001))]

    if let backdrop {
      if animated, look.blurRadius != newLook.blurRadius {
        let animation = CABasicAnimation(keyPath: "filters.gaussianBlur.inputRadius")
        animation.fromValue = look.blurRadius
        animation.toValue = newLook.blurRadius
        animation.duration = duration
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        backdrop.add(animation, forKey: "blurRadius")
      }
      SystemBlur.setScale(newLook.scale, on: backdrop)
      SystemBlur.setRadius(newLook.blurRadius, on: backdrop)
      SystemBlur.setSaturation(newLook.saturation, on: backdrop)
    }
    tint.backgroundColor = newLook.tintColor
    tint.opacity = Float(newLook.tintOpacity)
    grain.opacity = Float(newLook.grainOpacity)
    CATransaction.commit()
    look = newLook
    holes = newHoles
  }

  /// How far the clear area reaches past a thumbnail, and how soft its edge is. A hard
  /// edge reads as a box, because the blur outside it carries the thumbnail's own
  /// smudge while the wallpaper inside does not.
  private static let holeMargin: CGFloat = 6
  private static let holeSoftness: CGFloat = 8

  private func makeHoleMask(_ holes: [CGRect], in bounds: CGRect) -> CALayer? {
    guard !holes.isEmpty else { return nil }
    // Holes overlap (a thumbnail and its app icon), so merge them into one outline.
    func outline(grownBy margin: CGFloat) -> CGPath {
      holes.reduce(CGPath(rect: .zero, transform: nil)) { outline, hole in
        let rect = hole.insetBy(dx: -margin, dy: -margin)
        let corner = min(10, hole.width / 2, hole.height / 2) + margin
        return outline.union(CGPath(roundedRect: rect, cornerWidth: corner, cornerHeight: corner, transform: nil))
      }
    }
    let mask = CAShapeLayer()
    mask.frame = bounds
    if placement == .beneathFocus {
      // The overlay itself, with its shadow spilling softly into each hole.
      let margin = OverlayPanel.holeMargin
      let path = CGPath(rect: bounds.insetBy(dx: -4 * margin, dy: -4 * margin), transform: nil)
        .subtracting(outline(grownBy: margin))
      mask.path = path
      mask.shadowPath = path
      mask.shadowColor = .black
      mask.shadowOpacity = 1
      mask.shadowOffset = .zero
      mask.shadowRadius = OverlayPanel.holeSoftness
    } else {
      // Solid wherever the other overlay thins, then fading out beneath it, so the
      // other overlay's blur never meets an edge in what it samples.
      let path = outline(grownBy: OverlayPanel.holeMargin)
      mask.path = path
      mask.shadowPath = path
      mask.shadowColor = .black
      mask.shadowOpacity = 1
      mask.shadowOffset = .zero
      mask.shadowRadius = 4 * OverlayPanel.holeSoftness
    }
    return mask
  }

  /// Puts the panel directly beneath another window in the global window order.
  /// Passing nil sends it behind every normal window, so only the desktop blurs.
  func slot(beneath windowID: CGWindowID?) {
    if let windowID {
      order(.below, relativeTo: Int(windowID))
    } else {
      order(.below, relativeTo: 0)
    }
  }

  /// Brings the overlay in. Fade raises its opacity; Focus also pulls the blur up
  /// from nothing, like a lens; Pointer spreads it outward from the pointer.
  func reveal(_ effect: RevealEffect, duration: TimeInterval) {
    guard !isShown else { return }
    isShown = true
    switch effect {
    case .fade:
      animateAlpha(to: 1, duration: duration)
    case .focus:
      animateAlpha(to: 1, duration: min(duration, 0.15))
      animateRadius(from: 0, to: look.blurRadius, duration: duration)
    case .pointer:
      alphaValue = 1
      animateCircle(opening: true, duration: max(duration, 0.2))
    }
  }

  func conceal(_ effect: RevealEffect, duration: TimeInterval) {
    guard isShown else { return }
    isShown = false
    switch effect {
    case .fade:
      animateAlpha(to: 0, duration: duration, thenOrderOut: true)
    case .focus:
      animateRadius(from: look.blurRadius, to: 0, duration: duration)
      animateAlpha(to: 0, duration: duration, thenOrderOut: true)
    case .pointer:
      animateCircle(opening: false, duration: max(duration, 0.2))
      DispatchQueue.main.asyncAfter(deadline: .now() + max(duration, 0.2)) { [weak self] in
        guard let self, !self.isShown else { return }
        self.alphaValue = 0
        self.root.mask = nil
        self.orderOut(nil)
      }
    }
  }

  private func animateAlpha(to value: CGFloat, duration: TimeInterval, thenOrderOut: Bool = false) {
    NSAnimationContext.runAnimationGroup { context in
      context.duration = duration
      context.timingFunction = CAMediaTimingFunction(name: value > 0 ? .easeOut : .easeIn)
      animator().alphaValue = value
    } completionHandler: { [weak self] in
      MainActor.assumeIsolated {
        guard thenOrderOut, let self, !self.isShown else { return }
        self.orderOut(nil)
      }
    }
  }

  private func animateRadius(from start: Double, to end: Double, duration: TimeInterval) {
    guard let backdrop else { return }
    let animation = CABasicAnimation(keyPath: "filters.gaussianBlur.inputRadius")
    animation.fromValue = start
    animation.toValue = end
    animation.duration = duration
    animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
    backdrop.add(animation, forKey: "revealRadius")
  }

  /// A circle centred on the pointer that grows to cover the display, or shrinks back.
  private func animateCircle(opening: Bool, duration: TimeInterval) {
    let bounds = CGRect(origin: .zero, size: frame.size)
    let pointer = NSEvent.mouseLocation
    var centre = CGPoint(x: pointer.x - frame.minX, y: pointer.y - frame.minY)
    if !bounds.contains(centre) {
      centre = CGPoint(x: bounds.midX, y: bounds.midY)
    }
    let reach = hypot(max(centre.x, bounds.width - centre.x), max(centre.y, bounds.height - centre.y)) + 40
    func circle(_ radius: CGFloat) -> CGPath {
      CGPath(ellipseIn: CGRect(x: centre.x - radius, y: centre.y - radius, width: radius * 2, height: radius * 2), transform: nil)
    }
    let mask = CAShapeLayer()
    mask.frame = bounds
    mask.path = circle(opening ? reach : 1)
    root.mask = mask
    let animation = CABasicAnimation(keyPath: "path")
    animation.fromValue = circle(opening ? 1 : reach)
    animation.toValue = circle(opening ? reach : 1)
    animation.duration = duration
    animation.timingFunction = CAMediaTimingFunction(name: opening ? .easeOut : .easeIn)
    mask.add(animation, forKey: "reveal")
    if opening {
      DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
        guard let self, self.isShown else { return }
        self.root.mask = nil
      }
    }
  }

  /// One small noise tile, generated once and repeated by the window server.
  private static let grainImage: NSImage = {
    let side = 128
    var generator = SystemRandomNumberGenerator()
    var pixels = [UInt8](repeating: 0, count: side * side * 4)
    for index in stride(from: 0, to: pixels.count, by: 4) {
      let value = UInt8.random(in: 0...255, using: &generator)
      let alpha = UInt8.random(in: 40...255, using: &generator)
      // Premultiplied grey.
      let premultiplied = UInt8(UInt16(value) * UInt16(alpha) / 255)
      pixels[index] = premultiplied
      pixels[index + 1] = premultiplied
      pixels[index + 2] = premultiplied
      pixels[index + 3] = alpha
    }
    let image = NSImage(size: NSSize(width: side / 2, height: side / 2))
    let provider = CGDataProvider(data: Data(pixels) as CFData)
    if let provider, let cgImage = CGImage(
      width: side, height: side, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: side * 4,
      space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
      provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
    ) {
      image.addRepresentation(NSBitmapImageRep(cgImage: cgImage))
    }
    return image
  }()
}
