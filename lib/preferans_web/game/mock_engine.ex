defmodule PreferansWeb.Game.MockEngine do
  @moduledoc """
  Pure-function mock engine for Preferans game flow.
  Temporary module for UI development — will be replaced by C++ engine.
  """

  alias PreferansWeb.Game.Cards

  ## Public API

  def new_hand(dealer, bule, refe_counts, max_refes) do
    {hands, talon} = Cards.deal()

    %{
      phase: :bid,
      hands: hands,
      talon: talon,
      discards: [],
      current_player: first_bidder(dealer),
      dealer: dealer,
      bid_history: [],
      highest_bid: 0,
      passed_players: MapSet.new(),
      declarer: nil,
      game_type: nil,
      is_igra: false,
      defenders: [],
      defense_responses: %{},
      trick_number: 0,
      current_trick: [],
      trick_leader: nil,
      trick_winner: nil,
      tricks_won: [0, 0, 0],
      played_cards: [],
      bule: bule,
      refe_counts: refe_counts,
      max_refes: max_refes,
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
    legal = get_legal_actions(state)

    if action in legal do
      {:ok, do_apply_action(state, action)}
    else
      {:error, :illegal_action}
    end
  end

  def get_player_view(state, seat) do
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
      talon: if(state.phase == :discard, do: state.talon, else: nil),
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
        for(
          s <- [0, 1, 2],
          do: %{seat: s, is_declarer: state.declarer == s, is_defender: s in state.defenders}
        )
    }
  end

  ## Action dispatch (all clauses grouped)

  defp do_apply_action(%{phase: :bid} = state, :dalje) do
    state = %{
      state
      | bid_history: state.bid_history ++ [%{player: state.current_player, action: :dalje}],
        passed_players: MapSet.put(state.passed_players, state.current_player)
    }

    active = Enum.reject([0, 1, 2], &MapSet.member?(state.passed_players, &1))

    cond do
      active == [] ->
        refe_counts = List.update_at(state.refe_counts, state.dealer, &(&1 + 1))

        %{
          state
          | phase: :hand_over,
            refe_counts: refe_counts,
            scoring_result: %{
              all_passed: true,
              bule_changes: [0, 0, 0],
              supe_changes: [],
              declarer_passed: false,
              tricks: state.tricks_won
            }
        }

      length(active) == 1 and state.highest_bid > 0 ->
        [declarer] = active
        highest = max(state.highest_bid, 2)
        transition_to_talon_reveal(%{state | declarer: declarer, highest_bid: highest})

      length(active) == 1 and state.highest_bid == 0 ->
        # Last player hasn't acted yet and no bids — they must still pass or bid
        %{state | current_player: hd(active)}

      true ->
        %{state | current_player: next_player(state.current_player, active)}
    end
  end

  defp do_apply_action(%{phase: :bid} = state, {:bid, value}) do
    state = %{
      state
      | bid_history:
          state.bid_history ++ [%{player: state.current_player, action: {:bid, value}}],
        highest_bid: value
    }

    active = Enum.reject([0, 1, 2], &MapSet.member?(state.passed_players, &1))
    %{state | current_player: next_player(state.current_player, active)}
  end

  defp do_apply_action(%{phase: :discard} = state, {:discard, card1, card2}) do
    hand =
      Enum.at(state.hands, state.declarer)
      |> List.delete(card1)
      |> List.delete(card2)

    hands = List.replace_at(state.hands, state.declarer, hand)

    %{
      state
      | phase: :declare_game,
        hands: hands,
        discards: [card1, card2],
        current_player: state.declarer
    }
  end

  defp do_apply_action(%{phase: :declare_game} = state, game_type)
       when game_type in [:pik, :karo, :herc, :tref, :betl, :sans] do
    non_declarers = Enum.reject([0, 1, 2], &(&1 == state.declarer))
    state = %{state | game_type: game_type}

    if game_type == :betl do
      %{
        state
        | phase: :trick_play,
          defenders: non_declarers,
          trick_leader: first_bidder(state.dealer),
          current_player: first_bidder(state.dealer)
      }
    else
      first_defender = next_player(state.declarer, non_declarers)
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
        transition_to_scoring(state)
      else
        leader = first_bidder(state.dealer)
        %{state | phase: :trick_play, trick_leader: leader, current_player: leader}
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
    active_players = [state.declarer | state.defenders]

    state = %{state | hands: hands, current_trick: current_trick, played_cards: played_cards}

    if length(current_trick) == length(active_players) do
      resolve_trick(%{state | current_trick: current_trick})
    else
      next = next_player(seat, active_players)
      %{state | current_trick: current_trick, current_player: next}
    end
  end

  ## Helpers

  defp next_player(current, active_players) do
    next = rem(current + 2, 3)
    if next in active_players, do: next, else: next_player(next, active_players)
  end

  defp first_bidder(dealer), do: rem(dealer + 2, 3)

  defp trump_suit(:pik), do: :pik
  defp trump_suit(:karo), do: :karo
  defp trump_suit(:herc), do: :herc
  defp trump_suit(:tref), do: :tref
  defp trump_suit(_), do: nil

  defp bid_actions(state) do
    higher_bids = for v <- 2..7, v > state.highest_bid, do: {:bid, v}
    [:dalje | higher_bids]
  end

  defp discard_actions(state) do
    hand = Enum.at(state.hands, state.declarer)

    for {c1, i} <- Enum.with_index(hand),
        {c2, j} <- Enum.with_index(hand),
        i < j,
        do: {:discard, c1, c2}
  end

  defp declare_game_actions(state) do
    all_games = [:pik, :karo, :herc, :tref, :betl, :sans]
    Enum.filter(all_games, &(Cards.game_value(&1) >= state.highest_bid))
  end

  defp trick_play_actions(state) do
    hand = Enum.at(state.hands, state.current_player)
    trump = trump_suit(state.game_type)

    if state.current_trick == [] do
      Enum.map(hand, &{:play, &1})
    else
      {led_suit, _} = hd(state.current_trick).card
      suited = Enum.filter(hand, fn {s, _} -> s == led_suit end)

      cond do
        suited != [] ->
          Enum.map(suited, &{:play, &1})

        # Must play trump if can't follow suit (suit games only)
        trump != nil ->
          trumps = Enum.filter(hand, fn {s, _} -> s == trump end)
          if trumps != [], do: Enum.map(trumps, &{:play, &1}), else: Enum.map(hand, &{:play, &1})

        # Betl/Sans — no trump, play anything
        true ->
          Enum.map(hand, &{:play, &1})
      end
    end
  end

  defp resolve_trick(state) do
    {led_suit, _} = hd(state.current_trick).card
    trump_suit = trump_suit(state.game_type)

    winner_entry =
      cond do
        # Trump game and someone played trump
        trump_suit != nil and
            Enum.any?(state.current_trick, fn %{card: {s, _}} -> s == trump_suit end) ->
          state.current_trick
          |> Enum.filter(fn %{card: {s, _}} -> s == trump_suit end)
          |> Enum.max_by(fn %{card: {_, r}} -> Cards.rank_value(r) end)

        # No trump played or no-trump game — highest of led suit wins
        true ->
          state.current_trick
          |> Enum.filter(fn %{card: {s, _}} -> s == led_suit end)
          |> Enum.max_by(fn %{card: {_, r}} -> Cards.rank_value(r) end)
      end

    winner = winner_entry.player
    tricks_won = List.update_at(state.tricks_won, winner, &(&1 + 1))
    trick_number = state.trick_number + 1

    %{
      state
      | phase: :trick_result,
        tricks_won: tricks_won,
        trick_number: trick_number,
        trick_winner: winner,
        trick_leader: winner,
        current_player: winner
    }
  end

  defp transition_to_talon_reveal(state) do
    declarer_hand = Enum.at(state.hands, state.declarer) ++ state.talon
    hands = List.replace_at(state.hands, state.declarer, declarer_hand)
    %{state | phase: :discard, hands: hands, current_player: state.declarer}
  end

  defp transition_to_scoring(state) do
    result = calculate_scoring(state)
    %{state | phase: :scoring, scoring_result: result}
  end

  defp calculate_scoring(state) do
    gv = Cards.game_value(state.game_type)
    declarer = state.declarer
    declarer_tricks = Enum.at(state.tricks_won, declarer)

    if state.defenders == [] do
      # Both ne_dodjem — free pass
      %{
        all_passed: false,
        bule_changes: List.replace_at([0, 0, 0], declarer, -(gv * 2)),
        supe_changes: [],
        declarer_passed: true,
        tricks: state.tricks_won
      }
    else
      declarer_passed =
        cond do
          state.game_type == :betl -> declarer_tricks == 0
          true -> declarer_tricks >= 6
        end

      bule_changes =
        if declarer_passed do
          changes = List.replace_at([0, 0, 0], declarer, -(gv * 2))

          Enum.reduce(state.defenders, changes, fn def_seat, acc ->
            def_tricks = Enum.at(state.tricks_won, def_seat)
            combined = Enum.sum(for d <- state.defenders, do: Enum.at(state.tricks_won, d))

            if def_tricks < 2 and combined < 4 do
              List.update_at(acc, def_seat, &(&1 + gv * 2))
            else
              acc
            end
          end)
        else
          List.replace_at([0, 0, 0], declarer, gv * 2)
        end

      supe_changes =
        for def_seat <- state.defenders do
          def_tricks = Enum.at(state.tricks_won, def_seat)
          %{from: declarer, to: def_seat, amount: def_tricks * gv * 2}
        end

      %{
        all_passed: false,
        bule_changes: bule_changes,
        supe_changes: supe_changes,
        declarer_passed: declarer_passed,
        tricks: state.tricks_won
      }
    end
  end
end
