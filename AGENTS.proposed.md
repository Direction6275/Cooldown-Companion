# AGENTS.md — Cooldown Companion

## Lane

- This checkout targets World of Warcraft 12.1 PTR, Lua 5.1 with `bit`. Read the Interface from the addon TOCs.
- PTR references are exposed from `C:\Users\nicho\Desktop\Cooldown-Companion` through ignored junctions.
- Treat this lane label, `agent-reference/README.md`, `.codex/config.toml`, and `.mcp.json` as one promotion unit. When 12.1 becomes live, update all four together. Never fill a PTR evidence gap with live tools or source.

## Working Rules

- Make the smallest task-scoped change. Preserve unrelated edits and report adjacent cleanup instead of doing it.
- Inspect current owners, callers, defaults, migrations, and load order before changing behavior.
- Ask only when a choice materially changes the result or authorizes a workaround. Otherwise, state reasonable assumptions and proceed.
- For non-trivial work, define success and distinguish static proof, observed runtime evidence, and owner in-game validation still needed.

## WoW Evidence

- Before writing code that depends on a WoW API, use `blizzard-ui-ptr` generated records to verify the exact function, event, enum, type, nilability, defaults, and secret/access annotations. Check source provenance first; if a corpus fails its lane, Interface, build, or source guard, treat it as unavailable.
- Use `warcraft-wiki` for discovery, behavior, timing warnings, deprecations, replacements, and patch history. Verify active-lane structure and security metadata against Blizzard's generated records.
- Use `blizzard-ui-ptr` source tools for Blizzard implementations, templates, mixins, and call sites; `wago-tools` for DB2 identity facts; and `cc-devbridge-ptr` for observed CC state, config, events, deltas, errors, and spell captures. Corroborate build-sensitive Wago values against PTR evidence.
- Runtime snapshots prove only their recorded character, spec, combat state, target, instance, time, client build, addon revision, and source. Changes that can run in combat or restricted content require targeted in-game validation in that state.
- Prefer documented current namespaced APIs. Training data and external prose are discovery only.
- If the supported path is missing, ask before guessed APIs, `pcall` probes, heuristics, polling, caching, bridge logic, spell exceptions, or other indirect approaches. Do not use `pcall` for discovery or normal control flow.

## Routed Local Knowledge

Read only what the task requires:

- Start with `agent-reference/README.md` when local references are needed; it controls current, lane-specific, historical, and scoped status.
- API selection, combat-facing diagnosis, or secret-value work: use the relevant part of `agent-reference/api-sources.md`, `agent-reference/planning-and-verification.md`, `agent-reference/combat-api-decision-map.md`, or `agent-reference/secret-values.md`, then verify the active-lane API and current code.
- Aura work: inspect current owners such as `CooldownCompanion/Core/AuraDisplay.lua` and `CooldownCompanion/OtherBars/ResourceBarAuraHost.lua` first. `agent-reference/hotfix-overrides-12.1.md` is the current PTR hazard map; `docs/12.1-aura-validation-matrix.md` is scoped historical evidence, not implementation authority.
- Cooldown Viewer, AceGUI, panel ownership, and recurring project hazards: use the relevant section of `agent-reference/cooldown-viewer.md` or `agent-reference/patterns-and-gotchas.md`, then verify cited code and APIs.
- Performance: read `agent-reference/perf-program-2026-06-07-debrief.md` before proposing work. Its non-aura owner decisions remain context; measurements and aura statements are historical, so profile the current build.
- Reference maintenance: promote only hard-won, reusable knowledge that current code or authoritative tools cannot cheaply rediscover. Require lane/build, date, provenance, scope, and a supersession or review trigger.

Files classified as historical or scoped evidence by `agent-reference/README.md` are not current authority. Never use `agent-reference/refresh-contract-matrix.md`; it describes an abandoned design.

## Boundaries

- Do not change branches, commit, merge, push, or publish unless explicitly requested. Never add agent coauthor attribution.
- Keep development-only artifacts local unless the user requests the exact file. This includes `tests/`, `docs/plans/`, `agent-reference/`, `.agents/`, `.codex/`, `.tmp/`, and local scripts. If one is accidentally tracked, remove only its index entry and preserve the local file.
