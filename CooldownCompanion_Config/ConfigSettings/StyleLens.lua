--[[
    CooldownCompanion - StyleLens
    Panel/entry style inheritance, scope chrome, section editing, and advanced unlocks.

    Part of the Helpers family; see its ordered block in the addon TOC.
    Private helpers are shared through ST._SettingsHelpers.
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon
local AceGUI = LibStub("AceGUI-3.0")
local CS = ST._configState
local IsNoCooldownSpellID = ST.IsNoCooldownSpell
local UsesChargeBehavior = CooldownCompanion.UsesChargeBehavior

local SH = ST._SettingsHelpers

-- Helpers.lua
local ChainHeadingBadges = ST._ChainHeadingBadges

local function GroupSupportsPerButtonOverrides(group)
    return group and (group.displayMode or "icons") ~= "textures"
end

local function GetSelectedRuntimeButton(buttonData)
    local groupId = CS.selectedGroup
    local buttonIndex = CS.selectedButton
    if not (buttonData and groupId and buttonIndex) then
        return nil
    end

    local profile = CooldownCompanion.db and CooldownCompanion.db.profile
    local group = profile and profile.groups and profile.groups[groupId]
    if not (group and group.buttons and group.buttons[buttonIndex] == buttonData) then
        return nil
    end

    local frame = CooldownCompanion.groupFrames and CooldownCompanion.groupFrames[groupId]
    if not (frame and frame.buttons) then
        return nil
    end

    for _, button in ipairs(frame.buttons) do
        if button and button.buttonData == buttonData then
            return button
        end
    end
    return nil
end

-- Owner ruling (aura rebuild plan): group-level aura style sections are shown
-- only while the group actually has an aura-tracking entry. Shared by
-- GroupTabs and BarModeTabs (load order: Helpers loads first).
local function GroupHasAuraTrackingEntry(group)
    if not (group and group.buttons) then
        return false
    end
    for _, buttonData in ipairs(group.buttons) do
        if buttonData.type == "spell"
            and (buttonData.auraTracking or buttonData.addedAs == "aura") then
            return true
        end
    end
    return false
end

-- Aura style sections only apply while an entry tracks an aura. This gate is
-- config-visibility only, NOT part of ST.CanButtonUseOverrideSection: aura
-- tracking is a toggle, and the runtime check feeds GetEffectiveStyle's prune
-- pass, which would permanently delete the saved override on toggle-off.
local AURA_TRACKING_CONFIG_ONLY_SECTIONS = {
    auraText = true,
    auraStackText = true,
    auraDurationSwipe = true,
    auraIndicator = true,
    barActiveAura = true,
    pandemic = true,
    whileAuraActive = true,
    auraMissingDesaturation = true,
}

-- Keybind and custom text never reach a packed aura cell: the renderer draws
-- no replica for an aura host (AuraDisplay.lua), and an Aura Only Section's
-- members are exactly that. Config-visibility only, for the same reason the
-- list above is: membership is POSITIONAL, an entry can be dragged back out to
-- the base grid, and the runtime gate feeds GetEffectiveStyle's prune pass,
-- which would delete the saved keybind override on the way in.
--
-- `group` is optional: the runtime callers (prune, promote, migrations) never
-- pass one and are unaffected, which is exactly the separation this gate wants.
local function CanButtonUseConfigOverrideSection(buttonData, sectionId, group)
    if ST.CanButtonUseOverrideSection then
        local allowed, reason = ST.CanButtonUseOverrideSection(buttonData, sectionId)
        if not allowed then
            return false, reason
        end
    elseif buttonData and buttonData.type == "equipmentSlot"
        and ST.EQUIPMENT_SLOT_DENIED_OVERRIDE_SECTIONS
        and ST.EQUIPMENT_SLOT_DENIED_OVERRIDE_SECTIONS[sectionId] then
        return false, "entryType"
    end

    if AURA_TRACKING_CONFIG_ONLY_SECTIONS[sectionId]
        and not (buttonData and (buttonData.auraTracking or buttonData.addedAs == "aura")) then
        return false, "auraTracking"
    end

    if sectionId == "keybindText" and group and buttonData
        and ST.IsAuraSectionEntry and ST.IsAuraSectionEntry(group, buttonData) then
        return false, "auraSection"
    end

    if not (ST.NO_COOLDOWN_DENIED_OVERRIDE_SECTIONS
        and ST.NO_COOLDOWN_DENIED_OVERRIDE_SECTIONS[sectionId]
        and buttonData
        and buttonData.type == "spell"
        and not buttonData.isPassive) then
        return true
    end

    if UsesChargeBehavior and UsesChargeBehavior(buttonData) then
        return true
    end

    local cooldownSpellId = buttonData.id
    local button = GetSelectedRuntimeButton(buttonData)
    if button then
        local displaySpellId = button._displaySpellId or buttonData.id
        if button._noCooldown ~= nil and button._noCooldownSpellId == displaySpellId then
            return not button._noCooldown, button._noCooldown and "noCooldown" or nil
        end
        cooldownSpellId = displaySpellId
    end

    if IsNoCooldownSpellID and IsNoCooldownSpellID(cooldownSpellId) == true then
        return false, "noCooldown"
    end

    return true
end

------------------------------------------------------------------------
-- STYLE LENS
--
-- Selecting an entry turns the panel's styling tabs into a lens onto that
-- entry: every control reads the entry's effective value, and only the
-- sections the entry has actually customized write anywhere.
--
-- The lens is resolved once per build and handed down, so a single tab cannot
-- disagree with itself about which entry (or none) it is showing.
------------------------------------------------------------------------

-- One level deep is the whole contract: style tables are colors and other
-- flat value bags, and rows edit them IN PLACE. Handing a row the group's own
-- table would make a panel edit land on the entry's lens (or the reverse), so
-- every table value gets a fresh copy.
local function CopyDetachedStyleValue(value)
    if type(value) ~= "table" then
        return value
    end
    local copy = {}
    for k, v in pairs(value) do
        copy[k] = v
    end
    return copy
end

-- Build a DETACHED snapshot of what an entry actually renders with: the
-- panel's style with the entry's overrides laid on top.
--
-- Deliberately not GetEffectiveStyle: that returns buttonData.styleOverrides
-- itself wearing an __index metatable pointing at the group style, i.e. a live
-- alias of saved data. A config row handed that table would write straight
-- into the override store even for a section the entry never customized.
--
-- `pairs` never walks __index, so a metatable the runtime left on
-- styleOverrides is simply not seen here.
local function BuildDetachedEffectiveStyle(groupStyle, buttonData)
    local effective = {}
    for key, value in pairs(groupStyle or {}) do
        effective[key] = CopyDetachedStyleValue(value)
    end
    for key, value in pairs(buttonData and buttonData.styleOverrides or {}) do
        effective[key] = CopyDetachedStyleValue(value)
    end
    return effective
end

-- Resolve which lens the styling tabs are looking through:
--   "panel" - no entry selected (or the panel has no per-entry overrides at
--             all, as with texture panels): tabs edit the panel style.
--   "entry" - exactly one entry selected: tabs read that entry's effective
--             style; per-section scope decides where (or whether) they write.
--   "multi" - two or more entries selected: no single entry to show, so the
--             tabs stay on the panel style.
-- Multi-select is counted the same way every other per-entry surface counts
-- it, so scope chrome availability and lens mode can never disagree.
local function ResolveStyleLens(group)
    if not GroupSupportsPerButtonOverrides(group) then
        return { mode = "panel" }
    end

    local multiCount = 0
    if CS.selectedButtons then
        for _ in pairs(CS.selectedButtons) do multiCount = multiCount + 1 end
    end

    local buttonData = CS.selectedButton and group.buttons and group.buttons[CS.selectedButton]
    if buttonData and multiCount < 2 then
        return {
            mode = "entry",
            buttonIndex = CS.selectedButton,
            buttonData = buttonData,
            effective = BuildDetachedEffectiveStyle(group.style, buttonData),
        }
    end

    if multiCount >= 2 then
        return { mode = "multi" }
    end

    return { mode = "panel" }
end

-- Resolve one section against the lens. Returns scope, the table its controls
-- READ from, and the table they WRITE to.
--
-- A nil writeStyle is the inert marker and needs no separate flag: there is
-- nowhere for the section's controls to commit, so they are read-only.
--   "panel"/"multi" - panel style, read and written.
--   "panelOnly"     - a section with no override identity at all (sectionId
--                     nil): shown through the lens, never written per entry.
--   "denied"        - this entry type cannot use the section.
--   "customized"    - the entry owns this section: writes land in its
--                     styleOverrides.
--   "inherited"     - the entry follows the panel here: shown, not written.
local function ResolveLensSection(lens, group, sectionId)
    local mode = lens and lens.mode or "panel"

    if mode ~= "entry" then
        local groupStyle = group and group.style
        return (mode == "multi") and "multi" or "panel", groupStyle, groupStyle
    end

    if sectionId == nil then
        return "panelOnly", lens.effective, nil
    end

    local buttonData = lens.buttonData
    -- The denied REASON rides along as a fourth return so scope chrome can
    -- show the centralized copy for it. Callers that only want the first three
    -- are unaffected.
    local allowed, deniedReason = CanButtonUseConfigOverrideSection(buttonData, sectionId, group)
    if not allowed then
        return "denied", lens.effective, nil, deniedReason
    end

    -- "customized" requires the override STORE, not just the section flag: a
    -- flagged section with no styleOverrides table (hand-edited or partially
    -- imported data) resolves as inherited, so its Customize path recreates
    -- the store properly instead of a write-less customized scope leaking a
    -- live surface that edits the detached effective table.
    if buttonData.overrideSections and buttonData.overrideSections[sectionId]
        and buttonData.styleOverrides then
        return "customized", lens.effective, buttonData.styleOverrides
    end

    return "inherited", lens.effective, nil
end

-- Inert sections are built exactly like live ones and then gated afterwards,
-- so a read-only section can never drift from the section it mirrors. Mark the
-- column before the section's widgets go in, apply after.
local function MarkInertRange(column)
    local children = column and column.children
    return children and #children or 0
end

local function MakeWidgetTreeInert(widget, hideReverts)
    -- hideReverts rides the read-only panel walk only (MakeAdvancedPanelReadOnly):
    -- a REVERT glyph does not survive the lock (owner ruling 2026-08-31) - a
    -- destructive one-click delete has no place on a surface presented as
    -- locked. The glyph lives on the row FRAME where the child walk below
    -- never looks, so it is handled here, per widget, on the same traversal.
    -- The main column's inert ranges never pass the flag: their reverts stay.
    if hideReverts then
        local frame = widget.frame
        local revert = frame and frame._cdcScopeRowRevert
        if revert then
            revert:Hide()
        end
    end

    -- A row inside a locked advanced panel whose OWN nested lens section is
    -- independently writable (bar mode's Icon Zoom, customized while Bar Icon
    -- itself is inherited) opts out of the lock: greying it would leave an
    -- override the user just created with no live control. The flag is set
    -- only while a read-only build is underway and consumed here in the same
    -- BuildPanelContents call, so it can never ride a pooled widget into a
    -- later build. It exempts exactly the widget's OWN disable: the revert
    -- above still hides, and children are still walked, so a future flag on
    -- a container row cannot silently unlock a whole subtree.
    local exempt = widget._cdcReadOnlyExempt
    if exempt then
        widget._cdcReadOnlyExempt = nil
    end

    if not exempt and widget.SetDisabled then
        widget:SetDisabled(true)
    end

    -- Badges live on the widget's FRAME, not in the AceGUI child tree, so the
    -- walk below never reaches a gear - deliberately. A gear in an inert
    -- section stays live and keeps its normal idle/open colors (owner ruling
    -- 2026-08-31): it opens its panel read-only behind the unlock strip
    -- (AddAdvancedToggle's options.unlock), which is a way into the section,
    -- not an edit of it, and the panel is what says locked.

    local children = widget.children
    if children then
        for i = 1, #children do
            local child = children[i]
            if child then
                MakeWidgetTreeInert(child, hideReverts)
            end
        end
    end
end

local function ApplyInertRange(column, mark)
    local children = column and column.children
    if not children then
        return
    end
    for i = (mark or 0) + 1, #children do
        local child = children[i]
        if child then
            MakeWidgetTreeInert(child)
        end
    end
end

-- Why an entry cannot use a section, single-sourced as one clause per reason:
-- the scope chrome's denied tooltip AND the Customizations list both explain
-- the same denials, and the two must never describe one differently.
-- Each surface supplies only its own framing around the shared clause.
-- displayMode is list-only: a section from another display mode is never
-- DRAWN, so no chrome ever asks about it.
local SECTION_DENIAL_CLAUSES = {
    noCooldown = "this spell does not have a real cooldown",
    auraTracking = "this entry is not tracking an aura",
    auraSection = "this entry sits in an Aura Only Section",
    displayMode = "the panel's current display mode does not use it",
    entryType = "this entry type cannot use it",
}

local function GetSectionDenialClause(reason)
    return SECTION_DENIAL_CLAUSES[reason] or SECTION_DENIAL_CLAUSES.entryType
end

local function AddSectionDeniedTooltipLines(reason)
    GameTooltip:AddLine("Not available: " .. GetSectionDenialClause(reason) .. ".", 0.5, 0.5, 0.5)
end

------------------------------------------------------------------------
-- REVERT GLYPH HELPER (shared by the per-section scope chrome below)
------------------------------------------------------------------------
local REVERT_GLYPH_ATLAS = "common-search-clearbutton"
local REVERT_GLYPH_SIZE = 12

local function GetOverrideSectionLabel(sectionId)
    local sectionDef = sectionId and ST.OVERRIDE_SECTIONS[sectionId]
    return sectionDef and sectionDef.label or sectionId
end

-- The revert's WORDING and its CLICK, split out from the glyph so the heading
-- chrome's text affordance is the same action in a different shape. Any change
-- to what reverting says or does lands here for both.
--
-- The label form exists because ONE revert in the config is not a style section:
-- the per-entry text format is a flat field (buttonData.textFormat) outside the
-- section machinery, and it must still read as the same action.
local function GetRevertTooltipTextForLabel(label)
    return "Revert " .. label .. " to panel settings"
end

local function GetRevertTooltipText(sectionId)
    return GetRevertTooltipTextForLabel(GetOverrideSectionLabel(sectionId))
end

local function PerformSectionRevert(buttonData, sectionId)
    CooldownCompanion:RevertSection(buttonData, sectionId)
    CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
    CooldownCompanion:RefreshConfigPanel()
end

-- The revert glyph's LOOK and its HOVER/CLICK contract, split so a revert that
-- is not a style section wears exactly the same control without restating the
-- atlas, the size or the tooltip shape.
local function ApplyRevertGlyphLook(icon)
    icon:SetSize(REVERT_GLYPH_SIZE, REVERT_GLYPH_SIZE)
    icon:ClearAllPoints()
    icon:SetPoint("CENTER")
    icon:SetAtlas(REVERT_GLYPH_ATLAS)
end

local function BindRevertGlyph(revertBtn, tooltipText, onClick)
    revertBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(tooltipText)
        GameTooltip:Show()
    end)
    revertBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    revertBtn:SetScript("OnClick", onClick)
end

-- The revert glyph's look, wording and click flow. Worn by the scope chrome's
-- ROW reverts (the heading uses the text affordance below). The caller owns
-- creating and placing the button.
local function WireRevertGlyph(revertBtn, icon, buttonData, sectionId)
    ApplyRevertGlyphLook(icon)
    BindRevertGlyph(revertBtn, GetRevertTooltipText(sectionId), function()
        PerformSectionRevert(buttonData, sectionId)
    end)
end

------------------------------------------------------------------------
-- SCOPE CHROME
--
-- With an entry selected the styling tabs become a lens onto that entry, and
-- each section has to say whose values it is showing plus offer the one action
-- that changes that: Customize on a section the entry inherits from the panel,
-- Revert on one the entry owns. Sections the entry cannot use say so instead.
--
-- The chrome is the ESCAPE HATCH out of a read-only section, so it must stay
-- live where everything else is gated: it hangs off the widget's FRAME under
-- _cdcScope* names, and MakeWidgetTreeInert only ever walks AceGUI children -
-- never frame badges. Keep it that way - a scope control the inert pass can
-- reach would strand the entry with no way back out, and the advanced GEAR
-- must stay live too (owner ruling 2026-08-31): it is the only entrance into
-- a locked section's read-only panel, so the inert walk must never disable
-- _cdcAdvancedBtn. The one exception is the revert glyph, hidden by the
-- read-only panel walk's hideReverts flag.
--
-- Every element is cached on that frame, re-styled from scratch on each
-- attach, and hidden both at attach time and on widget release, because the
-- Heading and row pools are shared and a recycled frame must never wear the
-- previous tenant's scope.
------------------------------------------------------------------------
local SCOPE_CHROME_GOLD = { 1, 0.82, 0 }
local SCOPE_CHROME_GOLD_HOVER = { 1, 0.93, 0.45 }
local SCOPE_CHROME_GREY = { 0.5, 0.5, 0.5 }
local SCOPE_CHROME_HEIGHT = 14
local SCOPE_GLYPH_BUTTON_SIZE = 16
local SCOPE_GLYPH_ICON_SIZE = 12
-- A long entry name would push the heading's fading rule (or a row's control
-- column) off the line, so the NAME is cut rather than the sentence round it.
local SCOPE_ENTRY_NAME_MAX_CHARS = 18

-- _cdcScopeRevert is the heading's RETIRED glyph. The heading reverts through
-- _cdcScopeRevertText now, but a Heading frame that already carries the glyph
-- from an earlier build must still have it hidden, so the field stays on the
-- cleanup list. Rows keep the glyph and use their own field.
local HEADING_SCOPE_FIELDS = { "_cdcScopeNote", "_cdcScopeAction", "_cdcScopeRevert", "_cdcScopeRevertText" }
local ROW_SCOPE_FIELDS = { "_cdcScopeRowAction", "_cdcScopeRowRevert", "_cdcScopeRowPanel" }

-- A grey row has no affordance to explain itself, so the explanation is a
-- HOVER - on the CONTROL, not the row. It rides RowWidgets' SetScopeTooltip,
-- which stores the lines and raises a transparent overlay over the row's
-- control region; the row frame's own OnEnter never renders them, so hovering
-- the label or the empty middle of a grey row says nothing about scope (owner
-- ruling 2026-08-14: a row-wide scope hover was tooltip soup).
local ROW_SCOPE_INHERITED_TOOLTIP = {
    "Panel setting",
    { "Follows the panel. Customize to edit.", 1, 1, 1, true },
}

-- Cutting a multi-byte character in half renders as a broken glyph, so walk
-- whole UTF-8 sequences instead of taking a byte slice.
local function TruncateEntryName(name)
    if not name or name == "" then
        return nil
    end
    local pos, count, len = 1, 0, #name
    while pos <= len do
        if count >= SCOPE_ENTRY_NAME_MAX_CHARS then
            return name:sub(1, pos - 1) .. "..."
        end
        local byte = name:byte(pos)
        pos = pos + ((byte < 0xC0 and 1) or (byte < 0xE0 and 2) or (byte < 0xF0 and 3) or 4)
        count = count + 1
    end
    return name
end

local function GetLensEntryName(lens)
    local buttonData = lens and lens.buttonData
    if not buttonData then
        return nil
    end
    -- The config already has one entry-name resolver (override spells, custom
    -- names, equipment slots, CDM child slots); never grow a second.
    local name = ST._GetConfigEntryDisplayName
        and ST._GetConfigEntryDisplayName(buttonData)
        or buttonData.name
    return TruncateEntryName(name)
end

-- Customize: copy the panel's values for this section onto the entry, then
-- rebuild. Deliberately no tab navigation - the section the owner is looking
-- at is the section that just became editable, in place.
--
-- The preview command center is the one caller that defers the config rebuild:
-- it has to prepare the destination and queue the section's advanced panel
-- first, then its existing navigation path performs the one refresh that
-- consumes both. The pinned mirror still updates immediately through
-- UpdateGroupStyle, so the preview never waits on that navigation.
local function PromoteLensSection(lens, group, sectionId, opts)
    local buttonData = lens and lens.buttonData
    local groupStyle = group and group.style
    if not (buttonData and groupStyle and sectionId) then
        return false
    end
    CooldownCompanion:PromoteSection(buttonData, groupStyle, sectionId)
    CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
    if not (opts and opts.deferRefresh) then
        CooldownCompanion:RefreshConfigPanel()
    end
    return true
end

-- The unlock action for an advanced gear, resolved from the small LAZY spec
-- the gear site stores in options.unlock. Only the one panel being built ever
-- consumes an unlock, so all labels and closures are made HERE, at panel-build
-- time (BuildPanelContentsBody, AdvancedSettingsPanel.lua) - a tab rebuild
-- that opens no panel allocates none of them.
--
-- Lens spec { sec, enable }: the ONE next step that makes the panel's greyed
-- rows editable. An inherited section unlocks by Customize (the same
-- PromoteLensSection the scope chrome runs); a writable section whose parent
-- toggle is off unlocks by the enable spec, wrapped in the styling tabs'
-- standard refresh. Both-locked resolves Customize FIRST - after it the
-- panel rebinds live and re-renders the footer with the enable step.
--
-- Non-lens spec { target, enable, refreshKind }: the enable applies to the
-- caller's own settings table, then the named refresh sequence runs - each
-- kind reproduces exactly what its sites' checkboxes run.
--
-- An enable spec is { label, key } for the plain write-true case, or
-- { label, apply(write) [, after] } where enabling sets more than one key;
-- sites declare the plain ones as file-local constants. `enable.run` is the
-- non-lens seam for a shared enable function that owns its WHOLE sequence,
-- refresh included (the texture indicators' collision handling).
--
-- The enable action is deliberately ONE-WAY (owner ruling 2026-08-31, after
-- trying every variant in game): the footer may turn a feature ON to start
-- editing right where the settings are, but turning it OFF stays solely on
-- the toggle's own row. The gear itself is built for every scope except
-- "denied" - a denied section structurally cannot exist for the entry, so it
-- keeps no gear at all.
local ADVANCED_UNLOCK_REFRESH = {
    -- The styling tabs' standard write-then-rebuild pair.
    groupStyle = function()
        CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        CooldownCompanion:RefreshConfigPanel()
    end,
    -- Custom bars: apply the bars, then rebuild.
    resourceBars = function()
        CooldownCompanion:ApplyResourceBars()
        CooldownCompanion:RefreshConfigPanel()
    end,
    -- Trigger-panel effects: restyle the texture visuals, then rebuild.
    auraTextures = function()
        CooldownCompanion:RefreshAllAuraTextureVisuals()
        CooldownCompanion:RefreshConfigPanel()
    end,
    -- Cast bar contents: apply the live cast bar, then rebuild.
    castBar = function()
        CooldownCompanion:ApplyCastBarSettings()
        CooldownCompanion:RefreshConfigPanel()
    end,
}

local function ApplyAdvancedUnlockEnable(enable, write)
    if enable.apply then
        enable.apply(write)
    else
        write[enable.key] = true
    end
end

local function ResolveAdvancedUnlock(spec)
    if not spec then
        return nil
    end
    local sec = spec.sec
    local enable = spec.enable
    if not sec then
        -- Non-lens: no enable means the toggle is on, so the panel is live.
        if not enable then
            return nil
        end
        if enable.run then
            return { label = enable.label, onClick = enable.run }
        end
        return {
            label = enable.label,
            onClick = function()
                ApplyAdvancedUnlockEnable(enable, spec.target)
                ADVANCED_UNLOCK_REFRESH[spec.refreshKind]()
            end,
        }
    end
    if sec.write == nil then
        if sec.scope == "inherited" then
            return {
                label = "Customize " .. GetOverrideSectionLabel(sec.sectionId) .. " for this entry",
                onClick = function()
                    PromoteLensSection(sec.lens, sec.group, sec.sectionId)
                end,
            }
        end
        if sec.scope == "denied" then
            -- Denied stays nil by call-site convention: a denied section
            -- structurally cannot exist for the entry, so it keeps no gear
            -- and this helper is never consulted for one.
            return nil
        end
        -- Any other write-less scope ("panelOnly": a nil sectionId under an
        -- entry lens) must NEVER open live - its rows would bind the detached
        -- effective snapshot and edits would silently vanish on the next
        -- rebuild. Lock the panel with no footer action; the strip renders
        -- nothing for an unlock without one.
        return {}
    end
    if enable then
        return {
            label = enable.label,
            onClick = function()
                ApplyAdvancedUnlockEnable(enable, sec.write)
                CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
                -- The one seam for a section whose checkbox path runs an
                -- extra step between style apply and the config rebuild (the
                -- icon fill timer's cooldown rewalk) - the two entrances of
                -- one enable must run the same sequence.
                if enable.after then
                    enable.after()
                end
                CooldownCompanion:RefreshConfigPanel()
            end,
        }
    end
    return nil
end

-- The unlock strip's gold accents: a soft center-peaked wash behind the text
-- and a 1px rule fading out from center along its top edge - the two-half
-- gradient recipe the mode banners and the preview banner already draw, in
-- the scope chrome's gold.
local UNLOCK_STRIP_CLEAR = CreateColor(1, 0.82, 0, 0)
local UNLOCK_STRIP_WASH = CreateColor(1, 0.82, 0, 0.12)
local UNLOCK_STRIP_WASH_HOVER = CreateColor(1, 0.82, 0, 0.2)
local UNLOCK_STRIP_RULE = CreateColor(1, 0.82, 0, 0.55)

local function SetUnlockStripWash(art, color)
    art.bgLeft:SetGradient("HORIZONTAL", UNLOCK_STRIP_CLEAR, color)
    art.bgRight:SetGradient("HORIZONTAL", color, UNLOCK_STRIP_CLEAR)
end

-- The strip's accent art lives on a Cooldown Companion-OWNED singleton frame,
-- never on the pooled label (review finding 2026-08-31): textures can never
-- be reparented off a frame, the AceGUI pool is shared with every other addon
-- embedding the library, and the repo invariant forbids child regions on
-- pooled widget frames (agent-reference/patterns-and-gotchas.md). The frame
-- is attached to the label at build and detached on the label's release, the
-- same borrow-and-detach pattern the gears and info badges use. One panel
-- exists at a time (singleton by ruling), so one art frame serves.
local unlockStripArt

local function EnsureUnlockStripArt()
    if unlockStripArt then
        return unlockStripArt
    end
    local art = CreateFrame("Frame")
    art:EnableMouse(false)
    art:Hide()
    local function StripTexture(layer)
        local tex = art:CreateTexture(nil, layer)
        tex:SetTexture("Interface/Buttons/WHITE8x8")
        return tex
    end
    art.bgLeft = StripTexture("BACKGROUND")
    art.bgLeft:SetPoint("TOPLEFT")
    art.bgLeft:SetPoint("BOTTOMRIGHT", art, "BOTTOM", 0, 0)
    art.bgRight = StripTexture("BACKGROUND")
    art.bgRight:SetPoint("TOPLEFT", art, "TOP", 0, 0)
    art.bgRight:SetPoint("BOTTOMRIGHT")
    art.lineLeft = StripTexture("BORDER")
    art.lineLeft:SetHeight(1)
    art.lineLeft:SetPoint("TOPLEFT")
    art.lineLeft:SetPoint("TOPRIGHT", art, "TOP", 0, 0)
    art.lineLeft:SetGradient("HORIZONTAL", UNLOCK_STRIP_CLEAR, UNLOCK_STRIP_RULE)
    art.lineRight = StripTexture("BORDER")
    art.lineRight:SetHeight(1)
    art.lineRight:SetPoint("TOPLEFT", art, "TOP", 0, 0)
    art.lineRight:SetPoint("TOPRIGHT")
    art.lineRight:SetGradient("HORIZONTAL", UNLOCK_STRIP_RULE, UNLOCK_STRIP_CLEAR)
    unlockStripArt = art
    return art
end

local function DetachUnlockStripArt()
    if unlockStripArt then
        unlockStripArt:Hide()
        unlockStripArt:ClearAllPoints()
        unlockStripArt:SetParent(nil)
    end
end

-- The inline editor's first row is the existing one-step unlock action.
-- Its controls are gated separately so inherited outer sections cannot
-- disable Customize or Turn On along with the settings they unlock.
local function BuildAdvancedUnlockStrip(scroll, unlock)
    -- An unlock with no action is a pure lock (a write-less "panelOnly"
    -- section, ResolveAdvancedUnlock): the rows grey but there is
    -- no one next step to offer, so no footer renders.
    if not (unlock and unlock.onClick) then
        return
    end
    local action = AceGUI:Create("InteractiveLabel")
    -- The shared InteractiveLabel pool also serves the Navigator, whose rows
    -- hang plain-child badges off the label FRAME; nothing hides those on
    -- release, so a reacquired frame arrives wearing its previous tenant's
    -- badges. Same clean-on-acquire call every other non-Navigator consumer
    -- of the pool makes.
    if ST._CleanRecycledEntry then
        ST._CleanRecycledEntry(action)
    end
    action:SetFontObject(GameFontNormal)
    action:SetText(unlock.label)
    action:SetColor(SCOPE_CHROME_GOLD[1], SCOPE_CHROME_GOLD[2], SCOPE_CHROME_GOLD[3])
    action:SetJustifyH("CENTER")
    action:SetFullWidth(true)

    -- The editor's top padding and the following gap contain the action's
    -- wash. Detach its art when the label returns to the shared pool.
    local frame = action.frame
    local art = EnsureUnlockStripArt()
    art:SetParent(frame)
    art:SetFrameLevel(math.max(frame:GetFrameLevel() - 1, 0))
    art:ClearAllPoints()
    art:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 6)
    art:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, -6)
    art:Show()
    -- Re-asserted every build: a pointer that left without OnLeave firing
    -- (the refresh tore the frame out from under it) must not strand the
    -- hover wash.
    SetUnlockStripWash(art, UNLOCK_STRIP_WASH)

    -- Chain, don't replace, exactly as AddAdvancedToggle's release handler
    -- does: a freshly acquired widget has no OnRelease callback, but never
    -- clobber one another decorator installed in the same build.
    local prevOnRelease = action.events and action.events["OnRelease"]
    action:SetCallback("OnRelease", function(widget, event, ...)
        if prevOnRelease then
            prevOnRelease(widget, event, ...)
        end
        if unlockStripArt and unlockStripArt:GetParent() == frame then
            DetachUnlockStripArt()
        end
    end)

    action:SetCallback("OnClick", function()
        unlock.onClick()
    end)
    action:SetCallback("OnEnter", function(widget)
        if widget.label then
            widget.label:SetTextColor(SCOPE_CHROME_GOLD_HOVER[1],
                SCOPE_CHROME_GOLD_HOVER[2], SCOPE_CHROME_GOLD_HOVER[3])
        end
        SetUnlockStripWash(art, UNLOCK_STRIP_WASH_HOVER)
    end)
    action:SetCallback("OnLeave", function(widget)
        if widget.label then
            widget.label:SetTextColor(SCOPE_CHROME_GOLD[1],
                SCOPE_CHROME_GOLD[2], SCOPE_CHROME_GOLD[3])
        end
        SetUnlockStripWash(art, UNLOCK_STRIP_WASH)
    end)
    scroll:AddChild(action)
    if ST._AddModeSummarySpacer then ST._AddModeSummarySpacer(scroll, 6) end
    return action
end

-- Read-only gate for a locked advanced panel, applied AFTER the build so the
-- panel can never drift from its live twin - the same built-like-live rule the
-- main column's inert ranges follow. Runs before the unlock strip is appended,
-- so the sweep covers exactly the build's own rows. One traversal: the
-- hideReverts flag folds the revert-glyph hiding (owner ruling 2026-08-31,
-- see MakeWidgetTreeInert) into the same walk, and embedded rows with their
-- OWN lens sections (bar mode's Icon Zoom inside Bar Icon Advanced) keep
-- their scope chrome live - Customize is the escape hatch into the section.
local function MakeAdvancedPanelReadOnly(scroll)
    local children = scroll and scroll.children
    if not children then
        return
    end
    for i = 1, #children do
        local child = children[i]
        if child then
            MakeWidgetTreeInert(child, true)
        end
    end
end

-- One-click promotion for an inherited color control rebuilds the whole tab,
-- so the physical AceGUI ColorPicker the user clicked is released. Carry only
-- semantic identity across that rebuild; the replacement row consumes this
-- request and opens its own picker on the next frame.
local pendingInheritedColorOpen
local INHERITED_COLOR_CONTROL_TOOLTIP = {
    "Panel setting",
    { "Click to customize this color for the selected entry.", 1, 1, 1, true },
}

local function HideScopeChrome(frame, fields)
    for i = 1, #fields do
        local element = frame[fields[i]]
        if element then
            element:ClearAllPoints()
            element:Hide()
            element:EnableMouse(false)
            element:SetScript("OnEnter", nil)
            element:SetScript("OnLeave", nil)
            -- Frames have no OnClick script to clear, and asking for one is an
            -- error. Dropping it on the buttons releases the build's lens and
            -- group upvalues with the chrome.
            if element:GetObjectType() == "Button" then
                element:SetScript("OnClick", nil)
            end
            element:SetParent(nil)
            -- Re-attaching on the same frame in one build must not chain off
            -- the chrome that was just hidden.
            if frame._cdcHeadingBadgeTail == element then
                frame._cdcHeadingBadgeTail = nil
            end
        end
    end
end

-- The scope tooltip is DATA on the widget, and the row - not this file - owns
-- the overlay that shows it, so it is cleared the same way it is set: through
-- the row. Every path that hides row chrome clears it in the same breath, which
-- is what lowers the overlay. Guarded because only the row-grammar widgets
-- carry the channel.
local function SetRowScopeTooltip(rowWidget, lines)
    if rowWidget and rowWidget.SetScopeTooltip then
        rowWidget:SetScopeTooltip(lines)
    end
end

-- Denied rows explain themselves with the SHARED denial clause, so the row
-- hover and the heading's denied tooltip can never describe one denial
-- differently. Built per call because the clause depends on the reason.
local function BuildRowDeniedScopeTooltip(reason)
    local clause = GetSectionDenialClause(reason)
    return {
        "Not available",
        { clause:sub(1, 1):upper() .. clause:sub(2) .. ".", 1, 1, 1, true },
    }
end

-- Text chrome: a note (plain Frame) or an affordance (Button), both a single
-- line of text sized to the string so the badge chain can measure them.
local function EnsureScopeText(frame, field, clickable)
    local element = frame[field]
    if not element then
        element = CreateFrame(clickable and "Button" or "Frame", nil, frame)
        element:SetHeight(SCOPE_CHROME_HEIGHT)
        element.text = element:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        element.text:SetPoint("LEFT")
        frame[field] = element
    end

    element:SetParent(frame)
    element:ClearAllPoints()
    element:EnableMouse(clickable and true or false)
    element:SetScript("OnEnter", nil)
    element:SetScript("OnLeave", nil)
    if clickable then
        element:SetScript("OnClick", nil)
    end
    element:Show()
    element.text:Show()
    return element
end

local function SetScopeText(element, text, color)
    element.text:SetText(text or "")
    element.text:SetTextColor(color[1], color[2], color[3])
    element:SetWidth(math.max(element.text:GetStringWidth(), 1))
end

-- Glyph chrome: one 16px hit area carrying a 12px icon, worn by the revert
-- glyph. Every icon state it can wear is re-asserted here for pool reuse.
local function EnsureScopeGlyph(frame, field)
    local btn = frame[field]
    if not btn then
        btn = CreateFrame("Button", nil, frame)
        btn:SetSize(SCOPE_GLYPH_BUTTON_SIZE, SCOPE_GLYPH_BUTTON_SIZE)
        btn.icon = btn:CreateTexture(nil, "OVERLAY")
        btn.icon:SetSize(SCOPE_GLYPH_ICON_SIZE, SCOPE_GLYPH_ICON_SIZE)
        btn.icon:SetPoint("CENTER")
        frame[field] = btn
    end

    btn:SetParent(frame)
    btn:ClearAllPoints()
    btn:EnableMouse(true)
    btn:Enable()
    btn:SetScript("OnEnter", nil)
    btn:SetScript("OnLeave", nil)
    btn:SetScript("OnClick", nil)
    btn:Show()
    btn.icon:Show()
    btn.icon:SetDesaturated(false)
    btn.icon:SetVertexColor(1, 1, 1)
    return btn
end

-- The gold text affordance's hover language: brighten, and say what the click
-- does. Shared so Customize and Revert read as one family of controls.
local function WireScopeTextHover(action, tooltipText)
    action:SetScript("OnEnter", function(self)
        self.text:SetTextColor(SCOPE_CHROME_GOLD_HOVER[1], SCOPE_CHROME_GOLD_HOVER[2], SCOPE_CHROME_GOLD_HOVER[3])
        if tooltipText then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(tooltipText)
            GameTooltip:Show()
        end
    end)
    action:SetScript("OnLeave", function(self)
        self.text:SetTextColor(SCOPE_CHROME_GOLD[1], SCOPE_CHROME_GOLD[2], SCOPE_CHROME_GOLD[3])
        GameTooltip:Hide()
    end)
end

local function WireScopeAction(action, lens, group, sectionId, tooltipText)
    WireScopeTextHover(action, tooltipText)
    action:SetScript("OnClick", function()
        PromoteLensSection(lens, group, sectionId)
    end)
end

-- Revert as text, for section headings. Same wording and same click as the row
-- glyph (both go through GetRevertTooltipText / PerformSectionRevert); only the
-- shape differs, so a heading's pair of controls reads as one line.
local function WireScopeRevertAction(action, buttonData, sectionId)
    WireScopeTextHover(action, GetRevertTooltipText(sectionId))
    action:SetScript("OnClick", function()
        PerformSectionRevert(buttonData, sectionId)
    end)
end

-- Scope chrome for a section HEADING: the note says whose values the section
-- is showing, and the affordance after it is the only way to change that.
-- Returns the resolved scope for callers that also gate the section's body.
local function AttachHeadingScopeChrome(heading, lens, group, sectionId)
    local frame = heading and heading.frame
    if not frame then
        return nil
    end

    local scope, _, _, deniedReason = ResolveLensSection(lens, group, sectionId)
    HideScopeChrome(frame, HEADING_SCOPE_FIELDS)

    local attached = false

    if scope == "inherited" then
        local note = EnsureScopeText(frame, "_cdcScopeNote", false)
        SetScopeText(note, "Panel setting", SCOPE_CHROME_GREY)
        ChainHeadingBadges(heading, note)

        local action = EnsureScopeText(frame, "_cdcScopeAction", true)
        SetScopeText(action, "Customize for this entry", SCOPE_CHROME_GOLD)
        WireScopeAction(action, lens, group, sectionId)
        ChainHeadingBadges(heading, action)
        attached = true

    elseif scope == "customized" then
        local entryName = GetLensEntryName(lens)
        local note = EnsureScopeText(frame, "_cdcScopeNote", false)
        SetScopeText(note, "Customized for " .. (entryName or "this entry"), SCOPE_CHROME_GOLD)
        ChainHeadingBadges(heading, note)

        -- The note already carries the state, so the action beside it is the
        -- bare verb: "Customized for X" then "Revert", not two sentences.
        local revert = EnsureScopeText(frame, "_cdcScopeRevertText", true)
        SetScopeText(revert, "Revert", SCOPE_CHROME_GOLD)
        WireScopeRevertAction(revert, lens.buttonData, sectionId)
        ChainHeadingBadges(heading, revert)
        attached = true

    elseif scope == "denied" then
        local note = EnsureScopeText(frame, "_cdcScopeNote", false)
        SetScopeText(note, "Not available", SCOPE_CHROME_GREY)
        note:EnableMouse(true)
        note:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            AddSectionDeniedTooltipLines(deniedReason)
            GameTooltip:Show()
        end)
        note:SetScript("OnLeave", function() GameTooltip:Hide() end)
        ChainHeadingBadges(heading, note)
        attached = true

    elseif scope == "panelOnly" then
        local note = EnsureScopeText(frame, "_cdcScopeNote", false)
        SetScopeText(note, "Applies to all entries", SCOPE_CHROME_GREY)
        ChainHeadingBadges(heading, note)
        attached = true
    end

    if attached then
        -- Chain, don't replace: the collapse button, the left-aligned heading
        -- variant and ChainHeadingBadges all keep handlers here.
        local prevOnRelease = heading.events and heading.events["OnRelease"]
        heading:SetCallback("OnRelease", function(widget, event, ...)
            if prevOnRelease then
                prevOnRelease(widget, event, ...)
            end
            HideScopeChrome(frame, HEADING_SCOPE_FIELDS)
        end)
    end

    return scope
end

-- Scope chrome for a single ROW, for sections whose identity is one setting
-- rather than a whole heading. Chained through the row's badge anchor so it
-- composes with the gear and info badges instead of fighting them.
--
-- Call this AFTER the row's disabled state is set: a row greyed out by its own
-- dependency keeps that grey, and the revert glyph still shows ownership.
local function AttachRowScopeChrome(rowWidget, lens, group, sectionId)
    local frame = rowWidget and rowWidget.frame
    if not (frame and rowWidget.badgeAnchor) then
        return nil
    end

    local scope, _, _, deniedReason = ResolveLensSection(lens, group, sectionId)
    HideScopeChrome(frame, ROW_SCOPE_FIELDS)
    SetRowScopeTooltip(rowWidget, nil)

    local attached = false

    if scope == "inherited" then
        local action = EnsureScopeText(frame, "_cdcScopeRowAction", true)
        SetScopeText(action, "Customize", SCOPE_CHROME_GOLD)
        WireScopeAction(action, lens, group, sectionId,
            "Customize " .. GetOverrideSectionLabel(sectionId) .. " for this entry")
        ST._AnchorRowBadge(rowWidget, action)
        -- The grey row states WHOSE values it shows only on the CONTROL's
        -- hover; the gold affordance beside the label is the visible half of
        -- the same message.
        SetRowScopeTooltip(rowWidget, ROW_SCOPE_INHERITED_TOOLTIP)
        attached = true

    elseif scope == "customized" then
        -- Ownership is shown by Revert. Let the row own its label color so
        -- customization cannot masquerade as the disclosure's hover state.
        local revert = EnsureScopeGlyph(frame, "_cdcScopeRowRevert")
        WireRevertGlyph(revert, revert.icon, lens.buttonData, sectionId)
        ST._AnchorRowBadge(rowWidget, revert)
        attached = true

    elseif scope == "denied" then
        -- Still no BADGE on a denied row: the row is already inert-dimmed, and
        -- per-row badges read as clutter (owner ruling 2026-08-14). The reason
        -- is a hover on the CONTROL instead, so a row whose section heading is
        -- off screen can still say why it cannot be edited - and reaching for
        -- the control it cannot use is exactly when the owner asks.
        SetRowScopeTooltip(rowWidget, BuildRowDeniedScopeTooltip(deniedReason))
        attached = true

    end

    if attached then
        local prevOnRelease = rowWidget.events and rowWidget.events["OnRelease"]
        rowWidget:SetCallback("OnRelease", function(widget, event, ...)
            if prevOnRelease then
                prevOnRelease(widget, event, ...)
            end
            HideScopeChrome(frame, ROW_SCOPE_FIELDS)
            SetRowScopeTooltip(widget, nil)
        end)
    end

    return scope
end

-- Chrome for a row that stays PANEL-OWNED inside an entry-scope section: its
-- key has no override identity, so it always reads and writes the panel style,
-- and under an entry lens the grey label says so instead of the section's
-- Customize/Revert chrome. No affordance - there is nothing to promote.
local function AttachPanelSettingRowChrome(rowWidget)
    local frame = rowWidget and rowWidget.frame
    if not (frame and rowWidget.badgeAnchor) then
        return
    end

    HideScopeChrome(frame, ROW_SCOPE_FIELDS)
    -- The note is visible, so this row needs no hover explanation - but it must
    -- not keep one a previous tenant of the pooled row left behind.
    SetRowScopeTooltip(rowWidget, nil)

    local note = EnsureScopeText(frame, "_cdcScopeRowPanel", false)
    SetScopeText(note, "Panel setting", SCOPE_CHROME_GREY)
    ST._AnchorRowBadge(rowWidget, note)

    local prevOnRelease = rowWidget.events and rowWidget.events["OnRelease"]
    rowWidget:SetCallback("OnRelease", function(widget, event, ...)
        if prevOnRelease then
            prevOnRelease(widget, event, ...)
        end
        HideScopeChrome(frame, ROW_SCOPE_FIELDS)
        SetRowScopeTooltip(widget, nil)
    end)
end

------------------------------------------------------------------------
-- LENS SECTION HOST
------------------------------------------------------------------------
-- One context object owns the ritual every overridable section otherwise
-- repeats by hand: resolve the scope, pick the write-or-read table, derive the
-- disabled flag and shared-builder fallback, bracket the section's rows for
-- the inert pass, and attach scope chrome. Sections read fields and call
-- methods off the context instead of re-deriving the rules, so a convention
-- change lands here once.
--
--   local sec = ST._BeginLensSection(lens, group, "cooldownText", { column = textLeft })
--   ...rows bind tbl = sec.tbl, pass disabled = sec.disabled, guard commits
--      with `if not sec.write then return end`...
--   sec:Chrome(row)   -- row-level scope chrome, AFTER the row's disabled state is final
--   sec:Finish()      -- applies the inert bracket when the section is read-only
--
-- Field contract, all derived once at Begin:
--   scope         "panel" | "multi" | "panelOnly" | "denied" | "customized" | "inherited"
--   read / write  ResolveLensSection's tables; write == nil is the inert marker
--   tbl           write or read: the table value-displaying controls bind to.
--                 NOT for panel-only (nil sectionId) sections - their read is
--                 the detached snapshot, so writes would silently vanish;
--                 panel-only rows keep binding group.style and take only
--                 disabled/brackets from the host
--   disabled      write == nil: what row builders take as `disabled`
--   inert         the same test, named for bracket decisions
--   fallbackStyle group.style under "customized", else nil: what shared
--                 builders that layer overrides over panel values expect
--   deniedReason  ResolveLensSection's fourth return, for denial copy
--
-- A nil sectionId resolves "panelOnly" with no write table exactly under an
-- entry lens - the idiom for panel-only blocks that only need the bracket.
--
-- disabled/inert lean on group.style being non-nil in panel and multi modes
-- (a real panel always has one); a nil style would read as inert there. And
-- fallbackStyle IS group.style: sites that hand shared builders a local
-- `style` stay equivalent only while that local is the group's own style.
--
-- Brackets: passing opts.column marks it at Begin and Finish applies the inert
-- sweep to everything added since. A row that must stay live ahead of the
-- sweep is built first and the mark retaken with sec:Mark() (the foreign
-- dim-color row pattern), and a section spanning two columns takes a second
-- bracket with sec:Bracket()/sec:FinishBracket(). In practice opts.column fits
-- only sections whose column exists before Begin; heading-owning sections
-- create their columns after the chrome attaches, so they take their first
-- mark with sec:Mark() - that is the common path, not the exception.
local LensSection = {}
LensSection.__index = LensSection

-- The explicit-false rule for boolean override keys: under "customized" a
-- false must be STORED (deleting the key would fall back to the panel value
-- through the runtime __index), everywhere else false clears the key.
-- Spelled as statements: `and false or nil` collapses to nil, which is the
-- trap that kept explicit false from ever landing.
function LensSection:BoolValue(val)
    if val then
        return true
    end
    if self.scope == "customized" then
        return false
    end
    return nil
end

function LensSection:Chrome(row)
    -- The navigated-to section's anchor row (deferred highlight, see
    -- FireNavSettingHighlight): preciser than the collapsible's heading -
    -- several override sections can share one collapsible - and, unlike the
    -- advanced gear's rowKey match, present in every lens mode, including a
    -- section the entry only inherits.
    local pendingHighlight = CS.pendingSettingHighlight
    if pendingHighlight and pendingHighlight.sectionId
        and pendingHighlight.sectionId == self.sectionId
        and not pendingHighlight.sectionRowWidget then
        pendingHighlight.sectionRowWidget = row
    end
    return AttachRowScopeChrome(row, self.lens, self.group, self.sectionId)
end

-- Make an inherited color swatch direct-manipulable without enabling the
-- underlying inert ColorPicker. Promotion still owns the whole override
-- section; this is only a second entrance to the same Customize action.
function LensSection:DirectColorControl(row, key, externallyDisabled)
    if not (row and key) then return end

    if row.SetScopeControlAction then
        row:SetScopeControlAction(nil)
    end

    local pending = pendingInheritedColorOpen
    local contextMatches = pending
        and pending.group == self.group
        and pending.buttonData == (self.lens and self.lens.buttonData)
        and pending.groupId == CS.selectedGroup
        and pending.buttonIndex == CS.selectedButton
        and pending.sectionId == self.sectionId
        and pending.key == key

    if contextMatches and self.scope == "customized" then
        pendingInheritedColorOpen = nil
        local picker = row.colorPicker
        C_Timer.After(0, function()
            if CS.selectedGroup == pending.groupId
                and CS.selectedButton == pending.buttonIndex
                and self.lens and self.lens.buttonData == pending.buttonData
                and row.colorPicker == picker
                and row.disabled ~= true
                and picker and picker.frame and picker.frame:IsShown()
            then
                picker.frame:Click()
            end
        end)
    elseif pending and pending.sectionId == self.sectionId and pending.key == key then
        -- A rebuild landed on a different selection or scope. Never let its
        -- delayed action leak onto a later pooled row with the same setting.
        pendingInheritedColorOpen = nil
    end

    if self.scope ~= "inherited" or externallyDisabled
        or not row.SetScopeControlAction or not row.SetScopeTooltip then
        return
    end

    local expectedGroupId = CS.selectedGroup
    local expectedButtonIndex = self.lens and self.lens.buttonIndex
    row:SetScopeTooltip(INHERITED_COLOR_CONTROL_TOOLTIP)
    row:SetScopeControlAction(function(_, mouseButton)
        if mouseButton and mouseButton ~= "LeftButton" then return end
        if not (self.lens and self.lens.buttonData)
            or CS.selectedGroup ~= expectedGroupId
            or CS.selectedButton ~= expectedButtonIndex
        then
            return
        end

        local request = {
            group = self.group,
            buttonData = self.lens.buttonData,
            groupId = expectedGroupId,
            buttonIndex = expectedButtonIndex,
            sectionId = self.sectionId,
            key = key,
        }
        pendingInheritedColorOpen = request
        PromoteLensSection(self.lens, self.group, self.sectionId)
        if pendingInheritedColorOpen == request then
            pendingInheritedColorOpen = nil
        end
    end)
end

function LensSection:HeadingChrome(heading)
    return AttachHeadingScopeChrome(heading, self.lens, self.group, self.sectionId)
end

-- Chrome for a panel-owned row inside this section (see
-- AttachPanelSettingRowChrome): label only, and only under an entry lens.
function LensSection:PanelRowChrome(row)
    if self.lens and self.lens.mode == "entry" then
        AttachPanelSettingRowChrome(row)
    end
end

-- Take (or retake) the primary bracket mark. Heading-owning sections take
-- their FIRST mark here - their columns do not exist until after the heading
-- chrome attaches - and the dim-color pattern retakes it so rows already in
-- the column stay live.
function LensSection:Mark(column)
    self.column = column or self.column
    self.mark = MarkInertRange(self.column)
end

-- A second, independent bracket for sections spanning more than one column.
function LensSection:Bracket(column)
    return { column = column, mark = MarkInertRange(column) }
end

function LensSection:FinishBracket(bracket)
    if self.inert and bracket and bracket.column then
        ApplyInertRange(bracket.column, bracket.mark)
    end
end

function LensSection:Finish()
    if self.inert and self.column then
        ApplyInertRange(self.column, self.mark)
    end
end

local function BeginLensSection(lens, group, sectionId, opts)
    local scope, read, write, deniedReason = ResolveLensSection(lens, group, sectionId)
    local sec = setmetatable({
        lens = lens,
        group = group,
        sectionId = sectionId,
        scope = scope,
        read = read,
        write = write,
        deniedReason = deniedReason,
        tbl = write or read,
        disabled = write == nil,
        inert = write == nil,
        fallbackStyle = (scope == "customized") and group and group.style or nil,
    }, LensSection)

    local column = opts and opts.column
    if column then
        sec.column = column
        sec.mark = MarkInertRange(column)
    end
    return sec
end

------------------------------------------------------------------------
-- LENS NAVIGATION CHROME
------------------------------------------------------------------------

-- THE one decision point for which collapse key a section uses under the
-- current lens. Every navigation and section-building caller must route its
-- collapse key through here rather than testing the lens itself, so "which
-- sections open by default for this selection" has a single owner.
--
-- Sections an entry cannot edit ("panelOnly", "denied") are noise in an entry
-- lens, so they get their OWN key and open COLLAPSED the first time that key is
-- seen. The key is per SECTION, never per entry: collapsing one entry's inert
-- sections collapses them for the next entry too, which is the point - the
-- owner is expressing "hide what I cannot edit here", not a per-entry state.
-- Everything else keeps its base key, so a section's normal collapse state
-- survives selecting an entry and coming back.
--
-- Seeding writes to CS.collapsedSections, the store BuildCollapsibleSection
-- defaults to (truthy = collapsed). Lens sections must use that default store;
-- a caller with its own store would seed the wrong table.
local function ResolveLensCollapseKey(lens, group, sectionId, baseKey, opts)
    if not baseKey or not (lens and lens.mode == "entry") then
        return baseKey
    end

    local scope = ResolveLensSection(lens, group, sectionId)
    if scope ~= "panelOnly" and scope ~= "denied" then
        return baseKey
    end

    -- A panel-only collapsible can HOST an override section (Icon Settings
    -- hosts Icon Zoom). While the entry has CUSTOMIZED a hosted section it has
    -- live business inside, so the fold-by-default gives way (owner ruling
    -- 2026-08-14); an inherited hosted section stays behind the fold with its
    -- Customize one click away.
    local hosts = opts and opts.hostsSections
    if hosts then
        for i = 1, #hosts do
            if ResolveLensSection(lens, group, hosts[i]) == "customized" then
                return baseKey
            end
        end
    end

    local lensKey = "lens_" .. baseKey
    local store = CS.collapsedSections
    -- nil means never seen, which is exactly what the default-collapsed seed
    -- must not overwrite once the owner has expanded it (false is stored).
    if store and store[lensKey] == nil then
        store[lensKey] = true
    end
    return lensKey
end

-- One grey line at the top of a styling tab when several entries are selected.
-- The tabs edit the PANEL under a multi selection, and nothing else on the
-- surface says so: the per-section scope chrome only speaks under an entry
-- lens. Any other lens mode draws nothing.
--
-- includeEntryLens widens the note to a single-entry lens as well. The Layout
-- tab is the one caller: it has no per-entry sections, so it never grows the
-- scope chrome that tells the other tabs' story, and this line is the only
-- thing saying its edits land on the panel while an entry sits selected.
--
-- A plain AceGUI Label, the shape every other single-line note in the config
-- uses. Its stock font is already the small one the scope chrome wears, so
-- only the colour is set.
local function AddLensPanelScopeNote(container, lens, includeEntryLens)
    local mode = lens and lens.mode
    local speaks = mode == "multi" or (includeEntryLens and mode == "entry")
    if not (container and speaks) then
        return nil
    end

    local note = AceGUI:Create("Label")
    if ST._ConfigureWrappedHelperLabel then
        ST._ConfigureWrappedHelperLabel(note)
    end
    note:SetFullWidth(true)
    note:SetText("Editing panel settings. Changes apply to every entry.")
    note:SetColor(SCOPE_CHROME_GREY[1], SCOPE_CHROME_GREY[2], SCOPE_CHROME_GREY[3])
    container:AddChild(note)
    return note
end

ST._CanButtonUseConfigOverrideSection = CanButtonUseConfigOverrideSection
ST._GroupSupportsPerButtonOverrides = GroupSupportsPerButtonOverrides
ST._ResolveStyleLens = ResolveStyleLens
ST._ResolveLensSection = ResolveLensSection
ST._PromoteLensSection = PromoteLensSection
ST._ResolveAdvancedUnlock = ResolveAdvancedUnlock
ST._BuildAdvancedUnlockStrip = BuildAdvancedUnlockStrip
ST._MakeAdvancedPanelReadOnly = MakeAdvancedPanelReadOnly
ST._BeginLensSection = BeginLensSection
ST._ResolveLensCollapseKey = ResolveLensCollapseKey
ST._AddLensPanelScopeNote = AddLensPanelScopeNote
-- The text Format tab writes its own scope note (its field lives outside the
-- section machinery), so it borrows the NAME the chrome would have shown
-- rather than re-deriving one and truncating it differently.
ST._GetLensEntryName = GetLensEntryName
ST._GroupHasAuraTrackingEntry = GroupHasAuraTrackingEntry

-- Private helpers consumed by later Helpers files.
SH.GetSectionDenialClause = GetSectionDenialClause
SH.SCOPE_CHROME_HEIGHT = SCOPE_CHROME_HEIGHT
SH.GetOverrideSectionLabel = GetOverrideSectionLabel
SH.EnsureScopeText = EnsureScopeText
SH.SetScopeText = SetScopeText
SH.SCOPE_CHROME_GOLD = SCOPE_CHROME_GOLD
SH.WireScopeTextHover = WireScopeTextHover
SH.HideScopeChrome = HideScopeChrome
SH.EnsureScopeGlyph = EnsureScopeGlyph
SH.ApplyRevertGlyphLook = ApplyRevertGlyphLook
SH.BindRevertGlyph = BindRevertGlyph
SH.GetRevertTooltipTextForLabel = GetRevertTooltipTextForLabel
SH.WireRevertGlyph = WireRevertGlyph
