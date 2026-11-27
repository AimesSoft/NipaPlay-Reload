import SwiftUI

// Shared by all Apple hosts. iOS/macOS include this source through their
// Classes symlinks; tvOS includes it directly in its Swift Package target.
struct MediaCapsuleMenuItem: Identifiable {
    let id: Int
    let label: String
    let enabled: Bool
}

struct MediaCapsuleAction: Identifiable {
    let id: Int
    let label: String
    let symbol: String
    let enabled: Bool
    let selected: Bool
    let items: [MediaCapsuleMenuItem]?
}

@available(macOS 11.0, iOS 13.0, tvOS 13.0, *)
final class MediaCapsuleModel: ObservableObject {
    @Published private(set) var actions: [MediaCapsuleAction] = []
    @Published var hoveredIndex: Int?
    @Published var pressedIndex: Int?
    var onPressed: ((Int) -> Void)?
    var onSelected: ((Int, Int) -> Void)?

    func update(_ args: [String: Any]) {
        actions = (args["actions"] as? [[String: Any]] ?? []).enumerated().map { index, action in
            MediaCapsuleAction(id: index,
                label: action["label"] as? String ?? "",
                symbol: action["symbol"] as? String ?? "",
                enabled: action["enabled"] as? Bool ?? false,
                selected: action["selected"] as? Bool ?? false,
                items: (action["items"] as? [[String: Any]])?.enumerated().map { selected, item in
                    MediaCapsuleMenuItem(id: selected, label: item["label"] as? String ?? "",
                                         enabled: item["enabled"] as? Bool ?? true)
                })
        }
    }

    func isEnabled(_ index: Int) -> Bool {
        actions.indices.contains(index) && actions[index].enabled
    }

    func activate(_ index: Int) {
        guard isEnabled(index) else { return }
        if actions[index].items == nil { onPressed?(index) }
    }

    func select(_ index: Int, item: Int) {
        guard isEnabled(index), let items = actions[index].items,
              items.indices.contains(item), items[item].enabled else { return }
        onSelected?(index, item)
    }

    func setInteraction(index: Int?, hovered: Bool, pressed: Bool) {
        hoveredIndex = (hovered && index != nil) ? index : nil
        pressedIndex = (pressed && index != nil) ? index : nil
    }
}

/// Matches Erika's shared HStack + regular interactive glass. Buttons retain
/// independent hit targets, and the system owns the glass's response/animation.
@available(macOS 26.0, iOS 26.0, tvOS 26.0, *)
struct MediaDetailActionCapsule: View {
    @ObservedObject var model: MediaCapsuleModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    static let itemWidth: CGFloat = 44
    static let height: CGFloat = 44
    static let inset: CGFloat = 4

    var body: some View {
        HStack(spacing: 0) {
            ForEach(model.actions) { action in
                control(action)
                    .frame(width: Self.itemWidth, height: Self.height)
                    .background {
                        let isPressed = model.pressedIndex == action.id
                        let isHovered = model.hoveredIndex == action.id
                        Group {
                            if isPressed {
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(Color.white.opacity(0.18))
                            } else if isHovered {
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(Color.white.opacity(0.08))
                            }
                        }
                        .animation(reduceMotion ? nil : .snappy(duration: 0.15),
                                   value: model.pressedIndex)
                        .animation(reduceMotion ? nil : .snappy(duration: 0.15),
                                   value: model.hoveredIndex)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .disabled(!action.enabled)
                    .accessibilityLabel(Text(verbatim: action.label))
                    .accessibilityIdentifier("media-detail-action-\(action.id)")
                    .help(action.label)
            }
        }
        .font(.system(size: 18, weight: .regular))
        .padding(.horizontal, Self.inset)
        .frame(height: Self.height)
        .glassEffect(.regular.interactive(), in: Capsule())
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("作品操作"))
        .preferredColorScheme(.dark)
        #if os(macOS)
        .focusEffectDisabled()
        #endif
    }

    @ViewBuilder private func control(_ action: MediaCapsuleAction) -> some View {
        if let items = action.items {
            Menu {
                ForEach(items) { item in
                    Button(item.label) { model.select(action.id, item: item.id) }
                        .disabled(!item.enabled)
                }
            } label: { label(action) }
            #if os(macOS)
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            #endif
            .buttonStyle(MediaCapsuleButtonStyle())
        } else {
            Button { model.activate(action.id) } label: { label(action) }
                .buttonStyle(MediaCapsuleButtonStyle())
        }
    }

    private func label(_ action: MediaCapsuleAction) -> some View {
        Label(action.label, systemImage: action.symbol)
            .labelStyle(.iconOnly)
            .symbolVariant(action.selected ? .fill : .none)
            .foregroundStyle(.primary)
            .frame(width: Self.itemWidth, height: Self.height)
            .animation(reduceMotion ? nil : .snappy(duration: 0.18), value: action.selected)
    }
}

@available(macOS 26.0, iOS 26.0, tvOS 26.0, *)
private struct MediaCapsuleButtonStyle: ButtonStyle {
    @Environment(\.isFocused) private var focused
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        #if os(tvOS)
        configuration.label
            .foregroundStyle(focused ? Color.black : Color.primary)
            .background { Capsule().fill(Color.white).opacity(focused ? 1 : 0) }
            .contentShape(Capsule())
            .opacity(enabled ? 1 : 0.42)
            .scaleEffect(reduceMotion ? 1 : configuration.isPressed ? 0.94 : focused ? 1.1 : 1)
            .animation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.6), value: focused)
        #else
        configuration.label
            .contentShape(Rectangle())
            .opacity(!enabled ? 0.42 : configuration.isPressed ? 0.55 : 1)
        #endif
    }
}

#if canImport(UIKit)
import UIKit

/// Proper containment lets SwiftUI's Menu and accessibility presentation reach
/// the Flutter view controller, including after a route is removed/reinserted.
@available(iOS 26.0, tvOS 26.0, *)
final class MediaCapsuleHostingContainer: UIView {
    let hosting: UIHostingController<MediaDetailActionCapsule>

    init(frame: CGRect, model: MediaCapsuleModel) {
        hosting = UIHostingController(rootView: MediaDetailActionCapsule(model: model))
        super.init(frame: frame)
        backgroundColor = .clear
        overrideUserInterfaceStyle = .dark
        hosting.view.backgroundColor = .clear
        hosting.view.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hosting.view)
        NSLayoutConstraint.activate([
            hosting.view.leadingAnchor.constraint(equalTo: leadingAnchor),
            hosting.view.trailingAnchor.constraint(equalTo: trailingAnchor),
            hosting.view.topAnchor.constraint(equalTo: topAnchor),
            hosting.view.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil {
            hosting.willMove(toParent: nil)
            hosting.removeFromParent()
            return
        }
        var responder: UIResponder? = next
        while let current = responder, !(current is UIViewController) { responder = current.next }
        guard let parent = responder as? UIViewController, hosting.parent !== parent else { return }
        if hosting.parent != nil {
            hosting.willMove(toParent: nil)
            hosting.removeFromParent()
        }
        parent.addChild(hosting)
        hosting.didMove(toParent: parent)
    }
}
#endif
