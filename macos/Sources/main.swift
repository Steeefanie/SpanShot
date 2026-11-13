import AppKit
import Foundation

let args = CommandLine.arguments
#if !PRODUCTION_BUILD
if args.contains("--self-test") {
    exit(SelfTestRunner.runAllTests())
}

if let idx = args.firstIndex(of: "--generate-iconset"), idx + 1 < args.count {
    let outDir = args[idx + 1]
    if AppIconRenderer.generateIconset(at: outDir) {
        print("Generated iconset at: \(outDir)")
        exit(0)
    } else {
        fputs("Failed to generate iconset at: \(outDir)\n", stderr)
        exit(1)
    }
}

if let idx = args.firstIndex(of: "--generate-dmg-bg"), idx + 1 < args.count {
    let outDir = args[idx + 1]
    if AppIconRenderer.generateDmgBackground(at: outDir) {
        print("Generated DMG background assets at: \(outDir)")
        exit(0)
    } else {
        fputs("Failed to generate DMG background assets at: \(outDir)\n", stderr)
        exit(1)
    }
}
#endif

let startMinimized = args.contains { arg in
    arg.caseInsensitiveCompare("--autostart") == .orderedSame ||
    arg.caseInsensitiveCompare("--minimized") == .orderedSame
}
let relaunchCapture = args.contains("--relaunch-capture")

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var mainForm: MainForm?

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppSettings.syncAutoStartPathIfEnabled()
        UiTheme.refreshSystemTheme()
        NSApp.applicationIconImage = AppIconRenderer.renderAppIconImage(pointSize: 512, useSystemGridMargin: true)

        let form = MainForm()
        self.mainForm = form
        MainForm.rebuildApplicationMainMenu(mainForm: form)

        if startMinimized {
            form.orderOut(nil)
        } else {
            NSApp.activate(ignoringOtherApps: true)
            form.makeKeyAndOrderFront(nil)
            if relaunchCapture {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                    form.startCaptureFlow(preset: .none)
                }
            }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            mainForm?.onMenuShowMain()
        }
        return true
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.regular)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
