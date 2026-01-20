import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input", "output"]

  connect() {
    this.update()
  }

  update() {
    const value = parseFloat(this.inputTarget.value)
    this.outputTarget.textContent = value.toFixed(2)

    // Calculate percentage for the gradient
    const min = parseFloat(this.inputTarget.min) || 0
    const max = parseFloat(this.inputTarget.max) || 1
    const percent = ((value - min) / (max - min)) * 100

    // Update the background to show a "fat colored bar" on the left
    // Using the brand color #287fc6
    this.inputTarget.style.background = `linear-gradient(to right, #287fc6 0%, #287fc6 ${percent}%, #e5e7eb ${percent}%, #e5e7eb 100%)`
  }
}
