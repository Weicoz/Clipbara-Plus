import Foundation

enum PlusSettings {
    static let deduplicationKey = "plusAutomaticDeduplication"
    static let lowMemoryImagesKey = "plusLowMemoryImages"

    static var automaticDeduplication: Bool {
        UserDefaults.standard.object(forKey: deduplicationKey) as? Bool ?? true
    }

    static var lowMemoryImages: Bool {
        UserDefaults.standard.object(forKey: lowMemoryImagesKey) as? Bool ?? true
    }
}
