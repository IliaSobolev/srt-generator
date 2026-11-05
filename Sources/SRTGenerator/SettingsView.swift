import SRTCore
import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            Tab("Models", systemImage: "cpu") { ModelsSettingsView() }
            Tab("Model Settings", systemImage: "slider.horizontal.3") { ModelOptionsView() }
            Tab("Subtitles", systemImage: "captions.bubble") { SubtitleOptionsView() }
        }
        .frame(width: 640, height: 620)
    }
}

// MARK: - Model settings

struct ModelOptionsView: View {
    @Environment(AppState.self) private var state
    @State private var newWord = ""

    var body: some View {
        @Bindable var state = state
        let model = state.model
        Form {
            Section {
                LabeledContent("Active model") {
                    Text("\(model.name) · \(model.engine.title)").foregroundStyle(.secondary)
                }
                Picker("Spoken language", selection: $state.languageCode) {
                    Text("Auto-detect").tag("auto")
                    Divider()
                    ForEach(state.languageChoices, id: \.code) { Text($0.name).tag($0.code) }
                }
                .disabled(!model.supportsLanguageSelection)
                Toggle("Translate to English", isOn: Binding(
                    get: { state.outputMode == .english && model.supportsTranslation },
                    set: { state.outputMode = $0 ? .english : .original }
                ))
                .disabled(!model.supportsTranslation)
            } header: {
                Text("Language")
            } footer: {
                if !model.supportsTranslation {
                    Text("\(model.name) can't translate. Use a Whisper model, or “Also translate to” in the main window.")
                } else if !model.supportsLanguageSelection {
                    Text("\(model.name) only recognizes \(model.languages).")
                }
            }

            Section {
                ForEach(state.settings.customWords, id: \.self) { word in
                    HStack {
                        Text(word)
                        Spacer()
                        Button { state.settings.customWords.removeAll { $0 == word } } label: {
                            Image(systemName: "minus.circle.fill")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                    }
                }
                HStack {
                    TextField("Add a name, term or acronym", text: $newWord)
                        .onSubmit(addWord)
                    Button("Add", action: addWord)
                        .buttonStyle(.glass)
                        .disabled(newWord.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            } header: {
                Text("Custom Words")
            } footer: {
                Text("Helps Whisper spell names and jargon correctly. Parakeet ignores custom words.")
            }

            Section("Performance") {
                Picker("Run on", selection: $state.settings.compute) {
                    ForEach(ComputeTarget.allCases) { Text($0.title).tag($0) }
                }
                Picker("Unload model from memory", selection: $state.settings.unloadTimeout) {
                    ForEach(UnloadTimeout.allCases) { Text($0.title).tag($0) }
                }
            }

            Section {
                Toggle("Split audio at silences (VAD)", isOn: $state.settings.whisperVAD)
                Toggle("Retry hard passages (temperature fallback)", isOn: $state.settings.whisperTemperatureFallback)
                Toggle("Skip non-speech (music, noise)", isOn: $state.settings.whisperSuppressNonSpeech)
            } header: {
                Text("Whisper")
            } footer: {
                Text(model.engine == .whisper
                    ? "VAD makes long files faster and reduces hallucinations in silent parts."
                    : "These options apply only to Whisper models.")
            }
            .disabled(model.engine != .whisper)

            Section {
                Button("Restore Defaults") {
                    state.settings = TranscriptionSettings()
                }
            }
        }
        .formStyle(.grouped)
        .disabled(state.queue.isRunning)
    }

    private func addWord() {
        let word = newWord.trimmingCharacters(in: .whitespaces)
        guard !word.isEmpty, !state.settings.customWords.contains(word) else { return }
        state.settings.customWords.append(word)
        newWord = ""
    }
}

// MARK: - Subtitles

struct SubtitleOptionsView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        @Bindable var state = state
        Form {
            Section("Layout") {
                LabeledContent("Max characters per line") {
                    Stepper("\(state.settings.maxLineLength)", value: $state.settings.maxLineLength, in: 20...80, step: 2)
                }
                LabeledContent("Max cue duration") {
                    Stepper(String(format: "%.0f s", state.settings.maxCueDuration),
                            value: $state.settings.maxCueDuration, in: 2...15, step: 1)
                }
            }
            Section {
                LabeledContent("Save to") {
                    HStack {
                        Text(state.outputFolder?.path(percentEncoded: false) ?? "Same folder as source")
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundStyle(.secondary)
                        if state.outputFolder != nil {
                            Button("Reset") { state.outputFolder = nil }
                        }
                        Button("Choose…") { state.chooseOutputFolder() }
                    }
                }
            } header: {
                Text("Output")
            } footer: {
                Text("Files are named “video.srt”, “video.en.srt”, “video.de.srt”… Existing files are never overwritten.")
            }
        }
        .formStyle(.grouped)
        .disabled(state.queue.isRunning)
    }
}

// MARK: - Models

struct ModelsSettingsView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Models").font(.title2.bold())
                    Text("Click a model to download it and start using it. Models run entirely on your Mac.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                GlassEffectContainer(spacing: 10) {
                    VStack(spacing: 10) {
                        ForEach(ModelCatalog.all) { ModelCard(model: $0) }
                    }
                }
                HStack {
                    Text("Stored in ~/Library/Application Support")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Show Models Folder") {
                        let url = state.models.folder(for: state.model).deletingLastPathComponent()
                        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
                        NSWorkspace.shared.open(url)
                    }
                    .buttonStyle(.glass)
                }
            }
            .padding(22)
        }
    }
}

struct ModelCard: View {
    @Environment(AppState.self) private var state
    let model: ModelInfo
    @State private var confirmDelete = false

    private var isActive: Bool { state.model.id == model.id }
    private var isDownloaded: Bool { state.models.downloaded.contains(model.id) }
    private var progress: Double? { state.models.progress[model.id] }

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(model.name).font(.headline)
                    if isActive {
                        badge("Active", tint: .accentColor)
                    }
                    badge(model.engine.title, tint: model.engine == .whisper ? .purple : .teal)
                }
                Text(model.description)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                HStack(spacing: 14) {
                    Label(model.languages, systemImage: "globe")
                    Label(model.sizeText, systemImage: "internaldrive")
                    if model.supportsTranslation {
                        Label("Translate → EN", systemImage: "arrow.left.arrow.right")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                HStack(spacing: 18) {
                    ScoreBar(title: "Accuracy", value: model.accuracy)
                    ScoreBar(title: "Speed", value: model.speed)
                }
                if let progress {
                    ProgressView(value: progress) {
                        Text("Downloading… \(Int(progress * 100))%").font(.caption)
                    }
                }
                if let error = state.models.errors[model.id] {
                    Text(error).font(.caption).foregroundStyle(.red).lineLimit(3)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            action
        }
        .padding(16)
        .glassEffect(
            isActive ? .regular.tint(.accentColor.opacity(0.18)).interactive() : .regular.interactive(),
            in: .rect(cornerRadius: 20)
        )
        .contentShape(.rect(cornerRadius: 20))
        .onTapGesture { if progress == nil { state.use(model) } }
        .contextMenu {
            if isDownloaded {
                Button("Use This Model") { state.use(model) }
                Button("Delete Download", role: .destructive) { confirmDelete = true }
            }
        }
        .confirmationDialog("Delete \(model.name)?", isPresented: $confirmDelete) {
            Button("Delete", role: .destructive) { state.models.delete(model) }
        } message: {
            Text("Frees \(model.sizeText). You can download it again at any time.")
        }
        .animation(.smooth, value: progress != nil)
        .animation(.smooth, value: isActive)
    }

    @ViewBuilder private var action: some View {
        if progress != nil {
            Button("Cancel") { state.models.cancelDownload(model) }
                .buttonStyle(.glass)
        } else if isActive, isDownloaded {
            Image(systemName: "checkmark.circle.fill")
                .font(.title2)
                .foregroundStyle(Color.accentColor)
        } else if isDownloaded {
            HStack(spacing: 6) {
                Button("Use") { state.use(model) }
                    .buttonStyle(.glassProminent)
                Button { confirmDelete = true } label: { Image(systemName: "trash") }
                    .buttonStyle(.glass)
                    .disabled(state.queue.isRunning && isActive)
                    .help("Delete download")
            }
        } else {
            Button { state.use(model) } label: {
                Label("Download", systemImage: "arrow.down.circle")
            }
            .buttonStyle(.glassProminent)
        }
    }

    private func badge(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .glassEffect(.regular.tint(tint.opacity(0.35)), in: .capsule)
    }
}

struct ScoreBar: View {
    let title: String
    let value: Double

    var body: some View {
        HStack(spacing: 6) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            HStack(spacing: 2) {
                ForEach(0..<5) { i in
                    Capsule()
                        .fill(Double(i) < (value * 5).rounded() ? Color.accentColor : Color.secondary.opacity(0.25))
                        .frame(width: 12, height: 5)
                }
            }
        }
    }
}
