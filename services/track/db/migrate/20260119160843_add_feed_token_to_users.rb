class AddFeedTokenToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :feed_token, :string
    add_index :users, :feed_token, unique: true
  end
end
