---
title: Avoid Full Group Rebuilds for Style-Only Config Edits
type: perf
date: 2026-06-10
execution: code
---

# Avoid Full Group Rebuilds for Style-Only Config Edits

## Summary

This plan adds a safe `UpdateGroupStyle()` fast path for the runtime-group side of finding #3. The fast path restyles and relayouts active button frames in place when the rendered button sequence is unchanged, then uses the existing full rebuild path when the edit changes display shape, entry identity, or any structural condition.

---

## Problem Frame

Finding #3 in the user-supplied optimization verdict identifies that many high-traffic config callbacks still route style edits through full runtime rebuilds and full config panel refreshes. This plan targets the runtime group rebuild half only. Config column rebuild reduction remains deferred because existing `RefreshConfigPanel()` callers often own control visibility, advanced badges, and selected-panel content.

Finding #2's frame pooling is already present in this checkout, which makes rebuilds less harmful, but style-only edits still pay for release/acquire cleanup, Masque churn, active-list reconstruction, relayout from scratch, and immediate cooldown refresh work when the existing button frames could be updated in place.

The first implementation should avoid widening the config UI surface. Most style controls already call `CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)`, so the lowest-churn optimization is to make that shared owner smarter without editing `ConfigSettings/*` callbacks.

---

## Requirements

**Runtime fast path**

- R1. `UpdateGroupStyle(groupId)` must restyle existing active buttons in place when the rendered button sequence still matches the active buttons. The rendered button sequence is the ordered set of source indexes and `buttonData` objects that `PopulateGroupButtons()` would place in `frame.buttons` after usability filtering.
- R2. The in-place path must update style-owned visuals and geometry, layout points, group frame bookkeeping, group frame size, click-through, config previews, cooldown/visibility state, frame strata, and range-check registrations.
- R3. The in-place path must preserve and restyle text-mode group header rendering only when header enabled/disabled state remains unchanged.

**Fallback boundaries**

- R4. `UpdateGroupStyle(groupId)` must use a combat-aware full rebuild fallback when display mode, rendered button sequence, pool key, text header visibility, icon secondary-cooldown capability, or missing active button state prevents a safe in-place update. In protected combat, fallback must defer instead of mutating active frames.
- R5. Existing direct `RefreshGroupFrame()` callers remain structural. This plan must not convert aura tracking, display-mode switches, trigger condition changes, add/remove/reorder flows, import flows, or selection-driven config rebuilds into the style fast path.
- R6. This plan must not edit `ConfigSettings/*` callbacks. Misclassified callbacks are follow-up work unless a plan revision names exact files and validation scenarios.

**Safety and validation**

- R7. The change must not introduce gameplay-state caches, cooldown/aura throttling, speculative API probes, `pcall` wrappers, or new SavedVariables.
- R8. Local tests must prove the style path avoids `PopulateGroupButtons()` for safe style edits, falls back or defers for structural edits, and does not mutate protected frames during combat.
- R9. Static validation must pass, and in-game combat plus restricted-content validation remains required before treating the optimization as ship-ready.

---

## Scope Boundaries

- Only the runtime group rebuild portion of finding #3 is in scope. Do not lazy-load config UI, reduce config column rebuilds, coalesce cooldown events, change alpha/key-press-highlight drivers, or revisit frame pooling except as a dependency.
- The implementation should be centered in `Core/GroupFrame.lua`. Do not edit `ConfigSettings/*` callbacks in this plan.
- Existing callbacks that rebuild the config UI for control visibility, advanced badges, or selected-panel content keep doing so. This plan should avoid adding new `RefreshConfigPanel()` calls.
- Do not change cooldown, aura, item, charge, display-count, cast-count, visibility, secret-value, or sound-alert truth semantics.
- Do not claim runtime completion from local tests alone. Combat and restricted-content testing is still required because the affected path updates live frames from config callbacks.

---

## Key Technical Decisions

- KTD1. Centralize on `UpdateGroupStyle()`: Existing style-heavy config surfaces already call this method, so making it conditional avoids a broad widget-by-widget dispatch table and keeps structural callers unchanged.
- KTD2. Use a structural compatibility check: The fast path is allowed only when each visible position maps to the same `buttonData` object, the same source index, and the same `GetButtonPoolKey(group, buttonData, effectiveStyle)` as the active button.
- KTD3. Treat lane `UpdateStyle` methods as invalidating style refreshes: Icon and bar style methods clear runtime fields, so the fast path must call the existing cooldown/visibility refresh before returning and must not claim that live truth is preserved without rehydration.
- KTD4. Extract shared header/layout helpers: `PopulateGroupButtons()` and the fast path should share text header styling, active-button positioning, and populate-equivalent frame bookkeeping so future layout fixes do not diverge.
- KTD5. Preserve combat-aware fallback behavior: Protected frames must defer before compatibility checks during combat; otherwise, incompatible edits should keep using the existing full rebuild path.

---

## Implementation Units

### U1. Extract shared text-header and layout helpers

- **Goal:** Move the text-mode header style update, active button positioning, and frame bookkeeping out of `PopulateGroupButtons()` into local helpers that can be reused by `UpdateGroupStyle()`.
- **Files:** `Core/GroupFrame.lua`.
- **Approach:** Add one helper that applies or hides the text header and returns `headerHeight`, and one helper that records `visibleButtonCount`, `layoutButtonCount`, `_layoutDirty`, `_lastVisibleCount`, and active button points from the current group style, sizing options, and visible count. `UpdateGroupStyle()` may use the header helper only after compatibility confirms the header enabled/disabled state is unchanged.
- **Test scenarios:** Text groups with and without headers keep the same header text, font, color, width, and anchor after a normal populate. Icon, bar, text, texture, and trigger groups keep the same active button points after populate. Parent-container non-compact groups refresh `layoutButtonCount`. Compact groups still defer to `UpdateGroupLayout()` after active frame bookkeeping is refreshed.
- **Verification:** `luac -p Core/GroupFrame.lua`; focused harness coverage in U3.

### U2. Add the `UpdateGroupStyle()` fast path with structural fallback

- **Goal:** Make style-only config edits update active buttons in place instead of releasing/acquiring or recreating button frames.
- **Files:** `Core/GroupFrame.lua`.
- **Approach:** Before compatibility checks, defer when `InCombatLockdown()` and the group frame is protected. Then walk the rendered button sequence, derive each effective style and pool key, and confirm the active button at that visible position already owns the same source index, same `buttonData` object, and same pool key. If compatible, call the lane `UpdateStyle()` method, run shared layout and frame bookkeeping, resize, click-through, previews, cooldown/visibility refresh, strata propagation, compact-layout handling, and range-check registration. Masque-enabled icon groups should use the full rebuild fallback because the existing Masque path is remove/add based. If incompatible, use the existing `PopulateGroupButtons()` rebuild path after the protected-combat guard.
- **Test scenarios:** Changing icon size, icon spacing, bar length, bar height, text width, text height, colors, fonts, glow sizes, swipe options, and keybind text style should call active button `UpdateStyle()` without invoking `PopulateGroupButtons()`. Changing display mode, rendered button sequence, pool key, icon secondary-cooldown capability from `separateTextPositions` plus aura tracking, or text header visibility should use the fallback path. Protected-combat style edits should not mutate button points, scripts, or active button lists.
- **Verification:** `luac -p Core/GroupFrame.lua`; focused harness coverage in U3.

### U3. Run focused local regression coverage

- **Goal:** Prove the shared style fast path and fallback boundaries without a live WoW client.
- **Files:** Local ignored harness under `tests/`, not committed because that directory is intentionally ignored.
- **Approach:** Follow the existing lightweight harness pattern from `tests/group-button-frame-pooling.lua`: stub the needed frame/widget methods, load `Core/GroupFrame.lua`, override constructors and addon methods with counters, and exercise `PopulateGroupButtons()` followed by `UpdateGroupStyle()` under compatible and incompatible changes.
- **Test scenarios:** A compatible style edit does not increase constructor counts, does not add inactive pooled buttons, does not call release cleanup counters, updates each button's style counter, refreshes `button.index` for visible entries after unusable rows, relays out points, refreshes frame bookkeeping, resizes the group, applies previews, updates cooldowns, propagates strata, preserves or safely refreshes Masque membership for enabled icon groups, and updates range registrations. Structural edits for display mode, pool key, rendered button sequence, icon secondary-cooldown capability, and text header visibility fall back to the populate path. Texture and trigger groups preserve hidden alpha on style updates. Protected combat defers without mutating active frames.
- **Verification:** Run the local ignored style-fast-path harness or the repo-local Lua equivalent available on the machine.

### U4. Run validation and inspect the diff

- **Goal:** Confirm the optimization is narrow, parse-clean, and ready for review.
- **Files:** No additional committed source files expected beyond U1-U2 and this plan.
- **Approach:** Run the focused harness, Lua syntax validation for touched Lua files, and whitespace diff checks. Inspect the final diff for accidental config UI behavior changes, `ConfigSettings/*` callback edits, or broad rebuild semantics changes.
- **Test scenarios:** `git diff --check` passes. `Core/GroupFrame.lua` parses. The local ignored style-fast-path harness passes. Existing `tests/group-button-frame-pooling.lua` still passes because `PopulateGroupButtons()` remains the structural rebuild path.
- **Verification:** `git diff --check`; `luac -p Core/GroupFrame.lua`; local ignored style-fast-path harness; `lua tests/group-button-frame-pooling.lua`.

---

## System-Wide Impact

The change reduces the runtime group-refresh cost of many existing config sliders, color pickers, dropdowns, and toggles that already route through `UpdateGroupStyle()`. Structural edits still rebuild through the combat-aware full refresh path, and config UI rebuilds still happen where callbacks explicitly call `RefreshConfigPanel()` for visible-control changes. The optimization should therefore improve common edit responsiveness without claiming to close the config-column rebuild half of finding #3.

---

## Risks & Dependencies

- **Risk: stale active button state after a style edit.** Mitigation: require identity compatibility, treat `UpdateStyle()` as invalidating runtime fields, and immediately run the existing cooldown/visibility refresh before returning.
- **Risk: unsafe in-place update for a structural edit.** Mitigation: require rendered button sequence and pool-key compatibility before the fast path; fall back through the combat-aware full refresh path on any mismatch.
- **Risk: duplicated layout behavior.** Mitigation: extract shared helper code from `PopulateGroupButtons()` instead of copying layout math and frame bookkeeping into `UpdateGroupStyle()`.
- **Risk: Masque drift after in-place size changes.** Mitigation: force fallback for Masque-enabled icon groups so the current remove/add path stays authoritative.
- **Risk: combat/restricted behavior remains runtime-sensitive.** Mitigation: keep local validation honest and require in-game combat plus restricted-content checks before shipping.

---

## Sources / Research

- Source finding: user-supplied optimization verdict, Finding #3 "Config edits trigger full rebuilds".
- At plan time, `Core/GroupFrame.lua:2247` owned `PopulateGroupButtons()` and performed pooled release/acquire, layout, previews, cooldown update, strata propagation, and range registration.
- At plan time, `Core/GroupFrame.lua:2959` routed `UpdateGroupStyle()` directly to `PopulateGroupButtons()`.
- `ButtonFrame/IconMode.lua:1380`, `ButtonFrame/BarMode.lua:1801`, and `ButtonFrame/TextMode.lua:881` provide the existing lane-specific style refresh methods the fast path should reuse.
- `ConfigSettings/BarModeTabs.lua`, `ConfigSettings/TextModeTabs.lua`, `ConfigSettings/GroupTabs.lua`, and `ConfigSettings/Helpers.lua` already route many style controls through `UpdateGroupStyle()`.
- `docs/plans/2026-06-10-003-perf-group-button-frame-pooling-plan.md` documents the existing pooling dependency that makes structural rebuilds bounded but still worth avoiding for style-only edits.
