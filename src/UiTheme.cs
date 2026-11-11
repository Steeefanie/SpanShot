using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Windows.Forms;
using Microsoft.Win32;

namespace SpanShot
{
    internal static class UiTheme
    {
        private static bool? _cachedDarkMode;
        private static bool? _forcedDarkModeOverride;

        public static bool IsDarkMode
        {
            get
            {
                if (_forcedDarkModeOverride.HasValue)
                {
                    return _forcedDarkModeOverride.Value;
                }
                if (!_cachedDarkMode.HasValue)
                {
                    _cachedDarkMode = ReadSystemDarkMode();
                }
                return _cachedDarkMode.Value;
            }
        }

        public static bool RefreshSystemTheme()
        {
            bool prev = IsDarkMode;
            _cachedDarkMode = ReadSystemDarkMode();
            return _cachedDarkMode.Value != prev;
        }

        internal static void SetThemeOverrideForTest(bool? forceDark)
        {
            _forcedDarkModeOverride = forceDark;
        }

        private static bool ReadSystemDarkMode()
        {
            try
            {
                using (RegistryKey key = Registry.CurrentUser.OpenSubKey(
                    @"Software\Microsoft\Windows\CurrentVersion\Themes\Personalize", false))
                {
                    if (key != null)
                    {
                        object val = key.GetValue("AppsUseLightTheme");
                        if (val != null)
                        {
                            return Convert.ToInt32(val) == 0;
                        }
                    }
                }
            }
            catch { }
            return false;
        }

        // Accent Colors
        public static readonly Color WeChatGreen = Color.FromArgb(0, 122, 255);    // Primary Blue #007AFF
        public static readonly Color AccentBlue = Color.FromArgb(0, 122, 255);     // #007AFF
        public static readonly Color AccentTeal = Color.FromArgb(10, 132, 255);    // #0A84FF
        public static readonly Color AccentGreen = Color.FromArgb(0, 122, 255);    // #007AFF
        public static readonly Color AccentOrange = Color.FromArgb(255, 159, 10);  // #FF9F0A
        public static readonly Color AccentRed = Color.FromArgb(255, 69, 58);      // #FF453A
        public static readonly Color AccentPurple = Color.FromArgb(94, 92, 230);   // #5E5CE6

        public static Color LinkBlue
        {
            get { return IsDarkMode ? Color.FromArgb(56, 152, 255) : Color.FromArgb(0, 112, 240); }
        }

        // Dynamic Light/Dark Surfaces modeled after steeefanie.top tokens.css:
        // Light: --page #fafafa, --surface #ffffff, --surface-soft #f3f3f3, --surface-raised #ececec, --text #222222, --muted #888888, --border #d9d9d9
        // Dark:  --page #111111, --surface #1d1d1d, --surface-soft #1a1a1a, --surface-raised #262626, --text #eeeeee, --muted #888888, --border #333333
        public static Color BgDark
        {
            get { return IsDarkMode ? Color.FromArgb(17, 17, 17) : Color.FromArgb(250, 250, 250); }
        }

        public static Color ToolbarBg
        {
            get { return IsDarkMode ? Color.FromArgb(29, 29, 29) : Color.FromArgb(255, 255, 255); }
        }

        public static Color ToolbarHover
        {
            get { return IsDarkMode ? Color.FromArgb(38, 38, 38) : Color.FromArgb(236, 236, 236); }
        }

        public static Color ToolbarBorder
        {
            get { return IsDarkMode ? Color.FromArgb(51, 51, 51) : Color.FromArgb(217, 217, 217); }
        }

        public static Color DividerColor
        {
            get { return IsDarkMode ? Color.FromArgb(51, 51, 51) : Color.FromArgb(217, 217, 217); }
        }

        public static Color BgCard
        {
            get { return IsDarkMode ? Color.FromArgb(29, 29, 29) : Color.FromArgb(243, 243, 243); }
        }

        public static Color BgCardHover
        {
            get { return IsDarkMode ? Color.FromArgb(38, 38, 38) : Color.FromArgb(236, 236, 236); }
        }

        public static Color BgPill
        {
            get { return IsDarkMode ? Color.FromArgb(29, 29, 29) : Color.FromArgb(243, 243, 243); }
        }

        public static Color CanvasBg
        {
            get { return IsDarkMode ? Color.FromArgb(26, 26, 26) : Color.FromArgb(243, 243, 243); }
        }

        public static Color BorderSubtle
        {
            get { return IsDarkMode ? Color.FromArgb(51, 51, 51) : Color.FromArgb(217, 217, 217); }
        }

        public static Color TextPrimary
        {
            get { return IsDarkMode ? Color.FromArgb(238, 238, 238) : Color.FromArgb(34, 34, 34); }
        }

        public static Color TextSecondary
        {
            get { return Color.FromArgb(136, 136, 136); }
        }

        // Annotation color swatches (Apple System Colors)
        public static readonly Color[] AnnotColors = new Color[]
        {
            Color.FromArgb(255, 59, 48),   // Apple Red #FF3B30
            Color.FromArgb(255, 204, 0),   // Apple Yellow #FFCC00
            Color.FromArgb(52, 199, 89),   // Apple Green #34C759
            Color.FromArgb(0, 122, 255),   // Apple Blue #007AFF
            Color.FromArgb(255, 255, 255)  // White #FFFFFF
        };

        private static float _dpiScale = 0f;

        public static float DpiScale
        {
            get
            {
                if (_dpiScale <= 0f)
                {
                    try
                    {
                        using (Graphics g = Graphics.FromHwnd(IntPtr.Zero))
                        {
                            _dpiScale = Math.Max(1.0f, g.DpiX / 96.0f);
                        }
                    }
                    catch
                    {
                        _dpiScale = 1.0f;
                    }
                }
                return _dpiScale;
            }
        }

        public static int S(int px)
        {
            return (int)Math.Round(px * DpiScale);
        }

        public static Font FontPx(int designPx, bool bold = false)
        {
            float scaledPx = Math.Max(10f, designPx * DpiScale);
            return new Font("Microsoft YaHei", scaledPx, bold ? FontStyle.Bold : FontStyle.Regular, GraphicsUnit.Pixel);
        }

        public static GraphicsPath CreateRoundedRectPath(Rectangle rect, int radius)
        {
            GraphicsPath path = new GraphicsPath();
            if (rect.Width <= 0 || rect.Height <= 0) return path;
            if (radius <= 0)
            {
                path.AddRectangle(rect);
                return path;
            }
            int d = Math.Min(radius * 2, Math.Min(rect.Width, rect.Height));
            if (d <= 0)
            {
                path.AddRectangle(rect);
                return path;
            }
            path.AddArc(rect.X, rect.Y, d, d, 180, 90);
            path.AddArc(rect.Right - d, rect.Y, d, d, 270, 90);
            path.AddArc(rect.Right - d, rect.Bottom - d, d, d, 0, 90);
            path.AddArc(rect.X, rect.Bottom - d, d, d, 90, 90);
            path.CloseFigure();
            return path;
        }

        public static void FillRoundedRect(Graphics g, Brush brush, Rectangle rect, int radius)
        {
            if (rect.Width <= 0 || rect.Height <= 0) return;
            using (GraphicsPath path = CreateRoundedRectPath(rect, radius))
            {
                g.FillPath(brush, path);
            }
        }

        public static void DrawRoundedRect(Graphics g, Pen pen, Rectangle rect, int radius)
        {
            if (rect.Width <= 0 || rect.Height <= 0) return;
            using (GraphicsPath path = CreateRoundedRectPath(rect, radius))
            {
                g.DrawPath(pen, path);
            }
        }

        public static Color Lighten(Color c, int delta)
        {
            return Color.FromArgb(c.A,
                Math.Max(0, Math.Min(255, c.R + delta)),
                Math.Max(0, Math.Min(255, c.G + delta)),
                Math.Max(0, Math.Min(255, c.B + delta)));
        }

        public static Color AdjustHoverFill(Color baseColor)
        {
            if (baseColor.A == 0) return baseColor;
            int lum = baseColor.R + baseColor.G + baseColor.B;
            if (lum > 600)
            {
                return Lighten(baseColor, -12);
            }
            return Lighten(baseColor, 16);
        }

        public static void DrawPillButton(
            Graphics g, Rectangle rect, string text, Color baseColor,
            bool hovered, bool activeBorder = false, int radius = 4, Font customFont = null, Color? textColor = null)
        {
            if (rect.Width <= 0 || rect.Height <= 0) return;
            Color fill = hovered ? AdjustHoverFill(baseColor) : baseColor;
            int r = S(radius);
            if (fill.A > 0)
            {
                using (SolidBrush b = new SolidBrush(fill))
                {
                    FillRoundedRect(g, b, rect, r);
                }
            }
            if (activeBorder)
            {
                using (Pen p = new Pen(WeChatGreen, Math.Max(1.5f, 1.5f * DpiScale)))
                {
                    DrawRoundedRect(g, p, new Rectangle(rect.X + 1, rect.Y + 1, rect.Width - 2, rect.Height - 2), r);
                }
            }

            Font f = customFont ?? FontPx(13, false);
            Color fg = textColor ?? TextPrimary;
            try
            {
                using (SolidBrush tb = new SolidBrush(fg))
                using (StringFormat sf = new StringFormat
                {
                    Alignment = StringAlignment.Center,
                    LineAlignment = StringAlignment.Center,
                    FormatFlags = StringFormatFlags.NoWrap
                })
                {
                    g.DrawString(text, f, tb, rect, sf);
                }
            }
            finally
            {
                if (customFont == null) f.Dispose();
            }
        }

        // WeChat Toolbar Vector Icons
        public static void DrawIconRect(Graphics g, Rectangle btnRect, Color color)
        {
            int w = S(16);
            int h = S(13);
            int x = btnRect.X + (btnRect.Width - w) / 2;
            int y = btnRect.Y + (btnRect.Height - h) / 2;
            using (Pen p = new Pen(color, Math.Max(1.6f, 1.6f * DpiScale)))
            {
                g.DrawRectangle(p, x, y, w, h);
            }
        }

        public static void DrawIconArrow(Graphics g, Rectangle btnRect, Color color)
        {
            int s = S(14);
            int x0 = btnRect.X + (btnRect.Width - s) / 2;
            int y0 = btnRect.Y + (btnRect.Height + s) / 2;
            int x1 = x0 + s;
            int y1 = y0 - s;
            using (Pen p = new Pen(color, Math.Max(1.8f, 1.8f * DpiScale)) { StartCap = LineCap.Round, EndCap = LineCap.Round })
            {
                g.DrawLine(p, x0, y0, x1, y1);
                g.DrawLine(p, x1 - S(6), y1, x1, y1);
                g.DrawLine(p, x1, y1 + S(6), x1, y1);
            }
        }

        public static void DrawIconPen(Graphics g, Rectangle btnRect, Color color)
        {
            float cx = btnRect.X + btnRect.Width / 2f;
            float cy = btnRect.Y + btnRect.Height / 2f;
            float u = DpiScale;

            PointF tip = new PointF(cx - 6.5f * u, cy + 6.5f * u);
            PointF c1 = new PointF(cx - 5.0f * u, cy + 1.5f * u);
            PointF t1 = new PointF(cx + 3.0f * u, cy - 6.5f * u);
            PointF t2 = new PointF(cx + 6.5f * u, cy - 3.0f * u);
            PointF c2 = new PointF(cx - 1.5f * u, cy + 5.0f * u);

            using (Pen p = new Pen(color, Math.Max(1.6f, 1.6f * u)) { StartCap = LineCap.Round, EndCap = LineCap.Round, LineJoin = LineJoin.Round })
            {
                g.DrawPolygon(p, new PointF[] { tip, c1, t1, t2, c2 });
                g.DrawLine(p, c1, c2);
            }
        }

        public static void DrawIconUndo(Graphics g, Rectangle btnRect, Color color)
        {
            float cx = btnRect.X + btnRect.Width / 2f;
            float cy = btnRect.Y + btnRect.Height / 2f;
            float u = DpiScale;

            float topY = cy - 2.5f * u;
            float botY = cy + 5.5f * u;
            float arcR = (botY - topY) / 2f;
            float leftX = cx - 5.5f * u;
            float rightLineEnd = cx + 1.5f * u;

            using (Pen p = new Pen(color, Math.Max(1.7f, 1.7f * u)) { StartCap = LineCap.Round, EndCap = LineCap.Round, LineJoin = LineJoin.Round })
            {
                g.DrawLine(p, leftX, topY, rightLineEnd, topY);
                g.DrawArc(p, rightLineEnd - arcR, topY, arcR * 2f, arcR * 2f, -90f, 180f);
                g.DrawLine(p, cx - 2.5f * u, botY, rightLineEnd, botY);

                g.DrawLine(p, leftX + 3.5f * u, topY - 3.5f * u, leftX, topY);
                g.DrawLine(p, leftX + 3.5f * u, topY + 3.5f * u, leftX, topY);
            }
        }

        public static void DrawIconPin(Graphics g, Rectangle btnRect, Color color)
        {
            int cx = btnRect.X + btnRect.Width / 2;
            int cy = btnRect.Y + btnRect.Height / 2;
            using (Pen p = new Pen(color, Math.Max(1.7f, 1.7f * DpiScale)) { StartCap = LineCap.Round, EndCap = LineCap.Round })
            {
                g.DrawRectangle(p, cx - S(4), cy - S(6), S(8), S(6));
                g.DrawLine(p, cx - S(6), cy, cx + S(6), cy);
                g.DrawLine(p, cx, cy, cx, cy + S(6));
            }
        }

        public static void DrawIconSave(Graphics g, Rectangle btnRect, Color color)
        {
            int cx = btnRect.X + btnRect.Width / 2;
            int cy = btnRect.Y + btnRect.Height / 2;
            using (Pen p = new Pen(color, Math.Max(1.8f, 1.8f * DpiScale)) { StartCap = LineCap.Round, EndCap = LineCap.Round })
            {
                g.DrawLine(p, cx, cy - S(6), cx, cy + S(3));
                g.DrawLine(p, cx - S(4), cy - S(1), cx, cy + S(3));
                g.DrawLine(p, cx + S(4), cy - S(1), cx, cy + S(3));
                g.DrawLine(p, cx - S(6), cy + S(6), cx + S(6), cy + S(6));
            }
        }

        public static void DrawIconClose(Graphics g, Rectangle btnRect, Color color)
        {
            int r = S(5);
            int cx = btnRect.X + btnRect.Width / 2;
            int cy = btnRect.Y + btnRect.Height / 2;
            using (Pen p = new Pen(color, Math.Max(1.8f, 1.8f * DpiScale)) { StartCap = LineCap.Round, EndCap = LineCap.Round })
            {
                g.DrawLine(p, cx - r, cy - r, cx + r, cy + r);
                g.DrawLine(p, cx + r, cy - r, cx - r, cy + r);
            }
        }

        public static void DrawIconCheck(Graphics g, Rectangle btnRect, Color color)
        {
            int cx = btnRect.X + btnRect.Width / 2;
            int cy = btnRect.Y + btnRect.Height / 2;
            using (Pen p = new Pen(color, Math.Max(2.0f, 2.0f * DpiScale)) { StartCap = LineCap.Round, EndCap = LineCap.Round })
            {
                g.DrawLine(p, cx - S(6), cy, cx - S(2), cy + S(5));
                g.DrawLine(p, cx - S(2), cy + S(5), cx + S(7), cy - S(5));
            }
        }
    }

    internal sealed class ToastForm : Form
    {
        private readonly string _message;
        private readonly Color _accent;
        private readonly Timer _timer;
        private readonly Font _font;
        private int _ticks;

        private ToastForm(string message, Color accent)
        {
            UiTheme.RefreshSystemTheme();
            _message = message;
            _accent = accent;
            _font = UiTheme.FontPx(12, false);

            FormBorderStyle = FormBorderStyle.None;
            StartPosition = FormStartPosition.Manual;
            TopMost = true;
            ShowInTaskbar = false;
            DoubleBuffered = true;
            BackColor = UiTheme.ToolbarBg;

            using (Graphics g = CreateGraphics())
            {
                SizeF sz = g.MeasureString(message, _font);
                int w = Math.Min(UiTheme.S(260), Math.Max(UiTheme.S(140), (int)sz.Width + UiTheme.S(28)));
                int h = UiTheme.S(34);
                Rectangle screen = Screen.PrimaryScreen.WorkingArea;
                Bounds = new Rectangle(screen.Left + (screen.Width - w) / 2, screen.Top + UiTheme.S(32), w, h);
            }

            Region = new Region(UiTheme.CreateRoundedRectPath(new Rectangle(0, 0, Width, Height), UiTheme.S(6)));

            _timer = new Timer { Interval = 40 };
            _timer.Tick += (s, e) =>
            {
                _ticks++;
                if (_ticks > 28)
                {
                    Opacity -= 0.09;
                    if (Opacity <= 0.05)
                    {
                        _timer.Stop();
                        Close();
                    }
                }
            };
        }

        protected override CreateParams CreateParams
        {
            get
            {
                CreateParams cp = base.CreateParams;
                cp.ExStyle |= NativeMethods.WS_EX_TOPMOST | NativeMethods.WS_EX_TOOLWINDOW | NativeMethods.WS_EX_NOACTIVATE;
                return cp;
            }
        }

        protected override bool ShowWithoutActivation { get { return true; } }

        protected override void OnShown(EventArgs e)
        {
            base.OnShown(e);
            _timer.Start();
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            Graphics g = e.Graphics;
            g.SmoothingMode = SmoothingMode.AntiAlias;

            Rectangle rect = new Rectangle(0, 0, Width - 1, Height - 1);
            Rectangle textRect = new Rectangle(UiTheme.S(10), 0, Width - UiTheme.S(20), Height);
            using (SolidBrush bg = new SolidBrush(UiTheme.ToolbarBg))
            using (Pen border = new Pen(_accent, 1f))
            using (SolidBrush fg = new SolidBrush(UiTheme.TextPrimary))
            using (StringFormat sf = new StringFormat
            {
                Alignment = StringAlignment.Center,
                LineAlignment = StringAlignment.Center,
                FormatFlags = StringFormatFlags.NoWrap,
                Trimming = StringTrimming.EllipsisCharacter
            })
            {
                UiTheme.FillRoundedRect(g, bg, rect, UiTheme.S(6));
                UiTheme.DrawRoundedRect(g, border, rect, UiTheme.S(6));
                g.DrawString(_message, _font, fg, textRect, sf);
            }
        }

        protected override void Dispose(bool disposing)
        {
            if (disposing)
            {
                if (_timer != null) _timer.Dispose();
                if (_font != null) _font.Dispose();
            }
            base.Dispose(disposing);
        }

        public static void ShowToast(string message, Color accent)
        {
            try
            {
                for (int i = Application.OpenForms.Count - 1; i >= 0; i--)
                {
                    Form openForm = Application.OpenForms[i];
                    if (openForm == null || openForm.IsDisposed || !openForm.Visible) continue;
                    ResultPreviewForm preview = openForm as ResultPreviewForm;
                    if (preview != null)
                    {
                        preview.ShowInlineNotice(message, accent);
                        return;
                    }
                    MainForm main = openForm as MainForm;
                    if (main != null)
                    {
                        main.ShowInlineNotice(message, accent);
                        return;
                    }
                }

                ToastForm toast = new ToastForm(message, accent);
                toast.Show();
            }
            catch { }
        }
    }
}
