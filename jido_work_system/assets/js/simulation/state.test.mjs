import assert from "node:assert/strict"
import test from "node:test"

import {acceptProjection, transitionDuration} from "./state.mjs"

const projection = (runId, revision) => ({
  schema_version: 1,
  run_id: runId,
  revision,
  scene: {},
})

test("accepts a first projection and a newer revision", () => {
  const first = acceptProjection(null, projection("run-1", 0))
  assert.equal(first.accepted, true)

  const next = acceptProjection(first.state, projection("run-1", 1))
  assert.equal(next.accepted, true)
  assert.equal(next.state.revision, 1)
})

test("rejects duplicate and stale transitions", () => {
  const current = projection("run-1", 4)

  assert.equal(acceptProjection(current, projection("run-1", 4)).accepted, false)
  assert.equal(acceptProjection(current, projection("run-1", 3)).accepted, false)
})

test("accepts a same-revision full resync", () => {
  const current = projection("run-1", 4)
  const result = acceptProjection(current, projection("run-1", 4), {resync: true})

  assert.equal(result.accepted, true)
  assert.equal(result.reason, "resync")
})

test("accepts revision zero for another run", () => {
  const current = projection("run-1", 8)
  const result = acceptProjection(current, projection("run-2", 0))

  assert.equal(result.accepted, true)
  assert.equal(result.reason, "new_run")
})

test("rejects an invalid schema", () => {
  const result = acceptProjection(null, {schema_version: 2, run_id: "run-1", revision: 0})
  assert.equal(result.accepted, false)
  assert.equal(result.reason, "invalid")
})

test("removes animation time when reduced motion is active", () => {
  const transition = {duration_ms: 850}

  assert.equal(transitionDuration(transition), 850)
  assert.equal(transitionDuration(transition, {reducedMotion: true}), 0)
  assert.equal(transitionDuration(null), 0)
})
