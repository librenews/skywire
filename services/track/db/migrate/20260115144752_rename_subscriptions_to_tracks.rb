class RenameSubscriptionsToTracks < ActiveRecord::Migration[8.1]
  def change
    rename_table :subscriptions, :tracks
  end
end
