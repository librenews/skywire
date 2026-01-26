Rails.application.routes.draw do
  resources :tracks do
    resources :deliveries, only: [:index, :new, :create, :destroy]
    member do
      patch :deactivate
      patch :activate
      get :feed, defaults: { format: :rss }
    end
  end

  get "feeds/:token", to: "feeds#index", as: :user_feed, defaults: { format: :rss }

  # Bluesky Feed Generator endpoints
  get '/xrpc/app.bsky.feed.getFeedSkeleton', to: 'feed_generator#get_feed_skeleton'
  get '/xrpc/app.bsky.feed.describeFeedGenerator', to: 'feed_generator#describe_feed_generator'
  get '/.well-known/did.json', to: 'feed_generator#did_json'

  if Rails.env.test?
    get "/test/login", to: "test#login"
  end

  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Auth
  root "home#index"
  post "/auth/bluesky/start", to: "sessions#start", as: :start_bluesky_auth
  get "/auth/atproto/callback", to: "sessions#callback"
  get "/auth/failure", to: "sessions#failure"
  get "/oauth/client-metadata.json", to: "sessions#client_metadata", as: :client_metadata
  delete "/logout", to: "sessions#destroy", as: :logout
end
