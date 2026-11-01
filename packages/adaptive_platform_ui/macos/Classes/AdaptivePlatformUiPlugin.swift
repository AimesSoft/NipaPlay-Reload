import AppKit
import QuartzCore
import FlutterMacOS

public final class AdaptivePlatformUiPlugin: NSObject, FlutterPlugin {
    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "nipaplay/native_media_controls", binaryMessenger: registrar.messenger)
        channel.setMethodCallHandler { call, result in
            guard call.method == "supportsGlass" else { result(FlutterMethodNotImplemented); return }
            if #available(macOS 26.0, *) { result(true) } else { result(false) }
        }
        registrar.register(MediaControlFactory(registrar.messenger), withId: "nipaplay/native_media_control")
    }
}

private final class MediaControlFactory: NSObject, FlutterPlatformViewFactory {
    let messenger: FlutterBinaryMessenger
    init(_ messenger: FlutterBinaryMessenger) { self.messenger = messenger }
    func createArgsCodec() -> (FlutterMessageCodec & NSObjectProtocol)? { FlutterStandardMessageCodec.sharedInstance() }
    func create(withViewIdentifier viewId: Int64, arguments args: Any?) -> NSView {
        MediaControlView(viewId, messenger, args as? [String: Any] ?? [:])
    }
}

/// The public macOS 27 property is absent from the SDK used by Xcode 26 CI.
/// Resolve its Objective-C accessors at runtime so SDK 26 builds retain the
/// macOS 26 feedback layers and can still enable native interaction on macOS 27.
private enum MediaGlassInteraction {
    static let getter = NSSelectorFromString("effectIsInteractive")
    static let setter = NSSelectorFromString("setEffectIsInteractive:")

    static func update(_ enabled: Bool, on view: NSView) {
        guard #available(macOS 27.0, *),
              view.responds(to: getter), view.responds(to: setter) else { return }
        if (view.value(forKey: "effectIsInteractive") as? Bool) != enabled {
            view.setValue(enabled, forKey: "effectIsInteractive")
        }
    }
}

/// A borderless NSButton places imageLeading at the cell edge rather than
/// centering the icon/title as a group. Lay out its native content explicitly.
private final class MediaContentButton: NSButton {
    let iconView = NSImageView()
    let titleField = NSTextField(labelWithString: "")
    let detailField = NSTextField(labelWithString: "")

    init() {
        super.init(frame: .zero)
        title = ""
        isBordered = false
        iconView.imageScaling = .scaleProportionallyDown
        iconView.contentTintColor = .white
        titleField.font = .systemFont(ofSize: 15, weight: .semibold)
        titleField.textColor = .white
        detailField.font = .systemFont(ofSize: 11)
        detailField.textColor = .white.withAlphaComponent(0.78)
        for field in [titleField, detailField] {
            field.maximumNumberOfLines = 1
            field.lineBreakMode = .byTruncatingTail
            field.cell?.usesSingleLineMode = true
            field.setAccessibilityElement(false)
            addSubview(field)
        }
        iconView.setAccessibilityElement(false)
        addSubview(iconView)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func updateContent(label: String, detail: String, symbol: String) {
        titleField.stringValue = label
        detailField.stringValue = detail
        detailField.isHidden = detail.isEmpty
        iconView.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 20, weight: .regular))
        let opacity: CGFloat = isEnabled ? 1 : 0.45
        for view in [iconView, titleField, detailField] { view.alphaValue = opacity }
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let inset: CGFloat = 16
        let iconWidth: CGFloat = 20
        let spacing: CGFloat = 10
        let availableTextWidth = max(0, bounds.width - 2 * inset - iconWidth - spacing)
        // NSTextField's intrinsic width excludes its cell's horizontal inset.
        // Use cellSize so an exactly fitted label doesn't truncate itself.
        let titleSize = titleField.cell?.cellSize ?? titleField.intrinsicContentSize
        let detailSize = detailField.isHidden ? NSSize.zero :
            (detailField.cell?.cellSize ?? detailField.intrinsicContentSize)
        let textWidth = min(ceil(max(titleSize.width, detailSize.width)), floor(availableTextWidth))
        let groupWidth = iconWidth + spacing + textWidth
        let startX = (bounds.width - groupWidth) / 2
        let textX = startX + iconWidth + spacing
        let lineSpacing: CGFloat = detailField.isHidden ? 0 : 1
        let textHeight = titleSize.height + detailSize.height + lineSpacing
        let textY = (bounds.height - textHeight) / 2
        iconView.frame = NSRect(x: startX, y: (bounds.height - iconWidth) / 2,
                               width: iconWidth, height: iconWidth)
        titleField.frame = NSRect(x: textX,
            y: isFlipped ? textY : textY + detailSize.height + lineSpacing,
            width: textWidth, height: titleSize.height)
        detailField.frame = NSRect(x: textX,
            y: isFlipped ? textY + titleSize.height + lineSpacing : textY,
            width: textWidth, height: detailSize.height)
    }
}

/// Native tracking still receives AppKit mouse events when the Flutter input
/// adapter owns clicks. Keep high-frequency pointer movement on the native side.
@available(macOS 26.0, *)
private final class TrackingMediaGlassView: NSGlassEffectView {
    var onPointer: ((NSEvent, Bool) -> Void)?
    private var pointerTrackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        if let pointerTrackingArea { removeTrackingArea(pointerTrackingArea) }
        super.updateTrackingAreas()
        let area = NSTrackingArea(rect: .zero,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeInKeyWindow,
                      .inVisibleRect, .enabledDuringMouseDrag], owner: self, userInfo: nil)
        addTrackingArea(area)
        pointerTrackingArea = area
    }
    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        onPointer?(event, true)
    }
    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        onPointer?(event, true)
    }
    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        onPointer?(event, false)
    }
}

private final class MediaControlView: NSView {
    let button = MediaContentButton()
    let channel: FlutterMethodChannel
    let glassContainer: NSView
    private var accessibilityObserver: NSObjectProtocol?
    private var windowObservers: [NSObjectProtocol] = []
    let feedbackView = NSView()
    let pointerLight = CAGradientLayer()
    let outline = CAShapeLayer()
    private let pointerLightMask = CAShapeLayer()
    private(set) var hovered = false
    private(set) var pressedState = false
    private(set) var focused = false
    private(set) var windowActive = true
    private var nativePointerInside: Bool?
    private var menuTracking = false
    private var reduceMotion = false
    private var reducedEffects = false
    var entries: [[String: Any]]?

    init(_ id: Int64, _ messenger: FlutterBinaryMessenger, _ args: [String: Any]) {
        channel = FlutterMethodChannel(name: "nipaplay/native_media_control_\(id)", binaryMessenger: messenger)
        if #available(macOS 26.0, *) {
            let glass = TrackingMediaGlassView()
            glass.contentView = button
            MediaGlassInteraction.update(true, on: glass)
            glassContainer = glass
        } else {
            glassContainer = NSView()
            glassContainer.addSubview(button)
        }
        super.init(frame: .zero)
        // The immersive page always has a dark artwork background, independently
        // of the user's global light/dark appearance.
        appearance = NSAppearance(named: .darkAqua)
        wantsLayer = true
        button.target = self
        button.action = #selector(pressed)
        glassContainer.translatesAutoresizingMaskIntoConstraints = false
        addSubview(glassContainer)
        NSLayoutConstraint.activate([
            glassContainer.leadingAnchor.constraint(equalTo: leadingAnchor),
            glassContainer.trailingAnchor.constraint(equalTo: trailingAnchor),
            glassContainer.topAnchor.constraint(equalTo: topAnchor),
            glassContainer.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        button.autoresizingMask = [.width, .height]
        // Keep feedback above AppKit's view-managed glass/content layers. Adding
        // layers directly to the root can place them beneath its native subviews.
        feedbackView.wantsLayer = true
        feedbackView.setAccessibilityElement(false)
        feedbackView.autoresizingMask = [.width, .height]
        addSubview(feedbackView, positioned: .above, relativeTo: glassContainer)
        pointerLight.type = .radial
        pointerLight.colors = [NSColor.white.cgColor, NSColor.clear.cgColor]
        pointerLight.locations = [0, 1]
        pointerLight.opacity = 0
        pointerLight.mask = pointerLightMask
        feedbackView.layer?.addSublayer(pointerLight)
        outline.fillColor = nil
        outline.lineWidth = 1
        outline.opacity = 0
        feedbackView.layer?.addSublayer(outline)
        if #available(macOS 26.0, *), let glass = glassContainer as? TrackingMediaGlassView {
            glass.onPointer = { [weak self] event, inside in
                guard let self else { return }
                let changed = self.nativePointerInside != inside
                self.nativePointerInside = inside
                self.updatePointerLocation(self.convert(event.locationInWindow, from: nil))
                if changed { self.updateInteractionAppearance() }
            }
        }
        updateGlassStyle()
        accessibilityObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil, queue: .main
        ) { [weak self] _ in self?.updateGlassStyle() }
        update(args)
        channel.setMethodCallHandler { [weak self] call, result in
            switch call.method {
            case "update":
                if let args = call.arguments as? [String: Any] { self?.update(args) }
                result(nil)
            case "activate":
                if let self, self.button.isEnabled { self.button.performClick(nil) }
                result(nil)
            case "setInteraction":
                if let args = call.arguments as? [String: Any] {
                    self?.setInteraction(hovered: args["hovered"] as? Bool ?? false,
                        pressed: args["pressed"] as? Bool ?? false,
                        focused: args["focused"] as? Bool ?? false)
                }
                result(nil)
            default:
                result(FlutterMethodNotImplemented)
            }
        }
    }
    // AppKitView input is not forwarded by the pinned Flutter SDK. Let the
    // Flutter gesture/focus layer own input, avoiding duplicate native clicks.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit {
        channel.setMethodCallHandler(nil)
        if let accessibilityObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(accessibilityObserver)
        }
        for observer in windowObservers { NotificationCenter.default.removeObserver(observer) }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        for observer in windowObservers { NotificationCenter.default.removeObserver(observer) }
        windowObservers.removeAll()
        nativePointerInside = nil
        guard let window else {
            setWindowActive(false)
            return
        }
        window.acceptsMouseMovedEvents = true
        setWindowActive(window.isKeyWindow)
        let center = NotificationCenter.default
        windowObservers = [
            center.addObserver(forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main) { [weak self] _ in
                self?.setWindowActive(true)
            },
            center.addObserver(forName: NSWindow.didResignKeyNotification, object: window, queue: .main) { [weak self] _ in
                self?.setWindowActive(false)
            },
        ]
    }

    func setWindowActive(_ active: Bool) {
        windowActive = active
        if !active { pressedState = false }
        if active, let window {
            let point = convert(window.convertPoint(fromScreen: NSEvent.mouseLocation), from: nil)
            nativePointerInside = bounds.contains(point)
            updatePointerLocation(point)
        }
        updateInteractionAppearance(animated: false)
    }

    func setInteraction(hovered: Bool, pressed: Bool, focused: Bool) {
        self.hovered = button.isEnabled && hovered
        self.pressedState = button.isEnabled && pressed
        self.focused = button.isEnabled && focused
        updateInteractionAppearance()
    }

    func updatePointerLocation(_ point: NSPoint) {
        let normalized = reduceMotion ? CGPoint(x: 0.5, y: 0.5) :
            CGPoint(x: min(1, max(0, point.x / max(1, bounds.width))),
                    y: min(1, max(0, point.y / max(1, bounds.height))))
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        pointerLight.startPoint = normalized
        pointerLight.endPoint = CGPoint(x: normalized.x + 0.65, y: normalized.y + 1)
        CATransaction.commit()
    }

    private func updateInteractionAppearance(animated: Bool = true) {
        let active = button.isEnabled && windowActive && !menuTracking
        let over = active && hovered && nativePointerInside != false
        let down = active && pressedState
        let keyFocus = active && focused
        if down && !over { updatePointerLocation(NSPoint(x: bounds.midX, y: bounds.midY)) }
        if !animated || reduceMotion || !active {
            pointerLight.removeAllAnimations()
            outline.removeAllAnimations()
        }
        CATransaction.begin()
        CATransaction.setDisableActions(!animated || reduceMotion || !active)
        CATransaction.setAnimationDuration(down ? 0.07 : 0.18)
        // The glass material remains system-rendered. These native layers make
        // pointer/focus state visible even on macOS 26, before effectIsInteractive.
        pointerLight.opacity = reducedEffects ? 0 : (down ? 0.20 : over ? 0.10 : 0)
        outline.opacity = keyFocus ? 1 : (down ? 0.35 : over ? 0.16 : 0)
        outline.strokeColor = keyFocus ? NSColor.keyboardFocusIndicatorColor.cgColor : NSColor.white.cgColor
        outline.lineWidth = keyFocus ? 2 : 1
        button.highlight(down)
        CATransaction.commit()
        MediaGlassInteraction.update(active && !reduceMotion && !reducedEffects,
                                     on: glassContainer)
    }

    override func layout() {
        super.layout()
        button.frame = glassContainer.bounds
        feedbackView.frame = bounds
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        pointerLight.frame = bounds
        pointerLightMask.frame = pointerLight.bounds
        pointerLightMask.path = CGPath(roundedRect: bounds, cornerWidth: bounds.height / 2,
                                      cornerHeight: bounds.height / 2, transform: nil)
        outline.frame = bounds
        let outlineBounds = bounds.width > 3 && bounds.height > 3 ?
            bounds.insetBy(dx: 1.5, dy: 1.5) : bounds
        outline.path = CGPath(roundedRect: outlineBounds,
                              cornerWidth: max(0, bounds.height / 2 - 1.5),
                              cornerHeight: max(0, bounds.height / 2 - 1.5), transform: nil)
        CATransaction.commit()
        if #available(macOS 26.0, *), let glass = glassContainer as? NSGlassEffectView {
            glass.cornerRadius = bounds.height / 2
        }
    }

    private func updateGlassStyle() {
        let workspace = NSWorkspace.shared
        updateAccessibility(reduceMotion: workspace.accessibilityDisplayShouldReduceMotion,
            reducedEffects: workspace.accessibilityDisplayShouldReduceTransparency ||
                workspace.accessibilityDisplayShouldIncreaseContrast)
    }

    func updateAccessibility(reduceMotion: Bool, reducedEffects: Bool) {
        self.reduceMotion = reduceMotion
        self.reducedEffects = reducedEffects
        if reduceMotion {
            updatePointerLocation(NSPoint(x: bounds.midX, y: bounds.midY))
        }
        if #available(macOS 26.0, *), let glass = glassContainer as? NSGlassEffectView {
            // Preserve system readability options while using clear glass normally.
            glass.style = reducedEffects ? .regular : .clear
        }
        updateInteractionAppearance(animated: false)
    }

    func update(_ args: [String: Any]) {
        let label = args["label"] as? String ?? ""
        let detail = args["detail"] as? String ?? ""
        button.isEnabled = args["enabled"] as? Bool ?? false
        if !button.isEnabled { hovered = false; pressedState = false; focused = false }
        entries = args["items"] as? [[String: Any]]
        button.updateContent(label: label, detail: detail, symbol: args["symbol"] as? String ?? "")
        button.setAccessibilityLabel(label)
        button.setAccessibilityHelp(detail)
        button.isBordered = false
        button.contentTintColor = .white
        if #available(macOS 26.0, *), let glass = glassContainer as? NSGlassEffectView {
            let primary = args["primary"] as? Bool ?? false
            if primary, let argb = args["color"] as? NSNumber {
                let value = argb.uint32Value
                glass.tintColor = NSColor(red: CGFloat((value >> 16) & 255) / 255,
                    green: CGFloat((value >> 8) & 255) / 255, blue: CGFloat(value & 255) / 255,
                    alpha: CGFloat((value >> 24) & 255) / 255)
            } else { glass.tintColor = nil }
        }
        updateInteractionAppearance(animated: false)
    }

    @objc func pressed() {
        guard let entries else { channel.invokeMethod("pressed", arguments: nil); return }
        menuTracking = true
        updateInteractionAppearance(animated: false)
        defer {
            menuTracking = false
            if let window {
                let point = convert(window.convertPoint(fromScreen: NSEvent.mouseLocation), from: nil)
                nativePointerInside = bounds.contains(point)
                updatePointerLocation(point)
            }
            updateInteractionAppearance()
        }
        let menu = NSMenu()
        for (index, entry) in entries.enumerated() {
            let item = NSMenuItem(title: entry["label"] as? String ?? "", action: #selector(selected(_:)), keyEquivalent: "")
            item.target = self
            item.tag = index
            item.isEnabled = entry["enabled"] as? Bool ?? true
            menu.addItem(item)
        }
        menu.autoenablesItems = false
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.minY), in: button)
    }
    @objc func selected(_ item: NSMenuItem) { channel.invokeMethod("selected", arguments: item.tag) }
}
