using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.IO;
using System.Runtime.InteropServices;
using System.Windows.Forms;

namespace SpanShot
{
    internal static class AppIcon
    {
        private static Icon _windowIcon;
        private static Icon _trayIcon;
        private static Bitmap _headerLogo;

        public static Icon GetWindowIcon()
        {
            if (_windowIcon == null)
            {
                _windowIcon = CreateSingleSizeIcon(32);
            }
            return _windowIcon;
        }

        public static Icon GetTrayIcon()
        {
            if (_trayIcon == null)
            {
                int sz = 16;
                try
                {
                    sz = Math.Max(16, Math.Min(64, SystemInformation.SmallIconSize.Width));
                }
                catch { sz = 16; }
                _trayIcon = CreateSingleSizeIcon(sz);
            }
            return _trayIcon;
        }

        public static Bitmap GetHeaderBitmap(int pixelSize)
        {
            pixelSize = Math.Max(16, pixelSize);
            if (_headerLogo == null || _headerLogo.Width != pixelSize)
            {
                if (_headerLogo != null) _headerLogo.Dispose();
                _headerLogo = RenderIconBitmap(pixelSize);
            }
            return _headerLogo;
        }

        public static Icon CreateSingleSizeIcon(int size)
        {
            using (Bitmap bmp = RenderIconBitmap(size))
            using (MemoryStream ms = new MemoryStream())
            {
                WriteIcoWithBitmaps(ms, new Bitmap[] { bmp }, false);
                ms.Position = 0;
                return new Icon(ms);
            }
        }

        public static void SaveMultiSizeIco(string filePath)
        {
            int[] sizes = new int[] { 16, 20, 24, 32, 48, 256 };
            Bitmap[] bitmaps = new Bitmap[sizes.Length];
            try
            {
                for (int i = 0; i < sizes.Length; i++)
                {
                    bitmaps[i] = RenderIconBitmap(sizes[i]);
                }

                string dir = Path.GetDirectoryName(filePath);
                if (!string.IsNullOrEmpty(dir) && !Directory.Exists(dir))
                {
                    Directory.CreateDirectory(dir);
                }

                using (FileStream fs = new FileStream(filePath, FileMode.Create, FileAccess.Write, FileShare.Read))
                {
                    WriteIcoWithBitmaps(fs, bitmaps, true);
                }
            }
            finally
            {
                for (int i = 0; i < bitmaps.Length; i++)
                {
                    if (bitmaps[i] != null) bitmaps[i].Dispose();
                }
            }
        }

        /// <summary>
        /// Renders the SpanShot icon: Apple-Blue gradient squircle + screenshot crop brackets + open scissors.
        /// Tuned across 16px..256px for crisp system tray & desktop rendering.
        /// </summary>
        public static Bitmap RenderIconBitmap(int size)
        {
            // Supersample small sizes at 4x and downsample with HighQualityBicubic for ultra-clean anti-aliasing
            int renderSize = size < 64 ? size * 4 : size;
            using (Bitmap hiRes = RenderCore(renderSize, size <= 24))
            {
                if (renderSize == size)
                {
                    return (Bitmap)hiRes.Clone();
                }

                Bitmap target = new Bitmap(size, size, PixelFormat.Format32bppArgb);
                using (Graphics g = Graphics.FromImage(target))
                {
                    g.Clear(Color.Transparent);
                    g.InterpolationMode = InterpolationMode.HighQualityBicubic;
                    g.SmoothingMode = SmoothingMode.HighQuality;
                    g.PixelOffsetMode = PixelOffsetMode.HighQuality;
                    g.CompositingQuality = CompositingQuality.HighQuality;
                    g.DrawImage(hiRes, new Rectangle(0, 0, size, size));
                }
                return target;
            }
        }

        private static Bitmap RenderCore(int size, bool compactTrayMode)
        {
            Bitmap bmp = new Bitmap(size, size, PixelFormat.Format32bppArgb);
            using (Graphics g = Graphics.FromImage(bmp))
            {
                g.Clear(Color.Transparent);
                g.SmoothingMode = SmoothingMode.HighQuality;
                g.PixelOffsetMode = PixelOffsetMode.HighQuality;
                g.CompositingQuality = CompositingQuality.HighQuality;

                float s = size / 100f;
                float pad = compactTrayMode ? 2.2f * s : 4.5f * s;
                float badgeSide = size - pad * 2f;
                float radius = badgeSide * 0.235f;
                RectangleF badgeRect = new RectangleF(pad, pad, badgeSide, badgeSide);

                // 1. Vibrant Apple-Blue gradient squircle background
                using (GraphicsPath badgePath = CreateRoundedRectPathF(badgeRect, radius))
                {
                    using (LinearGradientBrush bgBrush = new LinearGradientBrush(
                        new PointF(pad, pad),
                        new PointF(pad + badgeSide, pad + badgeSide),
                        Color.FromArgb(255, 32, 158, 255),
                        Color.FromArgb(255, 0, 82, 218)))
                    {
                        ColorBlend blend = new ColorBlend(3);
                        blend.Colors = new Color[]
                        {
                            Color.FromArgb(255, 36, 164, 255), // Luminous sky blue
                            Color.FromArgb(255, 0, 122, 255),  // Signature #007AFF
                            Color.FromArgb(255, 0, 78, 210)    // Deep cobalt
                        };
                        blend.Positions = new float[] { 0f, 0.52f, 1f };
                        bgBrush.InterpolationColors = blend;
                        g.FillPath(bgBrush, badgePath);
                    }

                    // Subtle top-left gloss highlight & crisp rim
                    float rimInset = Math.Max(0.5f, 0.7f * s);
                    RectangleF innerRim = new RectangleF(
                        badgeRect.X + rimInset,
                        badgeRect.Y + rimInset,
                        badgeRect.Width - rimInset * 2f,
                        badgeRect.Height - rimInset * 2f);
                    using (GraphicsPath rimPath = CreateRoundedRectPathF(innerRim, Math.Max(1f, radius - rimInset)))
                    using (LinearGradientBrush rimBrush = new LinearGradientBrush(
                        new PointF(0, badgeRect.Top),
                        new PointF(0, badgeRect.Bottom),
                        Color.FromArgb(55, 255, 255, 255),
                        Color.FromArgb(22, 0, 18, 55)))
                    using (Pen rimPen = new Pen(rimBrush, Math.Max(1f, 1.15f * s)))
                    {
                        g.DrawPath(rimPen, rimPath);
                    }
                }

                // 2. Screenshot Viewfinder Corner Brackets (Top-Left, Top-Right, Bottom-Right)
                float cMargin = compactTrayMode ? 15.5f : 18.0f;
                float cArm = compactTrayMode ? 12.0f : 12.5f;
                float cRadius = 3.8f;
                float cStroke = (compactTrayMode ? 5.5f : 4.6f) * s;
                Color bracketColor = Color.FromArgb(compactTrayMode ? 235 : 220, 255, 255, 255);

                using (Pen bracketPen = new Pen(bracketColor, cStroke)
                {
                    StartCap = LineCap.Round,
                    EndCap = LineCap.Round,
                    LineJoin = LineJoin.Round
                })
                {
                    // Top-Left corner bracket
                    DrawCornerBracket(g, bracketPen, s, cMargin, cMargin, 1f, 1f, cArm, cRadius);
                    // Top-Right corner bracket (target of the scissor jaws)
                    DrawCornerBracket(g, bracketPen, s, 100f - cMargin, cMargin, -1f, 1f, cArm, cRadius);
                    // Bottom-Right corner bracket
                    DrawCornerBracket(g, bracketPen, s, 100f - cMargin, 100f - cMargin, -1f, -1f, cArm, cRadius);
                }

                // 3. Open Scissors Element (oriented along -45 deg diagonal: handles at bottom-left, blades opening to top-right)
                float pivotX = 50.2f;
                float pivotY = 49.8f;
                float scaleFactor = compactTrayMode ? 1.05f : 1.0f;

                DrawScissors(g, s, pivotX, pivotY, scaleFactor, compactTrayMode);
            }
            return bmp;
        }

        private static void DrawCornerBracket(
            Graphics g, Pen pen, float s,
            float cx, float cy, float dirX, float dirY, float arm, float cornerR)
        {
            using (GraphicsPath p = new GraphicsPath())
            {
                PointF p1 = new PointF((cx + dirX * arm) * s, cy * s);
                PointF pCorner1 = new PointF((cx + dirX * cornerR) * s, cy * s);
                PointF pVert = new PointF(cx * s, cy * s);
                PointF pCorner2 = new PointF(cx * s, (cy + dirY * cornerR) * s);
                PointF p2 = new PointF(cx * s, (cy + dirY * arm) * s);

                p.AddLine(p1, pCorner1);
                p.AddBezier(pCorner1, pVert, pVert, pCorner2);
                p.AddLine(pCorner2, p2);
                g.DrawPath(pen, p);
            }
        }

        private static void DrawScissors(Graphics g, float s, float px, float py, float k, bool compactTrayMode)
        {
            // Local basis around pivot (px, py) pointing toward top-right (-45 degrees)
            const float invSqrt2 = 0.70710678f;
            float ux = invSqrt2, uy = -invSqrt2; // Forward toward top-right
            float vx = invSqrt2, vy = invSqrt2;  // Perpendicular toward bottom-right

            // Draw both symmetric halves (sign = -1: upper-left blade + lower-right ring; sign = +1: lower-right blade + upper-left ring)
            DrawScissorHalf(g, s, px, py, ux, uy, vx, vy, k, -1f, compactTrayMode);
            DrawScissorHalf(g, s, px, py, ux, uy, vx, vy, k, +1f, compactTrayMode);

            // Central mechanical pivot screw cutout (deep royal blue dot for unmistakable scissor crossing)
            float screwR = (compactTrayMode ? 3.1f : 2.7f) * k * s;
            using (SolidBrush screwBrush = new SolidBrush(Color.FromArgb(255, 0, 88, 218)))
            {
                g.FillEllipse(screwBrush, px * s - screwR, py * s - screwR, screwR * 2f, screwR * 2f);
            }
        }

        private static void DrawScissorHalf(
            Graphics g, float s,
            float px, float py, float ux, float uy, float vx, float vy,
            float k, float sign, bool compactTrayMode)
        {
            // Jaw half-opening angle: 22 degrees
            float alpha = 22.0f * (float)(Math.PI / 180.0) * sign;
            float cosA = (float)Math.Cos(alpha);
            float sinA = (float)Math.Sin(alpha);

            // Blade forward unit vector D and outward normal N (pointing away from inner cutting gap)
            float dx = cosA * ux + sinA * vx;
            float dy = cosA * uy + sinA * vy;
            float nx = sign * (-sinA * ux + cosA * vx);
            float ny = sign * (-sinA * uy + cosA * vy);

            // Tapered blade polygon/Bezier in normalized units
            float tipDist = 33.5f * k;
            float backDist = -5.5f * k;
            float bladeWidth = (compactTrayMode ? 8.6f : 7.8f) * k;

            // Cutting edge sits slightly across the centerline (-1.2) so the two blades overlap cleanly at the pivot
            float innerOffset = -1.3f * k;

            PointF innerBack = ToScreen(s, px, py, dx, dy, nx, ny, backDist, innerOffset);
            PointF tip = ToScreen(s, px, py, dx, dy, nx, ny, tipDist, innerOffset + 0.3f * k);
            PointF outerCtrl1 = ToScreen(s, px, py, dx, dy, nx, ny, tipDist * 0.72f, innerOffset + bladeWidth * 0.72f);
            PointF outerCtrl2 = ToScreen(s, px, py, dx, dy, nx, ny, tipDist * 0.25f, innerOffset + bladeWidth * 1.02f);
            PointF outerBack = ToScreen(s, px, py, dx, dy, nx, ny, backDist, innerOffset + bladeWidth * 0.78f);

            using (GraphicsPath bladePath = new GraphicsPath())
            {
                bladePath.AddLine(innerBack, tip);
                bladePath.AddBezier(tip, outerCtrl1, outerCtrl2, outerBack);
                bladePath.CloseFigure();
                using (SolidBrush whiteBrush = new SolidBrush(Color.White))
                {
                    g.FillPath(whiteBrush, bladePath);
                }
            }

            // Shank connecting pivot smoothly to the opposite-side finger ring (-sign in V)
            float ringU = -20.5f * k;
            float ringV = -sign * 13.8f * k;
            float ringCenterX = (px + ringU * ux + ringV * vx) * s;
            float ringCenterY = (py + ringU * uy + ringV * vy) * s;

            float ringOuterR = (compactTrayMode ? 11.2f : 10.6f) * k * s;
            float ringStroke = (compactTrayMode ? 5.6f : 5.0f) * k * s;
            float ringMidR = ringOuterR - ringStroke * 0.5f;

            // Shank from pivot neck to tangent side of finger ring
            PointF shankStart = new PointF(
                (px - 2.0f * k * dx) * s,
                (py - 2.0f * k * dy) * s);
            PointF shankMid = new PointF(
                (px + (-10.5f * k) * ux + (-sign * 5.8f * k) * vx) * s,
                (py + (-10.5f * k) * uy + (-sign * 5.8f * k) * vy) * s);
            PointF shankEnd = new PointF(
                (px + (-15.0f * k) * ux + (-sign * 10.5f * k) * vx) * s,
                (py + (-15.0f * k) * uy + (-sign * 10.5f * k) * vy) * s);

            using (Pen shankPen = new Pen(Color.White, (compactTrayMode ? 5.8f : 5.2f) * k * s)
            {
                StartCap = LineCap.Round,
                EndCap = LineCap.Round,
                LineJoin = LineJoin.Round
            })
            {
                g.DrawBezier(shankPen, shankStart, shankMid, shankMid, shankEnd);
            }

            // Crisp circular finger loop
            using (Pen ringPen = new Pen(Color.White, ringStroke))
            {
                g.DrawEllipse(ringPen,
                    ringCenterX - ringMidR,
                    ringCenterY - ringMidR,
                    ringMidR * 2f,
                    ringMidR * 2f);
            }
        }

        private static PointF ToScreen(
            float s, float px, float py,
            float dx, float dy, float nx, float ny,
            float along, float perp)
        {
            return new PointF(
                (px + along * dx + perp * nx) * s,
                (py + along * dy + perp * ny) * s);
        }

        private static GraphicsPath CreateRoundedRectPathF(RectangleF rect, float radius)
        {
            GraphicsPath path = new GraphicsPath();
            float d = Math.Min(radius * 2f, Math.Min(rect.Width, rect.Height));
            if (d <= 0f)
            {
                path.AddRectangle(rect);
                return path;
            }
            path.AddArc(rect.X, rect.Y, d, d, 180f, 90f);
            path.AddArc(rect.Right - d, rect.Y, d, d, 270f, 90f);
            path.AddArc(rect.Right - d, rect.Bottom - d, d, d, 0f, 90f);
            path.AddArc(rect.X, rect.Bottom - d, d, d, 90f, 90f);
            path.CloseFigure();
            return path;
        }

        /// <summary>
        /// Writes a standard multi-frame Windows .ico stream:
        /// - Sizes &lt; 256 are written as 32-bpp ARGB DIBs for 100% Win32 &amp; .NET System.Drawing.Icon compatibility.
        /// - Size &gt;= 256 is written as PNG per Windows Vista+ icon specification.
        /// </summary>
        private static void WriteIcoWithBitmaps(Stream output, Bitmap[] bitmaps, bool allowPngForLarge)
        {
            int count = bitmaps.Length;
            byte[][] payloads = new byte[count][];

            for (int i = 0; i < count; i++)
            {
                Bitmap bmp = bitmaps[i];
                if (allowPngForLarge && (bmp.Width >= 256 || bmp.Height >= 256))
                {
                    using (MemoryStream ms = new MemoryStream())
                    {
                        bmp.Save(ms, ImageFormat.Png);
                        payloads[i] = ms.ToArray();
                    }
                }
                else
                {
                    payloads[i] = Build32BppIconDib(bmp);
                }
            }

            BinaryWriter bw = new BinaryWriter(output);
            // ICONDIR header (6 bytes)
            bw.Write((ushort)0);     // idReserved
            bw.Write((ushort)1);     // idType = 1 (Icon)
            bw.Write((ushort)count); // idCount

            int dataOffset = 6 + count * 16;
            for (int i = 0; i < count; i++)
            {
                Bitmap bmp = bitmaps[i];
                byte wByte = bmp.Width >= 256 ? (byte)0 : (byte)bmp.Width;
                byte hByte = bmp.Height >= 256 ? (byte)0 : (byte)bmp.Height;

                bw.Write(wByte);                       // bWidth
                bw.Write(hByte);                       // bHeight
                bw.Write((byte)0);                     // bColorCount
                bw.Write((byte)0);                     // bReserved
                bw.Write((ushort)1);                   // wPlanes
                bw.Write((ushort)32);                  // wBitCount
                bw.Write((uint)payloads[i].Length);    // dwBytesInRes
                bw.Write((uint)dataOffset);            // dwImageOffset

                dataOffset += payloads[i].Length;
            }

            for (int i = 0; i < count; i++)
            {
                bw.Write(payloads[i]);
            }
            bw.Flush();
        }

        private static byte[] Build32BppIconDib(Bitmap bmp)
        {
            int w = bmp.Width;
            int h = bmp.Height;
            int xorRowBytes = w * 4;
            int andRowBytes = ((w + 31) / 32) * 4;
            int totalImageBytes = xorRowBytes * h + andRowBytes * h;

            using (MemoryStream ms = new MemoryStream(40 + totalImageBytes))
            {
                BinaryWriter bw = new BinaryWriter(ms);
                // BITMAPINFOHEADER (40 bytes)
                bw.Write((uint)40);              // biSize
                bw.Write((int)w);                // biWidth
                bw.Write((int)(h * 2));          // biHeight (doubled for XOR + AND masks)
                bw.Write((ushort)1);             // biPlanes
                bw.Write((ushort)32);            // biBitCount
                bw.Write((uint)0);               // biCompression = BI_RGB
                bw.Write((uint)totalImageBytes); // biSizeImage
                bw.Write((int)0);                // biXPelsPerMeter
                bw.Write((int)0);                // biYPelsPerMeter
                bw.Write((uint)0);               // biClrUsed
                bw.Write((uint)0);               // biClrImportant

                BitmapData bd = bmp.LockBits(
                    new Rectangle(0, 0, w, h),
                    ImageLockMode.ReadOnly,
                    PixelFormat.Format32bppArgb);

                try
                {
                    byte[] srcRow = new byte[xorRowBytes];
                    byte[] andMask = new byte[andRowBytes * h];

                    // Bottom-up scanlines (y = h - 1 down to 0)
                    for (int outRow = 0; outRow < h; outRow++)
                    {
                        int srcY = h - 1 - outRow;
                        IntPtr rowPtr = new IntPtr(bd.Scan0.ToInt64() + (long)srcY * bd.Stride);
                        Marshal.Copy(rowPtr, srcRow, 0, xorRowBytes);
                        bw.Write(srcRow, 0, xorRowBytes);

                        int andRowOffset = outRow * andRowBytes;
                        for (int x = 0; x < w; x++)
                        {
                            byte alpha = srcRow[x * 4 + 3];
                            if (alpha == 0)
                            {
                                andMask[andRowOffset + (x >> 3)] |= (byte)(0x80 >> (x & 7));
                            }
                        }
                    }

                    bw.Write(andMask, 0, andMask.Length);
                }
                finally
                {
                    bmp.UnlockBits(bd);
                }

                bw.Flush();
                return ms.ToArray();
            }
        }
    }
}
