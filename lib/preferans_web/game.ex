defmodule PreferansWeb.Game do
  @moduledoc """
  The Game context — CRUD for matches and hands.
  """

  import Ecto.Query, warn: false
  alias PreferansWeb.Repo

  alias PreferansWeb.Game.Match
  alias PreferansWeb.Game.Hand

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
end
