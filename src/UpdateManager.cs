using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Globalization;
using System.IO;
using System.Net;
using System.Reflection;
using System.Text;
using System.Threading;
using System.Windows.Forms;
using Microsoft.Win32;

namespace SpanShot
{
    internal sealed class ReleaseInfo
    {
        public string TagName;
        public string NormalizedVersion;
        public string HtmlUrl;
        public string Body;
        public string WindowsAssetName;
        public string WindowsDownloadUrl;
        public long WindowsAssetSize;
        public bool IsNewer;
    }

    internal static class UpdateManager
    {
        public const string RepoLatestApiUrl = "https://api.github.com/repos/Steeefanie/SpanShot/releases/latest";
        public const string RepoReleasesPageUrl = "https://github.com/Steeefanie/SpanShot/releases/latest";

        public static string CurrentVersion
        {
            get
            {
                try
                {
                    Assembly asm = Assembly.GetExecutingAssembly();
                    object[] attrs = asm.GetCustomAttributes(typeof(AssemblyInformationalVersionAttribute), false);
                    if (attrs != null && attrs.Length > 0)
                    {
                        string infoVer = ((AssemblyInformationalVersionAttribute)attrs[0]).InformationalVersion;
                        if (!string.IsNullOrEmpty(infoVer)) return NormalizeVersionString(infoVer);
                    }
                    Version v = asm.GetName().Version;
                    if (v != null)
                    {
                        return string.Format("{0}.{1}.{2}", v.Major, v.Minor, Math.Max(0, v.Build));
                    }
                }
                catch { }
                return "1.1.0";
            }
        }

        public static void CleanupOldBinaryOnStartup()
        {
            try
            {
                string oldFile = Application.ExecutablePath + ".old";
                if (File.Exists(oldFile))
                {
                    File.Delete(oldFile);
                }
            }
            catch { }
        }

        public static bool CheckLatestRelease(out ReleaseInfo releaseInfo, out string errorMessage)
        {
            return CheckLatestReleaseAgainstVersion(CurrentVersion, out releaseInfo, out errorMessage);
        }

        public static bool CheckLatestReleaseAgainstVersion(string localVersion, out ReleaseInfo releaseInfo, out string errorMessage)
        {
            releaseInfo = null;
            errorMessage = null;

            try
            {
                EnsureTls12();

                HttpWebRequest req = (HttpWebRequest)WebRequest.Create(RepoLatestApiUrl);
                req.Method = "GET";
                req.UserAgent = "SpanShot-Updater/" + CurrentVersion;
                req.Accept = "application/vnd.github+json";
                req.Timeout = 12000;
                req.ReadWriteTimeout = 12000;
                req.Proxy = WebRequest.DefaultWebProxy;
                if (req.Proxy != null)
                {
                    req.Proxy.Credentials = CredentialCache.DefaultCredentials;
                }

                string json;
                using (HttpWebResponse resp = (HttpWebResponse)req.GetResponse())
                using (Stream stream = resp.GetResponseStream())
                using (StreamReader reader = new StreamReader(stream, Encoding.UTF8))
                {
                    json = reader.ReadToEnd();
                }

                if (string.IsNullOrEmpty(json))
                {
                    errorMessage = "GitHub 响应为空，点击重试";
                    return false;
                }

                string tagName = ExtractTopLevelJsonString(json, "tag_name");
                if (string.IsNullOrEmpty(tagName))
                {
                    errorMessage = "暂未找到已发布版本";
                    return false;
                }

                string htmlUrl = ExtractTopLevelJsonString(json, "html_url");
                if (string.IsNullOrEmpty(htmlUrl)) htmlUrl = RepoReleasesPageUrl;
                string body = ExtractTopLevelJsonString(json, "body") ?? string.Empty;

                string winName = null;
                string winUrl = null;
                long winSize = 0;

                List<string> assetObjects = ExtractJsonArrayObjects(json, "assets");
                for (int i = 0; i < assetObjects.Count; i++)
                {
                    string obj = assetObjects[i];
                    string name = ExtractTopLevelJsonString(obj, "name");
                    string dlUrl = ExtractTopLevelJsonString(obj, "browser_download_url");
                    if (!string.IsNullOrEmpty(name) &&
                        !string.IsNullOrEmpty(dlUrl) &&
                        name.EndsWith(".exe", StringComparison.OrdinalIgnoreCase))
                    {
                        winName = name;
                        winUrl = dlUrl;
                        winSize = ExtractTopLevelJsonLong(obj, "size");
                        break;
                    }
                }

                string normRemote = NormalizeVersionString(tagName);
                string normLocal = NormalizeVersionString(localVersion);

                releaseInfo = new ReleaseInfo
                {
                    TagName = tagName,
                    NormalizedVersion = normRemote,
                    HtmlUrl = htmlUrl,
                    Body = body,
                    WindowsAssetName = winName,
                    WindowsDownloadUrl = winUrl,
                    WindowsAssetSize = winSize,
                    IsNewer = CompareSemanticVersions(normRemote, normLocal) > 0
                };
                return true;
            }
            catch (WebException wex)
            {
                // Unauthenticated GitHub REST API is limited to 60 requests/hr per shared IP.
                // Fall back to zero-rate-limit GitHub Releases 302 redirect resolution.
                if (TryCheckViaHtmlRedirect(localVersion, out releaseInfo))
                {
                    errorMessage = null;
                    return true;
                }

                HttpWebResponse httpResp = wex.Response as HttpWebResponse;
                if (httpResp != null && httpResp.StatusCode == HttpStatusCode.Forbidden)
                {
                    errorMessage = "请求频率受限，请稍后重试";
                }
                else
                {
                    errorMessage = "连接 GitHub 失败，点击重试";
                }
                return false;
            }
            catch
            {
                if (TryCheckViaHtmlRedirect(localVersion, out releaseInfo))
                {
                    errorMessage = null;
                    return true;
                }
                errorMessage = "检查更新异常，点击重试";
                return false;
            }
        }

        private static bool TryCheckViaHtmlRedirect(string localVersion, out ReleaseInfo releaseInfo)
        {
            releaseInfo = null;
            try
            {
                EnsureTls12();

                string tagName = ResolveLatestTagViaRedirect(false);
                if (string.IsNullOrEmpty(tagName))
                {
                    tagName = ResolveLatestTagViaRedirect(true);
                }
                if (string.IsNullOrEmpty(tagName))
                {
                    return false;
                }

                string normRemote = NormalizeVersionString(tagName);
                string normLocal = NormalizeVersionString(localVersion);
                bool isNewer = CompareSemanticVersions(normRemote, normLocal) > 0;

                string htmlUrl = "https://github.com/Steeefanie/SpanShot/releases/tag/" + tagName;
                string winName = string.Format("SpanShot_v{0}.exe", normRemote);
                string winUrl = string.Format("https://github.com/Steeefanie/SpanShot/releases/download/{0}/{1}", tagName, winName);

                if (isNewer && !ProbeAssetExists(winUrl))
                {
                    string legacyUrl = string.Format("https://github.com/Steeefanie/SpanShot/releases/download/{0}/SpanShot.exe", tagName);
                    if (ProbeAssetExists(legacyUrl))
                    {
                        winName = "SpanShot.exe";
                        winUrl = legacyUrl;
                    }
                    else
                    {
                        winName = null;
                        winUrl = null;
                    }
                }

                releaseInfo = new ReleaseInfo
                {
                    TagName = tagName,
                    NormalizedVersion = normRemote,
                    HtmlUrl = htmlUrl,
                    Body = string.Empty,
                    WindowsAssetName = winName,
                    WindowsDownloadUrl = winUrl,
                    WindowsAssetSize = 0,
                    IsNewer = isNewer
                };
                return true;
            }
            catch
            {
                return false;
            }
        }

        private static string ResolveLatestTagViaRedirect(bool followRedirect)
        {
            try
            {
                HttpWebRequest req = (HttpWebRequest)WebRequest.Create(RepoReleasesPageUrl);
                req.Method = followRedirect ? "HEAD" : "GET";
                req.UserAgent = "SpanShot-Updater/" + CurrentVersion;
                req.AllowAutoRedirect = followRedirect;
                req.Timeout = 12000;
                req.ReadWriteTimeout = 12000;
                req.Proxy = WebRequest.DefaultWebProxy;
                if (req.Proxy != null)
                {
                    req.Proxy.Credentials = CredentialCache.DefaultCredentials;
                }

                using (HttpWebResponse resp = (HttpWebResponse)req.GetResponse())
                {
                    string loc = resp.Headers["Location"];
                    if (!string.IsNullOrEmpty(loc))
                    {
                        string t = ExtractTagFromReleaseUrl(loc);
                        if (!string.IsNullOrEmpty(t)) return t;
                    }
                    if (resp.ResponseUri != null)
                    {
                        return ExtractTagFromReleaseUrl(resp.ResponseUri.AbsoluteUri);
                    }
                }
            }
            catch (WebException wex)
            {
                HttpWebResponse httpResp = wex.Response as HttpWebResponse;
                if (httpResp != null)
                {
                    string loc = httpResp.Headers["Location"];
                    if (!string.IsNullOrEmpty(loc))
                    {
                        string t = ExtractTagFromReleaseUrl(loc);
                        if (!string.IsNullOrEmpty(t)) return t;
                    }
                    if (httpResp.ResponseUri != null)
                    {
                        return ExtractTagFromReleaseUrl(httpResp.ResponseUri.AbsoluteUri);
                    }
                }
            }
            catch { }
            return null;
        }

        private static string ExtractTagFromReleaseUrl(string url)
        {
            if (string.IsNullOrEmpty(url)) return null;
            const string marker = "/releases/tag/";
            int idx = url.IndexOf(marker, StringComparison.OrdinalIgnoreCase);
            if (idx < 0) return null;

            string tail = url.Substring(idx + marker.Length);
            int qIdx = tail.IndexOfAny(new char[] { '?', '#', '/' });
            if (qIdx >= 0) tail = tail.Substring(0, qIdx);
            tail = Uri.UnescapeDataString(tail).Trim();
            return string.IsNullOrEmpty(tail) ? null : tail;
        }

        private static bool ProbeAssetExists(string assetUrl)
        {
            try
            {
                HttpWebRequest req = (HttpWebRequest)WebRequest.Create(assetUrl);
                req.Method = "HEAD";
                req.UserAgent = "SpanShot-Updater/" + CurrentVersion;
                req.AllowAutoRedirect = false;
                req.Timeout = 8000;
                req.ReadWriteTimeout = 8000;
                req.Proxy = WebRequest.DefaultWebProxy;
                if (req.Proxy != null)
                {
                    req.Proxy.Credentials = CredentialCache.DefaultCredentials;
                }

                using (HttpWebResponse resp = (HttpWebResponse)req.GetResponse())
                {
                    int code = (int)resp.StatusCode;
                    return code == 200 || code == 301 || code == 302 || code == 303 || code == 307 || code == 308;
                }
            }
            catch (WebException wex)
            {
                HttpWebResponse httpResp = wex.Response as HttpWebResponse;
                if (httpResp != null)
                {
                    int code = (int)httpResp.StatusCode;
                    return code == 301 || code == 302 || code == 303 || code == 307 || code == 308;
                }
                return false;
            }
            catch
            {
                return false;
            }
        }

        public static bool DownloadAndApplyUpdate(
            ReleaseInfo info,
            Action<int> onProgressPercent,
            out bool permissionDenied,
            out string errorMessage)
        {
            permissionDenied = false;
            errorMessage = null;
            if (info == null || string.IsNullOrEmpty(info.WindowsDownloadUrl))
            {
                errorMessage = "暂未包含 Windows 安装包";
                return false;
            }

            string currentExe = Application.ExecutablePath;
            string currentDir = Path.GetDirectoryName(currentExe);
            string currentFileName = Path.GetFileName(currentExe);
            if (string.IsNullOrEmpty(currentDir))
            {
                errorMessage = "无法解析当前程序目录";
                return false;
            }

            // Test writability of current app folder before downloading
            string writeErr;
            if (!AppSettings.ValidateWritableFolder(currentDir, out writeErr))
            {
                permissionDenied = true;
                errorMessage = "目录无写入权限，点击前往下载";
                return false;
            }

            string targetExePath = currentExe;
            if (currentFileName.IndexOf("_v", StringComparison.OrdinalIgnoreCase) >= 0 &&
                !string.IsNullOrEmpty(info.WindowsAssetName) &&
                info.WindowsAssetName.EndsWith(".exe", StringComparison.OrdinalIgnoreCase))
            {
                targetExePath = Path.Combine(currentDir, info.WindowsAssetName);
            }

            string downloadTempPath = currentExe + ".download";
            string oldBackupPath = currentExe + ".old";

            try
            {
                if (File.Exists(downloadTempPath)) File.Delete(downloadTempPath);

                EnsureTls12();
                HttpWebRequest req = (HttpWebRequest)WebRequest.Create(info.WindowsDownloadUrl);
                req.Method = "GET";
                req.UserAgent = "SpanShot-Updater/" + CurrentVersion;
                req.AllowAutoRedirect = true;
                req.Timeout = 25000;
                req.ReadWriteTimeout = 25000;
                req.Proxy = WebRequest.DefaultWebProxy;
                if (req.Proxy != null)
                {
                    req.Proxy.Credentials = CredentialCache.DefaultCredentials;
                }

                using (HttpWebResponse resp = (HttpWebResponse)req.GetResponse())
                using (Stream netStream = resp.GetResponseStream())
                using (FileStream fs = new FileStream(downloadTempPath, FileMode.Create, FileAccess.Write, FileShare.None))
                {
                    long totalBytes = resp.ContentLength > 0 ? resp.ContentLength : info.WindowsAssetSize;
                    byte[] buffer = new byte[16384];
                    long received = 0;
                    int lastPct = -1;
                    int read;

                    while ((read = netStream.Read(buffer, 0, buffer.Length)) > 0)
                    {
                        fs.Write(buffer, 0, read);
                        received += read;
                        if (totalBytes > 0 && onProgressPercent != null)
                        {
                            int pct = (int)Math.Min(100L, (received * 100L) / totalBytes);
                            if (pct != lastPct)
                            {
                                lastPct = pct;
                                onProgressPercent(pct);
                            }
                        }
                    }
                    fs.Flush();
                }

                // Verify downloaded file is a valid non-corrupt Win32 PE executable ("MZ")
                FileInfo fi = new FileInfo(downloadTempPath);
                if (!fi.Exists || fi.Length < 32768)
                {
                    if (File.Exists(downloadTempPath)) File.Delete(downloadTempPath);
                    errorMessage = "下载的安装包不完整，已取消替换";
                    return false;
                }

                byte[] header = new byte[2];
                using (FileStream checkFs = new FileStream(downloadTempPath, FileMode.Open, FileAccess.Read, FileShare.Read))
                {
                    if (checkFs.Read(header, 0, 2) != 2 || header[0] != 0x4D || header[1] != 0x5A)
                    {
                        errorMessage = "下载的文件不是有效的可执行程序，已取消替换";
                        return false;
                    }
                }

                // Atomic swap: Windows allows moving a currently running .exe to .old in the same volume
                if (File.Exists(oldBackupPath))
                {
                    try { File.Delete(oldBackupPath); } catch { }
                }

                File.Move(currentExe, oldBackupPath);
                try
                {
                    if (File.Exists(targetExePath)) File.Delete(targetExePath);
                    File.Move(downloadTempPath, targetExePath);
                }
                catch
                {
                    // Rollback if moving new file failed
                    try { if (!File.Exists(currentExe) && File.Exists(oldBackupPath)) File.Move(oldBackupPath, currentExe); } catch { }
                    throw;
                }

                // Update Windows Startup registry entry if exe path changed (e.g. SpanShot_v1.1.0 -> SpanShot_v1.2.0)
                if (!string.Equals(currentExe, targetExePath, StringComparison.OrdinalIgnoreCase) &&
                    AppSettings.IsAutoStartEnabled())
                {
                    try
                    {
                        using (RegistryKey rk = Registry.CurrentUser.OpenSubKey(@"Software\Microsoft\Windows\CurrentVersion\Run", true))
                        {
                            if (rk != null)
                            {
                                rk.SetValue("SpanShot", string.Format("\"{0}\" --autostart", targetExePath), RegistryValueKind.String);
                            }
                        }
                    }
                    catch { }
                }

                // Launch new binary and schedule background cleanup of .old file after current process exits
                Process.Start(new ProcessStartInfo
                {
                    FileName = targetExePath,
                    WorkingDirectory = currentDir,
                    UseShellExecute = true
                });

                try
                {
                    Process.Start(new ProcessStartInfo
                    {
                        FileName = "cmd.exe",
                        Arguments = string.Format("/c ping 127.0.0.1 -n 3 > nul & del /f /q \"{0}\"", oldBackupPath),
                        CreateNoWindow = true,
                        WindowStyle = ProcessWindowStyle.Hidden,
                        UseShellExecute = false
                    });
                }
                catch { }

                return true;
            }
            catch
            {
                try { if (File.Exists(downloadTempPath)) File.Delete(downloadTempPath); } catch { }
                errorMessage = "拉取更新失败，点击重试";
                return false;
            }
        }

        private static void EnsureTls12()
        {
            try
            {
                // 3072 = Tls12, 768 = Tls11
                ServicePointManager.SecurityProtocol = (SecurityProtocolType)3072 | (SecurityProtocolType)768 | SecurityProtocolType.Tls;
            }
            catch { }
        }

        public static string NormalizeVersionString(string raw)
        {
            if (string.IsNullOrEmpty(raw)) return "0.0.0";
            string s = raw.Trim();
            if (s.StartsWith("v", StringComparison.OrdinalIgnoreCase))
            {
                s = s.Substring(1);
            }
            int dashIdx = s.IndexOf('-');
            if (dashIdx > 0) s = s.Substring(0, dashIdx);
            int plusIdx = s.IndexOf('+');
            if (plusIdx > 0) s = s.Substring(0, plusIdx);
            return s.Trim();
        }

        public static int CompareSemanticVersions(string a, string b)
        {
            int[] pa = ParseVersionParts(a);
            int[] pb = ParseVersionParts(b);
            int len = Math.Max(pa.Length, pb.Length);
            for (int i = 0; i < len; i++)
            {
                int va = i < pa.Length ? pa[i] : 0;
                int vb = i < pb.Length ? pb[i] : 0;
                if (va != vb) return va.CompareTo(vb);
            }
            return 0;
        }

        private static int[] ParseVersionParts(string v)
        {
            string norm = NormalizeVersionString(v);
            string[] tokens = norm.Split('.');
            int[] result = new int[tokens.Length];
            for (int i = 0; i < tokens.Length; i++)
            {
                int n;
                if (int.TryParse(tokens[i], out n)) result[i] = n;
            }
            return result;
        }

        #region Minimal Lexer-Safe JSON Helpers (Zero External Dependencies)

        private static string ExtractTopLevelJsonString(string jsonObject, string propertyName)
        {
            int valStart = FindTopLevelPropertyValueStart(jsonObject, propertyName);
            if (valStart < 0 || valStart >= jsonObject.Length || jsonObject[valStart] != '"')
                return null;

            int endQuote;
            return ReadJsonStringLiteral(jsonObject, valStart, out endQuote);
        }

        private static long ExtractTopLevelJsonLong(string jsonObject, string propertyName)
        {
            int valStart = FindTopLevelPropertyValueStart(jsonObject, propertyName);
            if (valStart < 0 || valStart >= jsonObject.Length) return 0;

            int i = valStart;
            while (i < jsonObject.Length && (char.IsDigit(jsonObject[i]) || jsonObject[i] == '-'))
            {
                i++;
            }
            long parsed;
            if (long.TryParse(jsonObject.Substring(valStart, i - valStart), out parsed))
                return parsed;
            return 0;
        }

        private static List<string> ExtractJsonArrayObjects(string jsonObject, string arrayPropertyName)
        {
            List<string> items = new List<string>();
            int valStart = FindTopLevelPropertyValueStart(jsonObject, arrayPropertyName);
            if (valStart < 0 || valStart >= jsonObject.Length || jsonObject[valStart] != '[')
                return items;

            int depth = 0;
            int objStart = -1;
            int i = valStart + 1;
            while (i < jsonObject.Length)
            {
                char c = jsonObject[i];
                if (c == '"')
                {
                    int endQ;
                    ReadJsonStringLiteral(jsonObject, i, out endQ);
                    i = endQ + 1;
                    continue;
                }
                if (c == '{')
                {
                    if (depth == 0) objStart = i;
                    depth++;
                }
                else if (c == '}')
                {
                    depth--;
                    if (depth == 0 && objStart >= 0)
                    {
                        items.Add(jsonObject.Substring(objStart, i - objStart + 1));
                        objStart = -1;
                    }
                }
                else if (c == ']' && depth == 0)
                {
                    break;
                }
                i++;
            }
            return items;
        }

        private static int FindTopLevelPropertyValueStart(string jsonObject, string targetKey)
        {
            if (string.IsNullOrEmpty(jsonObject)) return -1;
            int i = 0;
            while (i < jsonObject.Length && char.IsWhiteSpace(jsonObject[i])) i++;
            if (i >= jsonObject.Length || jsonObject[i] != '{') return -1;

            int depth = 0;
            while (i < jsonObject.Length)
            {
                char c = jsonObject[i];
                if (c == '"')
                {
                    int endQ;
                    string strVal = ReadJsonStringLiteral(jsonObject, i, out endQ);
                    i = endQ + 1;

                    if (depth == 1)
                    {
                        int k = i;
                        while (k < jsonObject.Length && char.IsWhiteSpace(jsonObject[k])) k++;
                        if (k < jsonObject.Length && jsonObject[k] == ':')
                        {
                            k++;
                            while (k < jsonObject.Length && char.IsWhiteSpace(jsonObject[k])) k++;
                            if (string.Equals(strVal, targetKey, StringComparison.Ordinal))
                            {
                                return k;
                            }
                            i = k;
                            continue;
                        }
                    }
                    continue;
                }

                if (c == '{' || c == '[') depth++;
                else if (c == '}' || c == ']') depth--;
                i++;
            }
            return -1;
        }

        private static string ReadJsonStringLiteral(string s, int openQuoteIdx, out int closeQuoteIdx)
        {
            StringBuilder sb = new StringBuilder();
            int i = openQuoteIdx + 1;
            while (i < s.Length)
            {
                char c = s[i];
                if (c == '"')
                {
                    closeQuoteIdx = i;
                    return sb.ToString();
                }
                if (c == '\\' && i + 1 < s.Length)
                {
                    char esc = s[i + 1];
                    switch (esc)
                    {
                        case '"': sb.Append('"'); i += 2; break;
                        case '\\': sb.Append('\\'); i += 2; break;
                        case '/': sb.Append('/'); i += 2; break;
                        case 'b': sb.Append('\b'); i += 2; break;
                        case 'f': sb.Append('\f'); i += 2; break;
                        case 'n': sb.Append('\n'); i += 2; break;
                        case 'r': sb.Append('\r'); i += 2; break;
                        case 't': sb.Append('\t'); i += 2; break;
                        case 'u':
                            if (i + 5 < s.Length)
                            {
                                int code;
                                if (int.TryParse(s.Substring(i + 2, 4), NumberStyles.HexNumber, CultureInfo.InvariantCulture, out code))
                                {
                                    sb.Append((char)code);
                                    i += 6;
                                    break;
                                }
                            }
                            sb.Append(esc);
                            i += 2;
                            break;
                        default:
                            sb.Append(esc);
                            i += 2;
                            break;
                    }
                    continue;
                }
                sb.Append(c);
                i++;
            }
            closeQuoteIdx = s.Length - 1;
            return sb.ToString();
        }

        #endregion
    }
}
