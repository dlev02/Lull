import AppKit
import QuartzCore

/// The window-server blur that NSVisualEffectView is built on, reached through
/// private Core Animation classes so the radius is adjustable. Everything here is
/// looked up at run time: if a macOS update removes a piece, `makeBackdrop` returns
/// nil and the overlay falls back to the public blur.
enum SystemBlur {
  static var isAvailable: Bool {
    NSClassFromString("CABackdropLayer") is CALayer.Type && filterClass != nil
  }

  private static var filterClass: AnyObject? {
    guard let filterClass = NSClassFromString("CAFilter") as AnyObject?,
          filterClass.responds(to: NSSelectorFromString("filterWithType:")) else { return nil }
    return filterClass
  }

  private static func makeFilter(_ type: String) -> NSObject? {
    guard let filterClass else { return nil }
    let filter = filterClass.perform(NSSelectorFromString("filterWithType:"), with: type)?
      .takeUnretainedValue() as? NSObject
    let setDefaults = NSSelectorFromString("setDefaults")
    if let filter, filter.responds(to: setDefaults) {
      filter.perform(setDefaults)
    }
    return filter
  }

  /// A layer that samples what is behind its window and blurs it.
  static func makeBackdrop() -> CALayer? {
    guard let backdropClass = NSClassFromString("CABackdropLayer") as? CALayer.Type,
          let blur = makeFilter("gaussianBlur"),
          let saturate = makeFilter("colorSaturate") else { return nil }
    let layer = backdropClass.init()
    layer.setValue(true, forKey: "allowsGroupBlending")
    layer.setValue(true, forKey: "allowsGroupOpacity")
    layer.setValue(false, forKey: "allowsEdgeAntialiasing")
    layer.setValue(true, forKey: "disablesOccludedBackdropBlurs")
    layer.setValue(true, forKey: "ignoresOffscreenGroups")
    layer.setValue(false, forKey: "allowsInPlaceFiltering")
    layer.setValue(true, forKey: "windowServerAware")
    layer.setValue(true, forKey: "allowsSubstituteColor")
    layer.setValue(UUID().uuidString, forKey: "groupName")
    blur.setValue(true, forKey: "inputNormalizeEdges")
    layer.setValue([saturate, blur], forKey: "filters")
    return layer
  }

  static func setRadius(_ radius: Double, on layer: CALayer) {
    layer.setValue(radius, forKeyPath: "filters.gaussianBlur.inputRadius")
  }

  static func setSaturation(_ amount: Double, on layer: CALayer) {
    layer.setValue(amount, forKeyPath: "filters.colorSaturate.inputAmount")
  }

  /// Sampling resolution: 1 is full, 0.25 a quarter. Lower is cheaper and softer.
  static func setScale(_ scale: Double, on layer: CALayer) {
    layer.setValue(scale, forKey: "scale")
  }

  /// Lets the window server keep the window's layer tree live, which a
  /// behind-window backdrop needs. Returns false if this macOS no longer allows it.
  @discardableResult
  static func prepare(_ window: NSWindow) -> Bool {
    // Key-value coding finds either spelling of the setter; macOS 27 underscores one.
    func hasSetter(_ key: String) -> Bool {
      window.responds(to: NSSelectorFromString("set\(key):")) || window.responds(to: NSSelectorFromString("_set\(key):"))
    }
    guard hasSetter("ShouldAutoFlattenLayerTree"), hasSetter("CanHostLayersInWindowServer") else { return false }
    window.setValue(false, forKey: "shouldAutoFlattenLayerTree")
    window.setValue(false, forKey: "canHostLayersInWindowServer")
    window.setValue(true, forKey: "canHostLayersInWindowServer")
    keepLiveDuringSwipes(window)
    return true
  }

  private typealias ConnectionFunction = @convention(c) () -> Int32
  private typealias SetTagsFunction = @convention(c) (Int32, Int32, UnsafePointer<Int32>, Int32) -> Int32

  /// Stops the window server flattening the blur during Space and Mission Control swipes.
  static func keepLiveDuringSwipes(_ window: NSWindow) {
    let handle = UnsafeMutableRawPointer(bitPattern: -2) // RTLD_DEFAULT
    guard let connectionSymbol = dlsym(handle, "CGSMainConnectionID"),
          let tagsSymbol = dlsym(handle, "CGSSetWindowTags") else { return }
    let connection = unsafeBitCast(connectionSymbol, to: ConnectionFunction.self)
    let setTags = unsafeBitCast(tagsSymbol, to: SetTagsFunction.self)
    var tags: [Int32] = [0, 1 << 23]
    _ = setTags(connection(), Int32(window.windowNumber), &tags, 0x40)
  }
}
