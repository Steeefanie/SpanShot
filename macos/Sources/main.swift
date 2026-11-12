import AppKit
import Foundation

let args = CommandLine.arguments
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
        setupMainMenu(mainForm: form)

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

    private func setupMainMenu(mainForm: MainForm) {
        let mainMenu = NSMenu()

        // 1. Application Menu
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenuItem.submenu = appMenu

        let aboutItem = NSMenuItem(
            title: "关于 SpanShot",
            action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
            keyEquivalent: ""
        )
        appMenu.addItem(aboutItem)
        appMenu.addItem(.separator())

        let captureItem = NSMenuItem(title: "开始截图", action: #selector(MainForm.onMenuCapture), keyEquivalent: "A")
        captureItem.keyEquivalentModifierMask = [.command, .shift]
        captureItem.target = mainForm
        appMenu.addItem(captureItem)

        let vScrollItem = NSMenuItem(title: "纵向长截图", action: #selector(MainForm.onMenuVerticalScroll), keyEquivalent: "")
        vScrollItem.target = mainForm
        appMenu.addItem(vScrollItem)

        let hScrollItem = NSMenuItem(title: "横向长截图", action: #selector(MainForm.onMenuHorizontalScroll), keyEquivalent: "")
        hScrollItem.target = mainForm
        appMenu.addItem(hScrollItem)

        appMenu.addItem(.separator())

        let hideItem = NSMenuItem(title: "隐藏 SpanShot", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(hideItem)

        let quitItem = NSMenuItem(title: "退出 SpanShot", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenu.addItem(quitItem)

        // 2. Edit Menu (enables ⌘C / ⌘V / ⌘X / ⌘A / ⌘Z in NSSavePanel and editors)
        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)
        let editMenu = NSMenu(title: "编辑")
        editMenuItem.submenu = editMenu

        editMenu.addItem(withTitle: "撤销", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "复制", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        // 3. Window Menu
        let windowMenuItem = NSMenuItem()
        mainMenu.addItem(windowMenuItem)
        let windowMenu = NSMenu(title: "窗口")
        windowMenuItem.submenu = windowMenu

        let showMainItem = NSMenuItem(title: "显示主窗口", action: #selector(MainForm.onMenuShowMain), keyEquivalent: "0")
        showMainItem.target = mainForm
        windowMenu.addItem(showMainItem)

        windowMenu.addItem(withTitle: "最小化", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "关闭窗口", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")

        NSApp.mainMenu = mainMenu
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.regular)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
