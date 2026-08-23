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
-- Text panels are AURA-BLIND on 12.1. {aura} is kept as a known token only so
-- saved formats holding it keep parsing instead of degrading to literal
-- braces; it emits nothing (SubstituteTokens below). A client-owned docked
-- readout was trialed and removed by owner decision, so there is deliberately
-- no {aurastacks} token and no reserved space for either.
local KNOWN_TOKENS = {
    name = true,
    time = true,
    charges = true,
    maxcharges = true,
    missingcharges = true,
    zerocharges = true,
    stacks = true,
    aura = true,
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

-- `aura` is kept ONLY so saved {?aura}/{!aura} formats keep parsing as
-- conditionals instead of degrading to literal braces. It can no longer be
-- true: the aura's presence lives entirely on the client now, so
-- EvaluateTokenPresence has nothing to answer with.
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
    -- No {aura} entry: the token renders nothing on 12.1, so it reserves no
    -- width either.
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
            -- tokens SubstituteTokens emits nothing for them either. {aura}
            -- renders nothing at all on 12.1, so it is absent here too.
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

-- Returns width, height, lineCount, provisional. `provisional` means the
-- numbers were measured against a {name} the client had not resolved yet, so
-- the caller must not treat them as final (see GetTextEntryMetrics).
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

    local width, lineCount = MeasureWorstCaseVariant(fs, segments, ctx)

    -- Only a format that actually renders {name} is wrong because of an
    -- unresolved name; every other format measures the same either way.
    local provisional = ctx.namePending == true and FormatHasNameToken(segments)

    -- Same helper the live FontString anchors through, against the measuring
    -- host (see GetTextStringPadding).
    local padX, padY = GetTextStringPadding(style, measureHostFrame)

    local boxWidth = math_max(1, math_ceil(width) + padX * 2)
    local boxHeight = math_max(1, lineCount * lineHeight + padY * 2)

    fs:SetText("")

    return boxWidth, boxHeight, lineCount, provisional
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

    if not forceRefresh and inputsMatch
        and cached.name == probeName
        and cached.keybind == probeKeybind then
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

    local width, height, lineCount, provisional =
        MeasureTextEntry(style, buttonData, fmt, button, identity)

    if not cached then
        cached = {}
        textMetricsCache[cacheKey] = cached
    end
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
    -- The client-resolved half of the inputs, plus the ids they were resolved
    -- through so a later data-only read reproduces the same strings.
    cached.name = probeName
    cached.keybind = probeKeybind
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

local function ApplyTextLayout(button, style, formatString)
    -- Force a re-measure: this is the restyle path, and it is the one place
    -- that re-resolves late-arriving inputs (spell/item name, keybind).
    local width, height, lineCount =
        GetTextEntryMetrics(style, button.buttonData, formatString, button, true)
    local isMultiline = lineCount > 1

    button:SetSize(width, height)
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
    if math_abs(width - currentWidth) < 0.5 and math_abs(height - currentHeight) < 0.5 then
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

local function ColorPrefix(color)
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
        -- Structurally false on 12.1: nothing sets _auraActive true any more
        -- and the aura's remaining duration is the client's, not the addon's.
        -- Kept as a defined answer so legacy {?aura} regions render empty
        -- rather than erroring or falling through to an unknown token.
        return button._auraActive == true or auraIsSecret or (auraRemaining and auraRemaining > 0)
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

            elseif token == "aura" then
                -- Emits NOTHING: text panels are aura-blind on 12.1, which
                -- made the tracked aura's remaining time and stack count
                -- unreadable to the addon. A client-drawn docked readout was
                -- trialed and removed by owner decision, so the token is kept
                -- only to stop saved formats degrading to literal braces.
                -- The config's format editor flags it.

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

    local text, secretValue, secretColorToken, secretStackValue, secretNameValue, hasSecretNameValue = SubstituteTokens(button, button._textSegments, style, es, secretNameOverride, hasSecretNameOverride, shouldStoreTextVisualState)
    button._textSecretNameActive = hasSecretNameValue == true

    if secretValue or secretStackValue or hasSecretNameValue then
        -- Secret value pass-through: use SetFormattedText with the secret value
        -- Per-token coloring via |c..|r escape sequences works alongside % format specifiers
        -- (they operate at different layers: WoW text rendering vs C sprintf)
        local baseColor = style.textFontColor or DEFAULT_WHITE
        button.textString:SetTextColor(baseColor[1], baseColor[2], baseColor[3], baseColor[4] or 1)

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
        button.textString:SetFormattedText(finalFmt, unpack(args))
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
        local baseColor = style.textFontColor or DEFAULT_WHITE
        button.textString:SetTextColor(baseColor[1], baseColor[2], baseColor[3], baseColor[4] or 1)
        button.textString:SetText(text)
        if shouldStoreTextVisualState then
            StoreTextVisualApplied(button, "text", text, secretValue, secretStackValue, hasSecretNameValue)
        end
    end

    -- Apply pulse alpha effect to the FontString
    if es then
        if es.pulseActive then
            button.textString:SetAlpha(es.pulseAlpha)
        else
            button.textString:SetAlpha(1.0)
        end
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
        if es.pulseActive then
            self.textString:SetAlpha(es.pulseAlpha)
        else
            self.textString:SetAlpha(1.0)
        end
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
        button.textString:SetAlpha(1.0)
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
