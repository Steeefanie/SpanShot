using System;
using System.Runtime.InteropServices;
using System.Threading;
using System.Windows.Forms;

namespace SpanShot
{
    internal static class Program
    {
        public static readonly uint WM_SHOW_MAIN = NativeMethods.RegisterWindowMessage("WM_SPANSHOT_SHOW_MAIN");

        [STAThread]
        private static int Main(string[] args)
        {
            NativeMethods.EnableHighDpiAwareness();

            bool startInTray = false;
            if (args != null)
            {
                for (int i = 0; i < args.Length; i++)
                {
                    if (string.Equals(args[i], "--self-test", StringComparison.OrdinalIgnoreCase))
                    {
                        return SelfTestRunner.RunAllTests();
                    }
                    if (string.Equals(args[i], "--gen-icon", StringComparison.OrdinalIgnoreCase) && i + 1 < args.Length)
                    {
                        AppIcon.SaveMultiSizeIco(args[i + 1]);
                        return 0;
                    }
                    if (string.Equals(args[i], "--autostart", StringComparison.OrdinalIgnoreCase) ||
                        string.Equals(args[i], "--minimized", StringComparison.OrdinalIgnoreCase))
                    {
                        startInTray = true;
                    }
                }
            }

            bool createdNew = true;
            Mutex instanceMutex = null;
            try
            {
                instanceMutex = new Mutex(true, @"Local\SpanShot_SingleInstance_Mutex", out createdNew);
            }
            catch
            {
                createdNew = true;
            }

            if (!createdNew)
            {
                if (!startInTray && WM_SHOW_MAIN != 0)
                {
                    NativeMethods.PostMessage(NativeMethods.HWND_BROADCAST, WM_SHOW_MAIN, IntPtr.Zero, IntPtr.Zero);
                }
                if (instanceMutex != null) instanceMutex.Dispose();
                return 0;
            }

            try
            {
                AppSettings.SyncAutoStartPathIfEnabled();

                Application.EnableVisualStyles();
                Application.SetCompatibleTextRenderingDefault(false);
                Application.Run(new MainForm(startInTray));
                return 0;
            }
            finally
            {
                if (instanceMutex != null)
                {
                    try { instanceMutex.ReleaseMutex(); } catch { }
                    instanceMutex.Dispose();
                }
            }
        }
    }
}
