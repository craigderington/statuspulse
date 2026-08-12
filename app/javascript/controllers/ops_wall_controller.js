import { Controller } from "@hotwired/stimulus"

// The hero operations wall.
//
// Rather than describing multi-tenancy, the hero shows it: several client
// workspaces checked in parallel, one of which degrades into an incident and
// then recovers. That is the moment the product earns its money, and it is the
// MSP operator's actual day.
//
// Everything here is illustrative. The view labels it as such.
const BAR_COUNT = 20
const TICK_MS = 1100

// The scripted incident, in ticks from the start of each cycle.
const SCRIPT = [
  { at: 6,  state: "degraded", severity: "degraded", text: "Latency above threshold on Checkout API" },
  { at: 11, state: "outage",   severity: "outage",   text: "Checkout API returning HTTP 502" },
  { at: 17, state: "operational", severity: "resolved", text: "Checkout API recovered — incident resolved" },
  { at: 22, state: null,       severity: null,       text: null }
]

export default class extends Controller {
  static targets = ["row", "dot", "strip", "latency", "incident", "clock"]

  connect() {
    this.tick = 0
    this.subject = Math.min(1, this.rowTargets.length - 1)
    this.baseLatencies = this.latencyTargets.map((el) => parseInt(el.textContent, 10) || 120)

    this.stripTargets.forEach((strip, i) => this.fillStrip(strip, i))

    if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) {
      // Compose a representative still frame instead of animating.
      this.applyState(this.subject, "degraded")
      this.showIncident("degraded", SCRIPT[0].text)
      return
    }

    this.timer = setInterval(() => this.advance(), TICK_MS)
  }

  disconnect() {
    if (this.timer) clearInterval(this.timer)
  }

  // ---- rendering -------------------------------------------------------

  fillStrip(strip, rowIndex) {
    strip.replaceChildren()
    for (let i = 0; i < BAR_COUNT; i++) {
      strip.appendChild(this.buildBar(this.sampleClass(rowIndex, i)))
    }
  }

  buildBar(modifier) {
    const bar = document.createElement("span")
    bar.className = modifier ? `mk-bar mk-bar--${modifier}` : "mk-bar"
    // Slight height variation reads as real measurement rather than a barcode.
    bar.style.height = `${72 + Math.floor(Math.random() * 29)}%`
    return bar
  }

  sampleClass(rowIndex, barIndex) {
    if (rowIndex === 3 && barIndex === 9) return "warn"
    if (rowIndex === 1 && barIndex === 21) return "warn"
    if (rowIndex === 2 && barIndex === 4) return "void"
    return null
  }

  advance() {
    this.tick += 1

    this.stripTargets.forEach((strip, i) => {
      const state = this.rowTargets[i].dataset.state
      let modifier = null
      if (i === this.subject && state === "degraded") modifier = "warn"
      if (i === this.subject && state === "outage") modifier = "down"

      strip.appendChild(this.buildBar(modifier))
      if (strip.children.length > BAR_COUNT) strip.firstElementChild.remove()
    })

    this.latencyTargets.forEach((el, i) => {
      const base = this.baseLatencies[i]
      const state = this.rowTargets[i].dataset.state
      const multiplier = state === "outage" ? 0 : state === "degraded" ? 6.5 : 1
      const value = multiplier === 0 ? 0 : Math.round(base * multiplier + (Math.random() * 24 - 12))
      el.textContent = value === 0 ? "—" : value
    })

    if (this.hasClockTarget) {
      this.clockTarget.textContent = `checked ${TICK_MS / 1000}s ago`
    }

    const beat = SCRIPT.find((step) => step.at === this.tick)
    if (beat) {
      if (beat.state) this.applyState(this.subject, beat.state)
      if (beat.text) this.showIncident(beat.severity, beat.text)
      else this.hideIncident()
    }

    if (this.tick > 26) this.tick = 0
  }

  applyState(index, state) {
    const row = this.rowTargets[index]
    if (!row) return

    if (state === "operational") delete row.dataset.state
    else row.dataset.state = state
  }

  showIncident(severity, text) {
    this.incidentTarget.dataset.visible = "true"
    this.incidentTarget.replaceChildren()

    const wrap = document.createElement("div")
    wrap.className = "mk-incident"

    const tag = document.createElement("span")
    tag.className = "mk-incident__tag"
    tag.dataset.severity = severity
    tag.textContent = severity === "resolved" ? "Resolved" : severity

    const body = document.createElement("span")
    body.textContent = text

    wrap.append(tag, body)
    this.incidentTarget.appendChild(wrap)
  }

  hideIncident() {
    this.incidentTarget.dataset.visible = "false"
    this.incidentTarget.replaceChildren()
  }
}
