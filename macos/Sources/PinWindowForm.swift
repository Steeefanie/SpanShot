import AppKit
import Foundation

/// Always-on-top floating Pin window (1:1 port of src/PinWindowForm.cs).
/// Supports left-drag to move, mouse wheel to scale (20% - 300%), double-click or right-click to close/copy.
public final class PinWindowForm: NSPanel {
    private static var activePins: [PinWindowForm] = []

    fileprivate let pinnedBitmap: RawBitmap
    fileprivate let pinnedNSImage: NSImage
    fileprivate var scaleFactor: CGFloat = 1.0
    fileprivate var dragging = false
    fileprivate var dragStartScreenPt: NSPoint = .zero
    fileprivate var winStartOrigin: NSPoint = .zero

    private final class PinContentView: NSView {
        weak var owner: PinWindowForm?

        override var isFlipped: Bool { true }
        override var acceptsFirstResponder: Bool { true }

        override func draw(_ dirtyRect: NSRect) {
            guard let owner = owner else { return }
            NSColor(srgbRed: 24 / 255.0, green: 28 / 255.0, blue: 38 / 255.0, alpha: 1.0).setFill()
            bounds.fill()

            NSGraphicsContext.current?.imageInterpolation = .high
            owner.pinnedNSImage.draw(
                in: NSRect(x: 2, y: 2, width: bounds.width - 4, height: bounds.height - 4),
                from: .zero,
                operation: .sourceOver,
                fraction: 1.0,
                respectFlipped: true,
                hints: nil
            )

            let borderColor = NSColor(srgbRed: 0 / 255.0, green: 185 / 255.0, blue: 255 / 255.0, alpha: 1.0)
            borderColor.setStroke()
            let borderPath = NSBezierPath(rect: NSRect(x: 1, y: 1, width: bounds.width - 2, height: bounds.height - 2))
            borderPath.lineWidth = 2.0
            borderPath.stroke()
        }

        override func mouseDown(with event: NSEvent) {
            window?.makeFirstResponder(self)
            if event.clickCount == 2 {
                owner?.closePin()
                return
            }
            guard let owner = owner else { return }
            owner.dragging = true
            owner.dragStartScreenPt = NSEvent.mouseLocation
            owner.winStartOrigin = owner.frame.origin
        }

        override func mouseDragged(with event: NSEvent) {
            guard let owner = owner, owner.dragging else { return }
            let cur = NSEvent.mouseLocation
            let dx = cur.x - owner.dragStartScreenPt.x
            let dy = cur.y - owner.dragStartScreenPt.y
            owner.setFrameOrigin(NSPoint(x: owner.winStartOrigin.x + dx, y: owner.winStartOrigin.y + dy))
        }

        override func mouseUp(with event: NSEvent) {
            owner?.dragging = false
        }

        override func scrollWheel(with event: NSEvent) {
            guard let owner = owner else { return }
            let delta = event.scrollingDeltaY
            if abs(delta) < 0.01 { return }
            let factor: CGFloat = delta > 0 ? 1.12 : 0.89
            owner.scaleFactor = max(0.2, min(3.0, owner.scaleFactor * factor))
            owner.updateScaledSize()
        }

        override func rightMouseDown(with event: NSEvent) {
            guard let owner = owner else { return }
            let menu = NSMenu()
            let copyItem = NSMenuItem(title: "复制图像 (⌘C)", action: #selector(PinWindowForm.copyImageAction), keyEquivalent: "")
            copyItem.target = owner
            menu.addItem(copyItem)

            let resetItem = NSMenuItem(title: "还原 100% 尺寸", action: #selector(PinWindowForm.resetSizeAction), keyEquivalent: "")
            resetItem.target = owner
            menu.addItem(resetItem)

            menu.addItem(.separator())

            let closeItem = NSMenuItem(title: "关闭贴图 (Esc / 双击)", action: #selector(PinWindowForm.closePinAction), keyEquivalent: "")
            closeItem.target = owner
            menu.addItem(closeItem)

            NSMenu.popUpContextMenu(menu, with: event, for: self)
        }

        override func keyDown(with event: NSEvent) {
            if event.keyCode == 53 { // Esc
                owner?.closePin()
            } else if (event.modifierFlags.contains(.command) || event.modifierFlags.contains(.control)),
                      event.charactersIgnoringModifiers?.lowercased() == "c" {
                owner?.copyImageAction()
            } else {
                super.keyDown(with: event)
            }
        }
    }

    public init(sourceBitmap: RawBitmap, initialTopDownLocation: CGPoint? = nil) {
        self.pinnedBitmap = sourceBitmap.clone()
        self.pinnedNSImage = self.pinnedBitmap.toNSImage()

        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let baseLogicalW = pinnedBitmap.logicalWidth
        let baseLogicalH = pinnedBitmap.logicalHeight
        if initialTopDownLocation == nil &&
            (baseLogicalW > screen.width * 0.7 || baseLogicalH > screen.height * 0.7) {
            scaleFactor = min(
                (screen.width * 0.7) / max(1.0, baseLogicalW),
                (screen.height * 0.7) / max(1.0, baseLogicalH)
            )
        }

        let w = max(60.0, round(baseLogicalW * scaleFactor)) + 4.0
        let h = max(40.0, round(baseLogicalH * scaleFactor)) + 4.0

        let frameRect: NSRect
        if let topLeft = initialTopDownLocation {
            let td = CGRect(x: topLeft.x - 2, y: topLeft.y - 2, width: w, height: h)
            frameRect = ScreenCapturer.topDownToCocoa(td)
        } else {
            frameRect = NSRect(
                x: screen.origin.x + (screen.width - w) / 2.0,
                y: screen.origin.y + (screen.height - h) / 2.0,
                width: w,
                height: h
            )
        }

        super.init(
            contentRect: frameRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        self.isOpaque = true
        self.level = .floating
        self.hasShadow = true
        self.isReleasedWhenClosed = false

        let view = PinContentView(frame: NSRect(x: 0, y: 0, width: w, height: h))
        view.owner = self
        self.contentView = view
    }

    override public var canBecomeKey: Bool { true }

    public func showPin() {
        PinWindowForm.activePins.append(self)
        self.makeKeyAndOrderFront(nil)
    }

    fileprivate func updateScaledSize() {
        let w = max(60.0, round(pinnedBitmap.logicalWidth * scaleFactor)) + 4.0
        let h = max(40.0, round(pinnedBitmap.logicalHeight * scaleFactor)) + 4.0
        let oldFrame = self.frame
        let newOrigin = NSPoint(x: oldFrame.origin.x, y: oldFrame.maxY - h)
        self.setFrame(NSRect(origin: newOrigin, size: NSSize(width: w, height: h)), display: true)
        self.contentView?.needsDisplay = true
    }

    @objc fileprivate func copyImageAction() {
        UiTheme.copyBitmapWithToast(pinnedBitmap)
    }

    @objc fileprivate func resetSizeAction() {
        scaleFactor = 1.0
        updateScaledSize()
    }

    @objc fileprivate func closePinAction() {
        closePin()
    }

    public func closePin() {
        self.orderOut(nil)
        PinWindowForm.activePins.removeAll { $0 === self }
    }
}
