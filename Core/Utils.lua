--[[
    CooldownCompanion - Utils
    Shared utilities, constants, and helpers used across multiple files
]]

local ADDON_NAME, ST = ...

-- Localize frequently-used globals for faster access
local InCombatLockdown = InCombatLockdown
local ipairs = ipairs
local string_format = string.format

--------------------------------------------------------------------------------
-- Constants
--------------------------------------------------------------------------------

ST.DEFAULT_OVERHANG_PCT = 32
ST.DEFAULT_GLOW_COLOR = {1, 1, 1, 1}
ST.DEFAULT_BG_COLOR = {0.2, 0.2, 0.2, 0.8}
ST.PARTICLE_COUNT = 12
ST.NUM_GLOW_STYLES = 3

-- Shared edge anchor spec: {point1, relPoint1, point2, relPoint2, x1sign, y1sign, x2sign, y2sign}
-- Signs: 0 = zero offset, 1 = +size, -1 = -size
ST.EDGE_ANCHOR_SPEC = {
    {"TOPLEFT", "TOPLEFT",     "BOTTOMRIGHT", "TOPRIGHT",     0, 0,  0, -1}, -- Top    (full width)
    {"TOPLEFT", "BOTTOMLEFT",  "BOTTOMRIGHT", "BOTTOMRIGHT",  0, 1,  0,  0}, -- Bottom (full width)
    {"TOPLEFT", "TOPLEFT",     "BOTTOMRIGHT", "BOTTOMLEFT",   0, -1,  1,  1}, -- Left   (inset to avoid corner overlap)
    {"TOPLEFT", "TOPRIGHT",    "BOTTOMRIGHT", "BOTTOMRIGHT", -1, -1,  0,  1}, -- Right  (inset to avoid corner overlap)
}

--------------------------------------------------------------------------------
-- Click-Through Helpers
--------------------------------------------------------------------------------

-- Helper function to make a frame click-through
-- disableClicks: prevent LMB/RMB clicks (allows camera movement pass-through)
-- disableMotion: prevent OnEnter/OnLeave hover events (disables tooltips)
function ST.SetFrameClickThrough(frame, disableClicks, disableMotion)
    if not frame then return end
    local inCombat = InCombatLockdown()

    if disableClicks then
        -- Disable mouse click interaction for camera pass-through
        -- SetMouseClickEnabled and SetPropagateMouseClicks are protected in combat
        if not inCombat then
            if frame.SetMouseClickEnabled then
                frame:SetMouseClickEnabled(false)
            end
            if frame.SetPropagateMouseClicks then
                frame:SetPropagateMouseClicks(true)
            end
            if frame.RegisterForClicks then
                frame:RegisterForClicks()
            end
            if frame.RegisterForDrag then
                frame:RegisterForDrag()
            end
        end
        frame:SetScript("OnMouseDown", nil)
        frame:SetScript("OnMouseUp", nil)
    else
        if not inCombat then
            if frame.SetMouseClickEnabled then
                frame:SetMouseClickEnabled(true)
            end
            if frame.SetPropagateMouseClicks then
                frame:SetPropagateMouseClicks(false)
            end
        end
    end

    if disableMotion then
        -- Disable mouse motion (hover) events
        if not inCombat then
            if frame.SetMouseMotionEnabled then
                frame:SetMouseMotionEnabled(false)
            end
            if frame.SetPropagateMouseMotion then
                frame:SetPropagateMouseMotion(true)
            end
        end
        frame:SetScript("OnEnter", nil)
        frame:SetScript("OnLeave", nil)
    else
        if not inCombat then
            if frame.SetMouseMotionEnabled then
                frame:SetMouseMotionEnabled(true)
            end
            if frame.SetPropagateMouseMotion then
                frame:SetPropagateMouseMotion(false)
            end
        end
    end

    -- EnableMouse must be true if we want motion events (tooltips)
    -- Only fully disable if both clicks and motion are disabled
    if not inCombat then
        if disableClicks and disableMotion then
            frame:EnableMouse(false)
            if frame.SetHitRectInsets then
                frame:SetHitRectInsets(10000, 10000, 10000, 10000)
            end
            frame:EnableKeyboard(false)
        elseif not disableClicks and not disableMotion then
            frame:EnableMouse(true)
            if frame.SetHitRectInsets then
                frame:SetHitRectInsets(0, 0, 0, 0)
            end
        else
            frame:EnableMouse(true)
            if frame.SetHitRectInsets then
                frame:SetHitRectInsets(0, 0, 0, 0)
            end
        end
    end
end

-- Recursively apply click-through to frame and all children
function ST.SetFrameClickThroughRecursive(frame, disableClicks, disableMotion)
    ST.SetFrameClickThrough(frame, disableClicks, disableMotion)
    -- Apply to all child frames
    for _, child in ipairs({frame:GetChildren()}) do
        ST.SetFrameClickThroughRecursive(child, disableClicks, disableMotion)
    end
end

--------------------------------------------------------------------------------
-- Spell Resolution Helpers
--------------------------------------------------------------------------------

-- Resolve a spell ID to its base form via C_Spell.GetBaseSpell.
-- Used at entry time so buttons always store the root of a transform chain,
-- enabling C_Spell.GetOverrideSpell to freely resolve to any current variant.
function ST.ResolveToBaseSpell(spellID)
    if not spellID then return spellID end
    local baseID = C_Spell.GetBaseSpell(spellID)
    return (baseID and baseID ~= 0) and baseID or spellID
end

--------------------------------------------------------------------------------
-- Spellbook Helpers
--------------------------------------------------------------------------------

-- Returns true if spellId (or its base spell) is an active (non-passive) entry
-- in the player's spellbook. Used by IsPassiveOrProc in Pickers to distinguish
-- real castable spells from aura/proc entries.
function ST.IsActiveSpellBookSpell(spellId)
    if not spellId then return false end

    local function IsActiveFromSpellIdentifier(spellIdentifier)
        local slotIdx, spellBank = C_SpellBook.FindSpellBookSlotForSpell(
            spellIdentifier,
            false, -- includeHidden
            true,  -- includeFlyouts
            false, -- includeFutureSpells
            true   -- includeOffSpec
        )
        if not slotIdx then
            return false
        end
        return not C_SpellBook.IsSpellBookItemPassive(slotIdx, spellBank)
    end

    if IsActiveFromSpellIdentifier(spellId) then
        return true
    end

    local baseSpellID = C_Spell.GetBaseSpell(spellId)
    if baseSpellID and baseSpellID ~= spellId then
        if IsActiveFromSpellIdentifier(baseSpellID) then
            return true
        end
    end

    return false
end

--------------------------------------------------------------------------------
-- CDM (Cooldown Manager) Helpers
--------------------------------------------------------------------------------

-- Returns true if spellId (or its override/tooltip override) is tracked by
-- Blizzard's Cooldown Manager in the Essential or Utility categories.
-- Spells with externally-applied cooldowns (class aura / talent passive) are
-- tracked here even when GetSpellBaseCooldown returns 0; true GCD-only spells
-- are not.
function ST.IsSpellInCDMCooldown(spellId)
    if not spellId then return false end
    for _, cat in ipairs({Enum.CooldownViewerCategory.Essential, Enum.CooldownViewerCategory.Utility}) do
        local ids = C_CooldownViewer.GetCooldownViewerCategorySet(cat, true)
        if ids then
            for _, cdID in ipairs(ids) do
                local info = C_CooldownViewer.GetCooldownViewerCooldownInfo(cdID)
                if info then
                    if info.spellID == spellId or info.overrideSpellID == spellId
                       or info.overrideTooltipSpellID == spellId then
                        return true
                    end
                end
            end
        end
    end
    return false
end

--------------------------------------------------------------------------------
-- Tooltip Cooldown Detection
--------------------------------------------------------------------------------

-- Returns true if the spell's tooltip indicates it has a cooldown.
-- Structurally detects the presence of rightText on the cast time line
-- (last type=0 line before the first type=34 description line) without
-- parsing localized text. Covers ALL spells including those with
-- externally-applied cooldowns that GetSpellBaseCooldown misses.
function ST.HasTooltipCooldown(spellId)
    if not spellId then return false end
    local data = C_TooltipInfo.GetSpellByID(spellId)
    if not data or not data.lines then return false end

    local lastNoneLine
    for _, line in ipairs(data.lines) do
        if line.type == Enum.TooltipDataLineType.SpellDescription then break end
        if line.type == Enum.TooltipDataLineType.None then
            lastNoneLine = line
        end
    end

    return lastNoneLine ~= nil and lastNoneLine.rightText ~= nil and lastNoneLine.rightText ~= ""
end

-- Returns true if the spell tooltip contains a UsageRequirement line
-- (e.g. "Requires Bear Form"). Uses structured tooltip data — no localized
-- text parsing. Complements HasTooltipCooldown for config-time gating.
function ST.HasUsageRequirement(spellId)
    if not spellId then return false end
    local data = C_TooltipInfo.GetSpellByID(spellId)
    if not data or not data.lines then return false end
    for _, line in ipairs(data.lines) do
        if line.type == Enum.TooltipDataLineType.UsageRequirement then
            return true
        end
    end
    return false
end

--------------------------------------------------------------------------------
-- Border Helpers
--------------------------------------------------------------------------------

-- Create 4 pixel-perfect border textures using PixelUtil (replaces backdrop edgeFile)
function ST.CreatePixelBorders(frame, r, g, b, a)
    r, g, b, a = r or 0, g or 0, b or 0, a or 1

    local top = frame:CreateTexture(nil, "BORDER")
    top:SetColorTexture(r, g, b, a)
    PixelUtil.SetPoint(top, "TOPLEFT", frame, "TOPLEFT", 0, 0)
    PixelUtil.SetPoint(top, "TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    PixelUtil.SetHeight(top, 1, 1)

    local bottom = frame:CreateTexture(nil, "BORDER")
    bottom:SetColorTexture(r, g, b, a)
    PixelUtil.SetPoint(bottom, "BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
    PixelUtil.SetPoint(bottom, "BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    PixelUtil.SetHeight(bottom, 1, 1)

    local left = frame:CreateTexture(nil, "BORDER")
    left:SetColorTexture(r, g, b, a)
    PixelUtil.SetPoint(left, "TOPLEFT", frame, "TOPLEFT", 0, 0)
    PixelUtil.SetPoint(left, "BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
    PixelUtil.SetWidth(left, 1, 1)

    local right = frame:CreateTexture(nil, "BORDER")
    right:SetColorTexture(r, g, b, a)
    PixelUtil.SetPoint(right, "TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    PixelUtil.SetPoint(right, "BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    PixelUtil.SetWidth(right, 1, 1)

    frame.borderTextures = { top, bottom, left, right }
end

--------------------------------------------------------------------------------
-- Color Utilities
--------------------------------------------------------------------------------

-- Format a color table {r, g, b, a} into a cache key string.
-- Replaces repeated string.format("%.2f%.2f%.2f%.2f", c[1], c[2], c[3], c[4]) calls.
function ST.FormatColorKey(c)
    return string_format("%.2f%.2f%.2f%.2f", c[1], c[2], c[3], c[4] or 1)
end

--------------------------------------------------------------------------------
-- Config Selection Helpers
--------------------------------------------------------------------------------

-- Returns true when a group/panel frame should be at full alpha because it
-- (or its parent container) is selected in the Config panel.
-- Used by: alpha fade system, alpha sync ticker, button force-visible.
function ST.IsGroupConfigSelected(groupId)
    local CS = ST._configState
    if not CS then return false end
    local configFrame = CS.configFrame
    if not configFrame or not configFrame.frame or not configFrame.frame:IsShown() then
        return false
    end

    -- Direct panel/group selection
    if CS.selectedGroup == groupId then return true end

    -- Multi-panel selection
    if CS.selectedPanels and CS.selectedPanels[groupId] then return true end

    -- Container selected, no specific panel → all panels in that container
    if CS.selectedContainer and not CS.selectedGroup then
        local db = ST.Addon.db
        local group = db and db.profile.groups[groupId]
        if group and group.parentContainerId == CS.selectedContainer then
            return true
        end
    end

    return false
end

-- Returns true when this runtime button should be force-visible because its
-- group/panel is selected in the Config panel.  Active only while the config
-- frame is shown.
--
-- Force-visible rules:
--   1. Container selected, no panel/button selected → ALL buttons in ALL panels
--   2. Panel header selected, no button selected → ALL buttons in that panel
--   3. Individual button(s) selected within panel → only those buttons
--   4. Multi-selected panels (Ctrl+click) → ALL buttons in each panel
function ST.IsConfigButtonForceVisible(button)
    if not button then return false end

    local groupId = button._groupId
    if not groupId then return false end
    local index = button.index
    if not index then return false end

    local CS = ST._configState
    if not CS then return false end
    local configFrame = CS.configFrame
    if not configFrame or not configFrame.frame or not configFrame.frame:IsShown() then
        return false
    end

    -- Single-selected panel: check for individual button selection
    if CS.selectedGroup == groupId then
        if CS.selectedButton then
            return CS.selectedButton == index
        end
        if next(CS.selectedButtons) then
            return CS.selectedButtons[index] or false
        end
        -- No button selected → header-only, force-show ALL buttons
        return true
    end

    -- Multi-selected panels → all buttons
    if CS.selectedPanels and CS.selectedPanels[groupId] then
        return true
    end

    -- Container selected, no specific panel → all buttons in all panels
    if CS.selectedContainer and not CS.selectedGroup then
        local db = ST.Addon.db
        local group = db and db.profile.groups[groupId]
        if group and group.parentContainerId == CS.selectedContainer then
            return true
        end
    end

    return false
end
