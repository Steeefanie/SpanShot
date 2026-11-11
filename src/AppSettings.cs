using System;
using System.Drawing;
using System.Drawing.Imaging;
using System.IO;
using System.Runtime.InteropServices;
using System.Windows.Forms;
using Microsoft.Win32;

namespace SpanShot
{
    internal static class AppSettings
    {
        private const string AppSettingsKeyPath = @"Software\SpanShot";
        private const string StartupRunKeyPath = @"Software\Microsoft\Windows\CurrentVersion\Run";
        private const string AppValueName = "SpanShot";

        public static void LoadPreferences(
            out bool keepInBackground,
            out bool quickCopyOnly,
            out bool autoSave,
            out string autoSaveDir)
        {
            keepInBackground = true;
            quickCopyOnly = false;
            autoSave = false;
            autoSaveDir = string.Empty;

            try
            {
                using (RegistryKey key = Registry.CurrentUser.OpenSubKey(AppSettingsKeyPath, false))
                {
                    if (key != null)
                    {
                        object keepVal = key.GetValue("KeepInBackground");
                        if (keepVal != null)
                        {
                            keepInBackground = Convert.ToInt32(keepVal) != 0;
                        }

                        object quickVal = key.GetValue("QuickCopyOnly");
                        if (quickVal != null)
                        {
                            quickCopyOnly = Convert.ToInt32(quickVal) != 0;
                        }

                        object dirVal = key.GetValue("AutoSaveDir");
                        if (dirVal is string)
                        {
                            autoSaveDir = ((string)dirVal).Trim();
                        }

                        object autoSaveVal = key.GetValue("AutoSave");
                        if (autoSaveVal != null)
                        {
                            autoSave = Convert.ToInt32(autoSaveVal) != 0;
                        }
                    }
                }
            }
            catch { }

            // Enforce invariant on load: autoSave can only remain enabled if folder is chosen and writable
            if (autoSave)
            {
                string err;
                if (!ValidateWritableFolder(autoSaveDir, out err))
                {
                    autoSave = false;
                }
            }
        }

        public static void SavePreferences(
            bool keepInBackground,
            bool quickCopyOnly,
            bool autoSave,
            string autoSaveDir)
        {
            try
            {
                using (RegistryKey key = Registry.CurrentUser.CreateSubKey(AppSettingsKeyPath))
                {
                    if (key != null)
                    {
                        key.SetValue("KeepInBackground", keepInBackground ? 1 : 0, RegistryValueKind.DWord);
                        key.SetValue("QuickCopyOnly", quickCopyOnly ? 1 : 0, RegistryValueKind.DWord);
                        key.SetValue("AutoSave", autoSave ? 1 : 0, RegistryValueKind.DWord);
                        key.SetValue("AutoSaveDir", autoSaveDir ?? string.Empty, RegistryValueKind.String);
                    }
                }
            }
            catch { }
        }

        /// <summary>
        /// Verifies that <paramref name="folderPath"/> exists and is genuinely writable by creating,
        /// writing, flushing, and deleting a temporary probe file.
        /// </summary>
        public static bool ValidateWritableFolder(string folderPath, out string errorMessage)
        {
            errorMessage = null;
            if (string.IsNullOrEmpty(folderPath) || folderPath.Trim().Length == 0)
            {
                errorMessage = "请先选择自动保存文件夹";
                return false;
            }

            string normalized;
            try
            {
                normalized = Path.GetFullPath(folderPath.Trim());
            }
            catch
            {
                errorMessage = "文件夹路径格式无效，请重新选择";
                return false;
            }

            if (!Directory.Exists(normalized))
            {
                errorMessage = "所选文件夹不存在，请重新选择";
                return false;
            }

            string probeFile = Path.Combine(
                normalized,
                string.Format(".spanshot_write_check_{0:N}.tmp", Guid.NewGuid()));

            try
            {
                using (FileStream fs = new FileStream(probeFile, FileMode.CreateNew, FileAccess.Write, FileShare.None))
                {
                    byte[] probeBytes = new byte[] { 0x53 };
                    fs.Write(probeBytes, 0, 1);
                    fs.Flush();
                }
                return true;
            }
            catch (UnauthorizedAccessException)
            {
                errorMessage = "该文件夹无写入权限，请重选";
                return false;
            }
            catch
            {
                errorMessage = "该文件夹不可写入，请重选";
                return false;
            }
            finally
            {
                try
                {
                    if (File.Exists(probeFile))
                    {
                        File.Delete(probeFile);
                    }
                }
                catch { }
            }
        }

        public static bool TryAutoSaveBitmap(Bitmap bmp, string folderPath, string tag, out string savedFilePath)
        {
            savedFilePath = null;
            if (bmp == null || string.IsNullOrEmpty(folderPath)) return false;

            try
            {
                if (!Directory.Exists(folderPath)) return false;

                string prefix = string.IsNullOrEmpty(tag)
                    ? string.Format("SpanShot_{0:yyyyMMdd_HHmmss}", DateTime.Now)
                    : string.Format("SpanShot_{0}_{1:yyyyMMdd_HHmmss}", tag, DateTime.Now);

                string candidate = Path.Combine(folderPath, prefix + ".png");
                int index = 1;
                while (File.Exists(candidate))
                {
                    candidate = Path.Combine(folderPath, string.Format("{0}_{1}.png", prefix, index));
                    index++;
                }

                bmp.Save(candidate, ImageFormat.Png);
                savedFilePath = candidate;
                return true;
            }
            catch
            {
                return false;
            }
        }

        public static string PickFolderDialog(IntPtr ownerHwnd, string initialFolder, string title)
        {
            // Try modern Windows Explorer folder picker (IFileOpenDialog + FOS_PICKFOLDERS)
            try
            {
                bool cancelled;
                string modernResult = ShowVistaFolderDialog(ownerHwnd, initialFolder, title, out cancelled);
                if (cancelled || !string.IsNullOrEmpty(modernResult))
                {
                    return modernResult;
                }
            }
            catch { }

            // Fallback to classic FolderBrowserDialog
            using (FolderBrowserDialog fbd = new FolderBrowserDialog())
            {
                fbd.Description = title ?? "选择自动保存文件夹";
                fbd.ShowNewFolderButton = true;
                if (!string.IsNullOrEmpty(initialFolder) && Directory.Exists(initialFolder))
                {
                    fbd.SelectedPath = initialFolder;
                }

                DialogResult dr = ownerHwnd != IntPtr.Zero
                    ? fbd.ShowDialog(new Win32WindowWrapper(ownerHwnd))
                    : fbd.ShowDialog();

                if (dr == DialogResult.OK && !string.IsNullOrEmpty(fbd.SelectedPath))
                {
                    return fbd.SelectedPath;
                }
                return null;
            }
        }

        public static bool IsAutoStartEnabled()
        {
            try
            {
                using (RegistryKey key = Registry.CurrentUser.OpenSubKey(StartupRunKeyPath, false))
                {
                    if (key == null) return false;
                    string val = key.GetValue(AppValueName) as string;
                    return !string.IsNullOrEmpty(val);
                }
            }
            catch
            {
                return false;
            }
        }

        public static bool SetAutoStart(bool enabled)
        {
            try
            {
                using (RegistryKey key = Registry.CurrentUser.OpenSubKey(StartupRunKeyPath, true))
                {
                    if (key == null) return false;
                    if (enabled)
                    {
                        string command = BuildAutoStartCommand();
                        key.SetValue(AppValueName, command, RegistryValueKind.String);
                    }
                    else
                    {
                        key.DeleteValue(AppValueName, false);
                    }
                    return true;
                }
            }
            catch
            {
                return false;
            }
        }

        public static void SyncAutoStartPathIfEnabled()
        {
            try
            {
                using (RegistryKey key = Registry.CurrentUser.OpenSubKey(StartupRunKeyPath, true))
                {
                    if (key == null) return;
                    string currentVal = key.GetValue(AppValueName) as string;
                    if (!string.IsNullOrEmpty(currentVal))
                    {
                        string expected = BuildAutoStartCommand();
                        if (!string.Equals(currentVal, expected, StringComparison.OrdinalIgnoreCase))
                        {
                            key.SetValue(AppValueName, expected, RegistryValueKind.String);
                        }
                    }
                }
            }
            catch { }
        }

        private static string BuildAutoStartCommand()
        {
            return string.Format("\"{0}\" --autostart", Application.ExecutablePath);
        }

        #region Modern Windows Folder Picker (IFileOpenDialog COM Interop)

        private const uint FOS_PICKFOLDERS = 0x00000020;
        private const uint FOS_FORCEFILESYSTEM = 0x00000040;
        private const uint FOS_PATHMUSTEXIST = 0x00000800;
        private const uint FOS_NOCHANGEDIR = 0x00000008;
        private const uint SIGDN_FILESYSPATH = 0x80058000;
        private const int HRESULT_CANCELLED = unchecked((int)0x800704C7);

        [DllImport("shell32.dll", CharSet = CharSet.Unicode, PreserveSig = true)]
        private static extern int SHCreateItemFromParsingName(
            [MarshalAs(UnmanagedType.LPWStr)] string pszPath,
            IntPtr pbc,
            ref Guid riid,
            [MarshalAs(UnmanagedType.Interface)] out IShellItem ppv);

        private static string ShowVistaFolderDialog(IntPtr ownerHwnd, string initialFolder, string title, out bool cancelled)
        {
            cancelled = false;
            IFileDialog dialog = (IFileDialog)(new FileOpenDialogRCW());
            try
            {
                uint options;
                dialog.GetOptions(out options);
                dialog.SetOptions(options | FOS_PICKFOLDERS | FOS_FORCEFILESYSTEM | FOS_PATHMUSTEXIST | FOS_NOCHANGEDIR);

                if (!string.IsNullOrEmpty(title))
                {
                    dialog.SetTitle(title);
                }

                if (!string.IsNullOrEmpty(initialFolder) && Directory.Exists(initialFolder))
                {
                    Guid shellItemGuid = typeof(IShellItem).GUID;
                    IShellItem folderItem;
                    if (SHCreateItemFromParsingName(initialFolder, IntPtr.Zero, ref shellItemGuid, out folderItem) == 0 && folderItem != null)
                    {
                        try
                        {
                            dialog.SetFolder(folderItem);
                        }
                        finally
                        {
                            Marshal.ReleaseComObject(folderItem);
                        }
                    }
                }

                int hr = dialog.Show(ownerHwnd);
                if (hr == HRESULT_CANCELLED)
                {
                    cancelled = true;
                    return null;
                }
                if (hr != 0)
                {
                    Marshal.ThrowExceptionForHR(hr);
                }

                IShellItem resultItem;
                dialog.GetResult(out resultItem);
                if (resultItem != null)
                {
                    try
                    {
                        string path;
                        resultItem.GetDisplayName(SIGDN_FILESYSPATH, out path);
                        return path;
                    }
                    finally
                    {
                        Marshal.ReleaseComObject(resultItem);
                    }
                }
                return null;
            }
            finally
            {
                Marshal.ReleaseComObject(dialog);
            }
        }

        [ComImport]
        [Guid("DC1C5A9C-E88A-4dde-A5A1-60F82A20AEF7")]
        private class FileOpenDialogRCW
        {
        }

        [ComImport]
        [Guid("42f85136-db7e-439c-85f1-e4075d135fc8")]
        [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
        private interface IFileDialog
        {
            [PreserveSig]
            int Show([In] IntPtr parent);
            void SetFileTypes([In] uint cFileTypes, [In] IntPtr rgFilterSpec);
            void SetFileTypeIndex([In] uint iFileType);
            void GetFileTypeIndex(out uint piFileType);
            void Advise([In] IntPtr pfde, out uint pdwCookie);
            void Unadvise([In] uint dwCookie);
            void SetOptions([In] uint fos);
            void GetOptions(out uint pfos);
            void SetDefaultFolder([In, MarshalAs(UnmanagedType.Interface)] IShellItem psi);
            void SetFolder([In, MarshalAs(UnmanagedType.Interface)] IShellItem psi);
            void GetFolder([MarshalAs(UnmanagedType.Interface)] out IShellItem ppsi);
            void GetCurrentSelection([MarshalAs(UnmanagedType.Interface)] out IShellItem ppsi);
            void SetFileName([In, MarshalAs(UnmanagedType.LPWStr)] string pszName);
            void GetFileName([MarshalAs(UnmanagedType.LPWStr)] out string pszName);
            void SetTitle([In, MarshalAs(UnmanagedType.LPWStr)] string pszTitle);
            void SetOkButtonLabel([In, MarshalAs(UnmanagedType.LPWStr)] string pszText);
            void SetFileNameLabel([In, MarshalAs(UnmanagedType.LPWStr)] string pszLabel);
            void GetResult([MarshalAs(UnmanagedType.Interface)] out IShellItem ppsi);
            void AddPlace([In, MarshalAs(UnmanagedType.Interface)] IShellItem psi, int fdap);
            void SetDefaultExtension([In, MarshalAs(UnmanagedType.LPWStr)] string pszDefaultExtension);
            void Close([MarshalAs(UnmanagedType.Error)] int hr);
            void SetClientGuid([In] ref Guid guid);
            void ClearClientData();
            void SetFilter([MarshalAs(UnmanagedType.Interface)] IntPtr pFilter);
        }

        [ComImport]
        [Guid("43826D1E-E718-42EE-BC55-A1E261C37BFE")]
        [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
        private interface IShellItem
        {
            void BindToHandler([In] IntPtr pbc, [In] ref Guid bhid, [In] ref Guid riid, out IntPtr ppv);
            void GetParent([MarshalAs(UnmanagedType.Interface)] out IShellItem ppsi);
            void GetDisplayName([In] uint sigdnName, [MarshalAs(UnmanagedType.LPWStr)] out string ppszName);
            void GetAttributes([In] uint sfgaoMask, out uint psfgaoAttribs);
            void Compare([In, MarshalAs(UnmanagedType.Interface)] IShellItem psi, [In] uint hint, out int piOrder);
        }

        private sealed class Win32WindowWrapper : IWin32Window
        {
            private readonly IntPtr _hwnd;
            public Win32WindowWrapper(IntPtr hwnd) { _hwnd = hwnd; }
            public IntPtr Handle { get { return _hwnd; } }
        }

        #endregion
    }
}
