import AppKit
import CoreGraphics
import Foundation

/// High-performance 32-bit BGRA top-down bitmap buffer (byte 0 = B, byte 1 = G, byte 2 = R, byte 3 = A).
/// Matches Windows PixelFormat.Format32bppArgb byte-for-byte for 1:1 StitchEngine compatibility.
public final class RawBitmap {
    public let width: Int
    public let height: Int
    public let stride: Int
    public let pixels: UnsafeMutablePointer<UInt8>
    public var scaleFactor: CGFloat

    public var logicalWidth: CGFloat {
        return CGFloat(width) / max(1.0, scaleFactor)
    }

    public var logicalHeight: CGFloat {
        return CGFloat(height) / max(1.0, scaleFactor)
    }

    public init(width: Int, height: Int, scaleFactor: CGFloat = 1.0) {
        let w = max(1, width)
        let h = max(1, height)
        self.width = w
        self.height = h
        self.stride = w * 4
        self.scaleFactor = max(1.0, scaleFactor)
        let totalBytes = self.stride * h
        self.pixels = UnsafeMutablePointer<UInt8>.allocate(capacity: totalBytes)
        self.pixels.initialize(repeating: 0, count: totalBytes)
    }

    deinit {
        pixels.deallocate()
    }

    public convenience init?(cgImage: CGImage, scaleFactor: CGFloat = 1.0) {
        let w = cgImage.width
        let h = cgImage.height
        guard w > 0 && h > 0 else { return nil }
        self.init(width: w, height: h, scaleFactor: scaleFactor)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        if let ctx = CGContext(
            data: pixels,
            width: w,
            height: h,
            bitsPerComponent: 8,
            bytesPerRow: stride,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) {
            ctx.interpolationQuality = .none
            ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
    }

    public func clone() -> RawBitmap {
        let copy = RawBitmap(width: width, height: height, scaleFactor: scaleFactor)
        memcpy(copy.pixels, pixels, stride * height)
        return copy
    }

    public func clone(x: Int, y: Int, width w: Int, height h: Int) -> RawBitmap {
        let out = RawBitmap(width: w, height: h, scaleFactor: scaleFactor)
        out.copyFrom(src: self, srcX: x, srcY: y, dstX: 0, dstY: 0, width: w, height: h)
        return out
    }

    @inline(__always)
    public func getPixel(x: Int, y: Int) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
        guard x >= 0 && x < width && y >= 0 && y < height else { return (0, 0, 0, 0) }
        let offset = y * stride + x * 4
        return (pixels[offset + 2], pixels[offset + 1], pixels[offset], pixels[offset + 3])
    }

    @inline(__always)
    public func setPixel(x: Int, y: Int, r: UInt8, g: UInt8, b: UInt8, a: UInt8 = 255) {
        guard x >= 0 && x < width && y >= 0 && y < height else { return }
        let offset = y * stride + x * 4
        pixels[offset] = b
        pixels[offset + 1] = g
        pixels[offset + 2] = r
        pixels[offset + 3] = a
    }

    public func clear(r: UInt8, g: UInt8, b: UInt8, a: UInt8 = 255) {
        let pixelVal: UInt32 = (UInt32(a) << 24) | (UInt32(r) << 16) | (UInt32(g) << 8) | UInt32(b)
        let count = width * height
        pixels.withMemoryRebound(to: UInt32.self, capacity: count) { ptr32 in
            for i in 0..<count {
                ptr32[i] = pixelVal
            }
        }
    }

    public func fillRect(x: Int, y: Int, w: Int, h: Int, r: UInt8, g: UInt8, b: UInt8, a: UInt8 = 255) {
        let x0 = max(0, x)
        let y0 = max(0, y)
        let x1 = min(width, x + w)
        let y1 = min(height, y + h)
        guard x1 > x0 && y1 > y0 else { return }

        let pixelVal: UInt32 = (UInt32(a) << 24) | (UInt32(r) << 16) | (UInt32(g) << 8) | UInt32(b)
        for py in y0..<y1 {
            let rowPtr = (pixels + py * stride).withMemoryRebound(to: UInt32.self, capacity: width) { $0 }
            for px in x0..<x1 {
                rowPtr[px] = pixelVal
            }
        }
    }

    public func drawLineHorizontal(x0: Int, x1: Int, y: Int, r: UInt8, g: UInt8, b: UInt8, thickness: Int = 1) {
        let startX = min(x0, x1)
        let endX = max(x0, x1)
        fillRect(x: startX, y: y, w: endX - startX + 1, h: max(1, thickness), r: r, g: g, b: b)
    }

    public func drawLineVertical(x: Int, y0: Int, y1: Int, r: UInt8, g: UInt8, b: UInt8, thickness: Int = 1) {
        let startY = min(y0, y1)
        let endY = max(y0, y1)
        fillRect(x: x, y: startY, w: max(1, thickness), h: endY - startY + 1, r: r, g: g, b: b)
    }

    public func drawRect(x: Int, y: Int, w: Int, h: Int, r: UInt8, g: UInt8, b: UInt8, thickness: Int = 1) {
        guard w > 0 && h > 0 else { return }
        // Matches GDI DrawRectangle(x, y, w, h) which strokes from x..x+w and y..y+h
        drawLineHorizontal(x0: x, x1: x + w, y: y, r: r, g: g, b: b, thickness: thickness)
        drawLineHorizontal(x0: x, x1: x + w, y: y + h, r: r, g: g, b: b, thickness: thickness)
        drawLineVertical(x: x, y0: y, y1: y + h, r: r, g: g, b: b, thickness: thickness)
        drawLineVertical(x: x + w, y0: y, y1: y + h, r: r, g: g, b: b, thickness: thickness)
    }

    public func copyFrom(src: RawBitmap, srcX: Int, srcY: Int, dstX: Int, dstY: Int, width copyW: Int, height copyH: Int) {
        var sx = srcX
        var sy = srcY
        var dx = dstX
        var dy = dstY
        var w = copyW
        var h = copyH

        if sx < 0 { w += sx; dx -= sx; sx = 0 }
        if sy < 0 { h += sy; dy -= sy; sy = 0 }
        if dx < 0 { w += dx; sx -= dx; dx = 0 }
        if dy < 0 { h += dy; sy -= dy; dy = 0 }

        w = min(w, min(src.width - sx, self.width - dx))
        h = min(h, min(src.height - sy, self.height - dy))
        guard w > 0 && h > 0 else { return }

        let rowBytes = w * 4
        for row in 0..<h {
            let srcRow = src.pixels + (sy + row) * src.stride + sx * 4
            let dstRow = self.pixels + (dy + row) * self.stride + dx * 4
            memmove(dstRow, srcRow, rowBytes)
        }
    }

    /// Bilinear subpixel sampling matching GDI+ InterpolationMode.Bilinear + PixelOffsetMode.Half
    public func drawImageBilinear(src: RawBitmap, dstX: Int, dstY: Int, width copyW: Int, height copyH: Int, srcX: Float, srcY: Float) {
        let x0i = Int(floor(srcX))
        let y0i = Int(floor(srcY))
        let fx = srcX - Float(x0i)
        let fy = srcY - Float(y0i)

        if abs(fx) < 1e-4 && abs(fy) < 1e-4 {
            copyFrom(src: src, srcX: x0i, srcY: y0i, dstX: dstX, dstY: dstY, width: copyW, height: copyH)
            return
        }

        let w00 = Int(((1.0 - fx) * (1.0 - fy)) * 256.0 + 0.5)
        let w10 = Int((fx * (1.0 - fy)) * 256.0 + 0.5)
        let w01 = Int(((1.0 - fx) * fy) * 256.0 + 0.5)
        let w11 = max(0, 256 - w00 - w10 - w01)

        for row in 0..<copyH {
            let dy = dstY + row
            if dy < 0 || dy >= self.height { continue }
            let sy0 = max(0, min(src.height - 1, y0i + row))
            let sy1 = max(0, min(src.height - 1, sy0 + 1))

            let srcRow0 = src.pixels + sy0 * src.stride
            let srcRow1 = src.pixels + sy1 * src.stride
            let dstRow = self.pixels + dy * self.stride

            for col in 0..<copyW {
                let dx = dstX + col
                if dx < 0 || dx >= self.width { continue }
                let sx0 = max(0, min(src.width - 1, x0i + col))
                let sx1 = max(0, min(src.width - 1, sx0 + 1))

                let o00 = sx0 * 4
                let o10 = sx1 * 4
                let dOff = dx * 4

                let b = (Int(srcRow0[o00]) * w00 + Int(srcRow0[o10]) * w10 + Int(srcRow1[o00]) * w01 + Int(srcRow1[o10]) * w11 + 128) >> 8
                let g = (Int(srcRow0[o00 + 1]) * w00 + Int(srcRow0[o10 + 1]) * w10 + Int(srcRow1[o00 + 1]) * w01 + Int(srcRow1[o10 + 1]) * w11 + 128) >> 8
                let r = (Int(srcRow0[o00 + 2]) * w00 + Int(srcRow0[o10 + 2]) * w10 + Int(srcRow1[o00 + 2]) * w01 + Int(srcRow1[o10 + 2]) * w11 + 128) >> 8

                dstRow[dOff] = UInt8(clamping: b)
                dstRow[dOff + 1] = UInt8(clamping: g)
                dstRow[dOff + 2] = UInt8(clamping: r)
                dstRow[dOff + 3] = 255
            }
        }
    }

    public func drawScaledFrom(src: RawBitmap, srcX: Int, srcY: Int, srcW: Int, srcH: Int, dstX: Int, dstY: Int, dstW: Int, dstH: Int) {
        guard srcW > 0 && srcH > 0 && dstW > 0 && dstH > 0 else { return }
        for ry in 0..<dstH {
            let dy = dstY + ry
            if dy < 0 || dy >= self.height { continue }
            let sy = min(src.height - 1, max(0, srcY + (ry * srcH) / dstH))
            let srcRow = src.pixels + sy * src.stride
            let dstRow = self.pixels + dy * self.stride
            for rx in 0..<dstW {
                let dx = dstX + rx
                if dx < 0 || dx >= self.width { continue }
                let sx = min(src.width - 1, max(0, srcX + (rx * srcW) / dstW))
                let sOff = sx * 4
                let dOff = dx * 4
                dstRow[dOff] = srcRow[sOff]
                dstRow[dOff + 1] = srcRow[sOff + 1]
                dstRow[dOff + 2] = srcRow[sOff + 2]
                dstRow[dOff + 3] = srcRow[sOff + 3]
            }
        }
    }

    public func withTopDownCGContext(_ body: (CGContext) -> Void) {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        guard let ctx = CGContext(
            data: pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: stride,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else { return }

        ctx.translateBy(x: 0, y: CGFloat(height))
        ctx.scaleBy(x: 1.0, y: -1.0)
        body(ctx)
    }

    public func drawString(_ text: String, x: Int, y: Int, fontSize: CGFloat, bold: Bool = false, r: UInt8, g: UInt8, b: UInt8) {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        guard let ctx = CGContext(
            data: pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: stride,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else { return }

        ctx.setAllowsAntialiasing(true)
        ctx.setShouldAntialias(true)
        ctx.setFillColor(red: CGFloat(r) / 255.0, green: CGFloat(g) / 255.0, blue: CGFloat(b) / 255.0, alpha: 1.0)

        let font = bold ? NSFont.boldSystemFont(ofSize: fontSize) : NSFont.systemFont(ofSize: fontSize)
        let ctFont = font as CTFont
        let attrs: [CFString: Any] = [
            kCTFontAttributeName: ctFont,
            kCTForegroundColorFromContextAttributeName: true
        ]
        guard let cfStr = CFAttributedStringCreate(kCFAllocatorDefault, text as CFString, attrs as CFDictionary) else { return }
        let line = CTLineCreateWithAttributedString(cfStr)
        let ascent = CTFontGetAscent(ctFont)
        ctx.textMatrix = .identity
        ctx.textPosition = CGPoint(x: CGFloat(x), y: CGFloat(height) - CGFloat(y) - ascent)
        CTLineDraw(line, ctx)
    }

    public func toCGImage() -> CGImage? {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        let totalBytes = stride * height
        guard let provider = CGDataProvider(data: NSData(bytes: pixels, length: totalBytes)) else {
            return nil
        }
        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: stride,
            space: colorSpace,
            bitmapInfo: bitmapInfo,
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        )
    }

    public func toNSImage() -> NSImage {
        let size = NSSize(width: logicalWidth, height: logicalHeight)
        guard let cg = toCGImage() else {
            return NSImage(size: size)
        }
        return NSImage(cgImage: cg, size: size)
    }

    public func pngData() -> Data? {
        guard let cg = toCGImage() else { return nil }
        let rep = NSBitmapImageRep(cgImage: cg)
        rep.size = NSSize(width: logicalWidth, height: logicalHeight)
        return rep.representation(using: .png, properties: [:])
    }

    public func jpegData(compression: Float = 0.92) -> Data? {
        guard let cg = toCGImage() else { return nil }
        let rep = NSBitmapImageRep(cgImage: cg)
        rep.size = NSSize(width: logicalWidth, height: logicalHeight)
        return rep.representation(using: .jpeg, properties: [.compressionFactor: compression])
    }
}
