import AppKit
import Foundation

/// Application preferences, verified auto-save directory management, and macOS LaunchAgent auto-start (1:1 port of src/AppSettings.cs).
public enum AppSettings {
    private static let launchAgentLabel = "com.steeefanie.spanshot"
    private static let prefKeyKeepAlive = "SpanShot.KeepInBackground"
    private static let prefKeyQuickCopy = "SpanShot.QuickCopyOnly"
    private static let prefKeyHideStatusBar = "SpanShot.HideStatusBarIcon"

    public struct Preferences {
        public var keepInBackground: Bool = true
        public var hideStatusBarIcon: Bool = false
        public var quickCopyOnly: Bool = false
        public var autoSave: Bool = false
        public var autoSaveDir: String = ""

        public init(
            keepInBackground: Bool = true,
            hideStatusBarIcon: Bool = false,
            quickCopyOnly: Bool = false,
            autoSave: Bool = false,
            autoSaveDir: String = ""
        ) {
            self.keepInBackground = keepInBackground
            self.hideStatusBarIcon = hideStatusBarIcon
            self.quickCopyOnly = quickCopyOnly
            self.autoSave = autoSave
            self.autoSaveDir = autoSaveDir
        }
    }

    private static var settingsFilePath: String {
        let baseDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?.path
            ?? (NSHomeDirectory() as NSString).appendingPathComponent("Library/Application Support")
        let dir = (baseDir as NSString).appendingPathComponent("SpanShot")
        return (dir as NSString).appendingPathComponent("settings.ini")
    }

    private static var launchAgentPlistPath: String {
        let agentsDir = (NSHomeDirectory() as NSString).appendingPathComponent("Library/LaunchAgents")
        return (agentsDir as NSString).appendingPathComponent("\(launchAgentLabel).plist")
    }

    public static func loadPreferences() -> Preferences {
        var prefs = Preferences()

        // Migrate / fallback from UserDefaults if present
        let defaults = UserDefaults.standard
        if defaults.object(forKey: prefKeyKeepAlive) != nil {
            prefs.keepInBackground = defaults.bool(forKey: prefKeyKeepAlive)
        }
        if defaults.object(forKey: prefKeyHideStatusBar) != nil {
            prefs.hideStatusBarIcon = defaults.bool(forKey: prefKeyHideStatusBar)
        }
        if defaults.object(forKey: prefKeyQuickCopy) != nil {
            prefs.quickCopyOnly = defaults.bool(forKey: prefKeyQuickCopy)
        }

        let path = settingsFilePath
        if FileManager.default.fileExists(atPath: path),
           let content = try? String(contentsOfFile: path, encoding: .utf8) {
            let lines = content.components(separatedBy: .newlines)
            for rawLine in lines {
                let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
                if line.isEmpty || line.hasPrefix("#") { continue }
                guard let eqIdx = line.firstIndex(of: "=") else { continue }
                let key = line[..<eqIdx].trimmingCharacters(in: .whitespaces).lowercased()
                let val = line[line.index(after: eqIdx)...].trimmingCharacters(in: .whitespaces)
                switch key {
                case "keepinbackground":
                    prefs.keepInBackground = parseBool(val, defaultVal: true)
                case "hidestatusbaricon":
                    prefs.hideStatusBarIcon = parseBool(val, defaultVal: false)
                case "quickcopyonly":
                    prefs.quickCopyOnly = parseBool(val, defaultVal: false)
                case "autosave":
                    prefs.autoSave = parseBool(val, defaultVal: false)
                case "autosavedir":
                    prefs.autoSaveDir = val
                default:
                    break
                }
            }
        }

        // Verify directory permissions on load; disable autoSave if folder was deleted or became unwritable
        if prefs.autoSave && !validateWritableFolder(prefs.autoSaveDir) {
            prefs.autoSave = false
        }

        return prefs
    }

    public static func savePreferences(
        keepInBackground: Bool,
        hideStatusBarIcon: Bool = false,
        quickCopyOnly: Bool,
        autoSave: Bool,
        autoSaveDir: String
    ) {
        let defaults = UserDefaults.standard
        defaults.set(keepInBackground, forKey: prefKeyKeepAlive)
        defaults.set(hideStatusBarIcon, forKey: prefKeyHideStatusBar)
        defaults.set(quickCopyOnly, forKey: prefKeyQuickCopy)

        let path = settingsFilePath
        let dir = (path as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)

        let lines = [
            "keepInBackground=\(keepInBackground ? "1" : "0")",
            "hideStatusBarIcon=\(hideStatusBarIcon ? "1" : "0")",
            "quickCopyOnly=\(quickCopyOnly ? "1" : "0")",
            "autoSave=\(autoSave ? "1" : "0")",
            "autoSaveDir=\(autoSaveDir)"
        ]
        let text = lines.joined(separator: "\n") + "\n"
        try? text.write(toFile: path, atomically: true, encoding: .utf8)
    }

    private static func parseBool(_ val: String, defaultVal: Bool) -> Bool {
        let v = val.lowercased()
        if v == "1" || v == "true" { return true }
        if v == "0" || v == "false" { return false }
        return defaultVal
    }

    /// Strict folder write-permission check:
    /// Verifies the directory exists and is genuinely writable by creating, flushing, and deleting a probe file.
    public static func validateWritableFolder(_ folderPath: String) -> Bool {
        let trimmed = folderPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: trimmed, isDirectory: &isDir), isDir.boolValue else {
            return false
        }

        let probeName = ".spanshot_write_check_\(UUID().uuidString.replacingOccurrences(of: "-", with: "")).tmp"
        let probePath = (trimmed as NSString).appendingPathComponent(probeName)
        let probeData = Data([0x53])

        do {
            try probeData.write(to: URL(fileURLWithPath: probePath), options: .atomic)
            try fm.removeItem(atPath: probePath)
            return true
        } catch {
            try? fm.removeItem(atPath: probePath)
            return false
        }
    }

    /// Saves a bitmap to the user's configured auto-save directory without overwriting existing files.
    @discardableResult
    public static func tryAutoSaveBitmap(_ bmp: RawBitmap, folderPath: String, tag: String) -> String? {
        guard validateWritableFolder(folderPath) else { return nil }
        let safeTag = tag.isEmpty ? "Shot" : tag

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let baseName = "SpanShot_\(safeTag)_\(formatter.string(from: Date()))"
        var fullPath = (folderPath as NSString).appendingPathComponent("\(baseName).png")
        var suffix = 1
        let fm = FileManager.default

        while fm.fileExists(atPath: fullPath) {
            fullPath = (folderPath as NSString).appendingPathComponent("\(baseName)_\(suffix).png")
            suffix += 1
        }

        guard let pngData = bmp.pngData() else { return nil }
        do {
            try pngData.write(to: URL(fileURLWithPath: fullPath), options: .atomic)
            if let attrs = try? fm.attributesOfItem(atPath: fullPath),
               let fileSize = attrs[.size] as? UInt64,
               fileSize > 0 {
                return fullPath
            }
            return nil
        } catch {
            return nil
        }
    }

    /// Prompts the user to pick a directory for auto-saving screenshots.
    public static func pickFolderDialog(currentDir: String) -> String? {
        let panel = NSOpenPanel()
        panel.title = "选择截图自动保存目录"
        panel.message = "请选择用于自动保存 SpanShot 截图的文件夹（需具备写入权限）"
        panel.prompt = "选择文件夹"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.level = .modalPanel

        var isDir: ObjCBool = false
        if !currentDir.isEmpty && FileManager.default.fileExists(atPath: currentDir, isDirectory: &isDir) && isDir.boolValue {
            panel.directoryURL = URL(fileURLWithPath: currentDir)
        } else if let picturesURL = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first {
            panel.directoryURL = picturesURL
        }

        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK, let url = panel.url {
            return url.path
        }
        return nil
    }

    private static var currentExecutablePath: String {
        if let execPath = Bundle.main.executablePath, !execPath.isEmpty {
            return execPath
        }
        return CommandLine.arguments.first ?? "/Applications/SpanShot.app/Contents/MacOS/SpanShot"
    }

    public static func isAutoStartEnabled() -> Bool {
        let plistPath = launchAgentPlistPath
        guard FileManager.default.fileExists(atPath: plistPath),
              let dict = NSDictionary(contentsOfFile: plistPath) else {
            return false
        }
        if let runAtLoad = dict["RunAtLoad"] as? Bool {
            return runAtLoad
        }
        return true
    }

    @discardableResult
    public static func setAutoStart(_ enabled: Bool) -> Bool {
        let plistPath = launchAgentPlistPath
        let fm = FileManager.default
        if enabled {
            let agentsDir = (plistPath as NSString).deletingLastPathComponent
            do {
                try fm.createDirectory(atPath: agentsDir, withIntermediateDirectories: true)
                let execPath = currentExecutablePath
                let plistDict: [String: Any] = [
                    "Label": launchAgentLabel,
                    "ProgramArguments": [execPath, "--autostart"],
                    "RunAtLoad": true,
                    "ProcessType": "Interactive"
                ]
                let data = try PropertyListSerialization.data(fromPropertyList: plistDict, format: .xml, options: 0)
                try data.write(to: URL(fileURLWithPath: plistPath), options: .atomic)
                return true
            } catch {
                return false
            }
        } else {
            if fm.fileExists(atPath: plistPath) {
                do {
                    try fm.removeItem(atPath: plistPath)
                } catch {
                    return false
                }
            }
            return true
        }
    }

    /// Updates the LaunchAgent executable path if the user moved `SpanShot.app` while auto-start is enabled.
    public static func syncAutoStartPathIfEnabled() {
        if isAutoStartEnabled() {
            _ = setAutoStart(true)
        }
    }
}
