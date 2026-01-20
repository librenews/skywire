class FeedsController < ApplicationController
  skip_before_action :verify_authenticity_token
  
  def index
    @user = User.find_by!(feed_token: params[:token])
    @matches = Match.where(track: @user.tracks)
                    .order(created_at: :desc)
                    .limit(50)
    
    respond_to do |format|
      format.rss { render layout: false }
    end
  end
end
