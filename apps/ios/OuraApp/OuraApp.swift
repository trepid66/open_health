import SwiftUI
import UniformTypeIdentifiers

// The SwiftUI screens for OuraApp. Data types live in Models.swift, the model/FFI
// orchestration in Core.swift, the reusable charts/cells in Components.swift, and the
// full-page sleep/activity reports in Reports.swift.
// SIBLING CLIENT: the web dashboard (dashboard/web/app.js) renders the SAME summary
// JSON — a user-facing change here usually belongs there too (docs/clients-web-and-ios.md).

// The home's unified "hoy": last night's sleep and that day's activity as ONE unit,
// each region tappable to open its own detail (sleep → SleepDetail, activity →
// ActivityDetail). Mirrors the web dashboard's day card. Previous days live behind
// "show all days" (AllDaysView → DayDetailView, which shows the same pairing).
struct TodayCard: View {
    let s: Summary
    let day: String
    let onSleep: () -> Void
    let onActivity: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // night — tap for the hypnogram + breakdown + that night's vitals
            if let n = s.night(forDay: day) {
                Button(action: onSleep) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            ObsTag("sueño", icon: "moon.fill")
                            Spacer()
                            Text(n.in_bed_h.map { String(format: "%.1fh", $0) } ?? "–")
                                .font(Obs.mono(11)).foregroundStyle(Obs.ink2)
                            Image(systemName: "chevron.right").font(.system(size: 11)).foregroundStyle(Obs.trace)
                        }
                        Text("\(n.start ?? "–") → \(n.end ?? "–")")
                            .font(Obs.mono(12)).foregroundStyle(Obs.ink2)
                        if n.hasHypnogram { Hypnogram(stages: n.hypnogram!, height: 28) }
                        else if let e = n.efficiency {
                            Text("Eficiencia \(Int(e))%").font(Obs.mono(12))
                                .foregroundStyle(e >= 85 ? Obs.good : (e < 75 ? Obs.bad : Obs.ink2))
                        }
                    }
                    .contentShape(Rectangle())
                }.buttonStyle(.plain)

                Rectangle().fill(Obs.trace.opacity(0.4)).frame(height: 0.5)
                    .padding(.vertical, 16)
            }

            // activity — tap for the movement ridge + steps/kcal + this day's workouts
            Button(action: onActivity) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        ObsTag("actividad", icon: "figure.walk")
                        Spacer()
                        if let st = s.activity_daily[day] {
                            Text("\(Int(st.steps ?? 0)) pasos").font(Obs.mono(11)).foregroundStyle(Obs.ink2)
                            Text("· \(Int(st.active_kcal ?? 0)) kcal").font(Obs.mono(11)).foregroundStyle(Obs.ink2)
                        }
                        Image(systemName: "chevron.right").font(.system(size: 11)).foregroundStyle(Obs.trace)
                    }
                    MovementRidge(profile: s.activity_profile[day] ?? [])
                    ForEach(Array(s.workoutsOn(day).prefix(2))) { w in
                        SessionRow(label: w.label, durationMin: w.durationMin, startHM: w.startHM)
                    }
                }
                .contentShape(Rectangle())
            }.buttonStyle(.plain)
        }
        .obsCard()
    }
}

// "show all days" → a page listing every day; tap one for its full report.
struct AllDaysView: View {
    let s: Summary
    @Environment(\.dayAnalysis) private var analysis
    @Environment(\.dismiss) private var dismiss

    private static let ymd: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"; return f
    }()
    private static let month: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "MMMM yyyy"; return f
    }()
    private static let weekday: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "EEE"; return f
    }()
    private static let number: NumberFormatter = { let f = NumberFormatter(); f.numberStyle = .decimal; return f }()

    /// Days grouped by month, newest first, keeping the summary's own order.
    private func groups(_ days: [String]) -> [(title: String, days: [String])] {
        var out: [(String, [String])] = []
        for day in days {
            let title = Self.ymd.date(from: day).map { Self.month.string(from: $0) } ?? "undated"
            if let last = out.last, last.0 == title { out[out.count - 1].1.append(day) }
            else { out.append((title, [day])) }
        }
        return out.map { (title: $0.0, days: $0.1) }
    }

    var body: some View {
        let s = analysis?.summary ?? s
        NavigationStack {
            ZStack {
                Obs.canvas.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(groups(s.days), id: \.title) { group in
                            Text(group.title.uppercased()).font(Obs.mono(10, .medium)).tracking(1.4)
                                .foregroundStyle(Obs.muted)
                                .padding(.top, 22).padding(.bottom, 8)
                            ForEach(group.days, id: \.self) { day in
                                NavigationLink { DayReportView(s: s, day: day, tab: .sleep) } label: { row(s, day) }
                                    .buttonStyle(.plain)
                                if day != group.days.last { Rectangle().fill(Obs.rule).frame(height: 1) }
                            }
                        }
                    }
                    .padding(.horizontal, 24).padding(.bottom, 24)
                }
            }
            .navigationTitle("Historial")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Listo") { dismiss() } } }
        }
    }

    @ViewBuilder private func row(_ s: Summary, _ day: String) -> some View {
        let date = Self.ymd.date(from: day)
        let night = s.night(forDay: day)
        let stat = s.activity_daily[day]
        HStack(spacing: 12) {
            // weekday over day-of-month, a fixed column so the rows line up
            VStack(alignment: .leading, spacing: 1) {
                Text(date.map { Self.weekday.string(from: $0).lowercased() } ?? "")
                    .font(Obs.mono(9)).tracking(0.8).foregroundStyle(Obs.muted)
                Text(String(day.suffix(2))).font(Obs.mono(17, .medium)).foregroundStyle(Obs.ink).monospacedDigit()
            }
            .frame(width: 36, alignment: .leading)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(night?.in_bed_h.map { String(format: "%.1fh", $0) } ?? "–")
                        .font(Obs.mono(12, .medium)).foregroundStyle(night == nil ? Obs.muted : Obs.ink)
                    if let st = stat, let steps = st.steps {
                        Text("·").foregroundStyle(Obs.trace)
                        Text("\(Self.number.string(from: NSNumber(value: Int(steps))) ?? "0") pasos")
                            .font(Obs.mono(12)).foregroundStyle(Obs.ink2)
                    }
                    if let st = stat, let kcal = st.active_kcal, kcal > 0 {
                        Text("·").foregroundStyle(Obs.trace)
                        Text("\(Int(kcal)) kcal").font(Obs.mono(12)).foregroundStyle(Obs.ink2)
                    }
                }
                if let n = night, n.hasHypnogram {
                    Hypnogram(stages: n.hypnogram!, height: 12)
                } else if let n = night, let start = n.start, let end = n.end {
                    Text("\(start) → \(end)").font(Obs.mono(10)).foregroundStyle(Obs.muted)
                }
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.right").font(.system(size: 11)).foregroundStyle(Obs.trace)
        }
        .padding(.vertical, 11)
        .contentShape(Rectangle())
    }
}

// Pair + sync from a real ring: paste the auth key (exported on the desktop), connect
// over BLE, drain history into the writable DB. BLE only works on a physical device.
struct SyncView: View {
    @ObservedObject var ring: RingSync
    let onSynced: (SyncReport) -> Void
    let onReset: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var key = Keychain.loadKey() ?? ""
    @ObservedObject private var diag = RingDiag.shared
    @ObservedObject private var store = DiagStore.shared
    @State private var diagnosticFile: URL?
    @State private var showKey = false
    @State private var clockReport: String?
    @State private var confirmReset = false
    @State private var confirmWipeRing = false
    @State private var showRestorePicker = false
    @State private var restoreNote: String?
    @FocusState private var keyFocused: Bool

    /// Validate the chosen file before it replaces anything: a truncated download or
    /// the wrong file entirely must not destroy a working database.
    private func restore(from result: Result<[URL], Error>) -> String {
        guard case .success(let urls) = result, let picked = urls.first else { return "Restore cancelled." }
        let scoped = picked.startAccessingSecurityScopedResource()
        defer { if scoped { picked.stopAccessingSecurityScopedResource() } }
        let staging = FileManager.default.temporaryDirectory
            .appendingPathComponent("restore-candidate.db")
        do {
            try? FileManager.default.removeItem(at: staging)
            try FileManager.default.copyItem(at: picked, to: staging)
        } catch { return "Could not read that file: \(error.localizedDescription)" }

        do {
            let verdict = try databaseIntegrity(dbPath: staging.path)
            guard verdict.lowercased().contains("ok") else {
                return "That file is not a healthy database (\(verdict)). Nothing changed."
            }
        } catch { return "That file is not an Open Oura backup. Nothing changed." }

        do {
            try DB.resetWritableStore()
            try FileManager.default.copyItem(at: staging, to: DB.url)
            try? FileManager.default.removeItem(at: staging)
        } catch { return "Restore failed midway: \(error.localizedDescription)" }
        return "Restored. The next sync continues from where the backup left off."
    }

    private var validKey: Bool {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.utf8.count == 32 && trimmed.utf8.allSatisfy {
            (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    if ring.connectionIssue != nil { syncStatus }
                    else { preparation }
                    if !ring.busy { pairingKey }
                    connection
                    support
                    BuildStamp()
                }
                .frame(maxWidth: 520)
                .padding(.horizontal, 24)
                .padding(.top, 20)
                .padding(.bottom, 32)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Obs.paper)
            .navigationTitle("Tu anillo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Listo") { dismiss() }
                        .foregroundStyle(Obs.ink)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Listo") { keyFocused = false }
                }
            }
            .alert("¿Borrar los datos locales sincronizados?", isPresented: $confirmReset) {
                Button("Cancelar", role: .cancel) {}
                Button("Borrar datos locales", role: .destructive) {
                    Task { if await ring.resetLocalDatabase() { onReset() } }
                }
            } message: {
                Text("Se borrarán los datos sincronizados de este iPhone. La próxima sincronización descargará el historial que siga disponible en el anillo.")
            }
            .alert("Factory-reset \(ring.knownSerial ?? "the ring")?", isPresented: $confirmWipeRing) {
                Button("Cancelar", role: .cancel) {}
                Button("Borrar el anillo", role: .destructive) {
                    let serial = ring.knownSerial ?? ""
                    let current = key
                    Task {
                        if await ring.factoryReset(keyHex: current, confirmSerial: serial) {
                            key = ""
                            showKey = false
                        }
                    }
                }
            } message: {
                Text("Borra la clave de vinculación, las conexiones Bluetooth, los eventos aún no enviados y el perfil guardado en el anillo. Sincroniza antes para no perder esos eventos. No se puede deshacer; después tendrás que vincular el anillo de nuevo.")
            }
        }
        .tint(Obs.ink)
        // Sync belongs to RingSync and continues when this panel is dismissed.
        .sheet(isPresented: Binding(get: { diagnosticFile != nil }, set: { if !$0 { diagnosticFile = nil } })) {
            if let diagnosticFile { DiagnosticsShare(url: diagnosticFile) }
        }
        .fileImporter(isPresented: $showRestorePicker,
                      allowedContentTypes: [.data],
                      allowsMultipleSelection: false) { result in
            restoreNote = restore(from: result)
            if restoreNote?.hasPrefix("Restored") == true { onReset() }
        }
        .presentationDragIndicator(.visible)
    }

    private var header: some View {
        Text("Vincula tu anillo")
            .font(Obs.serif(28))
            .foregroundStyle(Obs.ink)
    }

    private var preparation: some View {
        VStack(alignment: .leading, spacing: 12) {
            setupRow(icon: "bolt", title: "Coloca el anillo en su cargador, junto al iPhone", detail: nil)
            setupRow(icon: "antenna.radiowaves.left.and.right", title: "Libera la conexión Bluetooth",
                     detail: "Desactiva el Bluetooth en otros teléfonos que estén usando Oura.")
        }
    }

    private func setupRow(icon: String, title: String, detail: String?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(Obs.muted)
                .frame(width: 20)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.medium)).foregroundStyle(Obs.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if let detail {
                    Text(detail).font(.footnote).foregroundStyle(Obs.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var pairingKey: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Group {
                    if showKey { TextField("Pega tu clave de vinculación", text: $key) }
                    else { SecureField("Pega tu clave de vinculación", text: $key) }
                }
                .font(.system(.subheadline, design: .monospaced))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($keyFocused)
                .accessibilityLabel("Clave de vinculación")
                .disabled(ring.busy)
                Button { showKey.toggle() } label: {
                    Image(systemName: showKey ? "eye.slash" : "eye")
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel(showKey ? "Ocultar clave" : "Mostrar clave")
            }
            .foregroundStyle(Obs.ink)
            .padding(.leading, 14)
            .padding(.trailing, 4)
            .padding(.vertical, 4)
            .background(Obs.rule.opacity(0.25), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(keyFocused ? Obs.muted : Obs.rule))
            if !key.isEmpty && !validKey {
                Text("Introduce los 32 caracteres: números 0–9 y letras A–F.")
                    .font(.footnote)
                    .foregroundStyle(Obs.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            pairReset
        }
    }

    /// Adopt a factory-reset ring without a computer: mint the key on this iPhone.
    private var pairReset: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                keyFocused = false
                Task { if let minted = await ring.pair() { key = minted } }
            } label: {
                (Text("¿Sin clave? ").foregroundStyle(Obs.ink2)
                 + Text("Vincular un anillo restablecido de fábrica").foregroundStyle(Obs.ink).underline())
                    .font(.footnote)
            }
            .buttonStyle(.plain)
            .disabled(ring.busy)
            Text("Guarda la nueva clave: no se puede volver a leer del anillo.")
                .font(.footnote)
                .foregroundStyle(Obs.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var syncStatus: some View {
        if ring.busy || !ring.status.isEmpty {
            HStack(alignment: .top, spacing: 12) {
                if ring.busy {
                    ProgressView().tint(Obs.ink).frame(width: 24, height: 24)
                } else {
                    Image(systemName: ring.lastReport != nil ? "checkmark.circle" : "info.circle")
                        .font(.title3)
                        .foregroundStyle(ring.lastReport != nil ? Obs.good : Obs.ink2)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text(ring.busy ? "Sincronizando" : (ring.connectionIssue ?? (ring.lastReport != nil ? "Tu anillo está actualizado" : "Estado de sincronización")))
                        .font(.subheadline.weight(.semibold)).foregroundStyle(Obs.ink)
                    Text(ring.status)
                        .font(.subheadline).foregroundStyle(Obs.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                    if ring.busy {
                        Text("Mantén la app abierta. Si se pierde la conexión, la sincronización se reanuda automáticamente.")
                            .font(.footnote).foregroundStyle(Obs.ink2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(Obs.rule.opacity(0.3), in: RoundedRectangle(cornerRadius: 16))
        }
    }

    private var connection: some View {
        VStack(alignment: .leading, spacing: 16) {
            if ring.connectionIssue == nil { syncStatus }
            if ring.busy {
                Button { ring.pause() } label: {
                    Label("Pausar sincronización", systemImage: "pause")
                        .font(.body.weight(.medium))
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .foregroundStyle(Obs.ink)
                        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Obs.rule))
                }
                .buttonStyle(.plain)
            } else {
                Button {
                    keyFocused = false
                    Task {
                        if let report = await ring.run(keyHex: key) { onSynced(report) }
                    }
                } label: {
                    HStack(spacing: 10) {
                        Text("Conectar y sincronizar")
                        Image(systemName: "arrow.right")
                    }
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 54)
                    .foregroundStyle(validKey ? Obs.paper : Obs.muted)
                    .background(validKey ? Obs.ink : Obs.rule, in: RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
                .disabled(!validKey)
                Text("La primera sincronización puede tardar varios minutos.")
                    .font(.footnote).foregroundStyle(Obs.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // Help & diagnostics: one quiet card of grouped rows instead of nested disclosures.
    // Everyday actions first, the technical transcript one tap deeper, destructive last.
    private var support: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Ayuda y diagnóstico")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(Obs.ink)
                Spacer()
                Text(appVersion).font(Obs.mono(11)).foregroundStyle(Obs.muted)
            }
            VStack(spacing: 0) {
                SupportRow(icon: "arrow.down.doc", title: "Exportar datos",
                           detail: ring.exportStatus ?? "Un archivo con todos los eventos sincronizados",
                           disabled: ring.busy || ring.exportStatus != nil) {
                    Task { if let url = await ring.exportRawDatabase() { diagnosticFile = url } }
                }
                SupportDivider()
                NavigationLink {
                    ResearchExportView()
                } label: {
                    SupportRowLabel(icon: "tablecells", title: "Exportación de investigación",
                                    detail: "Cada latido y movimiento en CSV", trailing: "chevron.right")
                }
                .buttonStyle(.plain)
                SupportDivider()
                SupportRow(icon: "arrow.up.doc", title: "Restaurar copia de seguridad",
                           detail: restoreNote ?? "Sustituye los datos locales de este iPhone",
                           disabled: ring.busy) { showRestorePicker = true }
                SupportDivider()
                NavigationLink {
                    RawDataView()
                } label: {
                    SupportRowLabel(icon: "waveform.path.ecg", title: "Datos brutos y gráficos",
                                    detail: "Todos los eventos enviados por el anillo", trailing: "chevron.right")
                }
                .buttonStyle(.plain)
                SupportDivider()
                NavigationLink {
                    TechnicalReportsView(clockReport: $clockReport,
                                         checkDisabled: ring.busy,
                                         onCheck: { Task { await ring.checkDatabase() } },
                                         onShare: {
                                             Task {
                                                 let url = await Task.detached { DiagStore.shared.exportFile() }.value
                                                 if let url { diagnosticFile = url }
                                             }
                                         })
                } label: {
                    SupportRowLabel(icon: "doc.text.magnifyingglass", title: "Informes técnicos",
                                    detail: technicalSummary, trailing: "chevron.right")
                }
                .buttonStyle(.plain)
            }
            .background(Obs.rule.opacity(0.3), in: RoundedRectangle(cornerRadius: 16))

            VStack(spacing: 0) {
                SupportRow(icon: "trash", title: "Borrar datos locales",
                           detail: "La próxima sincronización recupera los datos disponibles",
                           tint: Obs.alert, disabled: ring.busy) { confirmReset = true }
                SupportDivider()
                SupportRow(icon: "exclamationmark.triangle", title: "Restablecer el anillo de fábrica",
                           detail: ring.knownSerial == nil
                               ? "Disponible tras la primera sincronización"
                               : "Borra el anillo. Deberás vincularlo de nuevo",
                           tint: Obs.alert,
                           disabled: ring.busy || ring.knownSerial == nil || !validKey) { confirmWipeRing = true }
            }
            .background(Obs.alert.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Obs.alert.opacity(0.18)))
        }
    }

    private var appVersion: String {
        // The plain swiftc simulator build ships Info.plist with unexpanded $(…) values.
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? ""
        let build = info?["CFBundleVersion"] as? String ?? ""
        guard !short.isEmpty, !short.contains("$(") else { return "" }
        return build.isEmpty || build.contains("$(") ? "v\(short)" : "v\(short) (\(build))"
    }

    private var technicalSummary: String {
        var parts: [String] = []
        if !store.incidents.isEmpty { parts.append("\(store.incidents.count) incidents") }
        if !store.sessions.isEmpty { parts.append("\(store.sessions.count) sessions") }
        if diag.totalLines > 0 { parts.append("\(diag.totalLines) log lines") }
        return parts.isEmpty ? "Ring clock, incidents and the live log" : parts.joined(separator: " · ")
    }
}

/// One tappable row of the Help & diagnostics card.
private struct SupportRow: View {
    let icon: String
    let title: String
    let detail: String
    var tint: Color = Obs.ink
    var disabled = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            SupportRowLabel(icon: icon, title: title, detail: detail, tint: tint, trailing: nil)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.45 : 1)
    }
}

private struct SupportRowLabel: View {
    let icon: String
    let title: String
    let detail: String
    var tint: Color = Obs.ink
    let trailing: String?
    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(tint == Obs.ink ? Obs.ink2 : tint)
                .frame(width: 32, height: 32)
                .background(Obs.paper.opacity(0.85), in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.subheadline.weight(.medium)).foregroundStyle(tint)
                Text(detail).font(.footnote).foregroundStyle(Obs.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            if let trailing {
                Image(systemName: trailing).font(.system(size: 12, weight: .semibold)).foregroundStyle(Obs.trace)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .frame(minHeight: 56)
        .contentShape(Rectangle())
    }
}

private struct SupportDivider: View {
    var body: some View { Rectangle().fill(Obs.rule).frame(height: 0.6).padding(.leading, 60) }
}

/// The technical transcript on its own page: ring clock anchors, recorded incidents,
/// previous sessions and the live log, each with a copy action.
private struct TechnicalReportsView: View {
    @Binding var clockReport: String?
    var checkDisabled: Bool = false
    var onCheck: () -> Void = {}
    var onShare: () -> Void = {}
    @ObservedObject private var diag = RingDiag.shared
    @ObservedObject private var store = DiagStore.shared
    @State private var copied: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(spacing: 10) {
                    Button { onShare() } label: {
                        Label("Compartir informe", systemImage: "square.and.arrow.up")
                            .font(.subheadline.weight(.medium))
                            .lineLimit(1).minimumScaleFactor(0.85)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Obs.rule))
                    }
                    Button { onCheck() } label: {
                        Label("Comprobar datos", systemImage: "externaldrive")
                            .font(.subheadline.weight(.medium))
                            .lineLimit(1).minimumScaleFactor(0.85)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Obs.rule))
                    }
                    .disabled(checkDisabled)
                }
                .buttonStyle(.plain).foregroundStyle(Obs.ink)
                section("Ring clock", copy: clockReport) {
                    Text(clockReport ?? "No summary rendered yet.")
                        .font(.caption.monospaced()).foregroundStyle(clockReport == nil ? Obs.muted : Obs.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                section("Incidents · \(store.incidents.count)", copy: nil) {
                    if store.incidents.isEmpty {
                        Text("No hay incidencias registradas.").font(.caption).foregroundStyle(Obs.muted)
                    }
                    ForEach(store.incidents.prefix(8)) { item in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(item.title).font(.caption.weight(.medium)).foregroundStyle(Obs.ink)
                                Spacer()
                                Text(item.date, format: .dateTime.month(.abbreviated).day().hour().minute())
                                    .font(.caption2).foregroundStyle(Obs.muted)
                            }
                            Text(item.preview).font(.caption.monospaced()).foregroundStyle(Obs.ink2)
                                .lineLimit(5).frame(maxWidth: .infinity, alignment: .leading)
                            copyButton("incident-\(item.id)", text: item.body)
                        }
                        .padding(10)
                        .background(Obs.paper.opacity(0.6), in: RoundedRectangle(cornerRadius: 10))
                    }
                }
                if !store.sessions.isEmpty {
                    section("Previous sessions · \(store.sessions.count)", copy: nil) {
                        ForEach(store.sessions.prefix(4)) { item in
                            HStack {
                                Text(item.title).font(Obs.mono(11)).foregroundStyle(Obs.ink2)
                                Spacer()
                                copyButton("session-\(item.id)", text: item.body)
                            }
                        }
                    }
                }
                section("Current session · \(diag.totalLines) lines", copy: nil) {
                    HStack {
                        Spacer()
                        Button(copied == "summary" ? "Copied" : "Copy summary") {
                            Task {
                                let text = await Task.detached { DiagStore.shared.exportSummary() }.value
                                UIPasteboard.general.string = text
                                flash("summary")
                            }
                        }
                        .font(.caption.weight(.medium)).foregroundStyle(Obs.ink).frame(minHeight: 32)
                    }
                    if diag.totalLines > 0 {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 2) {
                                ForEach(Array(diag.tail.enumerated()), id: \.offset) { _, line in
                                    Text(line).font(Obs.mono(9)).foregroundStyle(Obs.ink2)
                                        .lineLimit(3).frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                            .padding(8)
                        }
                        .defaultScrollAnchor(.bottom)
                        .frame(maxHeight: 260)
                        .background(Obs.paper.opacity(0.6), in: RoundedRectangle(cornerRadius: 10))
                    } else {
                        Text("Todavía no hay registros.").font(.caption).foregroundStyle(Obs.muted)
                    }
                }
            }
            .frame(maxWidth: 520)
            .padding(.horizontal, 24).padding(.vertical, 20)
            .frame(maxWidth: .infinity)
        }
        .background(Obs.paper)
        .navigationTitle("Informes técnicos")
        .navigationBarTitleDisplayMode(.inline)
        .task { if clockReport == nil { clockReport = await Task.detached { ClockReport.text() }.value } }
    }

    private func section<Content: View>(_ title: String, copy: String?, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(title.uppercased()).font(Obs.mono(10, .medium)).foregroundStyle(Obs.muted).tracking(0.8)
                Spacer()
                if let copy { copyButton(title, text: copy) }
            }
            content()
        }
        .padding(14)
        .background(Obs.rule.opacity(0.3), in: RoundedRectangle(cornerRadius: 16))
    }

    private func copyButton(_ id: String, text: String) -> some View {
        Button(copied == id ? "Copied" : "Copy") {
            UIPasteboard.general.string = text
            flash(id)
        }
        .font(.caption.weight(.medium)).foregroundStyle(Obs.ink).frame(minHeight: 32)
    }

    private func flash(_ id: String) {
        copied = id
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { if copied == id { copied = nil } }
    }
}

/// Human-readable rendering of the shared brain's `clock` block (per-boot ring clock
/// anchors), from the last rendered summary. Shown in Technical reports and appended
/// to the shared diagnostic report so a misdated night can be diagnosed remotely.
enum ClockReport {
    static func text() -> String? {
        guard let clock = SummaryCache.load()?.clock else { return nil }
        let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM-dd HH:mm"; fmt.timeZone = .current
        let day = { (unix: Int64?) -> String in unix.map { fmt.string(from: Date(timeIntervalSince1970: Double($0))) } ?? "–" }
        var lines: [String] = []
        for (i, e) in clock.epochs.enumerated() {
            let sources = (e.anchor_sources ?? []).joined(separator: ",")
            lines.append("boot \(i + 1): ds \(e.min_ds ?? 0)…\(e.max_ds ?? 0) (\(e.span_h ?? 0)h) synced \(day(e.capture_min))…\(day(e.capture_max)) anchors=\(e.anchors ?? 0)\(sources.isEmpty ? "" : " [\(sources)]") latest=\(day(e.latest_anchor_unix))")
        }
        for n in clock.undated_nights {
            lines.append("undated night: ds \(n.start_ds ?? 0)…\(n.end_ds ?? 0) \(n.in_bed_h ?? 0)h captured \(day(n.captured_unix)) (\(n.source ?? "?"))")
        }
        lines.append(contentsOf: clock.warnings.map { "warning: \($0)" })
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }
}

struct DiagnosticsShare: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

/// The top-bar sync affordance doubles as a live status light and the entry point
/// to diagnostics. Motion stays quiet: one slow continuous turn only while BLE is
/// active.
struct SyncIndicatorButton: View {
    @ObservedObject var ring: RingSync
    let action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var rotation = 0.0

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .stroke(Obs.rule, lineWidth: 0.8)
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(ring.busy ? Obs.ink : (ring.wasRecentlySynced ? Obs.good : Obs.ink2))
                    .rotationEffect(.degrees(rotation))
            }
            .frame(width: 31, height: 31)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(ring.busy ? "Sincronización en curso" : "Sincronización y diagnóstico")
        .accessibilityHint("Abre el estado de sincronización, los registros y los controles manuales")
        .onAppear(perform: updateAnimation)
        .onChange(of: ring.busy) { _, _ in updateAnimation() }
        .onChange(of: reduceMotion) { _, _ in updateAnimation() }
    }

    private func updateAnimation() {
        if ring.busy && !reduceMotion {
            rotation = 0
            withAnimation(.linear(duration: 1.6).repeatForever(autoreverses: false)) {
                rotation = 360
            }
        } else {
            withAnimation(.easeOut(duration: 0.2)) { rotation = 0 }
        }
    }
}

// ── root ─────────────────────────────────────────────────────────────────────
struct RootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var s: Summary? = SummaryCache.load()
    @State private var report: ReportSel?
    /// QA hooks for `simctl launch … -openSync` / `-openDay YYYY-MM-DD [activity]`, so
    /// a screen can be captured without driving the UI. Ignored in normal launches.
    private func applyLaunchArguments() {
        let args = CommandLine.arguments
        if args.contains("-openSync") { showSync = true }
        if args.contains("-openAllDays") { showAllDays = true }
        if let index = args.firstIndex(of: "-openDay"), index + 1 < args.count {
            report = ReportSel(day: args[index + 1], sleep: !args.contains("activity"))
        }
    }
    @State private var showAllDays = false
    @State private var showSync = false
    @State private var showProfile = false
    @State private var showLivePulse = false
    @State private var showSleepDebt = false
    @State private var vital: VitalKind?
    @State private var loadGeneration = 0
    @State private var isRefreshingSummary = false
    @State private var automaticSyncRequested = false
    @State private var reloadPending = false
    @StateObject private var ring = RingSync()
    @StateObject private var modelProgress = ModelProgress()
    private func f(_ v: Double?, _ fallback: String = "–") -> String {
        v.map { "\(Int($0))" } ?? fallback
    }
    private func relAge(_ diff: Double) -> String {
        let a = abs((diff * 10).rounded() / 10)
        if diff < -0.05 { return "\(a) yr younger" }
        if diff > 0.05 { return "\(a) yr older" }
        return "acorde a tu edad"
    }
    private func localDay(_ date: Date = Date()) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
    private func displayedDayLabel(_ day: String, now: Date = Date()) -> String {
        if day == localDay(now) { return "hoy" }
        if let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: now),
           day == localDay(yesterday) { return "ayer" }
        return day
    }
    private func latestLabel(date: String?, time: String? = nil) -> String {
        let day = date.map { String($0.suffix(5)) }
        let stamp = [day, time].compactMap { $0 }.joined(separator: " · ")
        return stamp.isEmpty ? "última sincronización" : "última · \(stamp)"
    }
    var body: some View {
        ZStack {
            Obs.canvas.ignoresSafeArea()
            if let s {
                content(s)
            } else {
                VStack(spacing: 14) {
                    ProgressView().tint(Obs.ink)
                    Text("Cargando tus datos…").font(Obs.mono(12)).foregroundStyle(Obs.ink2)
                }
            }
        }
        .fullScreenCover(item: $report) { sel in if let s { DayReportView(s: s, day: sel.day, tab: sel.sleep ? .sleep : .activity) } }
        .sheet(isPresented: $showAllDays) { if let s { AllDaysView(s: s) } }
        .onAppear(perform: applyLaunchArguments)
        .sheet(isPresented: $showSync) {
            SyncView(ring: ring, onSynced: refreshAfterSync, onReset: resetAndReload)
        }
        .sheet(isPresented: $showProfile) { ProfileSettingsView(profile: s?.profile, onSaved: refreshDerivedData) }
        .sheet(isPresented: $showLivePulse) { PersonalLivePulseView(ring: ring) }
        .sheet(isPresented: $showSleepDebt) { if let debt = s?.sleepDebt { SleepDebtDetail(debt: debt) } }
        .sheet(item: $vital) { kind in if let s { VitalTrendView(s: s, kind: kind) } }
        #if TORCH
        .environment(\.dayAnalysis, DayAnalysisContext(summary: s,
            isBusy: isRefreshingSummary || ring.busy, refresh: refreshDayAnalysis))
        #endif
        .onAppear {
            // A cached summary makes launch immediate; this forced load replaces it
            // with SQLite + model output without blanking the existing Today card.
            requestAutomaticSync()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.protectedDataDidBecomeAvailableNotification)) { _ in
            requestAutomaticSync()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                requestAutomaticSync()
            } else if phase == .background {
                WorkCoordinator.shared.invalidateAnalysis()
            }
        }
    }

    // re-read the DB after a sync brought in new events
    private func reload() {
        load(force: true, clearCurrent: true)
    }

    private func resetAndReload() {
        SummaryCache.clear()
        #if TORCH
        ModelCacheStore.clearAll()
        #endif
        reload()
    }

    /// Profile changes affect CVA and activity inference, but do not invalidate the
    /// summary already on screen. Keep the last complete result visible until every
    /// derived model has finished, avoiding a transient sleep-debt regression.
    private func refreshDerivedData() {
        load(force: true, clearCurrent: false)
    }

    /// New ring events invalidate every derived view. In particular this reruns AAD
    /// after the database transaction has completed, so newly accumulated movement
    /// cannot leave yesterday's activity sessions cached on screen.
    private func refreshAfterSync(_ report: SyncReport) {
        guard report.inserted > 0 else { return }
        load(force: true, clearCurrent: false)
    }

    private func requestAutomaticSync() {
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        guard !automaticSyncRequested, !showLivePulse, !ring.liveActive else { return }
        automaticSyncRequested = true
        Task {
            defer { automaticSyncRequested = false }
            _ = await ring.syncAutomaticallyIfNeeded()
            if WorkCoordinator.shared.available { load(force: true, clearCurrent: false) }
        }
    }

    #if TORCH
    @MainActor private func refreshDayAnalysis(_ request: DayAnalysisRequest) async -> String? {
        guard !isRefreshingSummary, !ring.busy, let previous = s else {
            return "Wait for sync and analysis to finish, then try again."
        }
        guard WorkCoordinator.shared.available else { return "Keep the app open to refresh analysis." }
        let run = WorkCoordinator.shared.newAnalysis()
        loadGeneration += 1
        let generation = loadGeneration
        isRefreshingSummary = true
        defer {
            if reloadPending {
                reloadPending = false
                load(force: true, clearCurrent: false)
            }
        }
        modelProgress.begin(generation)
        let progress = modelProgress.sink(generation)
        await WorkGate.shared.acquire()
        guard !run.isCancelled, WorkCoordinator.shared.available else {
            await WorkGate.shared.release()
            WorkCoordinator.shared.finishAnalysis(run)
            if generation == loadGeneration { isRefreshingSummary = false }
            return "Refresh paused. Keep the app open and try again."
        }
        IdleTimerLock.acquire("models")
        dlog("models", "refresh start day=\(request.day) kind=\(request.kind.rawValue) run=\(run.id)")
        let result: (summary: Summary, error: String?) = await withCheckedContinuation { completion in
            DispatchQueue.global(qos: .userInitiated).async {
                completion.resume(returning: run.perform {
                    Core.refreshAnalysis(previous, request: request, progress: progress)
                })
            }
        }
        let canPublish = generation == loadGeneration && !run.isCancelled && WorkCoordinator.shared.available
        if canPublish && result.error == nil {
            s = result.summary
            SummaryCache.save(result.summary)
            HealthExport.shared.push(result.summary)
        }
        if generation == loadGeneration {
            isRefreshingSummary = false
            modelProgress.report(generation, nil)
        }
        IdleTimerLock.release("models")
        WorkCoordinator.shared.finishAnalysis(run)
        await WorkGate.shared.release()
        dlog("models", "refresh end day=\(request.day) kind=\(request.kind.rawValue) cancelled=\(run.isCancelled)")
        return canPublish ? result.error : "Refresh paused. Keep the app open and try again."
    }
    #endif

    private func load(force: Bool = false, clearCurrent: Bool = false) {
        guard force || s == nil else { return }
        // Lifecycle notifications and sync completion can request the same load.
        // Queue one refresh instead of repeatedly cancelling its predecessor.
        guard !isRefreshingSummary else { reloadPending = true; return }
        let run = WorkCoordinator.shared.newAnalysis()
        loadGeneration += 1
        let generation = loadGeneration
        let previous = clearCurrent ? nil : s
        if clearCurrent { s = nil }
        isRefreshingSummary = true
        modelProgress.begin(generation)
        let progress = modelProgress.sink(generation)
        Task {
            defer {
                if reloadPending {
                    reloadPending = false
                    load(force: true, clearCurrent: false)
                }
            }
            modelProgress.report(generation, "Waiting for ring data")
            dlog("models", "waiting for work gate run=\(run.id)")
            await WorkGate.shared.acquire()
            guard !run.isCancelled, WorkCoordinator.shared.available else {
                await WorkGate.shared.release()
                WorkCoordinator.shared.finishAnalysis(run)
                if generation == loadGeneration { isRefreshingSummary = false; modelProgress.report(generation, "Analysis paused") }
                return
            }
            modelProgress.report(generation, "Reading ring data")
            IdleTimerLock.acquire("models")
            dlog("models", "start run=\(run.id)")
            let started = ProcessInfo.processInfo.systemUptime
            let full: Summary = await withCheckedContinuation { completion in
                DispatchQueue.global(qos: .userInitiated).async {
                    let summary = run.perform {
                        let base = Core.base()
                        #if TORCH
                        return base.error == nil && !run.isCancelled
                            ? Core.withModels(base, previous: previous, progress: progress) : base
                        #else
                        return base
                        #endif
                    }
                    completion.resume(returning: summary)
                }
            }
            if generation == loadGeneration {
                if !run.isCancelled, WorkCoordinator.shared.available {
                    if full.error == nil {
                        s = full
                        SummaryCache.save(full)
                        HealthExport.shared.push(full)
                    } else if s == nil { s = full }
                    modelProgress.report(generation, full.error == nil ? nil : "Couldn’t refresh data.")
                } else { modelProgress.report(generation, "Analysis paused") }
                isRefreshingSummary = false
            }
            dlog("models", "end run=\(run.id) cancelled=\(run.isCancelled) duration=\(Int(ProcessInfo.processInfo.systemUptime - started))s")
            IdleTimerLock.release("models")
            WorkCoordinator.shared.finishAnalysis(run)
            await WorkGate.shared.release()
        }
    }

    private func content(_ s: Summary) -> some View {
        V4Home(summary: s, ring: ring, refreshing: isRefreshingSummary,
            onSync: { showSync = true }, onProfile: { showProfile = true },
            onHistory: { showAllDays = true }, onPulse: { showLivePulse = true },
            onDebt: { showSleepDebt = true }, onVital: { vital = $0 },
            onRefresh: {
                guard !ring.busy, !showLivePulse else { return }
                guard let key = Keychain.loadKey() else { showSync = true; return }
                if let result = await ring.run(keyHex: key) { refreshAfterSync(result) }
            }, onBedtimeSaved: refreshDerivedData)
    }

}

/// Which build is actually on this phone. A sideloaded app has no App Store version
/// to compare against, and a failed install looks exactly like a successful one — so
/// show the version, when this binary was signed, and when its free-account
/// certificate stops launching (7 days).
struct BuildStamp: View {
    var prefix: String? = nil
    private static let signedAt: Date? = {
        guard let path = Bundle.main.executableURL?.path,
              let attrs = try? FileManager.default.attributesOfItem(atPath: path) else { return nil }
        return attrs[.modificationDate] as? Date
    }()

    private static let stampFormat: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d HH:mm"
        return f
    }()

    private static let dayFormat: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f
    }()

    private var line: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        var out = "Open Oura \(short) (\(build)) · \(coreVersion())"
        if let prefix { out = prefix + " · " + out }
        if let signed = Self.signedAt {
            out += " · built \(Self.stampFormat.string(from: signed))"
            if let expiry = Calendar.current.date(byAdding: .day, value: 7, to: signed) {
                let days = Calendar.current.dateComponents([.day], from: Date(), to: expiry).day ?? 0
                out += days < 0
                    ? " · signing expired"
                    : " · signing good to \(Self.dayFormat.string(from: expiry))"
            }
        }
        return out
    }

    var body: some View {
        Text(line)
            .font(Obs.mono(10))
            .foregroundStyle(Obs.muted)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, 6)
            .textSelection(.enabled)
    }
}

@main
struct OuraApp: App {
    init() { DiagStore.shared.bootstrap() }
    var body: some Scene { WindowGroup { RootView() } }
}



// Personal iOS dashboard. Scores are deliberately labelled as non-official,
// transparent estimates. Never substitute time in bed for measured sleep.
struct PersonalDailyScore: Identifiable {
    var id: String { title }
    let title: String
    let value: Int?
    let subtitle: String
    let explanation: String
    let factors: [String]
    let icon: String
}

enum PersonalDailyScores {
    static func positive(_ value: Double?) -> Double? {
        guard let value, value.isFinite, value > 0 else { return nil }
        return value
    }

    static func nonnegative(_ value: Double?) -> Double? {
        guard let value, value.isFinite, value >= 0 else { return nil }
        return value
    }

    static func clamp(_ value: Double) -> Int {
        Int(min(100, max(0, value)).rounded())
    }

    static func median(_ values: [Double]) -> Double? {
        let v = values.sorted()
        guard !v.isEmpty else { return nil }
        let middle = v.count / 2
        return v.count % 2 == 0 ? (v[middle - 1] + v[middle]) / 2 : v[middle]
    }

    static func sleep(_ summary: Summary, day: String, goal: Double) -> PersonalDailyScore {
        let night = summary.night(forDay: day)
        if let score = night?.sleep_score, score.score.isFinite,
           night?.stagingComplete == true,
           score.components.contains(where: { $0.key == "duration" }) {
            let names = ["duration": "Duración", "efficiency": "Eficiencia",
                         "onset_latency": "Tiempo hasta dormir", "waso": "Tiempo despierto",
                         "awakenings": "Despertares", "architecture": "Fases del sueño",
                         "physiology": "Pulso y HRV"]
            return PersonalDailyScore(title: "Sueño", value: clamp(score.score),
                subtitle: "Índice del proyecto",
                explanation: "Puntuación del algoritmo de sueño de Open Oura, basado en referencias de la literatura. No equivale al índice oficial de Oura ni es una valoración clínica.",
                factors: score.components.filter { $0.score.isFinite }.map {
                    "\(names[$0.key] ?? $0.key): \(clamp($0.score))/100"
                }, icon: "moon.fill")
        }
        let hours = positive(night?.in_bed_h)
        let value = hours.map { clamp($0 / max(1, goal) * 100) }
        return PersonalDailyScore(title: "Sueño", value: value,
            subtitle: value == nil ? "Sin datos" : "Solo tiempo en cama",
            explanation: "Sin análisis completo de fases no conocemos el tiempo realmente dormido. Este número es únicamente el porcentaje de tu objetivo de tiempo en cama (limitado a 100), no una puntuación de calidad del sueño.",
            factors: [hours.map { String(format: "Tiempo en cama: %.1f h", $0) } ?? "Sin ventana nocturna",
                      String(format: "Objetivo: %.1f h", goal),
                      "Fases y eficiencia: no evaluadas"], icon: "moon.fill")
    }

    static func activity(_ summary: Summary, day: String, stepsGoal: Int, activeGoal: Int) -> PersonalDailyScore {
        let steps = nonnegative(summary.activity_daily[day]?.steps)
        let profile = summary.activity_profile[day] ?? []
        // Match the existing ActivityReport's 3-MET threshold and bucket length.
        let hasProfile = !profile.isEmpty && profile.allSatisfy { $0.isFinite && $0 >= 0 }
        let activeMinutes: Double? = hasProfile
            ? Double(profile.filter { $0 >= 3 }.count) * 1440 / Double(profile.count)
            : nil
        var pieces: [Double] = []
        var factors: [String] = []
        if let steps {
            pieces.append(min(1, steps / Double(max(1, stepsGoal))))
            factors.append("\(Int(steps.rounded())) de \(stepsGoal) pasos")
        }
        if let activeMinutes {
            pieces.append(min(1, activeMinutes / Double(max(1, activeGoal))))
            factors.append("\(Int(activeMinutes.rounded())) de \(activeGoal) min activos")
        }
        let value: Int? = pieces.isEmpty ? nil : clamp(100 * pieces.reduce(0, +) / Double(pieces.count))
        return PersonalDailyScore(title: "Actividad", value: value,
            subtitle: pieces.isEmpty ? "Sin datos" : (pieces.count < 2 ? "Objetivo parcial" : "Progreso del día"),
            explanation: "Promedio del porcentaje de los objetivos disponibles de pasos y minutos activos (3 MET o más, como en el informe original). Cada componente se limita al 100%. Los objetivos son editables. No mide recuperación ni calidad del entrenamiento; una jornada en curso puede tener un valor bajo.",
            factors: factors, icon: "figure.walk")
    }

    static func recovery(_ summary: Summary, day: String) -> PersonalDailyScore {
        let missing = PersonalDailyScore(title: "Recuperación", value: nil,
            subtitle: "Calculando referencia",
            explanation: "Se necesitan pulso en reposo y HRV de una noche principal y al menos siete noches anteriores con ambas medidas. No se inventan valores para los datos ausentes. Índice orientativo, no oficial ni clínico.",
            factors: [], icon: "heart.fill")
        guard let night = summary.night(forDay: day),
              (night.in_bed_h ?? 0) >= 3,
              let hrv = positive(night.hrv_ms), let rhr = positive(night.rhr),
              let start = night.start_unix else { return missing }
        let history = summary.days.filter { $0 < day }.compactMap { summary.night(forDay: $0) }
            .filter { n in
                guard let end = n.end_unix else { return false }
                return end <= start && (n.in_bed_h ?? 0) >= 3
                    && positive(n.hrv_ms) != nil && positive(n.rhr) != nil
            }
        let prior = Array(history.prefix(28))
        guard prior.count >= 7,
              let baseHRV = median(prior.compactMap { positive($0.hrv_ms) }),
              let baseRHR = median(prior.compactMap { positive($0.rhr) }) else { return missing }
        // Heuristic (not Oura Readiness): lower HRV and higher resting HR relative to
        // a causal personal median reduce the index. No diagnosis or exercise advice.
        let hrvPart = max(0, 100 - max(0, 1 - hrv / baseHRV) * 200)
        let rhrPart = max(0, 100 - max(0, rhr / baseRHR - 1) * 400)
        return PersonalDailyScore(title: "Recuperación", value: clamp((hrvPart + rhrPart) / 2),
            subtitle: "Índice orientativo",
            explanation: "Estimación experimental basada exclusivamente en HRV y pulso nocturno en reposo frente a la mediana de hasta 28 noches anteriores (mínimo 7). Ambos componentes pesan un 50%. Un descenso de HRV del 10% resta 20 puntos a su componente; una subida de pulso del 10% resta 40. No mide la preparación real para entrenar ni reproduce Oura Readiness.",
            factors: [String(format: "HRV: %.0f ms · referencia %.0f ms", hrv, baseHRV),
                      String(format: "Pulso: %.0f lpm · referencia %.0f lpm", rhr, baseRHR),
                      "Noches de referencia: \(prior.count)"], icon: "heart.fill")
    }
}

struct PersonalDailyScoresView: View {
    let summary: Summary
    let day: String
    @AppStorage("personal.goals.steps") private var stepsGoal = 8000
    @AppStorage("personal.goals.activeMinutes") private var activeGoal = 30
    @AppStorage("personal.goals.inBedHours") private var bedGoal = 8.0
    @State private var selected: PersonalDailyScore?
    @State private var showGoals = false

    private var scores: [PersonalDailyScore] {
        [PersonalDailyScores.sleep(summary, day: day, goal: bedGoal),
         PersonalDailyScores.recovery(summary, day: day),
         PersonalDailyScores.activity(summary, day: day, stepsGoal: stepsGoal, activeGoal: activeGoal)]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Tus índices · \(day)").font(Obs.prose(14, .medium)).foregroundStyle(Obs.ink)
                Spacer()
                Button { showGoals = true } label: {
                    Label("Objetivos", systemImage: "slider.horizontal.3").font(Obs.prose(12))
                }.buttonStyle(.plain)
            }
            HStack(alignment: .top, spacing: 6) {
                ForEach(scores) { score in
                    Button { selected = score } label: {
                        VStack(spacing: 5) {
                            ZStack {
                                Circle().stroke(Obs.trace.opacity(0.3), lineWidth: 6)
                                if let value = score.value {
                                    Circle().trim(from: 0, to: CGFloat(value) / 100)
                                        .stroke(score.title == "Sueño" ? V4Tab.sleep.tint : score.title == "Actividad" ? V4Tab.sport.tint : V4Tab.health.tint, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                                        .rotationEffect(.degrees(-90))
                                }
                                VStack(spacing: 1) {
                                    Text(score.value.map { String($0) } ?? "–")
                                        .font(Obs.mono(23, .medium)).foregroundStyle(Obs.ink)
                                    Text("/100").font(Obs.mono(9)).foregroundStyle(Obs.muted)
                                }
                            }
                            .frame(width: 72, height: 72)
                            Label(score.title, systemImage: score.icon)
                                .font(Obs.prose(11, .medium)).foregroundStyle(Obs.ink)
                                .lineLimit(1).minimumScaleFactor(0.7)
                            Text(score.subtitle).font(Obs.prose(10)).foregroundStyle(Obs.ink2)
                                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                        }.frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(score.title), \(score.value.map { String($0) + " de 100" } ?? "sin datos"), \(score.subtitle)")
                }
            }
            Text("Índices propios, no puntuaciones oficiales de Oura.")
                .font(Obs.prose(11)).foregroundStyle(Obs.muted)
        }
        .obsCard()
        .sheet(item: $selected) { score in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Label(score.title, systemImage: score.icon).font(Obs.serif(26))
                    Text(score.value.map { "\($0)/100" } ?? "Sin datos suficientes")
                        .font(Obs.mono(28, .medium))
                    Text(score.subtitle).font(Obs.prose(15, .medium))
                    Text(score.explanation).font(Obs.prose(14))
                    ForEach(Array(score.factors.enumerated()), id: \.offset) { item in
                        Text(item.element).font(Obs.prose(14))
                    }
                    Button("Cerrar") { selected = nil }.buttonStyle(.bordered)
                }.foregroundStyle(Obs.ink).padding(24)
            }.background(Obs.paper)
        }
        .sheet(isPresented: $showGoals) {
            NavigationStack {
                Form {
                    Stepper("Pasos: \(stepsGoal)", value: $stepsGoal, in: 1000...30000, step: 500)
                    Stepper("Minutos activos: \(activeGoal)", value: $activeGoal, in: 5...180, step: 5)
                    Stepper("Tiempo en cama: \(bedGoal, specifier: "%.1f") h", value: $bedGoal, in: 5...12, step: 0.5)
                    Text("Estos objetivos son preferencias personales, no recomendaciones médicas. El de tiempo en cama no sustituye un análisis del sueño.")
                        .font(.footnote)
                }
                .navigationTitle("Objetivos diarios")
                .toolbar { ToolbarItem(placement: .topBarTrailing) {
                    Button("Listo") { showGoals = false }
                } }
            }
        }
    }
}
