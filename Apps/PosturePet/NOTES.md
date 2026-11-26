# Posture Pet — notes

## Status (2026-11-26)

v1 is feature-complete in code, apart from the AirPods device check below:

- Mochi in the menu bar and on the desktop.
- Posture mirroring and nudges.
- Break timer with wind-down.
- Neck Arcade: three games.
- Today and history.
- Pro purchase.
- Onboarding.

`make build` is clean and `make test` passes (133 Posture Pet test cases).

**Behavior:** Mochi has 58 short acts (`Pet/PetAct.swift`). `Pet/BehaviorDirector.swift` picks one per situation by weighted random choice: it never repeats any of the last 3, respects cooldowns, and keeps to face-only acts under Reduce Motion. Idle acts play every 12–35 s while Mochi is visible. Event reactions go through `PetEngine.react(to:)`. Lines rotate from `Pet/PetLines.swift`. `-RenderSnapshots` draws a contact sheet of every act (`Debug/acts-light.png`).

**Still open: the AirPods checklist.** It decides whether head tracking works for a menu bar app in the background. Until it's done, the sign conventions in `MotionAxes` (Sources/Sensing/HeadSample.swift) are assumed, not confirmed.

## Device findings

Checked on the development Mac (macOS 27.2.1, M2 Pro, sandboxed debug build):

| Signal | Result in the sandbox | Decision |
| --- | --- | --- |
| Headphone motion available (`isDeviceMotionAvailable`) | true | — |
| `NSMotionUsageDescription` in the built Info.plist | present | Keep `INFOPLIST_KEY_NSMotionUsageDescription` |
| Entitlements | `app-sandbox` only | No extra entitlement so far |
| Per-process mic input (`kAudioHardwarePropertyProcessObjectList`) | process list visible | **Main call signal** |
| Camera in use (CoreMediaIO) | 0 devices visible in the sandbox; 1 outside it | **Dropped for v1**: needs the camera entitlement. Revisit in 1.1 with the camera fallback |
| Display mirroring (`CGDisplayIsInMirrorSet`) | true, because this Mac mirrors its built-in display to a monitor all day | **Dropped**: everyday mirroring would keep Mochi quiet forever. Presentations are caught by the full-screen check |
| Full-screen front app (window bounds; no Screen Recording permission) | readable | Keep |
| Idle time (`CGEventSource`) | readable, no prompt | Keep |

**Motion access is only ever requested in onboarding's AirPods step and in Re-centre.** Starting motion is what shows the system prompt, and macOS ends a process that touches motion data without a usage string it can attribute. A debug run caught a game starting motion with no prompt context, so games now use the head only when access was already granted.

## AirPods checklist (needs your AirPods)

Run the frozen copy in `.build/Spike`, so rebuilding doesn't swap the app out from under the test:

```sh
open ".build/Spike/Posture Pet.app"
```

A leaf icon appears in the menu bar. Click it to open the Sensor Lab.

1. **Start.** Put your AirPods in, connected to this Mac. Click **Start recording** and allow motion access when macOS asks. "Stream" should become `live`, at about 25 Hz or more.
2. **Sign check.** Click **Begin**, then **Capture** three times as prompted (look at the screen, look down, tilt right).
3. **Background, 30 min.** Switch to another app and work normally. During that time:
   - watch about 5 minutes of full-screen video;
   - lock the screen (Control-Command-Q) for 2 minutes.

   Come back and look at **Samples per minute**: blue bars should be as tall as green ones.
4. **Window closed, 10 min.** Close the Sensor Lab window (recording continues), wait, then reopen it from the menu bar.
5. **Call, 2 min.** Make a FaceTime or Zoom call using the AirPods mic. Check that **Mic processes** lists the call app, and that motion keeps flowing.
6. **Disruptions.**
   - Take one AirPod out for 1 minute, then put it back.
   - Put both in the case for 1 minute, then back in.
   - Play music with Spatial Audio on for 1 minute.
   - If you have an iPhone nearby, let the AirPods switch to it, then switch back.
7. **Battery.** Note the AirPods battery level at the start and after 2 hours of recording.
8. **Report.** Click **Copy report** and paste it into the chat, along with the battery levels.

If step 3 shows short blue bars, run 10 more minutes with **Hold activity assertion** on, then copy the report again.

## Testing without AirPods

**Simulated AirPods** (debug builds only) feed head angles into `MotionHub` exactly where real AirPods samples arrive. Everything downstream is the real code: posture, mood, Mochi's pose, stats, nudges, games and calibration. `MotionHub(streamingEnabled: false)` guarantees that tests and snapshot runs never start real motion.

- **`make test`**: unit tests by feature.
  - The engine end to end with simulated AirPods (`EngineTests`).
  - Arcade sessions with keyboard and head (`GameSessionTests`).
  - Rules: posture, breaks, nudges, mood and growth, games, head input.
  - Appearance; storage, settings and quiet; Pro, through StoreKitTest and `PosturePet.storekit`.

  Each test gets its own temporary data folder and settings (`Tests/TestRig.swift`).
- **`make test-report`**: runs the tests, renders Mochi from the real engine fed simulated AirPods, and opens `.build/TestReport/index.html`. The page shows every test grouped by feature (in Korean), the simulated frames with the engine's readings, the latest in-app demo result, and screen snapshots.
- **In the app**: right-click Mochi › **Debug** › **AirPods Simulation Demo…**. It plays a 13-step session while a checklist window shows each step passing:
  1. Connect AirPods.
  2. Save the sitting position.
  3. Sit tall.
  4. Tilt right.
  5. Tilt left.
  6. Slump slowly.
  7. Hold the slump for 2 minutes (shown at 12× speed).
  8. Get the posture bubble.
  9. Recover.
  10. Get the break invite.
  11. Steer Leaf Glide with your head.
  12. See the results.
  13. Take the AirPods out.

  Your real data is restored afterwards.

  To run it unattended in a separate copy without touching real data:

  ```sh
  open -n "<app>" --args -EphemeralState YES -AirPodsDemo YES
  ```

  It writes `Debug/AirPodsDemo.txt`.

## Running and debugging

- `make build`, then run `.build/DerivedData/Build/Products/Debug/Posture Pet.app`, or open the workspace (`make open`) and run the PosturePet scheme. Xcode's Run action uses `PosturePet.storekit` for local purchase testing.
- In debug builds, right-click Mochi and choose **Debug**:
  - Sensor Lab;
  - a posture simulator (fake AirPods with pitch and roll sliders);
  - Time ×60, to walk through a day in minutes;
  - add sitting time, take a break, add treats;
  - show any nudge;
  - set the growth stage;
  - toggle Pro;
  - show onboarding.
- Launch arguments (debug builds):

  | Argument | Does |
  | --- | --- |
  | `-RenderSnapshots YES` | Renders every mood, growth stage, menu bar icon and SwiftUI screen to PNGs in the container's `Application Support/Debug` folder, then quits. Uses throwaway state. |
  | `-RenderAppIcon YES` | Renders the AppIcon sizes from Mochi's geometry into `Debug/AppIcon`. |
  | `-SmokeTest YES` | Drives the live app (panel and its tabs, paywall, bubble, a game round), logs each step to `Debug/SmokeTest.txt`, then quits. |
  | `-OpenPanel home`, `-ShowNudge breakInvite`, `-Play leafGlide` | Opens that surface at launch. |

- The snapshot renderer captures layers, so outlined pill buttons show faint vertical lines at their ends. That's a capture artifact; SwiftUI's own renderer draws them cleanly.

## App Review notes (draft for App Store Connect)

> Posture Pet is a menu bar companion. Click the creature in the menu bar to open its panel; right-click for the menu.
>
> **Head tracking uses AirPods.** It needs AirPods Pro, AirPods (3rd generation or later), AirPods Max or supported Beats. Motion data is processed on the Mac and never stored or transmitted, and the app has no account and no network features beyond StoreKit.
>
> **Without AirPods**, everything else works:
> - the break timer and its reminders;
> - the Today summary;
> - all three Neck Arcade games, played with the arrow keys or Space (Arcade tab, or "Play" on Home).
>
> To see a break reminder right away, open Settings in the panel and set "Remind me every" to 30 minutes.
>
> **Pro** is a one-time non-consumable ("posturepet.pro"). It unlocks Puddle Hop, Star Float and history beyond 7 days. Restore is in the paywall and in Settings.
>
> The app makes no medical claims; it encourages regular breaks and gentle movement.

## Before submitting

- Set `DEVELOPMENT_TEAM` and `BUNDLE_ID_PREFIX` in `Configs/MenuBarApp.yml` (see the README).
- In App Store Connect, create the non-consumable `posturepet.pro` and choose its price. The local test file uses $4.99.
- Privacy nutrition label: **Data Not Collected**. `Resources/PrivacyInfo.xcprivacy` declares UserDefaults (CA92.1) and system boot time (35F9.1); there is no tracking.
- Keep marketing copy honest: Mochi "stays quiet when it can tell you're in a call or presenting". Screen sharing without a call or a full-screen app can't be detected.
- Screenshots: render with `-RenderSnapshots YES` as a starting point, or capture the real panel.
