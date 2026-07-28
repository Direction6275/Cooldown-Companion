# AGENTS.md — Cooldown Companion

## Scope

- Target: World of Warcraft 12.1 PTR, Lua 5.1 with `bit`.
- Read the Interface value from the addon TOCs rather than a copied version number.
- Local-only project references are exposed from `C:\Users\nicho\Desktop\Cooldown-Companion` through ignored junctions.

## Working Rules

- Make the smallest task-scoped change. Preserve unrelated edits and only report adjacent cleanup.
- Ask only when a choice would materially change the result or authorize a workaround. Otherwise, state reasonable assumptions and proceed.
- For non-trivial work, define success and verify proportionately. State what is proven statically, observed at runtime, or still needs owner in-game validation.

## Evidence and Tool Selection

- Inspect task-relevant current code first; consult TOCs, defaults, and migrations when load order, ownership, or persistence matters.
- Match evidence to the claim: current code establishes implementation; the request and applicable owner rulings establish intent; PTR docs/source establish static API contracts; matching-build, addon-revision, and scenario observations establish only that recorded runtime context. Newer primary evidence beats a local summary.
- For 12.1 APIs and Blizzard internals, use `blizzard-ui-ptr` or raw PTR source. Use `wow-api` only for discovery and APIs covered by its reported build; verify every 12.1 availability, signature, and deprecation claim in PTR source. Neither presence nor absence in an older database settles the PTR contract.
- Use `cc-devbridge-ptr` for this checkout. Snapshots are observed persisted/runtime state, not schema authority or proof of forbidden/write-only AuraContainer state.
- Use `wago-tools` for DB2 identity facts such as spell IDs and textures; corroborate build-sensitive values against PTR evidence.
- Prefer documented current namespaced APIs. Treat training data, external prose, and community trackers as discovery only.
- If the supported path is missing, ask before guessed APIs, `pcall` probes, heuristics, polling, caching, bridge logic, spell exceptions, or other workarounds. Do not use `pcall` for discovery or normal control flow.

## Reference Routing

Read only the task-relevant sections below. Other local references are historical or unverified leads, not current authority.

- Aura work: inspect the current owner, such as `CooldownCompanion/Core/AuraDisplay.lua`, `CooldownCompanion/OtherBars/ResourceBarAuraHost.lua`, or relevant config code, then use PTR docs/source. `docs/12.1-aura-validation-matrix.md` is recorded evidence only for its build, addon revision, and scenario; `agent-reference/hotfix-overrides-12.1.md` is a hazard map. Never infer AuraContainer presence from `_auraActive`.
- Project hazards and Cooldown Viewer policy: consult relevant sections of `agent-reference/patterns-and-gotchas.md` or `agent-reference/cooldown-viewer.md`, then verify cited paths, symbols, and APIs.
- Performance: read `agent-reference/perf-program-2026-06-07-debrief.md` before proposing changes. Its non-aura design decisions remain context; measurements and aura statements are historical, so profile the current build.
- Spell captures in `agent-reference/spell-api-reference.md` and `agent-reference/spell-api/` are historical evidence for their recorded context. Out-of-combat plus in-combat captures do not establish current PTR behavior.
- Reference maintenance: use the durable promotion principles in `agent-reference/reference-maintenance.md`.

Do not use `agent-reference/refresh-contract-matrix.md`; it describes an abandoned design.

## Repository Boundaries

- Do not change branches, commit, merge, push, or publish unless explicitly requested.
- Never add agent coauthor signatures or similar attribution.
- Keep development-only artifacts local unless the user requests the exact file. This includes `tests/`, `docs/plans/`, `agent-reference/`, `.agents/`, `.codex/`, `.tmp/`, and local scripts. If accidentally tracked, remove only the index entry and preserve the local file.
