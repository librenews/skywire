class AddNameToTracks < ActiveRecord::Migration[8.1]
  def up
    add_column :tracks, :name, :string

    # Backfill existing tracks using their query as the name
    execute("UPDATE tracks SET name = query WHERE name IS NULL")

    change_column_null :tracks, :name, false
  end

  def down
    remove_column :tracks, :name
  end
end
