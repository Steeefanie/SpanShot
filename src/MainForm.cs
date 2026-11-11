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
        private MenuItem _menuOpenSaveDir;
        private MenuItem _menuAutoStart;

        private enum NoticeClickAction
        {
            None = 0,
            RetryCheckUpdate = 1,
            RetryPullUpdate = 2,
            OpenReleasesWeb = 3
        }

        private bool _startHidden;
        private bool _isCapturing;
        private bool _captureWasNormalVisible;
        private bool _keepInBackground = true;
        private bool _quickCopyOnly = false;
        private bool _autoSave = false;
        private string _autoSaveDir = string.Empty;
        private bool _autoStart = false;
        private bool _checkingUpdate = false;
        private bool _pullingUpdate = false;
        private int _pullProgressPct = 0;
        private ReleaseInfo _availableUpdate = null;
        private string _noticeText = string.Empty;
        private Color _noticeColor;
        private NoticeClickAction _noticeClickAction = NoticeClickAction.None;
        private System.Windows.Forms.Timer _noticeTimer;
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
        private Rectangle _chkAutoSaveTitleRect;
        private Rectangle _lblAutoSavePathRect;
        private Rectangle _btnOpenDirRect;
        private Rectangle _btnChooseDirRect;
        private Rectangle _bottomStatusRowRect;
        private Rectangle _lnkUpdateRect;
        private Rectangle _lnkPullUpdateRect;
        private Rectangle _lnkDismissUpdateRect;

        private Font _brandFont;
        private Font _actionFont;
        private Font _hotkeyFont;
        private Font _optionFont;
        private Font _subNoteFont;
        private Font _dirBtnFont;
        private float? _cachedPathOpticalDy;
        private float _cachedCjkCenterRelDy;

        public MainForm(bool startInTray = false)
        {
            UiTheme.RefreshSystemTheme();
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
            Size = new Size(UiTheme.S(318), UiTheme.S(310));

            StartPosition = FormStartPosition.Manual;
            Rectangle workArea = Screen.PrimaryScreen.WorkingArea;
            Location = new Point(
                workArea.Left + (workArea.Width - Width) / 2,
                workArea.Top + (workArea.Height - Height) / 2);

            BackColor = UiTheme.BgDark;
            ForeColor = UiTheme.TextPrimary;
            ShowInTaskbar = true;
            DoubleBuffered = true;

            SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.UserPaint | ControlStyles.OptimizedDoubleBuffer, true);
            Region = new Region(UiTheme.CreateRoundedRectPath(new Rectangle(0, 0, Width, Height), UiTheme.S(10)));

            _noticeTimer = new System.Windows.Forms.Timer { Interval = 2400 };
            _noticeTimer.Tick += (s, e) =>
            {
                _noticeTimer.Stop();
                if (_noticeClickAction == NoticeClickAction.None)
                {
                    _noticeText = string.Empty;
                    Invalidate();
                }
            };

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

            int dirBtnW = UiTheme.S(64);
            int dirBtnGap = UiTheme.S(6);
            _btnChooseDirRect = new Rectangle(Width - pad - dirBtnW, UiTheme.S(217), dirBtnW, UiTheme.S(22));
            _btnOpenDirRect = new Rectangle(_btnChooseDirRect.X - dirBtnGap - dirBtnW, UiTheme.S(217), dirBtnW, UiTheme.S(22));
            _chkAutoSaveRect = new Rectangle(pad, UiTheme.S(216), fullW, UiTheme.S(50));
            _chkAutoSaveTitleRect = new Rectangle(pad, UiTheme.S(216), _btnOpenDirRect.X - pad - UiTheme.S(4), UiTheme.S(24));
            _lblAutoSavePathRect = new Rectangle(pad + UiTheme.S(24), UiTheme.S(246), fullW - UiTheme.S(24), UiTheme.S(20));

            _bottomStatusRowRect = new Rectangle(pad, UiTheme.S(276), fullW, UiTheme.S(22));
            int hitW = UiTheme.S(76);
            _lnkUpdateRect = new Rectangle((Width - hitW) / 2, UiTheme.S(276), hitW, UiTheme.S(22));
            _lnkPullUpdateRect = Rectangle.Empty;
            _lnkDismissUpdateRect = Rectangle.Empty;
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
            _menuOpenSaveDir = new MenuItem("打开自动保存目录", (s, e) => OpenAutoSaveDirectory());
            _menuAutoStart = new MenuItem("开机自启", (s, e) => ToggleAutoStart());

            trayMenu.MenuItems.Add(_menuKeepAlive);
            trayMenu.MenuItems.Add(_menuQuickCopy);
            trayMenu.MenuItems.Add(_menuAutoSave);
            trayMenu.MenuItems.Add(menuSetDir);
            trayMenu.MenuItems.Add(_menuOpenSaveDir);
            trayMenu.MenuItems.Add(_menuAutoStart);
            trayMenu.MenuItems.Add("-");
            trayMenu.MenuItems.Add("检查更新...", (s, e) =>
            {
                RestoreFromTray();
                TriggerUpdateAction();
            });
            trayMenu.MenuItems.Add("彻底退出", (s, e) => ExitApplication());

            trayMenu.Popup += (s, e) =>
            {
                _autoStart = AppSettings.IsAutoStartEnabled();
                _menuKeepAlive.Checked = _keepInBackground;
                _menuQuickCopy.Checked = _quickCopyOnly;
                _menuAutoSave.Checked = _autoSave;
                _menuOpenSaveDir.Enabled = !string.IsNullOrEmpty(_autoSaveDir) && Directory.Exists(_autoSaveDir);
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

        public void HideToTray()
        {
            _draggingWindow = false;
            Hide();
        }

        public void ShowInlineNotice(string message, Color accent, int durationMs = 2400)
        {
            ShowInlineNoticeCore(message, accent, durationMs, NoticeClickAction.None);
        }

        private void ShowInlineNoticeCore(
            string message,
            Color accent,
            int durationMs,
            NoticeClickAction clickAction)
        {
            if (string.IsNullOrEmpty(message)) return;
            _noticeText = message;
            _noticeColor = (accent == UiTheme.WeChatGreen) ? UiTheme.TextSecondary : accent;
            _noticeClickAction = clickAction;

            if (_noticeTimer != null)
            {
                _noticeTimer.Stop();
                if (clickAction == NoticeClickAction.None && durationMs > 0)
                {
                    _noticeTimer.Interval = durationMs;
                    _noticeTimer.Start();
                }
            }
            Invalidate();
        }

        private void ClearInlineNotice()
        {
            _noticeText = string.Empty;
            _noticeClickAction = NoticeClickAction.None;
            if (_noticeTimer != null) _noticeTimer.Stop();
        }

        private void NotifyFeedback(string message, Color accent)
        {
            if (Visible || _captureWasNormalVisible)
            {
                ShowInlineNotice(message, accent);
            }
            else
            {
                ToastForm.ShowToast(message, accent);
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
                    ShowInlineNotice("已开启自动保存", UiTheme.WeChatGreen);
                    Invalidate();
                    return;
                }
                else
                {
                    ShowInlineNotice("目录不可写，请重新选择文件夹", UiTheme.AccentOrange);
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
                    ShowInlineNotice("未选择文件夹，自动保存未开启", UiTheme.AccentOrange);
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
                ShowInlineNotice(errorMessage, UiTheme.AccentRed);
                Invalidate();
                return false;
            }

            _autoSaveDir = Path.GetFullPath(chosen.Trim());
            if (enableAfterValidSelection)
            {
                _autoSave = true;
                ShowInlineNotice("已验证可写并开启自动保存", UiTheme.WeChatGreen);
            }
            else
            {
                ShowInlineNotice(_autoSave ? "已更新自动保存目录" : "保存目录已就绪，可勾选开启", UiTheme.WeChatGreen);
            }

            SaveCurrentPreferences();
            Invalidate();
            return true;
        }

        private void OpenAutoSaveDirectory()
        {
            if (string.IsNullOrEmpty(_autoSaveDir))
            {
                ShowInlineNotice("请先指定自动保存文件夹", UiTheme.AccentOrange);
                return;
            }
            if (!Directory.Exists(_autoSaveDir))
            {
                ShowInlineNotice("保存目录不存在，请重新选择", UiTheme.AccentRed);
                return;
            }
            try
            {
                System.Diagnostics.Process.Start("explorer.exe", string.Format("\"{0}\"", _autoSaveDir));
            }
            catch
            {
                ShowInlineNotice("无法打开保存文件夹", UiTheme.AccentRed);
            }
        }

        private void TriggerUpdateAction()
        {
            if (_checkingUpdate || _pullingUpdate) return;

            ClearInlineNotice();
            _checkingUpdate = true;
            Invalidate();

            ThreadPool.QueueUserWorkItem(_ =>
            {
                ReleaseInfo info;
                string err;
                bool ok = UpdateManager.CheckLatestRelease(out info, out err);

                try
                {
                    if (IsHandleCreated && !IsDisposed)
                    {
                        BeginInvoke(new Action(() =>
                        {
                            _checkingUpdate = false;
                            if (!ok)
                            {
                                ShowInlineNoticeCore(
                                    err ?? "连接 GitHub 失败，点击重试",
                                    UiTheme.AccentOrange,
                                    0,
                                    NoticeClickAction.RetryCheckUpdate);
                                return;
                            }

                            if (info != null && info.IsNewer)
                            {
                                _availableUpdate = info;
                                ClearInlineNotice();
                                Invalidate();
                            }
                            else
                            {
                                _availableUpdate = null;
                                ShowInlineNoticeCore(
                                    string.Format("当前已是最新版本 (v{0})", UpdateManager.CurrentVersion),
                                    UiTheme.WeChatGreen,
                                    2600,
                                    NoticeClickAction.None);
                            }
                        }));
                    }
                }
                catch { }
            });
        }

        private void StartInlinePullUpdate()
        {
            if (_pullingUpdate || _availableUpdate == null) return;

            if (string.IsNullOrEmpty(_availableUpdate.WindowsDownloadUrl))
            {
                try { System.Diagnostics.Process.Start(_availableUpdate.HtmlUrl ?? UpdateManager.RepoReleasesPageUrl); } catch { }
                return;
            }

            ClearInlineNotice();
            _pullingUpdate = true;
            _pullProgressPct = 0;
            Invalidate();

            ReleaseInfo targetRelease = _availableUpdate;
            ThreadPool.QueueUserWorkItem(_ =>
            {
                bool permDenied;
                string err;
                bool ok = UpdateManager.DownloadAndApplyUpdate(
                    targetRelease,
                    pct =>
                    {
                        try
                        {
                            if (IsHandleCreated && !IsDisposed)
                            {
                                BeginInvoke(new Action(() =>
                                {
                                    _pullProgressPct = pct;
                                    Invalidate();
                                }));
                            }
                        }
                        catch { }
                    },
                    out permDenied,
                    out err);

                try
                {
                    if (IsHandleCreated && !IsDisposed)
                    {
                        BeginInvoke(new Action(() =>
                        {
                            _pullingUpdate = false;
                            if (ok)
                            {
                                ExitApplication();
                            }
                            else
                            {
                                ShowInlineNoticeCore(
                                    err ?? "拉取更新失败，点击重试",
                                    UiTheme.AccentOrange,
                                    0,
                                    permDenied ? NoticeClickAction.OpenReleasesWeb : NoticeClickAction.RetryPullUpdate);
                            }
                        }));
                    }
                }
                catch { }
            });
        }

        private void ToggleAutoStart()
        {
            bool target = !_autoStart;
            if (AppSettings.SetAutoStart(target))
            {
                _autoStart = target;
                ShowInlineNotice(_autoStart ? "已开启开机自启（静默驻留托盘）" : "已关闭开机自启", UiTheme.WeChatGreen);
            }
            else
            {
                _autoStart = AppSettings.IsAutoStartEnabled();
                ShowInlineNotice("设置开机自启失败，请检查权限", UiTheme.AccentRed);
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
            else if (m.Msg == NativeMethods.WM_SETTINGCHANGE)
            {
                if (UiTheme.RefreshSystemTheme())
                {
                    BackColor = UiTheme.BgDark;
                    ForeColor = UiTheme.TextPrimary;
                    Invalidate();
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
            // Check directory action buttons & clickable path BEFORE the row checkbox toggle
            bool hasDir = !string.IsNullOrEmpty(_autoSaveDir);
            if (_btnChooseDirRect.Contains(pt))
            {
                ChooseAutoSaveDirectory(false);
                return;
            }
            if (hasDir && _btnOpenDirRect.Contains(pt))
            {
                OpenAutoSaveDirectory();
                return;
            }
            if (hasDir && _lblAutoSavePathRect.Contains(pt))
            {
                OpenAutoSaveDirectory();
                return;
            }
            if (_chkAutoSaveRect.Contains(pt))
            {
                ToggleAutoSave();
                return;
            }
            if (HandleBottomStatusMouseDown(pt))
            {
                return;
            }
        }

        private bool HandleBottomStatusMouseDown(Point pt)
        {
            if (_checkingUpdate || _pullingUpdate) return false;

            if (!string.IsNullOrEmpty(_noticeText))
            {
                if (_noticeClickAction != NoticeClickAction.None && _bottomStatusRowRect.Contains(pt))
                {
                    NoticeClickAction act = _noticeClickAction;
                    ClearInlineNotice();
                    if (act == NoticeClickAction.RetryCheckUpdate)
                    {
                        TriggerUpdateAction();
                    }
                    else if (act == NoticeClickAction.RetryPullUpdate)
                    {
                        StartInlinePullUpdate();
                    }
                    else if (act == NoticeClickAction.OpenReleasesWeb)
                    {
                        string url = (_availableUpdate != null && !string.IsNullOrEmpty(_availableUpdate.HtmlUrl))
                            ? _availableUpdate.HtmlUrl
                            : UpdateManager.RepoReleasesPageUrl;
                        try { System.Diagnostics.Process.Start(url); } catch { }
                        Invalidate();
                    }
                    return true;
                }
                return false;
            }

            if (_availableUpdate != null && _availableUpdate.IsNewer)
            {
                if (_lnkPullUpdateRect.Contains(pt))
                {
                    StartInlinePullUpdate();
                    return true;
                }
                if (_lnkDismissUpdateRect.Contains(pt))
                {
                    _availableUpdate = null;
                    Invalidate();
                    return true;
                }
                return false;
            }

            if (_lnkUpdateRect.Contains(pt))
            {
                TriggerUpdateAction();
                return true;
            }
            return false;
        }

        private bool IsBottomStatusClickableAt(Point pt)
        {
            if (_checkingUpdate || _pullingUpdate) return false;
            if (!string.IsNullOrEmpty(_noticeText))
            {
                return _noticeClickAction != NoticeClickAction.None && _bottomStatusRowRect.Contains(pt);
            }
            if (_availableUpdate != null && _availableUpdate.IsNewer)
            {
                return _lnkPullUpdateRect.Contains(pt) || _lnkDismissUpdateRect.Contains(pt);
            }
            return _lnkUpdateRect.Contains(pt);
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

            bool hasDir = !string.IsNullOrEmpty(_autoSaveDir);
            bool clickable = _btnMinRect.Contains(e.Location) ||
                             _btnCloseRect.Contains(e.Location) ||
                             _btnCaptureRect.Contains(e.Location) ||
                             _chkKeepAliveRect.Contains(e.Location) ||
                             _chkAutoStartRect.Contains(e.Location) ||
                             _chkQuickCopyRect.Contains(e.Location) ||
                             _btnChooseDirRect.Contains(e.Location) ||
                             (hasDir && _btnOpenDirRect.Contains(e.Location)) ||
                             _chkAutoSaveRect.Contains(e.Location) ||
                             IsBottomStatusClickableAt(e.Location);

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
            using (SolidBrush brandBrush = new SolidBrush(UiTheme.TextPrimary))
            {
                g.DrawString("SpanShot", _brandFont, brandBrush,
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
            using (Pen minPen = new Pen(minHover ? UiTheme.TextPrimary : UiTheme.TextSecondary, Math.Max(1.6f, 1.6f * UiTheme.DpiScale))
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
            DrawCheckboxOption(g, _chkKeepAliveRect, "常驻后台（最小化到托盘）", null, _keepInBackground, _chkKeepAliveRect.Contains(_mousePos), false, false, UiTheme.S(23));
            DrawCheckboxOption(g, _chkAutoStartRect, "开机自启", null, _autoStart, _chkAutoStartRect.Contains(_mousePos), false, false, UiTheme.S(23));
            DrawCheckboxOption(g, _chkQuickCopyRect, "快捷截图", "完成后直接复制到剪贴板，不打开预览窗", _quickCopyOnly, _chkQuickCopyRect.Contains(_mousePos), false, false, UiTheme.S(23));

            // Auto-save option + Open Folder / Choose Folder buttons + clickable folder path
            bool hasSaveDir = !string.IsNullOrEmpty(_autoSaveDir);
            bool chooseBtnHover = _btnChooseDirRect.Contains(_mousePos);
            bool openBtnHover = hasSaveDir && _btnOpenDirRect.Contains(_mousePos);
            bool pathLinkHover = hasSaveDir && !chooseBtnHover && !openBtnHover && _lblAutoSavePathRect.Contains(_mousePos);
            bool autoSaveRowHover = !chooseBtnHover && !openBtnHover && !pathLinkHover && _chkAutoSaveRect.Contains(_mousePos);

            string autoSaveSubNote = hasSaveDir
                ? null
                : "未指定目录，开启前需先选择可写文件夹";

            DrawCheckboxOption(g, _chkAutoSaveRect, "自动保存", autoSaveSubNote, _autoSave, autoSaveRowHover, false, false, UiTheme.S(30));
            if (hasSaveDir)
            {
                DrawAlignedFolderPathLine(g, _lblAutoSavePathRect, _autoSaveDir, pathLinkHover);
                DrawFolderActionButton(g, _btnOpenDirRect, "打开目录", openBtnHover);
            }
            DrawFolderActionButton(g, _btnChooseDirRect, hasSaveDir ? "更改目录" : "选择目录", chooseBtnHover);

            // Unified in-window bottom status / update row (strictly bounded within _bottomStatusRowRect)
            DrawBottomStatusArea(g);
        }

        private void DrawBottomStatusArea(Graphics g)
        {
            _lnkPullUpdateRect = Rectangle.Empty;
            _lnkDismissUpdateRect = Rectangle.Empty;

            using (StringFormat sfCenter = new StringFormat
            {
                Alignment = StringAlignment.Center,
                LineAlignment = StringAlignment.Center,
                FormatFlags = StringFormatFlags.NoWrap,
                Trimming = StringTrimming.EllipsisCharacter
            })
            {
                if (_pullingUpdate && _availableUpdate != null)
                {
                    string dlText = string.Format("正在拉取 {0}... {1}%", _availableUpdate.TagName, _pullProgressPct);
                    using (SolidBrush lb = new SolidBrush(UiTheme.LinkBlue))
                    {
                        g.DrawString(dlText, _hotkeyFont, lb, _bottomStatusRowRect, sfCenter);
                    }

                    int barW = UiTheme.S(160);
                    int barH = UiTheme.S(3);
                    Rectangle barTrack = new Rectangle((Width - barW) / 2, _bottomStatusRowRect.Bottom + UiTheme.S(1), barW, barH);
                    int fillW = Math.Max(UiTheme.S(6), (barW * _pullProgressPct) / 100);
                    using (SolidBrush trackBrush = new SolidBrush(UiTheme.BgCard))
                    using (SolidBrush fillBrush = new SolidBrush(UiTheme.LinkBlue))
                    {
                        UiTheme.FillRoundedRect(g, trackBrush, barTrack, UiTheme.S(2));
                        UiTheme.FillRoundedRect(g, fillBrush, new Rectangle(barTrack.X, barTrack.Y, fillW, barH), UiTheme.S(2));
                    }
                    return;
                }

                if (_checkingUpdate)
                {
                    using (SolidBrush sb = new SolidBrush(UiTheme.TextSecondary))
                    {
                        g.DrawString("正在检查更新...", _hotkeyFont, sb, _bottomStatusRowRect, sfCenter);
                    }
                    return;
                }

                if (!string.IsNullOrEmpty(_noticeText))
                {
                    bool clickable = _noticeClickAction != NoticeClickAction.None;
                    bool hovered = clickable && _bottomStatusRowRect.Contains(_mousePos);
                    Color col = hovered ? UiTheme.Lighten(_noticeColor, UiTheme.IsDarkMode ? 22 : -22) : _noticeColor;
                    using (SolidBrush nb = new SolidBrush(col))
                    {
                        g.DrawString(_noticeText, _hotkeyFont, nb, _bottomStatusRowRect, sfCenter);
                    }
                    return;
                }

                if (_availableUpdate != null && _availableUpdate.IsNewer)
                {
                    string prefix = string.Format("发现新版本 {0} ·", _availableUpdate.TagName);
                    string actionText = string.IsNullOrEmpty(_availableUpdate.WindowsDownloadUrl) ? "前往下载" : "拉取更新";
                    string dismissText = "忽略";

                    StringFormat sfTypo = StringFormat.GenericTypographic;
                    int wPrefix = (int)Math.Ceiling(g.MeasureString(prefix, _hotkeyFont, 1000, sfTypo).Width);
                    int dotGap = UiTheme.S(6);
                    int wAction = (int)Math.Ceiling(g.MeasureString(actionText, _hotkeyFont, 1000, sfTypo).Width);
                    int gap = UiTheme.S(12);
                    int wDismiss = (int)Math.Ceiling(g.MeasureString(dismissText, _hotkeyFont, 1000, sfTypo).Width);
                    int textH = (int)Math.Ceiling(g.MeasureString("测", _hotkeyFont, 200, sfTypo).Height);
                    int totalW = wPrefix + dotGap + wAction + gap + wDismiss;

                    int startX = Math.Max(_bottomStatusRowRect.X, (Width - totalW) / 2);
                    int rowY = _bottomStatusRowRect.Y;
                    int rowH = _bottomStatusRowRect.Height;
                    float drawY = rowY + (rowH - textH) / 2f;

                    int actionX = startX + wPrefix + dotGap;
                    int dismissX = actionX + wAction + gap;
                    _lnkPullUpdateRect = new Rectangle(actionX - UiTheme.S(2), rowY, wAction + UiTheme.S(4), rowH);
                    _lnkDismissUpdateRect = new Rectangle(dismissX - UiTheme.S(2), rowY, wDismiss + UiTheme.S(4), rowH);

                    bool pullHover = _lnkPullUpdateRect.Contains(_mousePos);
                    bool dismissHover = _lnkDismissUpdateRect.Contains(_mousePos);

                    Color pullCol = pullHover
                        ? UiTheme.Lighten(UiTheme.LinkBlue, UiTheme.IsDarkMode ? 24 : -24)
                        : UiTheme.LinkBlue;
                    Color dismissCol = dismissHover ? UiTheme.TextPrimary : UiTheme.TextSecondary;

                    using (SolidBrush bPrefix = new SolidBrush(UiTheme.TextSecondary))
                    using (SolidBrush bPull = new SolidBrush(pullCol))
                    using (SolidBrush bDismiss = new SolidBrush(dismissCol))
                    {
                        g.DrawString(prefix, _hotkeyFont, bPrefix, new PointF(startX, drawY), sfTypo);
                        g.DrawString(actionText, _hotkeyFont, bPull, new PointF(actionX, drawY), sfTypo);
                        g.DrawString(dismissText, _hotkeyFont, bDismiss, new PointF(dismissX, drawY), sfTypo);
                    }
                    return;
                }

                bool linkHover = _lnkUpdateRect.Contains(_mousePos);
                Color linkColor = linkHover
                    ? UiTheme.Lighten(UiTheme.LinkBlue, UiTheme.IsDarkMode ? 24 : -24)
                    : UiTheme.LinkBlue;
                using (SolidBrush lb = new SolidBrush(linkColor))
                {
                    g.DrawString("检查更新", _hotkeyFont, lb, _bottomStatusRowRect, sfCenter);
                }
            }
        }

        private void DrawFolderActionButton(Graphics g, Rectangle rect, string text, bool hovered)
        {
            Color fill = hovered ? UiTheme.BgCardHover : UiTheme.BgCard;
            Color borderCol = hovered ? UiTheme.WeChatGreen : UiTheme.BorderSubtle;
            Color fg = UiTheme.TextPrimary;

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

        private void DrawCheckboxOption(Graphics g, Rectangle rect, string label, string subNote, bool isChecked, bool hovered, bool pathEllipsis, bool highlightSubNote, int subNoteOffsetY)
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
            using (SolidBrush tb = new SolidBrush(UiTheme.TextPrimary))
            using (StringFormat sf = new StringFormat { Alignment = StringAlignment.Near, LineAlignment = StringAlignment.Center })
            {
                g.DrawString(label, _optionFont, tb, lblRect, sf);
            }

            if (!string.IsNullOrEmpty(subNote))
            {
                Rectangle noteRect = new Rectangle(textX, rect.Y + subNoteOffsetY, textW, UiTheme.S(20));
                Color subColor = highlightSubNote ? UiTheme.AccentTeal : UiTheme.TextSecondary;
                using (SolidBrush nb = new SolidBrush(subColor))
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

        private void DrawAlignedFolderPathLine(Graphics g, Rectangle rowRect, string folderPath, bool hovered)
        {
            if (!_cachedPathOpticalDy.HasValue)
            {
                float cjkRel;
                _cachedPathOpticalDy = ComputeInkMidpointOffset(_subNoteFont, "目录", @"C:\Users\taich", out cjkRel);
                _cachedCjkCenterRelDy = cjkRel;
            }

            Color col = hovered ? UiTheme.AccentTeal : UiTheme.TextSecondary;
            const string prefix = "目录";
            StringFormat sfTypo = StringFormat.GenericTypographic;
            int prefixW = (int)Math.Ceiling(g.MeasureString(prefix, _subNoteFont, 400, sfTypo).Width);
            int colonSpaceW = UiTheme.S(9);

            using (SolidBrush b = new SolidBrush(col))
            using (StringFormat sfPrefix = new StringFormat
            {
                Alignment = StringAlignment.Near,
                LineAlignment = StringAlignment.Center,
                FormatFlags = StringFormatFlags.NoWrap
            })
            using (StringFormat sfPath = new StringFormat
            {
                Alignment = StringAlignment.Near,
                LineAlignment = StringAlignment.Center,
                FormatFlags = StringFormatFlags.NoWrap,
                Trimming = StringTrimming.EllipsisPath
            })
            {
                RectangleF prefixRect = new RectangleF(rowRect.X, rowRect.Y, prefixW + UiTheme.S(8), rowRect.Height);
                g.DrawString(prefix, _subNoteFont, b, prefixRect, sfPrefix);

                // Draw optically centered colon dots aligned to the exact CJK glyph ink centroid
                float dotRadius = Math.Max(0.95f, 0.95f * UiTheme.DpiScale);
                float colonCenterX = rowRect.X + prefixW + UiTheme.S(5);
                float cjkCenterY = rowRect.Y + rowRect.Height * 0.5f + _cachedCjkCenterRelDy;
                float dotOffset = Math.Max(2.2f, 2.3f * UiTheme.DpiScale);
                g.FillEllipse(b, colonCenterX - dotRadius, cjkCenterY - dotOffset - dotRadius, dotRadius * 2f, dotRadius * 2f);
                g.FillEllipse(b, colonCenterX - dotRadius, cjkCenterY + dotOffset - dotRadius, dotRadius * 2f, dotRadius * 2f);

                float pathX = rowRect.X + prefixW + colonSpaceW;
                RectangleF pathRect = new RectangleF(
                    pathX,
                    rowRect.Y + _cachedPathOpticalDy.Value,
                    Math.Max(10f, rowRect.Right - pathX),
                    rowRect.Height);

                g.DrawString(folderPath, _subNoteFont, b, pathRect, sfPath);
            }
        }

        private static float ComputeInkMidpointOffset(Font font, string cjkSample, string latinSample, out float cjkRelFromRectCenter)
        {
            const int boxH = 72;
            float cjkCentroid = MeasureGlyphInkCentroidY(font, cjkSample, boxH);
            float latinCentroid = MeasureGlyphInkCentroidY(font, latinSample, boxH);
            cjkRelFromRectCenter = (cjkCentroid > 0f) ? (cjkCentroid - boxH * 0.5f) : 0f;
            if (cjkCentroid < 0f || latinCentroid < 0f) return 0f;
            return cjkCentroid - latinCentroid;
        }

        private static float MeasureGlyphInkCentroidY(Font font, string sample, int h)
        {
            const int w = 520;
            using (Bitmap bmp = new Bitmap(w, h, PixelFormat.Format32bppArgb))
            {
                using (Graphics g = Graphics.FromImage(bmp))
                using (StringFormat sf = new StringFormat
                {
                    Alignment = StringAlignment.Near,
                    LineAlignment = StringAlignment.Center,
                    FormatFlags = StringFormatFlags.NoWrap
                })
                {
                    g.SmoothingMode = SmoothingMode.AntiAlias;
                    g.Clear(Color.White);
                    g.DrawString(sample, font, Brushes.Black, new RectangleF(8f, 0f, w - 16f, h), sf);
                }

                double weightedSumY = 0.0;
                double totalWeight = 0.0;
                BitmapData bd = bmp.LockBits(new Rectangle(0, 0, w, h), ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
                try
                {
                    int stride = Math.Abs(bd.Stride);
                    byte[] raw = new byte[stride * h];
                    System.Runtime.InteropServices.Marshal.Copy(bd.Scan0, raw, 0, raw.Length);
                    for (int y = 0; y < h; y++)
                    {
                        int rowOff = y * stride;
                        for (int x = 0; x < w; x++)
                        {
                            int darkness = 255 - raw[rowOff + x * 4];
                            if (darkness > 12)
                            {
                                weightedSumY += y * darkness;
                                totalWeight += darkness;
                            }
                        }
                    }
                }
                finally
                {
                    bmp.UnlockBits(bd);
                }

                if (totalWeight <= 0.0) return -1f;
                return (float)(weightedSumY / totalWeight);
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
                    NotifyFeedback(string.Format("已复制并自动保存 ({0} × {1})", bmp.Width, bmp.Height), UiTheme.WeChatGreen);
                }
                else
                {
                    _autoSave = false;
                    SaveCurrentPreferences();
                    Invalidate();
                    NotifyFeedback("已复制（目录不可写，已关自动保存）", UiTheme.AccentRed);
                }
            }
            else
            {
                NotifyFeedback(string.Format("已复制到剪贴板 ({0} × {1})", bmp.Width, bmp.Height), UiTheme.WeChatGreen);
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
                        NotifyFeedback(editor.ConfirmedCopy ? "已复制并自动保存" : "已自动保存", UiTheme.WeChatGreen);
                    }
                    else
                    {
                        _autoSave = false;
                        SaveCurrentPreferences();
                        Invalidate();
                        NotifyFeedback("目录不可写，已关闭自动保存", UiTheme.AccentRed);
                    }
                }
                else if (!editor.ManuallySaved && editor.ConfirmedCopy)
                {
                    NotifyFeedback("已复制到剪贴板", UiTheme.WeChatGreen);
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
                    NotifyFeedback("已保存", UiTheme.WeChatGreen);
                }
            }
        }

        private void StartCaptureFlow()
        {
            if (_isCapturing) return;
            _isCapturing = true;

            bool wasNormalVisible = Visible && WindowState != FormWindowState.Minimized;
            _captureWasNormalVisible = wasNormalVisible;
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
                    Invalidate();
                }
                _captureWasNormalVisible = false;
                _isCapturing = false;
            }
        }

        protected override void Dispose(bool disposing)
        {
            if (disposing)
            {
                if (_noticeTimer != null) _noticeTimer.Dispose();
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
