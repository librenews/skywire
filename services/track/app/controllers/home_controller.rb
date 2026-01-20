class HomeController < ApplicationController
  layout "home"
  def index
    if session[:user_id]
      @current_user = User.find_by(id: session[:user_id])
      if @current_user
        redirect_to tracks_path
        nil
      end
    end
  end
end
