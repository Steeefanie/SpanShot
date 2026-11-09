# SpanShot — 轻量高精度跨平台（Windows / macOS）横纵长截图工具

**SpanShot** 是一款极轻量级、零第三方依赖的截图与横纵长图拼接工具，支持**普通区域截图**、**纵向长截图（Vertical Scrolling Capture）**与**横向长截图（Horizontal Scrolling Capture）**。

---

## 📁 仓库结构（单主分支双端共建）

- **`src/` & `build.ps1`（Windows 端）**：基于 C# + Win32 原生 API，使用系统内置 `csc.exe` 一键编译出单文件 `SpanShot.exe`（~96 KB）。
- **`macos/`（macOS 端）**：基于 Swift + AppKit + CoreGraphics，使用 `macos/build_dmg.sh` 一键编译打包出 `SpanShot.app` 与 `SpanShot.dmg`。

---

## ✨ 核心特性

1. **高精度横纵双轴拼接引擎 (`StitchEngine`)**
   - **超宽冻结列与固定表头剔除**：支持高达 **68% 屏宽**的左侧冻结列（如 Element UI / Ant Design / 飞书 / Excel 宽表）与底部/右侧滚动条自动剔除（两遍扫描算法，抗悬停高亮干扰）。
   - **交叉轴有效行带隔离 (`BuildActiveCrossBinMask`)**：自动隔离滚动的表格行与静态顶部工具栏（如“+添加行/删除”）、底部静态合计行（“合计:”）及反向移动的水平滚动条滑块。
   - **双向对称亚像素插值 + 双频带校验**：针对 125%/150% DPI 缩放及 Retina / 浏览器平滑滚动的亚像素偏移做双向半步插值匹配，并通过上下双频带（表头行 + 数据行）独立验证与严重失配惩罚，杜绝连续相同输入框（如多个 `[ 请输入 ]` / `0.00` 列）产生重复拼接或错位拼接。
   - **最小能量接缝切割 + 快速滚动桥接**：接缝自动避开文字笔画与右侧内嵌竖向滚动条，支持跨单屏重叠区的快速滚动过渡帧桥接恢复。
2. **极简工作流**
   - 主面板支持 **常驻后台**（最小化至托盘/状态栏）与 **快捷截图**（松手即复制到剪贴板，不弹窗）。
   - 选区悬浮栏支持一键切换 **纵向长截 / 横向长截**，完成后在预览窗支持 **矩形/画笔标注、撤销、钉在桌面（置顶贴图）、保存 PNG、复制**。

---

## 🛠 编译与自动化自测

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
