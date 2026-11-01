import Flutter
import UIKit
import XCTest

// The isolated test bundle builds the real control without the other plugin
// views or a running Flutter engine. Production registration is typechecked
// separately with all plugin sources.
final class AdaptivePlatformUiPlugin: NSObject {}

private final class TestMessenger: NSObject, FlutterBinaryMessenger {
    var calls: [FlutterMethodCall] = []
    func send(onChannel channel: String, message: Data?) {
        if let message = message {
            calls.append(FlutterStandardMethodCodec.sharedInstance().decodeMethodCall(message))
        }
    }
    func send(onChannel channel: String, message: Data?, binaryReply callback: FlutterBinaryReply?) {
        send(onChannel: channel, message: message)
        callback?(nil)
    }
    func setMessageHandlerOnChannel(_ channel: String,
                                   binaryMessageHandler handler: FlutterBinaryMessageHandler?) -> FlutterBinaryMessengerConnection { 1 }
    func cleanUpConnection(_ connection: FlutterBinaryMessengerConnection) {}
}

@available(iOS 26.0, *)
final class MediaDetailControlTests: XCTestCase {
    private let messenger = TestMessenger()
    private func control(_ args: [String: Any] = [:]) -> MediaDetailControlView {
        MediaDetailControlView(CGRect(x: 0, y: 0, width: 220, height: 44), 1, messenger,
                               ["label": "评论", "symbol": "bubble.right", "enabled": true]
                                .merging(args) { _, new in new })
    }

    func testContentLivesInUIKitAndPointerInteractionIsEnabled() {
        let view = control(["label": "继续观看", "detail": "第 3 话", "symbol": "play.fill"])
        let button = view.button
        XCTAssertTrue(view.view() === button)
        XCTAssertTrue(button.isPointerInteractionEnabled)
        XCTAssertEqual(button.configuration?.title, "继续观看")
        XCTAssertEqual(button.configuration?.subtitle, "第 3 话")
        XCTAssertNotNil(button.configuration?.image)
        button.layoutIfNeeded()
        XCTAssertEqual(button.titleLabel?.text, "继续观看")
        XCTAssertEqual(button.subtitleLabel?.text, "第 3 话")
        XCTAssertEqual(button.overrideUserInterfaceStyle, .dark)
    }

    func testAccentOnlyAppliesToPrimaryAndClearsOnReuse() {
        let view = control(["primary": true, "color": NSNumber(value: UInt32(0xFFFF3366))])
        let accent = UIColor(red: 1, green: 0.2, blue: 0.4, alpha: 1)
        XCTAssertEqual(view.button.tintColor, accent)
        XCTAssertEqual(view.button.configuration?.baseBackgroundColor, accent)
        view.update(["label": "返回", "symbol": "chevron.left", "enabled": true])
        XCTAssertEqual(view.button.tintColor, .white)
        XCTAssertNotEqual(view.button.configuration?.baseBackgroundColor, accent)
        XCTAssertEqual(view.button.configuration?.baseForegroundColor, .white)
    }

    func testNativeMenuReplacesActivationAndSupportsDisabledItems() {
        let view = control(["label": "更多", "symbol": "ellipsis", "items": [
            ["label": "修改背景图", "enabled": true], ["label": "收藏", "enabled": false]]])
        XCTAssertTrue(view.button.showsMenuAsPrimaryAction)
        let actions = view.button.menu?.children.compactMap { $0 as? UIAction }
        XCTAssertEqual(actions?.map { $0.title }, ["修改背景图", "收藏"])
        XCTAssertEqual(actions?.last?.attributes, .disabled)
        view.button.sendActions(for: .primaryActionTriggered)
        XCTAssertTrue(messenger.calls.isEmpty, "Opening More must not also dispatch pressed")
        view.update(["label": "评论", "symbol": "bubble.right", "enabled": true])
        XCTAssertNil(view.button.menu)
        XCTAssertFalse(view.button.showsMenuAsPrimaryAction)
        view.button.sendActions(for: .primaryActionTriggered)
        XCTAssertEqual(messenger.calls.map { $0.method }, ["pressed"])
    }

    func testSystemOwnsHighlightAndNoCustomTransformSurvivesCancelOrDisable() {
        let view = control()
        view.button.isHighlighted = true
        view.button.sendActions(for: .touchDown)
        view.button.sendActions(for: .touchCancel)
        view.button.isHighlighted = false
        XCTAssertEqual(view.button.transform, .identity)
        // No hand-written scale animation overrides UIKit's accessibility policy.
        XCTAssertFalse(view.button.allControlEvents.contains(.touchDown))
        view.update(["label": "评论", "enabled": false])
        XCTAssertFalse(view.button.isEnabled)
        XCTAssertTrue(view.button.isPointerInteractionEnabled)
        XCTAssertEqual(view.button.transform, .identity)
    }
}
