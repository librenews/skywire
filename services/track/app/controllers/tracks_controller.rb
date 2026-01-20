class TracksController < ApplicationController
  skip_before_action :verify_authenticity_token, only: [:feed]
  before_action :set_track, only: %i[ show edit update destroy deactivate activate feed ]

  def index
    @tracks = current_user.tracks.order(created_at: :desc)
  end

  def show
  end

  def feed
    @matches = @track.matches.order(created_at: :desc).limit(50)
    render layout: false
  end

  def new
    @track = current_user.tracks.new(threshold: 0.75)
  end

  def edit
  end

  def create
    @track = current_user.tracks.new(track_params)


    if @track.save
      Skywire::TrackService.new.create(@track)
      redirect_to tracks_path, notice: "Track was successfully created.", status: :see_other
    else
      render :new, status: :unprocessable_entity
    end
  end

  def update
    if @track.update(track_params)
      if params[:commit] == "Activate"
        Skywire::TrackService.new.activate(@track)
        notice_message = "Track was updated and activated."
      else
        Skywire::TrackService.new.update(@track)
        notice_message = "Track was successfully updated."
      end
      redirect_to tracks_path, notice: notice_message, status: :see_other
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    Skywire::TrackService.new.delete(@track)
    redirect_to tracks_path, notice: "Track was successfully destroyed.", status: :see_other
  end

  def deactivate
    Skywire::TrackService.new.deactivate(@track)
    redirect_to tracks_path, notice: "Track was successfully deactivated.", status: :see_other
  end

  def activate
    Skywire::TrackService.new.activate(@track)
    redirect_to tracks_path, notice: "Track was successfully activated.", status: :see_other
  end

  private
    def set_track
      if action_name == "feed"
        @track = Track.find_by!(external_id: params[:id])
      else
        @track = current_user.tracks.find_by!(external_id: params[:id])
      end
    end

    def track_params
      params.require(:track).permit(:name, :query, :threshold, keywords: []).tap do |p|
        p[:keywords].reject!(&:blank?) if p[:keywords]
      end
    end
end
