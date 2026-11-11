using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.Windows.Forms;

namespace SpanShot
{
    public sealed class ResultPreviewForm : Form
    {
        private enum EditTool
        {
            PanBrowse = 0,
            Rectangle = 1,
            Arrow = 2,
            Pen = 3,
            Crop = 4
        }

        private Bitmap _workingBitmap;
        private readonly Stack<Bitmap> _history = new Stack<Bitmap>();
        private readonly string _captureTypeTag;
        private readonly string _initialSaveDir;

        public Bitmap WorkingBitmap { get { return _workingBitmap; } }
        public bool ManuallySaved { get; private set; }
        public bool ConfirmedCopy { get; private set; }

        private Panel _scrollPanel;
        private PictureBox _picBox;

        private Button _btnToolPan;
        private Button _btnToolRect;
        private Button _btnToolArrow;
        private Button _btnToolPen;
        private Button _btnToolCrop;
        private Button _btnUndo;
        private Button _btnZoomToggle;

        private EditTool _currentTool = EditTool.PanBrowse;
        private bool _fitToWindow;

        private bool _isDragging;
        private Point _dragStartControlPt;
        private Point _dragCurrentControlPt;
        private Point _panStartScrollPos;
        private readonly List<Point> _penControlPoints = new List<Point>();

        public ResultPreviewForm(Bitmap bitmap, string captureTypeTag, string initialSaveDir = null)
        {
            if (bitmap == null) throw new ArgumentNullException("bitmap");
            _workingBitmap = (Bitmap)bitmap.Clone();
            _captureTypeTag = captureTypeTag;
            _initialSaveDir = initialSaveDir;

            bool isLongOrWide = (_workingBitmap.Height > _workingBitmap.Width * 1.8) ||
                                (_workingBitmap.Width > _workingBitmap.Height * 1.8);
            _fitToWindow = !isLongOrWide;

            InitializeComponent();
            CopyToClipboardSafe();
            UpdateToolButtonStyles();
            UpdateZoomLayout();
        }

        private void InitializeComponent()
        {
            UpdateWindowTitle();
            Icon = AppIcon.GetWindowIcon();
            Size = new Size(UiTheme.S(960), UiTheme.S(680));
            StartPosition = FormStartPosition.CenterScreen;
            BackColor = UiTheme.BgDark;
            ForeColor = Color.White;
            KeyPreview = true;

            Panel topBar = new Panel
            {
                Dock = DockStyle.Top,
                Height = UiTheme.S(52),
                BackColor = UiTheme.ToolbarBg
            };

            Font btnFont = UiTheme.FontPx(13, false);
            int y = UiTheme.S(9);
            int h = UiTheme.S(34);
            int gap = UiTheme.S(6);
            int curX = UiTheme.S(14);

            _btnToolPan = CreateButton("浏览", new Point(curX, y), new Size(UiTheme.S(60), h), UiTheme.BgPill, btnFont);
            _btnToolPan.Click += (s, e) => SelectTool(EditTool.PanBrowse);
            curX += _btnToolPan.Width + gap;

            _btnToolRect = CreateButton("方框", new Point(curX, y), new Size(UiTheme.S(60), h), UiTheme.BgPill, btnFont);
            _btnToolRect.Click += (s, e) => SelectTool(EditTool.Rectangle);
            curX += _btnToolRect.Width + gap;

            _btnToolArrow = CreateButton("箭头", new Point(curX, y), new Size(UiTheme.S(60), h), UiTheme.BgPill, btnFont);
            _btnToolArrow.Click += (s, e) => SelectTool(EditTool.Arrow);
            curX += _btnToolArrow.Width + gap;

            _btnToolPen = CreateButton("画笔", new Point(curX, y), new Size(UiTheme.S(60), h), UiTheme.BgPill, btnFont);
            _btnToolPen.Click += (s, e) => SelectTool(EditTool.Pen);
            curX += _btnToolPen.Width + gap;

            _btnToolCrop = CreateButton("裁剪", new Point(curX, y), new Size(UiTheme.S(60), h), UiTheme.BgPill, btnFont);
            _btnToolCrop.Click += (s, e) => SelectTool(EditTool.Crop);
            curX += _btnToolCrop.Width + gap;

            _btnUndo = CreateButton("撤销", new Point(curX, y), new Size(UiTheme.S(60), h), UiTheme.BgPill, btnFont);
            _btnUndo.Enabled = false;
            _btnUndo.Click += (s, e) => PerformUndo();
            curX += _btnUndo.Width + UiTheme.S(16);

            _btnZoomToggle = CreateButton(_fitToWindow ? "100%" : "适应窗口",
                new Point(curX, y), new Size(UiTheme.S(80), h), UiTheme.BgPill, btnFont);
            _btnZoomToggle.Click += (s, e) =>
            {
                _fitToWindow = !_fitToWindow;
                _btnZoomToggle.Text = _fitToWindow ? "100%" : "适应窗口";
                UpdateZoomLayout();
            };
            curX += _btnZoomToggle.Width + gap;

            Button btnPin = CreateButton("钉选", new Point(curX, y), new Size(UiTheme.S(68), h), UiTheme.BgPill, btnFont);
            btnPin.Click += (s, e) => PinToDesktop();
            curX += btnPin.Width + gap;

            Button btnSaveAs = CreateButton("下载", new Point(curX, y), new Size(UiTheme.S(68), h), UiTheme.BgPill, btnFont);
            btnSaveAs.Click += (s, e) => SaveToFile();
            curX += btnSaveAs.Width + gap;

            Button btnCopyClose = CreateButton("完成", new Point(curX, y), new Size(UiTheme.S(84), h), UiTheme.WeChatGreen, btnFont);
            btnCopyClose.Click += (s, e) =>
            {
                CopyToClipboardSafe();
                ConfirmedCopy = true;
                Close();
            };

            topBar.Controls.Add(_btnToolPan);
            topBar.Controls.Add(_btnToolRect);
            topBar.Controls.Add(_btnToolArrow);
            topBar.Controls.Add(_btnToolPen);
            topBar.Controls.Add(_btnToolCrop);
            topBar.Controls.Add(_btnUndo);
            topBar.Controls.Add(_btnZoomToggle);
            topBar.Controls.Add(btnPin);
            topBar.Controls.Add(btnSaveAs);
            topBar.Controls.Add(btnCopyClose);

            _scrollPanel = new Panel
            {
                Dock = DockStyle.Fill,
                AutoScroll = true,
                BackColor = Color.FromArgb(20, 20, 22)
            };

            _picBox = new PictureBox
            {
                Image = _workingBitmap,
                BackColor = Color.FromArgb(20, 20, 22)
            };
            _picBox.MouseDown += OnPicMouseDown;
            _picBox.MouseMove += OnPicMouseMove;
            _picBox.MouseUp += OnPicMouseUp;
            _picBox.Paint += OnPicPaintOverlay;

            _scrollPanel.Controls.Add(_picBox);
            _scrollPanel.Resize += (s, e) =>
            {
                if (_fitToWindow) UpdateZoomLayout();
            };

            Controls.Add(_scrollPanel);
            Controls.Add(topBar);
        }

        private void UpdateWindowTitle()
        {
            Text = string.Format("{0} ({1} × {2})", _captureTypeTag, _workingBitmap.Width, _workingBitmap.Height);
        }

        private void SelectTool(EditTool tool)
        {
            _currentTool = tool;
            UpdateToolButtonStyles();
            _picBox.Cursor = tool == EditTool.PanBrowse ? Cursors.SizeAll : Cursors.Cross;
        }

        private void UpdateToolButtonStyles()
        {
            SetToolBtnActive(_btnToolPan, _currentTool == EditTool.PanBrowse, UiTheme.WeChatGreen);
            SetToolBtnActive(_btnToolRect, _currentTool == EditTool.Rectangle, UiTheme.WeChatGreen);
            SetToolBtnActive(_btnToolArrow, _currentTool == EditTool.Arrow, UiTheme.WeChatGreen);
            SetToolBtnActive(_btnToolPen, _currentTool == EditTool.Pen, UiTheme.WeChatGreen);
            SetToolBtnActive(_btnToolCrop, _currentTool == EditTool.Crop, UiTheme.WeChatGreen);
        }

        private static void SetToolBtnActive(Button btn, bool active, Color activeColor)
        {
            if (btn == null) return;
            btn.BackColor = active ? activeColor : UiTheme.BgPill;
        }

        private static Button CreateButton(string text, Point location, Size size, Color backColor, Font font)
        {
            Button btn = new Button
            {
                Text = text,
                Location = location,
                Size = size,
                FlatStyle = FlatStyle.Flat,
                BackColor = backColor,
                ForeColor = Color.White,
                Font = font,
                Cursor = Cursors.Hand
            };
            btn.FlatAppearance.BorderSize = 0;
            return btn;
        }

        protected override void OnMouseWheel(MouseEventArgs e)
        {
            if (!_fitToWindow && _scrollPanel.AutoScroll)
            {
                bool scrollHoriz = (ModifierKeys & Keys.Shift) == Keys.Shift ||
                                   (_workingBitmap.Width > _workingBitmap.Height && _scrollPanel.VerticalScroll.Maximum <= _scrollPanel.ClientSize.Height);

                if (scrollHoriz)
                {
                    int curX = -_scrollPanel.AutoScrollPosition.X;
                    int curY = -_scrollPanel.AutoScrollPosition.Y;
                    int nextX = Math.Max(0, curX - e.Delta);
                    _scrollPanel.AutoScrollPosition = new Point(nextX, curY);
                    return;
                }
            }
            base.OnMouseWheel(e);
        }

        private void OnPicMouseDown(object sender, MouseEventArgs e)
        {
            if (e.Button != MouseButtons.Left) return;
            _isDragging = true;
            _dragStartControlPt = e.Location;
            _dragCurrentControlPt = e.Location;
            _penControlPoints.Clear();
            if (_currentTool == EditTool.Pen)
            {
                _penControlPoints.Add(e.Location);
            }

            if (_currentTool == EditTool.PanBrowse)
            {
                _panStartScrollPos = new Point(-_scrollPanel.AutoScrollPosition.X, -_scrollPanel.AutoScrollPosition.Y);
            }
        }

        private void OnPicMouseMove(object sender, MouseEventArgs e)
        {
            if (!_isDragging) return;
            _dragCurrentControlPt = e.Location;

            if (_currentTool == EditTool.PanBrowse && !_fitToWindow)
            {
                int dx = e.X - _dragStartControlPt.X;
                int dy = e.Y - _dragStartControlPt.Y;
                _scrollPanel.AutoScrollPosition = new Point(
                    Math.Max(0, _panStartScrollPos.X - dx),
                    Math.Max(0, _panStartScrollPos.Y - dy));
            }
            else if (_currentTool == EditTool.Pen)
            {
                if (_penControlPoints.Count == 0 ||
                    Math.Abs(_penControlPoints[_penControlPoints.Count - 1].X - e.X) +
                    Math.Abs(_penControlPoints[_penControlPoints.Count - 1].Y - e.Y) >= 2)
                {
                    _penControlPoints.Add(e.Location);
                }
                _picBox.Invalidate();
            }
            else if (_currentTool != EditTool.PanBrowse)
            {
                _picBox.Invalidate();
            }
        }

        private void OnPicMouseUp(object sender, MouseEventArgs e)
        {
            if (!_isDragging || e.Button != MouseButtons.Left) return;
            _isDragging = false;

            if (_currentTool == EditTool.PanBrowse) return;

            if (_currentTool == EditTool.Pen)
            {
                if (_penControlPoints.Count >= 2)
                {
                    PushHistory();
                    Point[] imgPts = new Point[_penControlPoints.Count];
                    for (int i = 0; i < _penControlPoints.Count; i++)
                    {
                        imgPts[i] = ControlToImagePoint(_penControlPoints[i]);
                    }
                    using (Graphics g = Graphics.FromImage(_workingBitmap))
                    using (Pen p = new Pen(UiTheme.AnnotColors[0], UiTheme.S(3)) { StartCap = LineCap.Round, EndCap = LineCap.Round, LineJoin = LineJoin.Round })
                    {
                        g.SmoothingMode = SmoothingMode.AntiAlias;
                        g.DrawLines(p, imgPts);
                    }
                    CopyToClipboardSafe();
                }
                _penControlPoints.Clear();
                _picBox.Invalidate();
                return;
            }

            Point imgStart = ControlToImagePoint(_dragStartControlPt);
            Point imgEnd = ControlToImagePoint(e.Location);

            Rectangle box = Rectangle.FromLTRB(
                Math.Min(imgStart.X, imgEnd.X),
                Math.Min(imgStart.Y, imgEnd.Y),
                Math.Max(imgStart.X, imgEnd.X),
                Math.Max(imgStart.Y, imgEnd.Y));
            box.Intersect(new Rectangle(0, 0, _workingBitmap.Width, _workingBitmap.Height));

            if (_currentTool == EditTool.Crop)
            {
                if (box.Width >= 24 && box.Height >= 24)
                {
                    PushHistory();
                    Bitmap cropped = new Bitmap(box.Width, box.Height, PixelFormat.Format32bppArgb);
                    using (Graphics g = Graphics.FromImage(cropped))
                    {
                        g.DrawImage(_workingBitmap, new Rectangle(0, 0, box.Width, box.Height), box, GraphicsUnit.Pixel);
                    }
                    _workingBitmap.Dispose();
                    _workingBitmap = cropped;
                    _picBox.Image = _workingBitmap;
                    UpdateWindowTitle();
                    UpdateZoomLayout();
                    CopyToClipboardSafe();
                }
                SelectTool(EditTool.PanBrowse);
            }
            else if (box.Width >= 4 || box.Height >= 4)
            {
                PushHistory();
                using (Graphics g = Graphics.FromImage(_workingBitmap))
                {
                    g.SmoothingMode = SmoothingMode.AntiAlias;
                    DrawAnnotationShape(g, _currentTool, imgStart, imgEnd, box);
                }
                CopyToClipboardSafe();
            }

            _picBox.Invalidate();
        }

        private void OnPicPaintOverlay(object sender, PaintEventArgs e)
        {
            if (!_isDragging || _currentTool == EditTool.PanBrowse) return;

            Graphics g = e.Graphics;
            g.SmoothingMode = SmoothingMode.AntiAlias;

            if (_currentTool == EditTool.Pen && _penControlPoints.Count >= 2)
            {
                using (Pen p = new Pen(UiTheme.AnnotColors[0], UiTheme.S(3)) { StartCap = LineCap.Round, EndCap = LineCap.Round, LineJoin = LineJoin.Round })
                {
                    g.DrawLines(p, _penControlPoints.ToArray());
                }
                return;
            }

            Rectangle box = Rectangle.FromLTRB(
                Math.Min(_dragStartControlPt.X, _dragCurrentControlPt.X),
                Math.Min(_dragStartControlPt.Y, _dragCurrentControlPt.Y),
                Math.Max(_dragStartControlPt.X, _dragCurrentControlPt.X),
                Math.Max(_dragStartControlPt.Y, _dragCurrentControlPt.Y));

            if (_currentTool == EditTool.Crop)
            {
                using (Pen cropPen = new Pen(UiTheme.WeChatGreen, UiTheme.S(2)))
                {
                    cropPen.DashStyle = DashStyle.Dash;
                    g.DrawRectangle(cropPen, box);
                }
            }
            else
            {
                DrawAnnotationShape(g, _currentTool, _dragStartControlPt, _dragCurrentControlPt, box);
            }
        }

        private static void DrawAnnotationShape(Graphics g, EditTool tool, Point p1, Point p2, Rectangle box)
        {
            if (tool == EditTool.Rectangle && box.Width > 2 && box.Height > 2)
            {
                using (Pen p = new Pen(UiTheme.AnnotColors[0], UiTheme.S(3)))
                {
                    g.DrawRectangle(p, box);
                }
            }
            else if (tool == EditTool.Arrow)
            {
                using (Pen p = new Pen(UiTheme.AnnotColors[0], UiTheme.S(3)))
                {
                    p.StartCap = LineCap.Round;
                    p.CustomEndCap = new AdjustableArrowCap(4.5f, 5.5f, true);
                    g.DrawLine(p, p1, p2);
                }
            }
        }

        private Point ControlToImagePoint(Point controlPt)
        {
            if (!_fitToWindow || _picBox.ClientSize.Width <= 0 || _picBox.ClientSize.Height <= 0)
            {
                return controlPt;
            }

            double imgAspect = (double)_workingBitmap.Width / _workingBitmap.Height;
            double boxAspect = (double)_picBox.ClientSize.Width / _picBox.ClientSize.Height;

            double scale;
            double offsetX = 0;
            double offsetY = 0;

            if (imgAspect > boxAspect)
            {
                scale = (double)_picBox.ClientSize.Width / _workingBitmap.Width;
                double renderedH = _workingBitmap.Height * scale;
                offsetY = (_picBox.ClientSize.Height - renderedH) / 2.0;
            }
            else
            {
                scale = (double)_picBox.ClientSize.Height / _workingBitmap.Height;
                double renderedW = _workingBitmap.Width * scale;
                offsetX = (_picBox.ClientSize.Width - renderedW) / 2.0;
            }

            int ix = (int)Math.Round((controlPt.X - offsetX) / Math.Max(0.001, scale));
            int iy = (int)Math.Round((controlPt.Y - offsetY) / Math.Max(0.001, scale));
            ix = Math.Max(0, Math.Min(_workingBitmap.Width, ix));
            iy = Math.Max(0, Math.Min(_workingBitmap.Height, iy));
            return new Point(ix, iy);
        }

        private void PushHistory()
        {
            if (_history.Count >= 10)
            {
                Bitmap[] arr = _history.ToArray();
                arr[arr.Length - 1].Dispose();
            }
            _history.Push((Bitmap)_workingBitmap.Clone());
            _btnUndo.Enabled = true;
        }

        private void PerformUndo()
        {
            if (_history.Count == 0) return;
            _workingBitmap.Dispose();
            _workingBitmap = _history.Pop();
            _picBox.Image = _workingBitmap;
            _btnUndo.Enabled = _history.Count > 0;
            UpdateWindowTitle();
            UpdateZoomLayout();
            CopyToClipboardSafe();
        }

        private void UpdateZoomLayout()
        {
            if (_scrollPanel.ClientSize.Width <= 10 || _scrollPanel.ClientSize.Height <= 10)
                return;

            if (_fitToWindow)
            {
                _scrollPanel.AutoScroll = false;
                _picBox.Dock = DockStyle.Fill;
                _picBox.SizeMode = PictureBoxSizeMode.Zoom;
            }
            else
            {
                _picBox.Dock = DockStyle.None;
                _picBox.SizeMode = PictureBoxSizeMode.AutoSize;
                _picBox.Location = new Point(0, 0);
                _scrollPanel.AutoScroll = true;
            }
            _picBox.Cursor = _currentTool == EditTool.PanBrowse ? Cursors.SizeAll : Cursors.Cross;
        }

        private void CopyToClipboardSafe()
        {
            try { Clipboard.SetImage(_workingBitmap); } catch { }
        }

        private void PinToDesktop()
        {
            PinWindowForm pin = new PinWindowForm(_workingBitmap);
            pin.Show();
            Close();
        }

        private void SaveToFile()
        {
            using (SaveFileDialog sfd = new SaveFileDialog())
            {
                sfd.Filter = "PNG 图像 (*.png)|*.png|JPEG 图像 (*.jpg)|*.jpg";
                sfd.DefaultExt = "png";
                if (!string.IsNullOrEmpty(_initialSaveDir) && System.IO.Directory.Exists(_initialSaveDir))
                {
                    sfd.InitialDirectory = _initialSaveDir;
                }
                sfd.FileName = string.Format("SpanShot_{0}_{1:yyyyMMdd_HHmmss}.png", _captureTypeTag, DateTime.Now);

                if (sfd.ShowDialog(this) == DialogResult.OK)
                {
                    ImageFormat fmt = sfd.FileName.EndsWith(".jpg", StringComparison.OrdinalIgnoreCase)
                        ? ImageFormat.Jpeg : ImageFormat.Png;
                    _workingBitmap.Save(sfd.FileName, fmt);
                    ManuallySaved = true;
                    ToastForm.ShowToast("已保存", UiTheme.WeChatGreen);
                }
            }
        }

        protected override void OnKeyDown(KeyEventArgs e)
        {
            base.OnKeyDown(e);
            if (e.KeyCode == Keys.Escape) Close();
            else if (e.KeyCode == Keys.Enter) { CopyToClipboardSafe(); ConfirmedCopy = true; Close(); }
            else if (e.Control && e.KeyCode == Keys.C) CopyToClipboardSafe();
            else if (e.Control && e.KeyCode == Keys.S) SaveToFile();
            else if (e.Control && e.KeyCode == Keys.Z) PerformUndo();
        }

        protected override void Dispose(bool disposing)
        {
            if (disposing)
            {
                if (_workingBitmap != null) _workingBitmap.Dispose();
                while (_history.Count > 0) _history.Pop().Dispose();
            }
            base.Dispose(disposing);
        }
    }
}
