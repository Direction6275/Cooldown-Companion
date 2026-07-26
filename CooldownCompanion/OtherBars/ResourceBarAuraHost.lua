--[[
    CooldownCompanion - ResourceBarAuraHost
    Custom-bar hosting for the AuraContainer display (the aura pass, Phase 1).

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
local CreateFrame = CreateFrame

local RB = ST._RB

function RB.CreateResourceBarAuraHostModule(deps)
    local resourceBarFrames = deps.resourceBarFrames

    local GetResourceBarSettings = RB.GetResourceBarSettings
    local GetSpecLayoutOrder = RB.GetSpecLayoutOrder
    local GetResourceDisplayValue = RB.GetResourceDisplayValue
    local GetResolvedCustomAuraBarAuraUnit = RB.GetResolvedCustomAuraBarAuraUnit
    local IsSpellCustomBarConfig = RB.IsSpellCustomBarConfig
    local GetResourceSegmentedSmoothing = RB.GetResourceSegmentedSmoothing
    local HidePixelBorders = RB.HidePixelBorders

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
            holders[customBarId] = holder
        end
        return holder
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
        local showStack = cabConfig.showStackText
        if IsSpellCustomBarConfig(cabConfig) then
            showStack = showStack == true
        elseif showStack == nil then
            showStack = cabConfig.showText == true
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

    local function WantsAbsentStackBlocks(barInfo)
        local cabConfig = barInfo and barInfo.cabConfig
        if not (cabConfig and barInfo.customBarId) then return nil end
        if IsSpellCustomBarConfig(cabConfig) then return nil end
        if cabConfig.hideWhenInactive == true then return nil end -- shell: kit renders the whole bar
        if not WantsStackMode(cabConfig, false) then return nil end
        if cabConfig.displayMode == "continuous" then return nil end
        local max = barInfo._ccCabStackMax
        if barInfo._ccCabStackMaxBarId ~= barInfo.customBarId then max = nil end
        if not max or max <= 1 or max > ST.STACK_SEGMENT_ATLAS_MAX then return nil end
        return max
    end

    local function ApplyCustomBarAbsentStackVisuals(barInfo, settings)
        local frame = barInfo and barInfo.frame
        if not frame then return end
        local max = WantsAbsentStackBlocks(barInfo)
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
        local inset = GetCustomBarBorderInset(settings)
        local rect = EnsureInsetRect(frame, inset)

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
        ST.LayoutStackBlocks(blocks, rect, max, frame._isVertical, style.barBgColor)
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
    -- The want collector: called by RunAuraRebind (structurally OOC) after
    -- the panel pass. Appends one want record per live aura-tracked custom
    -- bar, re-anchors holders, refreshes the stack-max cache, and re-lays
    -- the CC-side absent state.
    ------------------------------------------------------------------------

    function ST._CollectCustomBarAuraWants(wanted)
        local settings = GetResourceBarSettings()
        local collected -- customBarId -> true

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
                        local holder = EnsureHolder(barInfo.customBarId)
                        holder:ClearAllPoints()
                        holder:SetPoint("TOPLEFT", frame, "TOPLEFT", inset, -inset)
                        holder:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -inset, inset)
                        holder._isVertical = frame._isVertical == true
                        -- Full bar rect for the kit's shell replicas (the
                        -- shell bg + border ring must match the bar's real
                        -- footprint, not the inset mount) — same field name
                        -- the panel shell branch reads.
                        holder._barBounds = frame
                        -- Above the bar's textLayer (bar+2): the kit must
                        -- render over every CC-side bar visual. Same-strata
                        -- level ordering; the root already matches the
                        -- resource containers' MEDIUM strata.
                        holder:SetFrameLevel(frame:GetFrameLevel() + 3)
                        holder:Show()

                        local style = BuildStyleAdapter(cabConfig, settings)
                        style.barReverseFill = frame._reverseFill or false

                        -- Stack fill max: automatic, game-data resolved,
                        -- OOC (owner ruling — no manual max anywhere).
                        local stackBarMax
                        if CooldownCompanion:IsBarPanelAuraStackDisplay(buttonData) then
                            stackBarMax = CooldownCompanion:GetAuraStackBarMax(buttonData)
                        end
                        barInfo._ccCabStackMax = stackBarMax
                        barInfo._ccCabStackMaxBarId = barInfo.customBarId
                        ApplyCustomBarAbsentStackVisuals(barInfo, settings)

                        -- TEMP DEBUG (aura pass 1B white-fill investigation;
                        -- remove after validation): CC-side decided values
                        -- only — never a read-back from kit regions.
                        local c = style.barAuraColor
                        CooldownCompanion:Print(("aura-host bind %s kind=%s color=%s tex=%s stackMax=%s holder=%dx%d inset=%d"):format(
                            tostring(barInfo.customBarId),
                            buttonData.addedAs or "spell",
                            c and ("%.2f,%.2f,%.2f,%.2f"):format(c[1] or 0, c[2] or 0, c[3] or 0, c[4] or 1)
                                or "nil(kit green default)",
                            tostring(style.barTexture), tostring(stackBarMax),
                            holder:GetWidth() + 0.5, holder:GetHeight() + 0.5, inset))

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
    end

    -- Late-bound seam for FinalizeAppliedBarVisibility (the customBars
    -- module is created before this one; it looks the function up on RB at
    -- call time).
    RB.ApplyCustomBarAbsentStackVisuals = ApplyCustomBarAbsentStackVisuals

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
