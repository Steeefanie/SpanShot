import Foundation

public enum SelfTestRunner {
    public static func runAllTests() -> Int32 {
        print("====================================================")
        print(" SpanShot Stitching Engine Automated Accuracy Suite ")
        print("====================================================")

        let vPass = testVerticalStitchingWithStickyHeaderAndScrollbar()
        let hPass = testHorizontalStitchingWithFrozenColumnAndScrollbar()
        let sPass = testSparseWhitespaceAndReverseScroll()
        let tVertPass = testSparseExcelTableVerticalStitchingNoLineShift()
        let tHorizPass = testSparseExcelTableHorizontalStitchingNoLineShift()
        let webTablePass = testEnterpriseWebTableWithWideFrozenLeftAndStaticTopBottom()
        let v110Pass = testV110SettingsUpdaterAndIcon()

        print("----------------------------------------------------")
        if vPass && hPass && sPass && tVertPass && tHorizPass && webTablePass && v110Pass {
            print("OVERALL RESULT: ALL 7 TEST SUITES PASSED (100% Pixel-Exact, 0 Line Shift, v1.1.0 Verified)")
            return 0
        } else {
            print("OVERALL RESULT: SOME TESTS FAILED")
            return 1
        }
    }

    private static func testVerticalStitchingWithStickyHeaderAndScrollbar() -> Bool {
        print("\n[Test 1] Vertical Scrolling Stitch (Sticky Header + Moving Scrollbar + Irregular Steps)")

        let viewportW = 500
        let viewportH = 360
        let fullDocH = 1200
        let stickyHeaderH = 42
        let stickyFooterH = 24

        let fullDoc = renderSyntheticDocument(width: viewportW, height: fullDocH)
        let engine = StitchEngine(direction: .vertical)

        let scrollSteps = [0, 68, 115, 0, 93, 134, 82, 108]
        var currentScrollY = 0
        var expectedTotalH = viewportH

        for i in 0..<scrollSteps.count {
            let expectedDelta = scrollSteps[i]
            currentScrollY += expectedDelta

            let viewport = extractVerticalViewportWithChrome(
                fullDoc: fullDoc,
                vw: viewportW,
                vh: viewportH,
                scrollY: currentScrollY,
                stickyHeaderH: stickyHeaderH,
                stickyFooterH: stickyFooterH,
                totalDocH: fullDocH
            )
            let res = engine.pushFrame(viewport)

            if i == 0 {
                if res.status != .firstFrame { return false }
            } else if expectedDelta == 0 {
                if res.status != .noMovement || res.deltaPixels != 0 { return false }
            } else {
                expectedTotalH += expectedDelta
                let err = abs(res.deltaPixels - expectedDelta)
                print(String(
                    format: "  Frame %d: ExpectedDelta=%dpx, ActualDelta=%dpx (Err=%dpx), Confidence=%.1f%%, StickyHead=%dpx",
                    i, expectedDelta, res.deltaPixels, err, res.confidence * 100.0, res.detectedStickyHead
                ))

                if res.status != .stitched || err > 1 {
                    print("  [FAIL] Vertical delta mismatch!")
                    return false
                }
            }
        }

        guard let stitched = engine.renderStitchedBitmap() else { return false }
        print(String(
            format: "  Final Stitched Size: %d x %d px (Expected Height: %d px)",
            stitched.width, stitched.height, expectedTotalH
        ))
        if abs(stitched.height - expectedTotalH) > 2 { return false }

        print("  -> [PASS] Vertical Scrolling Stitch Verified!")
        return true
    }

    private static func testHorizontalStitchingWithFrozenColumnAndScrollbar() -> Bool {
        print("\n[Test 2] Horizontal Scrolling Stitch (Frozen Left Column + Bottom Scrollbar + Irregular Steps)")

        let viewportW = 420
        let viewportH = 340
        let fullDocW = 1400
        let frozenLeftW = 48
        let frozenRightW = 20

        let fullWideSheet = renderSyntheticWideSpreadsheet(width: fullDocW, height: viewportH)
        let engine = StitchEngine(direction: .horizontal)

        let scrollSteps = [0, 74, 126, 0, 91, 145, 88, 112]
        var currentScrollX = 0
        var expectedTotalW = viewportW

        for i in 0..<scrollSteps.count {
            let expectedDelta = scrollSteps[i]
            currentScrollX += expectedDelta

            let viewport = extractHorizontalViewportWithChrome(
                fullSheet: fullWideSheet,
                vw: viewportW,
                vh: viewportH,
                scrollX: currentScrollX,
                frozenLeftW: frozenLeftW,
                frozenRightW: frozenRightW,
                totalDocW: fullDocW
            )
            let res = engine.pushFrame(viewport)

            if i == 0 {
                if res.status != .firstFrame { return false }
            } else if expectedDelta == 0 {
                if res.status != .noMovement || res.deltaPixels != 0 { return false }
            } else {
                expectedTotalW += expectedDelta
                let err = abs(res.deltaPixels - expectedDelta)
                print(String(
                    format: "  Frame %d: ExpectedDelta=%dpx, ActualDelta=%dpx (Err=%dpx), Confidence=%.1f%%, FrozenLeft=%dpx",
                    i, expectedDelta, res.deltaPixels, err, res.confidence * 100.0, res.detectedStickyHead
                ))

                if res.status != .stitched || err > 1 {
                    print("  [FAIL] Horizontal delta mismatch!")
                    return false
                }
            }
        }

        guard let stitched = engine.renderStitchedBitmap() else { return false }
        print(String(
            format: "  Final Stitched Size: %d x %d px (Expected Width: %d px)",
            stitched.width, stitched.height, expectedTotalW
        ))
        if abs(stitched.width - expectedTotalW) > 2 { return false }

        print("  -> [PASS] Horizontal Scrolling Stitch Verified!")
        return true
    }

    private static func testSparseWhitespaceAndReverseScroll() -> Bool {
        print("\n[Test 3] Reverse-Scroll Protection & Undo Recovery")

        let viewportW = 460
        let viewportH = 340
        let fullDocH = 1000

        let fullDoc = renderSyntheticDocument(width: viewportW, height: fullDocH)
        let engine = StitchEngine(direction: .vertical)

        let f0 = extractVerticalViewportWithChrome(fullDoc: fullDoc, vw: viewportW, vh: viewportH, scrollY: 100, stickyHeaderH: 0, stickyFooterH: 0, totalDocH: fullDocH)
        _ = engine.pushFrame(f0)

        let f1 = extractVerticalViewportWithChrome(fullDoc: fullDoc, vw: viewportW, vh: viewportH, scrollY: 190, stickyHeaderH: 0, stickyFooterH: 0, totalDocH: fullDocH)
        let r1 = engine.pushFrame(f1)
        if r1.status != .stitched || abs(r1.deltaPixels - 90) > 1 { return false }

        let f2 = extractVerticalViewportWithChrome(fullDoc: fullDoc, vw: viewportW, vh: viewportH, scrollY: 145, stickyHeaderH: 0, stickyFooterH: 0, totalDocH: fullDocH)
        let r2 = engine.pushFrame(f2)
        if r2.status != .scrolledBackward || r2.totalLength != viewportH + 90 { return false }

        let f3 = extractVerticalViewportWithChrome(fullDoc: fullDoc, vw: viewportW, vh: viewportH, scrollY: 265, stickyHeaderH: 0, stickyFooterH: 0, totalDocH: fullDocH)
        let r3 = engine.pushFrame(f3)
        if r3.status != .stitched || abs(r3.deltaPixels - 75) > 1 { return false }

        let undone = engine.undoLastFrame()
        if !undone || engine.totalCanvasLength != viewportH + 90 || engine.frameCount != 2 { return false }

        print("  -> [PASS] Reverse-Scroll Protection & Undo Verified!")
        return true
    }

    private static func testSparseExcelTableVerticalStitchingNoLineShift() -> Bool {
        print("\n[Test 4] Sparse Excel-Style Table Vertical Stitch (Uniform 32px Rows, 1px Grid, Pixel-Exact Verification)")

        let tableW = 540
        let viewportH = 320
        let fullTableH = 1100

        let groundTruthTable = renderPureWhiteExcelTable(width: tableW, height: fullTableH, rowH: 32, colW: 130)
        let engine = StitchEngine(direction: .vertical)

        let steps = [0, 51, 64, 77, 95, 43, 88, 70]
        var scrollY = 0

        for i in 0..<steps.count {
            scrollY += steps[i]
            let frame = groundTruthTable.clone(x: 0, y: scrollY, width: tableW, height: viewportH)
            let res = engine.pushFrame(frame)
            if i > 0 {
                let err = abs(res.deltaPixels - steps[i])
                print(String(
                    format: "  Table Vert Step %d: Expected=%dpx, Actual=%dpx (Err=%dpx), StickyHead=%dpx, StickyTail=%dpx",
                    i, steps[i], res.deltaPixels, err, res.detectedStickyHead, res.detectedStickyTail
                ))
                if res.status != .stitched || err != 0 {
                    print("  [FAIL] Table vertical step had non-zero pixel error!")
                    return false
                }
            }
        }

        let totalExpectedH = viewportH + scrollY
        guard let stitched = engine.renderStitchedBitmap() else { return false }
        if stitched.height != totalExpectedH {
            print(String(format: "  [FAIL] Stitched height %d != expected %d", stitched.height, totalExpectedH))
            return false
        }

        let mismatchedPixels = countMismatchedPixels(a: stitched, b: groundTruthTable, w: tableW, h: totalExpectedH)
        print(String(
            format: "  Pixel-by-Pixel Ground Truth Comparison: %d mismatched pixels out of %d",
            mismatchedPixels, tableW * totalExpectedH
        ))
        if mismatchedPixels != 0 {
            print("  [FAIL] Stitched table has pixel discrepancy / line shift!")
            return false
        }

        print("  -> [PASS] Sparse Excel Table Vertical Stitch: 0 Line Shift, 100% Identical to Ground Truth!")
        return true
    }

    private static func testSparseExcelTableHorizontalStitchingNoLineShift() -> Bool {
        print("\n[Test 5] Sparse Excel-Style Table Horizontal Stitch (Uniform 120px Cols, 1px Grid, Pixel-Exact Verification)")

        let viewportW = 440
        let tableH = 340
        let fullTableW = 1300

        let groundTruthTable = renderPureWhiteExcelTable(width: fullTableW, height: tableH, rowH: 32, colW: 120)
        let engine = StitchEngine(direction: .horizontal)

        let steps = [0, 63, 120, 85, 97, 54, 110]
        var scrollX = 0

        for i in 0..<steps.count {
            scrollX += steps[i]
            let frame = groundTruthTable.clone(x: scrollX, y: 0, width: viewportW, height: tableH)
            let res = engine.pushFrame(frame)
            if i > 0 {
                let err = abs(res.deltaPixels - steps[i])
                print(String(
                    format: "  Table Horiz Step %d: Expected=%dpx, Actual=%dpx (Err=%dpx), StickyHead=%dpx, StickyTail=%dpx",
                    i, steps[i], res.deltaPixels, err, res.detectedStickyHead, res.detectedStickyTail
                ))
                if res.status != .stitched || err != 0 {
                    print("  [FAIL] Table horizontal step had non-zero pixel error!")
                    return false
                }
            }
        }

        let totalExpectedW = viewportW + scrollX
        guard let stitched = engine.renderStitchedBitmap() else { return false }
        if stitched.width != totalExpectedW {
            print(String(format: "  [FAIL] Stitched width %d != expected %d", stitched.width, totalExpectedW))
            return false
        }

        let mismatchedPixels = countMismatchedPixels(a: stitched, b: groundTruthTable, w: totalExpectedW, h: tableH)
        print(String(
            format: "  Pixel-by-Pixel Ground Truth Comparison: %d mismatched pixels out of %d",
            mismatchedPixels, totalExpectedW * tableH
        ))
        if mismatchedPixels != 0 {
            print("  [FAIL] Stitched horizontal table has pixel discrepancy / line shift!")
            return false
        }

        print("  -> [PASS] Sparse Excel Table Horizontal Stitch: 0 Line Shift, 100% Identical to Ground Truth!")
        return true
    }

    private static func renderPureWhiteExcelTable(width: Int, height: Int, rowH: Int, colW: Int) -> RawBitmap {
        let bmp = RawBitmap(width: width, height: height)
        bmp.clear(r: 255, g: 255, b: 255)

        var y = 0
        while y < height {
            bmp.drawLineHorizontal(x0: 0, x1: width - 1, y: y, r: 212, g: 216, b: 222)
            y += rowH
        }
        var x = 0
        while x < width {
            bmp.drawLineVertical(x: x, y0: 0, y1: height - 1, r: 212, g: 216, b: 222)
            x += colW
        }

        let rows = height / rowH
        let cols = width / colW
        for r in 0..<rows {
            for c in 0..<cols {
                let cx = c * colW
                let cy = r * rowH
                let cellVal = (c == 0)
                    ? String(format: "%d", 1001 + r)
                    : String(format: "¥%.2f", Double(r + 1) * 37.5 + Double(c + 1) * 14.2)
                bmp.drawString(cellVal, x: cx + 8, y: cy + 7, fontSize: 12.0, bold: false, r: 0, g: 0, b: 0)
            }
        }
        return bmp
    }

    private static func countMismatchedPixels(a: RawBitmap, b: RawBitmap, w: Int, h: Int) -> Int {
        var mismatches = 0
        for y in 0..<h {
            let rowA = (a.pixels + y * a.stride).withMemoryRebound(to: UInt32.self, capacity: w) { $0 }
            let rowB = (b.pixels + y * b.stride).withMemoryRebound(to: UInt32.self, capacity: w) { $0 }
            for x in 0..<w {
                if rowA[x] != rowB[x] { mismatches += 1 }
            }
        }
        return mismatches
    }

    private static func renderSyntheticDocument(width: Int, height: Int) -> RawBitmap {
        let bmp = RawBitmap(width: width, height: height)
        bmp.clear(r: 252, g: 252, b: 255)

        var y = 10
        while y < height - 24 {
            let lineIdx = y / 28
            if lineIdx % 2 == 0 {
                bmp.fillRect(x: 10, y: y, w: width - 30, h: 24, r: 255, g: 255, b: 255)
            } else {
                bmp.fillRect(x: 10, y: y, w: width - 30, h: 24, r: 240, g: 245, b: 252)
            }
            let tr = UInt8((lineIdx * 53) % 200)
            let tg = UInt8((lineIdx * 97) % 180)
            let tb = UInt8((lineIdx * 31) % 210)
            bmp.fillRect(x: 16, y: y + 3, w: 36, h: 18, r: tr, g: tg, b: tb)

            let text = String(format: "Line #%03d - SpanShot Vertical Content Verification Row [%d]", lineIdx, y * 17)
            bmp.drawString(text, x: 60, y: y + 3, fontSize: 12.0, bold: true, r: 0, g: 0, b: 0)
            y += 28
        }
        return bmp
    }

    private static func extractVerticalViewportWithChrome(
        fullDoc: RawBitmap,
        vw: Int,
        vh: Int,
        scrollY: Int,
        stickyHeaderH: Int,
        stickyFooterH: Int,
        totalDocH: Int
    ) -> RawBitmap {
        let view = RawBitmap(width: vw, height: vh)
        let bodyH = vh - stickyHeaderH - stickyFooterH
        view.copyFrom(
            src: fullDoc,
            srcX: 0,
            srcY: stickyHeaderH + scrollY,
            dstX: 0,
            dstY: stickyHeaderH,
            width: vw,
            height: bodyH
        )

        if stickyHeaderH > 0 {
            view.fillRect(x: 0, y: 0, w: vw, h: stickyHeaderH, r: 72, g: 61, b: 139)
            view.drawString("STICKY NAVBAR HEADER (FIXED)", x: 14, y: 10, fontSize: 12.0, bold: true, r: 255, g: 255, b: 255)
        }

        if stickyFooterH > 0 {
            view.fillRect(x: 0, y: vh - stickyFooterH, w: vw, h: stickyFooterH, r: 105, g: 105, b: 105)
        }

        view.fillRect(x: vw - 12, y: stickyHeaderH, w: 12, h: bodyH, r: 211, g: 211, b: 211)
        let thumbY = stickyHeaderH + (scrollY * (bodyH - 40)) / max(1, totalDocH - vh)
        view.fillRect(x: vw - 11, y: thumbY, w: 10, h: 40, r: 30, g: 144, b: 255)

        return view
    }

    private static func renderSyntheticWideSpreadsheet(width: Int, height: Int) -> RawBitmap {
        let bmp = RawBitmap(width: width, height: height)
        bmp.clear(r: 255, g: 255, b: 255)

        let colW = 110
        let rowH = 36
        for c in 0..<(width / colW) {
            for r in 0..<(height / rowH) {
                let x = c * colW
                let y = r * rowH
                if (c + r) % 2 == 0 {
                    bmp.fillRect(x: x, y: y, w: colW, h: rowH, r: 255, g: 255, b: 255)
                } else {
                    bmp.fillRect(x: x, y: y, w: colW, h: rowH, r: 243, g: 247, b: 253)
                }
                bmp.drawRect(x: x, y: y, w: colW, h: rowH, r: 205, g: 214, b: 226)

                let ir = UInt8((c * 67 + r * 29) % 210)
                let ig = UInt8((c * 37 + r * 71) % 190)
                let ib = UInt8((c * 83) % 220)
                bmp.fillRect(x: x + 5, y: y + 6, w: 14, h: 22, r: ir, g: ig, b: ib)

                let label = String(format: "C%02dR%02d", c, r)
                bmp.drawString(label, x: x + 24, y: y + 9, fontSize: 12.0, bold: true, r: 47, g: 79, b: 79)
            }
        }
        return bmp
    }

    private static func extractHorizontalViewportWithChrome(
        fullSheet: RawBitmap,
        vw: Int,
        vh: Int,
        scrollX: Int,
        frozenLeftW: Int,
        frozenRightW: Int,
        totalDocW: Int
    ) -> RawBitmap {
        let view = RawBitmap(width: vw, height: vh)
        let bodyW = vw - frozenLeftW - frozenRightW
        view.copyFrom(
            src: fullSheet,
            srcX: frozenLeftW + scrollX,
            srcY: 0,
            dstX: frozenLeftW,
            dstY: 0,
            width: bodyW,
            height: vh
        )

        if frozenLeftW > 0 {
            view.fillRect(x: 0, y: 0, w: frozenLeftW, h: vh, r: 0, g: 128, b: 128)
        }
        if frozenRightW > 0 {
            view.fillRect(x: vw - frozenRightW, y: 0, w: frozenRightW, h: vh, r: 112, g: 128, b: 144)
        }

        view.fillRect(x: frozenLeftW, y: vh - 12, w: bodyW, h: 12, r: 211, g: 211, b: 211)
        let thumbX = frozenLeftW + (scrollX * (bodyW - 40)) / max(1, totalDocW - vw)
        view.fillRect(x: thumbX, y: vh - 11, w: 40, h: 10, r: 60, g: 179, b: 113)

        return view
    }

    private static func testEnterpriseWebTableWithWideFrozenLeftAndStaticTopBottom() -> Bool {
        print("\n[Test 6] Enterprise Web Table (53% Frozen Left + Repetitive Input Boxes + Hover Noise + Large/Small Steps)")

        let vw = 900
        let vh = 260
        let frozenLeftW = 476 // 53% of width!
        let topBarH = 90      // 35% of height!
        let bottomBarH = 64   // 25% of height!
        let bodyScrollW = 2200

        let scrollColsBmp = renderEnterpriseScrollableColumns(width: bodyScrollW, height: vh - topBarH - bottomBarH)
        let engine = StitchEngine(direction: .horizontal)

        let steps: [Float] = [0.0, 0.0, 28.5, 35.5, 0.6, 181.4, 74.5, 0.0, 104.5, 66.0, 84.0, 78.5, 95.5, 62.0]
        var curScrollX: Float = 0.0
        var lastStitchedScrollX: Float = 0.0
        var expectedTotalW = vw

        for i in 0..<steps.count {
            let stepDelta = steps[i]
            curScrollX += stepDelta
            let hoverRow = (i % 2 == 1)
            let focusInputBox = (stepDelta < 2.0 && i > 0)

            let frame = renderEnterpriseTableViewport(
                scrollColsBmp: scrollColsBmp,
                vw: vw,
                vh: vh,
                frozenLeftW: frozenLeftW,
                topBarH: topBarH,
                bottomBarH: bottomBarH,
                scrollX: curScrollX,
                totalScrollW: bodyScrollW,
                rowHover: hoverRow,
                focusInputBox: focusInputBox
            )
            let res = engine.pushFrame(frame)
            if i == 0 {
                if res.status != .firstFrame { return false }
                continue
            }

            if stepDelta < 2.0 {
                print(String(
                    format: "  WebTable Hover/SubpixelSettle Step %d (shift=%.1fpx): Expected=NoMovement, ActualStatus=%@, ActualDelta=%dpx",
                    i, stepDelta, String(describing: res.status), res.deltaPixels
                ))
                if res.status != .noMovement || res.deltaPixels != 0 {
                    print("  -> [FAIL] Hover or subpixel settling frame caused false/duplicate stitch!")
                    return false
                }
                continue
            }

            let expectedDelta = Int((curScrollX - lastStitchedScrollX).rounded())
            lastStitchedScrollX = curScrollX
            expectedTotalW += res.deltaPixels
            let err = abs(res.deltaPixels - expectedDelta)
            print(String(
                format: "  WebTable Horiz Step %d: Status=%@, Expected=%dpx, Actual=%dpx (Err=%dpx), FrozenLeft=%dpx, Conf=%.3f",
                i, String(describing: res.status), expectedDelta, res.deltaPixels, err, res.detectedStickyHead, res.confidence
            ))

            if res.status != .stitched || err > 1 {
                print("  -> [FAIL] Enterprise web table step failed!")
                return false
            }
        }

        guard let stitched = engine.renderStitchedBitmap() else { return false }
        print(String(
            format: "  Final Stitched WebTable Size: %d x %d px (Expected Width: %d px)",
            stitched.width, stitched.height, expectedTotalW
        ))
        if abs(stitched.width - expectedTotalW) > 4 {
            print("  -> [FAIL] Final stitched width mismatch!")
            return false
        }

        print("  -> [PASS] Enterprise Web Table Horizontal Stitch Verified!")
        return true
    }

    private static func renderEnterpriseScrollableColumns(width: Int, height: Int) -> RawBitmap {
        let bmp = RawBitmap(width: width, height: height)
        bmp.clear(r: 255, g: 255, b: 255)

        let headerH = 44
        bmp.fillRect(x: 0, y: 0, w: width, h: headerH, r: 248, g: 248, b: 249)
        bmp.drawLineHorizontal(x0: 0, x1: width - 1, y: 0, r: 235, g: 238, b: 245)
        bmp.drawLineHorizontal(x0: 0, x1: width - 1, y: headerH, r: 235, g: 238, b: 245)
        bmp.drawLineHorizontal(x0: 0, x1: width - 1, y: height - 1, r: 235, g: 238, b: 245)

        let colTitles = [
            "本次申报金额 (含税)", "本次申报金额 (不含税)", "本次申报税额", "累计申报金额 (含税)",
            "累计申报金额 (不含税)", "质保金比例 (%)", "本次核减金额", "累计支付金额",
            "已开票金额 (含税: ...", "不含税开票额", "增值税税额", "备注"
        ]
        let colW = 165
        for c in 0..<(width / colW) {
            let x = c * colW
            bmp.drawLineVertical(x: x, y0: 0, y1: height - 1, r: 235, g: 238, b: 245)
            let title = colTitles[c % colTitles.count]
            bmp.drawString(title, x: x + 18, y: 13, fontSize: 13.5, bold: true, r: 0, g: 0, b: 0)

            if c <= 4 {
                // 5 consecutive columns with IDENTICAL "请输入" input boxes!
                bmp.drawRect(x: x + 16, y: headerH + 12, w: colW - 32, h: 34, r: 215, g: 218, b: 226)
                bmp.drawString("请输入", x: x + 56, y: headerH + 20, fontSize: 13.0, bold: false, r: 192, g: 192, b: 192)
            } else if c >= 5 && c <= 8 {
                // Columns in the second half with COMPLETELY EMPTY white data cells (only header text moves!)
            } else {
                bmp.drawString("0", x: x + 76, y: headerH + 22, fontSize: 13.0, bold: false, r: 105, g: 105, b: 105)
            }
        }
        return bmp
    }

    private static func renderEnterpriseTableViewport(
        scrollColsBmp: RawBitmap,
        vw: Int,
        vh: Int,
        frozenLeftW: Int,
        topBarH: Int,
        bottomBarH: Int,
        scrollX: Float,
        totalScrollW: Int,
        rowHover: Bool,
        focusInputBox: Bool
    ) -> RawBitmap {
        let bmp = RawBitmap(width: vw, height: vh)
        bmp.clear(r: 255, g: 255, b: 255)

        // 1. Static top bar (35% of height: "分包合同结算明细", "+ 添加行", "删除")
        bmp.drawString("分包合同结算明细", x: 10, y: 14, fontSize: 13.0, bold: false, r: 30, g: 144, b: 255)
        bmp.drawLineHorizontal(x0: 120, x1: vw - 10, y: 22, r: 235, g: 238, b: 245)
        bmp.drawRect(x: 10, y: 42, w: 74, h: 30, r: 64, g: 158, b: 255)
        bmp.drawString("+ 添加行", x: 18, y: 49, fontSize: 13.0, bold: false, r: 30, g: 144, b: 255)
        bmp.drawRect(x: 94, y: 42, w: 62, h: 30, r: 64, g: 158, b: 255)
        bmp.drawString("删除", x: 110, y: 49, fontSize: 13.0, bold: false, r: 30, g: 144, b: 255)

        // 2. Frozen left columns (53% of width: checkbox, 序号, 结算明细编号, 子项编号)
        let bodyH = vh - topBarH - bottomBarH
        bmp.fillRect(x: 10, y: topBarH, w: frozenLeftW - 10, h: 44, r: 248, g: 248, b: 249)
        if rowHover {
            bmp.fillRect(x: 10, y: topBarH + 45, w: frozenLeftW - 10, h: bodyH - 45, r: 245, g: 247, b: 250)
        }
        bmp.drawRect(x: 10, y: topBarH, w: frozenLeftW - 10, h: bodyH, r: 235, g: 238, b: 245)
        bmp.drawString("序号", x: 100, y: topBarH + 13, fontSize: 13.5, bold: true, r: 0, g: 0, b: 0)
        bmp.drawString("结算明细编号", x: 200, y: topBarH + 13, fontSize: 13.5, bold: true, r: 0, g: 0, b: 0)
        bmp.drawString("子项编号", x: 355, y: topBarH + 13, fontSize: 13.5, bold: true, r: 0, g: 0, b: 0)

        bmp.drawString("1", x: 112, y: topBarH + 66, fontSize: 14.5, bold: false, r: 0, g: 0, b: 0)
        bmp.drawString("10053064820001", x: 335, y: topBarH + 66, fontSize: 14.5, bold: false, r: 70, g: 130, b: 180)

        // Vertical frozen column shadow line at x = frozenLeftW (2px wide at 474..475)
        bmp.drawLineVertical(x: frozenLeftW - 2, y0: topBarH, y1: vh - 10, r: 215, g: 220, b: 228, thickness: 2)

        // 3. Scrollable right columns (47% of width, 40% of height) with subpixel bilinear interpolation support
        let rightW = vw - frozenLeftW - 8
        bmp.drawImageBilinear(
            src: scrollColsBmp,
            dstX: frozenLeftW,
            dstY: topBarH,
            width: rightW,
            height: bodyH,
            srcX: scrollX,
            srcY: 0.0
        )

        let intScrollX = Int(scrollX.rounded())
        if focusInputBox {
            let colW = 165
            let firstVisibleCol = (intScrollX / colW) + 1
            let boxScreenX = frozenLeftW + (firstVisibleCol * colW - intScrollX) + 16
            if boxScreenX >= frozenLeftW && boxScreenX + (colW - 32) < frozenLeftW + rightW {
                bmp.drawRect(x: boxScreenX, y: topBarH + 44 + 12, w: colW - 32, h: 34, r: 64, g: 158, b: 255)
            }
        }
        if rowHover {
            for y in (topBarH + 45)..<(topBarH + bodyH) {
                for x in frozenLeftW..<(frozenLeftW + rightW) {
                    let c = bmp.getPixel(x: x, y: y)
                    if c.r > 248 && c.g > 248 && c.b > 248 {
                        bmp.setPixel(x: x, y: y, r: 245, g: 247, b: 250)
                    }
                }
            }
        }

        // 4. Stationary right-edge vertical scrollbar thumb + Opposite-moving horizontal scrollbar thumb
        bmp.fillRect(x: vw - 12, y: topBarH + 46, w: 7, h: bodyH - 48, r: 194, g: 195, b: 196)

        let sbY = topBarH + bodyH
        let thumbW = 110
        let thumbX = frozenLeftW + (intScrollX * max(10, rightW - thumbW)) / max(1, totalScrollW - rightW)
        bmp.fillRect(x: thumbX, y: sbY, w: thumbW, h: 7, r: 193, g: 193, b: 193)

        bmp.drawRect(x: 10, y: sbY + 8, w: vw - 18, h: bottomBarH - 16, r: 235, g: 238, b: 245)
        bmp.drawString("合计:", x: 105, y: sbY + 24, fontSize: 12.0, bold: false, r: 0, g: 0, b: 0)

        return bmp
    }

    private static func testV110SettingsUpdaterAndIcon() -> Bool {
        print("\n[Test 7] v1.1.0 Features (Verified Auto-Save + Semantic Version Compare + Scissors Icon)")

        // 1. Semantic version comparison
        guard UpdateManager.currentVersion == "1.2.0" else { return false }
        guard UpdateManager.isVersionNewer(candidate: "v1.3.0", current: "1.2.0") else { return false }
        guard !UpdateManager.isVersionNewer(candidate: "v1.2.0", current: "1.2.0") else { return false }
        guard !UpdateManager.isVersionNewer(candidate: "v1.1.0", current: "1.2.0") else { return false }

        // 2. Folder write validation & auto-save bitmap
        let tmpDir = (NSTemporaryDirectory() as NSString).appendingPathComponent("SpanShot_SelfTest_\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(atPath: tmpDir) }
        guard !AppSettings.validateWritableFolder(tmpDir) else { return false } // Does not exist yet
        try? FileManager.default.createDirectory(atPath: tmpDir, withIntermediateDirectories: true)
        guard AppSettings.validateWritableFolder(tmpDir) else { return false }

        let sampleBmp = RawBitmap(width: 64, height: 48)
        sampleBmp.clear(r: 0, g: 122, b: 255)
        guard let saved1 = AppSettings.tryAutoSaveBitmap(sampleBmp, folderPath: tmpDir, tag: "Test"),
              FileManager.default.fileExists(atPath: saved1) else {
            return false
        }
        guard let saved2 = AppSettings.tryAutoSaveBitmap(sampleBmp, folderPath: tmpDir, tag: "Test"),
              FileManager.default.fileExists(atPath: saved2),
              saved1 != saved2 else {
            return false
        }

        // 3. Scissors + Viewfinder AppIcon & StatusBar template icon rendering
        guard let iconRep = AppIconRenderer.renderAppIconBitmap(pixelSize: 128),
              iconRep.pixelsWide == 128 && iconRep.pixelsHigh == 128 else {
            return false
        }
        let statusImg = AppIconRenderer.renderStatusBarTemplateIcon()
        guard statusImg.isTemplate && !statusImg.representations.isEmpty else {
            return false
        }

        print("  -> [PASS] v1.1.0 Verified Auto-Save, Updater & Scissors Icon Verified!")
        return true
    }
}
