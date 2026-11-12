import AppKit
import CoreGraphics
import CryptoKit
import Foundation
import ScreenCaptureKit

public enum ScreenCapturePermissionState {
    case granted
    case promptedSystemDialog
    case relaunchingWithNewPermission
    case denied
}

public enum HorizontalScrollMethod: Int {
    case nativeHWheel = 0
    case plainWheel = 1
    case shiftWheel = 2
    case rightArrowKey = 3
}

public struct DetectedWindowInfo {
    public let windowID: CGWindowID
    public let ownerPID: pid_t
    public let boundsTopDown: CGRect
    public let zIndex: Int
}

public enum ScreenCapturer {
    private static let captureQueue = DispatchQueue(label: "com.steeefanie.spanshot.screencapture", qos: .userInteractive)
    private static let cacheLock = NSLock()
    private static var cachedShareableContent: SCShareableContent?
    private static var lastContentFetchTime: TimeInterval = 0

    /// Returns the height of the primary screen (used to flip between Cocoa bottom-left and CG top-left coordinates).
    public static var primaryScreenHeight: CGFloat {
        return NSScreen.screens.first?.frame.height ?? 1080.0
    }

    /// Union of all displays in top-down global coordinates (0,0 at top-left of primary display).
    public static var virtualScreenTopDownBounds: CGRect {
        guard !NSScreen.screens.isEmpty else {
            return CGRect(x: 0, y: 0, width: 1440, height: 900)
        }
        var unionRect = CGRect.null
        for scr in NSScreen.screens {
            let td = cocoaToTopDown(scr.frame)
            unionRect = unionRect.isNull ? td : unionRect.union(td)
        }
        return unionRect.integral
    }

    public static func cocoaToTopDown(_ cocoaRect: NSRect) -> CGRect {
        let ph = primaryScreenHeight
        return CGRect(
            x: cocoaRect.origin.x,
            y: ph - cocoaRect.origin.y - cocoaRect.height,
            width: cocoaRect.width,
            height: cocoaRect.height
        )
    }

    public static func topDownToCocoa(_ topDownRect: CGRect) -> NSRect {
        let ph = primaryScreenHeight
        return NSRect(
            x: topDownRect.origin.x,
            y: ph - topDownRect.origin.y - topDownRect.height,
            width: topDownRect.width,
            height: topDownRect.height
        )
    }

    public static func mouseLocationTopDown() -> CGPoint {
        let loc = NSEvent.mouseLocation
        let ph = primaryScreenHeight
        return CGPoint(x: loc.x, y: ph - loc.y)
    }

    /// Returns the `NSScreen` containing the given top-down global point (or the nearest screen if in a multi-monitor gap).
    public static func screenContaining(topDownPoint: CGPoint) -> NSScreen? {
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return NSScreen.main }
        for scr in screens {
            let td = cocoaToTopDown(scr.frame)
            if td.insetBy(dx: -1.0, dy: -1.0).contains(topDownPoint) {
                return scr
            }
        }
        var bestScreen = screens[0]
        var bestDist = CGFloat.greatestFiniteMagnitude
        for scr in screens {
            let td = cocoaToTopDown(scr.frame)
            let dx = max(td.minX - topDownPoint.x, 0, topDownPoint.x - td.maxX)
            let dy = max(td.minY - topDownPoint.y, 0, topDownPoint.y - td.maxY)
            let dist = hypot(dx, dy)
            if dist < bestDist {
                bestDist = dist
                bestScreen = scr
            }
        }
        return bestScreen
    }

    /// Returns the `NSScreen` with the largest intersection with `topDownRect` (or nearest to its center).
    public static func screenContaining(topDownRect: CGRect) -> NSScreen? {
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return NSScreen.main }
        var bestScreen: NSScreen?
        var bestArea: CGFloat = 0
        for scr in screens {
            let td = cocoaToTopDown(scr.frame)
            let inter = td.intersection(topDownRect)
            if !inter.isNull {
                let area = inter.width * inter.height
                if area > bestArea {
                    bestArea = area
                    bestScreen = scr
                }
            }
        }
        if let found = bestScreen {
            return found
        }
        return screenContaining(topDownPoint: CGPoint(x: topDownRect.midX, y: topDownRect.midY))
    }

    /// Full bounds in top-down coordinates of the display containing `topDownPoint`.
    public static func screenTopDownBounds(for topDownPoint: CGPoint) -> CGRect {
        if let scr = screenContaining(topDownPoint: topDownPoint) {
            return cocoaToTopDown(scr.frame).integral
        }
        return virtualScreenTopDownBounds
    }

    /// Visible frame (excluding menu bar & Dock) in top-down coordinates of the display containing `topDownRect`.
    public static func screenVisibleTopDownBounds(for topDownRect: CGRect) -> CGRect {
        if let scr = screenContaining(topDownRect: topDownRect) {
            return cocoaToTopDown(scr.visibleFrame).integral
        }
        let fallback = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        return cocoaToTopDown(fallback).integral
    }

    private static let tccBinaryHashPrefKey = "SpanShot.LastTCCResetBinarySHA256"
    private static var hasRequestedPermissionInProcess = false

    private static func currentExecutableSHA256() -> String {
        guard let execPath = Bundle.main.executablePath,
              let data = try? Data(contentsOf: URL(fileURLWithPath: execPath), options: .mappedIfSafe) else {
            return "unknown"
        }
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func resetStaleTCCIfBinaryChanged() {
        let sha = currentExecutableSHA256()
        let defaults = UserDefaults.standard
        guard defaults.string(forKey: tccBinaryHashPrefKey) != sha else { return }
        defaults.set(sha, forKey: tccBinaryHashPrefKey)

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        proc.arguments = ["reset", "ScreenCapture", "com.steeefanie.spanshot"]
        try? proc.run()
        proc.waitUntilExit()
    }

    private static func relaunchForFreshTCCSession() -> Bool {
        guard let execPath = Bundle.main.executablePath else { return false }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: execPath)
        proc.arguments = ["--relaunch-capture"]
        do {
            try proc.run()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                NSApp.terminate(nil)
            }
            return true
        } catch {
            return false
        }
    }

    /// Checks and requests macOS Screen Recording permission with automatic stale-CDHash recovery
    /// and seamless PID relaunch when the user grants permission in System Settings without restarting.
    public static func checkOrRequestPermissionState() -> ScreenCapturePermissionState {
        if getShareableContent(forceRefresh: true) != nil {
            UserDefaults.standard.set(currentExecutableSHA256(), forKey: tccBinaryHashPrefKey)
            return .granted
        }

        // If binary SHA-256 changed (new build installed over old ad-hoc build), clear the stale CDHash once.
        resetStaleTCCIfBinaryChanged()

        if !hasRequestedPermissionInProcess && !CommandLine.arguments.contains("--relaunch-capture") {
            hasRequestedPermissionInProcess = true
            _ = CGRequestScreenCaptureAccess()
            // Re-check immediately in case access was granted synchronously
            if getShareableContent(forceRefresh: true) != nil {
                return .granted
            }
            return .promptedSystemDialog
        }

        // The user already saw the system prompt (and likely enabled the toggle in System Settings without restarting).
        // Because macOS caches Screen Recording denial per-PID until restart, relaunch once into a fresh PID.
        if !CommandLine.arguments.contains("--relaunch-capture") {
            if relaunchForFreshTCCSession() {
                return .relaunchingWithNewPermission
            }
        }

        return .denied
    }

    public static func openScreenCaptureSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Invalidates cached SCShareableContent so the next capture refreshes the display/window list.
    public static func invalidateShareableContentCache() {
        cacheLock.lock()
        cachedShareableContent = nil
        lastContentFetchTime = 0
        cacheLock.unlock()
    }

    private static func getShareableContent(forceRefresh: Bool = false) -> SCShareableContent? {
        let now = ProcessInfo.processInfo.systemUptime
        cacheLock.lock()
        if !forceRefresh, let cached = cachedShareableContent, (now - lastContentFetchTime) < 2.0 {
            cacheLock.unlock()
            return cached
        }
        cacheLock.unlock()

        let sem = DispatchSemaphore(value: 0)
        var fetched: SCShareableContent?

        captureQueue.async {
            SCShareableContent.getExcludingDesktopWindows(false, onScreenWindowsOnly: true) { content, _ in
                fetched = content
                sem.signal()
            }
        }
        _ = sem.wait(timeout: .now() + 2.0)

        if let content = fetched {
            cacheLock.lock()
            cachedShareableContent = content
            lastContentFetchTime = now
            cacheLock.unlock()
        }
        return fetched
    }

    private static func backingScaleForDisplay(_ displayID: CGDirectDisplayID) -> CGFloat {
        for scr in NSScreen.screens {
            if let num = scr.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
               CGDirectDisplayID(num.uint32Value) == displayID {
                return max(1.0, scr.backingScaleFactor)
            }
        }
        return max(1.0, NSScreen.main?.backingScaleFactor ?? 2.0)
    }

    /// Captures a specific rectangle in top-down global screen coordinates at full native Retina HiDPI quality
    /// using ScreenCaptureKit (`SCScreenshotManager`), automatically excluding SpanShot's own overlay windows.
    public static func captureRegion(_ topDownRect: CGRect) -> RawBitmap {
        let (bmp, _) = captureRegionWithStatus(topDownRect)
        return bmp
    }

    /// Returns `(bitmap, isFallback)` where `isFallback == true` indicates screen capture was blocked by TCC.
    public static func captureRegionWithStatus(_ topDownRect: CGRect) -> (bitmap: RawBitmap, isFallback: Bool) {
        let rect = topDownRect.integral
        let logicalW = max(1.0, rect.width)
        let logicalH = max(1.0, rect.height)
        let fallbackScale = NSScreen.main?.backingScaleFactor ?? 2.0

        // 1. Primary path: ScreenCaptureKit (supports single & multi-display Retina capture)
        if let bmp = captureViaScreenCaptureKit(rect: rect, scaleHint: fallbackScale) {
            return (bmp, false)
        }

        // 2. Retry once with fresh SCShareableContent in case display/window handles changed
        invalidateShareableContentCache()
        if let bmp = captureViaScreenCaptureKit(rect: rect, scaleHint: fallbackScale) {
            return (bmp, false)
        }

        // 3. Fallback: CGWindowListCreateImage ONLY when CGPreflightScreenCaptureAccess() is true
        // (When preflight is false, CGWindowListCreateImage returns a windowless gray wallpaper that hides TCC denial)
        if CGPreflightScreenCaptureAccess(),
           let cgImg = CGWindowListCreateImage(rect, .optionOnScreenOnly, kCGNullWindowID, [.bestResolution]),
           cgImg.width > 0 && cgImg.height > 0 {
            let scaleX = CGFloat(cgImg.width) / logicalW
            let scaleY = CGFloat(cgImg.height) / logicalH
            let scale = max(1.0, (((scaleX + scaleY) * 0.5) * 100.0).rounded() / 100.0)
            if let bmp = RawBitmap(cgImage: cgImg, scaleFactor: scale) {
                return (bmp, false)
            }
        }

        let fallback = RawBitmap(
            width: max(1, Int((logicalW * fallbackScale).rounded())),
            height: max(1, Int((logicalH * fallbackScale).rounded())),
            scaleFactor: fallbackScale
        )
        fallback.clear(r: 30, g: 30, b: 32)
        return (fallback, true)
    }

    private static func captureViaScreenCaptureKit(rect: CGRect, scaleHint: CGFloat) -> RawBitmap? {
        guard let content = getShareableContent(), !content.displays.isEmpty else {
            return nil
        }

        let myPID = ProcessInfo.processInfo.processIdentifier
        let excludedWindows = content.windows.filter { win in
            win.owningApplication?.processID == myPID
        }

        // Find all displays that intersect `rect`
        let intersecting = content.displays.filter { disp in
            let inter = rect.intersection(disp.frame)
            return !inter.isNull && inter.width >= 1 && inter.height >= 1
        }

        guard !intersecting.isEmpty else {
            return nil
        }

        // Fast path: `rect` lies completely within a single display
        if intersecting.count == 1 {
            let disp = intersecting[0]
            let subGlobal = rect.intersection(disp.frame).integral
            if abs(subGlobal.width - rect.width) < 1.5 && abs(subGlobal.height - rect.height) < 1.5 {
                let scale = backingScaleForDisplay(disp.displayID)
                return captureSingleDisplaySlice(
                    display: disp,
                    globalSubRect: subGlobal,
                    scale: scale,
                    excludedWindows: excludedWindows
                )
            }
        }

        // Multi-display composite path (e.g. virtualScreenTopDownBounds across two monitors)
        var maxScale = scaleHint
        for disp in intersecting {
            maxScale = max(maxScale, backingScaleForDisplay(disp.displayID))
        }

        let totalPxW = max(1, Int((rect.width * maxScale).rounded()))
        let totalPxH = max(1, Int((rect.height * maxScale).rounded()))
        let composite = RawBitmap(width: totalPxW, height: totalPxH, scaleFactor: maxScale)
        composite.clear(r: 20, g: 20, b: 22)

        var capturedAny = false
        for disp in intersecting {
            let subGlobal = rect.intersection(disp.frame).integral
            guard subGlobal.width >= 1 && subGlobal.height >= 1 else { continue }
            if let subBmp = captureSingleDisplaySlice(
                display: disp,
                globalSubRect: subGlobal,
                scale: maxScale,
                excludedWindows: excludedWindows
            ) {
                let dstX = Int(((subGlobal.origin.x - rect.origin.x) * maxScale).rounded())
                let dstY = Int(((subGlobal.origin.y - rect.origin.y) * maxScale).rounded())
                composite.copyFrom(
                    src: subBmp,
                    srcX: 0,
                    srcY: 0,
                    dstX: dstX,
                    dstY: dstY,
                    width: subBmp.width,
                    height: subBmp.height
                )
                capturedAny = true
            }
        }

        return capturedAny ? composite : nil
    }

    private static func captureSingleDisplaySlice(
        display: SCDisplay,
        globalSubRect: CGRect,
        scale: CGFloat,
        excludedWindows: [SCWindow]
    ) -> RawBitmap? {
        let dispFrame = display.frame
        let localRect = CGRect(
            x: globalSubRect.origin.x - dispFrame.origin.x,
            y: globalSubRect.origin.y - dispFrame.origin.y,
            width: globalSubRect.width,
            height: globalSubRect.height
        )

        let filter = SCContentFilter(display: display, excludingWindows: excludedWindows)
        let config = SCStreamConfiguration()
        config.sourceRect = localRect
        config.width = max(1, Int((localRect.width * scale).rounded()))
        config.height = max(1, Int((localRect.height * scale).rounded()))
        config.scalesToFit = true
        config.showsCursor = false
        config.captureResolution = .best

        let sem = DispatchSemaphore(value: 0)
        var capturedImage: CGImage?

        captureQueue.async {
            SCScreenshotManager.captureImage(contentFilter: filter, configuration: config) { cgImg, _ in
                capturedImage = cgImg
                sem.signal()
            }
        }
        _ = sem.wait(timeout: .now() + 2.0)

        guard let cgImg = capturedImage, cgImg.width > 0 && cgImg.height > 0 else {
            return nil
        }

        let actualScaleX = CGFloat(cgImg.width) / max(1.0, localRect.width)
        let actualScaleY = CGFloat(cgImg.height) / max(1.0, localRect.height)
        let finalScale = max(1.0, (((actualScaleX + actualScaleY) * 0.5) * 100.0).rounded() / 100.0)
        return RawBitmap(cgImage: cgImg, scaleFactor: finalScale)
    }

    /// Enumerates visible application windows in top-down global screen coordinates (front-to-back Z-order).
    public static func getVisibleWindows() -> [DetectedWindowInfo] {
        var list: [DetectedWindowInfo] = []
        let myPID = ProcessInfo.processInfo.processIdentifier
        if let infoList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] {
            var idx = 0
            for info in infoList {
                let ownerPID = (info[kCGWindowOwnerPID as String] as? pid_t) ?? 0
                if ownerPID == myPID { continue }
                let layer = (info[kCGWindowLayer as String] as? Int) ?? 0
                if layer != 0 { continue }
                let alpha = (info[kCGWindowAlpha as String] as? Double) ?? 1.0
                if alpha <= 0.05 { continue }
                let winID = (info[kCGWindowNumber as String] as? CGWindowID) ?? 0

                if let boundsDict = info[kCGWindowBounds as String] as? NSDictionary,
                   let rect = CGRect(dictionaryRepresentation: boundsDict) {
                    if rect.width >= 60 && rect.height >= 60 {
                        list.append(DetectedWindowInfo(
                            windowID: winID,
                            ownerPID: ownerPID,
                            boundsTopDown: rect.integral,
                            zIndex: idx
                        ))
                        idx += 1
                    }
                }
            }
        }
        if !list.isEmpty {
            return list
        }

        if let content = getShareableContent() {
            var idx = 0
            for win in content.windows {
                let ownerPID = win.owningApplication?.processID ?? 0
                if ownerPID == myPID { continue }
                if win.windowLayer != 0 || !win.isOnScreen { continue }
                let r = win.frame.integral
                if r.width >= 60 && r.height >= 60 {
                    list.append(DetectedWindowInfo(
                        windowID: win.windowID,
                        ownerPID: ownerPID,
                        boundsTopDown: r,
                        zIndex: idx
                    ))
                    idx += 1
                }
            }
        }
        return list
    }

    /// Enumerates visible application window rectangles in top-down global screen coordinates for auto-snapping in RegionSelector.
    public static func getVisibleWindowRectangles() -> [CGRect] {
        return getVisibleWindows().map { $0.boundsTopDown }
    }

    /// Captures a window (plus any attached same-app child sheets/popups above it) using macOS WindowServer's
    /// native `⌘⇧5` window framing (`.null` bounds + `.bestResolution`), preserving the window's exact native
    /// anti-aliased rounded corners and genuine system drop shadow with zero wallpaper bleed.
    public static func captureNativeWindowWithSystemShadow(
        windowInfo: DetectedWindowInfo,
        allDetectedWindows: [DetectedWindowInfo],
        scale: CGFloat
    ) -> RawBitmap? {
        guard windowInfo.windowID != 0 else { return nil }

        // Collect any frontmost child windows/dialogs belonging to the same process that overlap this window
        var windowIDs: [CGWindowID] = allDetectedWindows
            .filter { other in
                other.zIndex < windowInfo.zIndex
                    && other.ownerPID == windowInfo.ownerPID
                    && !other.boundsTopDown.intersection(windowInfo.boundsTopDown).isNull
            }
            .sorted { $0.zIndex < $1.zIndex }
            .map { $0.windowID }
        windowIDs.append(windowInfo.windowID)

        let cgImg: CGImage?
        if windowIDs.count == 1 {
            cgImg = CGWindowListCreateImage(
                .null,
                .optionIncludingWindow,
                windowInfo.windowID,
                [.bestResolution]
            )
        } else {
            cgImg = CGImage(
                windowListFromArrayScreenBounds: .null,
                windowArray: windowIDs as CFArray,
                imageOption: [.bestResolution]
            )
        }

        if let cgImg = cgImg, cgImg.width > 0 && cgImg.height > 0 {
            return RawBitmap(cgImage: cgImg, scaleFactor: scale)
        }

        // Fallback if CGWindowListCreateImage is unavailable: ScreenCaptureKit independent window + shadow
        let pw = max(1, Int((windowInfo.boundsTopDown.width * scale).rounded()))
        let ph = max(1, Int((windowInfo.boundsTopDown.height * scale).rounded()))
        if let isolated = captureIndependentWindow(
            windowID: windowInfo.windowID,
            targetPixelWidth: pw,
            targetPixelHeight: ph,
            scale: scale
        ) {
            return renderWindowWithMacOSShadow(windowBitmap: isolated, cornerRadiusPt: 11.5)
        }
        return nil
    }

    /// Captures a single isolated window (independent of desktop wallpaper and overlapping windows) via ScreenCaptureKit.
    public static func captureIndependentWindow(
        windowID: CGWindowID,
        targetPixelWidth: Int,
        targetPixelHeight: Int,
        scale: CGFloat
    ) -> RawBitmap? {
        guard windowID != 0,
              let content = getShareableContent(),
              let scWin = content.windows.first(where: { $0.windowID == windowID }) else {
            return nil
        }

        let filter = SCContentFilter(desktopIndependentWindow: scWin)
        let config = SCStreamConfiguration()
        config.width = max(1, targetPixelWidth)
        config.height = max(1, targetPixelHeight)
        config.scalesToFit = true
        config.showsCursor = false
        config.ignoreShadowsSingleWindow = true
        config.captureResolution = .best

        let sem = DispatchSemaphore(value: 0)
        var capturedImage: CGImage?

        captureQueue.async {
            SCScreenshotManager.captureImage(contentFilter: filter, configuration: config) { cgImg, _ in
                capturedImage = cgImg
                sem.signal()
            }
        }
        _ = sem.wait(timeout: .now() + 2.0)

        guard let cgImg = capturedImage, cgImg.width > 0 && cgImg.height > 0 else {
            return nil
        }
        return RawBitmap(cgImage: cgImg, scaleFactor: scale)
    }

    /// Composites an isolated window bitmap (which already carries its native WindowServer alpha-masked rounded corners)
    /// onto a transparent RGBA canvas with macOS-grade ambient + contact drop shadows cast directly from the window's
    /// own native alpha channel (no artificial corner clipping or border stroke).
    public static func renderWindowWithMacOSShadow(
        windowBitmap: RawBitmap,
        cornerRadiusPt: CGFloat = 0.0
    ) -> RawBitmap {
        let scale = max(1.0, windowBitmap.scaleFactor)
        let winLogicalW = CGFloat(windowBitmap.width) / scale
        let winLogicalH = CGFloat(windowBitmap.height) / scale

        let padLeftPt: CGFloat = 38.0
        let padRightPt: CGFloat = 38.0
        let padTopPt: CGFloat = 26.0
        let padBottomPt: CGFloat = 50.0

        let totalLogicalW = winLogicalW + padLeftPt + padRightPt
        let totalLogicalH = winLogicalH + padTopPt + padBottomPt
        let totalPxW = max(1, Int((totalLogicalW * scale).rounded()))
        let totalPxH = max(1, Int((totalLogicalH * scale).rounded()))

        let out = RawBitmap(width: totalPxW, height: totalPxH, scaleFactor: scale)
        guard let cgImg = windowBitmap.toCGImage() else { return windowBitmap }

        out.withTopDownCGContext { ctx in
            ctx.scaleBy(x: scale, y: scale)
            ctx.interpolationQuality = .high
            let winRect = CGRect(x: padLeftPt, y: padTopPt, width: winLogicalW, height: winLogicalH)

            // Flip local sub-context for CGContext.draw(_:in:) so the window image is drawn right-side-up
            let drawWindowImage = {
                ctx.saveGState()
                ctx.translateBy(x: winRect.minX, y: winRect.maxY)
                ctx.scaleBy(x: 1.0, y: -1.0)
                ctx.draw(cgImg, in: CGRect(x: 0, y: 0, width: winLogicalW, height: winLogicalH))
                ctx.restoreGState()
            }

            // 1. Crisp contact shadow cast directly from the window's native alpha mask
            ctx.saveGState()
            ctx.setShadow(
                offset: CGSize(width: 0, height: -2.0 * scale),
                blur: 5.0 * scale,
                color: NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.18).cgColor
            )
            drawWindowImage()
            ctx.restoreGState()

            // 2. Ambient soft Gaussian drop shadow + crisp native window pixels on top
            ctx.saveGState()
            ctx.setShadow(
                offset: CGSize(width: 0, height: -12.0 * scale),
                blur: 26.0 * scale,
                color: NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.34).cgColor
            )
            drawWindowImage()
            ctx.restoreGState()
        }
        return out
    }

    public static func warpMouseCursor(topDownPoint: CGPoint) {
        CGWarpMouseCursorPosition(topDownPoint)
        CGAssociateMouseAndMouseCursorPosition(1)
    }

    public static func sendVerticalWheel(wheelDelta: Int32) {
        if let ev = CGEvent(
            scrollWheelEvent2Source: nil,
            units: .pixel,
            wheelCount: 1,
            wheel1: wheelDelta,
            wheel2: 0,
            wheel3: 0
        ) {
            ev.post(tap: .cghidEventTap)
        }
    }

    public static func sendHorizontalScroll(amount: Int32, method: HorizontalScrollMethod) {
        switch method {
        case .nativeHWheel:
            if let ev = CGEvent(
                scrollWheelEvent2Source: nil,
                units: .pixel,
                wheelCount: 2,
                wheel1: 0,
                wheel2: -amount,
                wheel3: 0
            ) {
                ev.post(tap: .cghidEventTap)
            }
        case .plainWheel:
            if let ev = CGEvent(
                scrollWheelEvent2Source: nil,
                units: .pixel,
                wheelCount: 1,
                wheel1: -amount,
                wheel2: 0,
                wheel3: 0
            ) {
                ev.post(tap: .cghidEventTap)
            }
        case .shiftWheel:
            if let ev = CGEvent(
                scrollWheelEvent2Source: nil,
                units: .pixel,
                wheelCount: 1,
                wheel1: -amount,
                wheel2: 0,
                wheel3: 0
            ) {
                ev.flags = .maskShift
                ev.post(tap: .cghidEventTap)
            }
        case .rightArrowKey:
            if let down = CGEvent(keyboardEventSource: nil, virtualKey: 124, keyDown: true),
               let up = CGEvent(keyboardEventSource: nil, virtualKey: 124, keyDown: false) {
                down.post(tap: .cghidEventTap)
                up.post(tap: .cghidEventTap)
            }
        }
    }
}
