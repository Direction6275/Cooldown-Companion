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
    local GetResourceDisplayConfig = RB.GetResourceDisplayConfig
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
    -- custom bar lives at or below it). Resource bars stack far taller —
    -- segment children at +3, MW overlay segments at +4, and the text layer
    -- at +8 — so a resource holder at +3 would render UNDERNEATH the very
    -- segments it decorates. They pass 9 (see HOLDER_LEVEL_RESOURCE).
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
        return {
            type = "spell",
            id = tonumber(cabConfig.spellID),
            addedAs = (not isSpellBar) and "aura" or nil,
            auraTracking = true,
            auraSpellID = cabConfig.auraSpellID,
            auraUnit = GetResolvedCustomAuraBarAuraUnit(cabConfig, tonumber(cabConfig.spellID)),
            pandemicMarker = cabConfig.pandemicMarker,
            hideWhileAuraNotActive = cabConfig.hideWhenInactive == true,
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

        -- Pandemic marker (panel defaults): per-entry override rides
        -- buttonData.pandemicMarker in the entry adapter; the style keys
        -- follow the cabConfig pandemicMarker* family when set.
        style.pandemicMarkerEnabled = cabConfig.pandemicMarkerEnabled
        style.pandemicMarkerText = cabConfig.pandemicMarkerText
        style.pandemicMarkerColor = cabConfig.pandemicMarkerColor
        style.pandemicMarkerColorMode = cabConfig.pandemicMarkerColorMode

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

    local function ApplyCustomBarAbsentStackVisuals(barInfo, settings, opts)
        local frame = barInfo and barInfo.frame
        if not frame then return end
        local max = WantsAbsentStackBlocks(barInfo, opts)
        if not max then
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
        ST.LayoutStackBlocks(blocks, rect, max, frame._isVertical, bgColor, bgColor[4] or 1, rectLength)
        -- litStacks (config preview only): the Active Aura stand-in. On a
        -- live bar the kit paints its atlas fill over these same blocks; with
        -- no kit on the canvas, CC lights them itself, in the same colour the
        -- kit's stack fill uses.
        local lit = opts and tonumber(opts.litStacks) or nil
        if lit and lit > 0 then
            local auraColor = style.barAuraColor or { 0.2, 1.0, 0.2, 1.0 }
            for i = 1, math_min(lit, max) do
                local tex = blocks[i]
                if tex then
                    tex:SetColorTexture(
                        auraColor[1] or 0.2,
                        auraColor[2] or 1.0,
                        auraColor[3] or 0.2,
                        auraColor[4] ~= nil and auraColor[4] or 1
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

    -- Clear of every layer a resource bar draws: segment children at bar+3,
    -- MW overlay segments at +4, the CC-side aura lane pool at +7, and the
    -- text layer at +8. Frame level beats draw layer, so anything short of
    -- this renders behind the bar it is meant to decorate (the Phase 1
    -- FRAME-LEVEL lesson, re-applied to a much taller stack).
    local HOLDER_LEVEL_RESOURCE = 9

    local RESOURCE_OVERLAY_BAR_TYPES = {
        continuous = true,
        segmented = true,
        mw_segmented = true,
        stagger_continuous = true,
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
            -- Anchor rect for the full aura display shape: a plain CC
            -- square centered on the bar. The kit's icon/swipe/texts anchor
            -- to it; it renders nothing itself.
            holder._ccDisplayRect = CreateFrame("Frame", nil, holder)
            holder._ccDisplayRect:EnableMouse(false)
            holder._ccDisplayRect:SetPoint("CENTER", holder, "CENTER", 0, 0)
            holder._ccDisplayRect:SetSize(24, 24)
            resourceHolders[powerType] = holder
        end
        return holder
    end

    -- Where a resource holder mounts. Continuous-style bars carry their own
    -- pixel-border ring inside the bar rect, so the holder insets to keep
    -- the ring visible (the panel statusBar-mount contract). Segment
    -- clusters draw their rings per segment — the cluster frame has no ring
    -- of its own, and the tint must span the whole cluster (owner ruling),
    -- so those mount at the full rect.
    local function GetResourceHolderInset(barInfo, borderInset)
        if barInfo.barType == "segmented" or barInfo.barType == "mw_segmented" then
            return 0
        end
        return borderInset
    end

    -- Which overlay shapes an entry renders. New entries carry explicit
    -- shape* booleans; live-era entries with none set default from the
    -- closest live intent — "stacks" tracking meant the stack lane,
    -- everything else meant the fill recolor, whose combat-grade
    -- replacement is the whole-bar tint. Read-time defaulting only; the
    -- stored keys are never rewritten (no migrations).
    local function ResolveResourceOverlayShapes(entry)
        if entry.shapeTint ~= nil or entry.shapeDurationLane ~= nil
            or entry.shapeStackLane ~= nil or entry.shapeStackText ~= nil
            or entry.shapeAuraDisplay ~= nil then
            return {
                tint = entry.shapeTint == true,
                durationLane = entry.shapeDurationLane == true,
                stackLane = entry.shapeStackLane == true,
                stackText = entry.shapeStackText == true,
                display = entry.shapeAuraDisplay == true,
            }
        end
        if GetResourceAuraTrackingMode(entry) == "stacks" then
            return { stackLane = true, stackText = true }
        end
        return { tint = true }
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
    -- from. No barAura* effect keys: resource overlays carry no glow/pulse
    -- family (border glow declined by ruling), and the absent indicator
    -- key reads as effects-off.
    local function BuildResourceOverlayStyleAdapter(entry, settings, powerType, shapes)
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
        style.barAuraColor = color
        -- Overwritten by the collector from the live frame's fill direction.
        style.barReverseFill = false

        -- Texts ride the resource text styling (one home per control).
        local resourceConfig = GetResourceDisplayConfig(settings, powerType)
        local font = (resourceConfig and resourceConfig.textFont) or DEFAULT_RESOURCE_TEXT_FONT
        local fontSize = tonumber(resourceConfig and resourceConfig.textFontSize) or DEFAULT_RESOURCE_TEXT_SIZE
        local outline = (resourceConfig and resourceConfig.textFontOutline) or DEFAULT_RESOURCE_TEXT_OUTLINE
        local fontColor = resourceConfig and resourceConfig.textFontColor
        if type(fontColor) ~= "table" or fontColor[1] == nil or fontColor[2] == nil or fontColor[3] == nil then
            fontColor = DEFAULT_RESOURCE_TEXT_COLOR
        end
        style.auraTextFont, style.auraTextFontSize = font, fontSize
        style.auraTextFontOutline, style.auraTextFontColor = outline, fontColor
        style.auraStackFont, style.auraStackFontSize = font, fontSize
        style.auraStackFontOutline, style.auraStackFontColor = outline, fontColor
        -- The timer text belongs to the full display shape; the stack text
        -- is its own shape.
        style.showAuraText = shapes.display == true
        style.showAuraStackText = shapes.stackText == true

        style.showBarIcon = false
        style.showBarNameText = false
        style.showKeybindText = false
        style.pandemicMarkerEnabled = false

        style.resourceShapes = shapes
        style.resourceDisplaySize = tonumber(entry.displaySize) or 24
        return style
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
                            stackBarMax = CooldownCompanion:GetAuraStackBarMax(buttonData)
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
                        local shapes = ResolveResourceOverlayShapes(entry)
                        local buttonData = BuildResourceOverlayEntryAdapter(entry, settings, shapes)
                        local spellSet = CooldownCompanion:GetAuraCandidateSpellIDSet(buttonData)
                        if spellSet then
                            -- Stack lane fill max: automatic, game-data
                            -- resolved, OOC (owner ruling — no manual max
                            -- anywhere). A nil resolve means "not a
                            -- stacking aura": the lane (not the whole
                            -- entry) degrades away.
                            local stackBarMax
                            if shapes.stackLane then
                                stackBarMax = CooldownCompanion:GetAuraStackBarMax(buttonData)
                                if not stackBarMax then
                                    shapes.stackLane = false
                                    buttonData.auraBar.mode = "duration"
                                end
                            end

                            local holder = EnsureResourceHolder(barInfo.powerType)
                            AnchorHolderToBar(holder, frame,
                                GetResourceHolderInset(barInfo, inset),
                                HOLDER_LEVEL_RESOURCE)
                            -- Orientation from the LAYOUT, not the frame:
                            -- segment-cluster frames never carry the
                            -- _isVertical/_reverseFill fields continuous
                            -- bars do, and every resource bar follows the
                            -- global layout orientation anyway.
                            local vertical = IsVerticalResourceLayout(settings) == true
                            holder._isVertical = vertical
                            holder:Show()

                            local style = BuildResourceOverlayStyleAdapter(
                                entry, settings, barInfo.powerType, shapes)
                            style.barReverseFill = vertical
                                and IsVerticalFillReversed(settings) == true or false
                            local size = style.resourceDisplaySize
                            holder._ccDisplayRect:SetSize(size, size)

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
        return CooldownCompanion:GetAuraStackBarMax(buttonData)
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
        if holder._ccAnchoredFrame == frame then return end
        local settings = GetResourceBarSettings()
        if not settings then return end
        AnchorHolderToBar(holder, frame,
            GetResourceHolderInset(barInfo, GetCustomBarBorderInset(settings)),
            HOLDER_LEVEL_RESOURCE)
        -- Layout-derived, like the collector: cluster frames carry no
        -- _isVertical field for AnchorHolderToBar to read.
        holder._isVertical = IsVerticalResourceLayout(settings) == true
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
