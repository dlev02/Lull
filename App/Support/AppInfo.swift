import Foundation

/// Facts about this app that the interface and the command line both show.
enum AppInfo {
  static let name = "Lull"
  static let author = "Drew Levinson"
  static let authorURL = URL(string: "https://github.com/dlev02")!
  static let repositoryURL = URL(string: "https://github.com/dlev02/Lull")!
  static let privacyURL = URL(string: "https://github.com/dlev02/Lull/blob/main/PRIVACY.md")!

  static var version: String {
    Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
  }

  static var build: String {
    Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
  }

  /// A new GitHub issue, prefilled with what a report needs. Nothing is sent anywhere
  /// until the person submits the issue themselves.
  static func issueURL(displays: String, stageManager: Bool, blurBackend: String) -> URL {
    let body = """


    ---
    Lull \(version) (\(build))
    macOS \(ProcessInfo.processInfo.operatingSystemVersionString)
    Displays: \(displays)
    Stage Manager: \(stageManager ? "on" : "off")
    Blur: \(blurBackend)
    """
    var components = URLComponents(url: repositoryURL.appendingPathComponent("issues/new"), resolvingAgainstBaseURL: false)!
    components.queryItems = [URLQueryItem(name: "body", value: body)]
    return components.url ?? repositoryURL
  }
}
