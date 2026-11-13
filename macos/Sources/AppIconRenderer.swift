import AppKit
import CoreGraphics
import Foundation

/// Vector icon renderer for SpanShot adapted to Apple's macOS HIG 824/1024 continuous squircle grid:
/// 1. Tactile ceramic-white continuous superellipse squircle (#FFFFFF -> #EFF2F7) with subtle inner bevel & ambient drop shadow
/// 2. Layered translucent ice-blue selection card in the midground for depth
/// 3. Floating anodized Space-Black / Dark-Titanium corner brackets (#2E333D -> #111318) with soft elevation shadow
/// 4. Luminous Apple-Blue (#2997FF -> #0062E3) optical center jewel as a restrained focal accent
/// 5. Monochrome template icon (18x18 pt @1x/@2x Retina) for the macOS menu bar NSStatusItem
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
            // Must set `rep.size` AFTER drawing so NSGraphicsContext(bitmapImageRep:) does not apply a 2x CTM scale!
            rep.size = NSSize(width: ptSize, height: ptSize)
            img.addRepresentation(rep)
        }

        img.isTemplate = true
        return img
    }

    private static func drawStatusBarVector(ctx: CGContext, size: CGFloat) {
        let s = size / 100.0

        // Pure crisp monochrome strokes on 100% transparent background (no semi-transparent fill)
        let cMargin: CGFloat = 17.5
        let cRadius: CGFloat = 10.0
        let cArm: CGFloat = 21.0
        let cStroke: CGFloat = 7.6 * s

        let bracketsPath = CGMutablePath()
        let corners: [(cx: CGFloat, cy: CGFloat, dirX: CGFloat, dirY: CGFloat)] = [
            (cMargin, cMargin, 1, 1),
            (100.0 - cMargin, cMargin, -1, 1),
            (cMargin, 100.0 - cMargin, 1, -1),
            (100.0 - cMargin, 100.0 - cMargin, -1, -1)
        ]
        for c in corners {
            let p1 = CGPoint(x: (c.cx + c.dirX * cArm) * s, y: c.cy * s)
            let pVert = CGPoint(x: c.cx * s, y: c.cy * s)
            let p2 = CGPoint(x: c.cx * s, y: (c.cy + c.dirY * cArm) * s)
            bracketsPath.move(to: p1)
            bracketsPath.addArc(tangent1End: pVert, tangent2End: p2, radius: cRadius * s)
            bracketsPath.addLine(to: p2)
        }

        ctx.saveGState()
        ctx.setStrokeColor(red: 0, green: 0, blue: 0, alpha: 1.0)
        ctx.setLineWidth(cStroke)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        ctx.addPath(bracketsPath)
        ctx.strokePath()

        let dotR: CGFloat = 7.2 * s
        ctx.setFillColor(red: 0, green: 0, blue: 0, alpha: 1.0)
        ctx.fillEllipse(in: CGRect(x: 50.0 * s - dotR, y: 50.0 * s - dotR, width: dotR * 2.0, height: dotR * 2.0))
        ctx.restoreGState()
    }

    private static func drawAppIconInTopDownContext(
        ctx: CGContext,
        size: CGFloat,
        compactTrayMode: Bool,
        useSystemGridMargin: Bool
    ) {
        let colorSpace = CGColorSpaceCreateDeviceRGB()

        // Apple macOS HIG Icon Grid: 824x824 inside 1024x1024 (100/1024 = 9.765625% padding)
        // Corner curvature 0.262 * badgeSide matches macOS continuous squircle mask
        let pad: CGFloat = useSystemGridMargin
            ? (size * (100.0 / 1024.0))
            : (size * 0.02)
        let badgeSide = size - pad * 2.0
        let radius = badgeSide * 0.262
        let badgeRect = CGRect(x: pad, y: pad, width: badgeSide, height: badgeSide)
        let badgePath = continuousRoundedRectPath(rect: badgeRect, radius: radius)
        let bs = badgeSide / 100.0
        let badgeOrigin = badgeRect.origin

        // 0. Ambient macOS icon drop shadow when using standard 824/1024 icon grid
        // Note: CGContext.setShadow offset is in base device space (+Y is up), so negative height casts shadow downward.
        if useSystemGridMargin && size >= 64 {
            ctx.saveGState()
            ctx.setShadow(
                offset: CGSize(width: 0, height: -size * (10.0 / 1024.0)),
                blur: size * (24.0 / 1024.0),
                color: CGColor(red: 12.0 / 255.0, green: 18.0 / 255.0, blue: 32.0 / 255.0, alpha: 0.18)
            )
            ctx.setFillColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0)
            ctx.addPath(badgePath)
            ctx.fillPath()
            ctx.restoreGState()
        }

        // 1. Ceramic White continuous squircle base (#FFFFFF -> #FAFBFD -> #F1F4F9)
        ctx.saveGState()
        ctx.addPath(badgePath)
        ctx.clip()

        let bgColors: [CGFloat] = [
            1.0, 1.0, 1.0, 1.0,                                 // #FFFFFF Crisp top ceramic highlight
            250.0 / 255.0, 251.0 / 255.0, 253.0 / 255.0, 1.0,   // #FAFBFD Alabaster mid
            241.0 / 255.0, 244.0 / 255.0, 249.0 / 255.0, 1.0    // #F1F4F9 Subtle cool porcelain base
        ]
        if let grad = CGGradient(colorSpace: colorSpace, colorComponents: bgColors, locations: [0.0, 0.65, 1.0], count: 3) {
            ctx.drawLinearGradient(
                grad,
                start: CGPoint(x: badgeRect.midX, y: badgeRect.minY),
                end: CGPoint(x: badgeRect.midX, y: badgeRect.maxY),
                options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
            )
        }

        // Single flush hairline border (clipped to badgePath so zero double-ring artifact occurs)
        ctx.setStrokeColor(red: 15.0 / 255.0, green: 23.0 / 255.0, blue: 42.0 / 255.0, alpha: 0.11)
        ctx.setLineWidth(max(1.0, 1.6 * bs))
        ctx.addPath(badgePath)
        ctx.strokePath()
        ctx.restoreGState()

        // 2. Midground Depth Layer: Translucent Ice-Blue Selection Card (aligned with bracket centerline at 22.5..77.5)
        let cMargin: CGFloat = compactTrayMode ? 21.0 : 22.5
        let cRadius: CGFloat = 7.5
        let cardSide = (100.0 - cMargin * 2.0) * bs
        let cardRect = CGRect(
            x: badgeOrigin.x + cMargin * bs,
            y: badgeOrigin.y + cMargin * bs,
            width: cardSide,
            height: cardSide
        )
        let cardPath = CGPath(
            roundedRect: cardRect,
            cornerWidth: cRadius * bs,
            cornerHeight: cRadius * bs,
            transform: nil
        )

        // Soft downward floating shadow under the selection card
        ctx.saveGState()
        ctx.setShadow(
            offset: CGSize(width: 0, height: -2.5 * bs),
            blur: 6.5 * bs,
            color: CGColor(red: 0.0, green: 82.0 / 255.0, blue: 204.0 / 255.0, alpha: 0.12)
        )
        ctx.setFillColor(red: 236.0 / 255.0, green: 245.0 / 255.0, blue: 255.0 / 255.0, alpha: 1.0)
        ctx.addPath(cardPath)
        ctx.fillPath()
        ctx.restoreGState()

        // Selection card gradient fill (#F2F7FF -> #DFECFF) + subtle blue glass border
        ctx.saveGState()
        ctx.addPath(cardPath)
        ctx.clip()
        let cardColors: [CGFloat] = [
            243.0 / 255.0, 248.0 / 255.0, 255.0 / 255.0, 1.0, // #F3F8FF
            221.0 / 255.0, 236.0 / 255.0, 255.0 / 255.0, 1.0  // #DDECFF
        ]
        if let cardGrad = CGGradient(colorSpace: colorSpace, colorComponents: cardColors, locations: [0.0, 1.0], count: 2) {
            ctx.drawLinearGradient(
                cardGrad,
                start: CGPoint(x: cardRect.minX, y: cardRect.minY),
                end: CGPoint(x: cardRect.maxX, y: cardRect.maxY),
                options: []
            )
        }
        ctx.setStrokeColor(red: 0.0, green: 122.0 / 255.0, blue: 255.0 / 255.0, alpha: 0.25)
        ctx.setLineWidth(max(1.0, 2.2 * bs))
        ctx.addPath(cardPath)
        ctx.strokePath()
        ctx.restoreGState()

        // 3. Foreground Primary Motif: Architectural Space-Black / Titanium Corner Brackets astride the card corners
        let cArm: CGFloat = compactTrayMode ? 17.5 : 17.0
        let cStroke: CGFloat = (compactTrayMode ? 6.8 : 6.2) * bs

        let bracketsPath = CGMutablePath()
        let corners: [(cx: CGFloat, cy: CGFloat, dirX: CGFloat, dirY: CGFloat)] = [
            (cMargin, cMargin, 1, 1),
            (100.0 - cMargin, cMargin, -1, 1),
            (cMargin, 100.0 - cMargin, 1, -1),
            (100.0 - cMargin, 100.0 - cMargin, -1, -1)
        ]
        for c in corners {
            let p1 = CGPoint(x: badgeOrigin.x + (c.cx + c.dirX * cArm) * bs, y: badgeOrigin.y + c.cy * bs)
            let pVert = CGPoint(x: badgeOrigin.x + c.cx * bs, y: badgeOrigin.y + c.cy * bs)
            let p2 = CGPoint(x: badgeOrigin.x + c.cx * bs, y: badgeOrigin.y + (c.cy + c.dirY * cArm) * bs)
            bracketsPath.move(to: p1)
            bracketsPath.addArc(tangent1End: pVert, tangent2End: p2, radius: cRadius * bs)
            bracketsPath.addLine(to: p2)
        }

        let strokedBrackets = bracketsPath.copy(
            strokingWithWidth: cStroke,
            lineCap: .round,
            lineJoin: .round,
            miterLimit: 10.0
        )

        // Downward elevation shadow cast by the dark titanium brackets onto the card & ceramic base
        ctx.saveGState()
        ctx.setShadow(
            offset: CGSize(width: 0, height: -2.6 * bs),
            blur: 5.0 * bs,
            color: CGColor(red: 12.0 / 255.0, green: 18.0 / 255.0, blue: 32.0 / 255.0, alpha: 0.26)
        )
        ctx.setFillColor(red: 24.0 / 255.0, green: 28.0 / 255.0, blue: 35.0 / 255.0, alpha: 1.0)
        ctx.addPath(strokedBrackets)
        ctx.fillPath()
        ctx.restoreGState()

        // Machined Space-Black / Dark-Titanium vertical gradient (#3A4150 -> #1F232C -> #11141A)
        ctx.saveGState()
        ctx.addPath(strokedBrackets)
        ctx.clip()
        let titaniumColors: [CGFloat] = [
            60.0 / 255.0, 66.0 / 255.0, 80.0 / 255.0, 1.0,  // #3C4250 Gunmetal top highlight
            31.0 / 255.0, 35.0 / 255.0, 44.0 / 255.0, 1.0,  // #1F232C Anodized carbon mid
            17.0 / 255.0, 20.0 / 255.0, 26.0 / 255.0, 1.0   // #11141A Deep obsidian base
        ]
        if let tiGrad = CGGradient(colorSpace: colorSpace, colorComponents: titaniumColors, locations: [0.0, 0.5, 1.0], count: 3) {
            ctx.drawLinearGradient(
                tiGrad,
                start: CGPoint(x: badgeOrigin.x + 50.0 * bs, y: badgeOrigin.y + (cMargin - 3.5) * bs),
                end: CGPoint(x: badgeOrigin.x + 50.0 * bs, y: badgeOrigin.y + (100.0 - cMargin + 3.5) * bs),
                options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
            )
        }
        ctx.restoreGState()

        // 4. Focal Point Accent: Luminous Apple-Blue Optical Jewel at Center (50, 50)
        let centerPt = CGPoint(x: badgeOrigin.x + 50.0 * bs, y: badgeOrigin.y + 50.0 * bs)
        let outerRingR: CGFloat = (compactTrayMode ? 9.0 : 8.5) * bs
        let dotR: CGFloat = (compactTrayMode ? 6.5 : 6.0) * bs

        // Crisp white optical collar with soft downward blue elevation glow
        ctx.saveGState()
        ctx.setShadow(
            offset: CGSize(width: 0, height: -2.4 * bs),
            blur: 5.5 * bs,
            color: CGColor(red: 0.0, green: 108.0 / 255.0, blue: 255.0 / 255.0, alpha: 0.34)
        )
        ctx.setFillColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0)
        ctx.fillEllipse(in: CGRect(
            x: centerPt.x - outerRingR,
            y: centerPt.y - outerRingR,
            width: outerRingR * 2.0,
            height: outerRingR * 2.0
        ))
        ctx.restoreGState()

        // Luminous Apple-Blue jewel core (#38A8FF -> #007AFF -> #0051CC)
        let dotRect = CGRect(x: centerPt.x - dotR, y: centerPt.y - dotR, width: dotR * 2.0, height: dotR * 2.0)
        ctx.saveGState()
        ctx.addEllipse(in: dotRect)
        ctx.clip()
        let blueColors: [CGFloat] = [
            58.0 / 255.0, 170.0 / 255.0, 255.0 / 255.0, 1.0, // #3AAAFF Top highlight
            0.0 / 255.0, 122.0 / 255.0, 255.0 / 255.0, 1.0,  // #007AFF Apple Blue
            0.0 / 255.0, 81.0 / 255.0, 204.0 / 255.0, 1.0    // #0051CC Deep sapphire
        ]
        if let blueGrad = CGGradient(colorSpace: colorSpace, colorComponents: blueColors, locations: [0.0, 0.55, 1.0], count: 3) {
            ctx.drawLinearGradient(
                blueGrad,
                start: CGPoint(x: centerPt.x, y: dotRect.minY),
                end: CGPoint(x: centerPt.x, y: dotRect.maxY),
                options: []
            )
        }
        ctx.restoreGState()

        // Subtle optical lens specular highlight dot at top-left of the blue jewel
        let specR = 1.45 * bs
        ctx.saveGState()
        ctx.setFillColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.68)
        ctx.fillEllipse(in: CGRect(
            x: centerPt.x - 2.1 * bs - specR,
            y: centerPt.y - 2.1 * bs - specR,
            width: specR * 2.0,
            height: specR * 2.0
        ))
        ctx.restoreGState()
    }

    #if !PRODUCTION_BUILD
    /// Removes 1-2 LSB horizontal PRNG dither noise injected by `CGGradient` / `setShadow` along scanlines
    /// while preserving 100% of vertical gradient smoothness and anti-aliased edges, cutting PNG/ICNS/TIFF size by ~55-80%.
    private static func cleanScanlineDitherNoise(in rep: NSBitmapImageRep) {
        guard let ptr = rep.bitmapData else { return }
        let w = rep.pixelsWide
        let h = rep.pixelsHigh
        let bpr = rep.bytesPerRow
        for y in 0..<h {
            let row = ptr + y * bpr
            for x in 1..<w {
                let prev = row + (x - 1) * 4
                let cur = row + x * 4
                if abs(Int(cur[3]) - Int(prev[3])) <= 1 &&
                   abs(Int(cur[0]) - Int(prev[0])) <= 2 &&
                   abs(Int(cur[1]) - Int(prev[1])) <= 2 &&
                   abs(Int(cur[2]) - Int(prev[2])) <= 2 {
                    cur[0] = prev[0]
                    cur[1] = prev[1]
                    cur[2] = prev[2]
                    cur[3] = prev[3]
                }
            }
        }
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
            guard let rep = renderAppIconBitmap(pixelSize: spec.pixels, useSystemGridMargin: true) else {
                return false
            }
            cleanScanlineDitherNoise(in: rep)
            guard let pngData = rep.representation(using: .png, properties: [:]) else {
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

            cleanScanlineDitherNoise(in: rep)
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
    #endif

    #if !PRODUCTION_BUILD
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
    #endif
}
