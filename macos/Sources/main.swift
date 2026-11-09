import AppKit
import Foundation

if CommandLine.arguments.contains("--self-test") {
    exit(SelfTestRunner.runAllTests())
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var mainForm: MainForm?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let form = MainForm()
        self.mainForm = form
        NSApp.activate(ignoringOtherApps: true)
        form.makeKeyAndOrderFront(nil)
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
