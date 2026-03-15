defmodule PreferansWeb.Game.Match do
  use Ecto.Schema
  import Ecto.Changeset

  alias PreferansWeb.Accounts.User

  schema "matches" do
    field :status, :string, default: "in_progress"
    field :mode, :string
    field :max_refes, :integer, default: 2
    field :initial_bule, :integer, default: 10
    field :final_bule, {:array, :integer}
    field :final_refe_count, {:array, :integer}
    field :winner_seat, :integer
    field :total_hands, :integer

    belongs_to :player_0, User
    field :player_0_type, :string
    belongs_to :player_1, User
    field :player_1_type, :string
    belongs_to :player_2, User
    field :player_2_type, :string

    has_many :hands, PreferansWeb.Game.Hand

    timestamps(type: :utc_datetime)
  end

  @required_fields [:mode, :player_0_type, :player_1_type, :player_2_type]
  @optional_fields [
    :status,
    :max_refes,
    :initial_bule,
    :final_bule,
    :final_refe_count,
    :winner_seat,
    :total_hands,
    :player_0_id,
    :player_1_id,
    :player_2_id
  ]

  def changeset(match, attrs) do
    match
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_inclusion(:status, ~w(in_progress completed abandoned))
    |> validate_inclusion(:mode, ~w(3h 2h1ai 1h2ai))
    |> validate_player_types()
  end

  defp validate_player_types(changeset) do
    Enum.reduce(~w(player_0_type player_1_type player_2_type)a, changeset, fn field, cs ->
      validate_inclusion(cs, field, ~w(human ai))
    end)
  end
end
