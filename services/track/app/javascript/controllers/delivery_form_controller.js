import { Controller } from "@hotwired/stimulus"

// Simplified for MVP - only Webhook delivery is available
// Email and SMS delivery fields are hidden
export default class extends Controller {
  static targets = ["typeSelect", "webhookFields"]

  connect() {
    this.toggleFields()
  }

  toggleFields() {
    // For MVP, only webhook delivery is available
    // Simply show the webhook fields
    const type = this.typeSelectTarget.value

    if (type === "WebhookDelivery") {
      this.webhookFieldsTarget.classList.remove("hidden")
    }
  }
}
