import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            Tab("Models", systemImage: "cpu") { ModelsSettingsView() }
        }
        .frame(width: 640, height: 620)
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
                        let url = Transcriber.modelFolder(state.model).deletingLastPathComponent()
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
    private var isDownloaded: Bool { state.downloadedModels.contains(model.id) }
    private var progress: Double? { state.modelDownloads[model.id] }

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
                if let error = state.modelDownloadErrors[model.id] {
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
        .onTapGesture { if progress == nil { state.downloadAndUse(model) } }
        .contextMenu {
            if isDownloaded {
                Button("Use This Model") { state.downloadAndUse(model) }
                Button("Delete Download", role: .destructive) { confirmDelete = true }
            }
        }
        .confirmationDialog("Delete \(model.name)?", isPresented: $confirmDelete) {
            Button("Delete", role: .destructive) { state.deleteModel(model) }
        } message: {
            Text("Frees \(model.sizeText). You can download it again at any time.")
        }
        .animation(.smooth, value: progress != nil)
        .animation(.smooth, value: isActive)
    }

    @ViewBuilder private var action: some View {
        if progress != nil {
            Button("Cancel") { state.cancelDownload(model) }
                .buttonStyle(.glass)
        } else if isActive && isDownloaded {
            Image(systemName: "checkmark.circle.fill")
                .font(.title2)
                .foregroundStyle(Color.accentColor)
        } else if isDownloaded {
            HStack(spacing: 6) {
                Button("Use") { state.downloadAndUse(model) }
                    .buttonStyle(.glassProminent)
                Button { confirmDelete = true } label: { Image(systemName: "trash") }
                    .buttonStyle(.glass)
                    .disabled(state.isRunning && isActive)
                    .help("Delete download")
            }
        } else {
            Button { state.downloadAndUse(model) } label: {
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
