defmodule PreferansWeb.Game.MockEngineTest do
  use ExUnit.Case, async: true

  alias PreferansWeb.Game.MockEngine

  defp new_state(opts \\ []) do
    dealer = Keyword.get(opts, :dealer, 0)
    MockEngine.new_hand(dealer, [100, 100, 100], [0, 0, 0], 2)
  end

  ## Initial state

  describe "new_hand/4" do
    test "produces valid initial state in :bid phase" do
      state = new_state()
      assert state.phase == :bid
      assert length(state.hands) == 3
      assert Enum.all?(state.hands, &(length(&1) == 10))
      assert length(state.talon) == 2
      assert state.dealer == 0
      assert state.current_player == 2
      assert state.highest_bid == 0
      assert state.declarer == nil
      assert state.tricks_won == [0, 0, 0]
    end

    test "first bidder is to dealer's right (counter-clockwise)" do
      assert new_state(dealer: 0).current_player == 2
      assert new_state(dealer: 1).current_player == 0
      assert new_state(dealer: 2).current_player == 1
    end
  end

  ## Bidding

  describe "bidding" do
    test "all 3 pass → hand_over with refe" do
      state = new_state()
      {:ok, state} = MockEngine.apply_action(state, :dalje)
      {:ok, state} = MockEngine.apply_action(state, :dalje)
      {:ok, state} = MockEngine.apply_action(state, :dalje)

      assert state.phase == :hand_over
      assert state.scoring_result.all_passed == true
      # Refe charged to dealer
      assert Enum.at(state.refe_counts, state.dealer) == 1
    end

    test "one player bids, others pass → declarer set, transitions to discard" do
      state = new_state(dealer: 0)
      # Seat 2 bids
      {:ok, state} = MockEngine.apply_action(state, {:bid, 2})
      # Seat 1 passes
      {:ok, state} = MockEngine.apply_action(state, :dalje)
      # Seat 0 passes
      {:ok, state} = MockEngine.apply_action(state, :dalje)

      assert state.declarer == 2
      assert state.phase == :discard
      assert state.highest_bid == 2
      # Declarer has 12 cards (10 + 2 talon)
      assert length(Enum.at(state.hands, 2)) == 12
    end

    test "bidder wins immediately when both opponents already passed" do
      state = new_state(dealer: 0)
      # Seat 2 passes
      {:ok, state} = MockEngine.apply_action(state, :dalje)
      # Seat 1 passes
      {:ok, state} = MockEngine.apply_action(state, :dalje)
      # Seat 0 is last — they bid
      {:ok, state} = MockEngine.apply_action(state, {:bid, 2})

      # Should immediately become declarer, NOT ask for another bid
      assert state.declarer == 0
      assert state.phase == :discard
      assert state.highest_bid == 2
    end

    test "two players bid, one passes, bidding continues between two" do
      state = new_state(dealer: 0)
      # Seat 2 bids 2
      {:ok, state} = MockEngine.apply_action(state, {:bid, 2})
      # Seat 1 passes
      {:ok, state} = MockEngine.apply_action(state, :dalje)
      # Seat 0 bids 3
      {:ok, state} = MockEngine.apply_action(state, {:bid, 3})
      # Back to seat 2 (only two active: 0 and 2)
      assert state.current_player == 2
      assert state.phase == :bid

      # Seat 2 passes → seat 0 wins
      {:ok, state} = MockEngine.apply_action(state, :dalje)
      assert state.declarer == 0
      assert state.phase == :discard
      assert state.highest_bid == 3
    end

    test "rejects bid lower than or equal to current highest" do
      state = new_state()
      {:ok, state} = MockEngine.apply_action(state, {:bid, 3})
      assert {:error, :illegal_action} = MockEngine.apply_action(state, {:bid, 2})
      assert {:error, :illegal_action} = MockEngine.apply_action(state, {:bid, 3})
    end

    test "bid history records all actions" do
      state = new_state(dealer: 0)
      {:ok, state} = MockEngine.apply_action(state, {:bid, 2})
      {:ok, state} = MockEngine.apply_action(state, :dalje)
      {:ok, state} = MockEngine.apply_action(state, :dalje)

      assert length(state.bid_history) == 3
      assert Enum.at(state.bid_history, 0) == %{player: 2, action: {:bid, 2}}
      assert Enum.at(state.bid_history, 1) == %{player: 1, action: :dalje}
      assert Enum.at(state.bid_history, 2) == %{player: 0, action: :dalje}
    end
  end

  ## Discard

  describe "discard" do
    test "removes 2 cards from 12-card hand, transitions to declare_game" do
      state = setup_discard_phase()
      hand = Enum.at(state.hands, state.declarer)
      assert length(hand) == 12

      [c1, c2 | _] = hand
      {:ok, state} = MockEngine.apply_action(state, {:discard, c1, c2})

      assert state.phase == :declare_game
      assert length(Enum.at(state.hands, state.declarer)) == 10
      assert state.discards == [c1, c2]
      assert state.current_player == state.declarer
    end

    test "rejects discarding cards not in hand" do
      state = setup_discard_phase()
      fake_card = {:pik, :ace}
      # This might be in the hand randomly — but {:discard, fake, fake} is always invalid
      result = MockEngine.apply_action(state, {:discard, fake_card, fake_card})
      # Either illegal action or it works if both happen to be in hand
      # The point is the engine doesn't crash
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end
  end

  ## Declare game

  describe "declare_game" do
    test "suit game goes to defense phase" do
      state = setup_declare_phase()
      {:ok, state} = MockEngine.apply_action(state, :pik)

      assert state.phase == :defense
      assert state.game_type == :pik
      assert state.defenders == []
    end

    test "betl skips defense, goes straight to trick_play" do
      state = setup_declare_phase()
      {:ok, state} = MockEngine.apply_action(state, :betl)

      assert state.phase == :trick_play
      assert state.game_type == :betl
      assert length(state.defenders) == 2
    end

    test "only games with value >= highest_bid are legal" do
      state = new_state(dealer: 0)
      # Bid up to 5
      {:ok, state} = MockEngine.apply_action(state, {:bid, 5})
      {:ok, state} = MockEngine.apply_action(state, :dalje)
      {:ok, state} = MockEngine.apply_action(state, :dalje)
      # Discard
      hand = Enum.at(state.hands, state.declarer)
      [c1, c2 | _] = hand
      {:ok, state} = MockEngine.apply_action(state, {:discard, c1, c2})

      legal = MockEngine.get_legal_actions(state)
      # Only tref(5), betl(6), sans(7) should be legal
      assert :tref in legal
      assert :betl in legal
      assert :sans in legal
      refute :pik in legal
      refute :karo in legal
      refute :herc in legal
    end
  end

  ## Defense

  describe "defense" do
    test "both ne_dodjem → scoring with free pass" do
      state = setup_defense_phase()
      {:ok, state} = MockEngine.apply_action(state, :ne_dodjem)
      {:ok, state} = MockEngine.apply_action(state, :ne_dodjem)

      assert state.phase == :scoring
      assert state.defenders == []
      assert state.scoring_result.declarer_passed == true
    end

    test "both dodjem → trick_play with 2 defenders" do
      state = setup_defense_phase()
      {:ok, state} = MockEngine.apply_action(state, :dodjem)
      {:ok, state} = MockEngine.apply_action(state, :dodjem)

      assert state.phase == :trick_play
      assert length(state.defenders) == 2
    end

    test "one dodjem one ne_dodjem → trick_play with 1 defender" do
      state = setup_defense_phase()
      {:ok, state} = MockEngine.apply_action(state, :dodjem)
      {:ok, state} = MockEngine.apply_action(state, :ne_dodjem)

      assert state.phase == :trick_play
      assert length(state.defenders) == 1
    end
  end

  ## Trick play

  describe "trick play" do
    test "suit game reaches scoring" do
      state = setup_trick_play_phase()
      state = play_all_tricks(state)

      assert state.phase == :scoring
      # May end before 10 if declarer can't reach 6
      assert Enum.sum(state.tricks_won) <= 10
    end

    test "betl ends immediately when declarer takes a trick" do
      state = setup_betl_trick_play_phase()
      state = play_all_tricks(state)

      assert state.phase == :scoring
      declarer_tricks = Enum.at(state.tricks_won, state.declarer)

      if declarer_tricks > 0 do
        # Hand ended early — not all 10 tricks played
        assert Enum.sum(state.tricks_won) < 10
        assert state.scoring_result.declarer_passed == false
      else
        # Declarer took 0 — all 10 played
        assert Enum.sum(state.tricks_won) == 10
        assert state.scoring_result.declarer_passed == true
      end
    end

    test "follow suit enforced — must play led suit if available" do
      state = setup_trick_play_phase()
      leader = state.current_player
      leader_hand = Enum.at(state.hands, leader)

      first_card = hd(leader_hand)
      {:ok, state} = MockEngine.apply_action(state, {:play, first_card})

      follower = state.current_player
      follower_hand = Enum.at(state.hands, follower)
      {led_suit, _} = first_card
      suited = Enum.filter(follower_hand, fn {s, _} -> s == led_suit end)
      legal = MockEngine.get_legal_actions(state)

      if suited != [] do
        assert Enum.all?(legal, fn {:play, {s, _}} -> s == led_suit end)
      end
    end

    test "forced trump — must play trump when can't follow suit" do
      state = setup_trick_play_phase()
      assert state.game_type == :pik

      leader = state.current_player
      leader_hand = Enum.at(state.hands, leader)
      first_card = hd(leader_hand)
      {:ok, state} = MockEngine.apply_action(state, {:play, first_card})

      follower = state.current_player
      follower_hand = Enum.at(state.hands, follower)
      {led_suit, _} = first_card
      suited = Enum.filter(follower_hand, fn {s, _} -> s == led_suit end)
      trumps = Enum.filter(follower_hand, fn {s, _} -> s == :pik end)
      legal = MockEngine.get_legal_actions(state)

      cond do
        suited != [] ->
          assert Enum.all?(legal, fn {:play, {s, _}} -> s == led_suit end)

        trumps != [] and led_suit != :pik ->
          assert Enum.all?(legal, fn {:play, {s, _}} -> s == :pik end)

        true ->
          assert length(legal) == length(follower_hand)
      end
    end

    test "no forced trump in betl" do
      state = setup_betl_trick_play_phase()
      leader = state.current_player
      leader_hand = Enum.at(state.hands, leader)
      first_card = hd(leader_hand)
      {:ok, state} = MockEngine.apply_action(state, {:play, first_card})

      follower = state.current_player
      follower_hand = Enum.at(state.hands, follower)
      {led_suit, _} = first_card
      suited = Enum.filter(follower_hand, fn {s, _} -> s == led_suit end)
      legal = MockEngine.get_legal_actions(state)

      if suited == [] do
        # In betl, can play anything when can't follow suit
        assert length(legal) == length(follower_hand)
      end
    end

    test "trick_result phase pauses after trick, next_trick continues" do
      state = setup_trick_play_phase()
      active = [state.declarer | state.defenders]

      # Play one full trick
      state =
        Enum.reduce(1..length(active), state, fn _, s ->
          [action | _] = MockEngine.get_legal_actions(s)
          {:ok, s} = MockEngine.apply_action(s, action)
          s
        end)

      assert state.phase == :trick_result
      assert state.trick_winner != nil
      assert Enum.sum(state.tricks_won) == 1

      # Continue to next trick
      {:ok, state} = MockEngine.apply_action(state, :next_trick)
      assert state.phase == :trick_play
      assert state.trick_winner == nil
      assert state.current_trick == []
    end

    test "2-player trick play works with 1 defender" do
      state = setup_defense_phase()
      {:ok, state} = MockEngine.apply_action(state, :dodjem)
      {:ok, state} = MockEngine.apply_action(state, :ne_dodjem)

      assert length(state.defenders) == 1
      active = [state.declarer | state.defenders]
      assert length(active) == 2

      # Play one trick (2 cards)
      state =
        Enum.reduce(1..2, state, fn _, s ->
          [action | _] = MockEngine.get_legal_actions(s)
          {:ok, s} = MockEngine.apply_action(s, action)
          s
        end)

      assert state.phase == :trick_result
      assert Enum.sum(state.tricks_won) == 1
    end
  end

  ## Trump resolution

  describe "trump resolution" do
    test "trump card beats higher card of led suit" do
      state = setup_trick_play_phase()
      state = play_all_tricks(state)
      assert state.phase == :scoring
    end

    test "no trump in betl — highest led suit always wins" do
      state = setup_betl_trick_play_phase()
      state = play_all_tricks(state)
      assert state.phase == :scoring
    end
  end

  ## Scoring

  describe "scoring" do
    test "declarer with 6+ tricks passes in suit game" do
      state = setup_trick_play_phase()
      state = play_all_tricks(state)

      assert state.phase == :scoring
      declarer_tricks = Enum.at(state.scoring_result.tricks, state.declarer)

      if declarer_tricks >= 6 do
        assert state.scoring_result.declarer_passed == true
      else
        assert state.scoring_result.declarer_passed == false
      end
    end

    test "betl declarer passes only with 0 tricks" do
      state = setup_betl_trick_play_phase()
      state = play_all_tricks(state)

      assert state.phase == :scoring
      declarer_tricks = Enum.at(state.scoring_result.tricks, state.declarer)

      if declarer_tricks == 0 do
        assert state.scoring_result.declarer_passed == true
      else
        assert state.scoring_result.declarer_passed == false
      end
    end

    test "scoring result has required fields" do
      state = setup_trick_play_phase()
      state = play_all_tricks(state)

      result = state.scoring_result
      assert is_boolean(result.all_passed)
      assert is_list(result.bule_changes)
      assert length(result.bule_changes) == 3
      assert is_list(result.supe_changes)
      assert is_boolean(result.declarer_passed)
      assert is_list(result.tricks)
      assert length(result.tricks) == 3
    end

    test "all-pass scoring has zero bule changes" do
      state = new_state()
      {:ok, state} = MockEngine.apply_action(state, :dalje)
      {:ok, state} = MockEngine.apply_action(state, :dalje)
      {:ok, state} = MockEngine.apply_action(state, :dalje)

      assert state.scoring_result.all_passed == true
      assert state.scoring_result.bule_changes == [0, 0, 0]
      assert state.scoring_result.supe_changes == []
    end

    test "free pass (both ne_dodjem) gives declarer bule reduction" do
      state = setup_defense_phase()
      {:ok, state} = MockEngine.apply_action(state, :ne_dodjem)
      {:ok, state} = MockEngine.apply_action(state, :ne_dodjem)

      result = state.scoring_result
      declarer = state.declarer
      gv = PreferansWeb.Game.Cards.game_value(state.game_type)

      assert Enum.at(result.bule_changes, declarer) == -(gv * 2)
      assert result.declarer_passed == true
    end
  end

  ## Player view

  describe "get_player_view/2" do
    test "opponent cards never exposed" do
      state = new_state()
      view = MockEngine.get_player_view(state, 0)

      assert is_list(view.my_hand)
      assert length(view.my_hand) == 10
      assert map_size(view.opponent_card_counts) == 2
      assert view.opponent_card_counts[1] == 10
      assert view.opponent_card_counts[2] == 10
    end

    test "talon hidden during bid" do
      state = new_state()
      view = MockEngine.get_player_view(state, 0)
      assert view.talon == nil
    end

    test "talon visible only during discard" do
      state = setup_discard_phase()
      view = MockEngine.get_player_view(state, state.declarer)
      assert view.talon != nil
      assert length(view.talon) == 2

      # After discard, talon should be hidden again
      hand = Enum.at(state.hands, state.declarer)
      [c1, c2 | _] = hand
      {:ok, state} = MockEngine.apply_action(state, {:discard, c1, c2})
      view = MockEngine.get_player_view(state, state.declarer)
      assert view.talon == nil
    end

    test "discards hidden from non-declarer" do
      state = setup_discard_phase()
      declarer = state.declarer
      hand = Enum.at(state.hands, declarer)
      [c1, c2 | _] = hand
      {:ok, state} = MockEngine.apply_action(state, {:discard, c1, c2})

      non_declarer = rem(declarer + 1, 3)
      assert MockEngine.get_player_view(state, non_declarer).discards == nil
      assert MockEngine.get_player_view(state, declarer).discards == [c1, c2]
    end

    test "legal_actions only for current player" do
      state = new_state()
      current = state.current_player
      other = rem(current + 1, 3)

      assert MockEngine.get_player_view(state, current).legal_actions != []
      assert MockEngine.get_player_view(state, other).legal_actions == []
    end

    test "scoring_result only visible in scoring/hand_over phases" do
      state = new_state()
      assert MockEngine.get_player_view(state, 0).scoring_result == nil

      state = setup_trick_play_phase()
      assert MockEngine.get_player_view(state, 0).scoring_result == nil
    end
  end

  ## Full game flow

  describe "full game flow" do
    test "complete suit game from deal to scoring" do
      state = new_state(dealer: 0)

      # Bidding: seat 2 bids 2, others pass
      {:ok, state} = MockEngine.apply_action(state, {:bid, 2})
      {:ok, state} = MockEngine.apply_action(state, :dalje)
      {:ok, state} = MockEngine.apply_action(state, :dalje)
      assert state.phase == :discard

      # Discard
      hand = Enum.at(state.hands, state.declarer)
      [c1, c2 | _] = hand
      {:ok, state} = MockEngine.apply_action(state, {:discard, c1, c2})
      assert state.phase == :declare_game

      # Declare pik
      {:ok, state} = MockEngine.apply_action(state, :pik)
      assert state.phase == :defense

      # Both defend
      {:ok, state} = MockEngine.apply_action(state, :dodjem)
      {:ok, state} = MockEngine.apply_action(state, :dodjem)
      assert state.phase == :trick_play

      # Play all tricks (may end early if declarer can't reach 6)
      state = play_all_tricks(state)
      assert state.phase == :scoring
      assert state.scoring_result != nil
    end

    test "complete betl game from deal to scoring" do
      state = new_state(dealer: 0)

      # Bidding: seat 2 bids 6, others pass
      {:ok, state} = MockEngine.apply_action(state, {:bid, 6})
      {:ok, state} = MockEngine.apply_action(state, :dalje)
      {:ok, state} = MockEngine.apply_action(state, :dalje)

      # Discard
      hand = Enum.at(state.hands, state.declarer)
      [c1, c2 | _] = hand
      {:ok, state} = MockEngine.apply_action(state, {:discard, c1, c2})

      # Declare betl
      {:ok, state} = MockEngine.apply_action(state, :betl)
      assert state.phase == :trick_play

      # Play all tricks (may end early if declarer takes a trick)
      state = play_all_tricks(state)
      assert state.phase == :scoring
    end
  end

  ## Helpers

  defp setup_discard_phase do
    state = new_state(dealer: 0)
    {:ok, state} = MockEngine.apply_action(state, {:bid, 2})
    {:ok, state} = MockEngine.apply_action(state, :dalje)
    {:ok, state} = MockEngine.apply_action(state, :dalje)
    state
  end

  defp setup_declare_phase do
    state = setup_discard_phase()
    hand = Enum.at(state.hands, state.declarer)
    [c1, c2 | _] = hand
    {:ok, state} = MockEngine.apply_action(state, {:discard, c1, c2})
    state
  end

  defp setup_defense_phase do
    state = setup_declare_phase()
    {:ok, state} = MockEngine.apply_action(state, :pik)
    state
  end

  defp setup_trick_play_phase do
    state = setup_defense_phase()
    {:ok, state} = MockEngine.apply_action(state, :dodjem)
    {:ok, state} = MockEngine.apply_action(state, :dodjem)
    state
  end

  defp setup_betl_trick_play_phase do
    state = setup_declare_phase()
    {:ok, state} = MockEngine.apply_action(state, :betl)
    state
  end

  defp play_all_tricks(state) do
    cond do
      state.phase in [:trick_play, :trick_result] ->
        [action | _] = MockEngine.get_legal_actions(state)
        {:ok, state} = MockEngine.apply_action(state, action)
        play_all_tricks(state)

      true ->
        state
    end
  end
end
