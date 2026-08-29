--[[
    CooldownCompanion - ConfigSettings/RowWidgets.lua: the row grammar foundation.

    Every setting in the redesigned config is a fixed-height row: label on the
    LEFT, its control right-aligned into a fixed-width (140px) control column
    on the RIGHT, and its gear/info/scope badges chained left-to-right off
    the end of the label text. Rows live in two-column grids built by
    BeginRowGrid, so a cell is roughly 400px wide and the badge scatter stays
    bounded inside the label's own cell. This file registers the custom AceGUI
    widget types for those rows, the grid container types and top-aligned
    layout they sit in, and the thin builders that replace the AceGUI
    boilerplate at each call site.

    BuildAppearanceTab's icons path is the proving ground; the other tabs are
    converted by later packets.

    AceGUI recycles widgets from pools that are SHARED WITH EVERY OTHER ADDON,
    so these are new widget types with their own pools rather than mutations of
    the stock CheckBox/Slider/Dropdown/ColorPicker anatomy. Where a row needs
    real stock behaviour it embeds a stock widget as a child, under one of two
    ownership models:

      BORROWED (Dropdown, EditBox, ColorPicker): acquired in OnAcquire,
      released in OnRelease, only ever touched through its public API, so it
      goes back to the shared pool exactly as it came out.

      OWNED (CheckBox): created once in the Constructor and never released.
      That is what makes it legal to size, anchor and repair the child - the
      no-re-plumbing rule exists because of RELEASE, not because of embedding.
      Two reasons the checkbox needs this model. Stock CheckBox:OnWidthSet does
      desc:SetWidth(width - 30), and desc is created lazily by SetDescription
      and never destroyed (SetDescription(nil) only blanks and hides it), so a
      checkbox drawn from the shared pool can arrive carrying one and our 24px
      control width would drive it negative. Owning the child lets the
      Constructor drop that desc once instead of every acquire. And the
      settings surface is released and rebuilt wholesale on every tab switch
      and every RefreshConfigPanel, so borrowing would churn ~185 pooled
      checkboxes per refresh; owning keeps the footprint identical to the raw
      Buttons these rows used to hold.

    Embedding the stock widget is also what lets a UI skin find the control:
    skins such as ElvUI dispatch on an exact widget.type match, so a "CDC-" row
    type is never skinned but the stock child sitting inside it is.
]]

local ADDON_NAME, ST = ...
local AceGUI = LibStub("AceGUI-3.0")

-- Imports from Helpers.lua
local SetupColorCallbacks = ST._SetupColorCallbacks

local floor, min, max = math.floor, math.min, math.max

------------------------------------------------------------------------
-- ROW GRAMMAR CONSTANTS
-- One block so the proving-ground packet can tune the whole grammar here.
------------------------------------------------------------------------
-- The control column is deliberately compact: rows sit in half-width grid
-- cells (~360px at the default window size), so every pixel the column does
-- not take is label room.
local ROW_HEIGHT             = 30    -- every row is exactly this tall
local CONTROL_COLUMN_WIDTH   = 140   -- fixed control column pinned to the row's right edge
local MIN_CONTROL_COLUMN     = 110   -- floor when the row itself is narrow
local MIN_LABEL_WIDTH        = 90    -- label space the control column may never eat
local LABEL_INSET            = 2     -- label's left inset inside the row
local LABEL_CONTROL_GAP      = 8     -- gap between label text and the control column
local CHILD_INDENT           = 22    -- extra left inset for SetIndent(true) rows

local CHECK_SIZE             = 24    -- matches stock AceGUI CheckBox check art
-- track 90 + CONTROL_GAP 6 + value box 44 = CONTROL_COLUMN_WIDTH exactly. The
-- track's HEIGHT is deliberately not a constant here: it is the stock Slider's
-- own 15, or whatever a skin compressed it to (ElvUI uses 12).
local SLIDER_TRACK_WIDTH     = 90
local SLIDER_VALUE_WIDTH     = 44
local SLIDER_VALUE_HEIGHT    = 16
local DROPDOWN_WIDTH         = 140   -- fills the control column
local DROPDOWN_RIGHT_INSET   = 0     -- stock Dropdown art already cancels its own template padding
local EDITBOX_WIDTH          = 140   -- fills the control column
local EDITBOX_RIGHT_INSET    = 0
local COLOR_SWATCH_SIZE      = 19    -- matches stock AceGUI ColorPicker swatch
local CONTROL_GAP            = 6     -- gap between two controls inside the column

local BADGE_GAP              = 4     -- label -> badge and badge -> badge

local ROW_GRID_COLUMN_GAP    = 16    -- gutter between the two grid columns
-- Below this the grid cannot produce a sane two-column split, so a layout pass
-- that resolves to less than this keeps the previous geometry instead. See the
-- degenerate-width note on the layout itself.
local ROW_GRID_MIN_WIDTH     = 64

-- Hierarchy comes from position, size and color - never boxes or backdrops.
local LABEL_COLOR            = { 1, 1, 1 }
local LABEL_CHILD_COLOR      = { 0.749, 0.714, 0.612 }  -- #bfb69c
local LABEL_DISABLED_COLOR   = { 0.5, 0.5, 0.5 }

local CHECKBOX_ROW_TYPE = "CDC-CheckBoxRow"
local SLIDER_ROW_TYPE   = "CDC-SliderRow"
local DROPDOWN_ROW_TYPE = "CDC-DropdownRow"
local SOUND_PREVIEW_DROPDOWN_ITEM_TYPE = "CDC-Dropdown-Item-SoundPreview"
local EDITBOX_ROW_TYPE  = "CDC-EditBoxRow"
local COLOR_ROW_TYPE    = "CDC-ColorRow"
local LABEL_ROW_TYPE    = "CDC-LabelRow"
local ROW_GRID_TYPE     = "CDC-RowGrid"
local ROW_GRID_COL_TYPE = "CDC-RowGridColumn"
local ROW_WIDGET_VERSION = 1

-- Flip to true to trace every grid layout pass to chat. Left in deliberately:
-- the resize bug this template was hardened against was never reproduced from
-- the sources alone, so the next sighting should be captured, not re-theorised.
local DEBUG_ROW_GRID = false

------------------------------------------------------------------------
-- SHARED ROW SCAFFOLDING
------------------------------------------------------------------------

-- Reposition the invisible badge anchor at the end of the label text so the
-- gear/info/scope badge creators in Helpers.lua can hang off it.
local function UpdateBadgeAnchor(self)
    local label = self.rowLabel
    self.badgeAnchor:ClearAllPoints()
    self.badgeAnchor:SetPoint("LEFT", label, "LEFT", label:GetStringWidth() or 0, 0)
end

-- Chain a badge (gear / info / scope chrome) off the end of the row's label
-- text, growing LEFT to RIGHT: the first badge hangs off badgeAnchor, each
-- further one off the previous badge. Creation order gear -> info -> scope
-- therefore reads on screen as gear, info, scope.
--
-- Badges belong to the label, not to a shared rail. A full-width rail was
-- tried and reversed: with ~600px between a label and its control, badges
-- parked at the control column read as floating mid-screen rather than as
-- belonging to the setting. Inside a ~360px grid cell the horizontal scatter
-- is bounded and reads as ownership.
--
-- The chain is NOT clamped to the control column: badgeAnchor tracks the
-- label's unclipped string width, so a long label plus three badges can reach
-- a little past the column's left edge. That is safe only because every
-- control is right-aligned inside the column and the badge-bearing rows use
-- narrow controls (checkbox, color swatch). Never badge a slider row in a
-- grid cell - its track starts at that left edge.
--
-- Badges that are hidden because their setting is off must NOT be chained, or
-- they leave a hole; the callers already skip anchoring in that case.
local function AnchorRowBadge(row, btn, gap)
    if not (row and btn) then return btn end
    local previous = row._cdcLastBadge
    btn:SetParent(row.frame)
    btn:ClearAllPoints()
    btn:SetPoint("LEFT", previous or row.badgeAnchor, "RIGHT", gap or BADGE_GAP, 0)
    row._cdcLastBadge = btn
    return btn
end

local function ApplyLabelColor(self)
    local color = LABEL_COLOR
    if self.disabled then
        color = LABEL_DISABLED_COLOR
    elseif self.indented then
        color = LABEL_CHILD_COLOR
    end
    self.rowLabel:SetTextColor(color[1], color[2], color[3])
end

-- The control column is a fixed width pinned to the row's right edge, but a
-- narrow row (half-width grid column) must still leave the label room.
local function UpdateControlColumnWidth(self, width)
    width = width or self.frame:GetWidth() or 0
    local colWidth = self.controlColumnWidthOverride or CONTROL_COLUMN_WIDTH
    if not self.controlColumnWidthOverride and width > 0 then
        local available = width - LABEL_INSET - LABEL_CONTROL_GAP - MIN_LABEL_WIDTH
        if available < colWidth then
            colWidth = max(MIN_CONTROL_COLUMN, available)
        end
    end
    self.controlColumn:SetWidth(colWidth)
end

local function AddRowTooltipLines(lines)
    for _, line in ipairs(lines) do
        if type(line) == "table" then
            GameTooltip:AddLine(line[1], line[2], line[3], line[4], line[5])
        else
            GameTooltip:AddLine(line)
        end
    end
end

-- One tooltip per row, three sources: the row's own lines, a slider's range,
-- and the style-lens scope explanation (Helpers.lua's grey-row chrome). The
-- scope lines are a SEPARATE channel rather than an append to tooltipLines
-- because their owners are different - the call site describes the setting,
-- the lens describes whose values it is showing - and because they are shown
-- over a SMALLER area than the row: only `includeScope` callers render them,
-- and the only one is the control overlay below. The row frame's own OnEnter
-- never passes it, so a greyed row's label and empty middle say nothing about
-- scope (owner ruling 2026-08-14: the row-wide hover was tooltip soup).
local function ShowRowTooltip(self, includeScope)
    local lines = self.tooltipLines
    local range = self.rangeTooltip
    local scope = includeScope and self.scopeTooltipLines or nil
    local hasOwn = range or (lines and lines[1])
    if not (hasOwn or (scope and scope[1])) then return end

    GameTooltip:SetOwner(self.frame, "ANCHOR_RIGHT")
    if lines then
        AddRowTooltipLines(lines)
    end
    if range then
        GameTooltip:AddLine(range, 0.7, 0.7, 0.7)
    end
    if scope and scope[1] then
        if hasOwn then
            GameTooltip:AddLine(" ")
        end
        AddRowTooltipLines(scope)
    end
    GameTooltip:Show()
end

local function Row_OnEnter(frame)
    local self = frame.obj
    ShowRowTooltip(self)
    self:Fire("OnEnter")
end

local function Row_OnLeave(frame)
    local self = frame.obj
    GameTooltip:Hide()
    self:Fire("OnLeave")
end

------------------------------------------------------------------------
-- SCOPE HOVER
--
-- The style lens's scope explanation ("Panel setting / Follows the panel."
-- and "Not available: <reason>") is deliberately NARROWER than the row: it
-- belongs to the control the owner cannot use, not to the whole line. It is
-- delivered by a transparent overlay pinned over the row's CONTROL region,
-- created lazily on the row and shown only while the row carries scope lines
-- (Helpers' AttachRowScopeChrome sets them, and clears them on release).
--
-- The region is "leftmost control -> the control column's right edge, full row
-- height": every control is pinned to that right edge, so each row type only
-- has to publish its LEFTMOST control frame as `controlHoverAnchor`. A row
-- type with no control publishes none and gets NO scope hover - CDC-LabelRow
-- is the only one, and falling back to the whole row is exactly what this
-- replaced.
--
-- PRECEDENCE, explicit. The overlay is mouse-enabled and sits above every
-- frame in the control column, so exactly one handler runs at a time:
--   * pointer over the control  -> the overlay's OnEnter, and neither the
--     control's own OnEnter (it is covered) nor the row frame's (a
--     mouse-enabled child takes the hover, which is why entering one fires the
--     row frame's OnLeave first - the same crossing the stock children already
--     make today).
--   * pointer anywhere else on the row -> the row frame's OnEnter.
-- The overlay renders the row's OWN tooltip as well, so the control hover ADDS
-- the scope lines rather than replacing the row tooltip, and crossing back out
-- of it hides and re-shows the row-only tooltip. No double-show, no flicker
-- beyond the one hide/show every control crossing already does.
--
-- Clicks: the overlay normally eats clicks on an inert control. A narrow
-- caller may attach scopeControlAction to turn that otherwise-dead click into
-- a scope action; the underlying disabled widget is never re-enabled. Note the
-- overlay may go up BEFORE the inert sweep runs (several call sites chrome the
-- row, then Finish), which is why nothing here reads self.disabled.
------------------------------------------------------------------------
local function ScopeHover_OnEnter(frame)
    local self = frame.cdcRow
    if not self then return end
    ShowRowTooltip(self, true)
    self:Fire("OnEnter")
end

local function ScopeHover_OnLeave(frame)
    local self = frame.cdcRow
    if not self then return end
    GameTooltip:Hide()
    self:Fire("OnLeave")
end

local function ScopeHover_OnClick(frame, mouseButton)
    local self = frame.cdcRow
    local action = self and self.scopeControlAction
    if action then
        action(self, mouseButton)
    end
end

-- Park the overlay: no points into a control frame (the borrowed children go
-- back to a pool shared with every other addon, so a hidden overlay must not
-- keep an anchor into one), no mouse, no scripts.
local function ParkScopeHover(self)
    local hover = self.scopeHover
    if not hover then return end
    hover:Hide()
    hover:ClearAllPoints()
    hover:EnableMouse(false)
    hover:SetScript("OnEnter", nil)
    hover:SetScript("OnLeave", nil)
    hover:SetScript("OnClick", nil)
end

local function UpdateScopeHover(self)
    local lines = self.scopeTooltipLines
    local action = self.scopeControlAction
    local anchor = self.controlHoverAnchor
    if not (anchor and ((lines and lines[1]) or action)) then
        ParkScopeHover(self)
        return
    end

    local hover = self.scopeHover
    if not hover then
        hover = CreateFrame("Button", nil, self.frame)
        hover.cdcRow = self
        self.scopeHover = hover
    end

    hover:ClearAllPoints()
    hover:SetPoint("LEFT", anchor, "LEFT", 0, 0)
    hover:SetPoint("RIGHT", self.controlColumn, "RIGHT", 0, 0)
    hover:SetPoint("TOP", self.frame, "TOP", 0, 0)
    hover:SetPoint("BOTTOM", self.frame, "BOTTOM", 0, 0)
    -- Above every control: the stock children are parented to the control
    -- column (one level over it) and their own regions one over that.
    hover:SetFrameLevel(self.controlColumn:GetFrameLevel() + 10)
    hover:EnableMouse(true)
    hover:SetScript("OnEnter", ScopeHover_OnEnter)
    hover:SetScript("OnLeave", ScopeHover_OnLeave)
    hover:SetScript("OnClick", action and ScopeHover_OnClick or nil)
    hover:Show()
end

-- Methods every row type shares. Copied into each type's method table so the
-- widgets stay plain AceGUI widgets with no extra metatable layer.
local sharedMethods = {
    ["SetLabel"] = function(self, text)
        self.rowLabel:SetText(text or "")
        UpdateBadgeAnchor(self)
    end,

    ["GetLabel"] = function(self)
        return self.rowLabel:GetText()
    end,

    ["SetIndent"] = function(self, indent)
        self.indented = indent and true or false
        local label = self.rowLabel
        label:ClearAllPoints()
        label:SetPoint("LEFT", self.frame, "LEFT", LABEL_INSET + (self.indented and CHILD_INDENT or 0), 0)
        label:SetPoint("RIGHT", self.controlColumn, "LEFT", -LABEL_CONTROL_GAP, 0)
        ApplyLabelColor(self)
        UpdateBadgeAnchor(self)
    end,

    ["IsIndented"] = function(self)
        return self.indented
    end,

    -- tooltipLines follows CreateInfoButton's shape: plain strings are title
    -- lines, {text, r, g, b, wrap} tables are colored/wrapping body lines.
    ["SetRowTooltip"] = function(self, lines)
        self.tooltipLines = lines
    end,

    -- The style lens's channel into the same tooltip, same line shape - but
    -- shown over the CONTROL only, so setting it is also what raises and lowers
    -- the scope overlay. Set by the scope chrome only, and cleared by it on
    -- release; ResetRowBase clears it again on acquire so a pooled row cannot
    -- wear the last tenant's scope hover.
    ["SetScopeTooltip"] = function(self, lines)
        self.scopeTooltipLines = lines
        UpdateScopeHover(self)
    end,

    -- Optional action for an inert control. The scope overlay already owns
    -- mouse input over that control; this gives selected call sites a safe
    -- direct-manipulation path without re-enabling the disabled widget below.
    ["SetScopeControlAction"] = function(self, action)
        self.scopeControlAction = type(action) == "function" and action or nil
        UpdateScopeHover(self)
    end,

    ["OnWidthSet"] = function(self, width)
        UpdateControlColumnWidth(self, width)
    end,

    ["SetControlColumnWidth"] = function(self, width)
        self.controlColumnWidthOverride = tonumber(width)
        UpdateControlColumnWidth(self)
    end,
}

-- Reset the shared half of a row. Every type's OnAcquire calls this first,
-- then resets its own control, matching the AceGUI convention that OnAcquire
-- (not OnRelease) is what guarantees a clean widget.
local function ResetRowBase(self)
    self.disabled = false
    self.indented = false
    self.tooltipLines = nil
    self.scopeControlAction = nil
    -- Through the setter, not the field: this is also what parks a scope
    -- overlay the previous tenant of this pooled row left raised.
    self:SetScopeTooltip(nil)
    self.rangeTooltip = nil
    self._cdcLastBadge = nil
    self.controlColumnWidthOverride = nil
    self.frame:SetHeight(ROW_HEIGHT)
    self.rowLabel:SetWordWrap(false)
    if self.rowLabel.SetMaxLines then self.rowLabel:SetMaxLines(1) end
    self:SetWidth(CONTROL_COLUMN_WIDTH + MIN_LABEL_WIDTH)
    self:SetLabel("")
    self:SetIndent(false)
end

local function BuildRowBase(widgetType)
    local frame = CreateFrame("Frame", nil, UIParent)
    frame:Hide()
    frame:SetHeight(ROW_HEIGHT)
    frame:EnableMouse(true)
    frame:SetScript("OnEnter", Row_OnEnter)
    frame:SetScript("OnLeave", Row_OnLeave)

    local controlColumn = CreateFrame("Frame", nil, frame)
    controlColumn:SetPoint("TOPRIGHT")
    controlColumn:SetPoint("BOTTOMRIGHT")
    controlColumn:SetWidth(CONTROL_COLUMN_WIDTH)

    local rowLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    rowLabel:SetJustifyH("LEFT")
    rowLabel:SetWordWrap(false)
    rowLabel:SetPoint("LEFT", frame, "LEFT", LABEL_INSET, 0)
    rowLabel:SetPoint("RIGHT", controlColumn, "LEFT", -LABEL_CONTROL_GAP, 0)

    -- Zero-size anchor sitting at the end of the label text. Everything that
    -- belongs to the label hangs off it: the gear/info/scope badge chain via
    -- AnchorRowBadge, and one-off notes like the green "(Masque skinning is
    -- active)" line. It re-points itself whenever SetLabel or SetIndent runs,
    -- so the whole chain follows the text.
    local badgeAnchor = CreateFrame("Frame", nil, frame)
    badgeAnchor:SetSize(1, 1)
    badgeAnchor:SetPoint("LEFT", rowLabel, "LEFT", 0, 0)

    local widget = {
        frame         = frame,
        controlColumn = controlColumn,
        rowLabel      = rowLabel,
        badgeAnchor   = badgeAnchor,
        type          = widgetType,
    }
    for method, func in pairs(sharedMethods) do
        widget[method] = func
    end

    return widget, frame, controlColumn
end

------------------------------------------------------------------------
-- CDC-CheckBoxRow
--
-- The control is a stock AceGUI CheckBox, so the tristate cycle, the check
-- sounds and the disabled/desaturate handling are the native ones, and any UI
-- skin that keys on widget.type == "CheckBox" finds it. The child is OWNED
-- rather than borrowed - see the ownership note in the file header.
------------------------------------------------------------------------
do
    local function ForwardValueChanged(child, event, ...)
        local row = child:GetUserData("cdcRow")
        if row then row:Fire("OnValueChanged", ...) end
    end

    -- Entering the child fires the row frame's own OnLeave first, so without
    -- these the row tooltip drops the moment the pointer reaches the check.
    local function ForwardEnter(child)
        local row = child:GetUserData("cdcRow")
        if row then Row_OnEnter(row.frame) end
    end

    local function ForwardLeave(child)
        local row = child:GetUserData("cdcRow")
        if row then Row_OnLeave(row.frame) end
    end

    local methods = {
        ["OnAcquire"] = function(self)
            ResetRowBase(self)
            self.checkBox:SetTriState(nil)
            self.checkBox:SetValue(false)
            self:SetDisabled(false)
        end,

        ["OnRelease"] = function(self)
            self.tooltipLines = nil
            -- ButtonConditions.SetupBatchCheckbox parks the previous batch
            -- value on the row and nothing else clears it, so it would
            -- otherwise survive pooling.
            self._batchPrev = nil
        end,

        ["SetValue"] = function(self, value)
            self.checkBox:SetValue(value)
        end,

        ["GetValue"] = function(self)
            return self.checkBox:GetValue()
        end,

        ["SetTriState"] = function(self, enabled)
            self.checkBox:SetTriState(enabled)
        end,

        ["ToggleChecked"] = function(self)
            self.checkBox:ToggleChecked()
        end,

        ["SetDisabled"] = function(self, disabled)
            self.disabled = disabled and true or false
            self.checkBox:SetDisabled(self.disabled)
            ApplyLabelColor(self)
        end,
    }

    local function Constructor()
        local widget, _, controlColumn = BuildRowBase(CHECKBOX_ROW_TYPE)

        local check = AceGUI:Create("CheckBox")

        -- Blank the label. A skin may hook SetDisabled and rewrite the label
        -- when its text matches the localized "Enable" string; AceGUI:Create
        -- has already run one OnAcquire (SetValue -> SetDisabled) against
        -- whatever label a pooled child carried, so that hook can fire once on
        -- stale text before this line. The outcome is still right because the
        -- row supplies the label itself and the child's stays empty for good.
        check:SetLabel(nil)

        -- Stock drives the toggle from a frame-level OnMouseUp that ignores
        -- which button was pressed, so every mouse button would commit a value
        -- and a press released off the box would too. The check this replaced
        -- was a plain Button on OnClick, i.e. left-only, and the batch rows in
        -- ButtonConditions write their result to EVERY selected button - so
        -- gate the stock handler rather than inherit it. OnMouseDown is left
        -- alone: its AceGUI:ClearFocus() should still run on any press.
        local stockMouseUp = check.frame:GetScript("OnMouseUp")
        check.frame:SetScript("OnMouseUp", function(f, button, ...)
            if button == "LeftButton" then
                stockMouseUp(f, button, ...)
            end
        end)

        -- The child may have come out of the shared pool carrying a desc
        -- fontstring, whose width OnWidthSet derives as (width - 30) - which
        -- our 24px control column would drive negative. Rows never use
        -- descriptions and this child is never released, so drop it once here.
        if check.desc then
            check.desc:SetText("")
            check.desc:Hide()
            check.desc = nil
        end

        check:SetHeight(CHECK_SIZE)
        check:SetWidth(CHECK_SIZE)

        check:SetUserData("cdcRow", widget)
        check:SetCallback("OnValueChanged", ForwardValueChanged)
        check:SetCallback("OnEnter", ForwardEnter)
        check:SetCallback("OnLeave", ForwardLeave)

        check.frame:SetParent(controlColumn)
        check.frame:ClearAllPoints()
        check.frame:SetPoint("RIGHT", controlColumn, "RIGHT", 0, 0)
        check.frame:Show()

        -- Named like the other rows' children rather than "check", which on a
        -- stock CheckBox is the check-mark TEXTURE. The row deliberately does
        -- not mirror the child's checkbg/text fields onto itself: the badge
        -- helpers in Helpers.lua fall back to those names for widgets that
        -- have no badgeAnchor.
        widget.checkBox = check
        -- The scope overlay's region: the check art itself, not the 140px
        -- column it is pinned into. Static - this child is never released.
        widget.controlHoverAnchor = check.frame

        for method, func in pairs(methods) do
            widget[method] = func
        end

        return AceGUI:RegisterAsWidget(widget)
    end

    AceGUI:RegisterWidgetType(CHECKBOX_ROW_TYPE, Constructor, ROW_WIDGET_VERSION)
end

------------------------------------------------------------------------
-- CDC-SliderRow
--
-- The control is a stock AceGUI Slider, OWNED rather than borrowed - see the
-- ownership note in the file header. Owning it is what makes it legal to hide
-- the stock stacked regions (centered label over track over endpoint labels
-- over value box, 44px tall in total) and re-anchor just the track and the
-- value box into a 30px row. Embedding is also what lets a skin find them:
-- ElvUI's HandleSliderFrame runs on widget.slider at construction time.
------------------------------------------------------------------------
do
    local function RowOf(child)
        return child and child:GetUserData("cdcRow")
    end

    -- Stock AceGUI Slider display rounding. Operates on the stock child, which
    -- is where the value lives.
    local function UpdateValueText(self)
        local value = self.value or 0
        self.editbox:SetText(floor(value * 100 + 0.5) / 100)
    end

    local function FormatRangeValue(value)
        value = value or 0
        if value == floor(value) then
            return tostring(floor(value))
        end
        return tostring(floor(value * 100 + 0.5) / 100)
    end

    local function UpdateRangeTooltip(self)
        self.rangeTooltip = FormatRangeValue(self.min) .. " – " .. FormatRangeValue(self.max)
    end

    -- The stock child fires these; hand them on to the row so call sites keep
    -- the same contract (OnMouseUp is what opts.onRelease rides).
    local function ForwardValueChanged(child, event, value)
        local row = RowOf(child)
        if row then row:Fire("OnValueChanged", value) end
    end

    local function ForwardMouseUp(child, event, value)
        local row = RowOf(child)
        if row then row:Fire("OnMouseUp", value) end
    end

    local function ForwardEnter(child)
        local row = RowOf(child)
        if row then Row_OnEnter(row.frame) end
    end

    local function ForwardLeave(child)
        local row = RowOf(child)
        if row then Row_OnLeave(row.frame) end
    end

    -- Stock keeps the wheel disabled until the widget is clicked so a slider
    -- can't steal scrolling from the surrounding ScrollFrame. Rows live in a
    -- ScrollFrame too, so the row frame arms it the same way.
    local function Row_OnMouseDown(frame)
        frame.obj.slider:EnableMouseWheel(true)
        AceGUI:ClearFocus()
    end

    -- Typed values keep the row's own accept behaviour rather than the stock
    -- widget's: snapped to the slider's declared step, clamped to the range,
    -- and BOTH OnValueChanged and OnMouseUp fire so mirror-first call sites
    -- apply them live. (Stock fires only OnMouseUp here.) Integer-step values
    -- reach floor/modulo layout math, so a fractional store is never safe.
    local function EditBox_OnEnterPressed(frame)
        local self = frame.obj -- the stock child; it owns the value
        local value = tonumber(frame:GetText())
        if value then
            local step = self.step
            if step and step > 0 then
                value = floor((value - self.min) / step + 0.5) * step + self.min
                value = floor(value * 100 + 0.5) / 100 -- float dust; the finest step is 0.01
            else
                value = floor(value * 10 + 0.5) / 10
            end
            value = max(self.min, min(self.max, value))
            PlaySound(856) -- SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON
            self:SetValue(value)
            self:Fire("OnValueChanged", value)
            self:Fire("OnMouseUp", value)
        else
            UpdateValueText(self)
        end
        frame:ClearFocus()
    end

    local function EditBox_OnEscapePressed(frame)
        UpdateValueText(frame.obj)
        frame:ClearFocus()
    end

    -- Stock tints the value box's border on hover and restores a HARDCODED
    -- stock colour on leave, which would wipe whatever border a skin gave it.
    -- Read the colour on the way IN instead of caching one: a skin can
    -- recolour the box at any time (ElvUI registers every SetTemplate'd frame
    -- and re-runs them when its border colour changes), and a child drawn from
    -- a warm pool can arrive still tinted from a previous owner's hover - so a
    -- colour captured once at construction is never trustworthy. The hover
    -- flag keeps a second OnEnter from capturing the tint as the resting
    -- colour. Forwarding keeps the row tooltip up across the control.
    local function EditBox_OnEnter(frame)
        if not frame.cdcHovered and frame.GetBackdropBorderColor then
            local r, g, b, a = frame:GetBackdropBorderColor()
            if r then
                frame.cdcRestingBorder = { r, g, b, a }
                frame:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)
            end
        end
        frame.cdcHovered = true
        ForwardEnter(frame.obj)
    end

    local function EditBox_OnLeave(frame)
        frame.cdcHovered = nil
        local resting = frame.cdcRestingBorder
        if resting then
            frame:SetBackdropBorderColor(resting[1], resting[2], resting[3], resting[4])
        end
        ForwardLeave(frame.obj)
    end

    local methods = {
        ["OnAcquire"] = function(self)
            ResetRowBase(self)
            self:SetSliderValues(0, 100, 1)
            self:SetValue(0)
            self:SetDisabled(false)
            self.slider:EnableMouseWheel(false)
        end,

        ["OnRelease"] = function(self)
            self.editbox:ClearFocus()
            self.slider:EnableMouseWheel(false)
            self.min = nil
            self.max = nil
            self.rangeTooltip = nil
            self.tooltipLines = nil
        end,

        ["SetSliderValues"] = function(self, minValue, maxValue, step)
            -- The row keeps min/max only for the range tooltip; the child is
            -- the authority on all three.
            self.min = minValue or 0
            self.max = maxValue or 100
            self.sliderWidget:SetSliderValues(self.min, self.max, step)
            UpdateRangeTooltip(self)
        end,

        ["SetValue"] = function(self, value)
            self.sliderWidget:SetValue(value)
        end,

        ["GetValue"] = function(self)
            return self.sliderWidget:GetValue()
        end,

        ["SetDisabled"] = function(self, disabled)
            self.disabled = disabled and true or false
            self.sliderWidget:SetDisabled(self.disabled)
            ApplyLabelColor(self)
        end,
    }

    local function Constructor()
        local widget, frame, controlColumn = BuildRowBase(SLIDER_ROW_TYPE)
        frame:SetScript("OnMouseDown", Row_OnMouseDown)

        local child = AceGUI:Create("Slider")
        child:SetUserData("cdcRow", widget)
        child:SetCallback("OnValueChanged", ForwardValueChanged)
        child:SetCallback("OnMouseUp", ForwardMouseUp)
        child:SetCallback("OnEnter", ForwardEnter)
        child:SetCallback("OnLeave", ForwardLeave)

        -- A 30px row has no room for the stock stacked shape. The range lives
        -- in the row tooltip and the value box is the readout.
        child.label:Hide()
        child.lowtext:Hide()
        child.hightext:Hide()

        -- The child's frame is only a carrier for the two controls: the row
        -- owns the hover and the mouse-down that arms the wheel, so leave it
        -- transparent rather than letting it swallow the control column.
        child.frame:SetParent(controlColumn)
        child.frame:ClearAllPoints()
        child.frame:SetAllPoints(controlColumn)
        child.frame:EnableMouse(false)
        child.frame:Show()

        local editbox, slider = child.editbox, child.slider

        editbox:ClearAllPoints()
        editbox:SetSize(SLIDER_VALUE_WIDTH, SLIDER_VALUE_HEIGHT)
        editbox:SetPoint("RIGHT", controlColumn, "RIGHT", 0, 0)
        editbox:SetScript("OnEnter", EditBox_OnEnter)
        editbox:SetScript("OnLeave", EditBox_OnLeave)
        editbox:SetScript("OnEnterPressed", EditBox_OnEnterPressed)
        editbox:SetScript("OnEscapePressed", EditBox_OnEscapePressed)

        -- Width only: the track keeps the height the stock widget or the
        -- active skin gave it.
        slider:ClearAllPoints()
        slider:SetWidth(SLIDER_TRACK_WIDTH)
        slider:SetHitRectInsets(0, 0, -4, -4)
        slider:SetPoint("RIGHT", editbox, "LEFT", -CONTROL_GAP, 0)

        -- A wheel tick is a discrete commit like a typed value, not a drag, so
        -- it obeys the same rule: stock reaches the value through SetValue and
        -- fires OnValueChanged alone, never the frame-level OnMouseUp, which
        -- left mirror-first call sites repainting the preview and never
        -- applying to the live display. Compare the child's value across the
        -- stock handler because it clamps at the endpoints - a tick that moved
        -- nothing must not re-apply. Wrapping belongs here and not in
        -- OnAcquire: AceGUI pools by type, so the constructor runs once per
        -- physical widget and cannot stack wrappers on reuse.
        local stockMouseWheel = slider:GetScript("OnMouseWheel")
        slider:SetScript("OnMouseWheel", function(f, delta, ...)
            local self = f.obj -- the stock child; it owns the value
            local before = self.value
            stockMouseWheel(f, delta, ...)
            if not self.disabled and self.value ~= before then
                self:Fire("OnMouseUp", self.value)
            end
        end)

        -- slider.obj/editbox.obj stay pointed at the stock child because its
        -- own scripts read them. GroupTabs' staged texture sliders need the
        -- ROW from the raw frame, so publish it separately.
        slider.cdcRow = widget

        widget.sliderWidget = child
        widget.slider = slider   -- raw Slider frame, reached by call sites
        widget.editbox = editbox -- raw EditBox frame, reached by call sites
        -- The track is the LEFTMOST control, and the value box is pinned to the
        -- column's right edge, so track -> column right is exactly track plus
        -- gap plus value box. Static - this child is never released. Stock
        -- SetDisabled drops mouse on BOTH of these (AceGUIWidget-Slider.lua's
        -- SetDisabled calls EnableMouse(false) on the slider and the editbox),
        -- so a disabled slider row has no control hover of its own to fight -
        -- and re-enabling theirs would have handed back a draggable thumb and a
        -- focusable value box on an inert row.
        widget.controlHoverAnchor = slider

        for method, func in pairs(methods) do
            widget[method] = func
        end

        return AceGUI:RegisterAsWidget(widget)
    end

    AceGUI:RegisterWidgetType(SLIDER_ROW_TYPE, Constructor, ROW_WIDGET_VERSION)
end

------------------------------------------------------------------------
-- CDC-Dropdown-Item-SoundPreview
--
-- Sound rows need an action button inside each pullout item. Stock dropdown
-- item pools are shared with every addon, and frames cannot be destroyed, so
-- this uses an addon-owned item type rather than attaching permanent children
-- to pooled Dropdown-Item-Toggle widgets. The main row keeps stock toggle
-- semantics; the sound button fires OnPreview without selecting or closing.
------------------------------------------------------------------------
do
    local ItemBase = LibStub("AceGUI-3.0-DropDown-ItemBase"):GetItemBase()
    local SOUND_PREVIEW_ICON_ATLAS = "chatframe-button-icon-voicechat"
    local SOUND_PREVIEW_TEXT_LEFT_OFFSET = 18
    local SOUND_PREVIEW_TEXT_RIGHT_OFFSET = -8
    local SOUND_PREVIEW_TEXT_GAP = -4
    local SOUND_PREVIEW_BUTTON_RIGHT_OFFSET = -18

    local function UpdateToggle(self)
        self.check:SetShown(self.value == true)
    end

    local function SetValue(self, value)
        self.value = value
        UpdateToggle(self)
    end

    local function GetValue(self)
        return self.value
    end

    local function SetPreviewEnabled(self, enabled)
        enabled = enabled == true
        self.previewButton:SetShown(enabled)

        self.text:ClearAllPoints()
        self.text:SetPoint("TOPLEFT", self.frame, "TOPLEFT", SOUND_PREVIEW_TEXT_LEFT_OFFSET, 0)
        if enabled then
            self.text:SetPoint("BOTTOMRIGHT", self.previewButton, "LEFT", SOUND_PREVIEW_TEXT_GAP, 0)
        else
            self.text:SetPoint("BOTTOMRIGHT", self.frame, "BOTTOMRIGHT", SOUND_PREVIEW_TEXT_RIGHT_OFFSET, 0)
            self.events.OnPreview = nil
            self:SetUserData("cdcSoundPreviewCallback", nil)
        end
    end

    local function OnAcquire(self)
        ItemBase.OnAcquire(self)
        self:SetValue(nil)
        self:SetPreviewEnabled(false)
    end

    local function OnRelease(self)
        self:SetPreviewEnabled(false)
        self:SetValue(nil)
        ItemBase.OnRelease(self)
    end

    local function Frame_OnClick(frame)
        local self = frame.obj
        if self.disabled then return end

        self.value = not self.value
        PlaySound(self.value and 856 or 857)
        UpdateToggle(self)
        self:Fire("OnValueChanged", self.value)
    end

    local function Preview_OnClick(button)
        local self = button.obj
        if self.disabled then return end

        local value = self:GetUserData("value")
        if value ~= nil then
            self:Fire("OnPreview", value)
        end
    end

    local function Constructor()
        local widget = ItemBase.Create(SOUND_PREVIEW_DROPDOWN_ITEM_TYPE)

        widget.frame:SetScript("OnClick", Frame_OnClick)
        widget.OnAcquire = OnAcquire
        widget.OnRelease = OnRelease
        widget.SetValue = SetValue
        widget.GetValue = GetValue
        widget.SetPreviewEnabled = SetPreviewEnabled

        local previewButton = CreateFrame("Button", nil, widget.frame)
        previewButton.obj = widget
        previewButton:SetSize(16, 16)
        previewButton:SetPoint("RIGHT", widget.frame, "RIGHT", SOUND_PREVIEW_BUTTON_RIGHT_OFFSET, 0)
        previewButton:SetHighlightAtlas(SOUND_PREVIEW_ICON_ATLAS)
        if previewButton:GetHighlightTexture() then
            previewButton:GetHighlightTexture():SetAlpha(0.3)
        end
        previewButton:SetScript("OnClick", Preview_OnClick)

        local previewIcon = previewButton:CreateTexture(nil, "ARTWORK")
        previewIcon:SetSize(12, 12)
        previewIcon:SetPoint("CENTER")
        previewIcon:SetAtlas(SOUND_PREVIEW_ICON_ATLAS, false)

        widget.previewButton = previewButton

        AceGUI:RegisterAsWidget(widget)
        return widget
    end

    AceGUI:RegisterWidgetType(
        SOUND_PREVIEW_DROPDOWN_ITEM_TYPE,
        Constructor,
        ROW_WIDGET_VERSION + ItemBase.version)
end

------------------------------------------------------------------------
-- CDC-DropdownRow
--
-- Menu logic is not reimplemented: the row embeds a stock AceGUI Dropdown as
-- a child widget (acquired in OnAcquire, released in OnRelease) and delegates
-- to it. Only stock public API is used on that child - its anatomy is never
-- re-plumbed - so it goes back to the shared pool exactly as it came out.
------------------------------------------------------------------------
do
    local function ForwardValueChanged(child, event, ...)
        local row = child:GetUserData("cdcRow")
        if row then row:Fire("OnValueChanged", ...) end
    end

    local function ForwardOpened(child)
        local row = child:GetUserData("cdcRow")
        if row then row:Fire("OnOpened") end
    end

    local function ForwardClosed(child)
        local row = child:GetUserData("cdcRow")
        if row then row:Fire("OnClosed") end
    end

    local function ForwardEnter(child)
        local row = child:GetUserData("cdcRow")
        if row then Row_OnEnter(row.frame) end
    end

    local function ForwardLeave(child)
        local row = child:GetUserData("cdcRow")
        if row then Row_OnLeave(row.frame) end
    end

    local methods = {
        ["OnAcquire"] = function(self)
            ResetRowBase(self)

            local child = AceGUI:Create("Dropdown")
            self.dropdown = child
            child:SetUserData("cdcRow", self)
            child:SetCallback("OnValueChanged", ForwardValueChanged)
            child:SetCallback("OnOpened", ForwardOpened)
            child:SetCallback("OnClosed", ForwardClosed)
            child:SetCallback("OnEnter", ForwardEnter)
            child:SetCallback("OnLeave", ForwardLeave)
            child:SetLabel(nil)
            child:SetWidth(DROPDOWN_WIDTH)

            child.frame:SetParent(self.controlColumn)
            child.frame:ClearAllPoints()
            child.frame:SetPoint("RIGHT", self.controlColumn, "RIGHT", DROPDOWN_RIGHT_INSET, 0)
            child.frame:Show()

            -- Helpers.AddDropdownItemTooltips and CS.SetupFontDropdown reach
            -- for widget.pullout; the stock Dropdown creates it in its own
            -- OnAcquire and keeps the same object until release.
            self.pullout = child.pullout

            -- The dropdown fills the column, so its frame IS the scope
            -- overlay's region. Borrowed, so it is republished every acquire
            -- and dropped again on release.
            self.controlHoverAnchor = child.frame

            self:SetDisabled(false)
        end,

        ["OnRelease"] = function(self)
            local child = self.dropdown
            self.dropdown = nil
            self.pullout = nil
            self.tooltipLines = nil
            -- Before the child goes back to the shared pool: parks the scope
            -- overlay, which is anchored to the frame being released.
            self:SetScopeTooltip(nil)
            self.controlHoverAnchor = nil
            if child then
                AceGUI:Release(child)
            end
        end,

        ["SetList"] = function(self, list, order, itemType)
            self.dropdown:SetList(list, order, itemType)
        end,

        ["AddItem"] = function(self, value, text, itemType)
            self.dropdown:AddItem(value, text, itemType)
        end,

        ["SetValue"] = function(self, value)
            self.dropdown:SetValue(value)
        end,

        ["GetValue"] = function(self)
            return self.dropdown:GetValue()
        end,

        ["SetText"] = function(self, text)
            self.dropdown:SetText(text)
        end,

        ["SetItemValue"] = function(self, item, value)
            self.dropdown:SetItemValue(item, value)
        end,

        ["SetItemDisabled"] = function(self, item, disabled)
            self.dropdown:SetItemDisabled(item, disabled)
        end,

        ["SetPulloutWidth"] = function(self, width)
            self.dropdown:SetPulloutWidth(width)
        end,

        ["ClearFocus"] = function(self)
            if self.dropdown then
                self.dropdown:ClearFocus()
            end
        end,

        ["SetDisabled"] = function(self, disabled)
            self.disabled = disabled and true or false
            self.dropdown:SetDisabled(self.disabled)
            ApplyLabelColor(self)
        end,
    }

    local function Constructor()
        local widget = BuildRowBase(DROPDOWN_ROW_TYPE)
        for method, func in pairs(methods) do
            widget[method] = func
        end
        return AceGUI:RegisterAsWidget(widget)
    end

    AceGUI:RegisterWidgetType(DROPDOWN_ROW_TYPE, Constructor, ROW_WIDGET_VERSION)
end

------------------------------------------------------------------------
-- CDC-EditBoxRow
--
-- Same delegation shape as CDC-DropdownRow: the row embeds a stock AceGUI
-- EditBox as a child (acquired in OnAcquire, released in OnRelease) and only
-- ever touches its public API, so focus handling, the escape/enter contract
-- and the "okay" button are the native ones and the child goes back to the
-- shared pool exactly as it came out.
--
-- The child is deliberately label-less: EditBox:SetLabel(nil) drops its frame
-- to 26px (the labelled shape is 44px), which is what lets it sit inside a
-- 30px row with the label supplied by the row itself.
------------------------------------------------------------------------
do
    local function ForwardEnterPressed(child, event, text)
        local row = child:GetUserData("cdcRow")
        if row then row:Fire("OnEnterPressed", text) end
    end

    local function ForwardTextChanged(child, event, text)
        local row = child:GetUserData("cdcRow")
        if row then row:Fire("OnTextChanged", text) end
    end

    local function ForwardEnter(child)
        local row = child:GetUserData("cdcRow")
        if row then Row_OnEnter(row.frame) end
    end

    local function ForwardLeave(child)
        local row = child:GetUserData("cdcRow")
        if row then Row_OnLeave(row.frame) end
    end

    local methods = {
        ["OnAcquire"] = function(self)
            ResetRowBase(self)

            local child = AceGUI:Create("EditBox")
            self.editBoxWidget = child
            child:SetUserData("cdcRow", self)
            child:SetCallback("OnEnterPressed", ForwardEnterPressed)
            child:SetCallback("OnTextChanged", ForwardTextChanged)
            child:SetCallback("OnEnter", ForwardEnter)
            child:SetCallback("OnLeave", ForwardLeave)
            child:SetLabel(nil)
            child:SetWidth(EDITBOX_WIDTH)

            child.frame:SetParent(self.controlColumn)
            child.frame:ClearAllPoints()
            child.frame:SetPoint("RIGHT", self.controlColumn, "RIGHT", EDITBOX_RIGHT_INSET, 0)
            child.frame:Show()

            -- Call sites reach for the raw EditBox frame (hiding the
            -- InputBoxTemplate instructions text, for one); the stock widget
            -- keeps the same object until release.
            self.editbox = child.editbox

            -- The edit box fills the column, so its frame IS the scope
            -- overlay's region. Stock SetDisabled drops mouse on the inner
            -- EditBox, so a disabled row has no control hover of its own to
            -- fight - and re-enabling it would have handed back a focusable,
            -- typeable box on an inert row.
            self.controlHoverAnchor = child.frame

            self:SetDisabled(false)
        end,

        ["OnRelease"] = function(self)
            local child = self.editBoxWidget
            self.editBoxWidget = nil
            self.editbox = nil
            self.tooltipLines = nil
            -- Before the child goes back to the shared pool: parks the scope
            -- overlay, which is anchored to the frame being released.
            self:SetScopeTooltip(nil)
            self.controlHoverAnchor = nil
            if child then
                AceGUI:Release(child)
            end
        end,

        ["SetText"] = function(self, text)
            self.editBoxWidget:SetText(text)
        end,

        ["GetText"] = function(self)
            return self.editBoxWidget:GetText()
        end,

        ["DisableButton"] = function(self, disabled)
            self.editBoxWidget:DisableButton(disabled)
        end,

        ["ClearFocus"] = function(self)
            if self.editBoxWidget then
                self.editBoxWidget:ClearFocus()
            end
        end,

        ["SetFocus"] = function(self)
            self.editBoxWidget:SetFocus()
        end,

        ["HighlightText"] = function(self, from, to)
            self.editBoxWidget:HighlightText(from, to)
        end,

        ["SetDisabled"] = function(self, disabled)
            self.disabled = disabled and true or false
            self.editBoxWidget:SetDisabled(self.disabled)
            ApplyLabelColor(self)
        end,
    }

    local function Constructor()
        local widget = BuildRowBase(EDITBOX_ROW_TYPE)
        for method, func in pairs(methods) do
            widget[method] = func
        end
        return AceGUI:RegisterAsWidget(widget)
    end

    AceGUI:RegisterWidgetType(EDITBOX_ROW_TYPE, Constructor, ROW_WIDGET_VERSION)
end

------------------------------------------------------------------------
-- CDC-ColorRow
--
-- The swatch is a stock AceGUI ColorPicker child so the commit-on-close
-- bridge in Helpers.lua (SetupColorCallbacks) keeps working unchanged: point
-- it at row.colorPicker and the callback contract is identical to the stock
-- color pickers these rows replaced.
------------------------------------------------------------------------
do
    local function ForwardPickerEnter(child)
        local row = child:GetUserData("cdcRow")
        if row then Row_OnEnter(row.frame) end
    end

    local function ForwardPickerLeave(child)
        local row = child:GetUserData("cdcRow")
        if row then Row_OnLeave(row.frame) end
    end

    local methods = {
        ["OnAcquire"] = function(self)
            ResetRowBase(self)

            local child = AceGUI:Create("ColorPicker")
            self.colorPicker = child
            child:SetUserData("cdcRow", self)
            child:SetCallback("OnEnter", ForwardPickerEnter)
            child:SetCallback("OnLeave", ForwardPickerLeave)
            child:SetLabel("")
            child:SetWidth(COLOR_SWATCH_SIZE)
            child:SetHeight(COLOR_SWATCH_SIZE)

            child.frame:SetParent(self.controlColumn)
            child.frame:ClearAllPoints()
            child.frame:SetPoint("RIGHT", self.controlColumn, "RIGHT", 0, 0)
            child.frame:Show()

            self.controlHoverAnchor = child.frame
            self:SetDisabled(false)
        end,

        ["OnRelease"] = function(self)
            local child = self.colorPicker
            -- Before the swatch goes back to the shared pool: parks the scope
            -- overlay, which is anchored to the swatch.
            self:SetScopeControlAction(nil)
            self:SetScopeTooltip(nil)
            self.controlHoverAnchor = nil
            self.colorPicker = nil
            self.tooltipLines = nil
            if child then
                AceGUI:Release(child)
            end
        end,

        ["SetColor"] = function(self, r, g, b, a)
            self.colorPicker:SetColor(r, g, b, a)
        end,

        ["GetColor"] = function(self)
            local child = self.colorPicker
            return child.r, child.g, child.b, child.a
        end,

        ["SetHasAlpha"] = function(self, hasAlpha)
            self.colorPicker:SetHasAlpha(hasAlpha)
        end,

        ["SetDisabled"] = function(self, disabled)
            self.disabled = disabled and true or false
            self.colorPicker:SetDisabled(self.disabled)
            ApplyLabelColor(self)
        end,
    }

    local function Constructor()
        local widget = BuildRowBase(COLOR_ROW_TYPE)

        for method, func in pairs(methods) do
            widget[method] = func
        end

        return AceGUI:RegisterAsWidget(widget)
    end

    AceGUI:RegisterWidgetType(COLOR_ROW_TYPE, Constructor, ROW_WIDGET_VERSION)
end

------------------------------------------------------------------------
-- CDC-LabelRow
--
-- A row that presents an ITEM rather than a setting: a label on the left and
-- either one caller-supplied control or a short status word right-aligned in
-- the control column. Every other row type owns a control because it edits a
-- value; this one has no value to edit, so the control column is the caller's.
--
-- Added for the Visibility tab's selected-eligibility rows (a class-colored
-- character/spec/hero name with a remove X, or the word "locked" where the
-- selection is inherited). None of the setting-shaped rows fit those: a
-- checkbox/dropdown/slider row would invent an editable value that does not
-- exist, and leaving them as the pre-redesign 22px Flow rows would break the
-- 30px rhythm inside a grid column full of real rows.
--
-- The control is an AceGUI WIDGET, not a raw frame, and the row takes
-- OWNERSHIP of it: it is parented and anchored here rather than added as a
-- container child, so nothing else would ever return it to its pool. OnRelease
-- releases it.
--
-- This is the one row type with NO controlHoverAnchor, so it takes no scope
-- overlay: its control column holds either a caller-supplied widget of unknown
-- anatomy or a status word, neither of which is a control the lens can call
-- inherited or denied. Nothing chromes a label row through the lens today (the
-- Customizations list wears its own revert glyph, name link and row tooltip); a
-- future call site that sets a scope tooltip on one would get nothing, which is
-- the intended stop - the whole-row hover this replaced is not a fallback.
------------------------------------------------------------------------
do
    local methods = {
        ["OnAcquire"] = function(self)
            ResetRowBase(self)
            self:SetControlText(nil)
        end,

        ["OnRelease"] = function(self)
            local child = self.controlWidget
            self.controlWidget = nil
            self.tooltipLines = nil
            self.controlText:Hide()
            if child then
                AceGUI:Release(child)
            end
        end,

        ["SetControlWidget"] = function(self, widget)
            self.controlWidget = widget
            if not widget then return end
            widget.frame:SetParent(self.controlColumn)
            widget.frame:ClearAllPoints()
            widget.frame:SetPoint("RIGHT", self.controlColumn, "RIGHT", 0, 0)
            widget.frame:Show()
        end,

        ["SetControlText"] = function(self, text)
            self.controlText:SetText(text or "")
            if text and text ~= "" then
                self.controlText:Show()
            else
                self.controlText:Hide()
            end
        end,
    }

    local function Constructor()
        local widget, _, controlColumn = BuildRowBase(LABEL_ROW_TYPE)

        local controlText = controlColumn:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        controlText:SetJustifyH("RIGHT")
        controlText:SetWordWrap(false)
        controlText:SetPoint("RIGHT", controlColumn, "RIGHT", 0, 0)
        controlText:Hide()
        widget.controlText = controlText

        for method, func in pairs(methods) do
            widget[method] = func
        end

        return AceGUI:RegisterAsWidget(widget)
    end

    AceGUI:RegisterWidgetType(LABEL_ROW_TYPE, Constructor, ROW_WIDGET_VERSION)
end

------------------------------------------------------------------------
-- ROW BUILDERS
-- Thin Create -> configure -> AddChild wrappers mirroring the call-site
-- boilerplate they replace. Every one returns the row widget.
------------------------------------------------------------------------

local function ApplyCommonRowOptions(row, opts)
    row:SetLabel(opts.label)
    if opts.indent then row:SetIndent(true) end
    if opts.tooltip then row:SetRowTooltip(opts.tooltip) end
    if opts.relativeWidth then
        row:SetRelativeWidth(opts.relativeWidth)
    else
        row:SetFullWidth(true)
    end
    if opts.controlColumnWidth then
        row:SetControlColumnWidth(opts.controlColumnWidth)
    end
    if opts.labelLines and row.rowLabel then
        row.rowLabel:SetWordWrap(true)
        if row.rowLabel.SetMaxLines then row.rowLabel:SetMaxLines(opts.labelLines) end
        row:SetHeight(opts.height or ROW_HEIGHT)
    end
end

local function AddCheckboxRow(container, opts)
    local row = AceGUI:Create(CHECKBOX_ROW_TYPE)
    ApplyCommonRowOptions(row, opts)
    if opts.tristate then row:SetTriState(true) end
    row:SetValue(opts.value)
    row:SetDisabled(opts.disabled == true)
    if opts.onChange then
        row:SetCallback("OnValueChanged", function(widget, event, value)
            opts.onChange(value, widget)
        end)
    end
    container:AddChild(row)
    return row
end

local function AddSliderRow(container, opts)
    local row = AceGUI:Create(SLIDER_ROW_TYPE)
    ApplyCommonRowOptions(row, opts)
    row:SetSliderValues(opts.min or 0, opts.max or 100, opts.step or 1)
    row:SetValue(opts.value or opts.min or 0)
    row:SetDisabled(opts.disabled == true)
    if opts.onChange then
        row:SetCallback("OnValueChanged", function(widget, event, value)
            opts.onChange(value, widget)
        end)
    end
    if opts.onRelease then
        row:SetCallback("OnMouseUp", function(widget, event, value)
            opts.onRelease(value, widget)
        end)
    end
    container:AddChild(row)
    return row
end

local function AddDropdownRow(container, opts, itemTypeOverride)
    local row = AceGUI:Create(DROPDOWN_ROW_TYPE)
    ApplyCommonRowOptions(row, opts)
    if opts.pulloutWidth then row:SetPulloutWidth(opts.pulloutWidth) end
    row:SetList(opts.list, opts.order, itemTypeOverride or opts.itemType)
    if opts.value ~= nil then row:SetValue(opts.value) end
    row:SetDisabled(opts.disabled == true)
    if opts.onChange then
        row:SetCallback("OnValueChanged", function(widget, event, value, checked)
            opts.onChange(value, widget, checked)
        end)
    end
    container:AddChild(row)
    return row
end

local function ForwardSoundPreview(item, event, value)
    local callback = item:GetUserData("cdcSoundPreviewCallback")
    if callback then
        callback(value)
    end
end

-- The sound-specific wrapper keeps pullout anatomy and pooled cleanup inside
-- this file. opts.onPreview receives the clicked sound value; it does not
-- select the item or close the dropdown.
local function AddSoundPreviewDropdownRow(container, opts)
    local onPreview = opts.onPreview
    local row = AddDropdownRow(container, opts, SOUND_PREVIEW_DROPDOWN_ITEM_TYPE)

    row:SetCallback("OnOpened", function(widget)
        if not widget.pullout then return end

        for _, item in widget.pullout:IterateItems() do
            if item.type == SOUND_PREVIEW_DROPDOWN_ITEM_TYPE then
                local value = item:GetUserData("value")
                local canPreview = type(onPreview) == "function" and value ~= nil and value ~= "None"
                item:SetPreviewEnabled(canPreview)
                if canPreview then
                    item:SetUserData("cdcSoundPreviewCallback", onPreview)
                    item:SetCallback("OnPreview", ForwardSoundPreview)
                end
            end
        end
    end)

    return row
end

-- opts.value seeds the text; opts.onEnterPressed matches the stock EditBox
-- contract (the widget is passed second so a rejected value can be put back).
local function AddEditBoxRow(container, opts)
    local row = AceGUI:Create(EDITBOX_ROW_TYPE)
    ApplyCommonRowOptions(row, opts)
    row:SetText(opts.value)
    row:SetDisabled(opts.disabled == true)
    if opts.onEnterPressed then
        row:SetCallback("OnEnterPressed", function(widget, event, text)
            opts.onEnterPressed(text, widget)
        end)
    end
    container:AddChild(row)
    return row
end

-- opts.tbl/opts.key bind the color the same way the stock color pickers they
-- replaced did, so conversion packets swap call sites 1:1 (incl. deferCommit).
local function AddColorRow(container, opts)
    local row = AceGUI:Create(COLOR_ROW_TYPE)
    ApplyCommonRowOptions(row, opts)
    row:SetHasAlpha(opts.hasAlpha == true)

    local color = opts.color
    if not color and opts.tbl and opts.key then
        color = opts.tbl[opts.key] or opts.default
    end
    color = color or opts.default or { 1, 1, 1, 1 }
    row:SetColor(color[1], color[2], color[3], color[4])

    row:SetDisabled(opts.disabled == true)

    if opts.tbl and opts.key and SetupColorCallbacks then
        local onChange = opts.onChange
        local deferCommit = opts.deferCommit
        if opts.onConfirm then
            -- A picker drag is another continuous edit: unless the caller has
            -- a distinct canvas-only callback, keep it on the active config
            -- preview and apply the saved color to live displays on close.
            if not onChange or onChange == opts.onConfirm then
                onChange = ST._RefreshActiveConfigPreview
            end
            if deferCommit == nil then
                deferCommit = true
            end
        end
        SetupColorCallbacks(row.colorPicker, opts.tbl, opts.key,
            opts.onConfirm, onChange, deferCommit)
    end

    container:AddChild(row)
    return row
end

-- opts.controlWidget hands the row an AceGUI widget to own (see CDC-LabelRow);
-- opts.controlText puts a short right-aligned status word there instead.
local function AddLabelRow(container, opts)
    local row = AceGUI:Create(LABEL_ROW_TYPE)
    ApplyCommonRowOptions(row, opts)
    if opts.controlWidget then row:SetControlWidget(opts.controlWidget) end
    if opts.controlText then row:SetControlText(opts.controlText) end
    container:AddChild(row)
    return row
end

------------------------------------------------------------------------
-- SECTION ROW GRID
--
-- Two columns of rows, side by side. The columns are TOP-ALIGNED BY DESIGN:
-- this layout anchors the left column to the content's TOPLEFT and the right
-- column to its TOPRIGHT, so columns of unequal height cannot drift.
--
-- HAZARD - do not swap this for "Flow". AceGUI's Flow layout vertically
-- CENTERS side-by-side children (frameoffset = child.alignoffset or
-- frameheight / 2, then the row is anchored by the larger offset), so two
-- half-width columns of unequal height start on different lines. That is
-- exactly the drift the first two-column attempt shipped and the owner
-- reversed. Nothing about the column contents fixes it; only the anchoring
-- does.
--
-- Contract mirrors the stock "List" layout: resolve a width, size each child,
-- drive its DoLayout, then report the used height through LayoutFinished so the
-- grid sizes itself. Height is max(left, right) - the columns overlap
-- vertically, they do not stack.
--
-- The grid and its two columns are OUR OWN container types, not stock
-- SimpleGroups. Two reasons, both structural:
--
--  1. SimpleGroup:OnWidthSet (AceGUIContainer-SimpleGroup.lua:32-36) records
--     the new width and stops - it never re-runs the layout. Any host that
--     resizes a container without also calling DoLayout therefore leaves its
--     children anchored and sized for the previous width. AceGUI's own "Fill"
--     layout (AceGUI-3.0.lua:655-665) is exactly such a host: it calls
--     SetWidth/SetHeight/SetAllPoints on its single child and never calls
--     child:DoLayout(). The tab surface is a Fill TabGroup wrapping a List
--     ScrollFrame today, so the grid is one container away from that hole.
--     Our OnWidthSet re-lays, so a width change is self-correcting no matter
--     who drives it.
--
--  2. Pool hygiene. AceGUI's pools are shared with every other addon, and this
--     layout is the only thing in the game that anchors a child TOPRIGHT of its
--     parent content. Owning the types means a frame we anchored can only ever
--     be re-acquired by us. (AceGUI:Release does ClearAllPoints on the released
--     frame - AceGUI-3.0.lua:196 - so nothing leaks either way, but keeping our
--     geometry inside our own pool removes the question entirely.)
------------------------------------------------------------------------
local ROW_GRID_LAYOUT = "CDC-RowGridTopAligned"

local function DebugGrid(fmt, ...)
    if not DEBUG_ROW_GRID then return end
    print("|cff66ccffCDC-RowGrid|r " .. string.format(fmt, ...))
end

-- Shared body for the grid and its columns: a plain frame whose content fills
-- it, plus an OnWidthSet that re-lays on a real width change.
--
-- FULLSCREEN_DIALOG matches the strata SimpleGroup's constructor forces
-- (AceGUIContainer-SimpleGroup.lua:50). These types replace SimpleGroups in an
-- already owner-validated layout, so the draw order stays byte-identical.
local function BuildGridContainer(widgetType)
    local frame = CreateFrame("Frame", nil, UIParent)
    frame:SetFrameStrata("FULLSCREEN_DIALOG")

    local content = CreateFrame("Frame", nil, frame)
    content:SetPoint("TOPLEFT")
    content:SetPoint("BOTTOMRIGHT")

    local widget = {
        frame   = frame,
        content = content,
        type    = widgetType,
        _cdcNum = AceGUI:GetNextWidgetNum(widgetType),
    }

    widget.OnAcquire = function(self)
        -- Cleared here rather than in OnRelease: OnAcquire is what AceGUI
        -- guarantees runs before a widget is used again.
        self._cdcWidthLaid = nil
        self:SetWidth(300)
        self:SetHeight(ROW_HEIGHT)
    end

    widget.LayoutFinished = function(self, _, height)
        if self.noAutoHeight then return end
        self:SetHeight(height or 0)
    end

    widget.OnWidthSet = function(self, width)
        local frameContent = self.content
        frameContent:SetWidth(width)
        frameContent.width = width
        if width ~= self._cdcWidthLaid then
            self._cdcWidthLaid = width
            self:DoLayout()
        end
    end

    widget.OnHeightSet = function(self, height)
        local frameContent = self.content
        frameContent:SetHeight(height)
        frameContent.height = height
    end

    return AceGUI:RegisterAsContainer(widget)
end

AceGUI:RegisterWidgetType(ROW_GRID_TYPE, function()
    return BuildGridContainer(ROW_GRID_TYPE)
end, ROW_WIDGET_VERSION)

AceGUI:RegisterWidgetType(ROW_GRID_COL_TYPE, function()
    return BuildGridContainer(ROW_GRID_COL_TYPE)
end, ROW_WIDGET_VERSION)

if not AceGUI:GetLayout(ROW_GRID_LAYOUT) then
    AceGUI:RegisterLayout(ROW_GRID_LAYOUT, function(content, children)
        -- LIVE GEOMETRY IS THE GROUND TRUTH. The columns are anchored to this
        -- content frame's own left and right edges, so they have to be sized in
        -- its real coordinate space. content.width is only bookkeeping pushed
        -- down by whichever parent laid us out last, and the two genuinely
        -- disagree - by exactly the scrollbar's 20px - every time a ScrollFrame
        -- toggles its bar (AceGUIContainer-ScrollFrame.lua:104-118 moves the
        -- scroll rect and rewrites content.width in the same breath, and
        -- :152-156 recomputes it again from the widget width). A TOPLEFT column
        -- and a TOPRIGHT column sized from a stale number stop meeting in the
        -- middle; sized from the live rect they cannot.
        local width = content:GetWidth() or 0
        if width < ROW_GRID_MIN_WIDTH then
            -- No usable rect yet (first pass, before anchors resolve): fall
            -- back to what the parent told us.
            width = content.width or 0
        end

        local obj = content.obj

        -- DEGENERATE WIDTH: keep the last good geometry. The previous version
        -- clamped with max(1, ...), so a pass that resolved to 0 sized both
        -- columns to 1px - which parks every row's control column ~110px
        -- OUTSIDE the scroll rect, where it is clipped and invisible, and
        -- leaves the label a negative-width string that draws nothing. Worse,
        -- nothing comes back to fix it: the grid only re-lays when its width
        -- changes, and a collapsed grid does not change anyone's width. Doing
        -- nothing is strictly better than latching that state.
        if width < ROW_GRID_MIN_WIDTH then
            DebugGrid("#%d SKIP degenerate width live=%.1f book=%s",
                obj and obj._cdcNum or -1, content:GetWidth() or -1,
                tostring(content.width))
            return
        end

        local columnWidth = floor((width - ROW_GRID_COLUMN_GAP) / 2)
        local height = 0

        for i = 1, #children do
            local child = children[i]
            local frame = child.frame
            -- Every pass re-asserts the full anchor state from scratch, so a
            -- column can never inherit a point from an earlier pass or an
            -- earlier owner of the frame.
            frame:ClearAllPoints()
            if i <= 2 then
                frame:Show()
                if i == 1 then
                    frame:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
                else
                    frame:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, 0)
                end

                child:SetWidth(columnWidth)
                if child.DoLayout then
                    child:DoLayout()
                end

                height = max(height, frame.height or frame:GetHeight() or 0)
            else
                -- Exactly two columns by construction. A third child has no
                -- home, so hide it rather than leave it floating on whatever
                -- points it last had.
                frame:Hide()
            end
        end

        DebugGrid("#%d lay live=%.1f book=%s col=%d children=%d h=%.1f",
            obj and obj._cdcNum or -1, content:GetWidth() or -1,
            tostring(content.width), columnWidth, #children, height)

        -- Stock layouts route this through AceGUI's private safecall.
        -- PerformLayout already wraps this whole function in one, so call it
        -- directly and let real errors surface.
        if obj and obj.LayoutFinished then
            obj:LayoutFinished(nil, height)
        end
    end)
end

-- Open a two-column grid inside `container` (typically the tab's ScrollFrame,
-- laid out with "List"). Add rows to `left` and `right`; sections that only
-- need one column just leave `right` empty.
local function BeginRowGrid(container)
    local grid = AceGUI:Create(ROW_GRID_TYPE)
    grid:SetFullWidth(true)
    grid:SetLayout(ROW_GRID_LAYOUT)
    container:AddChild(grid)

    local left = AceGUI:Create(ROW_GRID_COL_TYPE)
    left:SetLayout("List")
    grid:AddChild(left)

    local right = AceGUI:Create(ROW_GRID_COL_TYPE)
    right:SetLayout("List")
    grid:AddChild(right)

    return left, right, grid
end

------------------------------------------------------------------------
-- Expose for the conversion packets
------------------------------------------------------------------------
ST._RowGrammar = {
    ROW_HEIGHT = ROW_HEIGHT,
    CONTROL_COLUMN_WIDTH = CONTROL_COLUMN_WIDTH,
    CHILD_INDENT = CHILD_INDENT,
    CHECKBOX_ROW_TYPE = CHECKBOX_ROW_TYPE,
    SLIDER_ROW_TYPE = SLIDER_ROW_TYPE,
    DROPDOWN_ROW_TYPE = DROPDOWN_ROW_TYPE,
    EDITBOX_ROW_TYPE = EDITBOX_ROW_TYPE,
    COLOR_ROW_TYPE = COLOR_ROW_TYPE,
    LABEL_ROW_TYPE = LABEL_ROW_TYPE,
}

ST._AddCheckboxRow = AddCheckboxRow
ST._AddSliderRow = AddSliderRow
ST._AddDropdownRow = AddDropdownRow
ST._AddSoundPreviewDropdownRow = AddSoundPreviewDropdownRow
ST._AddEditBoxRow = AddEditBoxRow
ST._AddColorRow = AddColorRow
ST._AddLabelRow = AddLabelRow
ST._AnchorRowBadge = AnchorRowBadge
ST._BeginRowGrid = BeginRowGrid
