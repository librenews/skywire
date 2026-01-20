import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input", "container", "hidden"]

  connect() {
    this.initialTags = JSON.parse(this.containerTarget.dataset.tags || "[]")
    this.initialTags.forEach(tag => this.addTag(tag))
  }

  handleKeydown(event) {
    if (event.key === "Enter" || event.key === ",") {
      event.preventDefault()
      const value = this.inputTarget.value.trim().replace(/,/g, "")
      if (value) {
        this.addTag(value)
        this.inputTarget.value = ""
      }
    } else if (event.key === "Backspace" && this.inputTarget.value === "") {
      this.removeLastTag()
    }
  }

  addTag(text) {
    if (this.hasTag(text)) return

    const tag = document.createElement("span")
    tag.className = "inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-blue-100 text-blue-800 m-1"
    tag.innerHTML = `
      ${text}
      <button type="button" class="ml-1 inline-flex-shrink-0 text-blue-400 hover:text-blue-500 focus:outline-none" data-action="click->tags#remove">
        <svg class="h-2 w-2" stroke="currentColor" fill="none" viewBox="0 0 8 8">
          <path stroke-linecap="round" stroke-width="1.5" d="M1 1l6 6m0-6L1 7" />
        </svg>
      </button>
    `
    // Store the value in a data attribute
    tag.dataset.value = text

    // Insert before the input
    this.containerTarget.insertBefore(tag, this.inputTarget)

    this.updateHiddenInput()
  }

  remove(event) {
    event.target.closest("span").remove()
    this.updateHiddenInput()
  }

  removeLastTag() {
    const tags = this.containerTarget.querySelectorAll("span")
    if (tags.length > 0) {
      tags[tags.length - 1].remove()
      this.updateHiddenInput()
    }
  }

  hasTag(text) {
    const existing = this.currentTags()
    return existing.includes(text)
  }

  currentTags() {
    return Array.from(this.containerTarget.querySelectorAll("span")).map(tag => tag.dataset.value)
  }

  updateHiddenInput() {
    // Clear existing hidden inputs
    this.hiddenTarget.innerHTML = ""

    this.currentTags().forEach(tag => {
      const input = document.createElement("input")
      input.type = "hidden"
      input.name = "track[keywords][]"
      input.value = tag
      this.hiddenTarget.appendChild(input)
    })
  }
}
