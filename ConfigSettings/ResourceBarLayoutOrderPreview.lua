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

local POWER_NAMES = RB.POWER_NAMES
local SEGMENTED_TYPES = RB.SEGMENTED_TYPES
local MAX_CUSTOM_AURA_BARS = RB.MAX_CUSTOM_AURA_BARS or ST.MAX_CUSTOM_AURA_BARS or 5
local CUSTOM_AURA_BAR_BASE = RB.CUSTOM_AURA_BAR_BASE
local RESOURCE_MAELSTROM_WEAPON = RB.RESOURCE_MAELSTROM_WEAPON
local DEFAULT_RESOURCE_TEXT_FONT = RB.DEFAULT_RESOURCE_TEXT_FONT
local DEFAULT_RESOURCE_TEXT_SIZE = RB.DEFAULT_RESOURCE_TEXT_SIZE
local DEFAULT_RESOURCE_TEXT_OUTLINE = RB.DEFAULT_RESOURCE_TEXT_OUTLINE
local DEFAULT_RESOURCE_TEXT_COLOR = RB.DEFAULT_RESOURCE_TEXT_COLOR

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
local StyleSegmentedBar = RB.StyleSegmentedBar
local PrepareCustomAuraBar = RB.PrepareCustomAuraBar
local ApplyPreviewBarState = RB.ApplyPreviewBarState
local GetMWMaxStacks = RB.GetMWMaxStacks
local CreatePixelBorders = RB.CreatePixelBorders
local ApplyPixelBorders = RB.ApplyPixelBorders
local HidePixelBorders = RB.HidePixelBorders

local LAYOUT_PREVIEW_PADDING = 12
local LAYOUT_PREVIEW_SECTION_GAP = 18
local LAYOUT_PREVIEW_PANEL_PAD = 4
local LAYOUT_PREVIEW_GAP = 4
local LAYOUT_PREVIEW_DRAG_KIND = "layout-slot"
local LAYOUT_PREVIEW_ICON_FALLBACK = "Interface\\Icons\\INV_Misc_QuestionMark"
local LAYOUT_PREVIEW_ANIM_DURATION = 0.08
local LAYOUT_PREVIEW_EMPTY_DROP_SIZE = 8
local LAYOUT_PREVIEW_MAX_REAL_ICONS = 4
local LAYOUT_PREVIEW_INFO_STRIP_HEIGHT = 28
local LAYOUT_PREVIEW_INFO_STRIP_OFFSET = 10

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
        CS.configFrame and CS.configFrame.col4 and CS.configFrame.col4.frame,
        CS.configFrame and CS.configFrame.col4 and CS.configFrame.col4.content,
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

local function EnsurePreviewState(host)
    local preview = host._cdcLayoutPreview
    if preview then
        preview.buildId = (preview.buildId or 0) + 1
        preview.skin = ResolvePreviewSkin(host)
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
        },
        used = {},
        tweens = {},
        skin = ResolvePreviewSkin(host),
    }
    host._cdcLayoutPreview = preview

    local root = CreateFrame("Frame", nil, host)
    root:SetAllPoints(host)
    root:SetClipsChildren(false)
    root:Hide()
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
    preview.layoutDrag = nil
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
    size = math_max(1, math_floor(size or 1))
    color = color or { 0, 0, 0, 1 }

    local top = frame.borderTextures[1]
    local bottom = frame.borderTextures[2]
    local left = frame.borderTextures[3]
    local right = frame.borderTextures[4]

    top:ClearAllPoints()
    top:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    top:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    top:SetHeight(size)

    bottom:ClearAllPoints()
    bottom:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
    bottom:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    bottom:SetHeight(size)

    left:ClearAllPoints()
    left:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    left:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
    left:SetWidth(size)

    right:ClearAllPoints()
    right:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    right:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    right:SetWidth(size)

    for i = 1, 4 do
        frame.borderTextures[i]:SetColorTexture(color[1] or 0, color[2] or 0, color[3] or 0, color[4] ~= nil and color[4] or 1)
        frame.borderTextures[i]:Show()
    end
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
    local bgColor = CloneColor(style.backgroundColor, { 0, 0, 0, 0.5 })
    local borderColor = CloneColor(style.borderColor, { 0, 0, 0, 1 })
    local showBorder = borderSize > 0 and ((borderColor[4] ~= nil and borderColor[4] > 0) or borderColor[4] == nil)

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
    iconFrame.icon:SetPoint("TOPLEFT", iconFrame, "TOPLEFT", borderSize, -borderSize)
    iconFrame.icon:SetPoint("BOTTOMRIGHT", iconFrame, "BOTTOMRIGHT", -borderSize, borderSize)
    iconFrame.icon:SetTexture((button and button.icon and button.icon:GetTexture()) or GetLayoutPreviewIcon(button and button.buttonData))
    iconFrame.icon:Show()
    iconFrame.countText:Hide()

    if button and button.icon and button.icon.GetTexCoord then
        iconFrame.icon:SetTexCoord(button.icon:GetTexCoord())
    else
        ApplyIconTexCoord(iconFrame.icon, iconFrame:GetWidth(), iconFrame:GetHeight())
    end

    if showBorder then
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
    frame:RegisterForClicks("LeftButtonDown")

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

local function ConfigureInfoStrip(preview, root, sourcePanel)
    local title = AcquireLabel(preview, root, "GameFontHighlight")
    title:ClearAllPoints()
    title:SetPoint("TOPLEFT", root, "TOPLEFT", LAYOUT_PREVIEW_PADDING, -LAYOUT_PREVIEW_INFO_STRIP_OFFSET)
    title:SetPoint("TOPRIGHT", root, "TOPRIGHT", -LAYOUT_PREVIEW_PADDING, -LAYOUT_PREVIEW_INFO_STRIP_OFFSET)
    title:SetHeight(LAYOUT_PREVIEW_INFO_STRIP_HEIGHT)
    title.text:SetJustifyH("CENTER")
    do
        local font, size, flags = GameFontHighlight:GetFont()
        if font and size then
            title.text:SetFont(font, size + 2, flags)
        end
    end
    title.text:SetText("|cffd7b24aMirroring:|r " .. (sourcePanel.panelName or ("Panel " .. tostring(sourcePanel.groupId or ""))))
    return title
end

GetLayoutPreviewIcon = function(buttonData)
    if not buttonData then
        return LAYOUT_PREVIEW_ICON_FALLBACK
    end

    local icon
    if buttonData.type == "spell" then
        icon = C_Spell.GetSpellTexture(buttonData.id)
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
    local buttons = {}
    local fallbackButtons = {}

    for _, buttonData in ipairs(group.buttons or {}) do
        if buttonData and buttonData.enabled ~= false then
            fallbackButtons[#fallbackButtons + 1] = { buttonData = buttonData }
            if not CooldownCompanion.IsButtonUsable or CooldownCompanion:IsButtonUsable(buttonData) then
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
    if not group or group.displayMode ~= "icons" then
        return nil, "The current attached anchor panel is not an icon-mode panel, so there is no icon row to mirror."
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
    if sampleButton and sampleButton.GetWidth and sampleButton.GetHeight then
        iconWidth = sampleButton:GetWidth() or iconWidth
        iconHeight = sampleButton:GetHeight() or iconHeight
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
    if group.displayMode ~= "icons" then return false end

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

    local folders = db.folders or {}
    local specId = CooldownCompanion._currentSpecId
    local folderContainers = {}
    local looseContainers = {}

    for containerId, container in pairs(containers) do
        local folderId = container.folderId
        local order = CooldownCompanion:GetOrderForSpec(container, specId, containerId)
        if folderId and folders[folderId] then
            folderContainers[folderId] = folderContainers[folderId] or {}
            folderContainers[folderId][#folderContainers[folderId] + 1] = { id = containerId, order = order }
        else
            looseContainers[#looseContainers + 1] = { id = containerId, order = order }
        end
    end

    for _, children in pairs(folderContainers) do
        table_sort(children, function(a, b)
            return a.order < b.order
        end)
    end
    table_sort(looseContainers, function(a, b)
        return a.order < b.order
    end)

    local topItems = {}
    for folderId in pairs(folderContainers) do
        topItems[#topItems + 1] = {
            kind = "folder",
            id = folderId,
            order = CooldownCompanion:GetOrderForSpec(folders[folderId], specId, folderId),
        }
    end
    for _, info in ipairs(looseContainers) do
        topItems[#topItems + 1] = { kind = "container", id = info.id, order = info.order }
    end
    table_sort(topItems, function(a, b)
        return a.order < b.order
    end)

    for _, item in ipairs(topItems) do
        local containerList = item.kind == "folder" and folderContainers[item.id] or { item }
        for _, containerInfo in ipairs(containerList) do
            local panels = CooldownCompanion:GetPanels(containerInfo.id)
            for _, panelInfo in ipairs(panels) do
                if IsGroupConfigAvailableForPreview(panelInfo.groupId, false) then
                    return panelInfo.groupId
                end
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

local function CollectPreviewSlots(rbSettings, cbSettings, layout, isVerticalLayout)
    local activeResources = GetConfigActiveResources()
    local customBars = CooldownCompanion:GetSpecCustomAuraBars()
    local primarySlots = {}
    local castSlots = {}
    local resourceBarsEnabled = rbSettings and rbSettings.enabled

    layout.resources = layout.resources or {}
    layout.customAuraBarSlots = layout.customAuraBarSlots or {}
    rbSettings = rbSettings or {}
    rbSettings.resources = rbSettings.resources or {}

    local function GetSlotColor(powerType)
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
        rbSettings.resources[powerType] = rbSettings.resources[powerType] or {}
        local resourceConfig = rbSettings.resources[powerType]
        local showResource = resourceBarsEnabled and resourceConfig.enabled ~= false
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
                shortLabel = GetShortLabel(POWER_NAMES[powerType] or ("Power " .. powerType)),
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
        for slotIndex = 1, MAX_CUSTOM_AURA_BARS do
            local customAura = customBars and customBars[slotIndex]
            if customAura and customAura.enabled and customAura.spellID and not IsTruthyConfigFlag(customAura.independentAnchorEnabled) then
                local spellInfo = C_Spell.GetSpellInfo(customAura.spellID)
                local label = spellInfo and spellInfo.name or ("Custom Aura " .. slotIndex)
                local slotName = "Custom Aura " .. slotIndex .. ": " .. label
                local function EnsureLayoutSlot()
                    layout.customAuraBarSlots[slotIndex] = layout.customAuraBarSlots[slotIndex] or {
                        position = "below",
                        order = 1000 + slotIndex,
                    }
                    return layout.customAuraBarSlots[slotIndex]
                end

                table_insert(primarySlots, {
                    id = "custom:" .. tostring(slotIndex),
                    slotCategory = "primary",
                    kind = "custom",
                    customAuraIndex = slotIndex,
                    powerType = CUSTOM_AURA_BAR_BASE + slotIndex - 1,
                    label = slotName,
                    shortLabel = GetShortLabel(label),
                    color = CloneColor(customAura.barColor, { 0.52, 0.64, 1.0, 1 }),
                    icon = C_Spell.GetSpellTexture(customAura.spellID) or LAYOUT_PREVIEW_ICON_FALLBACK,
                    getPos = function()
                        local slot = layout.customAuraBarSlots[slotIndex]
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
                        local slot = layout.customAuraBarSlots[slotIndex]
                        if isVerticalLayout then
                            return (slot and slot.verticalOrder) or (slot and slot.order) or (1000 + slotIndex)
                        end
                        return (slot and slot.order) or (1000 + slotIndex)
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

    if not activeTween and not preview.ghostActive then
        preview.root:SetScript("OnUpdate", nil)
    end
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

local function EnsureResourcePreview(frame, slot, preview, width, height)
    HideUnusedSlotVisuals(frame)

    local barInfo = frame.previewBarInfo
    local rbSettings = preview.rbSettings
    local segmentGap = rbSettings.segmentGap or 4

    if slot.kind == "custom" then
        local customBars = CooldownCompanion:GetSpecCustomAuraBars()
        barInfo = PrepareCustomAuraBar(
            frame.previewCanvas,
            barInfo,
            slot.powerType,
            customBars,
            rbSettings,
            preview.isVerticalLayout,
            IsVerticalFillReversed(rbSettings),
            width,
            height,
            segmentGap
        )
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

local function ConfigureCastPreview(frame, slot, preview, width, height)
    HideUnusedSlotVisuals(frame)

    local settings = preview.cbSettings
    local castPreview = EnsureCastPreview(frame)
    local root = castPreview.root
    local bar = castPreview.bar
    local iconFrame = castPreview.iconFrame
    local icon = castPreview.icon
    local border = castPreview.border
    local liveCastBar = PlayerCastingBarFrame

    root:SetParent(frame.previewCanvas)
    root:ClearAllPoints()
    root:SetPoint("TOPLEFT", frame.previewCanvas, "TOPLEFT", 0, 0)
    root:SetPoint("BOTTOMRIGHT", frame.previewCanvas, "BOTTOMRIGHT", 0, 0)
    root:Show()

    local iconShown = settings.showIcon ~= false
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
        local liveIcon = liveCastBar and liveCastBar.Icon and liveCastBar.Icon:GetTexture()
        icon:SetTexture(liveIcon or slot.icon or LAYOUT_PREVIEW_ICON_FALLBACK)
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
    bar:SetMinMaxValues(0, 100)
    bar:SetValue(65)
    bar:SetStatusBarTexture(CooldownCompanion:FetchStatusBar(settings.barTexture or "Solid"))
    local liveR, liveG, liveB, liveA = liveCastBar and liveCastBar.GetStatusBarColor and liveCastBar:GetStatusBarColor()
    local barColor = settings.barColor or { 1, 0.72, 0.18, 1 }
    if liveR ~= nil then
        bar:SetStatusBarColor(liveR, liveG or 1, liveB or 1, liveA ~= nil and liveA or 1)
    else
        bar:SetStatusBarColor(barColor[1], barColor[2], barColor[3], barColor[4] ~= nil and barColor[4] or 1)
    end
    local backgroundColor = settings.backgroundColor or { 0, 0, 0, 0.5 }
    bar.bg:SetColorTexture(backgroundColor[1], backgroundColor[2], backgroundColor[3], backgroundColor[4] ~= nil and backgroundColor[4] or 1)

    border:Hide()
    HideCastPixelBorders(castPreview)

    local borderStyle = settings.borderStyle or "pixel"
    if borderStyle == "pixel" then
        ApplyPixelBorders(castPreview.pixelBorders, bar, settings.borderColor or { 0, 0, 0, 1 }, settings.borderSize or 1)
        if iconFrame:IsShown() and settings.iconOffset then
            ApplyPixelBorders(castPreview.iconBorders, iconFrame, settings.borderColor or { 0, 0, 0, 1 }, settings.iconBorderSize or 1)
        else
            HidePixelBorders(castPreview.iconBorders)
        end
    elseif borderStyle == "blizzard" then
        border:SetAllPoints(bar)
        border:SetAtlas("ui-castingbar-frame")
        border:Show()
    end

    if settings.showNameText == false then
        bar.nameText:Hide()
    else
        local font = CooldownCompanion:FetchFont(settings.nameFont or DEFAULT_RESOURCE_TEXT_FONT)
        bar.nameText:SetFont(font, settings.nameFontSize or DEFAULT_RESOURCE_TEXT_SIZE, settings.nameFontOutline or DEFAULT_RESOURCE_TEXT_OUTLINE)
        bar.nameText:ClearAllPoints()
        bar.nameText:SetPoint("LEFT", bar, "LEFT", 4, 0)
        bar.nameText:SetPoint("RIGHT", bar, "RIGHT", -4, 0)
        local liveText = liveCastBar and liveCastBar.Text and liveCastBar.Text:GetText()
        bar.nameText:SetText((liveText and liveText ~= "") and liveText or "Preview Cast")
        bar.nameText:Show()
    end

    if settings.showCastTimeText == false then
        bar.timeText:Hide()
    else
        local font = CooldownCompanion:FetchFont(settings.castTimeFont or DEFAULT_RESOURCE_TEXT_FONT)
        bar.timeText:SetFont(font, settings.castTimeFontSize or DEFAULT_RESOURCE_TEXT_SIZE, settings.castTimeFontOutline or DEFAULT_RESOURCE_TEXT_OUTLINE)
        bar.timeText:ClearAllPoints()
        bar.timeText:SetPoint("RIGHT", bar, "RIGHT", -4 + (settings.castTimeXOffset or 0), settings.castTimeYOffset or 0)
        local liveTime = liveCastBar and liveCastBar.CastTimeText and liveCastBar.CastTimeText:GetText()
        bar.timeText:SetText((liveTime and liveTime ~= "") and liveTime or "1.5 s")
        bar.timeText:Show()
    end

    if settings.showSpark == false then
        bar.spark:Hide()
    else
        bar.spark:SetWidth(8)
        bar.spark:SetHeight(math_max(8, height * 1.66))
        bar.spark:ClearAllPoints()
        bar.spark:SetPoint("CENTER", bar, "LEFT", (bar:GetWidth() or width) * 0.65, 0)
        bar.spark:Show()
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
        local buttonWidth = (button and button:GetWidth()) or panelData.iconWidth
        local buttonHeight = (button and button:GetHeight()) or panelData.iconHeight
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

local function BuildLaneSlotGeometry(lane, index)
    local laneWidth = lane.frame:GetWidth() or lane.slotWidth or 1
    local laneHeight = lane.frame:GetHeight() or lane.slotHeight or 1
    if lane.axis == "x" then
        local x = (index - 1) * (lane.slotWidth + LAYOUT_PREVIEW_GAP)
        local y = -math_floor(math_max(0, laneHeight - lane.slotHeight) / 2)
        return x, y, lane.slotWidth, lane.slotHeight
    end
    local x = math_floor(math_max(0, laneWidth - lane.slotWidth) / 2)
    local y = -((index - 1) * (lane.slotHeight + LAYOUT_PREVIEW_GAP))
    return x, y, lane.slotWidth, lane.slotHeight
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

    local slotRects = {}
    for index = 1, #filtered do
        local x, y, w, h = BuildLaneSlotGeometry(lane, index)
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
        baseExtent = axis == "x" and width or height,
        acceptedCategory = acceptedCategory,
        visualSlots = {},
        slotFramesById = {},
    }

    for index, slotModel in ipairs(slotModels) do
        local slotFrame = AcquireSlot(preview, laneFrame)
        ConfigureSlotPreview(slotFrame, slotModel, preview, slotWidth, slotHeight, axis == "x")
        slotFrame.slotData = slotModel
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
        slotFrame:SetScript("OnEnter", function(self)
            if self.hoverHighlight then
                self.hoverHighlight:Show()
            end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(slotModel.label or "Bar", 1, 1, 1)
            GameTooltip:AddLine("Drag to reorder this attached bar.", 0.75, 0.82, 0.92, true)
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

local function GetLaneExtent(count, slotSize)
    if count <= 0 then
        return math_max(LAYOUT_PREVIEW_EMPTY_DROP_SIZE, slotSize or LAYOUT_PREVIEW_EMPTY_DROP_SIZE)
    end
    return (count * slotSize) + (math_max(0, count - 1) * LAYOUT_PREVIEW_GAP)
end

local function RenderHorizontalLayout(preview, content, layoutDrag, sourcePanel, slots, slotHeight)
    local panelFrame = RenderMirroredPanel(preview, content, sourcePanel)
    local panelWidth = panelFrame:GetWidth()
    local panelHeight = panelFrame:GetHeight()
    local aboveSlots = SortSlotsForSide(slots, "above", true)
    local belowSlots = SortSlotsForSide(slots, "below", false)
    local slotFrameHeight = math_max(8, slotHeight)
    local aboveHeight = GetLaneExtent(#aboveSlots, slotFrameHeight)
    local belowHeight = GetLaneExtent(#belowSlots, slotFrameHeight)
    local slotWidth = sourcePanel.width

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

local function RenderVerticalLayout(preview, content, layoutDrag, sourcePanel, primarySlots, castSlots, horizontalBarHeight, verticalBarWidth)
    local panelFrame = RenderMirroredPanel(preview, content, sourcePanel)
    local panelWidth = panelFrame:GetWidth()
    local panelHeight = panelFrame:GetHeight()
    local leftSlots = SortSlotsForSide(primarySlots, "left", true)
    local rightSlots = SortSlotsForSide(primarySlots, "right", false)
    local leftWidth = GetLaneExtent(#leftSlots, verticalBarWidth)
    local rightWidth = GetLaneExtent(#rightSlots, verticalBarWidth)
    local verticalBarHeight = sourcePanel.height

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
        local castAboveHeight = GetLaneExtent(#castAbove, castSlotFrameHeight)
        local castBelowHeight = GetLaneExtent(#castBelow, castSlotFrameHeight)

        local castAboveLane = BuildLane(preview, content, layoutDrag, nil, panelWidth, castAboveHeight, "y", "above", true, castAbove, sourcePanel.width, castSlotFrameHeight, "cast")
        castAboveLane.frame:SetPoint("TOPLEFT", content, "TOPLEFT", leftWidth + LAYOUT_PREVIEW_GAP, -(panelHeight + LAYOUT_PREVIEW_SECTION_GAP))

        castAboveLane.setPreviewOverflow = function(extra)
            castAboveLane.frame:ClearAllPoints()
            castAboveLane.frame:SetPoint("TOPLEFT", content, "TOPLEFT", leftWidth + LAYOUT_PREVIEW_GAP, -(panelHeight + LAYOUT_PREVIEW_SECTION_GAP) + extra)
            castAboveLane.frame:SetSize(castAboveLane.baseWidth or panelWidth, (castAboveLane.baseHeight or castAboveHeight) + extra)
        end
        castAboveLane.setPreviewOverflow(0)

        castPanel:ClearAllPoints()
        castPanel:SetPoint("TOPLEFT", castAboveLane.frame, "BOTTOMLEFT", 0, -LAYOUT_PREVIEW_GAP)

        local castBelowLane = BuildLane(preview, content, layoutDrag, nil, panelWidth, castBelowHeight, "y", "below", false, castBelow, sourcePanel.width, castSlotFrameHeight, "cast")
        castBelowLane.frame:SetPoint("TOPLEFT", castPanel, "BOTTOMLEFT", 0, -LAYOUT_PREVIEW_GAP)

        totalHeight = panelHeight + LAYOUT_PREVIEW_SECTION_GAP + castAboveHeight + castPanel:GetHeight() + castBelowHeight + (LAYOUT_PREVIEW_GAP * 2)
        totalWidth = math_max(totalWidth, leftWidth + LAYOUT_PREVIEW_GAP + panelWidth)
    end

    local iconCenterOffsetY = panelHeight / 2
    return totalWidth, totalHeight, iconCenterOffsetY
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
    local renderIndex = 1
    local visibleFrames = {}

    for _, slot in ipairs(lane.slotModels or {}) do
        local slotFrame = lane.slotFramesById[slot.id]
        if slotFrame then
            if slot.id == draggedSlotId then
                slotFrame:SetAlpha(0)
            else
                local displayIndex = renderIndex
                if gapIndex and displayIndex >= gapIndex then
                    displayIndex = displayIndex + 1
                end
                local x, y, w, h = BuildLaneSlotGeometry(lane, displayIndex)
                QueueSlotTween(preview, slotFrame, lane.frame, x, y, w, h, 1, LAYOUT_PREVIEW_ANIM_DURATION)
                slotFrame:SetShown(true)
                slotFrame:SetAlpha(1)
                table_insert(visibleFrames, slotFrame)
                renderIndex = renderIndex + 1
            end
        end
    end

    lane.visualSlots = visibleFrames
    local slotSize = (lane.axis == "x") and lane.slotWidth or lane.slotHeight
    local visualCount = #visibleFrames + (gapIndex and 1 or 0)
    local requiredExtent = GetLaneExtent(visualCount, slotSize)
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
    ConfigureSlotPreview(ghostSlot, slotData, preview, ghost:GetWidth(), ghost:GetHeight(), slotFrame.shortText:IsShown())
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

    layoutDrag.resolveDropTarget = function(cursorX, cursorY)
        return ResolveDropTarget(layoutDrag, cursorX, cursorY)
    end

    layoutDrag.onActivate = function(state)
        if not (state and state.widget and state.slotData) then return end
        layoutDrag.draggedSlotId = state.slotData.id
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
        local newOrder = GetLayoutOrderForInsertion(filtered, lane.reversed, adjustedIndex)
        local oldPos = slotData.getPos()
        local oldOrder = slotData.getOrder()

        slotData.setPos(lane.side)
        slotData.setOrder(newOrder)

        if oldPos ~= lane.side or oldOrder ~= newOrder then
            CooldownCompanion:UpdateAnchorStacking()
            CooldownCompanion:RefreshConfigPanel()
        end
    end

    return layoutDrag
end

function ST._BuildLayoutOrderPreviewPanel(container)
    if CS.dragState and CS.dragState.kind == LAYOUT_PREVIEW_DRAG_KIND and CancelDrag then
        CancelDrag()
    end

    local preview = EnsurePreviewState(container)
    preview.host = container
    preview.rbSettings = CooldownCompanion:GetResourceBarSettings()
    preview.cbSettings = CooldownCompanion:GetCastBarSettings()
    preview.isVerticalLayout = preview.rbSettings and IsResourceBarVerticalConfig(preview.rbSettings) or false

    ResetPreviewState(preview)
    HidePreviewMessage(preview)

    local rbSettings = preview.rbSettings
    local cbSettings = preview.cbSettings
    local supportsAttachedResourceBars = rbSettings and not IsTruthyConfigFlag(rbSettings.independentAnchorEnabled)
    local hasAttachedCastBar = cbSettings and cbSettings.enabled and not IsTruthyConfigFlag(cbSettings.independentAnchorEnabled)
    if not supportsAttachedResourceBars and not hasAttachedCastBar then
        SetPreviewMessage(preview, "These settings apply only when Resource Bars or Cast Bar are anchored to a panel.")
        FinalizePreviewState(preview)
        return
    end

    local layout = CooldownCompanion:GetSpecLayoutOrder()
    if not layout then
        SetPreviewMessage(preview, "Specialization data loading...")
        FinalizePreviewState(preview)
        return
    end

    local sourcePanel, sourceMessage = ResolveLayoutPreviewSourcePanel()
    if not sourcePanel then
        SetPreviewMessage(preview, sourceMessage)
        FinalizePreviewState(preview)
        return
    end

    local primarySlots, castSlots = CollectPreviewSlots(rbSettings, cbSettings, layout, preview.isVerticalLayout)
    if not preview.isVerticalLayout then
        for _, castSlot in ipairs(castSlots) do
            table_insert(primarySlots, castSlot)
        end
    end

    if #primarySlots == 0 and #castSlots == 0 then
        SetPreviewMessage(preview, "No active bars to order. Enable resources, custom aura bars, or cast bar first.")
        FinalizePreviewState(preview)
        return
    end

    local layoutDrag = CreateLayoutDragModel(preview)
    preview.layoutDrag = layoutDrag

    local root = preview.root
    local infoStrip = ConfigureInfoStrip(preview, root, sourcePanel)
    local content = AcquireContainer(preview, root)
    content:SetClipsChildren(false)

    local resourceThickness = (rbSettings and tonumber(GetResourceGlobalThickness(rbSettings))) or math_floor(sourcePanel.iconHeight * 0.56)
    local castBarHeight = cbSettings and (cbSettings.stylingEnabled and (cbSettings.height or 15) or 11) or resourceThickness
    local horizontalBarHeight = math_max(8, math_floor(math_max(resourceThickness, castBarHeight)))
    local verticalBarWidth = math_max(8, math_floor(resourceThickness))

    local contentWidth
    local contentHeight
    local iconCenterOffsetY
    if preview.isVerticalLayout then
        contentWidth, contentHeight, iconCenterOffsetY = RenderVerticalLayout(preview, content, layoutDrag, sourcePanel, primarySlots, castSlots, horizontalBarHeight, verticalBarWidth)
    else
        contentWidth, contentHeight, iconCenterOffsetY = RenderHorizontalLayout(preview, content, layoutDrag, sourcePanel, primarySlots, horizontalBarHeight)
    end

    content:SetSize(contentWidth, contentHeight)

    local hostWidth = container:GetWidth() or 0
    local hostHeight = container:GetHeight() or 0
    if hostWidth < 40 then hostWidth = 340 end
    if hostHeight < 40 then hostHeight = 520 end
    local maxWidth = math_max(120, hostWidth - (LAYOUT_PREVIEW_PADDING * 2))
    local stripReserve = (infoStrip and (LAYOUT_PREVIEW_INFO_STRIP_HEIGHT + LAYOUT_PREVIEW_INFO_STRIP_OFFSET + 6)) or 0
    local maxHeight = math_max(120, hostHeight - (LAYOUT_PREVIEW_PADDING * 2) - stripReserve)
    local scale = math_min(1, maxWidth / math_max(1, contentWidth), maxHeight / math_max(1, contentHeight))

    content:SetScale(scale)
    content:ClearAllPoints()
    local centerYOffset = ((iconCenterOffsetY or (contentHeight / 2)) - (contentHeight / 2)) * scale
    content:SetPoint("CENTER", root, "CENTER", 0, centerYOffset)

    FinalizePreviewState(preview)
end
