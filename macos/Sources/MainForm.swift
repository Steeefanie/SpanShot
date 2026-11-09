import AppKit
import Carbon
import Foundation

/// Minimalist dark main window + NSStatusItem menu bar agent (1:1 port of src/MainForm.cs).
public final class MainForm: NSWindow {
    fileprivate var statusItem: NSStatusItem?
    fileprivate var isCapturing = false
    fileprivate var keepInBackground = true
    fileprivate var quickCopyOnly = false

    fileprivate var draggingWindow = false
    fileprivate var dragStartScreenPt: NSPoint = .zero
    fileprivate var winStartOrigin: NSPoint = .zero
    fileprivate var mousePos: NSPoint = .zero

    fileprivate let headerRect = NSRect(x: 0, y: 0, width: 250, height: 44)
    fileprivate let btnCloseRect = NSRect(x: 296 - 36, y: 10, width: 26, height: 24)
    fileprivate let btnCaptureRect = NSRect(x: 16, y: 48, width: 296 - 32, height: 46)
    fileprivate let chkKeepAliveRect = NSRect(x: 16, y: 106, width: 296 - 32, height: 26)
    fileprivate let chkQuickCopyRect = NSRect(x: 16, y: 138, width: 296 - 32, height: 44)

    private var activeSelector: RegionSelectorForm?
    private var activeScrollSession: ScrollCaptureSessionForm?
    private var hotKeyRef: EventHotKeyRef?

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

            let brandFont = UiTheme.fontPx(15, bold: true)
            UiTheme.drawCenteredText(
                "SpanShot",
                in: NSRect(x: 16, y: 6, width: 160, height: 32),
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

            drawCaptureButton(
                rect: owner.btnCaptureRect,
                label: "开始截图",
                hotkey: "Alt + A",
                hovered: owner.btnCaptureRect.contains(owner.mousePos)
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

        private func drawCaptureButton(rect: NSRect, label: String, hotkey: String, hovered: Bool) {
            let bg = hovered ? UiTheme.lighten(UiTheme.weChatGreen, delta: 14) : UiTheme.weChatGreen
            UiTheme.fillRoundedRect(rect, radius: 8, color: bg)

            let textRect = NSRect(x: rect.minX + 18, y: rect.minY, width: rect.width - 100, height: rect.height)
            UiTheme.drawCenteredText(label, in: textRect, font: UiTheme.fontPx(15, bold: true), color: .white, alignment: .left)

            let hkRect = NSRect(x: rect.maxX - 76, y: rect.minY + (rect.height - 24) / 2, width: 60, height: 24)
            UiTheme.fillRoundedRect(hkRect, radius: 5, color: NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 45 / 255.0))
            UiTheme.drawCenteredText(hotkey, in: hkRect, font: UiTheme.fontPx(12), color: .white, alignment: .center)
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
            owner.mousePos = convert(event.locationInWindow, from: nil)
            needsDisplay = true
        }

        override func mouseDown(with event: NSEvent) {
            guard let owner = owner else { return }
            let pt = convert(event.locationInWindow, from: nil)

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
                owner.startCaptureFlow()
                return
            }
            if owner.chkKeepAliveRect.contains(pt) {
                owner.keepInBackground.toggle()
                needsDisplay = true
                return
            }
            if owner.chkQuickCopyRect.contains(pt) {
                owner.quickCopyOnly.toggle()
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
    }

    public init() {
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
        self.title = "SpanShot"

        let view = MainPanelView(frame: NSRect(x: 0, y: 0, width: w, height: h))
        view.owner = self
        self.contentView = view

        setupStatusItem()
        registerGlobalHotkey()
    }

    override public var canBecomeKey: Bool { true }
    override public var canBecomeMain: Bool { true }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "SpanShot"

        let menu = NSMenu()
        let captureItem = NSMenuItem(title: "截图 (Alt+A)", action: #selector(onMenuCapture), keyEquivalent: "")
        captureItem.target = self
        menu.addItem(captureItem)

        menu.addItem(.separator())

        let showItem = NSMenuItem(title: "显示主窗口", action: #selector(onMenuShowMain), keyEquivalent: "")
        showItem.target = self
        menu.addItem(showItem)

        let quitItem = NSMenuItem(title: "彻底退出", action: #selector(onMenuQuit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        item.menu = menu
        self.statusItem = item
    }

    private func registerGlobalHotkey() {
        // Register Option+A (Alt+A, keyCode 0 = 'A', optionKey = 2048) via Carbon EventHotKey
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        InstallEventHandler(
            GetApplicationEventTarget(),
            { (_, _, userData) -> OSStatus in
                guard let userData = userData else { return noErr }
                let mainForm = Unmanaged<MainForm>.fromOpaque(userData).takeUnretainedValue()
                DispatchQueue.main.async {
                    mainForm.startCaptureFlow()
                }
                return noErr
            },
            1,
            &eventType,
            selfPtr,
            nil
        )

        let hotKeyID = EventHotKeyID(signature: OSType(0x53505348), id: 9001) // 'SPSH'
        RegisterEventHotKey(
            UInt32(kVK_ANSI_A),
            UInt32(optionKey),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
    }

    @objc private func onMenuCapture() {
        startCaptureFlow()
    }

    @objc public func onMenuShowMain() {
        NSApp.activate(ignoringOtherApps: true)
        self.makeKeyAndOrderFront(nil)
    }

    @objc private func onMenuQuit() {
        NSApp.terminate(nil)
    }

    public func startCaptureFlow() {
        guard !isCapturing else { return }
        isCapturing = true

        let wasVisible = self.isVisible
        if wasVisible {
            self.orderOut(nil)
        }

        let delay: TimeInterval = wasVisible ? 0.12 : 0.02
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.presentRegionSelector(wasMainVisible: wasVisible)
        }
    }

    private func presentRegionSelector(wasMainVisible: Bool) {
        let selector = RegionSelectorForm(presetMode: .none)
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
