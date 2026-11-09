using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Windows.Forms;

namespace SpanShot
{
    /// <summary>
    /// Always-on-top floating Pin window (like Snipaste).
    /// Supports left-drag to move, mouse wheel to scale (25% - 300%), double-click or right-click to close/copy.
    /// </summary>
    public sealed class PinWindowForm : Form
    {
        private readonly Bitmap _pinnedBitmap;
        private double _scale = 1.0;
        private bool _dragging;
        private Point _dragStart;

        public PinWindowForm(Bitmap sourceBitmap, Point? initialLocation = null)
        {
            _pinnedBitmap = (Bitmap)sourceBitmap.Clone();

            FormBorderStyle = FormBorderStyle.None;
            StartPosition = initialLocation.HasValue ? FormStartPosition.Manual : FormStartPosition.CenterScreen;
            if (initialLocation.HasValue)
            {
                Location = new Point(initialLocation.Value.X - 2, initialLocation.Value.Y - 2);
            }
            TopMost = true;
            ShowInTaskbar = false;
            DoubleBuffered = true;
            BackColor = Color.FromArgb(24, 28, 38);

            // Cap initial display scale if image is huge and no explicit initial location was requested
            Rectangle screen = Screen.PrimaryScreen.WorkingArea;
            if (!initialLocation.HasValue && (_pinnedBitmap.Width > screen.Width * 0.7 || _pinnedBitmap.Height > screen.Height * 0.7))
            {
                _scale = Math.Min(
                    (screen.Width * 0.7) / _pinnedBitmap.Width,
                    (screen.Height * 0.7) / _pinnedBitmap.Height);
            }

            UpdateScaledSize();

            ContextMenu menu = new ContextMenu();
            menu.MenuItems.Add("复制图像 (Ctrl+C)", (s, e) => { try { Clipboard.SetImage(_pinnedBitmap); } catch { } });
            menu.MenuItems.Add("还原 100% 尺寸", (s, e) => { _scale = 1.0; UpdateScaledSize(); });
            menu.MenuItems.Add("-");
            menu.MenuItems.Add("关闭贴图 (Esc / 双击)", (s, e) => Close());
            ContextMenu = menu;
        }

        private void UpdateScaledSize()
        {
            int w = Math.Max(60, (int)Math.Round(_pinnedBitmap.Width * _scale)) + 4;
            int h = Math.Max(40, (int)Math.Round(_pinnedBitmap.Height * _scale)) + 4;
            Size = new Size(w, h);
            Invalidate();
        }

        protected override void OnMouseWheel(MouseEventArgs e)
        {
            base.OnMouseWheel(e);
            double factor = e.Delta > 0 ? 1.12 : 0.89;
            _scale = Math.Max(0.2, Math.Min(3.0, _scale * factor));
            UpdateScaledSize();
        }

        protected override void OnMouseDown(MouseEventArgs e)
        {
            base.OnMouseDown(e);
            if (e.Button == MouseButtons.Left)
            {
                _dragging = true;
                _dragStart = e.Location;
            }
        }

        protected override void OnMouseMove(MouseEventArgs e)
        {
            base.OnMouseMove(e);
            if (_dragging)
            {
                Location = new Point(Left + e.X - _dragStart.X, Top + e.Y - _dragStart.Y);
            }
        }

        protected override void OnMouseUp(MouseEventArgs e)
        {
            base.OnMouseUp(e);
            _dragging = false;
        }

        protected override void OnMouseDoubleClick(MouseEventArgs e)
        {
            base.OnMouseDoubleClick(e);
            if (e.Button == MouseButtons.Left)
            {
                Close();
            }
        }

        protected override void OnKeyDown(KeyEventArgs e)
        {
            base.OnKeyDown(e);
            if (e.KeyCode == Keys.Escape)
            {
                Close();
            }
            else if (e.Control && e.KeyCode == Keys.C)
            {
                try { Clipboard.SetImage(_pinnedBitmap); } catch { }
            }
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            Graphics g = e.Graphics;
            g.InterpolationMode = InterpolationMode.HighQualityBicubic;
            g.DrawImage(_pinnedBitmap, new Rectangle(2, 2, Width - 4, Height - 4));

            using (Pen borderPen = new Pen(Color.FromArgb(0, 185, 255), 2f))
            {
                g.DrawRectangle(borderPen, 1, 1, Width - 2, Height - 2);
            }
        }

        protected override void Dispose(bool disposing)
        {
            if (disposing && _pinnedBitmap != null)
            {
                _pinnedBitmap.Dispose();
            }
            base.Dispose(disposing);
        }
    }
}
