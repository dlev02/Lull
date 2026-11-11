# Privacy

Last updated: 10 November 2026

Lull has no accounts, advertising, analytics, crash reporting or remote logging. It collects nothing. The only network requests it makes are update checks and update downloads, both to GitHub. Nothing is sent to the developer.

## Update checks

Lull uses [Sparkle](https://sparkle-project.org), an open-source update framework, to keep itself current.

- **When:** once a day, in a copy installed in an Applications folder. A copy built from source and run from a build folder never checks.
- **What it requests:** one file, `appcast.xml`, from `raw.githubusercontent.com`. When that file lists a newer version, Lull downloads it from `github.com` and installs it the next time Lull quits. GitHub may redirect the download to `release-assets.githubusercontent.com`. If you use a firewall app, these are the hosts to allow.
- **What GitHub can see:** as with any web request, your IP address and the time, plus the app's name and version and Sparkle's version. GitHub handles this under [its privacy statement](https://docs.github.com/en/site-policy/privacy-policies/github-general-privacy-statement).
- **What is not sent:** your settings, the names of your apps or windows, anything on your screen, device identifiers, or a hardware or system profile.
- **How updates are checked:** the feed and every update are signed, and Lull verifies both against a key built into the app before installing anything.

To turn automatic checks off, open the panel, choose **More settings** and turn off **Automatic updates**. Lull then makes no network requests unless you click **Check Updates**.

## What stays on your Mac

- **Settings.** Sliders, modes, shortcuts, ignored apps and app groups are saved in the app's preferences on your Mac, along with the time of the last update check. They are not synced or uploaded.
- **The window list.** To follow focus, Lull reads the list of windows on screen: each window's number, the app that owns it, and its position and size. It does not read window titles or contents, and it never captures the screen. The blur is done by macOS.
- **Pointer and keyboard.** While a gesture is turned on, Lull watches pointer movement to recognise a shake or a screen corner. Positions are not saved or logged. Lull does not read what you type; macOS tells it only when one of its own shortcuts is pressed.
- **The log.** Lull keeps its most recent 600 log lines in memory and writes the same lines to the macOS system log. They record things like which app took focus, window numbers, commands that were run and errors. `lull diagnostics` prints the recent lines. The log is never sent anywhere.
- **The command socket.** The `lull` command talks to the running app through a local socket at `~/Library/Application Support/Lull/lull.sock`. Only your user account can open it, and it is not reachable from the network.

## The Automation permission

Lull needs no permissions for normal use. It does not ask for Accessibility or Screen Recording.

Auto-hide is the one exception. It hides the Dock or the menu bar while Lull is focusing, and macOS only allows that through System Events. The first time you turn Auto-hide on, macOS asks whether Lull may control System Events. Lull uses that permission only to read and change the two auto-hide settings, and it puts them back as they were when it stops focusing or quits. Auto-hide is off by default, so nothing is asked until you turn it on. You can withdraw the permission in System Settings under Privacy & Security > Automation.

## Reports you choose to share

**Ideas / Issues** in the panel opens a new GitHub issue in your browser, prefilled with the Lull version, the macOS version, your display sizes, whether Stage Manager is on and which blur is in use. Nothing is sent until you submit the issue yourself.

GitHub issues are public. The output of `lull diagnostics` includes the names of apps you have used, so read it before you paste it into a report.

## Removing Lull and its data

Quit Lull and move it from Applications to the Trash. To remove what it stored as well:

```sh
defaults delete io.github.dlev02.lull
rm -rf ~/Library/Application\ Support/Lull
```

If you installed the `lull` command, remove the link at `/usr/local/bin/lull`. Lull's entry under System Settings > General > Login Items goes when the app does.

## Contact

Questions about privacy go to [GitHub issues](https://github.com/dlev02/Lull/issues). For a security problem, follow [SECURITY.md](SECURITY.md) instead of posting details in a public issue.
