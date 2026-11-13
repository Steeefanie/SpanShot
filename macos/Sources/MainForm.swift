import AppKit
import Carbon
import Foundation

/// Minimalist adaptive main window + NSStatusItem menu bar agent (1:1 port of src/MainForm.cs v1.1.0, enhanced for macOS).
public final class MainForm: NSWindow, NSWindowDelegate {
    public private(set) static weak var shared: MainForm?

    private static let prefKeyHotkeyCode = "SpanShot.HotkeyKeyCode"
    private static let prefKeyHotkeyMods = "SpanShot.HotkeyCarbonMods"
    private static let prefKeyHotkeyLabel = "SpanShot.HotkeyDisplay"

    fileprivate var statusItem: NSStatusItem?
    fileprivate var menuCaptureItem: NSMenuItem?
    fileprivate var menuWindowShadowItem: NSMenuItem?
    fileprivate var menuQuickCopyItem: NSMenuItem?
    fileprivate var menuAutoSaveItem: NSMenuItem?
    fileprivate var menuAutoStartItem: NSMenuItem?
    fileprivate var menuKeepAliveItem: NSMenuItem?
    fileprivate var menuHideStatusBarItem: NSMenuItem?

    fileprivate var isCapturing = false
    fileprivate var captureWasNormalVisible = false
    fileprivate var keepInBackground = true
    fileprivate var hideStatusBarIcon = false
    fileprivate var windowShadowCapture = true
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
    fileprivate var isLanguageMenuOpen = false

    fileprivate var draggingWindow = false
    fileprivate var dragStartScreenPt: NSPoint = .zero
    fileprivate var winStartOrigin: NSPoint = .zero
    fileprivate var mousePos: NSPoint = NSPoint(x: -100, y: -100)

    fileprivate let brandIconImage: NSImage

    // Layout rects (326 x 420 logical points, functionally grouped macOS native settings cards)
    fileprivate var headerRect: NSRect = .zero
    fileprivate var btnLangRect: NSRect = .zero
    fileprivate var btnMinimizeRect: NSRect = .zero
    fileprivate var btnCloseRect: NSRect = .zero
    fileprivate var btnCaptureRect: NSRect = .zero
    fileprivate var btnHotkeyBadgeRect: NSRect = .zero
    fileprivate var lblCaptureSectionRect: NSRect = .zero
    fileprivate var captureCardRect: NSRect = .zero
    fileprivate var chkWindowShadowRect: NSRect = .zero
    fileprivate var chkQuickCopyRect: NSRect = .zero
    fileprivate var chkAutoSaveRect: NSRect = .zero
    fileprivate var btnOpenSaveDirRect: NSRect = .zero
    fileprivate var btnChangeSaveDirRect: NSRect = .zero
    fileprivate var lblAutoSavePathRect: NSRect = .zero
    fileprivate var lblSystemSectionRect: NSRect = .zero
    fileprivate var systemCardRect: NSRect = .zero
    fileprivate var chkKeepAliveRect: NSRect = .zero
    fileprivate var chkHideStatusBarRect: NSRect = .zero
    fileprivate var chkAutoStartRect: NSRect = .zero
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

            UiTheme.bgDark.setFill()
            bounds.fill()

            // 1. Spacious 52pt unified header bar: native left traffic lights (center Y=26, left X=19)
            //    + centered "SpanShot" title + right-side Globe button (center Y=26, right X=w-19)
            UiTheme.drawCenteredText(
                "SpanShot",
                in: NSRect(x: 0, y: 0, width: bounds.width, height: 52),
                font: NSFont.systemFont(ofSize: 13.5, weight: .semibold),
                color: UiTheme.textPrimary,
                alignment: .center
            )

            let langHovered = owner.btnLangRect.contains(owner.mousePos) || owner.isLanguageMenuOpen
            if langHovered {
                UiTheme.fillRoundedRect(owner.btnLangRect, radius: 6, color: UiTheme.bgCardHover)
            }
            UiTheme.drawIconGlobe(
                btnRect: owner.btnLangRect,
                color: langHovered ? UiTheme.textPrimary : UiTheme.textSecondary
            )

            // 2. Primary Capture Action Button
            let interactableHover = !owner.isLanguageMenuOpen
            let badgeHovered = interactableHover && owner.btnHotkeyBadgeRect.contains(owner.mousePos)
            let btnHovered = interactableHover && owner.btnCaptureRect.contains(owner.mousePos) && !badgeHovered
            drawCaptureButton(
                rect: owner.btnCaptureRect,
                badgeRect: owner.btnHotkeyBadgeRect,
                label: L10n.startCapture,
                hotkey: owner.isRecordingHotkey ? L10n.pressKeysPrompt : owner.hotkeyDisplay,
                btnHovered: btnHovered,
                badgeHovered: badgeHovered,
                recording: owner.isRecordingHotkey
            )

            let cardBorder = UiTheme.borderSubtle.withAlphaComponent(UiTheme.isDarkMode ? 0.55 : 0.75)
            let sectionFont = NSFont.systemFont(ofSize: 11.5, weight: .semibold)
            let sectionColor = UiTheme.textSecondary.withAlphaComponent(0.9)

            // 3. Group 1: 「截图与保存」 (Capture & Save Preferences)
            UiTheme.drawCenteredText(
                L10n.sectionCaptureAndSave,
                in: owner.lblCaptureSectionRect,
                font: sectionFont,
                color: sectionColor,
                alignment: .left
            )

            UiTheme.fillAndStrokeRoundedRect(
                owner.captureCardRect,
                radius: 10,
                fillColor: UiTheme.bgCard,
                strokeColor: cardBorder,
                lineWidth: 0.5
            )

            drawToggleRow(
                rect: owner.chkWindowShadowRect,
                label: L10n.windowShadowLabel,
                rightHint: L10n.windowShadowHint,
                isChecked: owner.windowShadowCapture,
                hovered: interactableHover && owner.chkWindowShadowRect.contains(owner.mousePos)
            )

            drawCardDivider(in: owner.captureCardRect, y: owner.chkQuickCopyRect.minY)

            drawToggleRow(
                rect: owner.chkQuickCopyRect,
                label: L10n.quickCopyLabel,
                rightHint: L10n.quickCopyHint,
                isChecked: owner.quickCopyOnly,
                hovered: interactableHover && owner.chkQuickCopyRect.contains(owner.mousePos)
            )

            drawCardDivider(in: owner.captureCardRect, y: owner.chkAutoSaveRect.minY)

            drawAutoSaveOption(owner: owner)

            // 4. Group 2: 「系统与后台」 (System & Background Preferences)
            UiTheme.drawCenteredText(
                L10n.sectionSystemAndBg,
                in: owner.lblSystemSectionRect,
                font: sectionFont,
                color: sectionColor,
                alignment: .left
            )

            UiTheme.fillAndStrokeRoundedRect(
                owner.systemCardRect,
                radius: 10,
                fillColor: UiTheme.bgCard,
                strokeColor: cardBorder,
                lineWidth: 0.5
            )

            drawToggleRow(
                rect: owner.chkKeepAliveRect,
                label: L10n.keepAliveLabel,
                rightHint: nil,
                isChecked: owner.keepInBackground,
                hovered: interactableHover && owner.chkKeepAliveRect.contains(owner.mousePos)
            )

            drawCardDivider(in: owner.systemCardRect, y: owner.chkHideStatusBarRect.minY)

            drawToggleRow(
                rect: owner.chkHideStatusBarRect,
                label: L10n.hideStatusBarLabel,
                rightHint: nil,
                isChecked: owner.hideStatusBarIcon,
                hovered: interactableHover && owner.chkHideStatusBarRect.contains(owner.mousePos)
            )

            drawCardDivider(in: owner.systemCardRect, y: owner.chkAutoStartRect.minY)

            drawToggleRow(
                rect: owner.chkAutoStartRect,
                label: L10n.autoStartLabel,
                rightHint: nil,
                isChecked: owner.autoStart,
                hovered: interactableHover && owner.chkAutoStartRect.contains(owner.mousePos)
            )

            // 5. Bottom Status / Inline Notice / Update Check Row
            drawBottomStatusRow(owner: owner)
        }

        private func drawCardDivider(in cardRect: NSRect, y: CGFloat) {
            UiTheme.dividerColor.withAlphaComponent(UiTheme.isDarkMode ? 0.55 : 0.65).setFill()
            NSRect(
                x: cardRect.minX + 14,
                y: floor(y),
                width: cardRect.width - 28,
                height: 0.5
            ).fill()
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
            UiTheme.fillRoundedRect(rect, radius: 10, color: bg)

            let textRect = NSRect(x: rect.minX + 16, y: rect.minY, width: rect.width - 100, height: rect.height)
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
                    radius: 6,
                    fillColor: badgeBg,
                    strokeColor: recording ? .white : NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.45),
                    lineWidth: 1.0
                )
            } else {
                UiTheme.fillRoundedRect(badgeRect, radius: 6, color: badgeBg)
            }
            UiTheme.drawCenteredText(
                hotkey,
                in: badgeRect,
                font: UiTheme.fontPx(recording ? 11 : 12, bold: recording),
                color: recording ? .black : .white,
                alignment: .center
            )
        }

        private func drawToggleRow(rect: NSRect, label: String, rightHint: String?, isChecked: Bool, hovered: Bool) {
            let swW: CGFloat = 32
            let swH: CGFloat = 18
            let swRect = NSRect(
                x: rect.maxX - swW,
                y: floor(rect.minY + (rect.height - swH) / 2.0),
                width: swW,
                height: swH
            )

            let lblFont = NSFont.systemFont(ofSize: 13, weight: .regular)
            let lblWidth = ceil((label as NSString).size(withAttributes: [.font: lblFont]).width)
            let maxAvailW = swRect.minX - rect.minX - 10
            let titleDrawW = min(maxAvailW, lblWidth + 2)
            let lblRect = NSRect(x: rect.minX, y: rect.minY, width: titleDrawW, height: rect.height)
            UiTheme.drawCenteredText(
                label,
                in: lblRect,
                font: lblFont,
                color: UiTheme.textPrimary,
                alignment: .left,
                lineBreakMode: .byTruncatingTail
            )

            if let hint = rightHint, !hint.isEmpty {
                let hintX = lblRect.maxX + 8
                let hintW = swRect.minX - 10 - hintX
                if hintW >= 36 {
                    let hintRect = NSRect(x: hintX, y: rect.minY, width: hintW, height: rect.height)
                    UiTheme.drawCenteredText(
                        hint,
                        in: hintRect,
                        font: UiTheme.fontPx(11.5),
                        color: UiTheme.textSecondary.withAlphaComponent(hovered ? 0.95 : 0.78),
                        alignment: .right,
                        lineBreakMode: .byTruncatingTail
                    )
                }
            }

            drawToggleSwitch(rect: swRect, isChecked: isChecked, hovered: hovered)
        }

        private func drawAutoSaveOption(owner: MainForm) {
            let rowRect = owner.chkAutoSaveRect
            let topLineH: CGFloat = 34
            let swW: CGFloat = 32
            let swH: CGFloat = 18
            let swRect = NSRect(
                x: rowRect.maxX - swW,
                y: floor(rowRect.minY + (topLineH - swH) / 2.0),
                width: swW,
                height: swH
            )

            let hasSaveDir = !owner.autoSaveDir.isEmpty
            let dirBtnFont = UiTheme.fontPx(11)
            let changeText = hasSaveDir ? L10n.btnChangeDir : L10n.btnSelectDir
            let openText = L10n.btnOpenDir
            let changeBtnW = max(48, ceil((changeText as NSString).size(withAttributes: [.font: dirBtnFont]).width) + 16)
            let openBtnW = max(48, ceil((openText as NSString).size(withAttributes: [.font: dirBtnFont]).width) + 16)
            let dirBtnH: CGFloat = 20
            let dirBtnY = floor(rowRect.minY + (topLineH - dirBtnH) / 2.0)

            owner.btnChangeSaveDirRect = NSRect(
                x: swRect.minX - 8 - changeBtnW,
                y: dirBtnY,
                width: changeBtnW,
                height: dirBtnH
            )
            owner.btnOpenSaveDirRect = hasSaveDir
                ? NSRect(
                    x: owner.btnChangeSaveDirRect.minX - 6 - openBtnW,
                    y: dirBtnY,
                    width: openBtnW,
                    height: dirBtnH
                )
                : .zero

            let changeHover = owner.btnChangeSaveDirRect.contains(owner.mousePos)
            let openHover = hasSaveDir && owner.btnOpenSaveDirRect.contains(owner.mousePos)
            let pathHover = hasSaveDir && owner.lblAutoSavePathRect.contains(owner.mousePos)
            let mainRowHover = rowRect.contains(owner.mousePos)
                && !changeHover && !openHover && !pathHover
                && owner.mousePos.y <= rowRect.minY + topLineH

            let rightActionLeft = hasSaveDir ? owner.btnOpenSaveDirRect.minX : owner.btnChangeSaveDirRect.minX
            let titleW = max(60, rightActionLeft - rowRect.minX - 6)
            let lblRect = NSRect(x: rowRect.minX, y: rowRect.minY, width: titleW, height: topLineH)
            UiTheme.drawCenteredText(
                L10n.autoSaveLabel,
                in: lblRect,
                font: NSFont.systemFont(ofSize: 13, weight: .regular),
                color: UiTheme.textPrimary,
                alignment: .left,
                lineBreakMode: .byTruncatingTail
            )

            if hasSaveDir {
                drawSmallDirButton(rect: owner.btnOpenSaveDirRect, text: openText, hovered: openHover, font: dirBtnFont)
            }
            drawSmallDirButton(
                rect: owner.btnChangeSaveDirRect,
                text: changeText,
                hovered: changeHover,
                font: dirBtnFont
            )

            drawToggleSwitch(rect: swRect, isChecked: owner.autoSave, hovered: mainRowHover)

            let noteY = rowRect.minY + topLineH - 1
            let noteRect = NSRect(x: rowRect.minX, y: noteY, width: rowRect.width, height: 19)

            if !hasSaveDir {
                owner.lblAutoSavePathRect = .zero
                UiTheme.drawCenteredText(
                    L10n.autoSaveNoDirNote,
                    in: noteRect,
                    font: UiTheme.fontPx(11),
                    color: UiTheme.textSecondary.withAlphaComponent(0.78),
                    alignment: .left
                )
            } else {
                owner.lblAutoSavePathRect = noteRect
                let pathLine = L10n.autoSaveDirPrefix(owner.autoSaveDir)
                let pathColor = pathHover ? UiTheme.weChatGreen : UiTheme.textSecondary.withAlphaComponent(0.85)
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
            let fill = hovered ? UiTheme.bgCardHover : UiTheme.bgDark
            let border = hovered ? UiTheme.weChatGreen : UiTheme.borderSubtle
            let fg = hovered ? UiTheme.textPrimary : UiTheme.textSecondary
            UiTheme.fillAndStrokeRoundedRect(rect, radius: 5, fillColor: fill, strokeColor: border, lineWidth: 0.8)
            UiTheme.drawCenteredText(text, in: rect, font: font, color: fg, alignment: .center)
        }

        private func drawToggleSwitch(rect: NSRect, isChecked: Bool, hovered: Bool) {
            let radius = rect.height / 2.0
            if isChecked {
                let trackColor = hovered ? UiTheme.lighten(UiTheme.weChatGreen, delta: 12) : UiTheme.weChatGreen
                UiTheme.fillRoundedRect(rect, radius: radius, color: trackColor)
            } else {
                let offFill = UiTheme.isDarkMode
                    ? NSColor(srgbRed: 1, green: 1, blue: 1, alpha: hovered ? 0.22 : 0.15)
                    : NSColor(srgbRed: 0, green: 0, blue: 0, alpha: hovered ? 0.16 : 0.10)
                let offStroke = UiTheme.isDarkMode
                    ? NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.12)
                    : NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.08)
                UiTheme.fillAndStrokeRoundedRect(rect, radius: radius, fillColor: offFill, strokeColor: offStroke, lineWidth: 0.5)
            }

            let knobD = rect.height - 4.0
            let knobX = isChecked ? (rect.maxX - knobD - 2.0) : (rect.minX + 2.0)
            let knobRect = NSRect(x: knobX, y: rect.minY + 2.0, width: knobD, height: knobD)

            if let ctx = NSGraphicsContext.current?.cgContext {
                ctx.saveGState()
                ctx.setShadow(
                    offset: CGSize(width: 0, height: -0.8),
                    blur: 1.6,
                    color: NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.28).cgColor
                )
                ctx.setFillColor(NSColor.white.cgColor)
                ctx.fillEllipse(in: knobRect)
                ctx.restoreGState()
            } else {
                NSColor.white.setFill()
                NSBezierPath(ovalIn: knobRect).fill()
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
                let status = L10n.pullingUpdate(ver, owner.pullProgress)
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
                    L10n.checkingUpdate,
                    in: owner.bottomStatusRowRect,
                    font: subFont,
                    color: UiTheme.textSecondary,
                    alignment: .center
                )
                return
            }

            if let avail = owner.availableUpdate, avail.isNewer {
                let prefix = L10n.newVersionFoundPrefix(avail.latestVersion)
                let actionText = avail.downloadUrl.isEmpty ? L10n.goToDownload : L10n.pullUpdateNow
                let ignoreText = L10n.ignoreUpdate

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

            let checkText = L10n.checkUpdate
            let csz = (checkText as NSString).size(withAttributes: [.font: subFont])
            let cw = ceil(csz.width) + 12
            owner.lnkUpdateActionRect = NSRect(
                x: owner.bottomStatusRowRect.minX + (owner.bottomStatusRowRect.width - cw) / 2.0,
                y: owner.bottomStatusRowRect.minY,
                width: cw,
                height: owner.bottomStatusRowRect.height
            )
            let hover = !owner.isLanguageMenuOpen && owner.lnkUpdateActionRect.contains(owner.mousePos)
            let linkColor = hover ? UiTheme.lighten(UiTheme.linkBlue, delta: 24) : UiTheme.linkBlue
            UiTheme.drawCenteredText(checkText, in: owner.lnkUpdateActionRect, font: subFont, color: linkColor, alignment: .center)
        }

        override func mouseMoved(with event: NSEvent) {
            guard let owner = owner else { return }
            let pt = convert(event.locationInWindow, from: nil)
            owner.mousePos = pt

            if owner.isLanguageMenuOpen {
                if owner.btnLangRect.contains(pt) {
                    NSCursor.pointingHand.set()
                } else {
                    NSCursor.arrow.set()
                }
                needsDisplay = true
                return
            }

            let hasSaveDir = !owner.autoSaveDir.isEmpty
            let inAutoSaveHit = owner.btnChangeSaveDirRect.contains(pt)
                || (hasSaveDir && owner.btnOpenSaveDirRect.contains(pt))
                || (hasSaveDir && owner.lblAutoSavePathRect.contains(pt))
                || (owner.chkAutoSaveRect.contains(pt) && pt.y <= owner.chkAutoSaveRect.minY + 34)
            let inUpdateHit = !owner.checkingUpdate && !owner.pullingUpdate
                && (owner.lnkUpdateActionRect.contains(pt) || owner.lnkIgnoreUpdateRect.contains(pt))

            let clickable = owner.btnLangRect.contains(pt)
                || owner.btnCaptureRect.contains(pt)
                || owner.chkKeepAliveRect.contains(pt)
                || owner.chkHideStatusBarRect.contains(pt)
                || owner.chkAutoStartRect.contains(pt)
                || owner.chkWindowShadowRect.contains(pt)
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

            if owner.btnLangRect.contains(pt) {
                owner.isRecordingHotkey = false
                needsDisplay = true
                owner.popUpLanguageMenu(from: self)
                return
            }

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

            if owner.chkWindowShadowRect.contains(pt) {
                owner.setWindowShadowCapture(!owner.windowShadowCapture)
                needsDisplay = true
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

            if owner.chkAutoSaveRect.contains(pt) && pt.y <= owner.chkAutoSaveRect.minY + 34 {
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
            if owner.isLanguageMenuOpen && event.keyCode == 53 {
                owner.isLanguageMenuOpen = false
                needsDisplay = true
                return
            }
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
        self.windowShadowCapture = prefs.windowShadowCapture
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

        let w: CGFloat = 356
        let h: CGFloat = 438
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let frame = NSRect(
            x: screen.origin.x + (screen.width - w) / 2.0,
            y: screen.origin.y + (screen.height - h) / 2.0,
            width: w,
            height: h
        )

        super.init(
            contentRect: frame,
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        MainForm.shared = self
        self.titlebarAppearsTransparent = true
        self.titleVisibility = .hidden
        let unifiedToolbar = NSToolbar(identifier: "SpanShotMainToolbar")
        unifiedToolbar.allowsUserCustomization = false
        self.toolbar = unifiedToolbar
        self.toolbarStyle = .unified
        self.appearance = NSAppearance(named: UiTheme.isDarkMode ? .darkAqua : .aqua)
        self.isOpaque = true
        self.backgroundColor = UiTheme.bgDark
        self.hasShadow = true
        self.sharingType = .none
        self.isReleasedWhenClosed = false
        self.acceptsMouseMovedEvents = true
        self.delegate = self
        self.title = "SpanShot"

        self.standardWindowButton(.zoomButton)?.isEnabled = false

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
            guard let self = self else { return }
            UiTheme.refreshSystemTheme()
            self.appearance = NSAppearance(named: UiTheme.isDarkMode ? .darkAqua : .aqua)
            self.backgroundColor = UiTheme.bgDark
            self.contentView?.needsDisplay = true
        }
    }

    override public var canBecomeKey: Bool { true }
    override public var canBecomeMain: Bool { true }

    public func windowShouldClose(_ sender: NSWindow) -> Bool {
        if keepInBackground {
            minimizeToTray()
        } else {
            NSApp.terminate(nil)
        }
        return false
    }

    private func computeLayout(width w: CGFloat, height h: CGFloat) {
        let padX: CGFloat = 19
        let fullW = w - padX * 2
        let innerX = padX + 14
        let innerW = fullW - 28

        // Unified 52pt header bar: left traffic lights at x=19, centerY=26; right Globe button at x=w-19-26, centerY=26
        btnLangRect = NSRect(x: w - padX - 26, y: 13, width: 26, height: 26)
        headerRect = NSRect(x: 84, y: 0, width: w - 84 - 48, height: 50)
        btnMinimizeRect = .zero
        btnCloseRect = .zero

        // Primary Capture Action
        btnCaptureRect = NSRect(x: padX, y: 52, width: fullW, height: 44)
        btnHotkeyBadgeRect = NSRect(x: padX + fullW - 84, y: 52 + (44 - 26) / 2, width: 72, height: 26)

        // Section 1: 「截图与保存」 (Capture & Save)
        lblCaptureSectionRect = NSRect(x: padX + 4, y: 106, width: fullW - 8, height: 18)
        captureCardRect = NSRect(x: padX, y: 126, width: fullW, height: 130)
        chkWindowShadowRect = NSRect(x: innerX, y: 126, width: innerW, height: 36)
        chkQuickCopyRect = NSRect(x: innerX, y: 162, width: innerW, height: 36)
        chkAutoSaveRect = NSRect(x: innerX, y: 198, width: innerW, height: 58)

        // Section 2: 「系统与后台」 (System & Background)
        lblSystemSectionRect = NSRect(x: padX + 4, y: 266, width: fullW - 8, height: 18)
        systemCardRect = NSRect(x: padX, y: 286, width: fullW, height: 108)
        chkKeepAliveRect = NSRect(x: innerX, y: 286, width: innerW, height: 36)
        chkHideStatusBarRect = NSRect(x: innerX, y: 322, width: innerW, height: 36)
        chkAutoStartRect = NSRect(x: innerX, y: 358, width: innerW, height: 36)

        // Bottom Status & Update Row
        bottomStatusRowRect = NSRect(x: padX, y: 404, width: fullW, height: 24)
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
            windowShadowCapture: windowShadowCapture,
            quickCopyOnly: quickCopyOnly,
            autoSave: autoSave,
            autoSaveDir: autoSaveDir
        )
    }

    fileprivate func minimizeToTray() {
        isRecordingHotkey = false
        isLanguageMenuOpen = false
        self.orderOut(nil)
        if NSApp.activationPolicy() != .accessory {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    public func windowDidResignKey(_ notification: Notification) {
        if isLanguageMenuOpen {
            isLanguageMenuOpen = false
            contentView?.needsDisplay = true
        }
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
            L10n.statusBarHiddenNotice(val),
            color: UiTheme.weChatGreen
        )
    }

    fileprivate func setWindowShadowCapture(_ val: Bool) {
        windowShadowCapture = val
        saveCurrentPreferences()
        menuWindowShadowItem?.state = val ? .on : .off
        contentView?.needsDisplay = true
        notifyFeedback(
            L10n.windowShadowNotice(val),
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
            notifyFeedback(L10n.autoStartNotice(next), color: UiTheme.weChatGreen)
        } else {
            notifyFeedback(L10n.autoStartFailedNotice, color: UiTheme.accentRed)
        }
    }

    fileprivate func toggleAutoSave() {
        if !autoSave {
            if autoSaveDir.isEmpty {
                chooseAutoSaveDirectory(enableAfterSelect: true)
                return
            }
            if !AppSettings.validateWritableFolder(autoSaveDir) {
                notifyFeedback(L10n.saveDirInvalidNotice, color: UiTheme.accentRed)
                chooseAutoSaveDirectory(enableAfterSelect: true)
                return
            }
            autoSave = true
            saveCurrentPreferences()
            menuAutoSaveItem?.state = .on
            contentView?.needsDisplay = true
            notifyFeedback(L10n.autoSaveEnabledNotice, color: UiTheme.weChatGreen)
        } else {
            autoSave = false
            saveCurrentPreferences()
            menuAutoSaveItem?.state = .off
            contentView?.needsDisplay = true
            notifyFeedback(L10n.autoSaveDisabledNotice, color: UiTheme.textSecondary)
        }
    }

    fileprivate func chooseAutoSaveDirectory(enableAfterSelect: Bool) {
        guard let selected = AppSettings.pickFolderDialog(currentDir: autoSaveDir), !selected.isEmpty else {
            return
        }
        if !AppSettings.validateWritableFolder(selected) {
            notifyFeedback(L10n.chosenDirNotWritableNotice, color: UiTheme.accentRed)
            return
        }
        autoSaveDir = selected
        if enableAfterSelect {
            autoSave = true
        }
        saveCurrentPreferences()
        menuAutoSaveItem?.state = autoSave ? .on : .off
        contentView?.needsDisplay = true
        notifyFeedback(L10n.saveDirUpdatedNotice, color: UiTheme.weChatGreen)
    }

    fileprivate func openAutoSaveDirectory() {
        var isDir: ObjCBool = false
        guard !autoSaveDir.isEmpty,
              FileManager.default.fileExists(atPath: autoSaveDir, isDirectory: &isDir),
              isDir.boolValue else {
            notifyFeedback(L10n.dirNotFoundNotice, color: UiTheme.accentRed)
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
                    let msg = result.errorMessage.isEmpty ? L10n.checkUpdateFailedNotice : result.errorMessage
                    self.notifyFeedback(msg, color: UiTheme.accentRed)
                } else if result.isNewer {
                    self.availableUpdate = result
                    self.noticeText = ""
                } else {
                    self.availableUpdate = nil
                    self.notifyFeedback(L10n.alreadyLatestVersionNotice(UpdateManager.currentVersion), color: UiTheme.weChatGreen)
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
                        if msg.contains("重启") || msg.contains("重啟") || msg.lowercased().contains("restarting") {
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

    fileprivate func popUpLanguageMenu(from view: NSView) {
        let menu = NSMenu()
        for lang in AppLanguage.allCases {
            let item = NSMenuItem(title: lang.displayName, action: #selector(onSelectLanguageItem(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = lang.rawValue
            item.state = (lang == L10n.current) ? .on : .off
            menu.addItem(item)
        }
        menu.update()
        let menuW = max(138.0, ceil(menu.size.width))
        let x = max(19.0, btnLangRect.maxX - menuW)
        let y = btnLangRect.maxY + 4.0
        menu.popUp(positioning: nil, at: NSPoint(x: x, y: y), in: view)
    }

    @objc private func onSelectLanguageItem(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let lang = AppLanguage.fromCode(raw) else { return }
        applyLanguage(lang)
    }

    private func applyLanguage(_ lang: AppLanguage) {
        L10n.setLanguage(lang)
        saveCurrentPreferences()
        rebuildStatusMenu()
        Self.rebuildApplicationMainMenu(mainForm: self)
        contentView?.needsDisplay = true
        showInlineNotice(message: L10n.languageSwitchedNotice(lang), color: UiTheme.weChatGreen)
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let btn = item.button {
            btn.image = AppIconRenderer.renderStatusBarTemplateIcon()
            btn.imagePosition = .imageOnly
        }
        self.statusItem = item
        rebuildStatusMenu()
        item.isVisible = !hideStatusBarIcon
    }

    private func rebuildStatusMenu() {
        guard let item = statusItem else { return }
        item.button?.toolTip = L10n.statusTooltip(hotkeyDisplay)

        let menu = NSMenu()

        let captureItem = NSMenuItem(title: L10n.menuStartCapture(hotkeyDisplay), action: #selector(onMenuCapture), keyEquivalent: "")
        captureItem.target = self
        menu.addItem(captureItem)
        self.menuCaptureItem = captureItem

        let vScrollItem = NSMenuItem(title: L10n.menuVerticalScroll, action: #selector(onMenuVerticalScroll), keyEquivalent: "")
        vScrollItem.target = self
        menu.addItem(vScrollItem)

        let hScrollItem = NSMenuItem(title: L10n.menuHorizontalScroll, action: #selector(onMenuHorizontalScroll), keyEquivalent: "")
        hScrollItem.target = self
        menu.addItem(hScrollItem)

        menu.addItem(.separator())

        let winShadowItem = NSMenuItem(title: L10n.menuWindowShadow, action: #selector(onMenuToggleWindowShadow), keyEquivalent: "")
        winShadowItem.target = self
        winShadowItem.state = windowShadowCapture ? .on : .off
        menu.addItem(winShadowItem)
        self.menuWindowShadowItem = winShadowItem

        let quickItem = NSMenuItem(title: L10n.menuQuickCopy, action: #selector(onMenuToggleQuickCopy), keyEquivalent: "")
        quickItem.target = self
        quickItem.state = quickCopyOnly ? .on : .off
        menu.addItem(quickItem)
        self.menuQuickCopyItem = quickItem

        let autoSaveItem = NSMenuItem(title: L10n.menuAutoSave, action: #selector(onMenuToggleAutoSave), keyEquivalent: "")
        autoSaveItem.target = self
        autoSaveItem.state = autoSave ? .on : .off
        menu.addItem(autoSaveItem)
        self.menuAutoSaveItem = autoSaveItem

        let pickDirItem = NSMenuItem(title: L10n.menuPickAutoSaveDir, action: #selector(onMenuPickAutoSaveDir), keyEquivalent: "")
        pickDirItem.target = self
        menu.addItem(pickDirItem)

        menu.addItem(.separator())

        let keepItem = NSMenuItem(title: L10n.menuKeepAlive, action: #selector(onMenuToggleKeepAlive), keyEquivalent: "")
        keepItem.target = self
        keepItem.state = keepInBackground ? .on : .off
        menu.addItem(keepItem)
        self.menuKeepAliveItem = keepItem

        let hideBarItem = NSMenuItem(title: L10n.menuHideStatusBar, action: #selector(onMenuToggleHideStatusBar), keyEquivalent: "")
        hideBarItem.target = self
        hideBarItem.state = hideStatusBarIcon ? .on : .off
        menu.addItem(hideBarItem)
        self.menuHideStatusBarItem = hideBarItem

        let autoStartItem = NSMenuItem(title: L10n.menuAutoStart, action: #selector(onMenuToggleAutoStart), keyEquivalent: "")
        autoStartItem.target = self
        autoStartItem.state = autoStart ? .on : .off
        menu.addItem(autoStartItem)
        self.menuAutoStartItem = autoStartItem

        let langRootItem = NSMenuItem(title: L10n.menuLanguage, action: nil, keyEquivalent: "")
        let langSubmenu = NSMenu(title: L10n.menuLanguage)
        for lang in AppLanguage.allCases {
            let lItem = NSMenuItem(title: lang.displayName, action: #selector(onSelectLanguageItem(_:)), keyEquivalent: "")
            lItem.target = self
            lItem.representedObject = lang.rawValue
            lItem.state = (lang == L10n.current) ? .on : .off
            langSubmenu.addItem(lItem)
        }
        langRootItem.submenu = langSubmenu
        menu.addItem(langRootItem)

        menu.addItem(.separator())

        let updateItem = NSMenuItem(title: L10n.menuCheckUpdate, action: #selector(onMenuCheckUpdate), keyEquivalent: "")
        updateItem.target = self
        menu.addItem(updateItem)

        let showItem = NSMenuItem(title: L10n.menuShowMain, action: #selector(onMenuShowMain), keyEquivalent: "")
        showItem.target = self
        menu.addItem(showItem)

        let quitItem = NSMenuItem(title: L10n.menuQuitApp, action: #selector(onMenuQuit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        item.menu = menu
    }

    public static func rebuildApplicationMainMenu(mainForm: MainForm) {
        let mainMenu = NSMenu()

        // 1. Application Menu
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenuItem.submenu = appMenu

        let aboutItem = NSMenuItem(
            title: L10n.tr("关于 SpanShot", "關於 SpanShot", "About SpanShot"),
            action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
            keyEquivalent: ""
        )
        appMenu.addItem(aboutItem)
        appMenu.addItem(.separator())

        let captureItem = NSMenuItem(title: L10n.startCapture, action: #selector(MainForm.onMenuCapture), keyEquivalent: "A")
        captureItem.keyEquivalentModifierMask = [.command, .shift]
        captureItem.target = mainForm
        appMenu.addItem(captureItem)

        let vScrollItem = NSMenuItem(title: L10n.titleVerticalScroll, action: #selector(MainForm.onMenuVerticalScroll), keyEquivalent: "")
        vScrollItem.target = mainForm
        appMenu.addItem(vScrollItem)

        let hScrollItem = NSMenuItem(title: L10n.titleHorizontalScroll, action: #selector(MainForm.onMenuHorizontalScroll), keyEquivalent: "")
        hScrollItem.target = mainForm
        appMenu.addItem(hScrollItem)

        appMenu.addItem(.separator())

        let hideItem = NSMenuItem(
            title: L10n.tr("隐藏 SpanShot", "隱藏 SpanShot", "Hide SpanShot"),
            action: #selector(NSApplication.hide(_:)),
            keyEquivalent: "h"
        )
        appMenu.addItem(hideItem)

        let quitItem = NSMenuItem(
            title: L10n.tr("退出 SpanShot", "退出 SpanShot", "Quit SpanShot"),
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        appMenu.addItem(quitItem)

        // 2. Edit Menu
        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)
        let editMenu = NSMenu(title: L10n.tr("编辑", "編輯", "Edit"))
        editMenuItem.submenu = editMenu

        editMenu.addItem(withTitle: L10n.tr("撤销", "復原", "Undo"), action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: L10n.tr("剪切", "剪下", "Cut"), action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: L10n.tr("复制", "複製", "Copy"), action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: L10n.tr("粘贴", "貼上", "Paste"), action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: L10n.tr("全选", "全選", "Select All"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        // 3. Window Menu
        let windowMenuItem = NSMenuItem()
        mainMenu.addItem(windowMenuItem)
        let windowMenu = NSMenu(title: L10n.tr("窗口", "視窗", "Window"))
        windowMenuItem.submenu = windowMenu

        let showMainItem = NSMenuItem(title: L10n.menuShowMain, action: #selector(MainForm.onMenuShowMain), keyEquivalent: "0")
        showMainItem.target = mainForm
        windowMenu.addItem(showMainItem)

        windowMenu.addItem(withTitle: L10n.tr("最小化", "最小化", "Minimize"), action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: L10n.tr("关闭窗口", "關閉視窗", "Close Window"), action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")

        NSApp.mainMenu = mainMenu
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
        menuCaptureItem?.title = L10n.menuStartCapture(hotkeyDisplay)
        statusItem?.button?.toolTip = L10n.statusTooltip(hotkeyDisplay)
        notifyFeedback(L10n.hotkeyUpdatedNotice(hotkeyDisplay), color: UiTheme.weChatGreen)
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

    @objc private func onMenuToggleWindowShadow() {
        setWindowShadowCapture(!windowShadowCapture)
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
        self.appearance = NSAppearance(named: UiTheme.isDarkMode ? .darkAqua : .aqua)
        self.backgroundColor = UiTheme.bgDark
        if NSApp.activationPolicy() != .regular {
            NSApp.setActivationPolicy(.regular)
            NSApp.applicationIconImage = AppIconRenderer.renderAppIconImage(pointSize: 512, useSystemGridMargin: true)
            MainForm.rebuildApplicationMainMenu(mainForm: self)
        }
        if self.isMiniaturized {
            self.deminiaturize(nil)
        }
        NSApp.activate(ignoringOtherApps: true)
        self.makeKeyAndOrderFront(nil)
        self.contentView?.needsDisplay = true
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            NSApp.activate(ignoringOtherApps: true)
            self.makeKeyAndOrderFront(nil)
        }
    }

    @objc public func onMenuQuit() {
        NSApp.terminate(nil)
    }

    private func copyAndOptionalAutoSave(_ bmp: RawBitmap, tag: String) {
        UiTheme.copyBitmapToClipboard(bmp)

        if autoSave {
            if AppSettings.tryAutoSaveBitmap(bmp, folderPath: autoSaveDir, tag: tag) != nil {
                notifyFeedback(L10n.copiedAndAutoSaved(bmp.width, bmp.height), color: UiTheme.weChatGreen)
            } else {
                autoSave = false
                saveCurrentPreferences()
                menuAutoSaveItem?.state = .off
                contentView?.needsDisplay = true
                notifyFeedback(L10n.copiedButAutoSaveFailed, color: UiTheme.accentRed)
            }
        } else {
            notifyFeedback(L10n.copiedToClipboardSize(bmp.width, bmp.height), color: UiTheme.weChatGreen)
        }
    }

    private func openPreviewAndOptionalAutoSave(_ bmp: RawBitmap, titleTag: String, fileTag: String) {
        let editor = ResultPreviewForm(bitmap: bmp, captureTypeTag: titleTag, initialSaveDir: autoSaveDir)
        editor.showModalOrFloating { [weak self] closedEditor in
            guard let self = self else { return }
            if self.autoSave && !closedEditor.manuallySaved {
                if AppSettings.tryAutoSaveBitmap(closedEditor.finalWorkingBitmap, folderPath: self.autoSaveDir, tag: fileTag) != nil {
                    self.notifyFeedback(closedEditor.confirmedCopy ? L10n.copiedAndAutoSavedShort : L10n.autoSavedShort, color: UiTheme.weChatGreen)
                } else {
                    self.autoSave = false
                    self.saveCurrentPreferences()
                    self.menuAutoSaveItem?.state = .off
                    self.contentView?.needsDisplay = true
                    self.notifyFeedback(L10n.dirNotWritableAutoSaveDisabled, color: UiTheme.accentRed)
                }
            } else if !closedEditor.manuallySaved && closedEditor.confirmedCopy {
                self.notifyFeedback(L10n.copiedToClipboardShort, color: UiTheme.weChatGreen)
            }
        }
    }

    private func saveBitmapDialog(_ bmp: RawBitmap, tag: String) {
        if UiTheme.saveBitmapDialog(bmp, tag: tag, initialDir: autoSaveDir) {
            notifyFeedback(L10n.savedShort, color: UiTheme.weChatGreen)
        }
    }

    public func startCaptureFlow(preset: CaptureActionMode = .none) {
        guard !isCapturing else { return }
        ScreenCapturer.invalidateShareableContentCache()
        switch ScreenCapturer.checkOrRequestPermissionState() {
        case .granted:
            break
        case .promptedSystemDialog:
            notifyFeedback(L10n.permissionPromptDialogNotice, color: UiTheme.accentOrange)
            return
        case .relaunchingWithNewPermission:
            return
        case .denied:
            notifyFeedback(L10n.permissionDeniedSettingsNotice, color: UiTheme.accentRed)
            ScreenCapturer.openScreenCaptureSettings()
            return
        }
        isCapturing = true
        isRecordingHotkey = false
        isLanguageMenuOpen = false

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
        let selector = RegionSelectorForm(presetMode: preset, windowShadowCapture: windowShadowCapture)
        if selector.captureWasBlockedByPermission {
            self.restoreMainIfNeeded(wasMainVisible)
            self.notifyFeedback(L10n.permissionDeniedSettingsNotice, color: UiTheme.accentRed)
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
                        self.openPreviewAndOptionalAutoSave(bmp, titleTag: L10n.titleNormalShot, fileTag: "Shot")
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
                                titleTag: dir == .vertical ? L10n.titleVerticalScroll : L10n.titleHorizontalScroll,
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
            self.appearance = NSAppearance(named: UiTheme.isDarkMode ? .darkAqua : .aqua)
            self.backgroundColor = UiTheme.bgDark
            self.makeKeyAndOrderFront(nil)
            self.contentView?.needsDisplay = true
        }
        captureWasNormalVisible = false
        isCapturing = false
    }
}
