# Implementation Prompt: GameServer + Mock Engine for Preferans UI

## Context

I'm building a web UI for Serbian Preferans (3-player, 32-card trick-taking card game) using Elixir Phoenix + LiveView. The real game engine is C++ (separate repo, currently training neural network). I need a **mock engine in pure Elixir** to develop the UI against. When the C++ engine's JSON REPL is ready, I'll swap it in — the LiveView layer should not need to change.

## What Already Exists

My Phoenix app has:

1. **Auth** — `mix phx.gen.auth` with LiveView. Users can register/login. Session-based auth.
2. **User schema** — `PreferansUi.Accounts.User` with fields: `username` (unique), `email`, `hashed_password`, `locale` (default "sr"), `rating`/`rating_deviation` (Glicko-2), `games_played`, `games_won`.
3. **Match schema** — `PreferansUi.Game.Match` (UUID primary key) with: `status`, `mode` ("1v2ai", "2v1ai", "3human"), `starting_bule`, `max_refes`, `current_dealer`, `hands_played`, `bule` (array of 3), `refe_counts` (array of 3), `supe_ledger` (flat array of 6), `players` (array of maps with seat/user_id/is_ai/ai_level).
4. **Hand schema** — `PreferansUi.Game.Hand` with: `match_id`, `hand_number`, `dealer`, `deal` (map — initial card distribution), `declarer`, `game_type`, `is_igra`, `winning_bid`, `actions` (array of maps), `scoring` (map).
5. **HandPlayer schema** — `PreferansUi.Game.HandPlayer` linking users to hands with seat, role, scoring.
6. **Game context** — `PreferansUi.Game` with CRUD for matches and hands.
7. **Engine placeholder** — `PreferansUi.Game.Engine` (empty module).
8. **Application supervisor** — includes `Registry` (`:unique`, name `PreferansUi.GameRegistry`), `DynamicSupervisor` (name `PreferansUi.GameSupervisor`), and `Phoenix.PubSub` (name `PreferansUi.PubSub`).
9. **Router** — authenticated routes for `/lobby` (LobbyLive), `/game/:id` (GameLive), `/history` (HistoryLive), `/history/:id` (ReplayLive), `/profile` (ProfileLive). All are stub LiveViews.
10. **i18n** — gettext configured with `sr` and `en` locales.

## What I Need Built

### 1. Card Representation (`PreferansUi.Game.Cards`)

A utility module for the 32-card Preferans deck.

```elixir
# Card representation throughout the Elixir layer.
# Cards are {suit, rank} tuples.
# Suits: :pik, :karo, :herc, :tref
# Ranks: :seven, :eight, :nine, :ten, :jack, :queen, :king, :ace
# Rank ordering: seven < eight < nine < ten < jack < queen < king < ace
```

Functions needed:
- `deck/0` — returns all 32 cards as a list of tuples
- `shuffle/1` — Fisher-Yates shuffle of a card list (use `:rand`)
- `deal/0` — shuffles deck, returns `{[hand0, hand1, hand2], talon}` where each hand is 10 cards and talon is 2. Just split 10/10/10/2 — no need for 5-5-5-2-5-5-5 pattern.
- `sort_hand/1` — sorts a hand by suit (pik, karo, herc, tref) then by rank descending (ace first) within each suit
- `rank_value/1` — returns integer for rank comparison (:seven = 0, :ace = 7)
- `suit_index/1` — returns integer for suit ordering (:pik = 0, :karo = 1, :herc = 2, :tref = 3)
- `card_to_string/1` — display string like "A♠", "K♥", "7♣"
- `game_value/1` — game type atom to scoring value: `:pik` = 2, `:karo` = 3, `:herc` = 4, `:tref` = 5, `:betl` = 6, `:sans` = 7

### 2. Mock Engine (`PreferansUi.Game.MockEngine`)

Pure-function module (no GenServer). Simulates game flow well enough to develop UI.

**State structure** — a map:

```elixir
%{
  phase: atom,            # :bid, :talon_reveal, :discard, :declare_game, 
                          # :defense, :trick_play, :scoring, :hand_over
  hands: [list, list, list],  # 3 lists of {suit, rank} tuples
  talon: [card, card],
  discards: [],               # 2 cards discarded by declarer
  current_player: integer,    # 0, 1, or 2
  dealer: integer,

  # Bidding
  bid_history: [],            # list of %{player: int, action: atom_or_tuple}
  highest_bid: 0,             # 0-7 (0 = no bid yet)
  passes: 0,                  # count of consecutive "dalje" in this bidding
  declarer: nil,              # set when bidding resolves

  # Game declaration
  game_type: nil,             # :pik, :karo, :herc, :tref, :betl, :sans
  is_igra: false,
  
  # Defense
  defenders: [],              # list of seats defending
  defense_responses: %{},     # %{seat => :dodjem | :ne_dodjem}

  # Trick play
  trick_number: 0,            # 0-9
  current_trick: [],          # list of %{player: int, card: tuple} in play order
  trick_leader: nil,
  tricks_won: [0, 0, 0],
  played_cards: [],           # all cards played so far (for inference display)

  # Match context (passed in, tracked here for convenience)
  bule: [100, 100, 100],
  refe_counts: [0, 0, 0],
  max_refes: 2,

  # Scoring result (set in :scoring phase)
  scoring_result: nil
}
```

**Public API:**

```elixir
MockEngine.new_hand(dealer, bule, refe_counts, max_refes) -> state
MockEngine.get_legal_actions(state) -> list of action terms
MockEngine.apply_action(state, action) -> {:ok, new_state} | {:error, reason}
MockEngine.get_player_view(state, seat) -> filtered_view_map
```

**Phase logic (simplified, not real rules):**

**`:bid` phase:**
- First bidder: player to dealer's right = `rem(dealer + 2, 3)` (counter-clockwise seating)
- Players bid in counter-clockwise order: seat 0 → 2 → 1 → 0 → ... (right to left)
- Wait — Preferans goes counter-clockwise, so from first bidder, next is `rem(current + 2, 3)` (the player to the RIGHT of current player)
- Actually, simpler: play order from first bidder is `[first, rem(first+2,3), rem(first+1,3)]` repeating. Just hardcode the rotation.
- Legal actions: `:dalje` (pass), and any bid value higher than `highest_bid` as `{:bid, n}` where n is 2-7
- When a player bids, update `highest_bid` and record in `bid_history`
- When a player passes (`:dalje`), record and increment `passes`
- **Bidding ends when 2 players have passed.** The remaining player is declarer. Or if all 3 pass, go to `:hand_over` with refe recorded.
- Skip Moje privilege entirely. Skip Igra. These can be added later.
- After bidding resolves with a winner: set `declarer`, transition to `:talon_reveal`

**`:talon_reveal` phase:**
- No player action needed. This is an automatic transition.
- Set `talon_revealed: true` on the state.
- Add the 2 talon cards to the declarer's hand (now 12 cards).
- Transition immediately to `:discard`. The current_player is the declarer.

**`:discard` phase:**
- Legal actions: `{:discard, card1, card2}` for all combinations of 2 cards from declarer's 12-card hand. That's C(12,2) = 66 options.
- On action: remove the 2 cards from declarer's hand (back to 10), store in `discards`.
- Transition to `:declare_game`. Current player stays as declarer.

**`:declare_game` phase:**
- Legal actions: game type atoms with value ≥ highest_bid. If highest bid was 2, all six games are legal. If highest bid was 5, only `:tref`, `:betl`, `:sans`.
- On action: set `game_type`. Transition to `:defense`.
- Current player becomes the defender to declarer's right: `rem(declarer + 2, 3)`.

**`:defense` phase:**
- If game_type is `:betl` — skip defense, everyone plays. Set defenders to both non-declarers. Transition to `:trick_play`.
- Otherwise: each non-declarer in order says `:dodjem` or `:ne_dodjem`.
- First responder: player to declarer's right. Second: the other non-declarer.
- Record responses in `defense_responses`.
- After both respond:
  - Both "ne_dodjem" → transition to `:scoring` (free pass for declarer)
  - At least one "dodjem" → set `defenders` list, transition to `:trick_play`
- Skip Poziv (calling) for now. Skip kontra chain for now.

**`:trick_play` phase:**
- First trick leader: first bidder (player to dealer's right) for trump games and betl. For sans, it should be defender to declarer's left, but mock can just use first bidder for all.
- Legal actions for current player: 
  - If leading (first card in trick): any card in hand → `{:play, card}`
  - If following: must follow suit if possible. Filter hand for cards matching the led suit. If none, any card.
  - Skip forced-trump rule. No trump logic at all. Mock just uses follow-suit.
- On action: add card to `current_trick`, remove from player's hand, add to `played_cards`.
- After all active players have played (2 in 2-player, 3 in 3-player):
  - Resolve trick winner: highest rank of the led suit wins. (No trump resolution in mock.)
  - Increment `tricks_won[winner]`.
  - Clear `current_trick`. Set `trick_leader` to winner. Increment `trick_number`.
  - If `trick_number` reaches 10: transition to `:scoring`.
  - Otherwise: set `current_player` to trick winner (they lead next).
- Active players: declarer + all defenders. Skip passive player's cards.

**`:scoring` phase:**
- Calculate simplified scoring:
  - Declarer passed if `tricks_won[declarer] >= 6`
  - If passed: `bule[declarer] -= game_value * 2`. Each defender earns supe: `tricks * game_value * 2` against declarer.
  - If failed: `bule[declarer] += game_value * 2`.
  - If both defenders passed (ne_dodjem): `bule[declarer] -= game_value * 2`, no supe.
  - Defender failed if individual tricks < 2 AND combined defender tricks < 4. Failed defender: `bule += game_value * 2`.
- Store result in `scoring_result`: `%{bule_changes: [...], supe_changes: [...], declarer_passed: bool, tricks: [...]}`
- Transition to `:hand_over`.

**`:hand_over` phase:**
- Terminal state. No more actions.
- The GameServer reads `scoring_result`, updates match-level bule/supe, increments dealer.

**`get_player_view/2` — CRITICAL function:**

Returns a map containing only what the specified seat can see:

```elixir
%{
  phase: state.phase,
  my_seat: seat,
  my_hand: sorted hand for this seat (face-up cards),
  opponent_card_counts: %{other_seat1 => count, other_seat2 => count},
  current_player: state.current_player,
  is_my_turn: state.current_player == seat,
  legal_actions: if current_player == seat, get_legal_actions(state), else [],
  dealer: state.dealer,
  
  # Bidding
  bid_history: state.bid_history,   # always fully visible
  highest_bid: state.highest_bid,
  declarer: state.declarer,
  
  # Talon: nil during bidding, visible after reveal
  talon: if state.phase not in [:bid], do: state.talon, else: nil,
  
  # Discards: only visible to declarer
  discards: if seat == state.declarer, do: state.discards, else: nil,
  
  # Game info
  game_type: state.game_type,
  defense_responses: state.defense_responses,
  defenders: state.defenders,
  
  # Trick play
  trick_number: state.trick_number,
  current_trick: state.current_trick,     # cards on table are visible to all
  tricks_won: state.tricks_won,
  played_cards: state.played_cards,       # all previously played cards visible
  
  # Match context
  bule: state.bule,
  refe_counts: state.refe_counts,
  
  # Scoring (only in :scoring and :hand_over phases)
  scoring_result: if state.phase in [:scoring, :hand_over], do: state.scoring_result, else: nil,
  
  # Player info
  players: [
    %{seat: 0, is_declarer: state.declarer == 0, is_defender: 0 in state.defenders},
    %{seat: 1, is_declarer: state.declarer == 1, is_defender: 1 in state.defenders},
    %{seat: 2, is_declarer: state.declarer == 2, is_defender: 2 in state.defenders}
  ]
}
```

### 3. GameServer (`PreferansUi.Game.GameServer`)

GenServer that manages one active game. Uses MockEngine now, swappable to C++ engine later.

**Init args:**
```elixir
%{
  game_id: uuid_string,
  players: [
    %{seat: 0, user_id: user_id_or_nil, is_ai: false, display_name: "Milenko"},
    %{seat: 1, user_id: nil, is_ai: true, ai_level: "heuristic", display_name: "Bot Duško"},
    %{seat: 2, user_id: nil, is_ai: true, ai_level: "heuristic", display_name: "Bot Nikola"}
  ],
  starting_bule: 100,
  max_refes: 2
}
```

**State:**
```elixir
%{
  game_id: string,
  players: list,          # from init, immutable
  engine_state: map,      # current MockEngine state
  match_bule: [100,100,100],
  match_refe_counts: [0,0,0],
  match_supe_ledger: %{},  # %{{from, to} => total_supe}
  hands_played: 0,
  current_dealer: 0,
  match_id: uuid           # for persistence
}
```

**Registration:** Use `{:via, Registry, {PreferansUi.GameRegistry, game_id}}`.

**Start under DynamicSupervisor:**
```elixir
DynamicSupervisor.start_child(PreferansUi.GameSupervisor, {GameServer, init_arg})
```

**Public API:**
```elixir
GameServer.get_player_view(game_id, seat) -> {:ok, view_map} | {:error, :not_found}
GameServer.submit_action(game_id, seat, action) -> :ok | {:error, reason}
GameServer.subscribe(game_id) -> :ok
GameServer.game_exists?(game_id) -> boolean
```

**Message handling:**

`handle_call({:get_player_view, seat}, ...)`
- Call `MockEngine.get_player_view(engine_state, seat)`
- Merge in player display names from `state.players`
- Return the view

`handle_call({:submit_action, seat, action}, ...)`
- Validate: is it this player's turn? `engine_state.current_player == seat`
- Validate: is this player human? Check `players[seat].is_ai == false`
- Validate: is the action in the legal actions list?
- Call `MockEngine.apply_action(engine_state, action)`
- On `{:ok, new_engine_state}`:
  - Update `engine_state`
  - Broadcast `{:game_state_updated, game_id}` via PubSub
  - Check if hand is over (phase == :hand_over) → handle hand completion
  - Check if next player is AI → schedule AI turn
  - Reply `:ok`
- On `{:error, reason}`: reply `{:error, reason}`

**AI turn flow:**
```elixir
# After any action, check if next player is AI
defp maybe_schedule_ai_turn(state) do
  seat = state.engine_state.current_player
  player = Enum.find(state.players, &(&1.seat == seat))
  
  if player && player.is_ai && state.engine_state.phase not in [:hand_over, :scoring] do
    Process.send_after(self(), {:ai_turn, seat}, ai_delay(state))
  end
end

# AI "thinking" delay — shorter for trivial phases, longer for trick play
defp ai_delay(state) do
  case state.engine_state.phase do
    :bid -> Enum.random(600..1200)
    :defense -> Enum.random(800..1500)
    :trick_play -> Enum.random(500..1000)
    _ -> 500
  end
end
```

`handle_info({:ai_turn, seat}, state)`
- Verify it's still this AI's turn (state might have changed)
- Pick an action: for mock, just pick randomly from legal actions. Or use simple heuristics:
  - Bidding: 70% dalje, 20% bid lowest legal, 10% bid one higher
  - Defense: 60% dodjem, 40% ne_dodjem
  - Trick play: play random legal card (or lowest card — slightly smarter)
  - Discard: random 2 cards
  - Declare game: pick the game matching highest_bid value
- Apply action via MockEngine
- Broadcast update
- Check for next AI turn (chain them)

**Hand completion:**
When `engine_state.phase == :hand_over`:
1. Read `scoring_result` from engine state
2. Update `match_bule` with bule changes
3. Update `match_supe_ledger` with supe changes
4. Increment `hands_played`
5. Rotate dealer: `current_dealer = rem(current_dealer + 1, 3)` (or +2 for counter-clockwise — check your convention)
6. Persist the hand to database (create Hand + HandPlayer records) — can be async via `Task.start`
7. Broadcast `{:hand_completed, game_id, scoring_result}`
8. After a delay (3-5 seconds for humans to read the score), start next hand:
   `Process.send_after(self(), :deal_next_hand, 4000)`

**Match end check:**
After updating bule: if `Enum.sum(match_bule) <= 0`, the match is over.
Broadcast `{:match_ended, game_id, final_scores}`. Update Match record in DB.

**PubSub topic:** `"game:#{game_id}"`

**Broadcast events:**
- `{:game_state_updated, game_id}` — generic "re-fetch your view" signal
- `{:action_played, game_id, seat, action}` — for animation (e.g., "seat 1 played K♥")
- `{:hand_completed, game_id, scoring_result}` — show scoring overlay
- `{:match_ended, game_id, final_scores}` — game over screen
- `{:new_hand_starting, game_id}` — clear table, deal animation

### 4. Game Context Updates (`PreferansUi.Game`)

Add these functions to the existing Game context:

```elixir
# Start a new single-player game (human seat 0, AI seats 1+2)
def start_solo_game(user_id, opts \\ []) -> {:ok, game_id} | {:error, reason}

# Find an active game for a user
def find_user_active_game(user_id) -> game_id | nil

# Persist a completed hand
def persist_hand(match_id, hand_number, engine_state, scoring_result, players) -> {:ok, Hand.t()}
```

`start_solo_game` should:
1. Create a Match record in DB (status: "active", mode: "1v2ai")
2. Start a GameServer via DynamicSupervisor with the match config
3. Return `{:ok, game_id}` where game_id = match.id

### 5. Bidding Turn Order Detail

Counter-clockwise seating means player order goes: 0 → 2 → 1 → 0 → 2 → 1 ...

The "next player" function:
```elixir
def next_player(current, active_players) do
  # Counter-clockwise: 0 -> 2 -> 1 -> 0
  next = rem(current + 2, 3)
  if next in active_players, do: next, else: next_player(next, active_players)
end
```

For trick play, active_players = [declarer | defenders].
For bidding, active_players = all who haven't passed yet.

### 6. Tests

Write tests for:

**Cards module:**
- `deck/0` returns 32 unique cards
- `deal/0` returns 3 hands of 10 + talon of 2, all 32 cards accounted for
- `sort_hand/1` sorts by suit then rank descending
- `rank_value/1` ordering is correct
- `game_value/1` returns correct values

**MockEngine:**
- `new_hand/4` produces valid initial state in `:bid` phase
- Bidding: 3 passes → hand_over
- Bidding: one player bids 2, others pass → declarer set, phase transitions
- Discard: removes 2 cards from 12-card hand, stores discards
- Trick play: 10 tricks complete → scoring phase
- Follow suit enforced: player with led suit must play it
- Player view: opponent cards never exposed, talon hidden during bid, discards hidden from non-declarer

**GameServer:**
- Starts and registers correctly
- Rejects actions from wrong player
- AI turns fire automatically after human action
- PubSub broadcasts on state changes
- Full hand cycles through all phases to completion
- New hand starts after scoring delay

## Important Notes

- **No JavaScript.** Everything is LiveView server-rendered. Card clicks are `phx-click` events. Animations will come later via CSS transitions and minimal JS hooks — not now.
- **The mock engine is temporary.** Don't over-engineer it. It needs to produce the right *shape* of data for the UI, not enforce correct Preferans rules. When the C++ engine is ready, MockEngine gets replaced and nothing else changes.
- **Player view filtering is the contract.** The map returned by `get_player_view` is the interface between backend and frontend. Get its shape right. The LiveView will be built entirely against this view map.
- **Serbian card names in UI, English in code.** All atoms/keys are English. Display strings use gettext for i18n. Card display uses Unicode suit symbols (♠♦♥♣).
- **Counter-clockwise is the seating order.** Players sit 0-1-2 counter-clockwise. "Next player" means the player to your RIGHT, which is `rem(current + 2, 3)`.
