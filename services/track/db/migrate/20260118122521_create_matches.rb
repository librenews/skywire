class CreateMatches < ActiveRecord::Migration[8.1]
  def change
    create_table :matches do |t|
      t.references :track, null: false, foreign_key: true
      t.jsonb :data

      t.timestamps
    end
  end
end
