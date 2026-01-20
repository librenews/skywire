class CreateUsers < ActiveRecord::Migration[8.1]
  def change
    create_table :users do |t|
      t.string :did
      t.string :handle
      t.string :display_name
      t.string :avatar_url
      t.text :access_token
      t.text :refresh_token
      t.datetime :expires_at

      t.timestamps
    end
    add_index :users, :did
  end
end
