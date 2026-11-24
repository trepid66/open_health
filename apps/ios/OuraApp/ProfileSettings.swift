import SwiftUI
import HealthKit

private struct EditableProfile {
    var sex: String
    var age: Double
    var heightCm: Double
    var weightKg: Double
    var ringSize: Double

    init(_ profile: Profile?) {
        sex = profile?.sex ?? "M"
        age = profile?.age ?? 30
        heightCm = (profile?.height_m ?? 1.78) * 100
        weightKg = profile?.weight_kg ?? 75
        ringSize = profile?.ring_size ?? 10
    }
}

private enum ProfileStore {
    static var url: URL { DB.url.deletingLastPathComponent().appendingPathComponent("profile.json") }

    static func save(_ p: EditableProfile) throws {
        let object: [String: Any] = [
            "sex": p.sex, "age": p.age, "height_m": p.heightCm / 100,
            "weight_kg": p.weightKg, "ring_size": p.ringSize,
        ]
        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url, options: .atomic)
    }
}

private struct HealthProfile {
    var sex: String?
    var age: Double?
    var heightCm: Double?
    var weightKg: Double?
}

private enum HealthProfileImporter {
    static func load(completion: @escaping (Result<HealthProfile, Error>) -> Void) {
        guard HKHealthStore.isHealthDataAvailable() else {
            completion(.failure(NSError(domain: "open_oura", code: 1,
                                        userInfo: [NSLocalizedDescriptionKey: "Apple Health is unavailable on this device."])))
            return
        }
        let store = HKHealthStore()
        let dob = HKObjectType.characteristicType(forIdentifier: .dateOfBirth)!
        let biologicalSex = HKObjectType.characteristicType(forIdentifier: .biologicalSex)!
        let height = HKObjectType.quantityType(forIdentifier: .height)!
        let mass = HKObjectType.quantityType(forIdentifier: .bodyMass)!
        let read: Set<HKObjectType> = [dob, biologicalSex, height, mass]
        store.requestAuthorization(toShare: [], read: read) { granted, error in
            if let error { DispatchQueue.main.async { completion(.failure(error)) }; return }
            guard granted else {
                let e = NSError(domain: "open_oura", code: 2,
                                userInfo: [NSLocalizedDescriptionKey: "Apple Health access was not granted."])
                DispatchQueue.main.async { completion(.failure(e)) }
                return
            }

            var result = HealthProfile()
            if let birth = try? store.dateOfBirthComponents().date {
                result.age = Double(Calendar.current.dateComponents([.year], from: birth, to: Date()).year ?? 0)
            }
            if let value = try? store.biologicalSex().biologicalSex {
                switch value {
                case .female: result.sex = "F"
                case .male: result.sex = "M"
                case .other: result.sex = "O"
                default: break
                }
            }

            let group = DispatchGroup()
            func latest(_ type: HKQuantityType, unit: HKUnit, assign: @escaping (Double) -> Void) {
                group.enter()
                let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
                let query = HKSampleQuery(sampleType: type, predicate: nil, limit: 1,
                                          sortDescriptors: [sort]) { _, samples, _ in
                    if let sample = samples?.first as? HKQuantitySample {
                        assign(sample.quantity.doubleValue(for: unit))
                    }
                    group.leave()
                }
                store.execute(query)
            }
            latest(height, unit: .meterUnit(with: .centi)) { result.heightCm = $0 }
            latest(mass, unit: .gramUnit(with: .kilo)) { result.weightKg = $0 }
            group.notify(queue: .main) { completion(.success(result)) }
        }
    }
}

struct ProfileSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var profile: EditableProfile
    @State private var importing = false
    @State private var message: String?
    @ObservedObject private var health = HealthExport.shared
    let onSaved: () -> Void

    init(profile: Profile?, onSaved: @escaping () -> Void) {
        _profile = State(initialValue: EditableProfile(profile))
        self.onSaved = onSaved
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Sexo biológico", selection: $profile.sex) {
                        Text("Mujer").tag("F")
                        Text("Hombre").tag("M")
                        Text("Otro").tag("O")
                    }
                    HStack {
                        Text("Edad")
                        Spacer()
                        TextField("Edad", value: $profile.age, format: .number.precision(.fractionLength(0...1)))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 100)
                    }
                    HStack {
                        Text("Altura (cm)")
                        Spacer()
                        TextField("Altura (cm)", value: $profile.heightCm, format: .number.precision(.fractionLength(0...1)))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 100)
                    }
                    HStack {
                        Text("Peso (kg)")
                        Spacer()
                        TextField("Peso (kg)", value: $profile.weightKg, format: .number.precision(.fractionLength(0...1)))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 100)
                    }
                    HStack {
                        Text("Talla del anillo")
                        Spacer()
                        TextField("Talla del anillo", value: $profile.ringSize, format: .number.precision(.fractionLength(0...1)))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 100)
                    }
                } header: {
                    Text("Tus datos")
                } footer: {
                    Text("Se guardan únicamente en este iPhone y se utilizan en los cálculos cardiovasculares y de actividad.")
                }

                Section {
                    Button {
                        importing = true; message = nil
                        HealthProfileImporter.load { result in
                            importing = false
                            switch result {
                            case .success(let health):
                                if let v = health.sex { profile.sex = v }
                                if let v = health.age, v > 0 { profile.age = v }
                                if let v = health.heightCm { profile.heightCm = v }
                                if let v = health.weightKg { profile.weightKg = v }
                                message = "Datos disponibles importados de Apple Salud."
                            case .failure(let error): message = error.localizedDescription
                            }
                        }
                    } label: {
                        HStack {
                            Label("Importar desde Apple Salud", systemImage: "heart.text.square")
                            Spacer()
                            if importing { ProgressView() }
                        }
                    }
                    .disabled(importing)
                    if let message { Text(message).font(.footnote).foregroundStyle(Obs.ink2) }
                }

                Section {
                    Toggle("Exportar datos del anillo a Apple Salud", isOn: Binding(
                        get: { health.enabled },
                        set: { health.setEnabled($0, summary: SummaryCache.load()) }
                    ))
                    if !health.status.isEmpty {
                        Text(health.status).font(.footnote).foregroundStyle(Obs.ink2)
                    }
                    if health.enabled {
                        Button("Eliminar los datos de Open Oura de Salud") {
                            health.removeExportedSamples()
                        }
                        .foregroundStyle(Obs.bad)
                    }
                } header: {
                    Text("Apple Salud")
                } footer: {
                    Text("Exporta entrenamientos, fases de sueño, pulso, HRV, pulso en reposo, pasos, calorías activas y distancia. Los datos permanecen en el iPhone.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Obs.canvas.ignoresSafeArea())
            .navigationTitle("Perfil")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") {
                        do {
                            try ProfileStore.save(profile)
                            onSaved()
                            dismiss()
                        } catch { message = "Could not save: \(error.localizedDescription)" }
                    }
                }
            }
        }
    }
}
