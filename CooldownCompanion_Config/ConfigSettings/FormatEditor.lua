--[[
    CooldownCompanion - ConfigSettings/FormatEditor.lua
    The text-mode format editor: syntax highlighting, validation, token and
    conditional pickers. Built into its one config surface - the panel's
    Format tab, which is a lens onto the selected entry - through the
    component below; this file owns no window of its own.

    There is no scenario preview here: the pinned live mirror above the config
    tabs shows the real panel rendering the real format, so the editor's job
    ends at the text.
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon
local AceGUI = LibStub("AceGUI-3.0")
local CS = ST._configState

local ParseFormatString = ST._ParseFormatString
local CreateInfoButton = ST._CreateInfoButton

-- Token list for insert buttons. Order is the order the buttons appear in.
-- {aura} and {aurastacks} are client-rendered aura pieces (TEXT RENDER PLAN
-- in ButtonFrame/TextMode.lua); the advisories below say when they cannot
-- show anything for the format being edited.
local TOKEN_LIST = {"name", "time", "charges", "maxcharges", "stacks", "aura", "aurastacks", "keybind", "status", "icon", "br"}

-- Tokens available as conditional targets.
local COND_TOKEN_LIST = {}
local COND_TOKEN_ORDER = {"time", "aura", "available", "charges", "maxcharges", "missingcharges", "zerocharges", "stacks", "keybind", "proc", "unusable", "oor", "incombat"}
for _, t in ipairs(COND_TOKEN_ORDER) do
    COND_TOKEN_LIST[t] = t
end

-- Mirrors DEFAULT_TEXT_FORMAT in ButtonFrame/TextMode.lua.
local DEFAULT_TEXT_FORMAT = "{name}  {status}"

-- Plain-language description of each conditional, shown under the
-- "Show Only When..." buttons. The wording tracks EvaluateTokenPresence in
-- ButtonFrame/TextMode.lua (what makes the condition TRUE), not what the
-- same-named value token prints.
local COND_TOKEN_HELP = {
    time = "Wraps the format so that part only shows while the entry is on cooldown.",
    aura = "Wraps the format so that part only shows while the tracked aura is active.",
    available = "Wraps the format so that part only shows while the entry is off cooldown.",
    charges = "Wraps the format so that part only shows for entries that use charges.",
    maxcharges = "Wraps the format so that part only shows while every charge is ready.",
    missingcharges = "Wraps the format so that part only shows while recharging with a charge still ready.",
    zerocharges = "Wraps the format so that part only shows while no charges are ready.",
    stacks = "Wraps the format so that part only shows while there is a stack or item count.",
    keybind = "Wraps the format so that part only shows while the entry has a keybind.",
    proc = "Wraps the format so that part only shows while the spell has a proc highlight.",
    unusable = "Wraps the format so that part only shows while the entry is not usable.",
    oor = "Wraps the format so that part only shows while the target is out of range.",
    incombat = "Wraps the format so that part only shows while you are in combat.",
}

-- Starter formats for the "Start From an Example" chips. Every string is
-- written in the parser's grammar (ButtonFrame/TextMode.lua) and validates
-- with no warnings and, under a panel lens, no advisories.
local FORMAT_TEMPLATES = {
    { label = "Name + Status",    format = DEFAULT_TEXT_FORMAT },
    { label = "Time Only",        format = "{time}" },
    { label = "Charges Tracker",  format = "{name}  {charges}/{maxcharges}" },
    { label = "Hide When Ready",  format = "{?time}{name}  {time}{/time}" },
    { label = "Pulse When Ready", format = "{?available}{pulse}{name}{/pulse}{/available}{?time}{name}  {time}{/time}" },
    { label = "Two Lines",        format = "{name}{br}{status}" },
    { label = "Stacks Watch",     format = "{name}  {stacks}" },
    { label = "Aura Timer",       format = "{name}  {aura}" },
    { label = "Aura Stacks",      format = "{name}{?aura}  {aurastacks}x{/aura}" },
}

-- Overwriting hand-written work is the one destructive thing a chip can do,
-- so it goes through the config's normal confirmation shape. The popup is
-- raised above the editor window the same way every other config popup is.
local TEMPLATE_CONFIRM_POPUP = "CDC_FORMAT_TEMPLATE_OVERWRITE"

StaticPopupDialogs[TEMPLATE_CONFIRM_POPUP] = {
    text = "Replace the current format with the %s example?\n\nThe format you have now is discarded.",
    button1 = "Replace",
    button2 = "Cancel",
    OnAccept = function(self, data)
        if data and data.apply then
            data.apply()
        end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

local function ShowTemplateConfirm(label, applyFn)
    local showFn = CS and CS.ShowPopupAboveConfig
    if showFn then
        return showFn(TEMPLATE_CONFIRM_POPUP, label, { apply = applyFn })
    end
    return StaticPopup_Show(TEMPLATE_CONFIRM_POPUP, label, nil, { apply = applyFn })
end

------------------------------------------------------------------------
-- SYNTAX COLORING
-- Builds a color-escaped string from parsed segments for display.
-- The output is set directly as EditBox text; WoW renders |c...|r natively.
------------------------------------------------------------------------
local COLOR_LITERAL      = "ffbbbbbb"  -- dim gray
local COLOR_TOKEN        = "ff00ff00"  -- green
local COLOR_UNKNOWN      = "ffff4444"  -- red
local COLOR_COND_PRESENT = "ffffff00"  -- yellow:  {?token} "show if present"
local COLOR_COND_NEGATED = "ffff8844"  -- orange:  {!token} "show if empty"
local COLOR_EFFECT       = "ffcc44ff"  -- purple:  {flash}, {pulse}, {glow}
local COLOR_COLOR_TAG    = "ff44bbff"  -- blue:    {cooldown}, {ready}, {active}

local function BuildSyntaxString(segments)
    -- Pass 1: pair cond_start with cond_end, and effect_start with effect_end
    local stack = {}       -- { {index, value, negated}, ... }
    local openMatched = {} -- openMatched[i] = true if cond_start at index i is paired
    local closeInfo = {}   -- closeInfo[i] = negated (bool) of matched opener, or nil if orphan

    local effectStack = {}
    local effectOpenMatched = {}
    local effectCloseMatched = {}

    local colorStack = {}
    local colorOpenMatched = {}
    local colorCloseMatched = {}

    for i, seg in ipairs(segments) do
        if seg.type == "cond_start" then
            stack[#stack + 1] = { index = i, value = seg.value, negated = seg.negated }
        elseif seg.type == "cond_end" then
            for j = #stack, 1, -1 do
                if stack[j].value == seg.value then
                    openMatched[stack[j].index] = true
                    closeInfo[i] = stack[j].negated
                    table.remove(stack, j)
                    break
                end
            end
        elseif seg.type == "effect_start" then
            effectStack[#effectStack + 1] = { index = i, value = seg.value }
        elseif seg.type == "effect_end" then
            for j = #effectStack, 1, -1 do
                if effectStack[j].value == seg.value then
                    effectOpenMatched[effectStack[j].index] = true
                    effectCloseMatched[i] = true
                    table.remove(effectStack, j)
                    break
                end
            end
        elseif seg.type == "color_start" then
            colorStack[#colorStack + 1] = { index = i, value = seg.value }
        elseif seg.type == "color_end" then
            for j = #colorStack, 1, -1 do
                if colorStack[j].value == seg.value then
                    colorOpenMatched[colorStack[j].index] = true
                    colorCloseMatched[i] = true
                    table.remove(colorStack, j)
                    break
                end
            end
        end
    end

    -- Pass 2: build colorized string using pairing info
    local parts = {}
    for i, seg in ipairs(segments) do
        if seg.type == "literal" then
            parts[#parts + 1] = "|c" .. COLOR_LITERAL .. seg.value .. "|r"
        elseif seg.type == "token" then
            local color = seg.unknown and COLOR_UNKNOWN or COLOR_TOKEN
            parts[#parts + 1] = "|c" .. color .. "{" .. seg.value .. "}|r"
        elseif seg.type == "cond_start" then
            local prefix = seg.negated and "!" or "?"
            local color
            if openMatched[i] then
                color = seg.negated and COLOR_COND_NEGATED or COLOR_COND_PRESENT
            else
                color = COLOR_UNKNOWN
            end
            parts[#parts + 1] = "|c" .. color .. "{" .. prefix .. seg.value .. "}|r"
        elseif seg.type == "cond_end" then
            local color
            if closeInfo[i] ~= nil then
                color = closeInfo[i] and COLOR_COND_NEGATED or COLOR_COND_PRESENT
            else
                color = COLOR_UNKNOWN
            end
            parts[#parts + 1] = "|c" .. color .. "{/" .. seg.value .. "}|r"
        elseif seg.type == "effect_start" then
            local color = effectOpenMatched[i] and COLOR_EFFECT or COLOR_UNKNOWN
            parts[#parts + 1] = "|c" .. color .. "{" .. seg.value .. "}|r"
        elseif seg.type == "effect_end" then
            local color = effectCloseMatched[i] and COLOR_EFFECT or COLOR_UNKNOWN
            parts[#parts + 1] = "|c" .. color .. "{/" .. seg.value .. "}|r"
        elseif seg.type == "color_start" then
            local color = colorOpenMatched[i] and COLOR_COLOR_TAG or COLOR_UNKNOWN
            parts[#parts + 1] = "|c" .. color .. "{" .. seg.value .. "}|r"
        elseif seg.type == "color_end" then
            local color = colorCloseMatched[i] and COLOR_COLOR_TAG or COLOR_UNKNOWN
            parts[#parts + 1] = "|c" .. color .. "{/" .. seg.value .. "}|r"
        end
    end
    return table.concat(parts)
end

------------------------------------------------------------------------
-- FORMAT VALIDATION
-- Analyzes parsed segments for structural errors (unclosed conditionals,
-- orphan close tags, unknown tokens) and returns a list of warning strings.
------------------------------------------------------------------------
local function ValidateFormat(segments)
    local warnings = {}

    -- Unknown tokens
    for _, seg in ipairs(segments) do
        if seg.type == "token" and seg.unknown then
            warnings[#warnings + 1] = "{" .. seg.value .. "} is not a recognized token"
        end
    end

    -- Pair conditionals with a stack (same logic as BuildSyntaxString)
    -- Also track segment index to detect empty conditionals.
    local stack = {}
    for i, seg in ipairs(segments) do
        if seg.type == "cond_start" then
            stack[#stack + 1] = { value = seg.value, negated = seg.negated, index = i }
        elseif seg.type == "cond_end" then
            local found = false
            for j = #stack, 1, -1 do
                if stack[j].value == seg.value then
                    -- Empty conditional: opener immediately followed by its closer
                    if stack[j].index == i - 1 then
                        local prefix = stack[j].negated and "!" or "?"
                        if stack[j].negated then
                            warnings[#warnings + 1] = "Empty {!" .. seg.value .. "}: add text to show when " .. seg.value .. " is empty"
                        else
                            warnings[#warnings + 1] = "Empty {?" .. seg.value .. "}: add text to show when " .. seg.value .. " has a value"
                        end
                    end
                    table.remove(stack, j)
                    found = true
                    break
                end
            end
            if not found then
                warnings[#warnings + 1] = "{/" .. seg.value .. "} has no matching opener"
            end
        end
    end
    for _, entry in ipairs(stack) do
        local prefix = entry.negated and "!" or "?"
        warnings[#warnings + 1] = "{" .. prefix .. entry.value .. "} is never closed"
    end

    -- Effect pairing
    local effectStack = {}
    for i, seg in ipairs(segments) do
        if seg.type == "effect_start" then
            effectStack[#effectStack + 1] = { value = seg.value, index = i }
        elseif seg.type == "effect_end" then
            local found = false
            for j = #effectStack, 1, -1 do
                if effectStack[j].value == seg.value then
                    if effectStack[j].index == i - 1 then
                        warnings[#warnings + 1] = "Empty {" .. seg.value .. "}: add content between {" .. seg.value .. "} and {/" .. seg.value .. "}"
                    end
                    table.remove(effectStack, j)
                    found = true
                    break
                end
            end
            if not found then
                warnings[#warnings + 1] = "{/" .. seg.value .. "} has no matching opener"
            end
        end
    end
    for _, entry in ipairs(effectStack) do
        warnings[#warnings + 1] = "{" .. entry.value .. "} is never closed"
    end

    -- Color tag pairing
    local colorStack = {}
    for i, seg in ipairs(segments) do
        if seg.type == "color_start" then
            colorStack[#colorStack + 1] = { value = seg.value, index = i }
        elseif seg.type == "color_end" then
            local found = false
            for j = #colorStack, 1, -1 do
                if colorStack[j].value == seg.value then
                    if colorStack[j].index == i - 1 then
                        warnings[#warnings + 1] = "Empty {" .. seg.value .. "}: add content between {" .. seg.value .. "} and {/" .. seg.value .. "}"
                    end
                    table.remove(colorStack, j)
                    found = true
                    break
                end
            end
            if not found then
                warnings[#warnings + 1] = "{/" .. seg.value .. "} has no matching opener"
            end
        end
    end
    for _, entry in ipairs(colorStack) do
        warnings[#warnings + 1] = "{" .. entry.value .. "} is never closed"
    end

    return warnings
end

------------------------------------------------------------------------
-- AURA ADVISORIES
--
-- Everything above is malformed-format territory. These are advisories: the
-- format still renders, it just will not do what the user meant. They ride
-- the same label, tinted so the two read apart without a severity system.
--
-- Aura tokens are client-rendered pieces cut out of the line by
-- BuildTextRenderPlan (TEXT RENDER PLAN in ButtonFrame/TextMode.lua). The
-- planner is the one authority on what an aura token can and cannot show,
-- so the advisories read its flags rather than re-deriving the rules from
-- the segments: {!aura} regions are dropped whole, CC tokens inside aura
-- content emit nothing, and only the first duration piece and the first
-- stacks-or-presence piece are live.
--
-- The last advisory is the editor's own: the pieces only ever get values
-- when the entry tracks an aura, which a panel-level format cannot know
-- (each entry decides for itself), so it is raised only under an entry
-- lens. entryData is the lens's buttonData, nil under a panel lens.
------------------------------------------------------------------------
local ADVISORY_COLOR = "|cffffcc66"

local function AddAdvisory(warnings, text)
    warnings[#warnings + 1] = ADVISORY_COLOR .. text .. "|r"
end

-- Mirrors the aura-tracking gate the text host applies (IsAuraOnlyEntry and
-- the Track an Aura toggle, ButtonSettingsAura.lua): a standalone aura entry
-- always tracks its aura; a spell entry tracks one only while the toggle is
-- on; nothing else can track one.
local function EntryTracksAura(entryData)
    return entryData.type == "spell"
        and (entryData.auraTracking == true or entryData.addedAs == "aura")
end

local function AppendAuraAdvisories(warnings, segments, entryData, style)
    local buildPlan = ST._BuildTextRenderPlan
    if not buildPlan then return end
    local plan = buildPlan(segments, entryData, style)

    if plan.hasNegatedAuraRegion then
        AddAdvisory(warnings, "{!aura} cannot show text while an aura is inactive on this game version, so that part never shows.")
    end
    if plan.hasUnsupportedInAura then
        AddAdvisory(warnings, "Only {aura}, {aurastacks}, {name}, {keybind}, {icon} and text work inside {?aura}...{/aura}; other tokens there show nothing.")
    end
    if plan.hasDuplicateAuraPiece then
        AddAdvisory(warnings, "{aura} can appear once per format, and {aurastacks} or a {?aura} part once; extra copies show nothing.")
    end
    if plan.hasWrappedAuraPiece then
        AddAdvisory(warnings, "Conditions and effects cannot wrap aura text; that part shows whenever the aura is active.")
    end
    if plan.hasAuraPieces and entryData and not EntryTracksAura(entryData) then
        AddAdvisory(warnings, "This entry tracks no aura, so its aura tokens show nothing. Turn on Track an Aura in the entry's Settings.")
    end
end

------------------------------------------------------------------------
-- COLOR CODE CURSOR MAPPING
-- Maps cursor positions between raw text and colorized text that has
-- |cXXXXXXXX...|r escape sequences injected by BuildSyntaxString.
------------------------------------------------------------------------
local function StripColorCodes(text)
    return text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
end

-- Convert byte position in colorized text to raw (uncolored) character count.
-- bytePos is 0-based (from GetCursorPosition): 0 = before first char.
local function ColorizedToRawPos(bytePos, text)
    local raw = 0
    local i = 1
    while i <= bytePos do
        if text:sub(i, i + 1) == "|c" and i + 9 <= #text then
            i = i + 10  -- skip |cXXXXXXXX
        elseif text:sub(i, i + 1) == "|r" then
            i = i + 2   -- skip |r
        else
            i = i + 1
            raw = raw + 1
        end
    end
    return raw
end

-- Convert raw character position to byte position in colorized text.
-- Returns 0-based position suitable for SetCursorPosition.
local function RawToColorizedPos(rawPos, colorizedText)
    if rawPos <= 0 then return 0 end
    local raw = 0
    local i = 1
    while raw < rawPos and i <= #colorizedText do
        if colorizedText:sub(i, i + 1) == "|c" and i + 9 <= #colorizedText then
            i = i + 10
        elseif colorizedText:sub(i, i + 1) == "|r" then
            i = i + 2
        else
            i = i + 1
            raw = raw + 1
        end
    end
    -- i is now 1-based position AFTER the rawPos'th visible char; convert to 0-based
    return i - 1
end

------------------------------------------------------------------------
-- COLOR TAG RESOLUTION
-- Maps a {cooldown}/{ready}/{active}/{custom} tag name onto the style color
-- the text renderer paints that span with. Only the insert-button swatches
-- read it now, through GetStyleTagColor below.
------------------------------------------------------------------------
local function ResolvePreviewColor(name, cdColor, readyColor, auraColor, customColor)
    if name == "cooldown" then return cdColor
    elseif name == "ready" then return readyColor
    elseif name == "active" then return auraColor
    elseif name == "custom" then return customColor
    end
end

-- Fallbacks for the swatch lookup below. Read-only: never write an index.
local DEFAULT_TAG_COOLDOWN_COLOR = {1, 0.3, 0.3, 1}
local DEFAULT_TAG_READY_COLOR    = {0.2, 1.0, 0.2, 1}
local DEFAULT_TAG_ACTIVE_COLOR   = {0, 0.925, 1, 1}
local DEFAULT_TAG_CUSTOM_COLOR   = {1, 0.82, 0, 1}

-- The palette color a {cooldown}/{ready}/{active}/{custom} tag resolves to
-- for one style, using the same fallbacks the text renderer falls back to so
-- a swatch and the rendered panel can never disagree. Always called with the
-- editor's CURRENT style, never a style captured when the window was first
-- built.
local function GetStyleTagColor(style, name)
    return ResolvePreviewColor(name,
        style.textCooldownColor or DEFAULT_TAG_COOLDOWN_COLOR,
        style.textReadyColor or DEFAULT_TAG_READY_COLOR,
        style.textAuraColor or DEFAULT_TAG_ACTIVE_COLOR,
        style.textCustomColor or DEFAULT_TAG_CUSTOM_COLOR)
end

------------------------------------------------------------------------
-- COLOR TAG SWATCHES
-- A stock AceGUI Button with a palette square inside it, left of the label.
-- AceGUI pools Button frames, so both the textures and the moved fontstring
-- anchors have to be undone on release or the next unrelated Button in the
-- config wears this one's swatch.
------------------------------------------------------------------------
local COLOR_SWATCH_SIZE = 12
local COLOR_SWATCH_INSET = 6
local COLOR_BUTTON_TEXT_INSET = COLOR_SWATCH_INSET + COLOR_SWATCH_SIZE + 4
local COLOR_BUTTON_RIGHT_INSET = 8

-- Stock anchors from AceGUIWidget-Button.lua's constructor.
local BUTTON_TEXT_STOCK_INSET = 15

local function ReleaseColorSwatch(button)
    local swatch = button._cdcColorSwatch
    if swatch then
        swatch.border:Hide()
        swatch.fill:Hide()
    end
    local text = button.text
    if text then
        text:ClearAllPoints()
        text:SetPoint("TOPLEFT", BUTTON_TEXT_STOCK_INSET, -1)
        text:SetPoint("BOTTOMRIGHT", -BUTTON_TEXT_STOCK_INSET, 1)
    end
end

-- Call after the button's final text is set: the width is measured from it.
local function AttachColorSwatch(button)
    local frame = button.frame
    local swatch = button._cdcColorSwatch
    if not swatch then
        local border = frame:CreateTexture(nil, "OVERLAY")
        border:SetColorTexture(0, 0, 0, 1)
        border:SetSize(COLOR_SWATCH_SIZE, COLOR_SWATCH_SIZE)
        border:SetPoint("LEFT", frame, "LEFT", COLOR_SWATCH_INSET, 0)

        local fill = frame:CreateTexture(nil, "OVERLAY", nil, 1)
        fill:SetPoint("TOPLEFT", border, "TOPLEFT", 1, -1)
        fill:SetPoint("BOTTOMRIGHT", border, "BOTTOMRIGHT", -1, 1)

        swatch = { border = border, fill = fill }
        button._cdcColorSwatch = swatch
    end
    swatch.border:Show()
    swatch.fill:Show()

    local text = button.text
    local textWidth = text:GetStringWidth()
    text:ClearAllPoints()
    text:SetPoint("TOPLEFT", COLOR_BUTTON_TEXT_INSET, -1)
    text:SetPoint("BOTTOMRIGHT", -COLOR_BUTTON_RIGHT_INSET, 1)
    button:SetWidth(textWidth + COLOR_BUTTON_TEXT_INSET + COLOR_BUTTON_RIGHT_INSET)

    button:SetCallback("OnRelease", ReleaseColorSwatch)
    return swatch.fill
end

------------------------------------------------------------------------
-- FORMAT EDITOR CONTENT
-- Builds everything an editor shows between its title and its Save button
-- into any AceGUI container, and returns a controller the host drives:
--
--   controller:SetTarget({ style, saveTarget, defaultFormat })
--   controller:GetRawText()
--   controller:Release()      -- safe to call twice
--
-- opts.target   initial target table, same shape as SetTarget's argument
-- opts.setting  Settings Finder descriptor for the Format String editor
-- opts.onDirty  optional; called with the controller whenever the raw format
--               string changes from typing, a starter chip, or an insert
-- opts.onCommit optional; called when editing is explicitly finished by focus
--               loss or Enter so the host can flush its debounced write
--
-- The host carries its own bookkeeping in the same target table (the groupId it
-- refreshes through); the component reads only the three keys listed above.
--
-- The host owns the tab, the title, and EVERY commit: this component never
-- writes to the profile and deliberately offers no commit method of its own.
-- The host debounces its write and ends it at RefreshGroupFrame, because a
-- commit path that reached RefreshConfigPanel would release the very editor
-- being typed in and drop the cursor.
------------------------------------------------------------------------
local function BuildFormatEditorContent(container, opts)
    opts = opts or {}
    local controller = {}

    -- Editor state, declared before any section so every section below can
    -- reach it. AceGUI's List layout follows AddChild order, so the order the
    -- widgets are created in below IS the order they appear in: edit box,
    -- validation, starter chips, then the insert sections.
    --
    -- The EditBox text carries |c...|r color codes for native rendering;
    -- currentRawText is the actual format string the user is editing.
    local initialTarget = opts.target or {}
    local currentStyle = initialTarget.style or {}
    -- The entry under an entry lens, nil under a panel lens. Kept apart from
    -- currentFormatTarget (which falls back to the style) because the aura
    -- advisories need to know WHETHER an entry is being edited.
    local currentEntryData = initialTarget.saveTarget
    local currentFormatTarget = currentEntryData or currentStyle
    local currentDefaultFormat = initialTarget.defaultFormat or DEFAULT_TEXT_FORMAT
    local currentRawText = currentFormatTarget.textFormat or currentDefaultFormat

    local eb                    -- edit box; assigned with the widget below
    local ApplyColorized        -- assigned once the edit box exists
    local UpdateDisplay         -- assigned once the warning label exists
    local RefreshColorSwatches  -- assigned once the color buttons exist

    local function NotifyDirty()
        if opts.onDirty then
            opts.onDirty(controller)
        end
    end

    local function NotifyCommit()
        if opts.onCommit then
            opts.onCommit(controller)
        end
    end

    -- ================================================================
    -- EDIT BOX (MultiLineEditBox) with inline syntax coloring
    -- ================================================================
    local editGroup = AceGUI:Create("MultiLineEditBox")
    editGroup:SetLabel("Format String")
    editGroup:SetFullWidth(true)
    editGroup:SetNumLines(6)
    editGroup.button:Hide()  -- hide "Accept" button, we save on change
    editGroup.scrollBar:Hide()
    editGroup.scrollBG:SetPoint("TOPRIGHT", editGroup.frame, "TOPRIGHT", -4, -23)
    if opts.setting and ST._BindSettingWidget then
        ST._BindSettingWidget(editGroup, opts.setting, "Format String")
    end
    container:AddChild(editGroup)

    eb = editGroup.editBox

    -- Helper: colorize raw text and set into EditBox, preserving cursor position.
    ApplyColorized = function(rawText, rawCursorPos)
        local colorized = BuildSyntaxString(ParseFormatString(rawText))
        local colorizedCursor = RawToColorizedPos(rawCursorPos, colorized)
        eb:SetText(colorized)
        eb:SetCursorPosition(colorizedCursor)
    end

    -- Set initial colorized text
    ApplyColorized(currentRawText, #currentRawText)

    -- ================================================================
    -- WARNING LABEL (below editbox, shows validation errors)
    --
    -- Stays immediately under the edit box: it comments on that box's
    -- contents, so nothing may be inserted between the two.
    -- ================================================================
    local warningLabel = AceGUI:Create("Label")
    ST._ConfigureWrappedHelperLabel(warningLabel)
    warningLabel:SetFullWidth(true)
    warningLabel:SetFontObject(GameFontNormalSmall)
    warningLabel:SetColor(1, 0.4, 0.4)
    warningLabel:SetText("")
    container:AddChild(warningLabel)

    -- ================================================================
    -- UPDATE FUNCTION
    -- Everything that has to follow currentRawText or currentStyle: the
    -- validation readout, and the palette swatches on the color buttons.
    -- What the format actually LOOKS like is the live mirror's job.
    -- ================================================================
    UpdateDisplay = function()
        local segments = ParseFormatString(currentRawText)

        -- Swatches follow currentStyle, so this also covers a _refresh that
        -- retargets the editor at a different panel.
        if RefreshColorSwatches then
            RefreshColorSwatches()
        end

        local warnings = ValidateFormat(segments)
        -- Runs after the structural pass so malformed-format errors always
        -- read first.
        AppendAuraAdvisories(warnings, segments, currentEntryData, currentStyle)
        if #warnings > 0 then
            warningLabel:SetText(table.concat(warnings, "\n"))
        else
            warningLabel:SetText("")
        end

        container:DoLayout()
    end

    -- Initial validation pass. RefreshColorSwatches is still nil here; the
    -- color section paints its own swatches once it has built them.
    UpdateDisplay()

    -- ================================================================
    -- STARTER TEMPLATES
    -- ================================================================
    local templateHeading = AceGUI:Create("Heading")
    templateHeading:SetText("Start From an Example")
    templateHeading.right:ClearAllPoints()
    templateHeading.right:SetPoint("RIGHT", templateHeading.frame, "RIGHT", -3, 0)
    templateHeading.right:SetPoint("LEFT", templateHeading.label, "RIGHT", 5, 0)
    templateHeading:SetFullWidth(true)
    container:AddChild(templateHeading)

    local templateGroup = AceGUI:Create("SimpleGroup")
    templateGroup:SetFullWidth(true)
    templateGroup:SetLayout("Flow")
    templateGroup:SetAutoAdjustHeight(true)
    container:AddChild(templateGroup)

    -- A chip overwrites silently only when there is nothing of the user's to
    -- lose: empty, still the default for this target, or already an example.
    local function IsDisposableFormat(text)
        if not text or text == "" then return true end
        if text == currentDefaultFormat or text == DEFAULT_TEXT_FORMAT then return true end
        for _, tpl in ipairs(FORMAT_TEMPLATES) do
            if text == tpl.format then return true end
        end
        return false
    end

    -- Same path typing takes: raw text, recolorize, validation, swatches.
    local function ApplyTemplate(formatString)
        -- The confirmation popup can outlive the editor that opened it.
        if controller.released then return end
        currentRawText = formatString
        ApplyColorized(currentRawText, #currentRawText)
        UpdateDisplay()
        eb:SetFocus()
        NotifyDirty()
    end

    for _, tpl in ipairs(FORMAT_TEMPLATES) do
        local chip = AceGUI:Create("Button")
        chip:SetText(tpl.label)
        chip:SetAutoWidth(true)
        chip:SetCallback("OnClick", function()
            if IsDisposableFormat(currentRawText) then
                ApplyTemplate(tpl.format)
            else
                ShowTemplateConfirm(tpl.label, function()
                    ApplyTemplate(tpl.format)
                end)
            end
        end)
        templateGroup:AddChild(chip)
    end

    -- ================================================================
    -- INSERT HELPER (shared by token + conditional buttons)
    -- ================================================================
    local function InsertAtCursor(insertText, cursorOffset)
        cursorOffset = cursorOffset or #insertText
        local colorized = eb:GetText() or ""
        local colorizedCursor = eb:GetCursorPosition()
        local rawCursor = ColorizedToRawPos(colorizedCursor, colorized)

        local newRaw = currentRawText:sub(1, rawCursor) .. insertText .. currentRawText:sub(rawCursor + 1)
        currentRawText = newRaw

        ApplyColorized(newRaw, rawCursor + cursorOffset)
        eb:SetFocus()
        UpdateDisplay()
        NotifyDirty()
    end

    -- ================================================================
    -- SHOW INFORMATION (value token inserts)
    -- ================================================================
    local tokenHeading = AceGUI:Create("Heading")
    tokenHeading:SetText("Show Information")
    tokenHeading:SetFullWidth(true)
    container:AddChild(tokenHeading)

    local tokenInfo = CreateInfoButton(tokenHeading.frame, tokenHeading.label, "LEFT", "RIGHT", 4, 0, {
        {"Available Tokens", 1, 0.82, 0},
        " ",
        {"|cff00ff00{name}|r  Spell/item display name", 1, 1, 1},
        {"|cff00ff00{time}|r  Cooldown time remaining", 1, 1, 1},
        {"|cff00ff00{charges}|r  Current charges (if spell has charges)", 1, 1, 1},
        {"|cff00ff00{maxcharges}|r  Maximum charges (if spell has charges)", 1, 1, 1},
        {"|cff00ff00{stacks}|r  Item count", 1, 1, 1},
        {"|cff00ff00{aura}|r  Remaining time of the tracked aura", 1, 1, 1},
        {"|cff00ff00{aurastacks}|r  Stacks of the tracked aura", 1, 1, 1},
        {"|cff00ff00{keybind}|r  Keybind text", 1, 1, 1},
        {"|cff00ff00{status}|r  Ready or cooldown; on aura entries, aura time", 1, 1, 1},
        {"|cff00ff00{icon}|r  Inline spell icon", 1, 1, 1},
        {"|cff00ff00{br}|r  Insert a manual line break", 1, 1, 1},
        " ",
        {"Aura Text", 1, 0.82, 0},
        " ",
        {"The game draws aura values in their own column,", 0.7, 0.7, 0.7},
        {"with room reserved for the longest value.", 0.7, 0.7, 0.7},
        " ",
        {"Put them at the end of a line, or on their own line,", 0.7, 0.7, 0.7},
        {"for the tightest fit.", 0.7, 0.7, 0.7},
        " ",
        {"Text inside |cffffff00{?aura}|r...|cffffff00{/aura}|r shows only", 0.7, 0.7, 0.7},
        {"while the aura is active.", 0.7, 0.7, 0.7},
        {"The entry must track an aura (see its Settings).", 0.7, 0.7, 0.7},
        " ",
        {"An aura with no duration shows no time.", 0.7, 0.7, 0.7},
        {"Use |cffffff00{?aura}|rActive|cffffff00{/aura}|r for a word while it is up.", 0.7, 0.7, 0.7},
        " ",
        {"Low Time, Pandemic and stack colours", 0.7, 0.7, 0.7},
        {"do not apply to text panels.", 0.7, 0.7, 0.7},
    }, tokenHeading)
    tokenHeading.right:ClearAllPoints()
    tokenHeading.right:SetPoint("RIGHT", tokenHeading.frame, "RIGHT", -3, 0)
    tokenHeading.right:SetPoint("LEFT", tokenInfo, "RIGHT", 4, 0)

    local tokenGroup = AceGUI:Create("SimpleGroup")
    tokenGroup:SetFullWidth(true)
    tokenGroup:SetLayout("Flow")
    tokenGroup:SetAutoAdjustHeight(true)
    container:AddChild(tokenGroup)

    for _, tokenName in ipairs(TOKEN_LIST) do
        local btn = AceGUI:Create("Button")
        btn:SetText("{" .. tokenName .. "}")
        btn:SetAutoWidth(true)
        btn:SetCallback("OnClick", function()
            InsertAtCursor("{" .. tokenName .. "}")
        end)
        tokenGroup:AddChild(btn)
    end

    -- ================================================================
    -- COLOR A SECTION (color tag inserts)
    -- ================================================================
    local colorHeading = AceGUI:Create("Heading")
    colorHeading:SetText("Color a Section")
    colorHeading:SetFullWidth(true)
    container:AddChild(colorHeading)

    local colorInfo = CreateInfoButton(colorHeading.frame, colorHeading.label, "LEFT", "RIGHT", 4, 0, {
        {"Color a Section", 1, 0.82, 0, true},
        " ",
        {"Wrap tokens or literal text to recolor that span,", 1, 1, 1, true},
        {"overriding the token's default coloring.", 1, 1, 1, true},
        " ",
        {"|cff44bbff{cooldown}|r  Cooldown color", 1, 1, 1, true},
        {"|cff44bbff{ready}|r  Ready color", 1, 1, 1, true},
        {"|cff44bbff{active}|r  Aura active color", 1, 1, 1, true},
        {"|cff44bbff{custom}|r  Custom color", 1, 1, 1, true},
        " ",
        {"The swatches show this panel's colors.", 0.7, 0.7, 0.7, true},
        {"Change them in the Colors section of the Appearance tab.", 0.7, 0.7, 0.7, true},
        " ",
        {"Example:", 0.7, 0.7, 0.7, true},
        {"|cff44bbff{cooldown}|r|cff00ff00{name}|r|cff44bbff{/cooldown}|r", 0.7, 0.7, 0.7, true},
        {"Shows the spell name in the cooldown color.", 0.7, 0.7, 0.7, true},
        " ",
        {"Nestable: inner color overrides outer.", 0.7, 0.7, 0.7, true},
        {"Composes with conditionals and effects.", 0.7, 0.7, 0.7, true},
    }, colorHeading)
    colorHeading.right:ClearAllPoints()
    colorHeading.right:SetPoint("RIGHT", colorHeading.frame, "RIGHT", -3, 0)
    colorHeading.right:SetPoint("LEFT", colorInfo, "RIGHT", 4, 0)

    local colorGroup = AceGUI:Create("SimpleGroup")
    colorGroup:SetFullWidth(true)
    colorGroup:SetLayout("Flow")
    colorGroup:SetAutoAdjustHeight(true)
    container:AddChild(colorGroup)

    local colorSwatches = {}
    for _, colorName in ipairs({"cooldown", "ready", "active", "custom"}) do
        local colorBtn = AceGUI:Create("Button")
        colorBtn:SetText("{" .. colorName .. "}")
        colorBtn:SetCallback("OnClick", function()
            local open = "{" .. colorName .. "}"
            local close = "{/" .. colorName .. "}"
            InsertAtCursor(open .. close, #open)
        end)
        -- Attach before AddChild so the first layout already sees the width
        -- the swatch forces.
        colorSwatches[#colorSwatches + 1] = {
            name = colorName,
            fill = AttachColorSwatch(colorBtn),
        }
        colorGroup:AddChild(colorBtn)
    end

    RefreshColorSwatches = function()
        for _, entry in ipairs(colorSwatches) do
            local c = GetStyleTagColor(currentStyle, entry.name)
            entry.fill:SetColorTexture(c[1] or 1, c[2] or 1, c[3] or 1, 1)
        end
    end
    RefreshColorSwatches()

    -- ================================================================
    -- SHOW ONLY WHEN (conditional inserts)
    -- ================================================================
    local condHeading = AceGUI:Create("Heading")
    condHeading:SetText("Show Only When...")
    condHeading:SetFullWidth(true)
    container:AddChild(condHeading)

    local condInfo = CreateInfoButton(condHeading.frame, condHeading.label, "LEFT", "RIGHT", 4, 0, {
        {"Available Conditionals", 1, 0.82, 0, true},
        " ",
        {"Show or hide parts of the format string based", 1, 1, 1, true},
        {"on whether a condition is true.", 1, 1, 1, true},
        " ",
        {"|cffffff00{time}|r  Cooldown time remaining", 1, 1, 1, true},
        {"|cffffff00{aura}|r  Tracked aura is active", 1, 1, 1, true},
        {"|cffffff00{available}|r  Off cooldown", 1, 1, 1, true},
        {"|cffffff00{charges}|r  Entry uses charges", 1, 1, 1, true},
        {"|cffffff00{maxcharges}|r  At max charges", 1, 1, 1, true},
        {"|cffffff00{missingcharges}|r  Recharging with charges left", 1, 1, 1, true},
        {"|cffffff00{zerocharges}|r  All charges spent", 1, 1, 1, true},
        {"|cffffff00{stacks}|r  Has a stack or item count", 1, 1, 1, true},
        {"|cffffff00{keybind}|r  Keybind text", 1, 1, 1, true},
        {"|cffffff00{proc}|r  Spell proc overlay active", 1, 1, 1, true},
        {"|cffffff00{unusable}|r  Spell/item not usable", 1, 1, 1, true},
        {"|cffffff00{oor}|r  Target out of range", 1, 1, 1, true},
        {"|cffffff00{incombat}|r  Player is in combat", 1, 1, 1, true},
        " ",
        {"Syntax", 1, 0.82, 0, true},
        " ",
        {"|cffffff00{?token}|r...|cffffff00{/token}|r  Show when true", 1, 1, 1, true},
        {"|cffff8844{!token}|r...|cffff8844{/token}|r  Show when false", 1, 1, 1, true},
        " ",
        {"|cffff8844{!aura}|r is not available on this game version.", 0.7, 0.7, 0.7, true},
        " ",
        {"Example:", 0.7, 0.7, 0.7, true},
        {"|cffffff00{?time}|rCD: |cff00ff00{time}|r|cffffff00{/time}|r", 0.7, 0.7, 0.7, true},
        {"Shows 'CD: 1:23' on cooldown, nothing when ready.", 0.7, 0.7, 0.7, true},
    }, condHeading)
    condHeading.right:ClearAllPoints()
    condHeading.right:SetPoint("RIGHT", condHeading.frame, "RIGHT", -3, 0)
    condHeading.right:SetPoint("LEFT", condInfo, "RIGHT", 4, 0)

    local condGroup = AceGUI:Create("SimpleGroup")
    condGroup:SetFullWidth(true)
    condGroup:SetLayout("Flow")
    condGroup:SetAutoAdjustHeight(true)
    container:AddChild(condGroup)

    local condDropdown = AceGUI:Create("Dropdown")
    condDropdown:SetLabel("")
    condDropdown:SetWidth(130)
    condDropdown:SetList(COND_TOKEN_LIST, COND_TOKEN_ORDER)
    condDropdown:SetValue("time")
    condGroup:AddChild(condDropdown)

    local function InsertConditional(prefix)
        local token = condDropdown:GetValue()
        local open = "{" .. prefix .. token .. "}"
        local close = "{/" .. token .. "}"
        InsertAtCursor(open .. close, #open)
    end

    local showBtn = AceGUI:Create("Button")
    showBtn:SetText("Show if present")
    showBtn:SetAutoWidth(true)
    showBtn:SetCallback("OnClick", function() InsertConditional("?") end)
    condGroup:AddChild(showBtn)

    local hideBtn = AceGUI:Create("Button")
    hideBtn:SetText("Show if empty")
    hideBtn:SetAutoWidth(true)
    hideBtn:SetCallback("OnClick", function() InsertConditional("!") end)
    condGroup:AddChild(hideBtn)

    -- Plain-language readout of whatever the dropdown currently names, so the
    -- conditions do not all have to be learned from the info button.
    local condHelp = AceGUI:Create("Label")
    ST._ConfigureWrappedHelperLabel(condHelp)
    condHelp:SetFullWidth(true)
    condHelp:SetFontObject(GameFontNormalSmall)
    condHelp:SetColor(0.6, 0.6, 0.6)
    container:AddChild(condHelp)

    local function UpdateCondHelp()
        condHelp:SetText(COND_TOKEN_HELP[condDropdown:GetValue()] or "")
        container:DoLayout()
    end
    condDropdown:SetCallback("OnValueChanged", UpdateCondHelp)
    UpdateCondHelp()

    -- ================================================================
    -- EFFECTS
    -- ================================================================
    local effectHeading = AceGUI:Create("Heading")
    effectHeading:SetText("Effects")
    effectHeading:SetFullWidth(true)
    container:AddChild(effectHeading)

    local effectInfo = CreateInfoButton(effectHeading.frame, effectHeading.label, "LEFT", "RIGHT", 4, 0, {
        {"Visual Effects", 1, 0.82, 0, true},
        " ",
        {"Wrap tokens or text in effect tags to add", 1, 1, 1, true},
        {"animated visual indicators.", 1, 1, 1, true},
        " ",
        {"|cffcc44ff{pulse}|r  Smooth sine alpha oscillation (~1Hz)", 1, 1, 1, true},
        " ",
        {"Composes with conditionals:", 0.7, 0.7, 0.7, true},
        {"|cffffff00{?charges}|r|cffcc44ff{pulse}|r|cff00ff00{charges}|r|cffcc44ff{/pulse}|r|cffffff00{/charges}|r", 0.7, 0.7, 0.7, true},
        {"Pulse only when charges exist.", 0.7, 0.7, 0.7, true},
        " ",
        {"Pulse affects the whole line's alpha.", 0.7, 0.7, 0.7, true},
    }, effectHeading)
    effectHeading.right:ClearAllPoints()
    effectHeading.right:SetPoint("RIGHT", effectHeading.frame, "RIGHT", -3, 0)
    effectHeading.right:SetPoint("LEFT", effectInfo, "RIGHT", 4, 0)

    local effectGroup = AceGUI:Create("SimpleGroup")
    effectGroup:SetFullWidth(true)
    effectGroup:SetLayout("Flow")
    effectGroup:SetAutoAdjustHeight(true)
    container:AddChild(effectGroup)

    local pulseBtn = AceGUI:Create("Button")
    pulseBtn:SetText("{pulse}")
    pulseBtn:SetAutoWidth(true)
    pulseBtn:SetCallback("OnClick", function()
        InsertAtCursor("{pulse}{/pulse}", 7)
    end)
    effectGroup:AddChild(pulseBtn)

    -- ================================================================
    -- LIVE EDIT CALLBACK
    -- ================================================================

    -- OnTextChanged fires only on user input (AceGUI checks userInput flag).
    -- Strip color codes from edited text, re-colorize, and restore cursor.
    editGroup:SetCallback("OnTextChanged", function(widget, event, text)
        local newRaw = StripColorCodes(text)
        if newRaw == currentRawText then return end

        local colorizedCursor = eb:GetCursorPosition()
        local rawCursor = ColorizedToRawPos(colorizedCursor, text)
        currentRawText = newRaw

        ApplyColorized(newRaw, rawCursor)
        UpdateDisplay()
        NotifyDirty()
    end)
    editGroup:SetCallback("OnEditFocusLost", NotifyCommit)
    editGroup:SetCallback("OnEnterPressed", NotifyCommit)

    -- ================================================================
    -- CONTROLLER
    -- ================================================================
    -- (Re)binds every piece of editor state, then repaints the text, the
    -- colorization, the validation and the swatches from the new target.
    function controller:SetTarget(newTarget)
        newTarget = newTarget or {}
        currentStyle = newTarget.style or {}
        currentEntryData = newTarget.saveTarget
        currentFormatTarget = currentEntryData or currentStyle
        currentDefaultFormat = newTarget.defaultFormat or DEFAULT_TEXT_FORMAT
        currentRawText = currentFormatTarget.textFormat or currentDefaultFormat
        ApplyColorized(currentRawText, #currentRawText)
        -- Repaints the swatches from the new style as well.
        UpdateDisplay()
    end

    function controller:GetRawText()
        return currentRawText
    end

    -- Drops everything the component owns outside AceGUI's own pooling. The
    -- widgets themselves go back with whoever releases the container.
    function controller:Release()
        if controller.released then return end
        controller.released = true
        -- A pending template confirmation has nothing left to apply, and
        -- ApplyTemplate refuses to run once released either way.
        StaticPopup_Hide(TEMPLATE_CONFIRM_POPUP)
    end

    return controller
end

------------------------------------------------------------------------
-- EXPORTS
------------------------------------------------------------------------
-- The editor body, built into its one config surface (the panel's Format tab).
-- See the component's header comment for the controller API.
ST._BuildFormatEditorContent = BuildFormatEditorContent
