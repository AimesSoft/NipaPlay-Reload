// Compiled together with the plugin source by tool/test_native_media_controls_macos.sh.
final class TestMessenger: NSObject, FlutterBinaryMessenger {
    var handlers: [String: FlutterBinaryMessageHandler] = [:]
    var events: [FlutterMethodCall] = []
    let codec = FlutterStandardMethodCodec.sharedInstance()
    func send(onChannel channel: String, message: Data?) {
        if let message { events.append(codec.decodeMethodCall(message)) }
    }
    func send(onChannel channel: String, message: Data?, binaryReply callback: FlutterBinaryReply?) {
        send(onChannel: channel, message: message)
        callback?(nil)
    }
    func setMessageHandlerOnChannel(_ channel: String, binaryMessageHandler handler: FlutterBinaryMessageHandler?) -> FlutterBinaryMessengerConnection {
        handlers[channel] = handler
        return 1
    }
    func cleanUpConnection(_ connection: FlutterBinaryMessengerConnection) {}
}

let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
// SDK/OS versions and ordinary views without these optional accessors must
// remain safe; never send an unsupported KVC message.
MediaGlassInteraction.update(true, on: NSView())
let messenger = TestMessenger()
let accent = NSNumber(value: UInt32(0xFFFF7274))
private let control = MediaControlView(42, messenger, ["label": "观看", "symbol": "play.fill", "primary": true, "color": accent, "enabled": true])
if #available(macOS 26.0, *) {
    let glass = control.glassContainer as! NSGlassEffectView
    assert(glass.contentView === control.button)
    let workspace = NSWorkspace.shared
    let reduced = workspace.accessibilityDisplayShouldReduceTransparency || workspace.accessibilityDisplayShouldIncreaseContrast
    assert(glass.style == (reduced ? .regular : .clear))
    if #available(macOS 27.0, *) {
        assert((glass.value(forKey: "effectIsInteractive") as? Bool) ==
               (!workspace.accessibilityDisplayShouldReduceMotion && !reduced))
    }
    let color = glass.tintColor!.usingColorSpace(.deviceRGB)!
    assert(abs(color.redComponent - 1) < 0.001)
    assert(abs(color.greenComponent - 114.0/255) < 0.001)
}
control.frame = NSRect(x: 0, y: 0, width: 200, height: 44)
control.layoutSubtreeIfNeeded()
assert(control.button.frame.size == NSSize(width: 200, height: 44))
assert(control.pointerLight.mask!.frame.size == control.bounds.size)
assert(control.feedbackView.frame == control.bounds)
assert(control.subviews.last === control.feedbackView)
assert(control.pointerLight.superlayer === control.feedbackView.layer)
assert(control.outline.superlayer === control.feedbackView.layer)
if #available(macOS 26.0, *) { assert((control.glassContainer as! NSGlassEffectView).cornerRadius == 22) }
// Check both icon and text as a centered group, not independently centered.
private func checkContentLayout(_ button: MediaContentButton) {
    button.layoutSubtreeIfNeeded()
    let icon = button.iconView.frame
    let title = button.titleField.frame
    assert(icon.minX >= 16 - 0.01)
    assert(title.maxX <= button.bounds.maxX - 16 + 0.01)
    assert(abs(title.minX - icon.maxX - 10) < 0.01)
    assert(abs((icon.minX + title.maxX) / 2 - button.bounds.midX) < 0.01)
    assert(abs(icon.midY - button.bounds.midY) < 0.01)
    // Group centering alone can pass while the label is too narrow to draw.
    // cellSize includes NSTextField's internal text inset; intrinsic width does not.
    assert(title.width >= ceil(button.titleField.cell!.cellSize.width))
}
checkContentLayout(control.button)
assert(control.hitTest(NSPoint(x: 1, y: 1)) == nil)
let activate = messenger.codec.encode(FlutterMethodCall(methodName: "activate", arguments: nil))
messenger.handlers["nipaplay/native_media_control_42"]!(activate) { _ in }
assert(messenger.events.map(\.method) == ["pressed"])
for title in ["返回", "评论", "更多", "选择剧集"] {
    let symbol = title == "返回" ? "chevron.left" : title == "评论" ? "bubble.right" : title == "更多" ? "ellipsis" : "list.bullet"
    control.update(["label": title, "symbol": symbol, "primary": false, "enabled": true])
    assert(control.button.iconView.image != nil)
    if #available(macOS 26.0, *) {
        assert((control.glassContainer as! NSGlassEffectView).tintColor == nil)
    }
    assert(!control.button.isBordered)
    assert(control.appearance?.name == .darkAqua)
    assert(control.button.contentTintColor == .white)
    control.frame.size = NSSize(width: title == "选择剧集" ? 145 : 100, height: 44)
    control.layoutSubtreeIfNeeded()
    checkContentLayout(control.button)
}
control.update(["label": "继续观看", "detail": "第 3 话 已经没什么好害怕的了", "symbol": "play.fill", "enabled": true])
control.frame.size = NSSize(width: 220, height: 44)
control.layoutSubtreeIfNeeded()
checkContentLayout(control.button)
assert(control.button.titleField.frame.minX == control.button.detailField.frame.minX)
assert(control.button.detailField.frame.width >= ceil(control.button.detailField.cell!.cellSize.width))
let textBounds = control.button.titleField.frame.union(control.button.detailField.frame)
assert(abs(textBounds.midY - control.button.bounds.midY) < 0.01)

// Native tracking is installed even though Flutter owns click hit-testing.
if #available(macOS 26.0, *) {
    let glass = control.glassContainer as! TrackingMediaGlassView
    glass.updateTrackingAreas()
    assert(glass.trackingAreas.contains { $0.options.contains(.mouseMoved) && $0.options.contains(.activeInKeyWindow) })
}
control.updateAccessibility(reduceMotion: false, reducedEffects: false)
if #available(macOS 26.0, *) {
    let moved = NSEvent.mouseEvent(with: .mouseMoved, location: NSPoint(x: 55, y: 22),
        modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
        eventNumber: 0, clickCount: 0, pressure: 0)!
    (control.glassContainer as! TrackingMediaGlassView).mouseMoved(with: moved)
    assert(abs(control.pointerLight.startPoint.x - 0.25) < 0.001)
}
control.setInteraction(hovered: true, pressed: false, focused: false)
assert(abs(control.pointerLight.opacity - 0.10) < 0.001)
control.updatePointerLocation(NSPoint(x: 22, y: 11))
assert(abs(control.pointerLight.startPoint.x - 0.1) < 0.001)
control.updatePointerLocation(NSPoint(x: 198, y: 33))
assert(abs(control.pointerLight.startPoint.x - 0.9) < 0.001)
control.setInteraction(hovered: true, pressed: true, focused: false)
assert(control.button.cell!.isHighlighted)
assert(abs(control.pointerLight.opacity - 0.20) < 0.001)
control.setInteraction(hovered: true, pressed: false, focused: true)
assert(!control.button.cell!.isHighlighted)
assert(control.outline.opacity == 1)
assert(control.outline.lineWidth == 2)
control.setWindowActive(false)
assert(control.pointerLight.opacity == 0 && control.outline.opacity == 0)
assert(control.pointerLight.animationKeys()?.isEmpty ?? true)
control.setWindowActive(true)
control.updateAccessibility(reduceMotion: true, reducedEffects: false)
control.updatePointerLocation(NSPoint(x: 198, y: 33))
assert(control.pointerLight.startPoint == CGPoint(x: 0.5, y: 0.5))
assert(control.pointerLight.animationKeys()?.isEmpty ?? true)
if #available(macOS 27.0, *) {
    assert((control.glassContainer.value(forKey: "effectIsInteractive") as? Bool) == false)
}
control.updateAccessibility(reduceMotion: false, reducedEffects: true)
assert(control.pointerLight.opacity == 0)
assert(control.outline.opacity == 1) // Keep keyboard focus readable.
if #available(macOS 26.0, *) {
    assert((control.glassContainer as! NSGlassEffectView).style == .regular)
}
control.updateAccessibility(reduceMotion: false, reducedEffects: false)
control.setInteraction(hovered: false, pressed: false, focused: false)
assert(control.pointerLight.opacity == 0 && control.outline.opacity == 0)

control.update(["label": "观看", "enabled": false])
messenger.handlers["nipaplay/native_media_control_42"]!(activate) { _ in }
assert(messenger.events.count == 1)
control.setInteraction(hovered: true, pressed: true, focused: true)
assert(!control.hovered && !control.pressedState && !control.focused)
assert(control.pointerLight.opacity == 0 && control.outline.opacity == 0)
control.update(["label": "更多", "enabled": true, "items": [["label": "修改背景图", "enabled": true]]])
assert(control.entries?.count == 1)
let selectedItem = NSMenuItem(title: "修改背景图", action: nil, keyEquivalent: "")
selectedItem.tag = 0
control.selected(selectedItem)
assert(messenger.events.last!.method == "selected")
assert(messenger.events.last!.arguments as? Int == 0)
print("Native control checks passed: tracking, pointer light, press/focus, inactive/disabled reset, accessibility, text layout, native menu callback")
