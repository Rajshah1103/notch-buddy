# Notch Hub (working name)

Turns the Mac notch into a live hub: hover to see your apps and what is inside them (windows, browser
tabs), jump to any of them in one click, or press **Control-Option-Space** and type to find anything open.
While Claude Code is working, the collapsed notch widens into a live activity.
Product plan: `docs/prd-and-execution-plan.md`.

## Install and run

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
  Return jumps, Esc closes.
- **Chips** (top left of the open notch): Claude Code sessions and tokens used today; GitHub review
  requests and the check state of your pull requests (connect with a token, or it uses your `gh` login).
- **Jenkins**: turn it on in Settings, add the address, username and API token, and press Test
  connection. Running builds show a progress bar; a running build also shows as a ring beside the
  collapsed notch when Claude is idle. On a VPN, connect it yourself: Notch Hub shows "offline" and
  recovers on its own.
- **Settings** (menu bar icon): hover delay, search shortcut, integrations, permissions.

## Layout

- `Sources/WindowEngine`: Spaces, windows, browser tabs, grouping, search. The only place private macOS
  APIs live.
- `Sources/ClaudeUsage`: live Claude Code activity and token counts from its local transcripts.
- `Sources/GitHubKit`: pull requests and check state from GitHub's GraphQL API, token handling.
- `Sources/JenkinsKit`: job state and live progress from Jenkins' JSON API, offline backoff.
- `Sources/NotchCore`: notch panel, outline animation, hover and keyboard focus. Knows nothing about windows.
- `Sources/NotchHub`: the app, wires the modules together.

## Debug tools

    NotchHub --dump                          what the window engine sees
    NotchHub --tabs                          browser windows and tabs the scripting bridge can read
    NotchHub --claude                        Claude Code activity (counts only)
    NotchHub --github                        pull request counts from GitHub (counts only)
    NotchHub --focus "App"                   jump to an app and report what came to the front
    NotchHub --snapshot out.png --demo [--app "Google Chrome"] [--light] [--search dep] [--claude-panel] [--github-panel] [--github-connect] [--live]
                                             render the UI offscreen with invented data
    NotchHub --window settings|welcome out.png [--light]
    NOTCHHUB_PERF=1 NotchHub                 log main-thread stalls and slow background reads

Tests use Swift Testing and need full Xcode to run (`swift test`).
