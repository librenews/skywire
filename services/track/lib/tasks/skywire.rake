namespace :skywire do
  desc "Start the Skywire Redis Stream Consumer"
  task consume: :environment do
    Skywire::StreamConsumer.start
  end
end
