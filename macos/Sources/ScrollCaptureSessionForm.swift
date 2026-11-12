import AppKit
import CoreGraphics
import Foundation

public enum ScrollSessionExitAction: Int {
    case cancelled = 0
    case copyDirectly = 1
    case pinDirectly = 2
    case saveDirectly = 3
    case openEditor = 4
}

/// 3px green (#07C160) hollow click-through border outside the capture rect.
/// Excluded from screen capture via sharingType = .none and ignoresMouseEvents = true.
internal final class HollowBorderOverlay: NSPanel {
    private let borderThickness: CGFloat = 3.0

    private final class HollowBorderView: NSView {
        let thickness: CGFloat

        init(frame: NSRect, thickness: CGFloat) {
            self.thickness = thickness
            super.init(frame: frame)
        }

        required init?(coder: NSCoder) { fatalError() }

        override var isFlipped: Bool { true }

        override func draw(_ dirtyRect: NSRect) {
            NSColor.clear.setFill()
            bounds.fill()

            let path = NSBezierPath(rect: bounds)
            path.appendRect(bounds.insetBy(dx: thickness, dy: thickness))
            path.windingRule = .evenOdd
            UiTheme.hollowBorderGreen.setFill()
            path.fill()
        }
    }

    init(topDownTargetRect: CGRect) {
        let expandedTopDown = topDownTargetRect.integral.insetBy(dx: -borderThickness, dy: -borderThickness).integral
        let cocoaFrame = ScreenCapturer.topDownToCocoa(expandedTopDown).integral

        super.init(
            contentRect: cocoaFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = false
        self.level = .statusBar
        self.ignoresMouseEvents = true
        self.sharingType = .none
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.contentView = HollowBorderView(
            frame: NSRect(x: 0, y: 0, width: cocoaFrame.width, height: cocoaFrame.height),
            thickness: borderThickness
        )
    }
}

/// Floating 210x250 live preview & control panel docked outside the capture region (1:1 port of src/ScrollCaptureSessionForm.cs).
public final class ScrollCaptureSessionForm: NSPanel {
    fileprivate let captureRectTopDown: CGRect
    fileprivate let direction: ScrollDirection
    fileprivate let engine: StitchEngine
    fileprivate let borderOverlay: HollowBorderOverlay
    fileprivate var captureTimer: Timer?
    fileprivate var keyMonitor: Any?
    fileprivate var localKeyMonitor: Any?

    fileprivate var autoScrolling = false
    fileprivate var autoScrollTickCounter = 0
    fileprivate var noMoveAutoCount = 0
    fileprivate var horizMethod: HorizontalScrollMethod = .nativeHWheel

    private static let autoScrollWheelAmount: Int32 = 56
    private static let autoScrollTickModulo = 4

    fileprivate var draggingPanel = false
    fileprivate var dragStartScreenPt: NSPoint = .zero
    fileprivate var winStartOrigin: NSPoint = .zero
    fileprivate var mousePos: NSPoint = .zero

    fileprivate var dimensionText: String = ""
    fileprivate var latestPreviewImage: NSImage?

    fileprivate var headerDragRect: NSRect = .zero
    fileprivate var previewCanvasRect: NSRect = .zero
    fileprivate var btnAutoToggleRect: NSRect = .zero
    fileprivate var btnCancelRect: NSRect = .zero
    fileprivate var btnFinishRect: NSRect = .zero

    public private(set) var finalStitchedBitmap: RawBitmap?
    public private(set) var exitAction: ScrollSessionExitAction = .cancelled
    private var onSessionFinished: ((RawBitmap?, ScrollSessionExitAction) -> Void)?
    private var isCompleted = false

    private final class SessionPanelView: NSView {
        weak var owner: ScrollCaptureSessionForm?

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
                radius: 12,
                fillColor: UiTheme.toolbarBg,
                strokeColor: UiTheme.weChatGreen,
                lineWidth: 1.0
            )

            let pad: CGFloat = 8
            let title = owner.direction == .vertical ? "纵向长截图" : "横向长截图"
            let headerInner = NSRect(x: pad, y: 0, width: bounds.width - pad * 2, height: 32)
            UiTheme.drawCenteredText(title, in: headerInner, font: UiTheme.fontPx(13, bold: true), color: UiTheme.textPrimary, alignment: .left)
            UiTheme.drawCenteredText(owner.dimensionText, in: headerInner, font: UiTheme.fontPx(12, bold: false), color: UiTheme.textSecondary, alignment: .right)

            UiTheme.fillAndStrokeRoundedRect(
                owner.previewCanvasRect,
                radius: 5,
                fillColor: UiTheme.canvasBg,
                strokeColor: UiTheme.borderSubtle,
                lineWidth: 1.0
            )

            if let previewImg = owner.latestPreviewImage {
                let px = owner.previewCanvasRect.origin.x + (owner.previewCanvasRect.width - previewImg.size.width) / 2.0
                let py = owner.previewCanvasRect.origin.y + (owner.previewCanvasRect.height - previewImg.size.height) / 2.0
                previewImg.draw(
                    in: NSRect(x: px, y: py, width: previewImg.size.width, height: previewImg.size.height),
                    from: .zero,
                    operation: .sourceOver,
                    fraction: 1.0,
                    respectFlipped: true,
                    hints: nil
                )
            }

            let btnFont = UiTheme.fontPx(12, bold: false)
            UiTheme.drawPillButton(
                rect: owner.btnAutoToggleRect,
                text: owner.autoScrolling ? "暂停" : "自动滚动",
                baseColor: owner.autoScrolling ? UiTheme.accentOrange : UiTheme.bgPill,
                hovered: owner.btnAutoToggleRect.contains(owner.mousePos),
                radius: 3,
                font: btnFont,
                textColor: owner.autoScrolling ? .black : UiTheme.textPrimary
            )

            if owner.btnCancelRect.contains(owner.mousePos) {
                UiTheme.fillRoundedRect(owner.btnCancelRect, radius: 3, color: UiTheme.toolbarHover)
            }
            let cancelIconColor = owner.btnCancelRect.contains(owner.mousePos)
                ? UiTheme.accentRed
                : UiTheme.textSecondary
            UiTheme.drawIconClose(btnRect: owner.btnCancelRect, color: cancelIconColor)

            UiTheme.drawPillButton(
                rect: owner.btnFinishRect,
                text: "完成",
                baseColor: UiTheme.weChatGreen,
                hovered: owner.btnFinishRect.contains(owner.mousePos),
                radius: 3,
                font: btnFont,
                textColor: .white
            )
        }

        override func mouseMoved(with event: NSEvent) {
            guard let owner = owner else { return }
            let pt = convert(event.locationInWindow, from: nil)
            owner.mousePos = pt
            let clickable = owner.btnAutoToggleRect.contains(pt) ||
                            owner.btnCancelRect.contains(pt) ||
                            owner.btnFinishRect.contains(pt)
            if clickable {
                NSCursor.pointingHand.set()
            } else {
                NSCursor.arrow.set()
            }
            needsDisplay = true
        }

        override func mouseDown(with event: NSEvent) {
            guard let owner = owner else { return }
            let pt = convert(event.locationInWindow, from: nil)
            if owner.headerDragRect.contains(pt) {
                owner.draggingPanel = true
                owner.dragStartScreenPt = NSEvent.mouseLocation
                owner.winStartOrigin = owner.frame.origin
                return
            }
            if owner.btnAutoToggleRect.contains(pt) {
                owner.toggleAutoScroll()
                return
            }
            if owner.btnCancelRect.contains(pt) {
                owner.completeWithAction(.cancelled)
                return
            }
            if owner.btnFinishRect.contains(pt) {
                owner.completeWithAction(.openEditor)
                return
            }
        }

        override func mouseDragged(with event: NSEvent) {
            guard let owner = owner, owner.draggingPanel else { return }
            let cur = NSEvent.mouseLocation
            let dx = cur.x - owner.dragStartScreenPt.x
            let dy = cur.y - owner.dragStartScreenPt.y
            owner.setFrameOrigin(NSPoint(x: owner.winStartOrigin.x + dx, y: owner.winStartOrigin.y + dy))
        }

        override func mouseUp(with event: NSEvent) {
            owner?.draggingPanel = false
        }
    }

    public init(physicalCaptureRect: CGRect, direction: ScrollDirection) {
        UiTheme.refreshSystemTheme()
        self.captureRectTopDown = physicalCaptureRect.integral
        self.direction = direction
        self.engine = StitchEngine(direction: direction)
        self.borderOverlay = HollowBorderOverlay(topDownTargetRect: self.captureRectTopDown)

        let panelW: CGFloat = 210
        let panelH: CGFloat = 250

        super.init(
            contentRect: NSRect(x: 0, y: 0, width: panelW, height: panelH),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        self.isOpaque = false
        self.backgroundColor = .clear
        self.level = .statusBar
        self.hasShadow = true
        self.sharingType = .none
        self.isReleasedWhenClosed = false
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        computeLayoutRects(width: panelW, height: panelH)
        positionPanelNearCaptureRect(width: panelW, height: panelH)

        self.dimensionText = String(format: "%d × %d", Int(captureRectTopDown.width), Int(captureRectTopDown.height))

        let view = SessionPanelView(frame: NSRect(x: 0, y: 0, width: panelW, height: panelH))
        view.owner = self
        self.contentView = view
    }

    override public var canBecomeKey: Bool { false }

    private func computeLayoutRects(width: CGFloat, height: CGFloat) {
        let pad: CGFloat = 8
        let innerW = width - pad * 2

        headerDragRect = NSRect(x: 0, y: 0, width: width, height: 32)
        previewCanvasRect = NSRect(x: pad, y: 34, width: innerW, height: height - 34 - 42)

        let barY = height - 34
        let btnH: CGFloat = 26
        let gap: CGFloat = 5
        let cancelW: CGFloat = 30
        let finishW: CGFloat = 58
        let autoW = innerW - cancelW - finishW - gap * 2

        var curX = pad
        btnAutoToggleRect = NSRect(x: curX, y: barY, width: autoW, height: btnH)
        curX += autoW + gap
        btnCancelRect = NSRect(x: curX, y: barY, width: cancelW, height: btnH)
        curX += cancelW + gap
        btnFinishRect = NSRect(x: curX, y: barY, width: finishW, height: btnH)
    }

    private func positionPanelNearCaptureRect(width: CGFloat, height: CGFloat) {
        let screen = ScreenCapturer.screenVisibleTopDownBounds(for: captureRectTopDown)
        let gap: CGFloat = 10

        let clampedY = max(screen.minY + 6, min(screen.maxY - height - 6, captureRectTopDown.maxY - height))
        let clampedX = max(screen.minX + 6, min(screen.maxX - width - 6, captureRectTopDown.maxX - width))

        let chosenTopDownOrigin: CGPoint
        if captureRectTopDown.maxY + gap + height <= screen.maxY {
            chosenTopDownOrigin = CGPoint(x: clampedX, y: captureRectTopDown.maxY + gap)
        } else if captureRectTopDown.maxX + gap + width <= screen.maxX {
            chosenTopDownOrigin = CGPoint(x: captureRectTopDown.maxX + gap, y: clampedY)
        } else if captureRectTopDown.minX - gap - width >= screen.minX {
            chosenTopDownOrigin = CGPoint(x: captureRectTopDown.minX - gap - width, y: clampedY)
        } else if captureRectTopDown.minY - gap - height >= screen.minY {
            chosenTopDownOrigin = CGPoint(x: clampedX, y: captureRectTopDown.minY - gap - height)
        } else {
            chosenTopDownOrigin = CGPoint(
                x: min(screen.maxX - width - 12, captureRectTopDown.maxX - width - 12),
                y: min(screen.maxY - height - 12, captureRectTopDown.maxY - height - 12)
            )
        }

        let topDownPanelRect = CGRect(origin: chosenTopDownOrigin, size: CGSize(width: width, height: height))
        self.setFrame(ScreenCapturer.topDownToCocoa(topDownPanelRect), display: false)
    }

    public func startSession(completion: @escaping (RawBitmap?, ScrollSessionExitAction) -> Void) {
        self.onSessionFinished = completion
        borderOverlay.orderFrontRegardless()
        self.orderFrontRegardless()

        captureAndProcessFrame()

        keyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKeyEvent(event)
        }
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if self?.handleKeyEvent(event) == true {
                return nil
            }
            return event
        }

        captureTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            self?.onCaptureTimerTick()
        }
    }

    @discardableResult
    private func handleKeyEvent(_ event: NSEvent) -> Bool {
        if event.keyCode == 53 { // Escape
            if autoScrolling {
                toggleAutoScroll()
            } else if engine.frameCount > 1 {
                completeWithAction(.openEditor)
            } else {
                completeWithAction(.cancelled)
            }
            return true
        } else if event.keyCode == 36 || event.keyCode == 49 { // Enter or Space
            completeWithAction(.openEditor)
            return true
        }
        return false
    }

    private func getScrollTargetPointTopDown() -> CGPoint {
        if direction == .horizontal {
            // Target the right-middle scrollable body (75% X, 58% Y) to avoid frozen left columns and top/bottom bars
            return CGPoint(
                x: captureRectTopDown.minX + (captureRectTopDown.width * 3.0) / 4.0,
                y: captureRectTopDown.minY + (captureRectTopDown.height * 58.0) / 100.0
            )
        } else {
            return CGPoint(
                x: captureRectTopDown.minX + captureRectTopDown.width / 2.0,
                y: captureRectTopDown.minY + (captureRectTopDown.height * 55.0) / 100.0
            )
        }
    }

    fileprivate func toggleAutoScroll() {
        autoScrolling.toggle()
        autoScrollTickCounter = 0
        noMoveAutoCount = 0
        if autoScrolling {
            let targetPt = getScrollTargetPointTopDown()
            let curTopDown = ScreenCapturer.mouseLocationTopDown()
            let panelTopDown = ScreenCapturer.cocoaToTopDown(self.frame)
            if !captureRectTopDown.contains(curTopDown) || panelTopDown.contains(curTopDown) {
                ScreenCapturer.warpMouseCursor(topDownPoint: targetPt)
            }
        }
        contentView?.needsDisplay = true
    }

    private func onCaptureTimerTick() {
        guard !isCompleted else { return }

        if autoScrolling {
            autoScrollTickCounter += 1
            if autoScrollTickCounter % Self.autoScrollTickModulo == 1 {
                if !draggingPanel {
                    if direction == .vertical {
                        ScreenCapturer.sendVerticalWheel(wheelDelta: -Self.autoScrollWheelAmount)
                    } else {
                        ScreenCapturer.sendHorizontalScroll(amount: Self.autoScrollWheelAmount, method: horizMethod)
                    }
                }
                return
            }
            if autoScrollTickCounter % Self.autoScrollTickModulo != 0 {
                return
            }
        }

        if !draggingPanel {
            captureAndProcessFrame()
        }
    }

    private func captureAndProcessFrame() {
        let frame = ScreenCapturer.captureRegion(captureRectTopDown)
        let res = engine.pushFrame(frame)

        if res.status == .firstFrame || res.status == .stitched {
            noMoveAutoCount = 0
            let totalW = direction == .vertical ? engine.crossDimension : res.totalLength
            let totalH = direction == .vertical ? res.totalLength : engine.crossDimension

            dimensionText = String(format: "%d × %d", totalW, totalH)
            updateLivePreview()
            contentView?.needsDisplay = true
        } else if res.status == .maxLengthReached {
            if autoScrolling { toggleAutoScroll() }
            contentView?.needsDisplay = true
        } else if res.status == .noMovement || res.status == .lowConfidence {
            if autoScrolling {
                noMoveAutoCount += 1
                if direction == .horizontal {
                    if noMoveAutoCount == 2 || noMoveAutoCount == 4 || noMoveAutoCount == 6 {
                        let nextRaw = (horizMethod.rawValue + 1) % 4
                        horizMethod = HorizontalScrollMethod(rawValue: nextRaw) ?? .nativeHWheel
                    } else if noMoveAutoCount >= 10 {
                        autoScrolling = false
                        contentView?.needsDisplay = true
                    }
                } else if noMoveAutoCount >= 8 {
                    autoScrolling = false
                    contentView?.needsDisplay = true
                }
            }
        }
    }

    private func updateLivePreview() {
        let scale = max(1.0, self.backingScaleFactor)
        let boxW = max(24, Int(((previewCanvasRect.width - 6) * scale).rounded()))
        let boxH = max(24, Int(((previewCanvasRect.height - 6) * scale).rounded()))
        if let thumb = engine.renderPreviewThumbnail(boxW: boxW, boxH: boxH) {
            thumb.scaleFactor = scale
            latestPreviewImage = thumb.toNSImage()
        }
    }

    fileprivate func completeWithAction(_ action: ScrollSessionExitAction) {
        guard !isCompleted else { return }
        isCompleted = true
        NSCursor.arrow.set()

        captureTimer?.invalidate()
        captureTimer = nil
        if let km = keyMonitor { NSEvent.removeMonitor(km); keyMonitor = nil }
        if let lkm = localKeyMonitor { NSEvent.removeMonitor(lkm); localKeyMonitor = nil }

        borderOverlay.orderOut(nil)
        self.orderOut(nil)

        exitAction = action
        if action != .cancelled {
            finalStitchedBitmap = engine.renderStitchedBitmap()
        } else {
            finalStitchedBitmap = nil
        }

        let callback = onSessionFinished
        onSessionFinished = nil
        callback?(finalStitchedBitmap, exitAction)
    }
}
