# PRD: Notch Hub (working name) — a live, useful Mac notch

Status: v0.4 — see "Build status" below · Date: 2026-10-22 · Owner: Raj

## 0. Spike result (throwaway, ~/notch-spike, not committed)
- Validated by Raj: notch overlay appears, hover expands with no delay/jank, Spaces and their windows are listed, and (per Raj) it is working.
- Not yet proven: click-to-jump for minimized Dock windows and menu-bar-only apps (Pritunl). I did NOT change the spike after Raj reported those; the planned fix (Accessibility raise/unminimize, proper Space switch) is built properly in milestone M2 instead. Space-switch was not tested by Raj.
- Spike UI is a plain placeholder, not the final design. Final UI gets designed with mockups first (M9).
- Machine note: only Command Line Tools are installed (no full Xcode). Needed for the product, see Prerequisites.
Items marked **[my call]** are my defaults, not Raj's decisions. Items marked **[open]** need Raj's answer.

## Build status (2026-10-23)
| Milestone | State |
|---|---|
| M1 Foundations (app shell, notch panel, permissions, menu bar) | Done |
| M2 WindowEngine (spaces, windows, focus, minimized, full-screen spaces) | Done |
| M3 Search + hotkey (Control-Option-Space, keyboard control) | Done |
| M4 Browser tabs | Done, via AppleScript (Chromium browsers) instead of the planned extension; Safari/Firefox not supported |
| M5 Integration framework + GitHub | Not started |
| M6 Jenkins | Not started |
| M7 Claude usage | Done: live ears while working, sessions panel, tokens today. Plan limits are not stored locally, so not shown |
| M8 Slack + Gmail (multi-account) | Not started |
| M9 Design polish | In progress: adaptive system material, light and dark |
| M10 Commercial (licensing, updates, notarization) | Not started; needs Developer ID |
| M11 Calls | Not started |

Findings that changed the design: macOS "Spaces" include one Space per full-screen app, so Desktops and
full-screen apps are labelled separately; Chrome reports hidden helper windows, so tabs come from its own
scripting; window titles are available without Screen Recording only for the current Desktop.

## 1. Context / Why
Raj runs ~10 apps across multiple Spaces plus VS Code and ~10 Chrome tabs. Finding anything means swiping between Spaces on the trackpad, hunting, swiping again, then switching Chrome tabs once inside Chrome. Notifications (Slack, Gmail) and CI/CD status live in separate places. The notch is dead screen real estate that is always visible and always at the top. Make it a live "dynamic island" for navigation, notifications and status, so Raj can reach anything in one hover + one click.

Prior art to study (not copy): NotchNook, Boring Notch, DynamicLake, AltTab, yabai. Differentiator **[my call]**: navigation-first (Spaces/windows/tabs jump + search), not a media-widget shelf.

## 2. Goals
1. Hover the notch → see all Spaces and their windows → one click jumps to the exact window. No trackpad swiping.
2. List Chrome tabs in the notch; click jumps to that tab without opening Chrome first.
3. Live notifications from Slack, Gmail (and later others) shown in the notch, with quick actions (open, reply, archive).
4. CI/CD pipeline progress shown live (GitHub Actions and Jenkins), e.g. running → pass/fail.
4a. GitHub pull requests: review requests, PR status/checks, comments, merge-ready, with quick actions (open, approve).
4b. Claude session usage: live view of Claude Code / Claude usage (session/limit consumption, active sessions) in the notch. Data source to be verified in spike **[open]**.
4c. **Modular by design:** every feature above is an integration module behind one plugin interface, so any new service (GitLab, Linear, Jira, CircleCI, etc.) can be added without touching the core.
4d. **Polished and sellable:** commercial-grade design, onboarding, settings, licensing, auto-update.
5. Type-to-go: type in the notch to (a) fuzzy-search open windows/tabs/Spaces and (b) open a URL/search in a new Chrome tab.
6. Calls: show active call state with timer and mute/hang-up where feasible.
7. Feels native and instant: hover-to-open under ~100 ms, no jank.

## 3. Non-goals
- Not a media/music widget, file shelf or calendar app (possible later).
- Not a full window manager (no tiling/resizing).
- Not reading other apps' notification database or screen-scraping.
- Not Mac App Store distribution in v1 (private APIs) **[my call]**; sell direct (own site + licensing, e.g. Paddle/Lemon Squeezy) **[my call]**.

## 4. Anti-goals (failure even if it "works")
- Slower than a trackpad swipe, or flaky hover that opens by accident.
- Noisy: duplicates every notification and trains Raj to ignore it.
- Breaks after each macOS update with no fallback.
- Heavy CPU/battery drain from constant polling.

## 5. Users
Primary: developers and power users with many windows/Spaces, code review, CI/CD and AI-tool usage to watch (Raj is user zero). **Decided by Raj: this is a polished product to sell.** Pricing/licensing model **[open]** (my guess: one-time purchase or small subscription, free trial).

## 6. Features (all in scope, phased)

### Phase 1 — Core navigation (MVP)
- Notch overlay window anchored to the notch; expands on hover, collapses on exit. Fallback pill at top-center for Macs without a notch/external displays.
- Spaces/windows view: Spaces as columns, apps/windows listed with icon + title; click focuses the window and switches Space.
- Search bar: type-to-filter windows/tabs; keyboard-only flow (global hotkey opens it).
- "New tab" command: typed text → URL or search → opens in a new Chrome tab.
- Chrome tabs list via companion Chrome extension (native messaging) **[my call]**; click activates tab + window.

### Phase 2 — Live info
- Notifications: Slack and Gmail via their own APIs/OAuth (Slack app/token, Gmail API), shown as notch banners + history list. Quick actions: open, mark read/archive, reply (Slack).
- **Multi-account:** connect multiple Slack workspaces and multiple Gmail accounts at once. Each account is its own integration instance with its own credentials in Keychain, a label/color badge on every notification so you can tell accounts apart, per-account mute/priority, and an optional unified inbox view vs per-account filter. The integration interface must support N instances per module, not one.
- CI/CD: GitHub Actions and Jenkins run status/progress for chosen repos/jobs; collapsed notch shows a progress ring, expands to job list; pass/fail alert.
- GitHub PRs: review requests, check status, new comments.
- Claude session usage: usage/limit meter and active sessions (source TBD in spike).
- Pinned/recent windows row.

### Platform: integration framework (built in Phase 1, used by everything else)
- One `Integration` plugin interface: declares auth, data polling/streaming, notch states (collapsed glyph, banner, expanded view) and actions.
- Core owns layout, priority/arbitration of what the notch shows, settings and credential storage; modules never draw outside their slots.
- Built-in integrations ship as modules using the same interface (proves it works); third-party/SDK loading is a later decision **[open]**.

### Phase 3 — Calls and extras
- Call detection (Meet/Zoom/FaceTime/Teams) with timer and mute/leave where controllable; otherwise indicator only.
- Other live activities (builds, downloads), more integrations.

## 7. Feasibility and constraints (to verify in spike)
| Area | Approach | Risk |
|---|---|---|
| Spaces/windows | Accessibility API + CoreGraphics; private CGS/SkyLight calls for Space mapping (as AltTab/yabai do) | Medium: undocumented, can break on macOS updates; needs Accessibility + Screen Recording permissions |
| Chrome tabs | Chrome extension + native messaging host | Low-Med: extension install step |
| Notifications | Slack/Gmail APIs (OAuth), not system DB | Medium: per-service setup, auth refresh |
| CI/CD | GitHub API polling/webhooks | Low |
| Calls | Heuristics (mic/camera in use, app state) + per-app scripting | High: control varies per app |
| Hover overlay | Borderless NSPanel above menu bar, tracking area on notch | Low-Med: multi-display, fullscreen apps |

## 8. Tech choices **[my call]**
Native macOS app: Swift + SwiftUI for UI, AppKit for the overlay panel and window control, Chrome extension in JS/TS. Direct-download distribution, notarized. Local-first; secrets in Keychain.

## 9. Success metrics
- Raj stops using trackpad Space-swipes for navigation within 2 weeks of use.
- Median jump-to-target ≤ 2 s (hover/hotkey → focused).
- Hover open latency < 100 ms; idle CPU < 2%.
- Notification actions handled from the notch without opening the app: majority.

## 10. Risks
- macOS updates breaking private Space APIs → keep that layer isolated, degrade to window-only mode.
- Scope: this is really 4–5 products. Mitigation: ship Phase 1 alone first, use it daily, then add layers.
- Permission fatigue (Accessibility, Screen Recording, Automation).
- Selling raises the bar: competitors (NotchNook etc.) are polished; need strong design, reliability, support, licensing, notarization, auto-update (Sparkle), privacy policy (tokens stay local in Keychain).
- Modularity risk: over-engineering the plugin API before real integrations exist. Mitigation: extract the interface from the first 2 integrations.

## 11. Open questions for Raj
1. Pricing model (one-time vs subscription) and free tier/trial?
2. Jenkins: **decided by Raj: behind VPN, and the user connects the VPN themselves on their own machine** (the app never manages or connects VPN). App talks to Jenkins directly from the user's Mac over that VPN (no cloud relay); store Jenkins URL + API token locally in Keychain; handle VPN-down gracefully (show "unreachable", not an error spam). GitHub Enterprise vs github.com only is still open.
2a. Claude usage: **decided by Raj: show in the notch when a Claude session/Claude is actively being used** (live activity: collapsed glyph while a session is running, expands to usage). Exact numbers (5-hour/weekly limits, tokens, cost) still open; source (local Claude Code session files/hooks) to be verified in spike.
2b. Should third parties eventually write modules (public SDK), or first-party only?
3. ~~Slack/Gmail: one or several?~~ Decided by Raj: **multiple** Slack workspaces and multiple Gmail accounts.
4. Is Chrome the only browser that matters?
5. Name.

## 12. Execution plan

### Prerequisites (Raj's side, before/around M1)
- Install full Xcode (only Command Line Tools now) for app bundle, signing, archive, SwiftUI previews.
- Apple Developer Program (~$99/yr) + Developer ID certificate, for notarized direct distribution.
- Pick a product name and buy a domain (needed for bundle ID, OAuth redirect URIs, privacy policy, site).
- Create the repo with Raj's personal git identity: personal email + signing key, `github.com-personal` alias, layered commits (never one giant commit), Conventional Commits subject-line only, no Co-Authored-By trailer (Raj's standing preferences override default attribution).

### Architecture [my call]
- Single Xcode project; SwiftPM local packages for isolation: `NotchCore` (panel, hover, arbitration, settings, Keychain), `WindowEngine` (Spaces/windows/AX, the only place private APIs live, behind a protocol with a degraded fallback), `Integrations/*` (one package per module: ChromeTabs, GitHub, Jenkins, Slack, Gmail, ClaudeUsage), and `App`.
- `Integration` protocol supports multiple instances per module (accounts), declares auth, refresh/stream, notch states (glyph, banner, expanded view) and actions. Designed by extracting from the first two real integrations (Chrome tabs + GitHub), not up front.
- Pure logic (fuzzy search, notification dedupe/priority arbitration, Jenkins/GitHub parsing, URL-vs-search detection) is unit-tested; OS-level behavior is verified manually (checklist below).

### Milestones (each ends with something Raj can use; go/no-go gates noted)
| # | Milestone | Done when |
|---|---|---|
| M1 | **Foundations**: new repo, app shell (menu-bar item, settings window, launch at login), productionized notch panel from the spike: hover intent (small delay/hysteresis), multi-display, fullscreen apps, non-notch fallback pill, permission onboarding (Accessibility, Screen Recording) | App launches at login, notch expands reliably on built-in + external display |
| M2 | **WindowEngine**: Spaces/windows listing, click-to-focus via AX raise, unminimize Dock windows, real Space switch, menu-bar-only apps (Pritunl) handled, window titles, app icons, pinned/recent row, graceful fallback if private APIs fail. **Gate:** if jump is unreliable on current macOS, fix before building anything on top | Terminal, minimized windows, Pritunl, fullscreen apps and other-Space windows all jump correctly; Raj uses it daily instead of swiping |
| M3 | **Search + hotkey**: global hotkey, fuzzy search across windows/Spaces, type-to-go (URL or search opens new Chrome tab) | Hotkey → type → Enter lands in <2 s |
| M4 | **Chrome tabs**: extension + native-messaging host, tab list in notch, activate tab; tabs included in search | 10 tabs listed and jumped to correctly |
| M5 | **Integration framework + GitHub**: extract `Integration` protocol, Keychain store, settings UI for accounts, arbitration of what the notch shows; GitHub Actions progress ring + PR list (review requests, checks, comments) | Push a workflow → ring appears, pass/fail banner; PR review request shows up |
| M6 | **Jenkins**: URL + token in Keychain, job/build progress, "unreachable" state when VPN is off (no error spam, auto-recover when VPN connects) | Build progress live over VPN; VPN off shows calm unreachable state |
| M7 | **Claude usage**: detect active Claude Code session (hooks/local session files, verified first), glyph while active, expand to usage numbers | Start a Claude session → notch shows it live; stops when idle |
| M8 | **Slack + Gmail, multi-account**: OAuth per account, account badges/colors, per-account mute/priority, quick actions (open, archive, reply), notification history | 2 Slack workspaces + 2 Gmail accounts live together |
| M9 | **Design and polish**: mockups first (collapsed/expanded/notification/progress states), then implement; animations, theming, accessibility, onboarding flow | Raj signs off on mockups, then on the build |
| M10 | **Commercial**: licensing + trial (Paddle or Lemon Squeezy), Sparkle auto-update, notarized DMG, website, privacy policy, crash/analytics opt-in, private beta | Beta users can install, pay, update |
| M11 | **Calls (Phase 3)**: detection + timer, controls where possible | After M10, if still wanted |

Order rationale: M1–M4 deliver Raj's original pain (navigation) and de-risk the hard OS layer first. M5 extracts the plugin API from real code. M6–M8 add live info in order of lowest to highest integration risk. Design (M9) is its own milestone so it isn't squeezed, but a basic clean look is used earlier so Raj can dogfood.

### Risks specific to execution
- **Gmail:** reading/modifying mail needs Google restricted scopes; a public app must pass Google OAuth verification and likely a paid third-party security assessment. This is the biggest commercial blocker. Mitigation: start with unverified/test-user mode for Raj and beta (limited users), decide before M10 whether to pass verification or use a lighter approach (e.g. unread counts only / IMAP app passwords).
- **Slack:** distributing to other workspaces requires a Slack app with OAuth install; non-Marketplace apps have API rate limits. Check before M8.
- **Private macOS APIs:** keep isolated in WindowEngine; add a smoke test checklist to run after each macOS update/beta.
- **Claude usage source:** unverified; M7 starts with a short investigation of what local data exists before committing to numbers shown.
- **Permissions UX** (Accessibility, Screen Recording, Automation) can lose users at install; onboarding in M1/M9 must explain each one.

### Decisions still needed from Raj (none block M1–M2)
Product name/domain, pricing model, GitHub Enterprise or github.com, which Claude usage numbers to show, Chrome-only vs other browsers, public module SDK or first-party only, Gmail verification strategy.

### Immediate next steps
1. Raj: pick a name, install Xcode, create repo (or I create it using personal-identity conventions).
2. Start M1 (writing-plans for M1–M2 detailed task list, then build).

## Verification (for M1–M4, once built)
- Repeat for built-in display and an external display, plus a fullscreen app in the foreground.
- Minimized Terminal window, a menu-bar-only app (Pritunl) and a window on another Space all jump correctly.
- Space switch: pick a window on a different Space; the correct Space and window come forward.
- Manual: open 10+ apps over 4+ Spaces, hover notch, click each entry; confirm correct Space + window focus, including fullscreen apps and external display.
- Chrome: 10 tabs, click each from notch; confirm correct tab activates.
- Type "foo bar" and a URL → new Chrome tab opens correctly.
- Measure hover latency and idle CPU (Instruments/Activity Monitor).
