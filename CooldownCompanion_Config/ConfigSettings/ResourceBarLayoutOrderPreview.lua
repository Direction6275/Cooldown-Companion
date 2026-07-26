--[[
    CooldownCompanion - ResourceBarLayoutOrderPreview
    Dedicated layout/order preview renderer for attached resource bars.
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
local ApplyIconTexCoord = ST._ApplyIconTexCoord
local SetStatusBarSmoothRange = ST.SetStatusBarSmoothRange
local SetStatusBarSmoothValue = ST.SetStatusBarSmoothValue
local SetStatusBarImmediateValue = ST.SetStatusBarImmediateValue

local POWER_NAMES = RB.POWER_NAMES
local SEGMENTED_TYPES = RB.SEGMENTED_TYPES
local RESOURCE_HEALTH = RB.RESOURCE_HEALTH
local RESOURCE_MAELSTROM_WEAPON = RB.RESOURCE_MAELSTROM_WEAPON
local DEFAULT_RESOURCE_TEXT_FONT = RB.DEFAULT_RESOURCE_TEXT_FONT
local DEFAULT_RESOURCE_TEXT_SIZE = RB.DEFAULT_RESOURCE_TEXT_SIZE
local DEFAULT_RESOURCE_TEXT_OUTLINE = RB.DEFAULT_RESOURCE_TEXT_OUTLINE

local IsTruthyConfigFlag = RB.IsTruthyConfigFlag
local IsVerticalFillReversed = RB.IsVerticalFillReversed
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
local PrepareCustomAuraBar = RB.PrepareCustomAuraBar
local EnsureCustomBarId = RB.EnsureCustomBarId
local EnsureCustomBarLayout = RB.EnsureCustomBarLayout
local GetCustomBarLayout = RB.GetCustomBarLayout
local ApplyPreviewBarState = RB.ApplyPreviewBarState
local GetMWMaxStacks = RB.GetMWMaxStacks
local CreatePixelBorders = RB.CreatePixelBorders
local ApplyPixelBorders = RB.ApplyPixelBorders
local HidePixelBorders = RB.HidePixelBorders
local POWER_SHORT_NAMES = RB.POWER_SHORT_NAMES or {}

local LAYOUT_PREVIEW_PADDING = 12
local LAYOUT_PREVIEW_SECTION_GAP = 18
local LAYOUT_PREVIEW_GAP = 4
local LAYOUT_PREVIEW_DRAG_KIND = "layout-slot"
local LAYOUT_PREVIEW_ICON_FALLBACK = "Interface\\Icons\\INV_Misc_QuestionMark"
local LAYOUT_PREVIEW_ANIM_DURATION = 0.08
local LAYOUT_PREVIEW_EMPTY_DROP_SIZE = 8
local LAYOUT_PREVIEW_MAX_REAL_ICONS = 4

-- The cast facsimile. A cast bar has no ready state, so the resting slot
-- shows a cast frozen part-way — enough to judge and to drag. The preview
-- state runs the same cast on a loop.
local CAST_PREVIEW_DURATION = 1.5
local CAST_PREVIEW_REST_FILL = 0.65
local CAST_PREVIEW_SPELL_NAME = "Preview Cast"

-- Custom-bar identity, revealed on hover (owner ruling 2026-07-26, after
-- seeing a permanent label in game). The preview must be clean at rest AND
-- identify every bar at a glance; those only conflict if identity is
-- visible at rest, so it is not. Hovering any bar names them ALL at once —
-- one mouse movement, no clicks, the whole map — and moving away leaves
-- bars only.
--
-- A permanent label was tried first and rejected: anything drawn inside the
-- bar's rect reads as the bar's own content no matter how it is styled,
-- because that rect is exactly where bar text lives. A transient overlay
-- has the opposite problem to solve — it reads as an affordance on sight,
-- so it can be properly legible instead of apologetically dim, and it is
-- never present while the owner is judging their design.
-- Custom bars only; resources are identified by their well-known colors.
local LAYOUT_PREVIEW_IDENTITY_FONT_SCREEN_SIZE = 10
local LAYOUT_PREVIEW_IDENTITY_INSET = 4
local LAYOUT_PREVIEW_IDENTITY_FONT_OUTLINE = "OUTLINE, SLUG"
-- Shell (Show Only While Aura Active) bars carry the bar-mode panel
-- mirror's crossed-eye badge, same atlas and counter-scale convention, so
-- the two previews say "this one only shows while its aura runs" the same
-- way. The atlas has substantial transparent padding around its glyph.
local LAYOUT_PREVIEW_VISIBILITY_BADGE_ATLAS = "GM-icon-visibleDis-pressed"
local LAYOUT_PREVIEW_VISIBILITY_BADGE_SCREEN_SIZE = 18

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

-- Bottom chrome on the host - the preview command center, on every
-- workspace that has one - claims a band the composition must stay clear
-- of. Hosts without a bar report 0.
local function GetHostBottomReserve(host)
    return host and host._cdcPreviewReserveBottom or 0
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
            labels = {},
            icons = {},
            slots = {},
            gaps = {},
            unitProxies = {},
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
    preview.used.labels = 0
    preview.used.icons = 0
    preview.used.slots = 0
    preview.used.gaps = 0
    preview.used.unitProxies = 0
    preview.renderedSelectionKeys = {}
    preview.independentResources = false
    preview.layoutDrag = nil
    preview.animated = preview.animated or {}
    wipe(preview.animated)
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
    frame:SetParent(parent)
    frame:Show()
    return frame
end

local function AcquireLabel(preview, parent, fontObject)
    local pool = preview.pools.labels
    local index = (preview.used.labels or 0) + 1
    preview.used.labels = index
    local frame = pool[index]
    if not frame then
        frame = CreateFrame("Frame", nil, parent)
        frame.text = frame:CreateFontString(nil, "OVERLAY", fontObject or "GameFontNormal")
        frame.text:SetAllPoints()
        frame.text:SetJustifyH("LEFT")
        frame.text:SetJustifyV("MIDDLE")
        pool[index] = frame
    end
    frame:SetParent(parent)
    frame:Show()
    if fontObject then
        frame.text:SetFontObject(fontObject)
    end
    return frame
end

local function AcquireIcon(preview, parent)
    local pool = preview.pools.icons
    local index = (preview.used.icons or 0) + 1
    preview.used.icons = index
    local frame = pool[index]
    if not frame then
        frame = CreateFrame("Frame", nil, parent)
        frame.bg = frame:CreateTexture(nil, "BACKGROUND")
        frame.bg:SetAllPoints()
        frame.icon = frame:CreateTexture(nil, "ARTWORK")
        frame.countText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
        frame.countText:SetPoint("CENTER")
        frame.countText:SetJustifyH("CENTER")
        frame.countText:SetJustifyV("MIDDLE")
        frame.borderTextures = {}
        for i = 1, 4 do
            local tex = frame:CreateTexture(nil, "OVERLAY")
            frame.borderTextures[i] = tex
        end
        pool[index] = frame
    end
    frame:SetParent(parent)
    frame:Show()
    return frame
end

local function ApplyPreviewEdgeBorder(frame, size, color)
    if not (frame and frame.borderTextures) then return end
    local renderMode = ST.GetEffectiveBorderRenderMode(frame._previewBorderRenderMode, nil, size)
    ST.ApplyBorderTextures(frame.borderTextures, frame, color or { 0, 0, 0, 1 }, size or 1, renderMode)
end

local function HidePreviewEdgeBorder(frame)
    if not (frame and frame.borderTextures) then return end
    for i = 1, 4 do
        frame.borderTextures[i]:Hide()
    end
end

local function GetSourceIconBorderSize(button, fallback)
    -- Live icon geometry can be secret-sensitive in config context, so do not
    -- derive inset size from GetLeft()/GetRight()-style measurements here.
    -- Use the configured border size as the safe preview fallback instead.
    return fallback
end

local function StyleMirroredIconFrame(iconFrame, button, group)
    if not iconFrame then return end

    local style = group and group.style or {}
    if button and button.buttonData and CooldownCompanion.GetEffectiveStyle then
        style = CooldownCompanion:GetEffectiveStyle(style, button.buttonData) or style
    end

    local borderSize = GetSourceIconBorderSize(button, style.borderSize or ST.DEFAULT_BORDER_SIZE or 1)
    local borderRenderMode = ST.GetBorderRenderMode(style)
    local borderLayoutSize = ST.GetEffectiveBorderLayoutSize(iconFrame, borderSize, borderRenderMode)
    local bgColor = CloneColor(style.backgroundColor, { 0, 0, 0, 0.5 })
    local borderColor = CloneColor(style.borderColor, { 0, 0, 0, 1 })
    local showBorder = (borderSize > 0 or ST.IsEffectiveCrispBorderRenderMode(borderRenderMode, nil, borderSize)) and ((borderColor[4] ~= nil and borderColor[4] > 0) or borderColor[4] == nil)

    if button and button.borderTextures then
        local anyShown = false
        for i = 1, 4 do
            local tex = button.borderTextures[i]
            if tex and tex:IsShown() then
                anyShown = true
                break
            end
        end
        showBorder = anyShown and showBorder
    end

    iconFrame.bg:SetColorTexture(bgColor[1] or 0, bgColor[2] or 0, bgColor[3] or 0, bgColor[4] ~= nil and bgColor[4] or 1)
    iconFrame.icon:ClearAllPoints()
    iconFrame.icon:SetPoint("TOPLEFT", iconFrame, "TOPLEFT", borderLayoutSize, -borderLayoutSize)
    iconFrame.icon:SetPoint("BOTTOMRIGHT", iconFrame, "BOTTOMRIGHT", -borderLayoutSize, borderLayoutSize)
    iconFrame.icon:SetTexture((button and button.icon and button.icon:GetTexture()) or GetLayoutPreviewIcon(button and button.buttonData))
    iconFrame.icon:Show()
    iconFrame.countText:Hide()

    if button and button.icon and button.icon.GetTexCoord then
        iconFrame.icon:SetTexCoord(button.icon:GetTexCoord())
    else
        ApplyIconTexCoord(iconFrame.icon, iconFrame:GetWidth(), iconFrame:GetHeight())
    end

    if showBorder then
        iconFrame._previewBorderRenderMode = borderRenderMode
        ApplyPreviewEdgeBorder(iconFrame, borderSize, borderColor)
    else
        HidePreviewEdgeBorder(iconFrame)
    end
end

local function StyleSummaryIconFrame(iconFrame, templateButton, group, extraCount)
    StyleMirroredIconFrame(iconFrame, templateButton, group)
    iconFrame.icon:Hide()
    iconFrame.countText:SetText("+" .. tostring(extraCount or 0))
    iconFrame.countText:Show()
end

local function CreateSlotFrame(parent)
    local frame = CreateFrame("Button", nil, parent, "BackdropTemplate")
    frame:SetClipsChildren(false)
    frame:RegisterForClicks("LeftButtonDown", "AnyUp")

    frame.titleIcon = frame:CreateTexture(nil, "ARTWORK")
    frame.titleIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    frame.titleText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frame.titleText:SetJustifyH("LEFT")
    frame.titleText:SetWordWrap(false)

    frame.shortText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frame.shortText:SetJustifyH("CENTER")
    frame.shortText:SetWordWrap(false)

    frame.previewCanvas = CreateFrame("Frame", nil, frame)
    frame.previewCanvas:SetClipsChildren(false)

    frame.grip = frame:CreateTexture(nil, "OVERLAY")
    frame.grip:SetColorTexture(1, 1, 1, 0.14)

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

    -- Config-chrome identity marks (custom bars only), above the bar
    -- visuals but below the hover/selection highlights so those still read
    -- as the topmost state.
    frame.identityLayer = CreateFrame("Frame", nil, frame)
    frame.identityLayer:SetAllPoints(frame.previewCanvas)
    frame.identityLayer:EnableMouse(false)
    frame.identityLayer.label = frame.identityLayer:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frame.identityLayer.label:SetWordWrap(false)
    frame.identityLayer.badge = frame.identityLayer:CreateTexture(nil, "OVERLAY", nil, 7)
    frame.identityLayer:Hide()

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

local function CreateUnitFrameProxy(parent)
    local frame = CreateFrame("Button", nil, parent)
    frame:RegisterForClicks("LeftButtonUp")
    frame:SetClipsChildren(false)

    frame.portrait = frame:CreateTexture(nil, "ARTWORK")
    frame.portrait:SetSize(26, 26)
    frame.portrait:SetPoint("LEFT", frame, "LEFT", 0, 0)

    frame.health = CreateFrame("StatusBar", nil, frame)
    frame.health:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    frame.health:SetMinMaxValues(0, 100)
    frame.health:SetValue(72)
    frame.health:SetStatusBarColor(0.18, 0.72, 0.28, 0.92)
    frame.health:SetPoint("TOPLEFT", frame.portrait, "TOPRIGHT", 4, -2)
    frame.health:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 2)
    frame.health.bg = frame.health:CreateTexture(nil, "BACKGROUND")
    frame.health.bg:SetAllPoints()
    frame.health.bg:SetColorTexture(0.04, 0.05, 0.04, 0.88)

    frame.name = frame.health:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frame.name:SetPoint("LEFT", frame.health, "LEFT", 4, 0)
    frame.name:SetPoint("RIGHT", frame.health, "RIGHT", -4, 0)
    frame.name:SetJustifyH("LEFT")

    frame.hover = frame:CreateTexture(nil, "OVERLAY")
    frame.hover:SetAllPoints(frame.health)
    frame.hover:SetColorTexture(1, 1, 1, 0.11)
    frame.hover:SetBlendMode("ADD")
    frame.hover:Hide()

    frame.selected = frame:CreateTexture(nil, "OVERLAY", nil, 1)
    frame.selected:SetAllPoints(frame.health)
    frame.selected:SetColorTexture(1, 1, 1, 0.16)
    frame.selected:SetBlendMode("ADD")
    frame.selected:Hide()

    frame.accent = frame:CreateTexture(nil, "OVERLAY", nil, 2)
    frame.accent:SetWidth(3)
    frame.accent:SetPoint("TOPLEFT", frame.health, "TOPLEFT", 0, 0)
    frame.accent:SetPoint("BOTTOMLEFT", frame.health, "BOTTOMLEFT", 0, 0)
    frame.accent:Hide()

    frame:SetScript("OnEnter", function(self)
        self.hover:Show()
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(self._cdcLabel or "Unit Frame", 1, 1, 1)
        GameTooltip:AddLine("Click to edit this frame's anchoring.", 0.75, 0.82, 0.92, true)
        GameTooltip:Show()
    end)
    frame:SetScript("OnLeave", function(self)
        self.hover:Hide()
        GameTooltip:Hide()
    end)
    return frame
end

local function AcquireUnitFrameProxy(preview, parent)
    local pool = preview.pools.unitProxies
    local index = (preview.used.unitProxies or 0) + 1
    preview.used.unitProxies = index
    local frame = pool[index]
    if not frame then
        frame = CreateUnitFrameProxy(parent)
        pool[index] = frame
    end
    frame:SetParent(parent)
    frame:Show()
    return frame
end

local function SetPreviewMessage(preview, message)
    local label = preview.messageLabel
    if not label then
        label = preview.root:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        label:SetJustifyH("CENTER")
        label:SetJustifyV("MIDDLE")
        label:SetWordWrap(true)
        label:SetPoint("TOPLEFT", preview.root, "TOPLEFT", 18, -18)
        label:SetPoint("BOTTOMRIGHT", preview.root, "BOTTOMRIGHT", -18, 18)
        preview.messageLabel = label
    end
    label:SetText(message or "")
    label:Show()
end

local function HidePreviewMessage(preview)
    if preview.messageLabel then
        preview.messageLabel:Hide()
    end
end

GetLayoutPreviewIcon = function(buttonData)
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

local function BuildPreviewIconEntries(visibleButtons)
    local entries = {}
    local total = #visibleButtons
    local visibleCount = math_min(total, LAYOUT_PREVIEW_MAX_REAL_ICONS)

    for i = 1, visibleCount do
        entries[#entries + 1] = {
            kind = "button",
            button = visibleButtons[i],
        }
    end

    if total > LAYOUT_PREVIEW_MAX_REAL_ICONS then
        entries[#entries + 1] = {
            kind = "summary",
            extraCount = total - LAYOUT_PREVIEW_MAX_REAL_ICONS,
            templateButton = visibleButtons[visibleCount + 1] or visibleButtons[visibleCount] or visibleButtons[1],
        }
    end

    return entries
end

local function GetPreviewButtonSize(button, fallbackWidth, fallbackHeight)
    local width = fallbackWidth
    local height = fallbackHeight
    if button and type(button.GetWidth) == "function" then
        width = button:GetWidth() or width
    end
    if button and type(button.GetHeight) == "function" then
        height = button:GetHeight() or height
    end
    return width, height
end

local function GetConfiguredPreviewIconSize(group)
    local style = group and group.style or {}

    if style.maintainAspectRatio then
        local size = style.buttonSize or ST.BUTTON_SIZE or 36
        return size, size
    end

    local width = style.iconWidth or style.buttonSize or ST.BUTTON_SIZE or 36
    local height = style.iconHeight or style.buttonSize or ST.BUTTON_SIZE or 36
    return width, height
end

local function GetSavedPreviewButtons(group)
    if CooldownCompanion:IsRotationAssistantGroup(group) then
        local spellID = CooldownCompanion:GetRotationAssistantActionSpellID()
        return {
            {
                buttonData = {
                    type = "spell",
                    id = spellID,
                    name = ST.ROTATION_ASSISTANT_NAME,
                    manualIcon = CooldownCompanion:GetRotationAssistantFallbackIcon(spellID),
                    _rotationAssistantVirtual = true,
                    _rotationAssistantMissing = true,
                },
            },
        }
    end

    local buttons = {}
    local fallbackButtons = {}

    for _, buttonData in ipairs(group.buttons or {}) do
        if buttonData and buttonData.enabled ~= false then
            fallbackButtons[#fallbackButtons + 1] = { buttonData = buttonData }
            if not CooldownCompanion.IsButtonUsable or CooldownCompanion:IsButtonUsable(buttonData, group) then
                buttons[#buttons + 1] = { buttonData = buttonData }
            end
        end
    end

    if #buttons == 0 then
        buttons = fallbackButtons
    end

    local maxVisibleButtons = tonumber(group.maxVisibleButtons) or 0
    if maxVisibleButtons > 0 and #buttons > maxVisibleButtons then
        local trimmed = {}
        for i = 1, maxVisibleButtons do
            trimmed[#trimmed + 1] = buttons[i]
        end
        buttons = trimmed
    end

    return buttons
end

local function BuildSourcePanelData(groupId, group, visibleButtons, frame)
    if not group or not CooldownCompanion:IsIconLikeDisplayMode(group.displayMode) then
        return nil, "The current attached anchor panel is not an icon-like panel, so there is no icon row to mirror."
    end

    if #visibleButtons == 0 then
        return nil, "The current anchor panel has no saved icon buttons to mirror."
    end

    local style = group.style or {}
    local orientation = style.orientation or "horizontal"
    local buttonsPerRow = style.buttonsPerRow or 12
    local spacing = style.buttonSpacing or ST.BUTTON_SPACING or 4
    local sampleButton = frame and visibleButtons[1]
    local iconWidth, iconHeight = GetConfiguredPreviewIconSize(group)
    if sampleButton then
        iconWidth, iconHeight = GetPreviewButtonSize(sampleButton, iconWidth, iconHeight)
    end
    local previewIcons = BuildPreviewIconEntries(visibleButtons)
    local previewCount = #previewIcons

    local rows, cols
    if orientation == "vertical" then
        rows = math_min(previewCount, buttonsPerRow)
        cols = math.ceil(previewCount / buttonsPerRow)
    else
        cols = math_min(previewCount, buttonsPerRow)
        rows = math.ceil(previewCount / buttonsPerRow)
    end

    local frameWidth = (cols * iconWidth) + (math_max(0, cols - 1) * spacing)
    local frameHeight = (rows * iconHeight) + (math_max(0, rows - 1) * spacing)

    return {
        groupId = groupId,
        group = group,
        panelName = (group.name and group.name ~= "" and group.name) or ("Panel " .. tostring(groupId)),
        frame = frame,
        buttons = visibleButtons,
        previewIcons = previewIcons,
        orientation = orientation,
        buttonsPerRow = buttonsPerRow,
        spacing = spacing,
        iconWidth = iconWidth,
        iconHeight = iconHeight,
        rows = rows,
        cols = cols,
        width = frameWidth,
        height = frameHeight,
    }
end

local function IsGroupConfigAvailableForPreview(groupId, checkLoadConditions)
    local group = CooldownCompanion.db.profile.groups and CooldownCompanion.db.profile.groups[groupId]
    if not group then return false end
    if not group.parentContainerId then return false end
    if not CooldownCompanion:IsIconLikeDisplayMode(group.displayMode) then return false end
    if group.anchorEligible == false then return false end
    if CooldownCompanion.DoesAnchorTargetReachCursorRoot
        and CooldownCompanion:DoesAnchorTargetReachCursorRoot("CooldownCompanionGroup" .. tostring(groupId)) then
        return false
    end

    local container = CooldownCompanion:GetParentContainer(group)
    if container and container.isGlobal and not container.anchorEligible then return false end
    if container and not container.isGlobal and container.anchorEligible == false then return false end

    return CooldownCompanion:IsGroupActive(groupId, {
        group = group,
        requireButtons = true,
        checkCharVisibility = true,
        checkLoadConditions = checkLoadConditions,
    })
end

local function GetFirstConfiguredAnchorGroup()
    local db = CooldownCompanion.db and CooldownCompanion.db.profile
    local groups = db and db.groups
    local containers = db and db.groupContainers
    if not groups or not containers then return nil end

    local specId = CooldownCompanion._currentSpecId
    local orderedContainers = {}

    for containerId, container in pairs(containers) do
        orderedContainers[#orderedContainers + 1] = {
            id = containerId,
            order = CooldownCompanion:GetOrderForSpec(container, specId, containerId),
        }
    end
    table_sort(orderedContainers, function(a, b)
        return a.order < b.order
    end)

    for _, containerInfo in ipairs(orderedContainers) do
        local panels = CooldownCompanion:GetPanels(containerInfo.id)
        for _, panelInfo in ipairs(panels) do
            if IsGroupConfigAvailableForPreview(panelInfo.groupId, false) then
                return panelInfo.groupId
            end
        end
    end

    return nil
end

local function ResolveLayoutPreviewSourcePanel()
    local liveGroupId = CooldownCompanion:GetFirstAvailableAnchorGroup()
    if liveGroupId then
        local liveGroup = CooldownCompanion.db.profile.groups and CooldownCompanion.db.profile.groups[liveGroupId]
        local liveFrame = CooldownCompanion.groupFrames and CooldownCompanion.groupFrames[liveGroupId]
        if liveGroup and liveFrame and liveFrame:IsShown() then
            local liveButtons = {}
            for _, button in ipairs(liveFrame.buttons or {}) do
                if button and button:IsShown() and button.buttonData then
                    table_insert(liveButtons, button)
                end
            end
            if #liveButtons > 0 then
                return BuildSourcePanelData(liveGroupId, liveGroup, liveButtons, liveFrame)
            end
        end
    end

    local groupId = liveGroupId or GetFirstConfiguredAnchorGroup()
    if not groupId then
        return nil, "No attached icon panel is configured to mirror. Enable or create an icon-mode panel first."
    end

    local group = CooldownCompanion.db.profile.groups and CooldownCompanion.db.profile.groups[groupId]
    local savedButtons = group and GetSavedPreviewButtons(group) or nil
    if not savedButtons or #savedButtons == 0 then
        return nil, "The current attached anchor panel has no saved icon buttons to mirror."
    end

    return BuildSourcePanelData(groupId, group, savedButtons, nil)
end

local function GetShortLabel(label)
    if not label or label == "" then
        return "Bar"
    end
    local first = string.match(label, "^(%S+)")
    if not first then
        return label
    end
    if #first > 4 then
        return string.sub(first, 1, 4)
    end
    return first
end

local function CollectPreviewSlots(rbSettings, cbSettings, layout, isVerticalLayout, includeResourceSlots,
    requireRuntimeEligibleSlots)
    includeResourceSlots = includeResourceSlots == true
    local activeResources = includeResourceSlots
        and (requireRuntimeEligibleSlots and RB.DetermineActiveResources() or GetConfigActiveResources())
        or {}
    local customBars = includeResourceSlots and CooldownCompanion:GetSpecCustomAuraBars() or {}
    local primarySlots = {}
    local castSlots = {}
    local resourceBarsEnabled = includeResourceSlots and rbSettings and rbSettings.enabled

    if includeResourceSlots then
        layout.resources = layout.resources or {}
        layout.customAuraBarSlots = layout.customAuraBarSlots or {}
        layout.customBars = layout.customBars or {}
        rbSettings = rbSettings or {}
        rbSettings.resources = rbSettings.resources or {}
    end

    -- Per-slot thickness, resolved exactly as the apply pass resolves it
    -- (ResourceBar.lua, the customBarHeights branch): the override only
    -- applies when that layout flag is on, and the axis decides which
    -- stored key wins. Without this every slot rendered at one uniform
    -- thickness, so a bar with an override previewed at the wrong size.
    local globalThickness = includeResourceSlots
        and tonumber(GetResourceGlobalThickness(rbSettings)) or nil

    local function ResolveSlotThickness(slotLayout)
        if not (layout.customBarHeights and type(slotLayout) == "table") then
            return globalThickness
        end
        local override
        if isVerticalLayout then
            override = slotLayout.barWidth or slotLayout.barHeight
        else
            override = slotLayout.barHeight or slotLayout.barWidth
        end
        return tonumber(override) or globalThickness
    end

    local function GetSlotColor(powerType)
        if powerType == RESOURCE_HEALTH then
            local health = rbSettings.resources and rbSettings.resources[RESOURCE_HEALTH]
            local color = CloneColor(health and health.healthBarColor, RB.DEFAULT_HEALTH_BAR_COLOR)
            color[4] = tonumber(health and health.healthBarOpacity) or RB.DEFAULT_HEALTH_BAR_OPACITY
            return color
        end

        local color = { GetResourceColors(powerType, rbSettings) }
        if color[1] == nil then
            return { 1, 1, 1, 1 }
        end
        return {
            color[1] or 1,
            color[2] or 1,
            color[3] or 1,
            color[4] ~= nil and color[4] or 1,
        }
    end

    for _, powerType in ipairs(activeResources) do
        if powerType == RESOURCE_HEALTH and type(rbSettings.resources[powerType]) ~= "table" then
            rbSettings.resources[powerType] = { enabled = false }
        else
            rbSettings.resources[powerType] = rbSettings.resources[powerType] or {}
        end
        local resourceConfig = rbSettings.resources[powerType]
        local showResource = resourceBarsEnabled and (
            powerType == RESOURCE_HEALTH and resourceConfig.enabled == true
            or resourceConfig.enabled ~= false
        )
        if showResource and powerType == 0 and rbSettings.hideManaForNonHealer then
            local specIndex = C_SpecializationInfo.GetSpecialization()
            if specIndex then
                local specID, _, _, _, role = C_SpecializationInfo.GetSpecializationInfo(specIndex)
                if specID ~= 62 and role ~= "HEALER" then
                    showResource = false
                end
            end
        end

        if showResource then
            local function EnsureLayoutResource()
                layout.resources[powerType] = layout.resources[powerType] or {}
                return layout.resources[powerType]
            end

            table_insert(primarySlots, {
                id = "resource:" .. tostring(powerType),
                slotCategory = "primary",
                kind = "resource",
                powerType = powerType,
                label = POWER_NAMES[powerType] or ("Power " .. powerType),
                shortLabel = POWER_SHORT_NAMES[powerType] or GetShortLabel(POWER_NAMES[powerType] or ("Power " .. powerType)),
                thickness = ResolveSlotThickness(layout.resources[powerType]),
                color = GetSlotColor(powerType),
                icon = resourceConfig.previewIcon or LAYOUT_PREVIEW_ICON_FALLBACK,
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

    if resourceBarsEnabled then
        for customIndex, customAura in ipairs(customBars or {}) do
            if customAura and customAura.enabled and customAura.spellID
                and (not requireRuntimeEligibleSlots
                    or CooldownCompanion:IsCustomBarRuntimeEligible(customAura)) then
                local customBarId = EnsureCustomBarId(rbSettings, customAura)
                local spellInfo = C_Spell.GetSpellInfo(customAura.spellID)
                local label = spellInfo and spellInfo.name or customAura.label or ("Custom Bar " .. customIndex)
                local slotName = "Custom Bar: " .. label
                local function EnsureLayoutSlot()
                    return EnsureCustomBarLayout(rbSettings, nil, customBarId, 1000 + customIndex)
                end

                table_insert(primarySlots, {
                    id = "custom:" .. tostring(customBarId),
                    slotCategory = "primary",
                    kind = "custom",
                    customAuraIndex = customIndex,
                    customBarId = customBarId,
                    customEntry = {
                        kind = "custom",
                        customBarIndex = customIndex,
                        customBarId = customBarId,
                        config = customAura,
                    },
                    label = slotName,
                    shortLabel = GetShortLabel(label),
                    thickness = ResolveSlotThickness(
                        GetCustomBarLayout(rbSettings, nil, customAura, false)),
                    color = CloneColor(customAura.barColor, { 0.52, 0.64, 1.0, 1 }),
                    icon = C_Spell.GetSpellTexture(customAura.spellID) or LAYOUT_PREVIEW_ICON_FALLBACK,
                    getPos = function()
                        local slot = GetCustomBarLayout(rbSettings, nil, customAura, false)
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
                        local slot = GetCustomBarLayout(rbSettings, nil, customAura, false)
                        if isVerticalLayout then
                            return (slot and slot.verticalOrder) or (slot and slot.order) or (1000 + customIndex)
                        end
                        return (slot and slot.order) or (1000 + customIndex)
                    end,
                    setPos = function(value)
                        local slot = EnsureLayoutSlot()
                        if isVerticalLayout then
                            slot.verticalPosition = value
                        else
                            slot.position = value
                        end
                    end,
                    setOrder = function(value)
                        local slot = EnsureLayoutSlot()
                        if isVerticalLayout then
                            slot.verticalOrder = value
                        else
                            slot.order = value
                        end
                    end,
                })
            end
        end
    end

    if cbSettings and cbSettings.enabled and not IsTruthyConfigFlag(cbSettings.independentAnchorEnabled) then
        table_insert(castSlots, {
            id = "cast",
            slotCategory = "cast",
            kind = "cast",
            label = "Cast Bar",
            shortLabel = "Cast",
            -- The cast bar's own height, not the stack's: it used to be
            -- folded into one max with the resource thickness, which
            -- clamped every bar up to whichever was taller.
            thickness = cbSettings.stylingEnabled and (tonumber(cbSettings.height) or 15) or 11,
            color = CloneColor(cbSettings.barColor, { 1.0, 0.72, 0.18, 1 }),
            icon = LAYOUT_PREVIEW_ICON_FALLBACK,
            getPos = function()
                return (layout.castBar and layout.castBar.position) or "below"
            end,
            getOrder = function()
                return (layout.castBar and layout.castBar.order) or 2000
            end,
            setPos = function(value)
                layout.castBar = layout.castBar or { position = "below", order = 2000 }
                layout.castBar.position = value
            end,
            setOrder = function(value)
                layout.castBar = layout.castBar or { position = "below", order = 2000 }
                layout.castBar.order = value
            end,
        })
    end

    return primarySlots, castSlots
end

local function SortSlotsForSide(slots, side, reversed)
    local out = {}
    for _, slot in ipairs(slots) do
        if slot.getPos() == side then
            table_insert(out, slot)
        end
    end
    table_sort(out, function(a, b)
        if reversed then
            return a.getOrder() > b.getOrder()
        end
        return a.getOrder() < b.getOrder()
    end)
    return out
end

local function SortSlotsForIndependentStack(slots, firstSide, secondSide)
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
        local aOrder = a.getOrder()
        local bOrder = b.getOrder()
        if aOrder ~= bOrder then
            return reversed and aOrder > bOrder or aOrder < bOrder
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

-- A running preview keeps the ticker alive on its own, independently of the
-- drag tweens that otherwise own it.
local function StartPreviewAnimationDriver(preview)
    if #preview.animated == 0 then
        return
    end
    preview.root:SetScript("OnUpdate", function()
        TickPreview(preview)
    end)
end

local function ConfigureSlotChrome(frame, slot, skin, isVertical)
    ApplyBackdrop(frame, { 0, 0, 0, 0 }, { 0, 0, 0, 0 })
    frame.titleIcon:Hide()
    frame.titleText:Hide()
    frame.shortText:Hide()
    frame.grip:Hide()
    if frame.hoverHighlight then
        frame.hoverHighlight:SetFrameLevel(frame:GetFrameLevel() + 20)
        frame.hoverHighlight:Hide()
    end
    if frame.selectedHighlight then
        frame.selectedHighlight:SetFrameLevel(frame:GetFrameLevel() + 19)
        frame.selectedHighlight:Hide()
    end
    if frame.identityLayer then
        frame.identityLayer:SetFrameLevel(frame:GetFrameLevel() + 18)
        frame.identityLayer:Hide()
    end

    frame.previewCanvas:ClearAllPoints()
    frame.previewCanvas:SetAllPoints(frame)
end

-- Identity marks for one custom-bar slot. Runs AFTER the content scale is
-- known so both marks can counter-scale and stay legible on a preview that
-- has been shrunk to fit. The badge is permanent (a small corner glyph
-- reads as chrome, and the setting it stands for has no other visual); the
-- name is laid out here but only shown while the preview is hovered.
-- widthOverride: for the drag ghost, whose slot takes its size from anchors
-- and would measure nothing until the next layout pass.
local function ApplySlotIdentityMarks(preview, frame, scale, widthOverride)
    local layer = frame and frame.identityLayer
    if not layer then return end
    local slot = frame.slotData
    if not (slot and slot.kind == "custom") then
        layer:Hide()
        return
    end

    scale = math_max(scale or 1, 0.01)
    local isVertical = frame._cdcIdentityVertical == true

    -- A narrow vertical bar cannot carry a name, so it gets the same short
    -- label the drag chrome uses; its plate is allowed to overhang the thin
    -- bar, which a transient overlay can afford to do.
    local text = isVertical and slot.shortLabel or slot.label
    -- Slot labels are stored as "Custom Bar: <name>"; the prefix is noise
    -- when every labelled bar in the canvas is a custom bar.
    if type(text) == "string" then
        text = string.gsub(text, "^Custom Bar:%s*", "")
    end

    local label = layer.label
    if text and text ~= "" then
        local fontFile = label:GetFont()
        -- Slug outline instead of a backing plate: it keeps the name
        -- legible over any bar color without laying an opaque rectangle
        -- across the bar the owner is trying to look at.
        label:SetFont(fontFile,
            math_max(8, math_min(14, LAYOUT_PREVIEW_IDENTITY_FONT_SCREEN_SIZE / scale)),
            LAYOUT_PREVIEW_IDENTITY_FONT_OUTLINE)
        ST.ApplyFontShadowForOutline(label, LAYOUT_PREVIEW_IDENTITY_FONT_OUTLINE)
        label:SetText(text)
        label:SetTextColor(1, 1, 1, 1)
        label:SetJustifyH("CENTER")
        label:ClearAllPoints()
        label:SetPoint("CENTER", layer, "CENTER", 0, 0)
        if isVertical then
            label:SetWidth(0)
        else
            -- Snug to the text, but never wider than the bar: a long name
            -- truncates with an ellipsis instead of overflowing. Measured
            -- off the slot frame, which was explicitly sized; the layer
            -- inherits its size by anchor and reports nothing until the
            -- next layout pass.
            local available = math_max(1,
                (widthOverride or frame:GetWidth() or 0) - (LAYOUT_PREVIEW_IDENTITY_INSET * 2))
            label:SetWidth(math_min(label:GetStringWidth() + 1, available))
        end
        layer._cdcHasLabel = true
        label:SetShown(preview.identityLabelsShown == true)
    else
        layer._cdcHasLabel = nil
        label:Hide()
    end

    local badge = layer.badge
    local config = slot.customEntry and slot.customEntry.config
    if type(config) == "table" and config.hideWhenInactive == true then
        local size = math_min(24, math_max(12,
            LAYOUT_PREVIEW_VISIBILITY_BADGE_SCREEN_SIZE / scale))
        badge:SetAtlas(LAYOUT_PREVIEW_VISIBILITY_BADGE_ATLAS, false)
        badge:SetSize(size, size)
        badge:ClearAllPoints()
        if isVertical then
            badge:SetPoint("TOP", layer, "TOP", 0, 0)
        else
            badge:SetPoint("RIGHT", layer, "RIGHT", 0, 0)
        end
        badge:Show()
    else
        badge:Hide()
    end

    layer:Show()
end

-- Only a CUSTOM bar reveals the names: resources are identified by their
-- own well-known colors and never carry a label, so passing over one has
-- no reason to light the set up.
local function AnyCustomPreviewSlotHovered(preview)
    local pool = preview.pools and preview.pools.slots
    if not pool then return false end
    for index = 1, (preview.used.slots or 0) do
        local frame = pool[index]
        if frame and frame.slotData and frame.slotData.kind == "custom"
            and frame:IsShown() and frame:IsMouseOver() then
            return true
        end
    end
    return false
end

-- A reorder freezes the reveal wherever it was when the drag began. Slots
-- tween out from under the cursor while dragging, so enter/leave fire
-- continuously and the names flickered; and mid-reorder is precisely when
-- a stable read of which bar is which is worth the most.
local function IsLayoutDragActive()
    return CS.dragState ~= nil and CS.dragState.kind == LAYOUT_PREVIEW_DRAG_KIND
end

-- Reveal or hide every custom bar's name at once. Hovering ONE bar names
-- them ALL: the point is the whole map in one glance, which naming only the
-- hovered bar would not give (the tooltip already does that).
local function SetIdentityLabelsShown(preview, shown)
    shown = shown == true
    if IsLayoutDragActive() or preview.identityLabelsShown == shown then
        return
    end
    preview.identityLabelsShown = shown
    local pool = preview.pools and preview.pools.slots
    if not pool then return end
    for index = 1, (preview.used.slots or 0) do
        local layer = pool[index] and pool[index].identityLayer
        if layer and layer._cdcHasLabel then
            layer.label:SetShown(shown)
        end
    end
end

local function HideUnusedSlotVisuals(frame)
    if frame.previewBarInfo and frame.previewBarInfo.frame then
        frame.previewBarInfo.frame:Hide()
    end
    if frame.castPreview and frame.castPreview.root then
        frame.castPreview.root:Hide()
    end
end

local function EnsureResourcePreview(frame, slot, preview, width, height)
    HideUnusedSlotVisuals(frame)

    local barInfo = frame.previewBarInfo
    local rbSettings = preview.rbSettings
    local layout = preview.layout
    local segmentGap = (layout and layout.segmentGap) or rbSettings.segmentGap or 4

    if slot.kind == "custom" then
        local customBars = CooldownCompanion:GetSpecCustomAuraBars()
        barInfo = PrepareCustomAuraBar(
            frame.previewCanvas,
            barInfo,
            slot.customEntry,
            customBars,
            rbSettings,
            preview.isVerticalLayout,
            IsVerticalFillReversed(rbSettings),
            width,
            height,
            segmentGap
        )
        frame._cdcCustomBarLength = preview.isVerticalLayout and height or width
        -- The Active Aura preview state, on the canvas rather than out in the
        -- world (owner ruling 2026-07-26). Written every pass so stopping the
        -- preview clears it from a recycled frame.
        local cabConfig = slot.customEntry and slot.customEntry.config
        barInfo.frame._barAuraActivePreview = cabConfig
            and CooldownCompanion:IsCustomAuraBarActivePreviewActive(cabConfig)
            or nil
    elseif slot.powerType == 101 then
        if not barInfo or barInfo.barType ~= "stagger_continuous" then
            if barInfo and barInfo.frame then
                barInfo.frame:Hide()
            end
            barInfo = {
                frame = CreateContinuousBar(frame.previewCanvas),
                barType = "stagger_continuous",
                powerType = slot.powerType,
            }
        end
        barInfo.frame:SetSize(width, height)
        StyleContinuousBar(barInfo.frame, slot.powerType, rbSettings)
    elseif slot.powerType == RESOURCE_HEALTH then
        if not barInfo or barInfo.barType ~= "health_continuous" then
            if barInfo and barInfo.frame then
                barInfo.frame:Hide()
            end
            barInfo = {
                frame = CreateContinuousBar(frame.previewCanvas),
                barType = "health_continuous",
                powerType = slot.powerType,
            }
        end
        barInfo.frame:SetSize(width, height)
        StyleHealthBar(barInfo.frame, rbSettings)
    elseif slot.powerType == RESOURCE_MAELSTROM_WEAPON then
        local mwMaxStacks = GetMWMaxStacks() or 5
        local halfSegments = (mwMaxStacks <= 5) and mwMaxStacks or (mwMaxStacks / 2)
        if not barInfo or barInfo.barType ~= "mw_segmented" or #barInfo.frame.segments ~= halfSegments then
            if barInfo and barInfo.frame then
                barInfo.frame:Hide()
            end
            barInfo = {
                frame = CreateOverlayBar(frame.previewCanvas, halfSegments),
                barType = "mw_segmented",
                powerType = slot.powerType,
            }
        end
        barInfo.frame:SetSize(width, height)
        LayoutOverlaySegments(barInfo.frame, width, height, segmentGap, rbSettings, halfSegments)
        local baseColor, overlayColor = GetResourceColors(RESOURCE_MAELSTROM_WEAPON, rbSettings)
        for i = 1, halfSegments do
            barInfo.frame.segments[i]:SetStatusBarColor(baseColor[1], baseColor[2], baseColor[3], 1)
            barInfo.frame.overlaySegments[i]:SetStatusBarColor(overlayColor[1], overlayColor[2], overlayColor[3], 1)
            barInfo.frame.overlaySegments[i]:Show()
        end
        RB.StyleSegmentedText(barInfo.frame, slot.powerType, rbSettings)
    elseif SEGMENTED_TYPES[slot.powerType] then
        local maxValue = UnitPowerMax("player", slot.powerType)
        if slot.powerType == 5 then
            maxValue = 6
        end
        if not maxValue or maxValue < 1 then
            maxValue = 5
        end
        if not barInfo or barInfo.barType ~= "segmented" or barInfo.frame._numSegments ~= maxValue then
            if barInfo and barInfo.frame then
                barInfo.frame:Hide()
            end
            barInfo = {
                frame = CreateSegmentedBar(frame.previewCanvas, maxValue),
                barType = "segmented",
                powerType = slot.powerType,
            }
        end
        barInfo.frame:SetSize(width, height)
        LayoutSegments(barInfo.frame, width, height, segmentGap, rbSettings)
        StyleSegmentedBar(barInfo.frame, slot.powerType, rbSettings)
    else
        if not barInfo or barInfo.barType ~= "continuous" then
            if barInfo and barInfo.frame then
                barInfo.frame:Hide()
            end
            barInfo = {
                frame = CreateContinuousBar(frame.previewCanvas),
                barType = "continuous",
                powerType = slot.powerType,
            }
        end
        barInfo.frame:SetSize(width, height)
        StyleContinuousBar(barInfo.frame, slot.powerType, rbSettings)
    end

    frame.previewBarInfo = barInfo
    if barInfo and barInfo.frame then
        barInfo.frame:SetParent(frame.previewCanvas)
        barInfo.frame:ClearAllPoints()
        barInfo.frame:SetPoint("TOPLEFT", frame.previewCanvas, "TOPLEFT", 0, 0)
        barInfo.frame:SetPoint("BOTTOMRIGHT", frame.previewCanvas, "BOTTOMRIGHT", 0, 0)
        barInfo.frame:Show()
        ApplyPreviewBarState(barInfo, rbSettings)
        -- The aura-absent layer for stacks-mode aura bars: the real
        -- capacity blocks and their per-block rings, the same call the live
        -- apply pass makes. Without it a stack bar previewed as one
        -- continuous fill — the headline fidelity gap.
        --
        -- includeShell because the canvas renders hide-while-inactive bars
        -- (they must stay visible to edit); barLength because the bar frame
        -- has not been through a layout pass this frame, so the block layout
        -- cannot measure it; maxStacks because a bar the config shows may
        -- have no live slot running and therefore no cached max.
        if slot.kind == "custom" and RB.ApplyCustomBarAbsentStackVisuals then
            -- One resolved max for the blocks AND for the stand-in's lit run
            -- and stack text, so the number of blocks drawn and the number
            -- the text quotes can never disagree.
            local standInMax = RB.GetCustomBarStandInStackMax
                and RB.GetCustomBarStandInStackMax(barInfo, rbSettings) or nil
            RB.ApplyCustomBarAbsentStackVisuals(barInfo, rbSettings, {
                includeShell = true,
                barLength = frame._cdcCustomBarLength,
                maxStacks = standInMax,
                -- The Active Aura stand-in on a stacks bar: the blocks are
                -- the bar, so the lit run is painted here rather than as a
                -- fill over the top of them.
                litStacks = RB.GetCustomBarStandInLitStacks
                    and RB.GetCustomBarStandInLitStacks(barInfo, rbSettings, standInMax) or nil,
            })
        end
        if barInfo.frame._barAuraActivePreview and RB.AnimatePreviewBarAura then
            table_insert(preview.animated, {
                barInfo = barInfo,
                Tick = function(entry)
                    RB.AnimatePreviewBarAura(entry.barInfo)
                end,
            })
        elseif barInfo.barType == "health_continuous"
            and RB.IsHealthEffectPreviewAnimated
            and RB.IsHealthEffectPreviewAnimated() then
            table_insert(preview.animated, {
                barInfo = barInfo,
                -- Resolved here rather than per tick; see the exporter.
                config = RB.GetHealthPreviewAnimationConfig
                    and RB.GetHealthPreviewAnimationConfig(rbSettings) or nil,
                Tick = function(entry)
                    RB.AnimatePreviewHealthEffects(entry.barInfo, entry.config)
                end,
            })
        end
    end
end

local function EnsureCastPreview(frame)
    local castPreview = frame.castPreview
    if castPreview then
        return castPreview
    end

    local root = CreateFrame("Frame", nil, frame.previewCanvas)
    root:SetClipsChildren(false)

    local bar = CreateFrame("StatusBar", nil, root)
    bar:SetPoint("TOPLEFT", root, "TOPLEFT", 0, 0)
    bar:SetPoint("BOTTOMRIGHT", root, "BOTTOMRIGHT", 0, 0)

    local bg = bar:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bar.bg = bg

    local spark = bar:CreateTexture(nil, "OVERLAY", nil, 2)
    spark:SetTexture("Interface\\CastingBar\\UI-CastingBar-Spark")
    spark:SetBlendMode("ADD")
    bar.spark = spark

    local nameText = bar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    nameText:SetJustifyH("LEFT")
    bar.nameText = nameText

    local timeText = bar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    timeText:SetJustifyH("RIGHT")
    bar.timeText = timeText

    local iconFrame = CreateFrame("Frame", nil, root)
    local icon = iconFrame:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT", 1, -1)
    icon:SetPoint("BOTTOMRIGHT", -1, 1)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    iconFrame.icon = icon

    castPreview = {
        root = root,
        bar = bar,
        iconFrame = iconFrame,
        icon = icon,
        border = bar:CreateTexture(nil, "ARTWORK", nil, 6),
        pixelBorders = CreatePixelBorders(bar),
        iconBorders = CreatePixelBorders(iconFrame),
    }
    frame.castPreview = castPreview
    return castPreview
end

local function HideCastPixelBorders(castPreview)
    if castPreview.pixelBorders then
        HidePixelBorders(castPreview.pixelBorders)
    end
    if castPreview.iconBorders then
        HidePixelBorders(castPreview.iconBorders)
    end
end

-- Place the fill, the spark and the countdown for one moment of a cast.
-- `progress` is 0..1; the resting facsimile sits at CAST_PREVIEW_REST_FILL
-- because a cast bar has no ready state to show and the slot still has to be
-- visible and draggable.
local function SetCastPreviewProgress(castPreview, progress)
    local bar = castPreview.bar
    SetStatusBarSmoothRange(bar, 0, 100)
    -- Immediate, not smoothed: the sweep advances every tick, and smoothing
    -- toward a moving target would drag visibly backwards at the wrap.
    SetStatusBarImmediateValue(bar, progress * 100)
    if bar.spark:IsShown() then
        -- The measured length is the fallback, not the source: the slot is
        -- built and laid out in the same frame, so the anchor chain may not
        -- have resolved yet on the first pass.
        local barLength = castPreview.barLength or bar:GetWidth() or 0
        bar.spark:ClearAllPoints()
        bar.spark:SetPoint("CENTER", bar, "LEFT", barLength * progress, 0)
    end
    if bar.timeText:IsShown() then
        bar.timeText:SetFormattedText("%.1f s", CAST_PREVIEW_DURATION * (1 - progress))
    end
end

local function ConfigureCastPreview(frame, slot, preview, width, height)
    HideUnusedSlotVisuals(frame)

    local settings = preview.cbSettings
    local castPreview = EnsureCastPreview(frame)
    local root = castPreview.root
    local bar = castPreview.bar
    local iconFrame = castPreview.iconFrame
    local icon = castPreview.icon
    local border = castPreview.border

    root:SetParent(frame.previewCanvas)
    root:ClearAllPoints()
    root:SetPoint("TOPLEFT", frame.previewCanvas, "TOPLEFT", 0, 0)
    root:SetPoint("BOTTOMRIGHT", frame.previewCanvas, "BOTTOMRIGHT", 0, 0)
    root:Show()

    -- Effective appearance, the same split the live bar makes: with Styling
    -- off the real cast bar reverts to Blizzard visuals and every custom
    -- setting on this panel is dormant (CastBar.lua gates its whole styling
    -- layer on it, and the inline icon area is only reserved when it is on).
    -- The facsimile used to paint those settings regardless, advertising a
    -- look the live bar would never wear.
    local styled = settings.stylingEnabled == true

    local iconShown = styled and settings.showIcon ~= false
    local iconSize = height
    local iconGap = 4
    local barLeft = 0
    local barRight = 0

    if iconShown then
        if settings.iconOffset then
            iconSize = math_min(height, settings.iconSize or height)
        end
        iconFrame:SetSize(iconSize, iconSize)
        iconFrame:Show()
        icon:SetTexture(slot.icon or LAYOUT_PREVIEW_ICON_FALLBACK)
        if settings.iconFlipSide then
            iconFrame:ClearAllPoints()
            iconFrame:SetPoint("TOPRIGHT", root, "TOPRIGHT", 0, 0)
            barRight = -(iconSize + iconGap)
        else
            iconFrame:ClearAllPoints()
            iconFrame:SetPoint("TOPLEFT", root, "TOPLEFT", 0, 0)
            barLeft = iconSize + iconGap
        end
    else
        iconFrame:Hide()
    end

    bar:ClearAllPoints()
    bar:SetPoint("TOPLEFT", root, "TOPLEFT", barLeft, 0)
    bar:SetPoint("BOTTOMRIGHT", root, "BOTTOMRIGHT", barRight, 0)
    castPreview.barLength = math_max(0, width + barRight - barLeft)
    bar:SetStatusBarTexture(CooldownCompanion:FetchEffectiveBarTexture(
        (styled and settings.barTexture) or "Solid"))
    -- The configured colour, not the live cast bar's current one: this is the
    -- cast bar as configured, and reading the world bar would mirror whatever
    -- the last real cast happened to leave behind.
    local barColor = (styled and settings.barColor) or { 1, 0.72, 0.18, 1 }
    bar:SetStatusBarColor(barColor[1], barColor[2], barColor[3], barColor[4] ~= nil and barColor[4] or 1)
    local backgroundColor = (styled and settings.backgroundColor) or { 0, 0, 0, 0.5 }
    bar.bg:SetColorTexture(backgroundColor[1], backgroundColor[2], backgroundColor[3], backgroundColor[4] ~= nil and backgroundColor[4] or 1)

    border:Hide()
    HideCastPixelBorders(castPreview)

    -- Mirrors CastBar.lua's own resolution verbatim.
    local borderStyle = styled and (settings.borderStyle or "pixel") or "blizzard"
    if borderStyle == "pixel" then
        ApplyPixelBorders(castPreview.pixelBorders, bar, settings.borderColor or { 0, 0, 0, 1 }, settings.borderSize or 1, ST.GetBorderRenderMode(settings))
        if iconFrame:IsShown() and settings.iconOffset then
            ApplyPixelBorders(castPreview.iconBorders, iconFrame, settings.borderColor or { 0, 0, 0, 1 }, settings.iconBorderSize or 1, ST.GetBorderRenderMode(settings, "iconBorderRenderMode"))
        else
            HidePixelBorders(castPreview.iconBorders)
        end
    elseif borderStyle == "blizzard" then
        border:SetAllPoints(bar)
        border:SetAtlas("ui-castingbar-frame")
        border:Show()
    end

    -- Text and spark visibility follow the live contract too: with Styling
    -- off the real bar shows all three unconditionally (ApplyPreview and the
    -- spark resolution in CastBar.lua), so the per-element toggles are
    -- dormant along with the fonts.
    if styled and settings.showNameText == false then
        bar.nameText:Hide()
    else
        local font = CooldownCompanion:FetchFont(
            (styled and settings.nameFont) or DEFAULT_RESOURCE_TEXT_FONT)
        local nameOutline = ST.GetEffectiveFontOutline(
            (styled and settings.nameFontOutline) or DEFAULT_RESOURCE_TEXT_OUTLINE)
        bar.nameText:SetFont(font,
            (styled and settings.nameFontSize) or DEFAULT_RESOURCE_TEXT_SIZE, nameOutline)
        ST.ApplyFontShadowForOutline(bar.nameText, nameOutline)
        bar.nameText:ClearAllPoints()
        bar.nameText:SetPoint("LEFT", bar, "LEFT", 4, 0)
        bar.nameText:SetPoint("RIGHT", bar, "RIGHT", -4, 0)
        bar.nameText:SetText(CAST_PREVIEW_SPELL_NAME)
        bar.nameText:Show()
    end

    if styled and settings.showCastTimeText == false then
        bar.timeText:Hide()
    else
        local font = CooldownCompanion:FetchFont(
            (styled and settings.castTimeFont) or DEFAULT_RESOURCE_TEXT_FONT)
        local timeOutline = ST.GetEffectiveFontOutline(
            (styled and settings.castTimeFontOutline) or DEFAULT_RESOURCE_TEXT_OUTLINE)
        bar.timeText:SetFont(font,
            (styled and settings.castTimeFontSize) or DEFAULT_RESOURCE_TEXT_SIZE, timeOutline)
        ST.ApplyFontShadowForOutline(bar.timeText, timeOutline)
        bar.timeText:ClearAllPoints()
        bar.timeText:SetPoint("RIGHT", bar, "RIGHT",
            -4 + (styled and settings.castTimeXOffset or 0),
            styled and settings.castTimeYOffset or 0)
        bar.timeText:Show()
    end

    if styled and settings.showSpark == false then
        bar.spark:Hide()
    else
        bar.spark:SetWidth(8)
        bar.spark:SetHeight(math_max(8, height * 1.66))
        bar.spark:Show()
    end

    -- The cast bar's preview state: a cast in progress, looping. Nothing on
    -- the resting bar can stand in for one, which is what makes it worth a
    -- control in the first place.
    if CooldownCompanion:IsCastBarPreviewActive() then
        castPreview.startedAt = GetTime()
        table_insert(preview.animated, {
            castPreview = castPreview,
            Tick = function(entry, now)
                local elapsed = (now - entry.castPreview.startedAt) % CAST_PREVIEW_DURATION
                SetCastPreviewProgress(entry.castPreview, elapsed / CAST_PREVIEW_DURATION)
            end,
        })
        SetCastPreviewProgress(castPreview, 0)
    else
        castPreview.startedAt = nil
        SetCastPreviewProgress(castPreview, CAST_PREVIEW_REST_FILL)
    end
end

local function ConfigureSlotPreview(frame, slot, preview, width, height, isVerticalSlot)
    ConfigureSlotChrome(frame, slot, preview.skin, isVerticalSlot)
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
local function ConfigureGhostSlotPreview(frame, slot, preview, width, height, isVerticalSlot)
    local enrolled = #preview.animated
    ConfigureSlotPreview(frame, slot, preview, width, height, isVerticalSlot)
    for index = #preview.animated, enrolled + 1, -1 do
        preview.animated[index] = nil
    end
end

local function RenderMirroredPanel(preview, parent, panelData)
    local frame = AcquireContainer(preview, parent)
    ApplyBackdrop(frame, { 0, 0, 0, 0 }, { 0, 0, 0, 0 }, 1)
    frame:SetSize(panelData.width, panelData.height)

    frame:EnableMouse(true)
    frame:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Icons stay in place.", 1, 1, 1)
        GameTooltip:AddLine("Drag the attached bars around the icon row instead.", 0.75, 0.82, 0.92, true)
        GameTooltip:Show()
    end)
    frame:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    frame:SetScript("OnMouseDown", function()
        if UIErrorsFrame and UIErrorsFrame.AddMessage then
            UIErrorsFrame:AddMessage("Icons are fixed. Drag the bars around them.", 1, 0.25, 0.25, 1)
        end
    end)

    for index, entry in ipairs(panelData.previewIcons or {}) do
        local iconFrame = AcquireIcon(preview, frame)
        local button = entry.button or entry.templateButton
        local buttonWidth, buttonHeight = GetPreviewButtonSize(button, panelData.iconWidth, panelData.iconHeight)
        iconFrame:SetSize(buttonWidth, buttonHeight)

        local row
        local col
        if panelData.orientation == "vertical" then
            col = math_floor((index - 1) / panelData.buttonsPerRow)
            row = (index - 1) % panelData.buttonsPerRow
        else
            row = math_floor((index - 1) / panelData.buttonsPerRow)
            col = (index - 1) % panelData.buttonsPerRow
        end
        local x = col * (panelData.iconWidth + panelData.spacing)
        local y = -(row * (panelData.iconHeight + panelData.spacing))

        iconFrame:ClearAllPoints()
        iconFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", x, y)
        if entry.kind == "summary" then
            StyleSummaryIconFrame(iconFrame, entry.templateButton, panelData.group, entry.extraCount)
        else
            StyleMirroredIconFrame(iconFrame, button, panelData.group)
        end
        iconFrame:EnableMouse(false)
        iconFrame:SetScript("OnEnter", nil)
        iconFrame:SetScript("OnLeave", nil)
        iconFrame:SetScript("OnMouseDown", nil)
    end

    return frame
end

-- The unified anchor preview (buttons view) injects the real button-panel
-- mirror as the primary panel frame; the facsimile renders everywhere else
-- (and for the vertical layout's separate cast-bar section, which needs a
-- second copy of the panel).
local function AcquirePrimaryPanelFrame(preview, parent, panelData)
    local external = preview.externalPanelFrame
    if external then
        external:SetParent(parent)
        external:Show()
        return external
    end
    return RenderMirroredPanel(preview, parent, panelData)
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

local function BuildStableLaneSlots(lane, draggedSlotId)
    local laneScale = GetLaneScale(lane)
    if not laneScale then
        return nil, nil
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

    return laneScale, slotRects
end

local function SelectPreviewSlot(slot, modifierMulti)
    if type(slot) ~= "table" then
        return false
    end

    if CS.castFramesEntrySelected then
        if slot.kind == "cast" then
            if ST._SelectConfigCastFramesItem then
                ST._SelectConfigCastFramesItem("castbar")
            else
                CS.castFramesSelectedItem = "castbar"
            end
            return true
        end
        return false
    end

    -- Unified anchor preview (buttons view): route to the unified bar
    -- selection, which owns the entry-vs-bar exclusivity and cast support.
    if not CS.resourcesEntrySelected then
        if ST._SelectUnifiedAnchorBar then
            return ST._SelectUnifiedAnchorBar(slot)
        end
        return false
    end

    if slot.kind == "resource" and slot.powerType ~= nil and ST._SelectConfigResource then
        ST._SelectConfigResource(slot.powerType, { toggle = true })
        return true
    end

    if slot.kind == "custom" and slot.customBarId ~= nil and ST._SelectConfigCustomBar then
        if modifierMulti and ST._ToggleConfigCustomBarMultiSelect then
            if not CS.selectedCustomBarId then
                ST._SelectConfigCustomBar(slot.customBarId)
            end
            ST._ToggleConfigCustomBarMultiSelect(slot.customBarId)
        else
            ST._SelectConfigCustomBar(slot.customBarId, {
                toggle = true,
            })
        end
        return true
    end

    return false
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
        -- cross-axis size stays uniform (attached bars stretch to the
        -- anchor, exactly as the live stack does).
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
        local slotExtent = lane.naturalSizes[index]
        ConfigureSlotPreview(
            slotFrame, slotModel, preview,
            axis == "x" and slotExtent or slotWidth,
            axis == "x" and slotHeight or slotExtent,
            axis == "x")
        slotFrame.slotData = slotModel
        ApplySlotHitExpansion(slotFrame, slotExtent, lane.slotGap, axis == "x")
        -- Read by the identity-mark pass, which runs after the content
        -- scale is known and no longer has the lane in hand.
        slotFrame._cdcIdentityVertical = axis == "x"
        preview.renderedSelectionKeys[slotModel.id] = true

        -- Mark the bar currently being configured: held hover-style glow
        -- plus inward-pointing arrows. In the Cast Bar home only its cast
        -- slot participates; in the buttons view (unified anchor preview)
        -- the highlight follows the unified bar selection, so a stale
        -- Resources-home selection can't light a bar up.
        local isSelected
        if CS.castFramesEntrySelected then
            isSelected = slotModel.kind == "cast" and CS.castFramesSelectedItem == "castbar"
        elseif not CS.resourcesEntrySelected then
            local kind = CS.unifiedBarKind
            isSelected = (kind == "resource" and slotModel.kind == "resource"
                    and slotModel.powerType ~= nil
                    and tostring(CS.selectedResourcePowerType) == tostring(slotModel.powerType))
                or (kind == "custom" and slotModel.kind == "custom"
                    and slotModel.customBarId ~= nil
                    and tostring(CS.selectedCustomBarId) == tostring(slotModel.customBarId))
                or (kind == "cast" and slotModel.kind == "cast")
        else
            isSelected = (slotModel.kind == "resource" and slotModel.powerType ~= nil
                and tostring(CS.selectedResourcePowerType) == tostring(slotModel.powerType))
            or (slotModel.kind == "custom" and slotModel.customBarId ~= nil
                and (tostring(CS.selectedCustomBarId) == tostring(slotModel.customBarId)
                    or (CS.selectedCustomBars and CS.selectedCustomBars[slotModel.customBarId] == true)))
        end
        if isSelected and slotFrame.selectedHighlight then
            local marker = slotFrame.selectedHighlight
            local arrowSize = math_max(14, math_min(28, slotExtent + 6))
            marker.side1:SetSize(arrowSize, arrowSize)
            marker.side2:SetSize(arrowSize, arrowSize)
            marker.side1:ClearAllPoints()
            marker.side2:ClearAllPoints()
            if axis == "x" then
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
        slotFrame:SetScript("OnMouseDown", function(self, button)
            if button ~= "LeftButton" or GetCursorInfo() then return end
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
                if CS.resourcesEntrySelected and slotModel.kind == "custom"
                    and slotModel.customBarId ~= nil then
                    ST._SelectConfigCustomBar(slotModel.customBarId)
                    CooldownCompanion:RefreshConfigPanel()
                    if ST._OpenConfigCustomBarMenu then
                        ST._OpenConfigCustomBarMenu(slotModel.customBarId)
                    end
                end
                return
            end

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
                CooldownCompanion:RefreshConfigPanel()
            end
        end)
        slotFrame:SetScript("OnEnter", function(self)
            if self.hoverHighlight then
                self.hoverHighlight:Show()
            end
            -- Names every custom bar, not just this one — and only a
            -- custom bar triggers it.
            if slotModel.kind == "custom" then
                SetIdentityLabelsShown(preview, true)
            end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(slotModel.label or "Bar", 1, 1, 1)
            local dragHelp
            if CS.resourcesEntrySelected and slotModel.kind == "cast" then
                dragHelp = "Drag to reorder this attached bar. Edit it under Cast Bar & Unit Frames."
            else
                dragHelp = preview.independentResources
                    and "Click to edit. Drag to reorder this independent bar."
                    or "Click to edit. Drag to reorder this attached bar."
            end
            GameTooltip:AddLine(dragHelp, 0.75, 0.82, 0.92, true)
            if CS.resourcesEntrySelected and slotModel.kind == "custom" then
                GameTooltip:AddLine("Ctrl+Click to multi-select. Right-click for actions.", 0.75, 0.82, 0.92, true)
            end
            GameTooltip:Show()
        end)
        slotFrame:SetScript("OnLeave", function(self)
            if self.hoverHighlight then
                self.hoverHighlight:Hide()
            end
            -- Next frame, so sliding from one bar straight onto its
            -- neighbour does not flicker the whole set off and back on:
            -- by then the neighbour's OnEnter has fired and this reports
            -- the cursor still inside the stack.
            C_Timer.After(0, function()
                SetIdentityLabelsShown(preview, AnyCustomPreviewSlotHovered(preview))
            end)
            GameTooltip:Hide()
        end)
        local x, y, w, h = BuildLaneSlotGeometry(lane, index)
        ApplySlotGeometry(slotFrame, laneFrame, x, y, w, h, 1)
        lane.visualSlots[index] = slotFrame
        lane.slotFramesById[slotModel.id] = slotFrame
    end

    lane.gapFrame = AcquireGap(preview, laneFrame)
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

local function RenderHorizontalLayout(preview, content, layoutDrag, sourcePanel, slots, slotHeight)
    local panelFrame = AcquirePrimaryPanelFrame(preview, content, sourcePanel)
    local panelWidth = panelFrame:GetWidth()
    local panelHeight = panelFrame:GetHeight()
    local aboveSlots = SortSlotsForSide(slots, "above", true)
    local belowSlots = SortSlotsForSide(slots, "below", false)
    local slotFrameHeight = math_max(8, slotHeight)
    local aboveHeight = GetLaneExtent(preview, aboveSlots, slotFrameHeight)
    local belowHeight = GetLaneExtent(preview, belowSlots, slotFrameHeight)
    -- Live attached bars stretch to the anchor frame's width, so slots
    -- follow the acquired panel frame (the real mirror when injected),
    -- not the facsimile's precomputed size.
    local slotWidth = panelWidth

    local aboveLane = BuildLane(preview, content, layoutDrag, nil, panelWidth, aboveHeight, "y", "above", true, aboveSlots, slotWidth, slotFrameHeight, nil)
    aboveLane.frame:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)

    aboveLane.setPreviewOverflow = function(extra)
        aboveLane.frame:ClearAllPoints()
        aboveLane.frame:SetPoint("TOPLEFT", content, "TOPLEFT", 0, extra)
        aboveLane.frame:SetSize(aboveLane.baseWidth or panelWidth, (aboveLane.baseHeight or aboveHeight) + extra)
    end
    aboveLane.setPreviewOverflow(0)

    panelFrame:ClearAllPoints()
    panelFrame:SetPoint("TOPLEFT", aboveLane.frame, "BOTTOMLEFT", 0, -LAYOUT_PREVIEW_GAP)

    local belowLane = BuildLane(preview, content, layoutDrag, nil, panelWidth, belowHeight, "y", "below", false, belowSlots, slotWidth, slotFrameHeight, nil)
    belowLane.frame:SetPoint("TOPLEFT", panelFrame, "BOTTOMLEFT", 0, -LAYOUT_PREVIEW_GAP)

    local iconCenterOffsetY = aboveHeight + LAYOUT_PREVIEW_GAP + (panelHeight / 2)
    return panelWidth, aboveHeight + panelHeight + belowHeight + (LAYOUT_PREVIEW_GAP * 2), iconCenterOffsetY
end

local function RenderIndependentHorizontalLayout(preview, content, layoutDrag, slots, slotWidth, slotHeight)
    local stackSlots, stackSide, reversed = SortSlotsForIndependentStack(slots, "above", "below")
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
    local stackSlots, stackSide, reversed = SortSlotsForIndependentStack(slots, "left", "right")
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

local function RenderVerticalLayout(preview, content, layoutDrag, sourcePanel, primarySlots, castSlots, horizontalBarHeight, verticalBarWidth)
    if #primarySlots == 0 and #castSlots > 0 then
        local castPanel = AcquirePrimaryPanelFrame(preview, content, sourcePanel)
        local panelWidth = castPanel:GetWidth()
        local panelHeight = castPanel:GetHeight()
        local castSlotFrameHeight = math_max(8, horizontalBarHeight)
        local castAbove = SortSlotsForSide(castSlots, "above", true)
        local castBelow = SortSlotsForSide(castSlots, "below", false)
        local castAboveHeight = GetLaneExtent(preview, castAbove, castSlotFrameHeight)
        local castBelowHeight = GetLaneExtent(preview, castBelow, castSlotFrameHeight)

        local castAboveLane = BuildLane(preview, content, layoutDrag, nil, panelWidth, castAboveHeight, "y", "above", true, castAbove, panelWidth, castSlotFrameHeight, "cast")
        castAboveLane.frame:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)

        castAboveLane.setPreviewOverflow = function(extra)
            castAboveLane.frame:ClearAllPoints()
            castAboveLane.frame:SetPoint("TOPLEFT", content, "TOPLEFT", 0, extra)
            castAboveLane.frame:SetSize(castAboveLane.baseWidth or panelWidth, (castAboveLane.baseHeight or castAboveHeight) + extra)
        end
        castAboveLane.setPreviewOverflow(0)

        castPanel:ClearAllPoints()
        castPanel:SetPoint("TOPLEFT", castAboveLane.frame, "BOTTOMLEFT", 0, -LAYOUT_PREVIEW_GAP)

        local castBelowLane = BuildLane(preview, content, layoutDrag, nil, panelWidth, castBelowHeight, "y", "below", false, castBelow, panelWidth, castSlotFrameHeight, "cast")
        castBelowLane.frame:SetPoint("TOPLEFT", castPanel, "BOTTOMLEFT", 0, -LAYOUT_PREVIEW_GAP)

        local iconCenterOffsetY = castAboveHeight + LAYOUT_PREVIEW_GAP + (panelHeight / 2)
        return panelWidth, castAboveHeight + panelHeight + castBelowHeight + (LAYOUT_PREVIEW_GAP * 2), iconCenterOffsetY
    end

    local panelFrame = AcquirePrimaryPanelFrame(preview, content, sourcePanel)
    local panelWidth = panelFrame:GetWidth()
    local panelHeight = panelFrame:GetHeight()
    local leftSlots = SortSlotsForSide(primarySlots, "left", true)
    local rightSlots = SortSlotsForSide(primarySlots, "right", false)
    local leftWidth = GetLaneExtent(preview, leftSlots, verticalBarWidth)
    local rightWidth = GetLaneExtent(preview, rightSlots, verticalBarWidth)
    local verticalBarHeight = panelHeight

    local leftLane = BuildLane(preview, content, layoutDrag, nil, leftWidth, panelHeight, "x", "left", true, leftSlots, verticalBarWidth, verticalBarHeight, "primary")
    leftLane.frame:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)

    leftLane.setPreviewOverflow = function(extra)
        leftLane.frame:ClearAllPoints()
        leftLane.frame:SetPoint("TOPLEFT", content, "TOPLEFT", -extra, 0)
        leftLane.frame:SetSize((leftLane.baseWidth or leftWidth) + extra, leftLane.baseHeight or panelHeight)
    end
    leftLane.setPreviewOverflow(0)

    panelFrame:ClearAllPoints()
    panelFrame:SetPoint("TOPLEFT", leftLane.frame, "TOPRIGHT", LAYOUT_PREVIEW_GAP, 0)

    local rightLane = BuildLane(preview, content, layoutDrag, nil, rightWidth, panelHeight, "x", "right", false, rightSlots, verticalBarWidth, verticalBarHeight, "primary")
    rightLane.frame:SetPoint("TOPLEFT", panelFrame, "TOPRIGHT", LAYOUT_PREVIEW_GAP, 0)

    local totalWidth = leftWidth + panelWidth + rightWidth + (LAYOUT_PREVIEW_GAP * 2)
    local totalHeight = panelHeight

    if #castSlots > 0 then
        local castPanel = RenderMirroredPanel(preview, content, sourcePanel)
        local castSlotFrameHeight = math_max(8, horizontalBarHeight)
        local castAbove = SortSlotsForSide(castSlots, "above", true)
        local castBelow = SortSlotsForSide(castSlots, "below", false)
        local castAboveHeight = GetLaneExtent(preview, castAbove, castSlotFrameHeight)
        local castBelowHeight = GetLaneExtent(preview, castBelow, castSlotFrameHeight)

        local castAboveLane = BuildLane(preview, content, layoutDrag, nil, panelWidth, castAboveHeight, "y", "above", true, castAbove, panelWidth, castSlotFrameHeight, "cast")
        castAboveLane.frame:SetPoint("TOPLEFT", content, "TOPLEFT", leftWidth + LAYOUT_PREVIEW_GAP, -(panelHeight + LAYOUT_PREVIEW_SECTION_GAP))

        castAboveLane.setPreviewOverflow = function(extra)
            castAboveLane.frame:ClearAllPoints()
            castAboveLane.frame:SetPoint("TOPLEFT", content, "TOPLEFT", leftWidth + LAYOUT_PREVIEW_GAP, -(panelHeight + LAYOUT_PREVIEW_SECTION_GAP) + extra)
            castAboveLane.frame:SetSize(castAboveLane.baseWidth or panelWidth, (castAboveLane.baseHeight or castAboveHeight) + extra)
        end
        castAboveLane.setPreviewOverflow(0)

        castPanel:ClearAllPoints()
        castPanel:SetPoint("TOPLEFT", castAboveLane.frame, "BOTTOMLEFT", 0, -LAYOUT_PREVIEW_GAP)

        local castBelowLane = BuildLane(preview, content, layoutDrag, nil, panelWidth, castBelowHeight, "y", "below", false, castBelow, panelWidth, castSlotFrameHeight, "cast")
        castBelowLane.frame:SetPoint("TOPLEFT", castPanel, "BOTTOMLEFT", 0, -LAYOUT_PREVIEW_GAP)

        totalHeight = panelHeight + LAYOUT_PREVIEW_SECTION_GAP + castAboveHeight + castPanel:GetHeight() + castBelowHeight + (LAYOUT_PREVIEW_GAP * 2)
        totalWidth = math_max(totalWidth, leftWidth + LAYOUT_PREVIEW_GAP + panelWidth)
    end

    local iconCenterOffsetY = panelHeight / 2
    return totalWidth, totalHeight, iconCenterOffsetY
end

local function ConfigureUnitFrameProxy(frame, item, label, selected)
    local r, g, b = 0.40, 0.67, 1.0
    local _, classKey = UnitClass("player")
    local classColor = classKey and C_ClassColor.GetClassColor(classKey)
    if classColor then
        r, g, b = classColor.r, classColor.g, classColor.b
    end

    frame._cdcLabel = label
    frame.name:SetText(label)
    if item == "player" and classKey then
        frame.portrait:SetAtlas("classicon-" .. string.lower(classKey), false)
    else
        frame.portrait:SetAtlas("groupfinder-icon-friend", false)
    end
    frame.portrait:SetVertexColor(1, 1, 1, 1)
    frame.accent:SetColorTexture(r, g, b, 1)
    frame.selected:SetShown(selected == true)
    frame.accent:SetShown(selected == true)

    frame:SetScript("OnEnter", function(self)
        self.hover:Show()
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(self._cdcLabel or "Unit Frame", 1, 1, 1)
        GameTooltip:AddLine("Click to edit this frame's anchoring.", 0.75, 0.82, 0.92, true)
        GameTooltip:Show()
    end)
    frame:SetScript("OnLeave", function(self)
        self.hover:Hide()
        GameTooltip:Hide()
    end)
    frame:SetScript("OnClick", function()
        if ST._SelectConfigCastFramesItem then
            ST._SelectConfigCastFramesItem(item)
        else
            CS.castFramesSelectedItem = item
        end
        CooldownCompanion:RefreshConfigPanel()
    end)
end

local function AppendUnitFrameProxies(preview, content, contentWidth, contentHeight)
    local settings = CooldownCompanion.GetFrameAnchoringSettings
        and CooldownCompanion:GetFrameAnchoringSettings()
    if not (CS.castFramesEntrySelected and settings and settings.enabled == true) then
        return contentWidth, contentHeight
    end

    local proxyWidth = 126
    local proxyHeight = 30
    local proxyGap = 14
    local rowWidth = (proxyWidth * 2) + proxyGap
    local row = AcquireContainer(preview, content)
    row:SetSize(rowWidth, proxyHeight)
    row:ClearAllPoints()
    row:SetPoint(
        "TOPLEFT",
        content,
        "TOPLEFT",
        math_max(0, math_floor((math_max(contentWidth, rowWidth) - rowWidth) / 2)),
        -(contentHeight > 0 and (contentHeight + LAYOUT_PREVIEW_SECTION_GAP) or 0)
    )

    local player = AcquireUnitFrameProxy(preview, row)
    player:SetSize(proxyWidth, proxyHeight)
    player:ClearAllPoints()
    player:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
    ConfigureUnitFrameProxy(player, "player", "Player Frame", CS.castFramesSelectedItem == "player")
    preview.renderedSelectionKeys["frame:player"] = true

    local target = AcquireUnitFrameProxy(preview, row)
    target:SetSize(proxyWidth, proxyHeight)
    target:ClearAllPoints()
    target:SetPoint("LEFT", player, "RIGHT", proxyGap, 0)
    ConfigureUnitFrameProxy(target, "target", "Target Frame", CS.castFramesSelectedItem == "target")
    preview.renderedSelectionKeys["frame:target"] = true

    local height = contentHeight + (contentHeight > 0 and LAYOUT_PREVIEW_SECTION_GAP or 0) + proxyHeight
    return math_max(contentWidth, rowWidth), height
end

local function GetLayoutOrderForInsertion(laneSlots, reversed, insertIndex)
    local beforeSlot = laneSlots[insertIndex - 1]
    local afterSlot = laneSlots[insertIndex]
    if beforeSlot and afterSlot then
        local beforeOrder = beforeSlot.getOrder()
        local afterOrder = afterSlot.getOrder()
        if beforeOrder == afterOrder then
            return beforeOrder + (reversed and -0.5 or 0.5)
        end
        return (beforeOrder + afterOrder) / 2
    end
    if beforeSlot then
        return beforeSlot.getOrder() + (reversed and -1 or 1)
    end
    if afterSlot then
        return afterSlot.getOrder() + (reversed and 1 or -1)
    end
    return 1
end

local function GetLaneInsertIndex(lane, cursorX, cursorY, draggedSlotId)
    local _, slots = BuildStableLaneSlots(lane, draggedSlotId)
    if not slots then
        return 1
    end

    if #slots == 0 then
        return 1
    end

    if lane.axis == "x" then
        for index, slotRect in ipairs(slots) do
            if cursorX < ((slotRect.left + slotRect.right) / 2) then
                return index
            end
        end
        return #slots + 1
    end

    for index, slotRect in ipairs(slots) do
        if cursorY > ((slotRect.top + slotRect.bottom) / 2) then
            return index
        end
    end
    return #slots + 1
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

local function ResolveDropTarget(layoutDrag, cursorX, cursorY)
    local closestLane
    local closestLaneScale
    local closestDistance

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
                    insertIndex = GetLaneInsertIndex(lane, cursorX, cursorY, layoutDrag.draggedSlotId),
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
                insertIndex = GetLaneInsertIndex(closestLane, cursorX, cursorY, layoutDrag.draggedSlotId),
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
        ApplyBackdrop(lane.gapFrame, preview.skin.gapBg, preview.skin.gapBorder)
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
    ConfigureGhostSlotPreview(ghostSlot, slotData, preview, ghost:GetWidth(), ghost:GetHeight(), slotFrame.shortText:IsShown())
    ghost.previewBarInfo = ghostSlot.previewBarInfo
    ghost.castPreview = ghostSlot.castPreview

    -- The ghost carries the dragged bar's name too. Its own slot is at
    -- alpha 0 for the duration, so without this the one bar you are
    -- actually moving is the only one left unnamed. Scale 1: the ghost
    -- hangs off UIParent, not off the scaled preview content.
    ghostSlot.slotData = slotData
    ghostSlot._cdcIdentityVertical = slotFrame._cdcIdentityVertical
    ApplySlotIdentityMarks(preview, ghostSlot, 1, ghost:GetWidth())
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

    layoutDrag.resolveDropTarget = function(cursorX, cursorY)
        return ResolveDropTarget(layoutDrag, cursorX, cursorY)
    end

    layoutDrag.onActivate = function(state)
        if not (state and state.widget and state.slotData) then return end
        layoutDrag.draggedSlotId = state.slotData.id
        preview.draggedSlotExtent = GetSlotExtent(state.slotData, nil)
        ConfigureGhost(preview, state.slotData, state.widget)
        for _, lane in ipairs(layoutDrag.lanes) do
            UpdateLanePreview(preview, lane, state.slotData.id, state.dropTarget)
        end
        preview.root:SetScript("OnUpdate", function()
            TickPreview(preview)
        end)
    end

    layoutDrag.onUpdate = function(state, cursorX, cursorY, dropTarget)
        if not (state and state.slotData) then return end
        layoutDrag.draggedSlotId = state.slotData.id
        preview.draggedSlotExtent = GetSlotExtent(state.slotData, nil)
        for _, lane in ipairs(layoutDrag.lanes) do
            UpdateLanePreview(preview, lane, state.slotData.id, dropTarget)
        end
        if not preview.ghostActive then
            ConfigureGhost(preview, state.slotData, state.widget)
        else
            UpdateGhostPosition(preview.ghost)
        end
        preview.root:SetScript("OnUpdate", function()
            TickPreview(preview)
        end)
    end

    layoutDrag.onCancel = function()
        layoutDrag.draggedSlotId = nil
        preview.draggedSlotExtent = nil
        -- Thaw the reveal once the drag really is over. Deferred because
        -- this runs while CS.dragState is still set (CancelDrag clears it
        -- immediately after), which is what the freeze keys on.
        C_Timer.After(0, function()
            SetIdentityLabelsShown(preview, AnyCustomPreviewSlotHovered(preview))
        end)
        for _, lane in ipairs(layoutDrag.lanes) do
            ResetLanePreview(preview, lane)
        end
        ClearGhost(preview)
        HideDragIndicator()
        preview.root:SetScript("OnUpdate", function()
            TickPreview(preview)
        end)
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

        local adjustedIndex = math_max(1, math_min(#filtered + 1, dropTarget.insertIndex or 1))
        local changed = false
        if preview.independentResources then
            -- Independent Resources is one continuous stack. Normalize every
            -- rendered slot to the chosen lane so the saved runtime layout
            -- matches the order shown after a drop.
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
        else
            local oldPos = slotData.getPos()
            local oldOrder = slotData.getOrder()
            local newOrder = (#filtered == 0 and oldPos == lane.side)
                and oldOrder
                or GetLayoutOrderForInsertion(filtered, lane.reversed, adjustedIndex)
            slotData.setPos(lane.side)
            slotData.setOrder(newOrder)
            changed = oldPos ~= lane.side or oldOrder ~= newOrder
        end

        if changed then
            CooldownCompanion:ApplyResourceBars()
            CooldownCompanion:RepositionCastBar()
            CooldownCompanion:UpdateAnchorStacking()
            CooldownCompanion:RefreshConfigPanel()
        end
    end

    return layoutDrag
end

function ST._BuildLayoutOrderPreviewPanel(container, opts)
    if CS.dragState and CS.dragState.kind == LAYOUT_PREVIEW_DRAG_KIND and CancelDrag then
        CancelDrag()
    end

    local preview = EnsurePreviewState(container)
    preview.host = container
    -- Unified anchor preview: the caller supplies the real button-panel
    -- mirror to use as the primary panel frame. Hidden until the render
    -- path re-shows it, so message-only builds don't leave it floating.
    preview.externalPanelFrame = opts and opts.externalPanel or nil
    if preview.externalPanelFrame then
        preview.externalPanelFrame:Hide()
    end
    preview.rbSettings = CooldownCompanion:GetResourceBarSettings()
    preview.cbSettings = CooldownCompanion:GetCastBarSettings()
    local layout = CooldownCompanion:GetSpecLayoutOrder()
    preview.isVerticalLayout = preview.rbSettings
        and preview.rbSettings.enabled == true
        and not CS.castFramesEntrySelected
        and IsResourceBarVerticalConfig(preview.rbSettings, layout)
        or false

    ResetPreviewState(preview)
    preview.layout = layout
    -- The real spacing between stacked bars, not a fixed 4px. (The gap
    -- between the icon panel and the lanes is a different setting,
    -- GetResourceAnchorGap, and still renders as the fixed chrome gap.)
    preview.slotGap = math_max(0, tonumber(layout and layout.barSpacing)
        or tonumber(preview.rbSettings and preview.rbSettings.barSpacing)
        or LAYOUT_PREVIEW_GAP)
    preview.draggedSlotExtent = nil
    HidePreviewMessage(preview)

    local rbSettings = preview.rbSettings
    local cbSettings = preview.cbSettings
    local resourceBarsEnabled = rbSettings and rbSettings.enabled == true
    local castBarEnabled = cbSettings and cbSettings.enabled == true
    local frameAnchoringSettings = CooldownCompanion.GetFrameAnchoringSettings
        and CooldownCompanion:GetFrameAnchoringSettings()
    local hasUnitFrameProxies = CS.castFramesEntrySelected
        and frameAnchoringSettings
        and frameAnchoringSettings.enabled == true
    if not (resourceBarsEnabled or castBarEnabled or hasUnitFrameProxies) then
        SetPreviewMessage(preview, "Enable Resource Bars or Cast Bar to configure layout.")
        FinalizePreviewState(preview)
        return
    end

    local independentResourcesPreview = CS.resourcesEntrySelected
        and resourceBarsEnabled
        and layout
        and IsTruthyConfigFlag(layout.independentAnchorEnabled)
    preview.independentResources = independentResourcesPreview == true
    local supportsAttachedResourceBars = resourceBarsEnabled
        and not (layout and IsTruthyConfigFlag(layout.independentAnchorEnabled))
    local hasAttachedCastBar = castBarEnabled and not IsTruthyConfigFlag(cbSettings.independentAnchorEnabled)
    local includeResourceSlots = not CS.castFramesEntrySelected
        and (supportsAttachedResourceBars or independentResourcesPreview)
    local includeCastSlots = not independentResourcesPreview
    local hasAttachedBarContext = not independentResourcesPreview
        and (includeResourceSlots or hasAttachedCastBar)
    local hasBarContext = independentResourcesPreview or hasAttachedBarContext
    if not hasBarContext and not hasUnitFrameProxies then
        SetPreviewMessage(preview, "These settings apply only when Resource Bars or Cast Bar are anchored to a panel.")
        FinalizePreviewState(preview)
        return
    end

    if hasBarContext and not layout then
        SetPreviewMessage(preview, "Specialization data loading...")
        FinalizePreviewState(preview)
        return
    end

    local primarySlots = {}
    local castSlots = {}
    local sourcePanel
    local sourceMessage
    if hasBarContext then
        primarySlots, castSlots = CollectPreviewSlots(
            rbSettings,
            includeCastSlots and cbSettings or nil,
            layout,
            preview.isVerticalLayout,
            includeResourceSlots,
            independentResourcesPreview == true
        )
        if not preview.isVerticalLayout then
            for _, castSlot in ipairs(castSlots) do
                table_insert(primarySlots, castSlot)
            end
        end

        if hasAttachedBarContext and (#primarySlots > 0 or #castSlots > 0) then
            sourcePanel, sourceMessage = ResolveLayoutPreviewSourcePanel()
            if not sourcePanel and not hasUnitFrameProxies then
                SetPreviewMessage(preview, sourceMessage)
                FinalizePreviewState(preview)
                return
            end
            if not sourcePanel then
                wipe(primarySlots)
                wipe(castSlots)
            end
        end
    end

    if #primarySlots == 0 and #castSlots == 0 and not hasUnitFrameProxies then
        if independentResourcesPreview then
            SetPreviewMessage(preview, "No active resources to order. Enable a resource or Custom Bar first.")
        else
            SetPreviewMessage(preview, "No active bars to order. Enable resources, Custom Bars, or cast bar first.")
        end
        FinalizePreviewState(preview)
        return
    end

    local layoutDrag
    if #primarySlots > 0 or #castSlots > 0 then
        layoutDrag = CreateLayoutDragModel(preview)
        preview.layoutDrag = layoutDrag
    end

    local root = preview.root
    local content = AcquireContainer(preview, root)
    content:SetClipsChildren(false)

    local contentWidth = 0
    local contentHeight = 0
    if independentResourcesPreview and layoutDrag then
        local resourceThickness = math_max(8, tonumber(GetResourceGlobalThickness(rbSettings)) or 12)
        local independentLength = math_max(
            20,
            tonumber(layout.independentWidth or rbSettings.independentWidth) or 200
        )
        if preview.isVerticalLayout then
            contentWidth, contentHeight = RenderIndependentVerticalLayout(
                preview,
                content,
                layoutDrag,
                primarySlots,
                independentLength,
                resourceThickness
            )
        else
            contentWidth, contentHeight = RenderIndependentHorizontalLayout(
                preview,
                content,
                layoutDrag,
                primarySlots,
                independentLength,
                resourceThickness
            )
        end
    elseif sourcePanel and layoutDrag then
        local resourceThickness = (rbSettings and tonumber(GetResourceGlobalThickness(rbSettings)))
            or math_floor(sourcePanel.iconHeight * 0.56)
        -- Fallback thickness only: every slot now carries its own (the cast
        -- bar its configured height, resources and custom bars their
        -- per-slot override). This used to be one max across both, which
        -- clamped every bar up to whichever was tallest.
        local horizontalBarHeight = math_max(8, math_floor(resourceThickness))
        local verticalBarWidth = math_max(8, math_floor(resourceThickness))

        if preview.isVerticalLayout then
            contentWidth, contentHeight = RenderVerticalLayout(
                preview,
                content,
                layoutDrag,
                sourcePanel,
                primarySlots,
                castSlots,
                horizontalBarHeight,
                verticalBarWidth
            )
        else
            contentWidth, contentHeight = RenderHorizontalLayout(
                preview,
                content,
                layoutDrag,
                sourcePanel,
                primarySlots,
                horizontalBarHeight
            )
        end
    end

    contentWidth, contentHeight = AppendUnitFrameProxies(preview, content, contentWidth, contentHeight)

    content:SetSize(contentWidth, contentHeight)

    local hostWidth = container:GetWidth() or 0
    local hostHeight = (container:GetHeight() or 0) - GetHostBottomReserve(container)
    if hostWidth < 40 then hostWidth = 340 end
    if hostHeight < 40 then hostHeight = 520 end
    local maxWidth = math_max(120, hostWidth - (LAYOUT_PREVIEW_PADDING * 2))
    local maxHeight = math_max(120, hostHeight - (LAYOUT_PREVIEW_PADDING * 2))
    local scale = math_min(1, maxWidth / math_max(1, contentWidth), maxHeight / math_max(1, contentHeight))

    -- Center the whole visual block in the pane so dead space stays
    -- symmetric regardless of how bars split across their configured sides.
    content:SetScale(scale)
    content:ClearAllPoints()
    content:SetPoint("CENTER", root, "CENTER", 0, 0)

    -- Identity marks last: they counter-scale against the fit above, so
    -- they can only be laid out once it is known. A rebuild can happen with
    -- the cursor already resting on a bar (a value change repaints the
    -- preview under it), so the reveal state is re-derived rather than
    -- assumed off.
    preview.identityLabelsShown = AnyCustomPreviewSlotHovered(preview)
    for index = 1, (preview.used.slots or 0) do
        ApplySlotIdentityMarks(preview, preview.pools.slots[index], scale)
    end

    FinalizePreviewState(preview)
    StartPreviewAnimationDriver(preview)
end

function ST._GetLayoutPreviewRenderedSelectionKeys(host)
    local preview = host and host._cdcLayoutPreview
    return preview and preview.renderedSelectionKeys or {}
end

-- True when the Layout & Order lanes would actually render bars around an
-- anchored panel: something enabled and attached, spec layout loaded, and
-- at least one active slot. The unified anchor preview gates on this so it
-- never trades the real mirror for a message-only pane.
function ST._HasAttachedBarLanesToRender()
    local rbSettings = CooldownCompanion:GetResourceBarSettings()
    local cbSettings = CooldownCompanion:GetCastBarSettings()
    local layout = CooldownCompanion:GetSpecLayoutOrder()
    if not layout then
        return false
    end
    local resourceBarsEnabled = rbSettings and rbSettings.enabled == true
    local castBarEnabled = cbSettings and cbSettings.enabled == true
    local supportsAttachedResourceBars = resourceBarsEnabled
        and not IsTruthyConfigFlag(layout.independentAnchorEnabled)
    local hasAttachedCastBar = castBarEnabled
        and not IsTruthyConfigFlag(cbSettings.independentAnchorEnabled)
    if not supportsAttachedResourceBars and not hasAttachedCastBar then
        return false
    end
    local isVertical = resourceBarsEnabled
        and IsResourceBarVerticalConfig(rbSettings, layout)
        or false
    local primarySlots, castSlots = CollectPreviewSlots(
        rbSettings,
        cbSettings,
        layout,
        isVertical,
        supportsAttachedResourceBars
    )
    return #primarySlots > 0 or #castSlots > 0
end

-- Does the Resources / Cast Bar canvas actually draw a cast lane right now?
-- The command center asks before offering the cast preview, because "the
-- cast bar is attached" is not the same question: an INDEPENDENT resource
-- stack drops the cast slot from this home entirely (includeCastSlots
-- below), and offering a preview whose destination is not on screen means
-- pressing play visibly does nothing.
--
-- Answered by re-deriving the build's own preconditions rather than by
-- reporting what the last build drew: the command center runs BEFORE the
-- renderer on every rebuild (it owns the host's bottom reserve, which the
-- renderer then measures), so a recorded answer would always be one change
-- stale. The source-panel resolve is the same one _BuildLayoutOrderPreview-
-- Panel makes and _HasAttachedBarLanesToRender already pays for; config
-- time, once per rebuild.
--
-- Deliberately an OFFER test only. It must not feed the stranded-preview
-- stop: `layout` is briefly nil across a spec change, and stopping on that
-- would kill a running preview for a transient live condition.
function ST._ResourcesPreviewRendersCastSlot()
    local cbSettings = CooldownCompanion:GetCastBarSettings()
    if not (cbSettings and cbSettings.enabled == true) then
        return false
    end
    if IsTruthyConfigFlag(cbSettings.independentAnchorEnabled) then
        return false
    end
    local layout = CooldownCompanion:GetSpecLayoutOrder()
    if not layout then
        -- "Specialization data loading..." - the canvas is a message.
        return false
    end
    local rbSettings = CooldownCompanion:GetResourceBarSettings()
    local independentResourcesPreview = CS.resourcesEntrySelected
        and rbSettings and rbSettings.enabled == true
        and IsTruthyConfigFlag(layout.independentAnchorEnabled)
    if independentResourcesPreview then
        return false
    end
    -- An attached cast lane is drawn around the mirrored icon panel, so no
    -- resolvable panel means no lane: either the canvas is a message, or the
    -- unit-frame-proxy path wiped the slots and rendered proxies alone.
    return ResolveLayoutPreviewSourcePanel() ~= nil
end

-- Shared with ButtonPanelPreview.lua: config-safe icon resolution and the
-- mirrored icon styling both previews use. StyleMirroredIconFrame expects an
-- icon frame carrying bg, icon, countText, and borderTextures[4]; pass
-- button as { buttonData = ... } to style purely from saved settings.
ST._GetLayoutPreviewIcon = GetLayoutPreviewIcon
ST._StyleMirroredIconFrame = StyleMirroredIconFrame
