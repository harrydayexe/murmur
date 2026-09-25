import Foundation
import FoundationModels

/// On-device model availability, with reasons as strings (they've changed between OS point releases).
enum ModelStatus {
    static func describe(_ availability: SystemLanguageModel.Availability) -> String {
        switch availability {
        case .available: "available"
        case .unavailable(let reason): String(describing: reason)
        }
    }

    /// Throws `AIError.unavailable` and logs the reason if the model can't be used.
    static func requireAvailable(_ model: SystemLanguageModel) throws {
        let availability = model.availability
        guard case .available = availability else {
            let reason = describe(availability)
            Log.ai.notice("On-device model unavailable: \(reason, privacy: .public)")
            throw AIError.unavailable(reason)
        }
    }

    /// True if the error means the prompt didn't fit the context window.
    static func isContextExceeded(_ error: Error) -> Bool {
        if #available(macOS 27, *), let error = error as? LanguageModelError, case .contextSizeExceeded = error {
            return true
        }
        if let error = error as? LanguageModelSession.GenerationError, case .exceededContextWindowSize = error {
            return true
        }
        return false
    }
}
