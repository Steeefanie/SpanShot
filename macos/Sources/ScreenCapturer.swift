import AppKit
import CoreGraphics
import Foundation

public enum HorizontalScrollMethod: Int {
    case nativeHWheel = 0
    case plainWheel = 1
    case shiftWheel = 2
    case rightArrowKey = 3
}

public enum ScreenCapturer {
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

    /// Captures a specific rectangle in top-down global screen coordinates.
    /// Windows with sharingType = .none are automatically excluded by the macOS WindowServer.
    public static func captureRegion(_ topDownRect: CGRect) -> RawBitmap {
        let rect = topDownRect.integral
        let w = max(1, Int(rect.width))
        let h = max(1, Int(rect.height))

        if let cgImg = CGWindowListCreateImage(rect, .optionOnScreenOnly, kCGNullWindowID, [.nominalResolution]),
           let bmp = RawBitmap(cgImage: cgImg) {
            if bmp.width == w && bmp.height == h {
                return bmp
            }
            let scaled = RawBitmap(width: w, height: h)
            scaled.drawScaledFrom(src: bmp, srcX: 0, srcY: 0, srcW: bmp.width, srcH: bmp.height, dstX: 0, dstY: 0, dstW: w, dstH: h)
            return scaled
        }

        let fallback = RawBitmap(width: w, height: h)
        fallback.clear(r: 30, g: 30, b: 32)
        return fallback
    }

    /// Enumerates visible application windows in top-down global screen coordinates for auto-snapping in RegionSelector.
    public static func getVisibleWindowRectangles() -> [CGRect] {
        var list: [CGRect] = []
        let myPID = ProcessInfo.processInfo.processIdentifier
        guard let infoList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return list
        }

        for info in infoList {
            if let ownerPID = info[kCGWindowOwnerPID as String] as? pid_t, ownerPID == myPID {
                continue
            }
            let layer = (info[kCGWindowLayer as String] as? Int) ?? 0
            if layer != 0 { continue }
            let alpha = (info[kCGWindowAlpha as String] as? Double) ?? 1.0
            if alpha <= 0.05 { continue }

            if let boundsDict = info[kCGWindowBounds as String] as? NSDictionary,
               let rect = CGRect(dictionaryRepresentation: boundsDict) {
                if rect.width >= 60 && rect.height >= 60 {
                    list.append(rect.integral)
                }
            }
        }
        return list
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
            // Virtual key 124 = Right Arrow on macOS
            if let down = CGEvent(keyboardEventSource: nil, virtualKey: 124, keyDown: true),
               let up = CGEvent(keyboardEventSource: nil, virtualKey: 124, keyDown: false) {
                down.post(tap: .cghidEventTap)
                up.post(tap: .cghidEventTap)
            }
        }
    }
}
