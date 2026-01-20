import { Controller } from "@hotwired/stimulus"
import { Socket } from "phoenix"

export default class extends Controller {
  static targets = ["modal", "results", "status", "query", "threshold", "keywords"]
  static values = { token: String }

  connect() {
    console.log("PreviewController: Connect")
    this.socket = null
    this.channel = null

    // Log presence of all expected targets
    const expectedTargets = ["modal", "results", "status", "query", "threshold", "keywords"]
    expectedTargets.forEach(t => {
      const has = this[`has${t.charAt(0).toUpperCase() + t.slice(1)}Target`]
      console.log(`PreviewController: Target '${t}' found?`, has)
    })

    // Ensure modal is hidden on connect (fixes Turbo restoration bugs)
    if (this.hasModalTarget) {
      console.log("PreviewController: Hiding modal on connect")
      this.modalTarget.style.display = "none"
      this.modalTarget.classList.add("hidden")
    } else {
      console.warn("PreviewController: No modal target found on connect (CRITICAL)")
    }
  }

  disconnect() {
    console.log("PreviewController: Disconnect")
    this.stop()
  }

  start(event) {
    console.log("PreviewController: Start clicked")
    event.preventDefault()
    if (!this.hasModalTarget) {
      console.error("PreviewController: Cannot find modal target")
      return
    }
    this.modalTarget.classList.remove("hidden")
    this.modalTarget.style.display = "block"
    this.resultsTarget.innerHTML = ""
    this.updateStatus("Connecting...", "text-yellow-600")

    const socketUrl = document.querySelector('meta[name="firehose-socket-url"]').content
    this.socket = new Socket(socketUrl, { params: { token: this.tokenValue } })
    this.socket.connect()

    const params = this.buildParams()
    console.log("Preview Params:", params)

    // Validate that we have at least query or keywords
    if (!params.query && (!params.keywords || params.keywords.length === 0)) {
      this.updateStatus("Error: Must provide query or keywords", "text-red-600")
      return
    }

    this.updateStatus("Joining channel...", "text-yellow-600")
    this.channel = this.socket.channel("preview", params)

    this.channel.join()
      .receive("ok", resp => {
        console.log("Joined successfully", resp)
        this.updateStatus("Live - Waiting for matches...", "text-green-600")
      })
      .receive("error", resp => {
        console.error("Unable to join", resp)
        // If the server rejects the join, it's often a param issue
        this.updateStatus("Connection Rejected: " + JSON.stringify(resp), "text-red-600")
      })
      .receive("timeout", () => console.log("Networking issue. Still waiting..."))

    this.channel.onError(e => {
      console.error("Channel Error", e)
      this.updateStatus("Channel Error", "text-red-600")
    })

    this.channel.onClose(e => {
      console.log("Channel Closed", e)
      // This fires if the server kills the channel process
    })

    this.socket.onOpen(() => console.log("Socket Opened"))
    this.socket.onClose(e => console.log("Socket Closed", e))
    this.socket.onError(e => console.log("Socket Error", e))

    this.channel.on("new_match", payload => {
      console.log("New Match:", payload)
      if (payload.matches) {
        payload.matches.forEach(match => this.appendMatch(match))
      }
    })
  }

  stop(event) {
    if (event) event.preventDefault()

    if (this.channel) {
      this.channel.leave()
      this.channel = null
    }
    if (this.socket) {
      this.socket.disconnect()
      this.socket = null
    }

    // Only attempt to hide modal if it still exists (it might be gone on page transition/disconnect)
    if (this.hasModalTarget) {
      this.modalTarget.classList.add("hidden")
      this.modalTarget.style.display = "none"
    }
  }

  buildParams() {
    const query = this.queryTarget.value
    const threshold = parseFloat(this.thresholdTarget.value)

    // Get hidden inputs
    const keywordInputs = this.element.querySelectorAll("input[name='track[keywords][]']")
    let keywords = Array.from(keywordInputs)
      .map(input => input.value)
      .filter(val => val !== "")

    // Also check the pending text in the tag input
    const pendingInput = this.element.querySelector("input[data-tags-target='input']")
    if (pendingInput && pendingInput.value.trim() !== "") {
      const pendingVal = pendingInput.value.trim().replace(/,/g, "")
      if (pendingVal && !keywords.includes(pendingVal)) {
        keywords.push(pendingVal)
      }
    }

    const params = { threshold, keywords }
    if (query) params.query = query

    return params
  }

  appendMatch(match) {
    const post = match.post
    const scoreColor = match.score >= 1.0 ? "text-green-600" : "text-[#287fc6]"

    const html = `
      <div class="p-4 bg-white border border-gray-200 rounded-lg shadow-sm animate-fade-in-down">
        <div class="flex justify-between items-start">
          <div class="flex-1">
            <p class="text-gray-900 text-sm whitespace-pre-wrap">${this.escapeHtml(post.text)}</p>
            <div class="mt-2 text-xs text-gray-500 flex items-center gap-2">
              <span>${new Date().toLocaleTimeString()}</span>
              <span>•</span>
              <span class="font-mono">${post.uri.split("/").pop()}</span>
            </div>
          </div>
          <div class="ml-4 flex-shrink-0">
             <span class="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-gray-100 ${scoreColor}">
               ${match.score.toFixed(2)}
             </span>
          </div>
        </div>
      </div>
    `
    this.resultsTarget.insertAdjacentHTML("afterbegin", html)
  }

  updateStatus(text, colorClass) {
    this.statusTarget.textContent = text
    this.statusTarget.className = `text-sm font-medium ${colorClass}`
  }

  escapeHtml(unsafe) {
    return unsafe
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;")
      .replace(/'/g, "&#039;")
  }
}
