using System;
using System.Runtime.InteropServices;
using System.Windows.Forms;

namespace SpanShot
{
    internal static class Program
    {
        [DllImport("kernel32.dll")]
        private static extern bool AttachConsole(int dwProcessId);
        private const int ATTACH_PARENT_PROCESS = -1;

        [STAThread]
        private static int Main(string[] args)
        {
            NativeMethods.EnableHighDpiAwareness();

            if (args != null && args.Length > 0 && args[0] == "--self-test")
            {
                return SelfTestRunner.RunAllTests();
            }

            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);
            Application.Run(new MainForm());
            return 0;
        }
    }
}
