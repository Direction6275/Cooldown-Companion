--[[
    CooldownCompanion - Helpers
    Shared settings headings, preview transactions, tooltips, and common controls.

    Part of the Helpers family; see its ordered block in the addon TOC.
    Private helpers are shared through ST._SettingsHelpers.
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon
local AceGUI = LibStub("AceGUI-3.0")
local CS = ST._configState
local ShowPopupAboveConfig = CS.ShowPopupAboveConfig

local SH = ST._SettingsHelpers

-- SettingsNavigation.lua
local RegisterLensAnchorHeading = SH.RegisterLensAnchorHeading

-- The Cooldown Visibility dropdown's user-facing strings, owned here because
-- three surfaces state them: the panel entry row (ButtonConditions), its
-- custom bar twin (ResourceBarPanelsCustomBars), and the preview's "hidden in
-- simulated state" reason text (ButtonPanelPreview), which promises to name
-- the row the way the entry's own tab does. One table keeps a rename on all
-- three at once. Bars offer no dim variants; they read the same labels.
ST._COOLDOWN_VISIBILITY = {
    labels = {
        show = "Always Show",
        dim_cooldown = "Dim On Cooldown",
        hide_cooldown = "Hide On Cooldown",
        dim_ready = "Dim While Ready",
        hide_ready = "Hide While Ready",
        zero_only = "Show Only At 0 Charges",
    },
    tooltipLines = {
        {"Ready means the spell is off cooldown. For a charge spell that is every charge available, and On Cooldown is any charge recharging.", 1, 1, 1, true},
        {" ", 1, 1, 1, true},
        {"Show Only At 0 Charges keeps a charge spell hidden until its last charge is spent.", 1, 1, 1, true},
    },
}

-- Continuous controls in the Buttons workspace render against the pinned
-- mirror while they are being manipulated.  The mirror helper is published
-- later in the config load order, so resolve it at call time.
local function RefreshSelectedButtonsPreview()
    if ST._RefreshButtonsPreviewMirror then
        ST._RefreshButtonsPreviewMirror(CS.selectedGroup, true)
    end
end

local function RefreshActiveConfigPreview()
    -- The Resources destination intentionally leaves selectedContainer in
    -- memory when it clears selectedGroup, so workspace ownership has to win
    -- over the stale Buttons selection here.
    if CS.barsEntrySelected and ST._RefreshResourcesLayoutPreview then
        ST._RefreshResourcesLayoutPreview()
    elseif CS.selectedGroup or CS.selectedContainer then
        RefreshSelectedButtonsPreview()
    end
end

local function PreviewScalarSetting(tbl, key, value, previewFn)
    local committed = tbl[key]
    tbl[key] = value
    previewFn()
    tbl[key] = committed
end

-- Helper: tint AceGUI Heading labels with player class color.
-- Also restores the stock right-line anchors: AceGUI recycles Heading
-- widgets and neither OnAcquire nor SetText repairs the right line, so a
-- heading whose right line was re-anchored to a decoration (info button,
-- collapse arrow, preview badge) carries that stale anchor into its next
-- life. Decorated call sites re-anchor again after calling this.
--
-- The label/left-line reset below is the same defence for the opt-in
-- left-aligned variant further down: those are the two pieces of stock
-- Heading anatomy that neither OnAcquire nor SetText puts back, and the
-- Heading pool is shared with every other addon. Re-asserting the stock
-- state here is a no-op for every centered heading.
local function ColorHeading(heading)
    local cc = C_ClassColor.GetClassColor(select(2, UnitClass("player")))
    if cc then
        heading.label:SetTextColor(cc.r, cc.g, cc.b)
    end
    heading.label:ClearAllPoints()
    heading.label:SetPoint("TOP")
    heading.label:SetPoint("BOTTOM")
    heading.label:SetJustifyH("CENTER")
    heading.left:ClearAllPoints()
    heading.left:SetPoint("LEFT", 3, 0)
    local headingText = heading.label:GetText()
    if headingText and headingText ~= "" then
        heading.left:SetPoint("RIGHT", heading.label, "LEFT", -5, 0)
    else
        heading.left:SetPoint("RIGHT", -3, 0)
    end
    heading.left:Show()
    heading.right:ClearAllPoints()
    heading.right:SetPoint("RIGHT", heading.frame, "RIGHT", -3, 0)
    heading.right:SetPoint("LEFT", heading.label, "RIGHT", 5, 0)
    local rule = heading.frame._cdcHeadingRule
    if rule then
        rule:Hide()
    end
end

-- Helper: attach a reusable collapse/expand arrow button to an AceGUI Heading.
-- Stores the button on heading.frame._cdcCollapseBtn so it survives widget
-- recycling without creating duplicate textures or stale handlers.
local COLLAPSE_ARROW_ATLAS = "glues-characterselect-icon-arrowdown-small"
local COLLAPSE_ROTATION_RIGHT = math.pi / 2   -- collapsed: arrow points right
local COLLAPSE_ROTATION_DOWN  = 0              -- expanded:  arrow points down

local function AttachCollapseButton(heading, isCollapsed, onClickFn)
    local frame = heading.frame
    local btn = frame._cdcCollapseBtn

    if not btn then
        btn = CreateFrame("Button", nil, frame)
        btn:SetSize(16, 16)
        btn._arrow = btn:CreateTexture(nil, "ARTWORK")
        btn._arrow:SetSize(12, 12)
        btn._arrow:SetPoint("CENTER")
        btn._arrow:SetAtlas(COLLAPSE_ARROW_ATLAS)
        frame._cdcCollapseBtn = btn
    end

    btn:SetParent(frame)
    btn:ClearAllPoints()
    btn:SetPoint("LEFT", heading.label, "RIGHT", 4, 0)
    btn:Show()
    btn._arrow:Show()

    heading.right:ClearAllPoints()
    heading.right:SetPoint("RIGHT", frame, "RIGHT", -3, 0)
    heading.right:SetPoint("LEFT", btn, "RIGHT", 4, 0)

    btn._arrow:SetRotation(isCollapsed and COLLAPSE_ROTATION_RIGHT or COLLAPSE_ROTATION_DOWN)

    btn:SetScript("OnClick", onClickFn)
    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(isCollapsed and "Expand" or "Collapse")
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    heading:SetCallback("OnRelease", function()
        btn:ClearAllPoints()
        btn:Hide()
        btn:SetParent(nil)
    end)

    return btn
end

-- Helper: re-shape a Heading into the row-grammar section header: caret at
-- the far left, then the label, then a thin rule fading out to the right,
-- with breathing room above the whole line so sections do not butt together.
-- The stock left/right border textures are hidden rather than re-textured,
-- and the fading rule is cached on heading.frame._cdcHeadingRule so it
-- survives widget recycling without stacking duplicate textures.
--
-- Everything touched here is put back on release, and the acquire side is
-- covered too: ColorHeading above re-asserts the label/left/right anatomy on
-- every acquire, and the taller frame is re-asserted by stock Heading's own
-- OnAcquire (`self:SetHeight(18)`), which is the one piece of state AceGUI
-- resets for us. So a Heading that passes through this variant can never
-- carry it into another addon's use of the shared pool.
local HEADING_CARET_INSET = 2
local HEADING_CARET_SIZE = 16          -- matches AttachCollapseButton's button
local HEADING_CARET_GAP = 4
local HEADING_RULE_GAP = 8
local HEADING_RULE_HEIGHT = 1
local HEADING_RULE_ALPHA = 0.35
-- Stock AceGUI Heading height; its own OnAcquire re-asserts this, which is
-- why the taller variant below only has to undo itself on release.
local HEADING_STOCK_HEIGHT = 18
-- Sections must not butt against each other, and the HEADER owns that gap so
-- every tab stamped from the row-grammar template inherits it. The frame
-- grows by HEADING_TOP_PAD and the header line is pinned to the frame's
-- BOTTOM, so the extra space lands ABOVE the text - air before a section,
-- never after it.
local HEADING_TOP_PAD = 10
-- The header line therefore sits half a pad below the frame's vertical
-- centre. Caret and badges hang off the LABEL and follow it for free, but
-- every point taken against the FRAME carries this offset - LEFT/RIGHT points
-- also declare a vertical centre, and two anchors declaring DIFFERENT centres
-- on the same region is over-constrained and resolves by luck.
local HEADING_LINE_Y = -HEADING_TOP_PAD / 2
-- Caret first, then label. The label sits at this inset whether or not the
-- section has a caret, so collapsible and plain section titles line up.
local HEADING_LABEL_INSET = HEADING_CARET_INSET + HEADING_CARET_SIZE + HEADING_CARET_GAP

-- flush: park the label at the caret column's left edge instead of the shared
-- label inset. For headings that never carry a caret or icon (the family
-- scoping lines), where the reserved column would read as a hole.
local function ApplyLeftAlignedHeading(heading, btn, flush)
    local frame = heading.frame
    local rule = frame._cdcHeadingRule

    if not rule then
        rule = frame:CreateTexture(nil, "BACKGROUND")
        rule:SetTexture("Interface/Buttons/WHITE8x8")
        rule:SetHeight(HEADING_RULE_HEIGHT)
        frame._cdcHeadingRule = rule
    end

    heading.left:Hide()
    heading.right:Hide()

    -- Taller than stock, with the label pushed down by the whole pad: the
    -- text keeps its 18px line at the BOTTOM of the frame and the extra room
    -- opens above it.
    heading:SetHeight(HEADING_STOCK_HEIGHT + HEADING_TOP_PAD)

    heading.label:ClearAllPoints()
    heading.label:SetJustifyH("LEFT")
    heading.label:SetPoint("TOP", frame, "TOP", 0, -HEADING_TOP_PAD)
    heading.label:SetPoint("BOTTOM")
    heading.label:SetPoint("LEFT", frame, "LEFT",
        flush and HEADING_CARET_INSET or HEADING_LABEL_INSET, HEADING_LINE_Y)
    -- Caret hangs off the LABEL, not the frame, so it rides the shifted line
    -- and the label's inset stays the same with or without one.
    if btn then
        btn:ClearAllPoints()
        btn:SetPoint("RIGHT", heading.label, "LEFT", -HEADING_CARET_GAP, 0)
    end

    local r, g, b = 0.8, 0.8, 0.8
    local cc = C_ClassColor.GetClassColor(select(2, UnitClass("player")))
    if cc then
        r, g, b = cc.r, cc.g, cc.b
    end
    rule:ClearAllPoints()
    rule:SetPoint("LEFT", heading.label, "RIGHT", HEADING_RULE_GAP, 0)
    rule:SetPoint("RIGHT", frame, "RIGHT", -3, HEADING_LINE_Y)
    rule:SetGradient("HORIZONTAL", CreateColor(r, g, b, HEADING_RULE_ALPHA), CreateColor(r, g, b, 0))
    rule:Show()

    -- Chain, don't replace: AttachCollapseButton already installed its own
    -- detach handler on this heading.
    local prevOnRelease = heading.events and heading.events["OnRelease"]
    heading:SetCallback("OnRelease", function(widget, event, ...)
        if prevOnRelease then
            prevOnRelease(widget, event, ...)
        end
        rule:Hide()
        rule:ClearAllPoints()
        heading:SetHeight(HEADING_STOCK_HEIGHT)
        heading.label:ClearAllPoints()
        heading.label:SetPoint("TOP")
        heading.label:SetPoint("BOTTOM")
        heading.label:SetJustifyH("CENTER")
        heading.left:ClearAllPoints()
        heading.left:SetPoint("LEFT", 3, 0)
        heading.left:SetPoint("RIGHT", heading.label, "LEFT", -5, 0)
        heading.left:Show()
        heading.right:ClearAllPoints()
        heading.right:SetPoint("RIGHT", heading.frame, "RIGHT", -3, 0)
        heading.right:SetPoint("LEFT", heading.label, "RIGHT", 5, 0)
        heading.right:Show()
    end)

    return rule
end

-- Re-anchor a left-aligned heading's fading rule to sit after the last badge
-- on the heading line. Returns false for centered headings so decorated call
-- sites can fall back to their stock `heading.right` re-anchor.
local function AnchorLeftAlignedHeadingRule(heading, afterFrame)
    local frame = heading and heading.frame
    local rule = frame and frame._cdcHeadingRule
    if not (rule and rule:IsShown()) then
        return false
    end
    rule:ClearAllPoints()
    rule:SetPoint("LEFT", afterFrame or heading.label, "RIGHT", HEADING_RULE_GAP, 0)
    -- Badges are label-anchored, so the LEFT point already rides the header
    -- line; the frame-anchored RIGHT point has to be dropped to match it.
    rule:SetPoint("RIGHT", frame, "RIGHT", -3, HEADING_LINE_Y)
    return true
end

-- Append one decoration to a heading's badge line and keep the trailing rule
-- (or the stock right line) behind it.
--
-- The chain grows label -> first badge -> second badge, so N decorations
-- compose without any caller having to know what came before it: the tail is
-- kept on the heading's FRAME, which is what AceGUI recycles. The tail is
-- cleared on release for the same reason ApplyLeftAlignedHeading restores the
-- stock anatomy there - a Heading that comes back out of the shared pool must
-- not still be chaining off a decoration from its previous life.
local HEADING_BADGE_GAP = 4

local function ChainHeadingBadges(heading, widget)
    local frame = heading and heading.frame
    if not (frame and widget) then
        return widget
    end

    local tail = frame._cdcHeadingBadgeTail or heading.label
    widget:SetParent(frame)
    widget:ClearAllPoints()
    widget:SetPoint("LEFT", tail, "RIGHT", HEADING_BADGE_GAP, 0)
    frame._cdcHeadingBadgeTail = widget

    -- Left-aligned headings fade a rule out to the right of the line; centered
    -- ones use the stock right texture. Same branch every badge helper takes.
    if not AnchorLeftAlignedHeadingRule(heading, widget) then
        heading.right:ClearAllPoints()
        heading.right:SetPoint("RIGHT", frame, "RIGHT", -3, 0)
        heading.right:SetPoint("LEFT", widget, "RIGHT", HEADING_BADGE_GAP, 0)
    end

    -- Chain, don't replace: the collapse button and the left-aligned variant
    -- already installed handlers of their own on this heading.
    local prevOnRelease = heading.events and heading.events["OnRelease"]
    heading:SetCallback("OnRelease", function(w, event, ...)
        if prevOnRelease then
            prevOnRelease(w, event, ...)
        end
        frame._cdcHeadingBadgeTail = nil
    end)

    return widget
end

local function BuildCollapsibleSection(container, title, key, store, refreshFn, opts)
    store = store or CS.collapsedSections
    local heading = AceGUI:Create("Heading")
    heading:SetText(title)
    ColorHeading(heading)
    heading:SetFullWidth(true)
    container:AddChild(heading)
    if RegisterLensAnchorHeading then
        RegisterLensAnchorHeading(heading, key)
    end

    local collapsed = store[key]
    local btn = AttachCollapseButton(heading, collapsed, function()
        store[key] = not store[key]
        if refreshFn then
            refreshFn()
        else
            CooldownCompanion:RefreshConfigPanel()
        end
    end)

    -- The navigated-to section (gear / Customizations link): remember its
    -- heading so the deferred fire can scroll to it and pulse it. First match
    -- wins - a route can force several nested keys open, and the first one
    -- built is the outermost destination.
    local pendingHighlight = CS.pendingSettingHighlight
    if pendingHighlight and pendingHighlight.collapseKeys
        and pendingHighlight.collapseKeys[key]
        and not pendingHighlight.headingWidget then
        pendingHighlight.headingWidget = heading
    end

    if opts and opts.leftAligned then
        ApplyLeftAlignedHeading(heading, btn)
    end

    return heading, collapsed, btn
end

------------------------------------------------------------------------
-- Entry identity heading
------------------------------------------------------------------------

-- One quiet line at the top of an entry pane (Settings, Aura, and the
-- trigger panels' Condition) naming what the tabs below are editing: the
-- entry's icon, its display name, and its tracking kind. Informational, not
-- a section, so it carries no caret and no collapse state - but it keeps the
-- row grammar's shape, so the sections that follow line up under it.
local IDENTITY_ICON_SIZE = 18
-- Spell and item art ships with a baked border that reads as a pasted
-- sticker at this size, so the outer 8% is trimmed off - the crop every
-- other icon in the config wears.
local IDENTITY_ICON_CROP = 0.08
-- The "Editing:" breadcrumb's muted grey, so "(Spell)" reads the same in
-- both places.
local IDENTITY_KIND_COLOR = "|cff7d7566"
-- Stock GameFontNormal gold. The section headings below wear the class
-- colour; this line names the entry rather than opening a section, so it
-- stays the plain heading gold and does not read as one of them.
local IDENTITY_LABEL_COLOR = { 1, 0.82, 0 }

-- Cached on the heading's FRAME, which is what AceGUI recycles, so a heading
-- that passes through here twice does not stack duplicate textures. Hidden
-- again on release (below) for the same reason the fading rule is: the
-- Heading pool is shared with every other user of it.
local function EnsureIdentityHeadingIcon(heading)
    local frame = heading.frame
    local icon = frame._cdcIdentityIcon
    if not icon then
        icon = frame:CreateTexture(nil, "OVERLAY")
        icon:SetSize(IDENTITY_ICON_SIZE, IDENTITY_ICON_SIZE)
        -- Set once: the crop survives every later SetTexture.
        icon:SetTexCoord(IDENTITY_ICON_CROP, 1 - IDENTITY_ICON_CROP,
            IDENTITY_ICON_CROP, 1 - IDENTITY_ICON_CROP)
        frame._cdcIdentityIcon = icon
    end
    return icon
end

-- The "Editing:" breadcrumb's kind string, replicated rather than shared:
-- its owner (UpdateEditingContext in Config/ButtonsWideColumn.lua) keeps it
-- in local scope. Same addedAs fallback the entry name decorations use.
-- Change the two together. Only spell entries carry a kind; items and
-- trigger entries show icon and name alone, exactly as the breadcrumb does.
local function GetEntryIdentityKindText(buttonData)
    if buttonData.type ~= "spell" then return nil end
    local addedAs = buttonData.addedAs
    if addedAs ~= "spell" and addedAs ~= "aura" then
        addedAs = buttonData.isPassive and "aura" or "spell"
    end
    return addedAs == "aura" and "Aura" or "Spell"
end

local function BuildEntryIdentityHeading(container, buttonData)
    if not (container and buttonData) then return nil end

    local name = (ST._GetConfigEntryDisplayName
        and ST._GetConfigEntryDisplayName(buttonData)) or buttonData.name
    if not name or name == "" then return nil end

    local kindText = GetEntryIdentityKindText(buttonData)
    if kindText then
        name = name .. " " .. IDENTITY_KIND_COLOR .. "(" .. kindText .. ")|r"
    end

    local heading = AceGUI:Create("Heading")
    heading:SetText(name)
    -- Restores the stock label/left/right anatomy a recycled Heading can
    -- arrive with stale; the class tint it also applies is overwritten below.
    ColorHeading(heading)
    heading.label:SetTextColor(IDENTITY_LABEL_COLOR[1], IDENTITY_LABEL_COLOR[2],
        IDENTITY_LABEL_COLOR[3])
    heading:SetFullWidth(true)
    container:AddChild(heading)

    -- The icon takes the caret column, so the label sits at the same inset as
    -- every collapsible section heading under it and the whole pane reads on
    -- one left edge.
    local icon = EnsureIdentityHeadingIcon(heading)
    icon:SetTexture((ST._GetButtonIcon and ST._GetButtonIcon(buttonData)) or 134400)
    ApplyLeftAlignedHeading(heading, icon)
    icon:Show()

    -- Chain, don't replace: ApplyLeftAlignedHeading just installed its own
    -- restore handler on this heading.
    local prevOnRelease = heading.events and heading.events["OnRelease"]
    heading:SetCallback("OnRelease", function(widget, event, ...)
        if prevOnRelease then
            prevOnRelease(widget, event, ...)
        end
        icon:Hide()
        icon:ClearAllPoints()
    end)

    return heading
end

-- Helper: add an advanced-settings button on a parent widget (CheckBox or Heading).
-- The button opens the shared side editor when options.build is provided.
local ADVANCED_TOGGLE_ATLAS = "QuestLog-icon-setting"
-- The gear's idle tint. Named because the Customizations list's own gear wears
-- it too (ApplyAdvancedGlyphLook below), and two copies of the same four
-- numbers is two chances for the two gears to stop looking like one control.
local ADVANCED_TOGGLE_IDLE_COLOR = { 0.72, 0.72, 0.72, 0.85 }
-- What the gear says under the pointer. Shared for the same reason.
local ADVANCED_TOGGLE_OPEN_TOOLTIP = "Open advanced settings"

local function GetAdvancedToggleTitle(parentWidget, options)
    if options and options.title and options.title ~= "" then
        return options.title
    end

    local labelText
    if parentWidget.GetLabel then
        labelText = parentWidget:GetLabel()
    elseif parentWidget.text and parentWidget.text.GetText then
        labelText = parentWidget.text:GetText()
    elseif parentWidget.label and parentWidget.label.GetText then
        labelText = parentWidget.label:GetText()
    elseif parentWidget.rowLabel and parentWidget.rowLabel.GetText then
        -- Row-grammar widgets (RowWidgets.lua) name their label rowLabel.
        labelText = parentWidget.rowLabel:GetText()
    end

    if labelText and labelText ~= "" then
        return labelText .. " Advanced"
    end

    return "Advanced Settings"
end

local function BuildAdvancedDescriptor(parentWidget, settingKey, options)
    return {
        settingKey = settingKey,
        title = GetAdvancedToggleTitle(parentWidget, options),
        build = options and options.build,
        isAvailable = options and options.isAvailable,
        context = options and options.context,
        unlock = options and options.unlock,
        -- Keep the editor open across panel/entry lens shifts. Page context
        -- and fresh row registration still govern its lifetime.
        lensAgnostic = not options or options.lensAgnostic ~= false,
    }
end

local function SetAdvancedToggleActive(btn, active)
    if btn and btn._icon then
        if active then
            btn._icon:SetVertexColor(1, 0.82, 0, 1)
        else
            btn._icon:SetVertexColor(ADVANCED_TOGGLE_IDLE_COLOR[1], ADVANCED_TOGGLE_IDLE_COLOR[2],
                ADVANCED_TOGGLE_IDLE_COLOR[3], ADVANCED_TOGGLE_IDLE_COLOR[4])
        end
    end
end

local function SetActiveAdvancedSettingsToggleButton(btn)
    local current = CS.activeAdvancedSettingsToggleButton
    if current and current ~= btn then
        SetAdvancedToggleActive(current, false)
    end

    CS.activeAdvancedSettingsToggleButton = btn
    SetAdvancedToggleActive(btn, true)
end

local function AddAdvancedToggle(parentWidget, settingKey, tabInfoBtns, isEnabled, options)
    local hasEditor = options and type(options.build) == "function" and CS.OpenAdvancedSettingsPanel
    local frame = parentWidget.frame
    local btn = frame._cdcAdvancedBtn
    if not btn then
        btn = CreateFrame("Button", nil, frame)
        btn:SetSize(14, 14)
        btn._icon = btn:CreateTexture(nil, "ARTWORK")
        btn._icon:SetSize(13, 13)
        btn._icon:SetPoint("CENTER")
        btn._icon:SetAtlas(ADVANCED_TOGGLE_ATLAS, false)
        frame._cdcAdvancedBtn = btn
    end
    btn:SetParent(frame)
    btn:ClearAllPoints()
    btn:Enable()
    btn._advancedSettingKey = settingKey

    local prevOnRelease = parentWidget.events and parentWidget.events["OnRelease"]
    parentWidget:SetCallback("OnRelease", function(widget, event, ...)
        if prevOnRelease then prevOnRelease(widget, event, ...) end
        if CS.ReleaseAdvancedSettingsRow then CS.ReleaseAdvancedSettingsRow(settingKey, widget) end
        if widget.SetSettingsDisclosure then widget:SetSettingsDisclosure(nil) end
        btn:ClearAllPoints()
        btn:Hide()
        btn:SetParent(nil)
        btn:SetScript("OnClick", nil)
        btn:SetScript("OnEnter", nil)
        btn:SetScript("OnLeave", nil)
        btn._advancedSettingKey = nil
        SetAdvancedToggleActive(btn, false)
        if CS.activeAdvancedSettingsToggleButton == btn then
            CS.activeAdvancedSettingsToggleButton = nil
        end
        local colBtn = frame._cdcCollapseBtn
        if colBtn then
            colBtn:ClearAllPoints()
            colBtn:Hide()
            colBtn:SetParent(nil)
        end
    end)

    local pending = CS.pendingSettingHighlight
    if pending and pending.rowKey == settingKey then pending.rowWidget = parentWidget end
    if isEnabled == false then
        if CS.CloseAdvancedSettingsPanel then
            CS.CloseAdvancedSettingsPanel({ settingKey = settingKey })
        end
        if parentWidget.SetSettingsDisclosure then parentWidget:SetSettingsDisclosure(nil) end
        btn:Hide()
        btn._icon:Hide()
        table.insert(tabInfoBtns, btn)
        return false, btn
    end

    btn:Show()
    btn._icon:Show()
    if parentWidget.badgeAnchor then
        ST._AnchorRowBadge(parentWidget, btn)
    elseif parentWidget.checkbg then
        btn:SetPoint("LEFT", parentWidget.checkbg, "RIGHT", parentWidget.text:GetStringWidth() + 6, 0)
    end

    -- Register first, build later: the page's inheritance sweeps must finish
    -- before the editor's independently gated body and unlock action exist.
    local isActive = hasEditor and CS.RegisterAdvancedSettingsRow(
        BuildAdvancedDescriptor(parentWidget, settingKey, options), parentWidget, btn) or false
    SetAdvancedToggleActive(btn, isActive)
    if isActive then
        SetActiveAdvancedSettingsToggleButton(btn)
    elseif CS.activeAdvancedSettingsToggleButton == btn then
        CS.activeAdvancedSettingsToggleButton = nil
    end

    local function ToggleEditor()
        AceGUI:ClearFocus()
        if hasEditor then
            CS.OpenAdvancedSettingsPanel(BuildAdvancedDescriptor(parentWidget, settingKey, options))
        end
        GameTooltip:Hide()
    end
    local function DisclosureHint()
        local active = CS.IsAdvancedSettingsPanelOpen(settingKey, options and options.context)
        return active and "Collapse settings" or "Expand settings"
    end
    btn:SetScript("OnClick", ToggleEditor)
    btn:SetScript("OnEnter", function(self)
        if hasEditor and parentWidget.ShowSettingsDisclosureTooltip then
            parentWidget:ShowSettingsDisclosureTooltip()
        else
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(DisclosureHint())
            GameTooltip:Show()
        end
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    if hasEditor and parentWidget.SetSettingsDisclosure then
        parentWidget:SetSettingsDisclosure(ToggleEditor, DisclosureHint, btn)
    end
    table.insert(tabInfoBtns, btn)
    return isActive, btn
end

CS.SetActiveAdvancedSettingsToggleButton = SetActiveAdvancedSettingsToggleButton

------------------------------------------------------------------------
-- INFO BUTTON HELPER
------------------------------------------------------------------------
local tooltipMeasureFrame = CreateFrame("Frame", nil, UIParent)
tooltipMeasureFrame:Hide()

local tooltipMeasureHeader = tooltipMeasureFrame:CreateFontString(nil, "ARTWORK", "GameTooltipHeaderText")
local tooltipMeasureBody = tooltipMeasureFrame:CreateFontString(nil, "ARTWORK", "GameTooltipText")

local function ResetInfoTooltipWidth()
    GameTooltip:SetMinimumWidth(0)
end

local function MeasureInfoTooltipLineWidth(text, isHeader)
    local fs = isHeader and tooltipMeasureHeader or tooltipMeasureBody
    fs:SetText(text or "")
    return fs:GetUnboundedStringWidth()
end

-- Creates a (?) info button anchored to a frame. Replaces the repeated
-- CreateFrameâ†’SetSizeâ†’SetPointâ†’CreateTextureâ†’SetAtlasâ†’tooltip pattern.
--
-- tooltipLines: array of entries. Strings become title lines (AddLine).
--   Tables {text, r, g, b, wrap} become body lines with color/wrapping.
--
-- cleanup: determines lifecycle management.
--   If it's a table:  button is inserted for lifecycle cleanup.
--   If it's an AceGUI widget: button is cleaned up via OnRelease callback.
local function CreateInfoButton(parentFrame, anchorFrame, anchorPoint, anchorRelPoint, xOff, yOff, tooltipLines, cleanup)
    local btn = CreateFrame("Button", nil, parentFrame)
    btn:SetSize(16, 16)
    btn:SetPoint(anchorPoint, anchorFrame, anchorRelPoint, xOff, yOff)
    local icon = btn:CreateTexture(nil, "OVERLAY")
    icon:SetSize(12, 12)
    icon:SetPoint("CENTER")
    icon:SetAtlas("QuestRepeatableTurnin")
    btn:SetScript("OnEnter", function(self)
        ResetInfoTooltipWidth()
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        for _, line in ipairs(tooltipLines) do
            if type(line) == "table" then
                GameTooltip:AddLine(line[1], line[2], line[3], line[4], line[5])
            else
                GameTooltip:AddLine(line)
            end
        end
        GameTooltip:Show()
        -- Expand tooltip width to fit the widest non-wrapping line.
        -- Wrapping lines don't drive width directly but enforce a
        -- comfortable minimum so wrapped text isn't cramped.
        local pad = 20
        local wrapFloor = 250
        local maxW = 0
        local hasWrap = false
        for i, entry in ipairs(tooltipLines) do
            local isWrapping = type(entry) == "table" and entry[5]
            if isWrapping then
                hasWrap = true
            else
                local text = type(entry) == "table" and entry[1] or entry
                local w = MeasureInfoTooltipLineWidth(text, i == 1)
                if w > maxW then maxW = w end
            end
        end
        if hasWrap and maxW < wrapFloor then maxW = wrapFloor end
        if maxW > 0 then
            GameTooltip:SetMinimumWidth(maxW + pad)
            GameTooltip:Show()
        end
    end)
    btn:SetScript("OnLeave", function()
        ResetInfoTooltipWidth()
        GameTooltip:Hide()
    end)

    if cleanup and cleanup.SetCallback then
        -- AceGUI widget: chain OnRelease cleanup so existing handlers (e.g.
        -- collapse/advanced button detach) are preserved.
        local prevOnRelease = cleanup.events and cleanup.events["OnRelease"]
        cleanup:SetCallback("OnRelease", function()
            if prevOnRelease then
                prevOnRelease(cleanup, "OnRelease")
            end
            btn:ClearAllPoints()
            btn:Hide()
            btn:SetParent(nil)
        end)
    else
        -- Array of buttons: insert for lifecycle cleanup.
        if CS.advancedSettingsPanelRefreshing then
            CS.advancedSettingsInfoButtons = CS.advancedSettingsInfoButtons or {}
            cleanup = CS.advancedSettingsInfoButtons
        end
        if type(cleanup) ~= "table" then
            return btn
        end
        table.insert(cleanup, btn)
    end

    return btn
end

local function ResetIndependentAnchorToParent(anchor)
    anchor.point = "CENTER"
    anchor.relativeTo = nil
    anchor.relativePoint = "CENTER"
    anchor.x = 0
    anchor.y = 0
end

local function ValidateIndependentAnchorTarget(frameName)
    local options = { domain = "external" }
    local ok = CooldownCompanion:ValidateAddonFrameAnchorTarget(frameName, options)
    if not ok then
        CooldownCompanion:PrintInvalidAnchorTargetReason(frameName, options)
        return false
    end
    return true
end

-- Row grammar only (RowWidgets.lua): the frame name takes the whole 140px
-- control column, so Pick does not share it - it goes to opts.pickContainer
-- (the head of the grid's other column) instead. The pre-redesign Flow
-- editbox + button pair had no call sites left after the conversion packets.
local function BuildIndependentAnchorTargetRow(container, anchor, applyFn, opts)
    local currentTargetName = anchor.relativeTo
    if not currentTargetName or currentTargetName == "UIParent" then
        currentTargetName = ""
    end

    local function CommitAnchorTargetText(text)
        if text == "" then
            local wasAnchored = anchor.relativeTo and anchor.relativeTo ~= "UIParent"
            if wasAnchored then
                ResetIndependentAnchorToParent(anchor)
            else
                anchor.relativeTo = nil
            end
        else
            local targetFrame = _G[text]
            if not targetFrame then
                CooldownCompanion:Print("Frame '" .. text .. "' not found.")
                CooldownCompanion:RefreshConfigPanel()
                return
            end
            if not ValidateIndependentAnchorTarget(text) then
                CooldownCompanion:RefreshConfigPanel()
                return
            end
            anchor.relativeTo = text
        end
        applyFn()
        CooldownCompanion:RefreshConfigPanel()
    end

    local function StartAnchorTargetPick()
        CS.StartPickFrame(function(name)
            if CS.configFrame then
                CS.configFrame.frame:Show()
            end
            if name then
                if not ValidateIndependentAnchorTarget(name) then
                    CooldownCompanion:RefreshConfigPanel()
                    return
                end
                anchor.point = "TOPLEFT"
                anchor.relativeTo = name
                anchor.relativePoint = "BOTTOMLEFT"
                anchor.x = 0
                anchor.y = -5
                applyFn()
            end
            CooldownCompanion:RefreshConfigPanel()
        end, nil, { domain = "external" })
    end

    local targetRow = ST._AddEditBoxRow(container, {
        label = "Anchor to Frame",
        setting = opts and opts.setting,
        indent = opts and opts.indent,
        value = currentTargetName,
        onEnterPressed = function(text)
            CommitAnchorTargetText(text)
        end,
    })
    if targetRow.editbox and targetRow.editbox.Instructions then
        targetRow.editbox.Instructions:Hide()
    end

    -- Exactly one grammar row tall so the button's centre lands on the
    -- editbox's: Flow insets its single row by 3px and the button is 24 tall,
    -- so 3 + 24 + 3 fills the 30px band. noAutoHeight keeps Flow's own 27px
    -- report from shrinking it back.
    local pickRow = AceGUI:Create("SimpleGroup")
    pickRow:SetFullWidth(true)
    pickRow:SetLayout("Flow")
    pickRow:SetHeight(ST._RowGrammar and ST._RowGrammar.ROW_HEIGHT or 30)
    pickRow.noAutoHeight = true

    local rowPickBtn = AceGUI:Create("Button")
    rowPickBtn:SetText("Pick")
    rowPickBtn:SetAutoWidth(true)
    rowPickBtn:SetCallback("OnClick", StartAnchorTargetPick)
    pickRow:AddChild(rowPickBtn)

    -- Added last so the List-layout column measures a populated row.
    ;((opts and opts.pickContainer) or container):AddChild(pickRow)
    return targetRow
end

------------------------------------------------------------------------
-- COMPACT MODE CONTROLS
------------------------------------------------------------------------
local function NormalizeCompactGrowthDirection(growthDirection)
    if growthDirection == "start" or growthDirection == "left" or growthDirection == "top" then
        return "start"
    end
    if growthDirection == "end" or growthDirection == "right" or growthDirection == "bottom" then
        return "end"
    end
    return "center"
end

-- orientationOverride exists for the Aura Panel row: an Aura BAR Panel is one
-- vertical column no matter what style.barOrientation still says (the aura
-- container's bars branch hard-codes the axis), and a stale horizontal key from
-- before the conversion would otherwise label the row Left/Center/Right for a
-- block that moves up and down.
local function GetCompactGrowthDirectionLabels(group, orientationOverride)
    local style = group.style or {}
    local orientation = orientationOverride or ST.GetPanelLayoutOrientation(group.displayMode, style)
    local growthOrigin = style.growthOrigin or "TOPLEFT"
    if ST.IsCenteredGrowthOrigin(growthOrigin) then
        -- An ACTIVE centered edge hides the compact alignment row entirely
        -- (it supersedes start/center/end), so a centered value here is
        -- axis-mismatched and the runtime folds it to TOPLEFT; these labels
        -- must agree with that fold.
        growthOrigin = "TOPLEFT"
    end
    if orientation == "vertical" then
        local startIsTop = (growthOrigin == "TOPLEFT" or growthOrigin == "TOPRIGHT")
        return {
            start = startIsTop and "Top" or "Bottom",
            center = "Center",
            ["end"] = startIsTop and "Bottom" or "Top",
        }
    end
    local startIsLeft = (growthOrigin == "TOPLEFT" or growthOrigin == "BOTTOMLEFT")
    return {
        start = startIsLeft and "Left" or "Right",
        center = "Center",
        ["end"] = startIsLeft and "Right" or "Left",
    }
end

-- Builds the compact mode row: a CDC-CheckBoxRow whose gear and info badge
-- chain off the end of its label, with the growth-direction and
-- max-visible-buttons controls behind the gear.
--
-- ONE call site, for every mode that offers it: the Layout tab's Arrangement
-- section (GroupTabsLayout.lua). It used to be built three times, once per
-- mode's Appearance tab. Compact mode is packing, so it reads beside the wrap
-- count; its copy membership deliberately stayed on the appearance scope
-- (ST.PANEL_COPY_SCOPES, Defaults.lua).
--
-- Row grammar only (RowWidgets.lua) - the pre-redesign full-width/half-width
-- checkbox shape had no call sites left once the bar and text tabs converted.
-- opts.indent makes it a child row.
--
-- An Aura Panel builds NOTHING here. Blizzard's aura container packs only the
-- active auras, so collapsing is inherent and always on (compactLayout is
-- forced false at birth) and Max Visible Buttons would be a limit CC never
-- applies. The one question that survives - WHICH END the packed block holds -
-- is not a compact-mode sub-setting for such a panel, it is simply how the
-- panel arranges itself, so it lives on the Layout tab's Arrangement section as
-- "Collapse Direction" (owner ruling 2026-08-15) rather than behind a toggle
-- that does not exist here.
local function BuildCompactModeControls(container, group, tabInfoButtons, opts)
    if CooldownCompanion:IsAuraPanel(group) then return end

    local suppressionReasons = CooldownCompanion.GetGroupCompactLayoutSuppressionReasons
        and CooldownCompanion:GetGroupCompactLayoutSuppressionReasons(CS.selectedGroup)
        or nil
    local compactSuppressed = type(suppressionReasons) == "table" and #suppressionReasons > 0

    local function ApplyCompactLayout(val)
        group.compactLayout = val == true
        CooldownCompanion:PopulateGroupButtons(CS.selectedGroup)
        local frame = CooldownCompanion.groupFrames[CS.selectedGroup]
        if frame then frame._layoutDirty = true end
        CooldownCompanion:RefreshConfigPanel()
    end

    local compactCb = ST._AddCheckboxRow(container, {
        label = compactSuppressed and "Compact Mode (temporarily inactive)" or "Compact Mode",
        value = group.compactLayout or false,
        indent = opts and opts.indent,
        onChange = ApplyCompactLayout,
    })
    -- This row's visible label carries a transient suppression suffix, so bind
    -- after construction instead of replacing that runtime explanation with
    -- the catalog's stable searchable label.
    if opts and opts.setting and ST._BindSettingWidget then
        ST._BindSettingWidget(compactCb, opts.setting)
    end

    -- Single rail (AdvancedSettingsPanel.lua): a panel is one narrow column, so
    -- both rows go straight onto the panel scroll and their (?) badges chain off
    -- the end of each row's label. The row builders are read at CALL time, for
    -- the load-order reason stated at AddFontControls' row branch below.
    local function BuildCompactAdvanced(panel)
        -- A centered Growth Direction on the Layout tab already answers the
        -- alignment question per line (owner ruling 2026-08-16), so the
        -- start/center/end row would contradict it and stays hidden.
        local style = group.style or {}
        local centeredActive = ST.GetCenteredGrowthEdge(
            style.growthOrigin,
            ST.GetPanelLayoutOrientation(group.displayMode, style)
        ) ~= nil
        if not centeredActive then
            local growthRow = ST._AddDropdownRow(panel, {
                label = "Growth Direction",
                setting = opts and opts.settings and opts.settings.growth,
                list = GetCompactGrowthDirectionLabels(group),
                order = {"start", "center", "end"},
                value = NormalizeCompactGrowthDirection(group.compactGrowthDirection),
                onChange = function(val)
                    group.compactGrowthDirection = NormalizeCompactGrowthDirection(val)
                    local frame = CooldownCompanion.groupFrames[CS.selectedGroup]
                    if frame then
                        frame._layoutDirty = true
                        if frame:IsShown() then
                            CooldownCompanion:UpdateGroupLayout(CS.selectedGroup)
                        end
                    end
                end,
            })
            -- Anchor args are a placeholder - AnchorRowBadge re-points the button
            -- onto the end of the row's label.
            ST._AnchorRowBadge(growthRow, CreateInfoButton(growthRow.frame, growthRow.frame, "LEFT", "LEFT", 0, 0, {
                "Growth Direction",
                {"Choose which edge acts as the compact anchor icon/bar as visibility changes. Horizontal uses Left/Center/Right, vertical uses Top/Center/Bottom.", 1, 1, 1, true},
            }, tabInfoButtons))
        end

        local totalButtons = #group.buttons
        local function SetMaxVisibleButtons(val)
            val = math.floor(val + 0.5)
            if val >= totalButtons then
                group.maxVisibleButtons = 0
            else
                group.maxVisibleButtons = val
            end
        end
        local maxVisRow = ST._AddSliderRow(panel, {
            label = "Max Visible Buttons",
            setting = opts and opts.settings and opts.settings.maxVisible,
            min = 1, max = math.max(totalButtons, 1), step = 1,
            value = group.maxVisibleButtons == 0 and totalButtons or group.maxVisibleButtons,
            onChange = function(val)
                local committed = group.maxVisibleButtons
                SetMaxVisibleButtons(val)
                RefreshSelectedButtonsPreview()
                group.maxVisibleButtons = committed
            end,
            onRelease = function(val)
                SetMaxVisibleButtons(val)
                CooldownCompanion:RefreshGroupFrame(CS.selectedGroup)
            end,
        })
        -- The cap counts CC's own buttons, and an Aura Only Section builds none
        -- (GroupFrame's visible-button pass skips its members). Said only on a
        -- panel that actually has one, so every other panel reads as before.
        local maxVisTooltip = {
            "Max Visible Buttons",
            {"Limits how many buttons can appear at once. The first buttons (by group order) that pass visibility checks are shown; the rest are hidden.", 1, 1, 1, true},
        }
        if ST.PanelHasAuraSection and ST.PanelHasAuraSection(group) then
            maxVisTooltip[#maxVisTooltip + 1] = {" ", 1, 1, 1, true}
            maxVisTooltip[#maxVisTooltip + 1] = {"Aura Only Sections are not counted.", 1, 1, 1, true}
        end
        ST._AnchorRowBadge(maxVisRow, CreateInfoButton(maxVisRow.frame, maxVisRow.frame, "LEFT", "LEFT", 0, 0,
            maxVisTooltip, tabInfoButtons))
    end

    AddAdvancedToggle(compactCb, "compactLayout", tabInfoButtons, true, {
        title = "Compact Mode Advanced",
        build = BuildCompactAdvanced,
        -- Non-lens lazy spec (ResolveAdvancedUnlock): the shared enable
        -- owns its whole sequence (populate + layout-dirty + rebuild), so
        -- it rides the spec as `run` - the checkbox above runs the same
        -- path.
        unlock = not group.compactLayout and {
            enable = { label = "Enable Compact Mode", run = function() ApplyCompactLayout(true) end },
        } or nil,
    })

    -- (?) tooltip for compact mode. The gear is already chained off the label,
    -- so this info button lands to its right; the anchor args below are a
    -- placeholder - AnchorRowBadge re-points the button.
    local compactTooltip = {
        "Compact Mode",
        {"Compacts visible buttons or bars when hide conditions remove entries, helping centered layouts stay centered.", 1, 1, 1, true},
        {" ", 1, 1, 1},
        {"Auras set to hide |cffffd100While Aura Inactive|r always keep their space reserved. The game hides whether auras are active from addons, so the panel cannot tighten around a hidden aura.", 1, 1, 1, true},
        {" ", 1, 1, 1},
    }
    if compactSuppressed then
        local reasonLabels = {
            frameAnchoring = "Unit Frames",
            resourceBars = "Resources",
            castBar = "Cast Bar",
        }
        local activeLabels = {}
        for _, reason in ipairs(suppressionReasons) do
            activeLabels[#activeLabels + 1] = reasonLabels[reason] or tostring(reason)
        end
        compactTooltip[#compactTooltip + 1] = {
            "Temporarily inactive while these attached features use this panel: "
                .. table.concat(activeLabels, ", ")
                .. ". Your preference is saved and will resume automatically when each attachment is disabled or given an independent anchor.",
            1, 1, 1, true,
        }
    else
        compactTooltip[#compactTooltip + 1] = {
            "When Unit Frames, Resources, or the Cast Bar uses this panel as its attached anchor, Compact Mode pauses temporarily so the attached layout keeps a stable footprint. Your preference remains saved.",
            1, 1, 1, true,
        }
    end
    local compactInfo = CreateInfoButton(compactCb.frame, compactCb.frame, "LEFT", "LEFT", 0, 0,
        compactTooltip, tabInfoButtons)
    ST._AnchorRowBadge(compactCb, compactInfo)
end

local charCopyButtons = {}

local CHARACTER_COPY_TOOLTIP_DETAILS = {
    frameAnchoring = {
        "Copies: enable state, unit-frame addon/custom frame choices, player/target anchors, mirroring, and alpha inheritance.",
        "Does not copy: Resource Bars, Cast Bar, panels, or panel contents.",
    },
    castBar = {
        "Copies: enable state, anchor/position mode, styling, icon, text, and cast effects.",
        "Does not copy: Resource Bars, Unit Frames, panels, or panel contents.",
    },
}

local function CreateCharacterCopyButton(enableCb, systemKey, label, onCopied)
    local _, copyOrder = CooldownCompanion:GetCharacterScopedSettingsCopyOptions(systemKey)
    if #copyOrder == 0 then return end

    -- Pool one button per systemKey to avoid frame leaks across panel rebuilds
    local btn = charCopyButtons[systemKey]
    if not btn then
        btn = CreateFrame("Button", nil, enableCb.frame)
        btn:SetSize(16, 16)

        local icon = btn:CreateTexture(nil, "OVERLAY")
        icon:SetSize(14, 14)
        icon:SetPoint("CENTER")
        icon:SetAtlas("BattleBar-SwapPetIcon", false)

        charCopyButtons[systemKey] = btn
    else
        btn:SetParent(enableCb.frame)
    end

    -- Row-grammar checkboxes have no checkbg/text anatomy: the badge chains
    -- off the end of the row's label instead, like every other row badge.
    -- AnchorRowBadge does the SetParent and ClearAllPoints itself.
    btn:Show()
    if enableCb.badgeAnchor then
        ST._AnchorRowBadge(enableCb, btn)
    else
        btn:ClearAllPoints()
        btn:SetPoint("LEFT", enableCb.checkbg, "RIGHT", enableCb.text:GetStringWidth() + 4, 0)
    end

    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Copy " .. label .. " Settings")
        local tooltipDetails = CHARACTER_COPY_TOOLTIP_DETAILS[systemKey]
        if tooltipDetails then
            for _, line in ipairs(tooltipDetails) do
                if line == "" then
                    GameTooltip:AddLine(" ")
                elseif line == "What is copied:" or line == "What is not copied:" then
                    GameTooltip:AddLine(line, 1, 0.82, 0, true)
                else
                    GameTooltip:AddLine(line, 1, 1, 1, true)
                end
            end
        else
            GameTooltip:AddLine("Copy settings from another character on this profile.", 1, 1, 1, true)
        end
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    btn:SetScript("OnClick", function()
        if not CS.charCopyMenu then
            CS.charCopyMenu = CreateFrame("Frame", "CDCCharCopyMenu", UIParent, "UIDropDownMenuTemplate")
        end
        local vals, order = CooldownCompanion:GetCharacterScopedSettingsCopyOptions(systemKey)
        if #order == 0 then return end

        UIDropDownMenu_Initialize(CS.charCopyMenu, function(self, level)
            for _, charKey in ipairs(order) do
                local info = UIDropDownMenu_CreateInfo()
                info.text = vals[charKey]
                info.notCheckable = true
                info.func = function()
                    CloseDropDownMenus()
                    if not ShowPopupAboveConfig then
                        CooldownCompanion:Print("Copy confirmation is unavailable.")
                        return
                    end
                    ShowPopupAboveConfig("CDC_CONFIRM_CHARACTER_SCOPED_COPY", label .. " settings from " .. (vals[charKey] or charKey) .. " to this character", {
                        systemKey = systemKey,
                        systemLabel = label,
                        sourceCharKey = charKey,
                        onCopied = onCopied,
                    })
                end
                UIDropDownMenu_AddButton(info, level)
            end
        end, "MENU")
        CS.charCopyMenu:SetFrameStrata("FULLSCREEN_DIALOG")
        ToggleDropDownMenu(1, nil, CS.charCopyMenu, "cursor", 0, 0)
    end)

    -- Clean up on widget release (raw frame persists across AceGUI recycling)
    local prevOnRelease = enableCb.events and enableCb.events["OnRelease"]
    enableCb:SetCallback("OnRelease", function()
        if prevOnRelease then
            prevOnRelease(enableCb, "OnRelease")
        end
        btn:ClearAllPoints()
        btn:Hide()
    end)

    return btn
end

-- The modern ColorPickerFrame never delivers AceGUI's OnValueConfirmed:
-- the OK button runs swatchFunc/opacityFunc BEFORE Hide(), so the widget's
-- "picker still open" test routes them to OnValueChanged â€” and its no-change
-- guard swallows them anyway, because the last drag tick already carried the
-- same values. Commit is therefore detected by picker CLOSE. Every close
-- path (OK, Cancel, Esc, any click outside the picker â€” including on
-- another swatch, which cancels via GLOBAL_MOUSE_DOWN before its own click
-- lands) runs through OnHide, and the cancel paths restore the original
-- color into the bound table via OnValueChanged before hiding â€” so flushing
-- the armed commit on hide applies the right value on every path.
local pendingColorCommit
local colorCommitHookInstalled
local function ArmColorCommitOnClose(onConfirmedFn)
    if not colorCommitHookInstalled then
        if not ColorPickerFrame then return end
        colorCommitHookInstalled = true
        ColorPickerFrame:HookScript("OnHide", function()
            local commit = pendingColorCommit
            pendingColorCommit = nil
            if commit then commit() end
        end)
    end
    pendingColorCommit = onConfirmedFn
end

-- Helper: wire up OnValueChanged and OnValueConfirmed for a ColorPicker widget.
-- Stores {r,g,b,a} into tbl[key]. onConfirmedFn fires when the color picker
-- closes (via the commit-on-close bridge above); onChangeFn (optional) fires
-- during drag for live preview.
-- With deferCommit, the drag value never rests in the bound table: it is
-- swapped in only for the duration of the onChangeFn call and committed for
-- real when the picker closes. Use it when a live renderer re-reads the same
-- table every tick and must keep showing the committed color during a drag.
local function SetupColorCallbacks(widget, tbl, key, onConfirmedFn, onChangeFn, deferCommit)
    widget:SetCallback("OnValueChanged", function(_, _, r, g, b, a)
        if deferCommit then
            -- Deferred mode: the live renderers re-read this table every tick,
            -- so an uncommitted drag value may only exist in it for the moment
            -- the config canvas rebuild reads it. Arm the close commit FIRST so
            -- a failed refresh still converges when the picker closes â€” and arm
            -- it unconditionally, because this closure is the only writer of
            -- tbl[key] in deferred mode; without it the edit would be silently
            -- discarded when no confirm callback is supplied.
            local pending = {r, g, b, a}
            ArmColorCommitOnClose(function()
                tbl[key] = pending
                if onConfirmedFn then onConfirmedFn() end
            end)
            local committed = tbl[key]
            tbl[key] = pending
            if onChangeFn then onChangeFn() end
            tbl[key] = committed
        else
            tbl[key] = {r, g, b, a}
            if onConfirmedFn then ArmColorCommitOnClose(onConfirmedFn) end
            if onChangeFn then onChangeFn() end
        end
    end)
    -- Kept wired so nothing double-fires if a future Ace3 update restores
    -- OnValueConfirmed: disarm the pending close commit before running it here.
    widget:SetCallback("OnValueConfirmed", function(_, _, r, g, b, a)
        pendingColorCommit = nil
        tbl[key] = {r, g, b, a}
        if onConfirmedFn then onConfirmedFn() end
    end)
end

------------------------------------------------------------------------
-- WIDGET FACTORIES
-- Composable builders that replace repeated AceGUI boilerplate.
-- Each creates, configures, and adds to container; single-widget factories return the widget.
------------------------------------------------------------------------

-- Create an anchor-point row using the pre-built list from State.lua.
-- Optional label param overrides the default "Anchor" label.
--
-- Row grammar only (RowWidgets.lua); opts.indent makes it a child row. The
-- pre-redesign full-width stock Dropdown had no call sites left after the
-- conversion packets.
--
-- The row builder is read at CALL time rather than hoisted to file scope:
-- Helpers.lua loads BEFORE RowWidgets.lua (TOC 46 vs 47), so ST._AddDropdownRow
-- does not exist yet while this file is being read.
local function AddAnchorDropdown(container, tbl, key, default, refreshFn, label, opts)
    return ST._AddDropdownRow(container, {
        label = label or "Anchor",
        setting = opts and opts.setting,
        indent = opts and opts.indent,
        list = CS.anchorDropdownList,
        order = CS.anchorPoints,
        value = tbl[key] or default,
        onChange = function(val)
            tbl[key] = val
            refreshFn()
        end,
    })
end

-- One compact positioning group for bar-panel and custom-bar text. Optional
-- preparation materializes an aura-only panel's first independent edit. Drag
-- previews restore raw saved values, including absent override keys.
local function AddBarTextPositionControls(container, tbl, anchorKey, xKey, yKey, refreshFn, opts)
    opts = opts or {}
    local settings = opts.settings or {}
    local list, order = {}, {}
    if opts.automatic then
        list.AUTO = "Automatic"
        order[1] = "AUTO"
    end
    for _, point in ipairs(CS.anchorPoints) do
        list[point] = CS.anchorDropdownList[point]
        order[#order + 1] = point
    end
    local point, x, y
    if opts.resolve then
        point, x, y = opts.resolve()
    else
        point = tbl[anchorKey] or (opts.automatic and "AUTO" or "CENTER")
        x, y = tbl[xKey] or 0, tbl[yKey] or 0
    end
    local function Set(key, value)
        if opts.prepare then opts.prepare() end
        tbl[key] = value
    end
    local function Commit(key, value)
        if opts.disabled then return end
        Set(key, value)
        refreshFn()
    end
    local function Preview(key, value)
        if opts.disabled then return end
        local keys = { anchorKey, xKey, yKey }
        if opts.prepareKey then keys[#keys + 1] = opts.prepareKey end
        local saved = {}
        for _, field in ipairs(keys) do saved[field] = rawget(tbl, field) end
        Set(key, value)
        local previewRefresh = opts.previewRefresh or RefreshSelectedButtonsPreview
        previewRefresh()
        for _, field in ipairs(keys) do tbl[field] = saved[field] end
    end
    local anchorRow = ST._AddDropdownRow(container, {
        label = "Anchor", setting = settings.anchor,
        list = list, order = order, value = point, disabled = opts.disabled,
        onChange = function(value) Commit(anchorKey, value) end,
    })
    local xRow = ST._AddSliderRow(container, {
        label = "X Offset", setting = settings.xOffset,
        min = -50, max = 50, step = 0.1, value = x, disabled = opts.disabled,
        onChange = function(value) Preview(xKey, value) end,
        onRelease = function(value) Commit(xKey, value) end,
    })
    local yRow = ST._AddSliderRow(container, {
        label = "Y Offset", setting = settings.yOffset,
        min = -50, max = 50, step = 0.1, value = y, disabled = opts.disabled,
        onChange = function(value) Preview(yKey, value) end,
        onRelease = function(value) Commit(yKey, value) end,
    })
    return anchorRow, xRow, yRow
end
ST._AddBarTextPositionControls = AddBarTextPositionControls

-- LibSharedMedia font names run well past the 140px control column, and a
-- dropdown sizes its menu from the control it hangs under.
local FONT_ROW_PULLOUT_WIDTH = 300

-- Create Font Size slider + Font dropdown + Font Outline dropdown.
-- prefix: key prefix (e.g. "cooldown" reads cooldownFont, cooldownFontSize, cooldownFontOutline).
-- defaults: {size, sizeMin, sizeMax, sizeStep, font, outline} â€” all optional with sane fallbacks.
--
-- Row grammar only (RowWidgets.lua); opts.indent makes them child rows. The
-- pre-redesign full-width stock trio had no call sites left after the
-- conversion packets.
--
-- The row builders are read at CALL time rather than hoisted to file scope:
-- Helpers.lua loads BEFORE RowWidgets.lua (TOC 46 vs 47), so ST._AddSliderRow
-- does not exist yet while this file is being read. Same rule the alpha and
-- anchor-target builders above follow.
local function AddFontControls(container, tbl, prefix, defaults, refreshFn, opts)
    local fontKey = prefix .. "Font"
    local sizeKey = prefix .. "FontSize"
    local outlineKey = prefix .. "FontOutline"
    local indent = opts and opts.indent
    local settings = opts and opts.settings or nil
    -- The slider is mirror-first everywhere. Resources and cast bars provide
    -- their own canvas callback; ordinary panel controls use the pinned
    -- Buttons preview. Dropdowns have no drag phase and remain discrete live
    -- commits through refreshFn.
    local previewRefresh = (opts and opts.previewRefresh) or RefreshSelectedButtonsPreview

    ST._AddSliderRow(container, {
        label = "Font Size",
        setting = settings and settings.size,
        indent = indent,
        min = defaults.sizeMin or 8,
        max = defaults.sizeMax or 32,
        step = defaults.sizeStep or 1,
        value = tbl[sizeKey] or defaults.size or 12,
        onChange = function(val)
            PreviewScalarSetting(tbl, sizeKey, val, previewRefresh)
        end,
        onRelease = function(val)
            tbl[sizeKey] = val
            refreshFn()
        end,
    })

    -- FONT ROW (the Item Settings pilot's rule, stated at that call site):
    -- the row is created with a label and a widened pullout but NO list and
    -- NO onChange, then handed to the shared font helpers exactly as a
    -- stock Dropdown would be. CDC-DropdownRow forwards SetList/SetDisabled
    -- to its embedded child and forwards the child's OnOpened with
    -- self = the row (aliasing row.pullout), which is everything
    -- CS.SetupFontDropdown touches. AddDropdownRow registers OnValueChanged
    -- only when opts.onChange is given, so SetFontDropdownCallback is the
    -- one registration and the profile-wide font lock still gates every
    -- write. The value is set AFTER SetupFontDropdown, because SetList
    -- rebuilds the list the displayed text is read from.
    local fontRow = ST._AddDropdownRow(container, {
        label = "Font",
        setting = settings and settings.font,
        indent = indent,
        pulloutWidth = FONT_ROW_PULLOUT_WIDTH,
    })
    CS.SetupFontDropdown(fontRow)
    fontRow:SetValue(tbl[fontKey] or defaults.font or "Friz Quadrata TT")
    CS.SetFontDropdownCallback(fontRow, function(widget, event, val)
        tbl[fontKey] = val
        refreshFn()
    end)

    local outlineRow = ST._AddDropdownRow(container, {
        label = "Font Outline",
        setting = settings and settings.outline,
        indent = indent,
    })
    CS.SetupFontOutlineDropdown(outlineRow)
    outlineRow:SetValue(tbl[outlineKey] or defaults.outline or "OUTLINE")
    CS.SetFontOutlineDropdownCallback(outlineRow, function(widget, event, val)
        tbl[outlineKey] = val
        refreshFn()
    end)
end

-- Create X Offset + Y Offset slider pair.
-- defaults: {x, y, range (default 20), step (default 0.1)}
--
-- Row grammar only (RowWidgets.lua); opts.indent makes them child rows. Same
-- call-time row-builder read as AddFontControls above, and for the same
-- load-order reason. The pre-redesign full-width stock pair had no call sites
-- left after the conversion packets.
local function AddOffsetSliders(container, tbl, xKey, yKey, defaults, refreshFn, opts)
    local range = defaults.range or 20
    local step = defaults.step or 0.1
    local indent = opts and opts.indent
    local settings = opts and opts.settings or nil
    local previewRefresh = (opts and opts.previewRefresh) or RefreshSelectedButtonsPreview

    local xRow = ST._AddSliderRow(container, {
        label = "X Offset",
        setting = settings and settings.x,
        indent = indent,
        min = -range, max = range, step = step,
        value = tbl[xKey] or defaults.x or 0,
        onChange = function(val)
            PreviewScalarSetting(tbl, xKey, val, previewRefresh)
        end,
        onRelease = function(val)
            tbl[xKey] = val
            refreshFn()
        end,
    })

    local yRow = ST._AddSliderRow(container, {
        label = "Y Offset",
        setting = settings and settings.y,
        indent = indent,
        min = -range, max = range, step = step,
        value = tbl[yKey] or defaults.y or 0,
        onChange = function(val)
            PreviewScalarSetting(tbl, yKey, val, previewRefresh)
        end,
        onRelease = function(val)
            tbl[yKey] = val
            refreshFn()
        end,
    })

    return xRow, yRow
end

local BORDER_THICKNESS_MODE_TOOLTIPS = {
    [ST.BORDER_RENDER_MODE_CUSTOM] = {
        "Custom Thickness",
        "Uses the Border Size slider, including fractional values.",
    },
    [ST.BORDER_RENDER_MODE_CRISP] = {
        "One-pixel",
        "Uses a stable one-pixel border for your current UI scale.",
    },
}

local function AddDropdownItemTooltips(dropdown, tooltipByValue)
    if not (dropdown and dropdown.pullout and tooltipByValue) then return end

    for _, item in dropdown.pullout:IterateItems() do
        local value = item.userdata and item.userdata.value
        local tooltip = tooltipByValue[value]
        if tooltip then
            item:SetCallback("OnEnter", function(widget)
                GameTooltip:SetOwner(widget.frame, "ANCHOR_RIGHT")
                GameTooltip:AddLine(tooltip[1], 1, 0.82, 0, true)
                GameTooltip:AddLine(tooltip[2], 1, 1, 1, true)
                GameTooltip:Show()
            end)
            item:SetCallback("OnLeave", function()
                GameTooltip:Hide()
            end)
        end
    end
end

-- Row grammar only (RowWidgets.lua); opts.indent makes it a child row. The
-- pre-redesign full-width stock Dropdown had no call sites left after the
-- conversion packets.
local function AddBorderRenderModeDropdown(container, tbl, key, refreshFn, disabled, opts)
    key = key or "borderRenderMode"
    local controlsDisabled = disabled == true or ST.IsBorderThicknessLocked()
    local modeList = {
        [ST.BORDER_RENDER_MODE_CUSTOM] = "Custom Thickness",
        [ST.BORDER_RENDER_MODE_CRISP] = "One-pixel",
    }
    local modeOrder = { ST.BORDER_RENDER_MODE_CUSTOM, ST.BORDER_RENDER_MODE_CRISP }

    local function ApplyRenderMode(val)
        if controlsDisabled then return end
        tbl[key] = ST.GetBorderRenderMode(val)
        if refreshFn then
            refreshFn()
        end
    end

    local modeRow = ST._AddDropdownRow(container, {
        label = "Border Thickness",
        setting = opts and opts.setting,
        indent = opts and opts.indent,
        list = modeList,
        order = modeOrder,
        value = ST.GetBorderRenderMode(tbl, key),
        disabled = controlsDisabled,
        onChange = ApplyRenderMode,
    })
    AddDropdownItemTooltips(modeRow, BORDER_THICKNESS_MODE_TOOLTIPS)
    modeRow:SetCallback("OnClosed", function()
        GameTooltip:Hide()
    end)

    return ST.GetBorderRenderMode(tbl, key), modeRow
end

-- Expose helpers for other ConfigSettings files
ST._ColorHeading = ColorHeading
ST._AttachCollapseButton = AttachCollapseButton
ST._ApplyLeftAlignedHeading = ApplyLeftAlignedHeading
ST._AnchorLeftAlignedHeadingRule = AnchorLeftAlignedHeadingRule
ST._BuildEntryIdentityHeading = BuildEntryIdentityHeading
ST._ChainHeadingBadges = ChainHeadingBadges
ST._BuildCollapsibleSection = BuildCollapsibleSection
ST._AddAdvancedToggle = AddAdvancedToggle

ST._CreateInfoButton = CreateInfoButton

ST._BuildCompactModeControls = BuildCompactModeControls
-- The compact vocabulary outlives the compact section: an Aura Panel's
-- Collapse Direction row (GroupTabsLayout.lua, Arrangement) asks the same
-- start/center/end question against the same compactGrowthDirection key, so it
-- reads and writes through these two rather than restating the mapping.
ST._GetCompactGrowthDirectionLabels = GetCompactGrowthDirectionLabels
ST._NormalizeCompactGrowthDirection = NormalizeCompactGrowthDirection
ST._CreateCharacterCopyButton = CreateCharacterCopyButton
ST._AddAnchorDropdown = AddAnchorDropdown
ST._RefreshSelectedButtonsPreview = RefreshSelectedButtonsPreview
ST._RefreshActiveConfigPreview = RefreshActiveConfigPreview
ST._PreviewScalarSetting = PreviewScalarSetting
-- Exposed so the row-grammar color row can bind the exact same
-- commit-on-close contract described above (see RowWidgets.lua).
ST._SetupColorCallbacks = SetupColorCallbacks

-- Shared alpha UI builder for groups, containers, resource bars, and other
-- shared alpha consumers.
-- container: AceGUI parent widget
-- config: table with alpha fields (baselineAlpha, forceAlpha*, forceHide*, fade*, etc.)
-- refreshFn: function called after value changes (typically RefreshConfigPanel)
-- collapseKey: string key for CS.collapsedSections
-- opts (optional): { previewRefresh = fn(), onBaselinePreview = fn(val),
-- onBaselineCommitted = fn(val), isGlobal = bool, disabled = bool,
-- disabledText = string, infoButtons = table, hideHeading = bool,
-- leadingRows = fn(leftTarget, rightTarget), settings = finder descriptor map }
--
-- Row grammar only (RowWidgets.lua): a collapsible left-aligned section header
-- and a two-column grid of fixed-height rows. Every caller opts in, so there is
-- no stock shape left to draw; opts.row is accepted and ignored for callers
-- that still state it.
local function BuildAlphaControls(container, config, refreshFn, collapseKey, opts)
    opts = opts or {}
    local finderSettings = opts.settings or {}
    local tabInfoBtns = opts.infoButtons or CS.tabInfoButtons
    local controlsDisabled = opts.disabled == true
    local previewRefresh = opts.previewRefresh or RefreshSelectedButtonsPreview

    local function ApplyAlphaSettingChange(refreshPanel)
        if CooldownCompanion.RefreshAlphaUpdateDriver then
            CooldownCompanion:RefreshAlphaUpdateDriver()
        end
        if refreshPanel and refreshFn then
            refreshFn()
        end
    end

    local ALPHA_TOOLTIP = {
        "Alpha",
        {"Controls transparency: 1 is fully visible, 0 is hidden.\n\nThe first four options (In Combat, Out of Combat, Regular Mount, Skyriding) cycle on click through Disabled, |cff00ff00Fully Visible|r, and |cffff0000Fully Hidden|r.\n\n|cff00ff00Fully Visible|r forces the display fully shown while its condition applies; |cffff0000Fully Hidden|r hides it.\n\nIf both apply at once, |cff00ff00Fully Visible|r wins.", 1, 1, 1, true},
    }

    if opts.hideHeading ~= true then
        local alphaHeading, alphaCollapsed = BuildCollapsibleSection(container, "Alpha", collapseKey, nil, nil, { leftAligned = true })

        -- The tooltip describes the whole section (the tri-state force
        -- conditions above all), so it rides the header rather than badging
        -- the Baseline Alpha row: a slider row's track starts exactly where a
        -- badge chain would run into it.
        local headingInfoBtn = CreateInfoButton(alphaHeading.frame, alphaHeading.label, "LEFT", "RIGHT", 4, 0,
            ALPHA_TOOLTIP, tabInfoBtns)
        AnchorLeftAlignedHeadingRule(alphaHeading, headingInfoBtn)

        if alphaCollapsed then return end
    end

    if controlsDisabled and opts.disabledText and opts.disabledText ~= "" then
        local disabledLabel = AceGUI:Create("Label")
        if ST._ConfigureWrappedHelperLabel then
            ST._ConfigureWrappedHelperLabel(disabledLabel)
        end
        disabledLabel:SetText("|cff888888" .. opts.disabledText .. "|r")
        disabledLabel:SetFullWidth(true)
        container:AddChild(disabledLabel)
    end

    -- LEFT column holds the baseline and the four combat/mount force
    -- conditions, RIGHT the unit and mouseover conditions plus the fade
    -- behaviour they all share. Both halves are top-aligned, so the gated
    -- child rows on either side just end their column early.
    local leftTarget, rightTarget = ST._BeginRowGrid(container)

    -- One caller leads the grid with rows of its own: the panel Visibility tab
    -- puts the Panel Alpha source row here, because it decides whether
    -- everything below it is live. Nothing else in the section depends on it,
    -- so it is a plain hook rather than another opts flag per row.
    if opts.leadingRows then
        opts.leadingRows(leftTarget, rightTarget)
    end

    local function ApplyBaselineAlpha(val)
        if controlsDisabled then return end
        local committed = config.baselineAlpha
        config.baselineAlpha = val
        if opts.onBaselinePreview then
            opts.onBaselinePreview(val)
        else
            previewRefresh()
        end
        config.baselineAlpha = committed
    end

    ST._AddSliderRow(leftTarget, {
        label = "Baseline Alpha",
        setting = finderSettings.baseline,
        min = 0, max = 1, step = 0.1,
        value = config.baselineAlpha or 1,
        disabled = controlsDisabled,
        onChange = ApplyBaselineAlpha,
        onRelease = function(val)
            if controlsDisabled then return end
            config.baselineAlpha = val
            if opts.onBaselineCommitted then
                opts.onBaselineCommitted(val)
            end
            ApplyAlphaSettingChange(false)
        end,
    })

    do
        local function GetTriState(visibleKey, hiddenKey)
            if config[hiddenKey] then return nil end
            if config[visibleKey] then return true end
            return false
        end

        local function TriStateLabel(base, value)
            if value == true then
                return base .. " - |cff00ff00Fully Visible|r"
            elseif value == nil then
                return base .. " - |cffff0000Fully Hidden|r"
            end
            return base
        end

        local function ApplyTriState(visibleKey, hiddenKey, newVal)
            if controlsDisabled then return end
            config[visibleKey] = (newVal == true)
            config[hiddenKey] = (newVal == nil)
            ApplyAlphaSettingChange(true)
        end

        local function AddTriStateToggle(parent, label, visibleKey, hiddenKey, setting)
            local val = GetTriState(visibleKey, hiddenKey)
            local row = ST._AddCheckboxRow(parent, {
                label = TriStateLabel(label, val),
                tristate = true,
                value = val,
                disabled = controlsDisabled,
                onChange = function(newVal)
                    ApplyTriState(visibleKey, hiddenKey, newVal)
                end,
            })
            -- Keep the visible state suffix. Passing setting= above would
            -- replace the dynamic label with the catalog's base label.
            if setting and ST._BindSettingWidget then
                ST._BindSettingWidget(row, setting)
            end
            return row
        end

        AddTriStateToggle(leftTarget, "In Combat", "forceAlphaInCombat", "forceHideInCombat", finderSettings.combat)
        AddTriStateToggle(leftTarget, "Out of Combat", "forceAlphaOutOfCombat", "forceHideOutOfCombat", finderSettings.outOfCombat)
        AddTriStateToggle(leftTarget, "Regular Mount", "forceAlphaRegularMounted", "forceHideRegularMounted", finderSettings.regularMount)
        AddTriStateToggle(leftTarget, "Skyriding", "forceAlphaDragonriding", "forceHideDragonriding", finderSettings.skyriding)

        local mountedActive = config.forceAlphaRegularMounted
            or config.forceHideRegularMounted
            or config.forceAlphaDragonriding
            or config.forceHideDragonriding
        local isDruid = CooldownCompanion._playerClassID == 11
        if mountedActive and (opts.isGlobal or isDruid) then
            local travelVal = config.treatTravelFormAsMounted or false
            local function ApplyTravelForm(val)
                if controlsDisabled then return end
                config.treatTravelFormAsMounted = val
                ApplyAlphaSettingChange(false)
            end

            -- Child of the two mount toggles above it, so it is indented and
            -- stays in their column.
            ST._AddCheckboxRow(leftTarget, {
                label = "Include Druid Travel Form (applies to both)",
                setting = finderSettings.travelForm,
                indent = true,
                value = travelVal,
                disabled = controlsDisabled,
                onChange = ApplyTravelForm,
            })
        end

        local function ApplyForceFlag(key, val, refreshPanel)
            if controlsDisabled then return end
            config[key] = val
            ApplyAlphaSettingChange(refreshPanel)
        end

        local targetVal = config.forceAlphaTargetExists or false
        local targetLabel = targetVal and "Target Exists - |cff00ff00Fully Visible|r" or "Target Exists"
        local targetRow = ST._AddCheckboxRow(rightTarget, {
            label = targetLabel,
            value = targetVal,
            disabled = controlsDisabled,
            onChange = function(val) ApplyForceFlag("forceAlphaTargetExists", val, true) end,
        })
        if finderSettings.target and ST._BindSettingWidget then
            ST._BindSettingWidget(targetRow, finderSettings.target)
        end

        if targetVal then
            ST._AddCheckboxRow(rightTarget, {
                label = "Enemy Only",
                setting = finderSettings.enemy,
                indent = true,
                value = config.forceAlphaTargetEnemyOnly or false,
                disabled = controlsDisabled,
                onChange = function(val) ApplyForceFlag("forceAlphaTargetEnemyOnly", val, true) end,
            })
        end

        local focusVal = config.forceAlphaFocusExists or false
        local focusLabel = focusVal and "Focus Exists - |cff00ff00Fully Visible|r" or "Focus Exists"
        local focusRow = ST._AddCheckboxRow(rightTarget, {
            label = focusLabel,
            value = focusVal,
            disabled = controlsDisabled,
            onChange = function(val) ApplyForceFlag("forceAlphaFocusExists", val, true) end,
        })
        if finderSettings.focus and ST._BindSettingWidget then
            ST._BindSettingWidget(focusRow, finderSettings.focus)
        end

        local mouseoverVal = config.forceAlphaMouseover or false
        local mouseoverLabel = mouseoverVal and "Mouseover - |cff00ff00Fully Visible|r" or "Mouseover"
        local mouseoverRow = ST._AddCheckboxRow(rightTarget, {
            label = mouseoverLabel,
            value = mouseoverVal,
            disabled = controlsDisabled,
            onChange = function(val) ApplyForceFlag("forceAlphaMouseover", val, true) end,
        })
        if finderSettings.mouseover and ST._BindSettingWidget then
            ST._BindSettingWidget(mouseoverRow, finderSettings.mouseover)
        end
        -- Row grammar: the badge hangs off the end of the label. The anchor
        -- args below are a placeholder - AnchorRowBadge re-points it.
        ST._AnchorRowBadge(mouseoverRow, CreateInfoButton(mouseoverRow.frame, mouseoverRow.frame, "LEFT", "LEFT", 0, 0, {
            "Mouseover",
            {"When enabled, mousing over forces full visibility. Like all |cff00ff00Force Visible|r conditions, this overrides |cffff0000Force Hidden|r.", 1, 1, 1, true},
        }, tabInfoBtns))

        local function ApplyCustomFade(val)
            if controlsDisabled then return end
            config.customFade = val or nil
            ApplyAlphaSettingChange(true)
        end

        ST._AddCheckboxRow(rightTarget, {
            label = "Custom Fade Settings",
            setting = finderSettings.customFade,
            value = config.customFade or false,
            disabled = controlsDisabled,
            onChange = ApplyCustomFade,
        })

        if config.customFade then
        local function AddFadeSlider(label, key, default, setting)
            ST._AddSliderRow(rightTarget, {
                label = label,
                setting = setting,
                indent = true,
                min = 0, max = 5, step = 0.1,
                value = config[key] or default,
                disabled = controlsDisabled,
                onRelease = function(val)
                    if controlsDisabled then return end
                    config[key] = val
                    ApplyAlphaSettingChange(false)
                end,
            })
        end

        AddFadeSlider("Fade Delay (seconds)", "fadeDelay", 1, finderSettings.fadeDelay)
        AddFadeSlider("Fade In Duration (seconds)", "fadeInDuration", 0.2, finderSettings.fadeIn)
        AddFadeSlider("Fade Out Duration (seconds)", "fadeOutDuration", 0.2, finderSettings.fadeOut)
        end -- config.customFade
    end
end
ST._BuildAlphaControls = BuildAlphaControls
ST._BuildIndependentAnchorTargetRow = BuildIndependentAnchorTargetRow

ST._AddFontControls = AddFontControls
ST._AddOffsetSliders = AddOffsetSliders
ST._AddBorderRenderModeDropdown = AddBorderRenderModeDropdown

-- Private helpers consumed by later Helpers files.
SH.ADVANCED_TOGGLE_ATLAS = ADVANCED_TOGGLE_ATLAS
SH.ADVANCED_TOGGLE_IDLE_COLOR = ADVANCED_TOGGLE_IDLE_COLOR
SH.ADVANCED_TOGGLE_OPEN_TOOLTIP = ADVANCED_TOGGLE_OPEN_TOOLTIP
