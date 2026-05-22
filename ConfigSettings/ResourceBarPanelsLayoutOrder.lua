--[[
    CooldownCompanion - ResourceBarPanelsLayoutOrder
    Column 4 layout order controls for resource bars, Custom Bars, and cast bars.
    The dedicated visual preview renderer lives in ResourceBarLayoutOrderPreview.lua.
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon
local AceGUI = LibStub("AceGUI-3.0")
local CS = ST._configState

local RB = ST._RB
local RBP = ST._RBP
local POWER_NAMES = RB.POWER_NAMES
local DEFAULT_POWER_COLORS = RB.DEFAULT_POWER_COLORS
local DEFAULT_MW_BASE_COLOR = RB.DEFAULT_MW_BASE_COLOR
local DEFAULT_HEALTH_BAR_COLOR = RB.DEFAULT_HEALTH_BAR_COLOR
local DEFAULT_COMBO_COLOR = RB.DEFAULT_COMBO_COLOR
local DEFAULT_RUNE_READY_COLOR = RB.DEFAULT_RUNE_READY_COLOR
local DEFAULT_SHARD_READY_COLOR = RB.DEFAULT_SHARD_READY_COLOR
local DEFAULT_HOLY_COLOR = RB.DEFAULT_HOLY_COLOR
local DEFAULT_CHI_COLOR = RB.DEFAULT_CHI_COLOR
local DEFAULT_ARCANE_COLOR = RB.DEFAULT_ARCANE_COLOR
local DEFAULT_ESSENCE_READY_COLOR = RB.DEFAULT_ESSENCE_READY_COLOR
local EnsureCustomBarId = RB.EnsureCustomBarId
local EnsureCustomBarLayout = RB.EnsureCustomBarLayout
local GetCustomBarLayout = RB.GetCustomBarLayout
local HealthResource = CS.healthResourceUI

local GetConfigActiveResources = RBP.GetConfigActiveResources
local GetCurrentConfigSpecID = RBP.GetCurrentConfigSpecID
local ReadSpecOverrideKey = RBP.ReadSpecOverrideKey
local IsResourceBarVerticalConfig = RBP.IsResourceBarVerticalConfig

local function BuildLayoutOrderPanel(container)
    if ST._BuildLayoutOrderPreviewPanel then
        ST._BuildLayoutOrderPreviewPanel(container)
        return
    end

    local rbSettings = CooldownCompanion:GetResourceBarSettings()
    local cbSettings = CooldownCompanion:GetCastBarSettings()

    if not rbSettings or not rbSettings.enabled then
        local label = AceGUI:Create("Label")
        ST._ConfigureWrappedHelperLabel(label)
        label:SetText("Enable Resource Bars to configure layout.")
        label:SetFullWidth(true)
        container:AddChild(label)
        return
    end

    local layout = CooldownCompanion:GetSpecLayoutOrder()
    if not layout then
        local label = AceGUI:Create("Label")
        ST._ConfigureWrappedHelperLabel(label)
        label:SetText("Specialization data loading...")
        label:SetFullWidth(true)
        container:AddChild(label)
        return
    end
    local isVerticalLayout = IsResourceBarVerticalConfig(rbSettings, layout)

    -- Build the ordered list of all active bar slots
    local activeResources = GetConfigActiveResources()
    local customBars = CooldownCompanion:GetSpecCustomAuraBars()

    -- Resolve the display color for a power type (respects per-spec overrides)
    local layoutSpecID = GetCurrentConfigSpecID()
    if not layoutSpecID then
        local specLabel = AceGUI:Create("Label")
        ST._ConfigureWrappedHelperLabel(specLabel)
        specLabel:SetText("Specialization data not yet available.")
        specLabel:SetFullWidth(true)
        container:AddChild(specLabel)
        return
    end
    local function GetResourceColor(pt)
        if pt == HealthResource.ID then
            local health = rbSettings.resources and rbSettings.resources[HealthResource.ID]
            return health and health.healthBarColor or DEFAULT_HEALTH_BAR_COLOR
        elseif pt == 4 then return ReadSpecOverrideKey(rbSettings, pt, layoutSpecID, "comboColor", DEFAULT_COMBO_COLOR)
        elseif pt == 5 then return ReadSpecOverrideKey(rbSettings, pt, layoutSpecID, "runeReadyColor", DEFAULT_RUNE_READY_COLOR)
        elseif pt == 7 then return ReadSpecOverrideKey(rbSettings, pt, layoutSpecID, "shardReadyColor", DEFAULT_SHARD_READY_COLOR)
        elseif pt == 9 then return ReadSpecOverrideKey(rbSettings, pt, layoutSpecID, "holyColor", DEFAULT_HOLY_COLOR)
        elseif pt == 12 then return ReadSpecOverrideKey(rbSettings, pt, layoutSpecID, "chiColor", DEFAULT_CHI_COLOR)
        elseif pt == 16 then return ReadSpecOverrideKey(rbSettings, pt, layoutSpecID, "arcaneColor", DEFAULT_ARCANE_COLOR)
        elseif pt == 19 then return ReadSpecOverrideKey(rbSettings, pt, layoutSpecID, "essenceReadyColor", DEFAULT_ESSENCE_READY_COLOR)
        elseif pt == 100 then return ReadSpecOverrideKey(rbSettings, pt, layoutSpecID, "mwBaseColor", DEFAULT_MW_BASE_COLOR)
        elseif pt == 101 then return ReadSpecOverrideKey(rbSettings, pt, layoutSpecID, "staggerGreenColor", { 0.52, 0.90, 0.52 })
        else return ReadSpecOverrideKey(rbSettings, pt, layoutSpecID, "color", DEFAULT_POWER_COLORS[pt] or { 1, 1, 1 })
        end
    end

    -- Helper: refresh after any order/position change
    local function ApplyAndRefresh()
        CooldownCompanion:ApplyResourceBars()
        CooldownCompanion:RepositionCastBar()
        CooldownCompanion:UpdateAnchorStacking()
        CooldownCompanion:RefreshConfigPanel()
    end

    local function RenderSlotOrdering(slots, sectionTitle, sideOne, sideTwo, dividerLabel, moveOneLabel, moveTwoLabel)
        if sectionTitle and sectionTitle ~= "" then
            local sectionHeading = AceGUI:Create("Heading")
            sectionHeading:SetText(sectionTitle)
            sectionHeading:SetFullWidth(true)
            container:AddChild(sectionHeading)
        end

        if #slots == 0 then
            local emptyLabel = AceGUI:Create("Label")
            ST._ConfigureWrappedHelperLabel(emptyLabel)
            emptyLabel:SetText("|cff888888No active entries in this section.|r")
            emptyLabel:SetFullWidth(true)
            container:AddChild(emptyLabel)
            return
        end

        local sideOneSlots = {}
        local sideTwoSlots = {}
        for _, slot in ipairs(slots) do
            if slot.getPos() == sideOne then
                table.insert(sideOneSlots, slot)
            else
                table.insert(sideTwoSlots, slot)
            end
        end
        table.sort(sideOneSlots, function(a, b) return a.getOrder() > b.getOrder() end)
        table.sort(sideTwoSlots, function(a, b) return a.getOrder() < b.getOrder() end)

        local displayList = {}
        for _, s in ipairs(sideOneSlots) do table.insert(displayList, s) end
        local dividerIdx = #displayList + 1
        for _, s in ipairs(sideTwoSlots) do table.insert(displayList, s) end

        for rowIdx, slot in ipairs(displayList) do
            if rowIdx == dividerIdx then
                local divLabel = AceGUI:Create("Heading")
                divLabel:SetText(dividerLabel or "Icons")
                divLabel:SetFullWidth(true)
                container:AddChild(divLabel)
            end

            local rowGroup = AceGUI:Create("SimpleGroup")
            rowGroup:SetLayout("Flow")
            rowGroup:SetFullWidth(true)
            container:AddChild(rowGroup)

            local nameLabel = AceGUI:Create("Label")
            ST._ConfigureWrappedHelperLabel(nameLabel)
            local c = slot.color
            local coloredText = slot.label
            if c then
                local r, g, b = (c[1] or 1) * 255, (c[2] or 1) * 255, (c[3] or 1) * 255
                coloredText = string.format("|cff%02x%02x%02x%s|r", math.floor(r + 0.5), math.floor(g + 0.5), math.floor(b + 0.5), slot.label)
            end
            nameLabel:SetText(coloredText)
            nameLabel:SetRelativeWidth(0.48)
            rowGroup:AddChild(nameLabel)

            local moveOneBtn = AceGUI:Create("Button")
            moveOneBtn:SetText(moveOneLabel)
            moveOneBtn:SetRelativeWidth(0.20)
            moveOneBtn:SetDisabled(rowIdx == 1 and slot.getPos() == sideOne)
            moveOneBtn:SetCallback("OnClick", function()
                local prev = displayList[rowIdx - 1]
                if prev and prev.getPos() == slot.getPos() then
                    local myOrder = slot.getOrder()
                    local prevOrder = prev.getOrder()
                    slot.setOrder(prevOrder)
                    prev.setOrder(myOrder)
                else
                    local minSideOne
                    for _, s in ipairs(sideOneSlots) do
                        local o = s.getOrder()
                        if not minSideOne or o < minSideOne then minSideOne = o end
                    end
                    local currentOrder = slot.getOrder()
                    slot.setPos(sideOne)
                    slot.setOrder(minSideOne and (minSideOne - 1) or currentOrder)
                end
                ApplyAndRefresh()
            end)
            rowGroup:AddChild(moveOneBtn)

            local moveTwoBtn = AceGUI:Create("Button")
            moveTwoBtn:SetText(moveTwoLabel)
            moveTwoBtn:SetRelativeWidth(0.24)
            moveTwoBtn:SetDisabled(rowIdx == #displayList and slot.getPos() == sideTwo)
            moveTwoBtn:SetCallback("OnClick", function()
                local nextSlot = displayList[rowIdx + 1]
                if nextSlot and nextSlot.getPos() == slot.getPos() then
                    local myOrder = slot.getOrder()
                    local nextOrder = nextSlot.getOrder()
                    slot.setOrder(nextOrder)
                    nextSlot.setOrder(myOrder)
                else
                    local minSideTwo
                    for _, s in ipairs(sideTwoSlots) do
                        local o = s.getOrder()
                        if not minSideTwo or o < minSideTwo then minSideTwo = o end
                    end
                    local currentOrder = slot.getOrder()
                    slot.setPos(sideTwo)
                    slot.setOrder(minSideTwo and (minSideTwo - 1) or currentOrder)
                end
                ApplyAndRefresh()
            end)
            rowGroup:AddChild(moveTwoBtn)
        end
    end

    local resourceSlots = {}
    if not rbSettings.resources then rbSettings.resources = {} end

    -- Class resource slots
    for _, pt in ipairs(activeResources) do
        if pt == HealthResource.ID then
            HealthResource.EnsureSettings(rbSettings)
        elseif not rbSettings.resources[pt] then rbSettings.resources[pt] = {} end
        local res = rbSettings.resources[pt]
        local showResource = pt == HealthResource.ID and res.enabled == true or res.enabled ~= false
        if showResource and pt == 0 and rbSettings.hideManaForNonHealer then
            local specIdx = C_SpecializationInfo.GetSpecialization()
            if specIdx then
                local specID, _, _, _, role = C_SpecializationInfo.GetSpecializationInfo(specIdx)
                if specID ~= 62 and role ~= "HEALER" then
                    showResource = false
                end
            end
        end
        if showResource then
            local name = POWER_NAMES[pt] or ("Power " .. pt)
            local function ensureLayoutRes()
                if not layout.resources[pt] then layout.resources[pt] = {} end
                return layout.resources[pt]
            end
            if isVerticalLayout then
                table.insert(resourceSlots, {
                    label = name,
                    color = GetResourceColor(pt),
                    getPos = function()
                        local lr = layout.resources[pt]
                        local pos = lr and lr.verticalPosition
                        if pos == "left" or pos == "right" then return pos end
                        return (lr and lr.position == "above") and "left" or "right"
                    end,
                    getOrder = function()
                        local lr = layout.resources[pt]
                        return (lr and lr.verticalOrder) or (lr and lr.order) or (900 + pt)
                    end,
                    setPos = function(v) ensureLayoutRes().verticalPosition = v end,
                    setOrder = function(v) ensureLayoutRes().verticalOrder = v end,
                })
            else
                table.insert(resourceSlots, {
                    label = name,
                    color = GetResourceColor(pt),
                    getPos = function()
                        local lr = layout.resources[pt]
                        return (lr and lr.position) or "below"
                    end,
                    getOrder = function()
                        local lr = layout.resources[pt]
                        return (lr and lr.order) or (900 + pt)
                    end,
                    setPos = function(v) ensureLayoutRes().position = v end,
                    setOrder = function(v) ensureLayoutRes().order = v end,
                })
            end
        end
    end

    -- Custom Bar slots
    for slotIdx, cab in ipairs(customBars or {}) do
        if cab and cab.enabled and cab.spellID then
            local customBarId = EnsureCustomBarId(rbSettings, cab)
            local spellInfo = C_Spell.GetSpellInfo(cab.spellID)
            local slotName = "Custom Bar"
            if spellInfo and spellInfo.name then
                slotName = slotName .. ": " .. spellInfo.name
            end
            local captured = slotIdx
            local function ensureLayoutSlot()
                return EnsureCustomBarLayout(rbSettings, layoutSpecID, customBarId, 1000 + captured)
            end
            if isVerticalLayout then
                table.insert(resourceSlots, {
                    label = slotName,
                    color = cab.barColor or {0.5, 0.5, 1},
                    getPos = function()
                        local slot = GetCustomBarLayout(rbSettings, layoutSpecID, cab, false)
                        local pos = slot and slot.verticalPosition
                        if pos == "left" or pos == "right" then return pos end
                        return (slot and slot.position == "above") and "left" or "right"
                    end,
                    getOrder = function()
                        local slot = GetCustomBarLayout(rbSettings, layoutSpecID, cab, false)
                        return (slot and slot.verticalOrder) or (slot and slot.order) or (1000 + captured)
                    end,
                    setPos = function(v) ensureLayoutSlot().verticalPosition = v end,
                    setOrder = function(v) ensureLayoutSlot().verticalOrder = v end,
                })
            else
                table.insert(resourceSlots, {
                    label = slotName,
                    color = cab.barColor or {0.5, 0.5, 1},
                    getPos = function()
                        local slot = GetCustomBarLayout(rbSettings, layoutSpecID, cab, false)
                        return (slot and slot.position) or "below"
                    end,
                    getOrder = function()
                        local slot = GetCustomBarLayout(rbSettings, layoutSpecID, cab, false)
                        return (slot and slot.order) or (1000 + captured)
                    end,
                    setPos = function(v) ensureLayoutSlot().position = v end,
                    setOrder = function(v) ensureLayoutSlot().order = v end,
                })
            end
        end
    end

    local castSlots = {}
    if cbSettings and cbSettings.enabled and not cbSettings.independentAnchorEnabled then
        local defaultAnchor = CooldownCompanion:GetFirstAvailableAnchorGroup()
        local cbAnchor = defaultAnchor
        local rbAnchor = defaultAnchor
        if cbAnchor and cbAnchor == rbAnchor then
            local cbColor = cbSettings.barColor or { 1.0, 0.7, 0.0 }
            table.insert(castSlots, {
                label = "Cast Bar",
                color = cbColor,
                getPos = function() return (layout.castBar and layout.castBar.position) or "below" end,
                getOrder = function() return (layout.castBar and layout.castBar.order) or 2000 end,
                setPos = function(v)
                    if not layout.castBar then layout.castBar = { position = "below", order = 2000 } end
                    layout.castBar.position = v
                end,
                setOrder = function(v)
                    if not layout.castBar then layout.castBar = { position = "below", order = 2000 } end
                    layout.castBar.order = v
                end,
            })
        end
    end

    if not isVerticalLayout then
        for _, slot in ipairs(castSlots) do
            table.insert(resourceSlots, slot)
        end
        if #resourceSlots == 0 then
            local label = AceGUI:Create("Label")
            ST._ConfigureWrappedHelperLabel(label)
            label:SetText("No active bars to order. Enable resources or Custom Bars first.")
            label:SetFullWidth(true)
            container:AddChild(label)
            return
        end
        RenderSlotOrdering(resourceSlots, nil, "above", "below", "Icons", "Up", "Down")
        return
    end

    if #resourceSlots == 0 and #castSlots == 0 then
        local label = AceGUI:Create("Label")
        ST._ConfigureWrappedHelperLabel(label)
        label:SetText("No active bars to order. Enable resources, Custom Bars, or cast bar first.")
        label:SetFullWidth(true)
        container:AddChild(label)
        return
    end

    RenderSlotOrdering(resourceSlots, nil, "left", "right", "Icons", "Left", "Right")

    if #castSlots > 0 then
        local spacer = AceGUI:Create("Label")
        spacer:SetText(" ")
        spacer:SetFullWidth(true)
        container:AddChild(spacer)
        RenderSlotOrdering(castSlots, "Cast Bar", "above", "below", "Icons", "Up", "Down")
    end
end

-- Expose for ButtonSettings.lua and Config.lua
ST._BuildLayoutOrderPanel = BuildLayoutOrderPanel
