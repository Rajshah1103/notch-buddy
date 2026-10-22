# Notch Hub (working name)

Turns the Mac notch into a live hub: hover to see your apps and what is inside them (windows, browser
tabs), jump to any of them in one click, or press **Control-Option-Space** and type to find anything open.
While Claude Code is working, the collapsed notch widens into a live activity.
Product plan: `docs/prd-and-execution-plan.md`.

## Run

    ./scripts/bundle.sh && open build/NotchHub.app

Grant these once from the menu bar item or the hint at the bottom of the notch:
Accessibility (jump to windows), Automation (read browser tabs), Screen Recording (live previews and
Chrome profile names). Requires macOS 14+. The build is ad-hoc signed, so macOS asks again after a rebuild.

## Using it

- **Hover the notch**: the app row shows your running apps, most recent first. Hover an app to list its
  windows (Chrome: its tabs, grouped by window and profile). Click an app to jump to it.
- **Control-Option-Space**, or the Search button: type to filter windows, tabs and apps. Up/Down choose,
  Return jumps, Esc closes.
- **Claude chip** (top left of the open notch): Claude Code sessions and tokens used today.

## Layout

- `Sources/WindowEngine`: Spaces, windows, browser tabs, grouping, search. The only place private macOS
  APIs live.
- `Sources/ClaudeUsage`: live Claude Code activity and token counts from its local transcripts.
- `Sources/NotchCore`: notch panel, outline animation, hover and keyboard focus. Knows nothing about windows.
- `Sources/NotchHub`: the app, wires the modules together.

## Debug tools

    NotchHub --dump                          what the window engine sees
    NotchHub --tabs                          browser windows and tabs the scripting bridge can read
    NotchHub --claude                        Claude Code activity (counts only)
    NotchHub --focus "App"                   jump to an app and report what came to the front
    NotchHub --snapshot out.png --demo [--app "Google Chrome"] [--light] [--search dep] [--claude-panel] [--live]
                                             render the UI offscreen with invented data
    NOTCHHUB_PERF=1 NotchHub                 log main-thread stalls and slow background reads

Tests use Swift Testing and need full Xcode to run (`swift test`).
