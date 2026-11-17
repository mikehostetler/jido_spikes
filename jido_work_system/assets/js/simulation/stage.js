import {Application, Container, Graphics, Text} from "pixi.js"

import {acceptProjection, transitionDuration} from "./state.mjs"

const COLORS = {
  background: 0x071017,
  floor: 0x10232c,
  grid: 0x21404d,
  text: 0xe2e8f0,
  muted: 0x94a3b8,
  human: 0x38bdf8,
  cell: 0xa78bfa,
  task: 0xfbbf24,
  evidence: 0x22d3ee,
  success: 0x34d399,
  failure: 0xfb7185,
}

const easeInOut = value => value < 0.5
  ? 2 * value * value
  : 1 - Math.pow(-2 * value + 2, 2) / 2

export class WorkSystemStage {
  constructor({onComplete, reducedMotion = false}) {
    this.onComplete = onComplete
    this.reducedMotion = reducedMotion
    this.app = null
    this.current = null
    this.nodes = new Map()
    this.animationHandler = null
    this.resizeObserver = null
    this.destroyed = false
  }

  async mount(element) {
    this.element = element
    this.app = new Application()

    await this.app.init({
      resizeTo: element,
      background: COLORS.background,
      antialias: true,
      autoDensity: true,
      resolution: Math.min(window.devicePixelRatio || 1, 2),
      sharedTicker: false,
    })

    if (this.destroyed) {
      this.app.destroy({removeView: true}, {children: true})
      return
    }

    element.appendChild(this.app.canvas)
    element.dataset.stageState = "ready"
    element.querySelector(".scenario-stage-fallback")?.remove()

    this.resizeObserver = new ResizeObserver(() => {
      if (this.current && !this.destroyed) {
        const interruptedAnimation = Boolean(this.animationHandler)
        this.render(this.current, {animate: false})
        if (interruptedAnimation) queueMicrotask(() => this.complete(this.current))
      }
    })
    this.resizeObserver.observe(element)
  }

  apply(incoming, {resync = false} = {}) {
    if (!this.app || this.destroyed) return false

    const result = acceptProjection(this.current, incoming, {resync})
    if (!result.accepted) return false

    this.current = result.state
    this.render(this.current, {animate: !resync})

    if (resync) queueMicrotask(() => this.complete(this.current))
    return true
  }

  render(projection, {animate}) {
    this.cancelAnimation()
    this.clearStage()
    this.nodes.clear()

    const layout = this.layout()
    this.drawRoom(layout)
    this.drawLocations(projection.scene.locations, layout)
    this.drawActors(projection.scene.actors, layout)
    this.drawTask(projection.scene.task, layout)
    this.drawEvidence(projection.scene.evidence, layout)
    this.drawVerifier(projection.scene.verifier, layout)
    this.drawOutcome(projection.scene.outcome)

    if (animate && projection.transition) {
      this.animate(projection.transition, layout, projection)
    } else if (!animate) {
      this.app.render()
    } else {
      queueMicrotask(() => this.complete(projection))
    }
  }

  layout() {
    const width = Math.max(this.app.screen.width, 320)
    const height = Math.max(this.app.screen.height, 430)

    return {
      width,
      height,
      locations: {
        "owner-desk": {x: width * 0.16, y: height * 0.3},
        handoff: {x: width * 0.39, y: height * 0.52},
        workbench: {x: width * 0.63, y: height * 0.3},
        "verification-desk": {x: width * 0.84, y: height * 0.58},
      },
    }
  }

  drawRoom(layout) {
    const floor = new Graphics()
      .roundRect(24, 24, layout.width - 48, layout.height - 48, 28)
      .fill({color: COLORS.floor})
      .stroke({color: 0x315264, width: 2, alpha: 0.7})

    this.app.stage.addChild(floor)

    const grid = new Graphics()
    for (let x = 60; x < layout.width; x += 54) {
      grid.moveTo(x, 42).lineTo(x, layout.height - 42)
    }
    for (let y = 60; y < layout.height; y += 54) {
      grid.moveTo(42, y).lineTo(layout.width - 42, y)
    }
    grid.stroke({color: COLORS.grid, width: 1, alpha: 0.2})
    this.app.stage.addChild(grid)

    const title = new Text({
      text: "MIKE'S WORK ROOM",
      style: {fontFamily: "ui-monospace, monospace", fontSize: 11, fill: COLORS.muted, letterSpacing: 2},
    })
    title.position.set(48, 40)
    this.app.stage.addChild(title)
  }

  drawLocations(locations, layout) {
    locations.forEach(location => {
      const point = layout.locations[location.id]
      const zone = new Graphics()
        .roundRect(-68, -38, 136, 76, 16)
        .fill({color: 0x173440, alpha: 0.78})
        .stroke({color: 0x3b6372, width: 1})
      zone.position.set(point.x, point.y)
      this.app.stage.addChild(zone)

      const label = new Text({
        text: location.label.toUpperCase(),
        style: {fontFamily: "ui-monospace, monospace", fontSize: 10, fill: COLORS.muted, letterSpacing: 1},
      })
      label.anchor.set(0.5)
      label.position.set(point.x, point.y + 53)
      this.app.stage.addChild(label)
    })
  }

  drawActors(actors, layout) {
    actors.forEach(actor => {
      const node = new Container()
      const isHuman = actor.kind === "human"
      const color = isHuman ? COLORS.human : COLORS.cell
      const body = new Graphics()

      if (isHuman) {
        body.circle(0, -17, 13).fill({color})
        body.roundRect(-20, -2, 40, 44, 14).fill({color})
      } else {
        body.roundRect(-25, -25, 50, 58, 12).fill({color})
        body.circle(-10, -6, 4).fill({color: 0x0f172a})
        body.circle(10, -6, 4).fill({color: 0x0f172a})
        body.roundRect(-12, 8, 24, 4, 2).fill({color: 0x0f172a})
      }

      const glow = new Graphics().circle(0, 8, 36).stroke({color, width: 2, alpha: 0.32})
      node.addChild(glow, body)

      const label = new Text({
        text: actor.label,
        style: {fontFamily: "ui-sans-serif, system-ui", fontSize: 12, fill: COLORS.text, fontWeight: "600"},
      })
      label.anchor.set(0.5, 1)
      label.position.set(0, -48)
      node.addChild(label)

      const point = layout.locations[actor.location]
      node.position.set(point.x, point.y - 4)
      this.app.stage.addChild(node)
      this.nodes.set(actor.id, node)
    })
  }

  drawTask(task, layout) {
    if (!task) return

    const node = new Container()
    const card = new Graphics()
      .roundRect(-38, -26, 76, 52, 8)
      .fill({color: COLORS.task})
      .stroke({color: 0xfef3c7, width: 2, alpha: 0.8})
    const lines = new Graphics()
      .roundRect(-24, -12, 36, 4, 2)
      .roundRect(-24, -2, 48, 4, 2)
      .roundRect(-24, 8, 28, 4, 2)
      .fill({color: 0x78350f, alpha: 0.65})

    node.addChild(card, lines)
    node.rotation = -0.04

    const point = layout.locations[task.location]
    const horizontalOffset = task.location === "verification-desk" ? -48 : 54
    node.position.set(point.x + horizontalOffset, point.y - 48)
    this.app.stage.addChild(node)
    this.nodes.set(task.id, node)
    this.nodes.set("task", node)
  }

  drawEvidence(evidence, layout) {
    evidence.forEach((item, index) => {
      const node = new Container()
      const token = new Graphics()
        .circle(0, 0, 14)
        .fill({color: COLORS.evidence})
        .stroke({color: 0xcffafe, width: 2})
      const check = new Text({text: "✓", style: {fontSize: 15, fill: 0x083344, fontWeight: "700"}})
      check.anchor.set(0.5)
      node.addChild(token, check)

      const point = layout.locations[item.location]
      node.position.set(point.x - 36 + index * 24, point.y - 54)
      this.app.stage.addChild(node)
      this.nodes.set(item.id, node)
    })
  }

  drawVerifier(verifier, layout) {
    const point = layout.locations["verification-desk"]
    const color = verifier.status === "passed"
      ? COLORS.success
      : verifier.status === "failed"
        ? COLORS.failure
        : COLORS.muted

    const node = new Container()
    const light = new Graphics()
      .circle(0, 0, 16)
      .fill({color, alpha: verifier.status === "idle" ? 0.35 : 1})
      .stroke({color: 0xffffff, width: 2, alpha: 0.5})
    node.addChild(light)
    node.position.set(point.x + 28, point.y - 45)
    this.app.stage.addChild(node)
    this.nodes.set("verifier", node)
  }

  drawOutcome(outcome) {
    if (!outcome) return

    const accepted = outcome.human_acceptance === "accepted"
    const badge = new Container()
    const background = new Graphics()
      .roundRect(-92, -23, 184, 46, 23)
      .fill({color: accepted ? COLORS.success : COLORS.failure, alpha: 0.95})
    const label = new Text({
      text: accepted ? "JOB DONE" : "JOB STOPPED",
      style: {fontFamily: "ui-sans-serif, system-ui", fontSize: 13, fill: 0x071017, fontWeight: "700", letterSpacing: 1},
    })
    label.anchor.set(0.5)
    badge.addChild(background, label)
    badge.position.set(this.app.screen.width / 2, this.app.screen.height - 54)
    this.app.stage.addChild(badge)
  }

  animate(transition, layout, projection) {
    const node = this.nodes.get(transition.subject_id)
    const from = transition.from && layout.locations[transition.from]
    const to = transition.to && layout.locations[transition.to]
    const duration = transitionDuration(transition, {reducedMotion: this.reducedMotion})

    if (!node || !to || duration <= 0 || transition.from === transition.to) {
      queueMicrotask(() => this.complete(projection))
      return
    }

    const offset = {x: node.x - to.x, y: node.y - to.y}
    const start = from || to
    const startX = start.x + offset.x
    const startY = start.y + offset.y
    const endX = to.x + offset.x
    const endY = to.y + offset.y
    let elapsed = 0

    node.position.set(startX, startY)

    this.animationHandler = ticker => {
      elapsed += ticker.deltaMS
      const progress = Math.min(elapsed / duration, 1)
      const eased = easeInOut(progress)
      node.position.set(
        startX + (endX - startX) * eased,
        startY + (endY - startY) * eased,
      )

      if (progress >= 1) {
        this.cancelAnimation()
        this.complete(projection)
      }
    }

    this.app.ticker.add(this.animationHandler)
  }

  complete(projection) {
    if (!this.destroyed) this.onComplete(projection.run_id, projection.revision)
  }

  cancelAnimation() {
    if (this.animationHandler && this.app) this.app.ticker.remove(this.animationHandler)
    this.animationHandler = null
  }

  clearStage() {
    this.app.stage.removeChildren().forEach(child => child.destroy({children: true}))
  }

  stop() {
    if (this.app && !this.destroyed) this.app.stop()
  }

  start() {
    if (this.app && !this.destroyed) this.app.start()
  }

  destroy() {
    if (this.destroyed) return
    this.destroyed = true
    this.cancelAnimation()
    if (this.resizeObserver) this.resizeObserver.disconnect()
    if (this.app) this.app.destroy({removeView: true}, {children: true})
    this.app = null
  }
}
