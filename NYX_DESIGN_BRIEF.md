# Nyx Mobile — Design Brief (for Flutter rebuild)

Source: `nyx-mobile` (Expo SDK 57 + React Native, TypeScript), read-only study on 2026-09-28.
Default theme: **Paper** (`theme.id === 'paper'`, userInterfaceStyle `light`). Read all hexes as Paper unless noted.

---

## 1. Color system

**Paper (default — cream "paper-and-ink"):**
| Role | Hex |
|---|---|
| Page background `bg` | `#F5F1E8` |
| Card surface `surface` | `#FDFCF9` |
| Border (card hairline) | `#E4DFD2` |
| Border strong | `#DCD5C6` |
| Text primary `ink` | `#1A1917` |
| Text secondary | `#57534B` |
| Text muted | `#726D62` |
| Text faint | `#948F82` |
| Accent (slate blue — interactive/live ONLY) | `#3F5A7D` |
| Accent dark | `#2B4260` |
| Accent soft (selected rows, user bubble fill) | `#E8ECF2` |
| On-accent text | `#F5F1E8` |
| Error / destructive | `#A34A3A` |
| Success | `#3E6B4F` |
| Warning | `#8A6A1F` |
| Tab bar bg | `#EDE7DA` |
| Tonal fill (fields, search bars, nav bar, chips) | `#EDE7DA` |
| Active nav pill | `#D6DEEA` |
| Selected/de-emphasized row fill | `#F8F6EF` |
| Internal row divider inside cards | `#EFEAE0` |
| Outlined button border | `#C9C2B2` |
| Faintest ink (timestamps) | `#B3ADA0` |
| Idle status dot | `#D5CEBE` |
| Overlay scrim | `#2A2823` (surfaces), 40% black modal scrim |

**M3 role mapping (how tokens compose):** primary = accent, primaryContainer = accent at 16% alpha, secondaryContainer = ink at 8% alpha, tertiaryContainer = `border`, surfaceContainer = tonalFill `#EDE7DA`, surfaceContainerHigh = rowSelected `#F8F6EF`, surfaceContainerHighest = navPill `#D6DEEA`, scrim = `#2A2823`.

**Alternate themes (user-switchable):** night `#0B1220`/`#121A2A` mint accent `#7DCEA0`; plum `#1A1220` violet accent `#B794F4`; moss `#E8EDE4` olive accent `#3D5C3A`; sand `#F3E6D4` terracotta `#C05621`; ink `#111111` white accent; terminal `#0A0F0A` phosphor `#39FF14`; ocean `#0C1B22` teal `#38B2AC`.

**Rule of the palette:** one accent color reserved for interactive/live elements only. Everything else is tonal ink/paper variation. For Pantheon, swap slate `#3F5A7D` for the Pantheon purple gradient `#7223FF → #4B00CD → #0C0046` — but keep the "accent = interactive only" discipline.

## 2. Typography

Three embedded families: **Clash Display** (headers/screen titles — Fontshare), **Satoshi** (all body/UI — Fontshare), **JetBrains Mono** (code, ids, token counts, machine-precise values). Max two weights used: 400/500. No fake bold.

Key sizes (Flutter equivalent sp):
- Screen title (large app bar): 28, weight 500, Clash Display
- Small app bar title: 22, weight 400, Clash Display
- Section title / card title: 20, weight 500, Clash Display
- Body: 15/22, weight 400, Satoshi
- Row title: 15/22, weight 500, Satoshi
- Label (buttons, chips): 14, weight 500, Satoshi
- Small meta: 11–12, Satoshi
- Overline (group headers "GATEWAY", "RECENT SESSIONS"): **11, weight 500, letterSpacing 1.5, ALL CAPS**, muted ink
- Mono small: 11; mono medium: 12 (JetBrains Mono)
- Eyebrow mono: 10, letterSpacing 0.8, uppercase

## 3. Screen structure

**Bottom tabs (5):** Home · Sessions · Artifacts · Memory · More. Tab bar: 80dp tall + system inset, bg `#EDE7DA`, hairline top border, 12sp labels (active `ink`, inactive `inkSecondary`). Active icon sits in a 64×32dp pill filled `#D6DEEA`; icons are 23dp thin-stroke line icons (1.6–1.8 stroke). Home carries an extended FAB "+ Ask" (60dp tall, ink fill, cream label).

**Stack (pushed from tabs/More):** Chat, Settings, Notifications, Analytics, Cron (scheduled jobs), Skills, Tools, Projects, Router, Voice, VoiceCall, FileViewer, Kanban/Goals/Heartbeats/Logs, NewAgent, AgentDocs, Approval, Plugins, Search, SignIn/Permissions.

**App bar:** 64dp small variant (large 152dp with scroll-collapse). Back = drawn chevron arrow, no label. Padding 16dp (12dp when a back arrow leads). Trailing icon buttons, 48dp targets.

**Home layout (top→bottom):** offline banner → queued-messages card → top app bar (ProfilePill + search + bell with count badge) → big headline ("Everything nominal") → gateway status card (filled tonal, platform status bars) → two side-by-side stat cards (Today tokens · Cron active+next) → "RECENT SESSIONS" overline + session list.

**More screen:** grouped list of hub cards (per feature) using the same Card + ListItem primitives.

## 4. Signature components

- **Cards:** `#FDFCF9` on `#F5F1E8`, **1dp hairline border `#E4DFD2`, 16dp radius, NO shadow**. Filled variant uses tonal `#EDE7DA` with no border. Card padding 14dp, stack gap 12dp, screen gutter 16dp.
- **ListItem:** standard row: 56dp min (64 two-line / 88 three-line), 14dp H / 13dp V padding, 12dp gaps; 15sp/500 title, 12sp muted subtitle; optional right-aligned mono "supporting" text (e.g. "48.2k tok"); status dots are 7dp, **top-aligned to the first text line** (idle `#D5CEBE` outline, live accent, error rust, success green); trailing chevron. Internal dividers `#EFEAE0`.
- **Chat composer:** pinned bottom row: 40dp attach button → tonal field (`surfaceContainerHighest`, 16dp radius) → 40dp mic → 40dp circular send (primary when sendable, muted otherwise). Pending attachments render as small chips above; listening state shows a pulsing dot + tabular timer + "Tap to stop".
- **FAB:** 60dp-tall extended rounded-rect (18dp radius, NOT a stadium), ink fill + cream label/icon. The ONLY shadow in the whole app: `0 6dp 16dp rgba(26,25,23,0.22)`. Sits 100dp from bottom (clears 80dp tab bar by 20).
- **Bottom sheets:** 28dp top radius, 32×4dp drag handle in `outlineVariant`, sheet bg `surfaceContainerLow`, max 90% height, scrim `#2A2823`. Sheets preferred over context menus.
- **Approval cards (the distinctive one):** surface card with **error-colored border** (`#A34A3A`), uppercase 11sp "APPROVAL NEEDED" kicker, description, command text, and pill action buttons: "once / session / always" in ink, "deny" in error red.
- **Chips:** 32dp min pill, 1dp outline when unselected, tonal fill when selected with check glyph. Status chips: tonal green/red/neutral.
- **Buttons:** 52dp tall, 20dp radius. Filled = accent; tonal = container; outlined = 1dp outlineBtn border; text = accent label. Pressed = 0.88 opacity (no ripple customization).
- **Text fields:** M3 filled tonal: 56dp min, 8dp radius, tonal fill, **2dp border only on focus/error**, label 12sp above field.
- **Segmented control:** pill container in tonal fill with 4dp padding; selected segment gets `surfaceContainerHighest` pill + check glyph.
- **Empty states:** centered: 40dp thin-stroke icon in faint ink, 20sp title, 15sp body (max 260dp), ink pill CTA ("New session" + plus) with optional outlined secondary action.
- **Banners:** queue/offline/context-limit banners = full-width tonal strips above content with icon + 13sp text + inline action.
- **Snackbar:** bottom-anchored above FAB/tab bar, dark inverse surface, 4dp radius, optional action label, ~4s auto-dismiss.
- **Galaxy3D:** 3D node-graph visualization (three.js-ish) on the Memory screen — dark, glowing edges/nodes, used as the memory-graph view alongside Clusters/Timeline segments. Pure flourish; skip unless you want a signature.

## 5. Shape language

Radii: **4** (chips/badges) · **8** (text fields) · **12** (nested) · **14** (hub rows) · **16** (cards) · **18** (FAB, send, message bubble) · **20** (buttons) · **26** (composer field) · **28** (sheets) · **999** (pills, nav pill, toggles, toggles 42×26 track with 22dp knob).

**Hairline > shadow.** Only sheets + FAB cast shadows; everything else is defined by 1dp borders. Spacing rhythm: 4dp base, 8dp rhythm, 16dp screen gutter, 12dp card stack gap. Touch targets 48dp minimum. Icons: custom thin-stroke line icons at 1.6 stroke (24dp default), never filled.

## 6. Animation/motion

Deliberately restrained — no page-transition choreography, no scroll effects beyond large-app-bar collapse:
- Attach icon **rotates 220ms** (easeInOut) when the attach sheet opens/closes.
- Assistant overlay mic dot **pulses in a 1.2s easeInOut loop**.
- Pressed states: simple 0.88 opacity (no scale/ripple).
- Bottom sheets/modals: fade. Snackbars: timed auto-dismiss.
- If you want "fun with animations" in Flutter: the natural hooks are the FAB morphing into the quick-entry sheet, sheet spring curves on bottom sheets, animated segmented-control indicator, and bringing Galaxy3D-style node graphs to life (the Nyx one is static-ish WebGL). Nyx itself keeps motion minimal — the smoothness comes from the rhythm, not the transitions.

## 7. Overall vibe

Nyx feels like a **printed field manual that happens to be an app**: cream paper, ink-black type, hairline rules instead of shadows, one quiet slate-blue reserved for things that are alive. Clash Display gives the headers a confident editorial voice while Satoshi keeps body text neutral and modern; everything sits on a strict 4/8 grid with generous whitespace. It's Material 3 in structure (tabs, sheets, snackbars, FAB) but stationery in spirit — calm, dense-without-clutter, and allergic to decoration. The craft is in the restraint: press states that just dim, dividers sampled to the exact pixel, mono reserved for machine truth. For Pantheon, keep the skeleton (tabs + sheets + hairline cards + thin icons + editorial type) and re-ink it: deep purple-navy surfaces, Pantheon purple as the single "live" accent, same discipline.
