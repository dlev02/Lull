import AppKit

/// Window-server notifications for windows opening, closing and changing order.
/// They arrive with no permission and no polling, which is what lets Lull follow
/// keyboard-driven changes (⌘W, ⌘`) as well as clicks. The functions are private,
/// so each is looked up at run time; if they are gone, `start` returns false and the
/// engine falls back to watching clicks.
final class WindowEvents {
  private enum Event: UInt32, CaseIterable {
    case closed = 804
    case reordered = 808
    case shown = 815
    case hidden = 816
    case missionControl = 1204
    case created = 1325
    case destroyed = 1326
    case frontChanged = 1508
  }

  private typealias Callback = @convention(c) (UInt32, UnsafeMutableRawPointer?, Int, UnsafeMutableRawPointer?, Int32) -> Void
  private typealias RegisterFunction = @convention(c) (Int32, Callback, UInt32, UnsafeMutableRawPointer?) -> Int32
  private typealias ConnectionFunction = @convention(c) () -> Int32
  private typealias RequestFunction = @convention(c) (Int32, UnsafePointer<UInt32>, Int32) -> Int32

  /// The callback is a C function and cannot capture, so it reaches the one instance here.
  private static weak var current: WindowEvents?

  private var connection: Int32 = 0
  private var request: RequestFunction?
  private var subscribed: [UInt32] = []
  private var isPending = false
  private let handler: () -> Void
  /// Lull's own windows; their events are ignored so moving an overlay never loops.
  var ownWindowIDs: Set<UInt32> = []

  init(handler: @escaping () -> Void) {
    self.handler = handler
  }

  @discardableResult
  func start() -> Bool {
    let handle = UnsafeMutableRawPointer(bitPattern: -2) // RTLD_DEFAULT
    guard let connectionSymbol = dlsym(handle, "SLSMainConnectionID"),
          let registerSymbol = dlsym(handle, "SLSRegisterConnectionNotifyProc"),
          let requestSymbol = dlsym(handle, "SLSRequestNotificationsForWindows") else {
      Log.warning(.windows, "window-server events unavailable; falling back to clicks")
      return false
    }
    connection = unsafeBitCast(connectionSymbol, to: ConnectionFunction.self)()
    request = unsafeBitCast(requestSymbol, to: RequestFunction.self)
    let register = unsafeBitCast(registerSymbol, to: RegisterFunction.self)
    WindowEvents.current = self

    let callback: Callback = { type, data, length, _, _ in
      // Created and destroyed events carry a space identifier before the window number.
      var windowID: UInt32 = 0
      if let data {
        if length >= 12 {
          windowID = data.load(fromByteOffset: 8, as: UInt32.self)
        } else if length >= 4 {
          windowID = data.load(as: UInt32.self)
        }
      }
      DispatchQueue.main.async {
        MainActor.assumeIsolated {
          WindowEvents.current?.received(type, windowID: windowID)
        }
      }
    }
    var failures = 0
    for event in Event.allCases where register(connection, callback, event.rawValue, nil) != 0 {
      failures += 1
    }
    Log.info(.windows, "window-server events registered, \(failures) refused")
    return failures < Event.allCases.count
  }

  /// Reorder and close events are only sent for windows asked about by number.
  func watch(_ windowIDs: [UInt32]) {
    guard let request, windowIDs != subscribed else { return }
    subscribed = windowIDs
    var ids = windowIDs
    _ = request(connection, &ids, Int32(ids.count))
  }

  private func received(_ type: UInt32, windowID: UInt32) {
    guard !ownWindowIDs.contains(windowID), !isPending else { return }
    // A single user action sends a burst; handle it once.
    isPending = true
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.012) { [weak self] in
      MainActor.assumeIsolated {
        guard let self else { return }
        self.isPending = false
        self.handler()
      }
    }
  }
}
