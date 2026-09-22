--[[
    CooldownCompanion - ButtonPanelPreviewText
    Text-slot styling, token rendering, aura pieces, and text group headers.

    Part of the ButtonPanelPreview family; see its ordered block in the addon TOC.
    Private helpers are shared through ST._ButtonPanelPreview.
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon
local math_max = math.max
local GetLayoutPreviewIcon = ST._GetLayoutPreviewIcon
local GetConfigEntryDisplayName = ST._GetConfigEntryDisplayName
local ApplyBorderEdgePositions = ST._ApplyBorderEdgePositions
local GetStoredConditionalPreviewState = ST._GetStoredConditionalPreviewState
local GetConditionalPreviewTiming = ST._GetConditionalPreviewTiming
local ParseFormatString = ST._ParseFormatString

local PP = ST._ButtonPanelPreview

-- ButtonPanelPreviewShared.lua
local IsBarPreviewAuraActive = PP.IsBarPreviewAuraActive

-- Forward declaration: defined with the text-slot suite below, referenced
-- by the ticker for the text countdown re-render.
local RenderTextSlot

-- Static mirror of TextMode.lua CreateTextFrame: same saved settings,
-- entry name in place of the live token-substituted format string.
local function StyleTextEntry(slot, buttonData, group)
    local style = group.style or {}
    if CooldownCompanion.GetEffectiveStyle then
        style = CooldownCompanion:GetEffectiveStyle(style, buttonData, group) or style
    end

    local bgColor = style.textBgColor or { 0, 0, 0, 0 }
    slot.bg:SetColorTexture(bgColor[1], bgColor[2], bgColor[3], bgColor[4])

    local borderSize = style.textBorderSize or 0
    local borderRenderMode = ST.GetBorderRenderMode(style, "textBorderRenderMode")
    local borderColor = style.textBorderColor or { 0, 0, 0, 1 }
    for i = 1, 4 do
        slot.borderTextures[i]:SetColorTexture(borderColor[1], borderColor[2], borderColor[3], borderColor[4])
    end
    ApplyBorderEdgePositions(slot.borderTextures, slot, borderSize, borderRenderMode)

    local ts = slot.textString
    local font = CooldownCompanion:FetchFont(style.textFont or "Friz Quadrata TT")
    local fontSize = style.textFontSize or 12
    local fontOutline = ST.GetEffectiveFontOutline(style.textFontOutline or "OUTLINE")
    ts:SetFont(font, fontSize, fontOutline)
    local baseColor = style.textFontColor or { 1, 1, 1, 1 }
    ts:SetTextColor(baseColor[1], baseColor[2], baseColor[3], baseColor[4] or 1)
    ts:SetJustifyH(style.textAlignment or "LEFT")
    ST.ApplyFontShadowForOutline(ts, fontOutline, style.textShadow == true)
    -- Same padding contract as the live renderer: the slot box already
    -- reserves textPadding (GetTextEntryMetrics), so the string must be
    -- inset by it too or the mirror pins text to the border while the
    -- live button pads it.
    local padX, padY = 2, 1
    if ST._GetTextStringPadding then
        padX, padY = ST._GetTextStringPadding(style, slot)
    end
    ts:ClearAllPoints()
    ts:SetPoint("TOPLEFT", padX, -padY)
    ts:SetPoint("BOTTOMRIGHT", -padX, padY)
    -- Text content is rendered by ApplyTextSlotConditionalPreview (the
    -- entry's real token format, in its base or previewed state).
    slot.style = style
end

------------------------------------------------------------------------
-- Text-slot format rendering + conditional previews: the text mirror
-- renders each entry's format through the shared TextFormat grammar/walk.
-- Its adapter reads only saved settings, static
-- name/keybind lookups, and the stored conditional preview state (never
-- live cooldown/aura/charge values). Idle base state: no time, aura
-- inactive, full charges, no stacks. The {pulse} animation is the one
-- live effect the static mirror does not run (its content still shows).
--
-- Composite formats (TextMode.lua TEXT RENDER PLAN): the same plan the
-- live entry renders from cuts the line into cc columns and aura pieces.
-- The mirror lays one stand-in FontString per column on the plan's own
-- geometry, renders the cc columns through the substitution below, and
-- fills the pieces with sample values only while an aura preview runs --
-- blank pieces ARE the idle look, the reserved gap the format editor's
-- tooltip describes.
------------------------------------------------------------------------
local TextFormat = ST._TextFormat
local DEFAULT_TEXT_FORMAT = TextFormat.DEFAULT_TEXT_FORMAT
local PREVIEW_TEXT_ADAPTER = {
    Name = function(data)
        local name = data.customName or data.name or ""
        if not data.customName and data.type == "spell" then
            local spellName = C_Spell.GetSpellName(data.id)
            if spellName then name = spellName end
        elseif not data.customName and CooldownCompanion.IsEntryItemLike(data) then
            local itemName = data.id and C_Item.GetItemNameByID(data.id)
            if itemName then name = itemName end
        end
        return name
    end,
    Keybind = function(data) return CooldownCompanion:GetKeybindText(data, nil, nil) end,
    Icon = GetLayoutPreviewIcon,
    InCombat = function() return UnitAffectingCombat("player") end,
}

-- Only saved identities and explicitly simulated values enter this context.
local function FormatPreviewTokens(slot, segments, style, buttonData, condState, now)
    local kind = condState and condState.kind or nil
    local timeRemaining
    if kind == "cooldown" and GetConditionalPreviewTiming then
        local startTime, _, remaining = GetConditionalPreviewTiming(condState, now)
        if startTime and remaining and remaining > 0 then
            timeRemaining = remaining
        end
    end

    local usesCharges = CooldownCompanion.UsesChargeBehavior
        and CooldownCompanion.UsesChargeBehavior(buttonData) or false
    local currentCharges, maxCharges, chargeState
    if usesCharges then
        maxCharges = buttonData.maxCharges
        if kind == "charge_missing" or kind == "charge_zero" or kind == "charge_full" then
            local mc = maxCharges or 2
            if mc < 2 then mc = 2 end
            maxCharges = mc
            if kind == "charge_missing" then
                currentCharges = math_max(1, mc - 1)
                chargeState = "missing"
            elseif kind == "charge_zero" then
                currentCharges = 0
                chargeState = "zero"
            else
                currentCharges = mc
                chargeState = "full"
            end
        else
            -- Idle mirror state: full charges (live learns the count at
            -- runtime; a never-observed maxCharges renders empty there too)
            currentCharges = maxCharges
            chargeState = "full"
        end
    end

    local ctx = slot._textFormatContext
    if not ctx then
        ctx = TextFormat.NewContext()
        slot._textFormatContext = ctx
    end
    ctx.auraOnlyEntry = TextFormat.IsAuraOnlyEntry(buttonData)
    ctx.timeRemaining = timeRemaining
    ctx.usesCharges, ctx.currentCharges, ctx.maxCharges = usesCharges, currentCharges, maxCharges
    ctx.chargeState = chargeState
    ctx.unusable, ctx.outOfRange = kind == "unusable", kind == "out_of_range"
    ctx.available = kind ~= "cooldown" and kind ~= "charge_zero"
    local text = TextFormat.Substitute(segments, style, ctx, PREVIEW_TEXT_ADAPTER, buttonData)
    return text
end

-- Forward declaration: assigned in the block below, next to RenderTextSlot.
-- This file sits at Lua 5.1's file-level local ceiling, so the composite
-- mirror's helpers live in block scope and only the two entry points the
-- rest of the file calls reach file level.
local ApplyTextSlotConditionalPreview

do
    local GetTextRenderPlanMetrics = ST._GetTextRenderPlanMetrics
    local ComputeTextColumnGeometry = ST._ComputeTextColumnGeometry
    local MEASURE_ICON_ESCAPE = ST._TEXT_MEASURE_ICON_ESCAPE
    local ICON_PLACEHOLDER_PATTERN = MEASURE_ICON_ESCAPE
        and (MEASURE_ICON_ESCAPE:gsub("%W", "%%%0")) or nil
    -- Remaining time shown in a duration piece by an aura preview that
    -- carries no countdown of its own (the stack text preview).
    local PIECE_SAMPLE_SECONDS = 8

    -- The mirror's mock aura is ACTIVE under any aura preview kind (the same
    -- union IsBarPreviewAuraActive takes), but only on an entry that tracks
    -- an aura: anything else gets no aura button at runtime, so its pieces
    -- stay blank there too, whatever preview runs.
    local function IsMirrorAuraActive(buttonData, condState)
        if not (buttonData and buttonData.type == "spell"
            and (buttonData.auraTracking or buttonData.addedAs == "aura")) then
            return false
        end
        return IsBarPreviewAuraActive(condState, nil)
    end

    -- A baked piece string escapes `%` as `%%` for the client's formatter
    -- and, measured with no button in hand, carries the placeholder for
    -- {icon}; the mirror shows it as plain text with the entry's own icon.
    local function UnbakePieceText(text, buttonData)
        if not text or text == "" then return "" end
        if ICON_PLACEHOLDER_PATTERN and text:find(MEASURE_ICON_ESCAPE, 1, true) then
            local iconTex = GetLayoutPreviewIcon(buttonData)
            if iconTex then
                local escape = string.format("|T%s:0|t", tostring(iconTex)):gsub("%%", "%%%%")
                text = text:gsub(ICON_PLACEHOLDER_PATTERN, escape)
            end
        end
        return (text:gsub("%%%%", "%%"))
    end

    -- Font, colour and shadow for a stand-in column string: the recipe
    -- StyleTextEntry gives the single string. The live cc runs
    -- (TextMode StyleTextRunString) and the live pieces (AuraDisplay
    -- StyleTextSlotKit: ApplyFontStyle "text" + the shadow rule) read the
    -- same keys to the same result, so one recipe serves both here.
    local function StyleMirrorColumnString(fs, style)
        local font = CooldownCompanion:FetchFont(style.textFont or "Friz Quadrata TT")
        local fontSize = style.textFontSize or 12
        local fontOutline = ST.GetEffectiveFontOutline(style.textFontOutline or "OUTLINE")
        fs:SetFont(font, fontSize, fontOutline)
        local baseColor = style.textFontColor or { 1, 1, 1, 1 }
        fs:SetTextColor(baseColor[1], baseColor[2], baseColor[3], baseColor[4] or 1)
        ST.ApplyFontShadowForOutline(fs, fontOutline, style.textShadow == true)
    end

    local function AcquireMirrorString(slot, listKey, index)
        local list = slot[listKey]
        if not list then
            list = {}
            slot[listKey] = list
        end
        local fs = list[index]
        if not fs then
            fs = slot:CreateFontString(nil, "OVERLAY")
            list[index] = fs
        end
        return fs
    end

    local function HideMirrorStrings(list, fromIndex)
        if not list then return end
        for i = fromIndex, #list do
            list[i]:SetText("")
            list[i]:Hide()
        end
    end

    -- Places one stand-in per rendered column on the plan's geometry
    -- (ComputeTextColumnGeometry: the numbers the live layout writes, read
    -- here through the sink so the live entry's plan is never written to).
    -- slot._cdcTextColumns pairs each column with its FontString in format
    -- order, so the per-tick render never re-walks the geometry.
    local function LayoutMirrorComposite(slot, style, plan, lineHeight, boxWidth)
        local columns = slot._cdcTextColumns
        if not columns then
            columns = {}
            slot._cdcTextColumns = columns
        end
        local count, runCount, pieceCount = 0, 0, 0
        ComputeTextColumnGeometry(plan, style, lineHeight, boxWidth, slot,
            function(column, x, y, width, height, justifyH)
                local kind = column.kind
                local fs
                if kind == "cc" then
                    runCount = runCount + 1
                    fs = AcquireMirrorString(slot, "_cdcRunStrings", runCount)
                elseif kind == "unsupported" then
                    -- No width, no render (TEXT RENDER PLAN).
                    return
                else
                    pieceCount = pieceCount + 1
                    fs = AcquireMirrorString(slot, "_cdcPieceStrings", pieceCount)
                end
                StyleMirrorColumnString(fs, style)
                fs:ClearAllPoints()
                fs:SetPoint("TOPLEFT", slot, "TOPLEFT", x, y)
                fs:SetSize(width, height)
                fs:SetJustifyH(justifyH)
                fs:SetJustifyV("MIDDLE")
                fs:SetWordWrap(false)
                fs:Show()
                count = count + 1
                local entry = columns[count]
                if not entry then
                    entry = {}
                    columns[count] = entry
                end
                entry.column = column
                entry.fs = fs
            end)
        for i = count + 1, #columns do
            columns[i].column = nil
            columns[i].fs = nil
        end
        slot._cdcTextColumnCount = count
        HideMirrorStrings(slot._cdcRunStrings, runCount + 1)
        HideMirrorStrings(slot._cdcPieceStrings, pieceCount + 1)
    end

    -- Composite -> single string (the format was edited, or the slot was
    -- reused for another entry): put the stand-ins away and let
    -- slot.textString render again.
    local function ClearMirrorComposite(slot)
        if not slot._cdcTextPlan then return end
        slot._cdcTextPlan = nil
        slot._cdcTextColumnCount = 0
        HideMirrorStrings(slot._cdcRunStrings, 1)
        HideMirrorStrings(slot._cdcPieceStrings, 1)
    end

    -- Per-tick body for a composite slot. cc columns go through the mirror
    -- substitution (the planner already balanced their tags per column);
    -- pieces show sample values while the mock aura is active and nothing
    -- otherwise. Sample rules follow the live host (AuraDisplay
    -- StyleTextSlotKit) under the bounded text contract (owner ruling
    -- 2026-09-03): duration = prefix .. Duration Format (aura lane, no
    -- low-time colour, no pandemic dressing) .. suffix, and an empty format
    -- renders none of it; stacks = prefix .. count .. suffix in the column's
    -- own colour (no stack policies on text); presence = the region's text.
    local function RenderMirrorComposite(slot, buttonData, style, condState, now)
        local columns = slot._cdcTextColumns
        local auraActive = IsMirrorAuraActive(buttonData, condState)
        local remaining
        if auraActive then
            remaining = PIECE_SAMPLE_SECONDS
            if GetConditionalPreviewTiming then
                local startTime, _, timed = GetConditionalPreviewTiming(condState, now)
                if startTime and timed then
                    remaining = timed
                end
            end
        end
        for i = 1, slot._cdcTextColumnCount or 0 do
            local entry = columns[i]
            local column, fs = entry.column, entry.fs
            local kind = column.kind
            if kind == "cc" then
                fs:SetText(FormatPreviewTokens(slot, column.segments, style, buttonData, condState, now))
            elseif not auraActive then
                fs:SetText("")
            elseif kind == "duration" then
                local sample = CooldownCompanion:FormatAuraDurationPreviewText(remaining, style, false, false)
                if sample == "" then
                    fs:SetText("")
                else
                    fs:SetText(UnbakePieceText(column.prefix, buttonData)
                        .. sample .. UnbakePieceText(column.suffix, buttonData))
                end
            elseif kind == "stacks" then
                fs:SetText(UnbakePieceText(column.prefix, buttonData)
                    .. tostring(condState.stackText or "3")
                    .. UnbakePieceText(column.suffix, buttonData))
            else
                fs:SetText(UnbakePieceText(column.text, buttonData))
            end
        end
    end

    function RenderTextSlot(slot, buttonData, style, condState, now)
        if slot._cdcTextPlan then
            RenderMirrorComposite(slot, buttonData, style, condState, now)
            return
        end
        local ts = slot.textString
        if not (ParseFormatString and slot._cdcTextSegments) then
            -- Parser unavailable: fall back to the plain entry name
            ts:SetText(buttonData.customName or buttonData.name
                or GetConfigEntryDisplayName(buttonData) or "")
            return
        end
        ts:SetText(FormatPreviewTokens(slot, slot._cdcTextSegments, style, buttonData, condState, now))
    end

    function ApplyTextSlotConditionalPreview(slot, buttonData, group, panelId, index, forceBase)
        slot._cdcCondAnim = nil
        slot.buttonData = buttonData

        local style = slot.style or group.style or {}
        local fmt = buttonData.textFormat or style.textFormat or DEFAULT_TEXT_FORMAT
        slot._cdcTextSegments = ParseFormatString and ParseFormatString(fmt) or nil

        -- Live ApplyTextLayout: a composite plan lays its columns out and
        -- silences the single string; otherwise multiline formats wrap from
        -- the top. buttonData is the metrics cache key, so this shares the
        -- entry's cache slot with the pitch pass rather than churning the
        -- style table's slot. The box width is the measured one, the same
        -- number the slot was sized from (GetTextSlotSize).
        if GetTextRenderPlanMetrics then
            local width, _, lineCount, plan, lineHeight = GetTextRenderPlanMetrics(style, buttonData, fmt)
            if plan and lineHeight and ComputeTextColumnGeometry then
                LayoutMirrorComposite(slot, style, plan, lineHeight, width)
                slot._cdcTextPlan = plan
                slot.textString:SetText("")
            else
                ClearMirrorComposite(slot)
                local isMultiline = (lineCount or 1) > 1
                slot.textString:SetJustifyV(isMultiline and "TOP" or "MIDDLE")
                slot.textString:SetWordWrap(isMultiline)
            end
        end

        local state = not forceBase and GetStoredConditionalPreviewState
            and GetStoredConditionalPreviewState(panelId, index) or nil
        local now = GetTime()
        RenderTextSlot(slot, buttonData, style, state, now)
        if state and (state.kind == "cooldown"
            or (slot._cdcTextPlan and IsMirrorAuraActive(buttonData, state)
                and GetConditionalPreviewTiming and GetConditionalPreviewTiming(state, now) ~= nil)) then
            -- The countdown (cooldown text, or a duration piece under a
            -- timed aura preview) needs re-rendering as it ticks
            slot._cdcCondAnim = state
        end
    end
end

-- Mirror of GroupFrame's ApplyTextGroupHeader, drawn on the content frame.
local function UpdateTextGroupHeader(preview, group, style, headerHeight)
    local header = preview.textHeader
    if headerHeight <= 0 then
        if header then header:Hide() end
        return
    end
    if not header then
        header = preview.content:CreateFontString(nil, "OVERLAY")
        header:SetJustifyV("TOP")
        preview.textHeader = header
    end
    local font = CooldownCompanion:FetchFont(style.textFont or "Friz Quadrata TT")
    local fontSize = style.textHeaderFontSize or style.textFontSize or 12
    local fontOutline = ST.GetEffectiveFontOutline(style.textFontOutline or "OUTLINE")
    header:SetFont(font, fontSize, fontOutline)
    local hdrColor = style.textHeaderFontColor or { 1, 1, 1, 1 }
    header:SetTextColor(hdrColor[1], hdrColor[2], hdrColor[3], hdrColor[4] or 1)
    ST.ApplyFontShadowForOutline(header, fontOutline, style.textShadow == true)
    local align = style.textAlignment or "LEFT"
    header:SetJustifyH(align)
    header:SetText(group.name or "")
    header:ClearAllPoints()
    local growthOrigin = style.growthOrigin or "TOPLEFT"
    -- Raw "BOTTOM" counts only while it is the ACTIVE centered edge, matching
    -- the live header path: an axis-mismatched value folds to TOPLEFT.
    local vEdge = (growthOrigin == "BOTTOMLEFT" or growthOrigin == "BOTTOMRIGHT"
        or ST.GetCenteredGrowthEdge(growthOrigin, ST.GetPanelLayoutOrientation(group.displayMode, style)) == "BOTTOM")
        and "BOTTOM" or "TOP"
    local anchor = align == "RIGHT" and (vEdge .. "RIGHT") or align == "CENTER" and vEdge or (vEdge .. "LEFT")
    local xOff = (align == "CENTER") and 0 or (align == "RIGHT") and -2 or 2
    local yOff = vEdge == "BOTTOM" and 1 or -1
    header:SetPoint(anchor, preview.content, anchor, xOff, yOff)
    header:SetWidth(math_max(1, (preview.content:GetWidth() or 0) - 4))
    header:Show()
end

-- Private helpers consumed by later ButtonPanelPreview files.
PP.RenderTextSlot = RenderTextSlot
PP.StyleTextEntry = StyleTextEntry
PP.ApplyTextSlotConditionalPreview = ApplyTextSlotConditionalPreview
PP.UpdateTextGroupHeader = UpdateTextGroupHeader
