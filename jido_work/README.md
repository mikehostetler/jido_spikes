# Jido Work

This spike tests whether a Jido v3 ReAct agent can use complete Agent Skills
packages. It uses one Phoenix LiveView, a real LM Studio path, a deterministic
QA path, Jido VFS storage, and Jido Shell tools.

## Candidate identity

- Jido `release/v3`: `ec96da6015b4b1e5a1642d50651235d9d52808ec`
- `agentjido/skills`: `a71868c975d13e6a92d3dfad802b799eac42ce79`
- Jido VFS `1.0.1`: published Hex package
- Jido Shell `main`: `3c585dd890376f16de5d38902ab7dd0124424a56`
- Skills: `jido` and `tutor`, copied without changes under `priv/skills/`

Jido v3 `Jido.AI.Skill` loads only the root `SKILL.md`. The
`JidoWork.FullSkillSource` adapter delegates root discovery and loading to that
native module. It adds a bounded resource manifest and a
`load_skill_resource` tool for nested references. This is the capability under
test. The ReAct agent raises `limits.tool_output_bytes` to 65,536 bytes so the
complete 23 KB Jido root skill reaches the model without truncation.

Project files use `Jido.VFS.Adapter.InMemory`. `Jido.Shell.Agent` attaches to
that caller-owned filesystem. Thin application tools provide VFS list, read,
search, and checked-edit operations. The shell tool allows only `pwd`, `ls`,
`cat`, and `help`. It does not expose host commands or host files.

The skill adapter can read only vendored skill resources. It does not execute
scripts. Explicit `$jido` and `$tutor` requests also install a skill gate.
Project tools stay blocked until ReAct loads the matching root and route
resource.

## Run

Start LM Studio and its local API server. Load a tool-capable model. Then run:

```bash
mix setup
mix phx.server
```

Open <http://127.0.0.1:4000>. Select **LM Studio**, enter the model ID from
`GET http://127.0.0.1:1234/v1/models`, and run a prompt.

Use **Deterministic QA** when LM Studio is not available. This path still runs
the real Jido ReAct flow, the full skill source, and the mock tools. A scripted
inference client chooses fixed tool calls so the result is repeatable.

## Checks

```bash
mix format --check-formatted
mix compile --warnings-as-errors
mix test
```

## Browser QA result

- Deterministic QA completed both `$jido` and `$tutor` ReAct paths. It loaded
  each root and required nested resource. The `$jido` path repaired the VFS
  calculator and verified the changed file through Jido Shell.
- LM Studio with `qwen/qwen3-coder-next` loaded the complete Jido root, command
  registry, Work, Understand, and Verify Katas, and the Debug and Verify
  methods. It then read both project files through Jido VFS. The skill gate was
  satisfied before project tools became available.
- The live model reached the five-minute elapsed limit before it edited the
  file. This is a model latency result, not a successful end-to-end live run.

## Scope limits

- This is a local technical spike, not a supported package.
- The in-memory Jido VFS workspace is shared by browser sessions.
- LM Studio model quality and tool-call reliability depend on the selected
  local model.
- Jido v3 caps ReAct at eight tool rounds. The live check records this as a
  core follow-up because advanced skills spend several sequential rounds on
  progressive disclosure before project work starts.
- The full skill adapter loads text resources only. It lists other regular
  files but does not execute or attach them.
