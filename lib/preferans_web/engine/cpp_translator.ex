defmodule PreferansWeb.Engine.CppTranslator do
  @moduledoc """
  Bidirectional translation between C++ engine JSON format and the
  internal Elixir format used by GameLive and components.

  C++ uses string cards ("AS", "10H"), flat action types ("bid_2", "declare_pik"),
  and string phases ("bid", "trick_play").

  Elixir uses {suit, rank} tuples, atom/tuple actions (:dalje, {:bid, 2}),
  and atom phases (:bid, :trick_play).
  """

  alias PreferansWeb.Game.Cards

  ## Card translation

  @suit_from_cpp %{"S" => :pik, "D" => :karo, "H" => :herc, "C" => :tref}
  @suit_to_cpp %{pik: "S", karo: "D", herc: "H", tref: "C"}

  @rank_from_cpp %{
    "7" => :seven,
    "8" => :eight,
    "9" => :nine,
    "10" => :ten,
    "J" => :jack,
    "Q" => :queen,
    "K" => :king,
    "A" => :ace
  }
  @rank_to_cpp %{
    seven: "7",
    eight: "8",
    nine: "9",
    ten: "10",
    jack: "J",
    queen: "Q",
    king: "K",
    ace: "A"
  }

  def parse_card(str) when is_binary(str) do
    {rank_str, suit_char} = split_card_string(str)
    {Map.fetch!(@suit_from_cpp, suit_char), Map.fetch!(@rank_from_cpp, rank_str)}
  end

  def card_to_cpp({suit, rank}) do
    Map.fetch!(@rank_to_cpp, rank) <> Map.fetch!(@suit_to_cpp, suit)
  end

  defp split_card_string(str) do
    # Cards are like "AS", "10H", "KD" — suit is always the last character
    suit_char = String.last(str)
    rank_str = String.slice(str, 0..(String.length(str) - 2)//1)
    {rank_str, suit_char}
  end

  ## Phase translation

  @phases_from_cpp %{
    "bid" => :bid,
    "discard" => :discard,
    "declare_game" => :declare_game,
    "defense" => :defense,
    "kontra" => :kontra,
    "trick_play" => :trick_play,
    "hand_over" => :hand_over
  }

  def parse_phase(str), do: Map.fetch!(@phases_from_cpp, str)

  ## Game type translation

  @game_types_from_cpp %{
    "pik" => :pik,
    "karo" => :karo,
    "herc" => :herc,
    "tref" => :tref,
    "betl" => :betl,
    "sans" => :sans
  }

  @game_types_to_cpp %{
    pik: "pik",
    karo: "karo",
    herc: "herc",
    tref: "tref",
    betl: "betl",
    sans: "sans"
  }

  def parse_game_type(nil), do: nil
  def parse_game_type(str), do: Map.fetch!(@game_types_from_cpp, str)

  ## Action translation: Elixir → C++ JSON

  def action_to_cpp(:dalje), do: %{"type" => "dalje"}
  def action_to_cpp(:moje), do: %{"type" => "moje"}
  def action_to_cpp(:igra), do: %{"type" => "igra"}
  def action_to_cpp(:igra_betl), do: %{"type" => "igra_betl"}
  def action_to_cpp(:igra_sans), do: %{"type" => "igra_sans"}
  def action_to_cpp(:dodjem), do: %{"type" => "dodjem"}
  def action_to_cpp(:ne_dodjem), do: %{"type" => "ne_dodjem"}
  def action_to_cpp(:poziv), do: %{"type" => "poziv"}
  def action_to_cpp(:sam), do: %{"type" => "sam"}
  def action_to_cpp(:idemo_zajedno), do: %{"type" => "idemo_zajedno"}
  def action_to_cpp(:moze), do: %{"type" => "moze"}
  def action_to_cpp(:kontra), do: %{"type" => "kontra"}
  def action_to_cpp(:rekontra), do: %{"type" => "rekontra"}
  def action_to_cpp(:subkontra), do: %{"type" => "subkontra"}
  def action_to_cpp(:mortkontra), do: %{"type" => "mortkontra"}

  def action_to_cpp({:bid, n}), do: %{"type" => "bid_#{n}"}

  def action_to_cpp({:discard, card1, card2}) do
    # C++ engine expects cards in its internal order (lower card first).
    # Normalize by sorting using the engine's card ordering.
    {c1, c2} = order_cards_for_cpp(card1, card2)
    %{"type" => "discard", "card1" => card_to_cpp(c1), "card2" => card_to_cpp(c2)}
  end

  def action_to_cpp({:declare, game}) do
    %{"type" => "declare_#{Map.fetch!(@game_types_to_cpp, game)}"}
  end

  def action_to_cpp({:play, card}) do
    %{"type" => "play_card", "card" => card_to_cpp(card)}
  end

  ## Legal action translation: C++ JSON → Elixir

  def parse_legal_action(%{"type" => "dalje"}), do: :dalje
  def parse_legal_action(%{"type" => "moje"}), do: :moje
  def parse_legal_action(%{"type" => "igra"}), do: :igra
  def parse_legal_action(%{"type" => "igra_betl"}), do: :igra_betl
  def parse_legal_action(%{"type" => "igra_sans"}), do: :igra_sans
  def parse_legal_action(%{"type" => "dodjem"}), do: :dodjem
  def parse_legal_action(%{"type" => "ne_dodjem"}), do: :ne_dodjem
  def parse_legal_action(%{"type" => "poziv"}), do: :poziv
  def parse_legal_action(%{"type" => "sam"}), do: :sam
  def parse_legal_action(%{"type" => "idemo_zajedno"}), do: :idemo_zajedno
  def parse_legal_action(%{"type" => "moze"}), do: :moze
  def parse_legal_action(%{"type" => "kontra"}), do: :kontra
  def parse_legal_action(%{"type" => "rekontra"}), do: :rekontra
  def parse_legal_action(%{"type" => "subkontra"}), do: :subkontra
  def parse_legal_action(%{"type" => "mortkontra"}), do: :mortkontra

  def parse_legal_action(%{"type" => "bid_" <> n}) do
    {:bid, String.to_integer(n)}
  end

  def parse_legal_action(%{"type" => "declare_" <> game}) do
    {:declare, Map.fetch!(@game_types_from_cpp, game)}
  end

  def parse_legal_action(%{"type" => "play_card", "card" => card_str}) do
    {:play, parse_card(card_str)}
  end

  def parse_legal_action(%{"type" => "discard", "card1" => c1, "card2" => c2}) do
    {:discard, parse_card(c1), parse_card(c2)}
  end

  def parse_legal_actions(nil), do: []
  def parse_legal_actions(actions), do: Enum.map(actions, &parse_legal_action/1)

  ## Event translation

  def parse_event(%{"player" => player, "action" => action}) do
    %{player: player, action: parse_legal_action(action)}
  end

  def parse_events(nil), do: []
  def parse_events(events), do: Enum.map(events, &parse_event/1)

  ## Extract bid history from accumulated events

  def extract_bid_history(events) do
    events
    |> Enum.filter(fn %{action: action} ->
      case action do
        :dalje -> true
        :moje -> true
        :igra -> true
        :igra_betl -> true
        :igra_sans -> true
        {:bid, _} -> true
        _ -> false
      end
    end)
  end

  ## Full state translation: C++ state → view map

  def translate_state(cpp_state, seat, extras \\ %{}) do
    phase = parse_phase(cpp_state["phase"])
    hand = Enum.map(cpp_state["hand"] || [], &parse_card/1) |> Cards.sort_hand()
    current_player = cpp_state["current_player"]
    legal_actions = parse_legal_actions(cpp_state["legal_actions"])

    is_my_turn = current_player == seat

    trick_play = cpp_state["trick_play"]
    current_trick = translate_current_trick(trick_play)
    tricks_won = translate_tricks_won(trick_play)
    trick_number = if trick_play, do: trick_play["trick_number"] || 0, else: 0

    bidding = cpp_state["bidding"] || %{}

    game_type = parse_game_type(cpp_state["declared_game"])

    %{
      phase: phase,
      my_seat: seat,
      my_hand: hand,
      opponent_card_counts: translate_opponent_counts(cpp_state["opponent_card_counts"]),
      current_player: current_player,
      is_my_turn: is_my_turn,
      legal_actions: if(is_my_turn, do: legal_actions, else: []),
      dealer: cpp_state["dealer"],
      bid_history: Map.get(extras, :bid_history, []),
      highest_bid: bidding["highest_bid"] || 0,
      declarer: cpp_state["declarer"],
      talon: translate_talon(cpp_state["talon"]),
      discards: nil,
      game_type: game_type,
      game_value: cpp_state["game_value"],
      is_igra: cpp_state["is_igra"] || false,
      defense_responses: Map.get(extras, :defense_responses, %{}),
      defenders: Map.get(extras, :defenders, []),
      trick_number: trick_number,
      current_trick: current_trick,
      trick_winner: nil,
      tricks_won: tricks_won,
      played_cards: [],
      bule: cpp_state["bule"] || [100, 100, 100],
      refe_counts: cpp_state["refes"] || [0, 0, 0],
      kontra_level: cpp_state["kontra_level"] || 0,
      kontra_giver: cpp_state["kontra_giver"],
      scoring_result: translate_result(cpp_state["result"]),
      players:
        for s <- [0, 1, 2] do
          %{
            seat: s,
            is_declarer: cpp_state["declarer"] == s,
            is_defender: false,
            is_active: true
          }
        end
    }
  end

  ## Private helpers

  defp translate_opponent_counts(nil), do: %{}

  defp translate_opponent_counts(counts) do
    for %{"player" => player, "cards" => cards} <- counts, into: %{} do
      {player, cards}
    end
  end

  defp translate_current_trick(nil), do: []

  defp translate_current_trick(%{"current_trick" => trick}) when is_list(trick) do
    Enum.map(trick, fn %{"player" => player, "card" => card_str} ->
      %{player: player, card: parse_card(card_str)}
    end)
  end

  defp translate_current_trick(_), do: []

  defp translate_tricks_won(nil), do: [0, 0, 0]
  defp translate_tricks_won(%{"tricks_won" => tw}) when is_list(tw), do: tw
  defp translate_tricks_won(_), do: [0, 0, 0]

  defp translate_talon(nil), do: nil
  defp translate_talon(cards) when is_list(cards), do: Enum.map(cards, &parse_card/1)

  def translate_result(nil), do: nil

  def translate_result(result) do
    passed_list = result["passed"] || [false, false, false]
    everyone_passed = Enum.all?(passed_list)
    declarer = result["declarer"]
    # All-pass = nobody bid (declarer is -1). Free pass = defenders declined (declarer is set).
    all_passed = everyone_passed and (declarer == nil or declarer < 0)
    free_pass = everyone_passed and declarer != nil and declarer >= 0

    declarer_passed =
      if declarer && !everyone_passed do
        tricks = result["tricks"] || [0, 0, 0]
        declarer_tricks = Enum.at(tricks, declarer, 0)
        # Declarer "passed" (succeeded) if they got 6+ tricks (normal game)
        # For betl, they pass if they got 0 tricks
        game_type = result["game_type"]

        cond do
          game_type == "betl" -> declarer_tricks == 0
          game_type == "sans" -> declarer_tricks == 10
          true -> declarer_tricks >= 6
        end
      else
        false
      end

    bule_changes = result["bule_change"] || [0, 0, 0]
    supe_written = result["supe_written"] || [0, 0, 0]

    supe_changes = build_supe_changes(supe_written, declarer)

    %{
      all_passed: all_passed,
      declarer_passed: declarer_passed,
      free_pass: free_pass,
      tricks: result["tricks"] || [0, 0, 0],
      bule_changes: bule_changes,
      supe_changes: supe_changes,
      game_type: parse_game_type(result["game_type"]),
      refe_consumed: result["refe_consumed"] || false,
      refe_recorded: result["refe_recorded"] || false
    }
  end

  defp build_supe_changes(supe_written, declarer) do
    supe_written
    |> Enum.with_index()
    |> Enum.filter(fn {amount, _seat} -> amount > 0 end)
    |> Enum.map(fn {amount, seat} ->
      # Supe is written by one player against another
      # When a defender writes supe, it's against the declarer
      # When the declarer writes supe, it's against defenders
      target = if seat == declarer, do: other_seat(seat, declarer), else: declarer
      {{seat, target}, amount}
    end)
  end

  defp other_seat(seat, _declarer) do
    # Return a non-self seat (for declarer writing supe against a defender)
    # In practice, supe_written for the declarer is rare, but handle it
    rem(seat + 1, 3)
  end

  # C++ engine orders cards by suit index (S=0,D=1,H=2,C=3) then rank (7=0..A=7).
  # Discard actions must have card1 < card2 in this ordering.
  @cpp_suit_order %{pik: 0, karo: 1, herc: 2, tref: 3}
  @cpp_rank_order %{seven: 0, eight: 1, nine: 2, ten: 3, jack: 4, queen: 5, king: 6, ace: 7}

  defp card_sort_key({suit, rank}) do
    {Map.fetch!(@cpp_suit_order, suit), Map.fetch!(@cpp_rank_order, rank)}
  end

  defp order_cards_for_cpp(card1, card2) do
    if card_sort_key(card1) <= card_sort_key(card2) do
      {card1, card2}
    else
      {card2, card1}
    end
  end

  ## Defense response extraction from events

  def extract_defense_responses(events) do
    events
    |> Enum.filter(fn %{action: action} ->
      action in [:dodjem, :ne_dodjem, :poziv, :sam, :idemo_zajedno]
    end)
    |> Enum.into(%{}, fn %{player: player, action: action} ->
      {player, action}
    end)
  end

  def extract_defenders(events) do
    events
    |> Enum.filter(fn %{action: action} -> action == :dodjem end)
    |> Enum.map(fn %{player: player} -> player end)
  end
end
