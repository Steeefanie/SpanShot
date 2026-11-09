using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.Windows.Forms;

namespace SpanShot
{
    public enum CaptureActionMode
    {
        None = 0,
        NormalCopyCompleted = 1,
        NormalPinCompleted = 2,
        NormalSaveCompleted = 3,
        VerticalScroll = 4,
        HorizontalScroll = 5
    }

    public sealed class RegionSelectorForm : Form
    {
        private enum ResizeHitZone
        {
            None = 0,
            Interior,
            TopLeft, Top, TopRight, Right, BottomRight, Bottom, BottomLeft, Left
        }

        private enum InlineAnnotateTool
        {
            None = 0,
            Rectangle = 1,
            Arrow = 2,
            Pen = 3
        }

        private sealed class AnnotationItem
        {
            public InlineAnnotateTool Tool;
            public Color Color;
            public int ThicknessIndex;
            public Point StartPt;
            public Point EndPt;
            public List<Point> PenPoints;
        }

        private readonly Bitmap _desktopSnapshot;
        private readonly Rectangle _virtualBounds;
        private readonly CaptureActionMode _presetMode;
        private readonly List<Rectangle> _detectedWindows;

        private Point _dragStart;
        private Rectangle _selectionRect;
        private Rectangle _hoverWindowRect;
        private Rectangle _resizeInitialRect;
        private ResizeHitZone _activeDragZone = ResizeHitZone.None;
        private bool _isSelecting;
        private bool _hasSelection;

        private InlineAnnotateTool _activeTool = InlineAnnotateTool.None;
        private int _selectedColorIndex = 0;      // Default Red (#FA5151)
        private int _selectedThicknessIndex = 1;  // 0=Thin, 1=Medium, 2=Thick
        private readonly List<AnnotationItem> _annotations = new List<AnnotationItem>();
        private AnnotationItem _currentDrawingItem;

        private Rectangle _toolbarBounds;
        private Rectangle _btnRectTool;
        private Rectangle _btnArrowTool;
        private Rectangle _btnPenTool;
        private Rectangle _btnVerticalScroll;
        private Rectangle _btnHorizontalScroll;
        private Rectangle _btnUndoTool;
        private Rectangle _btnPin;
        private Rectangle _btnSave;
        private Rectangle _btnCancel;
        private Rectangle _btnCopyFinish;

        // WeChat secondary sub-bar (thickness + color swatches)
        private Rectangle _subBarBounds;
        private readonly Rectangle[] _thicknessRects = new Rectangle[3];
        private readonly Rectangle[] _colorSwatchRects = new Rectangle[5];

        private Point _mousePos;
        private Font _toolbarFont;
        private Font _badgeFont;
        private Font _tooltipFont;

        public Rectangle SelectedPhysicalRect
        {
            get
            {
                return new Rectangle(
                    _selectionRect.X + _virtualBounds.X,
                    _selectionRect.Y + _virtualBounds.Y,
                    _selectionRect.Width,
                    _selectionRect.Height);
            }
        }

        public CaptureActionMode ChosenAction { get; private set; }
        public Bitmap AnnotatedRegionBitmap { get; private set; }

        public RegionSelectorForm(CaptureActionMode presetMode = CaptureActionMode.None, IntPtr ignoreHwnd = default(IntPtr))
        {
            _presetMode = presetMode;
            _virtualBounds = SystemInformation.VirtualScreen;
            _detectedWindows = NativeMethods.GetVisibleWindowRectangles(ignoreHwnd);
            _desktopSnapshot = ScreenCapturer.CaptureRegion(_virtualBounds);

            _toolbarFont = UiTheme.FontPx(13, false);
            _badgeFont = UiTheme.FontPx(12, false);
            _tooltipFont = UiTheme.FontPx(12, false);

            FormBorderStyle = FormBorderStyle.None;
            StartPosition = FormStartPosition.Manual;
            Bounds = _virtualBounds;
            TopMost = true;
            DoubleBuffered = true;
            ShowInTaskbar = false;
            KeyPreview = true;
            Cursor = Cursors.Cross;

            SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.UserPaint | ControlStyles.OptimizedDoubleBuffer, true);
        }

        protected override void OnShown(EventArgs e)
        {
            base.OnShown(e);
            NativeMethods.EnsureTopMost(Handle);
            Activate();
            _mousePos = PointToClient(Cursor.Position);
            _hoverWindowRect = FindHoveredWindowRect(_mousePos);
            Invalidate();
        }

        protected override void OnKeyDown(KeyEventArgs e)
        {
            base.OnKeyDown(e);
            if (e.KeyCode == Keys.Escape)
            {
                if (_hasSelection)
                {
                    _hasSelection = false;
                    _selectionRect = Rectangle.Empty;
                    _activeTool = InlineAnnotateTool.None;
                    _annotations.Clear();
                    _activeDragZone = ResizeHitZone.None;
                    Invalidate();
                }
                else
                {
                    ChosenAction = CaptureActionMode.None;
                    DialogResult = DialogResult.Cancel;
                    Close();
                }
                return;
            }

            if (_hasSelection && _selectionRect.Width >= 20 && _selectionRect.Height >= 20)
            {
                if (e.Control && e.KeyCode == Keys.Z)
                {
                    if (_annotations.Count > 0)
                    {
                        _annotations.RemoveAt(_annotations.Count - 1);
                        Invalidate();
                    }
                }
                else if (e.KeyCode == Keys.Enter || e.KeyCode == Keys.Space || (e.Control && e.KeyCode == Keys.C))
                {
                    FinishNormalWithAction(CaptureActionMode.NormalCopyCompleted);
                }
                else if (e.KeyCode == Keys.V)
                {
                    ConfirmScrollAction(CaptureActionMode.VerticalScroll);
                }
                else if (e.KeyCode == Keys.H)
                {
                    ConfirmScrollAction(CaptureActionMode.HorizontalScroll);
                }
                else if (e.KeyCode == Keys.P)
                {
                    FinishNormalWithAction(CaptureActionMode.NormalPinCompleted);
                }
                else if (e.Control && e.KeyCode == Keys.S)
                {
                    FinishNormalWithAction(CaptureActionMode.NormalSaveCompleted);
                }
                else if (_activeTool == InlineAnnotateTool.None &&
                         (e.KeyCode == Keys.Up || e.KeyCode == Keys.Down || e.KeyCode == Keys.Left || e.KeyCode == Keys.Right))
                {
                    int dx = e.KeyCode == Keys.Left ? -1 : (e.KeyCode == Keys.Right ? 1 : 0);
                    int dy = e.KeyCode == Keys.Up ? -1 : (e.KeyCode == Keys.Down ? 1 : 0);
                    if (e.Shift)
                    {
                        _selectionRect.Width = Math.Max(24, Math.Min(Width - _selectionRect.X, _selectionRect.Width + dx));
                        _selectionRect.Height = Math.Max(24, Math.Min(Height - _selectionRect.Y, _selectionRect.Height + dy));
                    }
                    else
                    {
                        _selectionRect.X = Math.Max(0, Math.Min(Width - _selectionRect.Width, _selectionRect.X + dx));
                        _selectionRect.Y = Math.Max(0, Math.Min(Height - _selectionRect.Height, _selectionRect.Y + dy));
                    }
                    UpdateToolbarLayout();
                    Invalidate();
                }
            }
        }

        private void ConfirmScrollAction(CaptureActionMode scrollMode)
        {
            ChosenAction = scrollMode;
            DialogResult = DialogResult.OK;
            Close();
        }

        private void FinishNormalWithAction(CaptureActionMode mode)
        {
            AnnotatedRegionBitmap = RenderSelectedRegionWithAnnotations();
            ChosenAction = mode;
            DialogResult = DialogResult.OK;
            Close();
        }

        private Bitmap RenderSelectedRegionWithAnnotations()
        {
            Bitmap bmp = new Bitmap(_selectionRect.Width, _selectionRect.Height, PixelFormat.Format32bppArgb);
            using (Graphics g = Graphics.FromImage(bmp))
            {
                g.SmoothingMode = SmoothingMode.AntiAlias;
                g.DrawImage(_desktopSnapshot,
                    new Rectangle(0, 0, _selectionRect.Width, _selectionRect.Height),
                    _selectionRect,
                    GraphicsUnit.Pixel);

                g.TranslateTransform(-_selectionRect.X, -_selectionRect.Y);
                for (int i = 0; i < _annotations.Count; i++)
                {
                    DrawSingleAnnotation(g, _annotations[i]);
                }
            }
            return bmp;
        }

        private Rectangle FindHoveredWindowRect(Point localPt)
        {
            Point screenPt = new Point(localPt.X + _virtualBounds.X, localPt.Y + _virtualBounds.Y);
            for (int i = 0; i < _detectedWindows.Count; i++)
            {
                Rectangle wr = _detectedWindows[i];
                if (wr.Contains(screenPt))
                {
                    Rectangle localRect = new Rectangle(
                        wr.X - _virtualBounds.X,
                        wr.Y - _virtualBounds.Y,
                        wr.Width,
                        wr.Height);
                    localRect.Intersect(new Rectangle(0, 0, Width, Height));
                    if (localRect.Width >= 50 && localRect.Height >= 50)
                    {
                        return localRect;
                    }
                }
            }
            return Rectangle.Empty;
        }

        private ResizeHitZone HitTestSelection(Point pt)
        {
            if (!_hasSelection || _selectionRect.Width <= 0 || _selectionRect.Height <= 0)
                return ResizeHitZone.None;

            int tol = UiTheme.S(7);
            Rectangle r = _selectionRect;

            bool nearLeft = Math.Abs(pt.X - r.Left) <= tol && pt.Y >= r.Top - tol && pt.Y <= r.Bottom + tol;
            bool nearRight = Math.Abs(pt.X - r.Right) <= tol && pt.Y >= r.Top - tol && pt.Y <= r.Bottom + tol;
            bool nearTop = Math.Abs(pt.Y - r.Top) <= tol && pt.X >= r.Left - tol && pt.X <= r.Right + tol;
            bool nearBottom = Math.Abs(pt.Y - r.Bottom) <= tol && pt.X >= r.Left - tol && pt.X <= r.Right + tol;

            if (nearLeft && nearTop) return ResizeHitZone.TopLeft;
            if (nearRight && nearTop) return ResizeHitZone.TopRight;
            if (nearRight && nearBottom) return ResizeHitZone.BottomRight;
            if (nearLeft && nearBottom) return ResizeHitZone.BottomLeft;
            if (nearTop) return ResizeHitZone.Top;
            if (nearBottom) return ResizeHitZone.Bottom;
            if (nearLeft) return ResizeHitZone.Left;
            if (nearRight) return ResizeHitZone.Right;

            if (r.Contains(pt)) return ResizeHitZone.Interior;
            return ResizeHitZone.None;
        }

        private Cursor GetCursorForHitZone(ResizeHitZone zone)
        {
            switch (zone)
            {
                case ResizeHitZone.TopLeft:
                case ResizeHitZone.BottomRight:
                    return Cursors.SizeNWSE;
                case ResizeHitZone.TopRight:
                case ResizeHitZone.BottomLeft:
                    return Cursors.SizeNESW;
                case ResizeHitZone.Top:
                case ResizeHitZone.Bottom:
                    return Cursors.SizeNS;
                case ResizeHitZone.Left:
                case ResizeHitZone.Right:
                    return Cursors.SizeWE;
                case ResizeHitZone.Interior:
                    return _activeTool != InlineAnnotateTool.None ? Cursors.Cross : Cursors.SizeAll;
                default:
                    return Cursors.Cross;
            }
        }

        protected override void OnMouseDoubleClick(MouseEventArgs e)
        {
            base.OnMouseDoubleClick(e);
            if (e.Button == MouseButtons.Left && _hasSelection && _selectionRect.Contains(e.Location))
            {
                FinishNormalWithAction(CaptureActionMode.NormalCopyCompleted);
            }
        }

        protected override void OnMouseDown(MouseEventArgs e)
        {
            base.OnMouseDown(e);

            if (e.Button == MouseButtons.Right)
            {
                if (_hasSelection)
                {
                    _hasSelection = false;
                    _selectionRect = Rectangle.Empty;
                    _activeTool = InlineAnnotateTool.None;
                    _annotations.Clear();
                    _activeDragZone = ResizeHitZone.None;
                    Cursor = Cursors.Cross;
                    _hoverWindowRect = FindHoveredWindowRect(e.Location);
                    Invalidate();
                }
                else
                {
                    ChosenAction = CaptureActionMode.None;
                    DialogResult = DialogResult.Cancel;
                    Close();
                }
                return;
            }

            if (e.Button != MouseButtons.Left) return;

            if (_hasSelection)
            {
                // Sub-bar clicks (when annotation tool is active)
                if (_activeTool != InlineAnnotateTool.None && _subBarBounds.Contains(e.Location))
                {
                    for (int i = 0; i < 3; i++)
                    {
                        if (_thicknessRects[i].Contains(e.Location))
                        {
                            _selectedThicknessIndex = i;
                            Invalidate();
                            return;
                        }
                    }
                    for (int i = 0; i < _colorSwatchRects.Length; i++)
                    {
                        if (_colorSwatchRects[i].Contains(e.Location))
                        {
                            _selectedColorIndex = i;
                            Invalidate();
                            return;
                        }
                    }
                    return;
                }

                if (_btnRectTool.Contains(e.Location))
                {
                    _activeTool = _activeTool == InlineAnnotateTool.Rectangle ? InlineAnnotateTool.None : InlineAnnotateTool.Rectangle;
                    UpdateToolbarLayout();
                    Invalidate();
                    return;
                }
                if (_btnArrowTool.Contains(e.Location))
                {
                    _activeTool = _activeTool == InlineAnnotateTool.Arrow ? InlineAnnotateTool.None : InlineAnnotateTool.Arrow;
                    UpdateToolbarLayout();
                    Invalidate();
                    return;
                }
                if (_btnPenTool.Contains(e.Location))
                {
                    _activeTool = _activeTool == InlineAnnotateTool.Pen ? InlineAnnotateTool.None : InlineAnnotateTool.Pen;
                    UpdateToolbarLayout();
                    Invalidate();
                    return;
                }
                if (_btnVerticalScroll.Contains(e.Location))
                {
                    ConfirmScrollAction(CaptureActionMode.VerticalScroll);
                    return;
                }
                if (_btnHorizontalScroll.Contains(e.Location))
                {
                    ConfirmScrollAction(CaptureActionMode.HorizontalScroll);
                    return;
                }
                if (_btnUndoTool.Contains(e.Location))
                {
                    if (_annotations.Count > 0) _annotations.RemoveAt(_annotations.Count - 1);
                    Invalidate();
                    return;
                }
                if (_btnPin.Contains(e.Location))
                {
                    FinishNormalWithAction(CaptureActionMode.NormalPinCompleted);
                    return;
                }
                if (_btnSave.Contains(e.Location))
                {
                    FinishNormalWithAction(CaptureActionMode.NormalSaveCompleted);
                    return;
                }
                if (_btnCancel.Contains(e.Location))
                {
                    ChosenAction = CaptureActionMode.None;
                    DialogResult = DialogResult.Cancel;
                    Close();
                    return;
                }
                if (_btnCopyFinish.Contains(e.Location))
                {
                    FinishNormalWithAction(CaptureActionMode.NormalCopyCompleted);
                    return;
                }

                if (_activeTool != InlineAnnotateTool.None && _selectionRect.Contains(e.Location))
                {
                    _currentDrawingItem = new AnnotationItem
                    {
                        Tool = _activeTool,
                        Color = UiTheme.AnnotColors[_selectedColorIndex],
                        ThicknessIndex = _selectedThicknessIndex,
                        StartPt = e.Location,
                        EndPt = e.Location,
                        PenPoints = _activeTool == InlineAnnotateTool.Pen ? new List<Point> { e.Location } : null
                    };
                    return;
                }

                ResizeHitZone hit = HitTestSelection(e.Location);
                if (hit != ResizeHitZone.None && _annotations.Count == 0)
                {
                    _activeDragZone = hit;
                    _dragStart = e.Location;
                    _resizeInitialRect = _selectionRect;
                    return;
                }
                if (_selectionRect.Contains(e.Location))
                {
                    return;
                }
            }

            _isSelecting = true;
            _hasSelection = false;
            _activeTool = InlineAnnotateTool.None;
            _annotations.Clear();
            _activeDragZone = ResizeHitZone.None;
            _dragStart = e.Location;
            _selectionRect = new Rectangle(e.Location, Size.Empty);
            Invalidate();
        }

        protected override void OnMouseMove(MouseEventArgs e)
        {
            base.OnMouseMove(e);
            _mousePos = e.Location;

            if (_currentDrawingItem != null)
            {
                int cx = Math.Max(_selectionRect.Left, Math.Min(_selectionRect.Right, e.X));
                int cy = Math.Max(_selectionRect.Top, Math.Min(_selectionRect.Bottom, e.Y));
                Point clamped = new Point(cx, cy);
                _currentDrawingItem.EndPt = clamped;
                if (_currentDrawingItem.Tool == InlineAnnotateTool.Pen && _currentDrawingItem.PenPoints != null)
                {
                    List<Point> pts = _currentDrawingItem.PenPoints;
                    if (pts.Count == 0 || Math.Abs(pts[pts.Count - 1].X - clamped.X) + Math.Abs(pts[pts.Count - 1].Y - clamped.Y) >= 2)
                    {
                        pts.Add(clamped);
                    }
                }
                Invalidate();
            }
            else if (_isSelecting)
            {
                int x = Math.Min(_dragStart.X, e.X);
                int y = Math.Min(_dragStart.Y, e.Y);
                int w = Math.Abs(e.X - _dragStart.X);
                int h = Math.Abs(e.Y - _dragStart.Y);
                _selectionRect = new Rectangle(x, y, w, h);
                Invalidate();
            }
            else if (_activeDragZone != ResizeHitZone.None)
            {
                ApplyResizeOrMove(e.Location);
                UpdateToolbarLayout();
                Invalidate();
            }
            else if (_hasSelection)
            {
                if (_toolbarBounds.Contains(e.Location) || (_activeTool != InlineAnnotateTool.None && _subBarBounds.Contains(e.Location)))
                {
                    Cursor = Cursors.Hand;
                }
                else
                {
                    Cursor = GetCursorForHitZone(HitTestSelection(e.Location));
                }
                Invalidate();
            }
            else
            {
                _hoverWindowRect = FindHoveredWindowRect(e.Location);
                Invalidate();
            }
        }

        private void ApplyResizeOrMove(Point pt)
        {
            int dx = pt.X - _dragStart.X;
            int dy = pt.Y - _dragStart.Y;
            Rectangle r = _resizeInitialRect;

            if (_activeDragZone == ResizeHitZone.Interior)
            {
                int nx = Math.Max(0, Math.Min(Width - r.Width, r.X + dx));
                int ny = Math.Max(0, Math.Min(Height - r.Height, r.Y + dy));
                _selectionRect = new Rectangle(nx, ny, r.Width, r.Height);
                return;
            }

            int left = r.Left;
            int top = r.Top;
            int right = r.Right;
            int bottom = r.Bottom;

            if (_activeDragZone == ResizeHitZone.TopLeft || _activeDragZone == ResizeHitZone.Left || _activeDragZone == ResizeHitZone.BottomLeft)
                left = Math.Max(0, Math.Min(right - 30, left + dx));

            if (_activeDragZone == ResizeHitZone.TopRight || _activeDragZone == ResizeHitZone.Right || _activeDragZone == ResizeHitZone.BottomRight)
                right = Math.Min(Width, Math.Max(left + 30, right + dx));

            if (_activeDragZone == ResizeHitZone.TopLeft || _activeDragZone == ResizeHitZone.Top || _activeDragZone == ResizeHitZone.TopRight)
                top = Math.Max(0, Math.Min(bottom - 30, top + dy));

            if (_activeDragZone == ResizeHitZone.BottomLeft || _activeDragZone == ResizeHitZone.Bottom || _activeDragZone == ResizeHitZone.BottomRight)
                bottom = Math.Min(Height, Math.Max(top + 30, bottom + dy));

            _selectionRect = Rectangle.FromLTRB(left, top, right, bottom);
        }

        protected override void OnMouseUp(MouseEventArgs e)
        {
            base.OnMouseUp(e);
            if (e.Button != MouseButtons.Left) return;

            if (_currentDrawingItem != null)
            {
                AnnotationItem item = _currentDrawingItem;
                _currentDrawingItem = null;
                bool valid = item.Tool == InlineAnnotateTool.Pen
                    ? (item.PenPoints != null && item.PenPoints.Count >= 2)
                    : (Math.Abs(item.EndPt.X - item.StartPt.X) > 3 || Math.Abs(item.EndPt.Y - item.StartPt.Y) > 3);
                if (valid)
                {
                    _annotations.Add(item);
                }
                Invalidate();
                return;
            }

            if (_isSelecting)
            {
                _isSelecting = false;
                if (_selectionRect.Width >= 30 && _selectionRect.Height >= 30)
                {
                    _hasSelection = true;
                }
                else if (_hoverWindowRect.Width >= 50 && _hoverWindowRect.Height >= 50)
                {
                    _selectionRect = _hoverWindowRect;
                    _hasSelection = true;
                }

                if (_hasSelection)
                {
                    if (_presetMode == CaptureActionMode.VerticalScroll || _presetMode == CaptureActionMode.HorizontalScroll)
                    {
                        ConfirmScrollAction(_presetMode);
                        return;
                    }
                    UpdateToolbarLayout();
                }
                else
                {
                    _selectionRect = Rectangle.Empty;
                }
                Invalidate();
            }
            else if (_activeDragZone != ResizeHitZone.None)
            {
                _activeDragZone = ResizeHitZone.None;
                UpdateToolbarLayout();
                Invalidate();
            }
        }

        private void UpdateToolbarLayout()
        {
            int barH = UiTheme.S(38);
            int pad = UiTheme.S(5);
            int btnH = barH - pad * 2;
            int iconW = UiTheme.S(32);
            int scrollW = UiTheme.S(76);
            int finishW = UiTheme.S(38);
            int gap = UiTheme.S(2);
            int divGap = UiTheme.S(11);

            int barWidth = pad * 2
                         + iconW * 3 + gap * 2 + divGap
                         + scrollW * 2 + gap + divGap
                         + iconW * 4 + finishW + gap * 4;

            int x = _selectionRect.Right - barWidth;
            if (x < 8) x = _selectionRect.Left;
            if (x + barWidth > Width - 8) x = Math.Max(8, Width - barWidth - 8);

            int totalNeededH = barH + (_activeTool != InlineAnnotateTool.None ? UiTheme.S(42) : 0);
            int y = _selectionRect.Bottom + UiTheme.S(6);
            bool placedAbove = false;
            if (y + totalNeededH > Height - 8)
            {
                y = _selectionRect.Top - barH - UiTheme.S(6);
                placedAbove = true;
                if (y < 8)
                {
                    y = _selectionRect.Bottom - barH - UiTheme.S(6);
                    placedAbove = false;
                }
            }

            _toolbarBounds = new Rectangle(x, y, barWidth, barH);

            int curX = x + pad;
            int btnY = y + pad;

            _btnRectTool = new Rectangle(curX, btnY, iconW, btnH); curX += iconW + gap;
            _btnArrowTool = new Rectangle(curX, btnY, iconW, btnH); curX += iconW + gap;
            _btnPenTool = new Rectangle(curX, btnY, iconW, btnH); curX += iconW + divGap;

            _btnVerticalScroll = new Rectangle(curX, btnY, scrollW, btnH); curX += scrollW + gap;
            _btnHorizontalScroll = new Rectangle(curX, btnY, scrollW, btnH); curX += scrollW + divGap;

            _btnUndoTool = new Rectangle(curX, btnY, iconW, btnH); curX += iconW + gap;
            _btnPin = new Rectangle(curX, btnY, iconW, btnH); curX += iconW + gap;
            _btnSave = new Rectangle(curX, btnY, iconW, btnH); curX += iconW + gap;
            _btnCancel = new Rectangle(curX, btnY, iconW, btnH); curX += iconW + gap;
            _btnCopyFinish = new Rectangle(curX, btnY, finishW, btnH);

            // Secondary Sub-bar for thickness & color swatches (WeChat style)
            int subW = UiTheme.S(232);
            int subH = UiTheme.S(34);
            int subX = _toolbarBounds.Left;
            int subY = placedAbove
                ? (_toolbarBounds.Top - subH - UiTheme.S(5))
                : (_toolbarBounds.Bottom + UiTheme.S(5));
            if (subY < 6) subY = _toolbarBounds.Bottom + UiTheme.S(5);

            _subBarBounds = new Rectangle(subX, subY, subW, subH);

            int sx = subX + UiTheme.S(8);
            int sy = subY + (subH - UiTheme.S(24)) / 2;
            for (int i = 0; i < 3; i++)
            {
                _thicknessRects[i] = new Rectangle(sx, sy, UiTheme.S(24), UiTheme.S(24));
                sx += UiTheme.S(26);
            }
            sx += UiTheme.S(10);
            for (int i = 0; i < _colorSwatchRects.Length; i++)
            {
                _colorSwatchRects[i] = new Rectangle(sx, sy + UiTheme.S(2), UiTheme.S(20), UiTheme.S(20));
                sx += UiTheme.S(26);
            }
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            Graphics g = e.Graphics;
            g.SmoothingMode = SmoothingMode.AntiAlias;

            g.DrawImageUnscaled(_desktopSnapshot, 0, 0);

            if (_selectionRect.Width > 0 && _selectionRect.Height > 0)
            {
                using (SolidBrush dimBrush = new SolidBrush(Color.FromArgb(120, 0, 0, 0)))
                using (Region dimRegion = new Region(new Rectangle(0, 0, Width, Height)))
                {
                    dimRegion.Exclude(_selectionRect);
                    g.FillRegion(dimBrush, dimRegion);
                }
            }
            else
            {
                using (SolidBrush dimBrush = new SolidBrush(Color.FromArgb(120, 0, 0, 0)))
                {
                    if (_hoverWindowRect.Width > 0 && _hoverWindowRect.Height > 0)
                    {
                        using (Region dimRegion = new Region(new Rectangle(0, 0, Width, Height)))
                        {
                            dimRegion.Exclude(_hoverWindowRect);
                            g.FillRegion(dimBrush, dimRegion);
                        }
                        using (SolidBrush hoverTint = new SolidBrush(Color.FromArgb(38, 0, 0, 0)))
                        {
                            g.FillRectangle(hoverTint, _hoverWindowRect);
                        }
                    }
                    else
                    {
                        g.FillRectangle(dimBrush, 0, 0, Width, Height);
                    }
                }
            }

            // Window hover frame (Apple UI Blue #007AFF)
            if (!_hasSelection && !_isSelecting && _hoverWindowRect.Width > 8 && _hoverWindowRect.Height > 8)
            {
                Rectangle insetHover = new Rectangle(
                    _hoverWindowRect.X + 2,
                    _hoverWindowRect.Y + 2,
                    _hoverWindowRect.Width - 4,
                    _hoverWindowRect.Height - 4);
                using (Pen hoverPen = new Pen(UiTheme.WeChatGreen, Math.Max(3f, UiTheme.S(3))))
                {
                    g.DrawRectangle(hoverPen, insetHover);
                }
            }

            if (!_hasSelection && !_isSelecting)
            {
                string prompt = _presetMode == CaptureActionMode.VerticalScroll
                    ? "纵向长截图 · 请拖动框选区域或点击窗口 (Esc 退出)"
                    : (_presetMode == CaptureActionMode.HorizontalScroll
                        ? "横向长截图 · 请拖动框选区域或点击窗口 (Esc 退出)"
                        : "请拖动框选区域或点击窗口 (Esc 退出)");
                SizeF psz = g.MeasureString(prompt, _toolbarFont);
                int pw = (int)psz.Width + UiTheme.S(28);
                int ph = UiTheme.S(34);
                Rectangle primary = Screen.PrimaryScreen.Bounds;
                int px = (primary.Left - _virtualBounds.Left) + (primary.Width - pw) / 2;
                int py = (primary.Top - _virtualBounds.Top) + UiTheme.S(24);
                Rectangle promptRect = new Rectangle(px, py, pw, ph);
                using (SolidBrush pbg = new SolidBrush(UiTheme.ToolbarBg))
                using (Pen pborder = new Pen(UiTheme.WeChatGreen, 1.5f))
                using (StringFormat psf = new StringFormat { Alignment = StringAlignment.Center, LineAlignment = StringAlignment.Center })
                {
                    UiTheme.FillRoundedRect(g, pbg, promptRect, UiTheme.S(6));
                    UiTheme.DrawRoundedRect(g, pborder, promptRect, UiTheme.S(6));
                    g.DrawString(prompt, _toolbarFont, Brushes.White, promptRect, psf);
                }
            }

            if (_selectionRect.Width > 0 && _selectionRect.Height > 0)
            {
                Region oldClip = g.Clip;
                g.SetClip(_selectionRect);
                for (int i = 0; i < _annotations.Count; i++)
                {
                    DrawSingleAnnotation(g, _annotations[i]);
                }
                if (_currentDrawingItem != null)
                {
                    DrawSingleAnnotation(g, _currentDrawingItem);
                }
                g.Clip = oldClip;

                using (Pen borderPen = new Pen(UiTheme.WeChatGreen, Math.Max(1.5f, 1.5f * UiTheme.DpiScale)))
                {
                    g.DrawRectangle(borderPen, _selectionRect);
                }

                if (_annotations.Count == 0 && _activeTool == InlineAnnotateTool.None)
                {
                    int midX = _selectionRect.Left + _selectionRect.Width / 2;
                    int midY = _selectionRect.Top + _selectionRect.Height / 2;
                    DrawWeChatSquareHandle(g, _selectionRect.Left, _selectionRect.Top);
                    DrawWeChatSquareHandle(g, midX, _selectionRect.Top);
                    DrawWeChatSquareHandle(g, _selectionRect.Right, _selectionRect.Top);
                    DrawWeChatSquareHandle(g, _selectionRect.Right, midY);
                    DrawWeChatSquareHandle(g, _selectionRect.Right, _selectionRect.Bottom);
                    DrawWeChatSquareHandle(g, midX, _selectionRect.Bottom);
                    DrawWeChatSquareHandle(g, _selectionRect.Left, _selectionRect.Bottom);
                    DrawWeChatSquareHandle(g, _selectionRect.Left, midY);
                }

                // WeChat-style top-left W x H tag
                string sizeText = string.Format("{0} × {1}", _selectionRect.Width, _selectionRect.Height);
                SizeF textSize = g.MeasureString(sizeText, _badgeFont);
                int bw = (int)textSize.Width + UiTheme.S(12);
                int bh = (int)textSize.Height + UiTheme.S(6);
                int bx = _selectionRect.Left;
                int by = _selectionRect.Top - bh - UiTheme.S(4);
                if (by < 6) by = _selectionRect.Top + UiTheme.S(4);

                Rectangle badgeRect = new Rectangle(bx, by, bw, bh);
                using (SolidBrush badgeBg = new SolidBrush(Color.FromArgb(220, 36, 36, 36)))
                using (StringFormat sf = new StringFormat { Alignment = StringAlignment.Center, LineAlignment = StringAlignment.Center })
                {
                    UiTheme.FillRoundedRect(g, badgeBg, badgeRect, UiTheme.S(3));
                    g.DrawString(sizeText, _badgeFont, Brushes.White, badgeRect, sf);
                }
            }

            if (_hasSelection && !_isSelecting && _activeDragZone == ResizeHitZone.None)
            {
                DrawWeChatToolbar(g);
                if (_activeTool != InlineAnnotateTool.None)
                {
                    DrawWeChatSubBar(g);
                }
            }
        }

        private void DrawWeChatToolbar(Graphics g)
        {
            using (SolidBrush bgBrush = new SolidBrush(UiTheme.ToolbarBg))
            using (Pen borderPen = new Pen(UiTheme.ToolbarBorder, 1f))
            using (Pen divPen = new Pen(UiTheme.DividerColor, 1f))
            {
                UiTheme.FillRoundedRect(g, bgBrush, _toolbarBounds, UiTheme.S(4));
                UiTheme.DrawRoundedRect(g, borderPen, _toolbarBounds, UiTheme.S(4));

                // Annotation icon buttons
                DrawIconBtnBg(g, _btnRectTool, _activeTool == InlineAnnotateTool.Rectangle, _btnRectTool.Contains(_mousePos));
                UiTheme.DrawIconRect(g, _btnRectTool, _activeTool == InlineAnnotateTool.Rectangle ? UiTheme.WeChatGreen : Color.White);

                DrawIconBtnBg(g, _btnArrowTool, _activeTool == InlineAnnotateTool.Arrow, _btnArrowTool.Contains(_mousePos));
                UiTheme.DrawIconArrow(g, _btnArrowTool, _activeTool == InlineAnnotateTool.Arrow ? UiTheme.WeChatGreen : Color.White);

                DrawIconBtnBg(g, _btnPenTool, _activeTool == InlineAnnotateTool.Pen, _btnPenTool.Contains(_mousePos));
                UiTheme.DrawIconPen(g, _btnPenTool, _activeTool == InlineAnnotateTool.Pen ? UiTheme.WeChatGreen : Color.White);

                int div1X = _btnPenTool.Right + UiTheme.S(5);
                g.DrawLine(divPen, div1X, _toolbarBounds.Top + UiTheme.S(9), div1X, _toolbarBounds.Bottom - UiTheme.S(9));

                // Long Screenshot buttons (Vertical & Horizontal)
                UiTheme.DrawPillButton(g, _btnVerticalScroll, "纵向长截",
                    _btnVerticalScroll.Contains(_mousePos) ? UiTheme.ToolbarHover : Color.Transparent,
                    false, false, 3, _toolbarFont, Color.White);

                UiTheme.DrawPillButton(g, _btnHorizontalScroll, "横向长截",
                    _btnHorizontalScroll.Contains(_mousePos) ? UiTheme.ToolbarHover : Color.Transparent,
                    false, false, 3, _toolbarFont, Color.White);

                int div2X = _btnHorizontalScroll.Right + UiTheme.S(5);
                g.DrawLine(divPen, div2X, _toolbarBounds.Top + UiTheme.S(9), div2X, _toolbarBounds.Bottom - UiTheme.S(9));

                // Undo, Pin, Save, Cancel, Check
                bool canUndo = _annotations.Count > 0;
                DrawIconBtnBg(g, _btnUndoTool, false, canUndo && _btnUndoTool.Contains(_mousePos));
                UiTheme.DrawIconUndo(g, _btnUndoTool, canUndo ? Color.White : Color.FromArgb(110, 110, 110));

                DrawIconBtnBg(g, _btnPin, false, _btnPin.Contains(_mousePos));
                UiTheme.DrawIconPin(g, _btnPin, Color.White);

                DrawIconBtnBg(g, _btnSave, false, _btnSave.Contains(_mousePos));
                UiTheme.DrawIconSave(g, _btnSave, Color.White);

                DrawIconBtnBg(g, _btnCancel, false, _btnCancel.Contains(_mousePos));
                UiTheme.DrawIconClose(g, _btnCancel, _btnCancel.Contains(_mousePos) ? UiTheme.AccentRed : Color.FromArgb(220, 220, 220));

                DrawIconBtnBg(g, _btnCopyFinish, false, _btnCopyFinish.Contains(_mousePos));
                UiTheme.DrawIconCheck(g, _btnCopyFinish, UiTheme.WeChatGreen);
            }

            // Draw hover tooltip for icon buttons
            string tip = null;
            Rectangle tipTarget = Rectangle.Empty;
            if (_btnRectTool.Contains(_mousePos)) { tip = "矩形"; tipTarget = _btnRectTool; }
            else if (_btnArrowTool.Contains(_mousePos)) { tip = "箭头"; tipTarget = _btnArrowTool; }
            else if (_btnPenTool.Contains(_mousePos)) { tip = "画笔"; tipTarget = _btnPenTool; }
            else if (_btnUndoTool.Contains(_mousePos)) { tip = "撤销"; tipTarget = _btnUndoTool; }
            else if (_btnPin.Contains(_mousePos)) { tip = "贴图"; tipTarget = _btnPin; }
            else if (_btnSave.Contains(_mousePos)) { tip = "保存"; tipTarget = _btnSave; }
            else if (_btnCancel.Contains(_mousePos)) { tip = "退出"; tipTarget = _btnCancel; }
            else if (_btnCopyFinish.Contains(_mousePos)) { tip = "完成"; tipTarget = _btnCopyFinish; }

            if (tip != null)
            {
                SizeF tsz = g.MeasureString(tip, _tooltipFont);
                int tw = (int)tsz.Width + UiTheme.S(12);
                int th = UiTheme.S(24);
                int tx = tipTarget.Left + (tipTarget.Width - tw) / 2;
                int ty = _toolbarBounds.Top - th - UiTheme.S(4);
                if (ty < 4) ty = _toolbarBounds.Bottom + UiTheme.S(4);
                Rectangle tipRect = new Rectangle(tx, ty, tw, th);
                using (SolidBrush tb = new SolidBrush(Color.FromArgb(235, 32, 32, 32)))
                using (StringFormat sf = new StringFormat { Alignment = StringAlignment.Center, LineAlignment = StringAlignment.Center })
                {
                    UiTheme.FillRoundedRect(g, tb, tipRect, UiTheme.S(3));
                    g.DrawString(tip, _tooltipFont, Brushes.White, tipRect, sf);
                }
            }
        }

        private void DrawWeChatSubBar(Graphics g)
        {
            using (SolidBrush bgBrush = new SolidBrush(UiTheme.ToolbarBg))
            using (Pen borderPen = new Pen(UiTheme.ToolbarBorder, 1f))
            using (Pen divPen = new Pen(UiTheme.DividerColor, 1f))
            {
                UiTheme.FillRoundedRect(g, bgBrush, _subBarBounds, UiTheme.S(4));
                UiTheme.DrawRoundedRect(g, borderPen, _subBarBounds, UiTheme.S(4));

                int[] dotRadii = new int[] { UiTheme.S(4), UiTheme.S(7), UiTheme.S(10) };
                for (int i = 0; i < 3; i++)
                {
                    Rectangle r = _thicknessRects[i];
                    int d = dotRadii[i];
                    Color c = (_selectedThicknessIndex == i) ? UiTheme.WeChatGreen : Color.FromArgb(165, 165, 165);
                    using (SolidBrush b = new SolidBrush(c))
                    {
                        g.FillEllipse(b, r.X + (r.Width - d) / 2, r.Y + (r.Height - d) / 2, d, d);
                    }
                }

                int divX = _thicknessRects[2].Right + UiTheme.S(6);
                g.DrawLine(divPen, divX, _subBarBounds.Top + UiTheme.S(8), divX, _subBarBounds.Bottom - UiTheme.S(8));

                for (int i = 0; i < _colorSwatchRects.Length; i++)
                {
                    Rectangle sr = _colorSwatchRects[i];
                    using (SolidBrush sb = new SolidBrush(UiTheme.AnnotColors[i]))
                    {
                        UiTheme.FillRoundedRect(g, sb, sr, UiTheme.S(2));
                    }
                    if (_selectedColorIndex == i)
                    {
                        Rectangle outer = new Rectangle(sr.X - UiTheme.S(2), sr.Y - UiTheme.S(2), sr.Width + UiTheme.S(4), sr.Height + UiTheme.S(4));
                        using (Pen sp = new Pen( Color.White, Math.Max(1.5f, 1.5f * UiTheme.DpiScale)))
                        {
                            UiTheme.DrawRoundedRect(g, sp, outer, UiTheme.S(3));
                        }
                    }
                }
            }
        }

        private static void DrawIconBtnBg(Graphics g, Rectangle rect, bool active, bool hovered)
        {
            if (!active && !hovered) return;
            using (SolidBrush b = new SolidBrush(active ? Color.FromArgb(72, 72, 72) : UiTheme.ToolbarHover))
            {
                UiTheme.FillRoundedRect(g, b, rect, UiTheme.S(3));
            }
        }

        private static void DrawSingleAnnotation(Graphics g, AnnotationItem item)
        {
            int[] strokeWidths = new int[] { UiTheme.S(2), UiTheme.S(4), UiTheme.S(6) };
            int strokeW = strokeWidths[Math.Max(0, Math.Min(2, item.ThicknessIndex))];

            if (item.Tool == InlineAnnotateTool.Rectangle)
            {
                Rectangle box = Rectangle.FromLTRB(
                    Math.Min(item.StartPt.X, item.EndPt.X),
                    Math.Min(item.StartPt.Y, item.EndPt.Y),
                    Math.Max(item.StartPt.X, item.EndPt.X),
                    Math.Max(item.StartPt.Y, item.EndPt.Y));
                if (box.Width > 2 && box.Height > 2)
                {
                    using (Pen p = new Pen(item.Color, strokeW))
                    {
                        g.DrawRectangle(p, box);
                    }
                }
            }
            else if (item.Tool == InlineAnnotateTool.Arrow)
            {
                using (Pen p = new Pen(item.Color, strokeW))
                {
                    p.StartCap = LineCap.Round;
                    p.CustomEndCap = new AdjustableArrowCap(4.5f, 5.5f, true);
                    g.DrawLine(p, item.StartPt, item.EndPt);
                }
            }
            else if (item.Tool == InlineAnnotateTool.Pen && item.PenPoints != null && item.PenPoints.Count >= 2)
            {
                using (Pen p = new Pen(item.Color, strokeW) { StartCap = LineCap.Round, EndCap = LineCap.Round, LineJoin = LineJoin.Round })
                {
                    g.DrawLines(p, item.PenPoints.ToArray());
                }
            }
        }

        private static void DrawWeChatSquareHandle(Graphics g, int x, int y)
        {
            int sz = UiTheme.S(6);
            Rectangle r = new Rectangle(x - sz / 2, y - sz / 2, sz, sz);
            using (SolidBrush b = new SolidBrush(UiTheme.WeChatGreen))
            {
                g.FillRectangle(b, r);
            }
        }

        protected override void Dispose(bool disposing)
        {
            if (disposing)
            {
                if (_desktopSnapshot != null) _desktopSnapshot.Dispose();
                if (_toolbarFont != null) _toolbarFont.Dispose();
                if (_badgeFont != null) _badgeFont.Dispose();
                if (_tooltipFont != null) _tooltipFont.Dispose();
            }
            base.Dispose(disposing);
        }
    }
}
