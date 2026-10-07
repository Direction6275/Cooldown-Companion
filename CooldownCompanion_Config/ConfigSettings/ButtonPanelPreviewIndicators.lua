--[[
    CooldownCompanion - ButtonPanelPreviewIndicators
    Indicator previews and fallback entry selection strips.

    Part of the ButtonPanelPreview family; see its ordered block in the addon TOC.
    Private helpers are shared through ST._ButtonPanelPreview.
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon
local CS = ST._configState
local math_floor = math.floor
local math_min = math.min
local math_max = math.max
local math_ceil = math.ceil

local PP = ST._ButtonPanelPreview
local AceGUI = LibStub("AceGUI-3.0")

-- The rules card: every rule the Indicator checks, in the same row grammar as
-- the settings (name on the left, value on the right), inside a titled
-- InlineGroup. Built only from AceGUI widgets, so it wears the same skin as
-- the rest of the config. It only shows: sources and rules are edited in
-- Visibility's When to Show, and clicking a rule opens its exact row there.
-- The model comes from ST._GetIndicatorSourceControls (IndicatorTabs.lua).
local VALUE_HOVER = {1, 0.82, 0}
local WARNING = {1, 0.72, 0.25}

local function ShowTooltip(frame, lines)
    GameTooltip:SetOwner(frame, "ANCHOR_TOP")
    GameTooltip:SetText(lines[1])
    if lines[2] then GameTooltip:AddLine(lines[2], 1, 1, 1, true) end
    GameTooltip:Show()
end

-- A rule's value: right-aligned text that turns gold on hover, like a
-- setting's name does when it opens something.
local function RuleValue(text, color, tooltip, onClick)
    local value = AceGUI:Create("InteractiveLabel")
    -- Navigator rows leave their icons and badges on pooled labels.
    ST._CleanRecycledEntry(value)
    value:SetFontObject(GameFontHighlight)
    value:SetText(text)
    value:SetJustifyH("RIGHT")
    value:SetWidth(math_min(math_ceil(value.label:GetStringWidth()) + 2, 200))
    if color then value:SetColor(color[1], color[2], color[3]) end
    value:SetCallback("OnEnter", function(widget)
        widget:SetColor(VALUE_HOVER[1], VALUE_HOVER[2], VALUE_HOVER[3])
        ShowTooltip(widget.frame, tooltip)
    end)
    value:SetCallback("OnLeave", function(widget)
        if color then widget:SetColor(color[1], color[2], color[3]) else widget:SetColor() end
        GameTooltip:Hide()
    end)
    -- The click rebuilds the preview and releases this hovered label.
    value:SetCallback("OnClick", function() GameTooltip:Hide(); onClick() end)
    return value
end

local function CardRow(card, label, indent)
    local row = AceGUI:Create("CDC-LabelRow")
    row:SetFullWidth(true)
    row:SetLabel(label)
    if indent then row:SetIndent(true) end
    card:AddChild(row)
    return row
end

-- One source: a row per rule, the first named for the source and the rest
-- joined with "and", as they read in Visibility. An aura reads its stack rule
-- (or While Active).
local function AddSourceRows(card, source, model, parts)
    local name = (source.icon and "|T" .. tostring(source.icon) .. ":16:16|t " or "") .. source.name
    if not source.enabled then name = "|cff999999" .. name .. " (not checked)|r" end
    local entry = {name = CardRow(card, name), rules = {}}
    parts.rows[#parts.rows + 1] = entry
    if source.aura then
        -- A rule that can never pass reads in the warning color; the reason
        -- sits under the rule in Visibility.
        -- Clickable like a spell's rule: it opens the aura's row in Visibility.
        entry.rules[1] = RuleValue(source.auraRule, source.auraRuleNever and WARNING or nil,
            {source.auraRule, "Click to open this aura in Visibility."},
            function() model.openAuraRule(source.entry) end)
        entry.name:SetControlWidget(entry.rules[1])
    elseif #source.rules == 0 then
        entry.rules[1] = RuleValue("Always", nil,
            {"No rules", "Shows whenever it can be tracked. Click to add rules in Visibility."},
            function() model.openRule(nil) end)
        entry.name:SetControlWidget(entry.rules[1])
    else
        for index, rule in ipairs(source.rules) do
            local clause = rule.clause
            local value = RuleValue(rule.label or "Unavailable", not rule.label and WARNING or nil,
                rule.label and {rule.label, "Click to open this rule in Visibility."}
                    or {"Unavailable rule", "This saved rule cannot match. Click to replace or remove it in Visibility."},
                function() model.openRule(clause) end)
            local row = index == 1 and entry.name or CardRow(card, "and", true)
            row:SetControlWidget(value)
            entry.rules[#entry.rules + 1] = value
        end
    end
end

local function ReleaseSourceControls(preview)
    if preview.indicatorCard then
        AceGUI:Release(preview.indicatorCard)
        preview.indicatorCard, preview.indicatorCardKey = nil, nil
    end
end

-- Build the card for `model` at `width`; returns the AceGUI group's frame.
-- The model's key names everything the card draws and every closure it keeps,
-- so an unchanged card is kept: previews refresh on every drag tick.
local function BuildRulesCard(preview, model, width)
    local cardKey = model.key .. "|" .. width
    local card = preview.indicatorCard
    if card and preview.indicatorCardKey == cardKey then
        card.frame:Show()
        return card.frame
    end
    ReleaseSourceControls(preview)
    card = AceGUI:Create("InlineGroup")
    card:SetLayout("List")
    card.frame:SetParent(preview.root)
    card:SetWidth(width)
    card:SetTitle("When to Show")
    local parts = {title = "When to Show", rows = {}}
    card._cdcRulesCard = parts
    if model.replacing or model.disabled then
        local note = AceGUI:Create("Label")
        note:SetFontObject(GameFontHighlight)
        note:SetColor(WARNING[1], WARNING[2], WARNING[3])
        local replacing = "Search for the new source in the field at the top. It starts with fresh rules; the look is kept."
        if #model.sources > 1 then replacing = replacing .. " Other spell and item sources stay." end
        note:SetText(model.replacing and replacing or "This Indicator is off. These rules apply once it is on.")
        note:SetFullWidth(true)
        card:AddChild(note)
        parts.note = note
    end
    for _, source in ipairs(model.sources) do AddSourceRows(card, source, model, parts) end
    card:DoLayout()
    card.frame:Show()
    preview.indicatorCard, preview.indicatorCardKey = card, cardKey
    return card.frame
end

function PP.ReleaseIndicatorPreviewControls(preview)
    local surface = preview.indicatorSurface
    if surface and surface.countdownTicker then surface.countdownTicker:SetScript("OnUpdate", nil) end
    if preview.indicatorDuration then
        AceGUI:Release(preview.indicatorDuration)
        preview.indicatorDuration = nil
    end
    if preview.indicatorStacks then
        AceGUI:Release(preview.indicatorStacks)
        preview.indicatorStacks = nil
    end
    if preview.indicatorAura then
        AceGUI:Release(preview.indicatorAura)
        preview.indicatorAura = nil
    end
    ReleaseSourceControls(preview)
end

-- The sample stack count for a stack rule (from Indicator.StackRule): the one
-- tried in the Stacks row, or a count that passes the rule. A changed rule
-- starts over at a passing count so the display is visible. Also returns the
-- row's key and its top: the aura's max when reported (or the rule's own
-- count, if higher). A saved sample never sits above the top. None for a rule
-- that cannot be checked.
local function PreviewStacks(panelId, compare, count, stackMax, readOnly)
    if not count then return end
    local top = stackMax and math_max(stackMax, count) or math_min(ST.Indicator.STACK_COUNT_MAX, math_max(10, count + 3))
    local passing = compare == "fewer" and count - 1 or count
    local key = tostring(panelId) .. ":" .. compare .. ":" .. count
    local saved = CS.indicatorPreviewStacks
    if readOnly or not (saved and saved.key == key) then return passing, key, top end
    return math_min(saved.value, top), key, top
end

-- Adopt one AceGUI row into the preview footer; PinFooter places it.
local function AddFooterRow(preview, footer, widget, width)
    widget.frame:SetParent(preview.root)
    widget:SetWidth(width)
    widget.frame:Show()
    footer[#footer + 1] = widget.frame
end

-- The footer hugs the preview's bottom edge, just above the add field, so the
-- artwork keeps the open space above it. Regions are listed top to bottom and
-- pinned bottom-up; returns the height the artwork must leave free.
local FOOTER_GAP = 8
local function PinFooter(preview, footer)
    local height, below = 0, nil
    for index = #footer, 1, -1 do
        local region = footer[index]
        region:ClearAllPoints()
        if below then
            region:SetPoint("BOTTOM", below, "TOP", 0, FOOTER_GAP)
        else
            region:SetPoint("BOTTOM", preview.root, "BOTTOM", 0, PP.PANEL_PREVIEW_PADDING)
        end
        height = height + FOOTER_GAP + region:GetHeight()
        below = region
    end
    return height
end

-- The Countdown state sweeps the sample timer the way panel duration-text
-- previews do, so Low Time colors and the Pandemic marker and effect appear
-- as the sample crosses their windows. CC-side frames only. The sweep ticks on
-- its own child frame: the effect runtime owns the surface's OnUpdate.
local COUNTDOWN_FROM = 12
local COUNTDOWN_INTERVAL = 0.1

-- The Pandemic effect stand-ins (Icon glow, Texture and Text recolor),
-- shown while the sample sits in the refresh window.
local function ShowPandemicStandIns(surface, shown)
    if surface.indicatorPandemicGlow then surface.indicatorPandemicGlow.host:SetShown(shown) end
    local tint = surface.indicatorPandemicTint
    if tint then
        tint.baseFrame:SetShown(shown)
        tint.foreFrame:SetShown(shown)
        tint.labelFrame:SetShown(shown)
    end
end

local function ShowPreviewCountdown(surface)
    local I = ST.Indicator
    local candidate = surface._countdownGroup
    local remaining = COUNTDOWN_FROM - ((GetTime() - surface._countdownStart) % COUNTDOWN_FROM)
    I.UpdateReadouts(surface, nil, candidate, remaining / I.PREVIEW_SECONDS)
    ShowPandemicStandIns(surface, I.IsPreviewPandemicWindow(remaining))
end

local function OnPreviewCountdownUpdate(ticker, elapsed)
    local surface = ticker:GetParent()
    surface._countdownElapsed = (surface._countdownElapsed or 0) + elapsed
    if surface._countdownElapsed < COUNTDOWN_INTERVAL then return end
    surface._countdownElapsed = 0
    ShowPreviewCountdown(surface)
end

function PP.BuildIndicatorPreview(preview, host, panelId, group, readOnly)
    if preview.indicatorDuration then preview.indicatorDuration.frame:Hide() end
    if preview.indicatorStacks then preview.indicatorStacks.frame:Hide() end
    if preview.indicatorAura then preview.indicatorAura.frame:Hide() end
    -- Hidden, not released: BuildRulesCard keeps an unchanged card.
    if preview.indicatorCard then preview.indicatorCard.frame:Hide() end
    local I = ST.Indicator
    if readOnly or not I.Primary(group) then ReleaseSourceControls(preview) end
    if not I.Primary(group) then
        PP.SetPreviewMessage(preview, "Add spells, items, or auras in the field at the top.", "Choose a source")
        PP.FinalizePreviewState(preview)
        return
    end
    -- Detached saved-design render: no production aura widgets are inspected.
    local candidate = CopyTable(group)
    I.Initialize(candidate)
    local stage = CS.textureConfigPreviewStage
    local pickerStage = CS.textureMirrorStage
    if not readOnly and pickerStage and pickerStage.groupId == panelId and pickerStage.selection then
        candidate.indicatorSettings.signal=CopyTable(pickerStage.selection)
    elseif not readOnly and stage and stage.groupId == panelId then
        candidate.indicatorSettings.signal=CopyTable(stage.settings)
    end
    local surface = preview.indicatorSurface
    if not surface then
        surface = CreateFrame("Frame",nil,preview.root)
        surface:EnableMouse(false)
        surface.visualRoot = CreateFrame("Frame",nil,surface)
        surface.visualRoot:SetPoint("CENTER")
        surface.primaryTexture = surface.visualRoot:CreateTexture(nil,"ARTWORK")
        surface.secondaryTexture = surface.visualRoot:CreateTexture(nil,"ARTWORK")
        preview.indicatorSurface = surface
    end
    local state = not readOnly and CS.indicatorPreviewState or "half"
    local fraction = state == "full" and 1 or state == "empty" and 0 or 0.5
    if state == "timeless" then fraction=1 end
    local settings = I.Settings(candidate)
    -- A presence-drawn display (While Missing, several auras) has no timer,
    -- drain or pandemic. Its Aura(s) row tries the states instead.
    local missing = I.UsesPresence(candidate)
    local showDuration = not readOnly and not missing and (settings.readouts.timer
        or settings.displayType == "texture" and settings.progress.enabled
        or I.IsAura(candidate) and I.PandemicEffectOn(candidate))
    -- The sweep runs only while its Duration control is drawn: that control is
    -- the only way to leave the Countdown state.
    local countdown = showDuration and state == "countdown"
    surface.countdownTicker = surface.countdownTicker or CreateFrame("Frame", nil, surface)
    surface.countdownTicker:SetScript("OnUpdate", nil)
    if countdown then
        surface._countdownStart = surface._countdownStart or GetTime()
        fraction = (COUNTDOWN_FROM - ((GetTime() - surface._countdownStart) % COUNTDOWN_FROM)) / I.PREVIEW_SECONDS
    else
        surface._countdownStart = nil
    end
    -- A stack rule shows or hides the sample like the real display does. A
    -- rule the aura's max settles (or one that cannot be checked) ignores the
    -- sample, as in game, and offers no Stacks row.
    local compare, count, stackMax = I.StackRule(candidate)
    local outcome = I.StackRuleOutcome(compare, count, stackMax)
    local stacks, stacksKey, stacksTop
    if not outcome then stacks, stacksKey, stacksTop = PreviewStacks(panelId, compare, count, stackMax, readOnly) end
    surface._previewStacks = stacks
    local passes
    if outcome then
        passes = outcome == "always"
    else
        passes = I.StackRulePasses(compare, count, stacks or 0)
    end
    -- While Missing starts on Missing so the display is visible; Active hides
    -- it as the real tracker does. A list tries its auras' Whens met or not,
    -- starting met.
    local list = I.IsMultiAura(candidate)
    local auraStates, auraOrder, auraPass
    if list then
        auraStates, auraOrder, auraPass = {met="Met", unmet="Not Met"}, {"met", "unmet"}, "met"
    else
        auraStates, auraOrder, auraPass = {missing="Missing", active="Active"}, {"missing", "active"}, "missing"
        -- Also During Pandemic: the window shows the aura's live display.
        if missing and I.AlsoDuringPandemic(candidate) then
            auraStates.pandemic = "Pandemic Window"
            auraOrder = {"missing", "pandemic", "active"}
        end
    end
    local auraKey = tostring(panelId) .. ":" .. tostring(list)
    local saved = CS.indicatorPreviewAura
    local auraState = missing and not readOnly and saved and saved.key == auraKey and auraStates[saved.value]
        and saved.value or auraPass
    -- The window sample: the live display (timer, pandemic glow) with time
    -- left inside the window, styled as the native twin is.
    local inWindow = missing and auraState == "pandemic"
    surface._ccPandemicTwin = inWindow or nil
    if inWindow then fraction = I.PREVIEW_PANDEMIC_FRACTION end
    if missing then passes = auraState == auraPass or inWindow end
    surface:SetAlpha(passes and 1 or 0)
    if not I.Render(surface,nil,candidate,true,fraction) then
        ShowPandemicStandIns(surface, false)
        ReleaseSourceControls(preview)
        PP.SetPreviewMessage(preview,"Choose artwork in Appearance to preview this Indicator.")
        PP.FinalizePreviewState(preview)
        return
    end
    if state == "timeless" and not inWindow then surface.indicatorReadouts.timer:SetText("") end
    -- The Pandemic effect stand-ins: the live rigs' stylers on CC-side kits.
    if not surface.indicatorPandemicGlow then I.CreatePandemicGlow(surface, false) end
    I.StylePandemicGlow(surface, candidate, true)
    I.StylePandemicTint(surface, candidate, true)
    ShowPandemicStandIns(surface, I.IsPreviewPandemicWindow(fraction * I.PREVIEW_SECONDS))
    if countdown then
        surface._countdownGroup, surface._countdownElapsed = candidate, 0
        surface.countdownTicker:SetScript("OnUpdate", OnPreviewCountdownUpdate)
    end
    if not readOnly then
        candidate.locked = true
        local sample = {buttonData=I.Primary(candidate), _textureAuraPreview=true}
        -- A native display plays only what its slot can (no Color Shift on
        -- Text; the window's twin also no Only In Combat): the runtime's own
        -- lists decide, so the sample matches the game.
        local plays = inWindow and I.PandemicTwinEffects(candidate) or I.NativeEffects(candidate)
        if plays then
            for key, effect in pairs(I.Effects(candidate)) do
                if type(effect) == "table" and effect.enabled and not plays[key] then effect.enabled=false end
            end
        end
        -- Every enabled effect plays together, for aura and condition sources.
        CooldownCompanion:ApplyIndicatorEffects(surface,sample,candidate,true,true)
    end
    local width,height=surface:GetSize()
    local footerHeight = 0
    if not readOnly then
        -- GetHostFitBox returns width and height; only the width sizes the footer.
        local fitWidth = PP.GetHostFitBox(host,false)
        local rowWidth = math_min(360,fitWidth)
        -- The preview is the source workspace: every source and rule the
        -- Indicator checks, Change/Remove for the main source, and for an
        -- aura where it is tracked.
        local footer = {}
        local model = ST._GetIndicatorSourceControls(group)
        if model then footer[#footer + 1] = BuildRulesCard(preview,model,rowWidth)
        else ReleaseSourceControls(preview) end
        if showDuration then
            local control = preview.indicatorDuration
            if not control then
                -- Use the shared row's dropdown geometry and pool cleanup.
                control = AceGUI:Create("CDC-DropdownRow")
                control:SetLabel("Duration")
                control:SetList({full="Full",half="Half",empty="Empty",countdown="Countdown",timeless="No Timer"},
                    {"full","half","empty","countdown","timeless"})
                control.frame:SetParent(preview.root)
                preview.indicatorDuration = control
            end
            AddFooterRow(preview,footer,control,rowWidth)
            control:SetValue(state)
            control:SetCallback("OnValueChanged",function(_,_,value)
                CS.indicatorPreviewState=value
                ST._RefreshButtonsPreviewMirror(panelId)
            end)
        end
        if missing then
            local control = preview.indicatorAura
            if not control then
                control = AceGUI:Create("CDC-DropdownRow")
                control.frame:SetParent(preview.root)
                preview.indicatorAura = control
            end
            control:SetLabel(list and "Auras" or "Aura")
            control:SetList(auraStates, auraOrder)
            AddFooterRow(preview,footer,control,rowWidth)
            control:SetValue(auraState)
            control:SetCallback("OnValueChanged",function(_,_,value)
                CS.indicatorPreviewAura={key=auraKey,value=value}
                ST._RefreshButtonsPreviewMirror(panelId)
            end)
        end
        if stacks then
            local control = preview.indicatorStacks
            if not control then
                control = AceGUI:Create("CDC-SliderRow")
                control:SetLabel("Stacks")
                control.frame:SetParent(preview.root)
                preview.indicatorStacks = control
            end
            control:SetSliderValues(0, stacksTop, 1)
            AddFooterRow(preview,footer,control,rowWidth)
            control:SetValue(stacks)
            control:SetCallback("OnValueChanged",function(_,_,value)
                CS.indicatorPreviewStacks={key=stacksKey,value=math_floor(value + 0.5)}
                ST._RefreshButtonsPreviewMirror(panelId)
            end)
        end
        footerHeight = PinFooter(preview,footer)
    end
    -- Caption and controls stay readable at the host scale. Reserve their
    -- measured height before fitting the artwork, which centers in the space
    -- left above the footer.
    local scale = PP.GetHostFitScale(host,width,height+(readOnly and 28 or 0),readOnly,footerHeight)
    surface:SetScale(scale)
    surface:ClearAllPoints()
    surface:SetPoint("CENTER",preview.root,"CENTER",0,readOnly and 10 or footerHeight / (2 * scale))
    surface:Show()
    preview.barBaseRect = {x=0,y=0,width=width,height=height}
    PP.FinalizePreviewState(preview)
end
local StylePreviewIcon = PP.StylePreviewIcon

-- ButtonPanelPreviewEffects.lua
local StopConditionalTicker = PP.StopConditionalTicker
local ClearSlotEffectPreviews = PP.ClearSlotEffectPreviews
local ApplySlotEffectPreviews = PP.ApplySlotEffectPreviews
local EnsureConditionalTicker = PP.EnsureConditionalTicker

-- ButtonPanelPreviewShared.lua
local SetPreviewMessage = PP.SetPreviewMessage
local FinalizePreviewState = PP.FinalizePreviewState
local STRIP_ICON_SIZE = PP.STRIP_ICON_SIZE
local STRIP_PER_ROW = PP.STRIP_PER_ROW
local STRIP_SPACING = PP.STRIP_SPACING
local GetHostFitScale = PP.GetHostFitScale
local AcquireSlot = PP.AcquireSlot
local ApplyPreviewSlotGeometry = PP.ApplyPreviewSlotGeometry
local DisableReadOnlySlotInteraction = PP.DisableReadOnlySlotInteraction
local PANEL_PREVIEW_HIGHLIGHT_LEVEL_OFFSET = PP.PANEL_PREVIEW_HIGHLIGHT_LEVEL_OFFSET
local CollectEntryStatus = ST._CollectEntryStatus
local PANEL_PREVIEW_DISABLED_ALPHA = PP.PANEL_PREVIEW_DISABLED_ALPHA
local ApplySlotBadges = PP.ApplySlotBadges
local ApplySelectionVisuals = PP.ApplySelectionVisuals
local CopyMode = PP.CopyMode

-- ButtonPanelPreviewInteraction.lua
local CreatePreviewLayoutDrag = PP.CreatePreviewLayoutDrag
local WireEntryInteraction = PP.WireEntryInteraction

-- ButtonPanelPreviewIcons.lua
local ResetSlotConditionalVisuals = PP.ResetSlotConditionalVisuals
local ApplySlotConditionalPreview = PP.ApplySlotConditionalPreview

local function BuildSelectionStrip(preview, host, panelId, group, readOnly)
    StopConditionalTicker(preview)
    local entries = {}
    for index, buttonData in ipairs(group.buttons or {}) do
        entries[#entries + 1] = { buttonData = buttonData, index = index }
    end

    local count = #entries
    if count == 0 then
        if readOnly then
            SetPreviewMessage(preview, "Empty Panel")
        else
            SetPreviewMessage(preview,
                "Search for a spell or item in the field at the top, enter an ID, or drag one into this preview.",
                "Add your first entry")
        end
        FinalizePreviewState(preview)
        return
    end

    local w, h = STRIP_ICON_SIZE, STRIP_ICON_SIZE
    local cols = math_min(count, STRIP_PER_ROW)
    local rows = math_ceil(count / STRIP_PER_ROW)
    local contentWidth = (cols - 1) * (w + STRIP_SPACING) + w
    local contentHeight = (rows - 1) * (h + STRIP_SPACING) + h
    local scale = GetHostFitScale(host, contentWidth, contentHeight, readOnly)

    local content = preview.content
    content:SetSize(contentWidth, contentHeight)
    content:SetScale(scale) -- slot badges below measure the final effective scale
    content:Show()

    local layoutDrag = readOnly and { slots = {} } or CreatePreviewLayoutDrag(preview, panelId)
    layoutDrag.count = count
    layoutDrag.slotW, layoutDrag.slotH = w, h
    layoutDrag.scale = scale
    layoutDrag.anchor = "TOPLEFT"
    layoutDrag.cellXY = function(d)
        local row = math_floor((d - 1) / STRIP_PER_ROW)
        local col = (d - 1) % STRIP_PER_ROW
        return col * (w + STRIP_SPACING), -(row * (h + STRIP_SPACING))
    end
    preview.layoutDrag = layoutDrag
    local dragModel = (not readOnly and count >= 2) and layoutDrag or nil

    for i, entryInfo in ipairs(entries) do
        local slot = AcquireSlot(preview, content, "iconSlots")
        slot:SetSize(w, h)
        local cx, cy = layoutDrag.cellXY(i)
        ApplyPreviewSlotGeometry(preview, slot, "TOPLEFT", cx, cy)

        local buttonData = entryInfo.buttonData
        StylePreviewIcon(slot, buttonData, group)
        -- Selection strips are pickers, not mirrors: no conditional or
        -- effect previews here, and recycled grid slots keep neither.
        ResetSlotConditionalVisuals(slot)
        slot.icon:SetVertexColor(1, 1, 1, 1)
        ClearSlotEffectPreviews(slot)
        if slot.keybindText then slot.keybindText:Hide() end

        if readOnly then
            slot.icon:SetDesaturated(false)
            DisableReadOnlySlotInteraction(slot)
        else
            local status = CollectEntryStatus(buttonData, group)
            slot.icon:SetDesaturated(not status.usable)
            if status.disabled then
                slot:SetAlpha(PANEL_PREVIEW_DISABLED_ALPHA)
            end
            slot._cdcBaseAlpha = status.disabled and PANEL_PREVIEW_DISABLED_ALPHA or 1
            ApplySlotBadges(slot, status, scale)
            ApplySelectionVisuals(slot, entryInfo.index)
            CopyMode.ApplyTargetVisuals(slot, panelId, buttonData)
            layoutDrag.slots[entryInfo.index] = slot
            WireEntryInteraction(slot, panelId, entryInfo.index, buttonData, status, dragModel)
        end
    end

    local anyAnimated = false
    for _, slot in pairs(layoutDrag.slots) do
        if slot and slot._cdcCondAnim then
            anyAnimated = true
            break
        end
    end
    if not readOnly and anyAnimated then
        EnsureConditionalTicker(preview)
    end

    content:ClearAllPoints()
    content:SetPoint("CENTER", preview.root, "CENTER", 0, 0)

    FinalizePreviewState(preview)
end

PP.BuildSelectionStrip = BuildSelectionStrip

function ST._RefreshIndicatorDisplayVisual(groupId)
    if groupId ~= CS.selectedGroup then return false end
    ST._RefreshButtonsPreviewMirror(groupId)
    return true
end
