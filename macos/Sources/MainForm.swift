import AppKit
import Carbon
import Foundation

/// Minimalist dark main window + NSStatusItem menu bar agent (1:1 port of src/MainForm.cs, enhanced for macOS).
public final class MainForm: NSWindow {
    private static let prefKeyKeepAlive = "SpanShot.KeepInBackground"
    private static let prefKeyQuickCopy = "SpanShot.QuickCopyOnly"
    private static let prefKeyHotkeyCode = "SpanShot.HotkeyKeyCode"
    private static let prefKeyHotkeyMods = "SpanShot.HotkeyCarbonMods"
    private static let prefKeyHotkeyLabel = "SpanShot.HotkeyDisplay"

    fileprivate var statusItem: NSStatusItem?
    fileprivate var menuCaptureItem: NSMenuItem?
    fileprivate var menuQuickCopyItem: NSMenuItem?
    fileprivate var menuKeepAliveItem: NSMenuItem?

    fileprivate var isCapturing = false
    fileprivate var keepInBackground = true
    fileprivate var quickCopyOnly = false

    fileprivate var hotkeyKeyCode: UInt32 = UInt32(kVK_ANSI_A)
    fileprivate var hotkeyCarbonMods: UInt32 = UInt32(cmdKey | shiftKey)
    fileprivate var hotkeyDisplay: String = "⌘⇧A"
    fileprivate var isRecordingHotkey = false

    fileprivate var draggingWindow = false
    fileprivate var dragStartScreenPt: NSPoint = .zero
    fileprivate var winStartOrigin: NSPoint = .zero
    fileprivate var mousePos: NSPoint = .zero

    fileprivate let brandIconImage: NSImage
    fileprivate let headerRect = NSRect(x: 0, y: 0, width: 250, height: 44)
    fileprivate let btnCloseRect = NSRect(x: 296 - 36, y: 10, width: 26, height: 24)
    fileprivate let btnCaptureRect = NSRect(x: 16, y: 48, width: 296 - 32, height: 46)
    fileprivate let btnHotkeyBadgeRect = NSRect(x: 16 + (296 - 32) - 82, y: 48 + (46 - 26) / 2, width: 70, height: 26)
    fileprivate let chkKeepAliveRect = NSRect(x: 16, y: 106, width: 296 - 32, height: 26)
    fileprivate let chkQuickCopyRect = NSRect(x: 16, y: 138, width: 296 - 32, height: 44)

    private var activeSelector: RegionSelectorForm?
    private var activeScrollSession: ScrollCaptureSessionForm?
    private var hotKeyRefs: [EventHotKeyRef?] = []
    private var eventHandlerinstalled = false

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

            let outer = bounds.insetBy(dx: 0.5, dy: 0.5)
            UiTheme.fillRoundedRect(outer, radius: 10, color: UiTheme.bgDark)
            UiTheme.strokeRoundedRect(outer, radius: 10, color: UiTheme.borderSubtle, lineWidth: 1.0)

            // Brand icon + Title in header
            let iconRect = NSRect(x: 14, y: 11, width: 22, height: 22)
            NSGraphicsContext.current?.imageInterpolation = .high
            owner.brandIconImage.draw(
                in: iconRect,
                from: .zero,
                operation: .sourceOver,
                fraction: 1.0,
                respectFlipped: true,
                hints: nil
            )

            let brandFont = UiTheme.fontPx(15, bold: true)
            UiTheme.drawCenteredText(
                "SpanShot",
                in: NSRect(x: 41, y: 6, width: 160, height: 32),
                font: brandFont,
                color: .white,
                alignment: .left
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

            drawCheckboxOption(
                rect: owner.chkKeepAliveRect,
                label: "常驻后台",
                subNote: nil,
                isChecked: owner.keepInBackground,
                hovered: owner.chkKeepAliveRect.contains(owner.mousePos)
            )

            drawCheckboxOption(
                rect: owner.chkQuickCopyRect,
                label: "快捷截图",
                subNote: "截图完默认只复制到剪贴板，不弹窗",
                isChecked: owner.quickCopyOnly,
                hovered: owner.chkQuickCopyRect.contains(owner.mousePos)
            )
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
                badgeBg = NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 52 / 255.0)
            }
            UiTheme.fillRoundedRect(badgeRect, radius: 5, color: badgeBg)
            if recording || badgeHovered {
                UiTheme.strokeRoundedRect(
                    badgeRect,
                    radius: 5,
                    color: recording ? .white : NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.45),
                    lineWidth: 1.0
                )
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
                UiTheme.fillRoundedRect(boxRect, radius: 4, color: UiTheme.bgCard)
                UiTheme.strokeRoundedRect(
                    boxRect,
                    radius: 4,
                    color: hovered ? UiTheme.weChatGreen : UiTheme.borderSubtle,
                    lineWidth: 1.0
                )
            }

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

        override func mouseMoved(with event: NSEvent) {
            guard let owner = owner else { return }
            let pt = convert(event.locationInWindow, from: nil)
            owner.mousePos = pt
            let clickable = owner.btnCloseRect.contains(pt) ||
                            owner.btnCaptureRect.contains(pt) ||
                            owner.chkKeepAliveRect.contains(pt) ||
                            owner.chkQuickCopyRect.contains(pt)
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

            if owner.btnCloseRect.contains(pt) {
                if owner.keepInBackground {
                    owner.orderOut(nil)
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
            if owner.chkQuickCopyRect.contains(pt) {
                owner.setQuickCopyOnly(!owner.quickCopyOnly)
                needsDisplay = true
                return
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
        self.brandIconImage = AppIconRenderer.renderAppIconImage(pointSize: 22)

        let defaults = UserDefaults.standard
        if defaults.object(forKey: Self.prefKeyKeepAlive) != nil {
            self.keepInBackground = defaults.bool(forKey: Self.prefKeyKeepAlive)
        }
        if defaults.object(forKey: Self.prefKeyQuickCopy) != nil {
            self.quickCopyOnly = defaults.bool(forKey: Self.prefKeyQuickCopy)
        }
        if let savedLabel = defaults.string(forKey: Self.prefKeyHotkeyLabel), !savedLabel.isEmpty {
            self.hotkeyKeyCode = UInt32(defaults.integer(forKey: Self.prefKeyHotkeyCode))
            self.hotkeyCarbonMods = UInt32(defaults.integer(forKey: Self.prefKeyHotkeyMods))
            self.hotkeyDisplay = savedLabel
        }

        let w: CGFloat = 296
        let h: CGFloat = 198
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

        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = true
        self.isReleasedWhenClosed = false
        self.acceptsMouseMovedEvents = true
        self.title = "SpanShot"

        let view = MainPanelView(frame: NSRect(x: 0, y: 0, width: w, height: h))
        view.owner = self
        self.contentView = view

        setupStatusItem()
        registerGlobalHotkeys()
    }

    override public var canBecomeKey: Bool { true }
    override public var canBecomeMain: Bool { true }

    fileprivate func setKeepInBackground(_ val: Bool) {
        keepInBackground = val
        UserDefaults.standard.set(val, forKey: Self.prefKeyKeepAlive)
        menuKeepAliveItem?.state = val ? .on : .off
        contentView?.needsDisplay = true
    }

    fileprivate func setQuickCopyOnly(_ val: Bool) {
        quickCopyOnly = val
        UserDefaults.standard.set(val, forKey: Self.prefKeyQuickCopy)
        menuQuickCopyItem?.state = val ? .on : .off
        contentView?.needsDisplay = true
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

        let keepItem = NSMenuItem(title: "常驻后台", action: #selector(onMenuToggleKeepAlive), keyEquivalent: "")
        keepItem.target = self
        keepItem.state = keepInBackground ? .on : .off
        menu.addItem(keepItem)
        self.menuKeepAliveItem = keepItem

        menu.addItem(.separator())

        let showItem = NSMenuItem(title: "显示主窗口", action: #selector(onMenuShowMain), keyEquivalent: "")
        showItem.target = self
        menu.addItem(showItem)

        let quitItem = NSMenuItem(title: "彻底退出 SpanShot", action: #selector(onMenuQuit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        item.menu = menu
        self.statusItem = item
    }

    private func registerGlobalHotkeys() {
        for ref in hotKeyRefs {
            if let r = ref {
                UnregisterEventHotKey(r)
            }
        }
        hotKeyRefs.removeAll()

        if !eventHandlerinstalled {
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
            eventHandlerinstalled = true
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

        // Require at least one modifier key (or F1..F12)
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
        ToastWindow.showToast(message: "快捷键已设为 \(hotkeyDisplay)", accent: UiTheme.weChatGreen)
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

    @objc private func onMenuToggleKeepAlive() {
        setKeepInBackground(!keepInBackground)
    }

    @objc public func onMenuShowMain() {
        NSApp.activate(ignoringOtherApps: true)
        self.makeKeyAndOrderFront(nil)
    }

    @objc public func onMenuQuit() {
        NSApp.terminate(nil)
    }

    public func startCaptureFlow(preset: CaptureActionMode = .none) {
        guard !isCapturing else { return }
        _ = ScreenCapturer.ensureScreenCapturePermission()
        isCapturing = true
        isRecordingHotkey = false

        let wasVisible = self.isVisible
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
                        UiTheme.copyBitmapWithToast(bmp)
                    } else {
                        let editor = ResultPreviewForm(bitmap: bmp, captureTypeTag: "截图")
                        editor.showModalOrFloating()
                    }
                }
                self.restoreMainIfNeeded(wasMainVisible)
                return
            }

            if chosen == .normalPinCompleted {
                if let bmp = annotatedBmp {
                    UiTheme.copyBitmapWithToast(bmp)
                    let pin = PinWindowForm(sourceBitmap: bmp, initialTopDownLocation: selectedRect.origin)
                    pin.showPin()
                }
                self.restoreMainIfNeeded(wasMainVisible)
                return
            }

            if chosen == .normalSaveCompleted {
                if let bmp = annotatedBmp {
                    UiTheme.saveBitmapDialog(bmp, tag: "Shot")
                }
                self.restoreMainIfNeeded(wasMainVisible)
                return
            }

            let dir: ScrollDirection = (chosen == .verticalScroll) ? .vertical : .horizontal
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                guard let self = self else { return }
                let session = ScrollCaptureSessionForm(physicalCaptureRect: selectedRect, direction: dir)
                self.activeScrollSession = session
                session.startSession { [weak self] stitchedResult, exitAction in
                    guard let self = self else { return }
                    self.activeScrollSession = nil

                    if let resultBmp = stitchedResult, exitAction != .cancelled {
                        if self.quickCopyOnly || exitAction == .copyDirectly {
                            UiTheme.copyBitmapWithToast(resultBmp)
                        } else if exitAction == .pinDirectly {
                            UiTheme.copyBitmapWithToast(resultBmp)
                            let pin = PinWindowForm(sourceBitmap: resultBmp)
                            pin.showPin()
                        } else if exitAction == .saveDirectly {
                            UiTheme.saveBitmapDialog(resultBmp, tag: dir == .vertical ? "Vertical" : "Horizontal")
                        } else if exitAction == .openEditor {
                            let editor = ResultPreviewForm(
                                bitmap: resultBmp,
                                captureTypeTag: dir == .vertical ? "纵向长截图" : "横向长截图"
                            )
                            editor.showModalOrFloating()
                        }
                    }

                    self.restoreMainIfNeeded(wasMainVisible)
                }
            }
        }
    }

    private func restoreMainIfNeeded(_ wasMainVisible: Bool) {
        if wasMainVisible {
            self.makeKeyAndOrderFront(nil)
        }
        isCapturing = false
    }
}
