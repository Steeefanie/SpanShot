import AppKit
import Carbon
import Foundation

/// Minimalist adaptive main window + NSStatusItem menu bar agent (1:1 port of src/MainForm.cs v1.1.0, enhanced for macOS).
public final class MainForm: NSWindow {
    public private(set) static weak var shared: MainForm?

    private static let prefKeyHotkeyCode = "SpanShot.HotkeyKeyCode"
    private static let prefKeyHotkeyMods = "SpanShot.HotkeyCarbonMods"
    private static let prefKeyHotkeyLabel = "SpanShot.HotkeyDisplay"

    fileprivate var statusItem: NSStatusItem?
    fileprivate var menuCaptureItem: NSMenuItem?
    fileprivate var menuQuickCopyItem: NSMenuItem?
    fileprivate var menuAutoSaveItem: NSMenuItem?
    fileprivate var menuAutoStartItem: NSMenuItem?
    fileprivate var menuKeepAliveItem: NSMenuItem?
    fileprivate var menuHideStatusBarItem: NSMenuItem?

    fileprivate var isCapturing = false
    fileprivate var captureWasNormalVisible = false
    fileprivate var keepInBackground = true
    fileprivate var hideStatusBarIcon = false
    fileprivate var autoStart = false
    fileprivate var quickCopyOnly = false
    fileprivate var autoSave = false
    fileprivate var autoSaveDir = ""

    fileprivate var checkingUpdate = false
    fileprivate var pullingUpdate = false
    fileprivate var pullProgress = 0
    fileprivate var availableUpdate: UpdateCheckResult?

    fileprivate var noticeText = ""
    fileprivate var noticeColor: NSColor = UiTheme.weChatGreen
    private var noticeTimer: Timer?
    private var themeObserver: NSObjectProtocol?

    fileprivate var hotkeyKeyCode: UInt32 = UInt32(kVK_ANSI_A)
    fileprivate var hotkeyCarbonMods: UInt32 = UInt32(cmdKey | shiftKey)
    fileprivate var hotkeyDisplay: String = "⌘⇧A"
    fileprivate var isRecordingHotkey = false

    fileprivate var draggingWindow = false
    fileprivate var dragStartScreenPt: NSPoint = .zero
    fileprivate var winStartOrigin: NSPoint = .zero
    fileprivate var mousePos: NSPoint = NSPoint(x: -100, y: -100)

    fileprivate let brandIconImage: NSImage

    // Layout rects (318 x 340 logical points, 1:1 with src/MainForm.cs + macOS status bar toggle)
    fileprivate var headerRect: NSRect = .zero
    fileprivate var btnMinimizeRect: NSRect = .zero
    fileprivate var btnCloseRect: NSRect = .zero
    fileprivate var btnCaptureRect: NSRect = .zero
    fileprivate var btnHotkeyBadgeRect: NSRect = .zero
    fileprivate var chkKeepAliveRect: NSRect = .zero
    fileprivate var chkHideStatusBarRect: NSRect = .zero
    fileprivate var chkAutoStartRect: NSRect = .zero
    fileprivate var chkQuickCopyRect: NSRect = .zero
    fileprivate var chkAutoSaveRect: NSRect = .zero
    fileprivate var btnOpenSaveDirRect: NSRect = .zero
    fileprivate var btnChangeSaveDirRect: NSRect = .zero
    fileprivate var lblAutoSavePathRect: NSRect = .zero
    fileprivate var bottomStatusRowRect: NSRect = .zero
    fileprivate var lnkUpdateActionRect: NSRect = .zero
    fileprivate var lnkIgnoreUpdateRect: NSRect = .zero

    private var activeSelector: RegionSelectorForm?
    private var activeScrollSession: ScrollCaptureSessionForm?
    private var hotKeyRefs: [EventHotKeyRef?] = []
    private var eventHandlerInstalled = false

    private final class MainPanelView: NSView {
        weak var owner: MainForm?

        override var isFlipped: Bool { true }
        override var acceptsFirstResponder: Bool { true }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            for area in trackingAreas { removeTrackingArea(area) }
            addTrackingArea(NSTrackingArea(
                rect: bounds,
                options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                owner: self,
                userInfo: nil
            ))
        }

        override func draw(_ dirtyRect: NSRect) {
            guard let owner = owner else { return }

            NSColor.clear.setFill()
            bounds.fill()

            UiTheme.fillAndStrokeRoundedRect(
                bounds,
                radius: 15,
                fillColor: UiTheme.bgDark,
                strokeColor: UiTheme.borderSubtle.withAlphaComponent(UiTheme.isDarkMode ? 0.65 : 0.35),
                lineWidth: 0.5
            )

            // 1. Brand icon + Title + Minimize & Close buttons
            let iconRect = NSRect(x: 16, y: 12, width: 20, height: 20)
            NSGraphicsContext.current?.imageInterpolation = .high
            owner.brandIconImage.draw(
                in: iconRect,
                from: .zero,
                operation: .sourceOver,
                fraction: 1.0,
                respectFlipped: true,
                hints: nil
            )

            UiTheme.drawCenteredText(
                "SpanShot",
                in: NSRect(x: 42, y: 6, width: 150, height: 32),
                font: UiTheme.fontPx(15, bold: true),
                color: UiTheme.textPrimary,
                alignment: .left
            )

            let minHovered = owner.btnMinimizeRect.contains(owner.mousePos)
            UiTheme.drawPillButton(
                rect: owner.btnMinimizeRect,
                text: "—",
                baseColor: minHovered ? UiTheme.bgCardHover : .clear,
                hovered: false,
                radius: 4,
                font: UiTheme.fontPx(12),
                textColor: minHovered ? UiTheme.textPrimary : UiTheme.textSecondary
            )

            let closeHovered = owner.btnCloseRect.contains(owner.mousePos)
            UiTheme.drawPillButton(
                rect: owner.btnCloseRect,
                text: "✕",
                baseColor: closeHovered ? UiTheme.accentRed : .clear,
                hovered: false,
                radius: 4,
                font: UiTheme.fontPx(12),
                textColor: closeHovered ? .white : UiTheme.textSecondary
            )

            // 2. Primary Capture Button
            let badgeHovered = owner.btnHotkeyBadgeRect.contains(owner.mousePos)
            let btnHovered = owner.btnCaptureRect.contains(owner.mousePos) && !badgeHovered
            drawCaptureButton(
                rect: owner.btnCaptureRect,
                badgeRect: owner.btnHotkeyBadgeRect,
                label: "开始截图",
                hotkey: owner.isRecordingHotkey ? "请按键..." : owner.hotkeyDisplay,
                btnHovered: btnHovered,
                badgeHovered: badgeHovered,
                recording: owner.isRecordingHotkey
            )

            // 3. Checkboxes: Keep in Background, Hide Status Bar Icon (macOS), Auto-Start, Quick Copy
            drawCheckboxOption(
                rect: owner.chkKeepAliveRect,
                label: "常驻后台（最小化到托盘）",
                subNote: nil,
                isChecked: owner.keepInBackground,
                hovered: owner.chkKeepAliveRect.contains(owner.mousePos)
            )

            drawCheckboxOption(
                rect: owner.chkHideStatusBarRect,
                label: "隐藏顶部状态栏图标（后台仍常驻运行）",
                subNote: nil,
                isChecked: owner.hideStatusBarIcon,
                hovered: owner.chkHideStatusBarRect.contains(owner.mousePos)
            )

            drawCheckboxOption(
                rect: owner.chkAutoStartRect,
                label: "开机自启",
                subNote: nil,
                isChecked: owner.autoStart,
                hovered: owner.chkAutoStartRect.contains(owner.mousePos)
            )

            drawCheckboxOption(
                rect: owner.chkQuickCopyRect,
                label: "快捷截图",
                subNote: "完成后直接复制到剪贴板，不打开预览窗",
                isChecked: owner.quickCopyOnly,
                hovered: owner.chkQuickCopyRect.contains(owner.mousePos)
            )

            // 4. Auto-Save section with folder action buttons & clickable path
            drawAutoSaveOption(owner: owner)

            // 5. Bottom Status / Inline Notice / Update Check Row
            drawBottomStatusRow(owner: owner)
        }

        private func drawCaptureButton(
            rect: NSRect,
            badgeRect: NSRect,
            label: String,
            hotkey: String,
            btnHovered: Bool,
            badgeHovered: Bool,
            recording: Bool
        ) {
            let bg = btnHovered ? UiTheme.lighten(UiTheme.weChatGreen, delta: 14) : UiTheme.weChatGreen
            UiTheme.fillRoundedRect(rect, radius: 8, color: bg)

            let textRect = NSRect(x: rect.minX + 18, y: rect.minY, width: rect.width - 104, height: rect.height)
            UiTheme.drawCenteredText(label, in: textRect, font: UiTheme.fontPx(15, bold: true), color: .white, alignment: .left)

            let badgeBg: NSColor
            if recording {
                badgeBg = UiTheme.accentOrange
            } else if badgeHovered {
                badgeBg = NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 95 / 255.0)
            } else {
                badgeBg = NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 48 / 255.0)
            }
            if recording || badgeHovered {
                UiTheme.fillAndStrokeRoundedRect(
                    badgeRect,
                    radius: 5,
                    fillColor: badgeBg,
                    strokeColor: recording ? .white : NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.45),
                    lineWidth: 1.0
                )
            } else {
                UiTheme.fillRoundedRect(badgeRect, radius: 5, color: badgeBg)
            }
            UiTheme.drawCenteredText(
                hotkey,
                in: badgeRect,
                font: UiTheme.fontPx(recording ? 11 : 12, bold: recording),
                color: recording ? .black : .white,
                alignment: .center
            )
        }

        private func drawCheckboxOption(rect: NSRect, label: String, subNote: String?, isChecked: Bool, hovered: Bool) {
            let boxSz: CGFloat = 16
            let boxY = rect.minY + 4
            let boxRect = NSRect(x: rect.minX, y: boxY, width: boxSz, height: boxSz)

            drawCheckBoxGlyph(boxRect: boxRect, isChecked: isChecked, hovered: hovered)

            let textX = boxRect.maxX + 8
            let textW = rect.width - boxSz - 8
            let lblRect = NSRect(x: textX, y: rect.minY, width: textW, height: 24)
            let lblColor = (hovered || isChecked) ? UiTheme.textPrimary : UiTheme.textSecondary
            UiTheme.drawCenteredText(label, in: lblRect, font: UiTheme.fontPx(13), color: lblColor, alignment: .left)

            if let note = subNote, !note.isEmpty {
                let noteRect = NSRect(x: textX, y: rect.minY + 22, width: textW, height: 20)
                UiTheme.drawCenteredText(note, in: noteRect, font: UiTheme.fontPx(11), color: UiTheme.textSecondary, alignment: .left)
            }
        }

        private func drawAutoSaveOption(owner: MainForm) {
            let boxSz: CGFloat = 16
            let boxY = owner.chkAutoSaveRect.minY + 4
            let boxRect = NSRect(x: owner.chkAutoSaveRect.minX, y: boxY, width: boxSz, height: boxSz)

            let hasSaveDir = !owner.autoSaveDir.isEmpty
            let dirBtnW: CGFloat = 64
            let dirBtnH: CGFloat = 22
            let dirBtnY = owner.chkAutoSaveRect.minY + 1

            owner.btnChangeSaveDirRect = NSRect(
                x: owner.chkAutoSaveRect.maxX - dirBtnW,
                y: dirBtnY,
                width: dirBtnW,
                height: dirBtnH
            )
            owner.btnOpenSaveDirRect = hasSaveDir
                ? NSRect(
                    x: owner.btnChangeSaveDirRect.minX - 6 - dirBtnW,
                    y: dirBtnY,
                    width: dirBtnW,
                    height: dirBtnH
                )
                : .zero

            let changeHover = owner.btnChangeSaveDirRect.contains(owner.mousePos)
            let openHover = hasSaveDir && owner.btnOpenSaveDirRect.contains(owner.mousePos)
            let pathHover = hasSaveDir && owner.lblAutoSavePathRect.contains(owner.mousePos)
            let mainRowHover = owner.chkAutoSaveRect.contains(owner.mousePos)
                && !changeHover && !openHover && !pathHover
                && owner.mousePos.y <= owner.chkAutoSaveRect.minY + 26

            drawCheckBoxGlyph(boxRect: boxRect, isChecked: owner.autoSave, hovered: mainRowHover)

            let textX = boxRect.maxX + 8
            let rightActionLeft = hasSaveDir ? owner.btnOpenSaveDirRect.minX : owner.btnChangeSaveDirRect.minX
            let titleW = max(60, rightActionLeft - textX - 6)
            let lblRect = NSRect(x: textX, y: owner.chkAutoSaveRect.minY, width: titleW, height: 24)
            let lblColor = (mainRowHover || owner.autoSave) ? UiTheme.textPrimary : UiTheme.textSecondary
            UiTheme.drawCenteredText("自动保存", in: lblRect, font: UiTheme.fontPx(13), color: lblColor, alignment: .left)

            let dirBtnFont = UiTheme.fontPx(11)
            if hasSaveDir {
                drawSmallDirButton(rect: owner.btnOpenSaveDirRect, text: "打开目录", hovered: openHover, font: dirBtnFont)
            }
            drawSmallDirButton(
                rect: owner.btnChangeSaveDirRect,
                text: hasSaveDir ? "更改目录" : "选择目录",
                hovered: changeHover,
                font: dirBtnFont
            )

            let noteY = owner.chkAutoSaveRect.minY + 26
            let noteW = owner.chkAutoSaveRect.width - boxSz - 8
            let noteRect = NSRect(x: textX, y: noteY, width: noteW, height: 20)

            if !hasSaveDir {
                owner.lblAutoSavePathRect = .zero
                UiTheme.drawCenteredText(
                    "未指定目录，开启前需先选择可写文件夹",
                    in: noteRect,
                    font: UiTheme.fontPx(11),
                    color: UiTheme.textSecondary,
                    alignment: .left
                )
            } else {
                owner.lblAutoSavePathRect = noteRect
                let pathLine = "目录 : \(owner.autoSaveDir)"
                let pathColor = pathHover ? UiTheme.weChatGreen : UiTheme.textSecondary
                UiTheme.drawCenteredText(
                    pathLine,
                    in: noteRect,
                    font: UiTheme.fontPx(11),
                    color: pathColor,
                    alignment: .left,
                    lineBreakMode: .byTruncatingMiddle
                )
            }
        }

        private func drawSmallDirButton(rect: NSRect, text: String, hovered: Bool, font: NSFont) {
            let fill = hovered ? UiTheme.bgCardHover : UiTheme.bgCard
            let border = hovered ? UiTheme.weChatGreen : UiTheme.borderSubtle
            let fg = hovered ? UiTheme.textPrimary : UiTheme.textSecondary
            UiTheme.fillAndStrokeRoundedRect(rect, radius: 4, fillColor: fill, strokeColor: border, lineWidth: 1.0)
            UiTheme.drawCenteredText(text, in: rect, font: font, color: fg, alignment: .center)
        }

        private func drawCheckBoxGlyph(boxRect: NSRect, isChecked: Bool, hovered: Bool) {
            if isChecked {
                UiTheme.fillRoundedRect(boxRect, radius: 4, color: UiTheme.weChatGreen)
                NSColor.white.setStroke()
                let checkPath = NSBezierPath()
                checkPath.lineWidth = 1.6
                checkPath.lineCapStyle = .round
                let cx = boxRect.midX
                let cy = boxRect.midY
                checkPath.move(to: NSPoint(x: cx - 4, y: cy))
                checkPath.line(to: NSPoint(x: cx - 1, y: cy + 3))
                checkPath.line(to: NSPoint(x: cx + 4, y: cy - 3))
                checkPath.stroke()
            } else {
                UiTheme.fillAndStrokeRoundedRect(
                    boxRect,
                    radius: 4,
                    fillColor: UiTheme.bgCard,
                    strokeColor: hovered ? UiTheme.weChatGreen : UiTheme.borderSubtle,
                    lineWidth: 1.0
                )
            }
        }

        private func drawBottomStatusRow(owner: MainForm) {
            owner.lnkUpdateActionRect = .zero
            owner.lnkIgnoreUpdateRect = .zero

            if !owner.noticeText.isEmpty && !owner.checkingUpdate && !owner.pullingUpdate {
                UiTheme.drawCenteredText(
                    owner.noticeText,
                    in: owner.bottomStatusRowRect,
                    font: UiTheme.fontPx(11),
                    color: owner.noticeColor,
                    alignment: .center
                )
                return
            }

            drawBottomUpdateRow(owner: owner)
        }

        private func drawBottomUpdateRow(owner: MainForm) {
            let subFont = UiTheme.fontPx(11)

            if owner.pullingUpdate {
                let ver = owner.availableUpdate?.latestVersion ?? ""
                let status = "正在拉取 v\(ver)... \(owner.pullProgress)%"
                UiTheme.drawCenteredText(
                    status,
                    in: owner.bottomStatusRowRect,
                    font: subFont,
                    color: UiTheme.textSecondary,
                    alignment: .center
                )

                let barW: CGFloat = 160
                let barH: CGFloat = 3
                let barX = owner.bottomStatusRowRect.minX + (owner.bottomStatusRowRect.width - barW) / 2.0
                let barY = owner.bottomStatusRowRect.maxY - 2
                let trackRect = NSRect(x: barX, y: barY, width: barW, height: barH)
                UiTheme.fillRoundedRect(trackRect, radius: 1, color: UiTheme.bgCard)

                let fillW = max(4, (barW * CGFloat(max(2, min(100, owner.pullProgress)))) / 100.0)
                let fillRect = NSRect(x: barX, y: barY, width: fillW, height: barH)
                UiTheme.fillRoundedRect(fillRect, radius: 1, color: UiTheme.weChatGreen)
                return
            }

            if owner.checkingUpdate {
                UiTheme.drawCenteredText(
                    "正在检查更新...",
                    in: owner.bottomStatusRowRect,
                    font: subFont,
                    color: UiTheme.textSecondary,
                    alignment: .center
                )
                return
            }

            if let avail = owner.availableUpdate, avail.isNewer {
                let prefix = "发现新版本 v\(avail.latestVersion) · "
                let actionText = avail.downloadUrl.isEmpty ? "前往下载" : "拉取更新"
                let ignoreText = "忽略"

                let prefixSz = (prefix as NSString).size(withAttributes: [.font: subFont])
                let actionSz = (actionText as NSString).size(withAttributes: [.font: subFont])
                let ignoreSz = (ignoreText as NSString).size(withAttributes: [.font: subFont])
                let gap: CGFloat = 10

                let totalW = ceil(prefixSz.width) + ceil(actionSz.width) + gap + ceil(ignoreSz.width)
                let startX = owner.bottomStatusRowRect.minX + (owner.bottomStatusRowRect.width - totalW) / 2.0

                let prefixRect = NSRect(x: startX, y: owner.bottomStatusRowRect.minY, width: ceil(prefixSz.width), height: owner.bottomStatusRowRect.height)
                owner.lnkUpdateActionRect = NSRect(x: prefixRect.maxX, y: owner.bottomStatusRowRect.minY, width: ceil(actionSz.width) + 4, height: owner.bottomStatusRowRect.height)
                owner.lnkIgnoreUpdateRect = NSRect(x: owner.lnkUpdateActionRect.maxX + gap - 2, y: owner.bottomStatusRowRect.minY, width: ceil(ignoreSz.width) + 4, height: owner.bottomStatusRowRect.height)

                let actHover = owner.lnkUpdateActionRect.contains(owner.mousePos)
                let ignHover = owner.lnkIgnoreUpdateRect.contains(owner.mousePos)

                UiTheme.drawCenteredText(prefix, in: prefixRect, font: subFont, color: UiTheme.textPrimary, alignment: .left)
                UiTheme.drawCenteredText(
                    actionText,
                    in: owner.lnkUpdateActionRect,
                    font: subFont,
                    color: actHover ? UiTheme.lighten(UiTheme.linkBlue, delta: 24) : UiTheme.linkBlue,
                    alignment: .center
                )
                UiTheme.drawCenteredText(
                    ignoreText,
                    in: owner.lnkIgnoreUpdateRect,
                    font: subFont,
                    color: ignHover ? UiTheme.textPrimary : UiTheme.textSecondary,
                    alignment: .center
                )
                return
            }

            let checkText = "检查更新"
            let csz = (checkText as NSString).size(withAttributes: [.font: subFont])
            let cw = ceil(csz.width) + 12
            owner.lnkUpdateActionRect = NSRect(
                x: owner.bottomStatusRowRect.minX + (owner.bottomStatusRowRect.width - cw) / 2.0,
                y: owner.bottomStatusRowRect.minY,
                width: cw,
                height: owner.bottomStatusRowRect.height
            )
            let hover = owner.lnkUpdateActionRect.contains(owner.mousePos)
            let linkColor = hover ? UiTheme.lighten(UiTheme.linkBlue, delta: 24) : UiTheme.linkBlue
            UiTheme.drawCenteredText(checkText, in: owner.lnkUpdateActionRect, font: subFont, color: linkColor, alignment: .center)
        }

        override func mouseMoved(with event: NSEvent) {
            guard let owner = owner else { return }
            let pt = convert(event.locationInWindow, from: nil)
            owner.mousePos = pt

            let hasSaveDir = !owner.autoSaveDir.isEmpty
            let inAutoSaveHit = owner.btnChangeSaveDirRect.contains(pt)
                || (hasSaveDir && owner.btnOpenSaveDirRect.contains(pt))
                || (hasSaveDir && owner.lblAutoSavePathRect.contains(pt))
                || (owner.chkAutoSaveRect.contains(pt) && pt.y <= owner.chkAutoSaveRect.minY + 26)
            let inUpdateHit = !owner.checkingUpdate && !owner.pullingUpdate
                && (owner.lnkUpdateActionRect.contains(pt) || owner.lnkIgnoreUpdateRect.contains(pt))

            let clickable = owner.btnMinimizeRect.contains(pt)
                || owner.btnCloseRect.contains(pt)
                || owner.btnCaptureRect.contains(pt)
                || owner.chkKeepAliveRect.contains(pt)
                || owner.chkHideStatusBarRect.contains(pt)
                || owner.chkAutoStartRect.contains(pt)
                || owner.chkQuickCopyRect.contains(pt)
                || inAutoSaveHit
                || inUpdateHit

            if clickable {
                NSCursor.pointingHand.set()
            } else {
                NSCursor.arrow.set()
            }
            needsDisplay = true
        }

        override func mouseExited(with event: NSEvent) {
            guard let owner = owner else { return }
            owner.mousePos = NSPoint(x: -100, y: -100)
            NSCursor.arrow.set()
            needsDisplay = true
        }

        override func mouseDown(with event: NSEvent) {
            guard let owner = owner else { return }
            let pt = convert(event.locationInWindow, from: nil)

            if owner.btnHotkeyBadgeRect.contains(pt) {
                owner.isRecordingHotkey.toggle()
                window?.makeFirstResponder(self)
                needsDisplay = true
                return
            }

            if owner.isRecordingHotkey {
                owner.isRecordingHotkey = false
                needsDisplay = true
            }

            if owner.btnMinimizeRect.contains(pt) {
                owner.minimizeToTray()
                return
            }

            if owner.btnCloseRect.contains(pt) {
                if owner.keepInBackground {
                    owner.minimizeToTray()
                } else {
                    NSApp.terminate(nil)
                }
                return
            }

            if owner.headerRect.contains(pt) {
                owner.draggingWindow = true
                owner.dragStartScreenPt = NSEvent.mouseLocation
                owner.winStartOrigin = owner.frame.origin
                return
            }

            if owner.btnCaptureRect.contains(pt) {
                owner.startCaptureFlow(preset: .none)
                return
            }

            if owner.chkKeepAliveRect.contains(pt) {
                owner.setKeepInBackground(!owner.keepInBackground)
                needsDisplay = true
                return
            }

            if owner.chkHideStatusBarRect.contains(pt) {
                owner.setHideStatusBarIcon(!owner.hideStatusBarIcon)
                needsDisplay = true
                return
            }

            if owner.chkAutoStartRect.contains(pt) {
                owner.toggleAutoStart()
                return
            }

            if owner.chkQuickCopyRect.contains(pt) {
                owner.setQuickCopyOnly(!owner.quickCopyOnly)
                needsDisplay = true
                return
            }

            if !owner.autoSaveDir.isEmpty && owner.btnOpenSaveDirRect.contains(pt) {
                owner.openAutoSaveDirectory()
                return
            }

            if owner.btnChangeSaveDirRect.contains(pt) {
                owner.chooseAutoSaveDirectory(enableAfterSelect: false)
                return
            }

            if !owner.autoSaveDir.isEmpty && owner.lblAutoSavePathRect.contains(pt) {
                owner.openAutoSaveDirectory()
                return
            }

            if owner.chkAutoSaveRect.contains(pt) && pt.y <= owner.chkAutoSaveRect.minY + 26 {
                owner.toggleAutoSave()
                return
            }

            if !owner.checkingUpdate && !owner.pullingUpdate {
                if owner.lnkIgnoreUpdateRect.contains(pt) {
                    owner.availableUpdate = nil
                    needsDisplay = true
                    return
                }
                if owner.lnkUpdateActionRect.contains(pt) {
                    if let avail = owner.availableUpdate, avail.isNewer {
                        owner.triggerPullUpdate()
                    } else {
                        owner.triggerCheckForUpdates()
                    }
                    return
                }
            }
        }

        override func mouseDragged(with event: NSEvent) {
            guard let owner = owner, owner.draggingWindow else { return }
            let cur = NSEvent.mouseLocation
            let dx = cur.x - owner.dragStartScreenPt.x
            let dy = cur.y - owner.dragStartScreenPt.y
            owner.setFrameOrigin(NSPoint(x: owner.winStartOrigin.x + dx, y: owner.winStartOrigin.y + dy))
        }

        override func mouseUp(with event: NSEvent) {
            owner?.draggingWindow = false
        }

        override func keyDown(with event: NSEvent) {
            guard let owner = owner else { return }
            if owner.isRecordingHotkey {
                if event.keyCode == 53 { // Esc cancels recording
                    owner.isRecordingHotkey = false
                    needsDisplay = true
                    return
                }
                if owner.recordNewHotkey(from: event) {
                    owner.isRecordingHotkey = false
                    needsDisplay = true
                }
                return
            }
            if event.keyCode == 36 || event.keyCode == 76 { // Return / Enter starts capture
                owner.startCaptureFlow(preset: .none)
            } else {
                super.keyDown(with: event)
            }
        }
    }

    public init() {
        UiTheme.refreshSystemTheme()
        self.brandIconImage = AppIconRenderer.renderAppIconImage(pointSize: 20)

        let prefs = AppSettings.loadPreferences()
        self.keepInBackground = prefs.keepInBackground
        self.hideStatusBarIcon = prefs.hideStatusBarIcon
        self.quickCopyOnly = prefs.quickCopyOnly
        self.autoSave = prefs.autoSave
        self.autoSaveDir = prefs.autoSaveDir
        self.autoStart = AppSettings.isAutoStartEnabled()

        let defaults = UserDefaults.standard
        if let savedLabel = defaults.string(forKey: Self.prefKeyHotkeyLabel), !savedLabel.isEmpty {
            self.hotkeyKeyCode = UInt32(defaults.integer(forKey: Self.prefKeyHotkeyCode))
            self.hotkeyCarbonMods = UInt32(defaults.integer(forKey: Self.prefKeyHotkeyMods))
            self.hotkeyDisplay = savedLabel
        }

        let w: CGFloat = 318
        let h: CGFloat = 340
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let frame = NSRect(
            x: screen.origin.x + (screen.width - w) / 2.0,
            y: screen.origin.y + (screen.height - h) / 2.0,
            width: w,
            height: h
        )

        super.init(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        MainForm.shared = self
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = true
        self.sharingType = .none
        self.isReleasedWhenClosed = false
        self.acceptsMouseMovedEvents = true
        self.title = "SpanShot"

        computeLayout(width: w, height: h)

        let view = MainPanelView(frame: NSRect(x: 0, y: 0, width: w, height: h))
        view.owner = self
        self.contentView = view

        setupStatusItem()
        registerGlobalHotkeys()

        themeObserver = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            UiTheme.refreshSystemTheme()
            self?.contentView?.needsDisplay = true
        }
    }

    override public var canBecomeKey: Bool { true }
    override public var canBecomeMain: Bool { true }

    private func computeLayout(width w: CGFloat, height h: CGFloat) {
        let padX: CGFloat = 16
        let fullW = w - padX * 2

        headerRect = NSRect(x: 0, y: 0, width: w - 76, height: 44)
        btnMinimizeRect = NSRect(x: w - 66, y: 10, width: 26, height: 24)
        btnCloseRect = NSRect(x: w - 36, y: 10, width: 26, height: 24)

        btnCaptureRect = NSRect(x: padX, y: 48, width: fullW, height: 46)
        btnHotkeyBadgeRect = NSRect(x: padX + fullW - 82, y: 48 + (46 - 26) / 2, width: 70, height: 26)

        chkKeepAliveRect = NSRect(x: padX, y: 106, width: fullW, height: 26)
        chkHideStatusBarRect = NSRect(x: padX, y: 136, width: fullW, height: 26)
        chkAutoStartRect = NSRect(x: padX, y: 166, width: fullW, height: 26)
        chkQuickCopyRect = NSRect(x: padX, y: 196, width: fullW, height: 44)
        chkAutoSaveRect = NSRect(x: padX, y: 246, width: fullW, height: 50)
        bottomStatusRowRect = NSRect(x: padX, y: 306, width: fullW, height: 22)
    }

    public static func tryShowInlineNotice(message: String, color: NSColor) -> Bool {
        guard let inst = shared else { return false }
        if inst.isVisible || inst.captureWasNormalVisible {
            inst.showInlineNotice(message: message, color: color)
            return true
        }
        return false
    }

    public func showInlineNotice(message: String, color: NSColor) {
        noticeText = message
        noticeColor = color
        contentView?.needsDisplay = true

        noticeTimer?.invalidate()
        noticeTimer = Timer.scheduledTimer(withTimeInterval: 3.2, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            self.noticeText = ""
            self.contentView?.needsDisplay = true
        }
    }

    private func notifyFeedback(_ message: String, color: NSColor) {
        if isVisible || captureWasNormalVisible {
            showInlineNotice(message: message, color: color)
        } else {
            ToastWindow.showToast(message: message, accent: color)
        }
    }

    private func saveCurrentPreferences() {
        AppSettings.savePreferences(
            keepInBackground: keepInBackground,
            hideStatusBarIcon: hideStatusBarIcon,
            quickCopyOnly: quickCopyOnly,
            autoSave: autoSave,
            autoSaveDir: autoSaveDir
        )
    }

    fileprivate func minimizeToTray() {
        isRecordingHotkey = false
        self.orderOut(nil)
    }

    fileprivate func setKeepInBackground(_ val: Bool) {
        keepInBackground = val
        saveCurrentPreferences()
        menuKeepAliveItem?.state = val ? .on : .off
        contentView?.needsDisplay = true
    }

    fileprivate func setHideStatusBarIcon(_ val: Bool) {
        hideStatusBarIcon = val
        if val && !keepInBackground {
            keepInBackground = true
            menuKeepAliveItem?.state = .on
        }
        saveCurrentPreferences()
        statusItem?.isVisible = !val
        menuHideStatusBarItem?.state = val ? .on : .off
        contentView?.needsDisplay = true
        notifyFeedback(
            val ? "已隐藏顶部状态栏图标（后台仍常驻运行）" : "已恢复显示顶部状态栏图标",
            color: UiTheme.weChatGreen
        )
    }

    fileprivate func setQuickCopyOnly(_ val: Bool) {
        quickCopyOnly = val
        saveCurrentPreferences()
        menuQuickCopyItem?.state = val ? .on : .off
        contentView?.needsDisplay = true
    }

    fileprivate func toggleAutoStart() {
        let next = !autoStart
        if AppSettings.setAutoStart(next) {
            autoStart = next
            menuAutoStartItem?.state = next ? .on : .off
            contentView?.needsDisplay = true
            notifyFeedback(next ? "已开启开机自启" : "已关闭开机自启", color: UiTheme.weChatGreen)
        } else {
            notifyFeedback("设置开机自启失败", color: UiTheme.accentRed)
        }
    }

    fileprivate func toggleAutoSave() {
        if !autoSave {
            if autoSaveDir.isEmpty {
                chooseAutoSaveDirectory(enableAfterSelect: true)
                return
            }
            if !AppSettings.validateWritableFolder(autoSaveDir) {
                notifyFeedback("保存目录不存在或无写入权限，请重选", color: UiTheme.accentRed)
                chooseAutoSaveDirectory(enableAfterSelect: true)
                return
            }
            autoSave = true
            saveCurrentPreferences()
            menuAutoSaveItem?.state = .on
            contentView?.needsDisplay = true
            notifyFeedback("已开启自动保存", color: UiTheme.weChatGreen)
        } else {
            autoSave = false
            saveCurrentPreferences()
            menuAutoSaveItem?.state = .off
            contentView?.needsDisplay = true
            notifyFeedback("已关闭自动保存", color: UiTheme.textSecondary)
        }
    }

    fileprivate func chooseAutoSaveDirectory(enableAfterSelect: Bool) {
        guard let selected = AppSettings.pickFolderDialog(currentDir: autoSaveDir), !selected.isEmpty else {
            return
        }
        if !AppSettings.validateWritableFolder(selected) {
            notifyFeedback("所选文件夹无写入权限，请更换目录", color: UiTheme.accentRed)
            return
        }
        autoSaveDir = selected
        if enableAfterSelect {
            autoSave = true
        }
        saveCurrentPreferences()
        menuAutoSaveItem?.state = autoSave ? .on : .off
        contentView?.needsDisplay = true
        notifyFeedback("保存目录已更新", color: UiTheme.weChatGreen)
    }

    fileprivate func openAutoSaveDirectory() {
        var isDir: ObjCBool = false
        guard !autoSaveDir.isEmpty,
              FileManager.default.fileExists(atPath: autoSaveDir, isDirectory: &isDir),
              isDir.boolValue else {
            notifyFeedback("目录不存在，请重新选择", color: UiTheme.accentRed)
            return
        }
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: autoSaveDir)
    }

    fileprivate func triggerCheckForUpdates() {
        guard !checkingUpdate && !pullingUpdate else { return }
        checkingUpdate = true
        availableUpdate = nil
        noticeText = ""
        contentView?.needsDisplay = true

        UpdateManager.checkForUpdatesAsync { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.checkingUpdate = false
                if !result.success {
                    let msg = result.errorMessage.isEmpty ? "检查更新失败" : result.errorMessage
                    self.notifyFeedback(msg, color: UiTheme.accentRed)
                } else if result.isNewer {
                    self.availableUpdate = result
                    self.noticeText = ""
                } else {
                    self.availableUpdate = nil
                    self.notifyFeedback("当前已是最新版本 (v\(UpdateManager.currentVersion))", color: UiTheme.weChatGreen)
                }
                self.contentView?.needsDisplay = true
            }
        }
    }

    fileprivate func triggerPullUpdate() {
        guard let avail = availableUpdate, !pullingUpdate else { return }
        if avail.downloadUrl.isEmpty {
            UpdateManager.openReleasesPage(avail.htmlUrl)
            return
        }

        pullingUpdate = true
        pullProgress = 1
        noticeText = ""
        contentView?.needsDisplay = true

        UpdateManager.pullAndApplyUpdateAsync(
            info: avail,
            onProgress: { [weak self] pct in
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    self.pullProgress = pct
                    self.contentView?.needsDisplay = true
                }
            },
            onCompleted: { [weak self] ok, msg in
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    self.pullingUpdate = false
                    self.contentView?.needsDisplay = true
                    if ok {
                        self.notifyFeedback(msg, color: UiTheme.weChatGreen)
                        if msg.contains("重启") {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                                NSApp.terminate(nil)
                            }
                        }
                    } else {
                        self.notifyFeedback(msg, color: UiTheme.accentRed)
                    }
                }
            }
        )
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let btn = item.button {
            btn.image = AppIconRenderer.renderStatusBarTemplateIcon()
            btn.imagePosition = .imageOnly
            btn.toolTip = "SpanShot — 跨屏横纵长截图 (\(hotkeyDisplay))"
        }

        let menu = NSMenu()

        let captureItem = NSMenuItem(title: "开始截图 (\(hotkeyDisplay))", action: #selector(onMenuCapture), keyEquivalent: "")
        captureItem.target = self
        menu.addItem(captureItem)
        self.menuCaptureItem = captureItem

        let vScrollItem = NSMenuItem(title: "纵向长截图...", action: #selector(onMenuVerticalScroll), keyEquivalent: "")
        vScrollItem.target = self
        menu.addItem(vScrollItem)

        let hScrollItem = NSMenuItem(title: "横向长截图...", action: #selector(onMenuHorizontalScroll), keyEquivalent: "")
        hScrollItem.target = self
        menu.addItem(hScrollItem)

        menu.addItem(.separator())

        let quickItem = NSMenuItem(title: "快捷截图（只复制不弹窗）", action: #selector(onMenuToggleQuickCopy), keyEquivalent: "")
        quickItem.target = self
        quickItem.state = quickCopyOnly ? .on : .off
        menu.addItem(quickItem)
        self.menuQuickCopyItem = quickItem

        let autoSaveItem = NSMenuItem(title: "自动保存截图", action: #selector(onMenuToggleAutoSave), keyEquivalent: "")
        autoSaveItem.target = self
        autoSaveItem.state = autoSave ? .on : .off
        menu.addItem(autoSaveItem)
        self.menuAutoSaveItem = autoSaveItem

        let pickDirItem = NSMenuItem(title: "选择自动保存目录...", action: #selector(onMenuPickAutoSaveDir), keyEquivalent: "")
        pickDirItem.target = self
        menu.addItem(pickDirItem)

        let autoStartItem = NSMenuItem(title: "开机自启", action: #selector(onMenuToggleAutoStart), keyEquivalent: "")
        autoStartItem.target = self
        autoStartItem.state = autoStart ? .on : .off
        menu.addItem(autoStartItem)
        self.menuAutoStartItem = autoStartItem

        let keepItem = NSMenuItem(title: "常驻后台", action: #selector(onMenuToggleKeepAlive), keyEquivalent: "")
        keepItem.target = self
        keepItem.state = keepInBackground ? .on : .off
        menu.addItem(keepItem)
        self.menuKeepAliveItem = keepItem

        let hideBarItem = NSMenuItem(title: "隐藏顶部状态栏图标", action: #selector(onMenuToggleHideStatusBar), keyEquivalent: "")
        hideBarItem.target = self
        hideBarItem.state = hideStatusBarIcon ? .on : .off
        menu.addItem(hideBarItem)
        self.menuHideStatusBarItem = hideBarItem

        menu.addItem(.separator())

        let updateItem = NSMenuItem(title: "检查更新...", action: #selector(onMenuCheckUpdate), keyEquivalent: "")
        updateItem.target = self
        menu.addItem(updateItem)

        let showItem = NSMenuItem(title: "显示主窗口", action: #selector(onMenuShowMain), keyEquivalent: "")
        showItem.target = self
        menu.addItem(showItem)

        let quitItem = NSMenuItem(title: "彻底退出 SpanShot", action: #selector(onMenuQuit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        item.menu = menu
        item.isVisible = !hideStatusBarIcon
        self.statusItem = item
    }

    private func registerGlobalHotkeys() {
        for ref in hotKeyRefs {
            if let r = ref {
                UnregisterEventHotKey(r)
            }
        }
        hotKeyRefs.removeAll()

        if !eventHandlerInstalled {
            var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            let selfPtr = Unmanaged.passUnretained(self).toOpaque()

            InstallEventHandler(
                GetApplicationEventTarget(),
                { (_, _, userData) -> OSStatus in
                    guard let userData = userData else { return noErr }
                    let mainForm = Unmanaged<MainForm>.fromOpaque(userData).takeUnretainedValue()
                    DispatchQueue.main.async {
                        mainForm.startCaptureFlow(preset: .none)
                    }
                    return noErr
                },
                1,
                &eventType,
                selfPtr,
                nil
            )
            eventHandlerInstalled = true
        }

        // 1. Register user's primary hotkey (default: ⌘⇧A)
        registerSingleCarbonHotkey(id: 9001, keyCode: hotkeyKeyCode, carbonMods: hotkeyCarbonMods)

        // 2. Also register ⌃⌘A (WeChat Mac habit) and ⌥A (Alt+A habit) as secondary triggers if distinct
        let ctrlCmdMods = UInt32(controlKey | cmdKey)
        if !(hotkeyKeyCode == UInt32(kVK_ANSI_A) && hotkeyCarbonMods == ctrlCmdMods) {
            registerSingleCarbonHotkey(id: 9002, keyCode: UInt32(kVK_ANSI_A), carbonMods: ctrlCmdMods)
        }

        let optMods = UInt32(optionKey)
        if !(hotkeyKeyCode == UInt32(kVK_ANSI_A) && hotkeyCarbonMods == optMods) {
            registerSingleCarbonHotkey(id: 9003, keyCode: UInt32(kVK_ANSI_A), carbonMods: optMods)
        }
    }

    private func registerSingleCarbonHotkey(id: UInt32, keyCode: UInt32, carbonMods: UInt32) {
        var ref: EventHotKeyRef?
        let hkID = EventHotKeyID(signature: OSType(0x53505348), id: id)
        let status = RegisterEventHotKey(
            keyCode,
            carbonMods,
            hkID,
            GetApplicationEventTarget(),
            0,
            &ref
        )
        if status == noErr {
            hotKeyRefs.append(ref)
        }
    }

    fileprivate func recordNewHotkey(from event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var cMods: UInt32 = 0
        var modSymbols = ""

        if flags.contains(.control) {
            cMods |= UInt32(controlKey)
            modSymbols += "⌃"
        }
        if flags.contains(.option) {
            cMods |= UInt32(optionKey)
            modSymbols += "⌥"
        }
        if flags.contains(.shift) {
            cMods |= UInt32(shiftKey)
            modSymbols += "⇧"
        }
        if flags.contains(.command) {
            cMods |= UInt32(cmdKey)
            modSymbols += "⌘"
        }

        guard cMods != 0, let keyName = Self.keyCodeToDisplayString(event.keyCode) else {
            return false
        }

        self.hotkeyKeyCode = UInt32(event.keyCode)
        self.hotkeyCarbonMods = cMods
        self.hotkeyDisplay = modSymbols + keyName

        let defaults = UserDefaults.standard
        defaults.set(Int(self.hotkeyKeyCode), forKey: Self.prefKeyHotkeyCode)
        defaults.set(Int(self.hotkeyCarbonMods), forKey: Self.prefKeyHotkeyMods)
        defaults.set(self.hotkeyDisplay, forKey: Self.prefKeyHotkeyLabel)

        registerGlobalHotkeys()
        menuCaptureItem?.title = "开始截图 (\(hotkeyDisplay))"
        statusItem?.button?.toolTip = "SpanShot — 跨屏横纵长截图 (\(hotkeyDisplay))"
        notifyFeedback("快捷键已设为 \(hotkeyDisplay)", color: UiTheme.weChatGreen)
        return true
    }

    private static func keyCodeToDisplayString(_ keyCode: UInt16) -> String? {
        let map: [UInt16: String] = [
            0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V",
            11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T", 18: "1", 19: "2",
            20: "3", 21: "4", 22: "6", 23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8",
            29: "0", 31: "O", 32: "U", 34: "I", 35: "P", 37: "L", 38: "J", 40: "K", 45: "N",
            46: "M", 122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7",
            100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12"
        ]
        return map[keyCode]
    }

    @objc public func onMenuCapture() {
        startCaptureFlow(preset: .none)
    }

    @objc public func onMenuVerticalScroll() {
        startCaptureFlow(preset: .verticalScroll)
    }

    @objc public func onMenuHorizontalScroll() {
        startCaptureFlow(preset: .horizontalScroll)
    }

    @objc private func onMenuToggleQuickCopy() {
        setQuickCopyOnly(!quickCopyOnly)
    }

    @objc private func onMenuToggleAutoSave() {
        toggleAutoSave()
    }

    @objc private func onMenuPickAutoSaveDir() {
        onMenuShowMain()
        chooseAutoSaveDirectory(enableAfterSelect: true)
    }

    @objc private func onMenuToggleAutoStart() {
        toggleAutoStart()
    }

    @objc private func onMenuToggleKeepAlive() {
        setKeepInBackground(!keepInBackground)
    }

    @objc public func onMenuToggleHideStatusBar() {
        setHideStatusBarIcon(!hideStatusBarIcon)
    }

    @objc private func onMenuCheckUpdate() {
        onMenuShowMain()
        triggerCheckForUpdates()
    }

    @objc public func onMenuShowMain() {
        UiTheme.refreshSystemTheme()
        NSApp.activate(ignoringOtherApps: true)
        self.makeKeyAndOrderFront(nil)
        self.contentView?.needsDisplay = true
    }

    @objc public func onMenuQuit() {
        NSApp.terminate(nil)
    }

    private func copyAndOptionalAutoSave(_ bmp: RawBitmap, tag: String) {
        UiTheme.copyBitmapToClipboard(bmp)

        if autoSave {
            if AppSettings.tryAutoSaveBitmap(bmp, folderPath: autoSaveDir, tag: tag) != nil {
                notifyFeedback(String(format: "已复制并自动保存 (%d × %d)", bmp.width, bmp.height), color: UiTheme.weChatGreen)
            } else {
                autoSave = false
                saveCurrentPreferences()
                menuAutoSaveItem?.state = .off
                contentView?.needsDisplay = true
                notifyFeedback("已复制（目录不可写，已关自动保存）", color: UiTheme.accentRed)
            }
        } else {
            notifyFeedback(String(format: "已复制到剪贴板 (%d × %d)", bmp.width, bmp.height), color: UiTheme.weChatGreen)
        }
    }

    private func openPreviewAndOptionalAutoSave(_ bmp: RawBitmap, titleTag: String, fileTag: String) {
        let editor = ResultPreviewForm(bitmap: bmp, captureTypeTag: titleTag, initialSaveDir: autoSaveDir)
        editor.showModalOrFloating { [weak self] closedEditor in
            guard let self = self else { return }
            if self.autoSave && !closedEditor.manuallySaved {
                if AppSettings.tryAutoSaveBitmap(closedEditor.finalWorkingBitmap, folderPath: self.autoSaveDir, tag: fileTag) != nil {
                    self.notifyFeedback(closedEditor.confirmedCopy ? "已复制并自动保存" : "已自动保存", color: UiTheme.weChatGreen)
                } else {
                    self.autoSave = false
                    self.saveCurrentPreferences()
                    self.menuAutoSaveItem?.state = .off
                    self.contentView?.needsDisplay = true
                    self.notifyFeedback("目录不可写，已关闭自动保存", color: UiTheme.accentRed)
                }
            } else if !closedEditor.manuallySaved && closedEditor.confirmedCopy {
                self.notifyFeedback("已复制到剪贴板", color: UiTheme.weChatGreen)
            }
        }
    }

    private func saveBitmapDialog(_ bmp: RawBitmap, tag: String) {
        if UiTheme.saveBitmapDialog(bmp, tag: tag, initialDir: autoSaveDir) {
            notifyFeedback("已保存", color: UiTheme.weChatGreen)
        }
    }

    public func startCaptureFlow(preset: CaptureActionMode = .none) {
        guard !isCapturing else { return }
        ScreenCapturer.invalidateShareableContentCache()
        switch ScreenCapturer.checkOrRequestPermissionState() {
        case .granted:
            break
        case .promptedSystemDialog:
            notifyFeedback("请在系统弹窗中点击允许（授权后再次点击即可截图）", color: UiTheme.accentOrange)
            return
        case .relaunchingWithNewPermission:
            return
        case .denied:
            notifyFeedback("请先在系统设置中开启 SpanShot 的屏幕录制权限", color: UiTheme.accentRed)
            ScreenCapturer.openScreenCaptureSettings()
            return
        }
        isCapturing = true
        isRecordingHotkey = false

        let wasVisible = self.isVisible
        captureWasNormalVisible = wasVisible
        if wasVisible {
            self.orderOut(nil)
        }

        let delay: TimeInterval = wasVisible ? 0.10 : 0.02
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.presentRegionSelector(wasMainVisible: wasVisible, preset: preset)
        }
    }

    private func presentRegionSelector(wasMainVisible: Bool, preset: CaptureActionMode) {
        let selector = RegionSelectorForm(presetMode: preset)
        if selector.captureWasBlockedByPermission {
            self.restoreMainIfNeeded(wasMainVisible)
            self.notifyFeedback("请先在系统设置中允许屏幕录制权限", color: UiTheme.accentRed)
            ScreenCapturer.openScreenCaptureSettings()
            return
        }
        self.activeSelector = selector

        selector.beginSelection { [weak self] sel in
            guard let self = self else { return }
            self.activeSelector = nil

            let chosen = sel.chosenAction
            let selectedRect = sel.selectedPhysicalRect
            let annotatedBmp = sel.annotatedRegionBitmap

            if chosen == .none {
                self.restoreMainIfNeeded(wasMainVisible)
                return
            }

            if chosen == .normalCopyCompleted {
                if let bmp = annotatedBmp {
                    if self.quickCopyOnly {
                        self.copyAndOptionalAutoSave(bmp, tag: "Shot")
                    } else {
                        self.openPreviewAndOptionalAutoSave(bmp, titleTag: "截图", fileTag: "Shot")
                    }
                }
                self.restoreMainIfNeeded(wasMainVisible)
                return
            }

            if chosen == .normalPinCompleted {
                if let bmp = annotatedBmp {
                    self.copyAndOptionalAutoSave(bmp, tag: "Shot")
                    let pin = PinWindowForm(sourceBitmap: bmp, initialTopDownLocation: selectedRect.origin)
                    pin.showPin()
                }
                self.restoreMainIfNeeded(wasMainVisible)
                return
            }

            if chosen == .normalSaveCompleted {
                if let bmp = annotatedBmp {
                    self.saveBitmapDialog(bmp, tag: "Shot")
                }
                self.restoreMainIfNeeded(wasMainVisible)
                return
            }

            let dir: ScrollDirection = (chosen == .verticalScroll) ? .vertical : .horizontal
            let scrollTag = (dir == .vertical) ? "Vertical" : "Horizontal"
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                guard let self = self else { return }
                let session = ScrollCaptureSessionForm(physicalCaptureRect: selectedRect, direction: dir)
                self.activeScrollSession = session
                session.startSession { [weak self] stitchedResult, exitAction in
                    guard let self = self else { return }
                    self.activeScrollSession = nil

                    if let resultBmp = stitchedResult, exitAction != .cancelled {
                        if self.quickCopyOnly || exitAction == .copyDirectly {
                            self.copyAndOptionalAutoSave(resultBmp, tag: scrollTag)
                        } else if exitAction == .pinDirectly {
                            self.copyAndOptionalAutoSave(resultBmp, tag: scrollTag)
                            let pin = PinWindowForm(sourceBitmap: resultBmp)
                            pin.showPin()
                        } else if exitAction == .saveDirectly {
                            self.saveBitmapDialog(resultBmp, tag: scrollTag)
                        } else if exitAction == .openEditor {
                            self.openPreviewAndOptionalAutoSave(
                                resultBmp,
                                titleTag: dir == .vertical ? "纵向长截图" : "横向长截图",
                                fileTag: scrollTag
                            )
                        }
                    }

                    self.restoreMainIfNeeded(wasMainVisible)
                }
            }
        }
    }

    private func restoreMainIfNeeded(_ wasMainVisible: Bool) {
        if wasMainVisible {
            UiTheme.refreshSystemTheme()
            self.makeKeyAndOrderFront(nil)
            self.contentView?.needsDisplay = true
        }
        captureWasNormalVisible = false
        isCapturing = false
    }
}
