import AppKit
import Foundation
import SRTCore
import SRTEngines

/// Composition root: the only place that knows which concrete implementations the app uses.
@MainActor
enum LiveDependencies {
    static func make(translation: Bool = true) -> AppDependencies {
        AppDependencies(
            registry: LiveEngines.registry(),
            decoder: AudioLoader(),
            translator: translation ? TranslationBridge() : nil,
            picker: PanelFilePicker(),
            languageTable: WhisperProvider.languageTable
        )
    }
}

/// AppKit open panels behind SRTCore's `FilePicking` protocol.
struct PanelFilePicker: FilePicking {
    func pickMedia() -> [URL] {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.message = "Choose audio or video files (any format)"
        return panel.runModal() == .OK ? panel.urls : []
    }

    func pickFolder() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = "Use Folder"
        return panel.runModal() == .OK ? panel.url : nil
    }
}
