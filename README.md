# Notch Hub (working name)

Turns the Mac notch into a live hub: hover to see every Space and window, jump to any of them in one click.
Product plan: `docs/prd-and-execution-plan.md`.

## Run

    ./scripts/bundle.sh && open build/NotchHub.app

Grant Accessibility (jump to windows) and Screen Recording (window titles) from the menu bar item.
`.build/debug/NotchHub --dump` prints what the window engine sees.

## Layout

- `Sources/WindowEngine`: Spaces, windows, focus. The only place private macOS APIs live.
- `Sources/NotchCore`: notch panel, geometry, hover. Knows nothing about windows.
- `Sources/NotchHub`: the app, wires the two together.

Tests use Swift Testing and need full Xcode to run (`swift test`).
