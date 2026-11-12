import AppKit
import CoreGraphics
import Foundation

/// Vector icon renderer for SpanShot (1:1 port of src/AppIcon.cs adapted to Apple's macOS HIG 824/1024 continuous squircle grid):
/// 1. Vibrant Apple-Blue gradient continuous superellipse squircle (#24A4FF -> #007AFF -> #004ED2)
/// 2. Three rounded screenshot viewfinder corner brackets (Top-Left, Top-Right, Bottom-Right)
/// 3. White open scissors oriented at -45 deg (handles at bottom-left, tapered blades opening toward top-right)
/// 4. Monochrome template icon (18x18 pt @1x/@2x Retina) for the macOS menu bar NSStatusItem
public enum AppIconRenderer {

    /// Apple's exact 3-Bezier continuous corner curve (`kCACornerCurveContinuous` superellipse squircle).
    public static func continuousRoundedRectPath(rect: CGRect, radius: CGFloat) -> CGPath {
        let minSide = min(rect.width, rect.height)
        let r = min(radius, minSide * 0.5)
        guard r > 0.5 else {
            return CGPath(rect: rect, transform: nil)
        }

        // Exact Apple continuous corner constants (clamped so d0 never exceeds half side length)
        let d0 = min(minSide * 0.5, 1.52866483 * r)
        let c1 = 1.08849296 * r
        let c2 = 0.86840694 * r
        let p1x = 0.63149379 * r
        let p1y = 0.07491139 * r
        let c3x = 0.37282383 * r
        let c3y = 0.16905956 * r

        let left = rect.minX
        let right = rect.maxX
        let top = rect.minY
        let bottom = rect.maxY

        let path = CGMutablePath()

        // Start on top edge after top-left corner
        path.move(to: CGPoint(x: left + d0, y: top))

        // Top edge -> Top-Right corner
        path.addLine(to: CGPoint(x: right - d0, y: top))
        path.addCurve(
            to: CGPoint(x: right - p1x, y: top + p1y),
            control1: CGPoint(x: right - c1, y: top),
            control2: CGPoint(x: right - c2, y: top)
        )
        path.addCurve(
            to: CGPoint(x: right - p1y, y: top + p1x),
            control1: CGPoint(x: right - c3x, y: top + c3y),
            control2: CGPoint(x: right - c3y, y: top + c3x)
        )
        path.addCurve(
            to: CGPoint(x: right, y: top + d0),
            control1: CGPoint(x: right, y: top + c2),
            control2: CGPoint(x: right, y: top + c1)
        )

        // Right edge -> Bottom-Right corner
        path.addLine(to: CGPoint(x: right, y: bottom - d0))
        path.addCurve(
            to: CGPoint(x: right - p1y, y: bottom - p1x),
            control1: CGPoint(x: right, y: bottom - c1),
            control2: CGPoint(x: right, y: bottom - c2)
        )
        path.addCurve(
            to: CGPoint(x: right - p1x, y: bottom - p1y),
            control1: CGPoint(x: right - c3y, y: bottom - c3x),
            control2: CGPoint(x: right - c3x, y: bottom - c3y)
        )
        path.addCurve(
            to: CGPoint(x: right - d0, y: bottom),
            control1: CGPoint(x: right - c2, y: bottom),
            control2: CGPoint(x: right - c1, y: bottom)
        )

        // Bottom edge -> Bottom-Left corner
        path.addLine(to: CGPoint(x: left + d0, y: bottom))
        path.addCurve(
            to: CGPoint(x: left + p1x, y: bottom - p1y),
            control1: CGPoint(x: left + c1, y: bottom),
            control2: CGPoint(x: left + c2, y: bottom)
        )
        path.addCurve(
            to: CGPoint(x: left + p1y, y: bottom - p1x),
            control1: CGPoint(x: left + c3x, y: bottom - c3y),
            control2: CGPoint(x: left + c3y, y: bottom - c3x)
        )
        path.addCurve(
            to: CGPoint(x: left, y: bottom - d0),
            control1: CGPoint(x: left, y: bottom - c2),
            control2: CGPoint(x: left, y: bottom - c1)
        )

        // Left edge -> Top-Left corner
        path.addLine(to: CGPoint(x: left, y: top + d0))
        path.addCurve(
            to: CGPoint(x: left + p1y, y: top + p1x),
            control1: CGPoint(x: left, y: top + c1),
            control2: CGPoint(x: left, y: top + c2)
        )
        path.addCurve(
            to: CGPoint(x: left + p1x, y: top + p1y),
            control1: CGPoint(x: left + c3y, y: top + c3x),
            control2: CGPoint(x: left + c3x, y: top + c3y)
        )
        path.addCurve(
            to: CGPoint(x: left + d0, y: top),
            control1: CGPoint(x: left + c2, y: top),
            control2: CGPoint(x: left + c1, y: top)
        )

        path.closeSubpath()
        return path
    }

    /// Renders the macOS squircle application icon at the requested pixel dimension.
    /// - Parameter useSystemGridMargin: When `true` (default for `.icns`), uses Apple's 824/1024 HIG icon grid margin (`9.765%`).
    ///   When `false` (for inline header icon in `MainForm`), uses minimal padding (`2%`).
    public static func renderAppIconBitmap(pixelSize: Int, useSystemGridMargin: Bool = true) -> NSBitmapImageRep? {
        let targetPx = max(16, pixelSize)
        let renderPx = targetPx < 64 ? targetPx * 4 : targetPx
        let compactMode = targetPx <= 24

        guard let hiRes = renderCoreBitmap(
            pixelSize: renderPx,
            compactTrayMode: compactMode,
            useSystemGridMargin: useSystemGridMargin
        ) else {
            return nil
        }
        if renderPx == targetPx {
            return hiRes
        }

        guard let outRep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: targetPx,
            pixelsHigh: targetPx,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: targetPx * 4,
            bitsPerPixel: 32
        ) else {
            return hiRes
        }

        NSGraphicsContext.saveGraphicsState()
        if let gctx = NSGraphicsContext(bitmapImageRep: outRep),
           let cgImg = hiRes.cgImage {
            NSGraphicsContext.current = gctx
            let ctx = gctx.cgContext
            ctx.setAllowsAntialiasing(true)
            ctx.setShouldAntialias(true)
            ctx.interpolationQuality = .high
            ctx.draw(cgImg, in: CGRect(x: 0, y: 0, width: targetPx, height: targetPx))
        }
        NSGraphicsContext.restoreGraphicsState()
        return outRep
    }

    private static func renderCoreBitmap(
        pixelSize: Int,
        compactTrayMode: Bool,
        useSystemGridMargin: Bool
    ) -> NSBitmapImageRep? {
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

        let sizeF = CGFloat(pixelSize)
        // Flip to top-down coordinates (0,0 at top-left, sizeF,sizeF at bottom-right)
        ctx.translateBy(x: 0, y: sizeF)
        ctx.scaleBy(x: 1.0, y: -1.0)

        drawAppIconInTopDownContext(
            ctx: ctx,
            size: sizeF,
            compactTrayMode: compactTrayMode,
            useSystemGridMargin: useSystemGridMargin
        )

        NSGraphicsContext.restoreGraphicsState()
        return rep
    }

    public static func renderAppIconImage(pointSize: CGFloat, useSystemGridMargin: Bool = false) -> NSImage {
        let px = max(32, Int((pointSize * 2.0).rounded()))
        let img = NSImage(size: NSSize(width: pointSize, height: pointSize))
        if let rep = renderAppIconBitmap(pixelSize: px, useSystemGridMargin: useSystemGridMargin) {
            rep.size = NSSize(width: pointSize, height: pointSize)
            img.addRepresentation(rep)
        }
        return img
    }

    /// Renders the 18x18 pt (@1x and @2x Retina) template icon for NSStatusBar using the same viewfinder + scissors motif.
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
                ctx.translateBy(x: 0, y: CGFloat(px))
                ctx.scaleBy(x: 1.0, y: -1.0)
                drawStatusBarVector(ctx: ctx, size: CGFloat(px))
            }
            NSGraphicsContext.restoreGraphicsState()
            img.addRepresentation(rep)
        }

        img.isTemplate = true
        return img
    }

    private static func drawStatusBarVector(ctx: CGContext, size: CGFloat) {
        let s = size / 100.0
        let fg = CGColor(red: 0, green: 0, blue: 0, alpha: 1.0)

        let cMargin: CGFloat = 10.5
        let cArm: CGFloat = 16.0
        let cRadius: CGFloat = 4.2
        let cStroke: CGFloat = 6.8 * s

        drawCornerBracket(ctx: ctx, origin: .zero, s: s, cx: cMargin, cy: cMargin, dirX: 1, dirY: 1, arm: cArm, cornerR: cRadius, strokeWidth: cStroke, color: fg)
        drawCornerBracket(ctx: ctx, origin: .zero, s: s, cx: 100.0 - cMargin, cy: cMargin, dirX: -1, dirY: 1, arm: cArm, cornerR: cRadius, strokeWidth: cStroke, color: fg)
        drawCornerBracket(ctx: ctx, origin: .zero, s: s, cx: 100.0 - cMargin, cy: 100.0 - cMargin, dirX: -1, dirY: -1, arm: cArm, cornerR: cRadius, strokeWidth: cStroke, color: fg)

        drawScissors(
            ctx: ctx,
            origin: .zero,
            s: s,
            px: 50.0,
            py: 50.0,
            k: 1.12,
            compactTrayMode: true,
            fgColor: fg,
            punchOutScrew: true,
            screwColor: nil
        )
    }

    private static func drawAppIconInTopDownContext(
        ctx: CGContext,
        size: CGFloat,
        compactTrayMode: Bool,
        useSystemGridMargin: Bool
    ) {
        let colorSpace = CGColorSpaceCreateDeviceRGB()

        // Apple macOS HIG Icon Grid: 824x824 inside 1024x1024 (100/1024 = 9.765625% padding)
        // Corner curvature 0.262 * badgeSide matches macOS Tahoe continuous squircle mask (diag=163 in 1024x1024)
        let pad: CGFloat = useSystemGridMargin
            ? (size * (100.0 / 1024.0))
            : (size * 0.02)
        let badgeSide = size - pad * 2.0
        let radius = badgeSide * 0.262
        let badgeRect = CGRect(x: pad, y: pad, width: badgeSide, height: badgeSide)
        let badgePath = continuousRoundedRectPath(rect: badgeRect, radius: radius)

        // Subtle macOS icon drop shadow when using standard 824/1024 icon grid
        if useSystemGridMargin && size >= 64 {
            ctx.saveGState()
            ctx.setShadow(
                offset: CGSize(width: 0, height: size * (10.0 / 1024.0)),
                blur: size * (22.0 / 1024.0),
                color: CGColor(red: 0, green: 0.08, blue: 0.24, alpha: 0.28)
            )
            ctx.setFillColor(red: 0.0, green: 0.38, blue: 0.88, alpha: 1.0)
            ctx.addPath(badgePath)
            ctx.fillPath()
            ctx.restoreGState()
        }

        // 1. Vibrant Apple-Blue gradient continuous squircle background (#24A4FF -> #007AFF -> #004ED2)
        ctx.saveGState()
        ctx.addPath(badgePath)
        ctx.clip()

        let bgColors: [CGFloat] = [
            36.0 / 255.0, 164.0 / 255.0, 255.0 / 255.0, 1.0, // #24A4FF Luminous sky blue
            0.0 / 255.0, 122.0 / 255.0, 255.0 / 255.0, 1.0,  // #007AFF Signature Apple Blue
            0.0 / 255.0, 78.0 / 255.0, 210.0 / 255.0, 1.0    // #004ED2 Deep cobalt
        ]
        if let grad = CGGradient(colorSpace: colorSpace, colorComponents: bgColors, locations: [0.0, 0.52, 1.0], count: 3) {
            ctx.drawLinearGradient(
                grad,
                start: CGPoint(x: badgeRect.minX, y: badgeRect.minY),
                end: CGPoint(x: badgeRect.maxX, y: badgeRect.maxY),
                options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
            )
        }

        // Flush hairline specular edge (stroked on badgePath while clipped to badgePath so zero inset gap occurs)
        let bs = badgeSide / 100.0
        ctx.setStrokeColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 42.0 / 255.0)
        ctx.setLineWidth(max(1.0, 1.6 * bs))
        ctx.addPath(badgePath)
        ctx.strokePath()

        ctx.restoreGState()

        // All interior graphics are mapped in the 0..100 coordinate space of `badgeRect`
        let badgeOrigin = badgeRect.origin

        // 2. Screenshot Viewfinder Corner Brackets (Top-Left, Top-Right, Bottom-Right)
        let cMargin: CGFloat = compactTrayMode ? 14.5 : 16.0
        let cArm: CGFloat = compactTrayMode ? 13.0 : 13.5
        let cRadius: CGFloat = 4.2
        let cStroke: CGFloat = (compactTrayMode ? 5.8 : 5.0) * bs
        let bracketAlpha: CGFloat = (compactTrayMode ? 240.0 : 228.0) / 255.0
        let bracketColor = CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: bracketAlpha)

        // Top-Left corner bracket
        drawCornerBracket(ctx: ctx, origin: badgeOrigin, s: bs, cx: cMargin, cy: cMargin, dirX: 1, dirY: 1, arm: cArm, cornerR: cRadius, strokeWidth: cStroke, color: bracketColor)
        // Top-Right corner bracket (target of the scissor jaws)
        drawCornerBracket(ctx: ctx, origin: badgeOrigin, s: bs, cx: 100.0 - cMargin, cy: cMargin, dirX: -1, dirY: 1, arm: cArm, cornerR: cRadius, strokeWidth: cStroke, color: bracketColor)
        // Bottom-Right corner bracket
        drawCornerBracket(ctx: ctx, origin: badgeOrigin, s: bs, cx: 100.0 - cMargin, cy: 100.0 - cMargin, dirX: -1, dirY: -1, arm: cArm, cornerR: cRadius, strokeWidth: cStroke, color: bracketColor)

        // 3. Open Scissors Element (oriented along -45 deg diagonal: handles at bottom-left, blades opening to top-right)
        let pivotX: CGFloat = 50.2
        let pivotY: CGFloat = 49.8
        let scaleFactor: CGFloat = compactTrayMode ? 1.08 : 1.04
        let whiteColor = CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0)
        let screwColor = CGColor(red: 0.0, green: 88.0 / 255.0, blue: 218.0 / 255.0, alpha: 1.0)

        drawScissors(
            ctx: ctx,
            origin: badgeOrigin,
            s: bs,
            px: pivotX,
            py: pivotY,
            k: scaleFactor,
            compactTrayMode: compactTrayMode,
            fgColor: whiteColor,
            punchOutScrew: false,
            screwColor: screwColor
        )
    }

    private static func drawCornerBracket(
        ctx: CGContext,
        origin: CGPoint,
        s: CGFloat,
        cx: CGFloat,
        cy: CGFloat,
        dirX: CGFloat,
        dirY: CGFloat,
        arm: CGFloat,
        cornerR: CGFloat,
        strokeWidth: CGFloat,
        color: CGColor
    ) {
        let p1 = CGPoint(x: origin.x + (cx + dirX * arm) * s, y: origin.y + cy * s)
        let pCorner1 = CGPoint(x: origin.x + (cx + dirX * cornerR) * s, y: origin.y + cy * s)
        let pVert = CGPoint(x: origin.x + cx * s, y: origin.y + cy * s)
        let pCorner2 = CGPoint(x: origin.x + cx * s, y: origin.y + (cy + dirY * cornerR) * s)
        let p2 = CGPoint(x: origin.x + cx * s, y: origin.y + (cy + dirY * arm) * s)

        let path = CGMutablePath()
        path.move(to: p1)
        path.addLine(to: pCorner1)
        path.addCurve(to: pCorner2, control1: pVert, control2: pVert)
        path.addLine(to: p2)

        ctx.saveGState()
        ctx.setStrokeColor(color)
        ctx.setLineWidth(strokeWidth)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        ctx.addPath(path)
        ctx.strokePath()
        ctx.restoreGState()
    }

    private static func drawScissors(
        ctx: CGContext,
        origin: CGPoint,
        s: CGFloat,
        px: CGFloat,
        py: CGFloat,
        k: CGFloat,
        compactTrayMode: Bool,
        fgColor: CGColor,
        punchOutScrew: Bool,
        screwColor: CGColor?
    ) {
        let invSqrt2: CGFloat = 0.70710678
        let ux = invSqrt2
        let uy = -invSqrt2
        let vx = invSqrt2
        let vy = invSqrt2

        drawScissorHalf(ctx: ctx, origin: origin, s: s, px: px, py: py, ux: ux, uy: uy, vx: vx, vy: vy, k: k, sign: -1.0, compactTrayMode: compactTrayMode, fgColor: fgColor)
        drawScissorHalf(ctx: ctx, origin: origin, s: s, px: px, py: py, ux: ux, uy: uy, vx: vx, vy: vy, k: k, sign: +1.0, compactTrayMode: compactTrayMode, fgColor: fgColor)

        let screwR = (compactTrayMode ? 3.1 : 2.7) * k * s
        let screwRect = CGRect(
            x: origin.x + px * s - screwR,
            y: origin.y + py * s - screwR,
            width: screwR * 2.0,
            height: screwR * 2.0
        )

        ctx.saveGState()
        if punchOutScrew {
            ctx.setBlendMode(.clear)
            ctx.fillEllipse(in: screwRect)
        } else if let sc = screwColor {
            ctx.setFillColor(sc)
            ctx.fillEllipse(in: screwRect)
        }
        ctx.restoreGState()
    }

    private static func drawScissorHalf(
        ctx: CGContext,
        origin: CGPoint,
        s: CGFloat,
        px: CGFloat,
        py: CGFloat,
        ux: CGFloat,
        uy: CGFloat,
        vx: CGFloat,
        vy: CGFloat,
        k: CGFloat,
        sign: CGFloat,
        compactTrayMode: Bool,
        fgColor: CGColor
    ) {
        let alpha = 22.0 * (.pi / 180.0) * sign
        let cosA = cos(alpha)
        let sinA = sin(alpha)

        let dx = cosA * ux + sinA * vx
        let dy = cosA * uy + sinA * vy
        let nx = sign * (-sinA * ux + cosA * vx)
        let ny = sign * (-sinA * uy + cosA * vy)

        let tipDist: CGFloat = 33.5 * k
        let backDist: CGFloat = -5.5 * k
        let bladeWidth: CGFloat = (compactTrayMode ? 8.6 : 7.8) * k
        let innerOffset: CGFloat = -1.3 * k

        let innerBack = toScreen(origin: origin, s: s, px: px, py: py, dx: dx, dy: dy, nx: nx, ny: ny, along: backDist, perp: innerOffset)
        let tip = toScreen(origin: origin, s: s, px: px, py: py, dx: dx, dy: dy, nx: nx, ny: ny, along: tipDist, perp: innerOffset + 0.3 * k)
        let outerCtrl1 = toScreen(origin: origin, s: s, px: px, py: py, dx: dx, dy: dy, nx: nx, ny: ny, along: tipDist * 0.72, perp: innerOffset + bladeWidth * 0.72)
        let outerCtrl2 = toScreen(origin: origin, s: s, px: px, py: py, dx: dx, dy: dy, nx: nx, ny: ny, along: tipDist * 0.25, perp: innerOffset + bladeWidth * 1.02)
        let outerBack = toScreen(origin: origin, s: s, px: px, py: py, dx: dx, dy: dy, nx: nx, ny: ny, along: backDist, perp: innerOffset + bladeWidth * 0.78)

        let bladePath = CGMutablePath()
        bladePath.move(to: innerBack)
        bladePath.addLine(to: tip)
        bladePath.addCurve(to: outerBack, control1: outerCtrl1, control2: outerCtrl2)
        bladePath.closeSubpath()

        ctx.saveGState()
        ctx.setFillColor(fgColor)
        ctx.addPath(bladePath)
        ctx.fillPath()
        ctx.restoreGState()

        let ringU: CGFloat = -20.5 * k
        let ringV: CGFloat = -sign * 13.8 * k
        let ringCenterX = origin.x + (px + ringU * ux + ringV * vx) * s
        let ringCenterY = origin.y + (py + ringU * uy + ringV * vy) * s

        let ringOuterR = (compactTrayMode ? 11.2 : 10.6) * k * s
        let ringStroke = (compactTrayMode ? 5.6 : 5.0) * k * s
        let ringMidR = ringOuterR - ringStroke * 0.5

        let shankStart = CGPoint(x: origin.x + (px - 2.0 * k * dx) * s, y: origin.y + (py - 2.0 * k * dy) * s)
        let shankMid = CGPoint(
            x: origin.x + (px + (-10.5 * k) * ux + (-sign * 5.8 * k) * vx) * s,
            y: origin.y + (py + (-10.5 * k) * uy + (-sign * 5.8 * k) * vy) * s
        )
        let shankEnd = CGPoint(
            x: origin.x + (px + (-15.0 * k) * ux + (-sign * 10.5 * k) * vx) * s,
            y: origin.y + (py + (-15.0 * k) * uy + (-sign * 10.5 * k) * vy) * s
        )

        let shankPath = CGMutablePath()
        shankPath.move(to: shankStart)
        shankPath.addCurve(to: shankEnd, control1: shankMid, control2: shankMid)

        ctx.saveGState()
        ctx.setStrokeColor(fgColor)
        ctx.setLineWidth((compactTrayMode ? 5.8 : 5.2) * k * s)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        ctx.addPath(shankPath)
        ctx.strokePath()

        ctx.setLineWidth(ringStroke)
        ctx.strokeEllipse(in: CGRect(
            x: ringCenterX - ringMidR,
            y: ringCenterY - ringMidR,
            width: ringMidR * 2.0,
            height: ringMidR * 2.0
        ))
        ctx.restoreGState()
    }

    private static func toScreen(
        origin: CGPoint,
        s: CGFloat,
        px: CGFloat,
        py: CGFloat,
        dx: CGFloat,
        dy: CGFloat,
        nx: CGFloat,
        ny: CGFloat,
        along: CGFloat,
        perp: CGFloat
    ) -> CGPoint {
        return CGPoint(
            x: origin.x + (px + along * dx + perp * nx) * s,
            y: origin.y + (py + along * dy + perp * ny) * s
        )
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
            guard let rep = renderAppIconBitmap(pixelSize: spec.pixels, useSystemGridMargin: true),
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

    /// Generates @1x (660x400) and @2x (1320x800) DMG installer background PNGs in `outDir`
    /// so `tiffutil -cathidpicheck` can combine them into a Retina-ready `background.tiff`.
    public static func generateDmgBackground(at outDir: String) -> Bool {
        let fm = FileManager.default
        do {
            try fm.createDirectory(atPath: outDir, withIntermediateDirectories: true)
        } catch {
            return false
        }

        let logicalW = 660
        let logicalH = 400

        for scale in [1, 2] {
            let pxW = logicalW * scale
            let pxH = logicalH * scale
            guard let rep = NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: pxW,
                pixelsHigh: pxH,
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: pxW * 4,
                bitsPerPixel: 32
            ) else {
                return false
            }

            NSGraphicsContext.saveGraphicsState()
            guard let gctx = NSGraphicsContext(bitmapImageRep: rep) else {
                NSGraphicsContext.restoreGraphicsState()
                return false
            }
            NSGraphicsContext.current = gctx
            let ctx = gctx.cgContext
            ctx.setAllowsAntialiasing(true)
            ctx.setShouldAntialias(true)
            ctx.interpolationQuality = .high

            ctx.translateBy(x: 0, y: CGFloat(pxH))
            ctx.scaleBy(x: CGFloat(scale), y: -CGFloat(scale))

            drawDmgBackgroundInTopDownContext(ctx: ctx, width: CGFloat(logicalW), height: CGFloat(logicalH))

            NSGraphicsContext.restoreGraphicsState()

            rep.size = NSSize(width: logicalW, height: logicalH)

            guard let pngData = rep.representation(using: .png, properties: [:]) else {
                return false
            }
            let fileName = (scale == 1) ? "bg.png" : "bg@2x.png"
            let fileURL = URL(fileURLWithPath: outDir).appendingPathComponent(fileName)
            do {
                try pngData.write(to: fileURL)
            } catch {
                return false
            }
        }
        return true
    }

    private static func drawDmgBackgroundInTopDownContext(ctx: CGContext, width w: CGFloat, height h: CGFloat) {
        let colorSpace = CGColorSpaceCreateDeviceRGB()

        let bgColors: [CGFloat] = [
            249.0 / 255.0, 251.0 / 255.0, 255.0 / 255.0, 1.0,
            238.0 / 255.0, 243.0 / 255.0, 250.0 / 255.0, 1.0
        ]
        if let grad = CGGradient(colorSpace: colorSpace, colorComponents: bgColors, locations: [0.0, 1.0], count: 2) {
            ctx.drawLinearGradient(
                grad,
                start: CGPoint(x: w * 0.5, y: 0),
                end: CGPoint(x: w * 0.5, y: h),
                options: []
            )
        }

        let glowColors: [CGFloat] = [
            0.0 / 255.0, 122.0 / 255.0, 255.0 / 255.0, 0.11,
            0.0 / 255.0, 122.0 / 255.0, 255.0 / 255.0, 0.035,
            0.0 / 255.0, 122.0 / 255.0, 255.0 / 255.0, 0.00
        ]
        if let radial = CGGradient(colorSpace: colorSpace, colorComponents: glowColors, locations: [0.0, 0.55, 1.0], count: 3) {
            for cx in [CGFloat(180.0), CGFloat(480.0)] {
                let center = CGPoint(x: cx, y: 176.0)
                ctx.drawRadialGradient(
                    radial,
                    startCenter: center,
                    startRadius: 0,
                    endCenter: center,
                    endRadius: 125.0,
                    options: []
                )
            }
        }

        let arrowY: CGFloat = 172.0

        let chevronXs: [(x: CGFloat, alpha: CGFloat)] = [
            (288.0, 0.28),
            (304.0, 0.52)
        ]
        for item in chevronXs {
            ctx.saveGState()
            ctx.setStrokeColor(red: 0.0, green: 122.0 / 255.0, blue: 255.0 / 255.0, alpha: item.alpha)
            ctx.setLineWidth(3.6)
            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)
            ctx.move(to: CGPoint(x: item.x - 7.0, y: arrowY - 9.5))
            ctx.addLine(to: CGPoint(x: item.x + 2.0, y: arrowY))
            ctx.addLine(to: CGPoint(x: item.x - 7.0, y: arrowY + 9.5))
            ctx.strokePath()
            ctx.restoreGState()
        }

        ctx.saveGState()
        ctx.setShadow(
            offset: CGSize(width: 0, height: 3),
            blur: 8,
            color: CGColor(red: 0.0, green: 122.0 / 255.0, blue: 255.0 / 255.0, alpha: 0.28)
        )
        ctx.setStrokeColor(red: 0.0, green: 122.0 / 255.0, blue: 255.0 / 255.0, alpha: 0.96)
        ctx.setLineWidth(5.0)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)

        ctx.move(to: CGPoint(x: 320.0, y: arrowY))
        ctx.addLine(to: CGPoint(x: 377.0, y: arrowY))
        ctx.move(to: CGPoint(x: 363.0, y: arrowY - 13.5))
        ctx.addLine(to: CGPoint(x: 378.0, y: arrowY))
        ctx.addLine(to: CGPoint(x: 363.0, y: arrowY + 13.5))
        ctx.strokePath()
        ctx.restoreGState()

        let pillW: CGFloat = 336.0
        let pillH: CGFloat = 32.0
        let pillRect = CGRect(x: (w - pillW) * 0.5, y: 322.0, width: pillW, height: pillH)
        let pillPath = CGPath(roundedRect: pillRect, cornerWidth: 16.0, cornerHeight: 16.0, transform: nil)

        ctx.saveGState()
        ctx.setShadow(
            offset: CGSize(width: 0, height: 2),
            blur: 6,
            color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.05)
        )
        ctx.setFillColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.88)
        ctx.addPath(pillPath)
        ctx.fillPath()
        ctx.restoreGState()

        ctx.saveGState()
        ctx.setStrokeColor(red: 0.0, green: 122.0 / 255.0, blue: 255.0 / 255.0, alpha: 0.18)
        ctx.setLineWidth(1.0)
        ctx.addPath(pillPath)
        ctx.strokePath()
        ctx.restoreGState()

        let prevCtx = NSGraphicsContext.current
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        let textAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12.5, weight: .medium),
            .foregroundColor: NSColor(srgbRed: 68.0 / 255.0, green: 80.0 / 255.0, blue: 98.0 / 255.0, alpha: 1.0),
            .paragraphStyle: style
        ]
        let tip = "将 SpanShot 拖入右侧 Applications 文件夹即可安装" as NSString
        let tSize = tip.size(withAttributes: textAttrs)
        let textRect = NSRect(
            x: pillRect.origin.x,
            y: pillRect.origin.y + (pillRect.height - tSize.height) * 0.5,
            width: pillRect.width,
            height: tSize.height + 2.0
        )
        tip.draw(in: textRect, withAttributes: textAttrs)
        NSGraphicsContext.current = prevCtx
    }
}
