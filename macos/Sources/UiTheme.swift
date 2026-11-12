import AppKit
import CoreGraphics
import Foundation

public enum UiTheme {
    // Dynamic system theme detection (auto-syncs with macOS Light / Dark mode, 1:1 with src/UiTheme.cs)
    public private(set) static var isDarkMode: Bool = detectSystemDarkMode()

    public static func refreshSystemTheme() {
        isDarkMode = detectSystemDarkMode()
    }

    private static func detectSystemDarkMode() -> Bool {
        if let app = NSApp {
            let match = app.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua])
            return match == .darkAqua
        }
        let style = UserDefaults.standard.string(forKey: "AppleInterfaceStyle") ?? ""
        return style.caseInsensitiveCompare("Dark") == .orderedSame
    }

    // Primary brand & action accents
    public static let weChatGreen = NSColor(srgbRed: 0 / 255.0, green: 122 / 255.0, blue: 255 / 255.0, alpha: 1.0)      // #007AFF
    public static var linkBlue: NSColor {
        return isDarkMode
            ? NSColor(srgbRed: 56 / 255.0, green: 152 / 255.0, blue: 255 / 255.0, alpha: 1.0)
            : NSColor(srgbRed: 0 / 255.0, green: 112 / 255.0, blue: 240 / 255.0, alpha: 1.0)
    }
    public static let hollowBorderGreen = NSColor(srgbRed: 7 / 255.0, green: 193 / 255.0, blue: 96 / 255.0, alpha: 1.0) // #07C160

    // Adaptive surface & border tokens (modeled after tokens.css)
    public static var bgDark: NSColor {
        return isDarkMode
            ? NSColor(srgbRed: 17 / 255.0, green: 17 / 255.0, blue: 17 / 255.0, alpha: 1.0)       // #111111
            : NSColor(srgbRed: 250 / 255.0, green: 250 / 255.0, blue: 250 / 255.0, alpha: 1.0)    // #FAFAFA
    }
    public static var toolbarBg: NSColor {
        return isDarkMode
            ? NSColor(srgbRed: 29 / 255.0, green: 29 / 255.0, blue: 29 / 255.0, alpha: 1.0)       // #1D1D1D
            : NSColor(srgbRed: 255 / 255.0, green: 255 / 255.0, blue: 255 / 255.0, alpha: 1.0)    // #FFFFFF
    }
    public static var toolbarHover: NSColor {
        return isDarkMode
            ? NSColor(srgbRed: 38 / 255.0, green: 38 / 255.0, blue: 38 / 255.0, alpha: 1.0)       // #262626
            : NSColor(srgbRed: 236 / 255.0, green: 236 / 255.0, blue: 236 / 255.0, alpha: 1.0)    // #ECECEC
    }
    public static var toolbarBorder: NSColor {
        return isDarkMode
            ? NSColor(srgbRed: 51 / 255.0, green: 51 / 255.0, blue: 51 / 255.0, alpha: 1.0)       // #333333
            : NSColor(srgbRed: 217 / 255.0, green: 217 / 255.0, blue: 217 / 255.0, alpha: 1.0)    // #D9D9D9
    }
    public static var dividerColor: NSColor { return toolbarBorder }
    public static var bgCard: NSColor {
        return isDarkMode
            ? NSColor(srgbRed: 29 / 255.0, green: 29 / 255.0, blue: 29 / 255.0, alpha: 1.0)       // #1D1D1D
            : NSColor(srgbRed: 243 / 255.0, green: 243 / 255.0, blue: 243 / 255.0, alpha: 1.0)    // #F3F3F3
    }
    public static var bgCardHover: NSColor { return toolbarHover }
    public static var bgPill: NSColor { return bgCard }
    public static var canvasBg: NSColor {
        return isDarkMode
            ? NSColor(srgbRed: 26 / 255.0, green: 26 / 255.0, blue: 26 / 255.0, alpha: 1.0)       // #1A1A1A
            : NSColor(srgbRed: 243 / 255.0, green: 243 / 255.0, blue: 243 / 255.0, alpha: 1.0)    // #F3F3F3
    }
    public static var borderSubtle: NSColor { return toolbarBorder }

    public static let accentBlue = NSColor(srgbRed: 0 / 255.0, green: 122 / 255.0, blue: 255 / 255.0, alpha: 1.0)       // #007AFF
    public static let accentTeal = NSColor(srgbRed: 10 / 255.0, green: 132 / 255.0, blue: 255 / 255.0, alpha: 1.0)      // #0A84FF
    public static let accentGreen = NSColor(srgbRed: 0 / 255.0, green: 122 / 255.0, blue: 255 / 255.0, alpha: 1.0)      // #007AFF
    public static let accentOrange = NSColor(srgbRed: 255 / 255.0, green: 159 / 255.0, blue: 10 / 255.0, alpha: 1.0)    // #FF9F0A
    public static let accentRed = NSColor(srgbRed: 255 / 255.0, green: 69 / 255.0, blue: 58 / 255.0, alpha: 1.0)        // #FF453A
    public static let accentPurple = NSColor(srgbRed: 94 / 255.0, green: 92 / 255.0, blue: 230 / 255.0, alpha: 1.0)     // #5E5CE6

    public static var textPrimary: NSColor {
        return isDarkMode
            ? NSColor(srgbRed: 238 / 255.0, green: 238 / 255.0, blue: 238 / 255.0, alpha: 1.0)    // #EEEEEE
            : NSColor(srgbRed: 34 / 255.0, green: 34 / 255.0, blue: 34 / 255.0, alpha: 1.0)       // #222222
    }
    public static var textSecondary: NSColor {
        return NSColor(srgbRed: 136 / 255.0, green: 136 / 255.0, blue: 136 / 255.0, alpha: 1.0)   // #888888
    }

    // Annotation color swatches (Apple System Colors)
    public static let annotColors: [NSColor] = [
        NSColor(srgbRed: 255 / 255.0, green: 59 / 255.0, blue: 48 / 255.0, alpha: 1.0),   // Apple Red #FF3B30
        NSColor(srgbRed: 255 / 255.0, green: 204 / 255.0, blue: 0 / 255.0, alpha: 1.0),   // Apple Yellow #FFCC00
        NSColor(srgbRed: 52 / 255.0, green: 199 / 255.0, blue: 89 / 255.0, alpha: 1.0),   // Apple Green #34C759
        NSColor(srgbRed: 0 / 255.0, green: 122 / 255.0, blue: 255 / 255.0, alpha: 1.0),   // Apple Blue #007AFF
        NSColor(srgbRed: 255 / 255.0, green: 255 / 255.0, blue: 255 / 255.0, alpha: 1.0)  // White #FFFFFF
    ]

    public static func fontPx(_ size: CGFloat, bold: Bool = false) -> NSFont {
        return bold ? NSFont.boldSystemFont(ofSize: size) : NSFont.systemFont(ofSize: size, weight: .regular)
    }

    public static func lighten(_ c: NSColor, delta: Int) -> NSColor {
        guard let rgb = c.usingColorSpace(.sRGB) else { return c }
        let d = CGFloat(delta) / 255.0
        return NSColor(
            srgbRed: min(1.0, max(0.0, rgb.redComponent + d)),
            green: min(1.0, max(0.0, rgb.greenComponent + d)),
            blue: min(1.0, max(0.0, rgb.blueComponent + d)),
            alpha: rgb.alphaComponent
        )
    }

    public static func adjustHoverFill(_ baseColor: NSColor) -> NSColor {
        guard let rgb = baseColor.usingColorSpace(.sRGB) else { return baseColor }
        if rgb.alphaComponent == 0 { return baseColor }
        let r = Int((rgb.redComponent * 255.0).rounded())
        let g = Int((rgb.greenComponent * 255.0).rounded())
        let b = Int((rgb.blueComponent * 255.0).rounded())
        let lum = r * 2 + g * 5 + b
        return lum > 600 ? lighten(baseColor, delta: -12) : lighten(baseColor, delta: 16)
    }

    public static func fillRoundedRect(_ rect: NSRect, radius: CGFloat, color: NSColor) {
        guard rect.width > 0 && rect.height > 0, let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.saveGState()
        ctx.setFillColor(color.cgColor)
        ctx.addPath(AppIconRenderer.continuousRoundedRectPath(rect: rect, radius: radius))
        ctx.fillPath()
        ctx.restoreGState()
    }

    public static func strokeRoundedRect(_ rect: NSRect, radius: CGFloat, color: NSColor, lineWidth: CGFloat = 1.0) {
        guard rect.width > 0 && rect.height > 0, let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.saveGState()
        ctx.setStrokeColor(color.cgColor)
        ctx.setLineWidth(lineWidth)
        ctx.addPath(AppIconRenderer.continuousRoundedRectPath(rect: rect, radius: radius))
        ctx.strokePath()
        ctx.restoreGState()
    }

    /// Fills and strokes a continuous rounded rectangle by clipping to the outer silhouette so that
    /// the fill and border share the exact same outer edge with zero corner bleed or double-border ghosting.
    public static func fillAndStrokeRoundedRect(
        _ rect: NSRect,
        radius: CGFloat,
        fillColor: NSColor,
        strokeColor: NSColor,
        lineWidth: CGFloat = 1.0
    ) {
        guard rect.width > 0 && rect.height > 0, let ctx = NSGraphicsContext.current?.cgContext else { return }
        let path = AppIconRenderer.continuousRoundedRectPath(rect: rect, radius: radius)
        ctx.saveGState()
        ctx.addPath(path)
        ctx.clip()
        ctx.setFillColor(fillColor.cgColor)
        ctx.fill(rect)
        if lineWidth > 0 {
            ctx.setStrokeColor(strokeColor.cgColor)
            ctx.setLineWidth(lineWidth * 2.0)
            ctx.addPath(path)
            ctx.strokePath()
        }
        ctx.restoreGState()
    }

    public static func drawCenteredText(
        _ text: String,
        in rect: NSRect,
        font: NSFont,
        color: NSColor,
        alignment: NSTextAlignment = .center,
        lineBreakMode: NSLineBreakMode = .byClipping
    ) {
        let style = NSMutableParagraphStyle()
        style.alignment = alignment
        style.lineBreakMode = lineBreakMode
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: style
        ]
        let size = (text as NSString).size(withAttributes: attrs)
        let drawRect = NSRect(
            x: rect.origin.x,
            y: rect.origin.y + (rect.height - size.height) / 2.0,
            width: rect.width,
            height: size.height + 2.0
        )
        (text as NSString).draw(in: drawRect, withAttributes: attrs)
    }

    public static func drawPillButton(
        rect: NSRect,
        text: String,
        baseColor: NSColor,
        hovered: Bool,
        activeBorder: Bool = false,
        radius: CGFloat = 4.0,
        font: NSFont? = nil,
        textColor: NSColor? = nil
    ) {
        guard rect.width > 0 && rect.height > 0 else { return }
        let fill = hovered ? adjustHoverFill(baseColor) : baseColor
        if fill.alphaComponent > 0.01 {
            fillRoundedRect(rect, radius: radius, color: fill)
        }
        if activeBorder {
            strokeRoundedRect(rect.insetBy(dx: 1, dy: 1), radius: radius, color: weChatGreen, lineWidth: 1.5)
        }
        let f = font ?? fontPx(13, bold: false)
        drawCenteredText(text, in: rect, font: f, color: textColor ?? textPrimary)
    }

    // Toolbar Vector Icons (expects flipped view coordinates where y increases downward, matching src/UiTheme.cs)
    public static func drawIconRect(btnRect: NSRect, color: NSColor) {
        let w: CGFloat = 16
        let h: CGFloat = 13
        let x = btnRect.origin.x + (btnRect.width - w) / 2
        let y = btnRect.origin.y + (btnRect.height - h) / 2
        color.setStroke()
        let path = NSBezierPath(rect: NSRect(x: x, y: y, width: w, height: h))
        path.lineWidth = 1.6
        path.stroke()
    }

    public static func drawIconArrow(btnRect: NSRect, color: NSColor) {
        let s: CGFloat = 14
        let x0 = btnRect.origin.x + (btnRect.width - s) / 2
        let y0 = btnRect.origin.y + (btnRect.height + s) / 2
        let x1 = x0 + s
        let y1 = y0 - s
        color.setStroke()
        let path = NSBezierPath()
        path.lineWidth = 1.8
        path.lineCapStyle = .round
        path.move(to: NSPoint(x: x0, y: y0))
        path.line(to: NSPoint(x: x1, y: y1))
        path.move(to: NSPoint(x: x1 - 6, y: y1))
        path.line(to: NSPoint(x: x1, y: y1))
        path.move(to: NSPoint(x: x1, y: y1 + 6))
        path.line(to: NSPoint(x: x1, y: y1))
        path.stroke()
    }

    public static func drawIconPen(btnRect: NSRect, color: NSColor) {
        let cx = btnRect.midX
        let cy = btnRect.midY
        let tip = NSPoint(x: cx - 6.5, y: cy + 6.5)
        let c1 = NSPoint(x: cx - 5.0, y: cy + 1.5)
        let t1 = NSPoint(x: cx + 3.0, y: cy - 6.5)
        let t2 = NSPoint(x: cx + 6.5, y: cy - 3.0)
        let c2 = NSPoint(x: cx - 1.5, y: cy + 5.0)

        color.setStroke()
        let path = NSBezierPath()
        path.lineWidth = 1.6
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.move(to: tip)
        path.line(to: c1)
        path.line(to: t1)
        path.line(to: t2)
        path.line(to: c2)
        path.close()
        path.move(to: c1)
        path.line(to: c2)
        path.stroke()
    }

    public static func drawIconUndo(btnRect: NSRect, color: NSColor) {
        let cx = btnRect.midX
        let cy = btnRect.midY
        let topY = cy - 2.5
        let botY = cy + 5.5
        let arcR = (botY - topY) / 2.0
        let leftX = cx - 5.5
        let rightLineEnd = cx + 1.5

        color.setStroke()
        let path = NSBezierPath()
        path.lineWidth = 1.7
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.move(to: NSPoint(x: leftX, y: topY))
        path.line(to: NSPoint(x: rightLineEnd, y: topY))
        path.appendArc(
            withCenter: NSPoint(x: rightLineEnd, y: topY + arcR),
            radius: arcR,
            startAngle: -90,
            endAngle: 90,
            clockwise: false
        )
        path.line(to: NSPoint(x: cx - 2.5, y: botY))

        path.move(to: NSPoint(x: leftX + 3.5, y: topY - 3.5))
        path.line(to: NSPoint(x: leftX, y: topY))
        path.line(to: NSPoint(x: leftX + 3.5, y: topY + 3.5))
        path.stroke()
    }

    public static func drawIconPin(btnRect: NSRect, color: NSColor) {
        let cx = btnRect.midX
        let cy = btnRect.midY
        color.setStroke()
        let path = NSBezierPath()
        path.lineWidth = 1.7
        path.lineCapStyle = .round
        path.appendRect(NSRect(x: cx - 4, y: cy - 6, width: 8, height: 6))
        path.move(to: NSPoint(x: cx - 6, y: cy))
        path.line(to: NSPoint(x: cx + 6, y: cy))
        path.move(to: NSPoint(x: cx, y: cy))
        path.line(to: NSPoint(x: cx, y: cy + 6))
        path.stroke()
    }

    public static func drawIconSave(btnRect: NSRect, color: NSColor) {
        let cx = btnRect.midX
        let cy = btnRect.midY
        color.setStroke()
        let path = NSBezierPath()
        path.lineWidth = 1.8
        path.lineCapStyle = .round
        path.move(to: NSPoint(x: cx, y: cy - 6))
        path.line(to: NSPoint(x: cx, y: cy + 3))
        path.move(to: NSPoint(x: cx - 4, y: cy - 1))
        path.line(to: NSPoint(x: cx, y: cy + 3))
        path.move(to: NSPoint(x: cx + 4, y: cy - 1))
        path.line(to: NSPoint(x: cx, y: cy + 3))
        path.move(to: NSPoint(x: cx - 6, y: cy + 6))
        path.line(to: NSPoint(x: cx + 6, y: cy + 6))
        path.stroke()
    }

    public static func drawIconClose(btnRect: NSRect, color: NSColor) {
        let r: CGFloat = 5
        let cx = btnRect.midX
        let cy = btnRect.midY
        color.setStroke()
        let path = NSBezierPath()
        path.lineWidth = 1.8
        path.lineCapStyle = .round
        path.move(to: NSPoint(x: cx - r, y: cy - r))
        path.line(to: NSPoint(x: cx + r, y: cy + r))
        path.move(to: NSPoint(x: cx + r, y: cy - r))
        path.line(to: NSPoint(x: cx - r, y: cy + r))
        path.stroke()
    }

    public static func drawIconCheck(btnRect: NSRect, color: NSColor) {
        let cx = btnRect.midX
        let cy = btnRect.midY
        color.setStroke()
        let path = NSBezierPath()
        path.lineWidth = 2.0
        path.lineCapStyle = .round
        path.move(to: NSPoint(x: cx - 6, y: cy))
        path.line(to: NSPoint(x: cx - 2, y: cy + 5))
        path.line(to: NSPoint(x: cx + 7, y: cy - 5))
        path.stroke()
    }

    /// Renders a crisp WeChat-style tapered annotation arrow whose shaft terminates inside the arrowhead base (`neckPt`),
    /// guaranteeing the shaft never protrudes past the sharp arrowhead tip (`endPt`).
    public static func drawAnnotationArrow(from startPt: NSPoint, to endPt: NSPoint, color: NSColor, strokeWidth: CGFloat) {
        let dx = endPt.x - startPt.x
        let dy = endPt.y - startPt.y
        let len = hypot(dx, dy)
        guard len >= 3.0 else { return }

        let angle = atan2(dy, dx)
        let ux = dx / len
        let uy = dy / len
        let nx = -uy
        let ny = ux

        let maxHeadLen = max(11.0, strokeWidth * 3.8)
        let headLen = min(maxHeadLen, max(6.0, len * 0.8))
        let wing: CGFloat = .pi / 6.2

        let a1 = NSPoint(
            x: endPt.x - headLen * cos(angle - wing),
            y: endPt.y - headLen * sin(angle - wing)
        )
        let a2 = NSPoint(
            x: endPt.x - headLen * cos(angle + wing),
            y: endPt.y - headLen * sin(angle + wing)
        )
        let baseDepth = headLen * cos(wing)
        let neckDepth = baseDepth * 0.88
        let neckPt = NSPoint(
            x: endPt.x - neckDepth * ux,
            y: endPt.y - neckDepth * uy
        )

        color.setFill()

        if len > neckDepth + 1.0 {
            let rStart = max(1.0, strokeWidth * 0.35)
            let rEnd = max(1.2, strokeWidth * 0.52)
            let shaft = NSBezierPath()
            shaft.move(to: NSPoint(x: startPt.x + nx * rStart, y: startPt.y + ny * rStart))
            shaft.line(to: NSPoint(x: neckPt.x + nx * rEnd, y: neckPt.y + ny * rEnd))
            shaft.line(to: NSPoint(x: neckPt.x - nx * rEnd, y: neckPt.y - ny * rEnd))
            shaft.line(to: NSPoint(x: startPt.x - nx * rStart, y: startPt.y - ny * rStart))
            shaft.close()
            shaft.fill()

            let tailCap = NSBezierPath(
                ovalIn: NSRect(
                    x: startPt.x - rStart,
                    y: startPt.y - rStart,
                    width: rStart * 2.0,
                    height: rStart * 2.0
                )
            )
            tailCap.fill()
        }

        let head = NSBezierPath()
        head.move(to: endPt)
        head.line(to: a1)
        head.line(to: neckPt)
        head.line(to: a2)
        head.close()
        head.fill()
    }

    public static func copyBitmapToClipboard(_ bmp: RawBitmap) {
        guard let cg = bmp.toCGImage() else { return }
        let rep = NSBitmapImageRep(cgImage: cg)
        rep.size = NSSize(width: bmp.logicalWidth, height: bmp.logicalHeight)
        let pb = NSPasteboard.general
        pb.clearContents()
        if let png = rep.representation(using: .png, properties: [:]) {
            pb.setData(png, forType: .png)
        }
        if let tiff = rep.tiffRepresentation {
            pb.setData(tiff, forType: .tiff)
        }
    }

    public static func copyBitmapWithToast(_ bmp: RawBitmap) {
        copyBitmapToClipboard(bmp)
        ToastWindow.showToast(
            message: String(format: "已复制到剪贴板 (%d × %d)", bmp.width, bmp.height),
            accent: weChatGreen
        )
    }

    @discardableResult
    public static func saveBitmapDialog(_ bmp: RawBitmap, tag: String, initialDir: String = "") -> Bool {
        copyBitmapToClipboard(bmp)
        let panel = NSSavePanel()
        panel.allowedFileTypes = ["png", "jpg"]
        panel.canCreateDirectories = true
        var isDir: ObjCBool = false
        if !initialDir.isEmpty && FileManager.default.fileExists(atPath: initialDir, isDirectory: &isDir) && isDir.boolValue {
            panel.directoryURL = URL(fileURLWithPath: initialDir)
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        panel.nameFieldStringValue = "SpanShot_\(tag)_\(formatter.string(from: Date())).png"
        panel.level = .modalPanel

        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK, let url = panel.url {
            let isJpg = url.pathExtension.lowercased() == "jpg" || url.pathExtension.lowercased() == "jpeg"
            let data = isJpg ? bmp.jpegData() : bmp.pngData()
            if let data = data {
                try? data.write(to: url)
                ToastWindow.showToast(message: "已保存", accent: weChatGreen)
                return true
            }
        }
        return false
    }
}

public final class ToastWindow: NSPanel {
    private static var activeToasts: [ToastWindow] = []
    private var fadeTimer: Timer?
    private var ticks = 0

    private final class ToastView: NSView {
        let message: String
        let accent: NSColor

        init(frame: NSRect, message: String, accent: NSColor) {
            self.message = message
            self.accent = accent
            super.init(frame: frame)
        }

        required init?(coder: NSCoder) { fatalError() }

        override var isFlipped: Bool { true }

        override func draw(_ dirtyRect: NSRect) {
            NSColor.clear.setFill()
            bounds.fill()
            UiTheme.fillAndStrokeRoundedRect(
                bounds,
                radius: 10,
                fillColor: UiTheme.toolbarBg,
                strokeColor: accent,
                lineWidth: 1.0
            )
            UiTheme.drawCenteredText(message, in: bounds, font: UiTheme.fontPx(12), color: UiTheme.textPrimary)
        }
    }

    private init(message: String, accent: NSColor) {
        UiTheme.refreshSystemTheme()
        let font = UiTheme.fontPx(12)
        let textSize = (message as NSString).size(withAttributes: [.font: font])
        let w = max(140.0, ceil(textSize.width) + 32.0)
        let h: CGFloat = 34.0

        let activeScreen = ScreenCapturer.screenContaining(topDownPoint: ScreenCapturer.mouseLocationTopDown()) ?? NSScreen.main
        let screen = activeScreen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let frame = NSRect(
            x: screen.origin.x + (screen.width - w) / 2.0,
            y: screen.maxY - h - 36.0,
            width: w,
            height: h
        )

        super.init(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        self.isOpaque = false
        self.backgroundColor = .clear
        self.level = .statusBar
        self.ignoresMouseEvents = true
        self.hasShadow = true
        self.sharingType = .none
        self.contentView = ToastView(frame: NSRect(x: 0, y: 0, width: w, height: h), message: message, accent: accent)

        self.fadeTimer = Timer.scheduledTimer(withTimeInterval: 0.04, repeats: true) { [weak self] t in
            guard let self = self else { t.invalidate(); return }
            self.ticks += 1
            if self.ticks > 28 {
                self.alphaValue -= 0.09
                if self.alphaValue <= 0.05 {
                    t.invalidate()
                    self.orderOut(nil)
                    ToastWindow.activeToasts.removeAll { $0 === self }
                }
            }
        }
    }

    public static func showToast(message: String, accent: NSColor) {
        DispatchQueue.main.async {
            // Route to inline notice if ResultPreviewForm or MainForm is visible (matching src/UiTheme.cs)
            if ResultPreviewForm.tryShowInlineNotice(message: message, color: accent) {
                return
            }
            if MainForm.tryShowInlineNotice(message: message, color: accent) {
                return
            }
            let toast = ToastWindow(message: message, accent: accent)
            activeToasts.append(toast)
            toast.orderFrontRegardless()
        }
    }
}
