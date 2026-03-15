defmodule PreferansWeb.Game do
  @moduledoc """
  The Game context — CRUD for matches and hands.
  """

  import Ecto.Query, warn: false
  alias PreferansWeb.Repo

  alias PreferansWeb.Game.Match
  alias PreferansWeb.Game.Hand
  alias PreferansWeb.Game.GameServer

  ## Matches

  def list_matches do
    Repo.all(Match)
  end

  def list_matches_for_user(user_id) do
    from(m in Match,
      where:
        m.player_0_id == ^user_id or
          m.player_1_id == ^user_id or
          m.player_2_id == ^user_id,
      order_by: [desc: m.inserted_at]
    )
    |> Repo.all()
  end

  def get_match!(id), do: Repo.get!(Match, id)

  def get_match_with_hands!(id) do
    Match
    |> Repo.get!(id)
    |> Repo.preload(hands: from(h in Hand, order_by: h.hand_number))
  end

  def create_match(attrs \\ %{}) do
    %Match{}
    |> Match.changeset(attrs)
    |> Repo.insert()
  end

  def update_match(%Match{} = match, attrs) do
    match
    |> Match.changeset(attrs)
    |> Repo.update()
  end

  ## Hands

  def list_hands_for_match(match_id) do
    from(h in Hand, where: h.match_id == ^match_id, order_by: h.hand_number)
    |> Repo.all()
  end

  def get_hand!(id), do: Repo.get!(Hand, id)

  def create_hand(%Match{} = match, attrs \\ %{}) do
    %Hand{}
    |> Hand.changeset(attrs)
    |> Ecto.Changeset.put_assoc(:match, match)
    |> Repo.insert()
  end

  def update_hand(%Hand{} = hand, attrs) do
    hand
    |> Hand.changeset(attrs)
    |> Repo.update()
  end

  ## Game lifecycle

  def start_solo_game(user_id, opts \\ []) do
    starting_bule = Keyword.get(opts, :starting_bule, [100, 100, 100])
    max_refes = Keyword.get(opts, :max_refes, 2)

    user = PreferansWeb.Accounts.get_user!(user_id)

    match_attrs = %{
      status: "in_progress",
      mode: "1h2ai",
      initial_bule: hd(starting_bule),
      max_refes: max_refes,
      player_0_id: user_id,
      player_0_type: "human",
      player_1_type: "ai",
      player_2_type: "ai"
    }

    case create_match(match_attrs) do
      {:ok, match} ->
        init_arg = %{
          game_id: to_string(match.id),
          match_id: match.id,
          starting_bule: starting_bule,
          max_refes: max_refes,
          current_dealer: 0,
          refe_counts: [0, 0, 0],
          players: [
            %{seat: 0, user_id: user_id, is_ai: false, display_name: user.username || "Player"},
            %{
              seat: 1,
              user_id: nil,
              is_ai: true,
              ai_level: "heuristic",
              display_name: "Bot Duško"
            },
            %{
              seat: 2,
              user_id: nil,
              is_ai: true,
              ai_level: "heuristic",
              display_name: "Bot Nikola"
            }
          ]
        }

        case DynamicSupervisor.start_child(PreferansWeb.GameSupervisor, {GameServer, init_arg}) do
          {:ok, _pid} -> {:ok, to_string(match.id)}
          {:error, reason} -> {:error, reason}
        end

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  def find_user_active_game(user_id) do
    match =
      from(m in Match,
        where: m.player_0_id == ^user_id and m.status == "in_progress",
        order_by: [desc: m.inserted_at],
        limit: 1
      )
      |> Repo.one()

    cond do
      match == nil -> nil
      GameServer.game_exists?(to_string(match.id)) -> to_string(match.id)
      true -> nil
    end
  end
end
