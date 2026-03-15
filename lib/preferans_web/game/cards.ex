defmodule PreferansWeb.Game.Cards do
  @moduledoc """
  Utility module for the 32-card Preferans deck.

  Cards are {suit, rank} tuples.
  Suits: :pik, :karo, :herc, :tref
  Ranks: :seven, :eight, :nine, :ten, :jack, :queen, :king, :ace
  """

  @suits [:pik, :karo, :herc, :tref]
  @ranks [:seven, :eight, :nine, :ten, :jack, :queen, :king, :ace]

  @rank_values %{
    seven: 0,
    eight: 1,
    nine: 2,
    ten: 3,
    jack: 4,
    queen: 5,
    king: 6,
    ace: 7
  }

  @suit_indices %{pik: 0, karo: 1, herc: 2, tref: 3}

  @game_values %{pik: 2, karo: 3, herc: 4, tref: 5, betl: 6, sans: 7}

  @suit_symbols %{pik: "♠", karo: "♦", herc: "♥", tref: "♣"}

  @rank_symbols %{
    seven: "7",
    eight: "8",
    nine: "9",
    ten: "10",
    jack: "J",
    queen: "Q",
    king: "K",
    ace: "A"
  }

  def suits, do: @suits
  def ranks, do: @ranks

  def deck do
    for suit <- @suits, rank <- @ranks, do: {suit, rank}
  end

  def shuffle(cards) do
    Enum.shuffle(cards)
  end

  def deal do
    cards = shuffle(deck())
    {hand0, rest} = Enum.split(cards, 10)
    {hand1, rest} = Enum.split(rest, 10)
    {hand2, talon} = Enum.split(rest, 10)
    {[hand0, hand1, hand2], talon}
  end

  def sort_hand(hand) do
    Enum.sort_by(hand, fn {suit, rank} ->
      {suit_index(suit), -rank_value(rank)}
    end)
  end

  def rank_value(rank), do: Map.fetch!(@rank_values, rank)

  def suit_index(suit), do: Map.fetch!(@suit_indices, suit)

  def card_to_string({suit, rank}) do
    @rank_symbols[rank] <> @suit_symbols[suit]
  end

  def game_value(game_type), do: Map.fetch!(@game_values, game_type)
end
