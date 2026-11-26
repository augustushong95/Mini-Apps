import AppKit

/// The menu bar item. Left-click runs `onPrimaryClick`; right-click (or
/// Control-click) shows the menu from `menuProvider`, positioned and
/// highlighted the way the system positions status item menus.
@MainActor
public final class StatusItemController: NSObject, NSMenuDelegate {
    public var onPrimaryClick: (() -> Void)?
    public var menuProvider: (() -> NSMenu)?

    private let item: NSStatusItem

    /// - Parameters:
    ///   - autosaveName: keeps the item's position in the menu bar across launches.
    ///   - placeholderSymbol: an SF Symbol shown until the app sets its own image.
    ///   - width: a fixed width, so changing the icon never shifts other items.
    public init(autosaveName: String, placeholderSymbol: String, width: CGFloat = 28) {
        item = NSStatusBar.system.statusItem(withLength: width)
        super.init()
        item.autosaveName = autosaveName
        if let button = item.button {
            let image = NSImage(systemSymbolName: placeholderSymbol, accessibilityDescription: nil) ?? NSImage()
            image.isTemplate = true
            button.image = image
            button.imagePosition = .imageOnly
            button.target = self
            button.action = #selector(handleClick)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.setAccessibilityLabel(AppInfo.name)
        }
    }

    public var button: NSStatusBarButton? { item.button }

    /// The status item's frame in screen coordinates, or nil when it isn't
    /// on screen (hidden behind the notch or by the user).
    public var screenFrame: NSRect? {
        guard let button = item.button, let window = button.window, window.isVisible,
              window.occlusionState.contains(.visible)
        else { return nil }
        return window.convertToScreen(button.convert(button.bounds, to: nil))
    }

    public func setImage(_ image: NSImage, accessibilityLabel: String) {
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

    public func showMenu() {
        guard let menu = menuProvider?() else { return }
        menu.delegate = self
        // Assigning the menu and clicking is what gives the native position
        // and the highlighted button; it's removed again when it closes so
        // left-click keeps working.
        item.menu = menu
        item.button?.performClick(nil)
    }

    public func menuDidClose(_ menu: NSMenu) {
        item.menu = nil
    }
}

/// Builds an `NSMenuItem` that runs a closure, so menus can be built inline.
/// The item keeps its handler alive through `representedObject`.
@MainActor
public func ClosureMenuItem(
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

@MainActor
private final class MenuActionTarget: NSObject {
    private let handler: () -> Void

    init(_ handler: @escaping () -> Void) {
        self.handler = handler
    }

    @objc func run() {
        handler()
    }
}
