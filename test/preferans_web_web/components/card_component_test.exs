defmodule PreferansWebWeb.CardComponentTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest
  import PreferansWebWeb.CardComponent

  test "renders face-up card with rank and suit" do
    html =
      render_component(&card/1,
        card: {:herc, :ace},
        face: :up,
        size: :md
      )

    assert html =~ "A"
    assert html =~ "♥"
    assert html =~ "pf-card-face"
  end

  test "renders face-down card without card info" do
    html =
      render_component(&card/1,
        card: nil,
        face: :down,
        size: :md
      )

    assert html =~ "pf-card-back"
    refute html =~ "♥"
    refute html =~ "♠"
  end

  test "renders small card with smaller dimensions" do
    html =
      render_component(&card/1,
        card: {:pik, :king},
        face: :up,
        size: :sm
      )

    # sm width is 44px (md is 64px)
    assert html =~ "width: 44px"
    assert html =~ "K"
    assert html =~ "♠"
  end
end
