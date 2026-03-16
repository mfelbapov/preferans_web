# Preferans Mock Engine — Rule-by-Rule Implementation Guide

## READ THIS FIRST

This document specifies EXACTLY how to implement each rule of the Preferans mock engine.
Every rule has: the logic as pseudocode, concrete card examples, and expected outcomes.
Do NOT paraphrase or interpret. Implement EXACTLY what is written here.

The mock engine is pure functions. No GenServer. No side effects.
Input: state map + action → Output: new state map.

---

## PART 1: CARD BASICS

### 1.1 The Deck

32 cards total. 4 suits × 8 ranks.

**Suits (in order):** `:pik` (♠), `:karo` (♦), `:herc` (♥), `:tref` (♣)
**Ranks (low to high):** `:seven`, `:eight`, `:nine`, `:ten`, `:jack`, `:queen`, `:king`, `:ace`

A card is a tuple: `{suit, rank}`. Example: `{:herc, :ace}` = Ace of Hearts.

**Rank comparison:** `:ace` > `:king` > `:queen` > `:jack` > `:ten` > `:nine` > `:eight` > `:seven`

Use this rank value map:
```
:seven = 0
:eight = 1
:nine  = 2
:ten   = 3
:jack  = 4
:queen = 5
:king  = 6
:ace   = 7
```

**Card A beats Card B (same suit)** if `rank_value(A) > rank_value(B)`.

### 1.2 Dealing

Shuffle all 32 cards. Split:
- Cards 0-9 → Player 0's hand (10 cards)
- Cards 10-19 → Player 1's hand (10 cards)
- Cards 20-29 → Player 2's hand (10 cards)
- Cards 30-31 → Talon (2 cards)

Sort each hand by suit order (pik first, tref last), then by rank descending within suit.

**Sort key for a card:** `{suit_index(suit), -rank_value(rank)}`
where `suit_index(:pik) = 0, :karo = 1, :herc = 2, :tref = 3`

Example sorted hand:
```
A♠ K♠ 10♠ | A♦ Q♦ 7♦ | K♥ J♥ | 9♣ 7♣
(pik first, descending) (karo) (herc) (tref)
```

---

## PART 2: PLAYER ORDER

### 2.1 Three Players in a Circle

Players: 0, 1, 2 seated counter-clockwise.

```
        1
       / \
      /   \
     2 --- 0
```

Play goes counter-clockwise: 0 → 2 → 1 → 0 → 2 → 1 ...

### 2.2 Next Player Function

```
next_player_in_circle(current):
    if current == 0: return 2
    if current == 1: return 0
    if current == 2: return 1
```

Or mathematically: `rem(current + 2, 3)`

**TEST THIS:**
- `next_player(0)` = 2 ✓
- `next_player(2)` = 1 ✓
- `next_player(1)` = 0 ✓

### 2.3 First Bidder

The first bidder is the player to the dealer's RIGHT in counter-clockwise seating.

```
first_bidder(dealer):
    rem(dealer + 2, 3)
```

**TEST THIS:**
- Dealer = 0 → First bidder = 2
- Dealer = 1 → First bidder = 0
- Dealer = 2 → First bidder = 1

### 2.4 Next Active Player

During bidding, some players have passed. Skip them:

```
next_active_player(current, passed_players):
    candidate = next_player_in_circle(current)
    if candidate not in passed_players: return candidate
    
    candidate = next_player_in_circle(candidate)
    if candidate not in passed_players: return candidate
    
    # All others passed — should not happen if called correctly
    return nil
```

---

## PART 3: BIDDING PHASE

### 3.1 Overview

Players take turns bidding. A bid is a number 2-7. Higher bids beat lower bids. You can bid or pass ("dalje"). Once you pass, you're out permanently. Bidding ends when 2 players have passed.

### 3.2 Initial Bidding State

```elixir
%{
  phase: :bid,
  current_player: first_bidder(dealer),   # player to dealer's right
  dealer: dealer,
  bid_history: [],          # list of %{player: int, action: atom_or_tuple}
  highest_bid: 0,           # 0 means no bid yet
  highest_bidder: nil,      # who holds the current highest bid
  passed_players: [],       # players who said dalje (permanently out)
  moje_holder: first_bidder(dealer),  # first bidder starts with Moje privilege
  # ... other state fields
}
```

### 3.3 Legal Bid Actions

For the current player, legal actions are:

```
legal_bid_actions(state):
    actions = [:dalje]    # can always pass
    
    # Number bids: any value strictly greater than highest_bid
    for value in 2..7:
        if value > state.highest_bid:
            actions = actions ++ [{:bid, value}]
    
    # Moje: ONLY if current player is the moje_holder AND there is a highest bid
    if state.current_player == state.moje_holder AND state.highest_bid > 0:
        actions = actions ++ [:moje]
    
    return actions
```

**Example 1:** highest_bid = 0 (no bids yet)
→ Legal: [:dalje, {:bid, 2}, {:bid, 3}, {:bid, 4}, {:bid, 5}, {:bid, 6}, {:bid, 7}]

**Example 2:** highest_bid = 3
→ Legal: [:dalje, {:bid, 4}, {:bid, 5}, {:bid, 6}, {:bid, 7}]
Plus :moje if you're the moje_holder.

**Example 3:** highest_bid = 7
→ Legal: [:dalje] only (nothing higher than 7).
Plus :moje if you're the moje_holder.

### 3.4 Applying a Bid Action

**Action: `:dalje` (pass)**

```
apply_dalje(state):
    new_state = state
    new_state.bid_history = state.bid_history ++ [%{player: state.current_player, action: :dalje}]
    new_state.passed_players = state.passed_players ++ [state.current_player]
    
    # Transfer Moje privilege if the moje_holder is passing
    if state.current_player == state.moje_holder:
        # Moje transfers to the next player in circle who hasn't passed
        next = next_player_in_circle(state.current_player)
        if next not in new_state.passed_players:
            new_state.moje_holder = next
        else:
            new_state.moje_holder = nil   # nobody left to hold it
    
    # Check if bidding is over (2 players passed)
    if length(new_state.passed_players) == 2:
        return resolve_bidding(new_state)
    
    if length(new_state.passed_players) == 3:
        # All three passed — no game played
        return all_pass(new_state)
    
    # Move to next active player
    new_state.current_player = next_active_player(state.current_player, new_state.passed_players)
    return new_state
```

**Action: `{:bid, value}` (number bid)**

```
apply_bid(state, value):
    # value MUST be > state.highest_bid
    new_state = state
    new_state.bid_history = state.bid_history ++ [%{player: state.current_player, action: {:bid, value}}]
    new_state.highest_bid = value
    new_state.highest_bidder = state.current_player
    
    # Move to next active player
    new_state.current_player = next_active_player(state.current_player, state.passed_players)
    return new_state
```

**Action: `:moje` (match current highest bid)**

```
apply_moje(state):
    # current player MUST be moje_holder
    # This effectively claims the current highest_bid
    new_state = state
    new_state.bid_history = state.bid_history ++ [%{player: state.current_player, action: {:moje, state.highest_bid}}]
    new_state.highest_bidder = state.current_player   # moje_holder takes over the bid
    # highest_bid stays the same — moje matches, doesn't raise
    
    # Move to next active player
    new_state.current_player = next_active_player(state.current_player, state.passed_players)
    return new_state
```

### 3.5 Bidding Resolution

When 2 players have passed, the remaining player wins the bid.

```
resolve_bidding(state):
    # Find the player NOT in passed_players
    winner = Enum.find([0, 1, 2], fn p -> p not in state.passed_players end)
    
    new_state = state
    new_state.declarer = winner
    
    if state.highest_bid == 0:
        # Winner never actually bid a number (others passed immediately)
        # This shouldn't happen in normal play but handle it:
        # The winner must still see the talon and declare
        new_state.highest_bid = 2   # minimum bid
    
    new_state.phase = :talon_reveal
    return new_state
```

### 3.6 All Three Pass

```
all_pass(state):
    new_state = state
    new_state.phase = :hand_over
    new_state.scoring_result = %{
        all_passed: true,
        bule_changes: [0, 0, 0],
        supe_changes: %{},
        record_refe: should_record_refe(state)
    }
    return new_state
```

### 3.7 Refe Check

```
should_record_refe(state):
    # No refe if any player is under kapa (negative bule)
    if Enum.any?(state.bule, fn b -> b < 0 end): return false
    
    # No refe if all players at max refes
    if Enum.all?(state.refe_counts, fn r -> r >= state.max_refes end): return false
    
    return true
```

### 3.8 Complete Bidding Example — Walk Through

```
Dealer = 0. First bidder = 2. Moje holder = 2.

Players: 0 (dealer), 1, 2 (first bidder, has Moje)
Turn order from first bidder: 2 → 1 → 0 → 2 → 1 → 0 ...

--- State: highest_bid=0, passed=[], moje_holder=2 ---

Turn 1: Player 2 (current_player=2)
  Legal: [:dalje, {:bid,2}, {:bid,3}, {:bid,4}, {:bid,5}, {:bid,6}, {:bid,7}, :moje]
  Wait — :moje requires highest_bid > 0. highest_bid = 0. So NO :moje.
  Legal: [:dalje, {:bid,2}, {:bid,3}, {:bid,4}, {:bid,5}, {:bid,6}, {:bid,7}]
  Player 2 picks: {:bid, 2}
  → highest_bid=2, highest_bidder=2, current_player=1

Turn 2: Player 1 (current_player=1)
  Legal: [:dalje, {:bid,3}, {:bid,4}, {:bid,5}, {:bid,6}, {:bid,7}]
  (No :moje — player 1 is not moje_holder)
  Player 1 picks: {:bid, 3}
  → highest_bid=3, highest_bidder=1, current_player=0

Turn 3: Player 0 (current_player=0)
  Legal: [:dalje, {:bid,4}, {:bid,5}, {:bid,6}, {:bid,7}]
  Player 0 picks: :dalje
  → passed=[0], current_player=2
  (Player 0 passed. Moje holder is still 2.)

Turn 4: Player 2 (current_player=2)
  Legal: [:dalje, {:bid,4}, {:bid,5}, {:bid,6}, {:bid,7}, :moje]
  (:moje IS available — player 2 is moje_holder and highest_bid=3 > 0)
  Player 2 picks: :moje
  → highest_bidder=2 (takes over), highest_bid stays 3, current_player=1

Turn 5: Player 1 (current_player=1)
  Legal: [:dalje, {:bid,4}, {:bid,5}, {:bid,6}, {:bid,7}]
  Player 1 picks: :dalje
  → passed=[0, 1]. TWO players passed. Bidding over.

Resolution: Player 2 wins the bid at value 3.
  declarer = 2, highest_bid = 3
  Phase transitions to :talon_reveal
```

### 3.9 Bidding Example — Moje Transfer

```
Dealer = 1. First bidder = 0. Moje holder = 0.

Turn 1: Player 0 (has Moje)
  Player 0 picks: :dalje
  → passed=[0], moje_holder transfers to next non-passed player = 2
  → current_player=2

Turn 2: Player 2 (now has Moje)
  Player 2 picks: {:bid, 2}
  → highest_bid=2, highest_bidder=2, current_player=1
  (Skip player 0 — they passed)

Turn 3: Player 1
  Player 1 picks: {:bid, 3}
  → highest_bid=3, highest_bidder=1, current_player=2

Turn 4: Player 2 (has Moje)
  Legal includes :moje (player 2 is moje_holder, highest_bid > 0)
  Player 2 picks: :moje
  → highest_bidder=2, highest_bid stays 3, current_player=1

Turn 5: Player 1
  Player 1 picks: :dalje
  → passed=[0, 1]. TWO passed. Bidding over.

Resolution: Player 2 wins at value 3.
```

### 3.10 Bidding Example — All Pass

```
Dealer = 0. First bidder = 2.

Turn 1: Player 2 picks: :dalje → passed=[2]
Turn 2: Player 1 picks: :dalje → passed=[2, 1]
  Wait — only 2 passed so far. But player 0 hasn't spoken.
  Actually: after player 2 passes, next active is player 1.
  After player 1 passes, passed=[2,1]. That's 2 passed.
  
  Remaining player is 0. They win the bid.
  But wait — highest_bid is still 0 because nobody bid.
  
  Resolution: Player 0 wins by default with minimum bid 2.
  
ALTERNATIVE — true all-pass:

Turn 1: Player 2 picks: :dalje → passed=[2], next active = 1
Turn 2: Player 1 picks: :dalje → passed=[2,1]. 2 passed. 
  Player 0 is the remaining player and wins automatically.
  They didn't pass — they just never got a chance to bid.
  
For TRUE all-pass (all 3 say dalje):
  This only happens if the remaining player (after 2 pass) also passes.
  But once 2 pass, bidding ends. The remaining player WINS.
  
  So "all three pass" requires:
  Turn 1: Player 2 picks: :dalje → passed=[2], next=1
  Turn 2: Player 1 picks: :dalje → passed=[2,1].
    Now only player 0 remains. Bidding should end with player 0 as winner.
    
  WAIT. Re-reading the rules:
  "Bidding ends when two players have passed."
  "All three pass ("Dalje" × 3): The hand is not played."
  
  So there IS a scenario where all 3 pass. How?
  
  The FIRST player can pass, then the second, and then the third.
  All three speak in order and all say dalje.
  
  Turn 1: Player 2: :dalje → passed=[2], next=1
  Turn 2: Player 1: :dalje → passed=[2,1], next=0
    Two have passed. But player 0 hasn't spoken yet.
    
  CLARIFICATION: "Bidding ends when two players have passed" means
  when there's only one player left who hasn't passed. That player wins.
  
  If the FIRST player passes, second passes — third wins without bidding.
  
  For all-three-pass: it only happens when the third player (the last one)
  ALSO passes. But the rules say bidding ends when two pass...
  
  RE-READING RULES SPEC Section 4.5:
  "Bidding ends when two players have passed."
  "All three pass ("Dalje" × 3): The hand is not played."
  
  RESOLUTION: 
  If after two passes, the remaining player has NOT yet bid anything 
  (highest_bid == 0), they can ALSO pass, making it all-three-pass.
  If the remaining player HAS bid something, bidding ends and they win.

  So the logic is:
  When 2 have passed:
    if highest_bid == 0:
      The remaining player gets one turn. They can bid or pass.
      If they pass → all-three-pass → hand over, refe recorded.
      If they bid → they win with that bid value.
    else:
      The remaining player wins with the current highest_bid.
```

**CORRECTED resolve logic:**

```
after_pass_check(state):
    if length(state.passed_players) < 2:
        # Normal — advance to next player
        state.current_player = next_active_player(state.current_player, state.passed_players)
        return state
    
    if length(state.passed_players) == 2:
        remaining = find_remaining_player(state.passed_players)
        
        if state.highest_bid > 0:
            # Someone bid. Remaining player wins.
            return resolve_bidding_winner(state, remaining)
        else:
            # Nobody bid yet. Give remaining player a chance.
            state.current_player = remaining
            return state
            # If they also pass, length becomes 3 → all_pass
    
    if length(state.passed_players) == 3:
        return all_pass(state)
```

### 3.11 Bidding — Final Pseudocode

```
apply_bid_action(state, action):
    case action:
        :dalje ->
            state = add_to_history(state, state.current_player, :dalje)
            state = add_to_passed(state, state.current_player)
            state = maybe_transfer_moje(state, state.current_player)
            state = after_pass_check(state)
            return state
        
        {:bid, value} ->
            assert value > state.highest_bid
            state = add_to_history(state, state.current_player, {:bid, value})
            state = %{state | highest_bid: value, highest_bidder: state.current_player}
            state = advance_to_next_active(state)
            return state
        
        :moje ->
            assert state.current_player == state.moje_holder
            assert state.highest_bid > 0
            state = add_to_history(state, state.current_player, {:moje, state.highest_bid})
            state = %{state | highest_bidder: state.current_player}
            state = advance_to_next_active(state)
            return state
```

---

## PART 4: TALON REVEAL

### 4.1 What Happens

The talon (2 cards) is turned face-up. ALL players see both talon cards.
The declarer takes both talon cards into their hand (now 12 cards).

This phase has NO player action. It's an automatic transition.

### 4.2 Implementation

```
enter_talon_reveal(state):
    # Reveal talon to all
    state = %{state | talon_revealed: true}
    
    # Add talon cards to declarer's hand
    declarer = state.declarer
    declarer_hand = state.hands[declarer] ++ state.talon
    state = put_in(state, [:hands, declarer], declarer_hand)
    
    # Declarer now has 12 cards. Phase moves to discard.
    state = %{state | phase: :discard, current_player: declarer}
    return state
```

### 4.3 Example

```
Before talon reveal:
  Player 2 (declarer) hand: [A♠, K♠, Q♦, J♦, 10♥, 9♥, 8♥, K♣, Q♣, 7♣]  (10 cards)
  Talon: [A♥, 7♦]
  
After talon reveal:
  Player 2 hand: [A♠, K♠, Q♦, J♦, 7♦, A♥, 10♥, 9♥, 8♥, K♣, Q♣, 7♣]  (12 cards, re-sorted)
  Talon: [A♥, 7♦]  (still stored — all players remember what was in it)
  talon_revealed: true
  Phase: :discard
  current_player: 2
```

---

## PART 5: DISCARD

### 5.1 What Happens

The declarer (holding 12 cards) must discard exactly 2 cards face-down.
The discards are removed from play. Only the declarer knows what was discarded.

### 5.2 Legal Actions

```
legal_discard_actions(state):
    hand = state.hands[state.declarer]
    # All combinations of 2 cards from the 12-card hand
    actions = for i <- 0..(length(hand)-2), j <- (i+1)..(length(hand)-1) do
        {:discard, Enum.at(hand, i), Enum.at(hand, j)}
    end
    return actions
    # This produces C(12,2) = 66 actions
```

### 5.3 Applying Discard

```
apply_discard(state, card1, card2):
    declarer = state.declarer
    hand = state.hands[declarer]
    
    # Verify both cards are in hand
    assert card1 in hand
    assert card2 in hand
    assert card1 != card2
    
    # Remove both cards from hand
    new_hand = hand -- [card1, card2]
    # Now 10 cards
    
    # Sort the hand again
    new_hand = sort_hand(new_hand)
    
    state = put_in(state, [:hands, declarer], new_hand)
    state = %{state | discards: [card1, card2]}
    state = %{state | phase: :declare_game, current_player: declarer}
    return state
```

### 5.4 Example

```
Declarer (player 2) has 12 cards: [A♠, K♠, Q♦, J♦, 7♦, A♥, 10♥, 9♥, 8♥, K♣, Q♣, 7♣]
Declarer discards: 7♦ and 7♣

After discard:
  Hand: [A♠, K♠, Q♦, J♦, A♥, 10♥, 9♥, 8♥, K♣, Q♣]  (10 cards)
  Discards: [7♦, 7♣]  (stored, known only to declarer)
  Phase: :declare_game
```

---

## PART 6: GAME DECLARATION

### 6.1 What Happens

The declarer announces which game they will play. The game must have a value >= the winning bid value.

### 6.2 Game Values

```
:pik  = 2
:karo = 3
:herc = 4
:tref = 5
:betl = 6
:sans = 7
```

### 6.3 Legal Actions

```
legal_declare_actions(state):
    min_value = state.highest_bid
    actions = []
    if 2 >= min_value: actions = actions ++ [{:declare, :pik}]
    if 3 >= min_value: actions = actions ++ [{:declare, :karo}]
    if 4 >= min_value: actions = actions ++ [{:declare, :herc}]
    if 5 >= min_value: actions = actions ++ [{:declare, :tref}]
    if 6 >= min_value: actions = actions ++ [{:declare, :betl}]
    if 7 >= min_value: actions = actions ++ [{:declare, :sans}]
    return actions
```

**Example:** highest_bid = 4 → Legal: [{:declare, :herc}, {:declare, :tref}, {:declare, :betl}, {:declare, :sans}]

**Example:** highest_bid = 2 → Legal: all six games

### 6.4 Applying Declaration

```
apply_declare(state, game_type):
    value = game_value(game_type)
    assert value >= state.highest_bid
    
    state = %{state | game_type: game_type, game_value: value}
    
    # Determine trump suit
    state = %{state | trump: trump_for_game(game_type)}
    
    # Move to defense phase
    # First defender to speak: player to declarer's RIGHT
    first_defender = next_player_in_circle(state.declarer)
    
    if game_type == :betl:
        # Betl: mandatory defense, skip defense decision
        defenders = [0, 1, 2] -- [state.declarer]
        state = %{state | 
            defenders: defenders,
            defense_responses: %{},
            phase: :trick_play
        }
        state = set_first_trick_leader(state)
        return state
    
    state = %{state | phase: :defense, current_player: first_defender}
    return state
```

### 6.5 Trump Determination

```
trump_for_game(game_type):
    case game_type:
        :pik  -> :pik
        :karo -> :karo
        :herc -> :herc
        :tref -> :tref
        :betl -> nil    # no trump
        :sans -> nil    # no trump
```

---

## PART 7: DEFENSE DECISIONS

### 7.1 What Happens

Each non-declarer player decides: "Dodjem" (I defend) or "Ne dodjem" (I pass).
The player to the declarer's RIGHT speaks first. Then the other.

### 7.2 Legal Actions

```
legal_defense_actions(state):
    [:dodjem, :ne_dodjem]
```

### 7.3 Applying Defense Decision

```
apply_defense(state, action):
    player = state.current_player
    
    state = put_in(state, [:defense_responses, player], action)
    state = add_to_history(state, player, action)
    
    # Find the other non-declarer who hasn't responded yet
    non_declarers = [0, 1, 2] -- [state.declarer]
    responded = Map.keys(state.defense_responses)
    remaining = non_declarers -- responded
    
    if remaining != []:
        # Other defender still needs to respond
        state = %{state | current_player: hd(remaining)}
        return state
    
    # Both have responded. Determine what happens.
    responses = state.defense_responses
    defenders_in = for {seat, resp} <- responses, resp == :dodjem, do: seat
    
    case length(defenders_in):
        0 ->
            # Both passed. Free pass for declarer.
            state = score_free_pass(state)
            return state
        
        _ ->
            # At least one defends
            state = %{state | defenders: defenders_in}
            state = %{state | phase: :trick_play}
            state = set_first_trick_leader(state)
            return state
```

### 7.4 Defense Decision Order — Concrete Example

```
Declarer = 1. Non-declarers = [0, 2].
Player to declarer's right = next_player_in_circle(1) = 0.

Step 1: current_player = 0. Player 0 says :dodjem or :ne_dodjem.
Step 2: current_player = 2. Player 2 says :dodjem or :ne_dodjem.
Then resolve.
```

```
Declarer = 0. Non-declarers = [1, 2].
Player to declarer's right = next_player_in_circle(0) = 2.

Step 1: current_player = 2. Player 2 decides.
Step 2: current_player = 1. Player 1 decides.
```

### 7.5 Free Pass (Both Defenders Pass)

```
score_free_pass(state):
    gv = state.game_value
    bule_change = gv * 2   # times refe multiplier if applicable
    
    refe_mult = if has_active_refe(state, state.declarer), do: 2, else: 1
    bule_change = bule_change * refe_mult
    
    bule_changes = [0, 0, 0]
    bule_changes = put_at(bule_changes, state.declarer, -bule_change)  # negative = good
    
    state = %{state |
        phase: :hand_over,
        scoring_result: %{
            declarer_passed: true,
            free_pass: true,
            tricks: [0, 0, 0],
            bule_changes: bule_changes,
            supe_changes: %{},
            game_type: state.game_type,
            game_value: state.game_value
        }
    }
    return state
```

---

## PART 8: TRICK PLAY

This is the most complex part. Read carefully.

### 8.1 Who Leads First Trick

```
set_first_trick_leader(state):
    case state.game_type:
        :sans ->
            # Left defender leads. Left = the player who plays BEFORE declarer
            # in counter-clockwise order. That's next_player(declarer).
            # Wait — "left" in Preferans means to declarer's LEFT when seated.
            # In counter-clockwise play: left of declarer = the player AFTER declarer.
            # Actually: RULES_SPEC says "defender to the declarer's LEFT always leads"
            # The player to your LEFT in counter-clockwise seating is the one 
            # who plays just BEFORE you (since play goes right-to-left).
            # left_of(X) = rem(X + 1, 3)
            
            left_defender = rem(state.declarer + 1, 3)
            
            # Verify this player is actually defending
            if left_defender in state.defenders:
                state = %{state | trick_leader: left_defender, current_player: left_defender}
            else:
                # Fallback: first active player
                state = %{state | trick_leader: first_active_player(state)}
            
        _ ->
            # Trump games and Betl: first bidder leads
            # First bidder = player to dealer's right = rem(dealer + 2, 3)
            leader = rem(state.dealer + 2, 3)
            
            # If leader is not active (passive), find next active player
            active = get_active_players(state)
            if leader not in active:
                leader = next_active_in_order(leader, active)
            
            state = %{state | trick_leader: leader, current_player: leader}
    
    return state
```

### 8.2 Active Players

```
get_active_players(state):
    [state.declarer | state.defenders] |> Enum.sort()
```

For 2-player hands (one defender), this is [declarer, defender] — 2 players.
For 3-player hands (both defend), this is [declarer, def1, def2] — 3 players.

### 8.3 Play Order Within a Trick

Starting from the trick leader, go counter-clockwise, but ONLY include active players.

```
trick_play_order(leader, active_players):
    order = [leader]
    next = next_player_in_circle(leader)
    
    while length(order) < length(active_players):
        if next in active_players:
            order = order ++ [next]
        next = next_player_in_circle(next)
    
    return order
```

**Example — 3 players active, leader = 0:**
Order: [0, 2, 1] (counter-clockwise: 0 → 2 → 1)

**Example — 2 players active [0, 2], leader = 0:**
Order: [0, 2] (skip player 1 who is passive)

**Example — 3 players active, leader = 2:**
Order: [2, 1, 0]

### 8.4 Legal Card Plays

**When LEADING (first card in trick):** Any card in your hand is legal.

```
legal_plays_leading(hand):
    for card <- hand, do: {:play, card}
```

**When FOLLOWING in a TRUMP game (pik/karo/herc/tref):**

```
legal_plays_following_trump(hand, led_suit, trump_suit):
    # Step 1: Must follow suit if possible
    same_suit = Enum.filter(hand, fn {suit, _rank} -> suit == led_suit end)
    if same_suit != []:
        return for card <- same_suit, do: {:play, card}
    
    # Step 2: If void in led suit, MUST play trump if you have any
    trumps = Enum.filter(hand, fn {suit, _rank} -> suit == trump_suit end)
    if trumps != []:
        return for card <- trumps, do: {:play, card}
    
    # Step 3: Void in both led suit and trump — play anything
    return for card <- hand, do: {:play, card}
```

**When FOLLOWING in Betl or Sans (no trump):**

```
legal_plays_following_no_trump(hand, led_suit):
    # Step 1: Must follow suit if possible
    same_suit = Enum.filter(hand, fn {suit, _rank} -> suit == led_suit end)
    if same_suit != []:
        return for card <- same_suit, do: {:play, card}
    
    # Step 2: Void in led suit — play anything (no forced trump)
    return for card <- hand, do: {:play, card}
```

### 8.5 CRITICAL EXAMPLES — Follow Suit and Forced Trump

**Example 1: Must follow suit**
```
Game: TREF (♣ is trump)
Leader plays: A♠ (Ace of Spades)
Your hand: [K♠, 9♠, A♥, 10♥, 7♣]

You HAVE spades (K♠, 9♠). You MUST play a spade.
Legal: [{:play, {pik, king}}, {:play, {pik, nine}}]
NOT legal: any heart or club.
```

**Example 2: Void in led suit, must trump**
```
Game: TREF (♣ is trump)
Leader plays: A♠
Your hand: [A♥, 10♥, 9♦, 7♣, 8♣]

You have NO spades. You HAVE trumps (7♣, 8♣). You MUST play a trump.
Legal: [{:play, {tref, seven}}, {:play, {tref, eight}}]
NOT legal: any heart or diamond.
```

**Example 3: Void in led suit AND trump — play anything**
```
Game: TREF (♣ is trump)  
Leader plays: A♠
Your hand: [A♥, 10♥, 9♦, Q♦, J♦]

You have NO spades and NO trumps (clubs). Play anything.
Legal: all 5 cards.
```

**Example 4: Betl — no forced trump**
```
Game: BETL (no trump)
Leader plays: A♠
Your hand: [A♥, 10♥, 7♣]

You have NO spades. In Betl there is NO forced trump. Play anything.
Legal: [{:play, {herc, ace}}, {:play, {herc, ten}}, {:play, {tref, seven}}]
```

**Example 5: Sans — no forced trump**
```
Game: SANS (no trump)
Leader plays: K♦
Your hand: [Q♦, 7♠, A♣]

You HAVE diamonds (Q♦). Must follow suit.
Legal: [{:play, {karo, queen}}] only.
```

### 8.6 Applying a Card Play

```
apply_play_card(state, card):
    player = state.current_player
    
    # Remove card from player's hand
    new_hand = state.hands[player] -- [card]
    state = put_in(state, [:hands, player], new_hand)
    
    # Add to current trick
    state = update_in(state, [:current_trick], fn trick ->
        trick ++ [%{player: player, card: card}]
    end)
    
    # Add to played_cards (public record)
    state = update_in(state, [:played_cards], fn pc -> pc ++ [card] end)
    
    # Track cards played by this player (for inference)
    state = update_in(state, [:played_by, player], fn pb -> pb ++ [card] end)
    
    # Is the trick complete?
    active_count = length(get_active_players(state))
    if length(state.current_trick) == active_count:
        # Trick complete — resolve it
        state = resolve_trick(state)
    else:
        # More cards needed — advance to next player in trick
        play_order = trick_play_order(state.trick_leader, get_active_players(state))
        current_idx = Enum.find_index(play_order, fn p -> p == player end)
        next_in_trick = Enum.at(play_order, current_idx + 1)
        state = %{state | current_player: next_in_trick}
    
    return state
```

### 8.7 Trick Resolution — Who Wins

```
resolve_trick(state):
    trick = state.current_trick
    trump = state.trump   # nil for betl/sans
    
    # First card determines the led suit
    led_card = hd(trick).card
    led_suit = elem(led_card, 0)
    
    # Start with first player as winner
    winner = hd(trick)
    
    for play <- tl(trick):
        card = play.card
        winner_card = winner.card
        
        if beats?(card, winner_card, led_suit, trump):
            winner = play
    
    # Update tricks won
    state = update_in(state, [:tricks_won, winner.player], fn t -> t + 1 end)
    
    # Clear current trick
    state = %{state | 
        current_trick: [],
        trick_number: state.trick_number + 1,
        trick_leader: winner.player,
        current_player: winner.player
    }
    
    # Check if all tricks played
    if state.trick_number >= 10:
        state = %{state | phase: :scoring}
        state = calculate_scoring(state)
    
    return state
```

### 8.8 Card Beats Card — The Key Function

```
beats?(challenger, current_winner, led_suit, trump):
    c_suit = elem(challenger, 0)
    c_rank = rank_value(elem(challenger, 1))
    w_suit = elem(current_winner, 0)
    w_rank = rank_value(elem(current_winner, 1))
    
    cond:
        # Same suit as current winner — higher rank wins
        c_suit == w_suit and c_rank > w_rank ->
            true
        
        # Challenger is trump, current winner is NOT trump — trump wins
        trump != nil and c_suit == trump and w_suit != trump ->
            true
        
        # Both trump — higher rank wins (already covered by first case since suits match)
        # This case is handled by c_suit == w_suit above.
        
        # Everything else — challenger doesn't beat current winner
        true ->
            false
```

**CRITICAL: A card that doesn't follow the led suit and isn't trump NEVER wins.** Even if it's an Ace. Only cards of the led suit or trump cards can win.

### 8.9 Trick Resolution Examples

**Example 1: Simple — all follow suit**
```
Game: HERC (♥ trump). Led suit: ♠
  Player 0 leads: K♠
  Player 2 plays: A♠
  Player 1 plays: 9♠

Winner: Player 2 (A♠ beats K♠ — same suit, higher rank)
```

**Example 2: Trump beats high card**
```
Game: HERC (♥ trump). Led suit: ♠
  Player 0 leads: A♠ (highest spade!)
  Player 2 plays: 7♥ (lowest trump — has no spades, forced to trump)
  Player 1 plays: K♠

Winner: Player 2 (7♥). ANY trump beats ANY non-trump.
```

**Example 3: Higher trump beats lower trump**
```
Game: TREF (♣ trump). Led suit: ♠
  Player 1 leads: Q♠
  Player 0 plays: 8♣ (trump — void in spades)
  Player 2 plays: J♣ (trump — void in spades)

Winner: Player 2 (J♣ beats 8♣ — both trump, J > 8)
```

**Example 4: Off-suit card loses**
```
Game: HERC (♥ trump). Led suit: ♠
  Player 0 leads: 10♠
  Player 2 plays: A♦ (void in spades, void in trump, plays off-suit)
  Player 1 plays: 7♠

Winner: Player 0 (10♠). A♦ is neither led suit nor trump — it can't win.
7♠ follows suit but 10 > 7. Player 0 wins with 10♠.
```

**Example 5: Betl — no trump, only led suit wins**
```
Game: BETL (no trump). Led suit: ♦
  Player 0 leads: K♦
  Player 2 plays: A♣ (void in diamonds — plays anything)
  Player 1 plays: 7♦

Winner: Player 0 (K♦). A♣ doesn't follow suit and there's no trump.
7♦ follows suit but K > 7. Player 0 wins.
```

### 8.10 Two-Player Trick Play

When only one defender says "dodjem", only 2 players are active.

```
Active: [declarer, defender]. 10 tricks of 2 cards each.
Trick play order: leader, then the other player.
Everything else is identical — same follow suit rules, same resolution.
```

---

## PART 9: SCORING

### 9.1 After 10 Tricks — Who Passed, Who Failed

**Declarer:**
- PASSED if tricks_won[declarer] >= 6
- FAILED if tricks_won[declarer] < 6

**Betl special case:**
- Declarer PASSED if tricks_won[declarer] == 0 (took NO tricks)
- Declarer FAILED if tricks_won[declarer] > 0 (took ANY trick)

**Defenders (when both defend, no kontra, no caller):**
Each defender individually:
- PASSED if tricks_won[defender] >= 2 OR (tricks_won[def_a] + tricks_won[def_b]) >= 4
- FAILED if tricks_won[defender] < 2 AND (tricks_won[def_a] + tricks_won[def_b]) < 4

**Defenders (solo defender):**
- PASSED if tricks_won[defender] >= 2
- FAILED if tricks_won[defender] < 2

### 9.2 Pass/Fail Examples

```
Tricks: Declarer=6, DefA=3, DefB=1. Combined defense=4.
→ Declarer: PASSED (6 >= 6)
→ DefA: PASSED (3 >= 2)
→ DefB: PASSED (combined 4 >= 4, even though individual 1 < 2)
```

```
Tricks: Declarer=7, DefA=2, DefB=1. Combined defense=3.
→ Declarer: PASSED (7 >= 6)
→ DefA: PASSED (2 >= 2, individual threshold met)
→ DefB: FAILED (individual 1 < 2 AND combined 3 < 4)
```

```
Tricks: Declarer=8, DefA=1, DefB=1. Combined defense=2.
→ Declarer: PASSED (8 >= 6)
→ DefA: FAILED (1 < 2, combined 2 < 4)
→ DefB: FAILED (1 < 2, combined 2 < 4)
```

```
Tricks: Declarer=6, DefA=4, DefB=0. Combined defense=4.
→ Declarer: PASSED
→ DefA: PASSED (4 >= 2)
→ DefB: PASSED (combined 4 >= 4!)
  Yes — DefB took ZERO tricks but still passed because combined threshold met.
```

```
Tricks: Declarer=5, DefA=3, DefB=2.
→ Declarer: FAILED (5 < 6)
→ DefA: PASSED (3 >= 2)
→ DefB: PASSED (2 >= 2)
```

### 9.3 Bule Changes

```
calculate_bule_changes(state):
    gv = state.game_value
    base = gv * 2
    
    # Multipliers
    kontra_mult = kontra_multiplier(state.kontra_level)   # 1, 2, 4, 8, or 16
    refe_mult = if has_active_refe(state, state.declarer), do: 2, else: 1
    total_mult = kontra_mult * refe_mult
    
    change = base * total_mult
    bule_changes = [0, 0, 0]
    
    # Declarer
    if declarer_passed(state):
        bule_changes[state.declarer] = -change    # negative = bule go DOWN (good)
    else:
        bule_changes[state.declarer] = +change     # positive = bule go UP (bad)
    
    # Defenders
    for defender in state.defenders:
        if defender_failed(state, defender):
            bule_changes[defender] = +change       # failed defender's bule go UP
        # Passing defenders: bule unchanged (stay 0)
    
    return bule_changes
```

### 9.4 Supe Changes

```
calculate_supe_changes(state):
    gv = state.game_value
    kontra_mult = kontra_multiplier(state.kontra_level)
    refe_mult = if has_active_refe(state, state.declarer), do: 2, else: 1
    total_mult = kontra_mult * refe_mult
    
    supe = %{}
    
    if state.game_type == :betl and not declarer_passed(state):
        # Betl FAILURE: fixed supe, not trick-based
        fixed = 60 * total_mult   # 60 for standard betl
        for defender in state.defenders:
            supe = Map.put(supe, {defender, state.declarer}, fixed)
        return supe
    
    # Normal supe: tricks × game_value × 2 × multipliers
    for defender in state.defenders:
        tricks = state.tricks_won[defender]
        amount = tricks * gv * 2 * total_mult
        if amount > 0:
            supe = Map.put(supe, {defender, state.declarer}, amount)
    
    return supe
```

**Supe key `{from, against}`:** `{defender_seat, declarer_seat}` means "defender writes `amount` supe against the declarer."

### 9.5 Supe Examples

```
Game: TREF (value 5). No kontra, no refe.
Declarer=0, tricks: [6, 3, 1]

Defender 1: 3 × 5 × 2 = 30 supe against player 0
Defender 2: 1 × 5 × 2 = 10 supe against player 0

supe = %{{1, 0} => 30, {2, 0} => 10}
```

```
Game: HERC (value 4). Kontra (×2). Declarer has refe (×2). Total ×4.
Declarer=1, tricks: [2, 5, 3]  → declarer took 5, FAILED

Bule: declarer bule change = +(4 × 2 × 4) = +32

Supe: defender 0: 2 × 4 × 2 × 4 = 64 against player 1
      defender 2: 3 × 4 × 2 × 4 = 96 against player 1

supe = %{{0, 1} => 64, {2, 1} => 96}
```

```
Game: BETL (value 6). No kontra, no refe.
Declarer=2, tricks: [3, 5, 2]  → declarer took 2, FAILED betl

Bule: declarer bule change = +(6 × 2) = +12

Supe: FIXED 60 per defender (not trick-based!)
Defender 0: 60 against player 2
Defender 1: 60 against player 2

supe = %{{0, 2} => 60, {1, 2} => 60}
```

### 9.6 Full Scoring Function

```
calculate_scoring(state):
    bule_changes = calculate_bule_changes(state)
    supe_changes = calculate_supe_changes(state)
    
    state = %{state |
        phase: :hand_over,
        scoring_result: %{
            declarer_passed: declarer_passed(state),
            free_pass: false,
            tricks: state.tricks_won,
            bule_changes: bule_changes,
            supe_changes: supe_changes,
            game_type: state.game_type,
            game_value: state.game_value
        }
    }
    return state
```

### 9.7 Kontra Multiplier

```
kontra_multiplier(level):
    case level:
        0 -> 1      # no kontra
        1 -> 2      # kontra
        2 -> 4      # rekontra
        3 -> 8      # subkontra
        4 -> 16     # mortkontra
```

### 9.8 Refe Check for Declarer

```
has_active_refe(state, player):
    state.refe_counts[player] > 0
```

---

## PART 10: PLAYER VIEW — INFORMATION HIDING

### 10.1 What Each Player Can See

This function is called to build the view sent to a specific player. It must NEVER leak hidden information.

```
get_player_view(state, seat):
    active_players = get_active_players(state)
    
    %{
        phase: state.phase,
        my_seat: seat,
        
        # MY cards: always visible to me
        my_hand: sort_hand(state.hands[seat]),
        
        # Opponent cards: ONLY the count, NEVER the actual cards
        opponent_card_counts: for p <- [0,1,2], p != seat, into: %{} do
            {p, length(state.hands[p])}
        end,
        
        current_player: state.current_player,
        is_my_turn: state.current_player == seat,
        
        # Legal actions: ONLY if it's my turn
        legal_actions: if state.current_player == seat do
            get_legal_actions(state)
        else
            []
        end,
        
        dealer: state.dealer,
        
        # Bidding: always fully visible
        bid_history: state.bid_history,
        highest_bid: state.highest_bid,
        
        # Declarer: visible once determined
        declarer: state.declarer,
        
        # Talon: HIDDEN during bidding. Visible after reveal. NEVER visible during Igra.
        talon: cond do
            state.phase == :bid -> nil
            state.is_igra -> nil
            state.talon_revealed -> state.talon
            true -> nil
        end,
        
        # Discards: ONLY visible to the declarer
        discards: if seat == state.declarer, do: state.discards, else: nil,
        
        # Game info
        game_type: state.game_type,
        defense_responses: state.defense_responses,
        defenders: state.defenders,
        
        # Trick play
        trick_number: state.trick_number,
        current_trick: state.current_trick,
        tricks_won: state.tricks_won,
        played_cards: state.played_cards,
        
        # Match context
        bule: state.bule,
        refe_counts: state.refe_counts,
        
        # Scoring: only visible in scoring/hand_over phases
        scoring_result: if state.phase in [:scoring, :hand_over] do
            state.scoring_result
        else
            nil
        end,
        
        # Player metadata
        players: for p <- [0,1,2] do
            %{
                seat: p,
                is_declarer: state.declarer == p,
                is_defender: p in (state.defenders || []),
                is_active: p in active_players
            }
        end
    }
```

### 10.2 NEVER LEAK THESE

- `state.hands[other_player]` — NEVER include other players' actual cards
- `state.discards` when `seat != declarer` — NEVER show what declarer discarded
- `state.talon` during `:bid` phase — NOBODY sees the talon during bidding
- `state.talon` during Igra — NOBODY EVER sees the talon

---

## PART 11: FULL STATE MACHINE

### 11.1 Phase Transitions

```
apply_action(state, action):
    case state.phase:
        :bid ->
            apply_bid_action(state, action)
            # May transition to: :talon_reveal (bid winner found)
            #                    :hand_over (all pass)
        
        :talon_reveal ->
            # NO player action. Auto-transition.
            enter_talon_reveal(state)
            # Transitions to: :discard
        
        :discard ->
            apply_discard(state, action)
            # Transitions to: :declare_game
        
        :declare_game ->
            apply_declare(state, action)
            # Transitions to: :defense (normal games)
            #                 :trick_play (betl — auto-defend)
        
        :defense ->
            apply_defense(state, action)
            # Transitions to: :trick_play (at least one defends)
            #                 :hand_over (both pass — free pass)
        
        :trick_play ->
            apply_play_card(state, action)
            # Stays in :trick_play until 10 tricks done
            # Then transitions to: :scoring → :hand_over
```

### 11.2 The Talon Reveal Auto-Transition

The `:talon_reveal` phase has no player action. When the phase becomes `:talon_reveal`, the engine should immediately process it and move to `:discard`.

Option A: Do it inside `resolve_bidding_winner`:
```
resolve_bidding_winner(state, winner):
    state = %{state | declarer: winner}
    # Skip talon_reveal as a separate phase — do it inline
    state = %{state | talon_revealed: true}
    declarer_hand = state.hands[winner] ++ state.talon
    state = put_in(state, [:hands, winner], sort_hand(declarer_hand))
    state = %{state | phase: :discard, current_player: winner}
    return state
```

Option B: Make `apply_action` handle it:
```
apply_action(state, action):
    if state.phase == :talon_reveal:
        return enter_talon_reveal(state)   # auto, ignores action
    ...
```

**Use Option A.** It's simpler. The UI can check for `talon_revealed: true` to know to show the talon cards.

---

## PART 12: COMPLETE HAND WALKTHROUGH

Here is a FULL example hand from deal to scoring. Every step.

```
=== SETUP ===
Dealer: 0
First bidder: rem(0+2, 3) = 2
Moje holder: 2

After dealing:
  Player 0: [A♠, K♠, 10♠, A♦, Q♦, 7♦, K♥, J♥, 9♣, 7♣]
  Player 1: [Q♠, 9♠, 8♠, K♦, J♦, 10♦, 8♦, A♣, Q♣, J♣]
  Player 2: [J♠, 7♠, 9♦, A♥, Q♥, 10♥, 9♥, 8♥, 10♣, 8♣]
  Talon: [7♥, K♣]

=== BIDDING ===
Phase: :bid, current_player: 2

Turn 1: Player 2 bids {:bid, 2}
  → highest_bid=2, highest_bidder=2, current_player=1

Turn 2: Player 1 bids :dalje
  → passed=[1], current_player=0

Turn 3: Player 0 bids {:bid, 3}
  → highest_bid=3, highest_bidder=0, current_player=2

Turn 4: Player 2 uses :moje (player 2 is moje_holder, highest_bid=3 > 0)
  → highest_bidder=2, highest_bid=3, current_player=0
  (skip player 1 who passed)

Turn 5: Player 0 bids :dalje
  → passed=[1, 0]. TWO passed. Bidding over.

Winner: Player 2, bid value 3.

=== TALON REVEAL + DISCARD SETUP ===
Talon [7♥, K♣] revealed to all players.
Player 2's hand becomes 12 cards:
  [J♠, 7♠, 9♦, A♥, Q♥, 10♥, 9♥, 8♥, 7♥, K♣, 10♣, 8♣]
  (sorted: pik first, then karo, herc, tref)

Phase: :discard, current_player: 2

=== DISCARD ===
Player 2 discards: 7♠ and 9♦  (action: {:discard, {pik, seven}, {karo, nine}})
Player 2's hand now 10 cards:
  [J♠, A♥, Q♥, 10♥, 9♥, 8♥, 7♥, K♣, 10♣, 8♣]

Discards stored: [{pik, seven}, {karo, nine}] — only player 2 knows these.

Phase: :declare_game, current_player: 2

=== GAME DECLARATION ===
highest_bid was 3. Legal declarations: 
  [{:declare, :karo}, {:declare, :herc}, {:declare, :tref}, {:declare, :betl}, {:declare, :sans}]
  (NOT :pik because pik value 2 < bid value 3)

Player 2 declares: {:declare, :herc}
  → game_type: :herc, trump: :herc, game_value: 4

Phase: :defense

=== DEFENSE ===
Declarer is player 2.
First defender to speak: next_player_in_circle(2) = 1
Second defender: player 0

Player 1 (current_player=1): :dodjem → defense_responses: %{1 => :dodjem}
Player 0 (current_player=0): :dodjem → defense_responses: %{0 => :dodjem, 1 => :dodjem}

Both defend. Defenders: [0, 1].
Active players: [0, 1, 2].

Phase: :trick_play

=== FIRST TRICK LEADER ===
Game is herc (trump), not sans.
First leader = first bidder = rem(dealer+2, 3) = rem(0+2, 3) = 2.
Player 2 is active. Player 2 leads.

=== TRICK 1 ===
Leader: Player 2
Play order: [2, 1, 0]  (counter-clockwise from 2)

Player 2 leads: A♥ (trump ace — strongest card)
  Led suit: :herc

Player 1's hand: [Q♠, 9♠, 8♠, K♦, J♦, 10♦, 8♦, A♣, Q♣, J♣]
  Has herc? NO. Must play trump? herc IS trump and they're void in it.
  Wait — led suit is herc which IS trump. They must follow suit (play herc).
  They have no herc. So: void in led suit. Must play trump if they have it.
  But led suit IS trump and they don't have it. So they're void in trump.
  → Play anything.
  Player 1 plays: 8♠

Player 0's hand: [A♠, K♠, 10♠, A♦, Q♦, 7♦, K♥, J♥, 9♣, 7♣]
  Has herc? YES (K♥, J♥). Must follow suit.
  Legal: [{:play, {herc, king}}, {:play, {herc, jack}}]
  Player 0 plays: K♥

Trick resolution:
  A♥ (herc, ace, rank 7) — leader, current winner
  8♠ (pik, eight, rank 1) — not herc, not trump (wait, herc IS trump, 8♠ is not trump) → doesn't beat
  K♥ (herc, king, rank 6) — same suit as winner (herc), but rank 6 < rank 7 → doesn't beat

Winner: Player 2 (A♥). tricks_won: [0, 0, 1]

=== TRICK 2 ===
Leader: Player 2 (won trick 1)
Play order: [2, 1, 0]

Player 2 leads: Q♥
  Led suit: :herc

Player 1: no herc. Void in led suit. Led suit IS trump. No trump cards. Play anything.
  Player 1 plays: Q♣

Player 0: has J♥ (herc). Must follow suit.
  Player 0 plays: J♥

Trick: Q♥ vs Q♣ vs J♥
  Q♥ (herc, queen=5) — winner
  Q♣ (tref, queen=5) — not herc/not trump → no
  J♥ (herc, jack=4) — same suit, rank 4 < 5 → no

Winner: Player 2. tricks_won: [0, 0, 2]

... (tricks 3-10 continue similarly) ...

=== SCORING (after all 10 tricks) ===
Suppose final tricks_won: [3, 1, 6]

Declarer (player 2): 6 tricks → PASSED (>= 6)

Defenders check:
  Player 0: 3 tricks (>= 2 individually → PASSED)
  Player 1: 1 trick. Individual < 2. Combined: 3+1=4 >= 4 → PASSED

Bule changes:
  game_value = 4 (herc), no kontra, no refe
  base = 4 × 2 = 8
  Declarer (player 2): -8 (bule decrease, good)
  Defenders: 0 (both passed)
  bule_changes: [0, 0, -8]

Supe changes:
  Player 0: 3 × 4 × 2 = 24 supe against player 2 → {0, 2} => 24
  Player 1: 1 × 4 × 2 = 8 supe against player 2  → {1, 2} => 8

Scoring result:
  %{
    declarer_passed: true,
    tricks: [3, 1, 6],
    bule_changes: [0, 0, -8],
    supe_changes: %{{0, 2} => 24, {1, 2} => 8},
    game_type: :herc,
    game_value: 4
  }
```

---

## PART 13: TESTS TO WRITE

For EVERY rule above, write at least one test. Here are the specific test cases:

### Player Order Tests
```
test "next_player 0 -> 2" 
test "next_player 2 -> 1"
test "next_player 1 -> 0"
test "first_bidder when dealer=0 is 2"
test "first_bidder when dealer=1 is 0"
test "first_bidder when dealer=2 is 1"
```

### Bidding Tests
```
test "legal bids when no bids yet — all values 2-7 plus dalje"
test "legal bids when highest is 3 — only 4,5,6,7 plus dalje"
test "legal bids when highest is 7 — only dalje"
test "moje only available to moje_holder"
test "moje not available when highest_bid is 0"
test "bid raises highest_bid and sets highest_bidder"
test "dalje adds player to passed list"
test "moje transfers highest_bidder without raising bid"
test "moje_holder transfers on pass"
test "bidding ends when 2 pass — remaining player wins"
test "all three pass — hand over with refe"
test "bidding order is counter-clockwise"
```

### Talon + Discard Tests
```
test "talon cards added to declarer hand — now 12 cards"
test "discard removes 2 cards — back to 10"
test "discards stored in state"
test "all 32 cards accounted for after discard (10+10+10+2 discards)"
```

### Declaration Tests
```
test "can declare any game >= bid value"
test "cannot declare game below bid value"
test "bid 2 can declare anything"
test "bid 5 can only declare tref, betl, sans"
```

### Defense Tests
```
test "first defender is to declarer's right"
test "both pass — free pass scored"
test "one defends — trick play begins with 2 active"
test "both defend — trick play begins with 3 active"
test "betl — auto defend, skip defense phase"
```

### Trick Play Tests
```
test "leading — any card legal"
test "following suit — must play same suit if have it"
test "void in led suit with trump — must play trump"
test "void in led suit without trump — play anything"
test "betl — void in led suit — play anything (no forced trump)"
test "highest card of led suit wins (no trump in play)"
test "trump beats non-trump"
test "higher trump beats lower trump"
test "off-suit non-trump never wins"
test "10 tricks complete — phase becomes scoring"
test "trick winner leads next trick"
test "2-player hand — 10 tricks of 2 cards"
test "3-player hand — 10 tricks of 3 cards"
```

### Scoring Tests
```
test "declarer passes with 6+ tricks"
test "declarer fails with 5 or fewer tricks"
test "betl declarer passes with 0 tricks"
test "betl declarer fails with any tricks"
test "defender passes with 2+ individual tricks"
test "defender passes with 4+ combined even if individual < 2"
test "defender fails with < 2 individual AND < 4 combined"
test "bule decrease for passing declarer"
test "bule increase for failing declarer"
test "bule increase for failing defender"
test "supe = tricks × game_value × 2"
test "betl failure supe = fixed 60 per defender"
test "free pass — no supe written"
test "all pass — refe recorded when appropriate"
test "refe not recorded when any player under kapa"
```

### Information Hiding Tests
```
test "player view never contains other players' cards"
test "player view shows opponent card counts"
test "talon hidden during bidding phase"
test "talon visible after reveal"
test "discards visible only to declarer"
test "discards nil for non-declarer"
test "legal_actions empty when not your turn"
test "scoring_result nil before scoring phase"
```
