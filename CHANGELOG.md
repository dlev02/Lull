# Changelog

## 0.1.2 — 2026-11-10

- Clicking the menu bar icon while the panel is open now closes it, instead of opening it again.
- Buttons and shortcut keys in the panel no longer flash dark as the panel opens and closes.
- The "Made by" link goes to drewlevinson.me.

## 0.1.1 — 2026-11-10

A polish pass on the panel.

- Scrolling the panel is smooth. It used to stall whenever the pointer was between two cards.
- Sliders now snap to steps, with a tick at each, so a setting is easy to return to.
- Cards have more room, hairlines between rows and clearer icons, and buttons respond to the pointer.
- Clicking the space between cards closes the panel.

## 0.1.0 — 2026-11-10

The first version of Lull. It blurs everything on screen except the window you are working in.

### Focus

- Lull follows the window in front, whether you switch with the pointer or the keyboard.
- App-wide focus keeps every window of the app in front sharp.
- App groups keep chosen apps sharp together.
- Ignored apps make Lull stand down while they are in front. Finder is ignored to begin with.
- With more than one display, choose one focus across all of them or one per screen.
- Stage Manager's thumbnails stay sharp, unless you turn on Blur Stage Manager.

### Look

- Two modes: Ambient keeps the top of the screen clear and fades to full blur about halfway down; Deep blurs everything.
- Sliders for blur, tint and grain, with a tint colour of your choice.
- Monochrome drains the colour from everything that is blurred.
- Set how fast the blur arrives, and how: Fade, Focus or Pointer.

### Control

- A panel opens from the menu bar icon.
- Shake the pointer to turn Lull on or off. Hold Shift and shake to peek at everything.
- Peek at corners, if you turn it on, shows everything while the pointer rests in a screen corner.
- Four keyboard shortcuts: Control-Option-Command with F to toggle Lull, M to switch mode, E to ignore the app in front and C to open the panel. Each can be changed or removed.
- Auto-hide tucks away the Dock, the menu bar or both while Lull is focusing.
- The `lull` command and `lull://` links control everything from scripts. Install the command from Scripting Commands in the panel.

### Good to know

- Lull needs macOS 26 or later.
- It needs no permissions for normal use. Only Auto-hide asks for Automation, and only when you turn it on.
- Lull starts at login, checks for updates once a day and installs an update the next time it quits. Both can be turned off in the panel.
- There is no analytics, no crash reporting and no account.
