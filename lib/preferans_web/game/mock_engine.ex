defmodule PreferansWeb.Game.MockEngine do
  @moduledoc """
  Pure-function mock engine for Preferans game flow.
  Temporary module for UI development — will be replaced by C++ engine.

  Implements rules exactly as specified in PROMPT_RULES_IMPLEMENTATION.md.
  Input: state map + action → Output: new state map.
  """

  alias PreferansWeb.Game.Cards

  ## Public API

  def new_hand(dealer, bule, refe_counts, max_refes) do
    {hands, talon} = Cards.deal()
    hands = Enum.map(hands, &Cards.sort_hand/1)
    first = first_bidder(dealer)

    %{
      phase: :bid,
      hands: hands,
      talon: talon,
      talon_revealed: false,
      discards: [],
      current_player: first,
      dealer: dealer,
      bid_history: [],
      highest_bid: 0,
      highest_bidder: nil,
      passed_players: [],
      moje_holder: first,
      declarer: nil,
      game_type: nil,
      game_value: nil,
      trump: nil,
      is_igra: false,
      defenders: [],
      defense_responses: %{},
      trick_number: 0,
      current_trick: [],
      trick_leader: nil,
      trick_winner: nil,
      tricks_won: [0, 0, 0],
      played_cards: [],
      played_by: %{0 => [], 1 => [], 2 => []},
      bule: bule,
      refe_counts: refe_counts,
      max_refes: max_refes,
      kontra_level: 0,
      scoring_result: nil
    }
  end

  def get_legal_actions(state) do
    case state.phase do
      :bid -> bid_actions(state)
      :discard -> discard_actions(state)
      :declare_game -> declare_game_actions(state)
      :defense -> [:dodjem, :ne_dodjem]
      :trick_play -> trick_play_actions(state)
      :trick_result -> [:next_trick]
      _ -> []
    end
  end

  def apply_action(state, action) do
    # Normalize discard actions — MapSet.to_list may return cards in either order
    action = normalize_action(state, action)
    legal = get_legal_actions(state)

    if action in legal do
      {:ok, do_apply_action(state, action)}
    else
      {:error, :illegal_action}
    end
  end

  defp normalize_action(%{phase: :discard} = state, {:discard, card1, card2}) do
    hand = Enum.at(state.hands, state.declarer)
    idx1 = Enum.find_index(hand, &(&1 == card1))
    idx2 = Enum.find_index(hand, &(&1 == card2))

    if idx1 != nil and idx2 != nil and idx1 > idx2 do
      {:discard, card2, card1}
    else
      {:discard, card1, card2}
    end
  end

  defp normalize_action(_state, action), do: action

  def get_player_view(state, seat) do
    active_players = get_active_players(state)
    is_my_turn = state.current_player == seat

    %{
      phase: state.phase,
      my_seat: seat,
      my_hand: Cards.sort_hand(Enum.at(state.hands, seat)),
      opponent_card_counts:
        for(s <- [0, 1, 2], s != seat, into: %{}, do: {s, length(Enum.at(state.hands, s))}),
      current_player: state.current_player,
      is_my_turn: is_my_turn,
      legal_actions: if(is_my_turn, do: get_legal_actions(state), else: []),
      dealer: state.dealer,
      bid_history: state.bid_history,
      highest_bid: state.highest_bid,
      declarer: state.declarer,
      talon: talon_for_view(state),
      discards: if(seat == state.declarer, do: state.discards, else: nil),
      game_type: state.game_type,
      defense_responses: state.defense_responses,
      defenders: state.defenders,
      trick_number: state.trick_number,
      current_trick: state.current_trick,
      trick_winner: state.trick_winner,
      tricks_won: state.tricks_won,
      played_cards: state.played_cards,
      bule: state.bule,
      refe_counts: state.refe_counts,
      scoring_result:
        if(state.phase in [:scoring, :hand_over], do: state.scoring_result, else: nil),
      players:
        for s <- [0, 1, 2] do
          %{
            seat: s,
            is_declarer: state.declarer == s,
            is_defender: s in (state.defenders || []),
            is_active: s in active_players
          }
        end
    }
  end

  defp talon_for_view(state) do
    cond do
      state.phase == :bid -> nil
      state.is_igra -> nil
      state.talon_revealed -> state.talon
      true -> nil
    end
  end

  ## Player order helpers

  defp next_player_in_circle(current), do: rem(current + 2, 3)

  defp first_bidder(dealer), do: rem(dealer + 2, 3)

  defp next_active_player(current, passed_players) do
    candidate = next_player_in_circle(current)

    cond do
      candidate not in passed_players ->
        candidate

      true ->
        candidate2 = next_player_in_circle(candidate)
        if candidate2 not in passed_players, do: candidate2, else: nil
    end
  end

  ## Action dispatch

  defp do_apply_action(%{phase: :bid} = state, :dalje) do
    current = state.current_player
    passed = state.passed_players ++ [current]

    state = %{
      state
      | bid_history: state.bid_history ++ [%{player: current, action: :dalje}],
        passed_players: passed
    }

    # Transfer moje if the passer is the moje_holder
    state =
      if current == state.moje_holder do
        next = next_player_in_circle(current)

        if next not in passed do
          %{state | moje_holder: next}
        else
          %{state | moje_holder: nil}
        end
      else
        state
      end

    after_pass_check(state)
  end

  defp do_apply_action(%{phase: :bid} = state, {:bid, value}) do
    state = %{
      state
      | bid_history:
          state.bid_history ++ [%{player: state.current_player, action: {:bid, value}}],
        highest_bid: value,
        highest_bidder: state.current_player
    }

    # If 2 have already passed, bidder wins immediately
    if length(state.passed_players) == 2 do
      resolve_bidding_winner(state, state.current_player)
    else
      %{state | current_player: next_active_player(state.current_player, state.passed_players)}
    end
  end

  defp do_apply_action(%{phase: :bid} = state, :moje) do
    state = %{
      state
      | bid_history:
          state.bid_history ++
            [%{player: state.current_player, action: {:moje, state.highest_bid}}],
        highest_bidder: state.current_player
    }

    if length(state.passed_players) == 2 do
      resolve_bidding_winner(state, state.current_player)
    else
      %{state | current_player: next_active_player(state.current_player, state.passed_players)}
    end
  end

  defp do_apply_action(%{phase: :discard} = state, {:discard, card1, card2}) do
    hand =
      Enum.at(state.hands, state.declarer)
      |> List.delete(card1)
      |> List.delete(card2)
      |> Cards.sort_hand()

    hands = List.replace_at(state.hands, state.declarer, hand)

    %{
      state
      | phase: :declare_game,
        hands: hands,
        discards: [card1, card2],
        current_player: state.declarer
    }
  end

  defp do_apply_action(%{phase: :declare_game} = state, {:declare, game_type}) do
    gv = Cards.game_value(game_type)
    trump = trump_for_game(game_type)
    non_declarers = Enum.reject([0, 1, 2], &(&1 == state.declarer))

    state = %{state | game_type: game_type, game_value: gv, trump: trump}

    if game_type == :betl do
      # Betl: mandatory defense, skip defense phase
      leader = first_bidder(state.dealer)
      active = [state.declarer | non_declarers] |> Enum.sort()
      leader = ensure_active_leader(leader, active)

      %{
        state
        | phase: :trick_play,
          defenders: non_declarers,
          trick_leader: leader,
          current_player: leader
      }
    else
      first_defender = next_player_in_circle(state.declarer)
      %{state | phase: :defense, current_player: first_defender, defenders: []}
    end
  end

  defp do_apply_action(%{phase: :defense} = state, action)
       when action in [:dodjem, :ne_dodjem] do
    seat = state.current_player
    responses = Map.put(state.defense_responses, seat, action)

    defenders =
      if action == :dodjem, do: state.defenders ++ [seat], else: state.defenders

    non_declarers = Enum.reject([0, 1, 2], &(&1 == state.declarer))
    state = %{state | defense_responses: responses, defenders: defenders}

    if map_size(responses) == 2 do
      if defenders == [] do
        # Both ne_dodjem — free pass
        score_free_pass(state)
      else
        state = %{state | defenders: defenders}
        set_first_trick_leader(state)
      end
    else
      remaining = Enum.reject(non_declarers, &Map.has_key?(responses, &1))
      %{state | current_player: hd(remaining)}
    end
  end

  defp do_apply_action(%{phase: :trick_result} = state, :next_trick) do
    if state.trick_number >= 10 do
      transition_to_scoring(%{state | current_trick: [], trick_winner: nil})
    else
      %{
        state
        | phase: :trick_play,
          current_trick: [],
          trick_winner: nil,
          current_player: state.trick_leader
      }
    end
  end

  defp do_apply_action(%{phase: :trick_play} = state, {:play, card}) do
    seat = state.current_player
    hand = Enum.at(state.hands, seat) |> List.delete(card)
    hands = List.replace_at(state.hands, seat, hand)

    trick_entry = %{player: seat, card: card}
    current_trick = state.current_trick ++ [trick_entry]
    played_cards = state.played_cards ++ [card]
    played_by = Map.update!(state.played_by, seat, &(&1 ++ [card]))

    state = %{
      state
      | hands: hands,
        current_trick: current_trick,
        played_cards: played_cards,
        played_by: played_by
    }

    active_players = get_active_players(state)

    if length(current_trick) == length(active_players) do
      resolve_trick(%{state | current_trick: current_trick})
    else
      play_order = trick_play_order(state.trick_leader, active_players)
      current_idx = Enum.find_index(play_order, &(&1 == seat))
      next_in_trick = Enum.at(play_order, current_idx + 1)
      %{state | current_trick: current_trick, current_player: next_in_trick}
    end
  end

  ## Bidding helpers

  defp after_pass_check(state) do
    passed_count = length(state.passed_players)

    cond do
      passed_count < 2 ->
        %{state | current_player: next_active_player(state.current_player, state.passed_players)}

      passed_count == 2 ->
        remaining = Enum.find([0, 1, 2], fn p -> p not in state.passed_players end)

        if state.highest_bid > 0 do
          resolve_bidding_winner(state, remaining)
        else
          # Nobody bid yet — give remaining player a chance
          %{state | current_player: remaining}
        end

      passed_count == 3 ->
        all_pass(state)
    end
  end

  defp resolve_bidding_winner(state, winner) do
    highest = max(state.highest_bid, 2)

    state = %{state | declarer: winner, highest_bid: highest, talon_revealed: true}

    # Inline talon reveal (Option A from spec)
    declarer_hand =
      (Enum.at(state.hands, winner) ++ state.talon)
      |> Cards.sort_hand()

    hands = List.replace_at(state.hands, winner, declarer_hand)
    %{state | phase: :discard, hands: hands, current_player: winner}
  end

  defp all_pass(state) do
    record_refe = should_record_refe?(state)

    refe_counts =
      if record_refe do
        List.update_at(state.refe_counts, state.dealer, &(&1 + 1))
      else
        state.refe_counts
      end

    %{
      state
      | phase: :hand_over,
        refe_counts: refe_counts,
        scoring_result: %{
          all_passed: true,
          bule_changes: [0, 0, 0],
          supe_changes: %{},
          declarer_passed: false,
          tricks: state.tricks_won,
          record_refe: record_refe
        }
    }
  end

  defp should_record_refe?(state) do
    no_kapa = Enum.all?(state.bule, &(&1 >= 0))

    not_all_max =
      not Enum.all?(state.refe_counts, &(&1 >= state.max_refes))

    no_kapa and not_all_max
  end

  ## Legal actions

  defp bid_actions(state) do
    higher_bids = for v <- 2..7, v > state.highest_bid, do: {:bid, v}
    actions = [:dalje | higher_bids]

    # Moje: only if current player is moje_holder AND highest_bid > 0
    if state.current_player == state.moje_holder and state.highest_bid > 0 do
      actions ++ [:moje]
    else
      actions
    end
  end

  defp discard_actions(state) do
    hand = Enum.at(state.hands, state.declarer)

    for {c1, i} <- Enum.with_index(hand),
        {c2, j} <- Enum.with_index(hand),
        i < j,
        do: {:discard, c1, c2}
  end

  defp declare_game_actions(state) do
    min_value = state.highest_bid

    games = [
      {:declare, :pik},
      {:declare, :karo},
      {:declare, :herc},
      {:declare, :tref},
      {:declare, :betl},
      {:declare, :sans}
    ]

    Enum.filter(games, fn {:declare, g} -> Cards.game_value(g) >= min_value end)
  end

  defp trick_play_actions(state) do
    hand = Enum.at(state.hands, state.current_player)

    if state.current_trick == [] do
      # Leading — any card
      Enum.map(hand, &{:play, &1})
    else
      {led_suit, _} = hd(state.current_trick).card

      if state.trump != nil do
        legal_plays_following_trump(hand, led_suit, state.trump)
      else
        legal_plays_following_no_trump(hand, led_suit)
      end
    end
  end

  defp legal_plays_following_trump(hand, led_suit, trump_suit) do
    same_suit = Enum.filter(hand, fn {s, _} -> s == led_suit end)

    cond do
      same_suit != [] ->
        Enum.map(same_suit, &{:play, &1})

      true ->
        trumps = Enum.filter(hand, fn {s, _} -> s == trump_suit end)

        if trumps != [] do
          Enum.map(trumps, &{:play, &1})
        else
          Enum.map(hand, &{:play, &1})
        end
    end
  end

  defp legal_plays_following_no_trump(hand, led_suit) do
    same_suit = Enum.filter(hand, fn {s, _} -> s == led_suit end)

    if same_suit != [] do
      Enum.map(same_suit, &{:play, &1})
    else
      Enum.map(hand, &{:play, &1})
    end
  end

  ## Trick resolution

  defp resolve_trick(state) do
    trick = state.current_trick
    {led_suit, _} = hd(trick).card
    trump = state.trump

    winner_entry =
      Enum.reduce(tl(trick), hd(trick), fn play, current_winner ->
        if beats?(play.card, current_winner.card, led_suit, trump) do
          play
        else
          current_winner
        end
      end)

    winner = winner_entry.player
    tricks_won = List.update_at(state.tricks_won, winner, &(&1 + 1))
    trick_number = state.trick_number + 1

    state = %{
      state
      | tricks_won: tricks_won,
        trick_number: trick_number,
        trick_winner: winner,
        trick_leader: winner,
        current_player: winner
    }

    if hand_decided?(state) do
      transition_to_scoring(%{state | current_trick: [], trick_winner: nil})
    else
      %{state | phase: :trick_result}
    end
  end

  defp beats?(challenger, current_winner, _led_suit, trump) do
    {c_suit, c_rank} = challenger
    {w_suit, w_rank} = current_winner
    c_val = Cards.rank_value(c_rank)
    w_val = Cards.rank_value(w_rank)

    cond do
      # Same suit — higher rank wins
      c_suit == w_suit and c_val > w_val -> true
      # Challenger is trump, winner is not — trump wins
      trump != nil and c_suit == trump and w_suit != trump -> true
      # Everything else — challenger doesn't beat
      true -> false
    end
  end

  defp hand_decided?(state) do
    declarer_tricks = Enum.at(state.tricks_won, state.declarer)
    tricks_remaining = 10 - state.trick_number

    cond do
      state.trick_number >= 10 -> true
      state.game_type == :betl and declarer_tricks > 0 -> true
      state.game_type != :betl and declarer_tricks + tricks_remaining < 6 -> true
      true -> false
    end
  end

  ## First trick leader

  defp set_first_trick_leader(state) do
    case state.game_type do
      :sans ->
        # Left defender leads. Left of declarer = rem(declarer + 1, 3)
        left_defender = rem(state.declarer + 1, 3)

        leader =
          if left_defender in state.defenders do
            left_defender
          else
            # Fallback: first active non-declarer
            hd(state.defenders)
          end

        %{state | phase: :trick_play, trick_leader: leader, current_player: leader}

      _ ->
        # Trump games: first bidder leads
        leader = first_bidder(state.dealer)
        active = get_active_players(state)
        leader = ensure_active_leader(leader, active)

        %{state | phase: :trick_play, trick_leader: leader, current_player: leader}
    end
  end

  defp ensure_active_leader(leader, active) do
    if leader in active do
      leader
    else
      next = next_player_in_circle(leader)
      if next in active, do: next, else: next_player_in_circle(next)
    end
  end

  ## Active players and play order

  def get_active_players(state) do
    case state.defenders do
      [] -> [state.declarer]
      defs -> Enum.sort([state.declarer | defs])
    end
  end

  defp trick_play_order(leader, active_players) do
    build_play_order(leader, active_players, [leader])
  end

  defp build_play_order(current, active_players, order) do
    if length(order) == length(active_players) do
      order
    else
      next = next_player_in_circle(current)

      if next in active_players do
        build_play_order(next, active_players, order ++ [next])
      else
        build_play_order(next, active_players, order)
      end
    end
  end

  ## Trump determination

  defp trump_for_game(:pik), do: :pik
  defp trump_for_game(:karo), do: :karo
  defp trump_for_game(:herc), do: :herc
  defp trump_for_game(:tref), do: :tref
  defp trump_for_game(_), do: nil

  ## Scoring

  defp transition_to_scoring(state) do
    result = calculate_scoring(state)
    %{state | phase: :scoring, scoring_result: result}
  end

  defp score_free_pass(state) do
    gv = Cards.game_value(state.game_type)
    refe_mult = refe_multiplier(state)
    bule_change = gv * 2 * refe_mult

    bule_changes = List.replace_at([0, 0, 0], state.declarer, -bule_change)

    %{
      state
      | phase: :hand_over,
        scoring_result: %{
          all_passed: false,
          declarer_passed: true,
          free_pass: true,
          tricks: [0, 0, 0],
          bule_changes: bule_changes,
          supe_changes: %{},
          game_type: state.game_type,
          game_value: Cards.game_value(state.game_type)
        }
    }
  end

  defp calculate_scoring(state) do
    gv = Cards.game_value(state.game_type)
    declarer = state.declarer
    declarer_tricks = Enum.at(state.tricks_won, declarer)

    if state.defenders == [] do
      # Both ne_dodjem — free pass (shouldn't reach here normally, but handle it)
      %{
        all_passed: false,
        bule_changes: List.replace_at([0, 0, 0], declarer, -(gv * 2)),
        supe_changes: %{},
        declarer_passed: true,
        free_pass: true,
        tricks: state.tricks_won,
        game_type: state.game_type,
        game_value: gv
      }
    else
      declarer_passed = declarer_passed?(state.game_type, declarer_tricks)
      bule_changes = calculate_bule_changes(state, gv, declarer, declarer_passed)
      supe_changes = calculate_supe_changes(state, gv, declarer_passed)

      %{
        all_passed: false,
        bule_changes: bule_changes,
        supe_changes: supe_changes,
        declarer_passed: declarer_passed,
        free_pass: false,
        tricks: state.tricks_won,
        game_type: state.game_type,
        game_value: gv
      }
    end
  end

  defp calculate_bule_changes(state, gv, declarer, declarer_passed) do
    kontra_mult = kontra_multiplier(state.kontra_level)
    refe_mult = refe_multiplier(state)
    total_mult = kontra_mult * refe_mult
    change = gv * 2 * total_mult

    bule_changes =
      if declarer_passed do
        List.replace_at([0, 0, 0], declarer, -change)
      else
        List.replace_at([0, 0, 0], declarer, change)
      end

    # Check each defender for failure
    Enum.reduce(state.defenders, bule_changes, fn def_seat, acc ->
      if defender_failed?(state, def_seat) do
        List.update_at(acc, def_seat, &(&1 + change))
      else
        acc
      end
    end)
  end

  defp calculate_supe_changes(state, gv, declarer_passed) do
    kontra_mult = kontra_multiplier(state.kontra_level)
    refe_mult = refe_multiplier(state)
    total_mult = kontra_mult * refe_mult

    if state.game_type == :betl and not declarer_passed do
      # Betl failure: fixed supe
      fixed = 60 * total_mult

      for def_seat <- state.defenders, into: %{} do
        {{def_seat, state.declarer}, fixed}
      end
    else
      # Normal supe: tricks × game_value × 2 × multipliers
      for def_seat <- state.defenders,
          tricks = Enum.at(state.tricks_won, def_seat),
          amount = tricks * gv * 2 * total_mult,
          amount > 0,
          into: %{} do
        {{def_seat, state.declarer}, amount}
      end
    end
  end

  defp declarer_passed?(:betl, tricks), do: tricks == 0
  defp declarer_passed?(_, tricks), do: tricks >= 6

  defp defender_failed?(state, def_seat) do
    def_tricks = Enum.at(state.tricks_won, def_seat)

    if length(state.defenders) == 2 do
      # Both defending — check individual >= 2 OR combined >= 4
      other_def = Enum.find(state.defenders, &(&1 != def_seat))
      other_tricks = Enum.at(state.tricks_won, other_def)
      combined = def_tricks + other_tricks

      def_tricks < 2 and combined < 4
    else
      # Solo defender — must get >= 2
      def_tricks < 2
    end
  end

  defp kontra_multiplier(0), do: 1
  defp kontra_multiplier(1), do: 2
  defp kontra_multiplier(2), do: 4
  defp kontra_multiplier(3), do: 8
  defp kontra_multiplier(4), do: 16

  defp refe_multiplier(state) do
    if has_active_refe?(state, state.declarer), do: 2, else: 1
  end

  defp has_active_refe?(state, player) do
    Enum.at(state.refe_counts, player) > 0
  end
end
