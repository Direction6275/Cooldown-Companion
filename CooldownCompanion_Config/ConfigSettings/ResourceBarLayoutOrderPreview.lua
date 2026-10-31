--[[
    CooldownCompanion - ResourceBarLayoutOrderPreview
    The bars workspace canvas (Independent Resources stack and Cast Bar)
    and the resource and cast painters the panel module preview reuses.
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon
local CS = ST._configState
local RB = ST._RB
local RBP = ST._RBP

local math_floor = math.floor
local math_min = math.min
local math_max = math.max
local table_insert = table.insert
local table_sort = table.sort

local GetConfigActiveResources = RBP.GetConfigActiveResources
local IsResourceBarVerticalConfig = RBP.IsResourceBarVerticalConfig

local StartDragTracking = ST._StartDragTracking
local CancelDrag = ST._CancelDrag
local HideDragIndicator = ST._HideDragIndicator

local POWER_NAMES = RB.POWER_NAMES
local SEGMENTED_TYPES = RB.SEGMENTED_TYPES
local RESOURCE_HEALTH = RB.RESOURCE_HEALTH
local RESOURCE_MAELSTROM_WEAPON = RB.RESOURCE_MAELSTROM_WEAPON

local GetResourceGlobalThickness = RB.GetResourceGlobalThickness
local GetResourceColors = RB.GetResourceColors
local CreateContinuousBar = RB.CreateContinuousBar
local CreateSegmentedBar = RB.CreateSegmentedBar
local LayoutSegments = RB.LayoutSegments
local CreateOverlayBar = RB.CreateOverlayBar
local LayoutOverlaySegments = RB.LayoutOverlaySegments
local StyleContinuousBar = RB.StyleContinuousBar
local StyleHealthBar = RB.StyleHealthBar
local StyleSegmentedBar = RB.StyleSegmentedBar
local ApplyPreviewBarState = RB.ApplyPreviewBarState
local GetMWMaxStacks = RB.GetMWMaxStacks

-- The bars workspace canvas draws an Independent Resources stack or an
-- Independent Cast Bar. A module on a panel is drawn in that panel's
-- workspace instead, by the panel module preview at the end of this file,
-- which reuses this file's resource and cast painters.
local function IsBarsWorkspaceActive()
    return CS.barsEntrySelected == true
end

local LAYOUT_PREVIEW_PADDING = 12
local LAYOUT_PREVIEW_GAP = 4
local LAYOUT_PREVIEW_DRAG_KIND = "layout-slot"
local LAYOUT_PREVIEW_ICON_FALLBACK = "Interface\\Icons\\INV_Misc_QuestionMark"
local LAYOUT_PREVIEW_ANIM_DURATION = 0.08
local LAYOUT_PREVIEW_EMPTY_DROP_SIZE = 8

-- The cast facsimile. A cast bar has no ready state, so the resting slot
-- shows a cast frozen part-way — enough to judge and to drag. The preview
-- state runs the same cast on a loop.
local CAST_PREVIEW_DURATION = 1.5
local CAST_PREVIEW_REST_FILL = 0.65
local CAST_PREVIEW_SPELL_NAME = "Preview Cast"

local GetLayoutPreviewIcon

local function CloneColor(color, fallback)
    if type(color) ~= "table" then
        return fallback and { fallback[1], fallback[2], fallback[3], fallback[4] } or nil
    end
    return {
        color[1] or (fallback and fallback[1]) or 0,
        color[2] or (fallback and fallback[2]) or 0,
        color[3] or (fallback and fallback[3]) or 0,
        color[4] ~= nil and color[4] or (fallback and fallback[4]) or 1,
    }
end

local function TintColor(color, amount, alpha)
    color = CloneColor(color, { 0.12, 0.12, 0.12, 1 })
    local mul = amount or 0
    return {
        math_max(0, math_min(1, color[1] + mul)),
        math_max(0, math_min(1, color[2] + mul)),
        math_max(0, math_min(1, color[3] + mul)),
        alpha ~= nil and alpha or color[4],
    }
end

local function ApplyBackdrop(frame, bg, border, edgeSize)
    if not frame then return end
    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = edgeSize or 1,
    })
    frame:SetBackdropColor((bg and bg[1]) or 0, (bg and bg[2]) or 0, (bg and bg[3]) or 0, (bg and bg[4]) or 1)
    frame:SetBackdropBorderColor((border and border[1]) or 0, (border and border[2]) or 0, (border and border[3]) or 0, (border and border[4]) or 1)
end

local function ResolvePreviewSkin(host)
    local frames = {
        host,
        host and host:GetParent(),
        CS.configFrame and CS.configFrame.col3 and CS.configFrame.col3.frame,
        CS.configFrame and CS.configFrame.col3 and CS.configFrame.col3.content,
    }

    local baseBg
    local baseBorder
    for _, frame in ipairs(frames) do
        if frame and frame.GetBackdropColor then
            local r, g, b, a = frame:GetBackdropColor()
            if r then
                baseBg = { r, g, b, a }
                break
            end
        end
    end
    for _, frame in ipairs(frames) do
        if frame and frame.GetBackdropBorderColor then
            local r, g, b, a = frame:GetBackdropBorderColor()
            if r then
                baseBorder = { r, g, b, a }
                break
            end
        end
    end

    baseBg = baseBg or { 0.08, 0.08, 0.10, 0.92 }
    baseBorder = baseBorder or { 0.25, 0.25, 0.28, 1 }

    return {
        slotBg = TintColor(baseBg, 0.01, 0.94),
        slotBorder = TintColor(baseBorder, 0.02, 1),
        slotHover = { 0.38, 0.60, 0.92, 1 },
        gapBg = TintColor(baseBg, 0.03, 0.28),
        gapBorder = { 0.38, 0.60, 0.92, 0.95 },
        ghostBg = TintColor(baseBg, 0.03, 0.96),
        ghostBorder = TintColor(baseBorder, 0.04, 1),
    }
end

-- Bottom chrome on the host claims a band the composition must stay clear
-- of. Two owners can claim it, each from its own corner: the preview
-- command center (bottom-left, on every workspace that has one) and the
-- bars workspace's module-enable cluster (bottom-right). They share one
-- band, so the reserve is whichever needs more. Hosts with neither report 0.
local function GetHostBottomReserve(host)
    if not host then return 0 end
    return math_max(host._cdcPreviewReserveBottom or 0,
        host._cdcBarsCornerReserveBottom or 0)
end

local function ApplyHostBottomReserve(host, root)
    root:ClearAllPoints()
    root:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0)
    root:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", 0, GetHostBottomReserve(host))
end

local function EnsurePreviewState(host)
    local preview = host._cdcLayoutPreview
    if preview then
        preview.buildId = (preview.buildId or 0) + 1
        preview.skin = ResolvePreviewSkin(host)
        ApplyHostBottomReserve(host, preview.root)
        return preview
    end

    preview = {
        buildId = 1,
        pools = {
            containers = {},
            slots = {},
            gaps = {},
            pills = {},
        },
        used = {},
        tweens = {},
        -- Slots whose rendered state is time-driven: the Active Aura
        -- stand-in's pulse and colour shift, the low-health alert, the cast
        -- sweep. Rebuilt every pass, ticked by TickPreview while non-empty.
        animated = {},
        skin = ResolvePreviewSkin(host),
    }
    host._cdcLayoutPreview = preview

    -- The root already carries the host's bottom reserve, so the content
    -- block centers into it with a zero offset - which stays exact under
    -- the fit-to-host scale, where a non-zero anchor offset would be
    -- measured in the scaled frame's own coordinate space and have to be
    -- divided back out.
    local root = CreateFrame("Frame", nil, host)
    root:SetClipsChildren(false)
    root:Hide()
    ApplyHostBottomReserve(host, root)
    preview.root = root

    local ghost = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    ghost:SetFrameStrata("TOOLTIP")
    ghost:SetFrameLevel(2000)
    ghost:SetClipsChildren(false)
    ghost:EnableMouse(false)
    ghost:Hide()
    preview.ghost = ghost

    return preview
end

local function ResetPreviewState(preview)
    preview.used.containers = 0
    preview.used.slots = 0
    preview.used.gaps = 0
    preview.used.pills = 0
    preview.renderedSelectionKeys = {}
    preview.independentResources = false
    preview.layoutDrag = nil
    preview.animated = preview.animated or {}
    wipe(preview.animated)
    -- Fresh static layout: discard any tweens the canceled drag queued so they
    -- can't replay against the rebuilt slot positions once the animation
    -- driver re-arms (the drop path cancels the drag mid-rebuild, so its
    -- settle tweens target pre-rebuild geometry and parents).
    wipe(preview.tweens)
    preview.root:Show()
    preview.root:SetScript("OnUpdate", nil)
end

local function FinalizePreviewState(preview)
    for poolName, pool in pairs(preview.pools) do
        local used = preview.used[poolName] or 0
        for index = used + 1, #pool do
            local frame = pool[index]
            frame:Hide()
            frame:ClearAllPoints()
            frame:SetParent(preview.root)
            frame:SetScript("OnMouseDown", nil)
            frame:SetScript("OnMouseUp", nil)
            frame:SetScript("OnEnter", nil)
            frame:SetScript("OnLeave", nil)
        end
    end
end

local function AcquireContainer(preview, parent)
    local pool = preview.pools.containers
    local index = (preview.used.containers or 0) + 1
    preview.used.containers = index
    local frame = pool[index]
    if not frame then
        frame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
        frame:SetClipsChildren(false)
        pool[index] = frame
    end
    -- Containers are pooled across builds and change roles (the content
    -- frame, the lanes), so acquire clears the scripts, mouse capture and
    -- backdrop an earlier tenant set. Consumers that want them re-apply
    -- after acquiring.
    frame:EnableMouse(false)
    frame:SetScript("OnEnter", nil)
    frame:SetScript("OnLeave", nil)
    frame:SetScript("OnMouseDown", nil)
    frame:SetScript("OnMouseUp", nil)
    frame:SetBackdrop(nil)
    frame:SetParent(parent)
    frame:Show()
    return frame
end

local function CreateSlotFrame(parent)
    local frame = CreateFrame("Button", nil, parent, "BackdropTemplate")
    frame:SetClipsChildren(false)
    frame:RegisterForClicks("LeftButtonDown", "AnyUp")

    frame.previewCanvas = CreateFrame("Frame", nil, frame)
    frame.previewCanvas:SetClipsChildren(false)

    frame.hoverHighlight = CreateFrame("Frame", nil, frame)
    frame.hoverHighlight:SetAllPoints(frame.previewCanvas)
    frame.hoverHighlight:EnableMouse(false)
    frame.hoverHighlight.tex = frame.hoverHighlight:CreateTexture(nil, "OVERLAY")
    frame.hoverHighlight.tex:SetAllPoints()
    frame.hoverHighlight.tex:SetColorTexture(1, 1, 1, 0.10)
    frame.hoverHighlight.tex:SetBlendMode("ADD")
    frame.hoverHighlight:Hide()

    -- Selection marker: the hover-style glow held on while the bar is
    -- selected, plus inward-pointing arrows flanking it. Elevated like
    -- hoverHighlight so it renders above the bar visuals.
    frame.selectedHighlight = CreateFrame("Frame", nil, frame)
    frame.selectedHighlight:SetAllPoints(frame.previewCanvas)
    frame.selectedHighlight:EnableMouse(false)
    frame.selectedHighlight.tex = frame.selectedHighlight:CreateTexture(nil, "OVERLAY")
    frame.selectedHighlight.tex:SetAllPoints()
    frame.selectedHighlight.tex:SetColorTexture(1, 1, 1, 0.10)
    frame.selectedHighlight.tex:SetBlendMode("ADD")
    frame.selectedHighlight.side1 = frame.selectedHighlight:CreateTexture(nil, "OVERLAY")
    frame.selectedHighlight.side2 = frame.selectedHighlight:CreateTexture(nil, "OVERLAY")
    frame.selectedHighlight:Hide()

    return frame
end

local function AcquireSlot(preview, parent)
    local pool = preview.pools.slots
    local index = (preview.used.slots or 0) + 1
    preview.used.slots = index
    local frame = pool[index]
    if not frame then
        frame = CreateSlotFrame(parent)
        pool[index] = frame
    end
    frame:SetParent(parent)
    frame:Show()
    frame:SetScript("OnMouseDown", nil)
    frame:SetScript("OnEnter", nil)
    frame:SetScript("OnLeave", nil)
    return frame
end

local function AcquireGap(preview, parent)
    local pool = preview.pools.gaps
    local index = (preview.used.gaps or 0) + 1
    preview.used.gaps = index
    local frame = pool[index]
    if not frame then
        frame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
        frame.text = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        frame.text:SetPoint("CENTER")
        frame.text:SetText("Drop")
        pool[index] = frame
    end
    frame:SetParent(parent)
    frame:Show()
    frame.text:Hide()
    return frame
end

-- The bars workspace's module-enable pills, pinned to the pane's
-- bottom-right corner. Everything else this workspace can configure but is
-- not drawing right now goes to the quiet text-chip strip in the editing
-- surface, not here.
--
local BARS_PILL_MIN_WIDTH = 112
local BARS_PILL_GAP = 10
local BARS_PILL_LINE_GAP = 6
local BARS_PILL_INSET = 9
local BARS_PILL_ACCENT_WIDTH = 3
local BARS_PILL_ICON_SIZE = 16
local BARS_PILL_ICON_GAP = 5
local BARS_PILL_TEXT_COLOR = { 0.70, 0.68, 0.64 }
local BARS_PILL_SELECTED_TEXT_COLOR = { 1, 1, 1 }
local BARS_PILL_NEUTRAL_ACCENT = { 0.46, 0.48, 0.53 }
local BARS_PILL_ENABLE_ACCENT = { 0.36, 0.72, 0.45 }
-- Selection border: the same blue the canvas slots use for hover/selection.
local BARS_PILL_SELECTED_BORDER = { 0.38, 0.60, 0.92, 1 }

-- The module-enable cluster mirrors the preview command center across the
-- pane: same bottom band, same insets off its own corner, so the two read
-- as one line of chrome framing the canvas. Matching that band is why
-- these pills are the bar's height.
-- Its lines stack upward when the pane is too narrow for one row.
local BARS_CORNER_PILL_HEIGHT = 20
local BARS_CORNER_BOTTOM_INSET = 3
local BARS_CORNER_SIDE_INSET = 4
local BARS_CORNER_COMMAND_GAP = 12

-- Re-attached on every acquire: FinalizePreviewState strips these from
-- pooled frames it parks, so a pill reused by a later build would come back
-- without its hover state or tooltip.
local function BarsPillOnEnter(self)
    self.hover:Show()
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(self._cdcTooltip or "", 1, 1, 1)
    if self._cdcTooltipLine then
        GameTooltip:AddLine(self._cdcTooltipLine, 0.75, 0.82, 0.92, true)
    end
    if self._cdcTooltipNote then
        GameTooltip:AddLine(self._cdcTooltipNote, 0.62, 0.62, 0.66, true)
    end
    GameTooltip:Show()
end

local function BarsPillOnLeave(self)
    self.hover:Hide()
    GameTooltip:Hide()
end

local function CreateBarsPill(parent)
    local frame = CreateFrame("Button", nil, parent, "BackdropTemplate")
    frame:RegisterForClicks("AnyUp")
    frame:SetClipsChildren(false)

    frame.accent = frame:CreateTexture(nil, "ARTWORK")
    frame.accent:SetWidth(BARS_PILL_ACCENT_WIDTH)
    frame.accent:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -1)
    frame.accent:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 1, 1)

    frame.icon = frame:CreateTexture(nil, "ARTWORK")
    frame.icon:SetSize(BARS_PILL_ICON_SIZE, BARS_PILL_ICON_SIZE)
    frame.icon:SetPoint("LEFT", frame, "LEFT", BARS_PILL_ACCENT_WIDTH + BARS_PILL_ICON_GAP, 0)
    frame.icon:Hide()

    frame.label = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frame.label:SetJustifyH("CENTER")
    frame.label:SetJustifyV("MIDDLE")
    frame.label:SetWordWrap(false)

    frame.hover = frame:CreateTexture(nil, "OVERLAY")
    frame.hover:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -1)
    frame.hover:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -1, 1)
    frame.hover:SetColorTexture(1, 1, 1, 0.10)
    frame.hover:SetBlendMode("ADD")
    frame.hover:Hide()

    frame.selected = frame:CreateTexture(nil, "OVERLAY", nil, 1)
    frame.selected:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -1)
    frame.selected:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -1, 1)
    frame.selected:SetColorTexture(1, 1, 1, 0.10)
    frame.selected:SetBlendMode("ADD")
    frame.selected:Hide()

    return frame
end

local function AcquireBarsPill(preview, parent)
    local pool = preview.pools.pills
    local index = (preview.used.pills or 0) + 1
    preview.used.pills = index
    local frame = pool[index]
    if not frame then
        frame = CreateBarsPill(parent)
        pool[index] = frame
    end
    frame:SetParent(parent)
    frame:SetScript("OnEnter", BarsPillOnEnter)
    frame:SetScript("OnLeave", BarsPillOnLeave)
    frame.hover:Hide()
    frame:Show()
    return frame
end

-- The root already stops short of the host's bottom band, so a message
-- centered in it never collides with the chrome pinned down there.
local function SetPreviewMessage(preview, message)
    local label = preview.messageLabel
    if not label then
        label = preview.root:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        label:SetJustifyH("CENTER")
        label:SetJustifyV("MIDDLE")
        label:SetWordWrap(true)
        preview.messageLabel = label
    end
    label:ClearAllPoints()
    label:SetPoint("TOPLEFT", preview.root, "TOPLEFT", 18, -18)
    label:SetPoint("BOTTOMRIGHT", preview.root, "BOTTOMRIGHT", -18, 18)
    label:SetText(message or "")
    label:Show()
end

local function HidePreviewMessage(preview)
    if preview.messageLabel then
        preview.messageLabel:Hide()
    end
end

GetLayoutPreviewIcon = function(buttonData)
    if buttonData and buttonData.rotationAssistant then return ST.ROTATION_ASSISTANT_FALLBACK_ICON end
    if not buttonData then
        return LAYOUT_PREVIEW_ICON_FALLBACK
    end

    local icon
    if buttonData.type == "spell" then
        icon = C_Spell.GetSpellTexture(buttonData.id)
    elseif CooldownCompanion.IsEquipmentSlotEntry
        and CooldownCompanion.IsEquipmentSlotEntry(buttonData) then
        local effectiveItem = CooldownCompanion.ResolveEffectiveItem
            and CooldownCompanion.ResolveEffectiveItem(buttonData, true) or nil
        if effectiveItem and effectiveItem.trackable then
            icon = effectiveItem.icon
        end
    elseif buttonData.type == "item" then
        icon = C_Item.GetItemIconByID(buttonData.id)
    end

    if buttonData.manualIcon then
        icon = buttonData.manualIcon
    end

    return icon or LAYOUT_PREVIEW_ICON_FALLBACK
end

local function GetPreviewPanelId()
    if not IsBarsWorkspaceActive() and CS.selectedGroup then return CS.selectedGroup end
    local kind = IsBarsWorkspaceActive() and CS.barWorkspaceKind or "resources"
    return CooldownCompanion:ResolveModulePanel(kind or "resources").panelId
end

local function ModuleBelongsToPreview(kind, panelId, forSettings, settings)
    if forSettings then
        local target = CooldownCompanion:ResolveModulePanel(kind, nil, { configured = true, settings = settings })
        return target.eligible == true and target.panelId == panelId and target.mode ~= "independent"
    end
    local target = CooldownCompanion:ResolveModulePanel(kind)
    return target.group ~= nil and target.panelId == panelId and target.mode ~= "independent"
end

-- Both resource lists keep listing BOTH halves of a mutually exclusive pair
-- (the runtime filter that drops the hidden half lives in ApplyResourceBars),
-- but the pair is one bar in the world and therefore one slot here. Drop the
-- half that proxies its placement onto the other; the surviving slot draws as
-- whichever half is currently live. Two slots is what let the pair be ordered
-- against Fury twice, so the canvas and the stack disagreed the moment the
-- player entered or left meta. Shared so the slot builder and the lane
-- enumeration below can never collapse differently.
local function CollapseToPlacementPowerTypes(powerTypes)
    local placementResources = {}
    for _, pt in ipairs(powerTypes) do
        if RB.GetCanonicalPowerType(pt) == pt then
            placementResources[#placementResources + 1] = pt
        end
    end
    return placementResources
end

local function CollectPreviewSlots(rbSettings, cbSettings, layout, isVerticalLayout, includeResourceSlots,
    requireRuntimeEligibleSlots, geometryHost)
    includeResourceSlots = includeResourceSlots == true
    local activeResources = CollapseToPlacementPowerTypes(includeResourceSlots
        and (requireRuntimeEligibleSlots and RB.DetermineActiveResources(rbSettings) or GetConfigActiveResources())
        or {})
    local primarySlots = {}
    local castSlots = {}
    local resourceBarsEnabled = includeResourceSlots and rbSettings and rbSettings.enabled

    if includeResourceSlots then
        layout.resources = layout.resources or {}
        rbSettings = rbSettings or {}
        rbSettings.resources = rbSettings.resources or {}
    end

    local function ResolveSlotThickness(powerType)
        return ST.ResolveResourceBarGeometry(rbSettings, layout, powerType,
            geometryHost or ST.GetModuleGeometryHost("resources")).thickness
    end

    for _, powerType in ipairs(activeResources) do
        -- `powerType` is the slot's PLACEMENT identity throughout (the entry
        -- every drag reads and writes); `renderType` is the half the slot
        -- currently DRAWS as. They differ only for a mutually exclusive pair
        -- while its non-canonical half is the one up in the world, so the
        -- canvas shows Collapsing Star in meta and Void Metamorphosis out of
        -- it, both times in the pair's single slot. Everything the eye reads
        -- — enabled state, name, color, icon, shape — follows renderType,
        -- because those live per half in settings.resources.
        local renderType = RB.GetPlacementRenderPowerType(powerType)
        local showResource = resourceBarsEnabled and RB.IsResourceEnabled(renderType, rbSettings)

        if showResource then
            local function EnsureLayoutResource()
                layout.resources[powerType] = layout.resources[powerType] or {}
                return layout.resources[powerType]
            end

            table_insert(primarySlots, {
                -- Keyed by what the slot DRAWS, not by where it stores: the
                -- id is a per-build handle (drag identity, frame map, and
                -- the "Not currently shown:" strip's rendered set), never
                -- saved. Keying it to the placement half would have left the
                -- hidden half's chip missing and the visible half's chip
                -- offered while it was on screen.
                id = "resource:" .. tostring(renderType),
                slotCategory = "primary",
                kind = "resource",
                powerType = renderType,
                label = POWER_NAMES[renderType] or ("Power " .. renderType),
                thickness = ResolveSlotThickness(powerType),
                getPos = function()
                    local slot = layout.resources[powerType]
                    if isVerticalLayout then
                        local pos = slot and slot.verticalPosition
                        if pos == "left" or pos == "right" then
                            return pos
                        end
                        return (slot and slot.position == "above") and "left" or "right"
                    end
                    return (slot and slot.position) or "below"
                end,
                getOrder = function()
                    local slot = layout.resources[powerType]
                    if isVerticalLayout then
                        return (slot and slot.verticalOrder) or (slot and slot.order) or (900 + powerType)
                    end
                    return (slot and slot.order) or (900 + powerType)
                end,
                setPos = function(value)
                    local slot = EnsureLayoutResource()
                    if isVerticalLayout then
                        slot.verticalPosition = value
                    else
                        slot.position = value
                    end
                end,
                setOrder = function(value)
                    local slot = EnsureLayoutResource()
                    if isVerticalLayout then
                        slot.verticalOrder = value
                    else
                        slot.order = value
                    end
                end,
            })
        end
    end

    if cbSettings and cbSettings.enabled and (not CooldownCompanion:IsModuleAnchorIndependent("castbar")
        or (IsBarsWorkspaceActive() and CS.barWorkspaceKind == "castbar")) then
        table_insert(castSlots, {
            id = "cast",
            slotCategory = "cast",
            kind = "cast",
            label = "Cast Bar",
            -- The cast bar's own height, not the stack's: it used to be
            -- folded into one max with the resource thickness, which
            -- clamped every bar up to whichever was taller.
            thickness = ST.ResolveCastBarGeometry(cbSettings, ST.GetModuleGeometryHost("castbar")).thickness,
            icon = LAYOUT_PREVIEW_ICON_FALLBACK,
            getPos = function()
                return (layout.castBar and layout.castBar.position) or "below"
            end,
            getOrder = function()
                return (layout.castBar and layout.castBar.order) or 2000
            end,
            setPos = function(value)
                -- Pin the displayed screen Y before a side change. Legacy
                -- character defaults otherwise flip their sign on drop.
                local _, _, offset = ST.GetCastBarAttachmentOffset(cbSettings, layout)
                layout.castBar = layout.castBar or { position = "below", order = 2000 }
                layout.castBar.panelAnchorScreenYOffset = offset
                layout.castBar.panelAnchorYOffset = nil
                layout.castBar.position = value
            end,
            setOrder = function(value)
                layout.castBar = layout.castBar or { position = "below", order = 2000 }
                layout.castBar.order = value
            end,
        })
    end

    for _, slots in ipairs({ primarySlots, castSlots }) do
        for _, slot in ipairs(slots) do
            local independent = not geometryHost and (slot.kind == "cast" and CooldownCompanion:IsModuleAnchorIndependent("castbar")
                or slot.kind ~= "cast" and CooldownCompanion:IsResourceBarAnchorIndependent())
            slot.anchorGroup = geometryHost or CooldownCompanion:ResolveModulePanel(slot.kind == "cast" and "castbar" or "resources").group
            if not independent and (slot.kind == "cast" or not isVerticalLayout) then
                ST._ConfigureAttachedBarPreviewSlot(slot, function()
                    if slot.kind == "cast" then
                        layout.castBar = layout.castBar or { position = "below", order = 2000 }
                        return layout.castBar
                    end
                    local pt = RB.GetCanonicalPowerType(slot.powerType)
                    layout.resources[pt] = layout.resources[pt] or {}
                    return layout.resources[pt]
                end)
            end
        end
    end
    return primarySlots, castSlots
end

-- Stack sections. Fixed bars rank by their anchor region, and the cast bar
-- anchors past everything: the stack reserves no space for an interleaved
-- cast bar, so the far end is the only slot live geometry can honour (owner
-- ruling 2026-08-09). Order values alone cannot express that, so the sort
-- ranks sections first and orders within a section second — ALWAYS, so this
-- canvas can never show an arrangement the live stack cannot render. A lane
-- of fixed bars in one region has one rank and still sorts purely on order.
local STACK_RANK_FIXED = 0
local STACK_RANK_CAST = 1
local function GetSlotStackRank(slot, regionOverride)
    if slot.kind == "cast" then return STACK_RANK_CAST end
    local region = regionOverride
    if region == nil then region = slot.getRegionRank and slot.getRegionRank() or 0 end
    return STACK_RANK_FIXED + region * 0.25
end

-- Sections run the same direction the lane does: on a reversed lane index 1
-- is the slot furthest from the panel, so the cast bar has to come first there
-- and last everywhere else.
local function CompareStackRank(a, b, reversed)
    local aRank = GetSlotStackRank(a)
    local bRank = GetSlotStackRank(b)
    if aRank == bRank then
        return nil
    end
    if reversed then
        return aRank > bRank
    end
    return aRank < bRank
end

local function SortSlotsForIndependentStack(slots, firstSide, secondSide, preview)
    local firstCount = 0
    local secondCount = 0
    local out = {}
    for _, slot in ipairs(slots) do
        local side = slot.getPos()
        if side == firstSide then
            firstCount = firstCount + 1
        elseif side == secondSide then
            secondCount = secondCount + 1
        end
        table_insert(out, slot)
    end

    -- Preserve the visual direction of the side that already owns the
    -- stack. Ties use the normal below/right direction.
    local side = firstCount > secondCount and firstSide or secondSide
    local reversed = side == firstSide
    table_sort(out, function(a, b)
        local rankResult = CompareStackRank(a, b, reversed)
        if rankResult ~= nil then
            return rankResult
        end
        local aOrder = a.getOrder()
        local bOrder = b.getOrder()
        if aOrder ~= bOrder then
            -- Not `reversed and a>b or a<b`: that parses as `(reversed and
            -- a>b) or (a<b)`, which answers true for BOTH orderings of an
            -- unequal pair when reversed, and table.sort rejects such a
            -- comparator ("invalid order function").
            if reversed then return aOrder > bOrder end
            return aOrder < bOrder
        end
        return tostring(a.id) < tostring(b.id)
    end)
    return out, side, reversed
end

local function ApplySlotGeometry(frame, parent, x, y, width, height, alpha)
    frame:SetParent(parent)
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    frame:SetSize(width, height)
    frame:SetAlpha(alpha or 1)
    frame._cdcPreviewParent = parent
    frame._cdcPreviewX = x
    frame._cdcPreviewY = y
    frame._cdcPreviewW = width
    frame._cdcPreviewH = height
    frame._cdcPreviewA = alpha or 1
end

local function QueueSlotTween(preview, frame, parent, x, y, width, height, alpha, duration)
    local currentParent = frame._cdcPreviewParent
    if currentParent ~= parent or not frame._cdcPreviewX then
        ApplySlotGeometry(frame, parent, x, y, width, height, alpha)
        preview.tweens[frame] = nil
        return
    end

    local currentX = frame._cdcPreviewX
    local currentY = frame._cdcPreviewY
    local currentW = frame._cdcPreviewW
    local currentH = frame._cdcPreviewH
    local currentA = frame._cdcPreviewA

    if math.abs(currentX - x) < 0.5
        and math.abs(currentY - y) < 0.5
        and math.abs(currentW - width) < 0.5
        and math.abs(currentH - height) < 0.5
        and math.abs((currentA or 1) - (alpha or 1)) < 0.02 then
        ApplySlotGeometry(frame, parent, x, y, width, height, alpha)
        preview.tweens[frame] = nil
        return
    end

    preview.tweens[frame] = {
        parent = parent,
        sx = currentX,
        sy = currentY,
        sw = currentW,
        sh = currentH,
        sa = currentA or 1,
        tx = x,
        ty = y,
        tw = width,
        th = height,
        ta = alpha or 1,
        t0 = GetTime(),
        dur = duration or LAYOUT_PREVIEW_ANIM_DURATION,
    }
end

local function EaseInOut(t)
    return t < 0.5 and (2 * t * t) or (1 - (((-2 * t + 2) ^ 2) / 2))
end

local function Interpolate(a, b, t)
    return a + ((b - a) * t)
end

local function UpdateGhostPosition(ghost)
    if not (ghost and ghost:IsShown()) then
        return
    end
    local scale = UIParent:GetEffectiveScale()
    local cursorX, cursorY = GetCursorPosition()
    cursorX = cursorX / scale
    cursorY = cursorY / scale
    local offsetX = math_floor((ghost:GetWidth() or 0) / 2)
    local offsetY = math_floor((ghost:GetHeight() or 0) / 2)
    ghost:ClearAllPoints()
    ghost:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", cursorX - offsetX, cursorY + offsetY)
end

-- The panel preview (ButtonPanelPreviewShared) shares the tween curve and
-- the drag ghost.
ST._PreviewEaseInOut = EaseInOut
ST._PreviewInterpolate = Interpolate
ST._UpdatePreviewGhostPosition = UpdateGhostPosition

local function TickPreview(preview)
    local activeTween = false
    local now = GetTime()

    for frame, tween in pairs(preview.tweens) do
        local progress = math_min(1, math_max(0, (now - tween.t0) / tween.dur))
        local eased = EaseInOut(progress)
        ApplySlotGeometry(
            frame,
            tween.parent,
            Interpolate(tween.sx, tween.tx, eased),
            Interpolate(tween.sy, tween.ty, eased),
            Interpolate(tween.sw, tween.tw, eased),
            Interpolate(tween.sh, tween.th, eased),
            Interpolate(tween.sa, tween.ta, eased)
        )
        if progress >= 1 then
            preview.tweens[frame] = nil
        else
            activeTween = true
        end
    end

    UpdateGhostPosition(preview.ghost)

    for _, entry in ipairs(preview.animated) do
        entry.Tick(entry, now)
    end

    if not activeTween and not preview.ghostActive and #preview.animated == 0 then
        preview.root:SetScript("OnUpdate", nil)
    end
end

-- One OnUpdate closure per preview table (long-lived on its host), so a drag
-- does not allocate a new one every frame.
local function GetPreviewTick(preview)
    local tick = preview.tick
    if not tick then
        tick = function() TickPreview(preview) end
        preview.tick = tick
    end
    return tick
end

-- A running preview keeps the ticker alive on its own, independently of the
-- drag tweens that otherwise own it.
local function StartPreviewAnimationDriver(preview)
    if #preview.animated == 0 then
        return
    end
    preview.root:SetScript("OnUpdate", GetPreviewTick(preview))
end

local function ConfigureSlotChrome(frame)
    ApplyBackdrop(frame, { 0, 0, 0, 0 }, { 0, 0, 0, 0 })
    if frame.hoverHighlight then
        frame.hoverHighlight:SetFrameLevel(frame:GetFrameLevel() + 20)
        frame.hoverHighlight:Hide()
    end
    if frame.selectedHighlight then
        frame.selectedHighlight:SetFrameLevel(frame:GetFrameLevel() + 19)
        frame.selectedHighlight:Hide()
    end
    frame.previewCanvas:ClearAllPoints()
    frame.previewCanvas:SetAllPoints(frame)
end

local function HideUnusedSlotVisuals(frame)
    if frame.previewBarInfo and frame.previewBarInfo.frame then
        frame.previewBarInfo.frame:Hide()
    end
    if frame.castPreview and frame.castPreview.root then
        frame.castPreview.root:Hide()
    end
end


-- A shape change swaps the slot's renderer. The outgoing one is parked on the
-- row by shape, so toggling back reuses it instead of orphaning a frame on
-- every change; the caller restyles, resizes and shows whichever it gets.
local function SwapPreviewRenderer(frame, barInfo, barType, powerType, segmentCount, create, ...)
    local parked = frame._parkedPreviewRenderers
    if not parked then
        parked = {}
        frame._parkedPreviewRenderers = parked
    end
    if barInfo and barInfo.frame then
        barInfo.frame:Hide()
        local outgoing = barInfo.frame.segments and #barInfo.frame.segments or 0
        parked[barInfo.barType .. ":" .. outgoing] = barInfo.frame
    end
    local key = barType .. ":" .. (segmentCount or 0)
    local renderer = parked[key]
    parked[key] = nil
    return { frame = renderer or create(...), barType = barType, powerType = powerType }
end
local function EnsureResourcePreview(frame, slot, preview, width, height)
    HideUnusedSlotVisuals(frame)

    local barInfo = frame.previewBarInfo
    local rbSettings = preview.rbSettings
    local layout = preview.layout
    local segmentGap = ST.ResolveResourceSegmentGap(rbSettings, layout, slot.powerType, slot.anchorGroup)
    -- Overview depicts the configured panel, which may differ from the live
    -- fallback. Resolve once and carry that appearance through every painter.
    local spec = CooldownCompanion._currentSpecId
    local host = ST.PanelSupportsAttachedBars(slot.anchorGroup) and slot.anchorGroup or false
    local style, panel, object = ST.ResolveModuleBarStyle("resources", rbSettings, slot.powerType, spec, host)
    local appearance = { style = style, panel = panel, object = object, spec = spec }

    if slot.powerType == 101 then
        if not barInfo or barInfo.barType ~= "stagger_continuous" then
            barInfo = SwapPreviewRenderer(frame, barInfo, "stagger_continuous", slot.powerType, nil,
                CreateContinuousBar, frame.previewCanvas)
        end
        RB.SetResourceBarSize(barInfo.frame, width, height)
        StyleContinuousBar(barInfo.frame, slot.powerType, rbSettings, nil, appearance)
    elseif slot.powerType == RESOURCE_HEALTH then
        if not barInfo or barInfo.barType ~= "health_continuous" then
            barInfo = SwapPreviewRenderer(frame, barInfo, "health_continuous", slot.powerType, nil,
                CreateContinuousBar, frame.previewCanvas)
        end
        RB.SetResourceBarSize(barInfo.frame, width, height)
        StyleHealthBar(barInfo.frame, rbSettings, appearance)
    elseif slot.powerType == RESOURCE_MAELSTROM_WEAPON then
        -- Mirrors the three real MW shapes exactly (ResourceBar.lua's apply
        -- branch); the canvas must show the shape the bar will actually be.
        local mwMaxStacks = GetMWMaxStacks() or 5
        local mwStyle = RB.GetMWDisplayStyle(rbSettings)
        if mwStyle == "continuous" then
            if not barInfo or barInfo.barType ~= "mw_continuous" then
                barInfo = SwapPreviewRenderer(frame, barInfo, "mw_continuous", slot.powerType, nil,
                    CreateContinuousBar, frame.previewCanvas)
            end
            RB.SetResourceBarSize(barInfo.frame, width, height)
            StyleContinuousBar(barInfo.frame, slot.powerType, rbSettings, nil, appearance)
        elseif mwStyle == "segments" then
            if not barInfo or barInfo.barType ~= "mw_segments"
                or #barInfo.frame.segments ~= mwMaxStacks then
                barInfo = SwapPreviewRenderer(frame, barInfo, "mw_segments", slot.powerType, mwMaxStacks,
                    CreateSegmentedBar, frame.previewCanvas, mwMaxStacks)
            end
            RB.SetResourceBarSize(barInfo.frame, width, height)
            LayoutSegments(barInfo.frame, width, height, segmentGap, rbSettings, slot.powerType, appearance)
            local baseColor = GetResourceColors(RESOURCE_MAELSTROM_WEAPON, rbSettings)
            for i = 1, mwMaxStacks do
                barInfo.frame.segments[i]:SetStatusBarColor(baseColor[1], baseColor[2], baseColor[3], 1)
            end
            RB.StyleSegmentedText(barInfo.frame, slot.powerType, rbSettings, appearance)
        else
            local halfSegments = (mwMaxStacks <= 5) and mwMaxStacks or (mwMaxStacks / 2)
            if not barInfo or barInfo.barType ~= "mw_segmented" or #barInfo.frame.segments ~= halfSegments then
                barInfo = SwapPreviewRenderer(frame, barInfo, "mw_segmented", slot.powerType, halfSegments,
                    CreateOverlayBar, frame.previewCanvas, halfSegments)
            end
            RB.SetResourceBarSize(barInfo.frame, width, height)
            LayoutOverlaySegments(barInfo.frame, width, height, segmentGap, rbSettings, halfSegments, slot.powerType, appearance)
            local baseColor, overlayColor = GetResourceColors(RESOURCE_MAELSTROM_WEAPON, rbSettings)
            for i = 1, halfSegments do
                barInfo.frame.segments[i]:SetStatusBarColor(baseColor[1], baseColor[2], baseColor[3], 1)
                barInfo.frame.overlaySegments[i]:SetStatusBarColor(overlayColor[1], overlayColor[2], overlayColor[3], 1)
                barInfo.frame.overlaySegments[i]:Show()
            end
            RB.StyleSegmentedText(barInfo.frame, slot.powerType, rbSettings, appearance)
        end
    elseif RB.AURA_STACK_RESOURCES[slot.powerType] then
        -- Mirrors the two real aura-stack shapes (ResourceBar.lua's apply
        -- branch); the canvas must show the shape the bar will actually be.
        -- Reached through RB rather than new file-level aliases: this chunk
        -- holds about 160 of the 200 locals Lua 5.1 allows (158 on 2026-10-21).
        -- The resolver, not the raw field: a member whose maximum is read
        -- live shows its real cap here too. Previewing another class's
        -- resources answers with that member's fallback, which is the
        -- point — a preview is a shape, not a live reading.
        local stackMax = RB.GetAuraStackResourceMax(slot.powerType)
        if RB.GetAuraStackDisplayStyle(rbSettings, slot.powerType) == "continuous" then
            if not barInfo or barInfo.barType ~= "stackaura_continuous" then
                barInfo = SwapPreviewRenderer(frame, barInfo, "stackaura_continuous", slot.powerType, nil,
                    CreateContinuousBar, frame.previewCanvas)
            else
                -- Pooled slot frames keep their barInfo when the shape
                -- matches, so a reused one still carried the PREVIOUS half's
                -- power type — and max, colors, border keys and the Active
                -- Aura preview state all resolve from it. The runtime branch
                -- restamps identity on reuse for exactly this reason.
                barInfo.powerType = slot.powerType
            end
            RB.SetResourceBarSize(barInfo.frame, width, height)
            StyleContinuousBar(barInfo.frame, slot.powerType, rbSettings, nil, appearance)
        else
            if not barInfo or barInfo.barType ~= "stackaura_segments"
                or #barInfo.frame.segments ~= stackMax then
                barInfo = SwapPreviewRenderer(frame, barInfo, "stackaura_segments", slot.powerType, stackMax,
                    CreateSegmentedBar, frame.previewCanvas, stackMax)
            else
                -- Same pooled-identity restamp as the continuous shape above.
                barInfo.powerType = slot.powerType
            end
            RB.SetResourceBarSize(barInfo.frame, width, height)
            LayoutSegments(barInfo.frame, width, height, segmentGap, rbSettings, slot.powerType, appearance)
            local baseColor = GetResourceColors(slot.powerType, rbSettings)
            for i = 1, stackMax do
                barInfo.frame.segments[i]:SetStatusBarColor(baseColor[1], baseColor[2], baseColor[3], 1)
            end
            RB.StyleSegmentedText(barInfo.frame, slot.powerType, rbSettings, appearance)
        end
    elseif SEGMENTED_TYPES[slot.powerType] then
        local maxValue = UnitPowerMax("player", slot.powerType)
        if slot.powerType == 5 then
            maxValue = 6
        end
        if not maxValue or maxValue < 1 then
            maxValue = 5
        end
        if not barInfo or barInfo.barType ~= "segmented" or barInfo.frame._numSegments ~= maxValue then
            barInfo = SwapPreviewRenderer(frame, barInfo, "segmented", slot.powerType, maxValue,
                CreateSegmentedBar, frame.previewCanvas, maxValue)
        else
            -- Same pooled-identity restamp as the aura-stack shapes above:
            -- a reused equal-count frame otherwise keeps the previous
            -- resource's power type, and colors and the max-stack border
            -- resolve from it.
            barInfo.powerType = slot.powerType
        end
        RB.SetResourceBarSize(barInfo.frame, width, height)
        LayoutSegments(barInfo.frame, width, height, segmentGap, rbSettings, slot.powerType, appearance)
        StyleSegmentedBar(barInfo.frame, slot.powerType, rbSettings, appearance)
    else
        if not barInfo or barInfo.barType ~= "continuous" then
            barInfo = SwapPreviewRenderer(frame, barInfo, "continuous", slot.powerType, nil,
                CreateContinuousBar, frame.previewCanvas)
        else
            -- Same pooled-identity restamp as the other reused shapes: every
            -- continuous power type shares this barType, so a reused frame
            -- otherwise keeps the previous resource's power type — and the
            -- bar text maximum and the Active Aura preview state resolve
            -- from it.
            barInfo.powerType = slot.powerType
        end
        RB.SetResourceBarSize(barInfo.frame, width, height)
        StyleContinuousBar(barInfo.frame, slot.powerType, rbSettings, nil, appearance)
    end

    frame.previewBarInfo = barInfo
    barInfo.appearance = appearance
    if barInfo and barInfo.frame then
        barInfo.frame:SetParent(frame.previewCanvas)
        barInfo.frame:ClearAllPoints()
        barInfo.frame:SetPoint("TOPLEFT", frame.previewCanvas, "TOPLEFT", 0, 0)
        barInfo.frame:SetPoint("BOTTOMRIGHT", frame.previewCanvas, "BOTTOMRIGHT", 0, 0)
        barInfo.frame:Show()
        -- The resource overlay's Active Aura preview state, on the canvas
        -- rather than out in the world (owner ruling 2026-07-26). Keyed by
        -- power type, and written every pass so stopping the preview clears
        -- it from a recycled frame. Set before the render, which reads it.
        barInfo.frame._resourceAuraActivePreview = not preview.readOnly and barInfo.powerType ~= nil
            and CooldownCompanion:IsResourceAuraActivePreviewActive(barInfo.powerType)
            or nil
        ApplyPreviewBarState(barInfo, rbSettings, preview.readOnly, appearance)
        if not preview.readOnly and barInfo.barType == "health_continuous"
            and RB.IsHealthEffectPreviewAnimated
            and RB.IsHealthEffectPreviewAnimated() then
            table_insert(preview.animated, {
                barInfo = barInfo,
                -- Resolved here rather than per tick; see the exporter.
                config = RB.GetHealthPreviewAnimationConfig
                    and RB.GetHealthPreviewAnimationConfig(rbSettings, appearance) or nil,
                Tick = function(entry)
                    RB.AnimatePreviewHealthEffects(entry.barInfo, entry.config)
                end,
            })
        end
    end
end

local CastBarVisuals = ST._CastBarVisuals

local function EnsureCastPreview(frame)
    if not frame.castPreview then
        local root = CreateFrame("Frame", nil, frame.previewCanvas)
        root:SetClipsChildren(false)
        CastBarVisuals.CreateContents(root)
        frame.castPreview = { root = root }
    end
    return frame.castPreview
end

local function ConfigureCastPreviewChannelMarks(castPreview, settings)
    local root = castPreview.root
    CastBarVisuals.HideChannelTickMarks(root)
    if settings.showChannelTickMarks ~= true then return end
    -- Five sample end ticks, not the cadence of a live spell.
    for index = 1, 4 do
        CastBarVisuals.SetChannelTickMark(root, settings, index, index / 5, index == 4)
    end
end

local function SetCastPreviewProgress(castPreview, progress)
    local shownProgress = castPreview.isChannelPreview and (1 - progress) or progress
    CastBarVisuals.SetFill(castPreview.root, shownProgress, true)
    CastBarVisuals.SetTimeText(castPreview.root, CAST_PREVIEW_DURATION * (1 - progress))
end

local function ConfigureCastPreview(frame, slot, preview, width, height)
    HideUnusedSlotVisuals(frame)
    local settings = preview.cbSettings
    local castPreview = EnsureCastPreview(frame)
    local root = castPreview.root
    root:SetParent(frame.previewCanvas)
    root:ClearAllPoints()
    root:SetPoint("TOPLEFT", frame.previewCanvas, "TOPLEFT", 0, 0)
    root:SetPoint("BOTTOMRIGHT", frame.previewCanvas, "BOTTOMRIGHT", 0, 0)
    CastBarVisuals.Layout(root, settings, width, height)
    CastBarVisuals.Style(root, settings)
    root.icon:SetTexture(slot.icon or LAYOUT_PREVIEW_ICON_FALLBACK)
    root.nameText:SetText(CAST_PREVIEW_SPELL_NAME)
    castPreview.isChannelPreview = settings.showChannelTickMarks == true
    ConfigureCastPreviewChannelMarks(castPreview, settings)
    root:Show()

    -- The cast bar's preview state: a cast in progress, looping. Nothing on
    -- the resting bar can stand in for one, which is what makes it worth a
    -- control in the first place.
    local sample = not preview.readOnly and ST._ConfigPreview.GetSample("cast")
    if sample then
        table_insert(preview.animated, {
            castPreview = castPreview, sample = sample,
            Tick = function(entry, now)
                local elapsed = (now - entry.sample.startedAt) % CAST_PREVIEW_DURATION
                SetCastPreviewProgress(entry.castPreview, elapsed / CAST_PREVIEW_DURATION)
            end,
        })
        SetCastPreviewProgress(castPreview, ((GetTime() - sample.startedAt) % CAST_PREVIEW_DURATION) / CAST_PREVIEW_DURATION)
    else
        SetCastPreviewProgress(castPreview, CAST_PREVIEW_REST_FILL)
    end
end

local function ConfigureSlotPreview(frame, slot, preview, width, height)
    ConfigureSlotChrome(frame)
    if slot.kind == "cast" then
        ConfigureCastPreview(frame, slot, preview, width, height)
    else
        EnsureResourcePreview(frame, slot, preview, width, height)
    end
end

-- The drag ghost runs through the same slot renderer, which would enrol its
-- throwaway frames in the animation list. That list is only emptied by a
-- full rebuild, and cancelling a drag does not rebuild — so each cancelled
-- drag left an entry ticking a hidden ghost, and they accumulated.
local function ConfigureGhostSlotPreview(frame, slot, preview, width, height)
    local enrolled = #preview.animated
    ConfigureSlotPreview(frame, slot, preview, width, height)
    for index = #preview.animated, enrolled + 1, -1 do
        preview.animated[index] = nil
    end
end

-- Bars are not all the same thickness: the layout supports a per-slot
-- override and the cast bar carries its own height. The lane therefore
-- positions from an ordered list of extents rather than from one repeated
-- slot size, and `sizes` lets a caller pass a hypothetical order (drag
-- hit-testing works against the list with the dragged slot removed).
-- The configured thickness verbatim. The thickness sliders run 4-40 in 0.1
-- steps and the live layout uses the saved value directly, so flooring it
-- and clamping it up to 8 made every bar under 8px preview at the wrong
-- size and threw away every fractional value — inside the pass whose whole
-- point is that the preview matches. A thin bar is a thin drag target; that
-- is handled by expanding the hit rect, not by drawing the bar wrong.
local function GetSlotExtent(slot, fallback)
    local thickness = tonumber(slot and slot.thickness)
    if thickness and thickness > 0 then
        return thickness
    end
    return fallback
end

-- Smallest comfortable grab area for a reorder drag. Thin bars keep their
-- true size and borrow the empty space around them instead, capped at half
-- the inter-bar gap so neighbouring slots never claim the same pixels.
local LAYOUT_PREVIEW_MIN_HIT_EXTENT = 10

local function ApplySlotHitExpansion(frame, extent, gap, isVerticalSlot)
    local missing = LAYOUT_PREVIEW_MIN_HIT_EXTENT - (tonumber(extent) or 0)
    local pad = 0
    if missing > 0 then
        pad = math_min(missing / 2, math_max(0, (tonumber(gap) or 0) / 2))
    end
    -- Negative insets EXPAND the mouse rect beyond the frame.
    if isVerticalSlot then
        frame:SetHitRectInsets(-pad, -pad, 0, 0)
    else
        frame:SetHitRectInsets(0, 0, -pad, -pad)
    end
end

local function BuildSlotExtents(slots, fallback)
    local sizes = {}
    for index, slot in ipairs(slots) do
        sizes[index] = GetSlotExtent(slot, fallback)
    end
    return sizes
end

local function GetExtentTotal(sizes, gap, fallbackSize)
    local count = sizes and #sizes or 0
    if count <= 0 then
        return math_max(LAYOUT_PREVIEW_EMPTY_DROP_SIZE, fallbackSize or LAYOUT_PREVIEW_EMPTY_DROP_SIZE)
    end
    local total = 0
    for _, size in ipairs(sizes) do
        total = total + size
    end
    return total + ((count - 1) * gap)
end

local function BuildLaneSlotGeometry(lane, index, sizes)
    sizes = sizes or lane.renderSizes or {}
    local gap = lane.slotGap or LAYOUT_PREVIEW_GAP
    local laneWidth = lane.frame:GetWidth() or lane.slotWidth or 1
    local laneHeight = lane.frame:GetHeight() or lane.slotHeight or 1
    local defaultExtent = lane.defaultExtent
        or (lane.axis == "x" and lane.slotWidth or lane.slotHeight)
        or LAYOUT_PREVIEW_EMPTY_DROP_SIZE

    local offset = 0
    for i = 1, index - 1 do
        offset = offset + (sizes[i] or defaultExtent) + gap
    end
    local extent = sizes[index] or defaultExtent

    if lane.axis == "x" then
        local y = -math_floor(math_max(0, laneHeight - lane.slotHeight) / 2)
        return offset, y, extent, lane.slotHeight
    end
    local x = math_floor(math_max(0, laneWidth - lane.slotWidth) / 2)
    return x, -offset, lane.slotWidth, extent
end

-- The insert index a drop is ALLOWED to take, clamped out of the raw one.
-- `filtered` is the destination lane's slots with the dragged one lifted out.
--
-- One rule covers every case: the drop may not break the lane's rank order.
-- A fixed bar therefore stays inside its region's run and the cast bar at the
-- far end; cross-lane drops read the destination lane's ranks.
--
-- Ranks always bind: a lane of only fixed bars has one rank and stays a
-- free reorder, while the cast bar is confined to the far end everywhere —
-- the stack reserves no space for an interleaved cast bar, so the far end
-- is the only slot live geometry can honour.
local function ClampLaneInsertIndex(lane, slotData, filtered, insertIndex)
    local count = #filtered
    if not slotData then
        return math_max(1, math_min(count + 1, insertIndex or 1))
    end

    -- Sections run the lane's own direction: on a reversed lane index 1 is
    -- the slot furthest from the panel, so ranks descend there.
    local reversed = lane.reversed == true
    -- Every new attached placement has destination region rank zero: main
    -- placements save main, and split panel destinations have no region tie.
    -- The source's own region rank must not constrain the landing.
    local rank = GetSlotStackRank(slotData, 0)

    local lower = 1
    for index = 1, count do
        local other = GetSlotStackRank(filtered[index])
        local precedes
        if reversed then precedes = other > rank else precedes = other < rank end
        if not precedes then
            break
        end
        lower = index + 1
    end

    local upper = count + 1
    for index = count, 1, -1 do
        local other = GetSlotStackRank(filtered[index])
        local follows
        if reversed then follows = other < rank else follows = other > rank end
        if not follows then
            break
        end
        upper = index
    end

    -- A lane the sort never ranked can hold slots out of rank order, which
    -- collapses the window; the lower bound wins and the post-drop sort
    -- settles the rest.
    if upper < lower then
        upper = lower
    end
    return math_max(lower, math_min(upper, insertIndex or lower))
end

local function GetScaledFrameRect(frame)
    if not (frame and frame.GetScaledRect) then
        return nil
    end

    local left, bottom, width, height = frame:GetScaledRect()
    if not (left and bottom and width and height) then
        return nil
    end

    return left, left + width, bottom + height, bottom, width, height
end

local function GetLaneScale(lane)
    local left, right, top, bottom, scaledWidth, scaledHeight = GetScaledFrameRect(lane.frame)
    if not (left and right and top and bottom and scaledWidth and scaledHeight) then
        return nil
    end

    local laneWidth = lane.frame:GetWidth() or lane.slotWidth or 1
    local laneHeight = lane.frame:GetHeight() or lane.slotHeight or 1
    local scaleX = (laneWidth > 0) and (scaledWidth / laneWidth) or 1
    local scaleY = (laneHeight > 0) and (scaledHeight / laneHeight) or 1

    return {
        left = left,
        right = right,
        top = top,
        bottom = bottom,
        width = scaledWidth,
        height = scaledHeight,
        scaleX = scaleX,
        scaleY = scaleY,
    }
end

-- Returns the lane's scale, the hit rects, and the slot models those rects
-- belong to. The models come back because the drag containment has to clamp
-- against the same list the rects were measured from.
local function BuildStableLaneSlots(lane, draggedSlotId)
    local laneScale = GetLaneScale(lane)
    if not laneScale then
        return nil, nil, nil
    end

    local filtered = {}
    for _, slot in ipairs(lane.slotModels or {}) do
        if slot.id ~= draggedSlotId then
            table_insert(filtered, slot)
        end
    end
    -- Hit-test against the order WITHOUT the dragged slot, so the rects
    -- match what the lane would look like if it were dropped elsewhere.
    local filteredSizes = BuildSlotExtents(filtered, lane.defaultExtent)

    local slotRects = {}
    for index = 1, #filtered do
        local x, y, w, h = BuildLaneSlotGeometry(lane, index, filteredSizes)
        local left = laneScale.left + (x * laneScale.scaleX)
        local top = laneScale.top + (y * laneScale.scaleY)
        local right = left + (w * laneScale.scaleX)
        local bottom = top - (h * laneScale.scaleY)
        slotRects[index] = {
            left = left,
            right = right,
            top = top,
            bottom = bottom,
        }
    end

    return laneScale, slotRects, filtered
end

local function SelectPreviewSlot(slot, modifierMulti)
    if type(slot) ~= "table" then
        return false
    end
    if ST._HandleModuleThicknessCopy and ST._HandleModuleThicknessCopy(slot) then return true end
    local allowToggle = not CS.spellbookPanelWindow

    -- Unified anchor preview (buttons view): route to the unified bar
    -- selection, which owns the entry-vs-bar exclusivity and cast support.
    if not IsBarsWorkspaceActive() then
        if ST._SelectUnifiedAnchorBar then
            return ST._SelectUnifiedAnchorBar(slot, { multi = modifierMulti, toggle = allowToggle })
        end
        return false
    end

    -- Every slot on the workspace canvas is click-to-edit, whatever is
    -- selected right now. The State.lua setters own the exclusivity between
    -- the three selection families, so there is nothing to clear here.
    if slot.kind == "cast" then
        if ST._SelectConfigCastFramesItem then
            ST._SelectConfigCastFramesItem("castbar")
        else
            CS.castFramesSelectedItem = "castbar"
        end
        return true
    end

    if slot.kind == "resource" and slot.powerType ~= nil and ST._SelectConfigResource then
        ST._SelectConfigResource(slot.powerType, { toggle = allowToggle })
        return true
    end

    return false
end
ST._SelectPanelAttachmentModule = SelectPreviewSlot

local function ApplySlotSelection(slotFrame, slotModel, vertical, slotExtent)
    if ST._ApplyModuleCopyTargetVisuals then ST._ApplyModuleCopyTargetVisuals(slotFrame, slotModel) end
    local isSelected
    if IsBarsWorkspaceActive() then
        isSelected = (slotModel.kind == "cast" and CS.castFramesSelectedItem == "castbar")
            or (slotModel.kind == "resource" and slotModel.powerType ~= nil
                and tostring(CS.selectedResourcePowerType) == tostring(slotModel.powerType))
    else
        local kind = CS.unifiedBarKind
        isSelected = (kind == "resource" and slotModel.kind == "resource"
                and slotModel.powerType ~= nil
                and tostring(CS.selectedResourcePowerType) == tostring(slotModel.powerType))
            or (kind == "cast" and slotModel.kind == "cast")
    end
    if isSelected and slotFrame.selectedHighlight then
        local marker = slotFrame.selectedHighlight
        local arrowSize = math_max(14, math_min(28, slotExtent + 6))
        marker.side1:SetSize(arrowSize, arrowSize)
        marker.side2:SetSize(arrowSize, arrowSize)
        marker.side1:ClearAllPoints()
        marker.side2:ClearAllPoints()
        if vertical then
            -- Tall vertical bar: arrows above and below, pointing inward
            marker.side1:SetAtlas("npe_arrowdown", false)
            marker.side1:SetPoint("BOTTOM", marker, "TOP", 0, 2)
            marker.side2:SetAtlas("npe_arrowup", false)
            marker.side2:SetPoint("TOP", marker, "BOTTOM", 0, -2)
        else
            -- Wide horizontal bar: arrows at the sides, pointing inward
            marker.side1:SetAtlas("npe_arrowright", false)
            marker.side1:SetPoint("RIGHT", marker, "LEFT", -2, 0)
            marker.side2:SetAtlas("npe_arrowleft", false)
            marker.side2:SetPoint("LEFT", marker, "RIGHT", 2, 0)
        end
        marker:Show()
    end
end

local function BuildLane(preview, parent, layoutDrag, title, width, height, axis, side, reversed, slotModels, slotWidth, slotHeight, acceptedCategory)
    local laneFrame = AcquireContainer(preview, parent)
    laneFrame:SetSize(width, height)
    ApplyBackdrop(laneFrame, { 0, 0, 0, 0 }, { 0, 0, 0, 0 })

    local lane = {
        frame = laneFrame,
        axis = axis,
        side = side,
        reversed = reversed,
        slotModels = slotModels,
        baseWidth = width,
        baseHeight = height,
        slotWidth = slotWidth,
        slotHeight = slotHeight,
        -- Along-axis fallback for a slot with no resolved thickness; the
        -- cross-axis size stays uniform (every bar spans the stack's
        -- width, exactly as the live stack does).
        defaultExtent = axis == "x" and slotWidth or slotHeight,
        slotGap = preview.slotGap or LAYOUT_PREVIEW_GAP,
        baseExtent = axis == "x" and width or height,
        acceptedCategory = acceptedCategory,
        visualSlots = {},
        slotFramesById = {},
    }
    lane.naturalSizes = BuildSlotExtents(slotModels, lane.defaultExtent)
    lane.renderSizes = lane.naturalSizes

    for index, slotModel in ipairs(slotModels) do
        local slotFrame = AcquireSlot(preview, laneFrame)
        -- Explicit, and before the chrome pass reads it: the drop gap rides
        -- at the lane's level + 1, so a pooled slot must not come back
        -- carrying a level from another lane.
        slotFrame:SetFrameLevel(laneFrame:GetFrameLevel() + 2)
        local slotExtent = lane.naturalSizes[index]
        ConfigureSlotPreview(
            slotFrame, slotModel, preview,
            axis == "x" and slotExtent or slotWidth,
            axis == "x" and slotHeight or slotExtent)
        ApplySlotHitExpansion(slotFrame, slotExtent, lane.slotGap, axis == "x")
        preview.renderedSelectionKeys[slotModel.id] = true

        -- Mark the bar currently being configured: held hover-style glow
        -- plus inward-pointing arrows. In the workspace exactly one object
        -- is selected across all three families, so one slot lights up
        -- whichever kind it is; in the buttons view (unified anchor preview)
        -- the highlight follows the unified bar selection, so a stale
        -- workspace selection can't light a bar up.
        ApplySlotSelection(slotFrame, slotModel, axis == "x", slotExtent)
        slotFrame:SetScript("OnMouseDown", function(self, button)
            if button ~= "LeftButton" or GetCursorInfo() or preview.standaloneCast then return end
            layoutDrag.slotCategory = slotModel.slotCategory
            local cursorX, cursorY = GetCursorPosition()
            CS.dragState = {
                kind = LAYOUT_PREVIEW_DRAG_KIND,
                phase = "pending",
                widget = self,
                scrollWidget = UIParent,
                startX = cursorX,
                startY = cursorY,
                layoutDrag = layoutDrag,
                slotData = slotModel,
            }
            StartDragTracking()
        end)
        slotFrame:SetScript("OnMouseUp", function(self, button)
            if button == "RightButton" then
                if ST._ShowModuleThicknessMenu then ST._ShowModuleThicknessMenu(slotModel) end
                return
            end

            if button == "LeftButton" and preview.standaloneCast then
                SelectPreviewSlot(slotModel, false)
                CooldownCompanion:RefreshConfigPanel()
                return
            end
            -- Escape already cancelled this drag; the release the user is still
            -- holding belongs to that cancel, never to a selection click.
            if button == "LeftButton" and ST._ConsumeDragEscapeMouseUp() then return end

            local state = CS.dragState
            if button ~= "LeftButton"
                or not state
                or state.kind ~= LAYOUT_PREVIEW_DRAG_KIND
                or state.phase ~= "pending"
                or state.widget ~= self then
                return
            end

            if CancelDrag then
                CancelDrag()
            else
                CS.dragState = nil
            end

            if SelectPreviewSlot(slotModel, IsControlKeyDown and IsControlKeyDown()) then
                if CS.spellbookPanelWindow then CS.CloseSpellbookPanel() end
                CooldownCompanion:RefreshConfigPanel()
            end
        end)
        slotFrame:SetScript("OnEnter", function(self)
            if self.hoverHighlight then
                self.hoverHighlight:Show()
            end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(slotModel.label or "Bar", 1, 1, 1)
            local dragHelp = preview.standaloneCast and "Click to edit."
                or "Click to edit. Drag to reorder this independent bar."
            GameTooltip:AddLine(dragHelp, 0.75, 0.82, 0.92, true)
            GameTooltip:Show()
        end)
        slotFrame:SetScript("OnLeave", function(self)
            if self.hoverHighlight then
                self.hoverHighlight:Hide()
            end
            GameTooltip:Hide()
        end)
        local x, y, w, h = BuildLaneSlotGeometry(lane, index)
        ApplySlotGeometry(slotFrame, laneFrame, x, y, w, h, 1)
        lane.visualSlots[index] = slotFrame
        lane.slotFramesById[slotModel.id] = slotFrame
    end


    lane.gapFrame = AcquireGap(preview, laneFrame)
    lane.gapFrame:SetFrameLevel(laneFrame:GetFrameLevel() + 1)
    lane.gapFrame:Hide()
    ApplyBackdrop(lane.gapFrame, preview.skin.gapBg, preview.skin.gapBorder)
    lane.gapFrame:SetAlpha(0.95)
    lane.gapFrame.text:SetText("")
    if not lane.gapFrame.inner then
        lane.gapFrame.inner = lane.gapFrame:CreateTexture(nil, "BACKGROUND")
        lane.gapFrame.inner:SetPoint("TOPLEFT", lane.gapFrame, "TOPLEFT", 2, -2)
        lane.gapFrame.inner:SetPoint("BOTTOMRIGHT", lane.gapFrame, "BOTTOMRIGHT", -2, 2)
    end
    lane.gapFrame.inner:SetColorTexture(preview.skin.slotHover[1], preview.skin.slotHover[2], preview.skin.slotHover[3], 0.22)

    table_insert(layoutDrag.lanes, lane)
    return lane
end

-- The lane's along-axis size for a set of slots, honoring each slot's own
-- thickness and the configured inter-bar spacing.
local function GetLaneExtent(preview, slots, slotSize)
    return GetExtentTotal(
        BuildSlotExtents(slots, slotSize),
        preview.slotGap or LAYOUT_PREVIEW_GAP,
        slotSize)
end

local function RenderIndependentHorizontalLayout(preview, content, layoutDrag, slots, slotWidth, slotHeight)
    local stackSlots, stackSide, reversed = SortSlotsForIndependentStack(slots, "above", "below", preview)
    local slotFrameHeight = math_max(8, slotHeight)
    local stackHeight = GetLaneExtent(preview, stackSlots, slotFrameHeight)

    local lane = BuildLane(
        preview,
        content,
        layoutDrag,
        nil,
        slotWidth,
        stackHeight,
        "y",
        stackSide,
        reversed,
        stackSlots,
        slotWidth,
        slotFrameHeight,
        "primary"
    )
    lane.frame:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)

    return slotWidth, stackHeight
end

local function RenderIndependentVerticalLayout(preview, content, layoutDrag, slots, slotHeight, slotWidth)
    local stackSlots, stackSide, reversed = SortSlotsForIndependentStack(slots, "left", "right", preview)
    local stackWidth = GetLaneExtent(preview, stackSlots, slotWidth)

    local lane = BuildLane(
        preview,
        content,
        layoutDrag,
        nil,
        stackWidth,
        slotHeight,
        "x",
        stackSide,
        reversed,
        stackSlots,
        slotWidth,
        slotHeight,
        "primary"
    )
    lane.frame:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)

    return stackWidth, slotHeight
end

local function ConfigureBarsPill(preview, frame, item)
    local skin = preview.skin
    local selected = item.selected == true
    local accent = item.accent or BARS_PILL_NEUTRAL_ACCENT

    frame.label:SetText(item.label or "")
    frame.label:ClearAllPoints()
    if item.icon then
        frame.icon:SetAtlas(item.icon, false)
        frame.icon:SetVertexColor(1, 1, 1, 1)
        frame.icon:Show()
        frame.label:SetPoint("LEFT", frame.icon, "RIGHT", BARS_PILL_ICON_GAP, 0)
    else
        frame.icon:Hide()
        frame.label:SetPoint("LEFT", frame, "LEFT", BARS_PILL_ACCENT_WIDTH + BARS_PILL_INSET, 0)
    end
    frame.label:SetPoint("RIGHT", frame, "RIGHT", -BARS_PILL_INSET, 0)

    ApplyBackdrop(frame, skin.slotBg,
        selected and BARS_PILL_SELECTED_BORDER or skin.slotBorder, 1)
    frame.accent:SetColorTexture(accent[1], accent[2], accent[3], selected and 1 or 0.85)
    frame.selected:SetShown(selected)
    local color = selected and BARS_PILL_SELECTED_TEXT_COLOR or BARS_PILL_TEXT_COLOR
    frame.label:SetTextColor(color[1], color[2], color[3])

    frame._cdcTooltip = item.tooltip or item.label
    frame._cdcTooltipLine = item.tooltipLine
    frame._cdcTooltipNote = item.tooltipNote
    frame:SetScript("OnClick", function(_, mouseButton)
        if mouseButton == "RightButton" then
            if item.onRightClick then
                item.onRightClick()
            end
            return
        end
        if mouseButton == "LeftButton" and item.onClick then
            item.onClick()
        end
    end)
end

-- Mirrors ConfigureBarsPill's anchors exactly, so a pill sized from this is
-- the natural width of what it draws and the label's centering has no slack
-- to absorb.
local function GetBarsPillWidth(frame, item)
    local lead = item.icon
        and (BARS_PILL_ICON_GAP + BARS_PILL_ICON_SIZE + BARS_PILL_ICON_GAP)
        or BARS_PILL_INSET
    local width = BARS_PILL_ACCENT_WIDTH + lead
        + math_floor((frame.label:GetStringWidth() or 0) + 0.5) + BARS_PILL_INSET
    return math_max(BARS_PILL_MIN_WIDTH, width)
end

-- The module-enable cluster, pinned to the pane's bottom-right corner: one
-- pill per module of this workspace that is switched off entirely. It is
-- host chrome rather than canvas content, built on every bars build before
-- anything measures itself, so it is on screen in the message-only states
-- too - those are exactly the states whose way out is turning a module on.
--
-- It claims its own share of the host's bottom reserve (see
-- GetHostBottomReserve), which is why a wrap costs the composition height
-- instead of drawing over it. One line matches the command center's band
-- exactly, so the common case costs nothing.
--
-- Never more than two pills: with all three modules off the workspace
-- shows its overview pane instead and no canvas is built at all.
local function BuildBarsEnableCluster(preview)
    local host = preview.host
    if not host then
        return
    end

    local items = IsBarsWorkspaceActive()
        and ST._CollectBarsEnableItems
        and ST._CollectBarsEnableItems()
        or nil
    if not (items and #items > 0) then
        if preview.enableCluster then
            preview.enableCluster:Hide()
        end
        host._cdcBarsCornerReserveBottom = nil
        return
    end

    local cluster = preview.enableCluster
    if not cluster then
        cluster = CreateFrame("Frame", nil, host)
        cluster:SetClipsChildren(false)
        -- Level with the command center, above the composition's own
        -- frames, so neither corner is ever buried by an overhanging slot.
        cluster:SetFrameLevel(host:GetFrameLevel() + 20)
        preview.enableCluster = cluster
    end
    cluster:Show()

    local frames = {}
    local widths = {}
    for index, item in ipairs(items) do
        item.accent = BARS_PILL_ENABLE_ACCENT
        item.label = "+ " .. tostring(item.label or "")
        local frame = AcquireBarsPill(preview, cluster)
        ConfigureBarsPill(preview, frame, item)
        frames[index] = frame
        widths[index] = GetBarsPillWidth(frame, item)
    end

    -- The command center owns the left of this band. Leave it its width
    -- plus a gap and wrap into what is left; when even one pill will not
    -- fit that, the cluster takes the room it needs and the command center
    -- keeps the left edge it is anchored to.
    local hostWidth = host:GetWidth() or 0
    if hostWidth < 40 then
        hostWidth = 340
    end
    local occupied = ST._GetPreviewCommandCenterOccupiedWidth
        and ST._GetPreviewCommandCenterOccupiedWidth(host) or 0
    local budget = hostWidth - BARS_CORNER_SIDE_INSET - occupied
    if occupied > 0 then
        budget = budget - BARS_CORNER_COMMAND_GAP
    end
    budget = math_max(BARS_PILL_MIN_WIDTH, budget)

    local lines = {}
    local current = { width = 0, first = 1, last = 0 }
    for index = 1, #frames do
        local candidate = current.width > 0
            and (current.width + BARS_PILL_GAP + widths[index])
            or widths[index]
        if current.width > 0 and candidate > budget then
            lines[#lines + 1] = current
            current = { width = widths[index], first = index, last = index }
        else
            current.width = candidate
            current.last = index
        end
    end
    if current.last >= current.first then
        lines[#lines + 1] = current
    end

    local clusterWidth = 0
    for _, line in ipairs(lines) do
        clusterWidth = math_max(clusterWidth, line.width)
    end

    local top = 0
    for lineIndex, line in ipairs(lines) do
        local right = 0
        for index = line.last, line.first, -1 do
            local frame = frames[index]
            frame:SetSize(widths[index], BARS_CORNER_PILL_HEIGHT)
            frame:ClearAllPoints()
            frame:SetPoint("TOPRIGHT", cluster, "TOPRIGHT", -right, -top)
            right = right + widths[index] + BARS_PILL_GAP
        end
        top = top + BARS_CORNER_PILL_HEIGHT
            + (lineIndex < #lines and BARS_PILL_LINE_GAP or 0)
    end

    cluster:SetSize(math_max(1, clusterWidth), math_max(1, top))
    cluster:ClearAllPoints()
    cluster:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT",
        -BARS_CORNER_SIDE_INSET, BARS_CORNER_BOTTOM_INSET)

    host._cdcBarsCornerReserveBottom = BARS_CORNER_BOTTOM_INSET + top
end

local function FinishPreviewWithMessage(preview, message)
    SetPreviewMessage(preview, message)
    FinalizePreviewState(preview)
end

-- The cursor's raw landing spot, CLAMPED into the positions the drop is
-- allowed to take. Clamping here rather than at commit time is what makes the
-- drag teach the rule: the gap indicator reads this same index, so the cast
-- bar dragged toward the panel shows the gap holding at the far end instead
-- of opening somewhere it would only snap back from.
local function GetLaneInsertIndex(lane, cursorX, cursorY, draggedSlotId, draggedSlot)
    local _, slots, models = BuildStableLaneSlots(lane, draggedSlotId)
    if not slots then
        return 1
    end

    local raw
    if #slots == 0 then
        raw = 1
    elseif lane.axis == "x" then
        raw = #slots + 1
        for index, slotRect in ipairs(slots) do
            if cursorX < ((slotRect.left + slotRect.right) / 2) then
                raw = index
                break
            end
        end
    else
        raw = #slots + 1
        for index, slotRect in ipairs(slots) do
            if cursorY > ((slotRect.top + slotRect.bottom) / 2) then
                raw = index
                break
            end
        end
    end

    return ClampLaneInsertIndex(lane, draggedSlot, models or {}, raw)
end

local function GetDistanceToLane(laneScale, cursorX, cursorY)
    if not laneScale then
        return nil
    end

    local left, right = laneScale.left, laneScale.right
    local top, bottom = laneScale.top, laneScale.bottom
    local dx = 0
    if cursorX < left then
        dx = left - cursorX
    elseif cursorX > right then
        dx = cursorX - right
    end

    local dy = 0
    if cursorY > top then
        dy = cursorY - top
    elseif cursorY < bottom then
        dy = bottom - cursorY
    end

    return (dx * dx) + (dy * dy)
end

local function ResolveDropTarget(layoutDrag, cursorX, cursorY, draggedSlot)
    local closestLane
    local closestLaneScale
    local closestDistance
    draggedSlot = draggedSlot or layoutDrag.draggedSlotData

    for _, lane in ipairs(layoutDrag.lanes or {}) do
        local frame = lane.frame
        if frame and frame:IsShown()
            and (not layoutDrag.slotCategory or not lane.acceptedCategory or lane.acceptedCategory == layoutDrag.slotCategory) then
            local laneScale = GetLaneScale(lane)
            local left = laneScale and laneScale.left
            local right = laneScale and laneScale.right
            local top = laneScale and laneScale.top
            local bottom = laneScale and laneScale.bottom
            local distance = GetDistanceToLane(laneScale, cursorX, cursorY)
            if distance ~= nil and (not closestDistance or distance < closestDistance) then
                closestDistance = distance
                closestLane = lane
                closestLaneScale = laneScale
            end
            if left and right and top and bottom
                and cursorX >= left and cursorX <= right
                and cursorY <= top and cursorY >= bottom then
                return {
                    lane = lane,
                    insertIndex = GetLaneInsertIndex(lane, cursorX, cursorY, layoutDrag.draggedSlotId, draggedSlot),
                }
            end
        end
    end

    if closestLane and closestDistance then
        local scaledSlotWidth = ((closestLane.slotWidth or 0) * ((closestLaneScale and closestLaneScale.scaleX) or 1))
        local scaledSlotHeight = ((closestLane.slotHeight or 0) * ((closestLaneScale and closestLaneScale.scaleY) or 1))
        local threshold = math_max(scaledSlotWidth, scaledSlotHeight, 24) + 60
        if closestDistance <= (threshold ^ 2) then
            return {
                lane = closestLane,
                insertIndex = GetLaneInsertIndex(closestLane, cursorX, cursorY, layoutDrag.draggedSlotId, draggedSlot),
            }
        end
    end

    return nil
end

local function UpdateLanePreview(preview, lane, draggedSlotId, dropTarget)
    local gapIndex = (dropTarget and dropTarget.lane == lane and dropTarget.insertIndex) or nil

    -- Render order for this frame: the lane's slots with the dragged one
    -- lifted out, and the drop gap (sized to the bar being dragged)
    -- inserted where it would land. Positions come from this list, so bars
    -- of different thicknesses shuffle correctly.
    local ordered = {}
    local sizes = {}
    for _, slot in ipairs(lane.slotModels or {}) do
        local slotFrame = lane.slotFramesById[slot.id]
        if slotFrame and slot.id ~= draggedSlotId then
            ordered[#ordered + 1] = slotFrame
            sizes[#sizes + 1] = GetSlotExtent(slot, lane.defaultExtent)
        end
    end
    if gapIndex then
        gapIndex = math_max(1, math_min(#ordered + 1, gapIndex))
        table_insert(sizes, gapIndex, preview.draggedSlotExtent or lane.defaultExtent)
    end
    lane.renderSizes = sizes

    local visibleFrames = {}
    for _, slot in ipairs(lane.slotModels or {}) do
        local slotFrame = lane.slotFramesById[slot.id]
        if slotFrame and slot.id == draggedSlotId then
            slotFrame:SetAlpha(0)
        end
    end
    for index, slotFrame in ipairs(ordered) do
        local displayIndex = index
        if gapIndex and displayIndex >= gapIndex then
            displayIndex = displayIndex + 1
        end
        local x, y, w, h = BuildLaneSlotGeometry(lane, displayIndex)
        QueueSlotTween(preview, slotFrame, lane.frame, x, y, w, h, 1, LAYOUT_PREVIEW_ANIM_DURATION)
        slotFrame:SetShown(true)
        slotFrame:SetAlpha(1)
        table_insert(visibleFrames, slotFrame)
    end

    lane.visualSlots = visibleFrames
    local requiredExtent = GetExtentTotal(sizes, lane.slotGap or LAYOUT_PREVIEW_GAP, lane.defaultExtent)
    local overflow = math_max(0, requiredExtent - (lane.baseExtent or requiredExtent))
    if lane.setPreviewOverflow then
        lane.setPreviewOverflow(overflow)
    end

    if gapIndex then
        local x, y, w, h = BuildLaneSlotGeometry(lane, gapIndex)
        -- BuildLane already painted the gap with this preview's skin, which
        -- only changes on a rebuild; the backdrop re-fits itself as it tweens.
        lane.gapFrame:SetAlpha(0.95)
        QueueSlotTween(preview, lane.gapFrame, lane.frame, x, y, w, h, 1, LAYOUT_PREVIEW_ANIM_DURATION)
        lane.gapFrame:Show()
    else
        lane.gapFrame:Hide()
    end
end

local function ResetLanePreview(preview, lane)
    lane.renderSizes = lane.naturalSizes
    for index, slot in ipairs(lane.slotModels or {}) do
        local slotFrame = lane.slotFramesById[slot.id]
        if slotFrame then
            local x, y, w, h = BuildLaneSlotGeometry(lane, index)
            QueueSlotTween(preview, slotFrame, lane.frame, x, y, w, h, 1, LAYOUT_PREVIEW_ANIM_DURATION)
            slotFrame:SetShown(true)
            slotFrame:SetAlpha(1)
            lane.visualSlots[index] = slotFrame
        end
    end
    lane.gapFrame:Hide()
    if lane.setPreviewOverflow then
        lane.setPreviewOverflow(0)
    end
end

local function ConfigureGhost(preview, slotData, slotFrame)
    local ghost = preview.ghost
    ghost:SetFrameStrata("TOOLTIP")
    ghost:SetFrameLevel(2000)
    ApplyBackdrop(ghost, preview.skin.ghostBg, preview.skin.ghostBorder)
    ghost:SetSize(slotFrame:GetWidth(), slotFrame:GetHeight())

    if not ghost._cdcSlot then
        ghost._cdcSlot = CreateSlotFrame(ghost)
        ghost._cdcSlot:SetAllPoints(ghost)
        ghost._cdcSlot:EnableMouse(false)
    end

    local ghostSlot = ghost._cdcSlot
    ghostSlot.previewBarInfo = ghost.previewBarInfo
    ghostSlot.castPreview = ghost.castPreview
    ConfigureGhostSlotPreview(ghostSlot, slotData, preview, ghost:GetWidth(), ghost:GetHeight())
    ghost.previewBarInfo = ghostSlot.previewBarInfo
    ghost.castPreview = ghostSlot.castPreview
    ghost:SetAlpha(0.92)
    ghost:Show()
    preview.ghostActive = true
    UpdateGhostPosition(ghost)
end

local function ClearGhost(preview)
    preview.ghostActive = false
    if preview.ghost then
        preview.ghost:Hide()
    end
end

local function CreateLayoutDragModel(preview)
    local layoutDrag = { host = preview.host, lanes = {} }

    -- The lifecycle hands the drag state through, and the dragged bar's model
    -- is what the containment clamp needs: its rank decides where the gap is
    -- allowed to open.
    layoutDrag.resolveDropTarget = function(cursorX, cursorY, state)
        return ResolveDropTarget(layoutDrag, cursorX, cursorY, state and state.slotData)
    end

    layoutDrag.onActivate = function(state)
        if not (state and state.widget and state.slotData) then return end
        layoutDrag.draggedSlotId = state.slotData.id
        layoutDrag.draggedSlotData = state.slotData
        preview.draggedSlotExtent = GetSlotExtent(state.slotData, nil)
        ConfigureGhost(preview, state.slotData, state.widget)
        for _, lane in ipairs(layoutDrag.lanes) do
            UpdateLanePreview(preview, lane, state.slotData.id, state.dropTarget)
        end
        preview.root:SetScript("OnUpdate", GetPreviewTick(preview))
    end

    layoutDrag.onUpdate = function(state, cursorX, cursorY, dropTarget)
        if not (state and state.slotData) then return end
        layoutDrag.draggedSlotId = state.slotData.id
        layoutDrag.draggedSlotData = state.slotData
        preview.draggedSlotExtent = GetSlotExtent(state.slotData, nil)
        for _, lane in ipairs(layoutDrag.lanes) do
            UpdateLanePreview(preview, lane, state.slotData.id, dropTarget)
        end
        if not preview.ghostActive then
            ConfigureGhost(preview, state.slotData, state.widget)
        else
            UpdateGhostPosition(preview.ghost)
        end
        preview.root:SetScript("OnUpdate", GetPreviewTick(preview))
    end

    layoutDrag.onCancel = function()
        layoutDrag.draggedSlotId = nil
        layoutDrag.draggedSlotData = nil
        preview.draggedSlotExtent = nil
        for _, lane in ipairs(layoutDrag.lanes) do
            ResetLanePreview(preview, lane)
        end
        ClearGhost(preview)
        HideDragIndicator()
        preview.root:SetScript("OnUpdate", GetPreviewTick(preview))
    end

    layoutDrag.applyDrop = function(state)
        local dropTarget = state and state.dropTarget
        local slotData = state and state.slotData
        if not dropTarget or not slotData or not dropTarget.lane then
            return
        end

        local lane = dropTarget.lane
        local filtered = {}
        for _, slot in ipairs(lane.slotModels or {}) do
            if slot.id ~= slotData.id then
                table_insert(filtered, slot)
            end
        end

        -- Re-clamped here, not just trusted from the drop target: the commit
        -- and the gap indicator must land on the same index, and this is the
        -- last point that can guarantee it.
        local adjustedIndex = ClampLaneInsertIndex(lane, slotData, filtered,
            math_max(1, math_min(#filtered + 1, dropTarget.insertIndex or 1)))
        -- The Independent Resources stack is the only drag source (the
        -- standalone cast slot never starts one), and it is one continuous
        -- stack: normalize every rendered slot to the chosen lane so the saved
        -- runtime layout matches the order shown after a drop.
        local changed = false
        table_insert(filtered, adjustedIndex, slotData)
        local slotCount = #filtered
        for index, slot in ipairs(filtered) do
            local normalizedOrder = lane.reversed and (slotCount - index + 1) or index
            if slot.getPos() ~= lane.side or slot.getOrder() ~= normalizedOrder then
                changed = true
            end
            slot.setPos(lane.side)
            slot.setOrder(normalizedOrder)
        end

        if changed then
            CooldownCompanion:ApplyResourceBars()
            CooldownCompanion:RefreshConfigPanel()
        end
    end

    return layoutDrag
end

function ST._BuildLayoutOrderPanel(container)
    if CS.dragState and CS.dragState.kind == LAYOUT_PREVIEW_DRAG_KIND and CancelDrag then
        CancelDrag()
    end

    local preview = EnsurePreviewState(container)
    preview.host = container
    preview.rbSettings = CooldownCompanion:GetResourceBarSettings()
    preview.cbSettings = CooldownCompanion:GetCastBarSettings()
    local rbSettings = preview.rbSettings
    local cbSettings = preview.cbSettings
    local workspaceKind = CS.barWorkspaceKind
    local standaloneCast = workspaceKind == "castbar"
    local standaloneResources = workspaceKind == "resources"
    local layout = CooldownCompanion:GetSpecLayoutOrder()
    if standaloneCast and not layout then layout = {} end
    local resourceBarsEnabled = standaloneResources and rbSettings and rbSettings.enabled == true
    local castBarEnabled = standaloneCast and cbSettings and cbSettings.enabled == true
    preview.isVerticalLayout = resourceBarsEnabled
        and IsResourceBarVerticalConfig(rbSettings, layout)
        or false

    ResetPreviewState(preview)
    -- Corner chrome first: it claims part of the host's bottom reserve, and
    -- everything below - the composition's fit box and the message box
    -- alike - is measured against what that reserve leaves. Every exit from
    -- this function is downstream of here, so the cluster is on screen in
    -- the message-only states too.
    BuildBarsEnableCluster(preview)
    ApplyHostBottomReserve(container, preview.root)
    preview.layout = layout
    -- The real spacing between stacked bars.
    preview.slotGap = math_max(0, tonumber(layout and layout.barSpacing)
        or tonumber(rbSettings and rbSettings.barSpacing)
        or LAYOUT_PREVIEW_GAP)
    preview.draggedSlotExtent = nil
    HidePreviewMessage(preview)

    local frameAnchoringSettings = CooldownCompanion.GetFrameAnchoringSettings
        and CooldownCompanion:GetFrameAnchoringSettings()
    local unitFramesEnabled = (workspaceKind == "player" or workspaceKind == "target")
        and frameAnchoringSettings
        and frameAnchoringSettings.enabled == true
    if not (resourceBarsEnabled or castBarEnabled or unitFramesEnabled) then
        FinishPreviewWithMessage(preview,
            workspaceKind == "resources" and "Enable Resource Bars below to start."
                or workspaceKind == "castbar" and "Enable Cast Bar below to start."
                or "Enable Unit Frame Anchoring below to start.")
        return
    end

    -- Only Independent bars are drawn here. A module on a panel is moved to
    -- that panel's workspace before every full refresh (_NormalizeBarWorkspace),
    -- and unit frames are never Independent, so a module awaiting a panel, or
    -- a rebuild that runs before the move, shows its anchor status (blank
    -- while that panel is fine).
    if ST._GetBarWorkspacePlacement(workspaceKind) ~= "independent" then
        FinishPreviewWithMessage(preview, CooldownCompanion:GetModuleAnchorStatusText(
            CooldownCompanion:ResolveModulePanel(workspaceKind)))
        return
    end

    preview.standaloneCast = standaloneCast
    preview.independentResources = resourceBarsEnabled == true
    if not layout then
        FinishPreviewWithMessage(preview, "Specialization data loading...")
        return
    end

    local slots, castSlots = CollectPreviewSlots(
        rbSettings,
        castBarEnabled and cbSettings or nil,
        layout,
        preview.isVerticalLayout,
        resourceBarsEnabled,
        resourceBarsEnabled
    )
    for _, castSlot in ipairs(castSlots) do
        table_insert(slots, castSlot)
    end
    if #slots == 0 then
        FinishPreviewWithMessage(preview, resourceBarsEnabled
            and "No active resources to order. Enable a resource first."
            or "No active bars to order. Enable Resources or the cast bar first.")
        return
    end

    local layoutDrag = CreateLayoutDragModel(preview)
    preview.layoutDrag = layoutDrag

    local root = preview.root
    local content = AcquireContainer(preview, root)
    content:SetClipsChildren(false)

    local resourceThickness = math_max(8, tonumber(GetResourceGlobalThickness(rbSettings)) or 12)
    local independentLength = math_max(
        20,
        tonumber(standaloneCast and cbSettings.independentWidth or layout.independentWidth or rbSettings.independentWidth) or 200
    )
    local contentWidth, contentHeight
    if preview.isVerticalLayout then
        contentWidth, contentHeight = RenderIndependentVerticalLayout(
            preview, content, layoutDrag, slots, independentLength, resourceThickness)
    else
        contentWidth, contentHeight = RenderIndependentHorizontalLayout(
            preview, content, layoutDrag, slots, independentLength, resourceThickness)
    end

    local hostWidth = container:GetWidth() or 0
    local hostHeight = (container:GetHeight() or 0) - GetHostBottomReserve(container)
    if hostWidth < 40 then hostWidth = 340 end
    if hostHeight < 40 then hostHeight = 520 end
    local maxWidth = math_max(120, hostWidth - (LAYOUT_PREVIEW_PADDING * 2))
    local maxHeight = math_max(120, hostHeight - (LAYOUT_PREVIEW_PADDING * 2))

    content:SetSize(math_max(1, contentWidth), math_max(1, contentHeight))
    -- Centered in the pane so dead space stays symmetric. The root already
    -- stops short of the host's bottom band, so this stays a zero anchor
    -- offset - which is what keeps it exact under the fit-to-host scale.
    content:SetScale(math_min(1, maxWidth / math_max(1, contentWidth), maxHeight / math_max(1, contentHeight)))
    content:ClearAllPoints()
    content:SetPoint("CENTER", root, "CENTER", 0, 0)

    -- Charge borders use the real physical-pixel inset. The fit is only known
    -- after building the lanes; repaint those bars at their final scale.
    for index = 1, (preview.used.slots or 0) do
        local barInfo = preview.pools.slots[index].previewBarInfo
        local bar = barInfo and barInfo.frame
        local charges = bar and bar._chargeSegments
        if charges and charges._attached and charges._scale ~= bar:GetEffectiveScale() then
            ApplyPreviewBarState(barInfo, preview.rbSettings, nil, barInfo.appearance)
        end
        if bar then
            local auraEffect = bar.barAuraEffect
            local auraOverlay = bar._ccResourceAuraPreview
            local maxBorder = bar._ccMWMaxBorder
            ST.RefreshBorderTextureScale(auraEffect and auraEffect.solidTextures)
            ST.RefreshBorderTextureScale(auraOverlay and auraOverlay.glow and auraOverlay.glow.edges)
            ST.RefreshBorderTextureScale(maxBorder and maxBorder.glow and maxBorder.glow.edges)
        end
    end

    FinalizePreviewState(preview)
    StartPreviewAnimationDriver(preview)
end

-- True when the Layout & Order lanes would actually render bars around an
-- anchored panel: something enabled and attached, spec layout loaded, and
-- at least one active slot. The buttons view gates the attached-bar badge
-- and the command center's bar controls on this.
function ST._HasAttachedBarLanesToRender(panelId)
    panelId = panelId or GetPreviewPanelId()
    local rbSettings = CooldownCompanion:GetResourceBarSettings()
    local cbSettings = CooldownCompanion:GetCastBarSettings()
    local layout = CooldownCompanion:GetSpecLayoutOrder()
    if not layout then
        return false
    end
    local resourceBarsEnabled = rbSettings and rbSettings.enabled == true and ModuleBelongsToPreview("resources", panelId)
    local castBarEnabled = cbSettings and cbSettings.enabled == true and ModuleBelongsToPreview("castbar", panelId)
    local supportsAttachedResourceBars = resourceBarsEnabled
        and not CooldownCompanion:IsResourceBarAnchorIndependent()
    local hasAttachedCastBar = castBarEnabled
        and not CooldownCompanion:IsModuleAnchorIndependent("castbar")
    if not supportsAttachedResourceBars and not hasAttachedCastBar then
        return false
    end
    local isVertical = resourceBarsEnabled
        and IsResourceBarVerticalConfig(rbSettings, layout)
        or false
    local primarySlots, castSlots = CollectPreviewSlots(
        rbSettings,
        castBarEnabled and cbSettings or nil,
        layout,
        isVertical,
        supportsAttachedResourceBars
    )
    return #primarySlots > 0 or #castSlots > 0
end

-- Does the bars canvas draw a cast slot right now? The command center asks
-- before offering the cast preview: offering a preview whose destination is
-- not on screen means pressing play visibly does nothing. Only the Cast Bar
-- workspace's Independent Cast Bar is a cast slot here.
--
-- Answered by re-deriving the build's own preconditions rather than by
-- reporting what the last build drew: the command center runs BEFORE the
-- renderer on every rebuild (it owns the host's bottom reserve, which the
-- renderer then measures), so a recorded answer would always be one change
-- stale.
--
-- Deliberately an OFFER test only. It must not feed the stranded-preview
-- stop: `layout` is briefly nil across a spec change, and stopping on that
-- would kill a running preview for a transient live condition.
function ST._ResourcesPreviewRendersCastSlot()
    if not IsBarsWorkspaceActive() or CS.barWorkspaceKind ~= "castbar" then
        return false
    end
    local settings = CooldownCompanion:GetCastBarSettings()
    return settings and settings.enabled == true
        and ST._GetBarWorkspacePlacement("castbar") == "independent" or false
end

-- Which resource power types the canvas draws lanes for right now: the SAME
-- three-way choice CollectPreviewSlots makes, exported so the preview command
-- center can offer a resource-aura toggle exactly when its destination lane is
-- on screen. Re-deriving the list over there is what put the two out of step
-- in BOTH directions — the runtime list honors form eligibility and the
-- Druid persistent-spec setting while the config list is spec-based, and
-- each is the right answer for a different anchor mode.
--
-- Offer test only, like the cast-slot sibling above: a nil layout is the
-- transient spec-change state, not a reason to stop a running preview.
--
-- A mutually exclusive pair is collapsed exactly as the slot builder
-- collapses it, then mapped to the half actually DRAWN: one lane exists for
-- the pair, and offering the hidden half a resource-aura toggle pointed at a
-- lane that is not on screen.
function ST._ResourcesPreviewResourceLanePowerTypes()
    local workspace = IsBarsWorkspaceActive()
    if workspace then
        -- The bars canvas draws the Independent stack only.
        if CS.barWorkspaceKind ~= "resources"
            or ST._GetBarWorkspacePlacement("resources") ~= "independent" then return {} end
    elseif not ModuleBelongsToPreview("resources", GetPreviewPanelId()) then
        return {}
    end
    local rbSettings = CooldownCompanion:GetResourceBarSettings()
    if not (rbSettings and rbSettings.enabled == true) then
        return {}
    end
    local layout = CooldownCompanion:GetSpecLayoutOrder()
    if not layout then
        -- "Specialization data loading..." - the canvas is a message.
        return {}
    end
    local powerTypes
    if workspace then
        -- The Independent stack draws from the runtime-eligible list.
        powerTypes = RB.DetermineActiveResources and RB.DetermineActiveResources(rbSettings) or {}
    else
        powerTypes = GetConfigActiveResources()
    end
    local lanes = CollapseToPlacementPowerTypes(powerTypes)
    for i = 1, #lanes do
        lanes[i] = RB.GetPlacementRenderPowerType(lanes[i])
    end
    return lanes
end

-- Select links fill gaps in the interactive preview, including the ordinary
-- panel's attached-module composition. Hidden or read-only copies cannot
-- replace a link. Call this after the active preview has finished building.
function ST._GetLayoutPreviewRenderedSelectionKeys(host)
    local function PanelKeys(panel)
        if not (panel and panel.root and panel.root:IsVisible()) or panel.readOnly then return end
        local modules = panel.modulePreview
        return modules and modules.root:IsVisible() and modules.renderedSelectionKeys or nil
    end
    local panel = host and host._cdcPanelPreview
    if panel and panel.root and panel.root:IsVisible() then
        return PanelKeys(panel)
    end
    local preview = host and host._cdcLayoutPreview
    if not (preview and preview.root and preview.root:IsVisible()) then return end
    return preview.renderedSelectionKeys
end

-- Config-safe icon identity is also used by the button preview family.
ST._GetLayoutPreviewIcon = GetLayoutPreviewIcon

local PanelHasConfiguredModuleBars

-- Ordinary panels render modules inside the same attachment composition as
-- their entries. Reuse this file's resource/cast painters and preview state.
-- Inside one settings rebuild the answer is reused (ST._WithModuleBarsMemo,
-- Config/State.lua), filed under the raw panel id so 12 and "12" stay apart.
function ST._PanelHasConfiguredModuleBars(panelId, kind)
    local memo = panelId ~= nil and ST._GetModuleBarsMemo()
    if not memo then return PanelHasConfiguredModuleBars(panelId, kind) end
    local answers = memo[panelId]
    if not answers then
        answers = {}
        memo[panelId] = answers
    end
    local slot = kind or "any"
    local answer = answers[slot]
    if answer == nil then
        answer = PanelHasConfiguredModuleBars(panelId, kind)
        answers[slot] = answer
    end
    return answer
end

PanelHasConfiguredModuleBars = function(panelId, kind)
    local group = CooldownCompanion.db.profile.groups[panelId]
    if not ST.PanelSupportsAttachedBars(group) then return false end
    local cast = ST.GetConfiguredModuleBarSettings("castbar")
    if kind ~= "resources" and cast and cast.enabled and CooldownCompanion:IsBarsAndFramesRuntimeFeatureEnabled("castBar")
        and ModuleBelongsToPreview("castbar", panelId, true, cast) then return true end
    if kind == "castbar" then return false end
    local saved = ST.GetConfiguredModuleBarSettings("resources")
    if not (saved and saved.enabled and CooldownCompanion:IsBarsAndFramesRuntimeFeatureEnabled("resourceBars")) then return false end
    -- Read-only on the live settings: module attachment falls back to their
    -- own independentAnchorEnabled, exactly what layout seeding writes.
    if not RB.GetCurrentSpecID() or not ModuleBelongsToPreview("resources", panelId, true, saved) then return false end
    for _, powerType in ipairs(GetConfigActiveResources()) do
        if RB.IsResourceEnabled(powerType, saved) then return true end
    end
    return false
end

function ST._GetPanelAttachmentPreviewModules(panelId, options)
    local group = CooldownCompanion.db.profile.groups[panelId]
    local overview = options and options.groupOverview == true
    if not ST.PanelSupportsAttachedBars(group) or (not overview and CS.unifiedAnchorBarsHidden) then return {} end
    local settings, cast, layout
    if overview then
        if CS.otherClassLibraryActive then return {} end
        local saved = ST.GetConfiguredModuleBarSettings("resources")
        if not (saved and saved.enabled and CooldownCompanion:IsBarsAndFramesRuntimeFeatureEnabled("resourceBars")) then return {} end
        -- Layout/default normalization and slot collection may fill nils. Keep
        -- all of those writes on the same detached snapshot used by painting.
        settings = CopyTable(saved)
        layout = RB.GetSpecLayoutOrder(settings)
    else
        settings, cast = CooldownCompanion:GetResourceBarSettings(), CooldownCompanion:GetCastBarSettings()
        layout = CooldownCompanion:GetSpecLayoutOrder()
    end
    if not layout then return {} end
    local resources = settings and settings.enabled and ModuleBelongsToPreview("resources", panelId, overview, settings)
    local hasCast = cast and cast.enabled and ModuleBelongsToPreview("castbar", panelId)
    local vertical = resources and IsResourceBarVerticalConfig(settings, layout) or false
    local slots, casts = CollectPreviewSlots(settings, hasCast and cast or nil, layout, vertical,
        resources == true, nil, overview and group or nil)
    local modules, sides = {}, {}
    local spacing = ST.ResolveBarGeometry(group).spacing
    for _, slot in ipairs(slots) do
        if slot.kind == "resource" then
            local side = RB.GetBarLaneSide(slot.getPos())
            local block = sides[side]
            if not block then
                local region = RB.GetResourceBlockRegion(layout, side, vertical)
                block = { kind = "resources", side = side, region = region == "main" and "main" or "outer",
                    slots = {}, thickness = 0, spacing = spacing, layout = layout,
                    resourceSettings = overview and settings or nil }
                sides[side], modules[#modules + 1] = block, block
            end
            block.slots[#block.slots + 1] = slot
        end
    end
    for _, block in ipairs(modules) do
        table.sort(block.slots, function(a,b)
            if a.getOrder() == b.getOrder() then return a.id < b.id end
            return a.getOrder() < b.getOrder()
        end)
        for i, slot in ipairs(block.slots) do
            block.thickness = block.thickness + (slot.thickness or 12) + (i > 1 and spacing or 0)
        end
    end
    for _, slot in ipairs(casts) do
        local side = RB.GetBarLaneSide(slot.getPos())
        local saved = layout.castBar or {}
        modules[#modules + 1] = { kind = "cast", side = side,
            region = saved.anchorRegion == "main" and "main" or "outer", slots = { slot },
            thickness = slot.thickness, layout = layout,
            attachmentOffset = ST.GetCastBarAttachmentOffset(cast, layout) }
    end
    return modules
end

function ST._ResetPanelModulePreview(preview)
    local state = preview.modulePreview
    if not state then return end
    state.root:Hide()
    state.renderedSelectionKeys = nil
    state.root:SetScript("OnUpdate", nil)
    wipe(state.animated)
    state.rbSettings, state.cbSettings, state.layout = nil, nil, nil
    for _, frame in ipairs(state.pools.slots) do
        frame:Hide()
        frame:EnableMouse(false)
        frame:SetScript("OnMouseDown", nil)
        frame:SetScript("OnMouseUp", nil)
        frame:SetScript("OnEnter", nil)
        frame:SetScript("OnLeave", nil)
    end
end

function ST._BuildPanelModulePreview(preview, panelId, positions, drag, animate)
    local state = preview.modulePreview
    if not positions or #positions == 0 then
        ST._ResetPanelModulePreview(preview)
        return
    end
    if not state then
        state = { pools = { slots = {} }, used = {}, animated = {}, tweens = {} }
        state.root = CreateFrame("Frame", nil, preview.content)
        state.root:SetAllPoints(preview.content)
        preview.modulePreview = state
    end
    wipe(state.animated)
    state.root:SetScript("OnUpdate", nil)
    state.skin = ResolvePreviewSkin(preview.root:GetParent())
    state.readOnly = preview.readOnly == true
    -- Only overview modules carry detached settings. Read-only drag ghosts
    -- still use the focused preview's resource and cast configuration.
    if preview.groupOverview then
        state.rbSettings = positions[1].module.resourceSettings
        state.cbSettings = nil
        state.layout = positions[1].module.layout
    else
        state.rbSettings, state.cbSettings = CooldownCompanion:GetResourceBarSettings(), CooldownCompanion:GetCastBarSettings()
        state.layout = CooldownCompanion:GetSpecLayoutOrder()
    end
    state.anchorPanelId = panelId
    state.used.slots = 0
    if not animate then state.framesBySlot = {} end
    state.renderedSelectionKeys = {}
    state.root:Show()
    for _, position in ipairs(positions or {}) do
        local module, offset = position.module, 0
        for _, slot in ipairs(module.slots) do
            local frame = animate and state.framesBySlot[slot] or AcquireSlot(state, state.root)
            local extent = slot.thickness or 12
            local vertical = position.vertical
            local width, height = vertical and extent or position.width, vertical and position.height or extent
            state.isVerticalLayout = vertical
            ConfigureSlotPreview(frame, slot, state, width, height)
            if preview.groupOverview and slot.kind == "resource" then
                -- The overview identifies the composition; sample values crowd
                -- thin resource stacks. Focused styling restores saved text.
                local bar = frame.previewBarInfo and frame.previewBarInfo.frame
                if bar and bar.text then bar.text:Hide() end
            end
            frame:SetSize(width, height)
            local x, y = position.x, position.y
            if module.side == "above" then y = y - position.height + offset + height
            elseif module.side == "below" then y = y - offset
            elseif module.side == "left" then x = x + position.width - offset - width
            else x = x + offset end
            if animate then
                ST._ButtonPanelPreview.QueuePreviewSlotTween(preview, frame, "TOPLEFT", x, y)
            else
                ST._ButtonPanelPreview.ApplyPreviewSlotGeometry(preview, frame, "TOPLEFT", x, y)
                state.framesBySlot[slot] = frame
                frame:SetAlpha(1)
            end
            frame._attachmentX, frame._attachmentY = x, y
            state.renderedSelectionKeys[slot.id] = true
            frame:EnableMouse(not state.readOnly)
            if state.readOnly and frame.copyTargetHighlight then frame.copyTargetHighlight:Hide() end
            if not state.readOnly then ApplySlotSelection(frame, slot, vertical, extent) end
            if not state.readOnly and not animate and ST._WirePanelAttachmentModule then
                ST._WirePanelAttachmentModule(frame, module, slot, drag)
            end
            offset = offset + extent + (module.spacing or 0)
        end
    end
    if not animate then
        for i = state.used.slots + 1, #state.pools.slots do state.pools.slots[i]:Hide() end
    end
    if #state.animated > 0 then
        state.root:SetScript("OnUpdate", function()
            local now = GetTime()
            for _, animation in ipairs(state.animated) do animation.Tick(animation, now) end
        end)
    end
end
