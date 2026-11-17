import {WorkSystemStage} from "../simulation/stage"

const ScenarioStage = {
  mounted() {
    this.destroyedStage = false
    this.stage = new WorkSystemStage({
      reducedMotion: window.matchMedia("(prefers-reduced-motion: reduce)").matches,
      onComplete: (runId, revision) => {
        this.pushEvent("animation_complete", {run_id: runId, revision})
      },
    })

    this.sceneEventRef = this.handleEvent("scene:sync", projection => {
      this.stage.apply(projection)
    })

    this.visibilityHandler = () => {
      if (document.hidden) this.stage.stop()
      else this.stage.start()
    }
    document.addEventListener("visibilitychange", this.visibilityHandler)

    this.mountStage()
  },

  async mountStage() {
    try {
      await this.stage.mount(this.el)
      if (this.destroyedStage) return
      const projection = await this.pushEvent("scene_ready", {})
      if (projection.status !== "no_run") this.stage.apply(projection, {resync: true})
    } catch (_error) {
      this.el.dataset.stageState = "error"
      const fallback = this.el.querySelector(".scenario-stage-fallback")
      if (fallback) fallback.textContent = "The visual stage could not start. Use the controls or open debug view."
      this.pushEvent("stage_failed", {}).catch(() => {})
    }
  },

  disconnected() {
    this.stage.stop()
  },

  async reconnected() {
    this.stage.start()
    const projection = await this.pushEvent("scene_ready", {})
    if (projection.status !== "no_run") this.stage.apply(projection, {resync: true})
  },

  destroyed() {
    this.destroyedStage = true
    document.removeEventListener("visibilitychange", this.visibilityHandler)
    if (this.sceneEventRef) this.removeHandleEvent(this.sceneEventRef)
    this.stage.destroy()
  },
}

export default ScenarioStage
