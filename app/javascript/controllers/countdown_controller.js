import { Controller } from "@hotwired/stimulus"

// Counts down to a service's next scheduled health check.
//
// No polling is required. When a check completes, Service#perform_check! calls
// update!, which fires the after_update_commit broadcast; Turbo swaps in a fresh
// service card and this controller reconnects with a new seconds value. The
// countdown therefore resets itself without ever asking the server.
export default class extends Controller {
  static values = {
    seconds: Number,
    checked: Boolean,
    paused: Boolean
  }

  connect() {
    this.remaining = this.secondsValue
    this.render()

    // A paused service has no next check to count toward, so don't burn a timer.
    if (this.pausedValue) return

    this.timer = setInterval(() => this.tick(), 1000)
  }

  disconnect() {
    this.stop()
  }

  stop() {
    if (this.timer) {
      clearInterval(this.timer)
      this.timer = null
    }
  }

  tick() {
    // Already at zero: the sweep runs once a minute, so there is nothing further
    // to count and no reason to keep a timer alive.
    if (this.remaining <= 0) {
      this.stop()
      return
    }

    this.remaining -= 1
    this.render()
  }

  render() {
    if (this.pausedValue) {
      this.element.textContent = "monitoring paused"
      return
    }

    if (!this.checkedValue) {
      this.element.textContent = "awaiting first check"
      return
    }

    // "due now" rather than "checking…": the scheduler sweeps every 60s, so a
    // service can sit at zero for up to a minute before it is actually checked.
    if (this.remaining <= 0) {
      this.element.textContent = "due now"
      return
    }

    this.element.textContent = `next check in ${this.formatDuration(this.remaining)}`
  }

  formatDuration(totalSeconds) {
    const minutes = Math.floor(totalSeconds / 60)
    const seconds = totalSeconds % 60

    return `${minutes}:${String(seconds).padStart(2, "0")}`
  }
}
