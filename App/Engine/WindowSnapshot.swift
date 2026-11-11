import AppKit
import CoreGraphics

struct WindowInfo {
  var id: CGWindowID
  var pid: pid_t
  var owner: String
  /// Global coordinates with the origin at the top-left of the primary display.
  var bounds: CGRect
  var alpha: Double
}

/// One read of the on-screen window list, front to back. Reading window numbers,
/// owners and bounds needs no permission.
struct WindowSnapshot {
  /// Normal-level windows that could hold focus, front to back. Lull's own windows,
  /// Stage Manager's strip and invisible helper windows are left out.
  var candidates: [WindowInfo] = []
  /// Every normal-level window, front to back, including Lull's overlays.
  var ordered: [WindowInfo] = []
  /// Stage Manager's own windows; together they mark where the strip is.
  var stripRects: [CGRect] = []

  static let stageManagerOwner = "WindowManager"

  static func capture(ownPID: pid_t = ProcessInfo.processInfo.processIdentifier) -> WindowSnapshot {
    var snapshot = WindowSnapshot()
    guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[CFString: Any]] else {
      return snapshot
    }
    for entry in list {
      guard (entry[kCGWindowLayer] as? Int) == 0,
            let number = entry[kCGWindowNumber] as? Int,
            let pid = entry[kCGWindowOwnerPID] as? Int,
            let boundsValue = entry[kCGWindowBounds],
            let bounds = CGRect(dictionaryRepresentation: boundsValue as! CFDictionary) else { continue }
      let info = WindowInfo(
        id: CGWindowID(number),
        pid: pid_t(pid),
        owner: entry[kCGWindowOwnerName] as? String ?? "",
        bounds: bounds,
        alpha: entry[kCGWindowAlpha] as? Double ?? 1
      )
      snapshot.ordered.append(info)
      if info.owner == stageManagerOwner {
        snapshot.stripRects.append(bounds)
      }
    }
    // A Stage Manager thumbnail is the app's real window, shrunk, with a Stage Manager
    // window of identical bounds on top of it.
    let stripRects = snapshot.stripRects
    snapshot.candidates = snapshot.ordered.filter { window in
      window.pid != ownPID
        && window.owner != stageManagerOwner
        && window.alpha > 0.01
        && window.bounds.width >= 60 && window.bounds.height >= 60
        && !stripRects.contains(window.bounds)
    }
    return snapshot
  }
}
