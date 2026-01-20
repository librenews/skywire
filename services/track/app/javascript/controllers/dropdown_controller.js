import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="dropdown"
export default class extends Controller {
  connect() {
    // Optional: Add listeners if needed, but data-action is preferred
  }

  close(event) {
    // If the click is outside the dropdown element (the details tag)
    if (!this.element.contains(event.target)) {
      this.element.removeAttribute("open")
    }
  }
}
