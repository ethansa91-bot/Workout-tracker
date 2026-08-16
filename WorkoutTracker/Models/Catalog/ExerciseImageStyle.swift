import Foundation

/// The 3 fixed illustration styles an AI-generated exercise image can be produced in.
/// Wording is intentionally not user-editable — only which of the 3 to apply is a choice.
enum ExerciseImageStyle: String, CaseIterable, Identifiable {
    case flatVector
    case lineArt
    case anatomical3D

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .flatVector: "Flat Illustration"
        case .lineArt: "Line Art"
        case .anatomical3D: "3D Anatomical"
        }
    }

    /// Asset catalog name of the thumbnail shown in the style picker.
    var previewAssetName: String {
        switch self {
        case .flatVector: "StylePreviewFlatVector"
        case .lineArt: "StylePreviewLineArt"
        case .anatomical3D: "StylePreviewAnatomical3D"
        }
    }

    /// Fixed style text appended to every generation prompt.
    var promptModifier: String {
        switch self {
        case .flatVector:
            "flat 2D vector illustration, two-panel diagram showing the start and end position of the movement, bold clean outlines, navy blue athletic shorts, light skin tone, red highlighted target muscle group, flat solid colors with no shading or gradients, plain light gray background, minimalist fitness/medical illustration style"
        case .lineArt:
            "black and white hand-drawn line art sketch, two-panel numbered diagram (1 and 2) showing the start and end position, motion arrows indicating the direction of movement, black outlines only on a plain white background, no color fill, technical instructional sketch style"
        case .anatomical3D:
            "3D rendered anatomical muscle diagram, realistic human figure model, red highlighted engaged muscle groups against a grayscale body, two-panel sequence showing start and end position, dark background, dramatic studio lighting, photorealistic 3D render fitness-app style"
        }
    }
}
