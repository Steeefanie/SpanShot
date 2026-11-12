import AppKit
import CoreGraphics
import Foundation

public enum CaptureActionMode: Int {
    case none = 0
    case normalCopyCompleted = 1
    case normalPinCompleted = 2
    case normalSaveCompleted = 3
    case verticalScroll = 4
    case horizontalScroll = 5
}

/// Fullscreen Retina-native region selector with window auto-snapping, pixel loupe magnifier,
/// inline annotation tools, and floating toolbar. 1:1 port of src/RegionSelectorForm.cs.
public final class RegionSelectorForm: NSPanel {
    fileprivate enum ResizeHitZone {
        case none
        case interior
        case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left
    }

    fileprivate enum InlineAnnotateTool {
        case none
        case rectangle
        case arrow
        case pen
    }

    fileprivate final class AnnotationItem {
        var tool: InlineAnnotateTool
        var color: NSColor
        var thicknessIndex: Int
        var startPt: NSPoint
        var endPt: NSPoint
        var penPoints: [NSPoint]

        init(tool: InlineAnnotateTool, color: NSColor, thicknessIndex: Int, startPt: NSPoint) {
            self.tool = tool
            self.color = color
            self.thicknessIndex = thicknessIndex
            self.startPt = startPt
            self.endPt = startPt
            self.penPoints = tool == .pen ? [startPt] : []
        }
    }

    fileprivate let desktopSnapshot: RawBitmap
    fileprivate let desktopNSImage: NSImage
    fileprivate let virtualBoundsTopDown: CGRect
    fileprivate let backingScaleX: CGFloat
    fileprivate let backingScaleY: CGFloat
    fileprivate let presetMode: CaptureActionMode
    fileprivate let windowShadowCapture: Bool
    fileprivate let detectedWindows: [DetectedWindowInfo]

    fileprivate var dragStart: NSPoint = .zero
    fileprivate var selectionRect: NSRect = .zero
    fileprivate var hoverWindowRect: NSRect = .zero
    fileprivate var hoveredWindowInfo: DetectedWindowInfo?
    fileprivate var selectedWindowInfo: DetectedWindowInfo?
    fileprivate var resizeInitialRect: NSRect = .zero
    fileprivate var activeDragZone: ResizeHitZone = .none
    fileprivate var isSelecting = false
    fileprivate var hasSelection = false

    fileprivate var isWindowShadowSelectionActive: Bool {
        return windowShadowCapture && selectedWindowInfo != nil
    }

    fileprivate var activeTool: InlineAnnotateTool = .none
    fileprivate var selectedColorIndex = 0      // Default Red
    fileprivate var selectedThicknessIndex = 1  // 0=Thin, 1=Medium, 2=Thick
    fileprivate var annotations: [AnnotationItem] = []
    fileprivate var currentDrawingItem: AnnotationItem?

    fileprivate var toolbarBounds: NSRect = .zero
    fileprivate var btnRectTool: NSRect = .zero
    fileprivate var btnArrowTool: NSRect = .zero
    fileprivate var btnPenTool: NSRect = .zero
    fileprivate var btnVerticalScroll: NSRect = .zero
    fileprivate var btnHorizontalScroll: NSRect = .zero
    fileprivate var btnUndoTool: NSRect = .zero
    fileprivate var btnPin: NSRect = .zero
    fileprivate var btnSave: NSRect = .zero
    fileprivate var btnCancel: NSRect = .zero
    fileprivate var btnCopyFinish: NSRect = .zero

    fileprivate var subBarBounds: NSRect = .zero
    fileprivate var thicknessRects: [NSRect] = Array(repeating: .zero, count: 3)
    fileprivate var colorSwatchRects: [NSRect] = Array(repeating: .zero, count: 5)

    fileprivate var mousePos: NSPoint = .zero
    private var companionPanels: [CompanionSelectorPanel] = []
    private var localKeyMonitor: Any?
    private var globalKeyMonitor: Any?
    private var onComplete: ((RegionSelectorForm) -> Void)?
    private var finished = false

    /// Companion full-screen overlay panel for secondary/tertiary displays on macOS when "Displays have separate Spaces" is enabled.
    private final class CompanionSelectorPanel: NSPanel {
        weak var ownerSelector: RegionSelectorForm?

        override var canBecomeKey: Bool { true }
        override var canBecomeMain: Bool { true }

        override func cancelOperation(_ sender: Any?) {
            ownerSelector?.handleEscapeAction()
        }
    }

    /// Selected rectangle in global top-down logical screen coordinates (used by ScrollCaptureSessionForm and PinWindowForm).
    public var selectedPhysicalRect: CGRect {
        return CGRect(
            x: selectionRect.origin.x + virtualBoundsTopDown.origin.x,
            y: selectionRect.origin.y + virtualBoundsTopDown.origin.y,
            width: selectionRect.width,
            height: selectionRect.height
        ).integral
    }

    public private(set) var chosenAction: CaptureActionMode = .none
    public private(set) var annotatedRegionBitmap: RawBitmap?
    public let captureWasBlockedByPermission: Bool

    public init(presetMode: CaptureActionMode = .none, windowShadowCapture: Bool = true) {
        UiTheme.refreshSystemTheme()
        self.presetMode = presetMode
        self.windowShadowCapture = windowShadowCapture
        self.virtualBoundsTopDown = ScreenCapturer.virtualScreenTopDownBounds
        self.detectedWindows = ScreenCapturer.getVisibleWindows()
        let captured = ScreenCapturer.captureRegionWithStatus(self.virtualBoundsTopDown)
        self.desktopSnapshot = captured.bitmap
        self.captureWasBlockedByPermission = captured.isFallback
        self.desktopNSImage = self.desktopSnapshot.toNSImage()
        self.backingScaleX = CGFloat(self.desktopSnapshot.width) / max(1.0, self.virtualBoundsTopDown.width)
        self.backingScaleY = CGFloat(self.desktopSnapshot.height) / max(1.0, self.virtualBoundsTopDown.height)

        let allScreens = NSScreen.screens
        let primaryCocoaFrame = allScreens.first?.frame ?? ScreenCapturer.topDownToCocoa(self.virtualBoundsTopDown)
        let primaryTopDown = ScreenCapturer.cocoaToTopDown(primaryCocoaFrame).integral

        super.init(
            contentRect: primaryCocoaFrame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        self.isOpaque = true
        self.level = .screenSaver
        self.hasShadow = false
        self.sharingType = .none
        self.isReleasedWhenClosed = false
        self.acceptsMouseMovedEvents = true
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let view = SelectorCanvasView(frame: NSRect(x: 0, y: 0, width: primaryCocoaFrame.width, height: primaryCocoaFrame.height))
        view.owner = self
        view.virtualOffset = NSPoint(
            x: primaryTopDown.origin.x - self.virtualBoundsTopDown.origin.x,
            y: primaryTopDown.origin.y - self.virtualBoundsTopDown.origin.y
        )
        self.contentView = view

        // Create a dedicated full-screen overlay NSPanel for each additional display
        // so macOS WindowServer ("Displays have separate Spaces") renders across all monitors simultaneously.
        if allScreens.count > 1 {
            for scr in allScreens.dropFirst() {
                let scrCocoa = scr.frame
                let scrTopDown = ScreenCapturer.cocoaToTopDown(scrCocoa).integral
                let panel = CompanionSelectorPanel(
                    contentRect: scrCocoa,
                    styleMask: [.borderless],
                    backing: .buffered,
                    defer: false
                )
                panel.ownerSelector = self
                panel.isOpaque = true
                panel.level = .screenSaver
                panel.hasShadow = false
                panel.sharingType = .none
                panel.isReleasedWhenClosed = false
                panel.acceptsMouseMovedEvents = true
                panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

                let subView = SelectorCanvasView(frame: NSRect(x: 0, y: 0, width: scrCocoa.width, height: scrCocoa.height))
                subView.owner = self
                subView.virtualOffset = NSPoint(
                    x: scrTopDown.origin.x - self.virtualBoundsTopDown.origin.x,
                    y: scrTopDown.origin.y - self.virtualBoundsTopDown.origin.y
                )
                panel.contentView = subView
                self.companionPanels.append(panel)
            }
        }
    }

    override public var canBecomeKey: Bool { true }
    override public var canBecomeMain: Bool { true }

    /// Intercept NSPanel's built-in Escape cancelOperation so it never closes without calling onComplete!
    override public func cancelOperation(_ sender: Any?) {
        handleEscapeAction()
    }

    fileprivate func refreshAllDisplays() {
        self.contentView?.needsDisplay = true
        for panel in companionPanels {
            panel.contentView?.needsDisplay = true
        }
    }

    private func closeAllDisplays() {
        for panel in companionPanels {
            panel.orderOut(nil)
        }
        companionPanels.removeAll()
        self.orderOut(nil)
    }

    public func beginSelection(completion: @escaping (RegionSelectorForm) -> Void) {
        self.onComplete = completion
        NSApp.activate(ignoringOtherApps: true)
        for panel in companionPanels {
            panel.orderFrontRegardless()
        }
        self.makeKeyAndOrderFront(nil)
        self.makeFirstResponder(self.contentView)

        let curTopDown = ScreenCapturer.mouseLocationTopDown()
        mousePos = NSPoint(
            x: curTopDown.x - virtualBoundsTopDown.origin.x,
            y: curTopDown.y - virtualBoundsTopDown.origin.y
        )
        // If the mouse cursor starts on a secondary display, focus its companion panel
        let curCocoa = NSEvent.mouseLocation
        for panel in companionPanels where panel.frame.contains(curCocoa) {
            panel.makeKeyAndOrderFront(nil)
            panel.makeFirstResponder(panel.contentView)
            break
        }

        let hovered = findHoveredWindow(localPt: mousePos)
        hoverWindowRect = hovered.rect
        hoveredWindowInfo = hovered.info
        updateCursorForPoint(mousePos)
        refreshAllDisplays()

        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self, !self.finished else { return event }
            if self.handleSelectorKeyDown(event) {
                return nil
            }
            return event
        }

        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self, !self.finished else { return }
            _ = self.handleSelectorKeyDown(event)
        }
    }

    private func cleanupMonitorsAndCursor() {
        if let lm = localKeyMonitor { NSEvent.removeMonitor(lm); localKeyMonitor = nil }
        if let gm = globalKeyMonitor { NSEvent.removeMonitor(gm); globalKeyMonitor = nil }
        NSCursor.arrow.set()
    }

    fileprivate func handleEscapeAction() {
        guard !finished else { return }
        if hasSelection {
            hasSelection = false
            selectionRect = .zero
            selectedWindowInfo = nil
            activeTool = .none
            annotations.removeAll()
            activeDragZone = .none
            let hovered = findHoveredWindow(localPt: mousePos)
            hoverWindowRect = hovered.rect
            hoveredWindowInfo = hovered.info
            updateCursorForPoint(mousePos)
            refreshAllDisplays()
        } else {
            cancelSelection()
        }
    }

    @discardableResult
    fileprivate func handleSelectorKeyDown(_ event: NSEvent) -> Bool {
        if event.keyCode == 53 { // Escape
            handleEscapeAction()
            return true
        }

        guard hasSelection && selectionRect.width >= 20 && selectionRect.height >= 20 else {
            return false
        }

        let hasCmdOrCtrl = event.modifierFlags.contains(.command) || event.modifierFlags.contains(.control)
        let ch = event.charactersIgnoringModifiers?.lowercased() ?? ""

        if hasCmdOrCtrl && ch == "z" {
            if !annotations.isEmpty {
                _ = annotations.popLast()
                refreshAllDisplays()
            }
            return true
        } else if event.keyCode == 36 || event.keyCode == 76 || event.keyCode == 49 || (hasCmdOrCtrl && ch == "c") {
            finishNormalWithAction(.normalCopyCompleted)
            return true
        } else if ch == "v" && !hasCmdOrCtrl {
            confirmScrollAction(.verticalScroll)
            return true
        } else if ch == "h" && !hasCmdOrCtrl {
            confirmScrollAction(.horizontalScroll)
            return true
        } else if ch == "p" && !hasCmdOrCtrl {
            finishNormalWithAction(.normalPinCompleted)
            return true
        } else if hasCmdOrCtrl && ch == "s" {
            finishNormalWithAction(.normalSaveCompleted)
            return true
        } else if activeTool == .none && (event.keyCode == 123 || event.keyCode == 124 || event.keyCode == 125 || event.keyCode == 126) {
            selectedWindowInfo = nil
            let maxW = virtualBoundsTopDown.width
            let maxH = virtualBoundsTopDown.height
            let dx: CGFloat = event.keyCode == 123 ? -1 : (event.keyCode == 124 ? 1 : 0)
            let dy: CGFloat = event.keyCode == 126 ? -1 : (event.keyCode == 125 ? 1 : 0)
            if event.modifierFlags.contains(.shift) {
                selectionRect.size.width = max(24, min(maxW - selectionRect.origin.x, selectionRect.width + dx))
                selectionRect.size.height = max(24, min(maxH - selectionRect.origin.y, selectionRect.height + dy))
            } else {
                selectionRect.origin.x = max(0, min(maxW - selectionRect.width, selectionRect.origin.x + dx))
                selectionRect.origin.y = max(0, min(maxH - selectionRect.height, selectionRect.origin.y + dy))
            }
            updateToolbarLayout()
            refreshAllDisplays()
            return true
        }
        return false
    }

    fileprivate func confirmScrollAction(_ scrollMode: CaptureActionMode) {
        guard !finished else { return }
        finished = true
        cleanupMonitorsAndCursor()
        chosenAction = scrollMode
        closeAllDisplays()
        onComplete?(self)
    }

    fileprivate func finishNormalWithAction(_ mode: CaptureActionMode) {
        guard !finished else { return }
        finished = true
        cleanupMonitorsAndCursor()
        annotatedRegionBitmap = renderSelectedRegionWithAnnotations()
        chosenAction = mode
        closeAllDisplays()
        onComplete?(self)
    }

    fileprivate func cancelSelection() {
        guard !finished else { return }
        finished = true
        cleanupMonitorsAndCursor()
        chosenAction = .none
        closeAllDisplays()
        onComplete?(self)
    }

    private func renderSelectedRegionWithAnnotations() -> RawBitmap {
        let px = Int((selectionRect.origin.x * backingScaleX).rounded())
        let py = Int((selectionRect.origin.y * backingScaleY).rounded())
        let pw = max(1, Int((selectionRect.width * backingScaleX).rounded()))
        let ph = max(1, Int((selectionRect.height * backingScaleY).rounded()))

        var bmp: RawBitmap
        if isWindowShadowSelectionActive, let winInfo = selectedWindowInfo {
            let isOccludedByOtherApp = detectedWindows.contains { other in
                other.zIndex < winInfo.zIndex
                    && other.ownerPID != winInfo.ownerPID
                    && !other.boundsTopDown.intersection(winInfo.boundsTopDown).isNull
            }
            if isOccludedByOtherApp,
               let isolated = ScreenCapturer.captureIndependentWindow(
                   windowID: winInfo.windowID,
                   targetPixelWidth: pw,
                   targetPixelHeight: ph,
                   scale: desktopSnapshot.scaleFactor
               ) {
                bmp = isolated
            } else {
                bmp = desktopSnapshot.clone(x: px, y: py, width: pw, height: ph)
                bmp.scaleFactor = desktopSnapshot.scaleFactor
            }
        } else {
            bmp = desktopSnapshot.clone(x: px, y: py, width: pw, height: ph)
            bmp.scaleFactor = desktopSnapshot.scaleFactor
        }

        if !annotations.isEmpty {
            bmp.withTopDownCGContext { ctx in
                let prev = NSGraphicsContext.current
                NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
                ctx.scaleBy(x: backingScaleX, y: backingScaleY)
                if isWindowShadowSelectionActive {
                    let clipPath = AppIconRenderer.continuousRoundedRectPath(
                        rect: CGRect(x: 0, y: 0, width: selectionRect.width, height: selectionRect.height),
                        radius: 14.5
                    )
                    ctx.addPath(clipPath)
                    ctx.clip()
                }
                ctx.translateBy(x: -selectionRect.origin.x, y: -selectionRect.origin.y)
                for item in annotations {
                    SelectorCanvasView.drawSingleAnnotation(item)
                }
                NSGraphicsContext.current = prev
            }
        }

        if isWindowShadowSelectionActive {
            return ScreenCapturer.renderWindowWithMacOSShadow(windowBitmap: bmp, cornerRadiusPt: 14.5)
        }
        return bmp
    }

    fileprivate func findHoveredWindow(localPt: NSPoint) -> (rect: NSRect, info: DetectedWindowInfo?) {
        let screenPt = CGPoint(
            x: localPt.x + virtualBoundsTopDown.origin.x,
            y: localPt.y + virtualBoundsTopDown.origin.y
        )
        let viewBounds = NSRect(x: 0, y: 0, width: virtualBoundsTopDown.width, height: virtualBoundsTopDown.height)
        for win in detectedWindows {
            let wr = win.boundsTopDown
            if wr.contains(screenPt) {
                let localRect = NSRect(
                    x: wr.origin.x - virtualBoundsTopDown.origin.x,
                    y: wr.origin.y - virtualBoundsTopDown.origin.y,
                    width: wr.width,
                    height: wr.height
                ).intersection(viewBounds)
                if localRect.width >= 50 && localRect.height >= 50 {
                    return (localRect, win)
                }
            }
        }
        return (.zero, nil)
    }

    fileprivate func hitTestSelection(_ pt: NSPoint) -> ResizeHitZone {
        guard hasSelection && selectionRect.width > 0 && selectionRect.height > 0 else { return .none }
        let tol: CGFloat = 7
        let r = selectionRect

        let nearLeft = abs(pt.x - r.minX) <= tol && pt.y >= r.minY - tol && pt.y <= r.maxY + tol
        let nearRight = abs(pt.x - r.maxX) <= tol && pt.y >= r.minY - tol && pt.y <= r.maxY + tol
        let nearTop = abs(pt.y - r.minY) <= tol && pt.x >= r.minX - tol && pt.x <= r.maxX + tol
        let nearBottom = abs(pt.y - r.maxY) <= tol && pt.x >= r.minX - tol && pt.x <= r.maxX + tol

        if nearLeft && nearTop { return .topLeft }
        if nearRight && nearTop { return .topRight }
        if nearRight && nearBottom { return .bottomRight }
        if nearLeft && nearBottom { return .bottomLeft }
        if nearTop { return .top }
        if nearBottom { return .bottom }
        if nearLeft { return .left }
        if nearRight { return .right }
        if r.contains(pt) { return .interior }
        return .none
    }

    fileprivate func updateCursorForPoint(_ pt: NSPoint) {
        if hasSelection && !isSelecting {
            if toolbarBounds.contains(pt) || (activeTool != .none && subBarBounds.contains(pt)) {
                NSCursor.pointingHand.set()
                return
            }
            if activeTool != .none && selectionRect.contains(pt) {
                NSCursor.crosshair.set()
                return
            }
            if annotations.isEmpty {
                let zone = activeDragZone != .none ? activeDragZone : hitTestSelection(pt)
                switch zone {
                case .left, .right:
                    NSCursor.resizeLeftRight.set()
                    return
                case .top, .bottom:
                    NSCursor.resizeUpDown.set()
                    return
                case .topLeft, .bottomRight, .topRight, .bottomLeft:
                    NSCursor.crosshair.set()
                    return
                case .interior:
                    if activeDragZone == .interior {
                        NSCursor.closedHand.set()
                    } else {
                        NSCursor.openHand.set()
                    }
                    return
                case .none:
                    break
                }
            }
        }
        NSCursor.crosshair.set()
    }

    fileprivate func applyResizeOrMove(_ pt: NSPoint) {
        selectedWindowInfo = nil
        let dx = pt.x - dragStart.x
        let dy = pt.y - dragStart.y
        let r = resizeInitialRect
        let maxW = virtualBoundsTopDown.width
        let maxH = virtualBoundsTopDown.height

        if activeDragZone == .interior {
            let nx = max(0, min(maxW - r.width, r.origin.x + dx))
            let ny = max(0, min(maxH - r.height, r.origin.y + dy))
            selectionRect = NSRect(x: nx, y: ny, width: r.width, height: r.height).integral
            return
        }

        var left = r.minX
        var top = r.minY
        var right = r.maxX
        var bottom = r.maxY

        if activeDragZone == .topLeft || activeDragZone == .left || activeDragZone == .bottomLeft {
            left = max(0, min(right - 30, left + dx))
        }
        if activeDragZone == .topRight || activeDragZone == .right || activeDragZone == .bottomRight {
            right = min(maxW, max(left + 30, right + dx))
        }
        if activeDragZone == .topLeft || activeDragZone == .top || activeDragZone == .topRight {
            top = max(0, min(bottom - 30, top + dy))
        }
        if activeDragZone == .bottomLeft || activeDragZone == .bottom || activeDragZone == .bottomRight {
            bottom = min(maxH, max(top + 30, bottom + dy))
        }

        selectionRect = NSRect(x: left, y: top, width: right - left, height: bottom - top).integral
    }

    fileprivate func localDisplayVirtualRect(forPoint vPt: NSPoint) -> NSRect {
        let globalPt = CGPoint(
            x: vPt.x + virtualBoundsTopDown.origin.x,
            y: vPt.y + virtualBoundsTopDown.origin.y
        )
        let scrTopDown = ScreenCapturer.screenTopDownBounds(for: globalPt)
        return NSRect(
            x: scrTopDown.origin.x - virtualBoundsTopDown.origin.x,
            y: scrTopDown.origin.y - virtualBoundsTopDown.origin.y,
            width: scrTopDown.width,
            height: scrTopDown.height
        )
    }

    fileprivate func localDisplayVirtualRect(forRect vRect: NSRect) -> NSRect {
        let globalRect = CGRect(
            x: vRect.origin.x + virtualBoundsTopDown.origin.x,
            y: vRect.origin.y + virtualBoundsTopDown.origin.y,
            width: vRect.width,
            height: vRect.height
        )
        if let scr = ScreenCapturer.screenContaining(topDownRect: globalRect) {
            let scrTopDown = ScreenCapturer.cocoaToTopDown(scr.frame).integral
            return NSRect(
                x: scrTopDown.origin.x - virtualBoundsTopDown.origin.x,
                y: scrTopDown.origin.y - virtualBoundsTopDown.origin.y,
                width: scrTopDown.width,
                height: scrTopDown.height
            )
        }
        return localDisplayVirtualRect(forPoint: NSPoint(x: vRect.midX, y: vRect.midY))
    }

    fileprivate func updateToolbarLayout() {
        let dispBounds = localDisplayVirtualRect(forRect: selectionRect)

        let barH: CGFloat = 38
        let pad: CGFloat = 5
        let btnH = barH - pad * 2
        let iconW: CGFloat = 32
        let scrollW: CGFloat = 76
        let finishW: CGFloat = 38
        let gap: CGFloat = 2
        let divGap: CGFloat = 11

        let barWidth = pad * 2
                     + iconW * 3 + gap * 2 + divGap
                     + scrollW * 2 + gap + divGap
                     + iconW * 4 + finishW + gap * 4

        var x = selectionRect.maxX - barWidth
        if x < dispBounds.minX + 8 { x = max(dispBounds.minX + 8, selectionRect.minX) }
        if x + barWidth > dispBounds.maxX - 8 { x = max(dispBounds.minX + 8, dispBounds.maxX - barWidth - 8) }

        let totalNeededH = barH + (activeTool != .none ? 42 : 0)
        var y = selectionRect.maxY + 6
        var placedAbove = false
        if y + totalNeededH > dispBounds.maxY - 8 {
            y = selectionRect.minY - barH - 6
            placedAbove = true
            if y < dispBounds.minY + 8 {
                y = selectionRect.maxY - barH - 6
                placedAbove = false
            }
        }

        toolbarBounds = NSRect(x: x, y: y, width: barWidth, height: barH)

        var curX = x + pad
        let btnY = y + pad

        btnRectTool = NSRect(x: curX, y: btnY, width: iconW, height: btnH); curX += iconW + gap
        btnArrowTool = NSRect(x: curX, y: btnY, width: iconW, height: btnH); curX += iconW + gap
        btnPenTool = NSRect(x: curX, y: btnY, width: iconW, height: btnH); curX += iconW + divGap

        btnVerticalScroll = NSRect(x: curX, y: btnY, width: scrollW, height: btnH); curX += scrollW + gap
        btnHorizontalScroll = NSRect(x: curX, y: btnY, width: scrollW, height: btnH); curX += scrollW + divGap

        btnUndoTool = NSRect(x: curX, y: btnY, width: iconW, height: btnH); curX += iconW + gap
        btnPin = NSRect(x: curX, y: btnY, width: iconW, height: btnH); curX += iconW + gap
        btnSave = NSRect(x: curX, y: btnY, width: iconW, height: btnH); curX += iconW + gap
        btnCancel = NSRect(x: curX, y: btnY, width: iconW, height: btnH); curX += iconW + gap
        btnCopyFinish = NSRect(x: curX, y: btnY, width: finishW, height: btnH)

        let subW: CGFloat = 232
        let subH: CGFloat = 34
        let subX = toolbarBounds.minX
        var subY = placedAbove ? (toolbarBounds.minY - subH - 5) : (toolbarBounds.maxY + 5)
        if subY < dispBounds.minY + 6 { subY = toolbarBounds.maxY + 5 }

        subBarBounds = NSRect(x: subX, y: subY, width: subW, height: subH)

        var sx = subX + 8
        let sy = subY + (subH - 24) / 2
        for i in 0..<3 {
            thicknessRects[i] = NSRect(x: sx, y: sy, width: 24, height: 24)
            sx += 26
        }
        sx += 10
        for i in 0..<colorSwatchRects.count {
            colorSwatchRects[i] = NSRect(x: sx, y: sy + 2, width: 20, height: 20)
            sx += 26
        }
    }

    private final class SelectorCanvasView: NSView {
        weak var owner: RegionSelectorForm?
        var virtualOffset: NSPoint = .zero

        override var isFlipped: Bool { true }
        override var acceptsFirstResponder: Bool { true }

        private func virtualPoint(from event: NSEvent) -> NSPoint {
            let localPt = convert(event.locationInWindow, from: nil)
            return NSPoint(x: localPt.x + virtualOffset.x, y: localPt.y + virtualOffset.y)
        }

        private func ensurePanelFocusedIfNeeded() {
            if let win = self.window, !win.isKeyWindow {
                win.makeKey()
                win.makeFirstResponder(self)
            }
        }

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
            let virtualRect = NSRect(
                x: 0,
                y: 0,
                width: owner.virtualBoundsTopDown.width,
                height: owner.virtualBoundsTopDown.height
            )
            let localScreenVirtualRect = NSRect(origin: virtualOffset, size: bounds.size)

            NSGraphicsContext.saveGraphicsState()
            defer { NSGraphicsContext.restoreGraphicsState() }

            if let ctx = NSGraphicsContext.current?.cgContext {
                ctx.translateBy(x: -virtualOffset.x, y: -virtualOffset.y)
            }

            // Draw full-resolution Retina desktop snapshot 1:1 without interpolation blur
            NSGraphicsContext.current?.imageInterpolation = .none
            owner.desktopNSImage.draw(
                in: virtualRect,
                from: .zero,
                operation: .copy,
                fraction: 1.0,
                respectFlipped: true,
                hints: nil
            )

            let dimColor = NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 120 / 255.0)
            if owner.selectionRect.width > 0 && owner.selectionRect.height > 0 {
                if owner.isWindowShadowSelectionActive, let ctx = NSGraphicsContext.current?.cgContext {
                    let selPath = AppIconRenderer.continuousRoundedRectPath(rect: owner.selectionRect, radius: 14.5)
                    ctx.saveGState()
                    ctx.addRect(virtualRect)
                    ctx.addPath(selPath)
                    ctx.setFillColor(dimColor.cgColor)
                    ctx.fillPath(using: .evenOdd)
                    ctx.restoreGState()
                } else {
                    let path = NSBezierPath(rect: virtualRect)
                    path.appendRect(owner.selectionRect)
                    path.windingRule = .evenOdd
                    dimColor.setFill()
                    path.fill()
                }
            } else if owner.hoverWindowRect.width > 8 && owner.hoverWindowRect.height > 8,
                      let ctx = NSGraphicsContext.current?.cgContext {
                // Cut out the hovered macOS window using macOS Tahoe's 14.5pt continuous corner curve
                let winRadius: CGFloat = owner.windowShadowCapture ? 14.5 : 0.0
                let hoverPath = winRadius > 0
                    ? AppIconRenderer.continuousRoundedRectPath(rect: owner.hoverWindowRect, radius: winRadius)
                    : CGPath(rect: owner.hoverWindowRect, transform: nil)
                ctx.saveGState()
                ctx.addRect(virtualRect)
                ctx.addPath(hoverPath)
                ctx.setFillColor(dimColor.cgColor)
                ctx.fillPath(using: .evenOdd)
                ctx.restoreGState()

                // Draw a single flush 2pt continuous border right on the window edge (0..2pt inside hoverPath)
                ctx.saveGState()
                ctx.addPath(hoverPath)
                ctx.clip()
                ctx.setStrokeColor(UiTheme.weChatGreen.cgColor)
                ctx.setLineWidth(4.0) // outer 2pt clipped away -> crisp 2pt inner border flush with hoverPath
                ctx.addPath(hoverPath)
                ctx.strokePath()
                ctx.restoreGState()
            } else {
                dimColor.setFill()
                virtualRect.fill()
            }

            if !owner.hasSelection && !owner.isSelecting {
                let prompt: String
                if owner.presetMode == .verticalScroll {
                    prompt = L10n.promptVerticalScroll
                } else if owner.presetMode == .horizontalScroll {
                    prompt = L10n.promptHorizontalScroll
                } else {
                    prompt = L10n.promptNormalCapture
                }
                let font = UiTheme.fontPx(13)
                let psz = (prompt as NSString).size(withAttributes: [.font: font])
                let pw = ceil(psz.width) + 28
                let ph: CGFloat = 34
                let px = floor(localScreenVirtualRect.minX + (localScreenVirtualRect.width - pw) / 2.0)
                let py: CGFloat = localScreenVirtualRect.minY + 28
                let promptRect = NSRect(x: px, y: py, width: pw, height: ph)

                UiTheme.fillAndStrokeRoundedRect(
                    promptRect,
                    radius: 8,
                    fillColor: UiTheme.toolbarBg,
                    strokeColor: UiTheme.weChatGreen,
                    lineWidth: 1.0
                )
                UiTheme.drawCenteredText(prompt, in: promptRect, font: font, color: UiTheme.textPrimary)
            }

            if owner.selectionRect.width > 0 && owner.selectionRect.height > 0 {
                NSGraphicsContext.saveGraphicsState()
                if owner.isWindowShadowSelectionActive, let ctx = NSGraphicsContext.current?.cgContext {
                    let clipPath = AppIconRenderer.continuousRoundedRectPath(rect: owner.selectionRect, radius: 14.5)
                    ctx.addPath(clipPath)
                    ctx.clip()
                } else {
                    NSBezierPath(rect: owner.selectionRect).addClip()
                }
                for item in owner.annotations {
                    Self.drawSingleAnnotation(item)
                }
                if let current = owner.currentDrawingItem {
                    Self.drawSingleAnnotation(current)
                }
                NSGraphicsContext.restoreGraphicsState()

                if owner.isWindowShadowSelectionActive, let ctx = NSGraphicsContext.current?.cgContext {
                    let selPath = AppIconRenderer.continuousRoundedRectPath(rect: owner.selectionRect, radius: 14.5)
                    ctx.saveGState()
                    ctx.addPath(selPath)
                    ctx.clip()
                    ctx.setStrokeColor(UiTheme.weChatGreen.cgColor)
                    ctx.setLineWidth(3.0)
                    ctx.addPath(selPath)
                    ctx.strokePath()
                    ctx.restoreGState()
                } else {
                    // Exact pixel-aligned 1pt stroke at inset 0.5pt (zero subpixel ghosting on Retina)
                    UiTheme.weChatGreen.setStroke()
                    let bp = NSBezierPath(rect: owner.selectionRect.insetBy(dx: 0.5, dy: 0.5))
                    bp.lineWidth = 1.0
                    bp.stroke()
                }

                if owner.annotations.isEmpty && owner.activeTool == .none {
                    let midX = owner.selectionRect.midX
                    let midY = owner.selectionRect.midY
                    drawSquareHandle(x: owner.selectionRect.minX, y: owner.selectionRect.minY)
                    drawSquareHandle(x: midX, y: owner.selectionRect.minY)
                    drawSquareHandle(x: owner.selectionRect.maxX, y: owner.selectionRect.minY)
                    drawSquareHandle(x: owner.selectionRect.maxX, y: midY)
                    drawSquareHandle(x: owner.selectionRect.maxX, y: owner.selectionRect.maxY)
                    drawSquareHandle(x: midX, y: owner.selectionRect.maxY)
                    drawSquareHandle(x: owner.selectionRect.minX, y: owner.selectionRect.maxY)
                    drawSquareHandle(x: owner.selectionRect.minX, y: midY)
                }

                let dispBounds = owner.localDisplayVirtualRect(forRect: owner.selectionRect)
                let pxW = Int((owner.selectionRect.width * owner.backingScaleX).rounded())
                let pxH = Int((owner.selectionRect.height * owner.backingScaleY).rounded())
                let sizeText = owner.isWindowShadowSelectionActive
                    ? L10n.sizeBadgeWithWindowShadow(pxW, pxH)
                    : String(format: "%d × %d px", pxW, pxH)
                let badgeFont = UiTheme.fontPx(12)
                let tsz = (sizeText as NSString).size(withAttributes: [.font: badgeFont])
                let bw = ceil(tsz.width) + 12
                let bh = ceil(tsz.height) + 6
                let bx = max(dispBounds.minX + 6, min(dispBounds.maxX - bw - 6, owner.selectionRect.minX))
                var by = owner.selectionRect.minY - bh - 4
                if by < dispBounds.minY + 6 { by = owner.selectionRect.minY + 4 }

                let badgeRect = NSRect(x: bx, y: by, width: bw, height: bh)
                UiTheme.fillRoundedRect(
                    badgeRect,
                    radius: 4,
                    color: NSColor(srgbRed: 36 / 255.0, green: 36 / 255.0, blue: 36 / 255.0, alpha: 225 / 255.0)
                )
                UiTheme.drawCenteredText(sizeText, in: badgeRect, font: badgeFont, color: .white)
            }

            if owner.hasSelection && !owner.isSelecting && owner.activeDragZone == .none {
                drawWeChatToolbar(owner: owner)
                if owner.activeTool != .none {
                    drawWeChatSubBar(owner: owner)
                }
            }

            // Draw Retina Pixel Magnifier Loupe when hovering or actively dragging/resizing
            if !owner.hasSelection || owner.isSelecting || (owner.activeDragZone != .none && owner.activeDragZone != .interior) {
                drawMagnifierLoupe(owner: owner)
            }
        }

        private func drawMagnifierLoupe(owner: RegionSelectorForm) {
            let mp = owner.mousePos
            let dispBounds = owner.localDisplayVirtualRect(forPoint: mp)
            let loupeW: CGFloat = 118
            let loupeH: CGFloat = 142
            let offset: CGFloat = 20

            var lx = mp.x + offset
            var ly = mp.y + offset
            if lx + loupeW > dispBounds.maxX - 8 { lx = mp.x - loupeW - offset }
            if ly + loupeH > dispBounds.maxY - 8 { ly = mp.y - loupeH - offset }
            lx = floor(max(dispBounds.minX + 8, min(dispBounds.maxX - loupeW - 8, lx)))
            ly = floor(max(dispBounds.minY + 8, min(dispBounds.maxY - loupeH - 8, ly)))

            let loupeRect = NSRect(x: lx, y: ly, width: loupeW, height: loupeH)
            UiTheme.fillAndStrokeRoundedRect(
                loupeRect,
                radius: 8,
                fillColor: UiTheme.toolbarBg,
                strokeColor: UiTheme.toolbarBorder,
                lineWidth: 1.0
            )

            let scopeH: CGFloat = 94
            let scopeRect = NSRect(x: lx + 4, y: ly + 4, width: loupeW - 8, height: scopeH)

            let centerPxX = max(0, min(owner.desktopSnapshot.width - 1, Int((mp.x * owner.backingScaleX).rounded())))
            let centerPxY = max(0, min(owner.desktopSnapshot.height - 1, Int((mp.y * owner.backingScaleY).rounded())))

            let gridCols = 15
            let gridRows = 11
            let halfC = gridCols / 2
            let halfR = gridRows / 2
            let cellW = scopeRect.width / CGFloat(gridCols)
            let cellH = scopeRect.height / CGFloat(gridRows)

            if let ctx = NSGraphicsContext.current?.cgContext {
                let scopePath = AppIconRenderer.continuousRoundedRectPath(rect: scopeRect, radius: 5)
                ctx.saveGState()
                ctx.addPath(scopePath)
                ctx.clip()

                for r in 0..<gridRows {
                    let sy = max(0, min(owner.desktopSnapshot.height - 1, centerPxY + (r - halfR)))
                    for c in 0..<gridCols {
                        let sx = max(0, min(owner.desktopSnapshot.width - 1, centerPxX + (c - halfC)))
                        let px = owner.desktopSnapshot.getPixel(x: sx, y: sy)
                        NSColor(
                            srgbRed: CGFloat(px.r) / 255.0,
                            green: CGFloat(px.g) / 255.0,
                            blue: CGFloat(px.b) / 255.0,
                            alpha: 1.0
                        ).setFill()
                        let cellRect = NSRect(
                            x: scopeRect.origin.x + CGFloat(c) * cellW,
                            y: scopeRect.origin.y + CGFloat(r) * cellH,
                            width: ceil(cellW),
                            height: ceil(cellH)
                        )
                        cellRect.fill()
                    }
                }

                // Crosshair in the center of the loupe
                let cx = scopeRect.origin.x + CGFloat(halfC) * cellW + cellW * 0.5
                let cy = scopeRect.origin.y + CGFloat(halfR) * cellH + cellH * 0.5
                UiTheme.weChatGreen.withAlphaComponent(0.85).setStroke()
                let chPath = NSBezierPath()
                chPath.lineWidth = 1.0
                chPath.move(to: NSPoint(x: scopeRect.minX, y: cy))
                chPath.line(to: NSPoint(x: scopeRect.maxX, y: cy))
                chPath.move(to: NSPoint(x: cx, y: scopeRect.minY))
                chPath.line(to: NSPoint(x: cx, y: scopeRect.maxY))
                chPath.stroke()

                ctx.setStrokeColor(UiTheme.toolbarBorder.cgColor)
                ctx.setLineWidth(2.0)
                ctx.addPath(scopePath)
                ctx.strokePath()
                ctx.restoreGState()
            }

            // Info footer inside loupe: size/coords + hex color
            let centerRGB = owner.desktopSnapshot.getPixel(x: centerPxX, y: centerPxY)
            let hexStr = String(format: "#%02X%02X%02X", centerRGB.r, centerRGB.g, centerRGB.b)
            let coordStr: String
            if owner.selectionRect.width > 0 && owner.selectionRect.height > 0 {
                let sw = Int((owner.selectionRect.width * owner.backingScaleX).rounded())
                let sh = Int((owner.selectionRect.height * owner.backingScaleY).rounded())
                coordStr = "\(sw) × \(sh) px"
            } else {
                coordStr = "(\(centerPxX), \(centerPxY))"
            }

            let infoFont = UiTheme.fontPx(11)
            UiTheme.drawCenteredText(
                coordStr,
                in: NSRect(x: lx + 6, y: ly + scopeH + 6, width: loupeW - 12, height: 18),
                font: infoFont,
                color: UiTheme.textPrimary
            )

            let swatchRect = NSRect(x: lx + 20, y: ly + scopeH + 26, width: 11, height: 11)
            let swatchColor = NSColor(
                srgbRed: CGFloat(centerRGB.r) / 255.0,
                green: CGFloat(centerRGB.g) / 255.0,
                blue: CGFloat(centerRGB.b) / 255.0,
                alpha: 1.0
            )
            UiTheme.fillAndStrokeRoundedRect(
                swatchRect,
                radius: 2.5,
                fillColor: swatchColor,
                strokeColor: UiTheme.borderSubtle,
                lineWidth: 1.0
            )

            UiTheme.drawCenteredText(
                hexStr,
                in: NSRect(x: lx + 35, y: ly + scopeH + 22, width: loupeW - 41, height: 18),
                font: infoFont,
                color: UiTheme.textSecondary,
                alignment: .left
            )
        }

        private func drawSquareHandle(x: CGFloat, y: CGFloat) {
            let sz: CGFloat = 6
            UiTheme.weChatGreen.setFill()
            NSRect(x: x - sz / 2, y: y - sz / 2, width: sz, height: sz).fill()
        }

        private func drawIconBtnBg(_ rect: NSRect, active: Bool, hovered: Bool) {
            guard active || hovered else { return }
            let c = active ? UiTheme.toolbarHover : UiTheme.toolbarHover
            UiTheme.fillRoundedRect(rect, radius: 4, color: c)
        }

        private func drawWeChatToolbar(owner: RegionSelectorForm) {
            UiTheme.fillAndStrokeRoundedRect(
                owner.toolbarBounds,
                radius: 8,
                fillColor: UiTheme.toolbarBg,
                strokeColor: UiTheme.toolbarBorder,
                lineWidth: 1.0
            )

            let mp = owner.mousePos
            let iconFg = UiTheme.textPrimary
            drawIconBtnBg(owner.btnRectTool, active: owner.activeTool == .rectangle, hovered: owner.btnRectTool.contains(mp))
            UiTheme.drawIconRect(btnRect: owner.btnRectTool, color: owner.activeTool == .rectangle ? UiTheme.weChatGreen : iconFg)

            drawIconBtnBg(owner.btnArrowTool, active: owner.activeTool == .arrow, hovered: owner.btnArrowTool.contains(mp))
            UiTheme.drawIconArrow(btnRect: owner.btnArrowTool, color: owner.activeTool == .arrow ? UiTheme.weChatGreen : iconFg)

            drawIconBtnBg(owner.btnPenTool, active: owner.activeTool == .pen, hovered: owner.btnPenTool.contains(mp))
            UiTheme.drawIconPen(btnRect: owner.btnPenTool, color: owner.activeTool == .pen ? UiTheme.weChatGreen : iconFg)

            UiTheme.dividerColor.setFill()
            let div1X = floor(owner.btnPenTool.maxX + 5)
            NSRect(x: div1X, y: owner.toolbarBounds.minY + 9, width: 1.0, height: owner.toolbarBounds.height - 18).fill()

            let tbFont = UiTheme.fontPx(13)
            UiTheme.drawPillButton(
                rect: owner.btnVerticalScroll,
                text: L10n.toolbarVerticalScrollBtn,
                baseColor: owner.btnVerticalScroll.contains(mp) ? UiTheme.toolbarHover : .clear,
                hovered: false,
                radius: 4,
                font: tbFont,
                textColor: iconFg
            )
            UiTheme.drawPillButton(
                rect: owner.btnHorizontalScroll,
                text: L10n.toolbarHorizontalScrollBtn,
                baseColor: owner.btnHorizontalScroll.contains(mp) ? UiTheme.toolbarHover : .clear,
                hovered: false,
                radius: 4,
                font: tbFont,
                textColor: iconFg
            )

            UiTheme.dividerColor.setFill()
            let div2X = floor(owner.btnHorizontalScroll.maxX + 5)
            NSRect(x: div2X, y: owner.toolbarBounds.minY + 9, width: 1.0, height: owner.toolbarBounds.height - 18).fill()

            let canUndo = !owner.annotations.isEmpty
            drawIconBtnBg(owner.btnUndoTool, active: false, hovered: canUndo && owner.btnUndoTool.contains(mp))
            UiTheme.drawIconUndo(
                btnRect: owner.btnUndoTool,
                color: canUndo ? iconFg : UiTheme.textSecondary
            )

            drawIconBtnBg(owner.btnPin, active: false, hovered: owner.btnPin.contains(mp))
            UiTheme.drawIconPin(btnRect: owner.btnPin, color: iconFg)

            drawIconBtnBg(owner.btnSave, active: false, hovered: owner.btnSave.contains(mp))
            UiTheme.drawIconSave(btnRect: owner.btnSave, color: iconFg)

            drawIconBtnBg(owner.btnCancel, active: false, hovered: owner.btnCancel.contains(mp))
            UiTheme.drawIconClose(
                btnRect: owner.btnCancel,
                color: owner.btnCancel.contains(mp) ? UiTheme.accentRed : UiTheme.textSecondary
            )

            drawIconBtnBg(owner.btnCopyFinish, active: false, hovered: owner.btnCopyFinish.contains(mp))
            UiTheme.drawIconCheck(btnRect: owner.btnCopyFinish, color: UiTheme.weChatGreen)

            var tip: String?
            var tipTarget: NSRect = .zero
            if owner.btnRectTool.contains(mp) { tip = L10n.tipRectTool; tipTarget = owner.btnRectTool }
            else if owner.btnArrowTool.contains(mp) { tip = L10n.tipArrowTool; tipTarget = owner.btnArrowTool }
            else if owner.btnPenTool.contains(mp) { tip = L10n.tipPenTool; tipTarget = owner.btnPenTool }
            else if owner.btnVerticalScroll.contains(mp) { tip = L10n.tipVerticalScroll; tipTarget = owner.btnVerticalScroll }
            else if owner.btnHorizontalScroll.contains(mp) { tip = L10n.tipHorizontalScroll; tipTarget = owner.btnHorizontalScroll }
            else if owner.btnUndoTool.contains(mp) { tip = L10n.tipUndo; tipTarget = owner.btnUndoTool }
            else if owner.btnPin.contains(mp) { tip = L10n.tipPin; tipTarget = owner.btnPin }
            else if owner.btnSave.contains(mp) { tip = L10n.tipSave; tipTarget = owner.btnSave }
            else if owner.btnCancel.contains(mp) { tip = L10n.tipCancel; tipTarget = owner.btnCancel }
            else if owner.btnCopyFinish.contains(mp) { tip = L10n.tipFinish; tipTarget = owner.btnCopyFinish }

            if let tipText = tip {
                let dispBounds = owner.localDisplayVirtualRect(forRect: owner.toolbarBounds)
                let tipFont = UiTheme.fontPx(12)
                let tsz = (tipText as NSString).size(withAttributes: [.font: tipFont])
                let tw = ceil(tsz.width) + 12
                let th: CGFloat = 24
                let tx = floor(tipTarget.minX + (tipTarget.width - tw) / 2.0)
                var ty = owner.toolbarBounds.minY - th - 4
                if ty < dispBounds.minY + 4 { ty = owner.toolbarBounds.maxY + 4 }
                let tipRect = NSRect(x: tx, y: ty, width: tw, height: th)
                UiTheme.fillRoundedRect(
                    tipRect,
                    radius: 4,
                    color: NSColor(srgbRed: 32 / 255.0, green: 32 / 255.0, blue: 32 / 255.0, alpha: 235 / 255.0)
                )
                UiTheme.drawCenteredText(tipText, in: tipRect, font: tipFont, color: .white)
            }
        }

        private func drawWeChatSubBar(owner: RegionSelectorForm) {
            UiTheme.fillAndStrokeRoundedRect(
                owner.subBarBounds,
                radius: 8,
                fillColor: UiTheme.toolbarBg,
                strokeColor: UiTheme.toolbarBorder,
                lineWidth: 1.0
            )

            let dotRadii: [CGFloat] = [4, 7, 10]
            for i in 0..<3 {
                let r = owner.thicknessRects[i]
                let d = dotRadii[i]
                let c = (owner.selectedThicknessIndex == i)
                    ? UiTheme.weChatGreen
                    : NSColor(srgbRed: 165 / 255.0, green: 165 / 255.0, blue: 165 / 255.0, alpha: 1.0)
                c.setFill()
                let dotRect = NSRect(x: r.origin.x + (r.width - d) / 2, y: r.origin.y + (r.height - d) / 2, width: d, height: d)
                NSBezierPath(ovalIn: dotRect).fill()
            }

            UiTheme.dividerColor.setFill()
            let divX = floor(owner.thicknessRects[2].maxX + 6)
            NSRect(x: divX, y: owner.subBarBounds.minY + 8, width: 1.0, height: owner.subBarBounds.height - 16).fill()

            for i in 0..<owner.colorSwatchRects.count {
                let sr = owner.colorSwatchRects[i]
                UiTheme.fillAndStrokeRoundedRect(
                    sr,
                    radius: 3,
                    fillColor: UiTheme.annotColors[i],
                    strokeColor: UiTheme.borderSubtle,
                    lineWidth: 1.0
                )
                if owner.selectedColorIndex == i {
                    let outer = sr.insetBy(dx: -2, dy: -2)
                    UiTheme.strokeRoundedRect(outer, radius: 4, color: UiTheme.textPrimary, lineWidth: 1.5)
                }
            }
        }

        static func drawSingleAnnotation(_ item: AnnotationItem) {
            let strokeWidths: [CGFloat] = [2, 4, 6]
            let strokeW = strokeWidths[max(0, min(2, item.thicknessIndex))]

            if item.tool == .rectangle {
                let box = NSRect(
                    x: min(item.startPt.x, item.endPt.x),
                    y: min(item.startPt.y, item.endPt.y),
                    width: abs(item.endPt.x - item.startPt.x),
                    height: abs(item.endPt.y - item.startPt.y)
                )
                if box.width > 2 && box.height > 2 {
                    item.color.setStroke()
                    let p = NSBezierPath(rect: box)
                    p.lineWidth = strokeW
                    p.stroke()
                }
            } else if item.tool == .arrow {
                UiTheme.drawAnnotationArrow(
                    from: item.startPt,
                    to: item.endPt,
                    color: item.color,
                    strokeWidth: strokeW
                )
            } else if item.tool == .pen && item.penPoints.count >= 2 {
                item.color.setStroke()
                let p = NSBezierPath()
                p.lineWidth = strokeW
                p.lineCapStyle = .round
                p.lineJoinStyle = .round
                p.move(to: item.penPoints[0])
                for i in 1..<item.penPoints.count {
                    p.line(to: item.penPoints[i])
                }
                p.stroke()
            }
        }

        override func rightMouseDown(with event: NSEvent) {
            guard let owner = owner else { return }
            ensurePanelFocusedIfNeeded()
            let pt = virtualPoint(from: event)
            owner.mousePos = pt
            owner.handleEscapeAction()
        }

        override func mouseDown(with event: NSEvent) {
            guard let owner = owner else { return }
            ensurePanelFocusedIfNeeded()
            let pt = virtualPoint(from: event)
            owner.mousePos = pt

            if event.clickCount == 2 && owner.hasSelection && owner.selectionRect.contains(pt) {
                owner.finishNormalWithAction(.normalCopyCompleted)
                return
            }

            if owner.hasSelection {
                if owner.activeTool != .none && owner.subBarBounds.contains(pt) {
                    for i in 0..<3 where owner.thicknessRects[i].contains(pt) {
                        owner.selectedThicknessIndex = i
                        owner.refreshAllDisplays()
                        return
                    }
                    for i in 0..<owner.colorSwatchRects.count where owner.colorSwatchRects[i].contains(pt) {
                        owner.selectedColorIndex = i
                        owner.refreshAllDisplays()
                        return
                    }
                    return
                }

                if owner.btnRectTool.contains(pt) {
                    owner.activeTool = owner.activeTool == .rectangle ? .none : .rectangle
                    owner.updateToolbarLayout()
                    owner.updateCursorForPoint(pt)
                    owner.refreshAllDisplays()
                    return
                }
                if owner.btnArrowTool.contains(pt) {
                    owner.activeTool = owner.activeTool == .arrow ? .none : .arrow
                    owner.updateToolbarLayout()
                    owner.updateCursorForPoint(pt)
                    owner.refreshAllDisplays()
                    return
                }
                if owner.btnPenTool.contains(pt) {
                    owner.activeTool = owner.activeTool == .pen ? .none : .pen
                    owner.updateToolbarLayout()
                    owner.updateCursorForPoint(pt)
                    owner.refreshAllDisplays()
                    return
                }
                if owner.btnVerticalScroll.contains(pt) {
                    owner.confirmScrollAction(.verticalScroll)
                    return
                }
                if owner.btnHorizontalScroll.contains(pt) {
                    owner.confirmScrollAction(.horizontalScroll)
                    return
                }
                if owner.btnUndoTool.contains(pt) {
                    if !owner.annotations.isEmpty { _ = owner.annotations.popLast() }
                    owner.refreshAllDisplays()
                    return
                }
                if owner.btnPin.contains(pt) {
                    owner.finishNormalWithAction(.normalPinCompleted)
                    return
                }
                if owner.btnSave.contains(pt) {
                    owner.finishNormalWithAction(.normalSaveCompleted)
                    return
                }
                if owner.btnCancel.contains(pt) {
                    owner.cancelSelection()
                    return
                }
                if owner.btnCopyFinish.contains(pt) {
                    owner.finishNormalWithAction(.normalCopyCompleted)
                    return
                }

                if owner.activeTool != .none && owner.selectionRect.contains(pt) {
                    owner.currentDrawingItem = AnnotationItem(
                        tool: owner.activeTool,
                        color: UiTheme.annotColors[owner.selectedColorIndex],
                        thicknessIndex: owner.selectedThicknessIndex,
                        startPt: pt
                    )
                    return
                }

                let hit = owner.hitTestSelection(pt)
                if hit != .none && owner.annotations.isEmpty {
                    owner.activeDragZone = hit
                    owner.dragStart = pt
                    owner.resizeInitialRect = owner.selectionRect
                    owner.updateCursorForPoint(pt)
                    return
                }
                if owner.selectionRect.contains(pt) {
                    return
                }
            }

            owner.isSelecting = true
            owner.hasSelection = false
            owner.selectedWindowInfo = nil
            owner.activeTool = .none
            owner.annotations.removeAll()
            owner.activeDragZone = .none
            owner.dragStart = pt
            owner.selectionRect = NSRect(origin: pt, size: .zero)
            owner.updateCursorForPoint(pt)
            owner.refreshAllDisplays()
        }

        override func mouseMoved(with event: NSEvent) {
            guard let owner = owner else { return }
            ensurePanelFocusedIfNeeded()
            let pt = virtualPoint(from: event)
            owner.mousePos = pt
            if !owner.hasSelection && !owner.isSelecting {
                let hovered = owner.findHoveredWindow(localPt: pt)
                owner.hoverWindowRect = hovered.rect
                owner.hoveredWindowInfo = hovered.info
            }
            owner.updateCursorForPoint(pt)
            owner.refreshAllDisplays()
        }

        override func mouseDragged(with event: NSEvent) {
            guard let owner = owner else { return }
            let pt = virtualPoint(from: event)
            owner.mousePos = pt

            if let drawing = owner.currentDrawingItem {
                let cx = max(owner.selectionRect.minX, min(owner.selectionRect.maxX, pt.x))
                let cy = max(owner.selectionRect.minY, min(owner.selectionRect.maxY, pt.y))
                let clamped = NSPoint(x: cx, y: cy)
                drawing.endPt = clamped
                if drawing.tool == .pen {
                    if let last = drawing.penPoints.last {
                        if abs(last.x - clamped.x) + abs(last.y - clamped.y) >= 2 {
                            drawing.penPoints.append(clamped)
                        }
                    } else {
                        drawing.penPoints.append(clamped)
                    }
                }
                owner.refreshAllDisplays()
            } else if owner.isSelecting {
                let x = min(owner.dragStart.x, pt.x)
                let y = min(owner.dragStart.y, pt.y)
                let w = abs(pt.x - owner.dragStart.x)
                let h = abs(pt.y - owner.dragStart.y)
                owner.selectionRect = NSRect(x: x, y: y, width: w, height: h).integral
                owner.refreshAllDisplays()
            } else if owner.activeDragZone != .none {
                owner.applyResizeOrMove(pt)
                owner.updateToolbarLayout()
                owner.updateCursorForPoint(pt)
                owner.refreshAllDisplays()
            }
        }

        override func mouseUp(with event: NSEvent) {
            guard let owner = owner else { return }
            let pt = virtualPoint(from: event)
            owner.mousePos = pt

            if let item = owner.currentDrawingItem {
                owner.currentDrawingItem = nil
                let valid = item.tool == .pen
                    ? (item.penPoints.count >= 2)
                    : (abs(item.endPt.x - item.startPt.x) > 3 || abs(item.endPt.y - item.startPt.y) > 3)
                if valid {
                    owner.annotations.append(item)
                }
                owner.refreshAllDisplays()
                return
            }

            if owner.isSelecting {
                owner.isSelecting = false
                if owner.selectionRect.width >= 30 && owner.selectionRect.height >= 30 {
                    owner.hasSelection = true
                    owner.selectedWindowInfo = nil
                } else if owner.hoverWindowRect.width >= 50 && owner.hoverWindowRect.height >= 50 {
                    owner.selectionRect = owner.hoverWindowRect.integral
                    owner.hasSelection = true
                    owner.selectedWindowInfo = owner.hoveredWindowInfo
                }

                if owner.hasSelection {
                    if owner.presetMode == .verticalScroll || owner.presetMode == .horizontalScroll {
                        owner.confirmScrollAction(owner.presetMode)
                        return
                    }
                    owner.updateToolbarLayout()
                } else {
                    owner.selectionRect = .zero
                }
                owner.updateCursorForPoint(pt)
                owner.refreshAllDisplays()
            } else if owner.activeDragZone != .none {
                owner.activeDragZone = .none
                owner.updateToolbarLayout()
                owner.updateCursorForPoint(pt)
                owner.refreshAllDisplays()
            }
        }

        override func keyDown(with event: NSEvent) {
            guard let owner = owner else { return }
            _ = owner.handleSelectorKeyDown(event)
        }
    }
}
