import { Controller } from "@hotwired/stimulus"

// The left rail: the product's own uptime strip, running the full height of the
// page as its spine. Continuous monitoring made structural rather than stated.
//
// Density is derived from the viewport so the bars stay the same physical size
// on a laptop and an ultrawide.
const BAR_PITCH = 6

export default class extends Controller {
  static targets = ["bars"]

  connect() {
    this.render()
    this.onResize = () => this.render()
    window.addEventListener("resize", this.onResize, { passive: true })
  }

  disconnect() {
    window.removeEventListener("resize", this.onResize)
  }

  render() {
    const count = Math.max(12, Math.floor(this.barsTarget.clientHeight / BAR_PITCH))
    const bars = []

    for (let i = 0; i < count; i++) {
      const bar = document.createElement("span")
      bar.className = `mk-railbar${modifierFor(i, count)}`
      bars.push(bar)
    }

    this.barsTarget.replaceChildren(...bars)
  }
}

// A handful of blemishes, placed proportionally so the rail reads as real
// history rather than a solid green line — which would be its own small lie.
function modifierFor(index, count) {
  const at = index / count

  if (near(at, 0.22) || near(at, 0.71)) return " mk-railbar--warn"
  if (near(at, 0.47)) return " mk-railbar--down"
  if (near(at, 0.86)) return " mk-railbar--void"
  return ""
}

function near(value, target) {
  return Math.abs(value - target) < 0.008
}
