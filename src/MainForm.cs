using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.Threading;
using System.Windows.Forms;

namespace SpanShot
{
    public sealed class MainForm : Form
    {
        private const int HOTKEY_ID_GENERAL = 9001;

        private NotifyIcon _trayIcon;
        private bool _isCapturing;
        private bool _keepInBackground = true;
        private bool _quickCopyOnly = false;
        private bool _forceExit;

        private bool _draggingWindow;
        private Point _dragStartPt;
        private Point _mousePos;

        private Rectangle _headerRect;
        private Rectangle _btnCloseRect;
        private Rectangle _btnCaptureRect;
        private Rectangle _chkKeepAliveRect;
        private Rectangle _chkQuickCopyRect;

        private Font _brandFont;
        private Font _actionFont;
        private Font _hotkeyFont;
        private Font _optionFont;
        private Font _subNoteFont;

        public MainForm()
        {
            _brandFont = UiTheme.FontPx(15, true);
            _actionFont = UiTheme.FontPx(15, true);
            _hotkeyFont = UiTheme.FontPx(12, false);
            _optionFont = UiTheme.FontPx(13, false);
            _subNoteFont = UiTheme.FontPx(11, false);

            Text = "SpanShot";
            FormBorderStyle = FormBorderStyle.None;
            Size = new Size(UiTheme.S(296), UiTheme.S(198));
            StartPosition = FormStartPosition.CenterScreen;
            BackColor = UiTheme.BgDark;
            ForeColor = Color.White;
            ShowInTaskbar = true;
            DoubleBuffered = true;

            SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.UserPaint | ControlStyles.OptimizedDoubleBuffer, true);
            Region = new Region(UiTheme.CreateRoundedRectPath(new Rectangle(0, 0, Width, Height), UiTheme.S(10)));

            ComputeLayout();
            InitializeTrayIcon();
        }

        private void ComputeLayout()
        {
            int pad = UiTheme.S(16);
            int btnW = Width - pad * 2;
            int btnH = UiTheme.S(46);

            _headerRect = new Rectangle(0, 0, Width - UiTheme.S(46), UiTheme.S(44));
            _btnCloseRect = new Rectangle(Width - UiTheme.S(36), UiTheme.S(10), UiTheme.S(26), UiTheme.S(24));

            _btnCaptureRect = new Rectangle(pad, UiTheme.S(48), btnW, btnH);
            _chkKeepAliveRect = new Rectangle(pad, UiTheme.S(106), btnW, UiTheme.S(26));
            _chkQuickCopyRect = new Rectangle(pad, UiTheme.S(138), btnW, UiTheme.S(44));
        }

        private void InitializeTrayIcon()
        {
            ContextMenu trayMenu = new ContextMenu();
            trayMenu.MenuItems.Add("截图 (Alt+A)", (s, e) => StartCaptureFlow());
            trayMenu.MenuItems.Add("-");
            trayMenu.MenuItems.Add("显示主窗口", (s, e) =>
            {
                Show();
                WindowState = FormWindowState.Normal;
                Activate();
            });
            trayMenu.MenuItems.Add("彻底退出", (s, e) =>
            {
                _forceExit = true;
                Application.Exit();
            });

            _trayIcon = new NotifyIcon
            {
                Text = "SpanShot",
                Icon = SystemIcons.Application,
                ContextMenu = trayMenu,
                Visible = true
            };
            _trayIcon.DoubleClick += (s, e) =>
            {
                Show();
                WindowState = FormWindowState.Normal;
                Activate();
            };
        }

        protected override void OnHandleCreated(EventArgs e)
        {
            base.OnHandleCreated(e);
            NativeMethods.RegisterHotKey(Handle, HOTKEY_ID_GENERAL, NativeMethods.MOD_ALT, (uint)Keys.A);
        }

        protected override void OnHandleDestroyed(EventArgs e)
        {
            NativeMethods.UnregisterHotKey(Handle, HOTKEY_ID_GENERAL);
            base.OnHandleDestroyed(e);
        }

        protected override void OnFormClosing(FormClosingEventArgs e)
        {
            if (!_forceExit && e.CloseReason == CloseReason.UserClosing && _keepInBackground)
            {
                e.Cancel = true;
                WindowState = FormWindowState.Minimized;
                return;
            }
            base.OnFormClosing(e);
        }

        protected override void WndProc(ref Message m)
        {
            if (m.Msg == NativeMethods.WM_HOTKEY && !_isCapturing)
            {
                int id = m.WParam.ToInt32();
                if (id == HOTKEY_ID_GENERAL) StartCaptureFlow();
            }
            base.WndProc(ref m);
        }

        protected override void OnMouseDown(MouseEventArgs e)
        {
            base.OnMouseDown(e);
            if (e.Button != MouseButtons.Left) return;

            Point pt = e.Location;
            if (_btnCloseRect.Contains(pt))
            {
                if (_keepInBackground)
                {
                    WindowState = FormWindowState.Minimized;
                }
                else
                {
                    _forceExit = true;
                    Application.Exit();
                }
                return;
            }
            if (_headerRect.Contains(pt))
            {
                _draggingWindow = true;
                _dragStartPt = pt;
                return;
            }
            if (_btnCaptureRect.Contains(pt))
            {
                StartCaptureFlow();
                return;
            }
            if (_chkKeepAliveRect.Contains(pt))
            {
                _keepInBackground = !_keepInBackground;
                Invalidate();
                return;
            }
            if (_chkQuickCopyRect.Contains(pt))
            {
                _quickCopyOnly = !_quickCopyOnly;
                Invalidate();
                return;
            }
        }

        protected override void OnMouseMove(MouseEventArgs e)
        {
            base.OnMouseMove(e);
            _mousePos = e.Location;

            if (_draggingWindow)
            {
                Location = new Point(Left + e.X - _dragStartPt.X, Top + e.Y - _dragStartPt.Y);
                return;
            }

            bool clickable = _btnCloseRect.Contains(e.Location) ||
                             _btnCaptureRect.Contains(e.Location) ||
                             _chkKeepAliveRect.Contains(e.Location) ||
                             _chkQuickCopyRect.Contains(e.Location);

            Cursor = clickable ? Cursors.Hand : Cursors.Default;
            Invalidate();
        }

        protected override void OnMouseUp(MouseEventArgs e)
        {
            base.OnMouseUp(e);
            _draggingWindow = false;
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            Graphics g = e.Graphics;
            g.SmoothingMode = SmoothingMode.AntiAlias;

            Rectangle outer = new Rectangle(0, 0, Width - 1, Height - 1);
            using (SolidBrush bg = new SolidBrush(UiTheme.BgDark))
            using (Pen border = new Pen(UiTheme.BorderSubtle, 1f))
            {
                UiTheme.FillRoundedRect(g, bg, outer, UiTheme.S(10));
                UiTheme.DrawRoundedRect(g, border, outer, UiTheme.S(10));
            }

            using (StringFormat sfLeft = new StringFormat { Alignment = StringAlignment.Near, LineAlignment = StringAlignment.Center })
            {
                g.DrawString("SpanShot", _brandFont, Brushes.White,
                    new Rectangle(UiTheme.S(16), UiTheme.S(6), UiTheme.S(160), UiTheme.S(32)), sfLeft);
            }

            UiTheme.DrawPillButton(g, _btnCloseRect, "✕",
                _btnCloseRect.Contains(_mousePos) ? UiTheme.AccentRed : Color.Transparent,
                false, false, 4, _hotkeyFont, _btnCloseRect.Contains(_mousePos) ? Color.White : UiTheme.TextSecondary);

            DrawCaptureButton(g, _btnCaptureRect, "截图", "Alt + A", _btnCaptureRect.Contains(_mousePos));
            DrawCheckboxOption(g, _chkKeepAliveRect, "常驻后台", null, _keepInBackground, _chkKeepAliveRect.Contains(_mousePos));
            DrawCheckboxOption(g, _chkQuickCopyRect, "快捷截图", "截图完默认只复制到剪贴板，不弹窗", _quickCopyOnly, _chkQuickCopyRect.Contains(_mousePos));
        }

        private void DrawCaptureButton(Graphics g, Rectangle rect, string label, string hotkey, bool hovered)
        {
            Color bg = hovered ? UiTheme.Lighten(UiTheme.WeChatGreen, 14) : UiTheme.WeChatGreen;
            using (SolidBrush b = new SolidBrush(bg))
            {
                UiTheme.FillRoundedRect(g, b, rect, UiTheme.S(8));
            }

            Rectangle textRect = new Rectangle(rect.X + UiTheme.S(18), rect.Y, rect.Width - UiTheme.S(100), rect.Height);
            using (StringFormat sf = new StringFormat { Alignment = StringAlignment.Near, LineAlignment = StringAlignment.Center })
            {
                g.DrawString(label, _actionFont, Brushes.White, textRect, sf);
            }

            Rectangle hkRect = new Rectangle(rect.Right - UiTheme.S(76), rect.Y + (rect.Height - UiTheme.S(24)) / 2, UiTheme.S(60), UiTheme.S(24));
            using (SolidBrush hkb = new SolidBrush(Color.FromArgb(45, 0, 0, 0)))
            using (StringFormat sfCenter = new StringFormat { Alignment = StringAlignment.Center, LineAlignment = StringAlignment.Center })
            {
                UiTheme.FillRoundedRect(g, hkb, hkRect, UiTheme.S(5));
                g.DrawString(hotkey, _hotkeyFont, Brushes.White, hkRect, sfCenter);
            }
        }

        private void DrawCheckboxOption(Graphics g, Rectangle rect, string label, string subNote, bool isChecked, bool hovered)
        {
            int boxSz = UiTheme.S(16);
            int boxY = rect.Y + UiTheme.S(4);
            Rectangle boxRect = new Rectangle(rect.X, boxY, boxSz, boxSz);

            if (isChecked)
            {
                using (SolidBrush b = new SolidBrush(UiTheme.WeChatGreen))
                {
                    UiTheme.FillRoundedRect(g, b, boxRect, UiTheme.S(4));
                }
                using (Pen checkPen = new Pen(Color.White, Math.Max(1.6f, 1.6f * UiTheme.DpiScale)) { StartCap = LineCap.Round, EndCap = LineCap.Round })
                {
                    int cx = boxRect.X + boxSz / 2;
                    int cy = boxRect.Y + boxSz / 2;
                    g.DrawLine(checkPen, cx - UiTheme.S(4), cy, cx - UiTheme.S(1), cy + UiTheme.S(3));
                    g.DrawLine(checkPen, cx - UiTheme.S(1), cy + UiTheme.S(3), cx + UiTheme.S(4), cy - UiTheme.S(3));
                }
            }
            else
            {
                using (SolidBrush b = new SolidBrush(UiTheme.BgCard))
                using (Pen p = new Pen(hovered ? UiTheme.WeChatGreen : UiTheme.BorderSubtle, 1f))
                {
                    UiTheme.FillRoundedRect(g, b, boxRect, UiTheme.S(4));
                    UiTheme.DrawRoundedRect(g, p, boxRect, UiTheme.S(4));
                }
            }

            int textX = boxRect.Right + UiTheme.S(8);
            int textW = rect.Width - boxSz - UiTheme.S(8);
            Rectangle lblRect = new Rectangle(textX, rect.Y, textW, UiTheme.S(24));
            using (SolidBrush tb = new SolidBrush(hovered || isChecked ? UiTheme.TextPrimary : UiTheme.TextSecondary))
            using (StringFormat sf = new StringFormat { Alignment = StringAlignment.Near, LineAlignment = StringAlignment.Center })
            {
                g.DrawString(label, _optionFont, tb, lblRect, sf);
            }

            if (!string.IsNullOrEmpty(subNote))
            {
                Rectangle noteRect = new Rectangle(textX, rect.Y + UiTheme.S(22), textW, UiTheme.S(20));
                using (SolidBrush nb = new SolidBrush(UiTheme.TextSecondary))
                using (StringFormat sf = new StringFormat { Alignment = StringAlignment.Near, LineAlignment = StringAlignment.Center })
                {
                    g.DrawString(subNote, _subNoteFont, nb, noteRect, sf);
                }
            }
        }

        private void CopyBitmapWithToast(Bitmap bmp)
        {
            if (bmp == null) return;
            try
            {
                Clipboard.SetImage(bmp);
                ToastForm.ShowToast(string.Format("已复制到剪贴板 ({0} × {1})", bmp.Width, bmp.Height), UiTheme.WeChatGreen);
            }
            catch { }
        }

        private void SaveBitmapDialog(Bitmap bmp, string tag)
        {
            if (bmp == null) return;
            try { Clipboard.SetImage(bmp); } catch { }

            using (SaveFileDialog sfd = new SaveFileDialog())
            {
                sfd.Filter = "PNG 图像 (*.png)|*.png|JPEG 图像 (*.jpg)|*.jpg";
                sfd.DefaultExt = "png";
                sfd.FileName = string.Format("SpanShot_{0}_{1:yyyyMMdd_HHmmss}.png", tag, DateTime.Now);
                if (sfd.ShowDialog() == DialogResult.OK)
                {
                    ImageFormat fmt = sfd.FileName.EndsWith(".jpg", StringComparison.OrdinalIgnoreCase)
                        ? ImageFormat.Jpeg : ImageFormat.Png;
                    bmp.Save(sfd.FileName, fmt);
                    ToastForm.ShowToast("已保存", UiTheme.WeChatGreen);
                }
            }
        }

        private void StartCaptureFlow()
        {
            if (_isCapturing) return;
            _isCapturing = true;

            bool wasNormalVisible = Visible && WindowState != FormWindowState.Minimized;
            if (wasNormalVisible)
            {
                Hide();
                Application.DoEvents();
                Thread.Sleep(80);
            }

            try
            {
                Rectangle selectedRect;
                CaptureActionMode chosenAction;
                Bitmap inlineAnnotatedBmp = null;

                using (RegionSelectorForm selector = new RegionSelectorForm(CaptureActionMode.None, Handle))
                {
                    if (selector.ShowDialog() != DialogResult.OK || selector.ChosenAction == CaptureActionMode.None)
                    {
                        return;
                    }
                    selectedRect = selector.SelectedPhysicalRect;
                    chosenAction = selector.ChosenAction;
                    inlineAnnotatedBmp = selector.AnnotatedRegionBitmap;
                }

                if (chosenAction == CaptureActionMode.NormalCopyCompleted)
                {
                    using (inlineAnnotatedBmp)
                    {
                        if (_quickCopyOnly)
                        {
                            CopyBitmapWithToast(inlineAnnotatedBmp);
                        }
                        else
                        {
                            using (ResultPreviewForm editor = new ResultPreviewForm(inlineAnnotatedBmp, "截图"))
                            {
                                editor.ShowDialog();
                            }
                        }
                    }
                    return;
                }
                if (chosenAction == CaptureActionMode.NormalPinCompleted)
                {
                    using (inlineAnnotatedBmp)
                    {
                        CopyBitmapWithToast(inlineAnnotatedBmp);
                        PinWindowForm pin = new PinWindowForm(inlineAnnotatedBmp, selectedRect.Location);
                        pin.Show();
                    }
                    return;
                }
                if (chosenAction == CaptureActionMode.NormalSaveCompleted)
                {
                    using (inlineAnnotatedBmp)
                    {
                        SaveBitmapDialog(inlineAnnotatedBmp, "Shot");
                    }
                    return;
                }

                Application.DoEvents();
                Thread.Sleep(45);

                ScrollDirection dir = chosenAction == CaptureActionMode.VerticalScroll
                    ? ScrollDirection.Vertical
                    : ScrollDirection.Horizontal;

                Bitmap stitchedResult = null;
                ScrollSessionExitAction exitAction = ScrollSessionExitAction.Cancelled;

                using (ScrollCaptureSessionForm session = new ScrollCaptureSessionForm(selectedRect, dir))
                {
                    if (session.ShowDialog() == DialogResult.OK)
                    {
                        stitchedResult = session.FinalStitchedBitmap;
                        exitAction = session.ExitAction;
                    }
                }

                if (stitchedResult != null)
                {
                    using (stitchedResult)
                    {
                        if (_quickCopyOnly || exitAction == ScrollSessionExitAction.CopyDirectly)
                        {
                            CopyBitmapWithToast(stitchedResult);
                        }
                        else if (exitAction == ScrollSessionExitAction.PinDirectly)
                        {
                            CopyBitmapWithToast(stitchedResult);
                            PinWindowForm pin = new PinWindowForm(stitchedResult);
                            pin.Show();
                        }
                        else if (exitAction == ScrollSessionExitAction.SaveDirectly)
                        {
                            SaveBitmapDialog(stitchedResult, dir == ScrollDirection.Vertical ? "Vertical" : "Horizontal");
                        }
                        else if (exitAction == ScrollSessionExitAction.OpenEditor)
                        {
                            using (ResultPreviewForm editor = new ResultPreviewForm(stitchedResult, dir == ScrollDirection.Vertical ? "纵向长截图" : "横向长截图"))
                            {
                                editor.ShowDialog();
                            }
                        }
                    }
                }
            }
            finally
            {
                if (wasNormalVisible)
                {
                    Opacity = 1.0;
                    Show();
                    WindowState = FormWindowState.Normal;
                    Activate();
                }
                _isCapturing = false;
            }
        }

        protected override void Dispose(bool disposing)
        {
            if (disposing)
            {
                if (_trayIcon != null)
                {
                    _trayIcon.Visible = false;
                    _trayIcon.Dispose();
                }
                if (_brandFont != null) _brandFont.Dispose();
                if (_actionFont != null) _actionFont.Dispose();
                if (_hotkeyFont != null) _hotkeyFont.Dispose();
                if (_optionFont != null) _optionFont.Dispose();
                if (_subNoteFont != null) _subNoteFont.Dispose();
            }
            base.Dispose(disposing);
        }
    }
}
