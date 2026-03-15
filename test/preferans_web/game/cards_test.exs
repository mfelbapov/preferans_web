defmodule PreferansWeb.Game.CardsTest do
  use ExUnit.Case, async: true

  alias PreferansWeb.Game.Cards

  describe "deck/0" do
    test "returns 32 unique cards" do
      deck = Cards.deck()
      assert length(deck) == 32
      assert length(Enum.uniq(deck)) == 32
    end

    test "contains all suits and ranks" do
      deck = Cards.deck()

      for suit <- [:pik, :karo, :herc, :tref],
          rank <- [:seven, :eight, :nine, :ten, :jack, :queen, :king, :ace] do
        assert {suit, rank} in deck
      end
    end
  end

  describe "deal/0" do
    test "returns 3 hands of 10 and talon of 2" do
      {hands, talon} = Cards.deal()
      assert length(hands) == 3
      assert Enum.all?(hands, &(length(&1) == 10))
      assert length(talon) == 2
    end

    test "all 32 cards accounted for" do
      {hands, talon} = Cards.deal()
      all_cards = List.flatten(hands) ++ talon
      assert length(all_cards) == 32
      assert length(Enum.uniq(all_cards)) == 32
    end
  end

  describe "sort_hand/1" do
    test "sorts by suit then rank descending" do
      hand = [{:herc, :seven}, {:pik, :ace}, {:pik, :seven}, {:karo, :king}]
      sorted = Cards.sort_hand(hand)
      assert sorted == [{:pik, :ace}, {:pik, :seven}, {:karo, :king}, {:herc, :seven}]
    end
  end

  describe "rank_value/1" do
    test "ordering is correct" do
      assert Cards.rank_value(:seven) == 0
      assert Cards.rank_value(:ace) == 7
      assert Cards.rank_value(:seven) < Cards.rank_value(:eight)
      assert Cards.rank_value(:king) < Cards.rank_value(:ace)
    end
  end

  describe "game_value/1" do
    test "returns correct values" do
      assert Cards.game_value(:pik) == 2
      assert Cards.game_value(:karo) == 3
      assert Cards.game_value(:herc) == 4
      assert Cards.game_value(:tref) == 5
      assert Cards.game_value(:betl) == 6
      assert Cards.game_value(:sans) == 7
    end
  end

  describe "card_to_string/1" do
    test "formats cards correctly" do
      assert Cards.card_to_string({:pik, :ace}) == "A♠"
      assert Cards.card_to_string({:herc, :king}) == "K♥"
      assert Cards.card_to_string({:tref, :seven}) == "7♣"
      assert Cards.card_to_string({:karo, :ten}) == "10♦"
    end
  end
end
