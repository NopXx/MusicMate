import SwiftUI

enum LockScreenBackgroundStyle: String, CaseIterable, Identifiable {
    case blurredArtwork = "blurred_artwork"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .blurredArtwork: return "Blurred Artwork"
        }
    }
}