# UI Replacement Plan

Port the JSX/HTML design bundle (felt-table + paper-scoresheet aesthetic) over the existing Phoenix LiveView UI. Backend (GameServer, C++ engine, contexts) stays intact.

## What's there now

### UI to remove / rewrite
- [lib/preferans_web_web/live/game_live.ex:175-301](lib/preferans_web_web/live/game_live.ex#L175-L301) — the `render/1` block (everything from `<div class="flex h-screen…">` to `</div>`). Mount + event handlers stay.
- [lib/preferans_web_web/components/game_components.ex](lib/preferans_web_web/components/game_components.ex) — 815 lines of phase panels, opponent area, scoring sidebar, debug panel. Most gets replaced; the **debug panel** is worth preserving.
- [lib/preferans_web_web/components/card_component.ex](lib/preferans_web_web/components/card_component.ex) — current card; replace with the JSX-style face/back.
- [assets/css/app.css:105-170](assets/css/app.css#L105-L170) — `.game-table`, `.btn-game-*`, `.bg-card-*`. Replace with the felt/paper/dark surfaces + tokens from the design.

### Stays — do not touch
- All of `lib/preferans_web/` — context, `GameServer`, `Engine`, `Cards`, `Game.Match`, `Game.Hand`. The C++ engine is the source of truth.
- All `handle_event` / `handle_info` callbacks in `game_live.ex` (lines 39–170) — the new UI will reuse the same `phx-click` events (`bid_value`, `bid_moje`, `toggle_discard`, `confirm_discard`, `declare_game`, `defense`, `kontra`, `play_card`, `next_hand`).
- `view` assign shape produced by `GameServer.get_player_view/2` — the new components consume the same fields (`my_hand`, `bid_history`, `current_trick`, `tricks_won`, `match_bule`, `match_refe_counts`, `match_supe_ledger`, etc.).

### Data shape mismatch with the JSX prototype to keep in mind
- Cards are `{suit, rank}` tuples with atom suits `:pik | :karo | :herc | :tref` and atom ranks `:seven…:ace`. JSX uses `s/d/h/c` + `'7'..'A'`. The Elixir `Cards` module already has `suit_symbol/1`, `suit_color/1`, `rank_label/1` — port the JSX styling onto these atoms; **don't** rename anything backend-side.
- The JSX `ai.jsx` and `game-state.jsx` are **reference only** — `GameServer` already does all of that on the server. Skip the AI/state ports entirely.
- `Tweaks panel` (`tweaks-panel.jsx`) — design-tool only, skip.

---

## Phases

Three phases. Each phase has a clear deliverable and is independently mergeable. Steps 1–4 (Phase A) are atoms that can be built in parallel; Phase B wires them; Phase C cleans up.

| Phase | Theme | Steps | Est. |
|---|---|---|---|
| **A** | Foundation: tokens + atomic components | 1, 2, 3, 4 | ~2 hr |
| **B** | Phase panels + new render | 5, 6 | ~2.25 hr |
| **C** | Cleanup + verify | 7 | ~30 min |

**Total: ~4–5 hours.**

---

## Phase A — Foundation (~2 hr)

**Goal:** design tokens loaded, atomic components (`<.card>`, `<.mini_scoresheet>`, `<.refe>`, `<.seat_panel>`) compile and render in isolation. No wiring yet.

### Step 1 — Design tokens & fonts (~15 min)
- [ ] Add Google Fonts `<link>` (Cormorant Garamond / Caveat / JetBrains Mono / Manrope) to [lib/preferans_web_web/components/layouts/root.html.heex:10](lib/preferans_web_web/components/layouts/root.html.heex#L10).
- [ ] In [assets/css/app.css](assets/css/app.css), replace lines 105–170 with:
  - [ ] `:root` block with `--font-display`, `--font-card`, `--font-hand`, `--font-mono`, `--card-bg`, `--card-red`, `--card-black`, `--paper`, `--accent`.
  - [ ] `.pf-surface-felt`, `.pf-surface-dark`, `.pf-surface-paper` background gradients.
  - [ ] `@keyframes pf-card-in`.
  - [ ] `.pf-paper::before` overlay rule.
- [ ] Keep daisyUI / Tailwind `@import` and `@plugin` blocks above untouched.
- [ ] **Done when:** `mix phx.server` boots, page renders with new fonts loaded (check Network tab / DevTools fonts panel).

### Step 2 — Card atom: port `card-view.jsx` (~30 min)
- [ ] Rewrite [lib/preferans_web_web/components/card_component.ex](lib/preferans_web_web/components/card_component.ex):
  - [ ] `<.card face={:up}>` — cream background, TL + BR rank+suit corners, large center pip.
  - [ ] `<.card face={:down}>` — burgundy diagonal-stripe back with inner border + "P" monogram.
  - [ ] `:size` attr supports `:xs | :sm | :md | :lg`.
  - [ ] Use `Cards.suit_symbol/1`, `Cards.rank_label/1`, `Cards.suit_color/1` — no atom renaming.
- [ ] Preserve existing `:clickable / :selected / :dimmed / :click_event / :click_value` attrs (callers in `game_components.ex` already pass them).
- [ ] **Done when:** `mix compile --warnings-as-errors` passes; spot-render a hand by visiting `/game/:id` even though surrounding chrome is broken.

### Step 3 — Scoresheet + Refe: port `scoresheet.jsx` (~45 min)
- [ ] New file `lib/preferans_web_web/components/scoresheet.ex` with:
  - [ ] `<.mini_scoresheet>` — three columns Supa | Bule | Supa, paper background w/ ruled lines, sub-totals row, grand total row.
  - [ ] `<.refe>` — three SVG triangles in a row, tally marks per side, every 5th mark drawn as a 4+1 diagonal cross.
- [ ] Decide `entries` source: derive from `view.match_bule` deltas, or add a thin helper on `GameServer` returning `[%{hand: n, scores: [s0,s1,s2]}]`. Pick whichever needs fewer backend changes.
- [ ] `<.refe>` reads `view.match_refe_counts` directly (already a 3-int list).
- [ ] **Done when:** rendering `<.mini_scoresheet>` and `<.refe>` with stub data produces the paper-on-felt look matching the JSX prototype.

### Step 4 — Seat panel: port `seat-panel.jsx` (~30 min)
- [ ] New file `lib/preferans_web_web/components/seat_panel.ex` with `<.seat_panel>`:
  - [ ] Avatar circle + name.
  - [ ] Role badge: DECLARER / PARTNER / DEALER (small uppercase mono label).
  - [ ] Action bubble (e.g. "Pas", "Kontra") sourced from a recent-action prop.
  - [ ] Trick count "Štih X/10".
  - [ ] Fanned face-down hand (uses `<.card face={:down}>`).
  - [ ] `:side` attr (`:left | :right`) flips alignment / row direction.
- [ ] **Done when:** swapping the existing `opponent_area/1` call site for `<.seat_panel>` with the same data renders.

---

## Phase B — Phase panels & new render (~2.25 hr)

**Goal:** all 8 phase panels and the full three-column LiveView render are in place. Game is playable end-to-end.

### Step 5 — Phase panels: port `phase-panels.jsx` (~1.5 hr)
Rewrite the panels (in `game_components.ex` or a new `phase_components.ex`). **Keep the same `phx-click` event names** — handlers in `game_live.ex` lines 80–148 don't change.

- [ ] `bidding_panel/1` — 6-button ladder, bid history strip, Pass button. Wires to `bid_value`, `bid_moje`, `bid_igra`, `bid` (with `action="dalje"`).
- [ ] `talon_panel/1` — 2 face-up cards + TAKE button (no `phx-click` needed for AI declarer; the C++ engine drives it).
- [ ] `discard_panel/1` — selection counter "0 / 2", CONFIRM button. Reads `@selected_discards`, emits `toggle_discard` and `confirm_discard`.
- [ ] `declare_panel/1` — 6-option grid (Pik / Karo / Herc / Tref / Betl / Sans). Emits `declare_game` with the right `game` value.
- [ ] `defense_panel/1` — In / Out / Invite buttons + per-seat response chips. Emits `defense` with `dodjem | ne_dodjem | sam | idemo_zajedno`.
- [ ] `kontra_panel/1` — current chain label + next-step button + Pass. Emits `kontra` with `kontra | rekontra | subkontra | mortkontra | moze`.
- [ ] `trick_area/1` — three-position grid (left / right / bottom) for the in-flight trick; cards animate in with `pf-card-in`.
- [ ] `scoring_panel/1` — paper-card MADE/FAILED summary, per-seat score chips, NEXT HAND button → emits `next_hand`.
- [ ] **Done when:** every panel renders correctly when its phase is active; legal `phx-click` events fire and `GameServer` advances state.

### Step 6 — New `GameLive.render/1`: port `app.jsx` (~45 min)
Replace [game_live.ex:175-301](lib/preferans_web_web/live/game_live.ex#L175-L301).

- [ ] Outer wrapper with `class="pf-surface-felt"` filling the viewport (no `ScaleStage` transform — let CSS flex do it).
- [ ] Three-column grid: `320px 1fr 360px`.
- [ ] **Left rail (320px):** `<.seat_panel side={:left}>` for `@positions.left` + `<.mini_scoresheet>` for that seat + `<.refe>`.
- [ ] **Center column** (top → bottom):
  - [ ] Header strip: "PREFERANS" title + contract chip (suit symbol + kontra ×N) + "Štih X/10".
  - [ ] Phase content: `case @view.phase do … end` dispatching to step 5 panels.
  - [ ] Human hand row: name + role badges + trick count + fanned hand of clickable `<.card>`s.
- [ ] **Right rail (360px):** `<.seat_panel side={:right}>` for `@positions.right` + their `<.mini_scoresheet>` + the human's `<.mini_scoresheet>` (the intentional duplicate per the README).
- [ ] Skip `Layouts.app`/`flash_group` wrapper — `mount` already sets `layout: false`.
- [ ] **Done when:** loading `/game/:id` shows the felt table with all three seats populated and the human's hand at the bottom; clicking through phases works end-to-end.

---

## Phase C — Cleanup & verify (~30 min)

**Goal:** dead code removed, full hand verified in a browser.

### Step 7 — Trim & verify (~30 min)
- [ ] Delete unused functions from `game_components.ex`: `opponent_area/1`, `scoring_sidebar/1`, `bidding_phase/1`, `discard_phase/1`, `declare_game_phase/1`, `defense_phase/1`, `kontra_phase/1`, `trick_play_phase/1`, `trick_result_phase/1`, `scoring_phase/1`, `hand_over_phase/1`, `my_hand/1`, `game_info_bar/1`.
- [ ] **Keep** `debug_panel/1` and its `format_*` helpers — still wired to the Debug toggle.
- [ ] `grep -r btn-game lib/` — if nothing matches, drop the `.btn-game*` rules from `app.css`.
- [ ] `mix precommit` (compile w/ warnings-as-errors, format, test).
- [ ] `mix phx.server` → click through one full hand at `/lobby` → `/game/:id`:
  - [ ] Deal → Bid → Talon → Discard → Declare → Defense → Kontra → 10 Tricks → Scoring → Next Hand.
  - [ ] Verify in browser (CLAUDE.md note: type-checks ≠ feature correctness).
- [ ] **Done when:** `mix precommit` passes and one full hand plays through without console errors.
