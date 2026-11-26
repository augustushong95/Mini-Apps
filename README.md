# Mini Apps

Three small macOS menu bar apps, each shipped separately on the Mac App Store.

| App | Folder | Status |
| --- | --- | --- |
| Posture Pet | [Apps/PosturePet](Apps/PosturePet) | v1 in development; see [NOTES.md](Apps/PosturePet/NOTES.md) |
| Screenshot Redactor | [Apps/ScreenshotRedactor](Apps/ScreenshotRedactor) | v1 in development; see [NOTES.md](Apps/ScreenshotRedactor/NOTES.md) |

## Getting started

Requires Xcode 26 or later. Nothing else to install: the first `make` downloads the pinned XcodeGen into `.tools/`.

```sh
make open    # generate the Xcode projects and open MiniApps.xcworkspace
make build   # generate and build every app
make test    # run the unit tests of every app that has them
make test-report  # Posture Pet: run tests and open an HTML report with simulated-AirPods frames
make clean   # delete build output and generated projects
```

The `.xcodeproj` files are generated from each app's `project.yml` and aren't committed. After changing a `project.yml`, run `make` again.

## Layout

```
Apps/<App>/                 one folder per app
  project.yml               the app's XcodeGen spec (name, version, overrides)
  <App>.entitlements        App Sandbox and any other entitlements
  Sources/  Resources/  Tests/
Packages/MenuBarKit/        Swift package shared by every app
Configs/MenuBarApp.yml      settings and target template every app includes
MiniApps.xcworkspace        opens all the apps together
Scripts/xcodegen            runs the pinned XcodeGen
```

## Before the first App Store upload

In [Configs/MenuBarApp.yml](Configs/MenuBarApp.yml), set `DEVELOPMENT_TEAM` to your Apple Developer Team ID and `BUNDLE_ID_PREFIX` to your own reverse-DNS prefix. Bundle IDs can't be changed after an app is registered in App Store Connect.

Each app also needs its icon images in `Resources/Assets.xcassets/AppIcon.appiconset`.

## Adding an app

1. Copy `Apps/PosturePet` to `Apps/<Name>`, rename `PosturePet.entitlements` to `<Name>.entitlements`, and replace the sources.
2. In `Apps/<Name>/project.yml`, change the project and target names, `PRODUCT_NAME`, `PRODUCT_MODULE_NAME` and the category.
3. Add `Apps/<Name>/<Name>.xcodeproj` to `MiniApps.xcworkspace/contents.xcworkspacedata`.
4. Run `make build`.
