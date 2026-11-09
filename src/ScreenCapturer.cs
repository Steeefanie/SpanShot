using System;
using System.Drawing;
using System.Drawing.Imaging;

namespace SpanShot
{
    public static class ScreenCapturer
    {
        /// <summary>
        /// Captures a specific physical rectangle from the virtual desktop screen.
        /// Uses GDI BitBlt directly into a 24bpp/32bpp Bitmap for low overhead (~2-5ms).
        /// </summary>
        public static Bitmap CaptureRegion(Rectangle physicalRect)
        {
            if (physicalRect.Width <= 0 || physicalRect.Height <= 0)
                throw new ArgumentException("Capture rectangle dimensions must be positive.");

            Bitmap bmp = new Bitmap(physicalRect.Width, physicalRect.Height, PixelFormat.Format32bppArgb);
            using (Graphics g = Graphics.FromImage(bmp))
            {
                IntPtr hdcDest = g.GetHdc();
                IntPtr desktopHwnd = NativeMethods.GetDesktopWindow();
                IntPtr hdcSrc = NativeMethods.GetWindowDC(desktopHwnd);
                try
                {
                    NativeMethods.BitBlt(
                        hdcDest, 0, 0, physicalRect.Width, physicalRect.Height,
                        hdcSrc, physicalRect.X, physicalRect.Y,
                        NativeMethods.SRCCOPY);
                }
                finally
                {
                    NativeMethods.ReleaseDC(desktopHwnd, hdcSrc);
                    g.ReleaseHdc(hdcDest);
                }
            }
            return bmp;
        }
    }
}
