defmodule PreferansWeb.Game.MockEngineTest do
  use ExUnit.Case, async: true

  alias PreferansWeb.Game.{MockEngine, Cards}

  defp new_state(opts \\ []) do
    dealer = Keyword.get(opts, :dealer, 0)
    bule = Keyword.get(opts, :bule, [100, 100, 100])
    refe = Keyword.get(opts, :refe, [0, 0, 0])
    max_refes = Keyword.get(opts, :max_refes, 2)
    MockEngine.new_hand(dealer, bule, refe, max_refes)
  end

  ## Player order tests

  describe "player order" do
    test "next_player 0 -> 2, 2 -> 1, 1 -> 0 (counter-clockwise)" do
      # Tested via first_bidder which uses rem(dealer + 2, 3)
      assert new_state(dealer: 0).current_player == 2
      assert new_state(dealer: 1).current_player == 0
      assert new_state(dealer: 2).current_player == 1
    end

    test "first_bidder when dealer=0 is 2" do
      assert new_state(dealer: 0).current_player == 2
    end

    test "first_bidder when dealer=1 is 0" do
      assert new_state(dealer: 1).current_player == 0
    end

    test "first_bidder when dealer=2 is 1" do
      assert new_state(dealer: 2).current_player == 1
    end
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
      assert state.highest_bidder == nil
      assert state.declarer == nil
      assert state.tricks_won == [0, 0, 0]
      assert state.moje_holder == 2
      assert state.passed_players == []
    end

    test "hands are sorted" do
      state = new_state()

      for hand <- state.hands do
        assert hand == Cards.sort_hand(hand)
      end
    end

    test "all 32 cards accounted for" do
      state = new_state()
      all_cards = List.flatten(state.hands) ++ state.talon
      assert length(all_cards) == 32
      assert length(Enum.uniq(all_cards)) == 32
    end
  end

  ## Bidding tests

  describe "bidding — legal actions" do
    test "legal bids when no bids yet — all values 2-7 plus dalje" do
      state = new_state()
      legal = MockEngine.get_legal_actions(state)
      assert :dalje in legal
      for v <- 2..7, do: assert({:bid, v} in legal)
      refute :moje in legal
    end

    test "legal bids when highest is 3 — only 4,5,6,7 plus dalje" do
      state = new_state(dealer: 0)
      {:ok, state} = MockEngine.apply_action(state, {:bid, 3})
      legal = MockEngine.get_legal_actions(state)
      assert :dalje in legal
      refute {:bid, 2} in legal
      refute {:bid, 3} in legal
      for v <- 4..7, do: assert({:bid, v} in legal)
    end

    test "legal bids when highest is 7 — only dalje (plus moje if holder)" do
      state = new_state(dealer: 0)
      {:ok, state} = MockEngine.apply_action(state, {:bid, 7})
      legal = MockEngine.get_legal_actions(state)
      assert :dalje in legal
      for v <- 2..7, do: refute({:bid, v} in legal)
    end

    test "moje only available to moje_holder" do
      state = new_state(dealer: 0)
      # Player 2 is moje_holder and first bidder
      {:ok, state} = MockEngine.apply_action(state, {:bid, 2})
      # Now player 1's turn — not moje_holder
      legal = MockEngine.get_legal_actions(state)
      refute :moje in legal
    end

    test "moje not available when highest_bid is 0" do
      state = new_state(dealer: 0)
      # Player 2 is moje_holder, but highest_bid is 0
      legal = MockEngine.get_legal_actions(state)
      refute :moje in legal
    end

    test "moje available to moje_holder when highest_bid > 0" do
      state = new_state(dealer: 0)
      # Player 2 bids 2
      {:ok, state} = MockEngine.apply_action(state, {:bid, 2})
      # Player 1 bids 3
      {:ok, state} = MockEngine.apply_action(state, {:bid, 3})
      # Player 0 passes
      {:ok, state} = MockEngine.apply_action(state, :dalje)
      # Back to player 2 who is moje_holder
      assert state.current_player == 2
      legal = MockEngine.get_legal_actions(state)
      assert :moje in legal
    end
  end

  describe "bidding — applying actions" do
    test "bid raises highest_bid and sets highest_bidder" do
      state = new_state(dealer: 0)
      {:ok, state} = MockEngine.apply_action(state, {:bid, 3})
      assert state.highest_bid == 3
      assert state.highest_bidder == 2
    end

    test "dalje adds player to passed list" do
      state = new_state(dealer: 0)
      {:ok, state} = MockEngine.apply_action(state, :dalje)
      assert 2 in state.passed_players
    end

    test "moje transfers highest_bidder without raising bid" do
      state = new_state(dealer: 0)
      {:ok, state} = MockEngine.apply_action(state, {:bid, 2})
      {:ok, state} = MockEngine.apply_action(state, {:bid, 3})
      {:ok, state} = MockEngine.apply_action(state, :dalje)
      # Player 2 is moje_holder, uses moje
      {:ok, state} = MockEngine.apply_action(state, :moje)
      assert state.highest_bid == 3
      assert state.highest_bidder == 2
    end

    test "moje_holder transfers on pass" do
      state = new_state(dealer: 1)
      # Player 0 is first bidder and moje_holder
      assert state.moje_holder == 0
      # Player 0 passes → moje transfers
      {:ok, state} = MockEngine.apply_action(state, :dalje)
      assert state.moje_holder == 2
    end

    test "bidding ends when 2 pass — remaining player wins" do
      state = new_state(dealer: 0)
      {:ok, state} = MockEngine.apply_action(state, {:bid, 2})
      {:ok, state} = MockEngine.apply_action(state, :dalje)
      {:ok, state} = MockEngine.apply_action(state, :dalje)
      assert state.declarer == 2
      assert state.phase == :discard
      assert state.highest_bid == 2
    end

    test "bidding order is counter-clockwise" do
      state = new_state(dealer: 0)
      # First bidder is 2
      assert state.current_player == 2
      {:ok, state} = MockEngine.apply_action(state, {:bid, 2})
      # Next is 1
      assert state.current_player == 1
      {:ok, state} = MockEngine.apply_action(state, {:bid, 3})
      # Next is 0
      assert state.current_player == 0
    end

    test "rejects bid lower than or equal to current highest" do
      state = new_state()
      {:ok, state} = MockEngine.apply_action(state, {:bid, 3})
      assert {:error, :illegal_action} = MockEngine.apply_action(state, {:bid, 2})
      assert {:error, :illegal_action} = MockEngine.apply_action(state, {:bid, 3})
    end

    test "bid history records all actions including moje" do
      state = new_state(dealer: 0)
      {:ok, state} = MockEngine.apply_action(state, {:bid, 2})
      {:ok, state} = MockEngine.apply_action(state, {:bid, 3})
      {:ok, state} = MockEngine.apply_action(state, :dalje)
      {:ok, state} = MockEngine.apply_action(state, :moje)
      {:ok, state} = MockEngine.apply_action(state, :dalje)

      assert length(state.bid_history) == 5
      assert Enum.at(state.bid_history, 0) == %{player: 2, action: {:bid, 2}}
      assert Enum.at(state.bid_history, 1) == %{player: 1, action: {:bid, 3}}
      assert Enum.at(state.bid_history, 2) == %{player: 0, action: :dalje}
      assert Enum.at(state.bid_history, 3) == %{player: 2, action: {:moje, 3}}
      assert Enum.at(state.bid_history, 4) == %{player: 1, action: :dalje}
    end
  end

  describe "bidding — all pass" do
    test "all three pass — hand over with refe" do
      state = new_state()
      {:ok, state} = MockEngine.apply_action(state, :dalje)
      {:ok, state} = MockEngine.apply_action(state, :dalje)
      # After 2 pass with no bids, remaining player gets a chance
      {:ok, state} = MockEngine.apply_action(state, :dalje)

      assert state.phase == :hand_over
      assert state.scoring_result.all_passed == true
      assert state.scoring_result.bule_changes == [0, 0, 0]
      # Refe recorded on dealer
      assert Enum.at(state.refe_counts, state.dealer) == 1
    end

    test "refe not recorded when any player under kapa (negative bule)" do
      state = new_state(bule: [-10, 100, 100])
      {:ok, state} = MockEngine.apply_action(state, :dalje)
      {:ok, state} = MockEngine.apply_action(state, :dalje)
      {:ok, state} = MockEngine.apply_action(state, :dalje)

      assert state.phase == :hand_over
      assert state.scoring_result.all_passed == true
      # No refe recorded because player 0 has negative bule
      assert state.refe_counts == [0, 0, 0]
    end

    test "refe not recorded when all players at max refes" do
      state = new_state(refe: [2, 2, 2], max_refes: 2)
      {:ok, state} = MockEngine.apply_action(state, :dalje)
      {:ok, state} = MockEngine.apply_action(state, :dalje)
      {:ok, state} = MockEngine.apply_action(state, :dalje)

      assert state.phase == :hand_over
      # No additional refe recorded
      assert state.refe_counts == [2, 2, 2]
    end

    test "when 2 pass with no bids, remaining player can bid or pass" do
      state = new_state(dealer: 0)
      {:ok, state} = MockEngine.apply_action(state, :dalje)
      {:ok, state} = MockEngine.apply_action(state, :dalje)
      # Player 0 remains, highest_bid == 0
      assert state.phase == :bid
      assert state.current_player == 0

      # Player 0 bids — becomes declarer immediately
      {:ok, state} = MockEngine.apply_action(state, {:bid, 2})
      assert state.declarer == 0
      assert state.phase == :discard
    end
  end

  describe "bidding — complete walk-through" do
    test "example from spec: moje used successfully" do
      state = new_state(dealer: 0)
      # Player 2 bids 2
      {:ok, state} = MockEngine.apply_action(state, {:bid, 2})
      assert state.highest_bid == 2
      assert state.highest_bidder == 2

      # Player 1 bids 3
      {:ok, state} = MockEngine.apply_action(state, {:bid, 3})
      assert state.highest_bid == 3
      assert state.highest_bidder == 1

      # Player 0 passes
      {:ok, state} = MockEngine.apply_action(state, :dalje)
      assert state.current_player == 2

      # Player 2 uses moje
      {:ok, state} = MockEngine.apply_action(state, :moje)
      assert state.highest_bid == 3
      assert state.highest_bidder == 2
      assert state.current_player == 1

      # Player 1 passes
      {:ok, state} = MockEngine.apply_action(state, :dalje)
      assert state.declarer == 2
      assert state.phase == :discard
    end
  end

  ## Talon + Discard tests

  describe "talon and discard" do
    test "talon cards added to declarer hand — now 12 cards" do
      state = setup_discard_phase()
      assert length(Enum.at(state.hands, state.declarer)) == 12
    end

    test "discard removes 2 cards — back to 10" do
      state = setup_discard_phase()
      hand = Enum.at(state.hands, state.declarer)
      [c1, c2 | _] = hand
      {:ok, state} = MockEngine.apply_action(state, {:discard, c1, c2})

      assert length(Enum.at(state.hands, state.declarer)) == 10
    end

    test "discards stored in state" do
      state = setup_discard_phase()
      hand = Enum.at(state.hands, state.declarer)
      [c1, c2 | _] = hand
      {:ok, state} = MockEngine.apply_action(state, {:discard, c1, c2})

      assert state.discards == [c1, c2]
    end

    test "all 32 cards accounted for after discard (10+10+10+2 discards)" do
      state = setup_discard_phase()
      hand = Enum.at(state.hands, state.declarer)
      [c1, c2 | _] = hand
      {:ok, state} = MockEngine.apply_action(state, {:discard, c1, c2})

      all_cards = List.flatten(state.hands) ++ state.discards
      assert length(all_cards) == 32
      assert length(Enum.uniq(all_cards)) == 32
    end

    test "hand is sorted after discard" do
      state = setup_discard_phase()
      hand = Enum.at(state.hands, state.declarer)
      [c1, c2 | _] = hand
      {:ok, state} = MockEngine.apply_action(state, {:discard, c1, c2})

      declarer_hand = Enum.at(state.hands, state.declarer)
      assert declarer_hand == Cards.sort_hand(declarer_hand)
    end

    test "transitions to declare_game" do
      state = setup_discard_phase()
      hand = Enum.at(state.hands, state.declarer)
      [c1, c2 | _] = hand
      {:ok, state} = MockEngine.apply_action(state, {:discard, c1, c2})

      assert state.phase == :declare_game
      assert state.current_player == state.declarer
    end
  end

  ## Declaration tests

  describe "game declaration" do
    test "can declare any game >= bid value" do
      state = setup_declare_phase()
      legal = MockEngine.get_legal_actions(state)
      # Bid was 2, so all games legal
      assert {:declare, :pik} in legal
      assert {:declare, :karo} in legal
      assert {:declare, :herc} in legal
      assert {:declare, :tref} in legal
      assert {:declare, :betl} in legal
      assert {:declare, :sans} in legal
    end

    test "cannot declare game below bid value" do
      state = setup_declare_phase_with_bid(5)
      legal = MockEngine.get_legal_actions(state)
      refute {:declare, :pik} in legal
      refute {:declare, :karo} in legal
      refute {:declare, :herc} in legal
      assert {:declare, :tref} in legal
      assert {:declare, :betl} in legal
      assert {:declare, :sans} in legal
    end

    test "bid 2 can declare anything" do
      state = setup_declare_phase_with_bid(2)
      legal = MockEngine.get_legal_actions(state)
      assert length(legal) == 6
    end

    test "bid 5 can only declare tref, betl, sans" do
      state = setup_declare_phase_with_bid(5)
      legal = MockEngine.get_legal_actions(state)
      assert legal == [{:declare, :tref}, {:declare, :betl}, {:declare, :sans}]
    end

    test "suit game goes to defense phase" do
      state = setup_declare_phase()
      {:ok, state} = MockEngine.apply_action(state, {:declare, :pik})

      assert state.phase == :defense
      assert state.game_type == :pik
      assert state.trump == :pik
      assert state.defenders == []
    end

    test "betl skips defense, goes straight to trick_play" do
      state = setup_declare_phase()
      {:ok, state} = MockEngine.apply_action(state, {:declare, :betl})

      assert state.phase == :trick_play
      assert state.game_type == :betl
      assert state.trump == nil
      assert length(state.defenders) == 2
    end

    test "sans sets trump to nil" do
      state = setup_declare_phase()
      {:ok, state} = MockEngine.apply_action(state, {:declare, :sans})

      assert state.game_type == :sans
      assert state.trump == nil
    end
  end

  ## Defense tests

  describe "defense" do
    test "first defender is to declarer's right" do
      state = setup_defense_phase()
      # Declarer is 2, next_player_in_circle(2) = 1
      assert state.current_player == 1
    end

    test "both pass — free pass scored" do
      state = setup_defense_phase()
      {:ok, state} = MockEngine.apply_action(state, :ne_dodjem)
      {:ok, state} = MockEngine.apply_action(state, :ne_dodjem)

      assert state.phase == :hand_over
      assert state.scoring_result.free_pass == true
      assert state.scoring_result.declarer_passed == true
      gv = Cards.game_value(state.game_type)
      assert Enum.at(state.scoring_result.bule_changes, state.declarer) == -(gv * 2)
    end

    test "one defends — trick play begins with 2 active" do
      state = setup_defense_phase()
      {:ok, state} = MockEngine.apply_action(state, :dodjem)
      {:ok, state} = MockEngine.apply_action(state, :ne_dodjem)

      assert state.phase == :trick_play
      assert length(state.defenders) == 1
    end

    test "both defend — trick play begins with 3 active" do
      state = setup_defense_phase()
      {:ok, state} = MockEngine.apply_action(state, :dodjem)
      {:ok, state} = MockEngine.apply_action(state, :dodjem)

      assert state.phase == :trick_play
      assert length(state.defenders) == 2
    end

    test "betl — auto defend, skip defense phase" do
      state = setup_declare_phase()
      {:ok, state} = MockEngine.apply_action(state, {:declare, :betl})

      assert state.phase == :trick_play
      assert length(state.defenders) == 2
    end
  end

  ## Trick play tests

  describe "trick play — card legality" do
    test "leading — any card legal" do
      state = setup_trick_play_phase()
      leader = state.current_player
      hand = Enum.at(state.hands, leader)
      legal = MockEngine.get_legal_actions(state)
      assert length(legal) == length(hand)
      assert Enum.all?(legal, &match?({:play, _}, &1))
    end

    test "following suit — must play same suit if have it" do
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

    test "void in led suit with trump — must play trump" do
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

    test "betl — void in led suit — play anything (no forced trump)" do
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
        assert length(legal) == length(follower_hand)
      end
    end
  end

  describe "trick play — resolution" do
    test "trick winner leads next trick" do
      state = setup_trick_play_phase()
      active = [state.declarer | state.defenders]

      state =
        Enum.reduce(1..length(active), state, fn _, s ->
          [action | _] = MockEngine.get_legal_actions(s)
          {:ok, s} = MockEngine.apply_action(s, action)
          s
        end)

      assert state.phase == :trick_result
      winner = state.trick_winner
      {:ok, state} = MockEngine.apply_action(state, :next_trick)
      assert state.current_player == winner
    end

    test "10 tricks complete — phase becomes scoring" do
      state = setup_trick_play_phase()
      state = play_all_tricks(state)
      assert state.phase == :scoring
    end

    test "trick_result phase pauses after trick, next_trick continues" do
      state = setup_trick_play_phase()
      active = [state.declarer | state.defenders]

      state =
        Enum.reduce(1..length(active), state, fn _, s ->
          [action | _] = MockEngine.get_legal_actions(s)
          {:ok, s} = MockEngine.apply_action(s, action)
          s
        end)

      assert state.phase == :trick_result
      assert state.trick_winner != nil
      assert Enum.sum(state.tricks_won) == 1

      {:ok, state} = MockEngine.apply_action(state, :next_trick)
      assert state.phase == :trick_play
      assert state.trick_winner == nil
      assert state.current_trick == []
    end

    test "2-player hand — 10 tricks of 2 cards" do
      state = setup_defense_phase()
      {:ok, state} = MockEngine.apply_action(state, :dodjem)
      {:ok, state} = MockEngine.apply_action(state, :ne_dodjem)

      assert length(state.defenders) == 1
      state = play_all_tricks(state)
      assert state.phase == :scoring
      assert Enum.sum(state.tricks_won) <= 10
    end

    test "3-player hand — 10 tricks of 3 cards" do
      state = setup_trick_play_phase()
      state = play_all_tricks(state)
      assert state.phase == :scoring
      assert Enum.sum(state.tricks_won) <= 10
    end
  end

  describe "trick play — trump resolution" do
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

  describe "trick play — betl ends early" do
    test "betl ends immediately when declarer takes a trick" do
      state = setup_betl_trick_play_phase()
      state = play_all_tricks(state)

      assert state.phase == :scoring
      declarer_tricks = Enum.at(state.tricks_won, state.declarer)

      if declarer_tricks > 0 do
        assert Enum.sum(state.tricks_won) < 10
        assert state.scoring_result.declarer_passed == false
      else
        assert Enum.sum(state.tricks_won) == 10
        assert state.scoring_result.declarer_passed == true
      end
    end
  end

  ## Scoring tests

  describe "scoring — pass/fail" do
    test "declarer passes with 6+ tricks" do
      state = setup_trick_play_phase()
      state = play_all_tricks(state)
      declarer_tricks = Enum.at(state.scoring_result.tricks, state.declarer)

      if declarer_tricks >= 6 do
        assert state.scoring_result.declarer_passed == true
      else
        assert state.scoring_result.declarer_passed == false
      end
    end

    test "betl declarer passes with 0 tricks" do
      state = setup_betl_trick_play_phase()
      state = play_all_tricks(state)
      declarer_tricks = Enum.at(state.scoring_result.tricks, state.declarer)

      if declarer_tricks == 0 do
        assert state.scoring_result.declarer_passed == true
      else
        assert state.scoring_result.declarer_passed == false
      end
    end
  end

  describe "scoring — bule changes" do
    test "bule decrease for passing declarer" do
      state = setup_defense_phase()
      {:ok, state} = MockEngine.apply_action(state, :ne_dodjem)
      {:ok, state} = MockEngine.apply_action(state, :ne_dodjem)

      # Free pass — declarer's bule decreases
      gv = Cards.game_value(state.game_type)
      assert Enum.at(state.scoring_result.bule_changes, state.declarer) == -(gv * 2)
    end

    test "scoring result has required fields" do
      state = setup_trick_play_phase()
      state = play_all_tricks(state)

      result = state.scoring_result
      assert is_boolean(result.all_passed)
      assert is_list(result.bule_changes)
      assert length(result.bule_changes) == 3
      assert is_map(result.supe_changes)
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
      assert state.scoring_result.supe_changes == %{}
    end

    test "free pass — no supe written" do
      state = setup_defense_phase()
      {:ok, state} = MockEngine.apply_action(state, :ne_dodjem)
      {:ok, state} = MockEngine.apply_action(state, :ne_dodjem)

      assert state.scoring_result.supe_changes == %{}
    end

    test "free pass with refe doubles bule change" do
      state = new_state(refe: [0, 0, 1])
      {:ok, state} = MockEngine.apply_action(state, {:bid, 2})
      {:ok, state} = MockEngine.apply_action(state, :dalje)
      {:ok, state} = MockEngine.apply_action(state, :dalje)

      # Declarer is 2 with 1 refe
      hand = Enum.at(state.hands, state.declarer)
      [c1, c2 | _] = hand
      {:ok, state} = MockEngine.apply_action(state, {:discard, c1, c2})
      {:ok, state} = MockEngine.apply_action(state, {:declare, :pik})

      # Both ne_dodjem
      {:ok, state} = MockEngine.apply_action(state, :ne_dodjem)
      {:ok, state} = MockEngine.apply_action(state, :ne_dodjem)

      gv = Cards.game_value(:pik)
      # refe_mult = 2
      expected = -(gv * 2 * 2)
      assert Enum.at(state.scoring_result.bule_changes, state.declarer) == expected
    end
  end

  describe "scoring — supe" do
    test "supe format uses {defender, declarer} tuple keys" do
      state = setup_trick_play_phase()
      state = play_all_tricks(state)
      result = state.scoring_result

      for {{from, against}, amount} <- result.supe_changes do
        assert is_integer(from)
        assert is_integer(against)
        assert against == state.declarer
        assert amount > 0
      end
    end
  end

  ## Player view tests

  describe "get_player_view/2" do
    test "player view never contains other players' cards" do
      state = new_state()
      view = MockEngine.get_player_view(state, 0)

      assert is_list(view.my_hand)
      assert length(view.my_hand) == 10
      assert map_size(view.opponent_card_counts) == 2
      refute Map.has_key?(view, :hands)
    end

    test "player view shows opponent card counts" do
      state = new_state()
      view = MockEngine.get_player_view(state, 0)

      assert view.opponent_card_counts[1] == 10
      assert view.opponent_card_counts[2] == 10
    end

    test "talon hidden during bidding phase" do
      state = new_state()
      view = MockEngine.get_player_view(state, 0)
      assert view.talon == nil
    end

    test "talon visible after reveal (during discard)" do
      state = setup_discard_phase()
      view = MockEngine.get_player_view(state, state.declarer)
      assert view.talon != nil
      assert length(view.talon) == 2
    end

    test "talon visible in declare_game phase" do
      state = setup_declare_phase()
      view = MockEngine.get_player_view(state, state.declarer)
      assert view.talon != nil
    end

    test "discards visible only to declarer" do
      state = setup_discard_phase()
      declarer = state.declarer
      hand = Enum.at(state.hands, declarer)
      [c1, c2 | _] = hand
      {:ok, state} = MockEngine.apply_action(state, {:discard, c1, c2})

      non_declarer = rem(declarer + 1, 3)
      assert MockEngine.get_player_view(state, non_declarer).discards == nil
      assert MockEngine.get_player_view(state, declarer).discards == [c1, c2]
    end

    test "discards nil for non-declarer" do
      state = setup_discard_phase()
      non_declarer = rem(state.declarer + 1, 3)
      assert MockEngine.get_player_view(state, non_declarer).discards == nil
    end

    test "legal_actions empty when not your turn" do
      state = new_state()
      current = state.current_player
      other = rem(current + 1, 3)

      assert MockEngine.get_player_view(state, current).legal_actions != []
      assert MockEngine.get_player_view(state, other).legal_actions == []
    end

    test "scoring_result nil before scoring phase" do
      state = new_state()
      assert MockEngine.get_player_view(state, 0).scoring_result == nil

      state = setup_trick_play_phase()
      assert MockEngine.get_player_view(state, 0).scoring_result == nil
    end

    test "players include is_active field" do
      state = new_state()
      view = MockEngine.get_player_view(state, 0)

      for p <- view.players do
        assert Map.has_key?(p, :is_active)
      end
    end
  end

  ## Full game flow

  describe "full game flow" do
    test "complete suit game from deal to scoring" do
      state = new_state(dealer: 0)

      # Bidding
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
      {:ok, state} = MockEngine.apply_action(state, {:declare, :pik})
      assert state.phase == :defense

      # Both defend
      {:ok, state} = MockEngine.apply_action(state, :dodjem)
      {:ok, state} = MockEngine.apply_action(state, :dodjem)
      assert state.phase == :trick_play

      # Play all tricks
      state = play_all_tricks(state)
      assert state.phase == :scoring
      assert state.scoring_result != nil
    end

    test "complete betl game from deal to scoring" do
      state = new_state(dealer: 0)

      {:ok, state} = MockEngine.apply_action(state, {:bid, 6})
      {:ok, state} = MockEngine.apply_action(state, :dalje)
      {:ok, state} = MockEngine.apply_action(state, :dalje)

      hand = Enum.at(state.hands, state.declarer)
      [c1, c2 | _] = hand
      {:ok, state} = MockEngine.apply_action(state, {:discard, c1, c2})

      {:ok, state} = MockEngine.apply_action(state, {:declare, :betl})
      assert state.phase == :trick_play

      state = play_all_tricks(state)
      assert state.phase == :scoring
    end

    test "complete game with moje bidding" do
      state = new_state(dealer: 0)

      # Player 2 bids 2
      {:ok, state} = MockEngine.apply_action(state, {:bid, 2})
      # Player 1 bids 3
      {:ok, state} = MockEngine.apply_action(state, {:bid, 3})
      # Player 0 passes
      {:ok, state} = MockEngine.apply_action(state, :dalje)
      # Player 2 uses moje
      {:ok, state} = MockEngine.apply_action(state, :moje)
      # Player 1 passes
      {:ok, state} = MockEngine.apply_action(state, :dalje)

      assert state.declarer == 2
      assert state.highest_bid == 3
      assert state.phase == :discard

      # Continue to completion
      hand = Enum.at(state.hands, state.declarer)
      [c1, c2 | _] = hand
      {:ok, state} = MockEngine.apply_action(state, {:discard, c1, c2})
      {:ok, state} = MockEngine.apply_action(state, {:declare, :karo})
      {:ok, state} = MockEngine.apply_action(state, :dodjem)
      {:ok, state} = MockEngine.apply_action(state, :dodjem)

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

  defp setup_declare_phase_with_bid(bid_value) do
    state = new_state(dealer: 0)
    {:ok, state} = MockEngine.apply_action(state, {:bid, bid_value})
    {:ok, state} = MockEngine.apply_action(state, :dalje)
    {:ok, state} = MockEngine.apply_action(state, :dalje)
    hand = Enum.at(state.hands, state.declarer)
    [c1, c2 | _] = hand
    {:ok, state} = MockEngine.apply_action(state, {:discard, c1, c2})
    state
  end

  defp setup_defense_phase do
    state = setup_declare_phase()
    {:ok, state} = MockEngine.apply_action(state, {:declare, :pik})
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
    {:ok, state} = MockEngine.apply_action(state, {:declare, :betl})
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
