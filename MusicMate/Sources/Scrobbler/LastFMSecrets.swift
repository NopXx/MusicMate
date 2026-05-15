import Foundation

/// Last.fm API credentials baked into the app at build time via
/// `Secrets.xcconfig` → `Info.plist` substitution.
///
/// User-supplied keys (Settings → Last.fm) always take precedence;
/// these bundled values are the fallback so distributable builds work
/// out of the box without forcing every user to register their own API
/// application.
enum LastFMSecrets {
    static var bundledAPIKey: String {
        (Bundle.main.infoDictionary?["LastFMAPIKey"] as? String) ?? ""
    }

    static var bundledAPISecret: String {
        (Bundle.main.infoDictionary?["LastFMAPISecret"] as? String) ?? ""
    }

    /// Returns the user-provided key if non-empty, otherwise the bundled key.
    static func resolveKey(_ userKey: String?) -> String {
        let trimmed = (userKey ?? "").trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? bundledAPIKey : trimmed
    }

    /// Returns the user-provided secret if non-empty, otherwise the bundled secret.
    static func resolveSecret(_ userSecret: String?) -> String {
        let trimmed = (userSecret ?? "").trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? bundledAPISecret : trimmed
    }
}
