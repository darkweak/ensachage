import SwiftUI

/// Centralized presentation (label, icon, color) for a journal outcome, so the
/// list row and the detail view stay consistent.
extension LogEntry.Outcome {
    var title: String {
        switch self {
        case .success: return "Déverrouillage réussi"
        case .failure: return "Échec de déverrouillage"
        case .test:    return "Photo de test"
        }
    }

    var rowIcon: String {
        switch self {
        case .success: return "lock.open.fill"
        case .failure: return "lock.trianglebadge.exclamationmark.fill"
        case .test:    return "camera.fill"
        }
    }

    var detailIcon: String {
        switch self {
        case .success: return "checkmark.seal.fill"
        case .failure: return "exclamationmark.triangle.fill"
        case .test:    return "camera.viewfinder"
        }
    }

    var tint: Color {
        switch self {
        case .success: return .green
        case .failure: return .red
        case .test:    return .blue
        }
    }
}
