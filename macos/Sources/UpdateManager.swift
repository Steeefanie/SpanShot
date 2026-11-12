import AppKit
import Foundation

public final class UpdateCheckResult {
    public var success: Bool = false
    public var isNewer: Bool = false
    public var latestVersion: String = ""
    public var tagName: String = ""
    public var downloadUrl: String = ""
    public var htmlUrl: String = ""
    public var errorMessage: String = ""

    public init() {}
}

/// Online update checker and in-app DMG update puller (1:1 port of src/UpdateManager.cs for macOS).
public enum UpdateManager {
    public static let currentVersion = "1.1.0"
    public static let releasesLatestApiUrl = "https://api.github.com/repos/Steeefanie/SpanShot/releases/latest"
    public static let releasesLatestWebUrl = "https://github.com/Steeefanie/SpanShot/releases/latest"
    public static let releasesPageUrl = "https://github.com/Steeefanie/SpanShot/releases"

    private static var preferredMacArchSuffix: String {
        #if arch(arm64)
        return "AppleSilicon.dmg"
        #else
        return "Universal.dmg"
        #endif
    }

    public static func checkForUpdatesAsync(completion: @escaping (UpdateCheckResult) -> Void) {
        DispatchQueue.global(qos: .utility).async {
            let result = checkForUpdatesSync()
            completion(result)
        }
    }

    private static func checkForUpdatesSync() -> UpdateCheckResult {
        let res = UpdateCheckResult()

        guard let apiUrl = URL(string: releasesLatestApiUrl) else {
            res.errorMessage = "检查更新失败"
            return res
        }

        var req = URLRequest(url: apiUrl, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10.0)
        req.httpMethod = "GET"
        req.setValue("SpanShot-Updater/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        let sem = DispatchSemaphore(value: 0)
        var responseData: Data?
        var httpResponse: HTTPURLResponse?
        var requestError: Error?

        let task = URLSession.shared.dataTask(with: req) { data, resp, err in
            responseData = data
            httpResponse = resp as? HTTPURLResponse
            requestError = err
            sem.signal()
        }
        task.resume()
        _ = sem.wait(timeout: .now() + 11.0)

        if let status = httpResponse?.statusCode, status == 200, let data = responseData, !data.isEmpty {
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let tag = (json["tag_name"] as? String) ?? ""
                let htmlUrl = (json["html_url"] as? String) ?? ""
                if !tag.isEmpty {
                    var assetUrls: [String] = []
                    if let assets = json["assets"] as? [[String: Any]] {
                        for asset in assets {
                            if let url = asset["browser_download_url"] as? String, !url.isEmpty {
                                assetUrls.append(url)
                            }
                        }
                    }

                    let chosenDmg = selectBestMacDmgUrl(from: assetUrls, tag: tag)
                    res.tagName = tag
                    res.latestVersion = normalizeVersion(tag)
                    res.htmlUrl = htmlUrl.isEmpty ? releasesPageUrl : htmlUrl
                    res.downloadUrl = chosenDmg
                    res.isNewer = isVersionNewer(candidate: res.latestVersion, current: currentVersion)
                    res.success = true
                    return res
                }
            }
        }

        // Fallback via GitHub web 302 redirect (immune to GitHub REST API rate limits)
        if let fallback = tryCheckViaWebRedirect() {
            return fallback
        }

        if let httpStatus = httpResponse?.statusCode, httpStatus == 403 {
            res.errorMessage = "GitHub 请求受限，请稍后再试"
        } else if requestError != nil {
            res.errorMessage = "网络连接失败，无法访问 GitHub"
        } else {
            res.errorMessage = "检查更新失败"
        }
        return res
    }

    private static func selectBestMacDmgUrl(from urls: [String], tag: String) -> String {
        let dmgUrls = urls.filter { $0.lowercased().hasSuffix(".dmg") }
        #if arch(arm64)
        if let armMatch = dmgUrls.first(where: { $0.localizedCaseInsensitiveContains("AppleSilicon") || $0.localizedCaseInsensitiveContains("arm64") }) {
            return armMatch
        }
        #endif
        if let univMatch = dmgUrls.first(where: { $0.localizedCaseInsensitiveContains("Universal") }) {
            return univMatch
        }
        if let anyDmg = dmgUrls.first {
            return anyDmg
        }
        return "https://github.com/Steeefanie/SpanShot/releases/download/\(tag)/SpanShot_\(tag)_\(preferredMacArchSuffix)"
    }

    private final class NoRedirectDelegate: NSObject, URLSessionTaskDelegate {
        func urlSession(
            _ session: URLSession,
            task: URLSessionTask,
            willPerformHTTPRedirection response: HTTPURLResponse,
            newRequest request: URLRequest,
            completionHandler: @escaping (URLRequest?) -> Void
        ) {
            completionHandler(nil)
        }
    }

    private static func tryCheckViaWebRedirect() -> UpdateCheckResult? {
        guard let url = URL(string: releasesLatestWebUrl) else { return nil }
        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10.0)
        req.httpMethod = "GET"
        req.setValue("SpanShot-Updater/\(currentVersion)", forHTTPHeaderField: "User-Agent")

        let session = URLSession(configuration: .ephemeral, delegate: NoRedirectDelegate(), delegateQueue: nil)
        let sem = DispatchSemaphore(value: 0)
        var locationHeader: String?

        let task = session.dataTask(with: req) { _, resp, _ in
            if let http = resp as? HTTPURLResponse {
                locationHeader = (http.allHeaderFields["Location"] as? String)
                    ?? (http.allHeaderFields["location"] as? String)
            }
            sem.signal()
        }
        task.resume()
        _ = sem.wait(timeout: .now() + 11.0)

        guard let loc = locationHeader, !loc.isEmpty else { return nil }
        let marker = "/releases/tag/"
        guard let range = loc.range(of: marker, options: .caseInsensitive) else { return nil }
        let rawTag = String(loc[range.upperBound...])
        let tag = rawTag.split(whereSeparator: { $0 == "?" || $0 == "#" || $0 == "/" }).first.map(String.init) ?? ""
        guard !tag.isEmpty else { return nil }

        let res = UpdateCheckResult()
        res.tagName = tag
        res.latestVersion = normalizeVersion(tag)
        res.htmlUrl = "https://github.com/Steeefanie/SpanShot/releases/tag/\(tag)"
        res.downloadUrl = "https://github.com/Steeefanie/SpanShot/releases/download/\(tag)/SpanShot_\(tag)_\(preferredMacArchSuffix)"
        res.isNewer = isVersionNewer(candidate: res.latestVersion, current: currentVersion)
        res.success = true
        return res
    }

    public static func pullAndApplyUpdateAsync(
        info: UpdateCheckResult,
        onProgress: @escaping (Int) -> Void,
        onCompleted: @escaping (Bool, String) -> Void
    ) {
        if info.downloadUrl.isEmpty {
            onCompleted(false, "未找到更新包地址")
            return
        }

        DispatchQueue.global(qos: .utility).async {
            do {
                guard let url = URL(string: info.downloadUrl) else {
                    onCompleted(false, "更新包链接无效")
                    return
                }

                let tempDir = (NSTemporaryDirectory() as NSString).appendingPathComponent("SpanShot_Update_\(UUID().uuidString)")
                try FileManager.default.createDirectory(atPath: tempDir, withIntermediateDirectories: true)
                let dmgPath = (tempDir as NSString).appendingPathComponent("SpanShot_Update.dmg")

                onProgress(2)

                let ok = downloadFileWithProgress(url: url, destinationPath: dmgPath, onProgress: onProgress)
                guard ok else {
                    onCompleted(false, "下载失败，请检查网络连接")
                    return
                }

                guard let attrs = try? FileManager.default.attributesOfItem(atPath: dmgPath),
                      let fileSize = attrs[.size] as? UInt64,
                      fileSize > 50 * 1024 else {
                    try? FileManager.default.removeItem(atPath: dmgPath)
                    onCompleted(false, "下载的更新包不完整")
                    return
                }

                onProgress(96)

                // Try mounting the DMG and replacing the current .app bundle if running inside a writable .app
                let bundlePath = Bundle.main.bundlePath
                if bundlePath.hasSuffix(".app") {
                    let parentDir = (bundlePath as NSString).deletingLastPathComponent
                    if AppSettings.validateWritableFolder(parentDir),
                       installDmgIntoAppBundle(dmgPath: dmgPath, targetAppPath: bundlePath, tempDir: tempDir) {
                        onProgress(100)
                        onCompleted(true, "更新完成，正在重启 SpanShot...")
                        return
                    }
                }

                // Fallback: open the downloaded DMG in Finder so the user can drag-install immediately
                onProgress(100)
                DispatchQueue.main.async {
                    NSWorkspace.shared.open(URL(fileURLWithPath: dmgPath))
                }
                onCompleted(true, "已下载并打开最新安装包")
            } catch {
                onCompleted(false, "拉取更新失败")
            }
        }
    }

    private final class DownloadProgressDelegate: NSObject, URLSessionDownloadDelegate {
        var onProgress: ((Int) -> Void)?
        var destinationPath: String = ""
        var succeeded = false
        let semaphore = DispatchSemaphore(value: 0)

        func urlSession(
            _ session: URLSession,
            downloadTask: URLSessionDownloadTask,
            didWriteData bytesWritten: Int64,
            totalBytesWritten: Int64,
            totalBytesExpectedToWrite: Int64
        ) {
            if totalBytesExpectedToWrite > 0 {
                let pct = Int(min(95, max(2, (totalBytesWritten * 95) / totalBytesExpectedToWrite)))
                onProgress?(pct)
            }
        }

        func urlSession(
            _ session: URLSession,
            downloadTask: URLSessionDownloadTask,
            didFinishDownloadingTo location: URL
        ) {
            do {
                if FileManager.default.fileExists(atPath: destinationPath) {
                    try FileManager.default.removeItem(atPath: destinationPath)
                }
                try FileManager.default.moveItem(at: location, to: URL(fileURLWithPath: destinationPath))
                succeeded = true
            } catch {
                succeeded = false
            }
            semaphore.signal()
        }

        func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
            if error != nil {
                succeeded = false
                semaphore.signal()
            }
        }
    }

    private static func downloadFileWithProgress(
        url: URL,
        destinationPath: String,
        onProgress: @escaping (Int) -> Void
    ) -> Bool {
        let delegate = DownloadProgressDelegate()
        delegate.onProgress = onProgress
        delegate.destinationPath = destinationPath

        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 60.0)
        req.setValue("SpanShot-Updater/\(currentVersion)", forHTTPHeaderField: "User-Agent")

        let session = URLSession(configuration: .ephemeral, delegate: delegate, delegateQueue: nil)
        let task = session.downloadTask(with: req)
        task.resume()
        _ = delegate.semaphore.wait(timeout: .now() + 180.0)
        return delegate.succeeded
    }

    private static func installDmgIntoAppBundle(dmgPath: String, targetAppPath: String, tempDir: String) -> Bool {
        let mountPoint = (tempDir as NSString).appendingPathComponent("mnt")
        try? FileManager.default.createDirectory(atPath: mountPoint, withIntermediateDirectories: true)

        let attachProc = Process()
        attachProc.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        attachProc.arguments = ["attach", "-nobrowse", "-readonly", "-mountpoint", mountPoint, dmgPath]
        attachProc.standardOutput = Pipe()
        attachProc.standardError = Pipe()

        do {
            try attachProc.run()
            attachProc.waitUntilExit()
            guard attachProc.terminationStatus == 0 else { return false }
        } catch {
            return false
        }

        let mountedApp = (mountPoint as NSString).appendingPathComponent("SpanShot.app")
        guard FileManager.default.fileExists(atPath: mountedApp) else {
            detachMountPoint(mountPoint)
            return false
        }

        let stagedApp = (tempDir as NSString).appendingPathComponent("SpanShot.app")
        do {
            if FileManager.default.fileExists(atPath: stagedApp) {
                try FileManager.default.removeItem(atPath: stagedApp)
            }
            try FileManager.default.copyItem(atPath: mountedApp, toPath: stagedApp)
        } catch {
            detachMountPoint(mountPoint)
            return false
        }

        detachMountPoint(mountPoint)

        // Spawn helper shell script to swap the .app bundle after current process exits and relaunch
        let pid = ProcessInfo.processInfo.processIdentifier
        let scriptPath = (tempDir as NSString).appendingPathComponent("apply_update.sh")
        let scriptContent = """
        #!/bin/sh
        for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do
            if ! kill -0 \(pid) 2>/dev/null; then
                break
            fi
            sleep 0.3
        done
        rm -rf "\(targetAppPath)"
        mv "\(stagedApp)" "\(targetAppPath)"
        xattr -cr "\(targetAppPath)" 2>/dev/null || true
        open "\(targetAppPath)"
        rm -rf "\(tempDir)"
        """

        do {
            try scriptContent.write(toFile: scriptPath, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptPath)
            let launcher = Process()
            launcher.executableURL = URL(fileURLWithPath: "/bin/sh")
            launcher.arguments = [scriptPath]
            try launcher.run()
            return true
        } catch {
            return false
        }
    }

    private static func detachMountPoint(_ mountPoint: String) {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        proc.arguments = ["detach", mountPoint, "-force"]
        proc.standardOutput = Pipe()
        proc.standardError = Pipe()
        try? proc.run()
        proc.waitUntilExit()
    }

    public static func openReleasesPage(_ url: String? = nil) {
        let target = (url != nil && !url!.isEmpty) ? url! : releasesPageUrl
        if let u = URL(string: target) {
            NSWorkspace.shared.open(u)
        }
    }

    public static func normalizeVersion(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("v") || s.hasPrefix("V") {
            s.removeFirst()
        }
        if let sep = s.firstIndex(where: { $0 == "-" || $0 == "+" }) {
            s = String(s[..<sep])
        }
        return s
    }

    public static func isVersionNewer(candidate: String, current: String) -> Bool {
        let cNorm = normalizeVersion(candidate)
        let curNorm = normalizeVersion(current)
        guard !cNorm.isEmpty else { return false }

        let cParts = cNorm.split(separator: ".").map { Int($0) ?? 0 }
        let curParts = curNorm.split(separator: ".").map { Int($0) ?? 0 }
        let len = max(cParts.count, curParts.count)

        for i in 0..<len {
            let cv = i < cParts.count ? cParts[i] : 0
            let curv = i < curParts.count ? curParts[i] : 0
            if cv > curv { return true }
            if cv < curv { return false }
        }
        return false
    }
}
