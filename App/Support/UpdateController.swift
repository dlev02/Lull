import AppKit
import Observation
@preconcurrency import Sparkle

/// Automatic updates through Sparkle. Lull checks by itself, downloads quietly and
/// applies the update the next time it quits, so nothing interrupts the person. A
/// development build has no feed and never checks.
@Observable
final class UpdateController: NSObject, SPUUpdaterDelegate {
  private(set) var lastCheck: Date?
  private(set) var canCheck = false
  /// Set once an update has downloaded and is waiting for a relaunch.
  private(set) var isUpdateReady = false
  var checksAutomatically = false {
    didSet {
      guard let updater, updater.automaticallyChecksForUpdates != checksAutomatically else { return }
      updater.automaticallyChecksForUpdates = checksAutomatically
      updater.automaticallyDownloadsUpdates = checksAutomatically
    }
  }

  @ObservationIgnored private var standard: SPUStandardUpdaterController?
  @ObservationIgnored private var canCheckObservation: NSKeyValueObservation?
  @ObservationIgnored private var installNow: (() -> Void)?

  private var updater: SPUUpdater? { standard?.updater }

  /// True once the updater is running, which only happens in an installed release copy.
  private(set) var isAvailable = false

  private var hasFeed: Bool {
    Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String != nil
      && Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String != nil
  }

  func start() {
    guard standard == nil, hasFeed, LoginItem.isInstalledCopy else {
      Log.info(.update, "updates off: not an installed release copy")
      return
    }
    let standard = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: self, userDriverDelegate: nil)
    self.standard = standard
    canCheckObservation = standard.updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] _, change in
      let value = change.newValue ?? false
      DispatchQueue.main.async {
        MainActor.assumeIsolated { self?.canCheck = value }
      }
    }
    standard.startUpdater()
    isAvailable = true
    checksAutomatically = standard.updater.automaticallyChecksForUpdates
    lastCheck = standard.updater.lastUpdateCheckDate
    Log.info(.update, "updater started, automatic=\(checksAutomatically)")
  }

  /// A check the person asked for; Sparkle shows its own result window.
  func checkNow() {
    guard canCheck else { return }
    Log.info(.update, "manual update check")
    updater?.checkForUpdates()
  }

  /// A quiet check, as the daily one does: no window unless Sparkle needs a decision.
  func checkInBackground() {
    guard isAvailable else { return }
    Log.info(.update, "background update check")
    updater?.checkForUpdatesInBackground()
  }

  func relaunchToUpdate() {
    Log.info(.update, "relaunching to install the update")
    installNow?()
  }

  // MARK: - SPUUpdaterDelegate

  nonisolated func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: (any Error)?) {
    let message = error.map { "update check ended: \($0.localizedDescription)" } ?? "update check finished"
    DispatchQueue.main.async {
      MainActor.assumeIsolated {
        self.lastCheck = self.updater?.lastUpdateCheckDate
        Log.info(.update, message)
      }
    }
  }

  nonisolated func updater(_ updater: SPUUpdater, willInstallUpdateOnQuit item: SUAppcastItem, immediateInstallationBlock immediateInstallHandler: @escaping () -> Void) -> Bool {
    let version = item.displayVersionString
    nonisolated(unsafe) let install = immediateInstallHandler
    DispatchQueue.main.async {
      MainActor.assumeIsolated {
        self.installNow = install
        self.isUpdateReady = true
        Log.info(.update, "version \(version) downloaded; it installs at the next quit")
      }
    }
    return true
  }
}
