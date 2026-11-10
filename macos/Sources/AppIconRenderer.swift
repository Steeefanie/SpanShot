import AppKit
import CoreGraphics
import Foundation

/// Vector icon renderer for SpanShot:
/// 1. Full-bleed macOS squircle AppIcon (16x16 up to 1024x1024 for AppIcon.icns and MainForm brand badge)
/// 2. Crisp monochrome template icon (18x18 pt @2x Retina) for the macOS menu bar NSStatusItem
public enum AppIconRenderer {

    /// Renders the macOS squircle application icon at the requested pixel dimension.
    public static func renderAppIconBitmap(pixelSize: Int) -> NSBitmapImageRep? {
        let s = CGFloat(max(16, pixelSize))
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelSize,
            pixelsHigh: pixelSize,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: pixelSize * 4,
            bitsPerPixel: 32
        ) else {
            return nil
        }

        NSGraphicsContext.saveGraphicsState()
        guard let gctx = NSGraphicsContext(bitmapImageRep: rep) else {
            NSGraphicsContext.restoreGraphicsState()
            return nil
        }
        NSGraphicsContext.current = gctx
        let ctx = gctx.cgContext

        ctx.setAllowsAntialiasing(true)
        ctx.setShouldAntialias(true)
        ctx.interpolationQuality = .high

        // Flip to top-down coordinates (0,0 at top-left, s,s at bottom-right)
        ctx.translateBy(x: 0, y: s)
        ctx.scaleBy(x: 1.0, y: -1.0)

        drawAppIconInTopDownContext(ctx: ctx, size: s)

        NSGraphicsContext.restoreGraphicsState()
        return rep
    }

    public static func renderAppIconImage(pointSize: CGFloat) -> NSImage {
        let px = max(32, Int((pointSize * 2.0).rounded()))
        let img = NSImage(size: NSSize(width: pointSize, height: pointSize))
        if let rep = renderAppIconBitmap(pixelSize: px) {
            rep.size = NSSize(width: pointSize, height: pointSize)
            img.addRepresentation(rep)
        }
        return img
    }

    /// Renders the 18x18 pt (@1x and @2x Retina) template icon for NSStatusBar.
    public static func renderStatusBarTemplateIcon() -> NSImage {
        let ptSize: CGFloat = 18.0
        let img = NSImage(size: NSSize(width: ptSize, height: ptSize))

        for scale in [1, 2] {
            let px = Int(ptSize) * scale
            guard let rep = NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: px,
                pixelsHigh: px,
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: px * 4,
                bitsPerPixel: 32
            ) else { continue }

            rep.size = NSSize(width: ptSize, height: ptSize)
            NSGraphicsContext.saveGraphicsState()
            if let gctx = NSGraphicsContext(bitmapImageRep: rep) {
                NSGraphicsContext.current = gctx
                let ctx = gctx.cgContext
                ctx.setAllowsAntialiasing(true)
                ctx.setShouldAntialias(true)
                // Scale from 18x18 logical pt space to px space, flipped top-down
                ctx.translateBy(x: 0, y: CGFloat(px))
                ctx.scaleBy(x: CGFloat(scale), y: -CGFloat(scale))
                drawStatusBarVector(ctx: ctx, size: ptSize)
            }
            NSGraphicsContext.restoreGraphicsState()
            img.addRepresentation(rep)
        }

        img.isTemplate = true
        return img
    }

    private static func drawStatusBarVector(ctx: CGContext, size: CGFloat) {
        ctx.setStrokeColor(red: 0, green: 0, blue: 0, alpha: 1.0)
        ctx.setFillColor(red: 0, green: 0, blue: 0, alpha: 1.0)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)

        // 1. Four precision viewfinder corner brackets around (1.8, 1.8) .. (16.2, 16.2)
        let inset: CGFloat = 1.8
        let maxC = size - inset
        let arm: CGFloat = 3.6
        let r: CGFloat = 1.6
        ctx.setLineWidth(1.55)

        // Top-Left bracket
        let tl = CGMutablePath()
        tl.move(to: CGPoint(x: inset, y: inset + arm))
        tl.addArc(tangent1End: CGPoint(x: inset, y: inset), tangent2End: CGPoint(x: inset + arm, y: inset), radius: r)
        tl.addLine(to: CGPoint(x: inset + arm, y: inset))
        ctx.addPath(tl)
        ctx.strokePath()

        // Top-Right bracket
        let tr = CGMutablePath()
        tr.move(to: CGPoint(x: maxC - arm, y: inset))
        tr.addArc(tangent1End: CGPoint(x: maxC, y: inset), tangent2End: CGPoint(x: maxC, y: inset + arm), radius: r)
        tr.addLine(to: CGPoint(x: maxC, y: inset + arm))
        ctx.addPath(tr)
        ctx.strokePath()

        // Bottom-Left bracket
        let bl = CGMutablePath()
        bl.move(to: CGPoint(x: inset, y: maxC - arm))
        bl.addArc(tangent1End: CGPoint(x: inset, y: maxC), tangent2End: CGPoint(x: inset + arm, y: maxC), radius: r)
        bl.addLine(to: CGPoint(x: inset + arm, y: maxC))
        ctx.addPath(bl)
        ctx.strokePath()

        // Bottom-Right bracket
        let br = CGMutablePath()
        br.move(to: CGPoint(x: maxC - arm, y: maxC))
        br.addArc(tangent1End: CGPoint(x: maxC, y: maxC), tangent2End: CGPoint(x: maxC, y: maxC - arm), radius: r)
        br.addLine(to: CGPoint(x: maxC, y: maxC - arm))
        ctx.addPath(br)
        ctx.strokePath()

        // 2. Interior stitched horizontal lines + downward scroll arrow
        ctx.setLineWidth(1.45)
        // Top row bar
        ctx.move(to: CGPoint(x: 4.8, y: 5.5))
        ctx.addLine(to: CGPoint(x: 13.2, y: 5.5))
        ctx.strokePath()

        // Middle stitch seam line (dashed / split)
        ctx.move(to: CGPoint(x: 4.8, y: 8.4))
        ctx.addLine(to: CGPoint(x: 7.4, y: 8.4))
        ctx.move(to: CGPoint(x: 10.6, y: 8.4))
        ctx.addLine(to: CGPoint(x: 13.2, y: 8.4))
        ctx.strokePath()

        // Vertical scroll-stitch arrow in the center-bottom
        ctx.setLineWidth(1.55)
        ctx.move(to: CGPoint(x: 9.0, y: 7.4))
        ctx.addLine(to: CGPoint(x: 9.0, y: 13.6))
        ctx.move(to: CGPoint(x: 6.7, y: 11.4))
        ctx.addLine(to: CGPoint(x: 9.0, y: 13.7))
        ctx.addLine(to: CGPoint(x: 11.3, y: 11.4))
        ctx.strokePath()
    }

    private static func drawAppIconInTopDownContext(ctx: CGContext, size s: CGFloat) {
        let colorSpace = CGColorSpaceCreateDeviceRGB()

        // macOS Big Sur / Sonoma / Sequoia icon grid: 824/1024 squircle body
        let pad = s * 0.092
        let bodyRect = CGRect(x: pad, y: pad, width: s - pad * 2, height: s - pad * 2)
        let cornerR = bodyRect.width * 0.225

        // Soft drop shadow under squircle (for sizes >= 64)
        if s >= 64 {
            ctx.saveGState()
            ctx.setShadow(
                offset: CGSize(width: 0, height: s * 0.024),
                blur: s * 0.045,
                color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.42)
            )
            let shadowPath = CGPath(roundedRect: bodyRect, cornerWidth: cornerR, cornerHeight: cornerR, transform: nil)
            ctx.setFillColor(red: 0.05, green: 0.09, blue: 0.18, alpha: 1.0)
            ctx.addPath(shadowPath)
            ctx.fillPath()
            ctx.restoreGState()
        }

        // Clip to squircle
        let squirclePath = CGPath(roundedRect: bodyRect, cornerWidth: cornerR, cornerHeight: cornerR, transform: nil)
        ctx.saveGState()
        ctx.addPath(squirclePath)
        ctx.clip()

        // 1. Deep multi-stop sapphire-to-cyan gradient background
        let bgColors: [CGFloat] = [
            0.05, 0.09, 0.19, 1.0, // #0D1730 Deep Navy
            0.07, 0.18, 0.38, 1.0, // #122E61 Rich Sapphire
            0.02, 0.44, 0.78, 1.0  // #0570C7 Electric Ocean Blue
        ]
        if let grad = CGGradient(colorSpace: colorSpace, colorComponents: bgColors, locations: [0.0, 0.52, 1.0], count: 3) {
            ctx.drawLinearGradient(
                grad,
                start: CGPoint(x: bodyRect.minX, y: bodyRect.minY),
                end: CGPoint(x: bodyRect.maxX, y: bodyRect.maxY),
                options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
            )
        }

        // Ambient emerald-cyan glow in center-bottom
        let glowColors: [CGFloat] = [
            0.03, 0.78, 0.55, 0.34,
            0.00, 0.65, 0.95, 0.12,
            0.00, 0.40, 0.80, 0.00
        ]
        if let radial = CGGradient(colorSpace: colorSpace, colorComponents: glowColors, locations: [0.0, 0.55, 1.0], count: 3) {
            let center = CGPoint(x: s * 0.52, y: s * 0.56)
            ctx.drawRadialGradient(
                radial,
                startCenter: center,
                startRadius: 0,
                endCenter: center,
                endRadius: bodyRect.width * 0.55,
                options: []
            )
        }

        // Subtle background grid lines (precision engineering feel)
        ctx.saveGState()
        ctx.setStrokeColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.045)
        ctx.setLineWidth(max(1.0, s * 0.003))
        let step = bodyRect.width / 6.0
        for i in 1..<6 {
            let gx = bodyRect.minX + step * CGFloat(i)
            ctx.move(to: CGPoint(x: gx, y: bodyRect.minY))
            ctx.addLine(to: CGPoint(x: gx, y: bodyRect.maxY))
            let gy = bodyRect.minY + step * CGFloat(i)
            ctx.move(to: CGPoint(x: bodyRect.minX, y: gy))
            ctx.addLine(to: CGPoint(x: bodyRect.maxX, y: gy))
        }
        ctx.strokePath()
        ctx.restoreGState()

        // 2. Central Stitched Document / Table Card (split into Top Frame + Bottom Stitched Frame)
        let cardW = bodyRect.width * 0.54
        let cardH = bodyRect.height * 0.62
        let cardX = (s - cardW) * 0.5
        let cardY = (s - cardH) * 0.48
        let cardRect = CGRect(x: cardX, y: cardY, width: cardW, height: cardH)
        let cardR = cardW * 0.10

        // Card drop shadow
        ctx.saveGState()
        ctx.setShadow(
            offset: CGSize(width: 0, height: s * 0.018),
            blur: s * 0.035,
            color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.45)
        )
        let cardPath = CGPath(roundedRect: cardRect, cornerWidth: cardR, cornerHeight: cardR, transform: nil)
        ctx.setFillColor(red: 0.09, green: 0.13, blue: 0.22, alpha: 0.94)
        ctx.addPath(cardPath)
        ctx.fillPath()
        ctx.restoreGState()

        // Card content clipped
        ctx.saveGState()
        ctx.addPath(cardPath)
        ctx.clip()

        // Top header bar of the table card
        let headerH = cardH * 0.17
        ctx.setFillColor(red: 0.14, green: 0.22, blue: 0.38, alpha: 1.0)
        ctx.fill(CGRect(x: cardRect.minX, y: cardRect.minY, width: cardW, height: headerH))

        // Frozen left column highlight (symbolizing SpanShot's 68% sticky column engine)
        let frozenW = cardW * 0.30
        ctx.setFillColor(red: 0.11, green: 0.18, blue: 0.31, alpha: 1.0)
        ctx.fill(CGRect(x: cardRect.minX, y: cardRect.minY + headerH, width: frozenW, height: cardH - headerH))

        // Vertical divider line for frozen column
        ctx.setStrokeColor(red: 0.22, green: 0.65, blue: 1.0, alpha: 0.45)
        ctx.setLineWidth(max(1.0, s * 0.005))
        ctx.move(to: CGPoint(x: cardRect.minX + frozenW, y: cardRect.minY))
        ctx.addLine(to: CGPoint(x: cardRect.minX + frozenW, y: cardRect.maxY))
        ctx.strokePath()

        // Skeleton rows inside the card
        let rowYs: [CGFloat] = [0.27, 0.41, 0.62, 0.76, 0.89]
        let barH = max(2.0, cardH * 0.055)
        for (idx, ryFrac) in rowYs.enumerated() {
            let ry = cardRect.minY + cardH * ryFrac
            // Left frozen column pill
            let leftBarRect = CGRect(x: cardRect.minX + cardW * 0.06, y: ry, width: frozenW * 0.62, height: barH)
            let leftPath = CGPath(roundedRect: leftBarRect, cornerWidth: barH * 0.5, cornerHeight: barH * 0.5, transform: nil)
            ctx.setFillColor(red: 0.25, green: 0.72, blue: 1.0, alpha: 0.85)
            ctx.addPath(leftPath)
            ctx.fillPath()

            // Right scrolling column pills
            let rightW: CGFloat = (idx % 2 == 0) ? (cardW * 0.48) : (cardW * 0.38)
            let rightBarRect = CGRect(x: cardRect.minX + frozenW + cardW * 0.06, y: ry, width: rightW, height: barH)
            let rightPath = CGPath(roundedRect: rightBarRect, cornerWidth: barH * 0.5, cornerHeight: barH * 0.5, transform: nil)
            ctx.setFillColor(red: 0.85, green: 0.92, blue: 1.0, alpha: idx >= 2 ? 0.90 : 0.65)
            ctx.addPath(rightPath)
            ctx.fillPath()
        }

        // Glowing Emerald Stitch Seam Line across the middle of the card (y = 52%)
        let seamY = cardRect.minY + cardH * 0.525
        ctx.saveGState()
        ctx.setShadow(
            offset: .zero,
            blur: s * 0.018,
            color: CGColor(red: 0.03, green: 0.88, blue: 0.48, alpha: 0.9)
        )
        ctx.setStrokeColor(red: 0.04, green: 0.86, blue: 0.48, alpha: 1.0) // #0AD97B
        ctx.setLineWidth(max(1.5, s * 0.012))
        ctx.move(to: CGPoint(x: cardRect.minX, y: seamY))
        ctx.addLine(to: CGPoint(x: cardRect.maxX, y: seamY))
        ctx.strokePath()
        ctx.restoreGState()

        ctx.restoreGState() // End card clip

        // Card border stroke
        ctx.setStrokeColor(red: 0.40, green: 0.75, blue: 1.0, alpha: 0.42)
        ctx.setLineWidth(max(1.0, s * 0.006))
        ctx.addPath(cardPath)
        ctx.strokePath()

        // 3. Four Glowing Viewfinder Corner Brackets around the card
        let vfPad = s * 0.048
        let vfRect = cardRect.insetBy(dx: -vfPad, dy: -vfPad)
        let vfArm = s * 0.085
        let vfR = s * 0.028
        let vfStroke = max(2.0, s * 0.022)

        ctx.saveGState()
        ctx.setShadow(
            offset: CGSize(width: 0, height: s * 0.008),
            blur: s * 0.016,
            color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.40)
        )
        ctx.setStrokeColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.96)
        ctx.setLineWidth(vfStroke)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)

        // Top-Left
        let pTL = CGMutablePath()
        pTL.move(to: CGPoint(x: vfRect.minX, y: vfRect.minY + vfArm))
        pTL.addArc(tangent1End: CGPoint(x: vfRect.minX, y: vfRect.minY), tangent2End: CGPoint(x: vfRect.minX + vfArm, y: vfRect.minY), radius: vfR)
        pTL.addLine(to: CGPoint(x: vfRect.minX + vfArm, y: vfRect.minY))
        ctx.addPath(pTL)
        ctx.strokePath()

        // Top-Right
        let pTR = CGMutablePath()
        pTR.move(to: CGPoint(x: vfRect.maxX - vfArm, y: vfRect.minY))
        pTR.addArc(tangent1End: CGPoint(x: vfRect.maxX, y: vfRect.minY), tangent2End: CGPoint(x: vfRect.maxX, y: vfRect.minY + vfArm), radius: vfR)
        pTR.addLine(to: CGPoint(x: vfRect.maxX, y: vfRect.minY + vfArm))
        ctx.addPath(pTR)
        ctx.strokePath()

        // Bottom-Left
        let pBL = CGMutablePath()
        pBL.move(to: CGPoint(x: vfRect.minX, y: vfRect.maxY - vfArm))
        pBL.addArc(tangent1End: CGPoint(x: vfRect.minX, y: vfRect.maxY), tangent2End: CGPoint(x: vfRect.minX + vfArm, y: vfRect.maxY), radius: vfR)
        pBL.addLine(to: CGPoint(x: vfRect.minX + vfArm, y: vfRect.maxY))
        ctx.addPath(pBL)
        ctx.strokePath()

        ctx.restoreGState()

        // 4. Emerald Green (#07C160) Scroll-Stitch Badge at Bottom-Right Corner
        let badgeR = s * 0.135
        let badgeCenter = CGPoint(x: vfRect.maxX - badgeR * 0.35, y: vfRect.maxY - badgeR * 0.35)
        let badgeRect = CGRect(
            x: badgeCenter.x - badgeR,
            y: badgeCenter.y - badgeR,
            width: badgeR * 2.0,
            height: badgeR * 2.0
        )

        ctx.saveGState()
        ctx.setShadow(
            offset: CGSize(width: 0, height: s * 0.012),
            blur: s * 0.025,
            color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.45)
        )
        let badgeColors: [CGFloat] = [
            0.06, 0.85, 0.46, 1.0, // #0FD976
            0.03, 0.68, 0.35, 1.0  // #07AD59
        ]
        ctx.addEllipse(in: badgeRect)
        ctx.clip()
        if let bGrad = CGGradient(colorSpace: colorSpace, colorComponents: badgeColors, locations: [0.0, 1.0], count: 2) {
            ctx.drawLinearGradient(
                bGrad,
                start: CGPoint(x: badgeRect.minX, y: badgeRect.minY),
                end: CGPoint(x: badgeRect.maxX, y: badgeRect.maxY),
                options: []
            )
        }
        ctx.restoreGState()

        // White border around badge
        ctx.setStrokeColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.92)
        ctx.setLineWidth(max(1.5, s * 0.012))
        ctx.strokeEllipse(in: badgeRect)

        // Bidirectional scroll-stitch arrow inside badge
        ctx.saveGState()
        ctx.setStrokeColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0)
        ctx.setLineWidth(max(2.0, s * 0.022))
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)

        let arrowSpan = badgeR * 0.52
        let wing = badgeR * 0.32
        // Vertical shaft
        ctx.move(to: CGPoint(x: badgeCenter.x, y: badgeCenter.y - arrowSpan))
        ctx.addLine(to: CGPoint(x: badgeCenter.x, y: badgeCenter.y + arrowSpan))
        // Down arrowhead
        ctx.move(to: CGPoint(x: badgeCenter.x - wing, y: badgeCenter.y + arrowSpan - wing))
        ctx.addLine(to: CGPoint(x: badgeCenter.x, y: badgeCenter.y + arrowSpan))
        ctx.addLine(to: CGPoint(x: badgeCenter.x + wing, y: badgeCenter.y + arrowSpan - wing))
        // Horizontal stitch tick at top of shaft
        ctx.move(to: CGPoint(x: badgeCenter.x - wing * 0.85, y: badgeCenter.y - arrowSpan * 0.45))
        ctx.addLine(to: CGPoint(x: badgeCenter.x + wing * 0.85, y: badgeCenter.y - arrowSpan * 0.45))
        ctx.strokePath()
        ctx.restoreGState()

        // 5. Outer Squircle Glass Rim Highlight
        ctx.setStrokeColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.24)
        ctx.setLineWidth(max(1.0, s * 0.008))
        ctx.addPath(squirclePath)
        ctx.strokePath()

        ctx.restoreGState() // End squircle clip
    }

    /// Generates a complete macOS `.iconset` directory for `/usr/bin/iconutil -c icns`.
    public static func generateIconset(at iconsetDir: String) -> Bool {
        let fm = FileManager.default
        try? fm.removeItem(atPath: iconsetDir)
        do {
            try fm.createDirectory(atPath: iconsetDir, withIntermediateDirectories: true)
        } catch {
            return false
        }

        let specs: [(name: String, pixels: Int)] = [
            ("icon_16x16.png", 16),
            ("icon_16x16@2x.png", 32),
            ("icon_32x32.png", 32),
            ("icon_32x32@2x.png", 64),
            ("icon_128x128.png", 128),
            ("icon_128x128@2x.png", 256),
            ("icon_256x256.png", 256),
            ("icon_256x256@2x.png", 512),
            ("icon_512x512.png", 512),
            ("icon_512x512@2x.png", 1024)
        ]

        for spec in specs {
            guard let rep = renderAppIconBitmap(pixelSize: spec.pixels),
                  let pngData = rep.representation(using: .png, properties: [:]) else {
                return false
            }
            let fileURL = URL(fileURLWithPath: iconsetDir).appendingPathComponent(spec.name)
            do {
                try pngData.write(to: fileURL)
            } catch {
                return false
            }
        }
        return true
    }
}
