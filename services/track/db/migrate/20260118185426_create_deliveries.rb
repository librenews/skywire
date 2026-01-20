class CreateDeliveries < ActiveRecord::Migration[8.1]
  def change
    create_table :deliveries, id: :uuid do |t|
      t.references :track, null: false, foreign_key: { to_table: :tracks, type: :uuid }
      t.string :delivery_type, null: false
      t.jsonb :config, null: false, default: {}
      t.boolean :active, default: true

      t.timestamps
    end
  end
end
