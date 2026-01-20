import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["typeSelect", "emailFields", "smsFields", "webhookFields"]

  connect() {
    this.toggleFields()
  }

  toggleFields() {
    const type = this.typeSelectTarget.value

    this.emailFieldsTarget.classList.add("hidden")
    this.smsFieldsTarget.classList.add("hidden")
    this.webhookFieldsTarget.classList.add("hidden")

    if (type === "EmailDelivery") {
      this.emailFieldsTarget.classList.remove("hidden")
    } else if (type === "SmsDelivery") {
      this.smsFieldsTarget.classList.remove("hidden")
    } else if (type === "WebhookDelivery") {
      this.webhookFieldsTarget.classList.remove("hidden")
    }
  }
}
