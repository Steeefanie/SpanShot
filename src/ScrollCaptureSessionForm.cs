using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Windows.Forms;

namespace SpanShot
{
    public enum ScrollSessionExitAction
    {
        Cancelled = 0,
        CopyDirectly = 1,
        PinDirectly = 2,
        SaveDirectly = 3,
        OpenEditor = 4
    }

    internal sealed class HollowBorderOverlay : Form
    {
        private readonly int _borderThickness;
        private readonly Color _borderColor;

        public HollowBorderOverlay(Rectangle targetRect)
        {
            _borderThickness = Math.Max(3, UiTheme.S(3));
            _borderColor = UiTheme.WeChatGreen;

            FormBorderStyle = FormBorderStyle.None;
            StartPosition = FormStartPosition.Manual;
            Bounds = new Rectangle(
                targetRect.X - _borderThickness,
                targetRect.Y - _borderThickness,
                targetRect.Width + _borderThickness * 2,
                targetRect.Height + _borderThickness * 2);
            TopMost = true;
            ShowInTaskbar = false;
            DoubleBuffered = true;
            BackColor = _borderColor;

            Region outer = new Region(new Rectangle(0, 0, Width, Height));
            outer.Exclude(new Rectangle(_borderThickness, _borderThickness, targetRect.Width, targetRect.Height));
            Region = outer;
        }

        protected override void OnHandleCreated(EventArgs e)
        {
            base.OnHandleCreated(e);
            NativeMethods.MakeWindowClickThrough(Handle);
            NativeMethods.EnsureTopMost(Handle);
        }

        protected override bool ShowWithoutActivation { get { return true; } }

        protected override void OnPaint(PaintEventArgs e)
        {
            using (SolidBrush b = new SolidBrush(_borderColor))
            {
                e.Graphics.FillRectangle(b, 0, 0, Width, Height);
            }
        }
    }

    public sealed class ScrollCaptureSessionForm : Form
    {
        private readonly Rectangle _captureRect;
        private readonly ScrollDirection _direction;
        private readonly StitchEngine _engine;
        private readonly HollowBorderOverlay _borderOverlay;
        private readonly Timer _captureTimer;

        private bool _autoScrolling;
        private int _autoScrollTickCounter;
        private int _noMoveAutoCount;
        private bool _escWasDown;

        private HorizontalScrollMethod _horizMethod = HorizontalScrollMethod.PlainWheel;
        private const int AutoScrollWheelAmount = 120;
        private const int AutoScrollTickModulo = 4;

        private bool _draggingPanel;
        private Point _dragPanelStart;
        private Point _mousePos;

        private string _dimensionText = "";
        private Bitmap _latestPreviewBitmap;

        private Rectangle _headerDragRect;
        private Rectangle _previewCanvasRect;
        private Rectangle _btnAutoToggleRect;
        private Rectangle _btnCancelRect;
        private Rectangle _btnFinishRect;

        private Font _titleFont;
        private Font _dimFont;
        private Font _btnFont;

        public Bitmap FinalStitchedBitmap { get; private set; }
        public ScrollSessionExitAction ExitAction { get; private set; }

        public ScrollCaptureSessionForm(Rectangle physicalCaptureRect, ScrollDirection direction)
        {
            _captureRect = physicalCaptureRect;
            _direction = direction;
            _engine = new StitchEngine(direction);
            _borderOverlay = new HollowBorderOverlay(_captureRect);

            _titleFont = UiTheme.FontPx(13, true);
            _dimFont = UiTheme.FontPx(12, false);
            _btnFont = UiTheme.FontPx(12, false);

            FormBorderStyle = FormBorderStyle.None;
            StartPosition = FormStartPosition.Manual;
            Size = new Size(UiTheme.S(210), UiTheme.S(250));
            TopMost = true;
            ShowInTaskbar = false;
            BackColor = UiTheme.ToolbarBg;
            ForeColor = Color.White;
            KeyPreview = true;
            DoubleBuffered = true;

            SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.UserPaint | ControlStyles.OptimizedDoubleBuffer, true);

            ComputeLayoutRects();
            PositionPanelNearCaptureRect();

            _dimensionText = string.Format("{0} × {1}", _captureRect.Width, _captureRect.Height);
            _escWasDown = (NativeMethods.GetAsyncKeyState(NativeMethods.VK_ESCAPE) & 0x8000) != 0;

            _captureTimer = new Timer { Interval = 50 };
            _captureTimer.Tick += OnCaptureTimerTick;
        }

        private void ComputeLayoutRects()
        {
            int pad = UiTheme.S(8);
            int innerW = Width - pad * 2;

            _headerDragRect = new Rectangle(0, 0, Width, UiTheme.S(32));
            _previewCanvasRect = new Rectangle(pad, UiTheme.S(34), innerW, Height - UiTheme.S(34) - UiTheme.S(42));

            int barY = Height - UiTheme.S(34);
            int btnH = UiTheme.S(26);
            int gap = UiTheme.S(5);
            int cancelW = UiTheme.S(30);
            int finishW = UiTheme.S(58);
            int autoW = innerW - cancelW - finishW - gap * 2;

            int curX = pad;
            _btnAutoToggleRect = new Rectangle(curX, barY, autoW, btnH); curX += autoW + gap;
            _btnCancelRect = new Rectangle(curX, barY, cancelW, btnH); curX += cancelW + gap;
            _btnFinishRect = new Rectangle(curX, barY, finishW, btnH);
        }

        private void PositionPanelNearCaptureRect()
        {
            Rectangle screen = Screen.FromRectangle(_captureRect).WorkingArea;
            int gap = UiTheme.S(10);

            int clampedY = Math.Max(screen.Top + 6, Math.Min(screen.Bottom - Height - 6, _captureRect.Bottom - Height));
            int clampedX = Math.Max(screen.Left + 6, Math.Min(screen.Right - Width - 6, _captureRect.Right - Width));

            if (_captureRect.Bottom + gap + Height <= screen.Bottom)
            {
                Location = new Point(clampedX, _captureRect.Bottom + gap);
                return;
            }
            if (_captureRect.Right + gap + Width <= screen.Right)
            {
                Location = new Point(_captureRect.Right + gap, clampedY);
                return;
            }
            if (_captureRect.Left - gap - Width >= screen.Left)
            {
                Location = new Point(_captureRect.Left - gap - Width, clampedY);
                return;
            }
            if (_captureRect.Top - gap - Height >= screen.Top)
            {
                Location = new Point(clampedX, _captureRect.Top - gap - Height);
                return;
            }

            Location = new Point(
                Math.Min(screen.Right - Width - 12, _captureRect.Right - Width - 12),
                Math.Min(screen.Bottom - Height - 12, _captureRect.Bottom - Height - 12));
        }

        protected override void OnHandleCreated(EventArgs e)
        {
            base.OnHandleCreated(e);
            NativeMethods.TryExcludeWindowFromCapture(Handle);
            NativeMethods.EnsureTopMost(Handle);
        }

        protected override void OnShown(EventArgs e)
        {
            base.OnShown(e);
            _borderOverlay.Show();
            NativeMethods.EnsureTopMost(_borderOverlay.Handle);
            NativeMethods.EnsureTopMost(Handle);

            CaptureAndProcessFrame();
            _captureTimer.Start();
        }

        private void GetScrollTargetPoint(out int targetX, out int targetY)
        {
            if (_direction == ScrollDirection.Horizontal)
            {
                // Target the right-middle scrollable body (75% X, 58% Y) to avoid frozen left columns and top/bottom bars
                targetX = _captureRect.Left + (_captureRect.Width * 3) / 4;
                targetY = _captureRect.Top + (_captureRect.Height * 58) / 100;
            }
            else
            {
                targetX = _captureRect.Left + _captureRect.Width / 2;
                targetY = _captureRect.Top + (_captureRect.Height * 55) / 100;
            }
        }

        private void RefocusTargetWindow()
        {
            int tx, ty;
            GetScrollTargetPoint(out tx, out ty);
            NativeMethods.FocusWindowAtPoint(tx, ty);
            if (_borderOverlay != null && !_borderOverlay.IsDisposed)
            {
                NativeMethods.EnsureTopMost(_borderOverlay.Handle);
            }
            NativeMethods.EnsureTopMost(Handle);
        }

        protected override void OnMouseDown(MouseEventArgs e)
        {
            base.OnMouseDown(e);
            if (e.Button != MouseButtons.Left) return;

            Point pt = e.Location;

            if (_headerDragRect.Contains(pt))
            {
                _draggingPanel = true;
                _dragPanelStart = pt;
                return;
            }
            if (_btnAutoToggleRect.Contains(pt))
            {
                ToggleAutoScroll();
                return;
            }
            if (_btnCancelRect.Contains(pt))
            {
                CompleteWithAction(ScrollSessionExitAction.Cancelled);
                return;
            }
            if (_btnFinishRect.Contains(pt))
            {
                CompleteWithAction(ScrollSessionExitAction.OpenEditor);
                return;
            }
        }

        protected override void OnMouseMove(MouseEventArgs e)
        {
            base.OnMouseMove(e);
            _mousePos = e.Location;

            if (_draggingPanel)
            {
                Location = new Point(Left + e.X - _dragPanelStart.X, Top + e.Y - _dragPanelStart.Y);
                return;
            }

            bool overClickable = _btnAutoToggleRect.Contains(e.Location) ||
                                 _btnCancelRect.Contains(e.Location) ||
                                 _btnFinishRect.Contains(e.Location);

            Cursor = overClickable ? Cursors.Hand : (_headerDragRect.Contains(e.Location) ? Cursors.SizeAll : Cursors.Default);
            Invalidate();
        }

        protected override void OnMouseUp(MouseEventArgs e)
        {
            base.OnMouseUp(e);
            _draggingPanel = false;
        }

        protected override void OnKeyDown(KeyEventArgs e)
        {
            base.OnKeyDown(e);
            if (e.KeyCode == Keys.Enter || e.KeyCode == Keys.Space)
            {
                CompleteWithAction(ScrollSessionExitAction.OpenEditor);
            }
        }

        private void ToggleAutoScroll()
        {
            _autoScrolling = !_autoScrolling;
            _autoScrollTickCounter = 0;
            _noMoveAutoCount = 0;
            if (_autoScrolling)
            {
                int tx, ty;
                GetScrollTargetPoint(out tx, out ty);
                Point cur = Cursor.Position;
                if (!_captureRect.Contains(cur) || Bounds.Contains(cur))
                {
                    NativeMethods.SetCursorPos(tx, ty);
                }
                RefocusTargetWindow();
            }
            Invalidate();
        }

        private void OnCaptureTimerTick(object sender, EventArgs e)
        {
            if (_borderOverlay != null && !_borderOverlay.IsDisposed)
            {
                NativeMethods.EnsureTopMost(_borderOverlay.Handle);
            }
            NativeMethods.EnsureTopMost(Handle);

            bool escDown = (NativeMethods.GetAsyncKeyState(NativeMethods.VK_ESCAPE) & 0x8000) != 0;
            if (escDown && !_escWasDown)
            {
                _escWasDown = true;
                if (_autoScrolling)
                {
                    ToggleAutoScroll();
                    return;
                }
                else if (_engine.FrameCount > 1)
                {
                    CompleteWithAction(ScrollSessionExitAction.OpenEditor);
                    return;
                }
                else
                {
                    CompleteWithAction(ScrollSessionExitAction.Cancelled);
                    return;
                }
            }
            _escWasDown = escDown;

            if (_autoScrolling)
            {
                _autoScrollTickCounter++;
                if (_autoScrollTickCounter % AutoScrollTickModulo == 1)
                {
                    int targetX, targetY;
                    GetScrollTargetPoint(out targetX, out targetY);
                    Point curPos = Cursor.Position;
                    bool cursorInsideTarget = _captureRect.Contains(curPos) && !Bounds.Contains(curPos);
                    int scrollX = cursorInsideTarget ? curPos.X : targetX;
                    int scrollY = cursorInsideTarget ? curPos.Y : targetY;

                    if (!_draggingPanel)
                    {
                        if (_direction == ScrollDirection.Vertical)
                        {
                            NativeMethods.SendVerticalWheel(scrollX, scrollY, -AutoScrollWheelAmount, cursorInsideTarget);
                        }
                        else
                        {
                            NativeMethods.SendHorizontalScroll(scrollX, scrollY, AutoScrollWheelAmount, _horizMethod, cursorInsideTarget);
                        }
                    }
                    return;
                }
                if (_autoScrollTickCounter % AutoScrollTickModulo != 0)
                {
                    return;
                }
            }

            if (!_draggingPanel)
            {
                CaptureAndProcessFrame();
            }
        }

        private void CaptureAndProcessFrame()
        {
            try
            {
                using (Bitmap frame = ScreenCapturer.CaptureRegion(_captureRect))
                {
                    StitchResult res = _engine.PushFrame(frame);

                    if (res.Status == StitchStatus.FirstFrame || res.Status == StitchStatus.Stitched)
                    {
                        _noMoveAutoCount = 0;
                        int totalW = _direction == ScrollDirection.Vertical ? _engine.CrossDimension : res.TotalLength;
                        int totalH = _direction == ScrollDirection.Vertical ? res.TotalLength : _engine.CrossDimension;

                        _dimensionText = string.Format("{0} × {1}", totalW, totalH);
                        UpdateLivePreview();
                        Invalidate();
                    }
                    else if (res.Status == StitchStatus.MaxLengthReached)
                    {
                        if (_autoScrolling) ToggleAutoScroll();
                        Invalidate();
                    }
                    else if (res.Status == StitchStatus.NoMovement || res.Status == StitchStatus.LowConfidence)
                    {
                        if (_autoScrolling)
                        {
                            _noMoveAutoCount++;
                            if (_direction == ScrollDirection.Horizontal)
                            {
                                if (_noMoveAutoCount == 2 || _noMoveAutoCount == 4 || _noMoveAutoCount == 6)
                                {
                                    _horizMethod = (HorizontalScrollMethod)(((int)_horizMethod + 1) % 4);
                                }
                                else if (_noMoveAutoCount >= 10)
                                {
                                    _autoScrolling = false;
                                    Invalidate();
                                }
                            }
                            else if (_noMoveAutoCount >= 8)
                            {
                                _autoScrolling = false;
                                Invalidate();
                            }
                        }
                    }
                }
            }
            catch { }
        }

        private void UpdateLivePreview()
        {
            Bitmap thumb = _engine.RenderPreviewThumbnail(_previewCanvasRect.Width - 6, _previewCanvasRect.Height - 6);
            if (thumb != null)
            {
                Bitmap old = _latestPreviewBitmap;
                _latestPreviewBitmap = thumb;
                if (old != null) old.Dispose();
            }
        }

        private void CompleteWithAction(ScrollSessionExitAction action)
        {
            _captureTimer.Stop();
            _borderOverlay.Hide();
            ExitAction = action;
            if (action != ScrollSessionExitAction.Cancelled)
            {
                FinalStitchedBitmap = _engine.RenderStitchedBitmap();
                DialogResult = DialogResult.OK;
            }
            else
            {
                FinalStitchedBitmap = null;
                DialogResult = DialogResult.Cancel;
            }
            Close();
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            Graphics g = e.Graphics;
            g.SmoothingMode = SmoothingMode.AntiAlias;

            Rectangle cardRect = new Rectangle(0, 0, Width - 1, Height - 1);
            using (SolidBrush bg = new SolidBrush(UiTheme.ToolbarBg))
            using (Pen border = new Pen(UiTheme.WeChatGreen, Math.Max(1.5f, 1.5f * UiTheme.DpiScale)))
            {
                g.FillRectangle(bg, cardRect);
                g.DrawRectangle(border, cardRect);
            }

            int pad = UiTheme.S(8);
            string title = _direction == ScrollDirection.Vertical ? "纵向长截图" : "横向长截图";
            using (StringFormat sfLeft = new StringFormat { Alignment = StringAlignment.Near, LineAlignment = StringAlignment.Center })
            using (StringFormat sfRight = new StringFormat { Alignment = StringAlignment.Far, LineAlignment = StringAlignment.Center })
            using (SolidBrush subBrush = new SolidBrush(UiTheme.TextSecondary))
            {
                Rectangle headerInner = new Rectangle(pad, 0, Width - pad * 2, UiTheme.S(32));
                g.DrawString(title, _titleFont, Brushes.White, headerInner, sfLeft);
                g.DrawString(_dimensionText, _dimFont, subBrush, headerInner, sfRight);
            }

            using (SolidBrush canvasBg = new SolidBrush(Color.FromArgb(24, 24, 26)))
            using (Pen canvasBorder = new Pen(Color.FromArgb(62, 62, 66), 1f))
            {
                UiTheme.FillRoundedRect(g, canvasBg, _previewCanvasRect, UiTheme.S(4));
                UiTheme.DrawRoundedRect(g, canvasBorder, _previewCanvasRect, UiTheme.S(4));

                if (_latestPreviewBitmap != null)
                {
                    int px = _previewCanvasRect.X + (_previewCanvasRect.Width - _latestPreviewBitmap.Width) / 2;
                    int py = _previewCanvasRect.Y + (_previewCanvasRect.Height - _latestPreviewBitmap.Height) / 2;
                    g.DrawImageUnscaled(_latestPreviewBitmap, px, py);
                }
            }

            UiTheme.DrawPillButton(g, _btnAutoToggleRect,
                _autoScrolling ? "暂停" : "自动滚动",
                _autoScrolling ? UiTheme.AccentOrange : UiTheme.BgPill,
                _btnAutoToggleRect.Contains(_mousePos), false, 3, _btnFont,
                _autoScrolling ? Color.Black : Color.White);

            if (_btnCancelRect.Contains(_mousePos))
            {
                using (SolidBrush b = new SolidBrush(UiTheme.ToolbarHover))
                {
                    UiTheme.FillRoundedRect(g, b, _btnCancelRect, UiTheme.S(3));
                }
            }
            UiTheme.DrawIconClose(g, _btnCancelRect, _btnCancelRect.Contains(_mousePos) ? UiTheme.AccentRed : Color.FromArgb(220, 220, 220));

            UiTheme.DrawPillButton(g, _btnFinishRect, "完成",
                UiTheme.WeChatGreen, _btnFinishRect.Contains(_mousePos), false, 3, _btnFont, Color.White);
        }

        protected override void Dispose(bool disposing)
        {
            if (disposing)
            {
                if (_captureTimer != null) _captureTimer.Dispose();
                if (_borderOverlay != null) _borderOverlay.Dispose();
                if (_engine != null) _engine.Dispose();
                if (_latestPreviewBitmap != null) _latestPreviewBitmap.Dispose();
                if (_titleFont != null) _titleFont.Dispose();
                if (_dimFont != null) _dimFont.Dispose();
                if (_btnFont != null) _btnFont.Dispose();
            }
            base.Dispose(disposing);
        }
    }
}
