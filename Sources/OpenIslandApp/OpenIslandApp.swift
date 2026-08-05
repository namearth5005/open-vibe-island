import AppKit
import SwiftUI

@MainActor
final class OpenIslandAppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    private let harnessLaunchConfiguration = HarnessLaunchConfiguration()
    private let launchedAt = Date()
    private lazy var harnessRuntimeMonitor = HarnessRuntimeMonitor(launchedAt: launchedAt)

    func applicationDidFinishLaunching(_ notification: Notification) {
        ProcessInfo.processInfo.disableAutomaticTermination(
            "Open Island should remain active while monitoring local agent sessions."
        )
        ProcessInfo.processInfo.disableSuddenTermination()
        NSApp.setActivationPolicy(model.showDockIcon ? .regular : .accessory)
        harnessRuntimeMonitor.recordMilestone("applicationDidFinishLaunching")

        DispatchQueue.main.async { [self] in
            harnessRuntimeMonitor.recordMilestone("bootstrapStarted")
            model.harnessRuntimeMonitor = harnessRuntimeMonitor
            harnessRuntimeMonitor.recordLog(model.lastActionMessage)

            // Real launches only. Under a harness scenario the session log would
            // be polluted with synthetic runs, and the back-fill's transcript
            // walk would slow deterministic smoke runs for no benefit.
            if harnessLaunchConfiguration.scenario == nil {
                model.startSessionLogging()
            }

            model.ignoresPointerExitDuringHarness = harnessLaunchConfiguration.scenario != nil
            model.disablesOverlayEventMonitoringDuringHarness = harnessLaunchConfiguration.scenario != nil
            model.startIfNeeded(
                startBridge: harnessLaunchConfiguration.shouldStartBridge,
                shouldPerformBootAnimation: harnessLaunchConfiguration.shouldPerformBootAnimation,
                loadRuntimeState: harnessLaunchConfiguration.scenario == nil
            )
            harnessRuntimeMonitor.recordMilestone("modelStarted")

            if let scenario = harnessLaunchConfiguration.scenario {
                model.loadDebugSnapshot(
                    scenario.snapshot(),
                    presentOverlay: harnessLaunchConfiguration.presentOverlay
                )
            }

            // Hide all windows on launch — settings opens on demand only.
            OpenIslandAppDelegate.hideAllAppWindows()

            harnessRuntimeMonitor.recordMilestone("bootstrapCompleted")

            if let captureDelay = harnessLaunchConfiguration.captureDelay,
               harnessLaunchConfiguration.artifactDirectoryURL != nil {
                harnessRuntimeMonitor.recordMilestone(
                    "captureScheduled",
                    message: String(format: "%.3fs", captureDelay)
                )
                DispatchQueue.main.asyncAfter(deadline: .now() + captureDelay) { [self] in
                    harnessRuntimeMonitor.recordMilestone("captureStarted")
                    try? HarnessArtifactRecorder.record(
                        configuration: harnessLaunchConfiguration,
                        model: model,
                        launchedAt: launchedAt,
                        runtimeMonitor: harnessRuntimeMonitor
                    )
                }
            }

            if let autoExitAfter = harnessLaunchConfiguration.autoExitAfter {
                harnessRuntimeMonitor.recordMilestone(
                    "autoExitScheduled",
                    message: String(format: "%.3fs", autoExitAfter)
                )
                DispatchQueue.main.asyncAfter(deadline: .now() + autoExitAfter) {
                    NSApp.terminate(nil)
                }
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    private static func hideAllAppWindows() {
        for window in NSApp.windows {
            window.orderOut(nil)
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        model.showSettings()
        return false
    }
}

@main
struct OpenIslandApp: App {
    @NSApplicationDelegateAdaptor(OpenIslandAppDelegate.self)
    private var appDelegate

    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        Window("Open Island Settings", id: "settings") {
            SettingsWindowContent(model: appDelegate.model)
        }
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") {
                    openWindow(id: "settings")
                    appDelegate.model.showSettings()
                }
                .keyboardShortcut(",", modifiers: .command)
            }

            // The Window menu, not the app menu: this is a window you bring
            // forward, and it is where macOS users look for one.
            CommandGroup(before: .windowList) {
                Button(appDelegate.model.lang.t(CompanionWindow.titleKey)) {
                    openWindow(id: CompanionWindow.id)
                    appDelegate.model.showCompanion()
                }
                .keyboardShortcut("0", modifiers: .command)
            }
        }

        Window(CompanionWindow.title, id: CompanionWindow.id) {
            CompanionWindowContent(model: appDelegate.model)
        }
        .windowResizability(.contentMinSize)
        .defaultSize(
            width: CompanionSurfaceLayout.defaultSize.width,
            height: CompanionSurfaceLayout.defaultSize.height
        )
    }
}

/// Identity of the companion's window, in one place.
///
/// The `title` is the native window title AppKit matches on when
/// `AppModel.showCompanion` brings it forward, so it is deliberately *not*
/// localized — `showSettings` matches its window the same way, and a title that
/// changed with the app language would break the lookup the moment someone
/// switched locale. What the user reads is `titleKey`, on the menu item.
enum CompanionWindow {
    static let id = "companion"
    static let title = "Open Island Companion"
    static let titleKey = "companion.window.title"
}

/// Mirrors `SettingsWindowContent`: re-registers the `openWindow` closure each
/// time the window renders, so the model can reopen it after AppKit has torn
/// the window down.
private struct CompanionWindowContent: View {
    var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        CompanionSurfaceView(model: model)
            .preferredColorScheme(.dark)
            .onAppear {
                model.openCompanionWindow = { [openWindow] in
                    openWindow(id: CompanionWindow.id)
                }
            }
    }
}

/// Refreshes the `openWindow` registration each time the settings
/// window opens, keeping the closure current after window recreation.
private struct SettingsWindowContent: View {
    var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        SettingsView(model: model)
            .onAppear {
                model.openSettingsWindow = { [openWindow] in
                    openWindow(id: "settings")
                }
            }
    }
}
