export const acceptProjection = (current, incoming, {resync = false} = {}) => {
  if (!incoming || incoming.schema_version !== 1 || !incoming.run_id) {
    return {accepted: false, state: current, reason: "invalid"}
  }

  if (!current || current.run_id !== incoming.run_id) {
    return {accepted: true, state: incoming, reason: "new_run"}
  }

  if (incoming.revision > current.revision) {
    return {accepted: true, state: incoming, reason: "new_revision"}
  }

  if (resync && incoming.revision === current.revision) {
    return {accepted: true, state: incoming, reason: "resync"}
  }

  return {accepted: false, state: current, reason: "stale"}
}

export const transitionDuration = (transition, {reducedMotion = false} = {}) => {
  if (!transition || reducedMotion) return 0
  return Math.max(0, transition.duration_ms || 0)
}
