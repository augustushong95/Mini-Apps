# Mini Apps

Monorepo for three small macOS menu bar apps, each shipped separately on the Mac App Store. Layout, commands and the add-an-app steps are in README.md.

## Rules

- Never edit a `.xcodeproj`. It's generated and gitignored: change `Apps/<App>/project.yml` (one app) or `Configs/MenuBarApp.yml` (all apps), then run `make generate`.
- Code two apps need goes in `Packages/MenuBarKit`, not copied between apps. Its public types are marked `@MainActor` explicitly; the app targets default to MainActor isolation instead.
- Verify changes with `make build`, which builds every app, since a MenuBarKit change can break any of them.

## Mac App Store requirements every app must keep

- App Sandbox stays on. Add an entitlement to `Apps/<App>/<App>.entitlements` only when a feature needs it, and say why in the change.
- Menu bar only: `LSUIElement` is set in the shared template; don't add a Dock icon or main window.
- Launch at login only through `LaunchAtLogin` (SMAppService), and only after the user turns it on. Never enable it by default.
- No private APIs, and no reading or writing outside the sandbox container without a user-granted entitlement.
- Swift 6 language mode, deployment target macOS 14.
