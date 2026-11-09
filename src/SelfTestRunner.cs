using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;

namespace SpanShot
{
    public static class SelfTestRunner
    {
        public static int RunAllTests()
        {
            Console.WriteLine("====================================================");
            Console.WriteLine(" SpanShot Stitching Engine Automated Accuracy Suite ");
            Console.WriteLine("====================================================");

            bool vPass = TestVerticalStitchingWithStickyHeaderAndScrollbar();
            bool hPass = TestHorizontalStitchingWithFrozenColumnAndScrollbar();
            bool sPass = TestSparseWhitespaceAndReverseScroll();
            bool tVertPass = TestSparseExcelTableVerticalStitchingNoLineShift();
            bool tHorizPass = TestSparseExcelTableHorizontalStitchingNoLineShift();
            bool webTablePass = TestEnterpriseWebTableWithWideFrozenLeftAndStaticTopBottom();

            Console.WriteLine("----------------------------------------------------");
            if (vPass && hPass && sPass && tVertPass && tHorizPass && webTablePass)
            {
                Console.WriteLine("OVERALL RESULT: ALL 6 TEST SUITES PASSED (100% Pixel-Exact, 0 Line Shift)");
                return 0;
            }
            else
            {
                Console.WriteLine("OVERALL RESULT: SOME TESTS FAILED");
                return 1;
            }
        }

        private static bool TestVerticalStitchingWithStickyHeaderAndScrollbar()
        {
            Console.WriteLine("\n[Test 1] Vertical Scrolling Stitch (Sticky Header + Moving Scrollbar + Irregular Steps)");

            int viewportW = 500;
            int viewportH = 360;
            int fullDocH = 1200;
            int stickyHeaderH = 42;
            int stickyFooterH = 24;

            using (Bitmap fullDoc = RenderSyntheticDocument(viewportW, fullDocH))
            using (StitchEngine engine = new StitchEngine(ScrollDirection.Vertical))
            {
                int[] scrollSteps = new int[] { 0, 68, 115, 0, 93, 134, 82, 108 };
                int currentScrollY = 0;
                int expectedTotalH = viewportH;

                for (int i = 0; i < scrollSteps.Length; i++)
                {
                    int expectedDelta = scrollSteps[i];
                    currentScrollY += expectedDelta;

                    using (Bitmap viewport = ExtractVerticalViewportWithChrome(
                        fullDoc, viewportW, viewportH, currentScrollY, stickyHeaderH, stickyFooterH, fullDocH))
                    {
                        StitchResult res = engine.PushFrame(viewport);

                        if (i == 0)
                        {
                            if (res.Status != StitchStatus.FirstFrame) return false;
                        }
                        else if (expectedDelta == 0)
                        {
                            if (res.Status != StitchStatus.NoMovement || res.DeltaPixels != 0) return false;
                        }
                        else
                        {
                            expectedTotalH += expectedDelta;
                            int err = Math.Abs(res.DeltaPixels - expectedDelta);
                            Console.WriteLine("  Frame {0}: ExpectedDelta={1}px, ActualDelta={2}px (Err={3}px), Confidence={4:P1}, StickyHead={5}px",
                                i, expectedDelta, res.DeltaPixels, err, res.Confidence, res.DetectedStickyHead);

                            if (res.Status != StitchStatus.Stitched || err > 1)
                            {
                                Console.WriteLine("  [FAIL] Vertical delta mismatch!");
                                return false;
                            }
                        }
                    }
                }

                using (Bitmap stitched = engine.RenderStitchedBitmap())
                {
                    Console.WriteLine("  Final Stitched Size: {0} x {1} px (Expected Height: {2} px)",
                        stitched.Width, stitched.Height, expectedTotalH);
                    if (Math.Abs(stitched.Height - expectedTotalH) > 2) return false;
                }
            }

            Console.WriteLine("  -> [PASS] Vertical Scrolling Stitch Verified!");
            return true;
        }

        private static bool TestHorizontalStitchingWithFrozenColumnAndScrollbar()
        {
            Console.WriteLine("\n[Test 2] Horizontal Scrolling Stitch (Frozen Left Column + Bottom Scrollbar + Irregular Steps)");

            int viewportW = 420;
            int viewportH = 340;
            int fullDocW = 1400;
            int frozenLeftW = 48;
            int frozenRightW = 20;

            using (Bitmap fullWideSheet = RenderSyntheticWideSpreadsheet(fullDocW, viewportH))
            using (StitchEngine engine = new StitchEngine(ScrollDirection.Horizontal))
            {
                int[] scrollSteps = new int[] { 0, 74, 126, 0, 91, 145, 88, 112 };
                int currentScrollX = 0;
                int expectedTotalW = viewportW;

                for (int i = 0; i < scrollSteps.Length; i++)
                {
                    int expectedDelta = scrollSteps[i];
                    currentScrollX += expectedDelta;

                    using (Bitmap viewport = ExtractHorizontalViewportWithChrome(
                        fullWideSheet, viewportW, viewportH, currentScrollX, frozenLeftW, frozenRightW, fullDocW))
                    {
                        StitchResult res = engine.PushFrame(viewport);

                        if (i == 0)
                        {
                            if (res.Status != StitchStatus.FirstFrame) return false;
                        }
                        else if (expectedDelta == 0)
                        {
                            if (res.Status != StitchStatus.NoMovement || res.DeltaPixels != 0) return false;
                        }
                        else
                        {
                            expectedTotalW += expectedDelta;
                            int err = Math.Abs(res.DeltaPixels - expectedDelta);
                            Console.WriteLine("  Frame {0}: ExpectedDelta={1}px, ActualDelta={2}px (Err={3}px), Confidence={4:P1}, FrozenLeft={5}px",
                                i, expectedDelta, res.DeltaPixels, err, res.Confidence, res.DetectedStickyHead);

                            if (res.Status != StitchStatus.Stitched || err > 1)
                            {
                                Console.WriteLine("  [FAIL] Horizontal delta mismatch!");
                                return false;
                            }
                        }
                    }
                }

                using (Bitmap stitched = engine.RenderStitchedBitmap())
                {
                    Console.WriteLine("  Final Stitched Size: {0} x {1} px (Expected Width: {2} px)",
                        stitched.Width, stitched.Height, expectedTotalW);
                    if (Math.Abs(stitched.Width - expectedTotalW) > 2) return false;
                }
            }

            Console.WriteLine("  -> [PASS] Horizontal Scrolling Stitch Verified!");
            return true;
        }

        private static bool TestSparseWhitespaceAndReverseScroll()
        {
            Console.WriteLine("\n[Test 3] Reverse-Scroll Protection & Undo Recovery");

            int viewportW = 460;
            int viewportH = 340;
            int fullDocH = 1000;

            using (Bitmap fullDoc = RenderSyntheticDocument(viewportW, fullDocH))
            using (StitchEngine engine = new StitchEngine(ScrollDirection.Vertical))
            {
                using (Bitmap f0 = ExtractVerticalViewportWithChrome(fullDoc, viewportW, viewportH, 100, 0, 0, fullDocH))
                {
                    engine.PushFrame(f0);
                }

                using (Bitmap f1 = ExtractVerticalViewportWithChrome(fullDoc, viewportW, viewportH, 190, 0, 0, fullDocH))
                {
                    StitchResult r1 = engine.PushFrame(f1);
                    if (r1.Status != StitchStatus.Stitched || Math.Abs(r1.DeltaPixels - 90) > 1) return false;
                }

                using (Bitmap f2 = ExtractVerticalViewportWithChrome(fullDoc, viewportW, viewportH, 145, 0, 0, fullDocH))
                {
                    StitchResult r2 = engine.PushFrame(f2);
                    if (r2.Status != StitchStatus.ScrolledBackward || r2.TotalLength != viewportH + 90) return false;
                }

                using (Bitmap f3 = ExtractVerticalViewportWithChrome(fullDoc, viewportW, viewportH, 265, 0, 0, fullDocH))
                {
                    StitchResult r3 = engine.PushFrame(f3);
                    if (r3.Status != StitchStatus.Stitched || Math.Abs(r3.DeltaPixels - 75) > 1) return false;
                }

                bool undone = engine.UndoLastFrame();
                if (!undone || engine.TotalCanvasLength != viewportH + 90 || engine.FrameCount != 2) return false;
            }

            Console.WriteLine("  -> [PASS] Reverse-Scroll Protection & Undo Verified!");
            return true;
        }

        /// <summary>
        /// Specifically tests the user-reported bug:
        /// Pure white Excel-style table with uniform 32px row height, 1px gray grid lines,
        /// and sparse cell text where grid lines previously shifted or falsely triggered sticky-tail cutting.
        /// Verifies 0-pixel error against ground truth across the entire stitched table!
        /// </summary>
        private static bool TestSparseExcelTableVerticalStitchingNoLineShift()
        {
            Console.WriteLine("\n[Test 4] Sparse Excel-Style Table Vertical Stitch (Uniform 32px Rows, 1px Grid, Pixel-Exact Verification)");

            int tableW = 540;
            int viewportH = 320;
            int fullTableH = 1100;

            using (Bitmap groundTruthTable = RenderPureWhiteExcelTable(tableW, fullTableH, 32, 130))
            using (StitchEngine engine = new StitchEngine(ScrollDirection.Vertical))
            {
                // Include steps that are multiples of row height (64px) AND non-multiples (51px, 77px, 95px, 43px)
                int[] steps = new int[] { 0, 51, 64, 77, 95, 43, 88, 70 };
                int scrollY = 0;

                for (int i = 0; i < steps.Length; i++)
                {
                    scrollY += steps[i];
                    using (Bitmap frame = groundTruthTable.Clone(new Rectangle(0, scrollY, tableW, viewportH), PixelFormat.Format32bppArgb))
                    {
                        StitchResult res = engine.PushFrame(frame);
                        if (i > 0)
                        {
                            int err = Math.Abs(res.DeltaPixels - steps[i]);
                            Console.WriteLine("  Table Vert Step {0}: Expected={1}px, Actual={2}px (Err={3}px), StickyHead={4}px, StickyTail={5}px",
                                i, steps[i], res.DeltaPixels, err, res.DetectedStickyHead, res.DetectedStickyTail);
                            if (res.Status != StitchStatus.Stitched || err != 0)
                            {
                                Console.WriteLine("  [FAIL] Table vertical step had non-zero pixel error!");
                                return false;
                            }
                        }
                    }
                }

                int totalExpectedH = viewportH + scrollY;
                using (Bitmap stitched = engine.RenderStitchedBitmap())
                {
                    if (stitched.Height != totalExpectedH)
                    {
                        Console.WriteLine("  [FAIL] Stitched height {0} != expected {1}", stitched.Height, totalExpectedH);
                        return false;
                    }

                    // Pixel-by-pixel verification against groundTruthTable to ensure ZERO line shift or text occlusion!
                    int mismatchedPixels = CountMismatchedPixels(stitched, groundTruthTable, tableW, totalExpectedH);
                    Console.WriteLine("  Pixel-by-Pixel Ground Truth Comparison: {0} mismatched pixels out of {1}",
                        mismatchedPixels, tableW * totalExpectedH);
                    if (mismatchedPixels != 0)
                    {
                        Console.WriteLine("  [FAIL] Stitched table has pixel discrepancy / line shift!");
                        return false;
                    }
                }
            }

            Console.WriteLine("  -> [PASS] Sparse Excel Table Vertical Stitch: 0 Line Shift, 100% Identical to Ground Truth!");
            return true;
        }

        private static bool TestSparseExcelTableHorizontalStitchingNoLineShift()
        {
            Console.WriteLine("\n[Test 5] Sparse Excel-Style Table Horizontal Stitch (Uniform 120px Cols, 1px Grid, Pixel-Exact Verification)");

            int viewportW = 440;
            int tableH = 340;
            int fullTableW = 1300;

            using (Bitmap groundTruthTable = RenderPureWhiteExcelTable(fullTableW, tableH, 32, 120))
            using (StitchEngine engine = new StitchEngine(ScrollDirection.Horizontal))
            {
                int[] steps = new int[] { 0, 63, 120, 85, 97, 54, 110 };
                int scrollX = 0;

                for (int i = 0; i < steps.Length; i++)
                {
                    scrollX += steps[i];
                    using (Bitmap frame = groundTruthTable.Clone(new Rectangle(scrollX, 0, viewportW, tableH), PixelFormat.Format32bppArgb))
                    {
                        StitchResult res = engine.PushFrame(frame);
                        if (i > 0)
                        {
                            int err = Math.Abs(res.DeltaPixels - steps[i]);
                            Console.WriteLine("  Table Horiz Step {0}: Expected={1}px, Actual={2}px (Err={3}px), StickyHead={4}px, StickyTail={5}px",
                                i, steps[i], res.DeltaPixels, err, res.DetectedStickyHead, res.DetectedStickyTail);
                            if (res.Status != StitchStatus.Stitched || err != 0)
                            {
                                Console.WriteLine("  [FAIL] Table horizontal step had non-zero pixel error!");
                                return false;
                            }
                        }
                    }
                }

                int totalExpectedW = viewportW + scrollX;
                using (Bitmap stitched = engine.RenderStitchedBitmap())
                {
                    if (stitched.Width != totalExpectedW)
                    {
                        Console.WriteLine("  [FAIL] Stitched width {0} != expected {1}", stitched.Width, totalExpectedW);
                        return false;
                    }

                    int mismatchedPixels = CountMismatchedPixels(stitched, groundTruthTable, totalExpectedW, tableH);
                    Console.WriteLine("  Pixel-by-Pixel Ground Truth Comparison: {0} mismatched pixels out of {1}",
                        mismatchedPixels, totalExpectedW * tableH);
                    if (mismatchedPixels != 0)
                    {
                        Console.WriteLine("  [FAIL] Stitched horizontal table has pixel discrepancy / line shift!");
                        return false;
                    }
                }
            }

            Console.WriteLine("  -> [PASS] Sparse Excel Table Horizontal Stitch: 0 Line Shift, 100% Identical to Ground Truth!");
            return true;
        }

        private static Bitmap RenderPureWhiteExcelTable(int width, int height, int rowH, int colW)
        {
            Bitmap bmp = new Bitmap(width, height, PixelFormat.Format32bppArgb);
            using (Graphics g = Graphics.FromImage(bmp))
            using (Pen gridPen = new Pen(Color.FromArgb(212, 216, 222), 1f))
            using (Font cellFont = new Font("Microsoft YaHei UI", 9f, FontStyle.Regular))
            {
                // 100% uniform white background like real Excel / Feishu sheet
                g.Clear(Color.White);

                for (int y = 0; y < height; y += rowH)
                {
                    g.DrawLine(gridPen, 0, y, width, y);
                }
                for (int x = 0; x < width; x += colW)
                {
                    g.DrawLine(gridPen, x, 0, x, height);
                }

                // Sparse cell text (lots of whitespace inside each cell, only small text in left portion)
                int rows = height / rowH;
                int cols = width / colW;
                for (int r = 0; r < rows; r++)
                {
                    for (int c = 0; c < cols; c++)
                    {
                        int x = c * colW;
                        int y = r * rowH;
                        string cellVal = (c == 0)
                            ? string.Format("{0}", 1001 + r)
                            : string.Format("¥{0:N2}", (r + 1) * 37.5 + (c + 1) * 14.2);
                        g.DrawString(cellVal, cellFont, Brushes.Black, x + 8, y + 7);
                    }
                }
            }
            return bmp;
        }

        private static unsafe int CountMismatchedPixels(Bitmap a, Bitmap b, int w, int h)
        {
            Rectangle r = new Rectangle(0, 0, w, h);
            BitmapData da = a.LockBits(r, ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
            BitmapData db = b.LockBits(r, ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
            int mismatches = 0;
            try
            {
                byte* pa = (byte*)da.Scan0;
                byte* pb = (byte*)db.Scan0;
                for (int y = 0; y < h; y++)
                {
                    int* rowA = (int*)(pa + y * da.Stride);
                    int* rowB = (int*)(pb + y * db.Stride);
                    for (int x = 0; x < w; x++)
                    {
                        if (rowA[x] != rowB[x]) mismatches++;
                    }
                }
            }
            finally
            {
                a.UnlockBits(da);
                b.UnlockBits(db);
            }
            return mismatches;
        }

        private static Bitmap RenderSyntheticDocument(int width, int height)
        {
            Bitmap bmp = new Bitmap(width, height, PixelFormat.Format32bppArgb);
            using (Graphics g = Graphics.FromImage(bmp))
            using (Font f = new Font("Consolas", 10f, FontStyle.Bold))
            {
                g.Clear(Color.FromArgb(252, 252, 255));
                for (int y = 10; y < height - 24; y += 28)
                {
                    int lineIdx = y / 28;
                    Color rowBg = (lineIdx % 2 == 0) ? Color.White : Color.FromArgb(240, 245, 252);
                    using (SolidBrush b = new SolidBrush(rowBg))
                    {
                        g.FillRectangle(b, 10, y, width - 30, 24);
                    }
                    Color tagColor = Color.FromArgb((lineIdx * 53) % 200, (lineIdx * 97) % 180, (lineIdx * 31) % 210);
                    using (SolidBrush tb = new SolidBrush(tagColor))
                    {
                        g.FillRectangle(tb, 16, y + 3, 36, 18);
                    }
                    g.DrawString(string.Format("Line #{0:D3} - SpanShot Vertical Content Verification Row [{1}]", lineIdx, y * 17),
                        f, Brushes.Black, 60, y + 3);
                }
            }
            return bmp;
        }

        private static Bitmap ExtractVerticalViewportWithChrome(
            Bitmap fullDoc, int vw, int vh, int scrollY, int stickyHeaderH, int stickyFooterH, int totalDocH)
        {
            Bitmap view = new Bitmap(vw, vh, PixelFormat.Format32bppArgb);
            using (Graphics g = Graphics.FromImage(view))
            using (Font headerFont = new Font("Segoe UI", 10f, FontStyle.Bold))
            {
                int bodyH = vh - stickyHeaderH - stickyFooterH;
                g.DrawImage(fullDoc,
                    new Rectangle(0, stickyHeaderH, vw, bodyH),
                    new Rectangle(0, stickyHeaderH + scrollY, vw, bodyH),
                    GraphicsUnit.Pixel);

                if (stickyHeaderH > 0)
                {
                    g.FillRectangle(Brushes.DarkSlateBlue, 0, 0, vw, stickyHeaderH);
                    g.DrawString("STICKY NAVBAR HEADER (FIXED)", headerFont, Brushes.White, 14, 10);
                }

                if (stickyFooterH > 0)
                {
                    g.FillRectangle(Brushes.DimGray, 0, vh - stickyFooterH, vw, stickyFooterH);
                }

                g.FillRectangle(Brushes.LightGray, vw - 12, stickyHeaderH, 12, bodyH);
                int thumbY = stickyHeaderH + (scrollY * (bodyH - 40)) / Math.Max(1, totalDocH - vh);
                g.FillRectangle(Brushes.DodgerBlue, vw - 11, thumbY, 10, 40);
            }
            return view;
        }

        private static Bitmap RenderSyntheticWideSpreadsheet(int width, int height)
        {
            Bitmap bmp = new Bitmap(width, height, PixelFormat.Format32bppArgb);
            using (Graphics g = Graphics.FromImage(bmp))
            using (Font f = new Font("Consolas", 9.5f, FontStyle.Bold))
            using (Pen gridPen = new Pen(Color.FromArgb(205, 214, 226), 1f))
            {
                g.Clear(Color.White);
                int colW = 110;
                int rowH = 36;
                for (int c = 0; c < width / colW; c++)
                {
                    for (int r = 0; r < height / rowH; r++)
                    {
                        int x = c * colW;
                        int y = r * rowH;
                        Color bg = ((c + r) % 2 == 0) ? Color.White : Color.FromArgb(243, 247, 253);
                        using (SolidBrush b = new SolidBrush(bg))
                        {
                            g.FillRectangle(b, x, y, colW, rowH);
                        }
                        g.DrawRectangle(gridPen, x, y, colW, rowH);

                        Color indicator = Color.FromArgb((c * 67 + r * 29) % 210, (c * 37 + r * 71) % 190, (c * 83) % 220);
                        using (SolidBrush ib = new SolidBrush(indicator))
                        {
                            g.FillRectangle(ib, x + 5, y + 6, 14, 22);
                        }
                        g.DrawString(string.Format("C{0:D2}R{1:D2}", c, r), f, Brushes.DarkSlateGray, x + 24, y + 9);
                    }
                }
            }
            return bmp;
        }

        private static Bitmap ExtractHorizontalViewportWithChrome(
            Bitmap fullSheet, int vw, int vh, int scrollX, int frozenLeftW, int frozenRightW, int totalDocW)
        {
            Bitmap view = new Bitmap(vw, vh, PixelFormat.Format32bppArgb);
            using (Graphics g = Graphics.FromImage(view))
            {
                int bodyW = vw - frozenLeftW - frozenRightW;
                g.DrawImage(fullSheet,
                    new Rectangle(frozenLeftW, 0, bodyW, vh),
                    new Rectangle(frozenLeftW + scrollX, 0, bodyW, vh),
                    GraphicsUnit.Pixel);

                if (frozenLeftW > 0)
                {
                    g.FillRectangle(Brushes.Teal, 0, 0, frozenLeftW, vh);
                }

                if (frozenRightW > 0)
                {
                    g.FillRectangle(Brushes.SlateGray, vw - frozenRightW, 0, frozenRightW, vh);
                }

                g.FillRectangle(Brushes.LightGray, frozenLeftW, vh - 12, bodyW, 12);
                int thumbX = frozenLeftW + (scrollX * (bodyW - 40)) / Math.Max(1, totalDocW - vw);
                g.FillRectangle(Brushes.MediumSeaGreen, thumbX, vh - 11, 40, 10);
            }
            return view;
        }

        private static bool TestEnterpriseWebTableWithWideFrozenLeftAndStaticTopBottom()
        {
            Console.WriteLine("\n[Test 6] Enterprise Web Table (53% Frozen Left + Repetitive Input Boxes + Hover Noise + Large/Small Steps)");

            int vw = 900;
            int vh = 260;
            int frozenLeftW = 476; // 53% of width!
            int topBarH = 90;      // 35% of height!
            int bottomBarH = 64;   // 25% of height!
            int bodyScrollW = 2200;

            using (Bitmap scrollColsBmp = RenderEnterpriseScrollableColumns(bodyScrollW, vh - topBarH - bottomBarH))
            using (StitchEngine engine = new StitchEngine(ScrollDirection.Horizontal))
            {
                // Includes:
                // - Initial stationary hover frame right after FirstFrame (steps[1] = 0px) before any scroll
                // - Fractional/subpixel steps (28.5px, 35.5px) across 5 identical "[ 请输入 ]" columns (guards against 125%/150% DPI subpixel failure)
                // - Subpixel settling twitch (0.6px) + input-box hover/focus border change (guards against duplicate stitch on smooth-scroll tail)
                // - Large step (182px > 165px colW) across identical "[ 请输入 ]" columns (guards against -165px alias)
                // - Steps across empty-data-cell columns (c=5..8 where only 14px header text moves)
                float[] steps = new float[] { 0f, 0f, 28.5f, 35.5f, 0.6f, 181.4f, 74.5f, 0f, 104.5f, 66f, 84f, 78.5f, 95.5f, 62f };
                float curScrollX = 0f;
                float lastStitchedScrollX = 0f;
                int expectedTotalW = vw;

                for (int i = 0; i < steps.Length; i++)
                {
                    float stepDelta = steps[i];
                    curScrollX += stepDelta;
                    bool hoverRow = (i % 2 == 1);
                    bool focusInputBox = (stepDelta < 2.0f && i > 0);

                    using (Bitmap frame = RenderEnterpriseTableViewport(
                        scrollColsBmp, vw, vh, frozenLeftW, topBarH, bottomBarH, curScrollX, bodyScrollW, hoverRow, focusInputBox))
                    {
                        StitchResult res = engine.PushFrame(frame);
                        if (i == 0)
                        {
                            if (res.Status != StitchStatus.FirstFrame) return false;
                            continue;
                        }

                        if (stepDelta < 2.0f)
                        {
                            Console.WriteLine("  WebTable Hover/SubpixelSettle Step {0} (shift={1:F1}px): Expected=NoMovement, ActualStatus={2}, ActualDelta={3}px",
                                i, stepDelta, res.Status, res.DeltaPixels);
                            if (res.Status != StitchStatus.NoMovement || res.DeltaPixels != 0)
                            {
                                Console.WriteLine("  -> [FAIL] Hover or subpixel settling frame caused false/duplicate stitch!");
                                return false;
                            }
                            continue;
                        }

                        int expectedDelta = (int)Math.Round(curScrollX - lastStitchedScrollX);
                        lastStitchedScrollX = curScrollX;
                        expectedTotalW += res.DeltaPixels;
                        int err = Math.Abs(res.DeltaPixels - expectedDelta);
                        Console.WriteLine("  WebTable Horiz Step {0}: Status={1}, Expected={2}px, Actual={3}px (Err={4}px), FrozenLeft={5}px, Conf={6:F3}",
                            i, res.Status, expectedDelta, res.DeltaPixels, err, res.DetectedStickyHead, res.Confidence);

                        if (res.Status != StitchStatus.Stitched || err > 1)
                        {
                            Console.WriteLine("  -> [FAIL] Enterprise web table step failed!");
                            return false;
                        }
                    }
                }

                using (Bitmap stitched = engine.RenderStitchedBitmap())
                {
                    Console.WriteLine("  Final Stitched WebTable Size: {0} x {1} px (Expected Width: {2} px)",
                        stitched.Width, stitched.Height, expectedTotalW);
                    if (Math.Abs(stitched.Width - expectedTotalW) > 4)
                    {
                        Console.WriteLine("  -> [FAIL] Final stitched width mismatch!");
                        return false;
                    }
                }

                Console.WriteLine("  -> [PASS] Enterprise Web Table Horizontal Stitch Verified!");
                return true;
            }
        }

        private static Bitmap RenderEnterpriseScrollableColumns(int width, int height)
        {
            Bitmap bmp = new Bitmap(width, height, PixelFormat.Format32bppArgb);
            using (Graphics g = Graphics.FromImage(bmp))
            using (Font headerFont = new Font("Microsoft YaHei UI", 9.5f, FontStyle.Bold))
            using (Font cellFont = new Font("Microsoft YaHei UI", 9f, FontStyle.Regular))
            using (Pen borderPen = new Pen(Color.FromArgb(235, 238, 245), 1f))
            using (Pen inputPen = new Pen(Color.FromArgb(215, 218, 226), 1f))
            {
                g.Clear(Color.White);
                int headerH = 44;
                using (SolidBrush hb = new SolidBrush(Color.FromArgb(248, 248, 249)))
                {
                    g.FillRectangle(hb, 0, 0, width, headerH);
                }
                g.DrawLine(borderPen, 0, 0, width, 0);
                g.DrawLine(borderPen, 0, headerH, width, headerH);
                g.DrawLine(borderPen, 0, height - 1, width, height - 1);

                string[] colTitles = new string[]
                {
                    "本次申报金额 (含税)", "本次申报金额 (不含税)", "本次申报税额", "累计申报金额 (含税)",
                    "累计申报金额 (不含税)", "质保金比例 (%)", "本次核减金额", "累计支付金额",
                    "已开票金额 (含税: ...", "不含税开票额", "增值税税额", "备注"
                };
                int colW = 165;
                for (int c = 0; c < width / colW; c++)
                {
                    int x = c * colW;
                    g.DrawLine(borderPen, x, 0, x, height);
                    string title = colTitles[c % colTitles.Length];
                    g.DrawString(title, headerFont, Brushes.Black, x + 18, 13);

                    if (c <= 4)
                    {
                        // 5 consecutive columns with IDENTICAL "请输入" input boxes!
                        g.DrawRectangle(inputPen, x + 16, headerH + 12, colW - 32, 34);
                        g.DrawString("请输入", cellFont, Brushes.Silver, x + 56, headerH + 20);
                    }
                    else if (c >= 5 && c <= 8)
                    {
                        // Columns in the second half with COMPLETELY EMPTY white data cells (only header text moves!)
                    }
                    else
                    {
                        g.DrawString("0", cellFont, Brushes.DimGray, x + 76, headerH + 22);
                    }
                }
            }
            return bmp;
        }

        private static Bitmap RenderEnterpriseTableViewport(
            Bitmap scrollColsBmp, int vw, int vh, int frozenLeftW, int topBarH, int bottomBarH, float scrollX, int totalScrollW, bool rowHover, bool focusInputBox)
        {
            Bitmap bmp = new Bitmap(vw, vh, PixelFormat.Format32bppArgb);
            using (Graphics g = Graphics.FromImage(bmp))
            using (Font fBold = new Font("Microsoft YaHei UI", 9.5f, FontStyle.Bold))
            using (Font fReg = new Font("Microsoft YaHei UI", 9f, FontStyle.Regular))
            using (Pen linePen = new Pen(Color.FromArgb(235, 238, 245), 1f))
            using (Pen btnPen = new Pen(Color.FromArgb(64, 158, 255), 1f))
            {
                g.Clear(Color.White);

                // 1. Static top bar (35% of height: "分包合同结算明细", "+ 添加行", "删除")
                g.DrawString("分包合同结算明细", fReg, Brushes.DodgerBlue, 10, 14);
                g.DrawLine(linePen, 120, 22, vw - 10, 22);
                g.DrawRectangle(btnPen, 10, 42, 74, 30);
                g.DrawString("+ 添加行", fReg, Brushes.DodgerBlue, 18, 49);
                g.DrawRectangle(btnPen, 94, 42, 62, 30);
                g.DrawString("删除", fReg, Brushes.DodgerBlue, 110, 49);

                // 2. Frozen left columns (53% of width: checkbox, 序号, 结算明细编号, 子项编号)
                int bodyH = vh - topBarH - bottomBarH;
                using (SolidBrush hb = new SolidBrush(Color.FromArgb(248, 248, 249)))
                {
                    g.FillRectangle(hb, 10, topBarH, frozenLeftW - 10, 44);
                }
                if (rowHover)
                {
                    using (SolidBrush hoverB = new SolidBrush(Color.FromArgb(245, 247, 250)))
                    {
                        g.FillRectangle(hoverB, 10, topBarH + 45, frozenLeftW - 10, bodyH - 45);
                    }
                }
                g.DrawRectangle(linePen, 10, topBarH, frozenLeftW - 10, bodyH);
                g.DrawString("序号", fBold, Brushes.Black, 100, topBarH + 13);
                g.DrawString("结算明细编号", fBold, Brushes.Black, 200, topBarH + 13);
                g.DrawString("子项编号", fBold, Brushes.Black, 355, topBarH + 13);

                g.DrawString("1", fReg, Brushes.Black, 112, topBarH + 66);
                g.DrawString("10053064820001", fReg, Brushes.SteelBlue, 335, topBarH + 66);

                // Vertical frozen column shadow line at x = frozenLeftW
                using (Pen shadowPen = new Pen(Color.FromArgb(215, 220, 228), 2f))
                {
                    g.DrawLine(shadowPen, frozenLeftW - 1, topBarH, frozenLeftW - 1, vh - 10);
                }

                // 3. Scrollable right columns (47% of width, 40% of height) with subpixel bilinear interpolation support
                int rightW = vw - frozenLeftW - 8;
                g.InterpolationMode = InterpolationMode.Bilinear;
                g.PixelOffsetMode = PixelOffsetMode.Half;
                g.DrawImage(scrollColsBmp,
                    new RectangleF(frozenLeftW, topBarH, rightW, bodyH),
                    new RectangleF(scrollX, 0f, rightW, bodyH),
                    GraphicsUnit.Pixel);
                g.PixelOffsetMode = PixelOffsetMode.Default;
                int intScrollX = (int)Math.Round(scrollX);
                if (focusInputBox)
                {
                    // Simulate mouse hovering/focusing an input box inside the scrollable region (changing 133px border color!)
                    int colW = 165;
                    int firstVisibleCol = (intScrollX / colW) + 1;
                    int boxScreenX = frozenLeftW + (firstVisibleCol * colW - intScrollX) + 16;
                    if (boxScreenX >= frozenLeftW && boxScreenX + (colW - 32) < frozenLeftW + rightW)
                    {
                        using (Pen focusPen = new Pen(Color.FromArgb(64, 158, 255), 1f))
                        {
                            g.DrawRectangle(focusPen, boxScreenX, topBarH + 44 + 12, colW - 32, 34);
                        }
                    }
                }
                if (rowHover)
                {
                    for (int y = topBarH + 45; y < topBarH + bodyH; y++)
                    {
                        for (int x = frozenLeftW; x < frozenLeftW + rightW; x++)
                        {
                            Color c = bmp.GetPixel(x, y);
                            if (c.R > 248 && c.G > 248 && c.B > 248)
                            {
                                bmp.SetPixel(x, y, Color.FromArgb(245, 247, 250));
                            }
                        }
                    }
                }

                // 4. Stationary right-edge vertical scrollbar thumb (x = vw - 12 .. vw - 6) + Opposite-moving horizontal scrollbar thumb
                using (SolidBrush vsbBrush = new SolidBrush(Color.FromArgb(194, 195, 196)))
                {
                    g.FillRectangle(vsbBrush, vw - 12, topBarH + 46, 7, bodyH - 48);
                }

                int sbY = topBarH + bodyH;
                int thumbW = 110;
                int thumbX = frozenLeftW + (intScrollX * Math.Max(10, rightW - thumbW)) / Math.Max(1, totalScrollW - rightW);
                using (SolidBrush sbBrush = new SolidBrush(Color.FromArgb(193, 193, 193)))
                {
                    g.FillRectangle(sbBrush, thumbX, sbY, thumbW, 7);
                }

                g.DrawRectangle(linePen, 10, sbY + 8, vw - 18, bottomBarH - 16);
                g.DrawString("合计:", fReg, Brushes.Black, 105, sbY + 24);
            }
            return bmp;
        }
    }
}
