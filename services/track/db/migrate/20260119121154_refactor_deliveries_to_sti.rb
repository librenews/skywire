class RefactorDeliveriesToSti < ActiveRecord::Migration[8.1]
  def up
    rename_column :deliveries, :delivery_type, :type
    
    # Add new specific columns
    add_column :deliveries, :email, :string
    add_column :deliveries, :frequency, :string
    add_column :deliveries, :phone, :string
    add_column :deliveries, :url, :string
    add_column :deliveries, :secret, :string

    # Remove the old blob
    remove_column :deliveries, :config

    # Add constraints for data integrity
    execute <<-SQL
      ALTER TABLE deliveries ADD CONSTRAINT check_email_delivery 
      CHECK (
        (type = 'EmailDelivery' AND email IS NOT NULL AND frequency IS NOT NULL) OR
        (type != 'EmailDelivery')
      );

      ALTER TABLE deliveries ADD CONSTRAINT check_sms_delivery 
      CHECK (
        (type = 'SmsDelivery' AND phone IS NOT NULL) OR
        (type != 'SmsDelivery')
      );

      ALTER TABLE deliveries ADD CONSTRAINT check_webhook_delivery 
      CHECK (
        (type = 'WebhookDelivery' AND url IS NOT NULL) OR
        (type != 'WebhookDelivery')
      );
    SQL
  end

  def down
    remove_check_constraint :deliveries, name: "check_email_delivery"
    remove_check_constraint :deliveries, name: "check_sms_delivery"
    remove_check_constraint :deliveries, name: "check_webhook_delivery"

    add_column :deliveries, :config, :jsonb, default: {}, null: false
    remove_column :deliveries, :secret
    remove_column :deliveries, :url
    remove_column :deliveries, :phone
    remove_column :deliveries, :frequency
    remove_column :deliveries, :email
    
    rename_column :deliveries, :type, :delivery_type
  end
end
