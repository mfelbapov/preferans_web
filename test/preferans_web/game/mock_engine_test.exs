defmodule PreferansWeb.Game.MockEngineTest do
  use ExUnit.Case, async: true

  alias PreferansWeb.Game.MockEngine

  defp new_state(opts \\ []) do
    dealer = Keyword.get(opts, :dealer, 0)
    MockEngine.new_hand(dealer, [100, 100, 100], [0, 0, 0], 2)
  end

  describe "new_hand/4" do
    test "produces valid initial state in :bid phase" do
      state = new_state()
      assert state.phase == :bid
      assert length(state.hands) == 3
      assert Enum.all?(state.hands, &(length(&1) == 10))
      assert length(state.talon) == 2
      assert state.dealer == 0
      # First bidder is to dealer's right (counter-clockwise)
      assert state.current_player == 2
    end

    test "first bidder varies with dealer" do
      assert new_state(dealer: 0).current_player == 2
      assert new_state(dealer: 1).current_player == 0
      assert new_state(dealer: 2).current_player == 1
    end
  end

  describe "bidding" do
    test "3 passes leads to hand_over" do
      state = new_state()
      {:ok, state} = MockEngine.apply_action(state, :dalje)
      {:ok, state} = MockEngine.apply_action(state, :dalje)
      {:ok, state} = MockEngine.apply_action(state, :dalje)

      assert state.phase == :hand_over
      assert state.scoring_result.all_passed == true
    end

    test "one player bids, others pass — declarer set" do
      state = new_state(dealer: 0)
      # First bidder is seat 2
      {:ok, state} = MockEngine.apply_action(state, {:bid, 2})
      # Next is seat 1 (counter-clockwise: 2 -> 1)
      # Wait - counter-clockwise from 2 is rem(2+2,3) = 1
      {:ok, state} = MockEngine.apply_action(state, :dalje)
      # Next is seat 0
      {:ok, state} = MockEngine.apply_action(state, :dalje)

      # Seat 2 is declarer (only one who didn't pass)
      assert state.declarer == 2
      assert state.phase == :discard
      assert state.highest_bid == 2
      # Declarer now has 12 cards (10 + 2 talon)
      assert length(Enum.at(state.hands, 2)) == 12
    end

    test "rejects illegal bids" do
      state = new_state()
      {:ok, state} = MockEngine.apply_action(state, {:bid, 3})
      # Next player can't bid lower
      assert {:error, :illegal_action} = MockEngine.apply_action(state, {:bid, 2})
    end
  end

  describe "discard" do
    test "removes 2 cards from 12-card hand" do
      state = setup_discard_phase()
      hand = Enum.at(state.hands, state.declarer)
      assert length(hand) == 12

      [c1, c2 | _] = hand
      {:ok, state} = MockEngine.apply_action(state, {:discard, c1, c2})

      assert state.phase == :declare_game
      assert length(Enum.at(state.hands, state.declarer)) == 10
      assert state.discards == [c1, c2]
    end
  end

  describe "trick play" do
    test "10 tricks complete leads to scoring" do
      state = setup_trick_play_phase()

      # Play all 10 tricks
      state = play_all_tricks(state)

      assert state.phase == :scoring
      assert Enum.sum(state.tricks_won) == 10
    end

    test "follow suit enforced" do
      state = setup_trick_play_phase()
      leader = state.current_player
      leader_hand = Enum.at(state.hands, leader)

      # Leader plays first card
      first_card = hd(leader_hand)
      {:ok, state} = MockEngine.apply_action(state, {:play, first_card})

      # Next player
      follower = state.current_player
      follower_hand = Enum.at(state.hands, follower)
      {led_suit, _} = first_card

      suited = Enum.filter(follower_hand, fn {s, _} -> s == led_suit end)
      legal = MockEngine.get_legal_actions(state)

      if suited != [] do
        # Must follow suit — only suited cards are legal
        assert Enum.all?(legal, fn {:play, {s, _}} -> s == led_suit end)
      end
    end
  end

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

    test "talon visible after bid" do
      state = setup_discard_phase()
      view = MockEngine.get_player_view(state, state.declarer)
      assert view.talon != nil
      assert length(view.talon) == 2
    end

    test "discards hidden from non-declarer" do
      state = setup_discard_phase()
      declarer = state.declarer
      hand = Enum.at(state.hands, declarer)
      [c1, c2 | _] = hand
      {:ok, state} = MockEngine.apply_action(state, {:discard, c1, c2})

      non_declarer = rem(declarer + 1, 3)
      view = MockEngine.get_player_view(state, non_declarer)
      assert view.discards == nil

      declarer_view = MockEngine.get_player_view(state, declarer)
      assert declarer_view.discards == [c1, c2]
    end

    test "legal_actions only for current player" do
      state = new_state()
      current = state.current_player
      other = rem(current + 1, 3)

      current_view = MockEngine.get_player_view(state, current)
      other_view = MockEngine.get_player_view(state, other)

      assert current_view.legal_actions != []
      assert other_view.legal_actions == []
    end
  end

  describe "defense" do
    test "both ne_dodjem — free pass for declarer, goes to scoring" do
      state = setup_defense_phase()
      {:ok, state} = MockEngine.apply_action(state, :ne_dodjem)
      {:ok, state} = MockEngine.apply_action(state, :ne_dodjem)

      assert state.phase == :scoring
      assert state.defenders == []
      assert state.scoring_result.declarer_passed == true
    end

    test "at least one dodjem — goes to trick play" do
      state = setup_defense_phase()
      {:ok, state} = MockEngine.apply_action(state, :dodjem)
      {:ok, state} = MockEngine.apply_action(state, :ne_dodjem)

      assert state.phase == :trick_play
      assert length(state.defenders) == 1
    end
  end

  ## Helpers to set up various phases

  defp setup_discard_phase do
    state = new_state(dealer: 0)
    {:ok, state} = MockEngine.apply_action(state, {:bid, 2})
    {:ok, state} = MockEngine.apply_action(state, :dalje)
    {:ok, state} = MockEngine.apply_action(state, :dalje)
    state
  end

  defp setup_defense_phase do
    state = setup_discard_phase()
    hand = Enum.at(state.hands, state.declarer)
    [c1, c2 | _] = hand
    {:ok, state} = MockEngine.apply_action(state, {:discard, c1, c2})
    # Declare a non-betl game so defense phase happens
    {:ok, state} = MockEngine.apply_action(state, :pik)
    state
  end

  defp setup_trick_play_phase do
    state = setup_defense_phase()
    {:ok, state} = MockEngine.apply_action(state, :dodjem)
    {:ok, state} = MockEngine.apply_action(state, :dodjem)
    state
  end

  defp play_all_tricks(state) do
    if state.phase != :trick_play do
      state
    else
      [action | _] = MockEngine.get_legal_actions(state)
      {:ok, state} = MockEngine.apply_action(state, action)
      play_all_tricks(state)
    end
  end
end
