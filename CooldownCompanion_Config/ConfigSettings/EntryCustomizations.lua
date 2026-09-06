--[[
    CooldownCompanion - EntryCustomizations
    Entry customization summaries, destination links, and revert actions.

    Part of the Helpers family; see its ordered block in the addon TOC.
    Private helpers are shared through ST._SettingsHelpers.
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon
local CS = ST._configState

local SH = ST._SettingsHelpers

-- StyleLens.lua
local GetSectionDenialClause = SH.GetSectionDenialClause
local SCOPE_CHROME_HEIGHT = SH.SCOPE_CHROME_HEIGHT
local ResolveStyleLens = ST._ResolveStyleLens
local CanButtonUseConfigOverrideSection = ST._CanButtonUseConfigOverrideSection
local GetOverrideSectionLabel = SH.GetOverrideSectionLabel
local EnsureScopeText = SH.EnsureScopeText
local SetScopeText = SH.SetScopeText
local SCOPE_CHROME_GOLD = SH.SCOPE_CHROME_GOLD
local WireScopeTextHover = SH.WireScopeTextHover
local HideScopeChrome = SH.HideScopeChrome
local EnsureScopeGlyph = SH.EnsureScopeGlyph
local ApplyRevertGlyphLook = SH.ApplyRevertGlyphLook
local BindRevertGlyph = SH.BindRevertGlyph
local GetRevertTooltipTextForLabel = SH.GetRevertTooltipTextForLabel
local WireRevertGlyph = SH.WireRevertGlyph

-- Helpers.lua
local ADVANCED_TOGGLE_ATLAS = SH.ADVANCED_TOGGLE_ATLAS
local ADVANCED_TOGGLE_IDLE_COLOR = SH.ADVANCED_TOGGLE_IDLE_COLOR
local BuildCollapsibleSection = ST._BuildCollapsibleSection
local ChainHeadingBadges = ST._ChainHeadingBadges
local CreateInfoButton = ST._CreateInfoButton
local ADVANCED_TOGGLE_OPEN_TOOLTIP = SH.ADVANCED_TOGGLE_OPEN_TOOLTIP

------------------------------------------------------------------------
-- CUSTOMIZATIONS (entry Settings pane)
--
-- The one actionable index of everything this entry customizes. The styling
-- tabs chrome a customization IN PLACE, but only where they draw it: a section
-- belongs to one display mode's tabs, and a section the entry can no longer use
-- resolves "denied" with no revert at all. The saved keys survive either state
-- on purpose - they apply again when the block lifts - so a list that only
-- showed the unreachable ones answered "how do I undo this?" for the hard cases
-- and stayed silent for the easy ones.
--
-- So the list shows them ALL (owner ruling 2026-08-14, superseding the earlier
-- inactive-only list): active ones plain, inactive ones carrying the same
-- denial clause the scope chrome uses, each with its own revert, the name a
-- link to where the section is edited, and one Revert All on the heading.
-- Built only while at least one customization exists.
------------------------------------------------------------------------

-- One list for both frames the chrome lands on: a heading frame has no row
-- field and a row frame has no heading field, so HideScopeChrome skipping the
-- absent ones costs a nil read and removes a second constant.
local CUSTOMIZATIONS_CHROME_FIELDS = {
    "_cdcCustomizationsRevertAll",
    "_cdcCustomizationsRevert",
    "_cdcCustomizationsGear",
    "_cdcCustomizationsName",
}

-- The per-entry text format is a FLAT field (buttonData.textFormat) outside the
-- styleOverrides section machinery, so it has no section id, no label of its
-- own, and no home in ST._SECTION_HOME. It is still a customization, and the
-- one index of them cannot be the surface that forgets it.
--
-- Named for the THING, not its state: inside a section titled Customizations
-- every row is already custom. Word-for-word what the entry-slot hover tooltip
-- (ButtonPanelPreview) calls the same field, because Defaults.lua contracts
-- these two surfaces to never list a customization differently.
local FORMAT_ROW_LABEL = "Text Format"

local CUSTOMIZATIONS_TOOLTIP = {
    "Customizations",
    {"Everything this entry has its own settings for.", 1, 1, 1, true},
    " ",
    {"Click a name to open where it is edited.", 1, 1, 1, true},
    " ",
    {"Inactive ones stay saved and apply again when whatever blocks them changes.", 1, 1, 1, true},
}

-- This list's framing around the single-sourced denial clause (see
-- SECTION_DENIAL_CLAUSES above - never word a denial here directly).
local function GetInactiveCustomizationReason(reason)
    return "Saved for this entry, but inactive: " .. GetSectionDenialClause(reason) .. "."
end

-- Where this section is EDITED in the panel's display mode. Read straight off
-- the registry the tab builders state (ST._SECTION_HOME), because the answer is
-- only needed to decide whether the row's name is a link at all; the navigation
-- itself belongs to PreviewCommandCenter's route core and is never rebuilt here.
-- A mode with no home for the section (another mode's section, a trigger panel,
-- the rotation assistant) answers nil and the name stays plain text.
--
-- The WHOLE entry, not just its tab: the home also carries the optional
-- availability predicates the two helpers below consult (contract stated at the
-- first registration, ST._SECTION_HOME.bars in BarModeTabs.lua).
local function GetSectionHome(displayMode, sectionId)
    local homes = ST._SECTION_HOME
    local byMode = homes and homes[displayMode]
    return byMode and byMode[sectionId] or nil
end

-- Sections are drawn CONDITIONALLY. A bar panel with the icon hidden draws no
-- Icon Tint and no Timers/States block at all; the aura sections exist only
-- while the group tracks an aura. A name link into a section that is not there
-- lands on a tab where nothing answers the click, so the list asks the home
-- first. A section whose home registers no predicate is always drawn.
-- The panel-wide answer comes FIRST and needs no per-section registration: an
-- Aura Panel's tabs leave the sections its pure-aura entries can never use out
-- entirely rather than drawing them denied, so there is no row left for a name
-- link to land on. Every one of those gates cites ST.CanGroupUseOverrideSection,
-- so asking it here covers them all at once and cannot drift from them.
local function IsSectionHomeAvailable(home, group, style, sectionId)
    if sectionId and not ST.CanGroupUseOverrideSection(group, sectionId) then
        return false
    end
    local available = home and home.available
    if not available then
        return true
    end
    return available(group, style) and true or false
end

-- Same question for the section's advanced GEAR, whose surviving gates are
-- STRUCTURAL only (the Masque and fill-timer interlocks): parent toggles no
-- longer hide gears - an off toggle's gear opens its panel read-only behind
-- the Turn On footer. A queued advanced key with no gear left to consume it
-- would open a panel behind a gear that is not on screen, which is why the
-- structural gates still gate the list glyph too.
local function IsSectionHomeGearBuilt(home, group, style)
    local gearEnabled = home and home.gearEnabled
    if not gearEnabled then
        return true
    end
    return gearEnabled(group, style) and true or false
end

-- Which advanced GEAR a section owns in the panel's display mode, inverted from
-- the per-mode maps the tab builders state (those are keyed advancedKey ->
-- sectionId; this list wants the other direction).
--
-- The maps are named, not referenced: every file that declares one loads AFTER
-- this one (the .toc), so they are fetched off ST at build time, exactly as
-- ST._SECTION_HOME is above.
--
-- A mode's sources are EXACTLY the maps that mode's own builders declare, so
-- this list can never offer a gear the mode does not draw. Icons builds both
-- the Appearance and Indicators tabs off both maps; bars builds
-- its two tabs off the one bars map (its pandemic, unusable and tooltip gears
-- are listed there, so the indicators map is not a bars source); text's map is
-- deliberately empty today. Textures has no override sections at all, so it has
-- no entry and no row here ever resolves a gear.
local CUSTOMIZATIONS_GEAR_MAPS_BY_MODE = {
    icons = { "_APPEARANCE_SECTION_BY_ADVANCED_KEY", "_INDICATORS_OVERRIDE_SECTION_BY_ADVANCED_KEY" },
    bars = { "_BARMODE_SECTION_BY_ADVANCED_KEY" },
    text = { "_TEXTMODE_SECTION_BY_ADVANCED_KEY" },
}

-- A section with TWO OR MORE gears in one mode gets NO gear on its row. Pandemic
-- is the live case: the glow and the marker are two advanced panels under one
-- override section. Two gears on one list row is clutter, and silently picking
-- either one would misstate where the click lands - the name link already opens
-- the section with both gears in view, which is the honest answer.
--
-- A sentinel rather than a delete, so a third key arriving later cannot re-claim
-- the row the first pair disqualified.
local CUSTOMIZATIONS_GEAR_AMBIGUOUS = {}

local function BuildCustomizationsGearMap(displayMode)
    local sources = CUSTOMIZATIONS_GEAR_MAPS_BY_MODE[displayMode]
    if not sources then
        return nil
    end

    local bySection
    for i = 1, #sources do
        local map = ST[sources[i]]
        if map then
            for advancedKey, sectionId in pairs(map) do
                bySection = bySection or {}
                local current = bySection[sectionId]
                if current == nil then
                    bySection[sectionId] = advancedKey
                elseif current ~= advancedKey then
                    bySection[sectionId] = CUSTOMIZATIONS_GEAR_AMBIGUOUS
                end
            end
        end
    end
    return bySection
end

-- The list gear wears the settings-side gear's LOOK (AddAdvancedToggle's atlas,
-- icon size and idle tint) on the scope chrome's 16px glyph hit area, so it sits
-- in a row's badge chain beside the revert glyph rather than at the gear's own
-- 14px settings size.
--
-- Only the look and the panel QUEUE are shared with that gear. This one has no
-- live panel binding: it never goes gold, never rebinds a descriptor and never
-- toggles a panel shut. It is a link that happens to end in a panel.
local ADVANCED_GLYPH_ICON_SIZE = 13

local function ApplyAdvancedGlyphLook(icon)
    icon:SetSize(ADVANCED_GLYPH_ICON_SIZE, ADVANCED_GLYPH_ICON_SIZE)
    icon:ClearAllPoints()
    icon:SetPoint("CENTER")
    icon:SetAtlas(ADVANCED_TOGGLE_ATLAS, false)
    icon:SetVertexColor(ADVANCED_TOGGLE_IDLE_COLOR[1], ADVANCED_TOGGLE_IDLE_COLOR[2],
        ADVANCED_TOGGLE_IDLE_COLOR[3], ADVANCED_TOGGLE_IDLE_COLOR[4])
end

-- The row NAME as a link: a transparent hit area pinned over the label's text,
-- carrying the row's OWN FontString as its `text` so the scope chrome's
-- hover-brighten (WireScopeTextHover) works on the real label rather than a
-- second string laid over it.
--
-- Cached on the row FRAME like every other piece of chrome, and permanently
-- paired with that frame's label (BuildRowBase creates both, and neither
-- outlives the other), so the stored reference can never name another row's
-- text. The width is re-measured per build because the label is set per build.
local function EnsureRowNameButton(row, field)
    local frame = row.frame
    local btn = frame[field]
    if not btn then
        btn = CreateFrame("Button", nil, frame)
        btn:SetHeight(SCOPE_CHROME_HEIGHT)
        btn.text = row.rowLabel
        frame[field] = btn
    end

    btn:SetParent(frame)
    btn:ClearAllPoints()
    btn:SetPoint("LEFT", row.rowLabel, "LEFT", 0, 0)
    btn:SetWidth(math.max(row.rowLabel:GetStringWidth(), 1))
    btn:EnableMouse(true)
    btn:Enable()
    btn:SetScript("OnEnter", nil)
    btn:SetScript("OnLeave", nil)
    btn:SetScript("OnClick", nil)
    btn:Show()
    return btn
end

-- Clearing the entry's text format. Same two refreshes the Format tab's own
-- "Revert to Panel Format" makes, minus its CancelTextFormatTabCommit: a
-- debounced format write cannot be pending while this list is on screen. The
-- format editor is torn down at every seam that takes its container away, and
-- selecting the entry Settings tab is one of them - Panel.lua's entry TabGroup
-- calls ST._ReleaseTextFormatTabEditor before it builds anything, which flushes
-- the pending write and drops the timer. No guard, because there is nothing
-- reachable to guard against.
local function PerformFormatRevert(buttonData)
    buttonData.textFormat = nil
    CooldownCompanion:RefreshGroupFrame(CS.selectedGroup)
    CooldownCompanion:RefreshConfigPanel()
end

-- Every customization on one entry, in one pass. Deliberately NOT a loop over
-- PerformSectionRevert: that helper ends in UpdateGroupStyle plus a full config
-- rebuild, and paying for both once per section would rebuild the pane N times
-- to arrive exactly where one rebuild lands.
--
-- Resolved from ids rather than handed live tables: this runs behind a confirm
-- popup, and the entry it names can be gone by the time the click comes back.
local function RevertAllEntryCustomizations(groupId, buttonIndex)
    local profile = CooldownCompanion.db and CooldownCompanion.db.profile
    local group = profile and profile.groups and profile.groups[groupId]
    local buttonData = group and group.buttons and group.buttons[buttonIndex]
    if not buttonData then
        return
    end

    local sections = buttonData.overrideSections
    if sections then
        -- RevertSection clears keys out of this same table, so the local stays
        -- in step with it even on the call that empties it and detaches it from
        -- the entry.
        for _, sectionId in ipairs(ST.OVERRIDE_SECTION_ORDER or {}) do
            if sections[sectionId] then
                CooldownCompanion:RevertSection(buttonData, sectionId)
            end
        end
    end

    -- Gated on being SET, which is the same gate the list draws the row on, so
    -- Revert All clears exactly the rows it was shown beside - including a
    -- format stranded on a panel that is no longer a text panel, which the list
    -- shows as inactive rather than hiding.
    local formatCleared = false
    if buttonData.textFormat ~= nil then
        buttonData.textFormat = nil
        formatCleared = true
    end

    CooldownCompanion:UpdateGroupStyle(groupId)
    -- The format is re-parsed on the way through PopulateGroupButtons, which
    -- only the frame refresh reaches. Paid once, and only when a format was
    -- actually cleared.
    if formatCleared then
        CooldownCompanion:RefreshGroupFrame(groupId)
    end
    CooldownCompanion:RefreshConfigPanel()
end

local function BuildCustomizationsSection(scroll, group, buttonData, infoButtons)
    if not (group and buttonData) then
        return
    end

    -- Collect first, build second: the heading only exists when a row does.
    -- Same order and gates the entry-slot hover tooltip uses for these
    -- sections, so the two surfaces can never list them differently.
    local displayMode = group.displayMode or "icons"
    local sections = buttonData.overrideSections
    local items = {}

    -- The style the section homes' availability predicates are asked about.
    -- This list is built with exactly ONE entry selected, so the lens resolves
    -- "entry" and hands over the detached effective style - the same table a
    -- builder's `sec.read` resolves to there, which is what those predicates
    -- mirror. The fallback is the panel style for the same reason: under any
    -- other lens that is what the builders' gates read.
    local lens = ResolveStyleLens(group)
    local predicateStyle = (lens and lens.mode == "entry" and lens.effective) or group.style or {}

    -- Leads the list: the format is what a text entry IS, so its customization
    -- reads first rather than under the style sections.
    --
    -- A saved format on a panel that is no longer a text panel is stranded, not
    -- gone - the same "saved but unreachable" state the sections have - so it
    -- takes the same inactive shape: the displayMode clause, its own revert, and
    -- NO name link, because the Format tab it would open only exists in text
    -- mode (tab = nil is what drives that, exactly as it does for a section
    -- with no home in this mode).
    if buttonData.textFormat ~= nil then
        local textMode = displayMode == "text"
        items[#items + 1] = {
            format = true,
            label = FORMAT_ROW_LABEL,
            reason = (not textMode) and "displayMode" or nil,
            tab = textMode and "format" or nil,
        }
    end

    if sections then
        for _, sectionId in ipairs(ST.OVERRIDE_SECTION_ORDER or {}) do
            if sections[sectionId] then
                local sectionDef = ST.OVERRIDE_SECTIONS[sectionId]
                local allowed, deniedReason = CanButtonUseConfigOverrideSection(buttonData, sectionId, group)
                local modeOk = sectionDef and sectionDef.modes and sectionDef.modes[displayMode] == true
                local reason
                if not allowed then
                    reason = deniedReason or "entryType"
                elseif not modeOk then
                    reason = "displayMode"
                end
                local home = GetSectionHome(displayMode, sectionId)
                items[#items + 1] = {
                    sectionId = sectionId,
                    label = GetOverrideSectionLabel(sectionId),
                    reason = reason,
                    home = home,
                    tab = home and home.tab or nil,
                }
            end
        end
    end

    if #items == 0 then
        return
    end

    local heading, collapsed = BuildCollapsibleSection(scroll, "Customizations",
        CS.selectedGroup .. "_" .. CS.selectedButton .. "_customizations",
        nil, nil, { leftAligned = true })
    ChainHeadingBadges(heading, CreateInfoButton(heading.frame, heading.label,
        "LEFT", "RIGHT", 4, 0, CUSTOMIZATIONS_TOOLTIP, infoButtons))

    -- Heading-level action in the scope chrome's own shape: gold text that
    -- brightens on hover, beside the thing it acts on. Behind a confirm popup
    -- because it is the one control here that cannot be undone one row at a
    -- time. Attached whether or not the section is collapsed - the whole point
    -- of a folded list is still being able to empty it.
    local groupId, buttonIndex = CS.selectedGroup, CS.selectedButton
    local headingFrame = heading.frame
    local revertAll = EnsureScopeText(headingFrame, "_cdcCustomizationsRevertAll", true)
    SetScopeText(revertAll, "Revert All", SCOPE_CHROME_GOLD)
    WireScopeTextHover(revertAll, "Revert every customization on this entry")
    revertAll:SetScript("OnClick", function()
        local entryName = ST._GetConfigEntryDisplayName
            and ST._GetConfigEntryDisplayName(buttonData)
            or buttonData.name
        -- Through the house raiser, not StaticPopup_Show: the config window
        -- sits high enough to cover a stock dialog.
        local showPopup = ST._ShowPopupAboveConfig
        if showPopup then
            showPopup("CDC_REVERT_ENTRY_CUSTOMIZATIONS", entryName or "this entry",
                { groupId = groupId, buttonIndex = buttonIndex })
        end
    end)
    ChainHeadingBadges(heading, revertAll)

    -- Chain, don't replace: BuildCollapsibleSection installs its own handler.
    local prevHeadingRelease = heading.events and heading.events["OnRelease"]
    heading:SetCallback("OnRelease", function(widget, event, ...)
        if prevHeadingRelease then
            prevHeadingRelease(widget, event, ...)
        end
        HideScopeChrome(headingFrame, CUSTOMIZATIONS_CHROME_FIELDS)
    end)

    if collapsed then
        return
    end

    -- Row-grammar label rows in the grid's left column, so the list keeps the
    -- config's half-width cell instead of stretching across the pane. The
    -- revert glyph rides the label's badge chain; the reason is the row's
    -- hover tooltip. Read at call time, not load time: RowWidgets and Helpers
    -- have no load-order contract between them.
    local AddLabelRow = ST._AddLabelRow
    local AnchorRowBadge = ST._AnchorRowBadge
    local listLeft = ST._BeginRowGrid(scroll)
    -- Built once for the whole list: the mode is fixed for this pane, and the
    -- inversion walks every gear map the mode owns.
    local gearBySection = BuildCustomizationsGearMap(displayMode)

    for _, item in ipairs(items) do
        local label = item.label
        local reasonText = item.reason and GetInactiveCustomizationReason(item.reason) or nil
        local row = AddLabelRow(listLeft, {
            label = label,
            -- Active rows say nothing in the control column: the section is
            -- listed here, which already means it is customized. Only the
            -- inactive ones have news.
            controlText = item.reason and "Inactive" or nil,
            tooltip = reasonText and { label, {reasonText, 1, 1, 1, true} } or nil,
        })

        -- Every piece of chrome is cached on the row's FRAME (the pool recycles
        -- frames), re-wired per build, and hidden on release so a recycled row
        -- never wears a previous tenant's revert or link.
        local frame = row.frame

        -- Read before the badges so the gear can require it: a gear whose
        -- section has no home in this mode - or whose home is not DRAWN for
        -- this group and this entry - would navigate nowhere. An unavailable
        -- row keeps everything else it had: its revert, and its inactive clause
        -- when it has one. Only the link goes.
        local navigable = item.tab ~= nil
            and IsSectionHomeAvailable(item.home, group, predicateStyle, item.sectionId)

        -- ADVANCED GEAR (owner ruling 2026-08-14): a row whose section has an
        -- advanced panel carries the gear too, so the list is one click from the
        -- deep settings rather than a stop on the way to them.
        --
        -- ACTIVE rows only, and never the Text Format row. An inactive section
        -- is not drawn anywhere in this mode, so the tab it would land on builds
        -- no gear to consume the queue and the panel would never open; the
        -- format row is a flat field with no section and no advanced panel at
        -- all. Both fall out of the gates below rather than being special-cased.
        --
        -- The gear ALSO has to exist at the destination: a structural gate
        -- (Masque, the fill-timer interlock) can leave a drawn section with no
        -- gear, and the queue is consumed before that gate runs, so a panel
        -- would open behind a gear that is not on screen. Parent toggles no
        -- longer unbuild gears - an off toggle's gear opens read-only.
        local advancedKey
        if navigable and not item.reason and item.sectionId and gearBySection
            and IsSectionHomeGearBuilt(item.home, group, predicateStyle) then
            advancedKey = gearBySection[item.sectionId]
            if advancedKey == CUSTOMIZATIONS_GEAR_AMBIGUOUS then
                advancedKey = nil
            end
        end

        -- Anchored FIRST, so the chain reads [name][gear][revert]. That is the
        -- row grammar's own order (RowWidgets' AnchorRowBadge: gear, then info,
        -- then scope chrome), and the revert is scope chrome.
        if advancedKey then
            local gear = EnsureScopeGlyph(frame, "_cdcCustomizationsGear")
            ApplyAdvancedGlyphLook(gear.icon)
            gear:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:AddLine(ADVANCED_TOGGLE_OPEN_TOOLTIP)
                GameTooltip:Show()
            end)
            gear:SetScript("OnLeave", function() GameTooltip:Hide() end)
            -- Same route the name link takes, plus the key: the destination is
            -- resolved by PreviewCommandCenter from the section registry, and
            -- the panel is queued there after every navigation write.
            local gearSectionId = item.sectionId
            gear:SetScript("OnClick", function()
                local navigate = ST._NavigateToSectionHome
                if navigate then
                    navigate(gearSectionId, { advancedKey = advancedKey })
                end
            end)
            AnchorRowBadge(row, gear)
        end

        local revert = EnsureScopeGlyph(frame, "_cdcCustomizationsRevert")
        if item.format then
            ApplyRevertGlyphLook(revert.icon)
            BindRevertGlyph(revert, GetRevertTooltipTextForLabel(label), function()
                PerformFormatRevert(buttonData)
            end)
        else
            WireRevertGlyph(revert, revert.icon, buttonData, item.sectionId)
        end
        AnchorRowBadge(row, revert)

        -- The name becomes a link only where there is somewhere to go. Gold
        -- identifies these navigation links in the Customizations list.
        if navigable then
            row.rowLabel:SetTextColor(SCOPE_CHROME_GOLD[1], SCOPE_CHROME_GOLD[2], SCOPE_CHROME_GOLD[3])
            local nav = EnsureRowNameButton(row, "_cdcCustomizationsName")
            -- The link covers the label, so the row frame's own hover no longer
            -- fires there; the clause rides the link's tooltip so an inactive
            -- row still explains itself under the pointer.
            WireScopeTextHover(nav, reasonText)
            -- The route resolves the destination itself, from the same
            -- registry consulted above; the format row has no section and
            -- names its tab instead.
            local sectionId, formatRow = item.sectionId, item.format
            nav:SetScript("OnClick", function()
                local navigate = ST._NavigateToSectionHome
                if navigate then
                    navigate(sectionId, formatRow and { tab = "format" } or nil)
                end
            end)
        end

        local prevOnRelease = row.events and row.events["OnRelease"]
        row:SetCallback("OnRelease", function(widget, event, ...)
            if prevOnRelease then
                prevOnRelease(widget, event, ...)
            end
            HideScopeChrome(frame, CUSTOMIZATIONS_CHROME_FIELDS)
            if navigable then
                -- Hand the label colour back to the row: SetIndent re-derives
                -- it from the row's own disabled/indented state. The row's
                -- OnAcquire does this again on reuse; this just does not wait.
                if widget.SetIndent then
                    widget:SetIndent(widget.indented)
                end
            end
        end)
    end
end

ST._BuildCustomizationsSection = BuildCustomizationsSection
-- Reached from the confirm popup (Config/Popups.lua), not from a builder.
ST._RevertAllEntryCustomizations = RevertAllEntryCustomizations
