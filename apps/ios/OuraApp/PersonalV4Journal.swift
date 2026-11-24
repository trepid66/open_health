import Foundation
import SwiftUI
import UniformTypeIdentifiers

// Independent local data store. The ring database and pairing key are untouched.
enum V4Date {
    static func key(_ date: Date) -> String {
        let p = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", p.year ?? 0, p.month ?? 0, p.day ?? 0)
    }
    static func shifted(_ date: Date, _ days: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: days, to: date) ?? date
    }
    static func recent(_ date: Date, _ days: Int) -> [String] {
        (0..<days).reversed().map { key(shifted(date, -$0)) }
    }
    static func title(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "es_ES")
        formatter.dateFormat = "EEEE, d 'de' MMMM"
        return formatter.string(from: date).capitalized
    }
}

struct V4DiaryEntry: Codable, Equatable {
    var mood = ""
    var habits: [String] = []
    var weight: Double? = nil
    var notes = ""
    var isEmpty: Bool { mood.isEmpty && habits.isEmpty && weight == nil && notes.isEmpty }
}

struct V4Workout: Codable, Identifiable, Equatable {
    var id = UUID()
    var day: String
    var sport: String
    var minutes: Int
    var effort: Int
    var distance: Double?
    var notes: String
    var load: Int { minutes * effort }
}

struct V4PersonalData: Codable {
    var version = 1
    var diary: [String: V4DiaryEntry] = [:]
    var workouts: [V4Workout] = []
}

struct V4Backup: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    let bytes: Data
    init(bytes: Data) { self.bytes = bytes }
    init(configuration: ReadConfiguration) throws {
        guard let bytes = configuration.file.regularFileContents else { throw CocoaError(.fileReadCorruptFile) }
        self.bytes = bytes
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: bytes)
    }
}

@MainActor final class V4JournalStore: ObservableObject {
    @Published private(set) var data = V4PersonalData()
    @Published private(set) var error: String?
    private var unreadable = false
    private let url: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("OpenOuraPersonalV4.json")
    init() {
        if FileManager.default.fileExists(atPath: url.path) {
            do {
                let bytes = try Data(contentsOf: url)
                let saved = try JSONDecoder().decode(V4PersonalData.self, from: bytes)
                guard saved.version == 1 else { throw CocoaError(.fileReadCorruptFile) }
                data = saved
            } catch {
                unreadable = true
                self.error = "No se han podido leer los registros locales. Se conserva el archivo original."
            }
        }
    }
    func entry(_ day: String) -> V4DiaryEntry { data.diary[day] ?? V4DiaryEntry() }
    func workouts(_ day: String) -> [V4Workout] { data.workouts.filter { $0.day == day } }
    func encoded() throws -> Data {
        guard !unreadable else { throw CocoaError(.fileReadCorruptFile) }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(data)
    }
    private func commit(_ candidate: V4PersonalData) -> Bool {
        guard !unreadable else { return false }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let bytes = try JSONEncoder().encode(candidate)
            try bytes.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            data = candidate
            error = nil
            return true
        } catch {
            self.error = "No se han podido guardar los datos. Los registros anteriores se conservan."
            return false
        }
    }
    @discardableResult func save(_ entry: V4DiaryEntry, day: String) -> Bool {
        var candidate = data
        candidate.diary[day] = entry.isEmpty ? nil : entry
        return commit(candidate)
    }
    @discardableResult func save(_ workout: V4Workout) -> Bool {
        var candidate = data
        candidate.workouts.removeAll { $0.id == workout.id }
        candidate.workouts.append(workout)
        return commit(candidate)
    }
    func remove(_ id: UUID) {
        var candidate = data
        candidate.workouts.removeAll { $0.id == id }
        _ = commit(candidate)
    }
    func readBackup(_ url: URL) throws -> V4PersonalData {
        let granted = url.startAccessingSecurityScopedResource()
        defer { if granted { url.stopAccessingSecurityScopedResource() } }
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        guard (values.fileSize ?? 0) <= 10_000_000 else { throw CocoaError(.fileReadTooLarge) }
        let incoming = try JSONDecoder().decode(V4PersonalData.self, from: Data(contentsOf: url))
        guard incoming.version == 1,
              incoming.diary.allSatisfy({ validDay($0.key) && ($0.value.weight.map { $0.isFinite && $0 > 0 && $0 <= 500 } ?? true) }),
              incoming.workouts.allSatisfy({ validDay($0.day) && !$0.sport.isEmpty && (1...1440).contains($0.minutes) && (1...10).contains($0.effort) && ($0.distance.map { $0.isFinite && $0 > 0 && $0 <= 1000 } ?? true) })
        else { throw CocoaError(.fileReadCorruptFile) }
        return incoming
    }
    private func validDay(_ key: String) -> Bool {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        guard let date = formatter.date(from: key) else { return false }
        return formatter.string(from: date) == key
    }
    // Merge only missing entries: no destructive overwrite of existing days or IDs.
    @discardableResult func merge(_ incoming: V4PersonalData) -> Bool {
        var candidate = data
        for (day, entry) in incoming.diary where candidate.diary[day] == nil { candidate.diary[day] = entry }
        var ids = Set(candidate.workouts.map(\.id))
        for workout in incoming.workouts where ids.insert(workout.id).inserted { candidate.workouts.append(workout) }
        return commit(candidate)
    }
}

@MainActor struct V4DiaryEditor: View {
    let day: String
    @ObservedObject var store: V4JournalStore
    @State private var mood: String
    @State private var habits: Set<String>
    @State private var weight: String
    @State private var notes: String
    @State private var message: String?
    @FocusState private var focused: Bool
    static let choices = ["Muy bien", "Bien", "Normal", "Cansado", "Muy cansado"]
    static let tags = ["Alcohol", "Cafeína por la tarde", "Cena tardía", "Entrenamiento", "Magnesio", "Siesta", "Estrés elevado", "Molestias musculares", "Viaje", "Enfermedad"]
    init(day: String, store: V4JournalStore) {
        self.day = day
        self.store = store
        let e = store.entry(day)
        _mood = State(initialValue: e.mood)
        _habits = State(initialValue: Set(e.habits))
        _weight = State(initialValue: e.weight.map { String(format: "%.1f", $0) } ?? "")
        _notes = State(initialValue: e.notes)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 12) {
                Text("¿Cómo te encuentras?").font(.headline)
                Picker("Sensaciones", selection: $mood) {
                    Text("Sin registrar").tag("")
                    ForEach(Self.choices, id: \.self) { Text($0).tag($0) }
                }.tint(Obs.ink)
                Divider()
                Text("Hábitos del día").font(.headline)
                ForEach(Self.tags, id: \.self) { tag in
                    Toggle(tag, isOn: Binding(get: { habits.contains(tag) }, set: { on in
                        if on { habits.insert(tag) } else { habits.remove(tag) }
                        message = nil
                    })).tint(Obs.good)
                }
            }.v4Card()
            VStack(alignment: .leading, spacing: 12) {
                Text("Peso y notas").font(.headline)
                HStack {
                    Text("Peso (kg)")
                    Spacer()
                    TextField("Opcional", text: $weight).keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing).focused($focused)
                }
                Divider()
                TextField("Notas personales", text: $notes, axis: .vertical)
                    .lineLimit(3...6).focused($focused)
                Text("Registro manual. El peso no se modifica automáticamente en el perfil del anillo.")
                    .font(.caption).foregroundStyle(Obs.muted)
            }.v4Card()
            Button { save() } label: {
                Label("Guardar día", systemImage: "checkmark").frame(maxWidth: .infinity).padding(.vertical, 8)
            }.buttonStyle(.borderedProminent).tint(Obs.good)
            if let message { Text(message).font(.footnote).foregroundStyle(Obs.ink2) }
            if let error = store.error { Text(error).font(.footnote).foregroundStyle(Obs.alert) }
            Text("Los cambios se guardan al pulsar Guardar día. Haz una copia de tus registros desde Ajustes.")
                .font(.caption).foregroundStyle(Obs.muted)
        }
    }
    private func save() {
        focused = false
        let value = weight.trimmingCharacters(in: .whitespacesAndNewlines)
        let kg = Double(value.replacingOccurrences(of: ",", with: "."))
        if !value.isEmpty && (kg == nil || !(kg!.isFinite && kg! > 0 && kg! <= 500)) {
            message = "Introduce un peso válido en kg o deja el campo vacío."
            return
        }
        let entry = V4DiaryEntry(mood: mood, habits: habits.sorted(), weight: kg, notes: notes)
        message = store.save(entry, day: day) ? "Día guardado." : "No se ha guardado el día."
    }
}

@MainActor struct V4WorkoutEditor: View {
    let day: String
    @ObservedObject var store: V4JournalStore
    @Environment(\.dismiss) private var dismiss
    @State private var sport = "Running"
    @State private var minutes = 30
    @State private var effort = 5
    @State private var distance = ""
    @State private var notes = ""
    @State private var message: String?
    private let sports = ["Running", "Caminar", "Gimnasio", "Pádel", "Ciclismo", "Natación", "Senderismo", "Otro"]
    var body: some View {
        NavigationStack {
            Form {
                Section("Entrenamiento") {
                    Picker("Deporte", selection: $sport) { ForEach(sports, id: \.self) { Text($0) } }
                    Stepper("Duración: \(minutes) min", value: $minutes, in: 1...1440)
                    Stepper("Esfuerzo: \(effort)/10", value: $effort, in: 1...10)
                    Text("1 = muy suave; 10 = máximo esfuerzo percibido.").font(.caption)
                    TextField("Distancia en km (opcional)", text: $distance).keyboardType(.decimalPad)
                    TextField("Notas (opcional)", text: $notes, axis: .vertical)
                }
                Section("Carga percibida") {
                    Text("\(minutes * effort) unidades")
                    Text("Duración × esfuerzo percibido. No es una medición cardiovascular del anillo.").font(.footnote)
                }
                if let message { Text(message).foregroundStyle(Obs.alert) }
                if let error = store.error { Text(error).foregroundStyle(Obs.alert) }
            }
            .navigationTitle("Añadir entrenamiento")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Guardar") { save() } }
            }
        }
    }
    private func save() {
        let input = distance.trimmingCharacters(in: .whitespacesAndNewlines)
        let km = Double(input.replacingOccurrences(of: ",", with: "."))
        if !input.isEmpty && (km == nil || !(km!.isFinite && km! > 0 && km! <= 1000)) {
            message = "Introduce una distancia válida o déjala vacía."
            return
        }
        if store.save(V4Workout(day: day, sport: sport, minutes: minutes, effort: effort, distance: km, notes: notes)) { dismiss() }
    }
}
