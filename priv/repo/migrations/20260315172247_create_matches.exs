defmodule PreferansWeb.Repo.Migrations.CreateMatches do
  use Ecto.Migration

  def change do
    create table(:matches) do
      add :status, :string, null: false, default: "in_progress"
      add :mode, :string, null: false
      add :max_refes, :integer, default: 2
      add :initial_bule, :integer, default: 10
      add :final_bule, {:array, :integer}
      add :final_refe_count, {:array, :integer}
      add :winner_seat, :integer
      add :total_hands, :integer

      add :player_0_id, references(:users, on_delete: :nilify_all)
      add :player_0_type, :string, null: false
      add :player_1_id, references(:users, on_delete: :nilify_all)
      add :player_1_type, :string, null: false
      add :player_2_id, references(:users, on_delete: :nilify_all)
      add :player_2_type, :string, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:matches, [:player_0_id])
    create index(:matches, [:player_1_id])
    create index(:matches, [:player_2_id])
    create index(:matches, [:status])
  end
end
