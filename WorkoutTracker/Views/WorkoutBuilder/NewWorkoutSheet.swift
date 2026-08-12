import SwiftUI

struct NewWorkoutSheet: View {
    let onCreate: (String, WorkoutKind) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var kind: WorkoutKind = .personalized

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Workout name", text: $name)
                }
                Section("Type") {
                    Picker("Type", selection: $kind) {
                        Text("Personalized").tag(WorkoutKind.personalized)
                        Text("By Time").tag(WorkoutKind.byTime)
                        Text("By Reps").tag(WorkoutKind.byRep)
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                    Text(kindDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .themedListBackground()
            .navigationTitle("New Workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        onCreate(trimmedName, kind)
                        dismiss()
                    }
                    .disabled(trimmedName.isEmpty)
                }
            }
        }
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespaces)
    }

    private var kindDescription: String {
        switch kind {
        case .personalized: return "Mix time and rep blocks freely."
        case .byTime: return "A single timed block — add exercises next."
        case .byRep: return "A single set/rep block — add exercises next."
        }
    }
}
