class TestController < ApplicationController
  def login
    user = User.find(params[:user_id])
    session[:user_id] = user.id
    redirect_to root_path
  end
end
