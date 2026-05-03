import SwiftUI
import AppKit

@main
struct AutoMsgApp: App {
    @StateObject private var appState = AppState()
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            Group {
                if appState.setupComplete {
                    ContentView()
                } else {
                    SetupWizardView()
                }
            }
            .environmentObject(appState)
            .onAppear {
                appDelegate.appState = appState
                if appState.setupComplete {
                    appState.bootstrap()
                }
            }
            .onChange(of: appState.setupComplete) { _, complete in
                if complete {
                    appState.bootstrap()
                }
            }
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 800, height: 600)

        MenuBarExtra("AutoMsg", systemImage: appState.isGlobalEnabled ? "message.fill" : "message") {
            Toggle("Auto-Reply Active", isOn: $appState.isGlobalEnabled)
            Divider()
            Text("Ollama: \(appState.ollamaConnected ? "Connected" : "Disconnected")")
            Text("Monitor: \(appState.monitor.isRunning ? "Running" : "Stopped")")
            Divider()
            Button("Quit AutoMsg") {
                appState.shutdown()
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var appState: AppState?

    func applicationWillTerminate(_ notification: Notification) {
        appState?.shutdown()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }
}
