-- Resource aura overlays retain their own stable holders and module lifecycle.
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
        -- Use the explicit layout inputs: a resolved rect can be secret
        -- after the resource is chained behind a native aura container.
        local fw, fh = RB.GetResourceBarSize(frame)
        bounds._ccKitRectW, bounds._ccKitRectH = fw, fh
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

    local function GetResourceBarBorderInset(settings)
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
            holder = CreateFrame("Frame", nil, GetAuraHostRoot(), "DisableUntrustedLayoutScriptsTemplate")
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
        return GetResourceHolderInset(barInfo, GetResourceBarBorderInset(settings)) or 0
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

    function ST._CollectResourceBarAuraWants(wanted)
        local settings = GetResourceBarSettings()
        local collectedResources
        if settings and settings.enabled then
            local inset = GetResourceBarBorderInset(settings)
            for _, barInfo in ipairs(resourceBarFrames) do
                local frame = barInfo and barInfo.frame
                if frame and barInfo.powerType ~= nil
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
        for powerType, holder in pairs(resourceHolders) do
            if not (collectedResources and collectedResources[powerType]) then
                holder:Hide()
            end
        end
    end

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
                GetResourceHolderInset(barInfo, GetResourceBarBorderInset(settings)),
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
    function CooldownCompanion:GetResourceAuraHostRoot()
        return GetAuraHostRoot()
    end

    function CooldownCompanion:SetResourceAuraHostApplied(applied)
        SetAuraHostRootApplied(applied)
    end

    return {
        GetAuraHostRoot = GetAuraHostRoot,
        SetAuraHostRootApplied = SetAuraHostRootApplied,
    }
end
