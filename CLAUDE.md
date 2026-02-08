# CLAUDE.md — WoW Addon Development Reference

## Project: Cooldown Companion

Spell/item cooldown tracker with QoL enhancements: cooldown swipes, GCD indicators, proc glows, icon desaturation, usability checks, aura tracking, GCD swipe toggling.

**Environment:** Retail WoW 12.0.x (Midnight), Interface `120000`, Lua 5.1 (use `bit` library for bitwise ops).

---

## MANDATORY: API Verification

**Before writing ANY code, verify APIs exist in local reference files.** Do NOT guess signatures or assume APIs exist.

### Local API References

| Reference | Path | Contents |
|-----------|------|----------|
| **Blizzard API Docs** | `C:\Users\nicho\Desktop\BlizzardInterfaceCode\Interface\AddOns\Blizzard_APIDocumentationGenerated` | All C_* namespace APIs, events, enums, signatures |
| **Legacy Global Functions** | `C:\Users\nicho\Desktop\global and widget api\WoW_Legacy_Global_Functions_Reference.md` | Unit functions, action bar APIs, combat, secure hooking |
| **Widget API Reference** | `C:\Users\nicho\Desktop\global and widget api\WoW_Widget_API_Reference.md` | Frame/widget methods, script handlers, positioning |
| **Lua Utilities Reference** | `C:\Users\nicho\Desktop\global and widget api\WoW_Lua_Utilities_Reference.md` | Table utils, colors, slash commands, SavedVariables |

**Lookup rules:**
- `C_Spell`, `C_Item`, etc. → Blizzard API Docs (`{SystemName}Documentation.lua`)
- `UnitHealth`, `GetActionCooldown`, etc. → Legacy Global Functions
- Frame methods → Widget API Reference
- `tinsert`, `Mixin`, etc. → Lua Utilities Reference
- **If not found → ASK ME** (I have the API Interface addon). Do NOT implement workarounds until I confirm it doesn't exist.
- **If behavior is uncertain → ASK ME to test in-game.**

### Secondary Resources

- **Blizzard UI Source (GitHub):** `https://github.com/Gethe/wow-ui-source` (live branch)
- **API Docs (GitHub):** `https://raw.githubusercontent.com/Gethe/wow-ui-source/live/Interface/AddOns/Blizzard_APIDocumentationGenerated/{FileName}.lua`
- **Community wiki:** `https://warcraft.wiki.gg/wiki/API_{FunctionName}` — ask me if retrieval fails
- **Ketho's resources:** `https://github.com/Ketho/BlizzardInterfaceResources` (mainline)
- **Amadeus Dev Guide:** `https://github.com/Amadeus-/WoWAddonDevGuide`
- **Local Blizzard source:** `C:\Users\nicho\Desktop\BlizzardInterfaceCode\Interface\AddOns\`
- **FrameAlphaTweaks:** `C:\Users\nicho\Desktop\FrameAlphaTweaks` (personal addon, reference on request)

---

## WoW 12.0 SECRET VALUES SYSTEM (CRITICAL)

Secret values lock combat-related API returns — addons can **display** but not **read/compare/compute** with them during combat. Enforced during all combat. Normal outside combat.

### Forbidden operations on secret values (combat)
Compare, math, concatenate, use as table keys, check length, boolean test, tostring()

### Allowed operations on secret values
Store in variables/tables (as values), pass to approved widget APIs, pass to Lua functions

### Helper functions
`issecretvalue(v)`, `canaccesssecrets()`, `canaccessvalue(v)`, `issecrettable(t)`, `canaccesstable(t)`, `GetRestrictedActionStatus("type")`

### Secret Aspects (Widgets)
Setting a secret on a widget applies a secret aspect (e.g. `SetText(secret)` → `GetText()` returns secret). Clear with `SetToDefaults()`. Propagates to children via anchoring.

### Verified Non-Secret Values (Tested In-Game)

| Value | Source |
|-------|--------|
| `GetCooldownTimes()` on Cooldown widget | Returns start/duration in ms. Always readable. |
| `cooldownInfo.isOnGCD` | `NeverSecret`. Always readable. |
| `auraInstanceID` in UNIT_AURA payload | Always readable during combat. |
| `removedAuraInstanceIDs` in UNIT_AURA payload | `NeverSecretContents`. Always readable. |
| `GetAuraDuration(unit, instanceID)` | Returns LuaDurationObject. Works during combat. |
| `viewerChild.auraInstanceID` | Blizzard untainted code. Readable during combat. |
| `viewerChild.auraDataUnit` | "player" for buffs, "target" for debuffs. Readable. |
| `viewerChild.cooldownInfo.spellID/overrideSpellID/overrideTooltipSpellID` | Readable during combat. |
| `viewerChild.Cooldown:GetCooldownTimes()` | Non-secret start/duration in ms. |
| Config-time addon-stored values (e.g. `buttonData.auraSpellID`) | Not secret — addon data, not API returns. |

### Verified Secret Values

| Value | Source |
|-------|--------|
| `spellId` in UNIT_AURA payload | Prints `???` during combat. |
| `sourceUnit` in UNIT_AURA payload | Secret even for player auras. |
| `isHelpful` in UNIT_AURA payload | Secret during combat. |
| `auraData.duration/expirationTime` from `GetPlayerAuraBySpellID` | Secret; arithmetic errors. |

**Key insight:** Prefer querying **widget state** over **API return values**. Widgets expose non-secret internal state even when original values were secret.

### API Documentation Flags
`SecretReturns`, `SecretWhenUnitIdentityRestricted`, `ConditionalSecret`, `AcceptsSecretFromTaintedCode`, `NeverSecret`

### Whitelisted (Non-Secret in Combat)
GCD (61304), Skyriding, combat res, Maelstrom Weapon, Devourer DH resources, secondary resources (Holy Power, Combo Points, Runes, etc.)

### 12.0 Tools for Secrets
```lua
C_CurveUtil.CreateCurve() / CreateColorCurve()
CurveConstants.ScaleTo100, .Reverse, .ReverseTo100
C_DurationUtil.CreateDuration()
statusBar:SetTimerDuration(duration)
FontString:SetVertexColorFromBoolean(...)
Texture:SetVertexColorFromBoolean(...)
UnitHealthPercent/Missing(unit), UnitPowerPercent/Missing(unit)
SecondsFormatter -- formats secret durations
```

### Impact on Cooldown Companion

| Feature | Status | Approach |
|---------|--------|----------|
| Cooldown display | Works | `SetCooldown`/`SetCooldownFromDurationObject` accept secrets |
| Desaturation | Solved | `GetCooldownTimes()` on widget returns non-secret |
| Proc glow | Limited | Events + state tracking (can't compare `cooldown == 0`) |
| Resource checks | Partial | Secondary resources whitelisted; primary may be secret |
| Usability checks | Limited | Track via `SPELL_UPDATE_USABLE` events |
| Aura tracking | Solved | Read from Blizzard cooldown viewer frames (see below) |

### Development Strategy
1. Query widget state instead of API values
2. Use widget methods that accept secrets (`SetValue`, `SetCooldown`, `SetCooldownFromDurationObject`)
3. Prefer event-driven logic over polling
4. Avoid comparisons on secret values — use curves or widget state
5. Ask me to test if unsure about combat behavior

### References
- https://warcraft.wiki.gg/wiki/Patch_12.0.0/API_changes
- https://warcraft.wiki.gg/wiki/Patch_12.0.0/Planned_API_changes

---

## COOLDOWN VIEWER AURA TRACKING

Blizzard's cooldown viewer system provides combat-safe aura data via plain frame properties.

### How it works
- Viewer children have `cooldownInfo` table with `spellID`, `overrideSpellID`, `overrideTooltipSpellID`
- Blizzard's untainted code calls `C_UnitAuras.GetUnitAuras()` internally, stores results as `child.auraInstanceID` and `child.auraDataUnit`
- These are plain frame fields, readable by addon code during combat

### Viewer types — critical differences
- **Essential/Utility CooldownViewer**: Track spell cooldowns. Do NOT populate `auraInstanceID`/`auraDataUnit`. Cooldown widget shows spell cooldown.
- **BuffIcon/BuffBar CooldownViewer**: Track aura durations. DO populate `auraInstanceID`/`auraDataUnit`. Cooldown widget shows aura duration.
- `cooldownInfo.selfAura`/`hasAura` flags are NOT reliable — some spells have both `false` but are trackable.

### Transforming spells
- `overrideSpellID` changes dynamically (e.g. Solar↔Lunar Eclipse)
- `COOLDOWN_VIEWER_SPELL_OVERRIDE_UPDATED` fires with `baseSpellID`, `overrideSpellID`
- Must accumulate override mappings in viewer map

### Ability spell ID != Buff spell ID (critical gotcha)
- Some spells have different IDs for ability vs buff (e.g. Solar Eclipse ability=1233346, buff=48517)
- BuffIcon/BuffBar viewers track the BUFF spell ID, not the ability ID
- Manual fallback: "Spell ID Override" config field — user enters buff spell ID(s), supports comma-separated
- Override is addon config data, not affected by secrets

### Hardcoded ability→buff overrides (`ABILITY_BUFF_OVERRIDES` in Core.lua)
- `[abilitySpellID] = "comma-separated buff spell IDs"` for known unlinked pairs
- Pipeline auto-picks up new entries (map building, config, auto-enable, icon resolution)
- Current: Solar Eclipse (1233346), Lunar Eclipse (1233272) → buffs 48517, 48518

### Dual viewer types — architecture
- CDM tracks same spell in TWO viewer types: Essential/Utility (cooldown) + BuffIcon/BuffBar (aura)
- **Aura tracking → BuffIcon/BuffBar children** (only these have `auraInstanceID`/`auraDataUnit`)
- **Icon/name resolution → Essential/Utility children** (dynamic `GetSpellTexture()` for transforms)
- `FindCooldownViewerChild()` bridges this: finds Essential/Utility child when given a BuffIcon/BuffBar child
- When building override map: prefer BuffIcon/BuffBar children, but don't overwrite per-buff-ID mappings

### CDM layout changes
- `CooldownViewerSettings.OnDataChanged` fires on rearrange
- Frames are pooled — rebuild viewer map with `C_Timer.After(0.2, rebuild)`

### Usage pattern
```lua
-- Build map on login, spec change, CDM layout change
-- Map spellID, overrideSpellID, AND overrideTooltipSpellID from all 4 viewers
-- Read each tick: try override/aura IDs first, then ability ID
local viewerFrame = viewerMap[auraSpellID] or viewerMap[abilitySpellID]
if viewerFrame and viewerFrame.auraInstanceID then
    local durationObj = C_UnitAuras.GetAuraDuration(viewerFrame.auraDataUnit, viewerFrame.auraInstanceID)
    cooldown:SetCooldownFromDurationObject(durationObj)
elseif viewerFrame and viewerFrame.Cooldown then
    local startMs, durMs = viewerFrame.Cooldown:GetCooldownTimes()
    if startMs and durMs and durMs > 0 then
        cooldown:SetCooldown(startMs / 1000, durMs / 1000)
    end
end
```

### Limitations
- Player buffs + target debuffs only (not focus/custom units)
- Spell must be in Blizzard Cooldown Manager; viewer must be visible (BetterCooldownManager keeps them visible)
- Spell list curated per class/spec by Blizzard
- Items cannot be tracked via CDM

---

## COMMON PATTERNS & GOTCHAS

### AceGUI EditBox Widget Recycling (CRITICAL — recurring bug)

AceGUI pools widgets. Underlying WoW frames persist across recycling. This has caused multiple bugs.

**Rules:**
1. **NEVER `HookScript` on `widget.editbox`** — hooks are permanent. Use `widget:SetCallback("OnTextChanged", ...)` instead.
2. **NEVER create child regions on `widget.editbox`** — they persist. If you must, clean up on every acquisition: `if box.editbox.Instructions then box.editbox.Instructions:Hide() end`
3. **NEVER `SetScript` on `widget.editbox`** — breaks AceGUI's own handlers. Use `widget:SetCallback(...)`.
4. **Avoid `SetPoint` on `widget.editbox`** — persists across recycling.
5. **Always explicit Show/Hide for custom sub-elements** — don't assume default state.

**Principle:** Treat AceGUI widgets as opaque. Use widget API (`SetCallback`, `SetText`, `SetLabel`), not underlying frame.

### Key Patterns
```lua
-- Namespace: always use local or addon namespace, never bare globals
local ADDON_NAME, ns = ...

-- Event throttling
frame:SetScript("OnUpdate", function(self, elapsed)
    timeSinceLastUpdate = timeSinceLastUpdate + elapsed
    if timeSinceLastUpdate < 0.1 then return end
    timeSinceLastUpdate = 0
    -- work
end)

-- Secure frame check
if InCombatLockdown() then return end
```

### Debugging
```
/reload  /console scriptErrors 1  /fstack  /eventtrace
/dump C_Spell.GetSpellCooldown(61304)
/tinspect SomeFrame
```

---

## RULES

1. **NO "Co-authored-by: Claude" in commits.**
2. **Performance is critical.** Ask before trading features for CPU cost.
3. **Verify API signatures** in local references before using.
4. **Use modern namespaced APIs** (C_Spell, C_Item, C_Container, C_UnitAuras).
5. **Search Blizzard UI source** when in doubt about implementation patterns.
6. **Ask me to test in-game** rather than guessing runtime behavior.
7. **Prefer simplest solution.** Check if data is already exposed as a plain readable value (table field, widget property, frame attribute) before building workarounds.
8. **Read local Blizzard source before asking for in-game diagnostics.** When investigating Blizzard frame structure, mixins, or data flow, ALWAYS read the source files under `C:\Users\nicho\Desktop\BlizzardInterfaceCode\Interface\AddOns\` first. Do NOT ask the user to run `/dump` or `/run` commands to reverse-engineer frame hierarchies that are fully documented in source. Only ask for in-game commands when the question is about **runtime state** that source code cannot answer (e.g. secret values, timing, live aura data).