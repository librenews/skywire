Rails.application.config.after_initialize do
  unless Rails.env.test? || defined?(Rails::Console)
    Rails.logger.info "🚀 (Initializer) Starting Skywire Stream Consumer..."
    
    Thread.new do
      # Small delay to ensure everything is ready
      sleep 2
      begin
        Skywire::StreamConsumer.start
      rescue => e
        Rails.logger.error "💥 StreamConsumer crashed: #{e.message}"
        Rails.logger.error e.backtrace.join("\n")
      end
    end
  end
end
