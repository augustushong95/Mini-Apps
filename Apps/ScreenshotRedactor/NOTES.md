# Screenshot Redactor: notes

Screenshot Redactor is a menu bar app. You take a screenshot, and a second later a preview shows it with secrets, personal data and internal addresses covered by solid boxes. You can copy, drag or save the clean version. Everything runs on the Mac: the app has no network entitlement.

## Status (2026-11-26)

v1 is written, apart from the device checks below.

- **Detection** runs on device with Vision text recognition and face detection.
  - It finds provider tokens (AWS, GitHub, Slack, Stripe, OpenAI, Anthropic and 25 more), JWTs, private key blocks, credentials written after a keyword, and long random strings.
  - It also finds emails, phone numbers, card numbers (checked with Luhn), faces, IP addresses, internal hostnames, and Pro custom rules.
- **Ways in:**
  - watching the screenshot folder;
  - the app's own capture shortcut (⌥⇧⌘4: drag an area or click a window);
  - Open Image…, dropping a file on the panel, and Redact Clipboard Image.
- **Preview card:** Copy, drag, Save, Edit, Move original to Trash, and a pager for ⌘⇧3 on several displays.
- **Editor:** click a box to toggle it, drag to draw a new box, move and resize the boxes you drew, hold ⌥ to see under the boxes, a sidebar, undo and redo, and keyboard shortcuts.
- **Also built:** menu bar panel, Settings (5 tabs), onboarding, Pro and the 5-a-day free limit.

`make build` is clean with no warnings. `make test` runs 104 tests for this app, plus Posture Pet's.

**Shared code.** `StatusItemController`, `ClosureMenuItem`, `FloatingPanel`, `PanelController`, `PanelPlacement`, `ProStore` and `DebugFiles` now also live in MenuBarKit, made public, and this app uses those copies. Posture Pet still has its own identical types, which take precedence inside Posture Pet. Another session was working on Posture Pet, so its files weren't touched. To finish the move, delete Posture Pet's copies and add `productID:` to its `ProStore()` call.

## What the tests prove

- **Every secret is fully covered.** Planted secrets on generated screenshots (terminal, code editor, chat, web form, log) are drawn in light and dark mode, in SF Mono, Menlo and SF Pro, at 1× and 2×. Every pixel of each secret's glyphs must end up inside a box, after a real Vision scan.
- **No false positives.** A clean screenshot (Swift code, git SHAs, dates, versions, prices, paths) produces zero boxes.
- **Large images are handled.** A 5K screenshot, a tall scrolling capture, and long lines crossing tile seams are all fully covered. The 5K scan takes ≤ 1.5 s.
- **The output is clean.** The copied or exported PNG has only image, colour and resolution chunks: no EXIF, text or timestamp chunks. Pixels outside the boxes are bit-identical to the original.

## Findings that shaped the code

- **Vision has a size limit.** It reads nothing once text is smaller than about 1/120 of the image's longest side. 13 pt text at 1× is lost beyond about 1,920 px, and 12 pt text at 2× is lost at 5K. Downscaling keeps that ratio, so it doesn't help. Large images are therefore read in overlapping tiles (1,280 px at 1×, 2,048 px at 2×, chosen from the image's DPI). Duplicate or broken readings are merged (`LineStitcher`).
- **Vision's boxes cover whole words.** `boundingBox(for:)` snaps every range to whole words, so the box for `AKIA…` inside `KEY_ID=AKIA…` would cover the whole word. `TextExtent` estimates the part inside the word, erring towards covering more. The ink check (`InkRefiner`) then grows each box until no glyph is cut, and padding stops at the next letter.
- **URL resource values are cached.** `URL` caches resource values, so file identity and size are always read fresh (`freshResourceValues`). Otherwise a replaced original could be moved to the Trash.
- **The original is not deleted.** Only "Move original to Trash" is offered, and only if the file ID and modification date still match.

## Device checklist (needs you)

Run a copy, so rebuilding doesn't swap the app out from under you:

```sh
make build
mkdir -p .build/Dev && rm -rf ".build/Dev/Screenshot Redactor.app"
cp -R ".build/DerivedData/Build/Products/Debug/Screenshot Redactor.app" .build/Dev/
open ".build/Dev/Screenshot Redactor.app"
```

1. **Onboarding.** Choose Desktop in the open panel. The panel should then show "Watching Desktop".
2. **⌘⇧4 with the floating thumbnail on.** The card appears about 5 s later, top-right, on the display you captured.
3. **⌘⇧4 with the thumbnail off** (⇧⌘5 › Options). The card appears within about a second.
4. **No stolen typing.** Take a screenshot, then immediately type in Slack. No keystrokes go to the card. Clicking the card gives it focus, and ⌘C then copies.
5. **Paste into each app.** Paste into the Slack app, Jira and Gmail in Safari and in Chrome, and into Mail. The image should be redacted and the right size.
6. **Drag into apps.** Drag the card's thumbnail into Slack, into Chrome (Jira's attachment area) and into Finder.
7. **⌘⇧3 with two displays.** You should see one card with a "1 of 2" pager, and one redaction counted.
8. **Clipboard screenshot.** Take one with ⌃⇧⌘4, then use Redact Clipboard Image.
9. **Capture shortcut.** Press ⌥⇧⌘4:
   - The explainer appears, then macOS's prompt. Allow it, then Quit & Reopen if asked.
   - Try it again: drag an area, then click a window, then press Esc.
   - Deny permission once and check that the help alert opens System Settings.
10. **Full-screen app.** Take a screenshot over a full-screen app; the card appears over it.
11. **Second display.** Use a display with a different scale, and capture on each.
12. **Move to Trash.** Turn on "Move the original to the Trash", copy, and check that the original is in the Trash.
13. **Sleep.** Put the Mac to sleep, wake it, and take a screenshot: it is still watched.
14. **Your real screenshots.** Copy a few into the debug inbox (path below). Run `-RedactInbox YES` and check `Debug/Outbox`.
15. **TestFlight purchase.** Buy Pro with no network entitlement: the purchase and the restore both work.

## Running and debugging

- In debug builds, right-click the menu bar icon and choose **Debug** to:
  - toggle Pro;
  - reset or use up today's count;
  - open the sample;
  - show onboarding;
  - reveal the debug folder.
- **Launch arguments** (debug builds), run as `".build/Dev/Screenshot Redactor.app/Contents/MacOS/Screenshot Redactor" <args>`:

  | Argument | Does |
  | --- | --- |
  | `-RenderSnapshots YES` | Renders every card state, the editor, panel, settings, onboarding and icons to `Debug/Snapshots`, then quits. |
  | `-RenderAppIcon YES` | Writes the AppIcon PNGs to `Debug/AppIcon`. Copy them into `Resources/Assets.xcassets/AppIcon.appiconset`. |
  | `-SmokeTest YES` | Drives the live app: sample → scan → copy (to a private pasteboard) → PNG checks → editor → drag file. Logs to `Debug/SmokeTest.txt`. |
  | `-RedactInbox YES` | Scans the images in `Debug/Inbox`. Writes redacted copies and a findings list (labels and boxes, never text) to `Debug/Outbox`. |
  | `-OpenSample YES` | Opens the sample in the editor. |
  | `-EphemeralState YES` | Uses throwaway settings. Use it with any of the above. |

- **Debug folder:** `~/Library/Containers/com.example.miniapps.ScreenshotRedactor/Data/Library/Application Support/Debug`.
- **Entitlements.** Debug builds made by `make test` carry Xcode's test-host exceptions (read `/`, test manager lookups). Check the shipped entitlements on a Release or Archive build:

  ```sh
  codesign -d --entitlements - "Screenshot Redactor.app"
  ```

  The result should be only `app-sandbox`, `files.user-selected.read-write` and `files.bookmarks.app-scope`.

## App Review notes (draft for App Store Connect)

> Screenshot Redactor is a menu bar app. Click the icon in the menu bar to open its panel; right-click for the menu.
>
> **To try it without any setup:** choose "Try It with a Sample" at the end of onboarding, or press ⌥⇧⌘4 / take a screenshot after allowing the Desktop folder. The sample is a made-up screenshot with fake keys and contact details; a preview shows them covered, and Edit lets you uncover or add boxes.
>
> **Permissions.** The Desktop (or another folder the user picks) is read only to find new screenshots, through the standard open panel and a security-scoped bookmark. Screen Recording is requested only when the user presses the app's own capture shortcut; folder watching works without it.
>
> **Privacy.** The app has no network entitlement. Text recognition and face detection use Apple's Vision framework on device. Screenshots are processed in memory; nothing is uploaded, logged or stored except settings.
>
> **Pro** is a one-time non-consumable ("screenshotredactor.pro"). It removes the 5-a-day free limit and unlocks custom rules. Restore is in Settings › Pro and in the Pro window.

## Before submitting

- Set `DEVELOPMENT_TEAM` and `BUNDLE_ID_PREFIX` in `Configs/MenuBarApp.yml` (see the README).
- In App Store Connect:
  - create the non-consumable `screenshotredactor.pro` and choose its price (the local test file uses $9.99);
  - set the privacy nutrition label to **Data Not Collected**. `Resources/PrivacyInfo.xcprivacy` declares UserDefaults (CA92.1), file timestamps in a user-chosen folder (3B52.1) and system boot time (35F9.1). There is no tracking.
- **Business licensing.** Apple Business Manager volume purchases don't include in-app purchases. A business edition needs a separate paid app or a custom app.
- **Keep the marketing copy honest:**
  - Detection is automatic but not perfect, and the preview is there to check it.
  - Faces are "best effort".
  - With the floating thumbnail on, a screenshot dragged straight from the thumbnail skips the app.
