import AppKit
import CoreGraphics
import Foundation

public enum UiTheme {
    // Apple UI Blue & macOS Dark Mode Palette (1:1 with src/UiTheme.cs)
    public static let weChatGreen = NSColor(srgbRed: 0 / 255.0, green: 122 / 255.0, blue: 255 / 255.0, alpha: 1.0)      // #007AFF
    public static let hollowBorderGreen = NSColor(srgbRed: 7 / 255.0, green: 193 / 255.0, blue: 96 / 255.0, alpha: 1.0) // #07C160
    public static let toolbarBg = NSColor(srgbRed: 44 / 255.0, green: 44 / 255.0, blue: 46 / 255.0, alpha: 1.0)         // #2C2C2E
    public static let toolbarHover = NSColor(srgbRed: 58 / 255.0, green: 58 / 255.0, blue: 60 / 255.0, alpha: 1.0)      // #3A3A3C
    public static let toolbarBorder = NSColor(srgbRed: 72 / 255.0, green: 72 / 255.0, blue: 74 / 255.0, alpha: 1.0)     // #48484A
    public static let dividerColor = NSColor(srgbRed: 72 / 255.0, green: 72 / 255.0, blue: 74 / 255.0, alpha: 1.0)      // #48484A

    public static let bgDark = NSColor(srgbRed: 28 / 255.0, green: 28 / 255.0, blue: 30 / 255.0, alpha: 1.0)            // #1C1C1E
    public static let bgCard = NSColor(srgbRed: 44 / 255.0, green: 44 / 255.0, blue: 46 / 255.0, alpha: 1.0)            // #2C2C2E
    public static let bgCardHover = NSColor(srgbRed: 58 / 255.0, green: 58 / 255.0, blue: 60 / 255.0, alpha: 1.0)       // #3A3A3C
    public static let bgPill = NSColor(srgbRed: 58 / 255.0, green: 58 / 255.0, blue: 60 / 255.0, alpha: 1.0)            // #3A3A3C
    public static let borderSubtle = NSColor(srgbRed: 72 / 255.0, green: 72 / 255.0, blue: 74 / 255.0, alpha: 1.0)      // #48484A

    public static let accentBlue = NSColor(srgbRed: 0 / 255.0, green: 122 / 255.0, blue: 255 / 255.0, alpha: 1.0)       // #007AFF
    public static let accentTeal = NSColor(srgbRed: 10 / 255.0, green: 132 / 255.0, blue: 255 / 255.0, alpha: 1.0)      // #0A84FF
    public static let accentGreen = NSColor(srgbRed: 0 / 255.0, green: 122 / 255.0, blue: 255 / 255.0, alpha: 1.0)      // #007AFF
    public static let accentOrange = NSColor(srgbRed: 255 / 255.0, green: 159 / 255.0, blue: 10 / 255.0, alpha: 1.0)    // #FF9F0A
    public static let accentRed = NSColor(srgbRed: 255 / 255.0, green: 69 / 255.0, blue: 58 / 255.0, alpha: 1.0)        // #FF453A
    public static let accentPurple = NSColor(srgbRed: 94 / 255.0, green: 92 / 255.0, blue: 230 / 255.0, alpha: 1.0)     // #5E5CE6
    public static let textPrimary = NSColor(srgbRed: 245 / 255.0, green: 245 / 255.0, blue: 247 / 255.0, alpha: 1.0)    // #F5F5F7
    public static let textSecondary = NSColor(srgbRed: 152 / 255.0, green: 152 / 255.0, blue: 157 / 255.0, alpha: 1.0)  // #98989D

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

    public static func fillRoundedRect(_ rect: NSRect, radius: CGFloat, color: NSColor) {
        guard rect.width > 0 && rect.height > 0 else { return }
        color.setFill()
        let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
        path.fill()
    }

    public static func strokeRoundedRect(_ rect: NSRect, radius: CGFloat, color: NSColor, lineWidth: CGFloat = 1.0) {
        guard rect.width > 0 && rect.height > 0 else { return }
        color.setStroke()
        let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
        path.lineWidth = lineWidth
        path.stroke()
    }

    public static func drawCenteredText(_ text: String, in rect: NSRect, font: NSFont, color: NSColor, alignment: NSTextAlignment = .center) {
        let style = NSMutableParagraphStyle()
        style.alignment = alignment
        style.lineBreakMode = .byClipping
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
        textColor: NSColor = .white
    ) {
        guard rect.width > 0 && rect.height > 0 else { return }
        let fill = hovered ? lighten(baseColor, delta: 18) : baseColor
        if fill.alphaComponent > 0.01 {
            fillRoundedRect(rect, radius: radius, color: fill)
        }
        if activeBorder {
            strokeRoundedRect(rect.insetBy(dx: 1, dy: 1), radius: radius, color: weChatGreen, lineWidth: 1.5)
        }
        let f = font ?? fontPx(13, bold: false)
        drawCenteredText(text, in: rect, font: f, color: textColor)
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

    public static func saveBitmapDialog(_ bmp: RawBitmap, tag: String) {
        copyBitmapToClipboard(bmp)
        let panel = NSSavePanel()
        panel.allowedFileTypes = ["png", "jpg"]
        panel.canCreateDirectories = true
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        panel.nameFieldStringValue = "SpanShot_\(tag)_\(formatter.string(from: Date())).png"
        panel.level = .modalPanel

        if panel.runModal() == .OK, let url = panel.url {
            let isJpg = url.pathExtension.lowercased() == "jpg" || url.pathExtension.lowercased() == "jpeg"
            let data = isJpg ? bmp.jpegData() : bmp.pngData()
            if let data = data {
                try? data.write(to: url)
                ToastWindow.showToast(message: "已保存", accent: weChatGreen)
            }
        }
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
            let rect = bounds.insetBy(dx: 1, dy: 1)
            UiTheme.fillRoundedRect(rect, radius: 6, color: UiTheme.toolbarBg)
            UiTheme.strokeRoundedRect(rect, radius: 6, color: accent, lineWidth: 1.5)
            UiTheme.drawCenteredText(message, in: rect, font: UiTheme.fontPx(14), color: .white)
        }
    }

    private init(message: String, accent: NSColor) {
        let font = UiTheme.fontPx(14)
        let textSize = (message as NSString).size(withAttributes: [.font: font])
        let w = max(180.0, ceil(textSize.width) + 40.0)
        let h: CGFloat = 40.0

        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
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
            let toast = ToastWindow(message: message, accent: accent)
            activeToasts.append(toast)
            toast.orderFrontRegardless()
        }
    }
}
