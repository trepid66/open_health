import SwiftUI
import Foundation
import UniformTypeIdentifiers
import UIKit

// A warm, adaptive, card-based layout. All values are tied to the selected day;
// missing samples are blank, never silently replaced by zero or today's values.
enum V4Tab: String, CaseIterable {
    case dashboard = "Dashboard", sleep = "Sueño", health = "Salud", sport = "Deporte", diary = "Diario"
    var symbol: String {
        switch self {
        case .dashboard: return "square.grid.2x2"
        case .sleep: return "moon.fill"
        case .health: return "heart.text.square"
        case .sport: return "figure.run"
        case .diary: return "book"
        }
    }
    var tint: Color {
        switch self {
        case .dashboard, .health: return Obs.good
        case .sleep: return Color(red: 0.39, green: 0.54, blue: 0.76)
        case .sport: return Color(red: 0.73, green: 0.48, blue: 0.16)
        case .diary: return Color(red: 0.57, green: 0.45, blue: 0.76)
        }
    }
}

extension View {
    func v4Card() -> some View {
        self.frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(Color(uiColor: UIColor { traits in
                traits.userInterfaceStyle == .dark ? UIColor(white: 0.12, alpha: 1) : .white
            }), in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Obs.rule, lineWidth: 0.7))
    }
}

enum V4Format {
    static func number(_ value: Double?, decimals: Int = 0, unit: String = "") -> String {
        guard let value, value.isFinite else { return "–" }
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "es_ES")
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = decimals
        formatter.maximumFractionDigits = decimals
        return (formatter.string(from: NSNumber(value: value)) ?? "–") + (unit.isEmpty ? "" : " " + unit)
    }
    static func duration(_ hours: Double?) -> String {
        guard let hours, hours.isFinite, (0...168).contains(hours) else { return "–" }
        let minutes = Int((hours * 60).rounded())
        return "\(minutes / 60) h \(minutes % 60) min"
    }
    static func asleep(_ n: NightRow?) -> Double? {
        guard let n, n.hasHypnogram, n.stagingComplete,
              let m = Sleep.metrics(n.analysisStages, inBedS: n.durationS) else { return nil }
        return m.asleepMin / 60
    }
    static func shortDay(_ key: String) -> String {
        let p = key.split(separator: "-")
        return p.count == 3 ? "\(p[2])/\(p[1])" : key
    }
    static func stamp(_ date: Date?) -> String {
        guard let date else { return "Sin sincronización registrada" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "es_ES")
        f.dateFormat = "dd/MM · HH:mm"
        return f.string(from: date)
    }
    static func minutesActive(_ profile: [Double]?) -> Double? {
        guard let profile, profile.count == 96,
              profile.allSatisfy({ $0.isFinite && $0 >= 0 }) else { return nil }
        return Double(profile.filter { $0 >= 3 }.count * 15)
    }
}

struct V4Metric: View {
    let label: String
    let value: String
    var detail: String? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label).font(.caption).foregroundStyle(Obs.ink2)
            Text(value).font(.system(size: 23, weight: .semibold)).monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.55).foregroundStyle(Obs.ink)
            if let detail { Text(detail).font(.caption2).foregroundStyle(Obs.muted) }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct V4SectionTitle: View {
    let title: String
    let icon: String
    let tint: Color
    var arrow = false
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon).foregroundStyle(tint)
            Text(title).font(.headline).foregroundStyle(Obs.ink)
            Spacer()
            if arrow { Image(systemName: "chevron.right").font(.caption).foregroundStyle(Obs.muted) }
        }
    }
}

// One slot per calendar day: absent data stays absent, and 0 is an actual
// recorded zero. The chart does not connect missing days.
struct V4Bars: View {
    let title: String
    let keys: [String]
    let values: [Double?]
    let tint: Color
    var ceiling: Double? = nil
    var suffix = ""
    private var clean: [Double] { values.compactMap { v in
        guard let v, v.isFinite, v >= 0 else { return nil }; return v
    } }
    var body: some View {
        let upper = max(1, ceiling ?? clean.max() ?? 1)
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(title).font(.subheadline.weight(.medium))
                Spacer()
                Text("\(clean.count)/\(keys.count) días").font(.caption2).foregroundStyle(Obs.muted)
            }
            if clean.isEmpty {
                Text("Todavía no hay registros válidos.").font(.caption).foregroundStyle(Obs.muted)
            } else {
                GeometryReader { geo in
                    HStack(alignment: .bottom, spacing: 1) {
                        ForEach(values.indices, id: \.self) { i in
                            if let value = values[i], value.isFinite, value >= 0 {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(tint.opacity(0.85))
                                    .frame(height: max(2, geo.size.height * CGFloat(min(1, value / upper))))
                                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                            } else {
                                Color.clear.frame(maxWidth: .infinity)
                            }
                        }
                    }
                }.frame(height: 64)
                HStack {
                    Text(V4Format.shortDay(keys.first ?? ""))
                    Spacer()
                    Text("Máx. " + V4Format.number(clean.max(), decimals: suffix == "h" ? 1 : 0, unit: suffix))
                    Spacer()
                    Text(V4Format.shortDay(keys.last ?? ""))
                }.font(.caption2).foregroundStyle(Obs.muted)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

@MainActor struct V4Home: View {
    let summary: Summary
    @ObservedObject var ring: RingSync
    let refreshing: Bool
    let onSync: () -> Void
    let onProfile: () -> Void
    let onHistory: () -> Void
    let onPulse: () -> Void
    let onDebt: () -> Void
    let onVital: (VitalKind) -> Void
    let onRefresh: () async -> Void
    let onBedtimeSaved: () -> Void
    @StateObject private var store = V4JournalStore()
    @State private var tab: V4Tab = .dashboard
    @State private var date = Date()
    @State private var historyDays = 7
    @State private var showWorkout = false
    @State private var showDiagnostics = false
    @State private var showExporter = false
    @State private var backup: V4Backup?
    @State private var showImporter = false
    @State private var pendingBackup: V4PersonalData?
    @State private var confirmImport = false
    @State private var message: String?
    @State private var deleteWorkout: V4Workout?
    @State private var confirmDelete = false
    @AppStorage("personal.goals.steps") private var stepsGoal = 8000
    @AppStorage("personal.goals.activeMinutes") private var activeGoal = 30
    @AppStorage("personal.goals.inBedHours") private var bedGoal = 8.0
    private var day: String { V4Date.key(date) }
    private var today: Bool { Calendar.current.isDateInToday(date) }
    private var night: NightRow? { summary.night(forDay: day) }
    private var activity: DailyStat? { summary.activity_daily[day] }
    private var keys: [String] { V4Date.recent(date, historyDays) }
    private var columns: [GridItem] { [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)] }

    var body: some View {
        VStack(spacing: 0) {
            header
            dateBar
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if summary.error != nil {
                        Text("No se han podido cargar todavía los datos del anillo. Puedes sincronizar desde el botón superior.")
                            .font(.footnote).foregroundStyle(Obs.ink2).v4Card()
                    }
                    if let error = store.error { Text(error).font(.footnote).foregroundStyle(Obs.alert).v4Card() }
                    switch tab {
                    case .dashboard: dashboard
                    case .sleep: sleep
                    case .health: health
                    case .sport: sport
                    case .diary: diary
                    }
                }.padding(16).padding(.bottom, 12)
            }
            .id(tab)
            .refreshable { await onRefresh() }
            Divider()
            tabBar
        }
        .foregroundStyle(Obs.ink)
        .background(Obs.canvas)
        .environment(\.locale, Locale(identifier: "es_ES"))
        .sheet(isPresented: $showWorkout) { V4WorkoutEditor(day: day, store: store) }
        .sheet(isPresented: $showDiagnostics) {
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        ObsStat(label: "Firmware", value: summary.device?.firmware ?? "–")
                        ObsStat(label: "Batería", value: summary.device?.battery_pct.map { "\($0) %" } ?? "–")
                        ObsStat(label: "Última sincronización", value: V4Format.stamp(ring.lastSuccessfulSyncAt))
                        Text("Diagnóstico del último pulso").font(.headline)
                        Text(ring.liveDiagnostics.isEmpty ? "No hay una sesión de pulso registrada." : ring.liveDiagnostics.joined(separator: "\n"))
                            .font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                        if let warnings = summary.clock?.warnings, !warnings.isEmpty {
                            Text("Avisos del reloj del anillo").font(.headline)
                            ForEach(warnings, id: \.self) { Text($0).font(.caption) }
                        }
                        if let error = summary.error { Text(error).font(.caption).textSelection(.enabled) }
                        BuildStamp()
                    }.padding()
                }.navigationTitle("Diagnóstico técnico").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Cerrar") { showDiagnostics = false } } }
            }
        }
        .fileExporter(isPresented: $showExporter, document: backup, contentType: .json, defaultFilename: "OpenOura-diario-\(day)") { result in
            switch result {
            case .success: message = "Copia de diario y entrenamientos exportada."
            case .failure: message = "No se ha podido exportar la copia."
            }
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json]) { result in
            do { pendingBackup = try store.readBackup(result.get()); confirmImport = true }
            catch { message = "El archivo no es una copia válida de diario y entrenamientos." }
        }
        .confirmationDialog("Importar registros personales", isPresented: $confirmImport, titleVisibility: .visible) {
            Button("Añadir registros que falten") {
                if let pendingBackup { message = store.merge(pendingBackup) ? "Registros importados." : "No se han podido importar los registros." }
                pendingBackup = nil
            }
            Button("Cancelar", role: .cancel) { pendingBackup = nil }
        } message: { Text("Se mantienen los días y entrenamientos ya guardados. No se sobrescriben los existentes.") }
        .confirmationDialog("¿Eliminar este entrenamiento?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Eliminar", role: .destructive) { if let deleteWorkout { store.remove(deleteWorkout.id) }; deleteWorkout = nil }
            Button("Cancelar", role: .cancel) { deleteWorkout = nil }
        }
        .alert("Open Oura", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("Aceptar") { message = nil }
        } message: { Text(message ?? "") }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 11) {
                Text("Open Oura").font(Obs.serif(24))
                Text("V4").font(.caption2.weight(.medium)).foregroundStyle(Obs.muted)
                Spacer(minLength: 6)
                if let battery = summary.device?.battery_pct {
                    Image(systemName: battery < 20 ? "battery.25percent" : "battery.100percent")
                        .foregroundStyle(battery < 20 ? Obs.bad : Obs.good)
                    Text("\(battery)%").font(.caption.weight(.medium))
                }
                SyncIndicatorButton(ring: ring, action: onSync)
                Menu {
                    Button(action: onProfile) { Label("Perfil", systemImage: "person.crop.circle") }
                    Button(action: onSync) { Label("Anillo, sincronización y copia de datos", systemImage: "arrow.triangle.2.circlepath") }
                    Button(action: onHistory) { Label("Historial del anillo", systemImage: "calendar") }
                    Button { exportBackup() } label: { Label("Exportar diario y entrenamientos", systemImage: "square.and.arrow.up") }
                    Button { showImporter = true } label: { Label("Importar diario y entrenamientos", systemImage: "square.and.arrow.down") }
                    Button { showDiagnostics = true } label: { Label("Diagnóstico técnico", systemImage: "wrench.and.screwdriver") }
                } label: {
                    Image(systemName: "gearshape").font(.title3).foregroundStyle(Obs.ink2)
                        .frame(minWidth: 36, minHeight: 36)
                }.accessibilityLabel("Ajustes")
            }
            HStack(spacing: 5) {
                if ring.busy || refreshing { ProgressView().controlSize(.mini) }
                Text(ring.liveActive ? "Midiendo pulso…" : ring.busy ? "Sincronizando…" : refreshing ? "Actualizando datos…" : "Última sincronización: " + V4Format.stamp(ring.lastSuccessfulSyncAt))
                    .font(.caption2).foregroundStyle(Obs.muted).lineLimit(2)
                Spacer()
            }
        }.padding(.horizontal, 16).padding(.top, 6).padding(.bottom, 8)
    }

    private var dateBar: some View {
        HStack {
            Button { date = V4Date.shifted(date, -1) } label: {
                Image(systemName: "chevron.left").frame(width: 34, height: 36)
            }.accessibilityLabel("Día anterior")
            Spacer(minLength: 4)
            VStack(spacing: 1) {
                Text(today ? "Hoy" : V4Date.title(date)).font(.subheadline.weight(.semibold))
                    .lineLimit(1).minimumScaleFactor(0.75)
                DatePicker("Fecha", selection: $date, in: ...Date(), displayedComponents: .date)
                    .labelsHidden().datePickerStyle(.compact).tint(Obs.good)
            }
            Spacer(minLength: 4)
            Button {
                let next = V4Date.shifted(date, 1)
                date = next > Date() ? Date() : next
            } label: { Image(systemName: "chevron.right").frame(width: 34, height: 36) }
                .disabled(today).accessibilityLabel("Día siguiente")
            if !today { Button("Hoy") { date = Date() }.font(.caption).tint(Obs.good) }
        }.buttonStyle(.plain).padding(.horizontal, 14).padding(.vertical, 4)
    }

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(V4Tab.allCases, id: \.self) { item in
                Button {
                    tab = item
                } label: {
                    VStack(spacing: 5) {
                        Image(systemName: item.symbol).font(.system(size: 20, weight: .medium))
                        Text(item.rawValue).font(.system(size: 10, weight: tab == item ? .semibold : .regular))
                            .lineLimit(1).minimumScaleFactor(0.7)
                    }.frame(maxWidth: .infinity).frame(height: 50)
                        .foregroundStyle(tab == item ? item.tint : Obs.muted)
                }.buttonStyle(.plain).accessibilityAddTraits(tab == item ? .isSelected : [])
            }
        }.padding(.horizontal, 6).padding(.top, 3)
    }

    private var dashboard: some View {
        VStack(alignment: .leading, spacing: 14) {
            PersonalDailyScoresView(summary: summary, day: day)
            Button { tab = .sleep } label: { sleepSummary(arrow: true) }.buttonStyle(.plain)
            Button { tab = .health } label: {
                VStack(alignment: .leading, spacing: 14) {
                    V4SectionTitle(title: "Salud", icon: "heart-pulse", tint: V4Tab.health.tint, arrow: true)
                    vitalGrid
                }.v4Card()
            }.buttonStyle(.plain)
            Button { tab = .sport } label: { activitySummary(arrow: true) }.buttonStyle(.plain)
            Button { tab = .diary } label: {
                VStack(alignment: .leading, spacing: 10) {
                    V4SectionTitle(title: "Diario", icon: "book", tint: V4Tab.diary.tint, arrow: true)
                    let entry = store.entry(day)
                    Text(entry.isEmpty ? "Registra tus hábitos y cómo te encuentras." : ([entry.mood.isEmpty ? nil : entry.mood, entry.weight.map { V4Format.number($0, decimals: 1, unit: "kg") }, entry.habits.isEmpty ? nil : "\(entry.habits.count) hábitos"].compactMap { $0 }).joined(separator: " · "))
                        .font(.subheadline).foregroundStyle(Obs.ink2)
                }.v4Card()
            }.buttonStyle(.plain)
            historyPicker
            scoreHistory
        }
    }

    private func sleepSummary(arrow: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            V4SectionTitle(title: "Última noche del día", icon: "moon.fill", tint: V4Tab.sleep.tint, arrow: arrow)
            if let n = night {
                let asleep = V4Format.asleep(n)
                Text(V4Format.duration(asleep ?? n.in_bed_h)).font(.system(size: 30, weight: .semibold)).foregroundStyle(Obs.ink)
                Text((asleep == nil ? "Tiempo en cama · " : "Tiempo dormido · ") + (n.start ?? "–") + " – " + (n.end ?? "–"))
                    .font(.caption).foregroundStyle(Obs.muted)
                if let st = n.hypnogram, !st.isEmpty {
                    Canvas { ctx, size in
                        let stride = max(1, st.count / 240)
                        let sample = Array(st.enumerated().filter { $0.offset % stride == 0 }.map { $0.element })
                        let width = size.width / CGFloat(max(1, sample.count))
                        for (i, stage) in sample.enumerated() {
                            let row = (1...4).contains(stage) ? stage - 1 : 4
                            let rect = CGRect(x: CGFloat(i) * width, y: CGFloat(row) * size.height / 5,
                                              width: max(0.8, width), height: size.height / 5 - 1)
                            ctx.fill(Path(rect), with: .color(stage == 0 || !(1...4).contains(stage) ? Obs.rule : Obs.stage(stage)))
                        }
                    }.frame(height: 40)
                    Text(n.stagingComplete ? "Profundo · ligero · REM · despierto" : "Fases parciales · gris = sin datos").font(.caption2).foregroundStyle(Obs.muted)
                } else {
                    Text("Fases aún no disponibles. Se conservan las señales nocturnas.").font(.caption).foregroundStyle(Obs.muted)
                }
            } else {
                Text("Sin sueño registrado en esta fecha.").font(.subheadline).foregroundStyle(Obs.muted)
            }
        }.v4Card()
    }

    private var vitalGrid: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
            V4Metric(label: "Pulso nocturno mínimo", value: V4Format.number(night?.rhr, unit: "ppm"))
            V4Metric(label: "HRV nocturna", value: V4Format.number(night?.hrv_ms, unit: "ms"))
            V4Metric(label: "Oxígeno en sangre", value: V4Format.number(night?.spo2_mean, unit: "%"))
            V4Metric(label: "Temperatura cutánea", value: V4Format.number(night?.skin_temp, decimals: 1, unit: "°C"))
            V4Metric(label: "Frecuencia respiratoria", value: V4Format.number(night?.breath_rate, decimals: 1, unit: "rpm"))
        }
    }

    private func activitySummary(arrow: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            V4SectionTitle(title: "Actividad diaria", icon: "figure.walk", tint: V4Tab.sport.tint, arrow: arrow)
            HStack(alignment: .firstTextBaseline) {
                Text(V4Format.number(activity?.steps)).font(.system(size: 28, weight: .semibold)).foregroundStyle(Obs.ink)
                Text("de \(stepsGoal) pasos").font(.caption).foregroundStyle(Obs.muted)
            }
            if let steps = activity?.steps, steps.isFinite, steps >= 0 {
                ProgressView(value: min(1, steps / Double(max(1, stepsGoal)))).tint(V4Tab.sport.tint)
            }
            LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
                V4Metric(label: "Calorías activas", value: V4Format.number(activity?.active_kcal, unit: "kcal"))
                V4Metric(label: "Distancia estimada", value: V4Format.number(activity?.distance_m.map { $0 / 1000 }, decimals: 1, unit: "km"))
            }
            let workouts = store.workouts(day)
            if !workouts.isEmpty { Text("\(workouts.count) entrenamientos · \(workouts.reduce(0) { $0 + $1.minutes }) min registrados").font(.caption).foregroundStyle(Obs.ink2) }
        }.v4Card()
    }

    private var historyPicker: some View {
        HStack {
            Text("Evolución").font(.headline)
            Spacer()
            Picker("Periodo", selection: $historyDays) {
                Text("7 d").tag(7); Text("30 d").tag(30); Text("90 d").tag(90)
            }.pickerStyle(.segmented).frame(maxWidth: 190)
        }
    }

    private var scoreHistory: some View {
        VStack(alignment: .leading, spacing: 15) {
            V4Bars(title: "Sueño · calidad", keys: keys, values: keys.map { key in
                let n = summary.night(forDay: key)
                return n?.stagingComplete == true && n?.hasHypnogram == true ? n?.sleep_score?.score : nil
            }, tint: V4Tab.sleep.tint, ceiling: 100)
            V4Bars(title: "Recuperación", keys: keys, values: keys.map { PersonalDailyScores.recovery(summary, day: $0).value.map(Double.init) }, tint: V4Tab.health.tint, ceiling: 100)
            V4Bars(title: "Actividad", keys: keys, values: keys.map { PersonalDailyScores.activity(summary, day: $0, stepsGoal: stepsGoal, activeGoal: activeGoal).value.map(Double.init) }, tint: V4Tab.sport.tint, ceiling: 100)
            Text("Índices propios. El historial de actividad usa los objetivos actuales; no se mezcla el tiempo en cama con la puntuación de calidad del sueño.")
                .font(.caption2).foregroundStyle(Obs.muted)
        }.v4Card()
    }

    private var sleep: some View {
        VStack(alignment: .leading, spacing: 16) {
            sleepSummary(arrow: false)
            if let n = night {
                VStack(alignment: .leading, spacing: 12) {
                    V4SectionTitle(title: "Análisis de la noche", icon: "waveform.path.ecg", tint: V4Tab.sleep.tint)
                    Text(n.hasHypnogram ? (n.staging_source == "ring" ? "Fases calculadas por el anillo." : "Fases estimadas por el motor disponible.") : "Sin clasificación de fases. No se puede determinar el tiempo dormido real, la eficiencia ni los despertares.")
                        .font(.caption).foregroundStyle(Obs.muted)
                    if let coverage = n.staging_coverage_pct { ObsStat(label: "Cobertura de fases", value: V4Format.number(coverage, decimals: 1, unit: "%")) }
                    SleepReport(s: summary, day: day, onBedtimeSaved: onBedtimeSaved)
                }.v4Card()
                VStack(alignment: .leading, spacing: 12) {
                    V4SectionTitle(title: "Constantes nocturnas", icon: "heart.text.square", tint: V4Tab.health.tint)
                    vitalGrid
                }.v4Card()
                let otherNights = summary.nights.filter { summary.wakeYmd($0) == day && $0.stagingKey != n.stagingKey }
                if !otherNights.isEmpty {
                    VStack(alignment: .leading, spacing: 9) {
                        Text("Otros periodos de descanso").font(.headline)
                        ForEach(otherNights, id: \.stagingKey) { other in
                            ObsStat(label: (other.start ?? "–") + " – " + (other.end ?? "–"), value: V4Format.duration(other.in_bed_h))
                        }
                    }.v4Card()
                }
            }
            if let debt = summary.sleepDebt {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Deuda de sueño · último periodo analizado").font(.caption).foregroundStyle(Obs.muted)
                    SleepDebtCard(debt: debt, action: onDebt)
                }.v4Card()
            }
            historyPicker
            VStack(alignment: .leading, spacing: 14) {
                V4Bars(title: "Tiempo en cama", keys: keys, values: keys.map { summary.night(forDay: $0)?.in_bed_h }, tint: V4Tab.sleep.tint, suffix: "h")
                V4Bars(title: "Tiempo dormido", keys: keys, values: keys.map { V4Format.asleep(summary.night(forDay: $0)) }, tint: Obs.good, suffix: "h")
                let bedtimes = keys.compactMap { summary.night(forDay: $0)?.start }.compactMap { hm -> Int? in
                    let p = hm.split(separator: ":").compactMap { Int($0) }
                    guard p.count >= 2, (0...23).contains(p[0]), (0...59).contains(p[1]) else { return nil }
                    let minutes = p[0] * 60 + p[1]
                    return minutes < 720 ? minutes + 1440 : minutes
                }
                if bedtimes.count >= 3, let low = bedtimes.min(), let high = bedtimes.max() {
                    ObsStat(label: "Variación de hora de acostarse", value: "\(high - low) min")
                    Text("Diferencia entre la hora más temprana y tardía de las noches registradas (eje desde mediodía).").font(.caption2).foregroundStyle(Obs.muted)
                }
            }.v4Card()
        }.id(day)
    }

    private var health: some View {
        VStack(alignment: .leading, spacing: 16) {
            Button(action: onPulse) {
                VStack(alignment: .leading, spacing: 8) {
                    V4SectionTitle(title: "Medir pulso en directo", icon: "heart.fill", tint: Obs.alert, arrow: true)
                    Text("Medición de 60 segundos con el Ring 4.").font(.caption).foregroundStyle(Obs.muted)
                }.v4Card()
            }.buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 13) {
                V4SectionTitle(title: "Signos vitales de la noche", icon: "heart.text.square", tint: V4Tab.health.tint)
                vitalGrid
                if let hr = summary.vitals.hr, hr.date == day {
                    Divider()
                    V4Metric(label: "Última frecuencia registrada de ese día", value: V4Format.number(hr.latest, unit: "ppm"), detail: hr.hm)
                }
                Text("Las mediciones nocturnas corresponden a la fecha de despertar seleccionada.").font(.caption2).foregroundStyle(Obs.muted)
            }.v4Card()
            VStack(alignment: .leading, spacing: 12) {
                V4SectionTitle(title: "Rangos personales", icon: "chart.line.uptrend.xyaxis", tint: V4Tab.health.tint)
                rangeRow("Pulso nocturno mínimo", unit: "ppm", current: night?.rhr, pick: { $0.rhr })
                rangeRow("HRV nocturna", unit: "ms", current: night?.hrv_ms, pick: { $0.hrv_ms })
                rangeRow("Oxígeno en sangre", unit: "%", current: night?.spo2_mean, pick: { $0.spo2_mean })
                rangeRow("Temperatura cutánea", unit: "°C", current: night?.skin_temp, decimals: 1, pick: { $0.skin_temp })
                rangeRow("Frecuencia respiratoria", unit: "rpm", current: night?.breath_rate, decimals: 1, pick: { $0.breath_rate })
                Text("Intervalo descriptivo mínimo–máximo de hasta 28 noches previas, con al menos 7 válidas por variable. No es un rango clínico ni un diagnóstico.").font(.caption2).foregroundStyle(Obs.muted)
            }.v4Card()
            VStack(alignment: .leading, spacing: 9) {
                Text("Histórico de constantes").font(.headline)
                ForEach(VitalKind.allCases) { kind in
                    Button { onVital(kind) } label: {
                        HStack {
                            Text(vitalTitle(kind)).foregroundStyle(Obs.ink)
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(Obs.muted)
                        }.padding(.vertical, 7)
                    }.buttonStyle(.plain)
                }
                Text("Los informes históricos muestran su propio periodo de referencia.").font(.caption2).foregroundStyle(Obs.muted)
            }.v4Card()
            if let vo = summary.fitness?.vo2max {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Capacidad cardiovascular · última estimación").font(.headline)
                    V4Metric(label: "VO₂ máx. estimado", value: V4Format.number(vo, decimals: 1, unit: "ml/kg/min"))
                    Text("Estimación del proyecto basada en el perfil y los datos disponibles; no es una prueba de esfuerzo.").font(.caption).foregroundStyle(Obs.muted)
                }.v4Card()
            }
        }
    }

    private func vitalTitle(_ kind: VitalKind) -> String {
        switch kind {
        case .hrv: return "Variabilidad cardíaca (HRV)"
        case .heartRate: return "Frecuencia cardíaca"
        case .temp: return "Temperatura cutánea"
        case .oxygen: return "Oxígeno en sangre"
        }
    }

    private func rangeRow(_ name: String, unit: String, current: Double?, decimals: Int = 0,
                          pick: (NightRow) -> Double?) -> some View {
        let previous = Array(summary.nightlySeries(pick).filter { $0.date < day }.suffix(28)).map(\.value)
        let lo = previous.min()
        let hi = previous.max()
        let hasRange = previous.count >= 7 && lo != nil && hi != nil
        return VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(name).font(.subheadline)
                Spacer()
                Text(V4Format.number(current, decimals: decimals, unit: unit)).font(.subheadline.weight(.semibold))
            }
            if hasRange, let lo, let hi {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Obs.rule)
                        Capsule().fill(Obs.good.opacity(0.38)).padding(.horizontal, geo.size.width * 0.12)
                        if let current, current.isFinite {
                            let fraction = hi == lo ? (current == lo ? 0.5 : current < lo ? 0.03 : 0.97) : min(0.97, max(0.03, 0.12 + 0.76 * (current - lo) / (hi - lo)))
                            Circle().fill(Obs.ink).frame(width: 10, height: 10)
                                .offset(x: max(0, geo.size.width * CGFloat(fraction) - 5))
                        }
                    }
                }.frame(height: 8)
                Text("Referencia: \(V4Format.number(lo, decimals: decimals)) – \(V4Format.number(hi, decimals: decimals)) \(unit) · \(previous.count) noches")
                    .font(.caption2).foregroundStyle(Obs.muted)
            } else {
                Text("Creando referencia: \(previous.count)/7 noches válidas").font(.caption2).foregroundStyle(Obs.muted)
            }
        }
    }

    private var sport: some View {
        VStack(alignment: .leading, spacing: 16) {
            activitySummary(arrow: false)
            VStack(alignment: .leading, spacing: 14) {
                V4SectionTitle(title: "Actividad del anillo", icon: "chart.bar", tint: V4Tab.sport.tint)
                if activity != nil || summary.activity_profile[day] != nil {
                    ActivityReport(s: summary, day: day)
                } else {
                    Text("No hay datos de actividad en esta fecha.").font(.caption).foregroundStyle(Obs.muted)
                }
            }.v4Card()
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Entrenamientos manuales").font(.headline)
                    Spacer()
                    Button { showWorkout = true } label: { Label("Añadir", systemImage: "plus.circle") }.tint(Obs.good)
                }
                let sessions = store.workouts(day)
                if sessions.isEmpty { Text("No has registrado entrenamientos en este día.").font(.caption).foregroundStyle(Obs.muted) }
                ForEach(sessions) { workout in
                    HStack {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(workout.sport).font(.subheadline.weight(.semibold))
                            Text("\(workout.minutes) min · esfuerzo \(workout.effort)/10 · carga \(workout.load)").font(.caption).foregroundStyle(Obs.ink2)
                            if let distance = workout.distance { Text(V4Format.number(distance, decimals: 1, unit: "km")).font(.caption) }
                            if !workout.notes.isEmpty { Text(workout.notes).font(.caption).foregroundStyle(Obs.ink2) }
                        }
                        Spacer()
                        Button { deleteWorkout = workout; confirmDelete = true } label: {
                            Image(systemName: "trash").foregroundStyle(Obs.alert)
                        }.buttonStyle(.plain).accessibilityLabel("Eliminar entrenamiento")
                    }
                }
                let week = Set(V4Date.recent(date, 7))
                let lastSeven = store.data.workouts.filter { week.contains($0.day) }
                Divider()
                ObsStat(label: "Entrenamientos · últimos 7 días", value: "\(lastSeven.count)")
                ObsStat(label: "Minutos registrados", value: "\(lastSeven.reduce(0) { $0 + $1.minutes })")
                ObsStat(label: "Carga percibida", value: "\(lastSeven.reduce(0) { $0 + $1.load })")
                Text("Carga = minutos × esfuerzo percibido. No se suma a las calorías ni a los pasos del anillo.").font(.caption2).foregroundStyle(Obs.muted)
            }.v4Card()
            historyPicker
            VStack(alignment: .leading, spacing: 14) {
                V4Bars(title: "Pasos diarios", keys: keys, values: keys.map { summary.activity_daily[$0]?.steps }, tint: V4Tab.sport.tint)
                V4Bars(title: "Carga de entrenamientos registrados", keys: keys, values: keys.map { key in
                    let sessions = store.workouts(key)
                    return sessions.isEmpty ? nil : Double(sessions.reduce(0) { $0 + $1.load })
                }, tint: V4Tab.sport.tint)
            }.v4Card()
        }
    }

    private var diary: some View {
        VStack(alignment: .leading, spacing: 16) {
            V4DiaryEditor(day: day, store: store).id(day)
            historyPicker
            VStack(alignment: .leading, spacing: 10) {
                Text("Evolución del peso registrado").font(.headline)
                V4Bars(title: "Peso", keys: keys, values: keys.map { store.entry($0).weight }, tint: V4Tab.diary.tint, suffix: "kg")
                let recent = V4Date.recent(date, 7).compactMap { store.entry($0).weight }
                if !recent.isEmpty { ObsStat(label: "Media de los últimos 7 días", value: V4Format.number(recent.reduce(0, +) / Double(recent.count), decimals: 1, unit: "kg")) }
                Text("Se calcula solo con los días que tienen peso registrado.").font(.caption2).foregroundStyle(Obs.muted)
            }.v4Card()
        }
    }

    private func exportBackup() {
        do { backup = V4Backup(bytes: try store.encoded()); showExporter = true }
        catch { message = "No se ha podido preparar la copia de registros personales." }
    }
}
