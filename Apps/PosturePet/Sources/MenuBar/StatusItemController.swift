import AppKit
import MenuBarKit

/// The menu bar item. Left-click runs `onPrimaryClick`; right-click (or
/// Control-click) shows the menu from `menuProvider`, positioned and
/// highlighted the way the system positions status item menus.
final class StatusItemController: NSObject, NSMenuDelegate {
    var onPrimaryClick: (() -> Void)?
    var menuProvider: (() -> NSMenu)?

    private let item: NSStatusItem

    /// A fixed width, so animating the icon never shifts other menu bar items.
    static let width: CGFloat = 28

    override init() {
        item = NSStatusBar.system.statusItem(withLength: Self.width)
        super.init()
        item.autosaveName = "PosturePet"
        if let button = item.button {
            button.image = Self.placeholderImage
            button.imagePosition = .imageOnly
            button.target = self
            button.action = #selector(handleClick)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.setAccessibilityLabel(AppInfo.name)
        }
    }

    var button: NSStatusBarButton? { item.button }

    /// The status item's frame in screen coordinates, or nil when it isn't
    /// on screen (hidden behind the notch or by the user).
    var screenFrame: NSRect? {
        guard let button = item.button, let window = button.window, window.isVisible,
              window.occlusionState.contains(.visible)
        else { return nil }
        return window.convertToScreen(button.convert(button.bounds, to: nil))
    }

    func setImage(_ image: NSImage, accessibilityLabel: String) {
        item.button?.image = image
        item.button?.setAccessibilityLabel(accessibilityLabel)
    }

    @objc private func handleClick() {
        let event = NSApp.currentEvent
        let isSecondary = event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true
        if isSecondary {
            showMenu()
        } else {
            onPrimaryClick?()
        }
    }

    func showMenu() {
        guard let menu = menuProvider?() else { return }
        menu.delegate = self
        // Assigning the menu and clicking is what gives the native position
        // and the highlighted button; it's removed again when it closes so
        // left-click keeps working.
        item.menu = menu
        item.button?.performClick(nil)
    }

    func menuDidClose(_ menu: NSMenu) {
        item.menu = nil
    }

    private static let placeholderImage: NSImage = {
        let image = NSImage(systemSymbolName: "leaf.fill", accessibilityDescription: nil) ?? NSImage()
        image.isTemplate = true
        return image
    }()
}

/// Builds an `NSMenuItem` that runs a closure, so menus can be built inline.
/// The item keeps its handler alive through `representedObject`.
func ClosureMenuItem(
    _ title: String,
    key: String = "",
    modifiers: NSEvent.ModifierFlags = .command,
    handler: @escaping () -> Void
) -> NSMenuItem {
    let target = MenuActionTarget(handler)
    let item = NSMenuItem(title: title, action: #selector(MenuActionTarget.run), keyEquivalent: key)
    item.keyEquivalentModifierMask = modifiers
    item.target = target
    item.representedObject = target
    return item
}

private final class MenuActionTarget: NSObject {
    private let handler: () -> Void

    init(_ handler: @escaping () -> Void) {
        self.handler = handler
    }

    @objc func run() {
        handler()
    }
}
