# Contributing to Lull

Changes are welcome as pull requests: bug fixes, focused improvements and documentation. For a larger feature, open an issue describing the problem and the behaviour you propose before you start.

## Build

You need macOS 26 or later. Open the project in Bitrig, or build it from the command line:

```sh
xcodebuild -project Lull.xcodeproj -scheme Lull build
```

Sparkle, for updates, is the only dependency. [AGENTS.md](AGENTS.md) describes the layout of `App/` and the rules the code follows.

## Try a change

Only one copy of Lull runs at a time. Quit the installed copy with `lull quit` or from the menu bar, then open the app you built.

The running app answers the `lull` command, so you can check what it is doing without a debugger. If you have not installed the command, call the app's executable directly: `Lull.app/Contents/MacOS/Lull status`.

```sh
lull status        # settings, whether Lull is active, the focused window
lull windows       # the window order Lull sees, and where its overlays sit
lull diagnostics   # version, displays, which blur is in use, the recent log
```

There is no test target. Check a change by running it:

- Switch apps, switch windows with the keyboard, close windows and change Spaces.
- Repeat with Stage Manager on and with it off.
- Use a second display if you have one, in both multi-screen modes.

## Pull requests

Keep a change focused and leave unrelated work alone. Describe the result a user would see, what you checked and anything you could not check. Do not include signing keys, credentials or built app bundles.

Changes to these boundaries need discussion first:

- Lull needs no permissions for normal use.
- The update check is its only network connection.
- It does no work while nothing on screen changes, and it never captures the screen.
- Private macOS interfaces are looked up at run time and each has a public fallback.

## Licence

Lull is licensed under the [GNU General Public License, version 3](LICENSE). Contributions submitted for inclusion are under the same licence. Submit only work you have the right to contribute, and identify any third-party material and its licence.
