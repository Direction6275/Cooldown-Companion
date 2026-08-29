--[[
    CooldownCompanion - ResourceBarAuraHost
    Custom-bar hosting for the AuraContainer display (the aura pass, Phase 1)
    and resource-bar aura overlays (Phase 2).

    Bar-mode panels are the reference implementation (Core/AuraDisplay.lua);
    this module owns only what genuinely differs on the custom-bar host:

    * STABLE HOLDERS. Custom-bar frames are abandoned and recreated on type
      changes, but aura display records are permanent (slots can never be
      removed). Each holder is a plain CC frame keyed by customBarId,
      parented ONCE to a stable root and never reparented — the AuraContainer
      created inside it keeps its creation parent forever, the same
      discipline as a panel button's auraLayer. Rebinds only re-ANCHOR the
      holder onto the current bar frame (inset inside the pixel-border ring,
      the panel statusBar-mount contract), so recreation costs nothing.
    * ADAPTERS. AuraDisplay speaks the panel vocabulary (buttonData + style
      keys). The entry adapter and style adapter below synthesize exactly
      those keys from cabConfig + the resource settings; both are PLAIN
      tables (IsBarAuraIndicatorEnabled rawgets). soundAlerts is shared BY
      REFERENCE so the donor's refcounted native sound path reads the custom
      bar's own config unchanged.
    * ABSENT-STATE VISUALS. Two-layer compositing: the CC bar renders the
      aura-absent state (bg/borders, and per-stack capacity blocks for
      segmented stack bars); the kit occludes/overlays it only while the
      aura runs. The stack max is resolved OOC in the rebind pass and cached
      on the barInfo so in-combat re-applies re-lay blocks without touching
      the (restricted) max lookup.

    The rebind pass itself, park/bind, kit styling, sounds, and every slot
    rule stay in Core/AuraDisplay.lua — this module never touches the slot
    subtree. It publishes its want-collector through ST for the rebind pass
    (load-order safe: AuraDisplay looks it up at run time).
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon

local ipairs = ipairs
local pairs = pairs
local tonumber = tonumber
local tostring = tostring
local table_concat = table.concat
local math_min = math.min
local CreateFrame = CreateFrame

local RB = ST._RB

function RB.CreateResourceBarAuraHostModule(deps)
    local resourceBarFrames = deps.resourceBarFrames

    local GetResourceBarSettings = RB.GetResourceBarSettings
    local GetSpecLayoutOrder = RB.GetSpecLayoutOrder
    local GetResourceDisplayValue = RB.GetResourceDisplayValue
    local GetResolvedCustomAuraBarAuraUnit = RB.GetResolvedCustomAuraBarAuraUnit
    local IsSpellCustomBarConfig = RB.IsSpellCustomBarConfig
    local GetCustomBarCachedStackMax = RB.GetCustomBarCachedStackMax
    local SetCustomBarCachedStackMax = RB.SetCustomBarCachedStackMax
    local GetResourceSegmentedSmoothing = RB.GetResourceSegmentedSmoothing
    local HidePixelBorders = RB.HidePixelBorders
    local GetActiveResourceAuraEntry = RB.GetActiveResourceAuraEntry
    local IsResourceAuraOverlayEnabled = RB.IsResourceAuraOverlayEnabled
    local GetResourceAuraTrackingMode = RB.GetResourceAuraTrackingMode
    local SupportsResourceAuraStackMode = RB.SupportsResourceAuraStackMode
    local IsVerticalResourceLayout = RB.IsVerticalResourceLayout
    local IsVerticalFillReversed = RB.IsVerticalFillReversed
    local DEFAULT_RESOURCE_AURA_ACTIVE_COLOR = RB.DEFAULT_RESOURCE_AURA_ACTIVE_COLOR

    local DEFAULT_RESOURCE_TEXT_FONT = RB.DEFAULT_RESOURCE_TEXT_FONT
    local DEFAULT_RESOURCE_TEXT_SIZE = RB.DEFAULT_RESOURCE_TEXT_SIZE
    local DEFAULT_RESOURCE_TEXT_OUTLINE = RB.DEFAULT_RESOURCE_TEXT_OUTLINE
    local DEFAULT_RESOURCE_TEXT_COLOR = RB.DEFAULT_RESOURCE_TEXT_COLOR

    -- Root + holders. The root is the single stable parent for every holder;
    -- its shown state follows the applied state of the resource bars and its
    -- alpha rides the same writes as the resource containers (ResourceBar.lua
    -- alpha branches include it), so kit visuals fade and hide with the bars
    -- they decorate without any per-tick sync.
    local hostRoot
    local holders = {} -- customBarId -> holder frame

    local function GetAuraHostRoot()
        if not hostRoot then
            hostRoot = CreateFrame("Frame", nil, UIParent)
            hostRoot:SetFrameStrata("MEDIUM")
            hostRoot:SetSize(1, 1)
            hostRoot:SetPoint("CENTER")
            hostRoot:EnableMouse(false)
            hostRoot:Hide()
        end
        return hostRoot
    end

    local function SetAuraHostRootApplied(applied)
        GetAuraHostRoot():SetShown(applied == true)
    end

    -- Holder = the aura host frame AuraDisplay mounts a display on. It
    -- presents the host-button field interface the donor reads for bar
    -- hosts: _isBar, _isVertical, statusBar (the mount rect — the holder
    -- itself), and the click-through motion tag (resource bars never show
    -- aura tooltips).
    local function EnsureHolder(customBarId)
        local holder = holders[customBarId]
        if not holder then
            holder = CreateFrame("Frame", nil, GetAuraHostRoot())
            holder:EnableMouse(false)
            holder._ccAuraHostKind = "customBar"
            holder._isBar = true
            holder.statusBar = holder
            holder._cdcClickThroughMotion = true
            -- The bar's FULL footprint (the holder itself mounts inside the
            -- border ring). The kit's shell replicas anchor here instead of
            -- to the bar frame: bar frames are slot-position recycled, so a
            -- custom bar is handed a different one whenever the stack grows
            -- or shrinks — and those replicas live in the slot subtree,
            -- which cannot be re-anchored in combat. This frame is CC-owned
            -- and its identity never changes.
            holder._ccBounds = CreateFrame("Frame", nil, holder)
            holder._ccBounds:EnableMouse(false)
            holder._barBounds = holder._ccBounds
            holders[customBarId] = holder
        end
        return holder
    end

    -- All holder geometry in one place: the mount rect inside the border
    -- ring, the full-footprint bounds child, orientation, and level. Plain
    -- CC frames throughout — nothing here reaches the slot subtree, so it
    -- is equally valid in combat.
    -- levelOffset: how far above the bar frame the kit renders. Custom bars
    -- use 3 (their textLayer sits at bar+2, and everything CC draws on a
    -- custom bar lives at or below it — the kit MUST keep occluding CC's
    -- spell-bar cooldown text, which CC writes per tick with no way to know
    -- an aura is showing). Resource bars stack taller — segment children at
    -- +3, MW overlay segments at +4 — so a resource holder at +3 would
    -- render UNDERNEATH the very segments it decorates. They pass 9 (see
    -- HOLDER_LEVEL_RESOURCE). Resource TEXT is the one thing above either
    -- kit: it bands at RESOURCE_TEXT_LAYER_LEVEL, past the tallest
    -- holder's reserved strata span, so it survives font-size spill onto a
    -- neighboring bar (owner ruling: text > borders/glows > fills).
    local function AnchorHolderToBar(holder, frame, inset, levelOffset)
        holder:ClearAllPoints()
        holder:SetPoint("TOPLEFT", frame, "TOPLEFT", inset, -inset)
        holder:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -inset, inset)
        local bounds = holder._ccBounds
        bounds:ClearAllPoints()
        bounds:SetPoint("TOPLEFT", holder, "TOPLEFT", -inset, inset)
        bounds:SetPoint("BOTTOMRIGHT", holder, "BOTTOMRIGHT", inset, -inset)
        holder._isVertical = frame._isVertical == true
        -- The kit must render over every CC-side bar visual. Same-strata
        -- level ordering; the root already matches the resource containers'
        -- MEDIUM strata.
        holder:SetFrameLevel(frame:GetFrameLevel() + (levelOffset or 3))
        holder._ccAnchoredFrame = frame
        -- The holder's rect dims, from the bar's explicit size: dash-based
        -- kit effects bake geometry at style time, and a freshly-anchored
        -- holder reports last frame's rect (the lane lesson). Read by the
        -- kit glow's dashes leg via _ccKitRectW/H.
        local fw, fh = frame:GetSize()
        local w = (fw or 0) - inset * 2
        local h = (fh or 0) - inset * 2
        holder._ccKitRectW = w > 1 and w or 1
        holder._ccKitRectH = h > 1 and h or 1
    end

    ------------------------------------------------------------------------
    -- Geometry: the border inset. Resource pixel borders draw INSIDE the
    -- bar rect on an overlay layer; the kit renders at a higher frame level
    -- and would cover them, so the holder mounts inset by the border layout
    -- size — the CC border ring stays visible around the aura display,
    -- exactly like the panel statusBar mount.
    ------------------------------------------------------------------------

    local function GetCustomBarBorderInset(settings)
        local borderStyle = GetResourceDisplayValue(settings, "borderStyle", "pixel")
        if borderStyle ~= "pixel" then
            return 0
        end
        local borderSize = GetResourceDisplayValue(settings, "borderSize", 1)
        local renderMode = ST.GetEffectiveBorderRenderMode(
            GetResourceDisplayValue(settings, "borderRenderMode", ST.BORDER_RENDER_MODE_CUSTOM),
            nil, borderSize)
        return ST.GetBorderLayoutSize(GetAuraHostRoot(), borderSize, renderMode)
    end

    -- The inset rect: a plain child frame of the bar carrying the holder's
    -- exact geometry, so CC-side absent-state visuals (capacity blocks) and
    -- the kit fill above them always align. Re-anchored on every pass —
    -- plain CC frames, safe in combat.
    local function EnsureInsetRect(barFrame, inset)
        local rect = barFrame._ccCabInsetRect
        if not rect then
            rect = CreateFrame("Frame", nil, barFrame)
            rect:EnableMouse(false)
            barFrame._ccCabInsetRect = rect
        end
        rect:ClearAllPoints()
        rect:SetPoint("TOPLEFT", barFrame, "TOPLEFT", inset, -inset)
        rect:SetPoint("BOTTOMRIGHT", barFrame, "BOTTOMRIGHT", -inset, inset)
        return rect
    end

    ------------------------------------------------------------------------
    -- Adapters
    ------------------------------------------------------------------------

    local function IsAuraTrackedCustomBar(cabConfig)
        if type(cabConfig) ~= "table" or not tonumber(cabConfig.spellID) then
            return false
        end
        if IsSpellCustomBarConfig(cabConfig) then
            return cabConfig.auraTracking == true
        end
        return true
    end

    -- Stack-mode resolution, mirroring the helpers' trackingMode contract:
    -- aura entries default to "stacks", spell entries to "active" (duration).
    local function WantsStackMode(cabConfig, isSpellBar)
        local mode = cabConfig.trackingMode
        if mode ~= "active" and mode ~= "stacks" then
            mode = isSpellBar and "active" or "stacks"
        end
        return mode == "stacks"
    end

    -- cabConfig -> the buttonData vocabulary Core/Aura.lua and the kit read.
    -- Plain snapshot table, rebuilt every rebind (config-change frequency).
    local function BuildEntryAdapter(cabConfig, settings)
        local isSpellBar = IsSpellCustomBarConfig(cabConfig)
        local layout = GetSpecLayoutOrder(settings)
        local stackDisplayMode = cabConfig.displayMode == "continuous" and "continuous" or nil
        -- Stack text formatter options live in cab.auraBar under the panel
        -- key names (the shared config rows write them there), so the policy
        -- resolver and kit renderers read the adapter unchanged.
        local cabAuraBar = type(cabConfig.auraBar) == "table" and cabConfig.auraBar or nil
        return {
            type = "spell",
            id = tonumber(cabConfig.spellID),
            addedAs = (not isSpellBar) and "aura" or nil,
            auraTracking = true,
            auraSpellID = cabConfig.auraSpellID,
            -- User overrides (panel parity 2026-08-28): the shared
            -- resolvers and ResolveEntryAuraUnits read them off this
            -- adapter exactly as off a panel entry. Every cab synthetic
            -- carries both keys (see GetDefaultSpellCustomBarAuraUnit) so
            -- block and slot paths cannot disagree.
            auraUnitOverride = cabConfig.auraUnitOverride,
            auraIDOverride = tonumber(cabConfig.auraIDOverride),
            auraUnit = GetResolvedCustomAuraBarAuraUnit(cabConfig, tonumber(cabConfig.spellID)),
            -- No pandemicMarker field: the marker gate reads the STYLE side
            -- only now, where BuildStyleAdapter turns this bar's own key into
            -- a mode. A field no reader consumes would only look live.
            hideWhileAuraNotActive = cabConfig.hideWhenInactive == true,
            auraShellDim = cabConfig.auraShellDim == true or nil,
            -- Scope opt-ins ride the shared rebind-pass unit resolution
            -- (ResolveEntryAuraUnits): wants leave unit nil, so group fan-out,
            -- the pet-wins backstop, and the harmful-ignores-scope rule all
            -- apply exactly as they do to panel entries.
            auraTrackGroup = cabConfig.auraTrackGroup == true or nil,
            auraTrackPet = cabConfig.auraTrackPet == true or nil,
            -- Shared BY REFERENCE: GetButtonSoundAlertConfig and
            -- GetCustomBarSoundAlertConfig read the identical .soundAlerts
            -- shape, so the donor's native aura sound path works unchanged.
            soundAlerts = cabConfig.soundAlerts,
            auraBar = {
                mode = WantsStackMode(cabConfig, isSpellBar) and "stacks" or "duration",
                -- Overlay is not carried forward (owner ruling: panel parity
                -- only); anything but "continuous" takes the segmented
                -- default through the panel normalizer.
                stackDisplayMode = stackDisplayMode,
                segmentGap = (layout and layout.segmentGap) or settings.segmentGap or 4,
                segmentedSmoothing = GetResourceSegmentedSmoothing(settings),
                showCountAtOne = cabAuraBar and cabAuraBar.showCountAtOne or nil,
                thresholdValue = cabAuraBar and cabAuraBar.thresholdValue or nil,
                thresholdColor = cabAuraBar and cabAuraBar.thresholdColor or nil,
                maxColorEnabled = cabAuraBar and cabAuraBar.maxColorEnabled or nil,
                maxColor = cabAuraBar and cabAuraBar.maxColor or nil,
                blockGap = cabAuraBar and cabAuraBar.blockGap or nil,
            },
        }
    end

    local function ResolveCustomBarFont(cabConfig, prefix)
        local color = cabConfig[prefix .. "FontColor"]
        if type(color) ~= "table" or color[1] == nil or color[2] == nil or color[3] == nil then
            color = DEFAULT_RESOURCE_TEXT_COLOR
        end
        return cabConfig[prefix .. "Font"] or DEFAULT_RESOURCE_TEXT_FONT,
            tonumber(cabConfig[prefix .. "FontSize"]) or DEFAULT_RESOURCE_TEXT_SIZE,
            cabConfig[prefix .. "FontOutline"] or DEFAULT_RESOURCE_TEXT_OUTLINE,
            color
    end

    -- The custom bar's two flat marker keys as the one style mode the engine
    -- reads. The panel-shaped kill switch is asked FIRST and only ever says
    -- "off": it outranked the entry checkbox before the enum existed, which is
    -- the precedence the panel resolver and the migration's own
    -- PandemicMarkerKilledFor both keep. Below it the entry key is this bar's
    -- own switch (the bar IS the entry), so an explicit true/false becomes an
    -- explicit mode; everything else is the unit default. Shared with the
    -- config panel so its preview gate asks the same question the bind gate
    -- will answer.
    function RB.GetCustomBarPandemicMarkerMode(cabConfig)
        if type(cabConfig) ~= "table" then return "auto" end
        if cabConfig.pandemicMarkerEnabled == false then return "off" end
        if cabConfig.pandemicMarker ~= nil then
            return cabConfig.pandemicMarker == true and "on" or "off"
        end
        return "auto"
    end

    -- The marker preview gate for a custom bar. A cab has no style table, so
    -- every preview surface used to hand the cab in as its own style; the gate
    -- is style-only now, so the translation happens here instead and there is
    -- still ONE definition of "is the marker on".
    function CooldownCompanion:IsCustomBarPandemicMarkerPreviewWanted(cabConfig)
        if type(cabConfig) ~= "table" then return false end
        return self:IsPandemicMarkerPreviewWanted(cabConfig,
            { pandemicMarkerMode = RB.GetCustomBarPandemicMarkerMode(cabConfig) })
    end

    -- cabConfig + resource settings -> the StyleSlotKit vocabulary. Every
    -- key here was traced to its kit read (StyleSlotKit / StyleActiveBarFill
    -- / StyleKitBarGlowRegions / ApplyFontStyle); do not add keys the kit
    -- does not read.
    local function BuildStyleAdapter(cabConfig, settings)
        local style = {}

        -- Geometry / chrome (kit backdrop stripes, shell replicas, block
        -- borders): the custom bar renders with the resource cluster's own
        -- texture, background, and border settings.
        style.barTexture = GetResourceDisplayValue(settings, "barTexture", "Solid")
        style.barBgColor = GetResourceDisplayValue(settings, "backgroundColor", { 0, 0, 0, 0.5 })
        style.backgroundColor = style.barBgColor
        local borderStyle = GetResourceDisplayValue(settings, "borderStyle", "pixel")
        style.borderColor = GetResourceDisplayValue(settings, "borderColor", { 0, 0, 0, 1 })
        style.borderSize = borderStyle == "pixel" and GetResourceDisplayValue(settings, "borderSize", 1) or 0
        style.borderRenderMode = GetResourceDisplayValue(settings, "borderRenderMode", ST.BORDER_RENDER_MODE_CUSTOM)

        -- Fill: StyleActiveBarFill reads barAuraColor as THE fill color (the
        -- kit fill only exists while the aura runs). Unconditional, like the
        -- panels — never gated on the indicator toggle (that gate ate the
        -- configured aura color during 1B validation). An explicit
        -- barAuraColor always wins; without one, aura entries default to
        -- the bar's own color (the fill IS the bar) and spell entries to
        -- the kit's green aura-drain default (nil → StyleActiveBarFill).
        if cabConfig.barAuraColor then
            style.barAuraColor = cabConfig.barAuraColor
        elseif not IsSpellCustomBarConfig(cabConfig) then
            style.barAuraColor = cabConfig.barColor or { 0.5, 0.5, 1, 1 }
        end
        -- Overwritten by the collector from the live frame's fill direction.
        style.barReverseFill = false

        -- Active-aura effects: cabConfig already speaks the barAura* family;
        -- pass-through so the kit glow and fill animators read it natively.
        style.barAuraIndicatorEnabled = rawget(cabConfig, "barAuraIndicatorEnabled")
        style.barAuraEffect = cabConfig.barAuraEffect
        style.barAuraEffectColor = cabConfig.barAuraEffectColor
        style.barAuraEffectSize = cabConfig.barAuraEffectSize
        style.barAuraEffectSpeed = cabConfig.barAuraEffectSpeed
        style.barAuraEffectLines = cabConfig.barAuraEffectLines
        style.barAuraEffectThickness = cabConfig.barAuraEffectThickness
        style.barAuraPulseEnabled = cabConfig.barAuraPulseEnabled
        style.barAuraPulseSpeed = cabConfig.barAuraPulseSpeed
        style.barAuraColorShiftEnabled = cabConfig.barAuraColorShiftEnabled
        style.barAuraColorShiftColor = cabConfig.barAuraColorShiftColor
        style.barAuraColorShiftSpeed = cabConfig.barAuraColorShiftSpeed

        -- Texts: the custom-bar duration/stack text config maps onto the
        -- auraText/auraStack font families ApplyFontStyle reads.
        style.auraTextFont, style.auraTextFontSize, style.auraTextFontOutline, style.auraTextFontColor =
            ResolveCustomBarFont(cabConfig, "durationText")
        style.auraStackFont, style.auraStackFontSize, style.auraStackFontOutline, style.auraStackFontColor =
            ResolveCustomBarFont(cabConfig, "stackText")
        style.showAuraText = cabConfig.showDurationText == true
        -- Duration Format + Low Time Threshold: the kit's SetDurationText bind
        -- resolves the same shared policy the bar's CC-side cooldown phase and
        -- preview read off the cab config.
        style.durationFormat = cabConfig.durationFormat
        style.decimalTimers = cabConfig.decimalTimers
        style.durationLowTimeThreshold = cabConfig.durationLowTimeThreshold
        style.durationLowTimeDecimals = cabConfig.durationLowTimeDecimals
        style.durationLowTimeColor = cabConfig.durationLowTimeColor
        style.durationLowTimeThreshold2 = cabConfig.durationLowTimeThreshold2
        style.durationLowTimeColor2 = cabConfig.durationLowTimeColor2
        -- Stack text resolution mirrors StyleCustomAuraBar's compat rule:
        -- stacks-mode bars with no explicit showStackText fall back to the
        -- legacy showText flag.
        -- The legacy flag only ever meant stack text on stacks-mode bars, so
        -- the fallback carries that gate too: without it a duration bar with
        -- an old showText would render a stack count AND push its duration
        -- text off center (the kit splits the placement when both show).
        local showStack = cabConfig.showStackText
        if IsSpellCustomBarConfig(cabConfig) then
            showStack = showStack == true
        elseif showStack == nil then
            showStack = WantsStackMode(cabConfig, false) and cabConfig.showText == true
        end
        style.showAuraStackText = showStack == true

        -- Custom bars have no icon square, name text, or keybind replica.
        style.showBarIcon = false
        style.showBarNameText = false
        style.showKeybindText = false

        -- Pandemic marker: the engine gate is style-only now (owner ruling
        -- 2026-08-16), so this is where the custom bar's two flat keys become
        -- the panel vocabulary's one mode. The styling keys follow the
        -- cabConfig pandemicMarker* family when set.
        style.pandemicMarkerMode = RB.GetCustomBarPandemicMarkerMode(cabConfig)
        style.pandemicMarkerText = cabConfig.pandemicMarkerText
        style.pandemicMarkerColor = cabConfig.pandemicMarkerColor
        style.pandemicMarkerColorMode = cabConfig.pandemicMarkerColorMode

        -- Pandemic fill recolor (PTR 8 Phase 2): synthesized from the
        -- entry's FRESH keys — the entry-level showPandemicGlow /
        -- barPandemicColor names are import-retired and must never come
        -- back; this throwaway snapshot may speak the kit's style
        -- vocabulary safely because it is never stored.
        style.pandemicEffectEnabled = cabConfig.pandemicEffect == true
        style.barPandemicColor = cabConfig.pandemicColor

        return style
    end

    ------------------------------------------------------------------------
    -- CC-side absent-state stack blocks (segmented stack bars): the always-
    -- shown layer under the kit's atlas fill. The stack max is resolved OOC
    -- by the rebind collector and cached on the barInfo, so in-combat
    -- re-applies re-lay from the cache without touching the restricted max
    -- lookup. Layout runs after ClearStaleRecycledBarRuntimeState hid the
    -- pools (FinalizeAppliedBarVisibility calls this at the end of each
    -- apply iteration).
    ------------------------------------------------------------------------

    -- opts (config preview only): includeShell keeps the blocks for a
    -- hideWhenInactive bar, which the live bar never draws — the config
    -- canvas renders shell bars so they stay visible and editable.
    -- maxStacks supplies a max the shared runtime cache does not hold
    -- (a bar the config shows but no live slot is currently running).
    local function WantsAbsentStackBlocks(barInfo, opts)
        local cabConfig = barInfo and barInfo.cabConfig
        if not (cabConfig and barInfo.customBarId) then return nil end
        if IsSpellCustomBarConfig(cabConfig) then return nil end
        if cabConfig.hideWhenInactive == true and not (opts and opts.includeShell) then
            return nil -- shell: kit renders the whole bar
        end
        if not WantsStackMode(cabConfig, false) then return nil end
        if cabConfig.displayMode == "continuous" then return nil end
        local max = (opts and opts.maxStacks) or GetCustomBarCachedStackMax(barInfo)
        if not max or max <= 1 or max > ST.STACK_SEGMENT_ATLAS_MAX then return nil end
        return max
    end

    -- Where this bar's aura visuals mount. Normally inside the border ring,
    -- so the CC ring stays visible around the aura display (the panel
    -- statusBar-mount contract). A stacks-mode bar has NO whole-bar ring —
    -- owner ruling: the blocks and their per-block rings are the bar, and
    -- the outer ring comes off — so reserving space for it left the blocks
    -- short of the bar's edges with a dead margin around them. Those bars
    -- mount at the full rect instead. The kit fill uses this same answer,
    -- so it keeps landing exactly on the blocks beneath it.
    -- includeShell here, unlike the absent-state pass: a Show Only While
    -- Aura Active bar draws no blocks of its own (the kit renders the whole
    -- bar), but it is still a stacks bar with no whole-bar ring — its CC
    -- frame sits at alpha 0, so the reserved ring space was a margin around
    -- nothing, and its kit blocks stopped short of the bar's real edges
    -- while an identical non-shell bar's reached them.
    local function GetCustomBarHolderInset(barInfo, borderInset)
        if WantsAbsentStackBlocks(barInfo, { includeShell = true }) then
            return 0
        end
        return borderInset
    end

    -- Does this bar render as capacity blocks rather than as one fill? The
    -- config canvas asks before painting a preview: on a block bar the blocks
    -- ARE the bar, and a status-bar fill would draw straight over them.
    function RB.WantsCustomBarStackBlocks(barInfo, opts)
        return WantsAbsentStackBlocks(barInfo, opts)
    end

    -- The block textures a stacks bar currently renders as, for canvas
    -- overlays that must hug the blocks instead of the whole bar rect (the
    -- layout preview's bucket wash). Nil when the bar renders as one fill.
    function RB.GetCustomBarActiveStackBlocks(barInfo)
        local frame = barInfo and barInfo.frame
        if not (frame and frame._ccCabStackBlocksActive) then return nil end
        return frame._ccCabStackBlocks
    end

    local function ApplyCustomBarAbsentStackVisuals(barInfo, settings, opts)
        local frame = barInfo and barInfo.frame
        if not frame then return end
        local max = WantsAbsentStackBlocks(barInfo, opts)
        if not max then
            frame._ccCabPreviewLitStacks = nil
            frame._ccCabPreviewLitStackMax = nil
            if frame._ccCabStackBlocksActive then
                frame._ccCabStackBlocksActive = nil
                ST.HideStackBlocks(frame._ccCabStackBlocks)
                ST.HideStackBlockBorders(frame._ccCabStackBlockBorders)
            end
            -- Unconditional restore: blocks-mode zeroes the bg region alpha
            -- and ClearStaleRecycledBarRuntimeState clears the flag before
            -- this runs, so a mode switch back to duration would otherwise
            -- leave the background dark. Prepare re-applies the pixel
            -- borders itself; region alpha 1 is the untouched default.
            if frame.bg then
                frame.bg:SetAlpha(1)
            end
            return
        end

        settings = settings or GetResourceBarSettings()
        if not settings then return end
        -- Full rect, no border inset: the blocks ARE the bar here (see
        -- GetCustomBarHolderInset), so they run edge to edge and their
        -- per-block rings draw inside them, exactly as every other CC bar
        -- draws its ring inside its own fill.
        local rect = EnsureInsetRect(frame, 0)

        local blocks = frame._ccCabStackBlocks
        if not blocks then
            blocks = {}
            frame._ccCabStackBlocks = blocks
        end
        for i = #blocks + 1, max do
            local tex = frame:CreateTexture(nil, "BACKGROUND")
            tex:SetAlpha(0)
            blocks[i] = tex
        end
        local borders = frame._ccCabStackBlockBorders
        if not borders then
            borders = {}
            frame._ccCabStackBlockBorders = borders
        end
        for i = #borders + 1, max do
            local set = {}
            for edge = 1, 4 do
                local tex = frame:CreateTexture(nil, "OVERLAY", nil, 2)
                tex:SetAlpha(0)
                set[edge] = tex
            end
            borders[i] = set
        end

        local style = BuildStyleAdapter(barInfo.cabConfig, settings)
        -- Occlusion-free host: these blocks ARE the bar's background, so
        -- they carry the configured background alpha instead of the panel
        -- callers' forced-opaque occlusion default.
        local bgColor = style.barBgColor or { 0, 0, 0, 0.5 }
        -- The rect is the bar's full rect, so a caller-supplied bar length
        -- is the block run's length unchanged.
        local rectLength = opts and opts.barLength or nil
        ST.LayoutStackBlocks(blocks, rect, max, frame._isVertical, bgColor, bgColor[4] or 1, rectLength,
            CooldownCompanion:GetAuraStackBlockGapTexels(barInfo.cabConfig, max) / 512)
        -- litStacks (config preview only): the Active Aura stand-in. On a
        -- live bar the kit paints its atlas fill over these same blocks; with
        -- no kit on the canvas, CC lights them itself, in the same colour the
        -- kit's stack fill uses.
        local lit = opts and tonumber(opts.litStacks) or nil
        frame._ccCabPreviewLitStacks = nil
        frame._ccCabPreviewLitStackMax = nil
        if lit and lit > 0 then
            local pandemicActive = opts and opts.pandemicActive == true
            local auraColor = pandemicActive
                and (style.barPandemicColor or { 1, 0.5, 0, 1 })
                or (style.barAuraColor or { 0.2, 1.0, 0.2, 1.0 })
            -- Reverse fill starts the lit run at the opposite physical end,
            -- so each block maps to its LOGICAL stack before lighting
            -- (review 2026-08-15: the run landed on the wrong end of
            -- reversed bars).
            local reverse = frame.GetReverseFill and frame:GetReverseFill() == true
            lit = math_min(lit, max)
            frame._ccCabPreviewLitStacks = lit
            frame._ccCabPreviewLitStackMax = max
            for i = 1, max do
                local logical = reverse and (max - i + 1) or i
                local tex = logical <= lit and blocks[i] or nil
                if tex then
                    tex:SetColorTexture(
                        auraColor[1] or 0.2,
                        auraColor[2] or 1.0,
                        auraColor[3] or 0.2,
                        pandemicActive and 1
                            or (auraColor[4] ~= nil and auraColor[4] or 1)
                    )
                end
            end
        end
        ST.LayoutStackBlockBorders(borders, blocks, max, style)
        -- Owner ruling (panel parity): each stack is its own widget — the
        -- background slab and the whole-bar border ring come off; the blocks
        -- and their per-block rings are the bar.
        frame.bg:SetAlpha(0)
        if frame.borders then
            HidePixelBorders(frame.borders)
        end
        frame._ccCabStackBlocksActive = true
    end

    ------------------------------------------------------------------------
    -- Resource-bar aura overlays (Phase 2). Same holder discipline as the
    -- custom bars, keyed by powerType — the stable resource identity (bar
    -- frames and barInfo tables are recycled by stack position, so nothing
    -- here may key on a slot). One overlay entry per resource per spec,
    -- read through the surviving scoped keys (auraOverlayEntries family);
    -- the kit renders the chosen shapes, all Blizzard-driven.
    ------------------------------------------------------------------------

    local resourceHolders = {} -- powerType -> holder frame

    -- Shared with the config canvas, which stands the overlay in at the
    -- same height (see the constant for what it has to clear).
    local HOLDER_LEVEL_RESOURCE = RB.RESOURCE_OVERLAY_HOLDER_LEVEL

    local RESOURCE_OVERLAY_BAR_TYPES = {
        continuous = true,
        segmented = true,
        mw_segmented = true,
        mw_segments = true,
        mw_continuous = true,
        stackaura_segments = true,
        stackaura_continuous = true,
        stagger_continuous = true,
    }

    -- Bar shapes drawn as a row of separate segment widgets. They have no
    -- whole-bar border ring for the holder to sit inside (each segment
    -- carries its own) and the stack lane must span the whole cluster, so
    -- they mount at the full rect — which is also what makes the aura
    -- border wrap the entire cluster as one rect (owner ruling 2026-08-02,
    -- reversing the same day's per-segment ruling: the border runs over
    -- the whole bar as if it were continuous, on every shape).
    local SEGMENT_CLUSTER_BAR_TYPES = {
        segmented = true,
        mw_segmented = true,
        mw_segments = true,
        stackaura_segments = true,
    }

    local function EnsureResourceHolder(powerType)
        local holder = resourceHolders[powerType]
        if not holder then
            holder = CreateFrame("Frame", nil, GetAuraHostRoot())
            holder:EnableMouse(false)
            holder._ccAuraHostKind = "resourceBar"
            holder._isBar = true
            holder.statusBar = holder
            holder._cdcClickThroughMotion = true
            holder._ccBounds = CreateFrame("Frame", nil, holder)
            holder._ccBounds:EnableMouse(false)
            holder._barBounds = holder._ccBounds
            -- The fill proxy: a holder-owned anchor relay between the slot
            -- kit's tint (write-locked in combat) and the live bar's fill
            -- texture (a combat-time apply can abandon and recreate the
            -- bar). The tint binds to the PROXY once per OOC bind; the
            -- proxy is a plain CC frame, so the combat-safe anchor sync
            -- re-points it at a replacement bar's fill without touching
            -- the registered subtree.
            holder._ccFillProxy = CreateFrame("Frame", nil, holder)
            holder._ccFillProxy:EnableMouse(false)
            resourceHolders[powerType] = holder
        end
        return holder
    end

    -- Where a resource holder mounts. Continuous-style bars carry their own
    -- pixel-border ring inside the bar rect, so the holder insets to keep
    -- the ring visible (the panel statusBar-mount contract). Segment
    -- clusters draw their rings per segment — the cluster frame has no ring
    -- of its own, and the stack lane must span the whole cluster (owner
    -- ruling), so those mount at the full rect.
    local function GetResourceHolderInset(barInfo, borderInset)
        if SEGMENT_CLUSTER_BAR_TYPES[barInfo.barType] then
            return 0
        end
        return borderInset
    end

    -- Point one holder's fill proxy at the live bar's fill texture. Plain
    -- CC anchor writes, legal in combat — this is what keeps the tint on
    -- the CURRENT fill through a combat-time slot recycle. Bar types with
    -- no single fill just clear the proxy; the tint is off for them.
    local function AnchorResourceFillProxy(holder, frame, barType)
        local proxy = holder and holder._ccFillProxy
        if not proxy then return end
        local fillTex = RB.ResourceOverlayFillSupportsBarType(barType)
            and frame and frame.GetStatusBarTexture
            and frame:GetStatusBarTexture() or nil
        proxy:ClearAllPoints()
        if fillTex then
            proxy:SetPoint("TOPLEFT", fillTex, "TOPLEFT", 0, 0)
            proxy:SetPoint("BOTTOMRIGHT", fillTex, "BOTTOMRIGHT", 0, 0)
        end
    end

    local function IsLiveResourceAuraHolderBar(barInfo, settings)
        local frame = barInfo and barInfo.frame
        local powerType = barInfo and barInfo.powerType
        if not (frame and frame:IsShown() and powerType ~= nil
            and RESOURCE_OVERLAY_BAR_TYPES[barInfo.barType]) then
            return false
        end
        local resource = settings and settings.resources and settings.resources[powerType]
        local entry = resource and IsResourceAuraOverlayEnabled(resource)
            and GetActiveResourceAuraEntry(resource) or nil
        local auraSpellID = entry and tonumber(entry.auraColorSpellID) or nil
        return auraSpellID ~= nil and auraSpellID > 0
    end

    -- Whether the entry draws the aura border. On unless explicitly
    -- switched off (nil = on), so pre-toggle configs keep their border with
    -- no migration. Shared with the config panel and the preview stand-in.
    function RB.IsResourceOverlayBorderEnabled(entry)
        return not (type(entry) == "table" and entry.auraBorderEnabled == false)
    end

    -- The stack lane's fill colour. Its own key (owner ruling 2026-08-02:
    -- border and lane are separate systems, each with its own colour),
    -- falling back to the border colour so pre-split configs keep their
    -- look with no migration. Shared with the config panel and the preview
    -- stand-in.
    function RB.GetResourceOverlayLaneColor(entry)
        local color = type(entry) == "table" and entry.auraLaneColor or nil
        if type(color) == "table" and color[1] ~= nil and color[2] ~= nil and color[3] ~= nil then
            return color
        end
        color = type(entry) == "table" and entry.auraActiveColor or nil
        if type(color) == "table" and color[1] ~= nil and color[2] ~= nil and color[3] ~= nil then
            return color
        end
        return DEFAULT_RESOURCE_AURA_ACTIVE_COLOR
    end

    -- The fill tint (the pre-12.1 "active recolor" revival, probe-validated
    -- 2026-08-28). Own enable and colour keys, per the border/lane rule:
    -- each overlay system is independent with its own colour. OFF unless
    -- explicitly on (owner ruling 2026-08-28) — the tint is a new visual,
    -- so pre-feature configs keep their look with no migration. Shared with
    -- the config panel and the preview stand-in.
    function RB.IsResourceOverlayFillEnabled(entry)
        return type(entry) == "table" and entry.auraFillEnabled == true
    end

    function RB.GetResourceOverlayFillColor(entry)
        local color = type(entry) == "table" and entry.auraFillColor or nil
        if type(color) == "table" and color[1] ~= nil and color[2] ~= nil and color[3] ~= nil then
            return color
        end
        return DEFAULT_RESOURCE_AURA_ACTIVE_COLOR
    end

    -- Which bar types the fill tint can ride: the tint anchors to the ONE
    -- fill texture a continuous StatusBar carries, so segment clusters are
    -- out (no single fill, and the per-segment mechanism is unprobed).
    function RB.ResourceOverlayFillSupportsBarType(barType)
        return RESOURCE_OVERLAY_BAR_TYPES[barType] == true
            and not SEGMENT_CLUSTER_BAR_TYPES[barType]
    end

    -- Which overlay shapes an entry renders. The BORDER and the STACK LANE
    -- are INDEPENDENT toggles (owner ruling 2026-08-02: they are separate
    -- systems — any combination, including neither). The border is the
    -- aura-present visual riding Blizzard-driven slot visibility (live's
    -- "active" recolor stays dead in combat on 12.1, so it is the
    -- combat-grade stand-in), wrapping the WHOLE bar rect — one rect on
    -- segment clusters too, as if the bar were continuous. The lane fills
    -- with stacks on the same resources live offers it on.
    local function ResolveResourceOverlayShapes(entry, powerType, barType)
        local shapes = {}
        if RB.IsResourceOverlayBorderEnabled(entry) then
            shapes.border = true
        end
        if GetResourceAuraTrackingMode(entry) == "stacks"
            and SupportsResourceAuraStackMode(powerType) then
            shapes.stackLane = true
        end
        -- Only the collector passes barType (the live bar's shape); the
        -- config-facing callers resolve without it and never see fillTint.
        if barType ~= nil
            and RB.IsResourceOverlayFillEnabled(entry)
            and RB.ResourceOverlayFillSupportsBarType(barType) then
            shapes.fillTint = true
        end
        return shapes
    end

    -- The border style an entry renders ("solid" | "pixel"). Solid is the
    -- default — the calmer of the two launch styles. Shared with the config
    -- panel so its dropdown reads back what the runtime will draw.
    function RB.GetResourceOverlayBorderStyle(entry)
        if type(entry) == "table" and entry.auraBorderStyle == "pixel" then
            return "pixel"
        end
        return "solid"
    end

    -- Overlay entry -> the buttonData vocabulary Core/Aura.lua reads. The
    -- unit is left to the rebind pass's shared polarity resolve (auraUnit
    -- is its fallback for uncached spells). No soundAlerts: resource
    -- overlays carry no sound events.
    local function BuildResourceOverlayEntryAdapter(entry, settings, shapes)
        local layout = GetSpecLayoutOrder(settings)
        return {
            type = "spell",
            id = tonumber(entry.auraColorSpellID),
            addedAs = "aura",
            auraTracking = true,
            auraUnit = entry.auraUnit,
            auraBar = {
                mode = shapes.stackLane and "stacks" or "duration",
                segmentGap = (layout and layout.segmentGap) or settings.segmentGap or 4,
                segmentedSmoothing = GetResourceSegmentedSmoothing(settings),
            },
        }
    end

    -- Overlay entry + resource settings -> the StyleSlotKit vocabulary,
    -- plus the resourceShapes table the kit's resource branch lays shapes
    -- from. The aura border rides the barAura* effect family the kit glow
    -- reads natively, wrapping the whole bar rect on every shape.
    local function BuildResourceOverlayStyleAdapter(entry, settings, shapes)
        local style = {}

        style.barTexture = GetResourceDisplayValue(settings, "barTexture", "Solid")
        style.barBgColor = GetResourceDisplayValue(settings, "backgroundColor", { 0, 0, 0, 0.5 })
        style.backgroundColor = style.barBgColor
        local borderStyle = GetResourceDisplayValue(settings, "borderStyle", "pixel")
        style.borderColor = GetResourceDisplayValue(settings, "borderColor", { 0, 0, 0, 1 })
        style.borderSize = borderStyle == "pixel" and GetResourceDisplayValue(settings, "borderSize", 1) or 0
        style.borderRenderMode = GetResourceDisplayValue(settings, "borderRenderMode", ST.BORDER_RENDER_MODE_CUSTOM)

        local color = entry.auraActiveColor
        if type(color) ~= "table" or color[1] == nil or color[2] == nil or color[3] == nil then
            color = DEFAULT_RESOURCE_AURA_ACTIVE_COLOR
        end
        -- Each system carries its own colour: barAuraColor feeds the lane
        -- fill (own key, border-colour fallback), barAuraEffectColor the
        -- border. The enable flag is the border's whole gate: the glow
        -- builders style off when it is false.
        style.barAuraColor = RB.GetResourceOverlayLaneColor(entry)
        style.barAuraIndicatorEnabled = shapes.border == true
        -- The fill tint's colour rides its own key beside the lane's and
        -- the border's; the kit reads it only when shapes.fillTint is set.
        style.barAuraFillColor = RB.GetResourceOverlayFillColor(entry)
        style.barAuraEffect = RB.GetResourceOverlayBorderStyle(entry)
        style.barAuraEffectColor = color
        style.barAuraEffectSize = tonumber(entry.auraBorderSize)
        style.barAuraEffectThickness = tonumber(entry.auraBorderThickness)
        style.barAuraEffectSpeed = tonumber(entry.auraBorderSpeed)
        style.barAuraEffectLines = tonumber(entry.auraBorderLines)
        -- Overwritten by the collector from the live frame's fill direction.
        style.barReverseFill = false

        -- Live's overlay carries no text of its own: the resource bar's own
        -- text keeps saying what the resource is doing.
        style.showAuraText = false
        style.showAuraStackText = false

        style.showBarIcon = false
        style.showBarNameText = false
        style.showKeybindText = false
        style.pandemicMarkerMode = "off"

        style.resourceShapes = shapes
        return style
    end

    -- Shared with the config panel so its dropdown shows the mode the
    -- runtime will actually render: an entry set to stacks on a resource
    -- that has no stack lane reads back as active, here and there alike.
    function RB.GetResourceOverlayTrackingMode(entry, powerType)
        if type(entry) ~= "table" then
            return "active"
        end
        return ResolveResourceOverlayShapes(entry, powerType).stackLane
            and "stacks" or "active"
    end

    -- The inset the kit will mount this bar's holder at, so the config
    -- canvas can stand the overlay in on the same rect the live one covers.
    function RB.GetResourceOverlayHolderInset(barInfo)
        local settings = GetResourceBarSettings()
        if not (settings and barInfo) then return 0 end
        return GetResourceHolderInset(barInfo, GetCustomBarBorderInset(settings)) or 0
    end

    -- The automatic stack max for an overlay entry, resolved straight from
    -- game data through the same adapter the collector uses, for the config
    -- panel's status line. Deliberately does not touch the runtime cache:
    -- that cache is the in-combat safety net and the rebind pass owns it.
    function RB.ResolveResourceOverlayStackMax(entry, powerType)
        if type(entry) ~= "table" or not tonumber(entry.auraColorSpellID) then
            return nil
        end
        local settings = GetResourceBarSettings()
        if not settings then return nil end
        local buttonData = BuildResourceOverlayEntryAdapter(
            entry, settings, ResolveResourceOverlayShapes(entry, powerType))
        -- Constrained set, like every other max resolve on this file: the
        -- threshold policy resolves with the constrain flag, so any other
        -- choice lets the fill's max and the text's max disagree on spell
        -- entries with implicit fallbacks (review 2026-08-15).
        return CooldownCompanion:GetAuraStackBarMax(buttonData, true)
    end

    ------------------------------------------------------------------------
    -- The aura BLOCK (12.1): the collapsing container at the end of a side.
    --
    -- An aura entry that hides when inactive cannot hold a fixed slot in the
    -- CC-laid-out stack — aura presence is secret, so the CC accumulator can
    -- never pack around it. Those entries leave the stack entirely and the
    -- apply pass hands the partition here; Core/AuraDisplay.lua turns each
    -- side into ONE Blizzard AuraContainer running in GROUP mode, where
    -- Blizzard packs the ACTIVE auras itself.
    --
    -- This module owns only the CC-side half of that contract: where the
    -- container's plain mount root sits and what each entry wants (the same
    -- adapters and candidate set the slot path builds, resolved by the OOC
    -- rebind pass). Moving the root is combat-safe; AuraContainer topology
    -- and direct geometry remain restricted to the rebind pass.
    ------------------------------------------------------------------------

    local BLOCK_SIDES = { "above", "below", "left", "right" }

    -- Where a side's block container pins to that side's stack container,
    -- and which way its mount offset runs. Mirrors RelayoutBars' own
    -- accumulator signs, so the block continues the fixed stack seamlessly:
    -- below/right grow away from the anchor edge, above/left back toward it.
    --
    -- `far` is the same container's TRAILING edge — the corner a second
    -- per-unit bucket chains from. It is the mount point mirrored along the
    -- growth axis only (the cross-axis corner is unchanged), so a chained
    -- container keeps the mount's alignment and continues its flow.
    local BLOCK_MOUNTS = {
        above = { point = "BOTTOMLEFT", far = "TOPLEFT", dx = 0, dy = 1 },
        below = { point = "TOPLEFT", far = "BOTTOMLEFT", dx = 0, dy = -1 },
        left = { point = "TOPRIGHT", far = "TOPLEFT", dx = -1, dy = 0 },
        right = { point = "TOPLEFT", far = "TOPRIGHT", dx = 1, dy = 0 },
    }

    local blockState = {}      -- side -> recorded block contract
    local blockSignatures = {} -- side -> last bind-relevant signature

    -- Everything a rebind would have to re-derive: the entry set, its order,
    -- the mount geometry, and the park state. Mount-only changes still land
    -- immediately (the container is re-anchored below), but they also change
    -- the elementWidth/Height every group carries, so they belong here.
    local function BuildBlockSignature(side, state)
        local parts = {
            side,
            tostring(state.parent),
            tostring(state.unlockAssist),
            tostring(state.vertical),
            tostring(state.offset),
            tostring(state.width),
            tostring(state.spacing),
            -- Bucket order decides which container takes the stack mount and
            -- which chains, so a flip must force a rebind like a unit change.
            tostring(state.targetFirst),
        }
        for _, entry in ipairs(state.entries) do
            -- The unit rides the per-entry part: it decides which container an
            -- entry binds into (and therefore whether the side chains), so a
            -- unit change has to force a rebind exactly like an order change.
            parts[#parts + 1] = tostring(entry.customBarId)
                .. ":" .. tostring(entry.thickness)
                .. ":" .. tostring(entry.unit)
        end
        return table_concat(parts, "|")
    end

    -- Called at the end of every ApplyResourceBars pass (and from the revert
    -- with all sides empty). Records the desired state, re-anchors whatever
    -- containers already exist, and asks for a rebind when the recorded
    -- state materially changed. No slot work happens here: this runs in
    -- combat.
    function RB.SyncCustomBarAuraBlocks(blocks)
        local changed = false
        for _, side in ipairs(BLOCK_SIDES) do
            local block = type(blocks) == "table" and blocks[side] or nil
            local state
            if block then
                state = {
                    parent = block.parent,
                    offset = tonumber(block.offset) or 0,
                    width = tonumber(block.width) or 0,
                    spacing = tonumber(block.spacing) or 0,
                    vertical = block.vertical == true,
                    -- Unlock assist keeps the legacy expanded shells in the
                    -- stack (an arrange-mode stack must offer every bar as a
                    -- drag target), so the block owns nothing that pass.
                    unlockAssist = block.unlockAssist == true,
                    targetFirst = block.targetFirst == true,
                    entries = block.unlockAssist and {} or (block.entries or {}),
                }
            end
            blockState[side] = state
            local signature = state and BuildBlockSignature(side, state) or ""
            if blockSignatures[side] ~= signature then
                blockSignatures[side] = signature
                changed = true
            end
        end
        -- The AuraDisplay side moves a plain CC mount root immediately. It
        -- touches direct AuraContainer geometry only when the rebind gate is
        -- open, so form-driven stack offsets stay current in combat without
        -- crossing the restricted subtree boundary.
        if changed then
            if ST._SyncCustomBarAuraBlockMounts then
                ST._SyncCustomBarAuraBlockMounts()
            end
            CooldownCompanion:RequestAuraRebind("custom-bar-blocks")
        end
    end

    -- The TAIL of a side's block chain, for trailing frames (cast bar) to
    -- chain from: the target bucket when the side runs one, else the player
    -- bucket. Anything anchored to it must be created with
    -- DisableUntrustedLayoutScriptsTemplate and single-point anchored.
    function RB.GetCustomBarAuraBlockContainer(side)
        local get = ST._GetCustomBarAuraBlockContainer
        return get and get(side) or nil
    end

    -- The mount for a side: ONE anchor point (never two — the container's
    -- size is secret from its first aura group) plus the frame level the
    -- holders use. Nil parent means the side has no live stack container.
    function ST._GetCustomBarAuraBlockMount(side)
        local state = blockState[side]
        local mount = state and BLOCK_MOUNTS[side]
        if not (mount and state.parent) then return nil end
        return state.parent, mount.point,
            mount.dx * state.offset, mount.dy * state.offset,
            state.parent:GetFrameLevel() + 3
    end

    -- The mount for a side's SECOND unit bucket. It does not pin to the stack
    -- at all: it pins to the first bucket's trailing edge along the same
    -- growth axis, so the two buckets read as one block even though the first
    -- one's extent is secret. Same single-point discipline — the anchor is
    -- everything CC may state; the size stays Blizzard's. The level still
    -- comes from the stack container, so no aspected frame is read. Returns
    -- own point, the anchor's point, the offset, and the level.
    --
    -- The seam is one bar spacing, PAID BLIND: an all-inactive first bucket
    -- still sits in the chain as a ~1px sliver with the seam attached, so
    -- the block's outer gap breathes by spacing+1px in that state. That is
    -- structural — the engine's measured size excludes trailing spacing and
    -- an empty container measures its padding, so no offset choice can
    -- serve both states (proven against ApplyFlowLayout source). A fixed
    -- 2px seam was TRIALED AND REVERTED by owner ruling 2026-08-08: uniform
    -- spacing won and the breath is accepted and explained in config. Do
    -- not re-propose the tight seam.
    function ST._GetCustomBarAuraBlockChainMount(side)
        local state = blockState[side]
        local mount = state and BLOCK_MOUNTS[side]
        if not (mount and state.parent) then return nil end
        return mount.point, mount.far,
            mount.dx * state.spacing, mount.dy * state.spacing,
            state.parent:GetFrameLevel() + 3
    end

    -- OOC (rebind pass): one want per side, carrying the adapters, candidate
    -- set and explicit geometry for every entry in block order, each stamped
    -- with the unit resolved at partition time. Empty sides are reported too,
    -- so the bind pass can park them.
    function ST._CollectCustomBarAuraBlockWants()
        local wants = {}
        local settings = GetResourceBarSettings()
        for _, side in ipairs(BLOCK_SIDES) do
            local state = blockState[side]
            local want = {
                side = side,
                entries = {},
                -- From the recorded contract, not re-read from settings: the
                -- bind pass must see the same order the signature saw.
                targetFirst = state and state.targetFirst == true,
            }
            wants[#wants + 1] = want
            if state and settings and settings.enabled and not state.unlockAssist then
                -- Layout-derived, like the resource overlays: a block entry
                -- has no CC bar frame to read a fill direction off.
                local reverseFill = state.vertical
                    and IsVerticalFillReversed(settings) == true or false
                for _, entry in ipairs(state.entries) do
                    local cabConfig = entry.config
                    if IsAuraTrackedCustomBar(cabConfig)
                        and CooldownCompanion:IsCustomBarRuntimeEligible(cabConfig) then
                        local buttonData = BuildEntryAdapter(cabConfig, settings)
                        local spellSet = CooldownCompanion:GetAuraCandidateSpellIDSet(buttonData)
                        if spellSet then
                            -- Same automatic, game-data resolved max the
                            -- stack path uses (owner ruling — no manual max
                            -- anywhere). Cached by the BAR so the config
                            -- canvas can read it back.
                            local stackBarMax
                            if CooldownCompanion:IsBarPanelAuraStackDisplay(buttonData) then
                                -- Constrained (panel parity): boundStackMax must
                                -- equal the threshold policy's maxStacks or the
                                -- bound fill and the max text breakpoint disagree.
                                stackBarMax = CooldownCompanion:GetAuraStackBarMax(buttonData, true)
                            end
                            SetCustomBarCachedStackMax(entry.customBarId, stackBarMax)
                            local style = BuildStyleAdapter(cabConfig, settings)
                            style.barReverseFill = reverseFill
                            local thickness = tonumber(entry.thickness) or 0
                            want.entries[#want.entries + 1] = {
                                id = tostring(entry.customBarId),
                                -- Resolved once at partition time; the bind
                                -- pass adopts it verbatim, so which container
                                -- an entry lands in can never drift.
                                unit = entry.unit or "player",
                                buttonData = buttonData,
                                spellSet = spellSet,
                                style = style,
                                stackBarMax = stackBarMax,
                                spacing = state.spacing,
                                vertical = state.vertical,
                                -- The stack's cross-axis extent is the bar's
                                -- length; the entry's own thickness is the
                                -- other axis.
                                width = state.vertical and thickness or state.width,
                                height = state.vertical and state.width or thickness,
                                -- Border-ring inset for the kit fill. Widget
                                -- stacks take 0 (owner ruling 2026-08-08):
                                -- they draw per-block rings, never the
                                -- whole-bar ring the inset protects, and the
                                -- CC absent-state blocks already span the
                                -- full footprint (EnsureInsetRect(frame, 0)).
                                inset = (stackBarMax ~= nil
                                        and stackBarMax <= ST.STACK_SEGMENT_ATLAS_MAX
                                        and CooldownCompanion:GetBarPanelAuraStackDisplayMode(buttonData) == "segmented")
                                    and 0
                                    or GetCustomBarBorderInset(settings),
                            }
                        end
                    end
                end
            end
        end
        return wants
    end

    ------------------------------------------------------------------------
    -- The want collector: called by RunAuraRebind (structurally OOC) after
    -- the panel pass. Appends one want record per live aura-tracked custom
    -- bar, re-anchors holders, refreshes the stack-max cache, and re-lays
    -- the CC-side absent state.
    ------------------------------------------------------------------------

    function ST._CollectCustomBarAuraWants(wanted)
        local settings = GetResourceBarSettings()
        local collected -- customBarId -> true
        local collectedResources -- powerType -> true

        if settings and settings.enabled then
            local inset = GetCustomBarBorderInset(settings)
            for _, barInfo in ipairs(resourceBarFrames) do
                local cabConfig = barInfo and barInfo.cabConfig
                local frame = barInfo and barInfo.frame
                -- Hardened against stale slot state: the barType must be a
                -- live custom shape AND the entry must still be runtime-
                -- eligible (enabled, talent/load conditions) — cabConfig
                -- alone lingered on recycled slots.
                if frame and barInfo.customBarId
                    and (barInfo.barType == "custom_continuous" or barInfo.barType == "custom_cooldown")
                    and IsAuraTrackedCustomBar(cabConfig)
                    and CooldownCompanion:IsCustomBarRuntimeEligible(cabConfig)
                    and frame:IsShown() then
                    local buttonData = BuildEntryAdapter(cabConfig, settings)
                    local spellSet = CooldownCompanion:GetAuraCandidateSpellIDSet(buttonData)
                    if spellSet then
                        -- Stack fill max: automatic, game-data resolved,
                        -- OOC (owner ruling — no manual max anywhere).
                        -- Resolved BEFORE the holder is anchored: whether
                        -- this bar renders as stack blocks decides where
                        -- the holder mounts, and that answer comes from the
                        -- cached max.
                        local stackBarMax
                        if CooldownCompanion:IsBarPanelAuraStackDisplay(buttonData) then
                            -- Constrained (panel parity; see the block collector).
                            stackBarMax = CooldownCompanion:GetAuraStackBarMax(buttonData, true)
                        end
                        -- Keyed by the BAR, so it survives the slot churn a
                        -- form change causes (see the helper's note).
                        SetCustomBarCachedStackMax(barInfo.customBarId, stackBarMax)

                        local holder = EnsureHolder(barInfo.customBarId)
                        AnchorHolderToBar(holder, frame, GetCustomBarHolderInset(barInfo, inset))
                        holder:Show()

                        local style = BuildStyleAdapter(cabConfig, settings)
                        style.barReverseFill = frame._reverseFill or false

                        ApplyCustomBarAbsentStackVisuals(barInfo, settings)

                        wanted[#wanted + 1] = {
                            button = holder,
                            buttonData = buttonData,
                            spellSet = spellSet,
                            -- unit resolved by the rebind pass's shared
                            -- polarity rule (want.unit left nil).
                            style = style,
                            stackBarMax = stackBarMax,
                        }
                        collected = collected or {}
                        collected[barInfo.customBarId] = true
                    end
                elseif frame and barInfo.powerType ~= nil
                    and RESOURCE_OVERLAY_BAR_TYPES[barInfo.barType]
                    and frame:IsShown() then
                    -- Resource overlay leg (Phase 2): one want per shown
                    -- resource bar whose resource has a current-spec entry.
                    local resource = settings.resources and settings.resources[barInfo.powerType]
                    local entry = resource and IsResourceAuraOverlayEnabled(resource)
                        and GetActiveResourceAuraEntry(resource) or nil
                    local auraSpellID = entry and tonumber(entry.auraColorSpellID) or nil
                    if auraSpellID and auraSpellID > 0 then
                        local shapes = ResolveResourceOverlayShapes(entry, barInfo.powerType, barInfo.barType)
                        local buttonData = BuildResourceOverlayEntryAdapter(entry, settings, shapes)
                        local spellSet = CooldownCompanion:GetAuraCandidateSpellIDSet(buttonData)
                        if spellSet then
                            -- Stack lane fill max: automatic, game-data
                            -- resolved, OOC (owner ruling — no manual max
                            -- anywhere). A nil resolve means "not a
                            -- stacking aura", so the lane comes off and the
                            -- border alone carries the active state — live's
                            -- own fallback to the recolor when no max is
                            -- configured. The border is a separate toggle
                            -- since 2026-08-02, so it is NOT guaranteed to
                            -- be there: an entry with both off is legal
                            -- (owner ruling) and renders nothing while still
                            -- holding its slot. Nothing downstream may
                            -- assume a want draws at least one shape.
                            local stackBarMax
                            if shapes.stackLane then
                                -- Constrained (panel parity; see the block collector).
                                stackBarMax = CooldownCompanion:GetAuraStackBarMax(buttonData, true)
                                if not stackBarMax then
                                    shapes.stackLane = false
                                    buttonData.auraBar.mode = "duration"
                                end
                            end

                            local holder = EnsureResourceHolder(barInfo.powerType)
                            AnchorHolderToBar(holder, frame,
                                GetResourceHolderInset(barInfo, inset),
                                HOLDER_LEVEL_RESOURCE)
                            AnchorResourceFillProxy(holder, frame, barInfo.barType)
                            -- Orientation from the LAYOUT, not the frame:
                            -- segment-cluster frames never carry the
                            -- _isVertical/_reverseFill fields continuous
                            -- bars do, and every resource bar follows the
                            -- global layout orientation anyway.
                            local vertical = IsVerticalResourceLayout(settings) == true
                            holder._isVertical = vertical
                            holder:Show()

                            local style = BuildResourceOverlayStyleAdapter(entry, settings, shapes)
                            style.barReverseFill = vertical
                                and IsVerticalFillReversed(settings) == true or false

                            wanted[#wanted + 1] = {
                                button = holder,
                                buttonData = buttonData,
                                spellSet = spellSet,
                                -- unit resolved by the rebind pass's shared
                                -- polarity rule (want.unit left nil).
                                style = style,
                                stackBarMax = stackBarMax,
                            }
                            collectedResources = collectedResources or {}
                            collectedResources[barInfo.powerType] = true
                        end
                    end
                end
            end
        end

        -- Holders with no want this pass go dark: the main pass parks their
        -- displays (sentinel filter renders nothing); hiding the holder is
        -- the belt-and-braces CC-side mirror.
        for customBarId, holder in pairs(holders) do
            if not (collected and collected[customBarId]) then
                holder:Hide()
            end
        end
        for powerType, holder in pairs(resourceHolders) do
            if not (collectedResources and collectedResources[powerType]) then
                holder:Hide()
            end
        end
    end

    -- Late-bound seam for FinalizeAppliedBarVisibility (the customBars
    -- module is created before this one; it looks the function up on RB at
    -- call time).
    RB.ApplyCustomBarAbsentStackVisuals = ApplyCustomBarAbsentStackVisuals

    -- The automatic stack max for a cabConfig, resolved straight from game
    -- data through the same adapter the rebind collector uses. For the
    -- CONFIG canvas, which renders bars that may have no live slot running
    -- and therefore no cached max. Deliberately does not write the runtime
    -- cache: that cache is the in-combat safety net and the rebind pass
    -- owns it.
    function RB.ResolveCustomBarStackMax(cabConfig, settings)
        if not IsAuraTrackedCustomBar(cabConfig) then return nil end
        settings = settings or GetResourceBarSettings()
        if not settings then return nil end
        local buttonData = BuildEntryAdapter(cabConfig, settings)
        if not CooldownCompanion:IsBarPanelAuraStackDisplay(buttonData) then return nil end
        -- Constrained (panel parity; see the block collector).
        return CooldownCompanion:GetAuraStackBarMax(buttonData, true)
    end

    -- The stack threshold/max color policy for a cabConfig, resolved through
    -- the same adapter the rebind collector uses. Config-canvas consumer
    -- only: the stand-in paints CC-invented counts, so it may compare in
    -- Lua what the live kit renders engine-side.
    function RB.ResolveCustomBarStackThresholdPolicy(cabConfig, settings)
        if not IsAuraTrackedCustomBar(cabConfig) then return nil end
        settings = settings or GetResourceBarSettings()
        if not settings then return nil end
        return CooldownCompanion:ResolveAuraStackThresholdPolicy(
            BuildEntryAdapter(cabConfig, settings))
    end

    ------------------------------------------------------------------------
    -- Frame-identity repair. Bar frames are recycled by STACK POSITION, so
    -- anything that changes the stack's length — shapeshifting a resource in
    -- or out, most of all — hands a custom bar a different frame than the one
    -- its aura holder was anchored to. Out of combat the rebind pass fixes
    -- that on the next frame; in combat the rebind is deferred to combat end,
    -- so the display would sit on whatever now occupies the old position
    -- (validated in game 2026-07-26: the display landed on the resources).
    --
    -- Re-anchoring is pure CC-side geometry, which is why it is safe here:
    -- the holder is a CC frame under a CC root, and the aura subtree beneath
    -- it moves with its parent without any call reaching a slot object. The
    -- BIND (filters, stack max, styling) stays OOC-only as always — nothing
    -- about the aura state changes when the bar merely relocates.
    ------------------------------------------------------------------------

    function RB.SyncCustomBarAuraHostAnchor(barInfo)
        local frame = barInfo and barInfo.frame
        local customBarId = barInfo and barInfo.customBarId
        if not (frame and customBarId) then return end
        local holder = holders[customBarId]
        -- Never bound (or parked and hidden): the rebind owns those.
        if not (holder and holder._ccAnchoredFrame) then return end
        if holder._ccAnchoredFrame == frame then return end
        local settings = GetResourceBarSettings()
        if not settings then return end
        -- Same mount rule as the rebind pass. Safe in combat: the stack-
        -- blocks test reads the customBarId-keyed cache, never the
        -- restricted max lookup.
        AnchorHolderToBar(holder, frame,
            GetCustomBarHolderInset(barInfo, GetCustomBarBorderInset(settings)))
    end

    -- Show & hide rules (spell bars): the kit holder is parented to a
    -- stable root, not the bar frame, so a cooldown-rule hide on the CC bar
    -- would leave the aura visuals standing. This mirrors ONLY the rule
    -- alpha onto the holder — the aura shell (hideWhenInactive/auraShellDim)
    -- deliberately keeps the kit at full strength, and holder alpha writes
    -- are legal in combat. Composes multiplicatively with the root's fade.
    function RB.SetCustomBarAuraHostRuleAlpha(barInfo, alpha)
        local customBarId = barInfo and barInfo.customBarId
        local holder = customBarId and holders[customBarId]
        if holder then
            holder:SetAlpha(alpha)
        end
    end

    -- The resource-holder mirror of the repair above, keyed by powerType.
    -- Resource slots recycle exactly as readily on a form change; the mount
    -- rule here is plain barType + settings reads, so it is equally valid
    -- in combat.
    function RB.SyncResourceBarAuraHostAnchor(barInfo)
        local frame = barInfo and barInfo.frame
        local powerType = barInfo and barInfo.powerType
        if not (frame and powerType ~= nil) then return end
        local holder = resourceHolders[powerType]
        -- Never bound (or parked and hidden): the rebind owns those.
        if not (holder and holder._ccAnchoredFrame) then return end
        local settings = GetResourceBarSettings()
        if not settings then return end
        if not IsLiveResourceAuraHolderBar(barInfo, settings) then
            holder:Hide()
            return
        end
        if holder._ccAnchoredFrame ~= frame then
            AnchorHolderToBar(holder, frame,
                GetResourceHolderInset(barInfo, GetCustomBarBorderInset(settings)),
                HOLDER_LEVEL_RESOURCE)
            -- Layout-derived, like the collector: cluster frames carry no
            -- _isVertical field for AnchorHolderToBar to read.
            holder._isVertical = IsVerticalResourceLayout(settings) == true
            -- The tint's anchor relay follows the replacement frame too —
            -- this is the combat-safe half of the fill-tint contract (the
            -- registered tint itself is bound to the proxy and never
            -- touched here).
            AnchorResourceFillProxy(holder, frame, barInfo.barType)
        end
        -- A form can bring back a holder that this same restriction window
        -- hid. Its existing binding remains underneath; showing the plain CC
        -- holder is safe, while a never-bound holder still returns above.
        holder:Show()
    end

    -- Reconcile by stable resource identity after every apply. Slot-local
    -- cleanup cannot do this safely: a resource that moved to another slot is
    -- still live and must keep its holder, while a form-hidden resource has no
    -- FinalizeAppliedBarVisibility call that could turn its separate holder
    -- off. Plain holder visibility is safe during combat.
    function RB.ReconcileResourceAuraHolders()
        local settings = GetResourceBarSettings()
        local live = {}
        if settings and settings.enabled then
            for _, barInfo in ipairs(resourceBarFrames) do
                if IsLiveResourceAuraHolderBar(barInfo, settings) then
                    live[barInfo.powerType] = true
                end
            end
        end
        for powerType, holder in pairs(resourceHolders) do
            if not live[powerType] then
                holder:Hide()
            end
        end
    end

    -- Park one resource's overlay holder as soon as a recycled slot changes
    -- identity. The apply-wide reconciliation above covers resources that
    -- disappear without an incoming occupant; this fast path covers a
    -- mutually exclusive pair swapping in place. Hiding a plain CC frame is
    -- legal in combat; BINDING a never-seen incoming holder is not, and
    -- deliberately stays with the deferred rebind.
    function RB.HideResourceAuraHolder(powerType)
        local holder = powerType ~= nil and resourceHolders[powerType]
        if holder then
            holder:Hide()
        end
    end

    -- Addon methods rather than module-locals on purpose: ApplyResourceBars
    -- sits at Lua 5.1's 60-upvalue ceiling, and `self` reaches these for
    -- free from its call sites.
    function CooldownCompanion:GetCustomBarAuraHostRoot()
        return GetAuraHostRoot()
    end

    function CooldownCompanion:SetCustomBarAuraHostApplied(applied)
        SetAuraHostRootApplied(applied)
    end

    return {
        GetAuraHostRoot = GetAuraHostRoot,
        SetAuraHostRootApplied = SetAuraHostRootApplied,
    }
end
