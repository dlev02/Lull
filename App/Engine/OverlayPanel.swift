import AppKit
import QuartzCore

/// How one overlay should look right now.
struct OverlayLook: Equatable {
  var blurRadius: Double = 0
  var scale: Double = 0.25
  var saturation: Double = 1
  var tintColor: CGColor = .black
  var tintOpacity: Double = 0
  /// A faint wash over the blur: dark in Dark Mode, light in Light Mode.
  var veilColor: CGColor = .black
  var veilOpacity: Double = 0
  var grainOpacity: Double = 0
}

/// A click-through window covering one display. The engine slots it directly beneath
/// the focused window, so the window server blurs everything behind it and Lull does
/// no per-frame work.
final class OverlayPanel: NSPanel {
  enum Backend: String {
    case backdrop, material, dim
  }

  let displayID: CGDirectDisplayID
  private(set) var backend: Backend = .dim
  private let root = CALayer()
  private var backdrop: CALayer?
  private var material: NSVisualEffectView?
  private let veil = CALayer()
  private let tint = CALayer()
  private let grain = CALayer()
  private var look = OverlayLook()
  private var isShown = false

  init(screen: NSScreen, displayID: CGDirectDisplayID) {
    self.displayID = displayID
    super.init(
      contentRect: screen.frame,
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered,
      defer: false
    )
    level = .normal
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
    if SystemBlur.isAvailable, let layer = SystemBlur.makeBackdrop() {
      // The window is prepared after the backdrop joins its layer tree.
      root.addSublayer(layer)
      if SystemBlur.prepare(self) {
        backdrop = layer
        backend = .backdrop
      } else {
        layer.removeFromSuperlayer()
      }
    }
    if backdrop == nil {
      // Public fallback: fixed-strength system blur.
      let effect = NSVisualEffectView(frame: view.bounds)
      effect.material = .fullScreenUI
      effect.blendingMode = .behindWindow
      effect.state = .active
      effect.autoresizingMask = [.width, .height]
      view.addSubview(effect)
      material = effect
      backend = .material
    }
    grain.backgroundColor = NSColor(patternImage: OverlayPanel.grainImage).cgColor
    grain.opacity = 0
    for layer in [veil, tint, grain] {
      root.addSublayer(layer)
    }
    veil.opacity = 0
    tint.opacity = 0
    Log.info(.overlay, "overlay for display \(displayID) uses \(backend.rawValue) blur")
  }

  /// Applies a look. `coverage` is the part of the display to cover, in the panel's
  /// own coordinates; the Stage Manager strip is left out of it when it should stay sharp.
  func apply(_ newLook: OverlayLook, coverage: CGRect, animated: Bool, duration: TimeInterval) {
    CATransaction.begin()
    CATransaction.setDisableActions(!animated)
    CATransaction.setAnimationDuration(duration)
    for layer in [backdrop, veil, tint, grain].compactMap({ $0 }) where layer.frame != coverage {
      layer.frame = coverage
    }
    material?.frame = coverage
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
    veil.backgroundColor = newLook.veilColor
    veil.opacity = Float(newLook.veilOpacity)
    tint.backgroundColor = newLook.tintColor
    tint.opacity = Float(newLook.tintOpacity)
    grain.opacity = Float(newLook.grainOpacity)
    CATransaction.commit()
    look = newLook
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

  func fadeIn(duration: TimeInterval) {
    guard !isShown else { return }
    isShown = true
    NSAnimationContext.runAnimationGroup { context in
      context.duration = duration
      context.timingFunction = CAMediaTimingFunction(name: .easeOut)
      animator().alphaValue = 1
    }
  }

  func fadeOut(duration: TimeInterval) {
    guard isShown else { return }
    isShown = false
    NSAnimationContext.runAnimationGroup { context in
      context.duration = duration
      context.timingFunction = CAMediaTimingFunction(name: .easeIn)
      animator().alphaValue = 0
    } completionHandler: { [weak self] in
      MainActor.assumeIsolated {
        guard let self, !self.isShown else { return }
        self.orderOut(nil)
      }
    }
  }

  var isOverlayShown: Bool { isShown }

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
