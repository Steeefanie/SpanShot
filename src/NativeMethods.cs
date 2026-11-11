using System;
using System.Runtime.InteropServices;

namespace SpanShot
{
    internal static class NativeMethods
    {
        public const uint WDA_NONE = 0x00000000;
        public const uint WDA_MONITOR = 0x00000001;
        public const uint WDA_EXCLUDEFROMCAPTURE = 0x00000011;

        public const int GWL_EXSTYLE = -20;
        public const int WS_EX_LAYERED = 0x00080000;
        public const int WS_EX_TRANSPARENT = 0x00000020;
        public const int WS_EX_TOOLWINDOW = 0x00000080;
        public const int WS_EX_TOPMOST = 0x00000008;
        public const int WS_EX_NOACTIVATE = 0x08000000;

        public const int WM_SETTINGCHANGE = 0x001A;
        public const int WM_SYSCOMMAND = 0x0112;
        public const int SC_MINIMIZE = 0xF020;
        public const int WM_HOTKEY = 0x0312;
        public const uint WM_MOUSEWHEEL = 0x020A;
        public const uint WM_MOUSEHWHEEL = 0x020E;
        public const int MK_SHIFT = 0x0004;

        public const uint MOD_ALT = 0x0001;
        public const uint MOD_CONTROL = 0x0002;
        public const uint MOD_SHIFT = 0x0004;
        public const uint MOD_NOREPEAT = 0x4000;

        public const uint INPUT_MOUSE = 0;
        public const uint INPUT_KEYBOARD = 1;

        public const uint MOUSEEVENTF_MOVE = 0x0001;
        public const uint MOUSEEVENTF_LEFTDOWN = 0x0002;
        public const uint MOUSEEVENTF_LEFTUP = 0x0004;
        public const uint MOUSEEVENTF_WHEEL = 0x0800;
        public const uint MOUSEEVENTF_HWHEEL = 0x01000;

        public const uint KEYEVENTF_KEYUP = 0x0002;
        public const ushort VK_SHIFT = 0x10;
        public const ushort VK_ESCAPE = 0x1B;
        public const ushort VK_SPACE = 0x20;
        public const ushort VK_RIGHT = 0x27;
        public const ushort VK_DOWN = 0x28;

        public const int SRCCOPY = 0x00CC0020;

        [StructLayout(LayoutKind.Sequential)]
        public struct POINT
        {
            public int X;
            public int Y;
        }

        [StructLayout(LayoutKind.Sequential)]
        public struct RECT
        {
            public int Left;
            public int Top;
            public int Right;
            public int Bottom;
        }

        [StructLayout(LayoutKind.Sequential)]
        public struct INPUT
        {
            public uint type;
            public InputUnion U;
        }

        [StructLayout(LayoutKind.Explicit)]
        public struct InputUnion
        {
            [FieldOffset(0)]
            public MOUSEINPUT mi;
            [FieldOffset(0)]
            public KEYBDINPUT ki;
        }

        [StructLayout(LayoutKind.Sequential)]
        public struct MOUSEINPUT
        {
            public int dx;
            public int dy;
            public int mouseData;
            public uint dwFlags;
            public uint time;
            public IntPtr dwExtraInfo;
        }

        [StructLayout(LayoutKind.Sequential)]
        public struct KEYBDINPUT
        {
            public ushort wVk;
            public ushort wScan;
            public uint dwFlags;
            public uint time;
            public IntPtr dwExtraInfo;
        }

        [DllImport("user32.dll")]
        public static extern bool SetProcessDPIAware();

        [DllImport("shcore.dll")]
        public static extern int SetProcessDpiAwareness(int value);

        [DllImport("user32.dll", SetLastError = true)]
        public static extern bool SetWindowDisplayAffinity(IntPtr hWnd, uint dwAffinity);

        [DllImport("user32.dll", SetLastError = true)]
        public static extern int GetWindowLong(IntPtr hWnd, int nIndex);

        [DllImport("user32.dll", SetLastError = true)]
        public static extern int SetWindowLong(IntPtr hWnd, int nIndex, int dwNewLong);

        [DllImport("user32.dll", SetLastError = true)]
        public static extern bool SetLayeredWindowAttributes(IntPtr hwnd, uint crKey, byte bAlpha, uint dwFlags);

        [DllImport("user32.dll", SetLastError = true)]
        public static extern bool SetWindowPos(IntPtr hWnd, IntPtr hWndInsertAfter, int X, int Y, int cx, int cy, uint uFlags);

        public static readonly IntPtr HWND_TOPMOST = new IntPtr(-1);
        public static readonly IntPtr HWND_BROADCAST = new IntPtr(0xFFFF);
        public const uint SWP_NOSIZE = 0x0001;
        public const uint SWP_NOMOVE = 0x0002;
        public const uint SWP_NOACTIVATE = 0x0010;
        public const uint SWP_SHOWWINDOW = 0x0040;
        public const uint LWA_ALPHA = 0x00000002;

        [DllImport("user32.dll", SetLastError = true)]
        public static extern bool RegisterHotKey(IntPtr hWnd, int id, uint fsModifiers, uint vk);

        [DllImport("user32.dll", SetLastError = true)]
        public static extern bool UnregisterHotKey(IntPtr hWnd, int id);

        [DllImport("user32.dll", SetLastError = true)]
        public static extern uint SendInput(uint nInputs, [MarshalAs(UnmanagedType.LPArray), In] INPUT[] pInputs, int cbSize);

        [DllImport("user32.dll")]
        public static extern bool SetCursorPos(int x, int y);

        [DllImport("user32.dll")]
        public static extern bool GetCursorPos(out POINT lpPoint);

        public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

        [DllImport("user32.dll")]
        public static extern bool EnumWindows(EnumWindowsProc lpEnumFunc, IntPtr lParam);

        [DllImport("user32.dll")]
        public static extern bool EnumChildWindows(IntPtr hWndParent, EnumWindowsProc lpEnumFunc, IntPtr lParam);

        [DllImport("user32.dll")]
        public static extern IntPtr WindowFromPoint(POINT point);

        [DllImport("user32.dll", SetLastError = true)]
        public static extern bool PostMessage(IntPtr hWnd, uint Msg, IntPtr wParam, IntPtr lParam);

        [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        public static extern uint RegisterWindowMessage(string lpString);

        [DllImport("user32.dll")]
        public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);

        [DllImport("user32.dll")]
        public static extern bool IsWindowVisible(IntPtr hWnd);

        [DllImport("user32.dll")]
        public static extern bool IsIconic(IntPtr hWnd);

        [DllImport("user32.dll")]
        public static extern bool SetForegroundWindow(IntPtr hWnd);

        [DllImport("user32.dll")]
        public static extern short GetAsyncKeyState(int vKey);

        [DllImport("user32.dll")]
        public static extern IntPtr GetDesktopWindow();

        [DllImport("user32.dll")]
        public static extern IntPtr GetWindowDC(IntPtr hWnd);

        [DllImport("user32.dll")]
        public static extern int ReleaseDC(IntPtr hWnd, IntPtr hDC);

        [DllImport("gdi32.dll")]
        public static extern bool BitBlt(
            IntPtr hdcDest, int nXDest, int nYDest, int nWidth, int nHeight,
            IntPtr hdcSrc, int nXSrc, int nYSrc, int dwRop);

        public static void EnableHighDpiAwareness()
        {
            try
            {
                // PROCESS_PER_MONITOR_DPI_AWARE = 2
                SetProcessDpiAwareness(2);
            }
            catch
            {
                try { SetProcessDPIAware(); } catch { }
            }
        }

        public static bool TryExcludeWindowFromCapture(IntPtr hWnd)
        {
            try
            {
                return SetWindowDisplayAffinity(hWnd, WDA_EXCLUDEFROMCAPTURE);
            }
            catch
            {
                return false;
            }
        }

        public static void MakeWindowClickThrough(IntPtr hWnd)
        {
            int exStyle = GetWindowLong(hWnd, GWL_EXSTYLE);
            SetWindowLong(hWnd, GWL_EXSTYLE, exStyle | WS_EX_LAYERED | WS_EX_TRANSPARENT | WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE);
            SetLayeredWindowAttributes(hWnd, 0, 255, LWA_ALPHA);
        }

        public static void EnsureTopMost(IntPtr hWnd)
        {
            if (hWnd == IntPtr.Zero) return;
            try
            {
                SetWindowPos(hWnd, HWND_TOPMOST, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE | SWP_SHOWWINDOW);
            }
            catch { }
        }

        public static System.Collections.Generic.List<System.Drawing.Rectangle> GetVisibleWindowRectangles(IntPtr ignoreHwnd)
        {
            var list = new System.Collections.Generic.List<System.Drawing.Rectangle>();
            EnumWindows((hWnd, lParam) =>
            {
                if (hWnd == ignoreHwnd || !IsWindowVisible(hWnd) || IsIconic(hWnd))
                    return true;

                RECT r;
                if (GetWindowRect(hWnd, out r))
                {
                    int w = r.Right - r.Left;
                    int h = r.Bottom - r.Top;
                    if (w >= 60 && h >= 60)
                    {
                        // Also inspect child sub-containers (e.g., scrollable panels) first so inner panels match before outer frame
                        EnumChildWindows(hWnd, (childHwnd, p) =>
                        {
                            if (IsWindowVisible(childHwnd))
                            {
                                RECT cr;
                                if (GetWindowRect(childHwnd, out cr))
                                {
                                    int cw = cr.Right - cr.Left;
                                    int ch = cr.Bottom - cr.Top;
                                    if (cw >= 80 && ch >= 80 && (cw < w || ch < h))
                                    {
                                        list.Add(new System.Drawing.Rectangle(cr.Left, cr.Top, cw, ch));
                                    }
                                }
                            }
                            return true;
                        }, IntPtr.Zero);

                        list.Add(new System.Drawing.Rectangle(r.Left, r.Top, w, h));
                    }
                }
                return true;
            }, IntPtr.Zero);
            return list;
        }

        public static void FocusWindowAtPoint(int screenX, int screenY)
        {
            try
            {
                POINT pt = new POINT { X = screenX, Y = screenY };
                IntPtr targetHwnd = WindowFromPoint(pt);
                if (targetHwnd != IntPtr.Zero)
                {
                    SetForegroundWindow(targetHwnd);
                }
            }
            catch { }
        }

        private static IntPtr MakeWheelWParam(int delta, int keyFlags)
        {
            int high = (short)delta;
            int low = keyFlags & 0xFFFF;
            return new IntPtr((high << 16) | low);
        }

        private static IntPtr MakePointLParam(int screenX, int screenY)
        {
            return new IntPtr(((screenY & 0xFFFF) << 16) | (screenX & 0xFFFF));
        }

        public static void SendVerticalWheel(int screenX, int screenY, int wheelDelta, bool cursorInsideTarget)
        {
            if (cursorInsideTarget)
            {
                INPUT[] inputs = new INPUT[1];
                inputs[0].type = INPUT_MOUSE;
                inputs[0].U.mi.dwFlags = MOUSEEVENTF_WHEEL;
                inputs[0].U.mi.mouseData = wheelDelta;
                SendInput(1, inputs, Marshal.SizeOf(typeof(INPUT)));
            }
            else
            {
                POINT pt = new POINT { X = screenX, Y = screenY };
                IntPtr targetHwnd = WindowFromPoint(pt);
                if (targetHwnd != IntPtr.Zero)
                {
                    PostMessage(targetHwnd, WM_MOUSEWHEEL, MakeWheelWParam(wheelDelta, 0), MakePointLParam(screenX, screenY));
                }
            }
        }

        public static void SendHorizontalScroll(int screenX, int screenY, int amount, HorizontalScrollMethod method, bool cursorInsideTarget)
        {
            int cb = Marshal.SizeOf(typeof(INPUT));
            POINT pt = new POINT { X = screenX, Y = screenY };
            IntPtr targetHwnd = WindowFromPoint(pt);

            if (method == HorizontalScrollMethod.PlainWheel)
            {
                if (cursorInsideTarget)
                {
                    INPUT[] inputs = new INPUT[1];
                    inputs[0].type = INPUT_MOUSE;
                    inputs[0].U.mi.dwFlags = MOUSEEVENTF_WHEEL;
                    inputs[0].U.mi.mouseData = -amount;
                    SendInput(1, inputs, cb);
                }
                else if (targetHwnd != IntPtr.Zero)
                {
                    PostMessage(targetHwnd, WM_MOUSEWHEEL, MakeWheelWParam(-amount, 0), MakePointLParam(screenX, screenY));
                }
            }
            else if (method == HorizontalScrollMethod.NativeHWheel)
            {
                if (cursorInsideTarget)
                {
                    INPUT[] inputs = new INPUT[1];
                    inputs[0].type = INPUT_MOUSE;
                    inputs[0].U.mi.dwFlags = MOUSEEVENTF_HWHEEL;
                    inputs[0].U.mi.mouseData = amount;
                    SendInput(1, inputs, cb);
                }
                else if (targetHwnd != IntPtr.Zero)
                {
                    PostMessage(targetHwnd, WM_MOUSEHWHEEL, MakeWheelWParam(amount, 0), MakePointLParam(screenX, screenY));
                }
            }
            else if (method == HorizontalScrollMethod.ShiftWheel)
            {
                if (cursorInsideTarget)
                {
                    INPUT[] down = new INPUT[1];
                    down[0].type = INPUT_KEYBOARD;
                    down[0].U.ki.wVk = VK_SHIFT;
                    SendInput(1, down, cb);

                    System.Threading.Thread.Sleep(8);

                    INPUT[] wheel = new INPUT[1];
                    wheel[0].type = INPUT_MOUSE;
                    wheel[0].U.mi.dwFlags = MOUSEEVENTF_WHEEL;
                    wheel[0].U.mi.mouseData = -amount;
                    SendInput(1, wheel, cb);

                    System.Threading.Thread.Sleep(8);

                    INPUT[] up = new INPUT[1];
                    up[0].type = INPUT_KEYBOARD;
                    up[0].U.ki.wVk = VK_SHIFT;
                    up[0].U.ki.dwFlags = KEYEVENTF_KEYUP;
                    SendInput(1, up, cb);
                }
                else if (targetHwnd != IntPtr.Zero)
                {
                    PostMessage(targetHwnd, WM_MOUSEWHEEL, MakeWheelWParam(-amount, MK_SHIFT), MakePointLParam(screenX, screenY));
                }
            }
            else if (method == HorizontalScrollMethod.RightArrowKey)
            {
                FocusWindowAtPoint(screenX, screenY);
                INPUT[] inputs = new INPUT[2];
                inputs[0].type = INPUT_KEYBOARD;
                inputs[0].U.ki.wVk = VK_RIGHT;
                inputs[1].type = INPUT_KEYBOARD;
                inputs[1].U.ki.wVk = VK_RIGHT;
                inputs[1].U.ki.dwFlags = KEYEVENTF_KEYUP;
                SendInput(2, inputs, cb);
            }
        }
    }

    public enum HorizontalScrollMethod
    {
        PlainWheel = 0,
        NativeHWheel = 1,
        ShiftWheel = 2,
        RightArrowKey = 3
    }
}
