defmodule PreferansWebWeb.GameComponents do
  @moduledoc """
  Debug panel for the game table. The other phase-specific components moved to
  `PreferansWebWeb.PhasePanels` (and the seat / scoresheet components live in
  their own modules).
  """
  use Phoenix.Component

  ## Debug panel

  attr :debug_state, :map, required: true

  def debug_panel(assigns) do
    text = format_debug_text(assigns.debug_state)
    assigns = assign(assigns, :text, text)

    ~H"""
    <div
      class="w-96 bg-gray-900 border-l border-gray-700 p-3 flex flex-col gap-2 overflow-y-auto"
      style="position: fixed; top: 0; right: 0; bottom: 0; z-index: 100;"
    >
      <div class="flex justify-between items-center border-b border-gray-700 pb-2">
        <h3 class="text-gray-100 font-bold text-sm">Debug State</h3>
        <button
          id="copy-debug-btn"
          phx-hook="CopyToClipboard"
          data-target="debug-pre"
          class="text-xs bg-gray-700 hover:bg-gray-600 text-gray-200 px-2 py-1 rounded"
        >
          Copy All
        </button>
      </div>
      <pre id="debug-pre" class="text-xs text-gray-300 font-mono whitespace-pre-wrap break-words">{@text}</pre>
    </div>
    """
  end

  defp format_debug_text(d) do
    cpp = d.cpp_state
    trick_play = cpp["trick_play"]

    sections = [
      "=== GAME DEBUG STATE ===",
      "Phase: #{cpp["phase"]}",
      "Current Player: #{cpp["current_player"]}",
      "Dealer: #{d.current_dealer}",
      "Declarer: #{cpp["declarer"]}",
      "Game Type: #{cpp["declared_game"]}",
      "Game Value: #{cpp["game_value"]}",
      "Is Igra: #{cpp["is_igra"]}",
      "Kontra Level: #{cpp["kontra_level"]}",
      "Kontra Giver: #{cpp["kontra_giver"]}",
      "",
      "=== PLAYERS ===",
      format_players(d.players),
      "",
      "=== MY SEAT: #{d.seat} ===",
      "",
      "=== HAND ===",
      inspect(cpp["hand"]),
      "",
      "=== TALON ===",
      inspect(cpp["talon"]),
      "",
      "=== LEGAL ACTIONS ===",
      inspect(cpp["legal_actions"]),
      "",
      "=== BID HISTORY ===",
      format_bid_history(d.bid_history),
      "",
      "=== DEFENSE RESPONSES ===",
      format_defense_responses(d.defense_responses),
      "Defenders: #{inspect(d.defenders)}",
      "",
      "=== TRICK STATE ===",
      format_trick_state(trick_play),
      "",
      "=== ALL EVENTS ===",
      format_events(d.all_events),
      "",
      "=== MATCH STATE ===",
      "Bule: #{inspect(d.match_bule)}",
      "Refes: #{inspect(d.match_refe_counts)} (hands played: #{inspect(d.match_refe_hands_played)})",
      "Supe Ledger: #{inspect(d.match_supe_ledger)}",
      "Hands Played: #{d.hands_played}",
      "Max Refes: #{d.max_refes}",
      "",
      "=== SCORING RESULT ===",
      inspect(cpp["result"]),
      "",
      "=== RAW CPP STATE ===",
      inspect(cpp, pretty: true, limit: :infinity)
    ]

    Enum.join(sections, "\n")
  end

  defp format_players(players) do
    Enum.map_join(players, "\n", fn p ->
      "Seat #{p.seat}: #{p.display_name}#{if p.is_ai, do: " (AI)", else: " (Human)"}"
    end)
  end

  defp format_bid_history(history) do
    Enum.map_join(history, "\n", fn entry ->
      "Seat #{entry.player}: #{inspect(entry.action)}"
    end)
  end

  defp format_defense_responses(responses) do
    Enum.map_join(responses, "\n", fn {seat, action} ->
      "Seat #{seat}: #{inspect(action)}"
    end)
  end

  defp format_trick_state(nil), do: "No trick play state"

  defp format_trick_state(tp) do
    [
      "Trick Number: #{tp["trick_number"]}",
      "Tricks Won: #{inspect(tp["tricks_won"])}",
      "Current Trick: #{inspect(tp["current_trick"])}"
    ]
    |> Enum.join("\n")
  end

  defp format_events(events) do
    Enum.map_join(events, "\n", fn event ->
      inspect(event)
    end)
  end
end
