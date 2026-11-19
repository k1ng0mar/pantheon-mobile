# Pantheon mobile UI: what to copy from Conduit and Kyllene

A synthesis of three evidence layers, all read in full:

1. Umar's study package `pantheon-ui-study.zip` (38 recordings, 643 frames, 13 stills, the 2,186 line deep study, all 30 sections).
2. The Conduit iOS source, native SwiftUI, MIT [1]. Code report: `ui-analysis/conduit-code-report.md` (413 lines, every component opened and verified).
3. The Kyllene source, Kotlin Multiplatform + Compose Multiplatform, MIT [2]. Code report: `ui-analysis/kyllene-code-report.md` (243 lines, every composable opened and verified).

Target: `~/projects/pantheon-mobile`, Flutter.

> CORRECTION (verified against source 2026-11-19): the first draft of this doc claimed the app had "36 screens, one shared widget, no theme" and needed a kit built from scratch. That was wrong. The app is already mature: 107 Dart files, 36 screens, 28 shared widgets, 33 models, a `theme.dart` design system (P palette + PT typography), 187 passing tests, clean analyze. It already implements most of the invariants below (send to stop composer morph, human-words timeline, a full agent-native UI protocol v1 with diff/approval/form/task_list/progress cards, a live "Working for" ticker, optimistic pending bubbles, queue/steer/stop, loading/error/empty triad, retry, a swarm delegation view). The real work is closing the few genuine remaining gaps, not rebuilding. See section 7 for the corrected, surgical plan.

---

## 0. The thesis

Conduit and Kyllene feel splendid for the same reason, and it is not the colors. They treat an agent turn as a **legible state machine** rendered through a **typed presentation layer**, and they enforce a small set of layout invariants in code. The polish is a set of rules the code refuses to break, not decoration added on top.

Both codebases literally encode these rules as comments. Conduit: "a running turn's time is on the working line", "Not glass: glass redraws what is behind it on every frame". Kyllene: "What's happening now is said once, above the composer", "184k must never read as 184", "a job that didn't run is missed, a process the user stopped is stopped, not failed".

So the wheel we are not reinventing is: **one live surface, human words over raw internals, whole tool calls, measured layout, counted truncation, stable disclosure, typed verdict cards, guarded destructive actions.** Everything else is tokens and components.

The gap in Pantheon mobile is structural: 36 screens and one shared widget means every screen reinvents its own cards, pills, status lines and state handling. Conduit and Kyllene each have a shared design system plus a component kit that every screen and sheet reuses. That kit is the thing to build first.

---

## 1. The eight load bearing invariants

Each one is confirmed in both codebases and kills a specific flaw from the study.

### 1.1 One live surface, one clock
- Conduit: `TranscriptModel.LiveTurn.rows` emits working XOR streaming by construction. `ChatWorkingLine` owns the only count up timer, via self driving `Text(timerInterval:)` so the view never re renders per second. `ChatStepGroupHeader.title` shows elapsed time only once the run is done ("a running turn's time is on the working line"). `ChatAwaitingAgentsLine` rests the mark and shows no timer because the turn is not running. [1]
- Kyllene: `ProgressPanel` is the single "what's happening now" card above the composer. `RunningTime` ticks whole seconds with `delay(1000 - (now - started) % 1000)` so no second is skipped or shown twice, and is hidden from screen readers. Reply bodies keep only what they are made of; live progress belongs to the dock, not the reply. [2]
- Kills: the study's "three thinking indicators at once" and competing timers. This is the single highest leverage rule.

### 1.2 Human words over machine internals
- Conduit: `ChatStepStyle` maps tool name to icon, tint and a plain verb ("Ran a command", "Searched the web"). All phone tools read as "Using your iPhone", told apart by icon only, so `conduit_health` never leaks into a title. `ToolResultPresentation` is a typed cached parser (todos, colored diff, links, media, error, exitCode) that sits between gateway output and every view. Raw tool name appears only on expansion. [1]
- Kyllene: `toolVerb`/`toolDone` produce past tense verbs; `firstDetailLine()` refuses JSON inputs (`takeUnless { startsWith("{") || "[" }`); ~50 `CheckNote.Kind` values map to localized problem plus fix strings; cron becomes a readable schedule; delivery receipts become words. View models emit catalogue keys (`Said`/`Words`), screens resolve language. [2]
- Kills: raw JSON dumps, internal paths, "Running python3" status lines. Note: the kaomoji status lines in the videos ("(⊙_⊙) brainstorming…") are NOT in either codebase's verb layer; they come from a gateway/theme layer. Do not copy them.

### 1.3 Tool calls shown whole
- Conduit: `SettledToolCardContent` collapsed shows a human title plus one subject line; expanded shows interpreted result (`ToolResultBodyView`), then labeled raw `Input` and `Output`, pretty printed when JSON. [1]
- Kyllene: `ToolRow` expanded shows `RiskNote` plus Input / Changes(diff) / Output blocks, each with its own `CopyButton`, each commentable by a source string naming the exact call part. Failed calls label the block "Error". Mono blocks scroll horizontally with `softWrap = false` so columns survive. The same row is reused live and historical. [2]
- Kills: "tool input without output", "raw tool card JSON". Input + output + result belong in one expandable card, always.

### 1.4 Measured layout, nothing occludes
- Conduit: the transcript bottom inset tracks the composer's measured height; `ChatPlanDock` grows that inset when the plan expands; `AuthorityQueueDock` measures rows and caps at 240pt; `WindowSideInsets` + `ReadableContentWidth` keep content in the real safe column on split screens. [1]
- Kyllene: `dockHeight` via `onSizeChanged` feeds `listInset` feeds `contentPadding(bottom = 12dp + bottomInset)`. The jump pill rides at `bottom = 12dp + controlsInset` (the dock's real height). Reading back folds the composer to one line (`ComposerFold`), and the inset keeps the open height so folding does not scroll the chat and undo itself. Lists get `PageFoot` (96dp phone) so the last row clears floating chrome. [2]
- Kills: the study's #1 flaw, floating chrome over content. Important nuance: both codebases have this fix, yet the videos still show occlusion (the iOS tab bar + voice FAB, the Android "New chat" pill + U avatar). So the fix is either partial or the videos predate it. The lesson stands: bottom chrome must be part of the measured layout, never a free floating overlay.

### 1.5 No silent truncation
- Conduit: every bounded render has a counted affordance, "Show all N lines", "Show full message", "(N more lines)". Previews bounded by line AND byte count, sliced off the main actor, previous slices kept during re slice. [1]
- Kyllene: `TextAutoSize.StepBased` on every figure ("184k must never read as 184"); folded to expanded raises line caps (1 to 4, 2 to 6); `FlowRow` / `weight(1f, fill=false)` let secondary text yield instead of pushing actions off row; `fontScale > 1.3f` reflows tile grids 4 to 2 and legends 2 to 1; sheets scroll rather than clip. [2]
- Kills: truncated card titles, comparison cards wider than the viewport with no scroll cue, clipped tiles.

### 1.6 Disclosure state outside the row, scroll stable
- Conduit: `ChatRowDisclosure` is a non observable store keyed by message id, passed through the environment. Row local `@State` fails because a live card becomes a settled row with the same id, or a lazy row is rebuilt after scrolling away. `willToggle` notifies `TranscriptScroller.userWillToggleRow` BEFORE the height changes, so the tapped row stays under the finger. Rows that start open do so at init, not `onAppear`. `.rowFoldSwap` avoids double animation. [1]
- Kyllene: `rememberSaveable` + stable keys for every expanded row (survives recomposition and unfolding a foldable); content kept through exit animations (the `shown` pattern) so panels never empty mid fade; `key(request.id)` so secrets do not leak across requests. [2]
- Kills: cards folding shut under the reader, jump on expand, transition ghosting. This is the strongest single pattern in Conduit and worth copying first.

### 1.7 Typed verdict cards instead of prose dumps
- Conduit: `RichCard.Kind` has 20 cases (map, stats, chart, comparison, steps, media, status, table, timeline, checklist, progress, callout, diff, review, composed...). All share `RichInfoCardFrame`. Callout `Tone` = tip / note / warning. `RichComparisonCard` columns with a "Recommended" capsule. `RichReviewCard` decisions marked Approve / Change / Skip. `RichStepsCard` gives any step a timer (1 to 86,400s) that persists across launches and fires a local notification. [1]
- Kyllene: `InputRequestPanel` takes the composer's place for clarifications and approvals, amber for approvals/secrets, accent for questions, walking questions one at a time with Back/Skip + Next/Send. [2]
- This is the study's warning / comparison / options / deadline / note / tip / checklist cards. Agent output that asks for a decision should be a manipulable card, not a paragraph.

### 1.8 Guarded destructive actions, honest delivery
- Kyllene: `ConfirmChange` counts exactly what dies ("discard N later messages, here and on Hermes"), spells out branch semantics ("No task starts until you send something in the new chat"), auto dismisses when stale, gated by `canChangeChat` (stored && !running && connected && no command awaiting). `UnsettledActions` gives a doubtful prompt Check / Resend / Edit chips, never auto resends, and warns Resend could run twice. [2]
- Conduit: optimistic send with exact draft restoration on refusal (text, attachments, reply reference, keyed by a durable draft key); a device side pending queue rendered as an editable "Sends when connected" bubble. [1]
- Kills: "submit at 0/20", "send failure missing", silent double execution. On flaky mobile networks this is the honest pattern.

---

## 2. The copyable design system

Two different accent philosophies, same discipline: accent is reserved for status and action, never a large fill.

| Token | Conduit (SwiftUI) [1] | Kyllene (Compose) [2] | Adopt for Pantheon |
|---|---|---|---|
| Ground | near black + profile tinted maroon/purple glow (`ConduitBackdrop`) | graphite steps: bg #0A0A0C, surface #16161A, surface2 #1C1C22, surface3 #232329, well #121215 | graphite steps, no shadows; one optional glow |
| Elevation | glass ONLY on floating chrome; plain tinted fills + hairline in scroll content (perf: glass redraws per frame) | surfaces step in lightness instead of casting shadows; translucent hairlines (white 7%/12%) | lightness steps + translucent hairlines; blur only on floating chrome |
| Accent | amber/gold for status/action, green for success (vision confirmed) | Herald blue #2F6BF5, lighter #7AA5FF for text on dark; 6 accents, contrast unit tested at 4.5:1 | ONE accent, reserved for status/action; contrast test it |
| Status tints | semantic colors (success, attention, scheduled, voice) | GitHub ish #F85149/#3FB950/#F5A524 with *Soft tints at 9 to 14% alpha ONLY behind small glyphs | soft tints behind small glyphs only, never large fills |
| Text | semantic roles, `conduitTertiary` is a style not a color | 4 steps: text, textSecondary, textTertiary, textMuted | 4 text steps |
| Type | `scaledFont` (UIFontMetrics) + chatTextSize; `AdaptiveStack` stacks at accessibility sizes | Geist, weights 400/500/600 only; Geist Mono for ALL machine text; hierarchy from size + color | one sans (3 weights) + one mono for machine text |
| Radii | continuous corners: 22 step cards, 16 capsule, 14 chips, 13 code | scale 6/10/14/20/26/999 (inline code / tiles / cards / bubbles / composer / pills) | a fixed radius scale, not ad hoc |
| Motion | two named curves: response spring(0.34, 0.82), settle easeOut(0.22); reduce motion respected | 180ms scheme transition; content kept through exit animations | two named curves; never empty a panel mid fade |
| Touch | 44pt remove targets via negative padding | `MinTouchTarget` 48dp phone / 36dp desktop; draw small (28 to 38dp) tap big | draw small, tap big, 48dp minimum |
| Icons | SF Symbols via category maps | Lucide at explicit dp (11 to 20) | one icon set, category mapped |
| Width | `ReadableContentWidth` shared reading column | `READING_WIDTH = 760dp` | cap the reading column |
| Schemes | adaptive light/dark UIColor pairs | Light, Dark, PureBlack (OLED) | light + dark + OLED |

Vision confirmed the felt aesthetic: Conduit is warm (near black, maroon glow, amber/gold, green success, nested cards 24px outer / 12 to 16px inner, glassmorphism on chrome). Kyllene is cool (charcoal, blue accent, green done, 16 to 20px radii, monospace code, collapsible history). Both read premium because of restraint and hierarchy, not ornament. Given Umar's cinematic/industrial taste, a single warm accent on graphite steps is the natural Pantheon direction.

---

## 3. The component grammar to copy (the wheel)

Build these once as a shared kit; every screen and sheet reuses them. Source component names are the reference implementations to read.

1. **Work log / transcript row model.** Conduit `TranscriptRow.Kind` (loadEarlier, empty, message, thinking, streaming, working, awaitingAgents, pendingSend, room) + `TranscriptChangeSet` diffing by row id so streaming text does not invalidate the list. Kyllene `LiveSteps`/`LiveStepRow` (green check disc, past tense verb, mono detail chip, inline duration, only last 4 shown, "N earlier steps" collapse).
2. **Live status card.** Kyllene `ProgressPanel`/`ShimmerCard` (accent edge sweep drawn in `drawBehind` only, most specific first `currentStep`, whole second timer, always reachable Stop that fades when the turn ends, technical details folded beneath). Conduit `ChatWorkingLine` (phrase priority: repliesElsewhere > toolTitle > toolName verb > Thinking/Working).
3. **Tool row.** Conduit `SettledToolCardContent` + `ToolRawTextSection`; Kyllene `ToolRow` (Input/Changes/Output, per block copy, RiskNote, colored diff, horizontal scroll). One row, reused live and historical.
4. **Run group header.** Conduit `ChatStepGroupHeader` folds a run to "N steps · 12s", one disc per kind (max 5) via `ViewThatFits`, time only when settled, optional Hermes written summary. Kyllene `Tools` pill "Ran 3 tools · 42s" (sums the tools' own durations, not the turn's, because calls run side by side).
5. **Composer.** Conduit `ComposerBar` (one trailing slot driven by `ComposerAction` + per chat `BusyInputMode` steer/interrupt/queue/stop, long press for alternates, symbol replace morph, `ContextRingView` around send, optimistic send + draft restore, attachment strip clipped to card width). Kyllene `ComposerFold` (folds to one line on read back, measured inset).
6. **Sheets.** Conduit `SheetAboveAll` (one host, priority ordered, queued presentation, no stacked sheets) + sheets reuse the settings kit (`SettingsDetailContainer`, `ConduitSettingsSection`, `settingsCard`). Kyllene `BottomSheet` (one API, phone modal / desktop anchored popover, menus flip above when no room).
7. **Usage / context.** Kyllene `UsageSheet`/`ContextSplit` (segmented category bar, legend always beside color so color is never the only cue, `~`/"About" estimate qualifiers, files read in with "skipped", cost status included/not priced/estimated/billed, gateway limits verbatim, refresh keyed to live token count, `CONTEXT_WARNING = 0.8f`). Conduit `ContextSheet` + composer context ring.
8. **Model picker.** Kyllene `ModelSheet` (Yours/All/provider scopes, stars + recents, thinking chips auto scrolled to current, search only above 12 models with Enter picks best, provider pills with prices, recents recorded only on confirmed switch, expensive switch confirm). Conduit `ModelPickerView` + `KeptModelCatalog` (loading/failed/empty are three screens, not one blank list).
9. **Settings + connection diagnostic.** Kyllene `SettingsScreen` (grouped sections, search via CompositionLocal, `AccountCard` user first so a long address is what gets cut) + `ConnectionChecklist` (Server to SignIn to Live discs on a drawn spine, every failure paired with a localized fix hint, copyable for bug reports, reused in onboarding). Conduit settings kit reused by every sheet.
10. **Delegation.** Conduit `DelegateAgentActivity.Status` (queued/running/completed/failed/interrupted) + `DelegateAgentsSheet`/`DelegateAgentCard`/per agent tail + `ChatAwaitingAgentsLine`. Kyllene `TeamDots` (one overlapping dot per subagent, green done/accent working, +N beyond 4). See section 5.
11. **Verdict cards.** Conduit `RichCard` family (callout tip/note/warning, comparison, review options, steps with persisted timers + notifications). Kyllene `InputRequestPanel` for clarifications/approvals.
12. **Feedback + states.** Inline copy confirmation (Conduit label swaps to Copied, checkmark symbol replace, light haptic, 1.4s reset, `copyCount` guard). Kyllene `EmptyState` (+Try again), layout mirroring skeletons, one shared `Spinner`, `OfflineBanner` ("Your draft is kept"), `DeliveryChip`. Every page ships the loading/error/empty triad.

---

## 4. The state machine and the missing states we must build

The study logged 20 missing states. Most now have a copyable pattern; a few we still have to design because no recording shows them.

| Missing state | Copy from | Note |
|---|---|---|
| stopped by user | Kyllene `StopButton` + `canStop` + "Stopped" caption; Conduit stop | post stop transcript state still unobserved as a flow; design it |
| failed tool / turn + retry | Kyllene per turn error row + `RetryChip`, `ToolRow` Error block; Conduit error label + exit code | copy |
| offline / slow | Kyllene `OfflineBanner` "Your draft is kept" + `RetryChip`, `SavedCopyPill` offline encrypted copy with current age | copy |
| send failure / uncertain delivery | Kyllene `UnsettledActions` Check/Resend/Edit + double run warning; study still 4 "Not delivered" | copy, never auto resend |
| empty states | both `EmptyState` + Try again + teaching copy | copy |
| save lifecycle | Conduit inline Copied 1.4s; Kyllene per row saving spinner + `MessageBanner` | copy |
| token limit / context full | Kyllene `CONTEXT_WARNING` bar turns warning at 0.8; usage sheet | copy + add a live warning state |
| per task / subagent status | Conduit `DelegateAgentActivity.Status`; Kyllene `TeamDots` + subagent cards | copy |
| progress / ETA | Kyllene `PlanBar` "Step 2 of 5" + checklist; Conduit `RichStepsCard` timers | copy |
| selection feedback, disabled states, loading skeleton | both | copy |
| queued / pending send | Conduit `AuthorityQueueDock` (Send now/Edit/Remove, Resend/Discard for a cut turn) + `PendingComposerSendBubble` | copy |
| reconnecting | Conduit `ConnectionStatusIndicator` (green/secondary/orange/red, `hidesBriefReconnect` so the dot does not flap) | copy |

The rule from the study that ties these together: every spinner ends in a result or an error; every state says what happened in the user's terms (missed, stopped, not failed).

---

## 5. The delegation / subagent UI (best of three)

The study ranks Grok's subagent approach best (§29): a brief card showing what the delegate was TOLD, a count pill, a list sheet, a counted plain language log, present tense live rows, parent and delegate work on separate surfaces. The code gives us the mechanics to combine with it:

- Accountability: Grok's brief card (the goal the delegate was given) + Conduit `DelegateAgentActivity.goal`/`model`/`taskIndex`.
- Roster + control: Conduit `DelegateAgentsSheet` with per agent Steer / Live output / Stop, and `ChatAwaitingAgentsLine` for the gap after the main turn ends while delegates still run (polls so a missed end event does not leave it waiting forever).
- Inline glance: Kyllene `TeamDots` + subagent task cards, status disc plus the same state in words.
- Log discipline: counted plain language steps, present tense while live, past tense when settled, one timer.

Pantheon's delegation UI = Grok's brief card accountability + Conduit's per agent steer/stop + Kyllene's inline dots/cards. That is a concrete, buildable design, not a guess.

---

## 6. What NOT to copy (even in the favorites)

- Floating bottom chrome that eats rows: the iOS tab bar + voice FAB, the Android "New chat" pill + U avatar. The code has measured insets but the videos still show occlusion. Make bottom chrome part of the layout.
- Kaomoji status lines ("(⊙_⊙) brainstorming…"). Decoration as status; says nothing. Not in either verb layer.
- Raw JSON "Live output" dumps (Conduit #26) and raw tool card JSON (Kyllene #31/#32). Always route through the typed parser.
- Truncated card titles; comparison cards wider than the viewport with no scroll affordance.
- Greyed Save with no reason; per field Save with no "Saved" confirmation (Conduit #19).
- Two usage screens disagreeing on the window total (Kyllene #30 vs #33); "What fills it" not reconciling. One source of truth for every number.
- Unexplained green dot on the ••• menu; token footer "13.5k ↓ · 2k ↑" with no labels.
- Developer facing error copy ("edit config.yaml") on a phone. Map to a localized problem + fix.
- Rendering leaks: the "(es)" plural artifact, "•…•" markdown leak, spaced apostrophes.

### Version / naming caveat (read before referencing the source)
The cloned Kyllene HEAD does NOT contain several strings the study videos show (app v0.17.0 against Umar's gateway). Verified absences and their real counterparts [2]:
- "Compact Now" / "Keep in Focus" buttons: not present. Compaction is a transcript event row ("Earlier messages summarized"); the context sheet is read only.
- "N processes" pill: no count pill in chat chrome; the sheet header says "N running".
- "Go on" floating pill: the literal string does not exist; `InputRequestPanel` floats in the composer's place with Next/Send (the variable is even named `goOn`). The real floating pill is "New reply" (jump to latest).
- "Undo Last Turn": it is `editLastPrompt` (/undo), surfaced as "Edit last prompt" with a confirm.
Conduit has no card literally named "deadline"; `RichStepsCard` timers are the equivalent [1].
So the videos are a different build than HEAD, or those strings come from a layer not in this checkout. Copy the pattern, not the literal feature name, and re verify against the checkout before implementing.

---

## 7. The Pantheon mobile plan (Flutter)

Confirmed gap: 36 screens, one shared widget, no theme layer. The fix is a design system + component kit + state machine, not more screens. Phased, mirroring the study's sequencing and the two codebases' structure.

**Phase 1: tokens + kit (the wheel).** Create `lib/theme` (graphite lightness steps, translucent hairlines, 4 text steps, one accent reserved for status/action, soft tints behind small glyphs only, radius scale 6/10/14/20/26/999, one sans 3 weights + one mono, two named motion curves, light/dark/OLED). Create `lib/widgets` shared kit: card frame, pill, status disc, icon tile, section header, empty state, spinner, skeleton, bottom sheet host (one, priority ordered), inline copy feedback. Every existing screen migrates onto the kit. This alone closes most of the polish gap.

**Phase 2: the turn state machine.** One live surface (working XOR streaming), one self driving clock, settled headers show time only when done. Typed result parser between runtime output and views (todos, diff, links, media, error, exit code). Tool row with Input/Changes/Output + per block copy. Disclosure state outside the row, keyed by message id, scroller notified before height change. Measured composer inset so nothing occludes; fold on read back.

**Phase 3: the missing states.** stopped, failed + retry, offline ("your draft is kept"), send failure (Check/Resend/Edit, never auto resend), empty, save lifecycle, context warning at 0.8, queued/pending send, reconnecting (no flapping dot). Every spinner ends in a result or an error.

**Phase 4: verdict cards + delegation.** Callout (tip/note/warning), comparison, review options, steps with persisted timers. Delegation = brief card + roster with per agent steer/stop + inline dots + counted plain language log.

**Phase 5: surfaces.** Usage sheet (segmented context bar, legend beside color, estimate qualifiers, one source of truth for numbers), model picker (scopes, search above threshold, three load states), settings + staged connection diagnostic with fix hints, dashboard/insights/scheduled/capabilities with the loading/error/empty triad.

Flutter specifics: the self driving timer maps to a `Ticker`/`StreamBuilder` that does not rebuild the whole tree; disclosure outside the row maps to a keyed store in a provider/notifier rather than per widget `State`; measured inset maps to `LayoutBuilder`/`GlobalKey` size measurement feeding `SliverPadding`; glass only on chrome maps to `BackdropFilter` confined to the floating bar, plain fills in the scroll list (same perf reason Conduit gives).

Do not port SwiftUI/Compose code. Port the invariants, the tokens, and the component contracts. The two repos are the reference implementations to read while building each widget.

---

## 8. Sources & evidence

[1] Conduit iOS source (SwiftUI), MIT. https://github.com/kaishi00/hermes-conduit
[2] Kyllene source (Kotlin/Compose Multiplatform), MIT. https://github.com/Giton22/kyllene
[3] About Hermes Conduit. https://hermesconduit.app/about

Local evidence (read in full, not web):
- Study package: `~/gdrive/pantheon-ui-study.zip`, extracted to `~/.hermes/cache/scratch/ui-study/pantheon-ui-study/` (deep study md, README, 38 frame dirs).
- Conduit code report: `~/.hermes/cache/scratch/ui-analysis/conduit-code-report.md`.
- Kyllene code report: `~/.hermes/cache/scratch/ui-analysis/kyllene-code-report.md`.
- Cloned sources: `~/.hermes/cache/scratch/ui-analysis/conduit-src`, `kyllene-src`.
- Vision grounding: Kyllene still 3 (plan execution), Conduit still 4 (needs input), Conduit f002 (settings theme).
