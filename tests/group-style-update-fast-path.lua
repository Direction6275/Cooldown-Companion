local constructorCounts = {
    icon = 0,
    bar = 0,
    text = 0,
}

local clearVisualCount = 0
local buttonHideCount = 0
local rangeUpdateCount = 0
local previewCount = 0
local combatActive = false

function wipe(tbl)
    if not tbl then return end
    for key in pairs(tbl) do
        tbl[key] = nil
    end
end

function InCombatLockdown()
    return combatActive
end

function issecretvalue()
    return false
end

C_Secrets = {
    GetSpellCooldownSecrecy = function()
        return false
    end,
}

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
        protected = false,
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
        if self._isTestButton then
            buttonHideCount = buttonHideCount + 1
        end
    end

    function frame:IsShown()
        return self.shown
    end

    function frame:SetShown(shown)
        self.shown = shown and true or false
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
        return self.protected
    end

    function frame:ClearAllPoints()
        wipe(self.points)
    end

    function frame:SetPoint(...)
        self.points[#self.points + 1] = {...}
    end

    function frame:SetAllPoints()
        self.allPoints = true
    end

    function frame:AdjustPointsOffset(dx, dy)
        self.adjustedX = (self.adjustedX or 0) + dx
        self.adjustedY = (self.adjustedY or 0) + dy
    end

    function frame:SetFrameStrata(strata)
        self.frameStrata = strata
    end

    function frame:GetFrameStrata()
        return self.frameStrata
    end

    function frame:SetFixedFrameStrata(fixed)
        self.fixedFrameStrata = fixed
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

    function frame:EnableMouse(enabled)
        self.mouseEnabled = enabled
    end

    function frame:RegisterForDrag(...)
        self.dragButtons = {...}
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
        local child = NewFrame((self.name or "Frame") .. "Texture", self)
        function child:SetColorTexture(r, g, b, a)
            self.color = { r, g, b, a }
        end
        return child
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
    button.releasedAuraVisual = true
end

function CooldownCompanion:UpdateButtonIcon(button)
    button.updatedIcon = true
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
        availableQuantity = 1,
        quantityKind = "stacks",
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

function ST._ClearButtonVisualState(button)
    clearVisualCount = clearVisualCount + 1
    button.visualStateCleared = true
end

function ST._UnregisterKeyPressHighlightButton(button)
    button.unregisteredKph = true
end

function ST._CacheButtonBindingKeys(button, buttonData)
    button._bindingKeyInfos = { buttonData and buttonData.id or nil }
end

assert(loadfile("Core/GroupFrame.lua"))("CooldownCompanion", ST)

function CooldownCompanion:IsButtonUsable(buttonData)
    return buttonData.usable ~= false
end

function CooldownCompanion:UpdateGroupClickthrough()
end

function CooldownCompanion:ApplyConfigPreviewsToGroup()
    previewCount = previewCount + 1
end

function CooldownCompanion:UpdateRangeCheckRegistrations()
    rangeUpdateCount = rangeUpdateCount + 1
end

function CooldownCompanion:GetGroupLayoutButtonCount()
    return self._testLayoutButtonCount or 0
end

function CooldownCompanion:AddButtonToMasque(_, button)
    button.masqueAdded = (button.masqueAdded or 0) + 1
    button.masqueActive = true
end

function CooldownCompanion:RemoveButtonFromMasque(_, button)
    button.masqueRemoved = (button.masqueRemoved or 0) + 1
    button.masqueActive = nil
end

local function NewButtonFrame(kind, parent, index, buttonData, style)
    local button = NewFrame(kind .. tostring(constructorCounts[kind]), parent)
    button._isTestButton = true
    button.kind = kind
    button.index = index
    button.buttonData = buttonData
    button.style = style or {}
    button._groupId = parent.groupId
    button.icon = NewFrame(button.name .. "Icon", button)
    button.iconFill = NewFrame(button.name .. "IconFill", button)
    button.cooldown = NewFrame(button.name .. "Cooldown", button)
    button.locCooldown = NewFrame(button.name .. "LocCooldown", button)
    button.iconGCDCooldown = NewFrame(button.name .. "GCDCooldown", button)
    button.auraBlizzardCooldown = NewFrame(button.name .. "AuraCooldown", button)
    button.count = NewFrame(button.name .. "Count", button)
    button.auraStackCount = NewFrame(button.name .. "AuraStack", button)
    button.bg = NewFrame(button.name .. "Bg", button)
    button.borderTextures = { NewFrame(button.name .. "Border1", button) }
    if kind == "icon" and style and style.separateTextPositions and buttonData and buttonData.auraTracking and not buttonData.isPassive then
        button.secondaryCooldown = NewFrame(button.name .. "SecondaryCooldown", button)
    end
    function button:UpdateStyle(newStyle)
        ST._ClearButtonVisualState(self)
        self.style = newStyle
        self.styleUpdates = (self.styleUpdates or 0) + 1
        self:SetAlpha(1)
        self._lastVisAlpha = 1
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
    frame:Show()
    function frame:UpdateCooldowns()
        self.updateCooldownsCount = (self.updateCooldownsCount or 0) + 1
        for _, button in ipairs(self.buttons) do
            button:UpdateCooldown()
        end
    end
    return frame
end

local function ResetGroup(displayMode, buttons, style, extra)
    extra = extra or {}
    CooldownCompanion.db.profile.groups[1] = {
        name = "Style Fast Path Test",
        displayMode = displayMode or "icons",
        buttons = buttons,
        style = style or {
            buttonSize = 32,
            buttonSpacing = 2,
            buttonsPerRow = 12,
        },
        masqueEnabled = extra.masqueEnabled,
        parentContainerId = extra.parentContainerId,
        compactLayout = extra.compactLayout,
    }
end

local function ResetFrame()
    local frame = NewGroupFrame(1)
    CooldownCompanion.groupFrames[1] = frame
    CooldownCompanion._pendingFullRefresh = nil
    combatActive = false
    return frame
end

local function PointX(button)
    return button.points[1] and button.points[1][4] or nil
end

local frame = ResetFrame()
ResetGroup("icons", {
    { id = 101, type = "spell" },
    { id = 102, type = "spell" },
})
CooldownCompanion:PopulateGroupButtons(1)
AssertEqual(constructorCounts.icon, 2, "initial populate should create icon buttons")
local firstButton = frame.buttons[1]
local secondButton = frame.buttons[2]
local releaseBeforeStyle = buttonHideCount
local previewBeforeStyle = previewCount
local rangeBeforeStyle = rangeUpdateCount
local cooldownsBeforeStyle = frame.updateCooldownsCount
CooldownCompanion.db.profile.groups[1].style.buttonSize = 40
CooldownCompanion.db.profile.groups[1].style.buttonSpacing = 3
CooldownCompanion:UpdateGroupStyle(1)
AssertEqual(constructorCounts.icon, 2, "compatible style update should not create icon buttons")
AssertEqual(buttonHideCount, releaseBeforeStyle, "compatible style update should not release active buttons")
AssertEqual(frame.buttons[1], firstButton, "compatible style update should keep first active button")
AssertEqual(frame.buttons[2], secondButton, "compatible style update should keep second active button")
AssertEqual(firstButton.styleUpdates, 1, "compatible style update should refresh first button style")
AssertEqual(secondButton.styleUpdates, 1, "compatible style update should refresh second button style")
AssertEqual(PointX(secondButton), 43, "compatible style update should relayout second button")
AssertEqual(frame.visibleButtonCount, 2, "compatible style update should refresh visible button count")
AssertEqual(frame._lastVisibleCount, 2, "compatible style update should refresh last visible count")
assert(frame.updateCooldownsCount > cooldownsBeforeStyle, "compatible style update should refresh cooldown/visibility state")
assert(previewCount > previewBeforeStyle, "compatible style update should apply config previews")
assert(rangeUpdateCount > rangeBeforeStyle, "compatible style update should refresh range registrations")
AssertEqual(firstButton.frameStrata, "MEDIUM", "compatible style update should propagate strata")

frame = ResetFrame()
ResetGroup("icons", {
    { id = 201, type = "spell", usable = false },
    { id = 202, type = "spell" },
    { id = 203, type = "spell" },
})
CooldownCompanion:PopulateGroupButtons(1)
AssertEqual(frame.buttons[1].index, 2, "populate should preserve source index after unusable row")
AssertEqual(frame.buttons[2].index, 3, "populate should preserve second visible source index")
releaseBeforeStyle = buttonHideCount
CooldownCompanion.db.profile.groups[1].style.buttonSize = 44
CooldownCompanion:UpdateGroupStyle(1)
AssertEqual(buttonHideCount, releaseBeforeStyle, "source-index compatible style update should stay on fast path")
AssertEqual(frame.buttons[1].index, 2, "style fast path should preserve first visible source index")
AssertEqual(frame.buttons[2].index, 3, "style fast path should preserve second visible source index")

frame = ResetFrame()
ResetGroup("bars", {
    { id = 251, type = "spell" },
    { id = 252, type = "spell" },
}, {
    barLength = 160,
    barHeight = 18,
    buttonSpacing = 2,
})
CooldownCompanion:PopulateGroupButtons(1)
firstButton = frame.buttons[1]
releaseBeforeStyle = buttonHideCount
CooldownCompanion.db.profile.groups[1].style.barLength = 220
CooldownCompanion:UpdateGroupStyle(1)
AssertEqual(buttonHideCount, releaseBeforeStyle, "bar style update should stay on fast path")
AssertEqual(frame.buttons[1], firstButton, "bar style update should keep active button")
AssertEqual(firstButton.styleUpdates, 1, "bar style update should restyle active button")

frame = ResetFrame()
ResetGroup("text", {
    { id = 261, type = "spell" },
}, {
    textWidth = 150,
    textHeight = 18,
    buttonSpacing = 2,
    showTextGroupHeader = false,
})
CooldownCompanion:PopulateGroupButtons(1)
firstButton = frame.buttons[1]
releaseBeforeStyle = buttonHideCount
CooldownCompanion.db.profile.groups[1].style.textWidth = 180
CooldownCompanion:UpdateGroupStyle(1)
AssertEqual(buttonHideCount, releaseBeforeStyle, "text style update should stay on fast path when header visibility is unchanged")
AssertEqual(frame.buttons[1], firstButton, "text style update should keep active button")
AssertEqual(firstButton.styleUpdates, 1, "text style update should restyle active button")

frame = ResetFrame()
ResetGroup("icons", {
    { id = 301, type = "spell" },
    { id = 302, type = "spell" },
})
CooldownCompanion:PopulateGroupButtons(1)
releaseBeforeStyle = buttonHideCount
CooldownCompanion.db.profile.groups[1].buttons[#CooldownCompanion.db.profile.groups[1].buttons + 1] = { id = 303, type = "spell" }
CooldownCompanion:UpdateGroupStyle(1)
assert(buttonHideCount > releaseBeforeStyle, "rendered sequence change should fall back to populate")
AssertEqual(#frame.buttons, 3, "fallback should rebuild active button sequence")

frame = ResetFrame()
ResetGroup("icons", {
    { id = 311, type = "spell" },
})
CooldownCompanion:PopulateGroupButtons(1)
releaseBeforeStyle = buttonHideCount
local barConstructorsBefore = constructorCounts.bar
CooldownCompanion.db.profile.groups[1].displayMode = "bars"
CooldownCompanion:UpdateGroupStyle(1)
assert(buttonHideCount > releaseBeforeStyle, "display-mode change should fall back to populate")
assert(constructorCounts.bar > barConstructorsBefore, "display-mode fallback should create a bar button")
AssertEqual(frame.buttons[1].kind, "bar", "display-mode fallback should rebuild with bar buttons")

frame = ResetFrame()
ResetGroup("icons", {
    { id = 321, type = "spell", auraTracking = true },
})
CooldownCompanion:PopulateGroupButtons(1)
AssertEqual(frame.buttons[1].secondaryCooldown, nil, "plain icon populate should not create a secondary cooldown")
releaseBeforeStyle = buttonHideCount
CooldownCompanion.db.profile.groups[1].style.separateTextPositions = true
CooldownCompanion:UpdateGroupStyle(1)
assert(buttonHideCount > releaseBeforeStyle, "secondary cooldown pool-key change should fall back to populate")
assert(frame.buttons[1].secondaryCooldown, "secondary cooldown fallback should rebuild with secondary cooldown support")

frame = ResetFrame()
ResetGroup("text", {
    { id = 331, type = "spell" },
}, {
    textWidth = 150,
    textHeight = 18,
    buttonSpacing = 2,
    showTextGroupHeader = false,
})
CooldownCompanion:PopulateGroupButtons(1)
releaseBeforeStyle = buttonHideCount
CooldownCompanion.db.profile.groups[1].style.showTextGroupHeader = true
CooldownCompanion:UpdateGroupStyle(1)
assert(buttonHideCount > releaseBeforeStyle, "text-header visibility change should fall back to populate")
AssertEqual(frame._textHeaderShown, true, "text-header fallback should rebuild header state")

frame = ResetFrame()
CooldownCompanion._testLayoutButtonCount = 5
ResetGroup("icons", {
    { id = 341, type = "spell" },
    { id = 342, type = "spell" },
}, nil, { parentContainerId = 900, compactLayout = false })
CooldownCompanion:PopulateGroupButtons(1)
releaseBeforeStyle = buttonHideCount
CooldownCompanion._testLayoutButtonCount = 7
CooldownCompanion.db.profile.groups[1].style.buttonSpacing = 6
CooldownCompanion:UpdateGroupStyle(1)
AssertEqual(buttonHideCount, releaseBeforeStyle, "container style update should stay on fast path")
AssertEqual(frame.layoutButtonCount, 7, "container style update should refresh layout button count")
CooldownCompanion._testLayoutButtonCount = nil

frame = ResetFrame()
ResetGroup("textures", {
    { id = 401, type = "spell" },
})
CooldownCompanion:PopulateGroupButtons(1)
AssertEqual(frame.buttons[1]:GetAlpha(), 0, "texture populate should hide anchor button alpha")
releaseBeforeStyle = buttonHideCount
CooldownCompanion.db.profile.groups[1].style.buttonSize = 48
CooldownCompanion:UpdateGroupStyle(1)
AssertEqual(buttonHideCount, releaseBeforeStyle, "texture style update should stay on fast path")
AssertEqual(frame.buttons[1]:GetAlpha(), 0, "texture style fast path should restore hidden alpha")
AssertEqual(frame.buttons[1]._lastVisAlpha, 0, "texture style fast path should restore hidden alpha cache")

frame = ResetFrame()
ResetGroup("trigger", {
    { id = 451, type = "spell" },
})
CooldownCompanion:PopulateGroupButtons(1)
AssertEqual(frame.buttons[1]:GetAlpha(), 0, "trigger populate should hide anchor button alpha")
releaseBeforeStyle = buttonHideCount
CooldownCompanion.db.profile.groups[1].style.buttonSize = 49
CooldownCompanion:UpdateGroupStyle(1)
AssertEqual(buttonHideCount, releaseBeforeStyle, "trigger style update should stay on fast path")
AssertEqual(frame.buttons[1]:GetAlpha(), 0, "trigger style fast path should restore hidden alpha")
AssertEqual(frame.buttons[1]._lastVisAlpha, 0, "trigger style fast path should restore hidden alpha cache")

frame = ResetFrame()
CooldownCompanion.Masque = true
ResetGroup("icons", {
    { id = 501, type = "spell" },
}, nil, { masqueEnabled = true })
CooldownCompanion.MasqueGroups[1] = {}
CooldownCompanion:PopulateGroupButtons(1)
local masqueButton = frame.buttons[1]
local masqueAddsBefore = masqueButton.masqueAdded or 0
local masqueRemovesBefore = masqueButton.masqueRemoved or 0
releaseBeforeStyle = buttonHideCount
CooldownCompanion.db.profile.groups[1].style.buttonSize = 50
CooldownCompanion:UpdateGroupStyle(1)
assert(buttonHideCount > releaseBeforeStyle, "Masque-enabled icon style update should use rebuild fallback")
assert((masqueButton.masqueRemoved or 0) > masqueRemovesBefore, "Masque fallback should remove the pooled button from Masque")
assert((masqueButton.masqueAdded or 0) > masqueAddsBefore, "Masque fallback should add the rebuilt button to Masque")
AssertEqual(masqueButton.masqueActive, true, "Masque fallback should leave the rebuilt button registered")
CooldownCompanion.Masque = nil
CooldownCompanion.MasqueGroups[1] = nil

frame = ResetFrame()
ResetGroup("icons", {
    { id = 601, type = "spell" },
    { id = 602, type = "spell" },
})
CooldownCompanion:PopulateGroupButtons(1)
frame.protected = true
combatActive = true
local styleUpdatesBeforeCombat = (frame.buttons[1].styleUpdates or 0) + (frame.buttons[2].styleUpdates or 0)
local releaseBeforeCombat = buttonHideCount
local pointBeforeCombat = PointX(frame.buttons[2])
CooldownCompanion.db.profile.groups[1].displayMode = "bars"
CooldownCompanion:UpdateGroupStyle(1)
AssertEqual(CooldownCompanion._pendingFullRefresh, true, "protected combat style update should defer full refresh")
AssertEqual((frame.buttons[1].styleUpdates or 0) + (frame.buttons[2].styleUpdates or 0), styleUpdatesBeforeCombat, "protected combat style update should not restyle buttons")
AssertEqual(buttonHideCount, releaseBeforeCombat, "protected combat style update should not release buttons")
AssertEqual(PointX(frame.buttons[2]), pointBeforeCombat, "protected combat style update should not relayout buttons")

print("group-style-update-fast-path ok")
