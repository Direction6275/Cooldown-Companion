# Resources Preview Fidelity — Parallel Review Findings

**Review date:** 2026-07-26  
**Branch:** `resources-preview-fidelity`  
**Reviewed HEAD:** `f39fe2df7aa87a67161102d8298070f029c99bef`  
**Review base:** `12.1-ptr` at `80c5645b6ced3797bec9f599aebe0529f2f6cefb`  
**Remote base:** `origin/12.1-ptr` matched the local base  
**Review surface:** 11 files, 1,075 additions, 536 deletions  
**Workflow:** One report-only `parallel-review-recommendations` cohort with three independent reviewers

## Outcome

The branch is not ready to merge.

- **Fix now:** 7 findings
- **Clarify intent:** 1 confirmed P1 issue
- **Verify first:** none
- **Defer or decline:** none
- **Agent findings:** 3 reviewers with actionable findings, 0 with none

The P1 issue is not uncertain: the code performs forbidden Lua arithmetic on a potentially secret health value. The clarification is only about what the config preview should display when that value is inaccessible in restricted content.

## Review Context Supplied to All Reviewers

- Command-center resource, aura, health-effect, and attached-cast previews are intended to render on the config canvas without fabricating state on live display bars.
- The independent cast bar's unlock-to-position assist is an intentional exception because that bar has no canvas mirror.
- The Resources preview is intended to show configured ready/absent state using real game data rather than the character's transient state when the config opens.
- These product decisions did not establish implementation correctness or runtime validation.

## Findings

### 1. [P1] Health previews perform forbidden arithmetic on a potentially secret maximum

**Classification:** Clarify intent  
**Evidence:** Direct code evidence  
**Confidence:** High  
**Reported by:** Reviewer 2

**Locations**

- `CooldownCompanion/OtherBars/ResourceBarPreview.lua:328`
- `CooldownCompanion/OtherBars/ResourceBarHealth.lua:470`
- `CooldownCompanion/OtherBars/ResourceBarHealth.lua:493`
- `CooldownCompanion/OtherBars/ResourceBarHealth.lua:536`

**Problem**

The canvas evaluates `maxHealth * fraction`, including the resting case where `fraction == 1`. The incoming-heal, absorb, and heal-absorb stand-ins also multiply `UnitHealthMax("player")` by fixed shares.

The repository's secret-value contract explicitly says:

- `UnitHealthMax("player")` can return a secret value in restricted content.
- Lua arithmetic on secret values is forbidden.
- Health values must remain pass-through unless access has first been proven.

A config window opened before combat can remain active in restricted content. A repaint or health-preview action can therefore raise a secret-value Lua error.

**Required action**

Remove all arithmetic on an inaccessible health maximum. The full-health state can pass the real maximum through unchanged. Partial preview states must branch before arithmetic.

**Intent decision**

Choose the restricted-state presentation:

1. **Recommended:** render health-effect geometry with a normalized, non-secret canvas sample and suppress any derived current-health number that cannot be produced safely.
2. Make partial health-effect previews unavailable while the maximum is secret.

The implementation must not invent an API or use a guessed probe/workaround.

**Static validation**

Use a focused harness where:

- `UnitHealthMax` returns an arithmetic-failing sentinel.
- `issecretvalue` reports that sentinel as secret.
- Resting health and all four effect-preview paths complete without arithmetic or errors.

**Runtime validation**

Enter restricted combat with the config already open. Exercise resting health plus incoming-heal, absorb, heal-absorb, and low-health previews and confirm there are no BugSack errors.

---

### 2. [P2] Canvas health effects fall through to transient live prediction state

**Classification:** Fix now  
**Evidence:** Direct code evidence  
**Confidence:** High  
**Reported by:** Reviewers 1 and 3

**Locations**

- `CooldownCompanion/OtherBars/ResourceBarHealth.lua:446`
- `CooldownCompanion/OtherBars/ResourceBarPreview.lua:333`

**Problem**

The canvas passes `HEALTH_EFFECTS.preview` into `HealthBar.UpdateEffectBars`, but the function still evaluates branches such as:

- `config.showIncomingHeals or preview.incomingHeals`
- `config.showAbsorbs or preview.absorbs`
- `config.showHealAbsorbs or preview.healAbsorbs`
- the configured low-health alert path

When a preview key is not armed, an enabled configuration option falls through to live `UnitGetDetailedHealPrediction` or live health-percent state. As a result:

- the resting canvas can change while the player gains a shield, receives healing, or loses health;
- one explicit preview can be mixed with unrelated live effects;
- the canvas violates the deterministic ready/absent-state contract.

**Smallest clean fix**

Treat a supplied preview table as explicit canvas-only mode:

- show only preview keys that are `true`;
- hide and zero all other effect regions;
- do not call live prediction APIs in canvas mode;
- preserve the nil fourth-argument path for the real health bar.

Configuration should still supply styling, but it should not activate a canvas effect by itself.

**Static validation**

- Call `UpdateEffectBars(fakeBar, config, 1000, {})` with mocked nonzero live predictions and assert that no live prediction API is called and all effects remain hidden.
- Arm each preview key individually and assert that only its deterministic stand-in appears.
- Call the function without the fourth argument and confirm that the live bar still consumes real prediction state.

**Runtime validation**

Open Resources while low on health, shielded, and receiving incoming healing. Confirm that the resting canvas remains ready/absent until an explicit preview is started.

---

### 3. [P2] The cast facsimile does not mirror the live cast bar's effective appearance

**Classification:** Fix now  
**Evidence:** Direct code evidence  
**Confidence:** High  
**Reported by:** Reviewers 1 and 2

**Locations**

- `CooldownCompanion_Config/ConfigSettings/ResourceBarLayoutOrderPreview.lua:1678`
- `CooldownCompanion/OtherBars/CastBar.lua:1151`
- `CooldownCompanion/OtherBars/CastBar.lua:1171`
- `CooldownCompanion/OtherBars/CastBar.lua:1314`

**Problem**

`ConfigureCastPreview` always applies custom appearance settings, even when `settings.stylingEnabled` is false. The live cast bar instead restores Blizzard visuals when styling is disabled.

The facsimile also diverges in several configured states:

- It can show the custom icon while the live styling-disabled bar hides it.
- It places the icon within the preview slot with a fixed gap.
- It does not mirror the live inline-icon geometry.
- It ignores `iconOffsetX` and `iconOffsetY` for offset icons.
- It omits configured name and cast-time font colors.
- It can advertise custom texture, fill, background, and border settings that are dormant on the live bar.

**Smallest clean fix**

Mirror the existing effective appearance contract:

- add the styling-enabled versus Blizzard-default split;
- reproduce inline-left, inline-right, offset-left, and offset-right icon geometry;
- honor icon offsets;
- apply configured name and time font colors;
- avoid a broad cast-renderer refactor unless a very small shared effective-appearance helper clearly reduces duplication.

**Static validation**

Add fixtures for:

- styling disabled with conflicting custom settings;
- inline icon on both sides;
- offset icon on both sides with X/Y offsets;
- configured name and time text colors;
- pixel, Blizzard, and no-border modes.

**Runtime validation**

Compare the attached live cast bar and canvas side by side for each configuration, especially while toggling Styling off.

---

### 4. [P2] “Preview Cast Bar” can be offered when the current canvas contains no cast slot

**Classification:** Fix now  
**Evidence:** Direct code evidence  
**Confidence:** High  
**Reported by:** Reviewer 1

**Locations**

- `CooldownCompanion_Config/Config/PreviewCommandCenter.lua:1146`
- `CooldownCompanion_Config/ConfigSettings/ResourceBarLayoutOrderPreview.lua:2908`
- `CooldownCompanion_Config/ConfigSettings/ResourceBarLayoutOrderPreview.lua:2918`

**Problem**

On the Resources home, an independent resource stack sets `includeCastSlots = false`, even when the cast bar itself is attached. The command center checks only whether the cast bar is attached.

That produces this state:

- the chooser offers “Preview Cast Bar”;
- the current Resources canvas intentionally omits the cast slot;
- starting the preview repaints the same cast-free canvas and visibly does nothing.

**Smallest clean fix**

Derive command-center availability from the same current-surface predicate used by the renderer. Do not merely test whether the cast bar is generally attached.

**Static validation**

Cover this matrix:

- attached Resources / attached Cast;
- attached Resources / independent Cast;
- independent Resources / attached Cast;
- independent Resources / independent Cast;
- Resources home versus Cast Bar & Unit Frames home.

Every offered cast control must correspond to a rendered cast slot.

**Runtime validation**

Exercise each matrix state and confirm that every offered cast preview animates something visible.

---

### 5. [P2] Canvas cast-preview state survives after its destination disappears

**Classification:** Fix now  
**Evidence:** Direct code evidence  
**Confidence:** High  
**Reported by:** Reviewer 3

**Location**

- `CooldownCompanion_Config/Config/PreviewCommandCenter.lua:1146`

**Problem**

When cast becomes disabled or independent, it drops out of the applicable controls, but `UpdateBar` only filters or hides controls. It does not clear `isCanvasPreviewActive`.

Reproduction sequence:

1. Start the attached cast preview.
2. switch the cast bar to Independent, or disable it;
3. restore attached/enabled mode.

The old looping preview silently resumes because its state was never stopped.

**Smallest clean fix**

When the current surface no longer has an applicable cast destination, explicitly stop the canvas cast preview before updating the command center. Keep this separate from the intentional independent unlock-to-position assist.

**Static validation**

- Start canvas cast preview.
- Set `independentAnchorEnabled = true`.
- Refresh the Resources command center.
- Assert `IsCastBarPreviewActive() == false`.
- Restore attached mode and assert it remains stopped.
- Repeat for disable/re-enable.

**Runtime validation**

Exercise both transitions in the config UI and confirm that no preview silently resumes. Separately confirm that the independent unlock stand-in still works.

---

### 6. [P2] Valid thin and fractional bar thicknesses are altered by the preview

**Classification:** Fix now  
**Evidence:** Direct code evidence  
**Confidence:** High  
**Reported by:** Reviewer 1

**Locations**

- `CooldownCompanion_Config/ConfigSettings/ResourceBarLayoutOrderPreview.lua:1887`
- `CooldownCompanion_Config/ConfigSettings/CastBarPanels.lua:352`
- `CooldownCompanion_Config/ConfigSettings/ResourceBarPanelsResource.lua:1267`
- `CooldownCompanion_Config/ConfigSettings/ResourceBarPanelsResource.lua:1327`
- `CooldownCompanion_Config/ConfigSettings/ResourceBarPanelsCustomBars.lua:1021`

**Problem**

`GetSlotExtent` floors configured thickness and clamps it to a minimum of 8 pixels:

```lua
return math_max(8, math_floor(thickness))
```

The actual settings accept 4–40 pixels in 0.1-pixel increments, and the live layout uses the saved value directly.

Consequences:

- 4–7.9-pixel bars preview as 8 pixels;
- all fractional thicknesses lose fidelity;
- lane totals, drag insertion points, and drop-gap geometry are computed from the wrong extents.

**Smallest clean fix**

Return the positive configured numeric thickness without flooring it or imposing a stricter minimum than the setting contract.

**Static validation**

Assert correct slot extents, lane totals, drag hit-testing, and drop-gap sizing for at least:

- `4`
- `7.5`
- `12.3`

**Runtime validation**

Compare thin and fractional live bars with the preview, then reorder them and confirm the drag geometry remains aligned.

---

### 7. [P2] “Show Only While Aura Active” stack bars retain an inset for a border that does not exist

**Classification:** Fix now  
**Evidence:** Direct code evidence  
**Confidence:** High  
**Reported by:** Reviewer 2

**Locations**

- `CooldownCompanion/OtherBars/ResourceBarAuraHost.lua:341`
- `CooldownCompanion/OtherBars/ResourceBarAuraHost.lua:363`
- `CooldownCompanion/OtherBars/ResourceBarCustomBars.lua:847`
- `CooldownCompanion/Core/AuraDisplay.lua:1185`

**Problem**

`GetCustomBarHolderInset` calls `WantsAbsentStackBlocks(barInfo)` without `includeShell`. For `hideWhenInactive` bars, that predicate returns nil, so the holder keeps `borderInset`.

For widget-stack shells:

- the Cooldown Companion frame is transparent;
- the shell background slab is suppressed;
- the whole-bar border is suppressed;
- each stack block is its own widget and carries its own border.

The retained holder inset therefore leaves a transparent dead margin and makes active blocks stop short of the real bar edges.

**Smallest clean fix**

Include shell bars when resolving holder geometry, equivalent to:

```lua
WantsAbsentStackBlocks(barInfo, { includeShell = true })
```

When that returns a stack maximum, the holder inset should be zero.

**Static validation**

Create a shell aura bar with a cached stack maximum greater than one and assert that the holder uses zero inset.

**Runtime validation**

Activate a `Show Only While Aura Active` stacks bar with a visible pixel-border size. Confirm that its blocks reach the full bar footprint with no transparent margin.

---

### 8. [P2] Live resource teardown clears state that now belongs to the config canvas

**Classification:** Fix now  
**Evidence:** Direct code evidence  
**Confidence:** High  
**Reported by:** Reviewer 2

**Locations**

- `CooldownCompanion/OtherBars/ResourceBar.lua:1793`
- `CooldownCompanion/OtherBars/ResourceBar.lua:2298`
- `CooldownCompanion/OtherBars/ResourceBar.lua:2329`
- `CooldownCompanion/OtherBars/ResourceBar.lua:2354`
- `CooldownCompanion_Config/ConfigSettings/ResourceBarLayoutOrderPreview.lua:837`

**Problem**

`RevertResourceBars` wipes:

- `HEALTH_EFFECTS.preview`;
- `activeCustomAuraBarActivePreviews`;
- `activeCustomAuraBarPandemicPreviews`.

Those maps are now described and used as config-canvas state. Runtime teardown can occur for transient live conditions such as:

- no currently available anchor group;
- a non-icon-compatible anchor;
- an anchor frame that is temporarily hidden.

The canvas can still render from saved panel data in those conditions. Wiping the maps from live teardown can therefore:

- silently stop the command-center preview;
- leave the canvas and command-center controls inconsistent until another repaint;
- make canvas state depend on unrelated live-frame availability.

**Smallest clean fix**

Remove config-canvas preview ownership from `RevertResourceBars`.

Keep clearing in:

- `ClearAllConfigPreviews`;
- explicit preview stop actions;
- config-object disable/removal paths where the target no longer exists.

**Static validation**

- Arm health and custom-aura previews.
- Invoke runtime resource teardown.
- Assert the corresponding `Is...PreviewActive` methods remain true.
- Invoke `ClearAllConfigPreviews`.
- Assert all preview state is then cleared.

**Runtime validation**

Run a canvas preview while making the live anchor hide and return through load conditions. Confirm that the canvas preview remains active and synchronized.

## Reviewer Finding Index

### Reviewer 1

1. Canvas health effects leak transient live prediction state.
2. Cast facsimile does not mirror effective live styling, icon geometry, offsets, or text colors.
3. Cast preview can be offered on a Resources canvas that intentionally excludes cast.
4. Preview thickness flooring and the 8-pixel clamp misrepresent valid settings.

### Reviewer 2

1. Health preview arithmetic is unsafe for a potentially secret `UnitHealthMax`.
2. Shell stack bars retain a border inset despite having no whole-bar border.
3. Live resource teardown incorrectly clears config-canvas preview state.
4. Cast facsimile paints dormant custom styling when Styling is disabled.

### Reviewer 3

1. Canvas health effects fall through to live health and prediction state.
2. Canvas cast-preview state is not cleared when its destination becomes inapplicable.

## Verification Notes

- `git diff --check 80c5645b6ced3797bec9f599aebe0529f2f6cefb` passed.
- All 11 changed Lua files passed Lua 5.1 `luac -p`.
- `C_Spell.GetSpellCharges().maxCharges` was verified as `NeverSecret`; no charge-read finding was retained.
- No focused tests for these preview paths were included in the reviewed diff.
- No reviewer performed in-game, combat, restricted-content, or integration validation.
- The review was report-only; reviewers made no file changes.

## Recommended Next Sequence

1. Decide how partial health-effect previews should behave when the health maximum is secret.
2. Implement the seven `fix now` findings and the chosen secret-safe health behavior.
3. Add focused fixtures for:
   - secret-safe and deterministic health previews;
   - cast effective appearance and state transitions;
   - thin/fractional layout geometry;
   - shell stack holder inset;
   - runtime teardown versus canvas-state ownership.
4. Re-run Lua 5.1 parsing, focused fixtures, and `git diff --check`.
5. Complete the runtime checks listed under each finding before merging.

