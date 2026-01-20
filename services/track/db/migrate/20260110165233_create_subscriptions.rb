class CreateSubscriptions < ActiveRecord::Migration[8.1]
  def change
    create_table :subscriptions do |t|
      t.references :user, null: false, foreign_key: true
      t.uuid :external_id, null: false
      t.text :query, null: false
      t.float :threshold, null: false, default: 0.0
      t.string :status, null: false, default: "pending"
      t.string :callback_url

      t.timestamps
    end
    add_index :subscriptions, :external_id, unique: true
  end
end
