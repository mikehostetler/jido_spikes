# Jido Work System Spike Plan

## Goal

Build one deterministic, local simulation that tests the work-system data model. Store all durable state in Ash resources with AshSqlite. Show the full state on one Phoenix LiveView screen.

## Compatibility boundary

- The spike owns its data model and simulation logic.
- `jido_vsm` validates the shape of each viable work cell through `Jido.Vsm.Topology.CellSpec`. The spike does not copy or start the VSM runtime.
- No new public API is added to a Jido package.

## Small implementation sequence

1. Create a standalone Phoenix project with Ash and AshSqlite.
2. Add cohesive resources for organization, work, judgment, execution, evidence, and context.
3. Add a deterministic simulation service with success and rework or escalation paths.
4. Add one LiveView screen with reset and run controls.
5. Add focused tests for the model, authority, transitions, receipts, topology, and both paths.
6. Run formatting, database setup, tests, and compilation. Document limits and run steps.

## Explicit limits

Do not add authentication, distributed execution, dynamic hiring, production integrations, paid model calls, or a general workflow DSL. Do not change `jido_vsm` or any existing spike.
