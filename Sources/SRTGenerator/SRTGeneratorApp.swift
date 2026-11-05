import SwiftUI

@main
enum Entry {
    @MainActor static func main() {
        let args = Array(CommandLine.arguments.dropFirst())
        if args.first == "--cli" {
            Task.detached {
                await CLI.run(Array(args.dropFirst()))
                exit(0)
            }
            dispatchMain()
        } else {
            SRTGeneratorApp.main()
        }
    }
}

struct SRTGeneratorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private var state: AppState { appDelegate.state }

    var body: some Scene {
        WindowGroup("SRT Generator") {
            ContentView()
                .environment(state)
                .frame(minWidth: 760, minHeight: 640)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 920, height: 760)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Add Files…") { state.presentOpenPanel() }
                    .keyboardShortcut("o")
            }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let state = AppState()

    func application(_ application: NSApplication, open urls: [URL]) {
        state.add(urls)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Needed when launched as a bare SwiftPM executable (no bundle).
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
