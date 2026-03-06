--[[
    CooldownCompanion - Config/TalentPicker.lua: Visual talent tree picker popup
    for selecting a per-button talent condition.
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon

local ipairs = ipairs
local pairs = pairs
local math_min = math.min
local math_max = math.max
local math_floor = math.floor

------------------------------------------------------------------------
-- CONSTANTS
------------------------------------------------------------------------
local FRAME_WIDTH = 620
local FRAME_HEIGHT = 520
local NODE_SIZE = 30
local NODE_PADDING = 20  -- extra padding around bounding box edges
local CHOICE_ICON_SIZE = 22
local CHOICE_ICON_GAP = 2

-- Colors
local COLOR_BORDER_TAKEN    = { 0.3, 0.85, 0.3, 1 }
local COLOR_BORDER_NOTTAKEN = { 0.4, 0.4, 0.4, 0.7 }
local COLOR_BORDER_SELECTED = { 1.0, 0.82, 0.0, 1 }
local COLOR_BG              = { 0.08, 0.08, 0.12, 0.95 }
local COLOR_TITLE_BG        = { 0.15, 0.15, 0.2, 1 }

------------------------------------------------------------------------
-- FRAME POOL
------------------------------------------------------------------------
local pickerFrame = nil
local nodeButtons = {}
local choiceButtons = {}
local onSelectCallback = nil

------------------------------------------------------------------------
-- HELPERS
------------------------------------------------------------------------
local function SetBorderColor(tex, color)
    tex:SetColorTexture(color[1], color[2], color[3], color[4])
end

local function CreateNodeButton(parent, index)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(NODE_SIZE, NODE_SIZE)

    -- Icon
    btn.icon = btn:CreateTexture(nil, "ARTWORK")
    btn.icon:SetPoint("TOPLEFT", 2, -2)
    btn.icon:SetPoint("BOTTOMRIGHT", -2, 2)
    btn.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    -- Border (4 edge textures)
    btn.borders = {}
    local bSize = 2
    local b
    b = btn:CreateTexture(nil, "BORDER"); b:SetPoint("TOPLEFT", 0, 0); b:SetPoint("TOPRIGHT", 0, 0); b:SetHeight(bSize)
    btn.borders[1] = b
    b = btn:CreateTexture(nil, "BORDER"); b:SetPoint("BOTTOMLEFT", 0, 0); b:SetPoint("BOTTOMRIGHT", 0, 0); b:SetHeight(bSize)
    btn.borders[2] = b
    b = btn:CreateTexture(nil, "BORDER"); b:SetPoint("TOPLEFT", 0, 0); b:SetPoint("BOTTOMLEFT", 0, 0); b:SetWidth(bSize)
    btn.borders[3] = b
    b = btn:CreateTexture(nil, "BORDER"); b:SetPoint("TOPRIGHT", 0, 0); b:SetPoint("BOTTOMRIGHT", 0, 0); b:SetWidth(bSize)
    btn.borders[4] = b

    -- Highlight
    btn.highlight = btn:CreateTexture(nil, "HIGHLIGHT")
    btn.highlight:SetAllPoints()
    btn.highlight:SetColorTexture(1, 1, 1, 0.15)

    btn:SetScript("OnEnter", function(self)
        if self._talentName then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(self._talentName, 1, 1, 1)
            if self._rankText then
                GameTooltip:AddLine(self._rankText, 0.7, 0.7, 0.7)
            end
            if self._isChoiceNode then
                GameTooltip:AddLine("Click to see choices", 0.5, 0.8, 1)
            end
            GameTooltip:Show()
        end
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    return btn
end

local function CreateChoiceButton(parent)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(CHOICE_ICON_SIZE, CHOICE_ICON_SIZE)

    btn.icon = btn:CreateTexture(nil, "ARTWORK")
    btn.icon:SetPoint("TOPLEFT", 2, -2)
    btn.icon:SetPoint("BOTTOMRIGHT", -2, 2)
    btn.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    btn.borders = {}
    local bSize = 2
    local b
    b = btn:CreateTexture(nil, "BORDER"); b:SetPoint("TOPLEFT", 0, 0); b:SetPoint("TOPRIGHT", 0, 0); b:SetHeight(bSize)
    btn.borders[1] = b
    b = btn:CreateTexture(nil, "BORDER"); b:SetPoint("BOTTOMLEFT", 0, 0); b:SetPoint("BOTTOMRIGHT", 0, 0); b:SetHeight(bSize)
    btn.borders[2] = b
    b = btn:CreateTexture(nil, "BORDER"); b:SetPoint("TOPLEFT", 0, 0); b:SetPoint("BOTTOMLEFT", 0, 0); b:SetWidth(bSize)
    btn.borders[3] = b
    b = btn:CreateTexture(nil, "BORDER"); b:SetPoint("TOPRIGHT", 0, 0); b:SetPoint("BOTTOMRIGHT", 0, 0); b:SetWidth(bSize)
    btn.borders[4] = b

    btn.highlight = btn:CreateTexture(nil, "HIGHLIGHT")
    btn.highlight:SetAllPoints()
    btn.highlight:SetColorTexture(1, 1, 1, 0.15)

    btn:SetScript("OnEnter", function(self)
        if self._spellID then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetSpellByID(self._spellID)
            GameTooltip:Show()
        elseif self._talentName then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(self._talentName, 1, 1, 1)
            GameTooltip:Show()
        end
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    return btn
end

local function SetNodeBorderColor(btn, color)
    for _, border in ipairs(btn.borders) do
        SetBorderColor(border, color)
    end
end

------------------------------------------------------------------------
-- CHOICE SUBMENU
------------------------------------------------------------------------
local choiceFrame = nil

local function HideChoiceFrame()
    if choiceFrame then
        choiceFrame:Hide()
    end
end

local function ShowChoiceFrame(parentBtn, entries, nodeID, currentEntryID)
    if not choiceFrame then
        choiceFrame = CreateFrame("Frame", nil, pickerFrame, "BackdropTemplate")
        choiceFrame:SetBackdrop({
            bgFile = "Interface\\BUTTONS\\WHITE8X8",
            edgeFile = "Interface\\BUTTONS\\WHITE8X8",
            edgeSize = 1,
        })
        choiceFrame:SetBackdropColor(0.12, 0.12, 0.18, 0.98)
        choiceFrame:SetBackdropBorderColor(0.4, 0.4, 0.5, 1)
        choiceFrame:SetFrameStrata("FULLSCREEN_DIALOG")
    end

    -- Hide previous choice buttons
    for _, cb in ipairs(choiceButtons) do
        cb:Hide()
    end

    local count = #entries
    local totalWidth = count * CHOICE_ICON_SIZE + (count - 1) * CHOICE_ICON_GAP + 12
    choiceFrame:SetSize(totalWidth, CHOICE_ICON_SIZE + 10)
    choiceFrame:ClearAllPoints()
    choiceFrame:SetPoint("TOP", parentBtn, "BOTTOM", 0, -4)
    choiceFrame:Show()

    for i, entry in ipairs(entries) do
        local cb = choiceButtons[i]
        if not cb then
            cb = CreateChoiceButton(choiceFrame)
            choiceButtons[i] = cb
        end

        cb:SetParent(choiceFrame)
        cb:ClearAllPoints()
        cb:SetPoint("LEFT", choiceFrame, "LEFT", 6 + (i - 1) * (CHOICE_ICON_SIZE + CHOICE_ICON_GAP), 0)
        cb:Show()

        cb.icon:SetTexture(entry.icon)
        cb.icon:SetDesaturated(not entry.isTaken)
        if not entry.isTaken then
            cb.icon:SetVertexColor(0.6, 0.6, 0.6)
        else
            cb.icon:SetVertexColor(1, 1, 1)
        end

        local borderColor = COLOR_BORDER_NOTTAKEN
        if entry.entryID == currentEntryID then
            borderColor = COLOR_BORDER_SELECTED
        elseif entry.isTaken then
            borderColor = COLOR_BORDER_TAKEN
        end
        SetNodeBorderColor(cb, borderColor)

        cb._talentName = entry.name
        cb._spellID = entry.spellID

        cb:SetScript("OnClick", function()
            HideChoiceFrame()
            if onSelectCallback then
                onSelectCallback({
                    nodeID = nodeID,
                    entryID = entry.entryID,
                    spellID = entry.spellID,
                    talentName = entry.name,
                })
            end
            pickerFrame:Hide()
        end)
    end
end

------------------------------------------------------------------------
-- MAIN FRAME CREATION
------------------------------------------------------------------------
local function EnsurePickerFrame()
    if pickerFrame then return end

    pickerFrame = CreateFrame("Frame", "CooldownCompanionTalentPicker", UIParent, "BackdropTemplate")
    pickerFrame:SetSize(FRAME_WIDTH, FRAME_HEIGHT)
    pickerFrame:SetPoint("CENTER")
    pickerFrame:SetFrameStrata("FULLSCREEN_DIALOG")
    pickerFrame:SetMovable(true)
    pickerFrame:EnableMouse(true)
    pickerFrame:SetClampedToScreen(true)
    pickerFrame:SetBackdrop({
        bgFile = "Interface\\BUTTONS\\WHITE8X8",
        edgeFile = "Interface\\BUTTONS\\WHITE8X8",
        edgeSize = 1,
    })
    pickerFrame:SetBackdropColor(COLOR_BG[1], COLOR_BG[2], COLOR_BG[3], COLOR_BG[4])
    pickerFrame:SetBackdropBorderColor(0.3, 0.3, 0.4, 1)
    pickerFrame:Hide()

    -- Title bar
    local titleBar = CreateFrame("Frame", nil, pickerFrame, "BackdropTemplate")
    titleBar:SetHeight(28)
    titleBar:SetPoint("TOPLEFT", 0, 0)
    titleBar:SetPoint("TOPRIGHT", 0, 0)
    titleBar:SetBackdrop({ bgFile = "Interface\\BUTTONS\\WHITE8X8" })
    titleBar:SetBackdropColor(COLOR_TITLE_BG[1], COLOR_TITLE_BG[2], COLOR_TITLE_BG[3], COLOR_TITLE_BG[4])
    titleBar:EnableMouse(true)
    titleBar:RegisterForDrag("LeftButton")
    titleBar:SetScript("OnDragStart", function() pickerFrame:StartMoving() end)
    titleBar:SetScript("OnDragStop", function() pickerFrame:StopMovingOrSizing() end)

    local titleText = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    titleText:SetPoint("CENTER", titleBar, "CENTER", 0, 0)
    titleText:SetText("Pick a Talent")
    pickerFrame.titleText = titleText

    -- Close button
    local closeBtn = CreateFrame("Button", nil, titleBar, "UIPanelCloseButtonNoScripts")
    closeBtn:SetPoint("TOPRIGHT", titleBar, "TOPRIGHT", 0, 0)
    closeBtn:SetScript("OnClick", function() pickerFrame:Hide() end)

    -- Scroll frame for node content
    local scrollFrame = CreateFrame("ScrollFrame", nil, pickerFrame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", titleBar, "BOTTOMLEFT", 8, -8)
    scrollFrame:SetPoint("BOTTOMRIGHT", pickerFrame, "BOTTOMRIGHT", -28, 44)

    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetSize(1, 1) -- sized dynamically
    scrollFrame:SetScrollChild(scrollChild)
    pickerFrame.scrollChild = scrollChild
    pickerFrame.scrollFrame = scrollFrame

    -- Bottom buttons
    local clearBtn = CreateFrame("Button", nil, pickerFrame, "UIPanelButtonTemplate")
    clearBtn:SetSize(100, 24)
    clearBtn:SetPoint("BOTTOMLEFT", 12, 10)
    clearBtn:SetText("Clear")
    clearBtn:SetScript("OnClick", function()
        if onSelectCallback then
            onSelectCallback(nil)
        end
        pickerFrame:Hide()
    end)
    pickerFrame.clearBtn = clearBtn

    local cancelBtn = CreateFrame("Button", nil, pickerFrame, "UIPanelButtonTemplate")
    cancelBtn:SetSize(100, 24)
    cancelBtn:SetPoint("BOTTOMRIGHT", -12, 10)
    cancelBtn:SetText("Cancel")
    cancelBtn:SetScript("OnClick", function() pickerFrame:Hide() end)

    -- Escape key to close
    pickerFrame:SetScript("OnKeyDown", function(self, key)
        if key == "ESCAPE" then
            self:SetPropagateKeyboardInput(false)
            self:Hide()
        else
            self:SetPropagateKeyboardInput(true)
        end
    end)

    pickerFrame:SetScript("OnHide", function()
        HideChoiceFrame()
        onSelectCallback = nil
    end)

    tinsert(UISpecialFrames, "CooldownCompanionTalentPicker")
end

------------------------------------------------------------------------
-- POPULATE TREE
------------------------------------------------------------------------
local function GetEntryDisplayInfo(configID, entryID)
    local entryInfo = C_Traits.GetEntryInfo(configID, entryID)
    if not entryInfo or not entryInfo.definitionID then return nil end

    local defInfo = C_Traits.GetDefinitionInfo(entryInfo.definitionID)
    if not defInfo then return nil end

    local spellID = defInfo.spellID
    local name = defInfo.overrideName
    local icon = defInfo.overrideIcon

    if spellID then
        if not name then
            local spellInfo = C_Spell.GetSpellInfo(spellID)
            name = spellInfo and spellInfo.name
        end
        if not icon then
            icon = C_Spell.GetSpellTexture(spellID)
        end
    end

    return {
        entryID = entryID,
        definitionID = entryInfo.definitionID,
        spellID = spellID,
        name = name or ("Entry " .. entryID),
        icon = icon or 134400,
    }
end

local function PopulateTree(currentNodeID, currentEntryID)
    local scrollChild = pickerFrame.scrollChild

    -- Hide all existing buttons
    for _, btn in ipairs(nodeButtons) do
        btn:Hide()
    end
    for _, cb in ipairs(choiceButtons) do
        cb:Hide()
    end
    HideChoiceFrame()

    local configID = C_ClassTalents.GetActiveConfigID()
    if not configID then return end

    local specID = CooldownCompanion._currentSpecId
    if not specID then return end

    local treeID = C_ClassTalents.GetTraitTreeForSpec(specID)
    if not treeID then return end

    local nodeIDs = C_Traits.GetTreeNodes(treeID)
    if not nodeIDs then return end

    -- Gather visible class/spec nodes (exclude hero talent subtrees)
    local nodes = {}
    local minX, maxX, minY, maxY = math.huge, -math.huge, math.huge, -math.huge

    for _, nodeID in ipairs(nodeIDs) do
        local nodeInfo = C_Traits.GetNodeInfo(configID, nodeID)
        if nodeInfo and nodeInfo.isVisible and not nodeInfo.subTreeID
           and nodeInfo.type ~= Enum.TraitNodeType.SubTreeSelection then
            local px = nodeInfo.posX / 10
            local py = nodeInfo.posY / 10

            -- Build entry display info
            local entries = {}
            if nodeInfo.entryIDs then
                for _, eid in ipairs(nodeInfo.entryIDs) do
                    local displayInfo = GetEntryDisplayInfo(configID, eid)
                    if displayInfo then
                        displayInfo.isTaken = (nodeInfo.activeEntry
                            and nodeInfo.activeEntry.entryID == eid
                            and nodeInfo.activeRank > 0)
                        entries[#entries + 1] = displayInfo
                    end
                end
            end

            if #entries > 0 then
                local isChoice = (nodeInfo.type == Enum.TraitNodeType.Selection)
                nodes[#nodes + 1] = {
                    nodeID = nodeID,
                    px = px,
                    py = py,
                    activeRank = nodeInfo.activeRank or 0,
                    maxRanks = nodeInfo.maxRanks or 1,
                    activeEntryID = nodeInfo.activeEntry and nodeInfo.activeEntry.entryID or nil,
                    entries = entries,
                    isChoice = isChoice,
                    nodeType = nodeInfo.type,
                }

                if px < minX then minX = px end
                if px > maxX then maxX = px end
                if py < minY then minY = py end
                if py > maxY then maxY = py end
            end
        end
    end

    if #nodes == 0 then return end

    -- Calculate scaling to fit within the scroll child area
    local treeWidth = maxX - minX + NODE_SIZE
    local treeHeight = maxY - minY + NODE_SIZE
    local availWidth = FRAME_WIDTH - 50
    local availHeight = FRAME_HEIGHT - 100

    local scaleX = treeWidth > 0 and (availWidth - NODE_PADDING * 2) / treeWidth or 1
    local scaleY = treeHeight > 0 and (availHeight - NODE_PADDING * 2) / treeHeight or 1
    local scale = math_min(scaleX, scaleY, 1.0)

    local contentWidth = treeWidth * scale + NODE_PADDING * 2
    local contentHeight = treeHeight * scale + NODE_PADDING * 2
    scrollChild:SetSize(math_max(contentWidth, availWidth), math_max(contentHeight, availHeight))

    -- Place node buttons
    for i, node in ipairs(nodes) do
        local btn = nodeButtons[i]
        if not btn then
            btn = CreateNodeButton(scrollChild, i)
            nodeButtons[i] = btn
        end

        local x = (node.px - minX) * scale + NODE_PADDING
        local y = (node.py - minY) * scale + NODE_PADDING

        btn:SetParent(scrollChild)
        btn:ClearAllPoints()
        btn:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", x, -y)
        btn:Show()

        -- Display: use first entry's icon for single/tiered nodes
        local primaryEntry = node.entries[1]
        if node.isChoice and node.activeEntryID then
            for _, entry in ipairs(node.entries) do
                if entry.entryID == node.activeEntryID then
                    primaryEntry = entry
                    break
                end
            end
        end

        btn.icon:SetTexture(primaryEntry.icon)
        local isTaken = node.activeRank > 0
        btn.icon:SetDesaturated(not isTaken)
        if not isTaken then
            btn.icon:SetVertexColor(0.6, 0.6, 0.6)
        else
            btn.icon:SetVertexColor(1, 1, 1)
        end

        btn._talentName = primaryEntry.name
        btn._isChoiceNode = node.isChoice
        btn._rankText = (node.activeRank .. "/" .. node.maxRanks)

        -- Border color: selected > taken > not taken
        local borderColor = COLOR_BORDER_NOTTAKEN
        if node.nodeID == currentNodeID then
            borderColor = COLOR_BORDER_SELECTED
        elseif isTaken then
            borderColor = COLOR_BORDER_TAKEN
        end
        SetNodeBorderColor(btn, borderColor)

        -- Click handler
        local nodeRef = node
        btn:SetScript("OnClick", function(self)
            if nodeRef.isChoice and #nodeRef.entries > 1 then
                -- Show choice submenu
                ShowChoiceFrame(self, nodeRef.entries, nodeRef.nodeID, currentEntryID)
            else
                -- Single/tiered node: select directly
                HideChoiceFrame()
                if onSelectCallback then
                    onSelectCallback({
                        nodeID = nodeRef.nodeID,
                        entryID = nil,
                        spellID = primaryEntry.spellID,
                        talentName = primaryEntry.name,
                    })
                end
                pickerFrame:Hide()
            end
        end)
    end
end

------------------------------------------------------------------------
-- PUBLIC API
------------------------------------------------------------------------

-- Open the talent picker popup.
-- callback(result): called with { nodeID, entryID, spellID, talentName } or nil (clear).
-- currentNodeID/currentEntryID: highlight current selection.
function CooldownCompanion:OpenTalentPicker(callback, currentNodeID, currentEntryID)
    EnsurePickerFrame()
    onSelectCallback = callback
    pickerFrame:Show()
    PopulateTree(currentNodeID, currentEntryID)
end

function CooldownCompanion:IsTalentPickerOpen()
    return pickerFrame and pickerFrame:IsShown()
end
