using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.IO;
using System.Threading;
using System.Windows.Forms;

namespace SpanShot
{
    public sealed class MainForm : Form
    {
        private const int HOTKEY_ID_GENERAL = 9001;

        private NotifyIcon _trayIcon;
        private MenuItem _menuKeepAlive;
        private MenuItem _menuQuickCopy;
        private MenuItem _menuAutoSave;
        private MenuItem _menuAutoStart;

        private bool _startHidden;
        private bool _shownTrayHintOnce;
        private bool _isCapturing;
        private bool _keepInBackground = true;
        private bool _quickCopyOnly = false;
        private bool _autoSave = false;
        private string _autoSaveDir = string.Empty;
        private bool _autoStart = false;
        private bool _forceExit;

        private bool _draggingWindow;
        private Point _dragStartPt;
        private Point _mousePos = new Point(-1, -1);

        private Rectangle _headerRect;
        private Rectangle _btnMinRect;
        private Rectangle _btnCloseRect;
        private Rectangle _btnCaptureRect;
        private Rectangle _chkKeepAliveRect;
        private Rectangle _chkAutoStartRect;
        private Rectangle _chkQuickCopyRect;
        private Rectangle _chkAutoSaveRect;
        private Rectangle _btnChooseDirRect;

        private Font _brandFont;
        private Font _actionFont;
        private Font _hotkeyFont;
        private Font _optionFont;
        private Font _subNoteFont;
        private Font _dirBtnFont;

        public MainForm(bool startInTray = false)
        {
            _startHidden = startInTray;
            AppSettings.LoadPreferences(out _keepInBackground, out _quickCopyOnly, out _autoSave, out _autoSaveDir);
            _autoStart = AppSettings.IsAutoStartEnabled();

            _brandFont = UiTheme.FontPx(15, true);
            _actionFont = UiTheme.FontPx(15, true);
            _hotkeyFont = UiTheme.FontPx(12, false);
            _optionFont = UiTheme.FontPx(13, false);
            _subNoteFont = UiTheme.FontPx(11, false);
            _dirBtnFont = UiTheme.FontPx(11, false);

            Text = "SpanShot";
            Icon = AppIcon.GetWindowIcon();
            FormBorderStyle = FormBorderStyle.None;
            Size = new Size(UiTheme.S(310), UiTheme.S(276));

            StartPosition = FormStartPosition.Manual;
            Rectangle workArea = Screen.PrimaryScreen.WorkingArea;
            Location = new Point(
                workArea.Left + (workArea.Width - Width) / 2,
                workArea.Top + (workArea.Height - Height) / 2);

            BackColor = UiTheme.BgDark;
            ForeColor = Color.White;
            ShowInTaskbar = true;
            DoubleBuffered = true;

            SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.UserPaint | ControlStyles.OptimizedDoubleBuffer, true);
            Region = new Region(UiTheme.CreateRoundedRectPath(new Rectangle(0, 0, Width, Height), UiTheme.S(10)));

            ComputeLayout();
            InitializeTrayIcon();
        }

        protected override void SetVisibleCore(bool value)
        {
            if (_startHidden && value)
            {
                value = false;
                if (!IsHandleCreated)
                {
                    CreateHandle();
                }
            }
            base.SetVisibleCore(value);
        }

        private void ComputeLayout()
        {
            int pad = UiTheme.S(16);
            int fullW = Width - pad * 2;
            int btnH = UiTheme.S(46);

            _headerRect = new Rectangle(0, 0, Width - UiTheme.S(72), UiTheme.S(44));
            _btnMinRect = new Rectangle(Width - UiTheme.S(66), UiTheme.S(10), UiTheme.S(26), UiTheme.S(24));
            _btnCloseRect = new Rectangle(Width - UiTheme.S(36), UiTheme.S(10), UiTheme.S(26), UiTheme.S(24));

            _btnCaptureRect = new Rectangle(pad, UiTheme.S(48), fullW, btnH);
            _chkKeepAliveRect = new Rectangle(pad, UiTheme.S(106), fullW, UiTheme.S(26));
            _chkAutoStartRect = new Rectangle(pad, UiTheme.S(136), fullW, UiTheme.S(26));
            _chkQuickCopyRect = new Rectangle(pad, UiTheme.S(166), fullW, UiTheme.S(44));

            int dirBtnW = UiTheme.S(66);
            _btnChooseDirRect = new Rectangle(Width - pad - dirBtnW, UiTheme.S(217), dirBtnW, UiTheme.S(22));
            _chkAutoSaveRect = new Rectangle(pad, UiTheme.S(216), fullW, UiTheme.S(46));
        }

        private void InitializeTrayIcon()
        {
            ContextMenu trayMenu = new ContextMenu();
            trayMenu.MenuItems.Add("截图 (Alt+A)", (s, e) => TriggerCaptureFromMenu());
            trayMenu.MenuItems.Add("-");
            trayMenu.MenuItems.Add("显示主窗口", (s, e) => RestoreFromTray());
            trayMenu.MenuItems.Add("-");

            _menuKeepAlive = new MenuItem("常驻后台", (s, e) => ToggleKeepInBackground());
            _menuQuickCopy = new MenuItem("快捷截图", (s, e) => ToggleQuickCopy());
            _menuAutoSave = new MenuItem("自动保存", (s, e) => ToggleAutoSave());
            MenuItem menuSetDir = new MenuItem("指定自动保存目录...", (s, e) => ChooseAutoSaveDirectory(false));
            _menuAutoStart = new MenuItem("开机自启", (s, e) => ToggleAutoStart());

            trayMenu.MenuItems.Add(_menuKeepAlive);
            trayMenu.MenuItems.Add(_menuQuickCopy);
            trayMenu.MenuItems.Add(_menuAutoSave);
            trayMenu.MenuItems.Add(menuSetDir);
            trayMenu.MenuItems.Add(_menuAutoStart);
            trayMenu.MenuItems.Add("-");
            trayMenu.MenuItems.Add("彻底退出", (s, e) => ExitApplication());

            trayMenu.Popup += (s, e) =>
            {
                _autoStart = AppSettings.IsAutoStartEnabled();
                _menuKeepAlive.Checked = _keepInBackground;
                _menuQuickCopy.Checked = _quickCopyOnly;
                _menuAutoSave.Checked = _autoSave;
                _menuAutoStart.Checked = _autoStart;
            };

            _trayIcon = new NotifyIcon
            {
                Text = "SpanShot - 截图与长截图 (Alt+A)",
                Icon = AppIcon.GetTrayIcon(),
                ContextMenu = trayMenu,
                Visible = true
            };

            _trayIcon.MouseClick += (s, e) =>
            {
                if (e.Button == MouseButtons.Left)
                {
                    RestoreFromTray();
                }
            };
            _trayIcon.DoubleClick += (s, e) => RestoreFromTray();
        }

        private void TriggerCaptureFromMenu()
        {
            System.Windows.Forms.Timer delayTimer = new System.Windows.Forms.Timer { Interval = 110 };
            delayTimer.Tick += (s, e) =>
            {
                delayTimer.Stop();
                delayTimer.Dispose();
                StartCaptureFlow();
            };
            delayTimer.Start();
        }

        public void HideToTray(bool showHintIfFirstTime = true)
        {
            _draggingWindow = false;
            Hide();
            if (showHintIfFirstTime && !_shownTrayHintOnce)
            {
                _shownTrayHintOnce = true;
                ToastForm.ShowToast("已最小化到系统托盘 (Alt+A 随时截图)", UiTheme.WeChatGreen);
            }
        }

        public void RestoreFromTray()
        {
            _startHidden = false;
            Opacity = 1.0;
            Show();
            if (WindowState == FormWindowState.Minimized)
            {
                WindowState = FormWindowState.Normal;
            }
            Activate();
            if (IsHandleCreated)
            {
                NativeMethods.SetForegroundWindow(Handle);
            }
            Invalidate();
        }

        private void ExitApplication()
        {
            _forceExit = true;
            if (_trayIcon != null)
            {
                _trayIcon.Visible = false;
            }
            Application.Exit();
        }

        private void SaveCurrentPreferences()
        {
            AppSettings.SavePreferences(_keepInBackground, _quickCopyOnly, _autoSave, _autoSaveDir);
        }

        private void ToggleKeepInBackground()
        {
            _keepInBackground = !_keepInBackground;
            SaveCurrentPreferences();
            Invalidate();
        }

        private void ToggleQuickCopy()
        {
            _quickCopyOnly = !_quickCopyOnly;
            SaveCurrentPreferences();
            Invalidate();
        }

        private void ToggleAutoSave()
        {
            if (_autoSave)
            {
                _autoSave = false;
                SaveCurrentPreferences();
                Invalidate();
                return;
            }

            // Before enabling auto-save, ensure a folder has been selected AND is writable
            if (!string.IsNullOrEmpty(_autoSaveDir))
            {
                string errorMsg;
                if (AppSettings.ValidateWritableFolder(_autoSaveDir, out errorMsg))
                {
                    _autoSave = true;
                    SaveCurrentPreferences();
                    ToastForm.ShowToast("已开启自动保存", UiTheme.WeChatGreen);
                    Invalidate();
                    return;
                }
                else
                {
                    ToastForm.ShowToast("当前保存目录不可写，请重新选择文件夹", UiTheme.AccentOrange);
                    ChooseAutoSaveDirectory(true);
                    return;
                }
            }

            // No folder configured yet: prompt user to select a writable folder before turning on
            ChooseAutoSaveDirectory(true);
        }

        private bool ChooseAutoSaveDirectory(bool enableAfterValidSelection)
        {
            IntPtr owner = (Visible && IsHandleCreated) ? Handle : IntPtr.Zero;
            string dialogTitle = enableAfterValidSelection
                ? "开启自动保存前，请选择可写入的保存文件夹"
                : "选择截图自动保存文件夹";

            string chosen = AppSettings.PickFolderDialog(owner, _autoSaveDir, dialogTitle);
            if (string.IsNullOrEmpty(chosen))
            {
                if (enableAfterValidSelection)
                {
                    _autoSave = false;
                    SaveCurrentPreferences();
                    ToastForm.ShowToast("未选择文件夹，自动保存未开启", UiTheme.AccentOrange);
                    Invalidate();
                }
                return false;
            }

            string errorMessage;
            if (!AppSettings.ValidateWritableFolder(chosen, out errorMessage))
            {
                if (enableAfterValidSelection)
                {
                    _autoSave = false;
                    SaveCurrentPreferences();
                }
                ToastForm.ShowToast(errorMessage, UiTheme.AccentRed);
                Invalidate();
                return false;
            }

            _autoSaveDir = Path.GetFullPath(chosen.Trim());
            if (enableAfterValidSelection)
            {
                _autoSave = true;
                ToastForm.ShowToast("已验证目录可写并开启自动保存", UiTheme.WeChatGreen);
            }
            else
            {
                ToastForm.ShowToast(_autoSave ? "已更新自动保存目录" : "保存目录已就绪，可勾选开启自动保存", UiTheme.WeChatGreen);
            }

            SaveCurrentPreferences();
            Invalidate();
            return true;
        }

        private void ToggleAutoStart()
        {
            bool target = !_autoStart;
            if (AppSettings.SetAutoStart(target))
            {
                _autoStart = target;
                ToastForm.ShowToast(_autoStart ? "已开启开机自启（启动后静默驻留托盘）" : "已关闭开机自启", UiTheme.WeChatGreen);
            }
            else
            {
                _autoStart = AppSettings.IsAutoStartEnabled();
                ToastForm.ShowToast("设置开机自启失败，请检查系统权限", UiTheme.AccentRed);
            }
            Invalidate();
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

        protected override void OnResize(EventArgs e)
        {
            base.OnResize(e);
            if (!_isCapturing && WindowState == FormWindowState.Minimized)
            {
                HideToTray();
            }
        }

        protected override void OnFormClosing(FormClosingEventArgs e)
        {
            if (!_forceExit && e.CloseReason == CloseReason.UserClosing && _keepInBackground)
            {
                e.Cancel = true;
                HideToTray();
                return;
            }
            base.OnFormClosing(e);
        }

        protected override void WndProc(ref Message m)
        {
            if (m.Msg == NativeMethods.WM_SYSCOMMAND)
            {
                int cmd = (int)(m.WParam.ToInt64() & 0xFFF0);
                if (cmd == NativeMethods.SC_MINIMIZE)
                {
                    HideToTray();
                    return;
                }
            }
            else if (m.Msg == NativeMethods.WM_HOTKEY && !_isCapturing)
            {
                int id = m.WParam.ToInt32();
                if (id == HOTKEY_ID_GENERAL)
                {
                    StartCaptureFlow();
                    return;
                }
            }
            else if (Program.WM_SHOW_MAIN != 0 && (uint)m.Msg == Program.WM_SHOW_MAIN)
            {
                RestoreFromTray();
                return;
            }
            base.WndProc(ref m);
        }

        protected override void OnMouseDown(MouseEventArgs e)
        {
            base.OnMouseDown(e);
            if (e.Button != MouseButtons.Left) return;

            Point pt = e.Location;
            if (_btnMinRect.Contains(pt))
            {
                HideToTray();
                return;
            }
            if (_btnCloseRect.Contains(pt))
            {
                if (_keepInBackground)
                {
                    HideToTray();
                }
                else
                {
                    ExitApplication();
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
                ToggleKeepInBackground();
                return;
            }
            if (_chkAutoStartRect.Contains(pt))
            {
                ToggleAutoStart();
                return;
            }
            if (_chkQuickCopyRect.Contains(pt))
            {
                ToggleQuickCopy();
                return;
            }
            // Check directory selector button BEFORE the row checkbox rect
            if (_btnChooseDirRect.Contains(pt))
            {
                ChooseAutoSaveDirectory(false);
                return;
            }
            if (_chkAutoSaveRect.Contains(pt))
            {
                ToggleAutoSave();
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

            bool clickable = _btnMinRect.Contains(e.Location) ||
                             _btnCloseRect.Contains(e.Location) ||
                             _btnCaptureRect.Contains(e.Location) ||
                             _chkKeepAliveRect.Contains(e.Location) ||
                             _chkAutoStartRect.Contains(e.Location) ||
                             _chkQuickCopyRect.Contains(e.Location) ||
                             _btnChooseDirRect.Contains(e.Location) ||
                             _chkAutoSaveRect.Contains(e.Location);

            Cursor = clickable ? Cursors.Hand : Cursors.Default;
            Invalidate();
        }

        protected override void OnMouseLeave(EventArgs e)
        {
            base.OnMouseLeave(e);
            _mousePos = new Point(-1, -1);
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

            // Header custom scissors logo + brand title
            int iconSz = UiTheme.S(20);
            Bitmap logoBmp = AppIcon.GetHeaderBitmap(iconSz);
            if (logoBmp != null)
            {
                InterpolationMode prevInterp = g.InterpolationMode;
                g.InterpolationMode = InterpolationMode.HighQualityBicubic;
                g.DrawImage(logoBmp, new Rectangle(UiTheme.S(16), UiTheme.S(12), iconSz, iconSz));
                g.InterpolationMode = prevInterp;
            }

            using (StringFormat sfLeft = new StringFormat { Alignment = StringAlignment.Near, LineAlignment = StringAlignment.Center })
            {
                g.DrawString("SpanShot", _brandFont, Brushes.White,
                    new Rectangle(UiTheme.S(42), UiTheme.S(6), UiTheme.S(150), UiTheme.S(32)), sfLeft);
            }

            // Header Minimize-to-Tray button (—)
            bool minHover = _btnMinRect.Contains(_mousePos);
            if (minHover)
            {
                using (SolidBrush hb = new SolidBrush(UiTheme.BgCardHover))
                {
                    UiTheme.FillRoundedRect(g, hb, _btnMinRect, UiTheme.S(4));
                }
            }
            using (Pen minPen = new Pen(minHover ? Color.White : UiTheme.TextSecondary, Math.Max(1.6f, 1.6f * UiTheme.DpiScale))
            {
                StartCap = LineCap.Round,
                EndCap = LineCap.Round
            })
            {
                int my = _btnMinRect.Y + _btnMinRect.Height / 2;
                int halfW = UiTheme.S(5);
                int mx = _btnMinRect.X + _btnMinRect.Width / 2;
                g.DrawLine(minPen, mx - halfW, my, mx + halfW, my);
            }

            // Header Close button (✕)
            bool closeHover = _btnCloseRect.Contains(_mousePos);
            if (closeHover)
            {
                using (SolidBrush cb = new SolidBrush(UiTheme.AccentRed))
                {
                    UiTheme.FillRoundedRect(g, cb, _btnCloseRect, UiTheme.S(4));
                }
            }
            using (Pen closePen = new Pen(closeHover ? Color.White : UiTheme.TextSecondary, Math.Max(1.6f, 1.6f * UiTheme.DpiScale))
            {
                StartCap = LineCap.Round,
                EndCap = LineCap.Round
            })
            {
                int r = UiTheme.S(4);
                int cx = _btnCloseRect.X + _btnCloseRect.Width / 2;
                int cy = _btnCloseRect.Y + _btnCloseRect.Height / 2;
                g.DrawLine(closePen, cx - r, cy - r, cx + r, cy + r);
                g.DrawLine(closePen, cx + r, cy - r, cx - r, cy + r);
            }

            DrawCaptureButton(g, _btnCaptureRect, "截图", "Alt + A", _btnCaptureRect.Contains(_mousePos));
            DrawCheckboxOption(g, _chkKeepAliveRect, "常驻后台（最小化到托盘）", null, _keepInBackground, _chkKeepAliveRect.Contains(_mousePos), false);
            DrawCheckboxOption(g, _chkAutoStartRect, "开机自启", null, _autoStart, _chkAutoStartRect.Contains(_mousePos), false);
            DrawCheckboxOption(g, _chkQuickCopyRect, "快捷截图", "完成后直接复制到剪贴板，不打开预览窗", _quickCopyOnly, _chkQuickCopyRect.Contains(_mousePos), false);

            // Auto-save option + folder selector button
            bool dirBtnHover = _btnChooseDirRect.Contains(_mousePos);
            bool autoSaveRowHover = !dirBtnHover && _chkAutoSaveRect.Contains(_mousePos);
            string autoSaveSubNote = string.IsNullOrEmpty(_autoSaveDir)
                ? "未指定目录，开启前需先选择可写文件夹"
                : string.Format("目录：{0}", _autoSaveDir);

            DrawCheckboxOption(g, _chkAutoSaveRect, "自动保存", autoSaveSubNote, _autoSave, autoSaveRowHover, !string.IsNullOrEmpty(_autoSaveDir));
            DrawFolderActionButton(g, _btnChooseDirRect, string.IsNullOrEmpty(_autoSaveDir) ? "选择目录" : "更改目录", dirBtnHover);
        }

        private void DrawFolderActionButton(Graphics g, Rectangle rect, string text, bool hovered)
        {
            Color fill = hovered ? UiTheme.BgCardHover : UiTheme.BgCard;
            Color borderCol = hovered ? UiTheme.WeChatGreen : UiTheme.BorderSubtle;
            Color fg = hovered ? Color.White : UiTheme.TextPrimary;

            using (SolidBrush b = new SolidBrush(fill))
            using (Pen p = new Pen(borderCol, 1f))
            using (SolidBrush tb = new SolidBrush(fg))
            using (StringFormat sf = new StringFormat
            {
                Alignment = StringAlignment.Center,
                LineAlignment = StringAlignment.Center,
                FormatFlags = StringFormatFlags.NoWrap
            })
            {
                UiTheme.FillRoundedRect(g, b, rect, UiTheme.S(5));
                UiTheme.DrawRoundedRect(g, p, rect, UiTheme.S(5));
                g.DrawString(text, _dirBtnFont, tb, rect, sf);
            }
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

        private void DrawCheckboxOption(Graphics g, Rectangle rect, string label, string subNote, bool isChecked, bool hovered, bool pathEllipsis)
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
                Rectangle noteRect = new Rectangle(textX, rect.Y + UiTheme.S(23), textW, UiTheme.S(20));
                using (SolidBrush nb = new SolidBrush(UiTheme.TextSecondary))
                using (StringFormat sf = new StringFormat
                {
                    Alignment = StringAlignment.Near,
                    LineAlignment = StringAlignment.Center,
                    FormatFlags = StringFormatFlags.NoWrap,
                    Trimming = pathEllipsis ? StringTrimming.EllipsisPath : StringTrimming.EllipsisCharacter
                })
                {
                    g.DrawString(subNote, _subNoteFont, nb, noteRect, sf);
                }
            }
        }

        private void CopyAndOptionalAutoSave(Bitmap bmp, string tag)
        {
            if (bmp == null) return;
            try { Clipboard.SetImage(bmp); } catch { }

            if (_autoSave)
            {
                string savedPath;
                if (AppSettings.TryAutoSaveBitmap(bmp, _autoSaveDir, tag, out savedPath))
                {
                    ToastForm.ShowToast(string.Format("已复制并自动保存 ({0} × {1})", bmp.Width, bmp.Height), UiTheme.WeChatGreen);
                }
                else
                {
                    _autoSave = false;
                    SaveCurrentPreferences();
                    Invalidate();
                    ToastForm.ShowToast("已复制到剪贴板，但保存目录不可写，已关闭自动保存", UiTheme.AccentRed);
                }
            }
            else
            {
                ToastForm.ShowToast(string.Format("已复制到剪贴板 ({0} × {1})", bmp.Width, bmp.Height), UiTheme.WeChatGreen);
            }
        }

        private void OpenPreviewAndOptionalAutoSave(Bitmap bmp, string titleTag, string fileTag)
        {
            if (bmp == null) return;
            using (ResultPreviewForm editor = new ResultPreviewForm(bmp, titleTag, _autoSaveDir))
            {
                editor.ShowDialog();
                if (_autoSave && !editor.ManuallySaved && editor.WorkingBitmap != null)
                {
                    string savedPath;
                    if (AppSettings.TryAutoSaveBitmap(editor.WorkingBitmap, _autoSaveDir, fileTag, out savedPath))
                    {
                        ToastForm.ShowToast(editor.ConfirmedCopy ? "已复制并自动保存" : "已自动保存", UiTheme.WeChatGreen);
                    }
                    else
                    {
                        _autoSave = false;
                        SaveCurrentPreferences();
                        Invalidate();
                        ToastForm.ShowToast("自动保存失败（目录不可写），已关闭自动保存", UiTheme.AccentRed);
                    }
                }
                else if (!editor.ManuallySaved && editor.ConfirmedCopy)
                {
                    ToastForm.ShowToast("已复制到剪贴板", UiTheme.WeChatGreen);
                }
            }
        }

        private void SaveBitmapDialog(Bitmap bmp, string tag)
        {
            if (bmp == null) return;
            try { Clipboard.SetImage(bmp); } catch { }

            using (SaveFileDialog sfd = new SaveFileDialog())
            {
                sfd.Filter = "PNG 图像 (*.png)|*.png|JPEG 图像 (*.jpg)|*.jpg";
                sfd.DefaultExt = "png";
                if (!string.IsNullOrEmpty(_autoSaveDir) && Directory.Exists(_autoSaveDir))
                {
                    sfd.InitialDirectory = _autoSaveDir;
                }
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
                            CopyAndOptionalAutoSave(inlineAnnotatedBmp, "Shot");
                        }
                        else
                        {
                            OpenPreviewAndOptionalAutoSave(inlineAnnotatedBmp, "截图", "Shot");
                        }
                    }
                    return;
                }
                if (chosenAction == CaptureActionMode.NormalPinCompleted)
                {
                    using (inlineAnnotatedBmp)
                    {
                        CopyAndOptionalAutoSave(inlineAnnotatedBmp, "Shot");
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
                string scrollTag = dir == ScrollDirection.Vertical ? "Vertical" : "Horizontal";

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
                            CopyAndOptionalAutoSave(stitchedResult, scrollTag);
                        }
                        else if (exitAction == ScrollSessionExitAction.PinDirectly)
                        {
                            CopyAndOptionalAutoSave(stitchedResult, scrollTag);
                            PinWindowForm pin = new PinWindowForm(stitchedResult);
                            pin.Show();
                        }
                        else if (exitAction == ScrollSessionExitAction.SaveDirectly)
                        {
                            SaveBitmapDialog(stitchedResult, scrollTag);
                        }
                        else if (exitAction == ScrollSessionExitAction.OpenEditor)
                        {
                            OpenPreviewAndOptionalAutoSave(
                                stitchedResult,
                                dir == ScrollDirection.Vertical ? "纵向长截图" : "横向长截图",
                                scrollTag);
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
                if (_dirBtnFont != null) _dirBtnFont.Dispose();
            }
            base.Dispose(disposing);
        }
    }
}
