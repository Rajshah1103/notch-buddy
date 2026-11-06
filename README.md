# Notch Buddy

A macOS app that turns the notch into a live hub with a small buddy that tells you what needs you. (The app and its
code are still called Notch Hub internally.)

Turns the Mac notch into a live hub: hover to see your apps and what is inside them (windows, browser
tabs), jump to any of them in one click, or press **Control-Option-Space** and type to find anything open.
While Claude Code is working, the collapsed notch widens into a live activity.
Product plan: `docs/prd-and-execution-plan.md`.

## Connect any app

Anything that can run a command can show a bubble on the notch. The app listens on a Unix socket that only your
user can open (no network port), and `NotchHub emit` talks to it:

    NotchHub emit --source gitlab --headline "Pipeline failed" --detail "main" --url https://example.com --tint "#FC6D26"

`--source` and `--headline` are required; `--detail`, `--url` (http or https), `--tint`, `--mood`, `--symbol`, `--ttl`,
`--group` and `--id` are optional. `NotchHub agent --harness codex --session s1 --state working` shows that tool's activity in the notch. Connectors
(a folder with a script) and recipes for other AI tools are in `docs/extending.md`.

## Install and run

Homebrew (Apple silicon, macOS 14 or later):

    brew tap rajshah1103/tap
    brew trust rajshah1103/tap       (recent Homebrew asks you to trust a third-party tap once)
    brew install --cask notch-buddy

The app is not notarized yet; the cask clears the download quarantine for you. To build from source instead:

    ./scripts/install.sh        builds, installs to /Applications/Notch Hub.app, and opens it

(`./scripts/bundle.sh` just builds `build/Notch Hub.app`.) The first launch opens a welcome window with an
Allow button for each permission; pressing one is what makes the app appear in System Settings'
Privacy & Security lists. If it still isn't listed, or is listed but ignored after a rebuild, the
permissions help in the welcome and Settings has "Show in Finder" and "Reset permissions".

Grant these once from the menu bar item or the hint at the bottom of the notch:
Accessibility (jump to windows), Automation (read browser tabs), Screen Recording (live previews and
Chrome profile names). Requires macOS 14+. Local builds are ad-hoc signed, so macOS may ask for the permissions again after a rebuild;
a Developer ID signature (see Packaging) makes them stick.

## Keeping permissions across rebuilds

macOS ties permissions to the app's code signature. An ad-hoc signature changes with every build, so
permissions are forgotten. `scripts/bundle.sh` signs with a local certificate named "Notch Hub Local"
when one exists in your login keychain (the build then has the same identity every time). To create it:
make a self-signed certificate with the Code Signing extended key usage, import it, and trust it for code
signing (`security add-trusted-cert -r trustRoot -p codeSign ...`). With a Developer ID, set
`DEVELOPER_ID` instead.

## Packaging

    ./scripts/dmg.sh                         build/NotchHub.dmg, unsigned (Gatekeeper will warn downloaders)
    DEVELOPER_ID="Developer ID Application: Name (TEAMID)" ./scripts/dmg.sh
                                             signed with the hardened runtime
    ... NOTARY_PROFILE=name ./scripts/dmg.sh signed, notarized and stapled (profile from
                                             `xcrun notarytool store-credentials`)

## Using it

- **Hover the notch**: it opens at once when you move to it at a normal pace, and waits for you to stop if you
  swoop in fast (so sweeping past it to a menu bar icon does nothing). The app row shows your running apps, most recent first. Hover an app to list its
  windows (Chrome: its tabs, grouped by window and profile). Click an app to jump to it.
- **Control-Option-Space**, or the Search button: type to filter windows, tabs and apps. Up/Down choose,
  Return jumps, Esc closes. Type a web address, or any words, and an "Open in Chrome" row appears (first
  for an address, last for words); its right-hand pane lists your Chrome profiles, so you click or use ← →
  to pick which one the new tab opens in. Command-Return always searches the web, even when something
  open matches. Chromium browsers only (Chrome, Brave, Edge); the search engine is a setting.
- **It learns.** Results you pick often rise: choose a result for what you typed and it ranks higher next time
  you type the same (or a longer or shorter version of it); things you open from the app row count too, and
  old habits fade over a few weeks. It is all local, can be turned off, and can be wiped, in Settings.
- **Close things.** Hover a tab or window and press its ✕, or select it in search and press ⌘W. A closed tab
  disappears at once and the real list is read back a moment later, so a close that did not happen
  (an app asked to save) reappears. Windows can only be closed when they are on the current Space.
- **Hide apps** you never want in the notch (a VPN client, System Settings): right-click one in the row.
  Settings lists what is hidden and lets you bring it back.
- **Chips** (top left of the open notch): Claude Code sessions and tokens used today; GitHub review
  requests and the check state of your pull requests (connect with a token, or it uses your `gh` login).
- **Jenkins**: turn it on in Settings, add the address, username and API token, and press Test
  connection. Running builds show a progress bar; a running build also shows as a ring beside the
  collapsed notch when Claude is idle. On a VPN, connect it yourself: Notch Hub shows "offline" and
  recovers on its own.
- **Calendar**: turn on "Show next meeting" in Settings, then allow Calendar access from the panel. It reads
  the events already in the Calendar app (Google, iCloud, Exchange) and offers Join for Meet, Zoom, Teams and
  Webex links. Five minutes before a meeting the collapsed notch shows a calendar glyph and a countdown.
- **Settings** (menu bar icon): hover delay, search shortcut, integrations, permissions.

## Layout

- `Sources/WindowEngine`: Spaces, windows, browser tabs, browser profiles, grouping, search. The only place private macOS
  APIs live.
- `Sources/ClaudeUsage`: live Claude Code activity and token counts from its local transcripts.
- `Sources/GitHubKit`: pull requests and check state from GitHub's GraphQL API, token handling.
- `Sources/JenkinsKit`: job state and live progress from Jenkins' JSON API, offline backoff.
- `Sources/CalendarKit`: meetings, join-link detection, next-meeting logic and the EventKit monitor.
- `Sources/NotchCore`: notch panel, outline animation, hover and keyboard focus. Knows nothing about windows.
- `Sources/NotchHub`: the app, wires the modules together.

## Debug tools

    NotchHub --dump                          what the window engine sees
    NotchHub --tabs                          browser windows and tabs the scripting bridge can read
    NotchHub --claude                        Claude Code activity (counts only)
    NotchHub --github                        pull request counts from GitHub (counts only)
    NotchHub --focus "App"                   jump to an app and report what came to the front
    NotchHub --buddy-sheet out.png            every buddy mood, 1x and 3x
    NotchHub --idle-sheet out.png             every idle antic across the ears, at six moments
    NotchHub --snapshot out.png --demo --moment gmail|build-ok|build-fail|review|checks-bad|meeting|claude-done|claude-approve
    NOTCHHUB_DEMO_MOMENT=<same names> NotchHub   shows an invented bubble in the real window 2.5 s after launch
    NotchHub --snapshot out.png --demo [--app "Google Chrome"] [--light] [--search dep] [--claude-panel] [--github-panel] [--github-connect] [--calendar-panel] [--live] [--live-meeting]
                                             render the UI offscreen with invented data
    NotchHub --window settings|welcome out.png [--light]
    NotchHub --diagnostics                   the text "Copy diagnostics" in Settings puts on the clipboard
    NOTCHHUB_PERF=1 NotchHub                 log main-thread stalls and slow background reads

Tests use Swift Testing and need full Xcode to run (`swift test`).

### Launch film

`scripts/film.sh <work> <audio> <out> [binary]` renders the X videos offscreen from invented data (no screen recording, no real windows or accounts): `--film-still <name> out.png` draws the real views on a transparent background, `--film-frames <stills> <out> <scene|all> <16x9|1x1>` composes every frame as a pure function of time, and ffmpeg assembles the clips and the hero cut. Narration mp3s per scene go in `<audio>`.
