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

/// Fullscreen region selector with window auto-snapping, inline annotation tools, and floating toolbar.
/// 1:1 port of src/RegionSelectorForm.cs.
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
    fileprivate let presetMode: CaptureActionMode
    fileprivate let detectedWindows: [CGRect]

    fileprivate var dragStart: NSPoint = .zero
    fileprivate var selectionRect: NSRect = .zero
    fileprivate var hoverWindowRect: NSRect = .zero
    fileprivate var resizeInitialRect: NSRect = .zero
    fileprivate var activeDragZone: ResizeHitZone = .none
    fileprivate var isSelecting = false
    fileprivate var hasSelection = false

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
    private var onComplete: ((RegionSelectorForm) -> Void)?
    private var finished = false

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

    public init(presetMode: CaptureActionMode = .none) {
        self.presetMode = presetMode
        self.virtualBoundsTopDown = ScreenCapturer.virtualScreenTopDownBounds
        self.detectedWindows = ScreenCapturer.getVisibleWindowRectangles()
        self.desktopSnapshot = ScreenCapturer.captureRegion(self.virtualBoundsTopDown)
        self.desktopNSImage = self.desktopSnapshot.toNSImage()

        let cocoaFrame = ScreenCapturer.topDownToCocoa(self.virtualBoundsTopDown)

        super.init(
            contentRect: cocoaFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        self.isOpaque = true
        self.level = .screenSaver
        self.hasShadow = false
        self.sharingType = .none
        self.isReleasedWhenClosed = false
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let view = SelectorCanvasView(frame: NSRect(x: 0, y: 0, width: cocoaFrame.width, height: cocoaFrame.height))
        view.owner = self
        self.contentView = view
    }

    override public var canBecomeKey: Bool { true }
    override public var canBecomeMain: Bool { true }

    public func beginSelection(completion: @escaping (RegionSelectorForm) -> Void) {
        self.onComplete = completion
        NSApp.activate(ignoringOtherApps: true)
        self.makeKeyAndOrderFront(nil)
        self.makeFirstResponder(self.contentView)

        let curTopDown = ScreenCapturer.mouseLocationTopDown()
        mousePos = NSPoint(
            x: curTopDown.x - virtualBoundsTopDown.origin.x,
            y: curTopDown.y - virtualBoundsTopDown.origin.y
        )
        hoverWindowRect = findHoveredWindowRect(localPt: mousePos)
        contentView?.needsDisplay = true
    }

    fileprivate func confirmScrollAction(_ scrollMode: CaptureActionMode) {
        guard !finished else { return }
        finished = true
        chosenAction = scrollMode
        self.orderOut(nil)
        onComplete?(self)
    }

    fileprivate func finishNormalWithAction(_ mode: CaptureActionMode) {
        guard !finished else { return }
        finished = true
        annotatedRegionBitmap = renderSelectedRegionWithAnnotations()
        chosenAction = mode
        self.orderOut(nil)
        onComplete?(self)
    }

    fileprivate func cancelSelection() {
        guard !finished else { return }
        finished = true
        chosenAction = .none
        self.orderOut(nil)
        onComplete?(self)
    }

    private func renderSelectedRegionWithAnnotations() -> RawBitmap {
        let w = max(1, Int(selectionRect.width))
        let h = max(1, Int(selectionRect.height))
        let bmp = desktopSnapshot.clone(
            x: Int(selectionRect.origin.x),
            y: Int(selectionRect.origin.y),
            width: w,
            height: h
        )
        guard !annotations.isEmpty else { return bmp }

        bmp.withTopDownCGContext { ctx in
            let prev = NSGraphicsContext.current
            NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
            ctx.translateBy(x: -selectionRect.origin.x, y: -selectionRect.origin.y)
            for item in annotations {
                SelectorCanvasView.drawSingleAnnotation(item)
            }
            NSGraphicsContext.current = prev
        }
        return bmp
    }

    fileprivate func findHoveredWindowRect(localPt: NSPoint) -> NSRect {
        let screenPt = CGPoint(
            x: localPt.x + virtualBoundsTopDown.origin.x,
            y: localPt.y + virtualBoundsTopDown.origin.y
        )
        let viewBounds = NSRect(x: 0, y: 0, width: virtualBoundsTopDown.width, height: virtualBoundsTopDown.height)
        for wr in detectedWindows {
            if wr.contains(screenPt) {
                let localRect = NSRect(
                    x: wr.origin.x - virtualBoundsTopDown.origin.x,
                    y: wr.origin.y - virtualBoundsTopDown.origin.y,
                    width: wr.width,
                    height: wr.height
                ).intersection(viewBounds)
                if localRect.width >= 50 && localRect.height >= 50 {
                    return localRect
                }
            }
        }
        return .zero
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

    fileprivate func applyResizeOrMove(_ pt: NSPoint) {
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

    fileprivate func updateToolbarLayout() {
        let viewW = virtualBoundsTopDown.width
        let viewH = virtualBoundsTopDown.height

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
        if x < 8 { x = selectionRect.minX }
        if x + barWidth > viewW - 8 { x = max(8, viewW - barWidth - 8) }

        let totalNeededH = barH + (activeTool != .none ? 42 : 0)
        var y = selectionRect.maxY + 6
        var placedAbove = false
        if y + totalNeededH > viewH - 8 {
            y = selectionRect.minY - barH - 6
            placedAbove = true
            if y < 8 {
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
        if subY < 6 { subY = toolbarBounds.maxY + 5 }

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

            owner.desktopNSImage.draw(
                in: bounds,
                from: .zero,
                operation: .copy,
                fraction: 1.0,
                respectFlipped: true,
                hints: nil
            )

            let dimColor = NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 120 / 255.0)
            if owner.selectionRect.width > 0 && owner.selectionRect.height > 0 {
                let path = NSBezierPath(rect: bounds)
                path.appendRect(owner.selectionRect)
                path.windingRule = .evenOdd
                dimColor.setFill()
                path.fill()
            } else {
                if owner.hoverWindowRect.width > 0 && owner.hoverWindowRect.height > 0 {
                    let path = NSBezierPath(rect: bounds)
                    path.appendRect(owner.hoverWindowRect)
                    path.windingRule = .evenOdd
                    dimColor.setFill()
                    path.fill()

                    NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 38 / 255.0).setFill()
                    owner.hoverWindowRect.fill()
                } else {
                    dimColor.setFill()
                    bounds.fill()
                }
            }

            if !owner.hasSelection && !owner.isSelecting && owner.hoverWindowRect.width > 8 && owner.hoverWindowRect.height > 8 {
                let insetHover = owner.hoverWindowRect.insetBy(dx: 2, dy: 2)
                UiTheme.weChatGreen.setStroke()
                let hp = NSBezierPath(rect: insetHover)
                hp.lineWidth = 3.0
                hp.stroke()
            }

            if !owner.hasSelection && !owner.isSelecting {
                let prompt: String
                if owner.presetMode == .verticalScroll {
                    prompt = "纵向长截图 · 请拖动框选区域或点击窗口 (Esc 退出)"
                } else if owner.presetMode == .horizontalScroll {
                    prompt = "横向长截图 · 请拖动框选区域或点击窗口 (Esc 退出)"
                } else {
                    prompt = "请拖动框选区域或点击窗口 (Esc 退出)"
                }
                let font = UiTheme.fontPx(13)
                let psz = (prompt as NSString).size(withAttributes: [.font: font])
                let pw = ceil(psz.width) + 28
                let ph: CGFloat = 34
                let px = (bounds.width - pw) / 2.0
                let py: CGFloat = 28
                let promptRect = NSRect(x: px, y: py, width: pw, height: ph)

                UiTheme.fillRoundedRect(promptRect, radius: 6, color: UiTheme.toolbarBg)
                UiTheme.strokeRoundedRect(promptRect, radius: 6, color: UiTheme.weChatGreen, lineWidth: 1.5)
                UiTheme.drawCenteredText(prompt, in: promptRect, font: font, color: .white)
            }

            if owner.selectionRect.width > 0 && owner.selectionRect.height > 0 {
                NSGraphicsContext.saveGraphicsState()
                NSBezierPath(rect: owner.selectionRect).addClip()
                for item in owner.annotations {
                    Self.drawSingleAnnotation(item)
                }
                if let current = owner.currentDrawingItem {
                    Self.drawSingleAnnotation(current)
                }
                NSGraphicsContext.restoreGraphicsState()

                UiTheme.weChatGreen.setStroke()
                let bp = NSBezierPath(rect: owner.selectionRect)
                bp.lineWidth = 1.5
                bp.stroke()

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

                let sizeText = String(format: "%d × %d", Int(owner.selectionRect.width), Int(owner.selectionRect.height))
                let badgeFont = UiTheme.fontPx(12)
                let tsz = (sizeText as NSString).size(withAttributes: [.font: badgeFont])
                let bw = ceil(tsz.width) + 12
                let bh = ceil(tsz.height) + 6
                let bx = owner.selectionRect.minX
                var by = owner.selectionRect.minY - bh - 4
                if by < 6 { by = owner.selectionRect.minY + 4 }

                let badgeRect = NSRect(x: bx, y: by, width: bw, height: bh)
                UiTheme.fillRoundedRect(
                    badgeRect,
                    radius: 3,
                    color: NSColor(srgbRed: 36 / 255.0, green: 36 / 255.0, blue: 36 / 255.0, alpha: 220 / 255.0)
                )
                UiTheme.drawCenteredText(sizeText, in: badgeRect, font: badgeFont, color: .white)
            }

            if owner.hasSelection && !owner.isSelecting && owner.activeDragZone == .none {
                drawWeChatToolbar(owner: owner)
                if owner.activeTool != .none {
                    drawWeChatSubBar(owner: owner)
                }
            }
        }

        private func drawSquareHandle(x: CGFloat, y: CGFloat) {
            let sz: CGFloat = 6
            UiTheme.weChatGreen.setFill()
            NSRect(x: x - sz / 2, y: y - sz / 2, width: sz, height: sz).fill()
        }

        private func drawIconBtnBg(_ rect: NSRect, active: Bool, hovered: Bool) {
            guard active || hovered else { return }
            let c = active ? NSColor(srgbRed: 72 / 255.0, green: 72 / 255.0, blue: 72 / 255.0, alpha: 1.0) : UiTheme.toolbarHover
            UiTheme.fillRoundedRect(rect, radius: 3, color: c)
        }

        private func drawWeChatToolbar(owner: RegionSelectorForm) {
            UiTheme.fillRoundedRect(owner.toolbarBounds, radius: 4, color: UiTheme.toolbarBg)
            UiTheme.strokeRoundedRect(owner.toolbarBounds, radius: 4, color: UiTheme.toolbarBorder, lineWidth: 1.0)

            let mp = owner.mousePos
            drawIconBtnBg(owner.btnRectTool, active: owner.activeTool == .rectangle, hovered: owner.btnRectTool.contains(mp))
            UiTheme.drawIconRect(btnRect: owner.btnRectTool, color: owner.activeTool == .rectangle ? UiTheme.weChatGreen : .white)

            drawIconBtnBg(owner.btnArrowTool, active: owner.activeTool == .arrow, hovered: owner.btnArrowTool.contains(mp))
            UiTheme.drawIconArrow(btnRect: owner.btnArrowTool, color: owner.activeTool == .arrow ? UiTheme.weChatGreen : .white)

            drawIconBtnBg(owner.btnPenTool, active: owner.activeTool == .pen, hovered: owner.btnPenTool.contains(mp))
            UiTheme.drawIconPen(btnRect: owner.btnPenTool, color: owner.activeTool == .pen ? UiTheme.weChatGreen : .white)

            UiTheme.dividerColor.setStroke()
            let div1X = owner.btnPenTool.maxX + 5
            let div1 = NSBezierPath()
            div1.move(to: NSPoint(x: div1X, y: owner.toolbarBounds.minY + 9))
            div1.line(to: NSPoint(x: div1X, y: owner.toolbarBounds.maxY - 9))
            div1.stroke()

            let tbFont = UiTheme.fontPx(13)
            UiTheme.drawPillButton(
                rect: owner.btnVerticalScroll,
                text: "纵向长截",
                baseColor: owner.btnVerticalScroll.contains(mp) ? UiTheme.toolbarHover : .clear,
                hovered: false,
                radius: 3,
                font: tbFont,
                textColor: .white
            )
            UiTheme.drawPillButton(
                rect: owner.btnHorizontalScroll,
                text: "横向长截",
                baseColor: owner.btnHorizontalScroll.contains(mp) ? UiTheme.toolbarHover : .clear,
                hovered: false,
                radius: 3,
                font: tbFont,
                textColor: .white
            )

            UiTheme.dividerColor.setStroke()
            let div2X = owner.btnHorizontalScroll.maxX + 5
            let div2 = NSBezierPath()
            div2.move(to: NSPoint(x: div2X, y: owner.toolbarBounds.minY + 9))
            div2.line(to: NSPoint(x: div2X, y: owner.toolbarBounds.maxY - 9))
            div2.stroke()

            let canUndo = !owner.annotations.isEmpty
            drawIconBtnBg(owner.btnUndoTool, active: false, hovered: canUndo && owner.btnUndoTool.contains(mp))
            UiTheme.drawIconUndo(
                btnRect: owner.btnUndoTool,
                color: canUndo ? .white : NSColor(srgbRed: 110 / 255.0, green: 110 / 255.0, blue: 110 / 255.0, alpha: 1.0)
            )

            drawIconBtnBg(owner.btnPin, active: false, hovered: owner.btnPin.contains(mp))
            UiTheme.drawIconPin(btnRect: owner.btnPin, color: .white)

            drawIconBtnBg(owner.btnSave, active: false, hovered: owner.btnSave.contains(mp))
            UiTheme.drawIconSave(btnRect: owner.btnSave, color: .white)

            drawIconBtnBg(owner.btnCancel, active: false, hovered: owner.btnCancel.contains(mp))
            UiTheme.drawIconClose(
                btnRect: owner.btnCancel,
                color: owner.btnCancel.contains(mp) ? UiTheme.accentRed : NSColor(srgbRed: 220 / 255.0, green: 220 / 255.0, blue: 220 / 255.0, alpha: 1.0)
            )

            drawIconBtnBg(owner.btnCopyFinish, active: false, hovered: owner.btnCopyFinish.contains(mp))
            UiTheme.drawIconCheck(btnRect: owner.btnCopyFinish, color: UiTheme.weChatGreen)

            var tip: String?
            var tipTarget: NSRect = .zero
            if owner.btnRectTool.contains(mp) { tip = "矩形"; tipTarget = owner.btnRectTool }
            else if owner.btnArrowTool.contains(mp) { tip = "箭头"; tipTarget = owner.btnArrowTool }
            else if owner.btnPenTool.contains(mp) { tip = "画笔"; tipTarget = owner.btnPenTool }
            else if owner.btnUndoTool.contains(mp) { tip = "撤销"; tipTarget = owner.btnUndoTool }
            else if owner.btnPin.contains(mp) { tip = "贴图"; tipTarget = owner.btnPin }
            else if owner.btnSave.contains(mp) { tip = "保存"; tipTarget = owner.btnSave }
            else if owner.btnCancel.contains(mp) { tip = "退出"; tipTarget = owner.btnCancel }
            else if owner.btnCopyFinish.contains(mp) { tip = "完成"; tipTarget = owner.btnCopyFinish }

            if let tipText = tip {
                let tipFont = UiTheme.fontPx(12)
                let tsz = (tipText as NSString).size(withAttributes: [.font: tipFont])
                let tw = ceil(tsz.width) + 12
                let th: CGFloat = 24
                let tx = tipTarget.minX + (tipTarget.width - tw) / 2.0
                var ty = owner.toolbarBounds.minY - th - 4
                if ty < 4 { ty = owner.toolbarBounds.maxY + 4 }
                let tipRect = NSRect(x: tx, y: ty, width: tw, height: th)
                UiTheme.fillRoundedRect(
                    tipRect,
                    radius: 3,
                    color: NSColor(srgbRed: 32 / 255.0, green: 32 / 255.0, blue: 32 / 255.0, alpha: 235 / 255.0)
                )
                UiTheme.drawCenteredText(tipText, in: tipRect, font: tipFont, color: .white)
            }
        }

        private func drawWeChatSubBar(owner: RegionSelectorForm) {
            UiTheme.fillRoundedRect(owner.subBarBounds, radius: 4, color: UiTheme.toolbarBg)
            UiTheme.strokeRoundedRect(owner.subBarBounds, radius: 4, color: UiTheme.toolbarBorder, lineWidth: 1.0)

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

            UiTheme.dividerColor.setStroke()
            let divX = owner.thicknessRects[2].maxX + 6
            let div = NSBezierPath()
            div.move(to: NSPoint(x: divX, y: owner.subBarBounds.minY + 8))
            div.line(to: NSPoint(x: divX, y: owner.subBarBounds.maxY - 8))
            div.stroke()

            for i in 0..<owner.colorSwatchRects.count {
                let sr = owner.colorSwatchRects[i]
                UiTheme.fillRoundedRect(sr, radius: 2, color: UiTheme.annotColors[i])
                if owner.selectedColorIndex == i {
                    let outer = sr.insetBy(dx: -2, dy: -2)
                    UiTheme.strokeRoundedRect(outer, radius: 3, color: .white, lineWidth: 1.5)
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
                let dx = item.endPt.x - item.startPt.x
                let dy = item.endPt.y - item.startPt.y
                let len = hypot(dx, dy)
                guard len >= 3.0 else { return }

                item.color.setStroke()
                item.color.setFill()
                let p = NSBezierPath()
                p.lineWidth = strokeW
                p.lineCapStyle = .round
                p.move(to: item.startPt)
                p.line(to: item.endPt)
                p.stroke()

                let angle = atan2(dy, dx)
                let headLen = max(9.0, strokeW * 3.5)
                let wing: CGFloat = .pi / 6.5
                let a1 = NSPoint(x: item.endPt.x - headLen * cos(angle - wing), y: item.endPt.y - headLen * sin(angle - wing))
                let a2 = NSPoint(x: item.endPt.x - headLen * cos(angle + wing), y: item.endPt.y - headLen * sin(angle + wing))
                let head = NSBezierPath()
                head.move(to: item.endPt)
                head.line(to: a1)
                head.line(to: a2)
                head.close()
                head.fill()
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
            let pt = convert(event.locationInWindow, from: nil)
            if owner.hasSelection {
                owner.hasSelection = false
                owner.selectionRect = .zero
                owner.activeTool = .none
                owner.annotations.removeAll()
                owner.activeDragZone = .none
                owner.hoverWindowRect = owner.findHoveredWindowRect(localPt: pt)
                needsDisplay = true
            } else {
                owner.cancelSelection()
            }
        }

        override func mouseDown(with event: NSEvent) {
            guard let owner = owner else { return }
            let pt = convert(event.locationInWindow, from: nil)

            if event.clickCount == 2 && owner.hasSelection && owner.selectionRect.contains(pt) {
                owner.finishNormalWithAction(.normalCopyCompleted)
                return
            }

            if owner.hasSelection {
                if owner.activeTool != .none && owner.subBarBounds.contains(pt) {
                    for i in 0..<3 where owner.thicknessRects[i].contains(pt) {
                        owner.selectedThicknessIndex = i
                        needsDisplay = true
                        return
                    }
                    for i in 0..<owner.colorSwatchRects.count where owner.colorSwatchRects[i].contains(pt) {
                        owner.selectedColorIndex = i
                        needsDisplay = true
                        return
                    }
                    return
                }

                if owner.btnRectTool.contains(pt) {
                    owner.activeTool = owner.activeTool == .rectangle ? .none : .rectangle
                    owner.updateToolbarLayout()
                    needsDisplay = true
                    return
                }
                if owner.btnArrowTool.contains(pt) {
                    owner.activeTool = owner.activeTool == .arrow ? .none : .arrow
                    owner.updateToolbarLayout()
                    needsDisplay = true
                    return
                }
                if owner.btnPenTool.contains(pt) {
                    owner.activeTool = owner.activeTool == .pen ? .none : .pen
                    owner.updateToolbarLayout()
                    needsDisplay = true
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
                    needsDisplay = true
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
                    return
                }
                if owner.selectionRect.contains(pt) {
                    return
                }
            }

            owner.isSelecting = true
            owner.hasSelection = false
            owner.activeTool = .none
            owner.annotations.removeAll()
            owner.activeDragZone = .none
            owner.dragStart = pt
            owner.selectionRect = NSRect(origin: pt, size: .zero)
            needsDisplay = true
        }

        override func mouseMoved(with event: NSEvent) {
            guard let owner = owner else { return }
            let pt = convert(event.locationInWindow, from: nil)
            owner.mousePos = pt
            if !owner.hasSelection && !owner.isSelecting {
                owner.hoverWindowRect = owner.findHoveredWindowRect(localPt: pt)
            }
            needsDisplay = true
        }

        override func mouseDragged(with event: NSEvent) {
            guard let owner = owner else { return }
            let pt = convert(event.locationInWindow, from: nil)
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
                needsDisplay = true
            } else if owner.isSelecting {
                let x = min(owner.dragStart.x, pt.x)
                let y = min(owner.dragStart.y, pt.y)
                let w = abs(pt.x - owner.dragStart.x)
                let h = abs(pt.y - owner.dragStart.y)
                owner.selectionRect = NSRect(x: x, y: y, width: w, height: h).integral
                needsDisplay = true
            } else if owner.activeDragZone != .none {
                owner.applyResizeOrMove(pt)
                owner.updateToolbarLayout()
                needsDisplay = true
            }
        }

        override func mouseUp(with event: NSEvent) {
            guard let owner = owner else { return }

            if let item = owner.currentDrawingItem {
                owner.currentDrawingItem = nil
                let valid = item.tool == .pen
                    ? (item.penPoints.count >= 2)
                    : (abs(item.endPt.x - item.startPt.x) > 3 || abs(item.endPt.y - item.startPt.y) > 3)
                if valid {
                    owner.annotations.append(item)
                }
                needsDisplay = true
                return
            }

            if owner.isSelecting {
                owner.isSelecting = false
                if owner.selectionRect.width >= 30 && owner.selectionRect.height >= 30 {
                    owner.hasSelection = true
                } else if owner.hoverWindowRect.width >= 50 && owner.hoverWindowRect.height >= 50 {
                    owner.selectionRect = owner.hoverWindowRect.integral
                    owner.hasSelection = true
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
                needsDisplay = true
            } else if owner.activeDragZone != .none {
                owner.activeDragZone = .none
                owner.updateToolbarLayout()
                needsDisplay = true
            }
        }

        override func keyDown(with event: NSEvent) {
            guard let owner = owner else { return }
            if event.keyCode == 53 { // Escape
                if owner.hasSelection {
                    owner.hasSelection = false
                    owner.selectionRect = .zero
                    owner.activeTool = .none
                    owner.annotations.removeAll()
                    owner.activeDragZone = .none
                    needsDisplay = true
                } else {
                    owner.cancelSelection()
                }
                return
            }

            guard owner.hasSelection && owner.selectionRect.width >= 20 && owner.selectionRect.height >= 20 else { return }

            let hasCmdOrCtrl = event.modifierFlags.contains(.command) || event.modifierFlags.contains(.control)
            let ch = event.charactersIgnoringModifiers?.lowercased() ?? ""

            if hasCmdOrCtrl && ch == "z" {
                if !owner.annotations.isEmpty {
                    _ = owner.annotations.popLast()
                    needsDisplay = true
                }
            } else if event.keyCode == 36 || event.keyCode == 49 || (hasCmdOrCtrl && ch == "c") {
                owner.finishNormalWithAction(.normalCopyCompleted)
            } else if ch == "v" && !hasCmdOrCtrl {
                owner.confirmScrollAction(.verticalScroll)
            } else if ch == "h" && !hasCmdOrCtrl {
                owner.confirmScrollAction(.horizontalScroll)
            } else if ch == "p" && !hasCmdOrCtrl {
                owner.finishNormalWithAction(.normalPinCompleted)
            } else if hasCmdOrCtrl && ch == "s" {
                owner.finishNormalWithAction(.normalSaveCompleted)
            } else if owner.activeTool == .none && (event.keyCode == 123 || event.keyCode == 124 || event.keyCode == 125 || event.keyCode == 126) {
                let dx: CGFloat = event.keyCode == 123 ? -1 : (event.keyCode == 124 ? 1 : 0)
                let dy: CGFloat = event.keyCode == 126 ? -1 : (event.keyCode == 125 ? 1 : 0)
                if event.modifierFlags.contains(.shift) {
                    owner.selectionRect.size.width = max(24, min(bounds.width - owner.selectionRect.origin.x, owner.selectionRect.width + dx))
                    owner.selectionRect.size.height = max(24, min(bounds.height - owner.selectionRect.origin.y, owner.selectionRect.height + dy))
                } else {
                    owner.selectionRect.origin.x = max(0, min(bounds.width - owner.selectionRect.width, owner.selectionRect.origin.x + dx))
                    owner.selectionRect.origin.y = max(0, min(bounds.height - owner.selectionRect.height, owner.selectionRect.origin.y + dy))
                }
                owner.updateToolbarLayout()
                needsDisplay = true
            }
        }
    }
}
