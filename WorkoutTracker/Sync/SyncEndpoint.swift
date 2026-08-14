import Foundation
import SwiftData

// MARK: - Low-level PostgREST access

enum SupabaseRESTError: LocalizedError {
    case invalidResponse
    case httpError(status: Int, body: String)

    /// Without this, Swift's default `Error` bridging shows an unhelpful generic
    /// "The operation couldn't be completed. (WorkoutTracker.SupabaseRESTError error 0.)"
    /// with no indication of what Postgres/PostgREST actually rejected.
    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "The server response wasn't a valid HTTP response."
        case .httpError(let status, let body):
            return "Supabase request failed (HTTP \(status)): \(body)"
        }
    }
}

/// Raw URLSession calls against Supabase's PostgREST endpoint, rather than the
/// supabase-swift SPM package — this app has no auth/realtime needs, so the package
/// would only save some Codable boilerplate at the cost of a dependency to resolve.
enum SupabaseREST {
    private static var baseURL: URL {
        AppSecrets.supabaseURL.appendingPathComponent("rest/v1")
    }

    static let jsonDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            if let date = ISO8601Fractional.formatter.date(from: string) { return date }
            if let date = ISO8601Fractional.plainFormatter.date(from: string) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date: \(string)")
        }
        return decoder
    }()

    static let jsonEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(ISO8601Fractional.formatter.string(from: date))
        }
        return encoder
    }()

    private static func authorizedRequest(url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue(AppSecrets.supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(AppSecrets.supabaseAnonKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return request
    }

    /// One retry after a short delay for transient connection-level failures (dropped
    /// Wi-Fi handoff, a reset connection mid-request) — the kind of hiccup that shows up
    /// as e.g. "Connection has no local endpoint" in the console on a single attempt.
    /// HTTP-level failures (4xx/5xx) are not retried here — `validate` surfaces those as
    /// `SupabaseRESTError.httpError` for the caller to handle.
    private static func perform(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await URLSession.shared.data(for: request)
        } catch is URLError {
            try? await Task.sleep(nanoseconds: 500_000_000)
            return try await URLSession.shared.data(for: request)
        }
    }

    /// Rows changed strictly after `watermark` (all rows if nil).
    static func fetchUpdated<DTO: Decodable>(table: String, since watermark: Date?) async throws -> [DTO] {
        var components = URLComponents(url: baseURL.appendingPathComponent(table), resolvingAgainstBaseURL: false)!
        var queryItems = [URLQueryItem(name: "select", value: "*")]
        if let watermark {
            queryItems.append(URLQueryItem(name: "updated_at", value: "gt.\(ISO8601Fractional.formatter.string(from: watermark))"))
        }
        components.queryItems = queryItems
        let request = authorizedRequest(url: components.url!)
        let (data, response) = try await perform(request)
        try validate(response, data: data)
        return try jsonDecoder.decode([DTO].self, from: data)
    }

    /// Upsert-by-primary-key via PostgREST's `Prefer: resolution=merge-duplicates`.
    static func upsert<DTO: Encodable>(table: String, rows: [DTO]) async throws {
        guard !rows.isEmpty else { return }
        var request = authorizedRequest(url: baseURL.appendingPathComponent(table))
        request.httpMethod = "POST"
        request.setValue("resolution=merge-duplicates,return=minimal", forHTTPHeaderField: "Prefer")
        request.httpBody = try jsonEncoder.encode(rows)
        let (data, response) = try await perform(request)
        try validate(response, data: data)
    }

    /// Deletes join rows for `parentColumn == parentID` whose child isn't in `keepChildIDs`
    /// — the "replace all associations" half of syncing a many-to-many tag set.
    static func deleteJoinRows(table: String, parentColumn: String, parentID: UUID, childColumn: String, keepChildIDs: [UUID]) async throws {
        var components = URLComponents(url: baseURL.appendingPathComponent(table), resolvingAgainstBaseURL: false)!
        var queryItems = [URLQueryItem(name: parentColumn, value: "eq.\(parentID.uuidString)")]
        if !keepChildIDs.isEmpty {
            let list = keepChildIDs.map(\.uuidString).joined(separator: ",")
            queryItems.append(URLQueryItem(name: childColumn, value: "not.in.(\(list))"))
        }
        components.queryItems = queryItems
        var request = authorizedRequest(url: components.url!)
        request.httpMethod = "DELETE"
        let (data, response) = try await perform(request)
        try validate(response, data: data)
    }

    static func fetchWatermarks() async throws -> [String: Date] {
        var request = authorizedRequest(url: baseURL.appendingPathComponent("rpc/sync_watermarks"))
        request.httpMethod = "POST"
        request.httpBody = Data("{}".utf8)
        let (data, response) = try await perform(request)
        try validate(response, data: data)
        struct Row: Decodable { let tableName: String; let maxUpdatedAt: Date? }
        let rows = try jsonDecoder.decode([Row].self, from: data)
        return rows.reduce(into: [:]) { result, row in
            if let date = row.maxUpdatedAt { result[row.tableName] = date }
        }
    }

    private static func validate(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { throw SupabaseRESTError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw SupabaseRESTError.httpError(status: http.statusCode, body: String(data: data, encoding: .utf8) ?? "")
        }
    }
}

private enum ISO8601Fractional {
    static let formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    static let plainFormatter = ISO8601DateFormatter()
}

// MARK: - Catalog DTOs
//
// PostgREST's bulk insert/upsert requires every object in the JSON array to have the
// *same* set of keys (error PGRST102 "All object keys must match" otherwise). Swift's
// auto-synthesized Encodable uses `encodeIfPresent` for Optional properties, which
// *omits* the key entirely when nil — so a batch mixing e.g. bodyweight exercises
// (nil equipmentId) with equipped ones (non-nil) produces rows with different key
// sets. Every DTO below writes its own `encode(to:)` using plain `encode(_:forKey:)`
// instead, which always emits the key (as JSON `null` when the value is nil).

struct MuscleCategoryDTO: Codable {
    let id: UUID
    let name: String
    let updatedAt: Date
    let deletedAt: Date?

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(updatedAt, forKey: .updatedAt)
        try c.encode(deletedAt, forKey: .deletedAt)
    }
}

struct MuscleDTO: Codable {
    let id: UUID
    let name: String
    let iconAssetIdentifier: String
    let updatedAt: Date
    let deletedAt: Date?

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(iconAssetIdentifier, forKey: .iconAssetIdentifier)
        try c.encode(updatedAt, forKey: .updatedAt)
        try c.encode(deletedAt, forKey: .deletedAt)
    }
}

struct EquipmentDTO: Codable {
    let id: UUID
    let name: String
    let iconAssetIdentifier: String
    let isCustom: Bool
    let isAtHome: Bool
    let isAtGym: Bool
    let isWeighted: Bool
    let preferredWeightUnit: String?
    let updatedAt: Date
    let deletedAt: Date?

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(iconAssetIdentifier, forKey: .iconAssetIdentifier)
        try c.encode(isCustom, forKey: .isCustom)
        try c.encode(isAtHome, forKey: .isAtHome)
        try c.encode(isAtGym, forKey: .isAtGym)
        try c.encode(isWeighted, forKey: .isWeighted)
        try c.encode(preferredWeightUnit, forKey: .preferredWeightUnit)
        try c.encode(updatedAt, forKey: .updatedAt)
        try c.encode(deletedAt, forKey: .deletedAt)
    }
}

struct WeightComboDTO: Codable {
    let id: UUID
    let equipmentId: UUID
    let value: Double
    let sortOrder: Int
    let updatedAt: Date
    let deletedAt: Date?

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(equipmentId, forKey: .equipmentId)
        try c.encode(value, forKey: .value)
        try c.encode(sortOrder, forKey: .sortOrder)
        try c.encode(updatedAt, forKey: .updatedAt)
        try c.encode(deletedAt, forKey: .deletedAt)
    }
}

struct ExerciseCategoryDTO: Codable {
    let id: UUID
    let name: String
    let updatedAt: Date
    let deletedAt: Date?

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(updatedAt, forKey: .updatedAt)
        try c.encode(deletedAt, forKey: .deletedAt)
    }
}

struct ExerciseDTO: Codable {
    let id: UUID
    let name: String
    let label: String?
    let notes: String?
    let iconAssetIdentifier: String
    let isCustom: Bool
    let isFavorited: Bool
    let updatedAt: Date
    let deletedAt: Date?

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(label, forKey: .label)
        try c.encode(notes, forKey: .notes)
        try c.encode(iconAssetIdentifier, forKey: .iconAssetIdentifier)
        try c.encode(isCustom, forKey: .isCustom)
        try c.encode(isFavorited, forKey: .isFavorited)
        try c.encode(updatedAt, forKey: .updatedAt)
        try c.encode(deletedAt, forKey: .deletedAt)
    }
}

// MARK: - Adapter protocol

/// One conformance per syncable entity type. `CatalogSync` (SyncEngine.swift) is
/// written once against this protocol instead of once per table.
protocol CatalogSyncAdapter {
    associatedtype Model: SyncableModel
    associatedtype DTO: Codable

    static var tableName: String { get }
    static func dto(from model: Model) -> DTO
    static func id(of dto: DTO) -> UUID
    static func updatedAt(of dto: DTO) -> Date
    static func deletedAt(of dto: DTO) -> Date?
    static func fetchLocal(id: UUID, context: ModelContext) -> Model?
    static func insertLocal(from dto: DTO, context: ModelContext) -> Model
    static func applyRemote(_ dto: DTO, to model: Model, context: ModelContext)
}

enum MuscleCategorySyncAdapter: CatalogSyncAdapter {
    static let tableName = "muscle_categories"
    static func dto(from model: MuscleCategory) -> MuscleCategoryDTO {
        MuscleCategoryDTO(id: model.id, name: model.name, updatedAt: model.updatedAt, deletedAt: model.deletedAt)
    }
    static func id(of dto: MuscleCategoryDTO) -> UUID { dto.id }
    static func updatedAt(of dto: MuscleCategoryDTO) -> Date { dto.updatedAt }
    static func deletedAt(of dto: MuscleCategoryDTO) -> Date? { dto.deletedAt }
    static func fetchLocal(id: UUID, context: ModelContext) -> MuscleCategory? {
        var descriptor = FetchDescriptor<MuscleCategory>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }
    static func insertLocal(from dto: MuscleCategoryDTO, context: ModelContext) -> MuscleCategory {
        let model = MuscleCategory(id: dto.id, name: dto.name)
        context.insert(model)
        return model
    }
    static func applyRemote(_ dto: MuscleCategoryDTO, to model: MuscleCategory, context: ModelContext) {
        model.name = dto.name
    }
}

enum MuscleSyncAdapter: CatalogSyncAdapter {
    static let tableName = "muscles"
    static func dto(from model: Muscle) -> MuscleDTO {
        MuscleDTO(id: model.id, name: model.name, iconAssetIdentifier: model.iconSymbolName, updatedAt: model.updatedAt, deletedAt: model.deletedAt)
    }
    static func id(of dto: MuscleDTO) -> UUID { dto.id }
    static func updatedAt(of dto: MuscleDTO) -> Date { dto.updatedAt }
    static func deletedAt(of dto: MuscleDTO) -> Date? { dto.deletedAt }
    static func fetchLocal(id: UUID, context: ModelContext) -> Muscle? {
        var descriptor = FetchDescriptor<Muscle>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }
    static func insertLocal(from dto: MuscleDTO, context: ModelContext) -> Muscle {
        let model = Muscle(id: dto.id, name: dto.name, iconSymbolName: dto.iconAssetIdentifier)
        context.insert(model)
        return model
    }
    static func applyRemote(_ dto: MuscleDTO, to model: Muscle, context: ModelContext) {
        model.name = dto.name
        model.iconSymbolName = dto.iconAssetIdentifier
    }
}

enum EquipmentSyncAdapter: CatalogSyncAdapter {
    static let tableName = "equipment"
    static func dto(from model: Equipment) -> EquipmentDTO {
        EquipmentDTO(id: model.id, name: model.name, iconAssetIdentifier: model.iconSymbolName, isCustom: model.isCustom, isAtHome: model.isAtHome, isAtGym: model.isAtGym, isWeighted: model.isWeighted, preferredWeightUnit: model.preferredWeightUnit, updatedAt: model.updatedAt, deletedAt: model.deletedAt)
    }
    static func id(of dto: EquipmentDTO) -> UUID { dto.id }
    static func updatedAt(of dto: EquipmentDTO) -> Date { dto.updatedAt }
    static func deletedAt(of dto: EquipmentDTO) -> Date? { dto.deletedAt }
    static func fetchLocal(id: UUID, context: ModelContext) -> Equipment? {
        var descriptor = FetchDescriptor<Equipment>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }
    static func insertLocal(from dto: EquipmentDTO, context: ModelContext) -> Equipment {
        let model = Equipment(id: dto.id, name: dto.name, iconSymbolName: dto.iconAssetIdentifier, isCustom: dto.isCustom, isAtHome: dto.isAtHome, isAtGym: dto.isAtGym, isWeighted: dto.isWeighted, preferredWeightUnit: dto.preferredWeightUnit)
        context.insert(model)
        return model
    }
    static func applyRemote(_ dto: EquipmentDTO, to model: Equipment, context: ModelContext) {
        model.name = dto.name
        model.iconSymbolName = dto.iconAssetIdentifier
        model.isCustom = dto.isCustom
        model.isAtHome = dto.isAtHome
        model.isAtGym = dto.isAtGym
        model.isWeighted = dto.isWeighted
        model.preferredWeightUnit = dto.preferredWeightUnit
    }
}

enum WeightComboSyncAdapter: CatalogSyncAdapter {
    static let tableName = "weight_combos"
    static func dto(from model: WeightCombo) -> WeightComboDTO {
        WeightComboDTO(id: model.id, equipmentId: model.equipment?.id ?? UUID(), value: model.value, sortOrder: model.sortOrder, updatedAt: model.updatedAt, deletedAt: model.deletedAt)
    }
    static func id(of dto: WeightComboDTO) -> UUID { dto.id }
    static func updatedAt(of dto: WeightComboDTO) -> Date { dto.updatedAt }
    static func deletedAt(of dto: WeightComboDTO) -> Date? { dto.deletedAt }
    static func fetchLocal(id: UUID, context: ModelContext) -> WeightCombo? {
        var descriptor = FetchDescriptor<WeightCombo>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }
    static func insertLocal(from dto: WeightComboDTO, context: ModelContext) -> WeightCombo {
        let equipment = EquipmentSyncAdapter.fetchLocal(id: dto.equipmentId, context: context)
        let model = WeightCombo(id: dto.id, equipment: equipment, value: dto.value, sortOrder: dto.sortOrder)
        context.insert(model)
        return model
    }
    static func applyRemote(_ dto: WeightComboDTO, to model: WeightCombo, context: ModelContext) {
        model.value = dto.value
        model.sortOrder = dto.sortOrder
        if model.equipment?.id != dto.equipmentId {
            model.equipment = EquipmentSyncAdapter.fetchLocal(id: dto.equipmentId, context: context)
        }
    }
}

enum ExerciseCategorySyncAdapter: CatalogSyncAdapter {
    static let tableName = "exercise_categories"
    static func dto(from model: ExerciseCategory) -> ExerciseCategoryDTO {
        ExerciseCategoryDTO(id: model.id, name: model.name, updatedAt: model.updatedAt, deletedAt: model.deletedAt)
    }
    static func id(of dto: ExerciseCategoryDTO) -> UUID { dto.id }
    static func updatedAt(of dto: ExerciseCategoryDTO) -> Date { dto.updatedAt }
    static func deletedAt(of dto: ExerciseCategoryDTO) -> Date? { dto.deletedAt }
    static func fetchLocal(id: UUID, context: ModelContext) -> ExerciseCategory? {
        var descriptor = FetchDescriptor<ExerciseCategory>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }
    static func insertLocal(from dto: ExerciseCategoryDTO, context: ModelContext) -> ExerciseCategory {
        let model = ExerciseCategory(id: dto.id, name: dto.name)
        context.insert(model)
        return model
    }
    static func applyRemote(_ dto: ExerciseCategoryDTO, to model: ExerciseCategory, context: ModelContext) {
        model.name = dto.name
    }
}

enum ExerciseSyncAdapter: CatalogSyncAdapter {
    static let tableName = "exercises"
    static func dto(from model: Exercise) -> ExerciseDTO {
        ExerciseDTO(id: model.id, name: model.name, label: model.label, notes: model.notes, iconAssetIdentifier: model.iconSymbolName, isCustom: model.isCustom, isFavorited: model.isFavorited, updatedAt: model.updatedAt, deletedAt: model.deletedAt)
    }
    static func id(of dto: ExerciseDTO) -> UUID { dto.id }
    static func updatedAt(of dto: ExerciseDTO) -> Date { dto.updatedAt }
    static func deletedAt(of dto: ExerciseDTO) -> Date? { dto.deletedAt }
    static func fetchLocal(id: UUID, context: ModelContext) -> Exercise? {
        var descriptor = FetchDescriptor<Exercise>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }
    static func insertLocal(from dto: ExerciseDTO, context: ModelContext) -> Exercise {
        // imageAssetName isn't part of the sync payload — it's a local-only reference
        // photo derived from the exercise's name, the same on every device. Equipment
        // associations arrive separately via the `exercise_equipment` join sync.
        let model = Exercise(id: dto.id, name: dto.name, label: dto.label, notes: dto.notes, iconSymbolName: dto.iconAssetIdentifier, imageAssetName: ExerciseImageMapping.assetName[dto.name], isCustom: dto.isCustom, isFavorited: dto.isFavorited)
        context.insert(model)
        return model
    }
    static func applyRemote(_ dto: ExerciseDTO, to model: Exercise, context: ModelContext) {
        model.name = dto.name
        model.label = dto.label
        model.notes = dto.notes
        model.iconSymbolName = dto.iconAssetIdentifier
        model.isCustom = dto.isCustom
        model.isFavorited = dto.isFavorited
    }
}

// MARK: - Many-to-many join sync ("replace all associations for this parent")

/// Catalog tag associations (muscle↔category, exercise↔muscle, exercise↔category)
/// change rarely and only from this one device, so instead of tracking per-row
/// dirty/tombstone state for every join row, syncing a parent pushes its *complete*
/// current association set: upsert the pairs it has now, delete any remote pairs for
/// that parent it no longer has. Good enough for a single-device app; a multi-device
/// version would need per-row tombstones like every other table.
enum JoinSync {
    struct LinkDTO: Codable {
        let id: UUID
        let updatedAt: Date
        let deletedAt: Date?
    }

    static func pushMuscleCategories(for muscle: Muscle) async throws {
        try await replace(
            table: "muscle_muscle_categories",
            parentColumn: "muscle_id", parentID: muscle.id,
            childColumn: "muscle_category_id", childIDs: muscle.categories.map(\.id)
        )
    }

    static func pushExerciseMuscles(for exercise: Exercise) async throws {
        try await replace(
            table: "exercise_muscles",
            parentColumn: "exercise_id", parentID: exercise.id,
            childColumn: "muscle_id", childIDs: exercise.muscles.map(\.id)
        )
    }

    static func pushExerciseCategories(for exercise: Exercise) async throws {
        try await replace(
            table: "exercise_exercise_categories",
            parentColumn: "exercise_id", parentID: exercise.id,
            childColumn: "exercise_category_id", childIDs: exercise.categories.map(\.id)
        )
    }

    static func pushExerciseEquipment(for exercise: Exercise) async throws {
        try await replace(
            table: "exercise_equipment",
            parentColumn: "exercise_id", parentID: exercise.id,
            childColumn: "equipment_id", childIDs: exercise.equipmentItems.map(\.id)
        )
    }

    private static func replace(table: String, parentColumn: String, parentID: UUID, childColumn: String, childIDs: [UUID]) async throws {
        struct Row: Encodable {
            let id: UUID
            let updatedAt: Date
            // Encoded via a dynamic key since the parent/child column names vary by table.
            let parentColumn: String
            let parentID: UUID
            let childColumn: String
            let childID: UUID

            func encode(to encoder: Encoder) throws {
                struct Key: CodingKey {
                    var stringValue: String
                    init?(stringValue: String) { self.stringValue = stringValue }
                    var intValue: Int? { nil }
                    init?(intValue: Int) { nil }
                }
                var container = encoder.container(keyedBy: Key.self)
                try container.encode(id, forKey: Key(stringValue: "id")!)
                try container.encode(updatedAt, forKey: Key(stringValue: "updated_at")!)
                try container.encode(parentID, forKey: Key(stringValue: parentColumn)!)
                try container.encode(childID, forKey: Key(stringValue: childColumn)!)
            }
        }
        let rows = childIDs.map { childID in
            Row(id: pairID(parentID, childID), updatedAt: .now, parentColumn: parentColumn, parentID: parentID, childColumn: childColumn, childID: childID)
        }
        try await SupabaseREST.upsert(table: table, rows: rows)
        try await SupabaseREST.deleteJoinRows(table: table, parentColumn: parentColumn, parentID: parentID, childColumn: childColumn, keepChildIDs: childIDs)
    }

    /// Deterministic id for a (parent, child) pair — re-pushing the same association
    /// upserts the same remote row instead of accumulating duplicates.
    private static func pairID(_ a: UUID, _ b: UUID) -> UUID {
        let aBytes = withUnsafeBytes(of: a.uuid) { Array($0) }
        let bBytes = withUnsafeBytes(of: b.uuid) { Array($0) }
        var result = [UInt8](repeating: 0, count: 16)
        for i in 0..<16 { result[i] = aBytes[i] ^ bBytes[i] }
        return result.withUnsafeBytes { $0.load(as: UUID.self) }
    }
}
