--[[
    CooldownCompanion - ButtonFrame/TextMode
    Text-mode button creation, format string parser, styling, and display updates
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon
local CooldownLogic = ST.CooldownLogic
-- F2 canary sink (loaded before this file; dev-gated, observe-only).
local RefreshTelemetry = ST.RefreshTelemetry
local CHARGE_STATE_FULL = CooldownLogic.CHARGE_STATE_FULL
local CHARGE_STATE_MISSING = CooldownLogic.CHARGE_STATE_MISSING
local CHARGE_STATE_ZERO = CooldownLogic.CHARGE_STATE_ZERO

-- Localize frequently-used globals
local GetTime = GetTime
local pairs = pairs
local ipairs = ipairs
local unpack = unpack
local math_floor = math.floor
local math_ceil = math.ceil
local math_max = math.max
local math_abs = math.abs
local math_sin = math.sin
local math_pi = math.pi
local string_format = string.format
local table_concat = table.concat
local issecretvalue = issecretvalue
local wipe = wipe
local UsesChargeBehavior = CooldownCompanion.UsesChargeBehavior

-- Imports from Helpers
local ApplyBorderEdgePositions = ST._ApplyBorderEdgePositions

-- Imports from VisualState
local ClearButtonVisualState = ST._ClearButtonVisualState
local AreButtonVisualStateSnapshotsEnabled = ST._AreButtonVisualStateSnapshotsEnabled

-- Imports from Glows

-- Shared click-through helpers from Utils.lua
local SetFrameClickThroughRecursive = ST.SetFrameClickThroughRecursive

-- Shared helpers from ButtonFrame/Helpers.lua
local IsEntryItemLike = CooldownCompanion.IsEntryItemLike
local ResolveEffectiveItem = CooldownCompanion.ResolveEffectiveItem
local FormatTime = CooldownCompanion.FormatTime
local GetDurationSecretFormatSpec = CooldownCompanion.GetDurationSecretFormatSpec

-- Pre-defined color constant tables to avoid per-tick allocation.
-- These are used as fallbacks when style keys are nil (user hasn't customized).
-- IMPORTANT: These tables are read-only — never write to their indices.
local DEFAULT_WHITE = {1, 1, 1, 1}
local DEFAULT_CD_COLOR = {1, 0.3, 0.3, 1}
local DEFAULT_READY_COLOR = {0.2, 1.0, 0.2, 1}
local DEFAULT_AURA_COLOR = {0, 0.925, 1, 1}
local DEFAULT_CUSTOM_COLOR = {1, 0.82, 0, 1}
local DEFAULT_TEXT_FORMAT = "{name}  {status}"

local function IsAuraOnlyEntry(buttonData)
    return buttonData
        and buttonData.type == "spell"
        and buttonData.addedAs == "aura"
        and buttonData.auraTracking == true
end

------------------------------------------------------------------------
-- FORMAT STRING PARSER
-- Parses "{name}  {status}" into a list of segments:
--   { {type="literal", value="  "}, {type="token", value="name"}, ... }
-- Parsed once at creation/style-change; per-tick substitution walks the list.
------------------------------------------------------------------------
-- No pandemic token: it needed readable pandemic state, which 12.1 made
-- permanently secret (retired Phase 3; migrations scrub saved formats).
--
-- Aura tokens are CLIENT-RENDERED on 12.1. The addon can never read the
-- tracked aura's remaining time or application count, so {aura} (remaining
-- time) and {aurastacks} (application count) never reach SubstituteTokens:
-- BuildTextRenderPlan below cuts them out of the line as aura PIECES with
-- reserved widths, and Core/AuraDisplay's text host hands the client a
-- FontString per piece. {status} on a standalone aura entry is {aura}.
local KNOWN_TOKENS = {
    name = true,
    time = true,
    charges = true,
    maxcharges = true,
    missingcharges = true,
    zerocharges = true,
    stacks = true,
    aura = true,
    aurastacks = true,
    proc = true,
    unusable = true,
    oor = true,
    available = true,
    incombat = true,
    keybind = true,
    status = true,
    icon = true,
    br = true,
}

-- `aura` conditionals are resolved by the PLANNER, not at runtime: a
-- {?aura}...{/aura} region becomes client-rendered aura content that the
-- client shows only while the aura is active, and a {!aura}...{/aura} region
-- is dropped whole (the client cannot render "while inactive"). Neither ever
-- reaches EvaluateTokenPresence, which answers false for `aura` as a defined
-- fallback only.
local KNOWN_CONDITIONAL_TOKENS = {
    time = true,
    charges = true,
    maxcharges = true,
    missingcharges = true,
    zerocharges = true,
    stacks = true,
    aura = true,
    keybind = true,
    proc = true,
    unusable = true,
    oor = true,
    available = true,
    incombat = true,
}

local KNOWN_EFFECTS = {
    pulse = true,
}

local KNOWN_COLORS = {
    cooldown = true,
    ready = true,
    active = true,
    custom = true,
}

local function ParseFormatString(fmt)
    local segments = {}
    local pos = 1
    local len = #fmt
    while pos <= len do
        local openBrace = fmt:find("{", pos, true)
        if not openBrace then
            -- Rest is literal
            segments[#segments + 1] = { type = "literal", value = fmt:sub(pos) }
            break
        end
        -- Literal before the brace
        if openBrace > pos then
            segments[#segments + 1] = { type = "literal", value = fmt:sub(pos, openBrace - 1) }
        end
        local closeBrace = fmt:find("}", openBrace + 1, true)
        if not closeBrace then
            -- Unterminated brace — treat rest as literal
            segments[#segments + 1] = { type = "literal", value = fmt:sub(openBrace) }
            break
        end
        local inner = fmt:sub(openBrace + 1, closeBrace - 1):lower()

        -- Conditional start: {?token} or {!token}
        local condPrefix = inner:sub(1, 1)
        if condPrefix == "?" or condPrefix == "!" then
            local condToken = inner:sub(2)
            if KNOWN_CONDITIONAL_TOKENS[condToken] then
                segments[#segments + 1] = {
                    type = "cond_start",
                    value = condToken,
                    negated = (condPrefix == "!"),
                }
            else
                -- Unknown conditional token — treat as literal
                segments[#segments + 1] = { type = "literal", value = fmt:sub(openBrace, closeBrace) }
            end
        -- Conditional / effect end: {/token} or {/effect}
        elseif condPrefix == "/" then
            local condToken = inner:sub(2)
            if KNOWN_CONDITIONAL_TOKENS[condToken] then
                segments[#segments + 1] = { type = "cond_end", value = condToken }
            elseif KNOWN_EFFECTS[condToken] then
                segments[#segments + 1] = { type = "effect_end", value = condToken }
            elseif KNOWN_COLORS[condToken] then
                segments[#segments + 1] = { type = "color_end", value = condToken }
            else
                segments[#segments + 1] = { type = "literal", value = fmt:sub(openBrace, closeBrace) }
            end
        elseif KNOWN_TOKENS[inner] then
            segments[#segments + 1] = { type = "token", value = inner }
        elseif KNOWN_EFFECTS[inner] then
            segments[#segments + 1] = { type = "effect_start", value = inner }
        elseif KNOWN_COLORS[inner] then
            segments[#segments + 1] = { type = "color_start", value = inner }
        else
            -- Unknown token — render as empty
            segments[#segments + 1] = { type = "token", value = inner, unknown = true }
        end
        pos = closeBrace + 1
    end
    return segments
end

------------------------------------------------------------------------
-- EFFECT HELPERS
------------------------------------------------------------------------
local function HasAnyEffects(segments)
    for _, seg in ipairs(segments) do
        if seg.type == "effect_start" then return true end
    end
    return false
end

------------------------------------------------------------------------
-- TEXT RENDER PLAN
--
-- On 12.1 an aura's remaining time and application count belong to the
-- client, never to the addon: only a Blizzard aura button can render them,
-- into addon-owned FontStrings it is handed (SetDurationText /
-- SetApplicationCount) whose text is then secret. An aura value can
-- therefore never be spliced into the entry's single string. Instead a
-- format line is cut into COLUMNS that sit side by side, each with a fixed
-- width reserved from the same worst-case mock the box is sized from:
--
--   * "cc" columns hold ordinary segments and are rendered by the addon
--     through SubstituteTokens, one pooled FontString per column;
--   * aura PIECES are rendered by the client. Core/AuraDisplay's text host
--     anchors a client-driven FontString on each piece's geometry and
--     installs a formatter carrying the piece's baked prefix and suffix.
--
-- What becomes aura content:
--   * a {?aura}...{/aura} region (a {br} inside it ends the region on that
--     line and reopens it on the next);
--   * a bare {aura} or {aurastacks} outside a region (an implicit region
--     holding only that token);
--   * {status} on a standalone aura entry (buttonData.addedAs == "aura"),
--     which means the aura's remaining time and is treated exactly as {aura}.
-- A {!aura}...{/aura} region contributes nothing: the client cannot render
-- "while the aura is inactive", so the region is dropped whole and is not
-- measured.
--
-- Inside aura content: {aura} -> a "duration" piece, {aurastacks} -> a
-- "stacks" piece. Literal text, colour tags and the static tokens {name},
-- {keybind} and {icon} attach to the nearest PRECEDING value piece as its
-- suffix, or, when nothing precedes them, to the NEXT value piece as its
-- prefix. A region with no value token yields one "presence" piece whose
-- text shows while the aura is active. Every other CC token inside aura
-- content ({time}, {charges}, {stacks}, {status} on a spell entry, ...)
-- emits nothing and sets plan.hasUnsupportedInAura; CC conditionals and
-- effects inside aura content are ignored (their contents render as if
-- present).
--
-- Per-entry limits: one client aura button carries one duration FontString
-- and one count FontString, so across the whole format only the first
-- "duration" piece and the first "stacks"-or-"presence" piece are live.
-- Later ones become kind "unsupported" (no width, no render, their attached
-- chunks dropped) and set plan.hasDuplicateAuraPiece.
--
-- Plan shape. BuildTextRenderPlan is pure structure; BakeTextRenderPlan
-- fills the strings; measurement adds `width`; layout adds `x`, `y`,
-- `height`, `justifyH` (and `runIndex` on cc columns):
--   plan.composite         true when the plan must drive rendering: at least
--                          one live piece exists, or a {!aura} region was
--                          dropped. When false the plan is unused and every
--                          existing single-FontString path runs unchanged.
--   plan.hasAuraPieces     true when at least one live piece exists.
--   plan.hasUnsupportedInAura, plan.hasDuplicateAuraPiece,
--   plan.hasNegatedAuraRegion            editor advisories.
--   plan.lines[i].columns[j]  in format order, one of
--     { kind = "cc", segments = {...} }
--     { kind = "duration"|"stacks"|"presence"|"unsupported",
--       prefix = "", suffix = "", text = "",   -- baked; `%` escaped as `%%`
--       prefixSegments = {...}, suffixSegments = {...}, textSegments = {...},
--       region = n }                           -- colour state carries per region
--   plan.runColumns        flat list of the "cc" columns in format order
--   plan.auraPieces        flat list of the live pieces in format order
--
-- cc columns are self-balanced: a conditional, colour or effect tag still
-- open when a column is cut is closed at its end and reopened at the start
-- of the next cc column, so SubstituteTokens' per-call state never leaks
-- across FontStrings. Colour tags open in cc content when an aura region
-- starts are inherited by the region. Original segment tables are reused
-- (never mutated); only closing tags are synthesized. A cc column that
-- would render nothing (tags only) is not emitted.
--
-- Nothing here runs per tick: plans are built where the box is measured
-- (create / restyle / invalidation) and cached beside the metrics.
------------------------------------------------------------------------
local AURA_VALUE_TOKEN_KIND = { aura = "duration", aurastacks = "stacks" }
local AURA_STATIC_TOKENS = { name = true, keybind = true, icon = true }
local CC_TAG_END_TYPE = {
    cond_start = "cond_end",
    color_start = "color_end",
    effect_start = "effect_end",
}

local function IsStandaloneAuraEntry(buttonData)
    return buttonData ~= nil and buttonData.addedAs == "aura"
end

local function IsAuraValueSegment(seg, statusIsAura)
    if seg.type ~= "token" or seg.unknown then return nil end
    local token = seg.value
    if token == "status" and statusIsAura then token = "aura" end
    return AURA_VALUE_TOKEN_KIND[token]
end

-- True when the list holds something the renderer would draw (a literal or
-- a known token); tag-only lists draw nothing.
local function SegmentsRender(segments)
    for _, seg in ipairs(segments) do
        local segType = seg.type
        if segType == "literal" then
            if seg.value ~= "" then return true end
        elseif segType == "token" and not seg.unknown then
            return true
        end
    end
    return false
end

local function NewAuraPiece(kind, region)
    return {
        kind = kind,
        region = region,
        prefix = "",
        suffix = "",
        text = "",
        prefixSegments = {},
        suffixSegments = {},
        textSegments = {},
    }
end

local function BuildTextRenderPlan(segments, buttonData, style)
    local plan = {
        composite = false,
        hasAuraPieces = false,
        hasUnsupportedInAura = false,
        hasDuplicateAuraPiece = false,
        hasNegatedAuraRegion = false,
        -- A CC conditional or effect wrapped around (or opened inside) aura
        -- content cannot gate client-rendered text: the piece shows whenever
        -- the aura is active. Editor advisory.
        hasWrappedAuraPiece = false,
        -- An {icon} baked into a piece: the cache must then treat the entry's
        -- icon texture as an identity input (GetTextEntryMetrics).
        hasIconInAura = false,
        lines = {},
        runColumns = {},
        auraPieces = {},
    }
    local statusIsAura = IsStandaloneAuraEntry(buttonData)

    local line = { columns = {} }
    plan.lines[1] = line

    -- cc state
    local ccSegments = nil   -- the open cc column's list, nil between columns
    local openTags = {}      -- cond/colour/effect starts open in cc content

    -- aura state
    local inAura = false
    local auraDepth = 0      -- nested {?aura}/{!aura} tags inside a region
    local dropDepth = 0      -- > 0 while inside a dropped {!aura} region
    local pending = nil      -- chunks waiting for a value piece (its prefix)
    local lastPiece = nil    -- the region's latest value piece (takes suffix)
    local auraColors = nil   -- colour starts open inside the current region
    local regionCount = 0
    local haveDuration, haveCount = false, false

    local function OpenCcColumn()
        ccSegments = {}
        for i = 1, #openTags do
            ccSegments[i] = openTags[i]
        end
    end

    local function CloseCcColumn()
        if not ccSegments then return end
        if SegmentsRender(ccSegments) then
            for i = #openTags, 1, -1 do
                local tag = openTags[i]
                ccSegments[#ccSegments + 1] = { type = CC_TAG_END_TYPE[tag.type], value = tag.value }
            end
            local column = { kind = "cc", segments = ccSegments }
            line.columns[#line.columns + 1] = column
            plan.runColumns[#plan.runColumns + 1] = column
        end
        ccSegments = nil
    end

    local function AppendCc(seg)
        if not ccSegments then OpenCcColumn() end
        ccSegments[#ccSegments + 1] = seg
        local segType = seg.type
        if CC_TAG_END_TYPE[segType] then
            openTags[#openTags + 1] = seg
        elseif segType == "cond_end" or segType == "color_end" or segType == "effect_end" then
            -- Same tolerance as SubstituteTokens: an end pops the nearest
            -- open tag of its kind, whatever its name, and a stray end pops
            -- nothing.
            for i = #openTags, 1, -1 do
                if CC_TAG_END_TYPE[openTags[i].type] == segType then
                    table.remove(openTags, i)
                    break
                end
            end
        end
    end

    local function NewLine()
        CloseCcColumn()
        line = { columns = {} }
        plan.lines[#plan.lines + 1] = line
    end

    local function AddPiece(piece, live)
        line.columns[#line.columns + 1] = piece
        if live then
            plan.auraPieces[#plan.auraPieces + 1] = piece
            plan.hasAuraPieces = true
        else
            plan.hasDuplicateAuraPiece = true
        end
    end

    -- `seeds` are colour_start segments the region inherits (cc colours open
    -- when it starts, or the previous line's aura colours after a {br}).
    local function BeginAuraRegion(seeds)
        CloseCcColumn()
        for i = 1, #openTags do
            if openTags[i].type ~= "color_start" then
                plan.hasWrappedAuraPiece = true
                break
            end
        end
        regionCount = regionCount + 1
        inAura = true
        auraDepth = 0
        pending = {}
        lastPiece = nil
        auraColors = {}
        if seeds then
            for i = 1, #seeds do
                pending[i] = seeds[i]
                auraColors[i] = seeds[i]
            end
        end
    end

    local function EndAuraRegion()
        if not lastPiece and SegmentsRender(pending) then
            local live = not haveCount
            haveCount = true
            local piece = NewAuraPiece(live and "presence" or "unsupported", regionCount)
            piece.textSegments = pending
            AddPiece(piece, live)
        end
        inAura = false
        pending = nil
        lastPiece = nil
    end

    local function AuraChunk(seg)
        if lastPiece then
            lastPiece.suffixSegments[#lastPiece.suffixSegments + 1] = seg
        else
            pending[#pending + 1] = seg
        end
    end

    local function AddValuePiece(kind)
        local live
        if kind == "duration" then
            live = not haveDuration
            haveDuration = true
        else
            live = not haveCount
            haveCount = true
        end
        local piece = NewAuraPiece(live and kind or "unsupported", regionCount)
        piece.prefixSegments = pending
        pending = {}
        lastPiece = piece
        AddPiece(piece, live)
    end

    local function AuraToken(seg)
        if seg.unknown then return end
        local kind = IsAuraValueSegment(seg, statusIsAura)
        if kind then
            AddValuePiece(kind)
        elseif AURA_STATIC_TOKENS[seg.value] then
            if seg.value == "icon" then
                plan.hasIconInAura = true
            end
            AuraChunk(seg)
        else
            plan.hasUnsupportedInAura = true
        end
    end

    local function CcColorSeeds()
        local seeds = nil
        for i = 1, #openTags do
            if openTags[i].type == "color_start" then
                seeds = seeds or {}
                seeds[#seeds + 1] = openTags[i]
            end
        end
        return seeds
    end

    for _, seg in ipairs(segments) do
        local segType = seg.type
        local isAuraTag = seg.value == "aura" and (segType == "cond_start" or segType == "cond_end")
        if dropDepth > 0 then
            if isAuraTag then
                dropDepth = dropDepth + ((segType == "cond_start") and 1 or -1)
            end
        elseif inAura then
            if isAuraTag then
                if segType == "cond_start" then
                    auraDepth = auraDepth + 1
                elseif auraDepth > 0 then
                    auraDepth = auraDepth - 1
                else
                    EndAuraRegion()
                end
            elseif segType == "token" and seg.value == "br" and not seg.unknown then
                local carried = auraColors
                EndAuraRegion()
                NewLine()
                BeginAuraRegion(carried)
            elseif segType == "token" then
                AuraToken(seg)
            elseif segType == "literal" then
                AuraChunk(seg)
            elseif segType == "color_start" then
                AuraChunk(seg)
                auraColors[#auraColors + 1] = seg
            elseif segType == "color_end" then
                AuraChunk(seg)
                auraColors[#auraColors] = nil
            elseif segType == "cond_start" or segType == "effect_start" then
                -- CC conditionals and effects cannot gate client-rendered
                -- text: their contents render as if present. Flagged so the
                -- editor can say so; the end tags are simply ignored.
                plan.hasWrappedAuraPiece = true
            end
        else
            if isAuraTag then
                if segType == "cond_end" then
                    -- Stray {/aura}: nothing to close.
                elseif seg.negated then
                    plan.hasNegatedAuraRegion = true
                    dropDepth = 1
                else
                    BeginAuraRegion(CcColorSeeds())
                end
            elseif IsAuraValueSegment(seg, statusIsAura) then
                BeginAuraRegion(CcColorSeeds())
                AuraToken(seg)
                EndAuraRegion()
            elseif segType == "token" and seg.value == "br" and not seg.unknown then
                NewLine()
            else
                AppendCc(seg)
            end
        end
    end
    if dropDepth == 0 and inAura then
        -- Unclosed {?aura}: the region runs to the end of the format, as an
        -- unclosed conditional does in SubstituteTokens.
        EndAuraRegion()
    end
    CloseCcColumn()

    plan.composite = plan.hasAuraPieces or plan.hasNegatedAuraRegion
    return plan
end

-- Forward declaration: the memoized colour-escape helper is defined with the
-- rest of the colour wrapping below, after the measurement section that
-- bakes plans through it.
local ColorPrefix

local bakeParts = {}
local bakeColorStack = {}

-- `%` must survive the client's formatter, which treats the baked prefix and
-- suffix as a format string.
local function BakeEscape(text)
    if text == nil or text == "" then return end
    bakeParts[#bakeParts + 1] = (text:gsub("%%", "%%%%"))
end

-- Walks one chunk list into bakeParts, carrying the region's colour state in
-- bakeColorStack. Returns the colour table active afterwards. Colour tags
-- resolve to raw |cffRRGGBB / |r escapes here rather than per-chunk wraps so
-- an override opened before a value token still colours the client-rendered
-- value between prefix and suffix.
local function BakeChunks(chunks, colorOverride, ctx, iconEscape, cdColor, readyColor, auraColor, customColor)
    for _, seg in ipairs(chunks) do
        local segType = seg.type
        if segType == "literal" then
            BakeEscape(seg.value)
        elseif segType == "token" then
            local token = seg.value
            if token == "name" then
                BakeEscape(ctx.name)
            elseif token == "keybind" then
                BakeEscape(ctx.keybind)
            elseif token == "icon" then
                BakeEscape(iconEscape)
            end
        elseif segType == "color_start" then
            bakeColorStack[#bakeColorStack + 1] = colorOverride
            local name = seg.value
            if name == "cooldown" then colorOverride = cdColor
            elseif name == "ready" then colorOverride = readyColor
            elseif name == "active" then colorOverride = auraColor
            elseif name == "custom" then colorOverride = customColor
            end
            if colorOverride then
                bakeParts[#bakeParts + 1] = ColorPrefix(colorOverride)
            end
        elseif segType == "color_end" then
            colorOverride = bakeColorStack[#bakeColorStack]
            bakeColorStack[#bakeColorStack] = nil
            bakeParts[#bakeParts + 1] = "|r"
            if colorOverride then
                bakeParts[#bakeParts + 1] = ColorPrefix(colorOverride)
            end
        end
    end
    return colorOverride
end

-- Fills every piece's prefix/suffix/text from its chunk lists. `ctx` is the
-- mock context (its name and keybind are the same strings SubstituteTokens
-- would resolve, so the cache's identity comparisons already cover them);
-- `iconEscape` is the entry's inline icon escape. Each piece's strings are
-- self-contained: a colour active at a piece boundary is reopened at the
-- start of the next piece and closed at the end of the current one. A value
-- with no override wears the same role colour SubstituteTokens gives it
-- (the aura colour for a duration, the base colour for stacks).
local function BakeTextRenderPlan(plan, style, ctx, iconEscape)
    local cdColor = style.textCooldownColor or DEFAULT_CD_COLOR
    local readyColor = style.textReadyColor or DEFAULT_READY_COLOR
    local auraColor = style.textAuraColor or DEFAULT_AURA_COLOR
    local customColor = style.textCustomColor or DEFAULT_CUSTOM_COLOR

    local region = nil
    local colorOverride = nil
    for _, planLine in ipairs(plan.lines) do
        for _, column in ipairs(planLine.columns) do
            local kind = column.kind
            if kind ~= "cc" and kind ~= "unsupported" then
                if column.region ~= region then
                    region = column.region
                    colorOverride = nil
                    wipe(bakeColorStack)
                end
                if kind == "presence" then
                    wipe(bakeParts)
                    if colorOverride then bakeParts[1] = ColorPrefix(colorOverride) end
                    colorOverride = BakeChunks(column.textSegments, colorOverride, ctx, iconEscape,
                        cdColor, readyColor, auraColor, customColor)
                    if colorOverride then bakeParts[#bakeParts + 1] = "|r" end
                    column.text = table_concat(bakeParts)
                else
                    wipe(bakeParts)
                    if colorOverride then bakeParts[1] = ColorPrefix(colorOverride) end
                    colorOverride = BakeChunks(column.prefixSegments, colorOverride, ctx, iconEscape,
                        cdColor, readyColor, auraColor, customColor)
                    local valueColor = (not colorOverride) and (kind == "duration") and auraColor or nil
                    if valueColor then bakeParts[#bakeParts + 1] = ColorPrefix(valueColor) end
                    column.prefix = table_concat(bakeParts)

                    wipe(bakeParts)
                    if valueColor then bakeParts[1] = "|r" end
                    colorOverride = BakeChunks(column.suffixSegments, colorOverride, ctx, iconEscape,
                        cdColor, readyColor, auraColor, customColor)
                    if colorOverride then bakeParts[#bakeParts + 1] = "|r" end
                    column.suffix = table_concat(bakeParts)
                end
            end
        end
    end
    wipe(bakeParts)
    wipe(bakeColorStack)
end

------------------------------------------------------------------------
-- TEXT ENTRY AUTO-SIZING
--
-- A text entry is sized from what it can actually render, not from manual
-- width/height sliders. Height is the format's line count times the
-- measured single-line height of its font; width is a worst-case MOCK
-- render of the entry's format measured on a dedicated hidden FontString.
-- style.textPadding is the only manual size knob.
--
-- The LIVE FontString is never measured. Text-mode content can hold secret
-- values (secret cooldown/aura durations, secret stacks, secret aura
-- names), and getters on a secret-holding FontString can return secrets,
-- which may not feed Lua arithmetic (agent-reference/secret-values.md,
-- agent-reference/hotfix-overrides-12.1.md). The mock renderer below only
-- ever feeds plain, addon-authored strings into the measuring FontString.
--
-- Measurement runs on create/restyle paths plus two bounded invalidation
-- paths, and nothing here is reachable from a per-tick display path.
--
--   * IDENTITY: the cache stores the resolved name and keybind strings the
--     measurement consumed, and a read whose re-resolve disagrees is a miss.
--     That is what notices an override spell, a resolved item or a rebound key
--     changing the box, none of which touch a style key. Re-resolving is
--     capped at one probe per cache entry per rendered frame.
--   * PROVISIONAL: an entry whose {name} had not resolved when it was first
--     measured is cached as PROVISIONAL and re-measured on the next layout
--     pass, capped at one measurement per pass, so a box sized against a
--     missing login-time spell name heals instead of staying wrong.
--
-- A changed measurement only moves the live frame through
-- RefreshTextEntryLayout, which event handlers call; layout passes themselves
-- are dirty-flag gated. Every other cache hit costs a few comparisons plus the
-- once-per-frame probe and never re-renders the mock.
------------------------------------------------------------------------
local TEXT_PADDING_DEFAULT = 4

-- "|Ttexture:0|t" sizes the inline texture to the font's line height, so
-- the measured width does not depend on which texture is used. Measuring
-- with a fixed placeholder means the mock never depends on the button's
-- icon having resolved yet, and the data-only path (no live frame, used by
-- GroupFrame layout math) produces the same number as the per-button path.
local MEASURE_ICON_ESCAPE = "|TInterface\\Icons\\INV_Misc_QuestionMark:0|t"

-- Worst-case substitution values. WORST_CASE_SECONDS drives both candidate
-- time renders: the readable clock string from FormatTime, and the secret
-- pass-through render (a bare seconds number via the duration secret format
-- spec). Those are materially different widths, so both are measured.
--
-- 5999 is a DELIBERATE trade, not an upper bound: it reserves for the widest
-- render under 100 minutes ("99:59"). A cooldown of an hour or more renders
-- wider than that (an "1:39:59"-class clock, or a 5+ digit secret seconds
-- pass-through) and will clip inside its reserved box. Reserving for the real
-- ceiling would widen every text entry in the game for a case almost no
-- tracked cooldown reaches, so the clip is accepted.
local WORST_CASE_SECONDS = 5999
-- Stacks are reserved three digits wide: aura stack counts routinely pass 99.
local WORST_CASE_STACKS = "888"
local WORST_CASE_CHARGES = "8"
local STATUS_ACTIVE_TEXT = "Active"
local STATUS_DEFERRED_TEXT = "..."

local measureHostFrame
local measureFontString
local function GetMeasureFontString()
    if not measureFontString then
        measureHostFrame = CreateFrame("Frame", nil, UIParent)
        measureHostFrame:Hide()
        measureFontString = measureHostFrame:CreateFontString(nil, "ARTWORK")
        -- Unbounded measurement: no wrap, no line cap, no width constraint
        -- (same recipe as Core/AuraTexturesDisplay GetTriggerTextDisplayMetrics).
        measureFontString:SetWordWrap(false)
        measureFontString:SetMaxLines(0)
        measureFontString:SetWidth(0)
    end
    return measureFontString
end

local function MeasureStringWidth(fs, text)
    fs:SetText(text or "")
    local width = fs.GetUnboundedStringWidth and fs:GetUnboundedStringWidth() or fs:GetStringWidth()
    return width or 0
end

local function PickWidestString(fs, current, candidate)
    if not candidate or candidate == "" then return current end
    if not current or current == "" then return candidate end
    if MeasureStringWidth(fs, candidate) > MeasureStringWidth(fs, current) then
        return candidate
    end
    return current
end

-- Same resolution chain SubstituteTokens uses for {name}, minus the secret
-- aura-name override (a secret string that cannot be measured at all).
--
-- Second return is `pending`: true when the name came back empty AND there was
-- something to look up. Early in a session the client has not cached spell/item
-- names yet, so C_Spell.GetSpellName / C_Item.GetItemNameByID answer nil for an
-- id that will resolve moments later; measuring then freezes a too-small box.
-- What the inputs let us distinguish:
--   * no buttonData (the group-level baseline)      -> final, never pending
--   * a customName (even "")                        -> final, user-authored
--   * a stored buttonData.name fallback             -> final, we have a name
--   * spell/item type WITH an id, lookup empty      -> PENDING (retry later)
--   * spell/item type WITHOUT an id, or any other
--     entry type, and no stored name                -> final, genuinely nameless
-- The last two are the load-bearing split: a nameless entry must not retry
-- forever, and an unresolved id must not be cached as final.
local function ResolveMockEntryName(buttonData, identity)
    if not buttonData then return "", false end
    local name = buttonData.customName or buttonData.name or ""
    if buttonData.customName then
        return name, false
    end
    local hasLookupSource = false
    if buttonData.type == "spell" then
        local spellId = identity.spellId or buttonData.id
        hasLookupSource = spellId ~= nil
        local spellName = spellId and C_Spell.GetSpellName(spellId)
        if spellName and spellName ~= "" then return spellName, false end
    elseif IsEntryItemLike(buttonData) then
        local itemID = identity.itemId or buttonData.id
        hasLookupSource = itemID ~= nil
        local itemName = itemID and C_Item.GetItemNameByID(itemID)
        if itemName and itemName ~= "" then return itemName, false end
    end
    return name, (name == "" and hasLookupSource)
end

-- Which ids the mock render resolves {name} and the keybind through.
--
-- A live button can be displaying an OVERRIDE spell (IconMode's
-- UpdateButtonIcon writes button._displaySpellId) or a RESOLVED item
-- (CooldownUpdate's UpdateResolvedItemState writes button._resolvedItemId),
-- and both are assigned after the frame exists. Neither id is visible to a
-- data-only reader -- GroupFrame's grid pitch, the config mirror and the
-- config's Entry Size row all measure with buttonData and no button.
--
-- So the ids the last button-bearing measurement used are stored on the cache
-- entry and reused when there is no button. Without that the pitch measures
-- the BASE spell's name while the entry frame is sized from the override's,
-- and a longer override overflows its own slot.
local measureIdentity = { spellId = nil, itemId = nil }
local function ResolveMeasureIdentity(buttonData, button, cached)
    if button then
        measureIdentity.spellId = button._displaySpellId
        measureIdentity.itemId = button._resolvedItemId
    else
        measureIdentity.spellId = cached and cached.identitySpellId or nil
        measureIdentity.itemId = cached and cached.identityItemId or nil
    end
    return measureIdentity
end

-- The two client-resolved strings a measurement consumes. They are the cache's
-- identity: everything else the mock renders is derived from style keys and the
-- format string, which the cache already compares.
--
-- Both lookups are cache reads (C_Spell.GetSpellName / C_Item.GetItemNameByID
-- answer from the client's own name cache; GetKeybindText walks the addon's
-- slot maps), and GetTextEntryMetrics caps them at one probe per cache entry
-- per rendered frame.
local function ProbeMeasureStrings(buttonData, button, identity)
    if not buttonData then return "", "" end
    local name = ResolveMockEntryName(buttonData, identity)
    local keybind = CooldownCompanion:GetKeybindText(buttonData, identity.itemId, button)
    return name, (keybind and keybind ~= "") and keybind or ""
end

-- Worst-case value per token. The measuring FontString must already wear
-- the entry's font when this runs: the widest-candidate picks measure.
local function BuildMockContext(fs, style, buttonData, button, identity)
    local ctx = {}
    local mockName, namePending = ResolveMockEntryName(buttonData, identity)
    ctx.name = mockName
    ctx.namePending = namePending

    local clockText = FormatTime(WORST_CASE_SECONDS, style)
    local secretText = string_format(GetDurationSecretFormatSpec(style), WORST_CASE_SECONDS + 0.9)
    ctx.time = PickWidestString(fs, clockText, secretText)

    if IsAuraOnlyEntry(buttonData) then
        -- Aura-only entries have no ready/cooldown fallback in {status}.
        ctx.status = PickWidestString(fs, ctx.time, STATUS_ACTIVE_TEXT)
    else
        local status = PickWidestString(fs, style.textReadyText or "Ready", ctx.time)
        status = PickWidestString(fs, status, STATUS_ACTIVE_TEXT)
        ctx.status = PickWidestString(fs, status, STATUS_DEFERRED_TEXT)
    end

    local keybind = buttonData
        and CooldownCompanion:GetKeybindText(buttonData, identity.itemId, button)
        or nil
    ctx.keybind = (keybind and keybind ~= "") and keybind or ""

    local maxCharges = buttonData and buttonData.maxCharges
    -- {charges} only ever renders for charge-behavior entries.
    ctx.charges = UsesChargeBehavior(buttonData)
        and (maxCharges and tostring(maxCharges) or WORST_CASE_CHARGES)
        or ""
    -- {maxcharges} renders only when the max is known and above 1; an
    -- unknown max is a worst case, not an empty render.
    if maxCharges then
        ctx.maxcharges = (maxCharges > 1) and tostring(maxCharges) or ""
    else
        ctx.maxcharges = WORST_CASE_CHARGES
    end

    ctx.stacks = WORST_CASE_STACKS
    -- No {aura}/{aurastacks} entries: those never reach the mock text. The
    -- planner cuts them out as aura pieces, which MeasureTextEntry measures
    -- on their own from ctx.time and WORST_CASE_STACKS.
    return ctx
end

-- Emission-shape twin of SubstituteTokens, with every value replaced by its
-- worst case and every colour/effect tag dropped (the renderer strips those,
-- so they contribute no width). `presence` is a per-token map: a {?x} region
-- renders when presence[x] is true, a {!x} region renders when it is false,
-- exactly as EvaluateTokenPresence drives SubstituteTokens at runtime. One
-- presence map is therefore a runtime-reachable render, and enumerating every
-- map over the format's distinct conditional tokens is a TRUE upper bound --
-- unlike a single all-present / all-absent pair, which cannot produce a string
-- that mixes polarities across different tokens.
-- Tokens outside conditional regions always emit their worst case.
local mockParts = {}

-- One emission point, so the nil/empty guard cannot be forgotten at a call
-- site. Line splitting is MeasureMockText's job; this only collects.
local function MockEmit(value)
    if value == nil or value == "" then return end
    mockParts[#mockParts + 1] = value
end

-- Sentinel presence map: every conditional region renders regardless of its
-- polarity, so one render is a per-line SUPERSET of every reachable render.
-- Not itself reachable at runtime (a {?x} and a {!x} region on the same token
-- cannot both show), which is exactly why it is only used as a structural
-- upper bound where enumeration is refused -- see MeasureWorstCaseVariant.
local MOCK_PRESENCE_EMIT_ALL = {}

local function BuildMockText(segments, ctx, presence)
    wipe(mockParts)
    local emitAll = presence == MOCK_PRESENCE_EMIT_ALL
    local skipDepth = 0
    for _, seg in ipairs(segments) do
        local segType = seg.type
        if segType == "cond_start" then
            if skipDepth > 0 then
                skipDepth = skipDepth + 1
            elseif not emitAll then
                local present = presence[seg.value] == true
                local shouldShow = (seg.negated and not present) or (not seg.negated and present)
                if not shouldShow then
                    skipDepth = 1
                end
            end
        elseif segType == "cond_end" then
            if skipDepth > 0 then
                skipDepth = skipDepth - 1
            end
        elseif skipDepth > 0 then
            -- Inside a hidden conditional region

        elseif segType == "literal" then
            MockEmit(seg.value)
        elseif segType == "token" and not seg.unknown then
            local token = seg.value
            if token == "name" then
                MockEmit(ctx.name)
            elseif token == "time" then
                MockEmit(ctx.time)
            elseif token == "status" then
                MockEmit(ctx.status)
            elseif token == "charges" then
                MockEmit(ctx.charges)
            elseif token == "maxcharges" then
                MockEmit(ctx.maxcharges)
            elseif token == "stacks" then
                MockEmit(ctx.stacks)
            elseif token == "keybind" then
                MockEmit(ctx.keybind)
            elseif token == "icon" then
                MockEmit(MEASURE_ICON_ESCAPE)
            elseif token == "br" then
                MockEmit("\n")
            end
            -- missingcharges/zerocharges are conditional-only: as bare
            -- tokens SubstituteTokens emits nothing for them either.
            -- {aura}/{aurastacks} are absent because they never reach this
            -- walk: any format holding one produces a composite plan, whose
            -- cc columns exclude them and whose pieces are measured apart.
        end
        -- effect_start/effect_end/color_start/color_end and unknown tokens
        -- contribute no width.
    end
    return table_concat(mockParts)
end

local function MeasureMockText(fs, text)
    local maxWidth = 0
    local lineCount = 1
    local lineStart = 1
    while true do
        local lineBreak = text:find("\n", lineStart, true)
        local lineText = lineBreak and text:sub(lineStart, lineBreak - 1) or text:sub(lineStart)
        if lineText ~= "" then
            local lineWidth = MeasureStringWidth(fs, lineText)
            if lineWidth > maxWidth then
                maxWidth = lineWidth
            end
        end
        if not lineBreak then break end
        lineCount = lineCount + 1
        lineStart = lineBreak + 1
    end
    return maxWidth, lineCount
end

-- The gap between the frame edge and the FontString, on both axes.
--
-- ONE owner for three call sites: the measurement (which sizes the box) and
-- the two live anchor sites (UpdateTextStyle / CreateTextFrame, which position
-- the FontString inside it). They must agree or the padding never becomes
-- visible breathing room -- a left-justified string hugs the left edge while
-- the whole padding budget piles up on the right.
--
-- `region` differs per site on purpose: measurement passes the shared
-- measuring host so the data-only and per-button paths agree to the pixel,
-- while the live sites pass the button itself (crisp border mode reads the
-- region's effective scale). Only the formula is shared.
--
-- The border edge is a hard floor: the frame must clear it before any padding
-- counts, so padX is floored by the inset. padY is floored at 1 (the old fixed
-- inset) and is symmetric top/bottom, which keeps a single-line entry's
-- MIDDLE justification centered.
local function GetTextStringPadding(style, region)
    local borderSize = style.textBorderSize or 0
    local borderRenderMode = ST.GetBorderRenderMode(style, "textBorderRenderMode")
    local borderLayoutSize = ST.GetEffectiveBorderLayoutSize(region, borderSize, borderRenderMode)
    local hasEdge = borderSize > 0
        or ST.IsEffectiveCrispBorderRenderMode(borderRenderMode, nil, borderSize)
    local insetX = (hasEdge and borderLayoutSize or 0) + 2
    local padding = style.textPadding or TEXT_PADDING_DEFAULT
    return math_max(insetX, padding), math_max(1, padding)
end

-- Conditional-variant enumeration. 2^k renders bound a format holding k
-- distinct conditional tokens; the cap keeps the worst case at 16 SetText
-- rounds on a hidden FontString, which is nothing at config/restyle rates.
-- Formats above the cap (5+ distinct conditional tokens) do not occur in
-- practice. They fall back to three renders: the all-absent and all-present
-- pair (both runtime-reachable), plus the MOCK_PRESENCE_EMIT_ALL superset,
-- which emits every conditional region regardless of polarity and so is never
-- narrower than any reachable render of the same line. The pair alone could
-- under-measure a format that mixes polarities across different tokens; the
-- superset closes that. Raising the cap is still the exact fix if such a
-- format ever shows up -- the cost is exponential, not the correctness.
--
-- Residual: the superset is a per-LINE bound only while no line break lives
-- inside a conditional region. A skipped region holding {br} merges two lines
-- into one longer line that the superset never renders. Bounding that would
-- mean reserving the whole format on one line, which would visibly over-widen
-- every legitimate multiline format, so the enumerated path (<= 4 tokens,
-- which is every format seen in practice) stays the exact answer and the
-- fallback stays a close bound.
local MAX_ENUMERATED_COND_TOKENS = 4

local mockCondTokens = {}
local mockCondSeen = {}
local mockPresence = {}
local MOCK_PRESENCE_NONE = {}

-- Distinct conditional tokens in format order. Both {?x} and {!x} parse to a
-- cond_start on x, so one pass over cond_start collects the whole set.
local function CollectConditionalTokens(segments)
    wipe(mockCondTokens)
    wipe(mockCondSeen)
    for _, seg in ipairs(segments) do
        if seg.type == "cond_start" then
            local token = seg.value
            if not mockCondSeen[token] then
                mockCondSeen[token] = true
                mockCondTokens[#mockCondTokens + 1] = token
            end
        end
    end
    return mockCondTokens
end

local function FormatHasNameToken(segments)
    for _, seg in ipairs(segments) do
        if seg.type == "token" and seg.value == "name" and not seg.unknown then
            return true
        end
    end
    return false
end

-- Widest/tallest render across every conditional variant of this format.
local function MeasureWorstCaseVariant(fs, segments, ctx)
    local condTokens = CollectConditionalTokens(segments)
    local tokenCount = #condTokens

    if tokenCount == 0 then
        return MeasureMockText(fs, BuildMockText(segments, ctx, MOCK_PRESENCE_NONE))
    end

    local width, lineCount = 0, 1
    local variantCount, assignsPerVariant
    if tokenCount <= MAX_ENUMERATED_COND_TOKENS then
        variantCount = 2 ^ tokenCount
        assignsPerVariant = tokenCount
    else
        -- Fallback pair: variant 0 = all absent, variant 1 = all present.
        variantCount = 2
        assignsPerVariant = 0
    end

    for variant = 0, variantCount - 1 do
        wipe(mockPresence)
        if assignsPerVariant > 0 then
            local bits = variant
            for i = 1, tokenCount do
                mockPresence[condTokens[i]] = (bits % 2) == 1
                bits = math_floor(bits / 2)
            end
        else
            local allPresent = (variant == 1)
            for i = 1, tokenCount do
                mockPresence[condTokens[i]] = allPresent
            end
        end

        local variantWidth, variantLines = MeasureMockText(fs, BuildMockText(segments, ctx, mockPresence))
        if variantWidth > width then width = variantWidth end
        if variantLines > lineCount then lineCount = variantLines end
    end

    if tokenCount > MAX_ENUMERATED_COND_TOKENS then
        -- Structural upper bound for the un-enumerated case (see the cap
        -- comment): every conditional region emits, so no reachable render can
        -- put more on a line than this one does.
        local supersetWidth, supersetLines =
            MeasureMockText(fs, BuildMockText(segments, ctx, MOCK_PRESENCE_EMIT_ALL))
        if supersetWidth > width then width = supersetWidth end
        if supersetLines > lineCount then lineCount = supersetLines end
    end

    return width, lineCount
end

-- Composite measurement: every column of every line gets its own reserved
-- width, rounded UP to a whole pixel so the anchored offsets the layout
-- derives from them stay pixel-aligned. cc columns measure through the same
-- conditional-variant enumeration as a whole format; aura pieces measure as
-- one mock string around the same worst-case time / stack values. Colour
-- escapes are zero-width in GetUnboundedStringWidth, exactly as in the mock
-- text, so the baked strings measure as built -- only the `%%` escaping is
-- undone, since the client renders it as a single `%`.
local function MeasurePieceMock(fs, text)
    if text == "" then return 0 end
    return MeasureStringWidth(fs, (text:gsub("%%%%", "%%")))
end

local function MeasureRenderPlan(fs, plan, ctx)
    local maxLineWidth = 0
    for _, planLine in ipairs(plan.lines) do
        local lineWidth = 0
        for _, column in ipairs(planLine.columns) do
            local kind = column.kind
            local width
            if kind == "cc" then
                width = MeasureWorstCaseVariant(fs, column.segments, ctx)
            elseif kind == "duration" then
                width = MeasurePieceMock(fs, column.prefix .. ctx.time .. column.suffix)
            elseif kind == "stacks" then
                width = MeasurePieceMock(fs, column.prefix .. WORST_CASE_STACKS .. column.suffix)
            elseif kind == "presence" then
                width = MeasurePieceMock(fs, column.text)
            else
                width = 0
            end
            width = math_ceil(width)
            column.width = width
            lineWidth = lineWidth + width
        end
        planLine.width = lineWidth
        if lineWidth > maxLineWidth then
            maxLineWidth = lineWidth
        end
    end
    return maxLineWidth, #plan.lines
end

-- Returns width, height, lineCount, provisional, plan, lineHeight.
-- `provisional` means the numbers were measured against a {name} the client
-- had not resolved yet, so the caller must not treat them as final (see
-- GetTextEntryMetrics). `plan` is the baked, column-measured render plan
-- when the format is composite and nil otherwise.
local function MeasureTextEntry(style, buttonData, formatString, button, identity)
    local fs = GetMeasureFontString()
    local font = CooldownCompanion:FetchFont(style.textFont or "Friz Quadrata TT")
    local fontSize = style.textFontSize or 12
    local fontOutline = ST.GetEffectiveFontOutline(style.textFontOutline or "OUTLINE")
    fs:SetFont(font, fontSize, fontOutline)

    -- Line height comes from the client, not from the point size: only the
    -- client knows this font's real line box.
    fs:SetText("Ag")
    local lineHeight = math_max(1, math_floor((fs:GetStringHeight() or 0) + 0.999))

    local segments = ParseFormatString(formatString)
    local ctx = BuildMockContext(fs, style, buttonData, button, identity)

    local width, lineCount
    local iconTex
    local plan = BuildTextRenderPlan(segments, buttonData, style)
    if plan.composite then
        -- {icon} inside aura content bakes the live texture when a button
        -- exists; the placeholder measures identically (see
        -- MEASURE_ICON_ESCAPE), so the data-only path agrees to the pixel.
        -- The texture is read ONLY when a piece actually bakes it: it is
        -- the one identity input the cache then has to compare, and a plan
        -- without {icon} in aura content never touches it.
        local iconEscape = MEASURE_ICON_ESCAPE
        if plan.hasIconInAura and button and button.icon then
            iconTex = button.icon:GetTexture()
        end
        if iconTex then
            iconEscape = string_format("|T%s:0|t", tostring(iconTex))
        end
        BakeTextRenderPlan(plan, style, ctx, iconEscape)
        width, lineCount = MeasureRenderPlan(fs, plan, ctx)
    else
        plan = nil
        width, lineCount = MeasureWorstCaseVariant(fs, segments, ctx)
    end

    -- Only a format that actually renders {name} is wrong because of an
    -- unresolved name; every other format measures the same either way.
    -- (A {name} inside aura content is in `segments` too, so it counts.)
    local provisional = ctx.namePending == true and FormatHasNameToken(segments)

    -- Same helper the live FontString anchors through, against the measuring
    -- host (see GetTextStringPadding).
    local padX, padY = GetTextStringPadding(style, measureHostFrame)

    local boxWidth = math_max(1, math_ceil(width) + padX * 2)
    local boxHeight = math_max(1, lineCount * lineHeight + padY * 2)

    fs:SetText("")

    return boxWidth, boxHeight, lineCount, provisional, plan, lineHeight, iconTex
end

-- Per-entry metrics cache. Keyed by buttonData (or the style table for the
-- group-level baseline, which has no entry); both are stable identities --
-- GetEffectiveStyle returns either the group style table or the entry's own
-- styleOverrides table, never a fresh copy. Weak keys so deleted entries and
-- destroyed groups drop out on their own.
--
-- INVARIANT: cached.style is stored ONLY when the style table is not itself the
-- cache key; a nil cached.style therefore means "the key IS the style" (the
-- group-level baseline entry, which has no buttonData). Storing it on those
-- entries made the value table strongly reference its own weak key, and Lua 5.1
-- has no ephemerons, so the entry -- and the style table it pointed at -- could
-- never be collected even after the group was deleted.
local textMetricsCache = setmetatable({}, { __mode = "k" })

-- The four role colours BakeTextRenderPlan can bake into a piece are cache
-- inputs too. Compared component-wise (colour tables are mutated in place by
-- the config, so table identity proves nothing) and stored as plain fields,
-- so a hit allocates nothing.
local function SnapshotColor(cached, key, color)
    cached[key .. "R"], cached[key .. "G"], cached[key .. "B"], cached[key .. "A"] =
        color[1], color[2], color[3], color[4]
end

local function ColorMatches(cached, key, color)
    return cached[key .. "R"] == color[1] and cached[key .. "G"] == color[2]
        and cached[key .. "B"] == color[3] and cached[key .. "A"] == color[4]
end

local function GetTextEntryMetrics(style, buttonData, formatString, button, forceRefresh)
    if type(style) ~= "table" then
        return 1, 1, 1
    end
    local fmt = formatString or style.textFormat or DEFAULT_TEXT_FORMAT
    local cacheKey = buttonData or style
    local cached = textMetricsCache[cacheKey]
    local now = GetTime()
    local inputsMatch = cached
        and cached.fmt == fmt
        -- See the cache's INVARIANT: a baseline entry stores no style, because
        -- its key already IS the style table.
        and (cached.style or cacheKey) == style
        and cached.font == style.textFont
        and cached.fontSize == style.textFontSize
        and cached.outline == style.textFontOutline
        and cached.padding == style.textPadding
        and cached.readyText == style.textReadyText
        and cached.durationFormat == style.durationFormat
        and cached.decimalTimers == style.decimalTimers
        and cached.borderSize == style.textBorderSize
        and cached.borderMode == style.textBorderRenderMode
        and ColorMatches(cached, "cd", style.textCooldownColor or DEFAULT_CD_COLOR)
        and ColorMatches(cached, "ready", style.textReadyColor or DEFAULT_READY_COLOR)
        and ColorMatches(cached, "aura", style.textAuraColor or DEFAULT_AURA_COLOR)
        and ColorMatches(cached, "custom", style.textCustomColor or DEFAULT_CUSTOM_COLOR)

    -- The style keys above are only half the inputs. The other half is what the
    -- CLIENT resolved: the entry's displayed name and its keybind text. Both
    -- can change with no style edit at all -- a spell transforms into a longer
    -- override, an equipment slot resolves to a different item, a bind is
    -- rebound, or a login-time name simply arrives late -- and a cache that
    -- does not compare them hands back a box measured for the old strings
    -- forever. GetTime() advances once per rendered frame, so re-resolving is
    -- capped at one probe per cache entry per frame no matter how many readers
    -- hit it in the same layout pass.
    if not forceRefresh and inputsMatch and cached.probePass == now
        and (not cached.provisional or cached.provisionalPass == now) then
        return cached.width, cached.height, cached.lineCount
    end

    local identity = ResolveMeasureIdentity(buttonData, button, cached)
    local probeName, probeKeybind = ProbeMeasureStrings(buttonData, button, identity)
    -- Third client-resolved input, only for plans that baked an {icon} into
    -- a piece (a spell transform swaps the texture with no style edit). A
    -- data-only read has no texture to probe and keeps the stored one, the
    -- same fallback the spell/item identity uses.
    local probeIcon = cached and cached.iconTexture or nil
    if cached and cached.plan and cached.plan.hasIconInAura and button and button.icon then
        probeIcon = button.icon:GetTexture()
    end

    if not forceRefresh and inputsMatch
        and cached.name == probeName
        and cached.keybind == probeKeybind
        and cached.iconTexture == probeIcon then
        cached.probePass = now
        if not cached.provisional then
            return cached.width, cached.height, cached.lineCount
        end
        -- Provisional entry: these numbers were measured against a {name} the
        -- client had not cached yet, so a hit must NOT be trusted -- it would
        -- freeze a too-small box until the next restyle. Re-measure so the
        -- layout self-heals within a pass or two of the name arriving.
        --
        -- Cost bound: the same one-pass-per-frame stamp as above, which caps a
        -- never-resolving entry (a deleted spell id) at one measurement per
        -- pass instead of one per call. Layout passes are dirty-flag gated;
        -- per-tick display code never reaches this function at all.
        if cached.provisionalPass == now then
            return cached.width, cached.height, cached.lineCount
        end
    end

    local width, height, lineCount, provisional, plan, lineHeight, iconTex =
        MeasureTextEntry(style, buttonData, fmt, button, identity)

    if not cached then
        cached = {}
        textMetricsCache[cacheKey] = cached
    end
    -- The composite render plan (nil for a single-string format) and the
    -- line height its rows are stacked on. ApplyTextLayout reads both back
    -- through the cache right after its forced re-measure; the data-only
    -- readers never look at them.
    cached.plan = plan
    cached.lineHeight = lineHeight
    cached.fmt = fmt
    -- See the cache's INVARIANT: never store the style on the entry whose key
    -- it already is, or the weak key can never be collected.
    if cacheKey ~= style then
        cached.style = style
    else
        cached.style = nil
    end
    cached.font = style.textFont
    cached.fontSize = style.textFontSize
    cached.outline = style.textFontOutline
    cached.padding = style.textPadding
    cached.readyText = style.textReadyText
    cached.durationFormat = style.durationFormat
    cached.decimalTimers = style.decimalTimers
    cached.borderSize = style.textBorderSize
    cached.borderMode = style.textBorderRenderMode
    SnapshotColor(cached, "cd", style.textCooldownColor or DEFAULT_CD_COLOR)
    SnapshotColor(cached, "ready", style.textReadyColor or DEFAULT_READY_COLOR)
    SnapshotColor(cached, "aura", style.textAuraColor or DEFAULT_AURA_COLOR)
    SnapshotColor(cached, "custom", style.textCustomColor or DEFAULT_CUSTOM_COLOR)
    -- The client-resolved half of the inputs, plus the ids they were resolved
    -- through so a later data-only read reproduces the same strings.
    cached.name = probeName
    cached.keybind = probeKeybind
    cached.iconTexture = iconTex
    cached.identitySpellId = identity.spellId
    cached.identityItemId = identity.itemId
    cached.probePass = now
    cached.width = width
    cached.height = height
    cached.lineCount = lineCount
    -- Stored only once the name resolved; until then the entry stays flagged
    -- and stamped with the pass that last measured it.
    cached.provisional = provisional or nil
    cached.provisionalPass = provisional and now or nil
    return width, height, lineCount
end

------------------------------------------------------------------------
-- COMPOSITE LAYOUT
--
-- A composite entry renders its cc columns through pooled FontStrings
-- (button._textRunStrings, created lazily, one per cc column in format
-- order) while button.textString stays blank. Each column is anchored at
-- its measured x/y inside the box and sized to its reserved width; a line's
-- columns are shifted together by the alignment slack so LEFT / CENTER /
-- RIGHT behave as they do for a single string. Aura pieces get the same
-- geometry written onto their column tables (x, y, width, height,
-- justifyH); Core/AuraDisplay's text host anchors the client's FontStrings
-- from those numbers and nothing here creates them.
------------------------------------------------------------------------
-- Font, alignment, shadow and base colour for a pooled run string: the same
-- recipe UpdateTextStyle / CreateTextFrame apply to button.textString.
local function StyleTextRunString(fs, style)
    local font = CooldownCompanion:FetchFont(style.textFont or "Friz Quadrata TT")
    local fontSize = style.textFontSize or 12
    local fontOutline = ST.GetEffectiveFontOutline(style.textFontOutline or "OUTLINE")
    fs:SetFont(font, fontSize, fontOutline)
    local baseColor = style.textFontColor or DEFAULT_WHITE
    fs:SetTextColor(baseColor[1], baseColor[2], baseColor[3], baseColor[4] or 1)
    fs:SetJustifyH(style.textAlignment or "LEFT")
    fs:SetJustifyV("MIDDLE")
    fs:SetWordWrap(false)
    ST.ApplyFontShadowForOutline(fs, fontOutline, style.textShadow == true)
end

local function HideTextRunStrings(button, fromIndex)
    local runs = button._textRunStrings
    if not runs then return end
    for i = fromIndex, #runs do
        local fs = runs[i]
        fs:SetText("")
        fs:SetAlpha(1.0)
        fs:Hide()
    end
end

-- One alpha writer for both modes: the single string, or every live cc run.
local function SetTextRunsAlpha(button, alpha)
    local plan = button._textRenderPlan
    if plan then
        local runs = button._textRunStrings
        local runColumns = plan.runColumns
        for i = 1, #runColumns do
            runs[runColumns[i].runIndex]:SetAlpha(alpha)
        end
    else
        button.textString:SetAlpha(alpha)
    end
end

-- The geometry of a composite plan, with no writes: walks the lines and
-- columns in format order and hands each column's placement to `sink`
-- (column, x, y, width, height, justifyH). x already includes the left
-- padding, y is negative-down from the box's top, width is the column's
-- reserved width and height the line height. The live layout below writes
-- these onto the columns; the config mirror keeps its own copy, since the
-- plan it reads is the live entry's (see ST._GetTextRenderPlanMetrics).
local function ComputeTextColumnGeometry(plan, style, lineHeight, boxWidth, region, sink)
    local padX, padY = GetTextStringPadding(style, region)
    local align = style.textAlignment or "LEFT"
    local innerWidth = boxWidth - padX * 2
    for lineIndex, planLine in ipairs(plan.lines) do
        local x
        if align == "CENTER" then
            x = math_floor((innerWidth - planLine.width) / 2)
        elseif align == "RIGHT" then
            x = innerWidth - planLine.width
        else
            x = 0
        end
        local y = -(padY + (lineIndex - 1) * lineHeight)
        for _, column in ipairs(planLine.columns) do
            sink(column, padX + x, y, column.width, lineHeight, align)
            x = x + column.width
        end
    end
end

-- The live layout's sink. Module-level with its inputs in upvalues rather
-- than a closure per restyle; only LayoutCompositeText drives it, and never
-- re-entrantly.
local layoutButton, layoutStyle, layoutRunIndex
local function LayoutCompositeColumn(column, x, y, width, height, justifyH)
    column.x = x
    column.y = y
    column.height = height
    column.justifyH = justifyH
    if column.kind == "cc" then
        local button = layoutButton
        local runs = button._textRunStrings
        local runIndex = layoutRunIndex + 1
        layoutRunIndex = runIndex
        local fs = runs[runIndex]
        if not fs then
            fs = button:CreateFontString(nil, "OVERLAY")
            runs[runIndex] = fs
        end
        StyleTextRunString(fs, layoutStyle)
        fs:ClearAllPoints()
        fs:SetPoint("TOPLEFT", button, "TOPLEFT", x, y)
        fs:SetSize(width, height)
        fs:Show()
        column.runIndex = runIndex
    end
end

local function LayoutCompositeText(button, style, plan, lineHeight, boxWidth)
    if not button._textRunStrings then
        button._textRunStrings = {}
    end
    layoutButton, layoutStyle, layoutRunIndex = button, style, 0
    ComputeTextColumnGeometry(plan, style, lineHeight, boxWidth, button, LayoutCompositeColumn)
    local runIndex = layoutRunIndex
    layoutButton, layoutStyle = nil, nil
    HideTextRunStrings(button, runIndex + 1)
    -- The single string renders nothing while the plan drives the entry. It
    -- stays anchored, so a later non-composite restyle simply resumes it.
    button.textString:SetText("")
    button.textString:SetAlpha(1.0)
    button._textRenderPlan = plan
end

local function ApplyTextLayout(button, style, formatString)
    local buttonData = button.buttonData
    -- Force a re-measure: this is the restyle path, and it is the one place
    -- that re-resolves late-arriving inputs (spell/item name, keybind).
    local width, height, lineCount =
        GetTextEntryMetrics(style, buttonData, formatString, button, true)
    local isMultiline = lineCount > 1

    button:SetSize(width, height)

    -- The forced re-measure just refreshed this entry's cache slot, which is
    -- where the plan and line height live (same key GetTextEntryMetrics used).
    local cached = textMetricsCache[buttonData or style]
    local plan = cached and cached.plan
    if plan then
        LayoutCompositeText(button, style, plan, cached.lineHeight, width)
        return
    end
    if button._textRenderPlan then
        -- Composite -> single string (the format was edited): put the pooled
        -- runs away and let button.textString render again.
        HideTextRunStrings(button, 1)
        button._textRenderPlan = nil
    end
    button.textString:SetJustifyV(isMultiline and "TOP" or "MIDDLE")
    button.textString:SetWordWrap(isMultiline)
end

-- Re-measure and resize one text entry NOW, with no dirty flag and no combat
-- deferral. For callers that are already mid-rebuild and will re-pitch the
-- panel themselves on the same pass -- GroupFrame's PreparePooledButtonForUse
-- restyles a pooled frame BEFORE UpdateButtonIcon assigns its display
-- identity, exactly like CreateTextFrame used to, and ApplyActiveButtonLayout
-- runs immediately afterwards.
local function ApplyTextEntryLayout(button)
    if not button or not button._isText then return end
    local style = button.style
    local buttonData = button.buttonData
    if not style or not buttonData or not button.textString then return end
    ApplyTextLayout(button, style, buttonData.textFormat or style.textFormat or DEFAULT_TEXT_FORMAT)
end

-- Invalidation entry point. Re-reads one text entry's metrics through the
-- cache -- so it costs a few comparisons when nothing moved -- and, when the
-- box the entry SHOULD have no longer matches the frame it HAS, resizes the
-- frame and marks its panel for a re-pitch.
--
-- Returns the group id when the panel needs re-pitching, nil otherwise. The
-- caller batches: the grid pitch is the max over every entry, so one restyle
-- per panel settles any number of changed entries. The dirty flags are set for
-- the ticker's compact-reflow pass (Core/Lifecycle -> UpdateAllGroupLayouts);
-- a non-compact panel's slots are only re-placed by ApplyActiveButtonLayout,
-- which is why the caller still has to run one UpdateGroupStyle.
--
-- NOT reachable from any per-tick display path -- callers are event handlers.
local function RefreshTextEntryLayout(button)
    if not button or not button._isText then return nil end
    local style = button.style
    local buttonData = button.buttonData
    if not style or not buttonData or not button.textString then return nil end

    -- The once-per-frame probe cap exists to stop repeated LAYOUT readers from
    -- re-resolving the same strings inside one pass. An explicit invalidation
    -- is the opposite case and must always re-probe, so drop the stamp first.
    -- The measurement itself still only re-runs if a string actually moved.
    local cached = textMetricsCache[buttonData]
    if cached then
        cached.probePass = nil
    end

    local fmt = buttonData.textFormat or style.textFormat or DEFAULT_TEXT_FORMAT
    local width, height = GetTextEntryMetrics(style, buttonData, fmt, button)
    local currentWidth, currentHeight = button:GetSize()
    -- Measured box sizes are whole numbers, so this is an equality test with a
    -- sub-pixel guard: nothing here may turn a frequent event (action bar slot
    -- changes route through OnKeybindsChanged) into a per-event panel restyle.
    --
    -- A composite entry also re-lays out when the read above re-measured and
    -- so replaced the cached plan (the plan object the button renders is the
    -- one the cache handed it): a {keybind} baked into an aura piece can
    -- rebind to a same-width key, and the client host reads its pieces from
    -- the button's plan. A cache hit keeps the same object, so this costs one
    -- comparison when nothing moved.
    cached = textMetricsCache[buttonData]
    local planChanged = (cached and cached.plan) ~= button._textRenderPlan
    if not planChanged
        and math_abs(width - currentWidth) < 0.5 and math_abs(height - currentHeight) < 0.5 then
        return nil
    end

    if InCombatLockdown() then
        -- A text entry never resizes mid-combat. Ride the same out-of-combat
        -- recovery the deferred group refreshes use (Core/Lifecycle
        -- OnCombatEnd -> RefreshAllGroups).
        CooldownCompanion._pendingFullRefresh = true
        return nil
    end

    ApplyTextLayout(button, style, fmt)
    local groupFrame = button:GetParent()
    if groupFrame then
        groupFrame._sizeDirty = true
        groupFrame._layoutDirty = true
    end
    return button._groupId
end

local function ComputePulse(now)
    return 0.7 + 0.3 * math_sin(now * 2 * math_pi)
end

------------------------------------------------------------------------
-- COLOR WRAPPING
------------------------------------------------------------------------
-- The escape prefix is a pure function of the colour's first three components,
-- so it is memoized per colour table. Colour tables are mutated in place, so
-- the entry is revalidated component-wise and never by table identity. Weak
-- keys keep discarded colour tables collectable; nothing is written back onto
-- the colour table itself (they belong to persisted style data).
local colorPrefixCache = setmetatable({}, { __mode = "k" })

-- Assigns the forward-declared local above the measurement section (the
-- plan baker resolves colour tags through it).
function ColorPrefix(color)
    local r, g, b = color[1], color[2], color[3]
    local entry = colorPrefixCache[color]
    if entry and entry.r == r and entry.g == g and entry.b == b then
        return entry.prefix
    end

    local prefix = string_format("|cff%02x%02x%02x",
        math_floor(r * 255),
        math_floor(g * 255),
        math_floor(b * 255))
    if not entry then
        entry = {}
        colorPrefixCache[color] = entry
    end
    entry.r, entry.g, entry.b, entry.prefix = r, g, b, prefix
    return prefix
end

local function WrapColor(text, color)
    if not text or text == "" then return "" end
    if not color then return text end
    return ColorPrefix(color) .. text .. "|r"
end

local function ResolveTextModeStackDisplay(button)
    local itemCount = button._itemCount
    if itemCount and itemCount > 0 then
        return tostring(itemCount), "item"
    end

    return nil, nil
end

local function ClearTextVisualState(button)
    if button then
        button._textVisualIntent = nil
        button._textVisualApplied = nil
    end
end

local function ShouldStoreTextVisualState()
    return type(AreButtonVisualStateSnapshotsEnabled) == "function"
        and AreButtonVisualStateSnapshotsEnabled() == true
end

local function EnsureTextVisualTable(button, fieldName)
    local target = button[fieldName]
    if target then
        wipe(target)
    else
        target = {}
        button[fieldName] = target
    end
    return target
end

local function ResolveTextIntentDomain(button, auraOnlyEntry, auraActive, auraHasTimer, timeRemaining, timeIsSecret, auraRemaining, auraIsSecret)
    if auraActive then
        if auraHasTimer and (auraIsSecret or auraRemaining ~= nil) then
            return "aura-timer"
        end
        return "aura-active"
    end

    if auraOnlyEntry then
        return "aura-only"
    end

    if timeIsSecret or (timeRemaining and timeRemaining > 0) then
        return "cooldown"
    end

    if button._cooldownDeferred == true then
        return "deferred"
    end

    return "ready"
end

local function StoreTextVisualIntent(button, details)
    local intent = EnsureTextVisualTable(button, "_textVisualIntent")
    intent.domain = ResolveTextIntentDomain(
        button,
        details.auraOnlyEntry,
        details.auraActive,
        details.auraHasTimer,
        details.timeRemaining,
        details.timeIsSecret,
        details.auraRemaining,
        details.auraIsSecret
    )
    intent.stackSource = details.stackDisplayKind
    intent.secretDuration = details.secretValue ~= nil
    intent.secretDurationToken = details.secretColorToken
    intent.secretStack = details.secretStackValue ~= nil
    intent.secretName = details.hasSecretNameValue == true
    intent.hasText = details.text ~= nil and details.text ~= ""
    intent.pulseActive = details.effectState and details.effectState.pulseActive == true or false
    return intent
end

local function StoreTextVisualApplied(button, writePath, text, secretValue, secretStackValue, hasSecretNameValue)
    local applied = EnsureTextVisualTable(button, "_textVisualApplied")
    applied.writePath = writePath
    applied.hasText = text ~= nil and text ~= ""
    applied.secretDuration = secretValue ~= nil
    applied.secretStack = secretStackValue ~= nil
    applied.secretName = hasSecretNameValue == true
    return applied
end

local function UpdateTextVisualAppliedPulse(button)
    local applied = button and button._textVisualApplied
    if type(applied) ~= "table" then
        return
    end

    local es = button._effectState
    applied.pulseActive = es and es.pulseActive == true or false
end

------------------------------------------------------------------------
-- EVALUATE TOKEN PRESENCE
-- Returns true if the given token would produce non-empty output.
-- Used by conditional sections ({?token}...{/token}).
------------------------------------------------------------------------
local function EvaluateTokenPresence(button, tokenName, timeRemaining, timeIsSecret, auraRemaining, auraIsSecret, stackDisplayKind)
    if tokenName == "time" then
        return timeIsSecret or (timeRemaining and timeRemaining > 0)
    elseif tokenName == "charges" then
        return UsesChargeBehavior(button.buttonData)
    elseif tokenName == "maxcharges" then
        if not UsesChargeBehavior(button.buttonData) then return false end
        return button._chargeState == CHARGE_STATE_FULL
    elseif tokenName == "missingcharges" then
        if not UsesChargeBehavior(button.buttonData) then return false end
        return button._chargeState == CHARGE_STATE_MISSING
    elseif tokenName == "zerocharges" then
        if not UsesChargeBehavior(button.buttonData) then return false end
        return button._chargeState == CHARGE_STATE_ZERO
    elseif tokenName == "stacks" then
        return stackDisplayKind ~= nil
    elseif tokenName == "aura" then
        -- Never asked in practice: {?aura}/{!aura} regions are resolved by
        -- BuildTextRenderPlan (client-rendered content / dropped) and never
        -- reach SubstituteTokens. The aura's presence is the client's, not
        -- the addon's, so the defined fallback answer is false.
        return false
    elseif tokenName == "keybind" then
        local kb = CooldownCompanion:GetKeybindText(button.buttonData, button._resolvedItemId, button)
        return kb and kb ~= ""
    elseif tokenName == "proc" then
        return button._procOverlayActive == true
    elseif tokenName == "unusable" then
        return button._isUnusable == true
    elseif tokenName == "oor" then
        return button._isOutOfRange == true
    elseif tokenName == "available" then
        return button._desatCooldownActive ~= true
    elseif tokenName == "incombat" then
        return UnitAffectingCombat("player") == true
    end
    return false
end

------------------------------------------------------------------------
-- COLOR TAG RESOLUTION
------------------------------------------------------------------------
local function ResolveColorName(name, cdColor, readyColor, auraColor, customColor)
    if name == "cooldown" then return cdColor
    elseif name == "ready" then return readyColor
    elseif name == "active" then return auraColor
    elseif name == "custom" then return customColor
    end
end

------------------------------------------------------------------------
-- SUBSTITUTE TOKENS
-- Builds the final display string from pre-parsed segments.
-- Returns: displayText, secretValue, secretColorToken, secretStackValue, secretNameValue, hasSecretNameValue
------------------------------------------------------------------------
local function SubstituteTokens(button, segments, style, effectState, secretNameOverride, hasSecretNameOverride, shouldStoreTextVisualState)
    local buttonData = button.buttonData
    local parts = button._textModeParts
    if parts then
        wipe(parts)
    else
        parts = {}
        button._textModeParts = parts
    end
    local secretValue = nil
    local secretColorToken = nil
    local secretStackValue = nil
    local secretNameValue = nil
    local hasSecretNameValue = false

    local baseColor = style.textFontColor or DEFAULT_WHITE
    local cdColor = style.textCooldownColor or DEFAULT_CD_COLOR
    local readyColor = style.textReadyColor or DEFAULT_READY_COLOR
    local auraColor = style.textAuraColor or DEFAULT_AURA_COLOR
    local customColor = style.textCustomColor or DEFAULT_CUSTOM_COLOR

    -- Charge color resolution
    local chargeFull = style.chargeFontColor or DEFAULT_WHITE
    local chargeMissing = style.chargeFontColorMissing or DEFAULT_WHITE
    local chargeZero = style.chargeFontColorZero or DEFAULT_WHITE

    -- Gather live state
    local auraOnlyEntry = IsAuraOnlyEntry(buttonData)
    local currentCharges = button._currentReadableCharges
    local maxCharges = button.buttonData.maxCharges
    local stackDisplayText, stackDisplayKind = ResolveTextModeStackDisplay(button)
    local auraActive = button._auraActive
    local auraHasTimer = button._auraHasTimer == true
    -- _durationObj holds either cooldown remaining or aura remaining (when aura override is active).
    -- Determine which domain owns it this tick.
    local durationRemaining = nil
    local durationIsSecret = false
    if button._durationObj then
        local rem = button._durationObj:GetRemainingDuration()
        if button._durationObj:HasSecretValues() then
            -- F2 canary: secret remaining text is still a time-driven render,
            -- and the combat ticker floor skips in combat too -- this branch
            -- must feed the false-idle canary like the readable one below.
            RefreshTelemetry:NoteTimeRender()
            durationIsSecret = true
            durationRemaining = rem
        elseif rem and rem > 0 then
            -- F2 canary: spell-cooldown / aura remaining text is drawn from the
            -- duration object this walk (covered by the _cooldownState ==
            -- COOLDOWN / _auraActive classifier terms).
            RefreshTelemetry:NoteTimeRender()
            durationRemaining = rem
        end
    elseif not auraActive and button._itemCdStart and button._itemCdDuration and button._itemCdDuration > 0 then
        -- F2 canary: item cooldown text remaining is drawn this walk (covered by
        -- the _cooldownState == COOLDOWN classifier term).
        RefreshTelemetry:NoteTimeRender()
        local now = GetTime()
        local elapsed = now - button._itemCdStart
        local rem = button._itemCdDuration - elapsed
        if rem > 0 then
            durationRemaining = rem
        end
    end

    -- Split into time (cooldown) and aura remaining based on aura state
    local timeRemaining, timeIsSecret
    local auraRemaining, auraIsSecret
    if auraActive then
        auraRemaining = durationRemaining
        auraIsSecret = durationIsSecret
    else
        timeRemaining = durationRemaining
        timeIsSecret = durationIsSecret
    end

    -- Conditional skip state for {?token}...{/token} and {!token}...{/token}
    local skipDepth = 0

    -- Pulse effect depth counter for {pulse}...{/pulse} wrapper tags
    local pulseDepth = 0

    -- Color override state for {cooldown}...{/cooldown} etc.
    local colorOverride = nil
    local colorStack = button._textModeColorStack
    if colorStack then
        wipe(colorStack)
    else
        colorStack = {}
        button._textModeColorStack = colorStack
    end

    for _, seg in ipairs(segments) do
        -- Conditional section handling
        if seg.type == "cond_start" then
            if skipDepth > 0 then
                skipDepth = skipDepth + 1
            else
                local present = EvaluateTokenPresence(button, seg.value, timeRemaining, timeIsSecret, auraRemaining, auraIsSecret, stackDisplayKind)
                local shouldShow = (seg.negated and not present) or (not seg.negated and present)
                if not shouldShow then
                    skipDepth = 1
                end
            end
        elseif seg.type == "cond_end" then
            if skipDepth > 0 then
                skipDepth = skipDepth - 1
            end
        elseif skipDepth > 0 then
            -- Inside a false conditional — skip this segment

        elseif seg.type == "effect_start" then
            if effectState and seg.value == "pulse" then
                pulseDepth = pulseDepth + 1
            end

        elseif seg.type == "effect_end" then
            if effectState and seg.value == "pulse" and pulseDepth > 0 then
                pulseDepth = pulseDepth - 1
            end

        elseif seg.type == "color_start" then
            colorStack[#colorStack + 1] = colorOverride
            colorOverride = ResolveColorName(seg.value, cdColor, readyColor, auraColor, customColor)

        elseif seg.type == "color_end" then
            colorOverride = colorStack[#colorStack]
            colorStack[#colorStack] = nil

        elseif seg.type == "literal" then
            if colorOverride then
                parts[#parts + 1] = WrapColor(seg.value, colorOverride)
            else
                parts[#parts + 1] = seg.value
            end
            if pulseDepth > 0 and effectState then
                effectState.pulseActive = true
            end

        elseif seg.unknown then
            -- Unknown tokens render as empty
        else
            local prevPartCount = #parts
            local token = seg.value
            if token == "name" then
                local name = buttonData.customName or buttonData.name or ""
                if not buttonData.customName and buttonData.type == "spell" then
                    if button._auraActive and hasSecretNameOverride then
                        secretNameValue = secretNameOverride
                        hasSecretNameValue = true
                        parts[#parts + 1] = WrapColor("%NAME%", colorOverride or baseColor)
                        name = nil
                    else
                        local spellName = C_Spell.GetSpellName(button._displaySpellId or buttonData.id)
                        if spellName then name = spellName end
                    end
                elseif not buttonData.customName and IsEntryItemLike(buttonData) then
                    local itemID = button._resolvedItemId or buttonData.id
                    local itemName = itemID and C_Item.GetItemNameByID(itemID)
                    if itemName then name = itemName end
                end
                if name then
                    parts[#parts + 1] = WrapColor(name, colorOverride or baseColor)
                end

            elseif token == "time" then
                if timeIsSecret then
                    if not secretValue then
                        secretValue = timeRemaining
                        secretColorToken = "cd"
                    end
                    parts[#parts + 1] = WrapColor("%TIME%", colorOverride or cdColor)
                elseif timeRemaining then
                    parts[#parts + 1] = WrapColor(FormatTime(timeRemaining, style), colorOverride or cdColor)
                end

            elseif token == "charges" then
                if currentCharges ~= nil then
                    local cc
                    if currentCharges == maxCharges then
                        cc = chargeFull
                    elseif currentCharges == 0 then
                        cc = chargeZero
                    else
                        cc = chargeMissing
                    end
                    parts[#parts + 1] = WrapColor(tostring(currentCharges), colorOverride or cc)
                end

            elseif token == "maxcharges" then
                if maxCharges and maxCharges > 1 then
                    parts[#parts + 1] = WrapColor(tostring(maxCharges), colorOverride or baseColor)
                end

            elseif token == "stacks" then
                if stackDisplayKind then
                    if issecretvalue(stackDisplayText) then
                        if not secretStackValue then
                            secretStackValue = stackDisplayText
                        end
                        parts[#parts + 1] = WrapColor("%STACKS%", colorOverride or baseColor)
                    else
                        parts[#parts + 1] = WrapColor(stackDisplayText, colorOverride or baseColor)
                    end
                end

            elseif token == "aura" or token == "aurastacks" then
                -- Emits NOTHING here: the planner routes both tokens to
                -- client-rendered aura pieces, so a segment list handed to
                -- this walk never holds them. Kept as a defined no-op for
                -- safety only.

            elseif token == "keybind" then
                local kb = CooldownCompanion:GetKeybindText(buttonData, button._resolvedItemId, button)
                if kb and kb ~= "" then
                    parts[#parts + 1] = WrapColor(kb, colorOverride or baseColor)
                end

            elseif token == "status" then
                if auraActive then
                    if not auraHasTimer then
                        parts[#parts + 1] = WrapColor("Active", colorOverride or auraColor)
                    elseif auraIsSecret then
                        if not secretValue then
                            secretValue = auraRemaining
                            secretColorToken = "aura"
                        end
                        parts[#parts + 1] = WrapColor("%STATUS%", colorOverride or auraColor)
                    elseif auraRemaining then
                        parts[#parts + 1] = WrapColor(FormatTime(auraRemaining, style), colorOverride or auraColor)
                    else
                        parts[#parts + 1] = WrapColor("Active", colorOverride or auraColor)
                    end
                elseif auraOnlyEntry then
                    -- Aura-only entries do not have a ready/cooldown fallback.
                elseif timeIsSecret then
                    if not secretValue then
                        secretValue = timeRemaining
                        secretColorToken = "cd"
                    end
                    parts[#parts + 1] = WrapColor("%STATUS%", colorOverride or cdColor)
                elseif timeRemaining and timeRemaining > 0 then
                    parts[#parts + 1] = WrapColor(FormatTime(timeRemaining, style), colorOverride or cdColor)
                elseif button._cooldownDeferred then
                    -- Deferred cooldown: timer hasn't started yet, show cooldown
                    -- color with placeholder instead of "Ready".
                    parts[#parts + 1] = WrapColor("...", colorOverride or cdColor)
                else
                    parts[#parts + 1] = WrapColor(style.textReadyText or "Ready", colorOverride or readyColor)
                end

            elseif token == "icon" then
                local iconTex = button.icon and button.icon:GetTexture()
                if iconTex then
                    parts[#parts + 1] = string_format("|T%s:0|t", tostring(iconTex))
                end
            elseif token == "br" then
                parts[#parts + 1] = "\n"
            end

            -- Mark pulse active when a token emitted content inside pulse region
            if pulseDepth > 0 and effectState and #parts > prevPartCount then
                effectState.pulseActive = true
            end
        end
    end

    local text = table_concat(parts)
    if shouldStoreTextVisualState then
        StoreTextVisualIntent(button, {
            auraOnlyEntry = auraOnlyEntry,
            auraActive = auraActive,
            auraHasTimer = auraHasTimer,
            timeRemaining = timeRemaining,
            timeIsSecret = timeIsSecret,
            auraRemaining = auraRemaining,
            auraIsSecret = auraIsSecret,
            currentCharges = currentCharges,
            maxCharges = maxCharges,
            stackDisplayKind = stackDisplayKind,
            stackDisplayText = stackDisplayText,
            secretValue = secretValue,
            secretColorToken = secretColorToken,
            secretStackValue = secretStackValue,
            hasSecretNameValue = hasSecretNameValue,
            text = text,
            effectState = effectState,
        })
    end

    return text, secretValue, secretColorToken, secretStackValue, secretNameValue, hasSecretNameValue
end

------------------------------------------------------------------------
-- UPDATE TEXT DISPLAY
-- Called each tick from CooldownUpdate.lua after data is resolved.
------------------------------------------------------------------------
-- Sentinel placeholder table for the secret-value pass. Reused across calls:
-- the scan below reads the fields synchronously and never keeps the entry
-- tables, so only the per-call fields (val/active/fmt) are reassigned. The
-- %TIME%/%AURA%/%STATUS%/%STACKS% entries must keep `active` nil so they stay
-- gated on `val` alone; only %NAME% carries an explicit active flag.
local SECRET_PLACEHOLDERS = {
    {text = "%TIME%",   fmt = "%s"},
    {text = "%AURA%",   fmt = "%s"},
    {text = "%STATUS%", fmt = "%s"},
    {text = "%STACKS%", fmt = "%s"},
    {text = "%NAME%",   fmt = "%s"},
}

-- One run: substitutes `segments` and writes the result onto `fontString`,
-- through the secret pass-through when a secret value is in play. Shared by
-- the single-string path (button.textString, button._textSegments) and the
-- composite path (one call per cc column). The per-button scratch tables
-- SubstituteTokens and the secret pass borrow are reused across columns
-- within a tick; each run completes before the next starts.
-- Returns whether a secret name placeholder was written.
local function RenderTextRun(button, fontString, segments, style, es, secretNameOverride, hasSecretNameOverride, shouldStoreTextVisualState)
    local text, secretValue, secretColorToken, secretStackValue, secretNameValue, hasSecretNameValue = SubstituteTokens(button, segments, style, es, secretNameOverride, hasSecretNameOverride, shouldStoreTextVisualState)

    local baseColor = style.textFontColor or DEFAULT_WHITE
    fontString:SetTextColor(baseColor[1], baseColor[2], baseColor[3], baseColor[4] or 1)

    if secretValue or secretStackValue or hasSecretNameValue then
        -- Secret value pass-through: use SetFormattedText with the secret value
        -- Per-token coloring via |c..|r escape sequences works alongside % format specifiers
        -- (they operate at different layers: WoW text rendering vs C sprintf)
        local fmtStr = text

        -- Sentinel placeholders and their format specifiers / secret values
        -- Numeric secrets (cooldown/aura times) use the closest pass-through format; string secrets use %s.
        local timeFmt = GetDurationSecretFormatSpec(style)
        local allPlaceholders = SECRET_PLACEHOLDERS
        allPlaceholders[1].val, allPlaceholders[1].fmt = secretValue, timeFmt
        allPlaceholders[2].val, allPlaceholders[2].fmt = secretValue, timeFmt
        allPlaceholders[3].val, allPlaceholders[3].fmt = secretValue, timeFmt
        allPlaceholders[4].val = secretStackValue
        allPlaceholders[5].val = secretNameValue
        allPlaceholders[5].active = hasSecretNameValue

        -- Single left-to-right pass: build format string and ordered args together
        local args = button._textModeSecretArgs
        if args then
            wipe(args)
        else
            args = {}
            button._textModeSecretArgs = args
        end
        local resultParts = button._textModeSecretParts
        if resultParts then
            wipe(resultParts)
        else
            resultParts = {}
            button._textModeSecretParts = resultParts
        end
        local pos = 1
        while pos <= #fmtStr do
            local bestIdx, bestInfo
            for _, info in ipairs(allPlaceholders) do
                if info.active or info.val then
                    local idx = fmtStr:find(info.text, pos, true)
                    if idx and (not bestIdx or idx < bestIdx) then
                        bestIdx = idx
                        bestInfo = info
                    end
                end
            end

            if bestIdx then
                if bestIdx > pos then
                    resultParts[#resultParts + 1] = fmtStr:sub(pos, bestIdx - 1):gsub("%%", "%%%%")
                end
                resultParts[#resultParts + 1] = bestInfo.fmt
                args[#args + 1] = bestInfo.val
                pos = bestIdx + #bestInfo.text
            else
                resultParts[#resultParts + 1] = fmtStr:sub(pos):gsub("%%", "%%%%")
                break
            end
        end

        local finalFmt = table_concat(resultParts)
        fontString:SetFormattedText(finalFmt, unpack(args))
        if shouldStoreTextVisualState then
            StoreTextVisualApplied(button, "formatted", text, secretValue, secretStackValue, hasSecretNameValue)
        end
        wipe(args)
        -- Drop the secret references the shared placeholder table borrowed,
        -- for the same reason the arg list is wiped above.
        allPlaceholders[1].val, allPlaceholders[2].val, allPlaceholders[3].val = nil, nil, nil
        allPlaceholders[4].val, allPlaceholders[5].val = nil, nil
        allPlaceholders[5].active = nil
    else
        -- Normal path: full per-token coloring via escape sequences
        fontString:SetText(text)
        if shouldStoreTextVisualState then
            StoreTextVisualApplied(button, "text", text, secretValue, secretStackValue, hasSecretNameValue)
        end
    end

    return hasSecretNameValue == true
end

local function UpdateTextDisplay(button, secretNameOverride, hasSecretNameOverride)
    local style = button.style
    if not style or not button._textSegments then
        ClearTextVisualState(button)
        return
    end
    local shouldStoreTextVisualState = ShouldStoreTextVisualState()
    if not shouldStoreTextVisualState then
        ClearTextVisualState(button)
    end

    -- Reset pulse content flag before substitution
    local es = button._effectState
    if es then
        es.pulseActive = false
    end

    local plan = button._textRenderPlan
    local secretNameActive
    if plan then
        -- Composite: one run per cc column onto its pooled FontString. The
        -- aura pieces are the client's and are not touched here. The visual
        -- state snapshot (debug-only) records the first column.
        local runs = button._textRunStrings
        local runColumns = plan.runColumns
        secretNameActive = false
        for i = 1, #runColumns do
            local column = runColumns[i]
            if RenderTextRun(button, runs[column.runIndex], column.segments, style, es,
                secretNameOverride, hasSecretNameOverride, shouldStoreTextVisualState and i == 1) then
                secretNameActive = true
            end
        end
        if shouldStoreTextVisualState and #runColumns == 0 then
            ClearTextVisualState(button)
        end
    else
        secretNameActive = RenderTextRun(button, button.textString, button._textSegments, style, es,
            secretNameOverride, hasSecretNameOverride, shouldStoreTextVisualState)
    end
    button._textSecretNameActive = secretNameActive

    -- Apply pulse alpha effect to the FontString(s)
    if es then
        SetTextRunsAlpha(button, es.pulseActive and es.pulseAlpha or 1.0)
    end
    if shouldStoreTextVisualState then
        UpdateTextVisualAppliedPulse(button)
    end

end

------------------------------------------------------------------------
-- EFFECT ANIMATION ONUPDATE (30Hz)
------------------------------------------------------------------------
local EFFECT_INTERVAL = 1 / 30

local function EffectOnUpdate(self, elapsed)
    self._effectElapsed = (self._effectElapsed or 0) + elapsed
    if self._effectElapsed < EFFECT_INTERVAL then return end
    self._effectElapsed = self._effectElapsed - EFFECT_INTERVAL

    local now = GetTime()
    local es = self._effectState
    es.pulseAlpha = ComputePulse(now)

    if self._textSecretNameActive then
        SetTextRunsAlpha(self, es.pulseActive and es.pulseAlpha or 1.0)
        if ShouldStoreTextVisualState() then
            UpdateTextVisualAppliedPulse(self)
        else
            ClearTextVisualState(self)
        end
        return
    end

    UpdateTextDisplay(self)
end

local function InstallEffectOnUpdate(button)
    if HasAnyEffects(button._textSegments) then
        if not button._effectState then
            button._effectState = {}
        end
        local es = button._effectState
        es.pulseAlpha = 1.0
        es.pulseActive = false
        button._effectElapsed = 0
        button:SetScript("OnUpdate", EffectOnUpdate)
    elseif button._effectState then
        button._effectState = nil
        button._effectElapsed = nil
        button:SetScript("OnUpdate", nil)
        SetTextRunsAlpha(button, 1.0)
    end
end

------------------------------------------------------------------------
-- UPDATE TEXT STYLE
-- Called when group style changes (slider drags, config edits).
------------------------------------------------------------------------
local function UpdateTextStyle(button, newStyle)
    button.style = newStyle
    if ClearButtonVisualState then
        ClearButtonVisualState(button)
    end
    ClearTextVisualState(button)
    -- Background
    local bgColor = newStyle.textBgColor or {0, 0, 0, 0}
    button.bg:SetColorTexture(bgColor[1], bgColor[2], bgColor[3], bgColor[4])

    -- Border
    local borderSize = newStyle.textBorderSize or 0
    local borderRenderMode = ST.GetBorderRenderMode(newStyle, "textBorderRenderMode")
    local borderColor = newStyle.textBorderColor or {0, 0, 0, 1}
    for i = 1, 4 do
        button.borderTextures[i]:SetColorTexture(unpack(borderColor))
    end
    ApplyBorderEdgePositions(button.borderTextures, button, borderSize, borderRenderMode)

    -- Font
    local font = CooldownCompanion:FetchFont(newStyle.textFont or "Friz Quadrata TT")
    local fontSize = newStyle.textFontSize or 12
    local fontOutline = ST.GetEffectiveFontOutline(newStyle.textFontOutline or "OUTLINE")
    button.textString:SetFont(font, fontSize, fontOutline)

    -- Alignment
    local align = newStyle.textAlignment or "LEFT"
    button.textString:SetJustifyH(align)

    -- Text shadow
    ST.ApplyFontShadowForOutline(button.textString, fontOutline, newStyle.textShadow == true)

    -- Anchor text within frame respecting border and padding. Same helper the
    -- measurement sizes the box with, so the padding it reserved is the
    -- padding the FontString actually gets on all four sides.
    button.textString:ClearAllPoints()
    local padX, padY = GetTextStringPadding(newStyle, button)
    button.textString:SetPoint("TOPLEFT", padX, -padY)
    button.textString:SetPoint("BOTTOMRIGHT", -padX, padY)

    -- Re-parse format string
    local fmt = button.buttonData.textFormat or newStyle.textFormat or DEFAULT_TEXT_FORMAT
    button._textSegments = ParseFormatString(fmt)
    ApplyTextLayout(button, newStyle, fmt)

    -- Install or remove effect animation OnUpdate
    InstallEffectOnUpdate(button)

end

------------------------------------------------------------------------
-- CREATE TEXT FRAME
------------------------------------------------------------------------
function CooldownCompanion:CreateTextFrame(parent, index, buttonData, style)
    local fmt = buttonData.textFormat or style.textFormat or DEFAULT_TEXT_FORMAT

    -- Provisional size only. Every region created below anchors RELATIVELY to
    -- this frame (bg SetAllPoints, the four border edges through
    -- ApplyBorderEdgePositions, the FontString's TOPLEFT/BOTTOMRIGHT insets),
    -- so they all follow the real SetSize that ApplyTextLayout does at the end
    -- of this function -- after UpdateButtonIcon has assigned the display
    -- identity {name} measures through. Reading the cache directly instead of
    -- calling GetTextEntryMetrics keeps a cold entry from paying for a full
    -- mock render whose numbers are thrown away one measurement later.
    -- GetButtonDimensions runs immediately before this on every path that
    -- creates a text entry, and it measures the panel's baseline (keyed by the
    -- style) and then each entry (keyed by its buttonData), so one of the two
    -- lookups below is normally already warm with the right box.
    local w, h = 1, 1
    local warmMetrics = textMetricsCache[buttonData] or textMetricsCache[style]
    if warmMetrics and warmMetrics.width and warmMetrics.height then
        w, h = warmMetrics.width, warmMetrics.height
    end

    -- Main frame
    local button = CreateFrame("Frame", parent:GetName() .. "Text" .. index, parent)
    button:SetSize(w, h)
    button._isText = true

    -- F6: flatten this text frame's render layers into one render pass
    -- (owner-validated V1-V10: no visual difference).
    button:SetFlattensRenderLayers(true)

    -- Background (sublayer 0)
    local bgColor = style.textBgColor or {0, 0, 0, 0}
    button.bg = button:CreateTexture(nil, "BACKGROUND", nil, 0)
    button.bg:SetAllPoints()
    button.bg:SetColorTexture(bgColor[1], bgColor[2], bgColor[3], bgColor[4])

    -- Border textures
    local borderSize = style.textBorderSize or 0
    local borderRenderMode = ST.GetBorderRenderMode(style, "textBorderRenderMode")
    local borderColor = style.textBorderColor or {0, 0, 0, 1}
    button.borderTextures = {}
    for i = 1, 4 do
        local tex = button:CreateTexture(nil, "OVERLAY")
        tex:SetColorTexture(unpack(borderColor))
        button.borderTextures[i] = tex
    end
    ApplyBorderEdgePositions(button.borderTextures, button, borderSize, borderRenderMode)

    -- Main text FontString
    button.textString = button:CreateFontString(nil, "OVERLAY")
    local font = CooldownCompanion:FetchFont(style.textFont or "Friz Quadrata TT")
    local fontSize = style.textFontSize or 12
    local fontOutline = ST.GetEffectiveFontOutline(style.textFontOutline or "OUTLINE")
    button.textString:SetFont(font, fontSize, fontOutline)
    local baseColor = style.textFontColor or DEFAULT_WHITE
    button.textString:SetTextColor(baseColor[1], baseColor[2], baseColor[3], baseColor[4] or 1)

    local align = style.textAlignment or "LEFT"
    button.textString:SetJustifyH(align)

    -- Text shadow
    ST.ApplyFontShadowForOutline(button.textString, fontOutline, style.textShadow == true)

    -- Same padding the measurement reserved (GetTextStringPadding).
    local padX, padY = GetTextStringPadding(style, button)
    button.textString:SetPoint("TOPLEFT", padX, -padY)
    button.textString:SetPoint("BOTTOMRIGHT", -padX, padY)

    -- Hidden icon (required by UpdateButtonIcon pipeline)
    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetPoint("TOPLEFT", 0, 0)
    button.icon:SetSize(1, 1)
    button.icon:SetAlpha(0)

    -- Hidden cooldown widget (required by CooldownUpdate pipeline for GetCooldownTimes)
    button.cooldown = CreateFrame("Cooldown", button:GetName() .. "Cooldown", button, "CooldownFrameTemplate")
    button.cooldown:SetSize(1, 1)
    button.cooldown:SetPoint("CENTER")
    button.cooldown:SetAlpha(0)
    button.cooldown:SetDrawSwipe(false)
    button.cooldown:SetDrawEdge(false)
    button.cooldown:SetDrawBling(false)
    button.cooldown:SetHideCountdownNumbers(true)
    button.cooldown:Hide()
    SetFrameClickThroughRecursive(button.cooldown, true, true)
    button.cooldown:SetScript("OnCooldownDone", ST.OnButtonCooldownDone)

    -- Charge/item count overlay (hidden, but UpdateChargeTracking writes to button.count)
    button.overlayFrame = CreateFrame("Frame", nil, button)
    button.overlayFrame:SetAllPoints()
    button.overlayFrame:EnableMouse(false)
    button.count = button.overlayFrame:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    button.count:SetText("")
    button.count:SetAlpha(0)  -- Hidden; charge data read from button._currentReadableCharges

    -- Store button data
    button.buttonData = buttonData
    button.index = index
    button.style = style

    -- Cache spell cooldown secrecy level
    if buttonData.type == "spell" then
        buttonData._cooldownSecrecy = C_Secrets.GetSpellCooldownSecrecy(buttonData.id)
    end

    -- Parse format string. The measuring pass is deliberately NOT here: it
    -- runs after UpdateButtonIcon below, which is what assigns the entry's
    -- display identity.
    button._textSegments = ParseFormatString(fmt)

    -- Install effect animation if format uses effect tags
    InstallEffectOnUpdate(button)

    -- Aura tracking runtime state
    button._auraSpellID = CooldownCompanion:ResolveAuraSpellID(buttonData)
    button._auraUnit = buttonData.auraUnit or "player"
    button._auraActive = false
    button._auraTrackingReady = nil
    button._textSecretNameActive = nil

    if IsEntryItemLike(buttonData) then
        local effectiveItem = ResolveEffectiveItem(buttonData, true)
        button._resolvedItemId = effectiveItem and effectiveItem.itemID or buttonData.id
        button._resolvedItemAvailableQuantity = effectiveItem and effectiveItem.availableQuantity or 0
        button._resolvedItemQuantityKind = effectiveItem and effectiveItem.quantityKind or "stacks"
        button._equipmentSlotTrackable = CooldownCompanion.IsEquipmentSlotEntry(buttonData)
            and effectiveItem and effectiveItem.trackable == true or nil
    end

    -- Per-button visibility runtime state
    button._visibilityHidden = false
    button._prevVisibilityHidden = false
    button._visibilityAlphaOverride = nil
    button._lastVisAlpha = 1
    button._groupId = parent.groupId

    -- Methods (same interface as icon/bar buttons)
    button.UpdateCooldown = function(self)
        CooldownCompanion:UpdateButtonCooldown(self)
    end

    button.UpdateStyle = function(self, newStyle)
        UpdateTextStyle(self, newStyle)
    end

    -- Set icon (populates button._displaySpellId, updates button.icon texture)
    self:UpdateButtonIcon(button)

    -- Measure LAST. The box is sized from a worst-case render of the format,
    -- and {name} resolves through button._displaySpellId (set by
    -- UpdateButtonIcon just above) and button._resolvedItemId (set in the
    -- item block above). Measuring before either existed sized every override
    -- spell and every resolved item against the SAVED id's name, so a longer
    -- displayed name overflowed its box for the life of the frame.
    ApplyTextLayout(button, style, fmt)

    -- Click-through (text buttons are non-interactive by default)
    SetFrameClickThroughRecursive(button, true, true)
    SetFrameClickThroughRecursive(button.cooldown, true, true)

    return button
end

------------------------------------------------------------------------
-- EXPORTS
------------------------------------------------------------------------
ST._UpdateTextDisplay = UpdateTextDisplay
ST._ParseFormatString = ParseFormatString
-- (style, buttonData, formatString, button, forceRefresh) -> width, height, lineCount
ST._GetTextEntryMetrics = GetTextEntryMetrics
-- (button) -> groupId when the entry's box changed and its panel needs a
-- re-pitch, nil otherwise. Event-driven invalidation only.
ST._RefreshTextEntryLayout = RefreshTextEntryLayout
-- (button) -> nothing. Immediate re-measure + resize for rebuild paths that
-- re-pitch the panel themselves on the same pass.
ST._ApplyTextEntryLayout = ApplyTextEntryLayout
-- (style, region) -> padX, padY. The config text mirror anchors its replica
-- FontString with the same padding the live renderer uses.
ST._GetTextStringPadding = GetTextStringPadding
-- (style, buttonData, formatString) -> width, height, lineCount, plan,
-- lineHeight. GetTextEntryMetrics plus the cache entry's composite plan and
-- line height (plan is nil for a single-string format). The plan is the SAME
-- object the live entry renders from -- LayoutCompositeText writes its
-- geometry onto these columns and the aura host reads it back -- so a reader
-- must never write to it; the config mirror keeps its own geometry through
-- ComputeTextColumnGeometry's sink.
ST._GetTextRenderPlanMetrics = function(style, buttonData, formatString)
    local width, height, lineCount = GetTextEntryMetrics(style, buttonData, formatString)
    local cached = type(style) == "table" and textMetricsCache[buttonData or style] or nil
    return width, height, lineCount, cached and cached.plan or nil, cached and cached.lineHeight or nil
end
-- (plan, style, lineHeight, boxWidth, region, sink) -> nothing. Read-only
-- geometry walk of a composite plan; the same numbers the live layout writes
-- (see the function's note). The config mirror positions its stand-in
-- FontStrings through the sink.
ST._ComputeTextColumnGeometry = ComputeTextColumnGeometry
-- The placeholder an {icon} bakes into an aura piece when the plan is
-- measured with no button in hand (data-only readers, the config mirror);
-- a live entry bakes its own texture instead.
ST._TEXT_MEASURE_ICON_ESCAPE = MEASURE_ICON_ESCAPE
-- (segments, buttonData, style) -> plan. Pure planner (structure only, no
-- baked strings, no geometry) for the format editor and the config mirror;
-- see the TEXT RENDER PLAN comment for the shape and the advisory flags.
ST._BuildTextRenderPlan = BuildTextRenderPlan
-- (button) -> the button's laid-out live aura pieces as a flat array in
-- format order (kind, prefix, suffix, text, x, y, width, height, justifyH),
-- or nil when the entry is not composite. Core/AuraDisplay's text host reads
-- this at bind time, out of combat; the array is the plan's own and must not
-- be mutated.
ST._GetTextAuraPieces = function(button)
    local plan = button and button._textRenderPlan
    if not plan or not plan.hasAuraPieces then return nil end
    return plan.auraPieces
end
-- (buttonData, style) -> boolean. Data-only: does this entry's format put at
-- least one live aura piece on the client? No button needed, so the rebind
-- pass can decide which text entries get an aura button.
ST._TextEntryHasAuraPieces = function(buttonData, style)
    local fmt = buttonData and buttonData.textFormat
        or (type(style) == "table" and style.textFormat)
        or DEFAULT_TEXT_FORMAT
    return BuildTextRenderPlan(ParseFormatString(fmt), buttonData, style).hasAuraPieces
end
-- (buttonData, style) -> { duration = bool, stacks = bool, presence = bool }.
-- Data-only: which live piece kinds this entry's format puts on the client.
-- The Preview Command Center offers each aura preview only where a matching
-- column exists.
ST._TextEntryAuraPieceKinds = function(buttonData, style)
    local fmt = buttonData and buttonData.textFormat
        or (type(style) == "table" and style.textFormat)
        or DEFAULT_TEXT_FORMAT
    local kinds = { duration = false, stacks = false, presence = false }
    local plan = BuildTextRenderPlan(ParseFormatString(fmt), buttonData, style)
    for _, piece in ipairs(plan.auraPieces) do
        kinds[piece.kind] = true
    end
    return kinds
end

-- Display-identity edge for composite entries. A piece's prefix/suffix
-- bakes the resolved {name} / {keybind} / {icon} at measure time, so a spell
-- transforming into an override, an equipment slot resolving to another
-- item, or a texture swap must re-measure the entry -- the same probe-driven
-- re-read the keybind path uses (Core/Keybinds.lua). Called from
-- UpdateButtonIcon, which runs on those edges (and on SPELL_UPDATE_ICON for
-- every button), so it must stay cheap: a non-composite entry returns at
-- once (its {name} is substituted per tick anyway), and a composite entry
-- whose strings did not move costs the cache's few comparisons.
--
-- The restyle that re-pitches the panel and rebinds the aura button runs
-- AFTER the current walk, never inside it: UpdateGroupStyle can fall back to
-- repopulating the panel, which rebuilds the very button list being
-- iterated. One timer drains every panel touched in the same frame.
local pendingIdentityRelayoutGroups = {}
local identityRelayoutScheduled = false
local function DrainIdentityRelayout()
    identityRelayoutScheduled = false
    for groupId in pairs(pendingIdentityRelayoutGroups) do
        CooldownCompanion:UpdateGroupStyle(groupId)
    end
    wipe(pendingIdentityRelayoutGroups)
end
ST._RequestTextIdentityRelayout = function(button)
    if not (button and button._isText and button._textRenderPlan) then return end
    local groupId = RefreshTextEntryLayout(button)
    if not groupId then return end
    pendingIdentityRelayoutGroups[groupId] = true
    if not identityRelayoutScheduled then
        identityRelayoutScheduled = true
        C_Timer.After(0, DrainIdentityRelayout)
    end
end
-- (button) -> nothing. Pool hygiene for GroupFrame's ClearReusableButtonRuntime:
-- hides and blanks every pooled run string and forgets the plan, so a
-- released text button carries no composite render into its next entry.
ST._ResetTextRunStrings = function(button)
    HideTextRunStrings(button, 1)
    button._textRenderPlan = nil
end
