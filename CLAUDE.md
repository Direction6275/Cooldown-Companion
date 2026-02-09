# CLAUDE.md — WoW Addon Development Reference

## Project: Cooldown Companion

Spell/item cooldown tracker with QoL enhancements: cooldown swipes, GCD indicators, proc glows, icon desaturation, usability checks, aura tracking, GCD swipe toggling.

**Environment:** Retail WoW 12.0.x (Midnight), Interface `120000`, Lua 5.1 (use `bit` library for bitwise ops).

---

## MANDATORY: API Verification

**Before writing ANY code, verify APIs exist in local reference files.** Do NOT guess signatures or assume APIs exist.

### Local References (Priority Order)

| Priority | Reference | Path | Use When |
|----------|-----------|------|----------|
| **1** | **Blizzard UI Source** | `C:\Users\nicho\Desktop\BlizzardInterfaceCode\Interface\AddOns\` | Frame structure, mixins, data providers, templates, XML. **First place to look** for any Blizzard system. |
| **2** | **Blizzard API Docs** | `C:\Users\nicho\Desktop\BlizzardInterfaceCode\Interface\AddOns\Blizzard_APIDocumentationGenerated` | `C_*` namespace API signatures, events, enums. |
| **3** | **WoW Addon Dev Guide** | `C:\Users\nicho\Desktop\WoWAddonDevGuide\` | Everything else: legacy globals, widget methods, Lua utilities, patterns, best practices, examples, 12.0 migration, secret values. See lookup table below. |

### WoW Addon Dev Guide — File Lookup

Read these files from `C:\Users\nicho\Desktop\WoWAddonDevGuide\` as needed:

| Need | Read |
|------|------|
| API functions by category, legacy globals, Lua extensions | `01_API_Reference.md` |
| Event handling, registration | `02_Event_System.md` |
| Frames, widgets, XML, templates, mixins, widget methods | `03_UI_Framework.md` |
| TOC files, load order, file organization | `04_Addon_Structure.md` |
| Coding patterns, performance, best practices, object pooling | `05_Patterns_And_Best_Practices.md` |
| Saved variables, databases, profiles | `06_Data_Persistence.md` |
| Working code examples from Blizzard UI | `07_Blizzard_UI_Examples.md` |
| Ace3, LibStub, community frameworks, slash commands | `08_Community_Addon_Patterns.md` |
| Library reference (LibStub, Ace3, LDB) | `09_Addon_Libraries_Guide.md` |
| Cross-client, performance, multi-addon | `10_Advanced_Techniques.md` |
| Player housing APIs (12.0+) | `11_Housing_System_Guide.md` |
| 12.0 API migration, breaking changes | `12_API_Migration_Guide.md` |
| **Secret values complete reference** | `12a_Secret_Safe_APIs.md` |

### Lookup Rules

- Blizzard frame structure, mixins, data flow, templates → **Blizzard UI Source** (read `.lua`/`.xml` directly)
- `C_Spell`, `C_Item`, etc. → **Blizzard API Docs** (`{SystemName}Documentation.lua`)
- Legacy globals (`UnitHealth`, `GetTime`, etc.) → Dev Guide `01_API_Reference.md`
- Widget/frame methods → Dev Guide `03_UI_Framework.md`
- Lua utilities (`tinsert`, `Mixin`, `Clamp`, `C_Timer`, etc.) → Dev Guide `01_API_Reference.md` or `05_Patterns_And_Best_Practices.md`
- Secret values behavior → Dev Guide `12a_Secret_Safe_APIs.md` first, then my verified values below
- **If not found → ASK ME** (I have the API Interface addon). Do NOT implement workarounds until I confirm.
- **If behavior is uncertain → ASK ME to test in-game.**

### Secondary Resources

- **Blizzard UI Source (GitHub):** `https://github.com/Gethe/wow-ui-source` (live branch)
- **API Docs (GitHub):** `https://raw.githubusercontent.com/Gethe/wow-ui-source/live/Interface/AddOns/Blizzard_APIDocumentationGenerated/{FileName}.lua`
- **Community wiki:** `https://warcraft.wiki.gg/wiki/API_{FunctionName}`
- **Ketho's resources:** `https://github.com/Ketho/BlizzardInterfaceResources` (mainline)
- **FrameAlphaTweaks:** `C:\Users\nicho\Desktop\FrameAlphaTweaks` (personal addon, reference on request)

---

## WoW 12.0 SECRET VALUES — VERIFIED IN-GAME RESULTS

For general secret values documentation, read `12a_Secret_Safe_APIs.md` from the Dev Guide. The values below are **tested in-game ground truth** that override any conflicting documentation.

### Verified Non-Secret Values

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

AceGUI pools widgets. Underlying WoW frames persist across recycling.

**Rules:**
1. **NEVER `HookScript` on `widget.editbox`** — hooks are permanent. Use `widget:SetCallback("OnTextChanged", ...)`.
2. **NEVER create child regions on `widget.editbox`** — they persist. Clean up on every acquisition.
3. **NEVER `SetScript` on `widget.editbox`** — breaks AceGUI's own handlers. Use `widget:SetCallback(...)`.
4. **Avoid `SetPoint` on `widget.editbox`** — persists across recycling.
5. **Always explicit Show/Hide for custom sub-elements** — don't assume default state.

**Principle:** Treat AceGUI widgets as opaque. Use widget API (`SetCallback`, `SetText`, `SetLabel`), not underlying frame.

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
6. **Consult WoW Addon Dev Guide** for patterns, best practices, migration guidance, and secret values reference before implementing.
7. **Ask me to test in-game** rather than guessing runtime behavior.
8. **Prefer simplest solution.** Check if data is already exposed as a plain readable value before building workarounds.
9. **When in plan mode**, ask thorough clarifying questions using the AskUSerQuestionTool before proceeding—do not make assumptions about intent, scope, or implementation details. It's better to over-ask than to guess wrong. It also helps the user clarify their vision. Minimum 3 clarifying questions per plan mode, including when bypass permissions are on.
10. **Read local Blizzard source before asking for in-game diagnostics.** Only ask for in-game commands when the question is about **runtime state** that source code cannot answer (e.g. secret values, timing, live aura data).
