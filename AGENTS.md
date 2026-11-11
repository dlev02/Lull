# Lull

A macOS 26+ menu bar app (no Dock icon) that blurs everything on screen except the focused window.
Swift 6, AppKit with a SwiftUI panel; Sparkle 2 is the only dependency. GPL-3.0.
The update check to GitHub is the only network use, and normal use needs no permissions ([PRIVACY.md](PRIVACY.md)).

## Layout

- `App/Engine/`: `FocusEngine` picks the focused window and slots one `OverlayPanel` per display beneath it. `SystemBlur` and `WindowEvents` hold the private interfaces, `WindowSnapshot` reads the window list, `LullSettings` holds every setting.
- `App/Control/`: the ways in. `CommandRouter` is the command layer; `CommandSocket` and `CommandClient` carry the `lull` command; `HotKeys`, `PointerGestures`, `AutoHider`.
- `App/Panel/`: the SwiftUI panel and the menu bar icon. Views read `AppModel`.
- `App/Support/`: `Log`, `UpdateController`, login item, app facts.
- `App/main.swift`: one executable, two roles. With arguments it is the `lull` command; without, the app.

## One command layer

Every control surface (panel, shortcut, gesture, `lull` command, `lull://` link) changes state through `LullSettings` or an action on `FocusEngine`, and everything a person can do has a `CommandRouter` command. `LullSettings.onChange` in `AppDelegate` is the one place a change fans out from.

A new setting is complete when it appears in all of: `LullSettings.Key`, its property, `init`, `resetAll`, `CommandRouter.execute`, `status()`, the `usage` text, and the panel.

## Build

- Inside Bitrig: `bitrig build -destination 'generic/platform=macOS'`
- Otherwise: `xcodebuild -project Lull.xcodeproj -scheme Lull build`

## Verify on a running copy

There is no test target. A change is verified when the running build shows it.

1. Quit the copy that is running (`lull quit`). Only one runs at a time: a second launch exits as soon as the socket answers.
2. Open the built app.
3. Drive it with its own executable, `Lull.app/Contents/MacOS/Lull <command>`, or `lull` once the link is installed. Replies are JSON; the exit status is 1 on failure.

| Command | Shows |
| --- | --- |
| `status` | Every setting, `active`, the `standDown` reason, the focused window. |
| `windows` | The window order Lull sees, which windows are focus candidates, where the overlays sit. |
| `diagnostics` | `blurBackend` (`backdrop` or `material`), `overlays`, `evaluations`, `stageManager`, the recent log. |
| `log [lines]` | Recent log lines. Log through `Log` with a category so new code shows up here. |
| `tune scale\|radius\|grain\|fade <n>` | Undocumented look overrides, not saved. `tune reset` clears them. |

Done means checked with Stage Manager on and again with it off: `status` and `windows` show the expected focus in both, and the screen looks right in both. Changes to focus-following also get a keyboard pass (Command-W, Command-Backtick, a Space change), since those arrive by a different path from clicks.

A copy run from outside an Applications folder never starts the updater or registers the login item.

## Performance

- Idle means idle. Work happens on a focus change, a setting change or a command. `evaluations` in `diagnostics` stays flat while no window opens, closes or changes order.
- The one repeating timer is the modifier check in `PointerGestures`, alive only during a peek. Pointer monitors exist only while a gesture is on.
- The window server does the blurring. Lull captures no screen content and draws no frames; build effects from layer properties and Core Animation.
- The blur samples at quarter resolution (`scale` 0.25, or 0.5 below a radius of 6). Measure with `lull tune scale` before changing it.

## Private interfaces

Private API lives only in `SystemBlur` (the adjustable backdrop blur) and `WindowEvents` (window-server notifications). Look every class and symbol up at run time (`NSClassFromString`, `dlsym`, `responds(to:)`) and keep the public fallback working: `NSVisualEffectView` for the blur, click monitoring for window events. `blurBackend` reports which blur is live.

## Permissions

Normal use needs none, which rules the design: the window list is read without titles, shortcuts are Carbon hot keys, and global monitors watch the mouse only. Auto-hide's Automation prompt is the single exception and appears only when it is turned on. Raise any feature that would need Accessibility or Screen Recording before building it.

## Code style

- 2-space indent. One main type per file, named after it, with only its small helpers beside it. No SwiftUI previews.
- The target defaults to `MainActor` isolation. C callbacks return with `DispatchQueue.main.async { MainActor.assumeIsolated { … } }`.
- British spelling in comments and interface copy (colour, centre, recognise).
- Panel copy is short labels; let the layout explain.

## Commits and releases

- One user-facing change per commit. The title is plain English a user would understand, such as "Add reveal effects, auto-hide and peek at corners".
- Commits, pull requests and files carry the author's name only, with no tool, assistant or AI attribution.
- Releases follow `docs/RELEASING.md`. The top section of [CHANGELOG.md](CHANGELOG.md) becomes the release notes shown in the update window, so write it for people who use the app.
- When behaviour, network use or permissions change, update [README.md](README.md) and [PRIVACY.md](PRIVACY.md) in the same commit.
