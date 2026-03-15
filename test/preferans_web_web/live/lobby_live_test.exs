defmodule PreferansWebWeb.LobbyLiveTest do
  use PreferansWebWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  describe "LobbyLive" do
    setup :register_and_log_in_user

    test "renders lobby page with stats", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/lobby")
      assert html =~ "Lobby"
      assert html =~ "Games Played"
      assert html =~ "Rating"
      assert html =~ "New Game"
    end

    test "clicking New Game starts a game and redirects", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/lobby")

      {:ok, _lv, html} =
        lv
        |> element("#new-game-btn")
        |> render_click()
        |> follow_redirect(conn)

      # Should redirect to the game page
      assert html =~ "game-container" or html =~ "Bidding" or html =~ "Back to Lobby"
    end
  end
end
