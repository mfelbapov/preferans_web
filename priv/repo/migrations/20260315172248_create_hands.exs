defmodule PreferansWeb.Repo.Migrations.CreateHands do
  use Ecto.Migration

  def change do
    create table(:hands) do
      add :match_id, references(:matches, on_delete: :delete_all), null: false
      add :hand_number, :integer, null: false
      add :dealer, :integer, null: false
      add :initial_hands, {:array, :integer}
      add :talon, :integer
      add :bule_before, {:array, :integer}
      add :refe_before, {:array, :integer}
      add :all_passed, :boolean, default: false
      add :declarer, :integer
      add :declared_game, :string
      add :is_igra, :boolean, default: false
      add :game_value, :integer
      add :defenders, {:array, :integer}
      add :caller, :integer
      add :called, :integer
      add :kontra_level, :integer, default: 0
      add :tricks_won, {:array, :integer}
      add :bule_change, {:array, :integer}
      add :supe_written, {:array, :integer}
      add :action_history, {:array, :map}, default: []

      timestamps(type: :utc_datetime)
    end

    create index(:hands, [:match_id])
    create unique_index(:hands, [:match_id, :hand_number])
  end
end
