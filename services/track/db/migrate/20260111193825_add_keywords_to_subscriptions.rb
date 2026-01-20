class AddKeywordsToSubscriptions < ActiveRecord::Migration[8.1]
  def change
    add_column :subscriptions, :keywords, :text, array: true, default: []
  end
end
