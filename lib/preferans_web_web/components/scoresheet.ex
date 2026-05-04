defmodule PreferansWebWeb.Scoresheet do
  @moduledoc """
  Paper-card scoresheet for one player and the triangular Refe tally counter.
  Visual port of `scoresheet.jsx`.
  """
  use Phoenix.Component

  @doc """
  Per-player paper scoresheet: three columns (Supa | Bule | Supa), sub-totals
  and grand total. Caller supplies bule and supa entries plus the running total.

  ## Attrs
    * `player_name` — uppercased in the header.
    * `bule_entries` — `[%{hand: integer, score: integer}]` (positive, "won").
    * `supa_entries` — `[%{hand: integer, score: integer}]` (positive magnitude,
      "lost"; the component splits the list across the two red columns).
    * `total` — signed grand total displayed at the bottom.
    * `lang` — `:sr | :en`. Switches header labels.
  """
  attr :player_name, :string, required: true
  attr :bule_entries, :list, default: []
  attr :supa_entries, :list, default: []
  attr :total, :integer, default: 0
  attr :lang, :atom, default: :sr

  def mini_scoresheet(assigns) do
    {supa_left, supa_right} = split_supa(assigns.supa_entries)
    sum_l = sum_entries(supa_left)
    sum_r = sum_entries(supa_right)
    sum_bule = sum_entries(assigns.bule_entries)

    assigns =
      assigns
      |> assign(:supa_left, supa_left)
      |> assign(:supa_right, supa_right)
      |> assign(:sum_l, sum_l)
      |> assign(:sum_r, sum_r)
      |> assign(:sum_bule, sum_bule)

    ~H"""
    <div class="pf-mini-scoresheet" style={mini_outer_style()}>
      <div style={mini_header_style()}>
        <div style="font-size: 13px; font-weight: 700; letter-spacing: 0.08em;">
          {String.upcase(@player_name)}
        </div>
        <div style="font-size: 9px; opacity: 0.65; font-family: var(--font-mono); letter-spacing: 0.1em;">
          {if @lang == :sr, do: "TABLA", else: "SCORE"}
        </div>
      </div>

      <div style="display: grid; grid-template-columns: 1fr 1.4fr 1fr;">
        <div style={col_header_style(:red, :right)}>
          {if @lang == :sr, do: "Supa", else: "Lost"}
        </div>
        <div style={col_header_style(:neutral, :right)}>
          {if @lang == :sr, do: "Bule", else: "Won"}
        </div>
        <div style={col_header_style(:red, :none)}>
          {if @lang == :sr, do: "Supa", else: "Lost"}
        </div>

        <div style="border-right: 1px solid rgba(60,40,20,0.2);">
          <.supa_col entries={@supa_left} />
        </div>
        <div style={bule_cell_style()}>
          <div
            :for={b <- @bule_entries}
            style="display: flex; justify-content: space-between; line-height: 1.1;"
          >
            <span style="opacity: 0.45; font-size: 9px; font-family: var(--font-mono);">
              {b.hand}.
            </span>
            <span style="font-weight: 600;">{b.score}</span>
          </div>
        </div>
        <div>
          <.supa_col entries={@supa_right} />
        </div>

        <div style={subtotal_style(:red, :right)}>{display_sum(@sum_l)}</div>
        <div style={subtotal_style(:neutral, :right)}>{display_sum(@sum_bule)}</div>
        <div style={subtotal_style(:red, :none)}>{display_sum(@sum_r)}</div>
      </div>

      <div style={grand_total_row_style()}>
        <div style="font-family: var(--font-mono); font-size: 9px; opacity: 0.65; letter-spacing: 0.15em; text-transform: uppercase;">
          {if @lang == :sr, do: "Ukupno", else: "Total"}
        </div>
        <div style={"font-size: 18px; font-weight: 700; color: #{if @total < 0, do: "#8a1f1f", else: "#2a1d10"};"}>
          {format_total(@total)}
        </div>
      </div>
    </div>
    """
  end

  attr :entries, :list, required: true

  defp supa_col(assigns) do
    ~H"""
    <div style={supa_cell_style()}>
      <div :for={e <- @entries} style="text-align: center; line-height: 1.1;">{e.score}</div>
    </div>
    """
  end

  @doc """
  Three SVG triangles in a row. Each triangle has three sides (bottom = seat 0,
  left = seat 1, right = seat 2). Tally marks accumulate per side; every fifth
  mark is rendered as a diagonal cross over the prior four (4+1 grouping).

  ## Attrs
    * `counts` — 3-int list `[c0, c1, c2]`, total marks per seat across all refes.
    * `per_refe` — threshold before a side spills into the next triangle.
    * `count` — number of triangles to draw (default 3).
  """
  attr :counts, :list, required: true
  attr :per_refe, :integer, default: 10
  attr :count, :integer, default: 3

  def refe(assigns) do
    refes =
      for refe_idx <- 0..(assigns.count - 1) do
        Enum.map(assigns.counts, fn t ->
          t
          |> Kernel.-(refe_idx * assigns.per_refe)
          |> max(0)
          |> min(assigns.per_refe)
        end)
      end

    assigns = assign(assigns, :refes, refes)

    ~H"""
    <div
      class="pf-refe"
      style="width: 220px; padding: 8px 6px; display: flex; justify-content: space-around; gap: 4px;"
    >
      <svg :for={{counts, i} <- Enum.with_index(@refes)} viewBox="0 0 70 62" width="70" height="62">
        <polygon
          points="35,6 6,56 64,56"
          fill="none"
          stroke="#f5e9d4"
          stroke-width="1.5"
        />
        <%!-- bottom side B->C: seat 0 --%>
        <line
          :for={mark <- tally_marks({6, 56}, {64, 56}, Enum.at(counts, 0), @per_refe)}
          x1={mark.x1}
          y1={mark.y1}
          x2={mark.x2}
          y2={mark.y2}
          stroke="#f5e9d4"
          stroke-width="1.5"
        />
        <%!-- left side A->B: seat 1 --%>
        <line
          :for={mark <- tally_marks({35, 6}, {6, 56}, Enum.at(counts, 1), @per_refe)}
          x1={mark.x1}
          y1={mark.y1}
          x2={mark.x2}
          y2={mark.y2}
          stroke="#f5e9d4"
          stroke-width="1.5"
        />
        <%!-- right side C->A: seat 2 --%>
        <line
          :for={mark <- tally_marks({64, 56}, {35, 6}, Enum.at(counts, 2), @per_refe)}
          x1={mark.x1}
          y1={mark.y1}
          x2={mark.x2}
          y2={mark.y2}
          stroke="#f5e9d4"
          stroke-width="1.5"
        />
        <% _ = i %>
      </svg>
    </div>
    """
  end

  ## Tally generation — port of the JSX `tallyMarks` helper.

  defp tally_marks(_p1, _p2, 0, _per), do: []

  defp tally_marks({px, py}, {qx, qy}, count, per_refe) do
    dx = qx - px
    dy = qy - py
    len = :math.sqrt(dx * dx + dy * dy)
    nx = -dy / len
    ny = dx / len
    slash_len = 6.0
    n = min(count, per_refe)

    Enum.map(0..(n - 1), fn i ->
      t = (i + 1) / (per_refe + 1)
      cx = px + dx * t
      cy = py + dy * t
      cross? = rem(i + 1, 5) == 0

      if cross? do
        back = 4 / (per_refe + 1)

        %{
          x1: px + dx * (t - back) + nx * slash_len * 0.5,
          y1: py + dy * (t - back) + ny * slash_len * 0.5,
          x2: cx - nx * slash_len * 0.5,
          y2: cy - ny * slash_len * 0.5
        }
      else
        %{
          x1: cx - nx * slash_len / 2,
          y1: cy - ny * slash_len / 2,
          x2: cx + nx * slash_len / 2,
          y2: cy + ny * slash_len / 2
        }
      end
    end)
  end

  ## Styling helpers

  defp mini_outer_style do
    """
    color: #2a1d10; padding: 10px 12px; width: 220px;
    font-family: var(--font-display);
    background: var(--paper);
    background-image: repeating-linear-gradient(to bottom, transparent 0 22px, rgba(80,40,20,0.08) 22px 23px);
    border-radius: 2px;
    box-shadow: 0 12px 32px rgba(0,0,0,0.5), 0 2px 4px rgba(0,0,0,0.3);
    """
  end

  defp mini_header_style do
    """
    display: flex; justify-content: space-between; align-items: baseline;
    border-bottom: 1.5px solid rgba(60,40,20,0.5);
    padding-bottom: 4px; margin-bottom: 6px;
    """
  end

  defp col_header_style(color, divider) do
    base = """
    font-family: var(--font-mono); font-size: 8px; letter-spacing: 0.2em;
    text-transform: uppercase; text-align: center; padding: 3px 0;
    border-bottom: 1px solid rgba(60,40,20,0.25);
    """

    color_rule =
      case color do
        :red -> "color: #8a1f1f;"
        :neutral -> "color: rgba(60,40,20,0.65);"
      end

    divider_rule =
      case divider do
        :right -> "border-right: 1px solid rgba(60,40,20,0.2);"
        :none -> ""
      end

    base <> color_rule <> divider_rule
  end

  defp supa_cell_style do
    """
    padding: 3px 5px; font-family: var(--font-hand); font-size: 14px;
    color: #8a1f1f; background: rgba(138,31,31,0.04); min-height: 56px;
    display: flex; flex-direction: column; gap: 1px;
    """
  end

  defp bule_cell_style do
    """
    border-right: 1px solid rgba(60,40,20,0.2);
    border-left: 1px solid rgba(60,40,20,0.2);
    padding: 3px 5px; font-family: var(--font-hand); font-size: 15px;
    min-height: 56px; display: flex; flex-direction: column; gap: 1px;
    """
  end

  defp subtotal_style(color, divider) do
    base = """
    border-top: 1px solid rgba(60,40,20,0.3);
    text-align: center; padding: 3px 0; font-weight: 700;
    """

    color_rule =
      case color do
        :red -> "color: #8a1f1f; font-size: 13px;"
        :neutral -> "font-size: 14px;"
      end

    divider_rule =
      case divider do
        :right -> "border-right: 1px solid rgba(60,40,20,0.2);"
        :none -> ""
      end

    base <> color_rule <> divider_rule
  end

  defp grand_total_row_style do
    """
    margin-top: 6px; padding-top: 4px;
    border-top: 2px solid rgba(60,40,20,0.5);
    display: flex; justify-content: space-between; align-items: baseline;
    """
  end

  ## Data helpers

  defp split_supa(entries) do
    half = ceil(length(entries) / 2)
    Enum.split(entries, half)
  end

  defp sum_entries(entries), do: Enum.reduce(entries, 0, fn e, acc -> acc + e.score end)

  defp display_sum(0), do: ""
  defp display_sum(n), do: Integer.to_string(n)

  defp format_total(n) when n > 0, do: "+#{n}"
  defp format_total(n), do: Integer.to_string(n)
end
