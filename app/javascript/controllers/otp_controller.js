import { Controller } from "@hotwired/stimulus"

// Six-box one-time-code input.
//
// The boxes are presentation; a hidden field carries the value, so the server
// receives a single `code` parameter and the form still works without any of
// this. Behaviour aims at what people actually do: type six digits, or paste
// all six at once from a password manager.
export default class extends Controller {
  static targets = ["box", "value", "form", "group"]

  connect() {
    this.sync()
  }

  onInput(event) {
    const box = event.target
    // Strip anything non-numeric, including the character just typed.
    box.value = box.value.replace(/\D/g, "").slice(-1)

    if (box.value) this.focusNext(box)

    this.sync()
    this.submitIfComplete()
  }

  onKeydown(event) {
    const box = event.target

    // Backspace on an empty box steps back rather than doing nothing, which is
    // what every other code input does and therefore what fingers expect.
    if (event.key === "Backspace" && !box.value) {
      event.preventDefault()
      const previous = this.previousBox(box)
      if (previous) {
        previous.value = ""
        previous.focus()
        this.sync()
      }
      return
    }

    if (event.key === "ArrowLeft") {
      event.preventDefault()
      this.previousBox(box)?.focus()
    }

    if (event.key === "ArrowRight") {
      event.preventDefault()
      this.nextBox(box)?.focus()
    }
  }

  onPaste(event) {
    event.preventDefault()

    const digits = (event.clipboardData?.getData("text") || "").replace(/\D/g, "").slice(0, this.boxTargets.length)
    if (!digits) return

    this.boxTargets.forEach((box, i) => { box.value = digits[i] || "" })
    this.boxTargets[Math.min(digits.length, this.boxTargets.length) - 1]?.focus()

    this.sync()
    this.submitIfComplete()
  }

  // Clicking into the middle of a half-filled code is almost always a mistake;
  // send the caret to the first empty box instead.
  onFocus(event) {
    const firstEmpty = this.boxTargets.find((box) => !box.value)
    if (firstEmpty && firstEmpty !== event.target) firstEmpty.focus()
  }

  sync() {
    this.valueTarget.value = this.boxTargets.map((box) => box.value).join("")
  }

  // Submitting on the sixth digit removes a click for the overwhelmingly common
  // case. A wrong code costs a re-entry either way.
  submitIfComplete() {
    if (this.valueTarget.value.length !== this.boxTargets.length) return

    this.groupTarget.dataset.complete = "true"
    this.formTarget.requestSubmit()
  }

  nextBox(box) {
    return this.boxTargets[this.boxTargets.indexOf(box) + 1]
  }

  previousBox(box) {
    return this.boxTargets[this.boxTargets.indexOf(box) - 1]
  }

  focusNext(box) {
    this.nextBox(box)?.focus()
  }
}
