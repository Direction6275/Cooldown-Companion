# AGENTS.md — Cooldown Companion

## Scope

- Target: World of Warcraft 12.1 PTR, Lua 5.1 with `bit`.
- Read the Interface value from the addon TOCs rather than a copied version number.
- Local-only project references are exposed from `C:\Users\nicho\Desktop\Cooldown-Companion` through ignored junctions.

## Working Rules

- Make the smallest task-scoped change. Preserve unrelated user edits; report adjacent cleanup instead of performing it.
- Ask only when a choice would materially change the result or authorize a workaround. Otherwise, state reasonable assumptions and proceed.
- For non-trivial work, define success and verify proportionately. Distinguish static evidence, observed runtime evidence, and required owner in-game validation.

## Evidence Before Code

- Verify correctness-relevant API, data, and runtime assumptions before implementation. Training data and external prose are discovery aids, not proof.
- Use the smallest authoritative source set that answers the question. `agent-reference/api-sources.md` maps sources and freshness. Use task-relevant parts of `agent-reference/planning-and-verification.md` for test design and confidence labels, not as a mandatory full checklist or plan-approval gate.
- Prefer current namespaced APIs when a documented equivalent exists. Check deprecations with `wow-api`; use `wago-tools` for shipped DB2 facts.
- The applicable project hotfix override wins patch-specific conflicts. For 12.1-only APIs and Blizzard internals, use PTR sources rather than live or older generated snapshots.
- Use `cc-devbridge` and source evidence before asking the user to test. When they cannot establish timing, combat, taint, secret-value, or other runtime behavior, request the smallest focused in-game test. Never fill the gap with theory.
- If the supported path cannot be established, stop and ask before guessed APIs, `pcall` probes, heuristics, polling, caching, bridge logic, spell-specific exceptions, or other workarounds. Do not use `pcall` for discovery or normal control flow.

## Reference Routing

Read only the references relevant to the task:

- API/tool selection and verification: `agent-reference/api-sources.md` and, selectively, `agent-reference/planning-and-verification.md`.
- Combat-facing symptoms: `agent-reference/combat-api-decision-map.md`.
- Patch, secret-value, cooldown, tooltip, macro, private-aura, or CDM behavior: the applicable `agent-reference/hotfix-overrides*.md`, `agent-reference/secret-values.md`, and `agent-reference/cooldown-viewer.md`.
- Project structure and recurring implementation hazards: `agent-reference/codebase-map.md` and `agent-reference/patterns-and-gotchas.md`.
- Spell evidence: `agent-reference/spell-api-reference.md` and `agent-reference/spell-api/`; require both out-of-combat and in-combat baselines for full confidence.
- Performance work: read `agent-reference/perf-program-2026-06-07-debrief.md` before proposing changes. For 12.1 aura paths, `agent-reference/hotfix-overrides-12.1.md` and `docs/12.1-aura-tracking-research.md` supersede its pre-12.1 aura statements. Use the older refresh matrices only when explicitly in scope.
- Durable guidance maintenance: `agent-reference/reference-maintenance.md`.

## Repository Boundaries

- Do not change branches, commit, merge, push, or publish unless explicitly requested.
- Never add agent coauthor signatures or similar attribution.
- Keep development-only artifacts local unless the user requests the exact file. This includes `tests/`, `docs/plans/`, `agent-reference/`, `.agents/`, `.codex/`, `.tmp/`, and local scripts. If accidentally tracked, remove only the index entry and preserve the local file.
