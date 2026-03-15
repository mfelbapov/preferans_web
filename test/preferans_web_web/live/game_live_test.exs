defmodule PreferansWebWeb.GameLiveTest do
  use PreferansWebWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias PreferansWeb.Game

  setup :register_and_log_in_user

  defp start_game(%{user: user}) do
    {:ok, game_id} = Game.start_solo_game(user.id)
    %{game_id: game_id}
  end

  describe "mount" do
    test "redirects to lobby for invalid game_id", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/lobby"}}} = live(conn, ~p"/game/99999999")
    end

    test "renders game for valid game_id", %{conn: conn} = ctx do
      %{game_id: game_id} = start_game(ctx)
      {:ok, _lv, html} = live(conn, ~p"/game/#{game_id}")

      assert html =~ "game-container"
    end
  end

  describe "bidding" do
    setup :start_game

    test "shows bidding UI", %{conn: conn, game_id: game_id} do
      {:ok, _lv, html} = live(conn, ~p"/game/#{game_id}")

      # Should show either bidding UI or waiting message
      assert html =~ "Pass" or html =~ "Waiting"
    end
  end

  describe "card component" do
    test "renders in game view", %{conn: conn} = ctx do
      %{game_id: game_id} = start_game(ctx)
      {:ok, _lv, html} = live(conn, ~p"/game/#{game_id}")

      # Cards should be rendered (suit symbols)
      assert html =~ "♠" or html =~ "♦" or html =~ "♥" or html =~ "♣"
    end
  end

  describe "scoring sidebar" do
    test "shows bule values", %{conn: conn} = ctx do
      %{game_id: game_id} = start_game(ctx)
      {:ok, _lv, html} = live(conn, ~p"/game/#{game_id}")

      assert html =~ "Bule"
      assert html =~ "100"
    end
  end
end
