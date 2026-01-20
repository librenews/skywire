class RemoveCallbackUrlFromSubscriptions < ActiveRecord::Migration[8.1]
  def change
    remove_column :subscriptions, :callback_url, :string
  end
end
