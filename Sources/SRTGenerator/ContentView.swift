import SwiftUI
import Translation
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(AppState.self) private var state
    @State private var isTargeted = false
    @State private var showModels = false
    @State private var preview: URL?

    var body: some View {
        @Bindable var translator = state.translator
        ZStack {
            AmbientBackground()

            VStack(spacing: 16) {
                header
                SettingsPanel(showModels: $showModels)
                if state.jobs.isEmpty {
                    DropZone(isTargeted: isTargeted)
                } else {
                    JobList(preview: $preview)
                }
                footer
            }
            .padding(.horizontal, 24)
            .padding(.top, 6)
            .padding(.bottom, 20)
        }
        .dropDestination(for: URL.self) { urls, _ in
            state.add(urls)
            return true
        } isTargeted: { isTargeted = $0 }
        .sheet(isPresented: $showModels) { ModelManagerView() }
        .sheet(item: $preview) { SRTPreview(url: $0) }
        // Hidden host for Apple's on-device Translation sessions.
        .background {
            Color.clear.translationTask(translator.configuration) { session in
                await state.translator.run(session)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("SRT Generator")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                Text("Any audio or video → subtitles, fully on-device")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                state.presentOpenPanel()
            } label: {
                Label("Add Files", systemImage: "plus")
                    .padding(.horizontal, 4)
            }
            .buttonStyle(.glass)
            .controlSize(.large)
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            if !state.ffmpegAvailable {
                Label("Install ffmpeg (brew install ffmpeg) to support MKV, WebM, OGG and more.",
                      systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if state.jobs.contains(where: \.isFinished) && !state.isRunning {
                Button("Clear Finished") { state.clearFinished() }
                    .buttonStyle(.glass)
            }
            if state.isRunning {
                Button(role: .cancel) { state.cancel() } label: {
                    Label("Stop", systemImage: "stop.fill")
                }
                .buttonStyle(.glass)
                .controlSize(.large)
            } else {
                Button { state.start() } label: {
                    Label("Generate Subtitles", systemImage: "captions.bubble.fill")
                        .padding(.horizontal, 6)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .disabled(!state.jobs.contains { $0.status != .done })
                .keyboardShortcut(.return, modifiers: .command)
            }
        }
    }
}

extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}

// MARK: - Background

struct AmbientBackground: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let s = Float(sin(t * 0.25)) * 0.12
            let c = Float(cos(t * 0.2)) * 0.12
            MeshGradient(
                width: 3, height: 3,
                points: [
                    [0, 0], [0.5 + s, 0], [1, 0],
                    [0, 0.5 + c], [0.5 - c, 0.5 + s], [1, 0.5 - s],
                    [0, 1], [0.5 + c, 1], [1, 1],
                ],
                colors: scheme == .dark ? Self.dark : Self.light
            )
        }
        .ignoresSafeArea()
    }

    static let light: [Color] = [
        .init(red: 0.78, green: 0.86, blue: 1.0), .init(red: 0.88, green: 0.80, blue: 1.0), .init(red: 1.0, green: 0.84, blue: 0.90),
        .init(red: 0.74, green: 0.92, blue: 0.98), .init(red: 0.95, green: 0.95, blue: 1.0), .init(red: 0.98, green: 0.88, blue: 0.80),
        .init(red: 0.70, green: 0.88, blue: 0.90), .init(red: 0.82, green: 0.84, blue: 1.0), .init(red: 0.92, green: 0.78, blue: 0.96),
    ]
    static let dark: [Color] = [
        .init(red: 0.07, green: 0.10, blue: 0.28), .init(red: 0.22, green: 0.08, blue: 0.34), .init(red: 0.36, green: 0.07, blue: 0.22),
        .init(red: 0.03, green: 0.20, blue: 0.30), .init(red: 0.08, green: 0.08, blue: 0.16), .init(red: 0.30, green: 0.14, blue: 0.06),
        .init(red: 0.02, green: 0.18, blue: 0.20), .init(red: 0.10, green: 0.10, blue: 0.32), .init(red: 0.24, green: 0.06, blue: 0.30),
    ]
}

// MARK: - Settings

struct SettingsPanel: View {
    @Environment(AppState.self) private var state
    @Binding var showModels: Bool

    var body: some View {
        @Bindable var state = state
        GlassEffectContainer(spacing: 12) {
            VStack(spacing: 14) {
                HStack(spacing: 14) {
                    field("Model", systemImage: "cpu") {
                        HStack(spacing: 6) {
                            Picker("Model", selection: $state.model) {
                                ForEach(WhisperModel.allCases) { m in
                                    Text(m.title + (state.downloadedModels.contains(m) ? "" : " ↓")).tag(m)
                                }
                            }
                            .labelsHidden()
                            Button { showModels = true } label: { Image(systemName: "slider.horizontal.3") }
                                .buttonStyle(.glass)
                                .help("Manage local models")
                        }
                    }
                    field("Spoken language", systemImage: "waveform") {
                        Picker("Spoken language", selection: $state.languageCode) {
                            Text("Auto-detect").tag("auto")
                            Divider()
                            ForEach(AppState.whisperLanguages, id: \.code) { Text($0.name).tag($0.code) }
                        }
                        .labelsHidden()
                    }
                }
                HStack(spacing: 14) {
                    field("Subtitles in", systemImage: "text.bubble") {
                        Picker("Subtitles in", selection: $state.outputMode) {
                            ForEach(OutputMode.allCases) { Text($0.title).tag($0) }
                        }
                        .labelsHidden()
                    }
                    field("Also translate to", systemImage: "globe") {
                        TranslationTargetsMenu()
                    }
                }
                HStack(spacing: 14) {
                    field("Save to", systemImage: "folder") {
                        HStack {
                            Text(state.outputFolder?.lastPathComponent ?? "Same folder as source")
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            if state.outputFolder != nil {
                                Button { state.outputFolder = nil } label: { Image(systemName: "xmark") }
                                    .buttonStyle(.glass)
                                    .help("Save next to source files")
                            }
                            Button("Choose…") { state.chooseOutputFolder() }
                                .buttonStyle(.glass)
                        }
                    }
                }
            }
            .padding(18)
            .glassEffect(.regular, in: .rect(cornerRadius: 26))
        }
        .disabled(state.isRunning)
    }

    private func field<Content: View>(_ title: String, systemImage: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct TranslationTargetsMenu: View {
    @Environment(AppState.self) private var state

    var body: some View {
        Menu {
            if state.translationTargets.isEmpty {
                Text("Loading languages…")
            }
            if !state.extraTargets.isEmpty {
                Button("Clear All") { state.extraTargets.removeAll() }
                Divider()
            }
            ForEach(state.translationTargets, id: \.minimalIdentifier) { lang in
                let id = lang.minimalIdentifier
                Toggle(TranslationBridge.displayName(lang), isOn: Binding(
                    get: { state.extraTargets.contains(id) },
                    set: { on in if on { state.extraTargets.insert(id) } else { state.extraTargets.remove(id) } }
                ))
            }
        } label: {
            Text(summary).lineLimit(1)
        }
        .menuIndicator(.visible)
        .fixedSize(horizontal: false, vertical: true)
        .help("Extra SRT files translated on-device with Apple Translation")
    }

    private var summary: String {
        let names = state.extraTargets.sorted().map { TranslationBridge.displayName(Locale.Language(identifier: $0)) }
        switch names.count {
        case 0: return "None"
        case 1...3: return names.joined(separator: ", ")
        default: return "\(names.count) languages"
        }
    }
}

// MARK: - Drop zone

struct DropZone: View {
    @Environment(AppState.self) private var state
    var isTargeted: Bool

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: isTargeted ? "arrow.down.circle.fill" : "waveform.badge.plus")
                .font(.system(size: 54, weight: .light))
                .symbolEffect(.bounce, value: isTargeted)
                .contentTransition(.symbolEffect(.replace))
            Text("Drop audio or video files here")
                .font(.title3.weight(.semibold))
            Text("MP4 · MOV · MKV · WebM · AVI · MP3 · WAV · M4A · FLAC · OGG · Opus · and more")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Browse…") { state.presentOpenPanel() }
                .buttonStyle(.glass)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(30)
        .glassEffect(isTargeted ? .regular.tint(.accentColor.opacity(0.35)).interactive() : .regular.interactive(),
                     in: .rect(cornerRadius: 30))
        .overlay {
            RoundedRectangle(cornerRadius: 30)
                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [8, 6]))
                .foregroundStyle(.secondary.opacity(isTargeted ? 0.8 : 0.3))
                .padding(10)
        }
        .animation(.smooth, value: isTargeted)
        .onTapGesture { state.presentOpenPanel() }
    }
}

// MARK: - Jobs

struct JobList: View {
    @Environment(AppState.self) private var state
    @Binding var preview: URL?

    var body: some View {
        ScrollView {
            GlassEffectContainer(spacing: 10) {
                LazyVStack(spacing: 10) {
                    ForEach(state.jobs) { job in
                        JobRow(job: job, preview: $preview)
                            .transition(.blurReplace)
                    }
                }
                .padding(2)
            }
        }
        .scrollContentBackground(.hidden)
        .animation(.smooth, value: state.jobs.map(\.id))
    }
}

struct JobRow: View {
    @Environment(AppState.self) private var state
    let job: Job
    @Binding var preview: URL?

    var body: some View {
        HStack(spacing: 14) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: job.url.path))
                .resizable()
                .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(job.url.lastPathComponent)
                        .font(.headline)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if let lang = job.detectedLanguage {
                        Text(lang.uppercased())
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .glassEffect(.regular.tint(.blue.opacity(0.3)), in: .capsule)
                    }
                }
                statusView
                if !job.warnings.isEmpty {
                    Text(job.warnings.joined(separator: "\n"))
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 6) {
                if !job.outputs.isEmpty {
                    Menu {
                        ForEach(job.outputs, id: \.self) { url in
                            Button(url.lastPathComponent) { preview = url }
                        }
                    } label: {
                        Image(systemName: "eye")
                    } primaryAction: {
                        preview = job.outputs.first
                    }
                    .menuIndicator(job.outputs.count > 1 ? .visible : .hidden)
                    .fixedSize()
                    .help("Preview subtitles")

                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting(job.outputs)
                    } label: { Image(systemName: "folder") }
                        .help("Show in Finder")
                }
                if job.isFinished || !state.isRunning {
                    Button { state.remove(job) } label: { Image(systemName: "xmark") }
                        .help("Remove")
                }
            }
            .buttonStyle(.glass)
        }
        .padding(14)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 20))
    }

    @ViewBuilder private var statusView: some View {
        switch job.status {
        case .queued:
            status("Waiting", "clock", .secondary)
        case .downloadingModel(let p):
            progress("Downloading \(state.model.title) model (one-time)…", p)
        case .loadingModel:
            progress("Loading model… (first load compiles for this Mac and can take a few minutes)", nil)
        case .decoding:
            progress("Extracting audio…", nil)
        case .transcribing(let p):
            progress("Transcribing…", p)
        case .translating(let lang):
            progress("Translating to \(lang)…", nil)
        case .done:
            status("Done · " + job.outputs.map(\.lastPathComponent).joined(separator: ", "), "checkmark.circle.fill", .green)
        case .failed(let msg):
            status(msg, "exclamationmark.octagon.fill", .red)
        case .cancelled:
            status("Stopped", "stop.circle", .secondary)
        }
    }

    private func status(_ text: String, _ icon: String, _ color: Color) -> some View {
        Label(text, systemImage: icon)
            .font(.caption)
            .foregroundStyle(color)
            .lineLimit(2)
    }

    private func progress(_ text: String, _ value: Double?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(text).font(.caption).foregroundStyle(.secondary)
            if let value {
                ProgressView(value: value).progressViewStyle(.linear)
            } else {
                ProgressView().progressViewStyle(.linear)
            }
        }
    }
}

// MARK: - Preview

struct SRTPreview: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(url.lastPathComponent).font(.headline)
                Spacer()
                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                    .buttonStyle(.glass)
                Button("Done") { dismiss() }
                    .buttonStyle(.glassProminent)
                    .keyboardShortcut(.defaultAction)
            }
            .padding()
            ScrollView {
                Text((try? String(contentsOf: url, encoding: .utf8)) ?? "Could not read file.")
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
        }
        .frame(width: 620, height: 520)
    }
}

// MARK: - Models

struct ModelManagerView: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading) {
                    Text("Whisper Models").font(.title2.bold())
                    Text("Models are downloaded once, stored locally, and run entirely on your Mac. All support 99 languages.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done") { dismiss() }.buttonStyle(.glassProminent)
            }
            GlassEffectContainer(spacing: 8) {
                VStack(spacing: 8) {
                    ForEach(WhisperModel.allCases) { m in row(m) }
                }
            }
            if let error {
                Text(error).font(.caption).foregroundStyle(.red)
            }
            Button("Open Models Folder") {
                try? FileManager.default.createDirectory(at: Transcriber.storageRoot, withIntermediateDirectories: true)
                NSWorkspace.shared.open(Transcriber.storageRoot)
            }
            .buttonStyle(.glass)
        }
        .padding(22)
        .frame(width: 560)
    }

    private func row(_ m: WhisperModel) -> some View {
        HStack {
            Image(systemName: state.model == m ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(state.model == m ? Color.accentColor : .secondary)
                .onTapGesture { state.model = m }
            VStack(alignment: .leading) {
                Text(m.title).font(.headline)
                Text(m.detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if let p = state.modelDownloads[m] {
                ProgressView(value: p).frame(width: 120)
            } else if state.downloadedModels.contains(m) {
                Button(role: .destructive) { state.deleteModel(m) } label: { Image(systemName: "trash") }
                    .buttonStyle(.glass)
                    .disabled(state.isRunning)
            } else {
                Button("Download") {
                    Task {
                        do { try await state.download(m) } catch { self.error = error.localizedDescription }
                    }
                }
                .buttonStyle(.glass)
            }
        }
        .padding(12)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 16))
        .contentShape(.rect)
        .onTapGesture { state.model = m }
    }
}
