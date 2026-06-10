local constructorCounts = {
    icon = 0,
    bar = 0,
    text = 0,
}

local releaseAuraCount = 0
local masqueAdds = 0
local masqueRemoves = 0
local unregisterCount = 0
local clearVisualCount = 0
local updateIconCount = 0
local secrecyCalls = 0
local masqueMembers = {}

function wipe(tbl)
    if not tbl then return end
    for key in pairs(tbl) do
        tbl[key] = nil
    end
end

function InCombatLockdown()
    return false
end

function issecretvalue()
    return false
end

C_CVar = {
    GetCVarBool = function()
        return false
    end,
}

C_Secrets = {
    GetSpellCooldownSecrecy = function()
        secrecyCalls = secrecyCalls + 1
        return false
    end,
}

function LibStub()
    return {
        Fetch = function(_, _, name)
            return name
        end,
        IsValid = function()
            return true
        end,
    }
end

local function AssertEqual(actual, expected, message)
    assert(actual == expected, ("%s (expected %s, got %s)"):format(message, tostring(expected), tostring(actual)))
end

local function NewFrame(name, parent)
    local frame = {
        name = name,
        parent = parent,
        children = {},
        scripts = {},
        points = {},
        shown = false,
        alpha = 1,
        width = 1,
        height = 1,
        frameStrata = "MEDIUM",
        frameLevel = 1,
    }
    if parent and parent.children then
        parent.children[#parent.children + 1] = frame
    end

    function frame:GetName()
        return self.name
    end

    function frame:SetParent(newParent)
        self.parent = newParent
    end

    function frame:GetParent()
        return self.parent
    end

    function frame:SetScript(scriptName, handler)
        self.scripts[scriptName] = handler
    end

    function frame:GetScript(scriptName)
        return self.scripts[scriptName]
    end

    function frame:Show()
        self.shown = true
    end

    function frame:Hide()
        self.shown = false
    end

    function frame:IsShown()
        return self.shown
    end

    function frame:SetAlpha(alpha)
        self.alpha = alpha
    end

    function frame:GetAlpha()
        return self.alpha
    end

    function frame:SetSize(width, height)
        self.width = width
        self.height = height
    end

    function frame:GetSize()
        return self.width, self.height
    end

    function frame:GetWidth()
        return self.width
    end

    function frame:GetHeight()
        return self.height
    end

    function frame:IsProtected()
        return false
    end

    function frame:ClearAllPoints()
        wipe(self.points)
    end

    function frame:SetPoint(...)
        self.points[#self.points + 1] = {...}
    end

    function frame:AdjustPointsOffset(dx, dy)
        self.adjustedX = (self.adjustedX or 0) + dx
        self.adjustedY = (self.adjustedY or 0) + dy
    end

    function frame:SetFrameStrata(strata)
        self.frameStrata = strata
    end

    function frame:SetFixedFrameStrata(fixed)
        self.fixedFrameStrata = fixed
    end

    function frame:GetFrameStrata()
        return self.frameStrata
    end

    function frame:SetFrameLevel(level)
        self.frameLevel = level
    end

    function frame:GetFrameLevel()
        return self.frameLevel
    end

    function frame:GetChildren()
        return unpack(self.children)
    end

    function frame:CreateFontString()
        local child = NewFrame((self.name or "Frame") .. "FontString", self)
        function child:SetText(text)
            self.text = text
        end
        function child:SetFont(font, size, outline)
            self.font = font
            self.fontSize = size
            self.fontOutline = outline
        end
        function child:SetTextColor(r, g, b, a)
            self.textColor = { r, g, b, a }
        end
        function child:SetShadowColor(r, g, b, a)
            self.shadowColor = { r, g, b, a }
        end
        function child:SetShadowOffset(x, y)
            self.shadowOffset = { x, y }
        end
        function child:SetJustifyH(justify)
            self.justifyH = justify
        end
        function child:SetJustifyV(justify)
            self.justifyV = justify
        end
        function child:SetWidth(width)
            self.width = width
        end
        return child
    end

    function frame:CreateTexture()
        return NewFrame((self.name or "Frame") .. "Texture", self)
    end

    function frame:Clear()
        self.cleared = true
    end

    function frame:SetText(text)
        self.text = text
    end

    return frame
end

function CreateFrame(_, name, parent)
    return NewFrame(name, parent)
end

local CooldownCompanion = {
    db = {
        profile = {
            groups = {},
            groupContainers = {},
        },
    },
    groupFrames = {},
    _dormantFrames = {},
    MasqueGroups = {},
}

function CooldownCompanion:GetCursorAnchorTargetName()
    return "CooldownCompanionCursorAnchor"
end

function CooldownCompanion:GetDefaultCursorPanelAnchor()
    return {
        point = "BOTTOMLEFT",
        relativePoint = "CENTER",
        x = 16,
        y = 16,
    }
end

function CooldownCompanion:IsCursorAnchor()
    return false
end

function CooldownCompanion:GetEffectiveStyle(style, buttonData)
    if buttonData.style then
        local merged = {}
        for key, value in pairs(style or {}) do
            merged[key] = value
        end
        for key, value in pairs(buttonData.style) do
            merged[key] = value
        end
        return merged
    end
    return style or {}
end

function CooldownCompanion:FetchFont(font)
    return font
end

function CooldownCompanion:ReleaseAuraTextureVisual(button)
    releaseAuraCount = releaseAuraCount + 1
    button.releasedAuraVisual = (button.releasedAuraVisual or 0) + 1
end

function CooldownCompanion:AddButtonToMasque(_, button)
    masqueAdds = masqueAdds + 1
    button.masqueAdds = (button.masqueAdds or 0) + 1
    masqueMembers[button] = true
end

function CooldownCompanion:RemoveButtonFromMasque(_, button)
    masqueRemoves = masqueRemoves + 1
    button.masqueRemoves = (button.masqueRemoves or 0) + 1
    masqueMembers[button] = nil
end

function CooldownCompanion:UpdateButtonIcon(button)
    updateIconCount = updateIconCount + 1
    button.updatedIcon = (button.updatedIcon or 0) + 1
end

function CooldownCompanion:ResolveAuraSpellID(buttonData)
    return buttonData and buttonData.auraSpellID or nil
end

function CooldownCompanion.IsEntryItemLike(buttonData)
    return buttonData and buttonData.type == "item"
end

function CooldownCompanion.ResolveEffectiveItem(buttonData)
    return {
        itemID = buttonData.id + 100000,
        availableQuantity = 2,
        quantityKind = "charges",
        trackable = true,
    }
end

function CooldownCompanion.IsEquipmentSlotEntry(buttonData)
    return buttonData and buttonData.equipmentSlot == true
end

local ST = {
    Addon = CooldownCompanion,
    BUTTON_SIZE = 36,
    BUTTON_SPACING = 4,
    SetFrameClickThrough = function() end,
    SetFrameClickThroughRecursive = function() end,
    GetEffectiveFontOutline = function(outline)
        return outline
    end,
    EntryRuntime = {
        ClearAuraPandemicRuntimeState = function(button)
            button.pandemicRuntimeCleared = true
        end,
    },
}

function ST._UnregisterKeyPressHighlightButton(button)
    unregisterCount = unregisterCount + 1
    button.unregisteredKph = (button.unregisteredKph or 0) + 1
end

function ST._ClearButtonVisualState(button)
    clearVisualCount = clearVisualCount + 1
    button.visualStateCleared = (button.visualStateCleared or 0) + 1
end

function ST._CacheButtonBindingKeys(button, buttonData)
    button._bindingKeyInfos = { "cached", buttonData and buttonData.id or nil }
end

assert(loadfile("Core/GroupOperations.lua"))("CooldownCompanion", ST)
assert(loadfile("Core/GroupFrame.lua"))("CooldownCompanion", ST)

function CooldownCompanion:IsButtonUsable(buttonData)
    return buttonData.usable ~= false
end

function CooldownCompanion:UpdateGroupClickthrough()
    self.updateClickthroughCount = (self.updateClickthroughCount or 0) + 1
end

function CooldownCompanion:ApplyConfigPreviewsToGroup()
    self.previewCount = (self.previewCount or 0) + 1
end

function CooldownCompanion:UpdateRangeCheckRegistrations()
    self.rangeUpdateCount = (self.rangeUpdateCount or 0) + 1
end

function CooldownCompanion:AnchorGroupFrame()
    self.anchorCount = (self.anchorCount or 0) + 1
end

function CooldownCompanion:SetGroupDragControlsShown()
    self.dragControlCount = (self.dragControlCount or 0) + 1
end

function CooldownCompanion:IsGroupActive()
    return true
end

function CooldownCompanion:CreateMasqueGroup(groupId)
    self.MasqueGroups[groupId] = {}
end

function CooldownCompanion:DeleteMasqueGroup(groupId)
    self.MasqueGroups[groupId] = nil
end

local function AddTextSurfaces(button)
    button.count = NewFrame(button.name .. "Count", button)
    button.auraStackCount = NewFrame(button.name .. "AuraStack", button)
    button.textString = NewFrame(button.name .. "Text", button)
    button.nameText = NewFrame(button.name .. "Name", button)
    button.timeText = NewFrame(button.name .. "Time", button)
    button.statusBar = NewFrame(button.name .. "StatusBar", button)
end

local function AddCooldownSurfaces(button, includeSecondary)
    button.cooldown = NewFrame(button.name .. "Cooldown", button)
    button.locCooldown = NewFrame(button.name .. "LocCooldown", button)
    button.iconGCDCooldown = NewFrame(button.name .. "GCDCooldown", button)
    button.auraBlizzardCooldown = NewFrame(button.name .. "AuraCooldown", button)
    if includeSecondary then
        button.secondaryCooldown = NewFrame(button.name .. "SecondaryCooldown", button)
    end
end

local function NewButtonFrame(kind, parent, index, buttonData, style)
    local button = NewFrame(kind .. tostring(constructorCounts[kind]), parent)
    button.kind = kind
    button.index = index
    button.buttonData = buttonData
    button.style = style or {}
    button._groupId = parent.groupId
    button.iconFill = NewFrame(button.name .. "IconFill", button)
    button._iconBounds = NewFrame(button.name .. "IconBounds", button)
    button.assistedHighlight = NewFrame(button.name .. "Assist", button)
    button.procGlow = NewFrame(button.name .. "ProcGlow", button)
    button.auraGlow = NewFrame(button.name .. "AuraGlow", button)
    button.readyGlow = NewFrame(button.name .. "ReadyGlow", button)
    button.keyPressHighlight = NewFrame(button.name .. "KPH", button)
    button.barAuraEffect = NewFrame(button.name .. "BarAura", button)
    AddTextSurfaces(button)
    AddCooldownSurfaces(button, kind == "icon"
        and style
        and style.separateTextPositions
        and buttonData
        and buttonData.auraTracking
        and not buttonData.isPassive)
    function button:UpdateStyle(newStyle)
        self.style = newStyle
        self.updateStyleCount = (self.updateStyleCount or 0) + 1
    end
    function button:UpdateCooldown()
        self.updateCooldownCount = (self.updateCooldownCount or 0) + 1
    end
    return button
end

function CooldownCompanion:CreateButtonFrame(parent, index, buttonData, style)
    constructorCounts.icon = constructorCounts.icon + 1
    return NewButtonFrame("icon", parent, index, buttonData, style)
end

function CooldownCompanion:CreateBarFrame(parent, index, buttonData, style)
    constructorCounts.bar = constructorCounts.bar + 1
    local button = NewButtonFrame("bar", parent, index, buttonData, style)
    button._isBar = true
    return button
end

function CooldownCompanion:CreateTextFrame(parent, index, buttonData, style)
    constructorCounts.text = constructorCounts.text + 1
    local button = NewButtonFrame("text", parent, index, buttonData, style)
    button._isText = true
    return button
end

local function NewGroupFrame(groupId)
    local frame = NewFrame("Group" .. tostring(groupId))
    frame.groupId = groupId
    frame.buttons = {}
    function frame:UpdateCooldowns()
        self.updateCooldownsCount = (self.updateCooldownsCount or 0) + 1
        for _, button in ipairs(self.buttons) do
            button:UpdateCooldown()
        end
    end
    return frame
end

local function ActiveSet(frame)
    local set = {}
    for _, button in ipairs(frame.buttons) do
        set[button] = true
    end
    return set
end

local function AssertActiveButtonsCameFrom(frame, expectedSet, message)
    for _, button in ipairs(frame.buttons) do
        assert(expectedSet[button], message)
    end
end

local function CollectActiveAndPooledButtons(frame)
    local buttons = {}
    for _, button in ipairs(frame.buttons or {}) do
        buttons[#buttons + 1] = button
    end
    for _, pool in pairs(frame._buttonFramePools or {}) do
        for _, button in ipairs(pool) do
            buttons[#buttons + 1] = button
        end
    end
    return buttons
end

local function DirtyCooldownWidgets(button)
    local fields = {
        "cooldown",
        "locCooldown",
        "iconGCDCooldown",
        "secondaryCooldown",
        "auraBlizzardCooldown",
    }
    for _, field in ipairs(fields) do
        local widget = button[field]
        if widget then
            widget:SetScript("OnUpdate", function() end)
            widget.cleared = nil
            widget:Show()
        end
    end
end

local function AssertCooldownWidgetsCleared(button, message)
    local fields = {
        "cooldown",
        "locCooldown",
        "iconGCDCooldown",
        "secondaryCooldown",
        "auraBlizzardCooldown",
    }
    for _, field in ipairs(fields) do
        local widget = button[field]
        if widget then
            AssertEqual(widget:GetScript("OnUpdate"), nil, message .. " should clear " .. field .. " OnUpdate")
            AssertEqual(widget.cleared, true, message .. " should clear " .. field)
            AssertEqual(widget:IsShown(), false, message .. " should hide " .. field)
        end
    end
end

local function DirtySoundAlertRuntime(button)
    button._sndInitialized = true
    button._sndPrevCooldownActive = true
    button._sndPrevAuraActive = true
    button._sndPrevCharges = 1
    button._sndPrevChargeRecharging = true
    button._sndPrevChargeCooldownStart = 42
    button._sndTransitionOptions = {
        playContext = { id = 999 },
    }
end

local function AssertSoundAlertRuntimeCleared(button, message)
    local fields = {
        "_sndInitialized",
        "_sndPrevCooldownActive",
        "_sndPrevAuraActive",
        "_sndPrevCharges",
        "_sndPrevChargeRecharging",
        "_sndPrevChargeCooldownStart",
        "_sndTransitionOptions",
    }
    for _, field in ipairs(fields) do
        AssertEqual(button[field], nil, message .. " should clear " .. field)
    end
end

local function ResetGroup(displayMode, buttons, style)
    CooldownCompanion.db.profile.groups[1] = {
        name = "Pool Test",
        displayMode = displayMode or "icons",
        buttons = buttons,
        style = style or {
            buttonSize = 32,
            buttonSpacing = 2,
            buttonsPerRow = 12,
        },
        masqueEnabled = true,
    }
end

local frame = NewGroupFrame(1)
CooldownCompanion.groupFrames[1] = frame

ResetGroup("icons", {
    { id = 101, type = "spell" },
    { id = 102, type = "spell" },
    { id = 103, type = "spell" },
})
CooldownCompanion:PopulateGroupButtons(1)
AssertEqual(#frame.buttons, 3, "first populate should create three active icon buttons")
AssertEqual(constructorCounts.icon, 3, "first populate should allocate three icon buttons")
local firstIconSet = ActiveSet(frame)

CooldownCompanion:PopulateGroupButtons(1)
AssertEqual(#frame.buttons, 3, "same icon populate should keep three active buttons")
AssertEqual(constructorCounts.icon, 3, "same icon populate should reuse pooled buttons")
AssertActiveButtonsCameFrom(frame, firstIconSet, "same icon populate should reuse the warm icon pool")
AssertEqual(#(frame._buttonFramePools.icons or {}), 0, "same-size icon repopulate should consume the icon pool")
AssertEqual(secrecyCalls, 3, "first pooled spell rebind should cache spell secrecy")
CooldownCompanion:PopulateGroupButtons(1)
AssertEqual(secrecyCalls, 3, "same spell entries should reuse cached spell secrecy")

local seededReusableIcon = frame.buttons[#frame.buttons]
seededReusableIcon._resolvedItemId = 999
seededReusableIcon._resolvedItemMaxCharges = 4
seededReusableIcon._auraInstanceID = 888
seededReusableIcon._bindingKeyInfos = { "stale" }
seededReusableIcon._chargesSpent = 2
seededReusableIcon._spellOutOfRange = true
seededReusableIcon._savedOnUpdate = function() end
seededReusableIcon:SetScript("OnUpdate", function() end)
seededReusableIcon.iconFill:SetScript("OnUpdate", function() end)
DirtySoundAlertRuntime(seededReusableIcon)
DirtyCooldownWidgets(seededReusableIcon)

ResetGroup("icons", {
    { id = 201, type = "item", equipmentSlot = true },
    { id = 202, type = "spell" },
})
CooldownCompanion:PopulateGroupButtons(1)
AssertEqual(#frame.buttons, 2, "shrunk icon populate should leave two active buttons")
AssertEqual(constructorCounts.icon, 3, "shrunk icon populate should not allocate replacements")
AssertEqual(frame.buttons[1], seededReusableIcon, "shrunk icon populate should reuse the seeded LIFO icon first")
AssertEqual(frame.buttons[1]:GetScript("OnUpdate"), nil, "reused icon should clear parent OnUpdate")
AssertEqual(frame.buttons[1].iconFill:GetScript("OnUpdate"), nil, "reused icon should clear icon-fill OnUpdate")
AssertCooldownWidgetsCleared(frame.buttons[1], "reused icon")
AssertSoundAlertRuntimeCleared(frame.buttons[1], "reused icon")
AssertEqual(frame.buttons[1]._savedOnUpdate, nil, "reused icon should clear dormant saved OnUpdate")
AssertEqual(frame.buttons[1]._auraInstanceID, nil, "reused icon should clear aura instance state")
AssertEqual(frame.buttons[1]._resolvedItemMaxCharges, nil, "reused icon should clear stale max charges before resolving item")
AssertEqual(frame.buttons[1]._chargesSpent, nil, "reused icon should clear spent-charge state")
AssertEqual(frame.buttons[1]._spellOutOfRange, nil, "reused icon should clear range state")
AssertEqual(frame.buttons[1]._bindingKeyInfos[1], "cached", "reused item button should refresh binding-key state")
AssertEqual(frame.buttons[1]._resolvedItemId, 100201, "reused item button should resolve current item state")
AssertEqual(#(frame._buttonFramePools.icons or {}), 1, "shrunk icon populate should retain one pooled icon button")
local pooledIcon = frame._buttonFramePools.icons[1]
AssertEqual(pooledIcon:GetScript("OnUpdate"), nil, "pooled icon should clear parent OnUpdate")
AssertEqual(pooledIcon.iconFill:GetScript("OnUpdate"), nil, "pooled icon should clear icon-fill OnUpdate")

CooldownCompanion:PopulateGroupButtons(1)
AssertEqual(constructorCounts.icon, 3, "repopulating shrunk icon group should still reuse buttons")
AssertEqual(frame.buttons[1]._bindingKeyInfos[1], "cached", "reused item button should refresh binding-key state")
AssertEqual(frame.buttons[1]._resolvedItemId, 100201, "reused item button should resolve current item state")

ResetGroup("textures", {
    { id = 301, type = "spell" },
    { id = 302, type = "spell" },
})
CooldownCompanion:PopulateGroupButtons(1)
AssertEqual(constructorCounts.icon, 5, "texture mode should keep a separate pool from icon mode")
AssertEqual(frame.buttons[1]:GetAlpha(), 0, "texture-mode active buttons should start alpha hidden")
AssertEqual(frame.buttons[1]._lastVisAlpha, 0, "texture-mode active buttons should reset last visible alpha")
AssertEqual(#(frame._buttonFramePools.icons or {}), 3, "icon buttons should remain pooled when texture mode is active")

ResetGroup("icons", {
    { id = 401, type = "spell" },
    { id = 402, type = "spell" },
})
CooldownCompanion:PopulateGroupButtons(1)
AssertEqual(constructorCounts.icon, 5, "returning to icon mode should reuse the icon pool")
AssertEqual(frame.buttons[1]:GetAlpha(), 1, "reused icon-mode buttons should restore visible alpha")
AssertEqual(frame.buttons[1]._lastVisAlpha, 1, "reused icon-mode buttons should restore visible last alpha")

ResetGroup("icons", {
    {
        id = 501,
        type = "spell",
        auraTracking = true,
        style = { separateTextPositions = true },
    },
})
CooldownCompanion:PopulateGroupButtons(1)
AssertEqual(constructorCounts.icon, 6, "secondary-cooldown icon shape should allocate its own pool member")
assert(frame.buttons[1].secondaryCooldown, "secondary-cooldown icon should have a secondary cooldown widget")
local secondaryButton = frame.buttons[1]
secondaryButton._savedOnUpdate = function() end
DirtyCooldownWidgets(secondaryButton)

ResetGroup("icons", {
    { id = 502, type = "spell" },
})
CooldownCompanion:PopulateGroupButtons(1)
AssertEqual(constructorCounts.icon, 6, "plain icon should not consume the secondary-cooldown pool")
assert(not frame.buttons[1].secondaryCooldown, "plain icon should come from the plain icon pool")
AssertEqual(#(frame._buttonFramePools["icons-secondary"] or {}), 1, "secondary-cooldown icon should stay isolated in its pool")
AssertEqual(frame._buttonFramePools["icons-secondary"][1], secondaryButton, "secondary-cooldown pool should retain the secondary-capable frame")
AssertCooldownWidgetsCleared(secondaryButton, "pooled secondary icon")
AssertEqual(secondaryButton._savedOnUpdate, nil, "pooled secondary icon should clear dormant saved OnUpdate")

ResetGroup("text", {
    { id = 601, type = "spell" },
    { id = 602, type = "spell" },
}, {
    textWidth = 180,
    textHeight = 18,
})
local textCountBefore = constructorCounts.text
CooldownCompanion:PopulateGroupButtons(1)
AssertEqual(constructorCounts.text, textCountBefore + 2, "text mode should allocate text frames from a separate pool")
local textSet = ActiveSet(frame)
CooldownCompanion:PopulateGroupButtons(1)
AssertEqual(constructorCounts.text, textCountBefore + 2, "same text populate should reuse text frames")
AssertActiveButtonsCameFrom(frame, textSet, "same text populate should reuse the text pool")

ResetGroup("bars", {
    { id = 611, type = "spell" },
    { id = 612, type = "spell" },
}, {
    barLength = 120,
    barHeight = 16,
})
local barCountBefore = constructorCounts.bar
CooldownCompanion:PopulateGroupButtons(1)
AssertEqual(constructorCounts.bar, barCountBefore + 2, "bar mode should allocate bar frames from a separate pool")
local barSet = ActiveSet(frame)
CooldownCompanion:PopulateGroupButtons(1)
AssertEqual(constructorCounts.bar, barCountBefore + 2, "same bar populate should reuse bar frames")
AssertActiveButtonsCameFrom(frame, barSet, "same bar populate should reuse the bar pool")

ResetGroup("trigger", {
    { id = 621, type = "spell" },
})
local iconCountBeforeTrigger = constructorCounts.icon
CooldownCompanion:PopulateGroupButtons(1)
AssertEqual(constructorCounts.icon, iconCountBeforeTrigger + 1, "trigger mode should allocate an icon-shaped frame from a separate pool")
local triggerSet = ActiveSet(frame)
AssertEqual(frame.buttons[1]:GetAlpha(), 0, "trigger active button should start alpha hidden")
CooldownCompanion:PopulateGroupButtons(1)
AssertEqual(constructorCounts.icon, iconCountBeforeTrigger + 1, "same trigger populate should reuse trigger frames")
AssertActiveButtonsCameFrom(frame, triggerSet, "same trigger populate should reuse the trigger pool")

ResetGroup("icons", {
    { id = 701, type = "spell" },
    { id = 702, type = "spell" },
    { id = 703, type = "spell" },
})
CooldownCompanion.Masque = true
CooldownCompanion.MasqueGroups[1] = {}
wipe(masqueMembers)
CooldownCompanion:PopulateGroupButtons(1)
ResetGroup("icons", {
    { id = 701, type = "spell" },
    { id = 702, type = "spell" },
})
CooldownCompanion:PopulateGroupButtons(1)
local masqueTrackedButtons = CollectActiveAndPooledButtons(frame)
local masqueRemoveCounts = {}
for _, button in ipairs(masqueTrackedButtons) do
    masqueMembers[button] = true
    masqueRemoveCounts[button] = button.masqueRemoves or 0
end
CooldownCompanion.db.profile.groups[1].masqueEnabled = false
CooldownCompanion.MasqueGroups[1] = {}
CooldownCompanion:RefreshGroupFrame(1)
AssertEqual(CooldownCompanion.MasqueGroups[1], nil, "Masque disable refresh should delete the Masque group")
for _, button in ipairs(masqueTrackedButtons) do
    AssertEqual(masqueMembers[button], nil, "Masque disable refresh should remove active and pooled button membership")
    assert((button.masqueRemoves or 0) > masqueRemoveCounts[button], "Masque disable refresh should remove each tracked button")
end

ResetGroup("icons", {
    { id = 801, type = "spell" },
    { id = 802, type = "spell" },
})
CooldownCompanion:PopulateGroupButtons(1)
ResetGroup("icons", {
    { id = 801, type = "spell" },
})
CooldownCompanion:PopulateGroupButtons(1)
local discardPooledButton = frame._buttonFramePools.icons and frame._buttonFramePools.icons[1]
assert(discardPooledButton, "discard test should have a pooled icon button")
discardPooledButton._savedOnUpdate = function() end
discardPooledButton:SetScript("OnUpdate", function() end)
discardPooledButton.iconFill:SetScript("OnUpdate", function() end)
DirtySoundAlertRuntime(discardPooledButton)
DirtyCooldownWidgets(discardPooledButton)
masqueMembers[discardPooledButton] = true
local releaseAuraBeforeDiscard = releaseAuraCount
local unregisterBeforeDiscard = unregisterCount
local clearVisualBeforeDiscard = clearVisualCount
local masqueRemoveBeforeDiscard = masqueRemoves
CooldownCompanion._dormantFrames[1] = frame
CooldownCompanion:DiscardDormantFrame(1)
AssertEqual(CooldownCompanion._dormantFrames[1], nil, "discard should remove dormant frame reference")
AssertEqual(frame._buttonFramePools, nil, "discard should clear all retained group button pools")
AssertEqual(discardPooledButton:GetScript("OnUpdate"), nil, "discard should clear pooled parent OnUpdate")
AssertEqual(discardPooledButton.iconFill:GetScript("OnUpdate"), nil, "discard should clear pooled icon-fill OnUpdate")
AssertCooldownWidgetsCleared(discardPooledButton, "discarded pooled icon")
AssertSoundAlertRuntimeCleared(discardPooledButton, "discarded pooled icon")
AssertEqual(discardPooledButton._savedOnUpdate, nil, "discard should clear pooled dormant saved OnUpdate")
AssertEqual(masqueMembers[discardPooledButton], nil, "discard should remove pooled button Masque membership")
assert(releaseAuraCount > releaseAuraBeforeDiscard, "discard should release pooled aura texture visuals")
assert(unregisterCount > unregisterBeforeDiscard, "discard should unregister pooled key-press highlights")
assert(clearVisualCount > clearVisualBeforeDiscard, "discard should clear pooled shared visual state")
assert(masqueRemoves > masqueRemoveBeforeDiscard, "discard should remove pooled Masque membership")
assert(releaseAuraCount > 0, "pool releases should release aura texture visuals")
assert(masqueAdds > 0, "icon buttons should still be added to Masque")
assert(masqueRemoves > 0, "pooled buttons should be removed from Masque")
assert(unregisterCount > 0, "pooled buttons should unregister key-press highlights")
assert(clearVisualCount > 0, "pooled buttons should clear shared visual state")
assert(updateIconCount > 0, "reused buttons should refresh icons")

print("group-button-frame-pooling ok")
