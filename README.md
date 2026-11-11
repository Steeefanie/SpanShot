# SpanShot — 轻量高精度跨平台（Windows / macOS）横纵长截图工具

**SpanShot** 是一款极轻量级、零第三方依赖的原生截图与横纵长图拼接工具，支持**普通区域截图**、**纵向长截图（Vertical Scrolling Capture）**与**横向长截图（Horizontal Scrolling Capture）**。

---

## 📦 下载安装（GitHub Releases）

请直接前往 [**GitHub Releases 页面**](https://github.com/Steeefanie/SpanShot/releases/latest) 下载对应系统的安装包：

- **Windows 版**：下载 **`SpanShot_<版本号>.exe`**（单文件绿色免安装，内置多尺寸高清图标，双击即用）
- **macOS 版（Apple 芯片 M1/M2/M3/M4 推荐）**：下载 **`SpanShot_<版本号>_AppleSilicon.dmg`**（拖入 Applications 即可使用）
- **macOS 版（Universal 通用版，支持 Apple 芯片 + Intel）**：下载 **`SpanShot_<版本号>_Universal.dmg`**（拖入 Applications 即可使用）

---

## ✨ 核心特性

1. **高精度横纵双轴拼接引擎 (`StitchEngine`)**
   - **超宽冻结列与固定表头剔除**：支持高达 **68% 屏宽**的左侧冻结列（如 Element UI / Ant Design / 飞书 / Excel 宽表）与底部/右侧滚动条自动剔除（两遍扫描算法，抗悬停高亮干扰）。
   - **交叉轴有效行带隔离 (`BuildActiveCrossBinMask`)**：自动隔离滚动的表格行与静态顶部工具栏（如“+添加行/删除”）、底部静态合计行（“合计:”）及反向移动的水平滚动条滑块。
   - **双向对称亚像素插值 + 双频带校验**：针对 125%/150% DPI 缩放及 Retina / 浏览器平滑滚动的亚像素偏移做双向半步插值匹配，并通过上下双频带（表头行 + 数据行）独立验证与严重失配惩罚，杜绝连续相同输入框（如多个 `[ 请输入 ]` / `0.00` 列）产生重复拼接或错位拼接。
   - **最小能量接缝切割 + 快速滚动桥接**：接缝自动避开文字笔画与右侧内嵌竖向滚动条，支持跨单屏重叠区的快速滚动过渡帧桥接恢复。
2. **极简工作流与系统集成**
   - **自动匹配系统深浅色模式**：界面底色与层级实时跟随系统深浅色外观自动切换（无需手动配置）。
   - 主面板支持 **常驻后台**（最小化或关闭时彻底隐藏至系统托盘/状态栏，不占用任务栏）、**开机自启**（开机静默驻留托盘并即时响应快捷键）、**快捷截图**（完成后直接复制到剪贴板，不打开预览窗）以及 **自动保存**（开启前自动校验目录可写权限，支持一键打开保存目录，每次截图默认防重名保存 PNG）。
   - **在线检查与一键更新**：面板底部支持一键检测 GitHub Releases 最新版本，发现更新时可在应用内直接拉取最新安装包、自动完成替换与重启升级。
   - 单实例唤醒与托盘快捷菜单：已在后台运行时再次打开会自动唤出主窗口，支持单击托盘唤出及右键快捷切换各项配置。
   - 选区悬浮栏支持一键切换 **纵向长截 / 横向长截**，完成后在预览窗支持 **矩形/箭头/画笔标注、裁剪、撤销、钉在桌面（置顶贴图）、另存为、复制**。

---

## 📁 仓库结构

- **`src/`、`assets/` & `build.ps1`（Windows 端源码与多分辨率剪刀图标）**：基于 C# + Win32 原生 API，使用系统内置 `csc.exe` 编译打包单文件。
- **`macos/`（macOS 端源码）**：基于 Swift + AppKit + CoreGraphics，使用 `macos/build_dmg.sh` 编译打包。

---

## 🛠 本地编译与自动化自测

### Windows (`SpanShot.exe`)
```powershell
powershell -ExecutionPolicy Bypass -File .\build.ps1
.\SpanShot.exe --self-test | Out-Host
```

### macOS (`SpanShot.dmg`)
```bash
chmod +x ./macos/build_dmg.sh
./macos/build_dmg.sh
```
