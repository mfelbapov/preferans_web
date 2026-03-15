# Implementation Prompt: GameLive UI — Card Table, Phase Rendering, Scoring Sidebar

## Context

I'm building the main game screen for a Serbian Preferans card game. The backend is complete: GameServer (GenServer) manages game state via MockEngine, AI auto-plays with delays, PubSub broadcasts state updates. Now I need the LiveView that renders the card table and handles player interaction.

**Tech:** Elixir Phoenix LiveView. No JavaScript frameworks. Tailwind CSS for utility classes. Card rendering is CSS-only for now (structured so SVG swap is easy later). No animations yet — instant state swaps, animations come in a future pass.

## What Already Exists

### Backend (fully working, 143 tests passing)

- **GameServer** (`PreferansUi.Game.GameServer`) — GenServer per game, registered via `{:via, Registry, {PreferansUi.GameRegistry, game_id}}`
  - `GameServer.get_player_view(game_id, seat)` → `{:ok, view_map}`
  - `GameServer.submit_action(game_id, seat, action)` → `:ok | {:error, reason}`
  - `GameServer.subscribe(game_id)` → `:ok` (subscribes to PubSub topic `"game:#{game_id}"`)
  - `GameServer.game_exists?(game_id)` → `boolean`

- **PubSub events** broadcast on `"game:#{game_id}"`:
  - `{:game_state_updated, game_id}` — generic re-fetch signal
  - `{:action_played, game_id, seat, action}` — specific action (for future animation)
  - `{:hand_completed, game_id, scoring_result}` — scoring overlay trigger
  - `{:match_ended, game_id, final_scores}` — game over
  - `{:new_hand_starting, game_id}` — new hand dealing

- **Player view map** (returned by `get_player_view/2`):
```elixir
%{
  phase: :bid | :talon_reveal | :discard | :declare_game | :defense | :trick_play | :scoring | :hand_over,
  my_seat: 0 | 1 | 2,
  my_hand: [{:herc, :ace}, {:pik, :king}, ...],  # sorted by suit then rank desc
  opponent_card_counts: %{1 => 10, 2 => 10},     # just counts, never actual cards
  current_player: 0 | 1 | 2,
  is_my_turn: boolean,
  legal_actions: [:dalje, {:bid, 2}, {:bid, 3}, ...] | [{:play, card}, ...] | etc,
  dealer: 0 | 1 | 2,
  bid_history: [%{player: 0, action: {:bid, 2}}, %{player: 1, action: :dalje}, ...],
  highest_bid: 0..7,
  declarer: nil | 0 | 1 | 2,
  talon: nil | [card, card],          # nil during bidding, visible after
  discards: nil | [card, card],       # nil for non-declarers, always
  game_type: nil | :pik | :karo | :herc | :tref | :betl | :sans,
  defense_responses: %{1 => :dodjem, 2 => :ne_dodjem},
  defenders: [1, 2],
  trick_number: 0..9,
  current_trick: [%{player: 2, card: {:herc, :king}}, %{player: 0, card: {:herc, :seven}}],
  tricks_won: [3, 4, 3],
  played_cards: [{:herc, :ace}, {:pik, :ten}, ...],
  bule: [94, 100, 100],
  refe_counts: [0, 0, 0],
  scoring_result: nil | %{bule_changes: [-10, 0, 0], supe_changes: %{...}, declarer_passed: true, tricks: [6, 2, 2]},
  players: [
    %{seat: 0, display_name: "Milenko", is_ai: false, is_declarer: false, is_defender: true},
    %{seat: 1, display_name: "Bot Duško", is_ai: true, is_declarer: true, is_defender: false},
    %{seat: 2, display_name: "Bot Nikola", is_ai: true, is_declarer: false, is_defender: true}
  ]
}
```

- **Cards module** (`PreferansUi.Game.Cards`):
  - `Cards.card_to_string({:herc, :ace})` → `"A♥"`
  - `Cards.suit_symbol(:herc)` → `"♥"`
  - `Cards.rank_label(:ace)` → `"A"`
  - `Cards.suit_color(:herc)` → `:red` (herc/karo are red, pik/tref are black)
  - `Cards.game_value(:tref)` → `5`
  - `Cards.sort_hand(cards)` → sorted list

- **Game context** (`PreferansUi.Game`):
  - `Game.start_solo_game(user_id, opts)` → `{:ok, game_id}`
  - `Game.find_user_active_game(user_id)` → `game_id | nil`

- **Router** (already exists):
  - `live "/game/:id", GameLive` — behind auth (`require_authenticated_user`)
  - `live "/lobby", LobbyLive` — behind auth

- **Auth** — `assigns.current_user` available in all authenticated LiveViews via `on_mount` hook.

## What I Need Built

### 1. LobbyLive (`lib/preferans_ui_web/live/lobby_live.ex`)

Simple lobby page. For the first milestone (single-player vs 2 AI), it just needs:

- A "New Game" button that calls `Game.start_solo_game(current_user.id)` and redirects to `/game/{id}`
- If user already has an active game, show "Continue Game" button linking to it
- Show user's basic stats (games played, rating) from `current_user`
- Show recent match history (last 5 completed matches) — can be placeholder for now

### 2. GameLive (`lib/preferans_ui_web/live/game_live.ex`)

The main game screen. This is the big one.

**Mount:**
1. Extract `game_id` from params
2. Verify game exists (`GameServer.game_exists?/1`), redirect to lobby if not
3. Determine player's seat from `current_user.id` matching against GameServer's player list
4. Subscribe to PubSub: `GameServer.subscribe(game_id)`
5. Fetch initial view: `GameServer.get_player_view(game_id, seat)`
6. Assign everything to socket: `game_id`, `seat`, `view` (the player view map), plus any UI state (selected cards for discard, etc.)

**PubSub handling:**
```elixir
def handle_info({:game_state_updated, _game_id}, socket) do
  {:ok, view} = GameServer.get_player_view(socket.assigns.game_id, socket.assigns.seat)
  {:noreply, assign(socket, :view, view)}
end

def handle_info({:hand_completed, _game_id, scoring_result}, socket) do
  # Show scoring overlay
  {:noreply, assign(socket, show_scoring: true, scoring_result: scoring_result)}
end

def handle_info({:new_hand_starting, _game_id}, socket) do
  # Clear scoring overlay, fetch new state
  {:ok, view} = GameServer.get_player_view(socket.assigns.game_id, socket.assigns.seat)
  {:noreply, assign(socket, view: view, show_scoring: false, selected_discards: [])}
end
```

**Event handling (human actions):**

Bidding:
```elixir
def handle_event("bid", %{"action" => "dalje"}, socket)
def handle_event("bid", %{"action" => "bid", "value" => value}, socket)
# Convert string value to action atom/tuple, submit to GameServer
```

Discard:
```elixir
def handle_event("toggle_discard", %{"card" => card_string}, socket)
# Toggle card in selected_discards list. When 2 selected, enable "Confirm" button.
def handle_event("confirm_discard", _, socket)
# Submit {:discard, card1, card2} to GameServer
```

Declare game:
```elixir
def handle_event("declare_game", %{"game" => game_type_string}, socket)
```

Defense:
```elixir
def handle_event("defense", %{"action" => "dodjem"}, socket)
def handle_event("defense", %{"action" => "ne_dodjem"}, socket)
```

Play card:
```elixir
def handle_event("play_card", %{"card" => card_string}, socket)
# Convert card string back to tuple, submit {:play, card} to GameServer
```

**Card string encoding** for phx-click values:
Cards need to be serialized as strings for HTML data attributes. Use `"suit:rank"` format:
- `{:herc, :ace}` → `"herc:ace"`
- Parse back: `String.split(str, ":") |> then(fn [s, r] -> {String.to_existing_atom(s), String.to_existing_atom(r)} end)`

### 3. Table Layout

The game screen is split into two areas:

```
┌──────────────────────────────────┬──────────────┐
│                                  │              │
│          GAME TABLE              │   SCORING    │
│                                  │   SIDEBAR    │
│                                  │              │
│                                  │              │
└──────────────────────────────────┴──────────────┘
```

**Game table area** (left, ~75% width):

```
         ┌─────────────────────────────┐
         │     Opponent Left (seat X)   │
         │     [card backs in arc]      │
         │     Name  ● tricks: N        │
         └─────────────────────────────┘
    ┌──────────────────────────────────────┐
    │                                      │
    │            CENTER AREA               │
    │                                      │
    │    ┌──────────┐   ┌──────────┐       │
    │    │  Talon 1  │   │  Talon 2  │     │    ┌──────────────────┐
    │    └──────────┘   └──────────┘       │    │ Opponent Right    │
    │                                      │    │  (seat Y)        │
    │         ┌──────────┐                 │    │ [card backs]     │
    │         │  Played   │                │    │ Name ● tricks: N │
    │         │  Cards    │                │    └──────────────────┘
    │         └──────────┘                 │
    │                                      │
    └──────────────────────────────────────┘
         ┌─────────────────────────────┐
         │      YOUR HAND (seat 0)      │
         │  [face-up cards, clickable]  │
         │  Name  ● tricks: N           │
         │                              │
         │  [ACTION BUTTONS / PROMPTS]  │
         └─────────────────────────────┘
```

**Seating relative to the human player:**
The human is always at the bottom (seat 0 in single-player mode). The two AI opponents sit at left and right. Which AI goes where depends on counter-clockwise ordering:
- If human is seat 0: left opponent = seat 1, right opponent = seat 2
- The "left" position is the player who plays AFTER you. "Right" is the player who plays BEFORE you. (Counter-clockwise: 0 → 2 → 1, so seat 2 is to your right, seat 1 is to your left.)

Wait — actually in Preferans counter-clockwise order is 0 → 2 → 1. That means:
- Your right = next player after you = seat 2
- Your left = player before you = seat 1

So: **Right opponent = seat 2, Left opponent = seat 1.**

**Center area content changes by phase:**
- `:bid` — Show talon as 2 face-down cards. Show bid history as a scrolling log or speech bubbles.
- `:talon_reveal` — Talon cards flip face-up. Brief pause, auto-transitions.
- `:discard` — Declarer's hand shows 12 cards. Selected cards highlighted. "Confirm discard" button.
- `:declare_game` — Buttons for legal game types.
- `:defense` — Show what game was declared. Buttons for Dodjem/Ne dodjem.
- `:trick_play` — Current trick cards appear in center (positioned by who played them). Previous trick result fades.
- `:scoring` — Scoring summary overlay/card.
- `:hand_over` — Brief summary, then auto-transition to next hand.

### 4. Card Component (`lib/preferans_ui_web/components/card_component.ex`)

A function component for rendering a single playing card. CSS-only for now.

**Props/assigns:**
- `card` — `{suit, rank}` tuple, or `nil` for face-down
- `face` — `:up` or `:down` (override for showing/hiding)
- `clickable` — boolean, adds hover effect and phx-click
- `selected` — boolean, visually raised/highlighted (for discard selection)
- `played_by` — seat number (for positioning in trick area)
- `size` — `:normal` | `:small` (for opponent hands, played cards)

**Face-up card CSS design:**
- White/cream background with rounded corners and subtle border
- Rank + suit symbol in top-left corner and bottom-right (rotated)
- Suit color: red (#C41E3A) for herc/karo, black (#1A1A2E) for pik/tref
- Center area: large suit symbol
- Card dimensions: approximately 70px × 100px for normal, 50px × 72px for small
- Selected state: translate-y -8px, blue glow border
- Clickable state: cursor pointer, subtle scale on hover
- Keep the component structure clean so replacing inner content with SVG images later only touches this one file

**Face-down card:**
- Dark green/navy patterned back (simple CSS pattern — diagonal lines or crosshatch)
- Same dimensions as face-up
- No click handler

**Card back pattern idea (CSS only):**
```css
/* Repeating diamond pattern on card backs */
background-color: #1B4332;
background-image: repeating-linear-gradient(
  45deg,
  transparent,
  transparent 5px,
  rgba(255,255,255,0.05) 5px,
  rgba(255,255,255,0.05) 10px
);
border: 2px solid #2D6A4F;
```

### 5. Phase-Specific Components

Build each phase as a separate function component. GameLive renders the active one based on `view.phase`.

**BiddingPhase component:**
- Shows the human's 10 cards (face-up, NOT clickable during bidding)
- Bidding log in center area — list of who said what:
  ```
  Duško: 2
  Nikola: Dalje
  Your turn...
  ```
- Action buttons below hand (only when `is_my_turn`):
  - "Dalje" button (always available)
  - Number bid buttons: only values > highest_bid. Show as: "2 (Pik)", "3 (Karo)", "4 (Herc)", "5 (Tref)", "6 (Betl)", "7 (Sans)"
  - Disable/hide buttons that aren't in `legal_actions`
- Opponent hands shown as card backs (10 cards each)

**TalonRevealPhase component:**
- Same as bidding layout but talon cards are now face-up in center
- Brief display — the GameServer auto-transitions to discard phase
- Show a label: "Talon" / "Kup" above the revealed cards

**DiscardPhase component (only rendered for declarer):**
- Declarer's hand shows 12 cards (original 10 + 2 from talon)
- Cards are clickable — clicking toggles selection (highlight)
- Track `selected_discards` in socket assigns (list of up to 2 cards)
- When 2 cards selected: show "Baci" (Discard) confirm button
- When fewer than 2 selected: button disabled
- If not the declarer: show waiting message "Declarer is choosing cards to discard..."

**DeclareGamePhase component (only active for declarer):**
- Show the declared game options as buttons
- Each button shows: game name + suit symbol + value
- Only show options in `legal_actions`
- For non-declarer: show waiting message

**DefensePhase component:**
- Show what game was declared: "Duško igra Tref (♣)" in center
- If it's your turn to decide: show "Dolazim" (Dodjem) and "Ne dolazim" (Ne dodjem) buttons
- Show other player's decision if already made
- If not your turn: show waiting message or already-made decision

**TrickPlayPhase component:**
- YOUR HAND at bottom: face-up cards, clickable only when it's your turn
  - Legal cards have normal opacity + pointer cursor
  - Illegal cards (can't play due to follow-suit) are dimmed/grayed + no pointer
  - Determine legal cards from `legal_actions` list: extract the card from each `{:play, card}` tuple
- CURRENT TRICK in center: cards positioned by player (bottom-center for you, top-left for left opponent, top-right for right opponent)
- TRICK COUNT: show per-player tricks won near each player's area
- OPPONENT HANDS: show remaining card backs (count decreases each trick)
- After each trick resolves, show winner briefly, then clear for next trick

**ScoringPhase component:**
- Overlay or prominent card in center showing:
  - Who was declarer, what game
  - Trick distribution: "Duško: 6, You: 2, Nikola: 2"
  - Declarer result: "Passed ✓" or "Failed ✗"
  - Bule changes: "+0 / -10 / +0"
  - Supe earned: "You earned 20 supe against Duško"
  - Defender result if relevant
- Auto-dismisses when new hand starts (`:new_hand_starting` event)

### 6. Scoring Sidebar Component

Persistent right sidebar (~25% width, or 280-320px fixed). Traditional Preferans scoring sheet format.

**Layout:**
```
┌─────────────────────────────┐
│      SCORING SHEET          │
│─────────────────────────────│
│  Supe vs    │ BULE │ Supe vs│
│  Left Opp   │      │ Right  │
│─────────────│──────│────────│
│             │ 100  │        │  ← Starting bule (Player 0 / You)
│             │  94  │        │  ← After first hand
│             │      │        │
│─────────────│──────│────────│
│             │ 100  │        │  ← Player 1 bule
│             │      │        │
│─────────────│──────│────────│
│             │ 100  │        │  ← Player 2 bule
│             │      │        │
│─────────────────────────────│
│  Refes: ▮▯▯  ▯▯▯  ▯▯▯     │
│─────────────────────────────│
│  Hand #3  │  Dealer: Nikola │
└─────────────────────────────┘
```

Actually — the traditional Preferans score sheet has a **single shared layout**, not per-player sections. Let me describe the real format:

The sheet is a large cross/grid dividing space for 3 players. The standard paper layout:

```
┌──────────┬──────────┬──────────┐
│  Player0 │ Player1  │ Player2  │
│  supe    │  supe    │  supe    │
│  against │  against │  against │
│  P1      │  P2      │  P0      │
├──────────┼──────────┼──────────┤
│  P0 BULE │ P1 BULE  │ P2 BULE  │
│  100     │ 100      │ 100      │
│   94     │  90      │ 100      │
│   84     │  90      │  92      │
│  ------  │          │          │  ← kapa line if bule go negative
├──────────┼──────────┼──────────┤
│  Player0 │ Player1  │ Player2  │
│  supe    │  supe    │  supe    │
│  against │  against │  against │
│  P2      │  P0      │  P1      │
├──────────┴──────────┴──────────┤
│  Refes: ▮▮▯  ▯▯▯  ▮▯▯         │
└────────────────────────────────┘
```

Three columns. Each column is one player. The column has:
- **Top section:** Supe this player earned against the player to their LEFT
- **Middle section:** This player's BULE — a running column of numbers counting down
- **Bottom section:** Supe this player earned against the player to their RIGHT
- **Refe row** at the very bottom

For the sidebar, simplify to:

**Three-column scoring grid:**
- Column headers: player names (highlight "You" or use bold)
- Middle rows: bule values, most recent at bottom, scrollable if many hands
- Top/bottom: supe totals against each opponent
- Kapa line drawn across bule column when a player goes negative
- Refe marks shown as filled/empty squares below

This component receives `bule`, `refe_counts`, and the supe ledger from the view. Update it every time the view refreshes.

**Keep it simple for now.** Just show:
- Three columns with player names
- Current bule per player
- Total supe per pairing
- Refe counts
- Hand number + current dealer indicator

The full running-column-of-numbers format can come later when you have hand history. For now, just current values.

### 7. Gettext Strings

All user-visible text goes through gettext. Key strings to translate:

```elixir
# Bidding
gettext("Your turn to bid")
gettext("Pass")                    # Dalje
gettext("Waiting for %{name}...")

# Defense
gettext("I defend")               # Dodjem / Dolazim
gettext("I pass")                 # Ne dodjem / Ne dolazim
gettext("%{name} plays %{game}")

# Trick play
gettext("Your turn to play")
gettext("Waiting for %{name} to play...")

# Scoring
gettext("Passed")
gettext("Failed")
gettext("Tricks: %{count}")

# Game types
gettext("Pik")
gettext("Karo")
gettext("Herc")
gettext("Tref")
gettext("Betl")
gettext("Sans")

# Scoring sheet
gettext("Bule")
gettext("Supe")
gettext("Refes")
gettext("Hand #%{number}")
gettext("Dealer: %{name}")
```

Serbian translations go in `priv/gettext/sr/LC_MESSAGES/default.po`.

For game terms that are the same in Serbian (Betl, Sans, Bule, Supe, Refe), the translation is identical — but still route through gettext so the surrounding UI text is properly translated.

### 8. CSS / Styling Direction

**Overall feel:** Traditional card table. Dark green felt background. Warm, not cold. Think old European card room, not Vegas casino.

**Color palette:**
- Table felt: `#1B4332` (deep forest green) with subtle texture
- Card white: `#FEFCE8` (warm cream, not pure white)
- Card red suits: `#C41E3A` (classic playing card red)
- Card black suits: `#1A1A2E` (soft black)
- UI chrome: `#14532D` (darker green), `#F0FDF4` (light green tint for text)
- Action buttons: `#D97706` (amber/gold) for primary, `#6B7280` (gray) for secondary
- Sidebar background: `#0F2419` (very dark green, distinct from table)

**Typography:**
- Player names / UI: system sans-serif is fine for now
- Card rank/suit: a slightly condensed font works well, but standard is fine
- Scoring sheet: monospace or tabular numbers for alignment

**Table background CSS:**
```css
.game-table {
  background-color: #1B4332;
  background-image: 
    radial-gradient(ellipse at center, rgba(255,255,255,0.03) 0%, transparent 70%);
  /* Subtle light spot in center like overhead lamp */
}
```

### 9. File Structure

Create these files:

```
lib/preferans_ui_web/live/
  lobby_live.ex              # Lobby with New Game button
  game_live.ex               # Main game LiveView
  game_live.html.heex        # Game layout template

lib/preferans_ui_web/components/
  card_component.ex          # Single card rendering (face-up/down)
  game_components.ex         # Phase components + scoring sidebar
    - bidding_phase/1
    - talon_reveal_phase/1
    - discard_phase/1
    - declare_game_phase/1
    - defense_phase/1
    - trick_play_phase/1
    - scoring_phase/1
    - scoring_sidebar/1
    - player_area/1          # Opponent area (name, card backs, tricks)
    - trick_area/1           # Center trick display
    - action_buttons/1       # Generic action button row
```

### 10. Key Implementation Details

**Discard selection state:**
The discard phase needs local UI state — which cards the player has clicked to select. This is NOT in the engine state. Track it in socket assigns:
```elixir
# In mount or when entering discard phase:
assign(socket, selected_discards: MapSet.new())

# Toggle:
def handle_event("toggle_discard", %{"card" => card_str}, socket) do
  card = parse_card(card_str)
  selected = socket.assigns.selected_discards
  selected = if MapSet.member?(selected, card), 
    do: MapSet.delete(selected, card),
    else: if(MapSet.size(selected) < 2, do: MapSet.put(selected, card), else: selected)
  {:noreply, assign(socket, selected_discards: selected)}
end
```

**Legal card highlighting during trick play:**
Extract playable cards from legal_actions:
```elixir
defp playable_cards(legal_actions) do
  legal_actions
  |> Enum.filter(&match?({:play, _}, &1))
  |> Enum.map(fn {:play, card} -> card end)
  |> MapSet.new()
end
```
In the template, each card checks `card in playable_cards` to determine if it gets the clickable/dimmed treatment.

**Phase-based rendering in template:**
```heex
<div class="game-table">
  <%= case @view.phase do %>
    <% :bid -> %>
      <.bidding_phase view={@view} />
    <% :discard -> %>
      <.discard_phase view={@view} selected={@selected_discards} />
    <% :trick_play -> %>
      <.trick_play_phase view={@view} />
    <% ... %>
  <% end %>
  
  <.scoring_sidebar view={@view} />
</div>
```

**Seat-to-position mapping:**
The human is always rendered at bottom. Map opponent seats to left/right positions:
```elixir
defp seat_positions(my_seat) do
  # Counter-clockwise: next player is to your RIGHT on screen
  right = rem(my_seat + 2, 3)
  left = rem(my_seat + 1, 3)
  %{left: left, right: right, bottom: my_seat}
end
```

**Who is current player indicator:**
Show a subtle glow or dot next to the player whose turn it is. During trick play, this rotates rapidly as AI plays. During bidding, it helps the human track whose decision is pending.

**Empty states:**
- Waiting for opponent: show a pulsing dot or "thinking..." indicator near the relevant player
- Between hands: brief "Dealing..." message in center

### 11. What NOT to Build Yet

- No animations or transitions
- No sound effects
- No chat
- No game settings/options during play
- No hand replay
- No AI analysis
- No kontra UI (mock engine skips it)
- No Igra/Moje bidding UI (mock engine skips these)
- No mobile responsive layout (desktop only for now)
- No drag-and-drop for cards (click only)

### 12. Tests

**LiveView tests for GameLive:**
- Mount succeeds with valid game_id, shows cards
- Mount redirects to lobby for invalid game_id
- Bidding: clicking "Dalje" submits action, updates view
- Bidding: only legal bid buttons shown
- Discard: clicking cards toggles selection, max 2
- Discard: confirm button only enabled with 2 selected
- Trick play: only legal cards are clickable
- Trick play: clicking legal card submits action
- PubSub: receiving `:game_state_updated` refreshes the view
- Phase transitions: view updates when phase changes

**Component tests:**
- Card component renders rank and suit correctly
- Card component face-down shows no card info
- Scoring sidebar shows correct bule values
