--[[
    CooldownCompanion - SpellbookPanel
    A side window listing the player's learned spells, attached to the right
    edge of the config panel, so a spell can be dragged onto a Navigator row or
    the live preview without leaving the config for Blizzard's spellbook.

    The rows are raw pooled frames on a persistent host rather than AceGUI
    children: the window itself is a stock AceGUI "Window" so UI skins style
    its chrome, but a released Window frame goes back to the widget pool, so the
    host is detached on close and re-parented on open.

    The list covers everything a panel can hold: the learned spells of the
    active spec, the pet bank, flyout contents flattened in place, and an
    unavailable section for off-spec and not-yet-learned spells. Unavailable
    rows cannot be dragged -- Blizzard's own pickup no-ops for them -- so they
    add to the selected panel on click instead.
]]

local ADDON_NAME, ST = ...
local AceGUI = LibStub("AceGUI-3.0")
local CS = ST._configState

local WINDOW_WIDTH = 360
local WINDOW_GAP = 4
local CONTENT_INSET = 2
local HINT_GAP = 5
-- The stock AceGUI EditBox's own label-less height (its SetLabel("") branch),
-- restated here because a parked widget frame is sized by us, not by a layout.
local SEARCH_HEIGHT = 26
local SEARCH_GAP = 6
-- Taller than the label needs: the extra lands ABOVE the text, because the
-- label is pinned to the header's bottom edge, so sections do not butt together.
local HEADER_HEIGHT = 28
-- The label's lift off the header's bottom edge. With the 12px title font in a
-- 28px band this leaves the same 8px of air above and below the text, which is
-- what keeps a section title from crowding the first row under it.
local HEADER_LABEL_Y = 8
local HEADER_RULE_GAP = 8
local HEADER_RULE_HEIGHT = 1
local HEADER_RULE_ALPHA = 0.35
local HEADER_RULE_INSET = 3
-- Where the rule sits above the label's bottom edge: the label's optical middle.
local HEADER_RULE_Y = 6
local ROW_HEIGHT = 22
local ICON_SIZE = 20
local TEXT_GAP = 6
local WHEEL_ROWS = 3

local PLAYER_BANK = Enum.SpellBookSpellBank.Player
local PET_BANK = Enum.SpellBookSpellBank.Pet
local SPELL_ITEM_TYPE = Enum.SpellBookItemType.Spell
local FUTURE_SPELL_ITEM_TYPE = Enum.SpellBookItemType.FutureSpell
local PET_ACTION_ITEM_TYPE = Enum.SpellBookItemType.PetAction
local FLYOUT_ITEM_TYPE = Enum.SpellBookItemType.Flyout
local GENERAL_SKILL_LINE = Enum.SpellBookSkillLineIndex.General
local CLASS_SKILL_LINE = Enum.SpellBookSkillLineIndex.Class
local MAIN_SPEC_SKILL_LINE = Enum.SpellBookSkillLineIndex.MainSpec

local UNAVAILABLE_HEADER = "Unavailable (double-click to add)"
local NOT_LEARNED_REASON = "Not learned"
local DIM_TEXT = { 0.5, 0.5, 0.5 }
local NAME_TEXT = { 1, 1, 1 }
-- Stand-in for the class colour: GetClassColor MayReturnNothing, and gold is
-- what the config's headings fall back to everywhere else.
local HEADER_TEXT = { 1, 0.82, 0 }
local DIM_HEADER_TEXT = { 0.6, 0.6, 0.6 }

-- Blizzard registers these only while its own book is visible; so do we.
local REFRESH_EVENTS = { "SPELLS_CHANGED", "LEARNED_SPELL_IN_SKILL_LINE" }

local window
local chrome
local eventFrame
local searchText = ""
local suppressSearchChanged = false
local rowPool, activeRows = {}, {}
local headerPool, activeHeaders = {}, {}

local RebuildList

------------------------------------------------------------------------
-- List contents
------------------------------------------------------------------------

local function SetListScroll(offset)
    if not chrome then
        return
    end
    local maxScroll = math.max(0,
        (chrome.scrollChild:GetHeight() or 0) - (chrome.scrollFrame:GetHeight() or 0))
    chrome.scrollFrame:SetVerticalScroll(math.min(math.max(offset or 0, 0), maxScroll))
end

-- A flyout has no spellbook slot of its own, so its contents are listed in
-- place: a known slot drags by spell ID the way Blizzard's own flyout popup
-- buttons do, and the rest fall through to the unavailable section. Blizzard
-- reads the icon off the override and picks up the base spell; so do we.
local function CollectFlyoutItems(items, unavailable, info, offSpecID, reason)
    local numSlots = select(3, GetFlyoutInfo(info.actionID))
    for flyoutSlot = 1, numSlots or 0 do
        local spellID, overrideSpellID, isKnown, spellName, slotSpecID =
            GetFlyoutSlotInfo(info.actionID, flyoutSlot)
        if spellID then
            local entry = {
                name = spellName or "",
                icon = C_Spell.GetSpellTexture(overrideSpellID or spellID),
                tooltipSpellID = spellID,
            }
            if offSpecID then
                -- Blizzard's popup shows only the slots belonging to the spec
                -- being previewed; the others are another spec's problem.
                if slotSpecID == offSpecID then
                    entry.subName = reason
                    entry.addSpellID = overrideSpellID or spellID
                    entry.dim = true
                    unavailable[#unavailable + 1] = entry
                end
            elseif isKnown then
                entry.subName = info.name or ""
                entry.pickupSpellID = spellID
                items[#items + 1] = entry
            else
                entry.subName = NOT_LEARNED_REASON
                entry.addSpellID = overrideSpellID or spellID
                entry.dim = true
                unavailable[#unavailable + 1] = entry
            end
        end
    end
end

-- One entry per skill line, then the pet bank, then everything the player
-- cannot cast right now as a single section pinned last. The General line is
-- skipped outright: racials and utility are noise in a list whose only job is
-- filling a panel, and so are the lines Blizzard's own book hides.
--
-- The active spec's line comes first and the class line second, ahead of
-- Blizzard's own lineIndex order: a panel is nearly always being filled with
-- spec spells, so those belong under the search box rather than a scroll away.
local function CollectSections()
    local sections = {}
    local unavailable = {}
    -- Both are unique skill lines, so a single slot each is enough; anything
    -- else keeps its relative order behind them.
    local specSection, classSection
    local otherSections = {}

    for lineIndex = 1, C_SpellBook.GetNumSpellBookSkillLines() or 0 do
        local line = C_SpellBook.GetSpellBookSkillLineInfo(lineIndex)
        local listed = line and not line.shouldHide and lineIndex ~= GENERAL_SKILL_LINE
        if listed then
            -- Why the row is unavailable: the owning spec reads better than a
            -- bare "not learned" for a line the player simply isn't in.
            local offSpecID = line.offSpecID
            local reason = offSpecID and (line.name or "") or NOT_LEARNED_REASON
            local offset = line.itemIndexOffset or 0
            local items = {}
            for slot = offset + 1, offset + (line.numSpellBookItems or 0) do
                local info = C_SpellBook.GetSpellBookItemInfo(slot, PLAYER_BANK)
                if info and info.itemType == FLYOUT_ITEM_TYPE then
                    CollectFlyoutItems(items, unavailable, info, offSpecID, reason)
                elseif info and (info.itemType == SPELL_ITEM_TYPE
                    or info.itemType == FUTURE_SPELL_ITEM_TYPE) then
                    if offSpecID or info.itemType == FUTURE_SPELL_ITEM_TYPE then
                        unavailable[#unavailable + 1] = {
                            slot = slot,
                            bank = PLAYER_BANK,
                            name = info.name or "",
                            subName = reason,
                            icon = info.iconID,
                            -- spellID is the override-resolved one and nil only
                            -- for non-spells, which cannot reach this branch.
                            addSpellID = info.spellID or info.actionID,
                            dim = true,
                        }
                    else
                        items[#items + 1] = {
                            slot = slot,
                            bank = PLAYER_BANK,
                            name = info.name or "",
                            subName = info.subName or "",
                            icon = info.iconID,
                        }
                    end
                end
            end
            if #items > 0 then
                local section = { name = line.name or "", items = items }
                if lineIndex == MAIN_SPEC_SKILL_LINE then
                    specSection = section
                elseif lineIndex == CLASS_SKILL_LINE then
                    classSection = section
                else
                    otherSections[#otherSections + 1] = section
                end
            end
        end
    end

    if specSection then
        sections[#sections + 1] = specSection
    end
    if classSection then
        sections[#sections + 1] = classSection
    end
    for _, section in ipairs(otherSections) do
        sections[#sections + 1] = section
    end

    -- Blizzard's pet category counts the same way: slots 1..n off a zero offset.
    local numPetSpells = C_SpellBook.HasPetSpells()
    local petItems = {}
    for slot = 1, numPetSpells or 0 do
        local info = C_SpellBook.GetSpellBookItemInfo(slot, PET_BANK)
        -- A pet bank slot can be a bare command with no spell behind it; a
        -- panel has nothing to track there.
        if info and info.spellID and (info.itemType == SPELL_ITEM_TYPE
            or info.itemType == PET_ACTION_ITEM_TYPE) then
            petItems[#petItems + 1] = {
                slot = slot,
                bank = PET_BANK,
                name = info.name or "",
                subName = info.subName or "",
                icon = info.iconID,
            }
        end
    end
    if #petItems > 0 then
        sections[#sections + 1] = { name = PET or "Pet", items = petItems }
    end

    if #unavailable > 0 then
        sections[#sections + 1] = {
            name = UNAVAILABLE_HEADER,
            items = unavailable,
            dimHeader = true,
        }
    end
    return sections
end

local function ReleaseListFrames()
    for _, row in ipairs(activeRows) do
        row:Hide()
        row:ClearAllPoints()
        -- Every field the layout assigns, so a reused row can never act on the
        -- spell it held last time.
        row.slot = nil
        row.bank = nil
        row.pickupSpellID = nil
        row.tooltipSpellID = nil
        row.addSpellID = nil
        rowPool[#rowPool + 1] = row
    end
    wipe(activeRows)

    for _, header in ipairs(activeHeaders) do
        header:Hide()
        header:ClearAllPoints()
        headerPool[#headerPool + 1] = header
    end
    wipe(activeHeaders)
end

local function AcquireRow()
    local row = table.remove(rowPool)
    if row then return row end

    row = CreateFrame("Button", nil, chrome.scrollChild)
    row:SetHeight(ROW_HEIGHT)
    row:RegisterForDrag("LeftButton")
    row:RegisterForClicks("LeftButtonUp")

    -- The handlers read only the fields the layout wrote: a rebuild can hand
    -- this pooled row a different spell, a different bank, or none at all.
    row:SetScript("OnDragStart", function(self)
        -- Moving the cursor is protected while locked down, and an unavailable
        -- spell cannot be picked up at all -- Blizzard's own pickup no-ops for
        -- it -- so those rows add on double-click instead.
        if self.addSpellID or InCombatLockdown() then
            return
        end
        if self.slot and self.bank then
            C_SpellBook.PickupSpellBookItem(self.slot, self.bank)
        elseif self.pickupSpellID then
            C_Spell.PickupSpell(self.pickupSpellID)
        end
    end)

    -- Double-click, not click: a stray click on a list this dense should never
    -- put a spell in a panel.
    row:SetScript("OnDoubleClick", function(self)
        if not self.addSpellID then
            return
        end
        if not CS.selectedGroup then
            CooldownCompanion:Print("Select a group first before adding spells.")
            return
        end
        if ST._TryAdd(tostring(self.addSpellID)) then
            CooldownCompanion:RefreshConfigPanel()
        end
    end)

    -- Blizzard's own book builds the spell tooltip off the slot rather than the
    -- spell ID; a flattened flyout spell has no slot, so it goes by ID the way
    -- Blizzard's flyout popup buttons do.
    row:SetScript("OnEnter", function(self)
        local hasSlot = self.slot ~= nil and self.bank ~= nil
        if not (hasSlot or self.tooltipSpellID) then
            return
        end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if hasSlot then
            GameTooltip:SetSpellBookItem(self.slot, self.bank)
        else
            GameTooltip:SetSpellByID(self.tooltipSpellID)
        end
        if self.addSpellID then
            GameTooltip:AddLine("Double-click to add to the selected panel.", 0.7, 0.7, 0.7)
        end
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    -- HIGHLIGHT layer on a Button is mouse-gated automatically.
    local hover = row:CreateTexture(nil, "HIGHLIGHT")
    hover:SetAllPoints()
    hover:SetColorTexture(1, 1, 1, 0.06)

    local icon = row:CreateTexture(nil, "ARTWORK")
    icon:SetSize(ICON_SIZE, ICON_SIZE)
    icon:SetPoint("LEFT", row, "LEFT", 0, 0)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    row.icon = icon

    local subName = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    subName:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    subName:SetJustifyH("RIGHT")
    subName:SetWordWrap(false)
    row.subName = subName

    local name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    name:SetPoint("LEFT", icon, "RIGHT", TEXT_GAP, 0)
    name:SetPoint("RIGHT", subName, "LEFT", -TEXT_GAP, 0)
    name:SetJustifyH("LEFT")
    name:SetWordWrap(false)
    row.nameText = name

    return row
end

-- The class colour for anything the player can actually cast, matching the
-- config's Navigator; the unavailable section stays grey, which is the same
-- convention the Navigator uses for its unloaded bucket.
local function SectionHeaderColor(section)
    if section.dimHeader then
        return DIM_HEADER_TEXT[1], DIM_HEADER_TEXT[2], DIM_HEADER_TEXT[3]
    end
    local classColor = C_ClassColor.GetClassColor(select(2, UnitClass("player")))
    if classColor then
        return classColor.r, classColor.g, classColor.b
    end
    return HEADER_TEXT[1], HEADER_TEXT[2], HEADER_TEXT[3]
end

local function AcquireHeader()
    local header = table.remove(headerPool)
    if header then return header end

    header = CreateFrame("Frame", nil, chrome.scrollChild)
    header:SetHeight(HEADER_HEIGHT)

    local label = header:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("BOTTOMLEFT", header, "BOTTOMLEFT", 0, HEADER_LABEL_Y)
    label:SetJustifyH("LEFT")
    label:SetWordWrap(false)
    header.label = label

    -- The config's section rule: a thin line off the label's right edge fading
    -- out to the right. Both points are taken against the same line -- the
    -- label's own bottom, and the header's bottom plus the label's lift -- since
    -- two points declaring different vertical centres on a 1px texture is
    -- over-constrained and resolves by luck rather than by rule.
    local rule = header:CreateTexture(nil, "ARTWORK")
    rule:SetTexture("Interface/Buttons/WHITE8x8")
    rule:SetHeight(HEADER_RULE_HEIGHT)
    rule:SetPoint("BOTTOMLEFT", label, "BOTTOMRIGHT", HEADER_RULE_GAP, HEADER_RULE_Y)
    rule:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT",
        -HEADER_RULE_INSET, HEADER_LABEL_Y + HEADER_RULE_Y)
    header.rule = rule

    return header
end

-- `keepScroll` is for the refresh events, which fire while the user is looking
-- at a settled list; typing and opening both start at the top.
RebuildList = function(keepScroll)
    if not chrome then
        return
    end

    local previousScroll = keepScroll and chrome.scrollFrame:GetVerticalScroll() or 0
    ReleaseListFrames()

    local needle = string.lower(searchText)
    local y = 0
    local shown = 0

    for _, section in ipairs(CollectSections()) do
        local matched
        for _, item in ipairs(section.items) do
            if needle == "" or string.find(string.lower(item.name), needle, 1, true) then
                matched = matched or {}
                matched[#matched + 1] = item
            end
        end

        -- A section whose spells all filtered out loses its header too.
        if matched then
            local header = AcquireHeader()
            header:SetPoint("TOPLEFT", chrome.scrollChild, "TOPLEFT", 0, -y)
            header:SetPoint("TOPRIGHT", chrome.scrollChild, "TOPRIGHT", 0, -y)
            header.label:SetText(section.name)
            -- Pooled headers carry the last section's look, so the label AND the
            -- rule are re-tinted every time rather than only the grey one.
            local r, g, b = SectionHeaderColor(section)
            header.label:SetTextColor(r, g, b)
            header.rule:SetGradient("HORIZONTAL",
                CreateColor(r, g, b, HEADER_RULE_ALPHA), CreateColor(r, g, b, 0))
            header:Show()
            activeHeaders[#activeHeaders + 1] = header
            y = y + HEADER_HEIGHT

            for _, item in ipairs(matched) do
                local row = AcquireRow()
                row:SetPoint("TOPLEFT", chrome.scrollChild, "TOPLEFT", 0, -y)
                row:SetPoint("TOPRIGHT", chrome.scrollChild, "TOPRIGHT", 0, -y)
                row.slot = item.slot
                row.bank = item.bank
                row.pickupSpellID = item.pickupSpellID
                row.tooltipSpellID = item.tooltipSpellID
                row.addSpellID = item.addSpellID
                row.icon:SetTexture(item.icon)
                -- Pooled rows carry the last row's look, so both states are set
                -- every time rather than only the dim one.
                row.icon:SetDesaturated(item.dim == true)
                row.nameText:SetText(item.name)
                local nameColor = item.dim and DIM_TEXT or NAME_TEXT
                row.nameText:SetTextColor(nameColor[1], nameColor[2], nameColor[3])
                row.subName:SetText(item.subName)
                row:Show()
                activeRows[#activeRows + 1] = row
                y = y + ROW_HEIGHT
                shown = shown + 1
            end
        end
    end

    -- Only when the viewport has actually been measured: the window has no
    -- width on the first pass, and OnSizeChanged below owns the width from then
    -- on. Writing a zero here would shrink the rows to nothing.
    local viewportWidth = chrome.scrollFrame:GetWidth()
    if type(viewportWidth) == "number" and viewportWidth > 0 then
        chrome.scrollChild:SetWidth(viewportWidth)
    end
    chrome.scrollChild:SetHeight(math.max(1, y))
    chrome.empty:SetShown(shown == 0)
    SetListScroll(previousScroll)
end

------------------------------------------------------------------------
-- The content host: built once, re-parented into whichever Window frame
-- AceGUI hands us.
------------------------------------------------------------------------

local function EnsureChrome()
    if chrome then
        return chrome
    end

    local host = CreateFrame("Frame", nil, UIParent)
    host:Hide()

    -- Centred over the whole window and one size up from the list's own small
    -- text: it captions the list rather than labelling the search box. Still
    -- muted grey -- it is an instruction, not a heading.
    local hint = host:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    hint:SetPoint("TOPLEFT", host, "TOPLEFT", CONTENT_INSET, -CONTENT_INSET)
    hint:SetPoint("TOPRIGHT", host, "TOPRIGHT", -CONTENT_INSET, -CONTENT_INSET)
    hint:SetJustifyH("CENTER")
    hint:SetWordWrap(false)
    hint:SetText("Drag a spell onto a panel to add it.")

    -- A stock AceGUI EditBox rather than Blizzard's SearchBoxTemplate: UI skins
    -- style Ace3 widgets, which is what every other edit box in this config is.
    -- It is acquired once and never released -- the chrome outlives every Window
    -- the panel opens -- so its frame is parked on the host by hand instead of
    -- being sized and shown by a container's layout.
    local searchBox = AceGUI:Create("EditBox")
    searchBox:SetLabel("")     -- drops the label row; the widget re-heights itself
    searchBox:DisableButton(true)
    searchBox:SetText("")
    searchBox.frame:SetParent(host)
    searchBox.frame:ClearAllPoints()
    searchBox.frame:SetPoint("TOPLEFT", hint, "BOTTOMLEFT", 0, -HINT_GAP)
    searchBox.frame:SetPoint("TOPRIGHT", hint, "BOTTOMRIGHT", 0, -HINT_GAP)
    searchBox.frame:SetHeight(SEARCH_HEIGHT)
    searchBox.frame:Show()

    -- The template used to supply its own "Search" placeholder. InputBoxTemplate
    -- has one too, but the config's other AceGUI boxes hide it and own their own
    -- so it can be toggled from a text callback; do the same, with the same 6px
    -- buffer the add-spell box gives its placeholder.
    if searchBox.editbox.Instructions then
        searchBox.editbox.Instructions:Hide()
    end
    local searchHint = searchBox.editbox:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    searchHint:SetPoint("LEFT", searchBox.editbox, "LEFT", 6, 0)
    searchHint:SetPoint("RIGHT", searchBox.editbox, "RIGHT", -6, 0)
    searchHint:SetTextColor(0.5, 0.5, 0.5)
    searchHint:SetJustifyH("LEFT")
    searchHint:SetWordWrap(false)
    searchHint:SetText(SEARCH or "Search")

    -- Live filtering, one rebuild per keystroke. The widget only fires this when
    -- the text differs from what its own SetText last recorded, so the reset in
    -- OpenSpellbookPanel is already silent -- but the flag stays: the Ace3 that
    -- wins the load order need not be the copy vendored here.
    searchBox:SetCallback("OnTextChanged", function(_, _, text)
        searchHint:SetShown((text or "") == "")
        if suppressSearchChanged then
            return
        end
        searchText = text or ""
        RebuildList(false)
    end)

    local scrollFrame = CreateFrame("ScrollFrame", nil, host)
    scrollFrame:SetPoint("TOPLEFT", searchBox.frame, "BOTTOMLEFT", 0, -SEARCH_GAP)
    scrollFrame:SetPoint("TOPRIGHT", searchBox.frame, "BOTTOMRIGHT", 0, -SEARCH_GAP)
    scrollFrame:SetPoint("BOTTOMLEFT", host, "BOTTOMLEFT", CONTENT_INSET, CONTENT_INSET)
    scrollFrame:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", -CONTENT_INSET, CONTENT_INSET)
    scrollFrame:EnableMouseWheel(true)

    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetSize(1, 1)
    scrollFrame:SetScrollChild(scrollChild)

    scrollFrame:SetScript("OnMouseWheel", function(_, delta)
        SetListScroll((scrollFrame:GetVerticalScroll() or 0) - (delta * ROW_HEIGHT * WHEEL_ROWS))
    end)
    -- The rows span the scroll child, so tracking the viewport width here is
    -- all a resize needs; the window has no width on the first render pass.
    scrollFrame:SetScript("OnSizeChanged", function(_, width)
        if type(width) == "number" and width > 0 then
            scrollChild:SetWidth(width)
        end
        SetListScroll(scrollFrame:GetVerticalScroll())
    end)

    local empty = scrollFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    empty:SetPoint("TOP", scrollFrame, "TOP", 0, -6)
    empty:SetText("No spells match.")
    empty:Hide()

    chrome = {
        host = host,
        searchBox = searchBox,
        searchHint = searchHint,
        scrollFrame = scrollFrame,
        scrollChild = scrollChild,
        empty = empty,
    }
    return chrome
end

local function AttachChrome(parent)
    local host = EnsureChrome().host
    host:SetParent(parent)
    host:ClearAllPoints()
    host:SetAllPoints(parent)
    host:Show()
end

local function DetachChrome()
    if not chrome then
        return
    end
    -- The search box keeps the keyboard while it has focus, and nothing else
    -- takes it back on the way out.
    chrome.searchBox:ClearFocus()
    -- AceGUI recycles the Window frame, so nothing of ours may still hang off it.
    chrome.host:Hide()
    chrome.host:ClearAllPoints()
    chrome.host:SetParent(UIParent)
end

------------------------------------------------------------------------
-- Refresh events
------------------------------------------------------------------------

local function SetEventsRegistered(registered)
    if not eventFrame then
        if not registered then
            return
        end
        eventFrame = CreateFrame("Frame")
        eventFrame:SetScript("OnEvent", function()
            RebuildList(true)
        end)
    end

    if not registered then
        eventFrame:UnregisterAllEvents()
        return
    end
    for _, event in ipairs(REFRESH_EVENTS) do
        eventFrame:RegisterEvent(event)
    end
    eventFrame:RegisterUnitEvent("PLAYER_SPECIALIZATION_CHANGED", "player")
end

------------------------------------------------------------------------
-- The window
------------------------------------------------------------------------

-- Both corners of the anchored side, so the list spans the config's full
-- height and follows a resize of it. The side comes from the shared config
-- side-placement rule (Panel.lua); the config's geometry hooks re-run this
-- whenever the window's side choice could go stale.
local function AnchorWindow()
    local configFrame = CS.configFrame
    if not (window and configFrame and configFrame.frame and configFrame.frame:IsShown()) then
        return
    end
    local cf = configFrame.frame
    local wf = window.frame
    wf:ClearAllPoints()

    local side, xOff = "right", WINDOW_GAP
    if ST._ComputeConfigSidePlacement then
        side, xOff = ST._ComputeConfigSidePlacement(wf, WINDOW_WIDTH)
    end
    if side == "left" then
        wf:SetPoint("TOPRIGHT", cf, "TOPLEFT", xOff, 0)
        wf:SetPoint("BOTTOMRIGHT", cf, "BOTTOMLEFT", xOff, 0)
    else
        wf:SetPoint("TOPLEFT", cf, "TOPRIGHT", xOff, 0)
        wf:SetPoint("BOTTOMLEFT", cf, "BOTTOMRIGHT", xOff, 0)
    end
end
ST._ReanchorSpellbookPanelWindow = AnchorWindow

local function CleanupWindow(widget)
    -- Dropped first, so the re-entrant OnClose that AceGUI:Release can fire
    -- finds nothing left to clean up.
    if window ~= widget then
        return
    end
    window = nil
    CS.spellbookPanelWindow = nil

    SetEventsRegistered(false)
    ReleaseListFrames()
    DetachChrome()

    if CS.UnregisterConfigDragAlphaFrame then
        CS.UnregisterConfigDragAlphaFrame(widget.frame)
    end
    AceGUI:Release(widget)

    -- The preview command center's toggle is gold while this window is up, and
    -- closing it does not rebuild that bar.
    if ST._RefreshPreviewCommandCenterSpellbook then
        ST._RefreshPreviewCommandCenterSpellbook()
    end
end

local function CloseSpellbookPanel()
    if not window then
        return false
    end
    window:Hide()
    return true
end

-- The side editors that share the config's right edge: this window opening
-- takes it from them, exactly as an advanced panel opening does.
local function CloseCompetingEditors()
    if CS.CloseAdvancedSettingsPanel then
        CS.CloseAdvancedSettingsPanel({ skipRefresh = true })
    end
    if CS.CancelPickAuraTexture then
        CS.CancelPickAuraTexture()
    end
    if CS.CloseProfileWideFontWindow then
        CS.CloseProfileWideFontWindow()
    end
    if CS.CloseProfileWideBarTextureWindow then
        CS.CloseProfileWideBarTextureWindow()
    end
    if ST._CloseFormatEditor then
        ST._CloseFormatEditor()
    end
end

local function OpenSpellbookPanel()
    local configFrame = CS.configFrame
    if not (configFrame and configFrame.frame and configFrame.frame:IsShown()) then
        return false
    end
    if window then
        window.frame:Raise()
        return true
    end

    CloseCompetingEditors()

    window = AceGUI:Create("Window")
    window:SetTitle("Spellbook")
    window:SetWidth(WINDOW_WIDTH)
    window:SetLayout(nil) -- raw content, positioned by anchors
    window:EnableResize(false)
    window:SetCallback("OnClose", CleanupWindow)
    -- Modern UIPanelCloseButton art (RedButton-Exit) fills the whole 24x24
    -- button, so AceGUI's legacy (+2, +1) offset leaves the X hanging outside
    -- the corner.
    if window.closebutton then
        window.closebutton:ClearAllPoints()
        window.closebutton:SetPoint("TOPRIGHT", window.frame, "TOPRIGHT", -3, -3)
    end
    if CS.RegisterConfigDragAlphaFrame then
        CS.RegisterConfigDragAlphaFrame(window.frame)
    end
    -- AceGUI hands back a recycled frame, which keeps whatever level it last
    -- had; the window that just opened belongs on top.
    window.frame:Raise()
    CS.spellbookPanelWindow = window

    AnchorWindow()
    AttachChrome(window.content)

    searchText = ""
    suppressSearchChanged = true
    chrome.searchBox:SetText("")
    suppressSearchChanged = false
    -- The widget fires no text callback for its own SetText, so the placeholder
    -- that callback owns is put back here.
    chrome.searchHint:Show()

    SetEventsRegistered(true)
    RebuildList(false)

    if ST._RefreshPreviewCommandCenterSpellbook then
        ST._RefreshPreviewCommandCenterSpellbook()
    end
    return true
end

local function ToggleSpellbookPanel()
    if window then
        return CloseSpellbookPanel()
    end
    return OpenSpellbookPanel()
end

CS.OpenSpellbookPanel = OpenSpellbookPanel
CS.CloseSpellbookPanel = CloseSpellbookPanel
CS.ToggleSpellbookPanel = ToggleSpellbookPanel
