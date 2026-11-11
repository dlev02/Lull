# Security

Lull runs without the app sandbox, uses private macOS interfaces, updates itself and accepts commands from a local socket and from `lull://` links. A problem is security-sensitive if it lets an unsigned or tampered update install, lets another user account or another machine send Lull commands, makes a command or link do more than change Lull's own state, or exposes what is on screen.

## Reporting a vulnerability

Use [Report a vulnerability](https://github.com/dlev02/Lull/security/advisories/new) to share details privately with the maintainer.

If that page is unavailable, open a public issue asking for a private reporting channel, without including vulnerability details or sensitive attachments. Do not post exploit steps or private data in public issues.

A useful report includes the Lull version or commit, the macOS version, what you expected, what happened and a minimal way to reproduce it. `lull diagnostics` prints most of this; it also names apps you have used, so remove anything you would rather not share.

## Scope and fixes

Security fixes target the current source on `main` and the latest published release. There is no commitment to maintain older releases. Please allow time to investigate and coordinate a fix before public disclosure; this small project cannot promise a response deadline.

See [PRIVACY.md](PRIVACY.md) for what Lull reads, stores and sends.
