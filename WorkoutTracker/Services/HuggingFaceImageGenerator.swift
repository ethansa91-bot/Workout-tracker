import Foundation

/// Image generator using Hugging Face's free "HF Inference" provider, routed through
/// their unified Inference Providers gateway. Requires `AppSecrets.huggingFaceAPIToken`
/// — a token from https://huggingface.co/settings/tokens with the "Make calls to
/// Inference Providers" permission checked (the classic "Read" token alone is not
/// enough as of the Inference Providers migration) — no billing needed. `isAvailable`
/// reports false when no token is configured so callers can simply hide this option
/// rather than crash or force setup.
///
/// The legacy `api-inference.huggingface.co` host is fully decommissioned (DNS no
/// longer resolves); requests now go through `router.huggingface.co/hf-inference/...`.
/// The free tier is rate-limited and only serves a short, frequently-changing roster of
/// models — verified against `GET https://huggingface.co/api/models?pipeline_tag=text-to-image&inference_provider=hf-inference`
/// at the time this was written, which returned exactly one model
/// (`stabilityai/stable-diffusion-3-medium-diffusers`). Re-check that list before
/// assuming any other model id works here. A cold-start delay is possible the first
/// time an infrequently-used model is requested (the API returns a 503 with an
/// `estimated_time` while it loads — surfaced here as a retryable `serverMessage`, not
/// a hard failure).
struct HuggingFaceImageGenerator: ExerciseImageGenerating {
    private let model = "stabilityai/stable-diffusion-3-medium-diffusers"

    var isAvailable: Bool { AppSecrets.huggingFaceAPIToken != nil }

    func generateImage(description: String, style: ExerciseImageStyle) async throws -> Data {
        let trimmed = description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ExerciseImageGenerationError.emptyDescription }
        guard let token = AppSecrets.huggingFaceAPIToken else { throw ExerciseImageGenerationError.providerUnavailable }
        guard let url = URL(string: "https://router.huggingface.co/hf-inference/models/\(model)") else {
            throw ExerciseImageGenerationError.invalidResponse
        }

        let prompt = "\(trimmed). \(style.promptModifier)"

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(RequestBody(inputs: prompt))

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ExerciseImageGenerationError.invalidResponse
        }

        let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type") ?? ""
        guard httpResponse.statusCode == 200, contentType.hasPrefix("image/") else {
            if let errorBody = try? JSONDecoder().decode(ErrorResponse.self, from: data) {
                if let estimatedTime = errorBody.estimatedTime {
                    throw ExerciseImageGenerationError.serverMessage(
                        "The model is still warming up — try again in about \(Int(estimatedTime.rounded()))s."
                    )
                }
                throw ExerciseImageGenerationError.serverMessage(errorBody.error)
            }
            throw ExerciseImageGenerationError.invalidResponse
        }
        return data
    }

    private struct RequestBody: Encodable {
        let inputs: String
    }

    private struct ErrorResponse: Decodable {
        let error: String
        let estimatedTime: Double?

        enum CodingKeys: String, CodingKey {
            case error
            case estimatedTime = "estimated_time"
        }
    }
}
