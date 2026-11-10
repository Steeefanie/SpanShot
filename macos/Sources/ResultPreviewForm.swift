import AppKit
import CoreGraphics
import Foundation

/// Result preview & annotation editor window (1:1 port of src/ResultPreviewForm.cs).
public final class ResultPreviewForm: NSWindow, NSWindowDelegate {
    private static var activeWindows: [ResultPreviewForm] = []

    fileprivate enum EditTool {
        case panBrowse
        case rectangle
        case arrow
        case pen
        case crop
    }

    fileprivate struct OverlayAnnotation {
        var tool: EditTool
        var startPt: CGPoint
        var endPt: CGPoint
        var penPts: [CGPoint]
    }

    fileprivate var workingBitmap: RawBitmap
    fileprivate var workingNSImage: NSImage
    fileprivate var history: [RawBitmap] = []
    fileprivate let captureTypeTag: String

    fileprivate var currentTool: EditTool = .panBrowse
    fileprivate var fitToWindow: Bool

    fileprivate var topBarView: TopBarView!
    fileprivate var scrollView: NSScrollView!
    fileprivate var canvasView: CanvasImageView!

    public init(bitmap: RawBitmap, captureTypeTag: String) {
        self.workingBitmap = bitmap.clone()
        self.workingNSImage = self.workingBitmap.toNSImage()
        self.captureTypeTag = captureTypeTag

        let isLongOrWide = (Double(workingBitmap.height) > Double(workingBitmap.width) * 1.8) ||
                           (Double(workingBitmap.width) > Double(workingBitmap.height) * 1.8)
        self.fitToWindow = !isLongOrWide

        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let w: CGFloat = 960
        let h: CGFloat = 680
        let frame = NSRect(
            x: screen.origin.x + (screen.width - w) / 2.0,
            y: screen.origin.y + (screen.height - h) / 2.0,
            width: w,
            height: h
        )

        super.init(
            contentRect: frame,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )

        self.appearance = NSAppearance(named: .darkAqua)
        self.backgroundColor = UiTheme.bgDark
        self.isReleasedWhenClosed = false
        self.delegate = self

        setupUI()
        updateWindowTitle()
        UiTheme.copyBitmapToClipboard(workingBitmap)
        updateZoomLayout()
    }

    public func showModalOrFloating() {
        ResultPreviewForm.activeWindows.append(self)
        NSApp.activate(ignoringOtherApps: true)
        self.makeKeyAndOrderFront(nil)
    }

    public func windowWillClose(_ notification: Notification) {
        ResultPreviewForm.activeWindows.removeAll { $0 === self }
    }

    private func setupUI() {
        let rootView = NSView(frame: NSRect(x: 0, y: 0, width: 960, height: 680))
        rootView.wantsLayer = true
        rootView.layer?.backgroundColor = UiTheme.bgDark.cgColor

        topBarView = TopBarView(frame: NSRect(x: 0, y: 680 - 52, width: 960, height: 52))
        topBarView.owner = self
        topBarView.autoresizingMask = [.width, .minYMargin]

        scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 960, height: 680 - 52))
        scrollView.autoresizingMask = [.width, .height]
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.backgroundColor = NSColor(srgbRed: 20 / 255.0, green: 20 / 255.0, blue: 22 / 255.0, alpha: 1.0)
        scrollView.drawsBackground = true

        canvasView = CanvasImageView(frame: NSRect(x: 0, y: 0, width: workingBitmap.logicalWidth, height: workingBitmap.logicalHeight))
        canvasView.owner = self
        scrollView.documentView = canvasView

        rootView.addSubview(scrollView)
        rootView.addSubview(topBarView)
        self.contentView = rootView

        NotificationCenter.default.addObserver(
            forName: NSView.frameDidChangeNotification,
            object: scrollView.contentView,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            if self.fitToWindow {
                self.updateZoomLayout()
            }
        }
    }

    fileprivate func updateWindowTitle() {
        self.title = String(format: "%@ (%d × %d)", captureTypeTag, workingBitmap.width, workingBitmap.height)
    }

    fileprivate func selectTool(_ tool: EditTool) {
        currentTool = tool
        topBarView.needsDisplay = true
        canvasView.window?.invalidateCursorRects(for: canvasView)
    }

    fileprivate func toggleZoom() {
        fitToWindow.toggle()
        updateZoomLayout()
        topBarView.needsDisplay = true
    }

    fileprivate func updateZoomLayout() {
        let clipSize = scrollView.contentSize
        guard clipSize.width > 10 && clipSize.height > 10 else { return }

        if fitToWindow {
            canvasView.frame = NSRect(origin: .zero, size: clipSize)
        } else {
            canvasView.frame = NSRect(
                x: 0,
                y: 0,
                width: workingBitmap.logicalWidth,
                height: workingBitmap.logicalHeight
            )
        }
        canvasView.needsDisplay = true
    }

    fileprivate func pushHistory() {
        if history.count >= 10 {
            history.removeFirst()
        }
        history.append(workingBitmap.clone())
        topBarView.needsDisplay = true
    }

    fileprivate func performUndo() {
        guard let prev = history.popLast() else { return }
        workingBitmap = prev
        workingNSImage = workingBitmap.toNSImage()
        updateWindowTitle()
        updateZoomLayout()
        UiTheme.copyBitmapToClipboard(workingBitmap)
        topBarView.needsDisplay = true
        canvasView.needsDisplay = true
    }

    fileprivate func pinToDesktop() {
        let pin = PinWindowForm(sourceBitmap: workingBitmap)
        pin.showPin()
        self.close()
    }

    fileprivate func saveToFile() {
        UiTheme.saveBitmapDialog(workingBitmap, tag: captureTypeTag)
    }

    fileprivate func finishAndClose() {
        UiTheme.copyBitmapToClipboard(workingBitmap)
        ToastWindow.showToast(message: "已复制到剪贴板", accent: UiTheme.weChatGreen)
        self.close()
    }

    override public func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Esc
            self.close()
        } else if event.keyCode == 36 || event.keyCode == 76 { // Return / Enter
            finishAndClose()
        } else if event.modifierFlags.contains(.command) || event.modifierFlags.contains(.control) {
            let ch = event.charactersIgnoringModifiers?.lowercased() ?? ""
            if ch == "c" {
                UiTheme.copyBitmapWithToast(workingBitmap)
            } else if ch == "s" {
                saveToFile()
            } else if ch == "z" {
                performUndo()
            } else {
                super.keyDown(with: event)
            }
        } else {
            super.keyDown(with: event)
        }
    }

    fileprivate final class TopBarView: NSView {
        weak var owner: ResultPreviewForm?
        private var mousePos: NSPoint = .zero

        private struct BtnSpec {
            var id: String
            var title: String
            var rect: NSRect
        }

        override var isFlipped: Bool { true }

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

        private func buildButtons() -> [BtnSpec] {
            guard let owner = owner else { return [] }
            let y: CGFloat = 9
            let h: CGFloat = 34
            let gap: CGFloat = 6
            var curX: CGFloat = 14
            var list: [BtnSpec] = []

            func add(_ id: String, _ title: String, _ w: CGFloat, extraGap: CGFloat = 0) {
                list.append(BtnSpec(id: id, title: title, rect: NSRect(x: curX, y: y, width: w, height: h)))
                curX += w + gap + extraGap
            }

            add("pan", "浏览", 60)
            add("rect", "方框", 60)
            add("arrow", "箭头", 60)
            add("pen", "画笔", 60)
            add("crop", "裁剪", 60)
            add("undo", "撤销", 60, extraGap: 10)
            add("zoom", owner.fitToWindow ? "100%" : "适应窗口", 80)
            add("pin", "钉选", 68)
            add("save", "下载", 68)
            add("finish", "完成", 84)
            return list
        }

        override func draw(_ dirtyRect: NSRect) {
            UiTheme.toolbarBg.setFill()
            bounds.fill()

            guard let owner = owner else { return }
            let font = UiTheme.fontPx(13)

            for btn in buildButtons() {
                let hovered = btn.rect.contains(mousePos)
                var baseColor = UiTheme.bgPill
                var textColor = NSColor.white

                switch btn.id {
                case "pan": if owner.currentTool == .panBrowse { baseColor = UiTheme.weChatGreen }
                case "rect": if owner.currentTool == .rectangle { baseColor = UiTheme.weChatGreen }
                case "arrow": if owner.currentTool == .arrow { baseColor = UiTheme.weChatGreen }
                case "pen": if owner.currentTool == .pen { baseColor = UiTheme.weChatGreen }
                case "crop": if owner.currentTool == .crop { baseColor = UiTheme.weChatGreen }
                case "undo":
                    if owner.history.isEmpty {
                        textColor = UiTheme.textSecondary
                    }
                case "finish":
                    baseColor = UiTheme.weChatGreen
                default:
                    break
                }

                UiTheme.drawPillButton(
                    rect: btn.rect,
                    text: btn.title,
                    baseColor: baseColor,
                    hovered: hovered && (btn.id != "undo" || !owner.history.isEmpty),
                    radius: 4,
                    font: font,
                    textColor: textColor
                )
            }
        }

        override func mouseMoved(with event: NSEvent) {
            mousePos = convert(event.locationInWindow, from: nil)
            let hit = buildButtons().contains { $0.rect.contains(mousePos) }
            if hit {
                NSCursor.pointingHand.set()
            } else {
                NSCursor.arrow.set()
            }
            needsDisplay = true
        }

        override func mouseDown(with event: NSEvent) {
            guard let owner = owner else { return }
            let pt = convert(event.locationInWindow, from: nil)
            for btn in buildButtons() where btn.rect.contains(pt) {
                switch btn.id {
                case "pan": owner.selectTool(.panBrowse)
                case "rect": owner.selectTool(.rectangle)
                case "arrow": owner.selectTool(.arrow)
                case "pen": owner.selectTool(.pen)
                case "crop": owner.selectTool(.crop)
                case "undo": owner.performUndo()
                case "zoom": owner.toggleZoom()
                case "pin": owner.pinToDesktop()
                case "save": owner.saveToFile()
                case "finish": owner.finishAndClose()
                default: break
                }
                return
            }
        }
    }

    fileprivate final class CanvasImageView: NSView {
        weak var owner: ResultPreviewForm?
        private var isDragging = false
        private var dragStartPt: NSPoint = .zero
        private var dragCurPt: NSPoint = .zero
        private var panStartOrigin: NSPoint = .zero
        private var penPoints: [NSPoint] = []

        override var isFlipped: Bool { true }

        private func imageDrawRect() -> NSRect {
            guard let owner = owner else { return bounds }
            let logicalW = owner.workingBitmap.logicalWidth
            let logicalH = owner.workingBitmap.logicalHeight
            if !owner.fitToWindow || bounds.width <= 0 || bounds.height <= 0 {
                return NSRect(x: 0, y: 0, width: logicalW, height: logicalH)
            }
            let imgAspect = logicalW / max(1, logicalH)
            let boxAspect = bounds.width / max(1, bounds.height)

            if imgAspect > boxAspect {
                let scale = bounds.width / max(1, logicalW)
                let rh = logicalH * scale
                return NSRect(x: 0, y: (bounds.height - rh) / 2.0, width: bounds.width, height: rh)
            } else {
                let scale = bounds.height / max(1, logicalH)
                let rw = logicalW * scale
                return NSRect(x: (bounds.width - rw) / 2.0, y: 0, width: rw, height: bounds.height)
            }
        }

        private func controlToImagePoint(_ pt: NSPoint) -> NSPoint {
            guard let owner = owner else { return pt }
            let drawRect = imageDrawRect()
            let scaleX = CGFloat(owner.workingBitmap.width) / max(1.0, drawRect.width)
            let scaleY = CGFloat(owner.workingBitmap.height) / max(1.0, drawRect.height)
            let ix = round((pt.x - drawRect.origin.x) * scaleX)
            let iy = round((pt.y - drawRect.origin.y) * scaleY)
            return NSPoint(
                x: max(0, min(CGFloat(owner.workingBitmap.width), ix)),
                y: max(0, min(CGFloat(owner.workingBitmap.height), iy))
            )
        }

        override func draw(_ dirtyRect: NSRect) {
            NSColor(srgbRed: 20 / 255.0, green: 20 / 255.0, blue: 22 / 255.0, alpha: 1.0).setFill()
            bounds.fill()

            guard let owner = owner else { return }
            let destRect = imageDrawRect()
            NSGraphicsContext.current?.imageInterpolation = .high
            owner.workingNSImage.draw(
                in: destRect,
                from: .zero,
                operation: .sourceOver,
                fraction: 1.0,
                respectFlipped: true,
                hints: nil
            )

            guard isDragging && owner.currentTool != .panBrowse else { return }

            let annotColor = UiTheme.annotColors[0]
            if owner.currentTool == .pen && penPoints.count >= 2 {
                annotColor.setStroke()
                let path = NSBezierPath()
                path.lineWidth = 3.0
                path.lineCapStyle = .round
                path.lineJoinStyle = .round
                path.move(to: penPoints[0])
                for i in 1..<penPoints.count {
                    path.line(to: penPoints[i])
                }
                path.stroke()
                return
            }

            let box = NSRect(
                x: min(dragStartPt.x, dragCurPt.x),
                y: min(dragStartPt.y, dragCurPt.y),
                width: abs(dragCurPt.x - dragStartPt.x),
                height: abs(dragCurPt.y - dragStartPt.y)
            )

            if owner.currentTool == .crop {
                UiTheme.weChatGreen.setStroke()
                let path = NSBezierPath(rect: box)
                path.lineWidth = 2.0
                let pattern: [CGFloat] = [6.0, 4.0]
                path.setLineDash(pattern, count: 2, phase: 0)
                path.stroke()
            } else if owner.currentTool == .rectangle && box.width > 2 && box.height > 2 {
                annotColor.setStroke()
                let path = NSBezierPath(rect: box)
                path.lineWidth = 3.0
                path.stroke()
            } else if owner.currentTool == .arrow {
                Self.drawArrowPath(from: dragStartPt, to: dragCurPt, color: annotColor, lineWidth: 3.0)
            }
        }

        static func drawArrowPath(from p1: NSPoint, to p2: NSPoint, color: NSColor, lineWidth: CGFloat) {
            let dx = p2.x - p1.x
            let dy = p2.y - p1.y
            let len = hypot(dx, dy)
            guard len >= 3.0 else { return }

            color.setStroke()
            color.setFill()
            let path = NSBezierPath()
            path.lineWidth = lineWidth
            path.lineCapStyle = .round
            path.move(to: p1)
            path.line(to: p2)
            path.stroke()

            let angle = atan2(dy, dx)
            let headLen: CGFloat = max(10.0, lineWidth * 3.8)
            let wingAngle: CGFloat = .pi / 6.5
            let a1 = NSPoint(x: p2.x - headLen * cos(angle - wingAngle), y: p2.y - headLen * sin(angle - wingAngle))
            let a2 = NSPoint(x: p2.x - headLen * cos(angle + wingAngle), y: p2.y - headLen * sin(angle + wingAngle))

            let head = NSBezierPath()
            head.move(to: p2)
            head.line(to: a1)
            head.line(to: a2)
            head.close()
            head.fill()
        }

        override func mouseDown(with event: NSEvent) {
            guard let owner = owner else { return }
            let pt = convert(event.locationInWindow, from: nil)
            isDragging = true
            dragStartPt = pt
            dragCurPt = pt
            penPoints.removeAll()
            if owner.currentTool == .pen {
                penPoints.append(pt)
            }
            if owner.currentTool == .panBrowse {
                panStartOrigin = owner.scrollView.contentView.bounds.origin
            }
        }

        override func mouseDragged(with event: NSEvent) {
            guard isDragging, let owner = owner else { return }
            let pt = convert(event.locationInWindow, from: nil)
            dragCurPt = pt

            if owner.currentTool == .panBrowse && !owner.fitToWindow {
                let dx = pt.x - dragStartPt.x
                let dy = pt.y - dragStartPt.y
                let clipView = owner.scrollView.contentView
                let maxX = max(0, bounds.width - clipView.bounds.width)
                let maxY = max(0, bounds.height - clipView.bounds.height)
                let nextX = max(0, min(maxX, panStartOrigin.x - dx))
                let nextY = max(0, min(maxY, panStartOrigin.y - dy))
                clipView.scroll(to: NSPoint(x: nextX, y: nextY))
                owner.scrollView.reflectScrolledClipView(clipView)
            } else if owner.currentTool == .pen {
                if let last = penPoints.last {
                    if abs(last.x - pt.x) + abs(last.y - pt.y) >= 2 {
                        penPoints.append(pt)
                    }
                } else {
                    penPoints.append(pt)
                }
                needsDisplay = true
            } else if owner.currentTool != .panBrowse {
                needsDisplay = true
            }
        }

        override func mouseUp(with event: NSEvent) {
            guard isDragging, let owner = owner else { return }
            isDragging = false
            let pt = convert(event.locationInWindow, from: nil)
            dragCurPt = pt

            if owner.currentTool == .panBrowse { return }

            if owner.currentTool == .pen {
                if penPoints.count >= 2 {
                    owner.pushHistory()
                    let imgPts = penPoints.map { controlToImagePoint($0) }
                    let strokeW = 3.0 * owner.workingBitmap.scaleFactor
                    commitAnnotationToBitmap(owner: owner) {
                        UiTheme.annotColors[0].setStroke()
                        let path = NSBezierPath()
                        path.lineWidth = strokeW
                        path.lineCapStyle = .round
                        path.lineJoinStyle = .round
                        path.move(to: imgPts[0])
                        for i in 1..<imgPts.count {
                            path.line(to: imgPts[i])
                        }
                        path.stroke()
                    }
                }
                penPoints.removeAll()
                needsDisplay = true
                return
            }

            let imgStart = controlToImagePoint(dragStartPt)
            let imgEnd = controlToImagePoint(pt)
            let box = NSRect(
                x: min(imgStart.x, imgEnd.x),
                y: min(imgStart.y, imgEnd.y),
                width: abs(imgEnd.x - imgStart.x),
                height: abs(imgEnd.y - imgStart.y)
            ).intersection(NSRect(x: 0, y: 0, width: owner.workingBitmap.width, height: owner.workingBitmap.height))

            if owner.currentTool == .crop {
                if box.width >= 24 && box.height >= 24 {
                    owner.pushHistory()
                    owner.workingBitmap = owner.workingBitmap.clone(
                        x: Int(box.origin.x),
                        y: Int(box.origin.y),
                        width: Int(box.width),
                        height: Int(box.height)
                    )
                    owner.workingNSImage = owner.workingBitmap.toNSImage()
                    owner.updateWindowTitle()
                    owner.updateZoomLayout()
                    UiTheme.copyBitmapToClipboard(owner.workingBitmap)
                }
                owner.selectTool(.panBrowse)
            } else if box.width >= 4 || box.height >= 4 {
                owner.pushHistory()
                let tool = owner.currentTool
                let strokeW = 3.0 * owner.workingBitmap.scaleFactor
                commitAnnotationToBitmap(owner: owner) {
                    let color = UiTheme.annotColors[0]
                    if tool == .rectangle {
                        color.setStroke()
                        let path = NSBezierPath(rect: box)
                        path.lineWidth = strokeW
                        path.stroke()
                    } else if tool == .arrow {
                        Self.drawArrowPath(from: imgStart, to: imgEnd, color: color, lineWidth: strokeW)
                    }
                }
            }
            needsDisplay = true
        }

        private func commitAnnotationToBitmap(owner: ResultPreviewForm, drawBlock: () -> Void) {
            owner.workingBitmap.withTopDownCGContext { ctx in
                let prev = NSGraphicsContext.current
                NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
                drawBlock()
                NSGraphicsContext.current = prev
            }
            owner.workingNSImage = owner.workingBitmap.toNSImage()
            UiTheme.copyBitmapToClipboard(owner.workingBitmap)
        }
    }
}
