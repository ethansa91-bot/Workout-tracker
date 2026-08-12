import Foundation

/// Default SF Symbol assigned to a custom item created after install, keyed by the
/// closest catalog concept. The seed catalog assigns its own specific symbol per item
/// directly (see SeedData/*.json) — this mapping only covers user-created items.
enum IconSymbolMapping {
    static let defaultMuscleSymbol = "figure.strengthtraining.traditional"
    static let defaultEquipmentSymbol = "dumbbell.fill"

    static func defaultExerciseSymbol(forCategoryNames categoryNames: [String]) -> String {
        let lowered = Set(categoryNames.map { $0.lowercased() })
        if lowered.contains("cardio") { return "figure.run" }
        if lowered.contains("mobility") { return "figure.cooldown" }
        if lowered.contains("warmups") || lowered.contains("warm ups") { return "flame" }
        if lowered.contains("plyo") { return "figure.jumprope" }
        if lowered.contains("physio") { return "figure.flexibility" }
        if lowered.contains("calisthenics") { return "figure.core.training" }
        return "figure.strengthtraining.traditional"
    }
}
