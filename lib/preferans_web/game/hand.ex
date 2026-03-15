defmodule PreferansWeb.Game.Hand do
  use Ecto.Schema
  import Ecto.Changeset

  schema "hands" do
    belongs_to :match, PreferansWeb.Game.Match

    field :hand_number, :integer
    field :dealer, :integer
    field :initial_hands, {:array, :integer}
    field :talon, :integer
    field :bule_before, {:array, :integer}
    field :refe_before, {:array, :integer}
    field :all_passed, :boolean, default: false
    field :declarer, :integer
    field :declared_game, :string
    field :is_igra, :boolean, default: false
    field :game_value, :integer
    field :defenders, {:array, :integer}
    field :caller, :integer
    field :called, :integer
    field :kontra_level, :integer, default: 0
    field :tricks_won, {:array, :integer}
    field :bule_change, {:array, :integer}
    field :supe_written, {:array, :integer}
    field :action_history, {:array, :map}, default: []

    timestamps(type: :utc_datetime)
  end

  @required_fields [:hand_number, :dealer]
  @optional_fields [
    :initial_hands,
    :talon,
    :bule_before,
    :refe_before,
    :all_passed,
    :declarer,
    :declared_game,
    :is_igra,
    :game_value,
    :defenders,
    :caller,
    :called,
    :kontra_level,
    :tricks_won,
    :bule_change,
    :supe_written,
    :action_history
  ]

  def changeset(hand, attrs) do
    hand
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_inclusion(:dealer, 0..2)
    |> validate_inclusion(:declared_game, ~w(pik karo herc tref betl sans))
  end
end
