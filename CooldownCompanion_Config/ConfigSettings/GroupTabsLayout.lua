local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon
local AceGUI = LibStub("AceGUI-3.0")
local CS = ST._configState
local tonumber = tonumber

-- Imports from Helpers.lua
local BuildCollapsibleSection = ST._BuildCollapsibleSection
local CreateInfoButton = ST._CreateInfoButton
local AddAnchorDropdown = ST._AddAnchorDropdown
local AddOffsetSliders = ST._AddOffsetSliders
local GetCompactGrowthDirectionLabels = ST._GetCompactGrowthDirectionLabels
local NormalizeCompactGrowthDirection = ST._NormalizeCompactGrowthDirection

-- Imports from RowWidgets.lua (the row grammar)
local AddCheckboxRow = ST._AddCheckboxRow
local AddSliderRow = ST._AddSliderRow
local AddDropdownRow = ST._AddDropdownRow
local AnchorRowBadge = ST._AnchorRowBadge
local BeginRowGrid = ST._BeginRowGrid
local AddEditBoxRow = ST._AddEditBoxRow

-- Imports from GroupTabsShared.lua
local WireMirrorFirstSlider = ST._WireMirrorFirstSlider

-- Imports from GroupTabsSpecial.lua
local GetStandaloneTextureSettings = ST._GetStandaloneTextureSettings
local OpenOrRebindStandaloneTexturePicker = ST._OpenOrRebindStandaloneTexturePicker

-- A dropdown sizes its menu from the 140px control it hangs under, which is
-- too narrow for user-named panels and the longer worded options below.
local WIDE_PULLOUT_WIDTH = 300

-- Row-grammar section headers: caret far left, label, then a class-colored
-- rule fading right.
local ROW_SECTION = { leftAligned = true }

local tabInfoButtons = CS.tabInfoButtons
local appearanceTabElements = CS.appearanceTabElements

local function BuildLayoutTab(container)
    for _, elem in ipairs(appearanceTabElements) do
        elem:ClearAllPoints()
        elem:Hide()
        elem:SetParent(nil)
    end
    wipe(appearanceTabElements)

    if not CS.selectedGroup then return end
    local group = CooldownCompanion.db.profile.groups[CS.selectedGroup]
    if not group then return end
    local style = group.style
    local function IsResolvedExternalFrameAnchorTarget(frameName)
        if type(frameName) ~= "string" or frameName == "" or frameName == "UIParent" then
            return false
        end
        if CooldownCompanion.ParseAddonAnchorFrameName
            and CooldownCompanion:ParseAddonAnchorFrameName(frameName) ~= nil then
            return false
        end
        local target = _G[frameName]
        return type(target) == "table" and type(target.GetObjectType) == "function"
    end
    CooldownCompanion:ClearAllTextureIndicatorPreviews()
    if CooldownCompanion.ClearAllTriggerPanelEffectPreviews then
        CooldownCompanion:ClearAllTriggerPanelEffectPreviews()
    end

    if group.displayMode == "textures" or group.displayMode == "trigger" then
        local settings = GetStandaloneTextureSettings(group, true)
        if not settings then
            return
        end
        local textureGroupId = CS.selectedGroup
        local isTriggerPanel = group.displayMode == "trigger"
        local positionHeadingText = isTriggerPanel and "Trigger Display Position" or "Texture Position"
        local anchorLabel = isTriggerPanel and "Display Point" or "Texture Point"
        local defaultFrame = group.parentContainerId and ("CooldownCompanionContainer" .. group.parentContainerId) or "UIParent"
        local cursorAnchorTarget = CooldownCompanion.GetCursorAnchorTargetName
            and CooldownCompanion:GetCursorAnchorTargetName()
            or ST.CURSOR_ANCHOR_TARGET
            or "CooldownCompanionCursor"
        local isCursorAnchor = CooldownCompanion.IsCursorAnchor
            and CooldownCompanion:IsCursorAnchor(group.anchor)
            or false
        local canUseCursorAnchor = CooldownCompanion:CanGroupUseCursorAnchor(group)
        if isCursorAnchor and not canUseCursorAnchor then
            isCursorAnchor = false
        end

        settings.relativeTo = type(settings.relativeTo) == "string" and settings.relativeTo ~= "" and settings.relativeTo or "UIParent"
        local isPanel = group.parentContainerId ~= nil
        local function ResetStandalonePosition(relativeTo, point, relativePoint, x, y)
            settings.point = point or "CENTER"
            settings.relativeTo = relativeTo or "UIParent"
            settings.relativePoint = relativePoint or "CENTER"
            settings.x = x or 0
            settings.y = y or 0
        end
        local function GetStandaloneAnchorValidationOptions()
            return CooldownCompanion:GetGroupAnchorValidationOptions(textureGroupId)
        end
        local function SetStandalonePanelAnchorTarget(targetGroupId)
            local targetFrameName = "CooldownCompanionGroup" .. tostring(targetGroupId)
            local options = GetStandaloneAnchorValidationOptions()
            local ok = CooldownCompanion:ValidateAddonFrameAnchorTarget(targetFrameName, options)
            if not ok then
                CooldownCompanion:PrintInvalidAnchorTargetReason(targetFrameName, options)
                return false
            end
            ResetStandalonePosition(targetFrameName, "TOPLEFT", "BOTTOMLEFT", 0, -5)
            group.inheritPanelAlpha = group.inheritPanelAlpha ~= false
            return true
        end
        local function SetStandaloneFrameAnchorTarget(targetFrameName)
            if type(targetFrameName) ~= "string" or targetFrameName == "" then
                ResetStandalonePosition()
                return true
            end
            local target = _G[targetFrameName]
            if not target or type(target) ~= "table" or not target.GetObjectType then
                CooldownCompanion:Print("Frame not found: " .. targetFrameName)
                return false
            end
            local options = GetStandaloneAnchorValidationOptions()
            local ok = CooldownCompanion:ValidateAddonFrameAnchorTarget(targetFrameName, options)
            if not ok then
                CooldownCompanion:PrintInvalidAnchorTargetReason(targetFrameName, options)
                return false
            end
            ResetStandalonePosition(targetFrameName, "TOPLEFT", "BOTTOMLEFT", 0, -5)
            return true
        end
        local anchorKind, currentAnchorGroupId
        anchorKind, currentAnchorGroupId = CooldownCompanion:ParseAddonAnchorFrameName(settings.relativeTo)
        local currentAnchorIsPanel = anchorKind == "group"
            and isPanel
            and CooldownCompanion.IsPanelAnchoredToPanel
            and CooldownCompanion:IsPanelAnchoredToPanel(textureGroupId)
            or false
        if not currentAnchorIsPanel then
            currentAnchorGroupId = nil
        end
        CS.layoutAnchorTargetMode = CS.layoutAnchorTargetMode or {}
        local storedTargetMode = CS.layoutAnchorTargetMode[textureGroupId]
        local targetMode
        if isCursorAnchor then
            targetMode = "cursor"
        elseif currentAnchorIsPanel then
            targetMode = "panel"
        elseif settings.relativeTo ~= "UIParent" then
            targetMode = "frame"
        elseif storedTargetMode == "panel" and isPanel then
            targetMode = "panel"
        elseif storedTargetMode == "frame" then
            targetMode = "frame"
        else
            targetMode = "group"
        end
        local hasFrameAnchorTarget = isPanel
            and targetMode == "frame"
            and IsResolvedExternalFrameAnchorTarget(settings.relativeTo)

        local function RefreshTextureVisual()
            CooldownCompanion:RefreshAllAuraTextureVisuals()
        end

        local function RefreshCursorAnchor()
            if CooldownCompanion.ClearCursorAnchorLayoutPreviewOffset then
                CooldownCompanion:ClearCursorAnchorLayoutPreviewOffset(textureGroupId)
            end
            local frame = CooldownCompanion.groupFrames[textureGroupId]
            if frame then
                CooldownCompanion:AnchorGroupFrame(frame, group.anchor)
            end
            RefreshTextureVisual()
        end

        if targetMode == "cursor" then
            CooldownCompanion:ShowCursorAnchorLayoutPreview(textureGroupId)
        else
            CooldownCompanion:ClearCursorAnchorLayoutPreview()
        end

        -- ============================================================
        -- The row grammar (RowWidgets.lua). Same shapes as the panel half
        -- below - the rules are stated once in the recipe comment atop
        -- BuildAppearanceTab's icons path (GroupTabsAppearance.lua) and this
        -- half conforms to them.
        --
        -- A texture/trigger panel anchors ONE texture rather than a panel of
        -- entries, so it has no Arrangement and no per-icon strata; the three
        -- sections it does share (Anchor, Position, Alpha) reuse the same
        -- collapse keys, because they are the same sections on the same tab.
        -- ============================================================
        local anchorTargetList = isPanel
            and {
                group = "Group",
                panel = "Panel",
                frame = "Frame",
                cursor = "Cursor",
            }
            or {
                group = group.parentContainerId and "Group" or "Screen",
                frame = "Frame",
            }
        local anchorTargetOrder = isPanel
            and (canUseCursorAnchor and { "group", "panel", "frame", "cursor" } or { "group", "panel", "frame" })
            or { "group", "frame" }
        if not canUseCursorAnchor then
            anchorTargetList.cursor = nil
        end

        -- ============================================================
        -- Anchor (what this texture hangs off)
        -- ============================================================
        local _, anchorCollapsed = BuildCollapsibleSection(container, "Anchor", "layout_anchor", nil, nil, ROW_SECTION)

        if not anchorCollapsed then
        -- LEFT column: the target itself. RIGHT column: the one setting that
        -- belongs to the choice of target rather than to this panel - where
        -- its alpha comes from.
        local anchorLeft, anchorRight = BeginRowGrid(container)

        AddDropdownRow(anchorLeft, {
            label = "Anchor Target",
            list = anchorTargetList,
            order = anchorTargetOrder,
            value = targetMode,
            onChange = function(val, widget)
                if val == targetMode then return end
                if val == "cursor" then
                    if not canUseCursorAnchor then
                        widget:SetValue("group")
                        return
                    end
                    if CooldownCompanion:SetGroupAnchor(CS.selectedGroup, cursorAnchorTarget) then
                        CS.layoutAnchorTargetMode[CS.selectedGroup] = nil
                        ResetStandalonePosition()
                        CooldownCompanion:RefreshConfigPanel()
                    else
                        widget:SetValue(targetMode)
                    end
                elseif val == "group" then
                    CS.layoutAnchorTargetMode[CS.selectedGroup] = nil
                    ResetStandalonePosition()
                    CooldownCompanion:SetGroupAnchor(CS.selectedGroup, defaultFrame, true)
                    CooldownCompanion:RefreshConfigPanel()
                elseif val == "panel" then
                    if isCursorAnchor and not CooldownCompanion:SetGroupAnchor(CS.selectedGroup, defaultFrame, true) then
                        widget:SetValue(targetMode)
                        return
                    end
                    ResetStandalonePosition()
                    CS.layoutAnchorTargetMode[CS.selectedGroup] = "panel"
                    CooldownCompanion:RefreshConfigPanel()
                elseif val == "frame" then
                    if isCursorAnchor and not CooldownCompanion:SetGroupAnchor(CS.selectedGroup, defaultFrame, true) then
                        widget:SetValue(targetMode)
                        return
                    end
                    ResetStandalonePosition()
                    CS.layoutAnchorTargetMode[CS.selectedGroup] = "frame"
                    CooldownCompanion:RefreshConfigPanel()
                end
            end,
        })

        if targetMode == "panel" then
            local panelAnchorRow = AddDropdownRow(anchorLeft, {
                label = "Anchor to Panel",
                pulloutWidth = WIDE_PULLOUT_WIDTH,
                onChange = function(val, widget)
                    if not val or val == "" then return end
                    local targetGroupId = tonumber(val)
                    if targetGroupId and SetStandalonePanelAnchorTarget(targetGroupId) then
                        CooldownCompanion:RefreshAllAuraTextureVisuals()
                        CooldownCompanion:RefreshConfigPanel()
                    else
                        widget:SetValue(currentAnchorGroupId and tostring(currentAnchorGroupId) or nil)
                    end
                end,
            })
            -- The populator writes the stock Dropdown's own `list` table
            -- directly (container headers plus indented panel entries), so it
            -- takes the embedded child rather than the row wrapper.
            CooldownCompanion:PopulatePanelAnchorTargetDropdown(panelAnchorRow.dropdown, textureGroupId)
            panelAnchorRow:SetValue(currentAnchorGroupId and tostring(currentAnchorGroupId) or nil)
        end

        if isPanel and (targetMode == "panel" or hasFrameAnchorTarget) then
            AddDropdownRow(anchorRight, {
                label = "Panel Alpha",
                pulloutWidth = WIDE_PULLOUT_WIDTH,
                list = {
                    inherit = targetMode == "frame" and "Inherit Target Frame Alpha" or "Inherit Target Panel Alpha",
                    custom = "Custom Alpha",
                },
                order = { "inherit", "custom" },
                value = group.inheritPanelAlpha == false and "custom" or "inherit",
                onChange = function(val)
                    group.inheritPanelAlpha = val ~= "custom"
                    CooldownCompanion:RefreshAllAuraTextureVisuals()
                    CooldownCompanion:RefreshConfigPanel()
                end,
            })
        end

        if targetMode == "frame" then
            -- A frame name needs the whole 140px control column to stay
            -- readable, so Pick does not share it: the editbox row takes a
            -- grid of its own and Pick sits at the head of that grid's right
            -- column.
            local frameLeft, frameRight = BeginRowGrid(container)

            local frameAnchorText = settings.relativeTo
            if frameAnchorText == "UIParent" or currentAnchorGroupId then frameAnchorText = "" end

            local anchorRow = AddEditBoxRow(frameLeft, {
                label = "Anchor to Frame",
                value = frameAnchorText,
                onEnterPressed = function(text, widget)
                    if SetStandaloneFrameAnchorTarget(text) then
                        CooldownCompanion:RefreshAllAuraTextureVisuals()
                        CooldownCompanion:RefreshConfigPanel()
                    else
                        widget:SetText(frameAnchorText)
                    end
                end,
            })
            if anchorRow.editbox.Instructions then anchorRow.editbox.Instructions:Hide() end

            -- Exactly one grammar row tall so the button's centre lands on the
            -- editbox's: Flow insets its single row by 3px and the button is
            -- 24 tall, so 3 + 24 + 3 fills the 30px band. noAutoHeight keeps
            -- Flow's own 27px report from shrinking it back.
            local pickRow = AceGUI:Create("SimpleGroup")
            pickRow:SetFullWidth(true)
            pickRow:SetLayout("Flow")
            pickRow:SetHeight(ST._RowGrammar and ST._RowGrammar.ROW_HEIGHT or 30)
            pickRow.noAutoHeight = true

            local pickBtn = AceGUI:Create("Button")
            pickBtn:SetText("Pick")
            pickBtn:SetAutoWidth(true)
            pickBtn:SetCallback("OnClick", function()
                local grp = CS.selectedGroup
                CS.StartPickFrame(function(name)
                    if CS.configFrame then
                        CS.configFrame.frame:Show()
                    end
                    if name then
                        SetStandaloneFrameAnchorTarget(name)
                    end
                    CooldownCompanion:RefreshAllAuraTextureVisuals()
                    CooldownCompanion:RefreshConfigPanel()
                end, grp)
            end)
            pickRow:AddChild(pickBtn)

            CreateInfoButton(pickBtn.frame, pickBtn.frame, "LEFT", "RIGHT", 2, 0, {
                "Pick Frame",
                {"Hides the config panel and highlights frames under your cursor. Left-click a frame to anchor this panel to it, or right-click to cancel.", 1, 1, 1, true},
                " ",
                {"You can also type a frame name directly into the editbox.", 1, 1, 1, true},
            }, tabInfoButtons)

            -- Added last so the List-layout column measures a populated row.
            frameRight:AddChild(pickRow)
        end
        end -- not anchorCollapsed

        -- ============================================================
        -- Position (where the anchor point sits, and the offset from it)
        -- ============================================================
        -- Cursor anchoring pins the relative point; it is a stored setting,
        -- not a rendered control, so it is written whether or not the section
        -- below is expanded.
        if targetMode == "cursor" then
            group.anchor.relativePoint = "CENTER"
        end

        local _, positionCollapsed = BuildCollapsibleSection(container,
            targetMode == "cursor" and "Cursor Offset" or positionHeadingText,
            "layout_position", nil, nil, ROW_SECTION)

        if not positionCollapsed then
        -- LEFT column: the points that have to be read together (mine, then
        -- the target's). RIGHT column: the offset pair applied on top of them.
        -- Cursor mode has no relative point, so the left side ends early - and
        -- that is where its Reset goes, filling the shorter column's tail.
        local positionLeft, positionRight = BeginRowGrid(container)

        if targetMode == "cursor" then
            AddAnchorDropdown(positionLeft, group.anchor, "point", "BOTTOMLEFT",
                RefreshCursorAnchor, "Panel Point", { row = true })
            AddOffsetSliders(positionRight, group.anchor, "x", "y", {
                x = 16,
                y = 16,
                range = 2000,
                step = 1,
            }, RefreshCursorAnchor, {
                row = true,
                previewRefresh = function()
                    if CooldownCompanion.SetCursorAnchorLayoutPreviewOffset then
                        CooldownCompanion:SetCursorAnchorLayoutPreviewOffset(
                            textureGroupId,
                            group.anchor.x or 0,
                            group.anchor.y or 0
                        )
                    end
                end,
            })

            -- Destructive, and it replaces the whole anchor - the Panel Point
            -- above included - so it sits with what it clears.
            local resetBtn = AceGUI:Create("Button")
            resetBtn:SetText("Reset Cursor Offset")
            resetBtn:SetAutoWidth(true)
            resetBtn:SetCallback("OnClick", function()
                group.anchor = CooldownCompanion.GetDefaultCursorPanelAnchor
                    and CooldownCompanion:GetDefaultCursorPanelAnchor()
                    or {
                        point = "BOTTOMLEFT",
                        relativeTo = cursorAnchorTarget,
                        relativePoint = "CENTER",
                        x = 16,
                        y = 16,
                    }
                RefreshCursorAnchor()
                CooldownCompanion:RefreshConfigPanel()
            end)
            positionLeft:AddChild(resetBtn)
        else
            AddAnchorDropdown(positionLeft, settings, "point", "CENTER",
                RefreshTextureVisual, anchorLabel, { row = true })
            AddAnchorDropdown(positionLeft, settings, "relativePoint", "CENTER",
                RefreshTextureVisual,
                (targetMode == "panel" or targetMode == "frame") and "Target Point" or "Screen Point",
                { row = true })
            AddOffsetSliders(positionRight, settings, "x", "y", {
                x = 0,
                y = 0,
                range = 2000,
                step = 1,
            }, RefreshTextureVisual, { row = true })

            -- Both columns are two rows here, so the Reset goes with the
            -- offsets it zeroes rather than with the points.
            local resetBtn = AceGUI:Create("Button")
            resetBtn:SetText("Reset Position")
            resetBtn:SetAutoWidth(true)
            resetBtn:SetCallback("OnClick", function()
                if (targetMode == "panel" or targetMode == "frame") and settings.relativeTo ~= "UIParent" then
                    ResetStandalonePosition(settings.relativeTo, "TOPLEFT", "BOTTOMLEFT", 0, -5)
                else
                    ResetStandalonePosition()
                end
                CooldownCompanion:RefreshAllAuraTextureVisuals()
                CooldownCompanion:RefreshConfigPanel()
            end)
            positionRight:AddChild(resetBtn)
        end
        end -- not positionCollapsed

        if CS.IsAuraTexturePickerOpen and CS.IsAuraTexturePickerOpen() then
            OpenOrRebindStandaloneTexturePicker(group, settings, false)
        end
        RefreshTextureVisual()
        return
    end

    local isPanel = group.parentContainerId ~= nil
    local panelContainerFrame = isPanel and ("CooldownCompanionContainer" .. group.parentContainerId) or nil
    local currentAnchor = group.anchor.relativeTo
    local cursorAnchorTarget = CooldownCompanion.GetCursorAnchorTargetName
        and CooldownCompanion:GetCursorAnchorTargetName()
        or ST.CURSOR_ANCHOR_TARGET
        or "CooldownCompanionCursor"
    local isCursorAnchor = isPanel
        and CooldownCompanion.IsCursorAnchor
        and CooldownCompanion:IsCursorAnchor(group.anchor)
        or false
    local defaultFrame = isPanel and panelContainerFrame or "UIParent"
    local currentAnchorGroupId = type(currentAnchor) == "string"
        and currentAnchor:match("^CooldownCompanionGroup(%d+)$")
        or nil
    local targetMode
    if isCursorAnchor then
        targetMode = "cursor"
    elseif currentAnchorGroupId and isPanel then
        targetMode = "panel"
    elseif currentAnchor == nil or currentAnchor == "UIParent" or (isPanel and currentAnchor == panelContainerFrame) then
        targetMode = "group"
    else
        targetMode = "frame"
    end
    CS.layoutAnchorTargetMode = CS.layoutAnchorTargetMode or {}
    local preferredTargetMode = CS.layoutAnchorTargetMode[CS.selectedGroup]
    if (targetMode == "group" or targetMode == "cursor")
        and (preferredTargetMode == "frame" or (isPanel and preferredTargetMode == "panel")) then
        targetMode = preferredTargetMode
    end
    CS.layoutAnchorTargetMode[CS.selectedGroup] = targetMode
    local hasFrameAnchorTarget = isPanel
        and targetMode == "frame"
        and IsResolvedExternalFrameAnchorTarget(currentAnchor)
    if targetMode == "cursor" and isCursorAnchor then
        CooldownCompanion:ShowCursorAnchorLayoutPreview(CS.selectedGroup)
    else
        CooldownCompanion:ClearCursorAnchorLayoutPreview()
    end
    -- ================================================================
    -- The row grammar (RowWidgets.lua). The rules every row-grammar section
    -- follows are stated once, in the recipe comment at the top of
    -- BuildAppearanceTab's icons path (GroupTabsAppearance.lua); this tab
    -- conforms to them rather than restating them.
    --
    -- Every mode that reaches here shares this one layout: anchoring,
    -- position and frame strata are panel facts, not display-mode
    -- facts. (Alpha is a panel fact too, but it reads as visibility
    -- behavior, so it lives on the Visibility tab.)
    -- Only the Arrangement section and the icons-only strata block
    -- below vary, and each of those names its own mode gate. (Texture and
    -- trigger panels returned far above - they anchor a single texture rather
    -- than a panel of entries.)
    -- ================================================================
    -- nil displayMode means icons everywhere in the core, so it resolves to
    -- icons here too - the same fallback BuildAppearanceTab's dispatch makes.
    local displayMode = group.displayMode or "icons"
    local isIconsMode = displayMode == "icons"
    local isBarMode = displayMode == "bars"
    local isTextMode = displayMode == "text"

    local iconAnchorTargetList = isPanel
        and {
            group = "Group",
            panel = "Panel",
            frame = "Frame",
            cursor = "Cursor",
        }
        or {
            group = "Screen",
            frame = "Frame",
        }
    local iconAnchorTargetOrder = isPanel
        and { "group", "panel", "frame", "cursor" }
        or { "group", "frame" }

    -- ============================================================
    -- Anchor (what this panel hangs off)
    -- ============================================================
    local _, anchorCollapsed = BuildCollapsibleSection(container, "Anchor", "layout_anchor", nil, nil, ROW_SECTION)

    if not anchorCollapsed then
    -- LEFT column: the target itself. RIGHT column: the one setting that
    -- belongs to the choice of target rather than to this panel - where
    -- its alpha comes from.
    local anchorLeft, anchorRight = BeginRowGrid(container)

    AddDropdownRow(anchorLeft, {
        label = "Anchor Target",
        list = iconAnchorTargetList,
        order = iconAnchorTargetOrder,
        value = targetMode,
        onChange = function(val, widget)
            if val == targetMode then return end
            if val == "group" then
                CS.layoutAnchorTargetMode[CS.selectedGroup] = nil
                local wasAnchored = group.anchor.relativeTo and group.anchor.relativeTo ~= defaultFrame
                CooldownCompanion:SetGroupAnchor(CS.selectedGroup, defaultFrame, wasAnchored)
                CooldownCompanion:RefreshConfigPanel()
            elseif val == "cursor" then
                CS.layoutAnchorTargetMode[CS.selectedGroup] = nil
                if CooldownCompanion:SetGroupAnchor(CS.selectedGroup, cursorAnchorTarget) then
                    CooldownCompanion:RefreshConfigPanel()
                else
                    widget:SetValue(targetMode)
                end
            elseif val == "frame" or val == "panel" then
                CS.layoutAnchorTargetMode[CS.selectedGroup] = val
                CooldownCompanion:RefreshConfigPanel()
            end
        end,
    })

    if isPanel and targetMode == "panel" then
        local panelAnchorRow = AddDropdownRow(anchorLeft, {
            label = "Anchor to Panel",
            onChange = function(val, widget)
                if not val or val == "" then return end
                local targetGroupId = tonumber(val)
                if not targetGroupId then return end
                local targetFrameName = "CooldownCompanionGroup" .. targetGroupId
                if CooldownCompanion:SetGroupAnchor(CS.selectedGroup, targetFrameName) then
                    CooldownCompanion:RefreshConfigPanel()
                else
                    widget:SetValue(nil)
                end
            end,
        })
        -- The populator writes the stock Dropdown's own `list` table
        -- directly (container headers plus indented panel entries), so it
        -- takes the embedded child rather than the row wrapper.
        CooldownCompanion:PopulatePanelAnchorTargetDropdown(panelAnchorRow.dropdown, CS.selectedGroup)
        if currentAnchorGroupId then
            panelAnchorRow:SetValue(tostring(currentAnchorGroupId))
        else
            panelAnchorRow:SetValue(nil)
        end
    end

    if isPanel and (targetMode == "panel" or hasFrameAnchorTarget) then
        AddDropdownRow(anchorRight, {
            label = "Panel Alpha",
            list = {
                inherit = targetMode == "frame" and "Inherit Target Frame Alpha" or "Inherit Target Panel Alpha",
                custom = "Custom Alpha",
            },
            order = { "inherit", "custom" },
            value = group.inheritPanelAlpha == false and "custom" or "inherit",
            onChange = function(val)
                if val == "custom" then
                    group.inheritPanelAlpha = false
                else
                    group.inheritPanelAlpha = true
                end

                local frame = CooldownCompanion.groupFrames[CS.selectedGroup]
                if frame then
                    CooldownCompanion:AnchorGroupFrame(frame, group.anchor)
                end
                CooldownCompanion:RebuildPanelAlphaDependencyTargets()
                CooldownCompanion:RefreshConfigPanel()
            end,
        })
    end

    if targetMode == "frame" then
        -- A frame name needs the whole 140px control column to stay
        -- readable, so Pick does not share it: the editbox row takes a
        -- grid of its own and Pick sits at the head of that grid's right
        -- column. The gutter between columns is 16px, so the button lands
        -- immediately right of the editbox, and both are on line one of
        -- their own grid, so nothing above them can knock them apart.
        local frameLeft, frameRight = BeginRowGrid(container)

        local frameAnchorText = currentAnchor
        if frameAnchorText == "UIParent" or isCursorAnchor or currentAnchorGroupId then frameAnchorText = "" end
        if isPanel and frameAnchorText == panelContainerFrame then frameAnchorText = "" end

        local anchorRow = AddEditBoxRow(frameLeft, {
            label = "Anchor to Frame",
            value = frameAnchorText,
            onEnterPressed = function(text, widget)
                local wasAnchored = group.anchor.relativeTo and group.anchor.relativeTo ~= defaultFrame
                if text == "" then
                    CooldownCompanion:SetGroupAnchor(CS.selectedGroup, defaultFrame, wasAnchored)
                else
                    local target = _G[text]
                    if not target or type(target) ~= "table" or not target.GetObjectType then
                        CooldownCompanion:Print("Frame not found: " .. text)
                        widget:SetText(frameAnchorText)
                        return
                    end
                    CooldownCompanion:SetGroupAnchor(CS.selectedGroup, text)
                end
                CooldownCompanion:RefreshConfigPanel()
            end,
        })
        if anchorRow.editbox.Instructions then anchorRow.editbox.Instructions:Hide() end

        -- Exactly one grammar row tall so the button's centre lands on the
        -- editbox's: Flow insets its single row by 3px and the button is
        -- 24 tall, so 3 + 24 + 3 fills the 30px band. noAutoHeight keeps
        -- Flow's own 27px report from shrinking it back.
        local pickRow = AceGUI:Create("SimpleGroup")
        pickRow:SetFullWidth(true)
        pickRow:SetLayout("Flow")
        pickRow:SetHeight(ST._RowGrammar and ST._RowGrammar.ROW_HEIGHT or 30)
        pickRow.noAutoHeight = true

        local pickBtn = AceGUI:Create("Button")
        pickBtn:SetText("Pick")
        pickBtn:SetAutoWidth(true)
        pickBtn:SetCallback("OnClick", function()
            local grp = CS.selectedGroup
            CS.StartPickFrame(function(name)
                if CS.configFrame then
                    CS.configFrame.frame:Show()
                end
                if name then
                    CooldownCompanion:SetGroupAnchor(grp, name)
                end
                CooldownCompanion:RefreshConfigPanel()
            end, grp)
        end)
        pickRow:AddChild(pickBtn)

        -- (?) tooltip for anchor picking
        CreateInfoButton(pickBtn.frame, pickBtn.frame, "LEFT", "RIGHT", 2, 0, {
            "Pick Frame",
            {"Hides the config panel and highlights frames under your cursor. Left-click a frame to anchor this group to it, or right-click to cancel.", 1, 1, 1, true},
            " ",
            {"You can also type a frame name directly into the editbox.", 1, 1, 1, true},
        }, tabInfoButtons)

        -- Added last so the List-layout column measures a populated row.
        frameRight:AddChild(pickRow)
    end
    end -- not anchorCollapsed

    -- ============================================================
    -- Position (where the anchor point sits, and the offset from it)
    -- ============================================================
    -- Cursor anchoring pins the relative point; it is a stored setting,
    -- not a rendered control, so it is written whether or not the section
    -- below is expanded.
    if targetMode == "cursor" then
        group.anchor.relativePoint = "CENTER"
    end

    local function refreshGroupAnchor()
        local frame = CooldownCompanion.groupFrames[CS.selectedGroup]
        if frame then
            CooldownCompanion:AnchorGroupFrame(frame, group.anchor)
        end
    end

    local _, positionCollapsed = BuildCollapsibleSection(container,
        targetMode == "cursor" and "Cursor Offset" or "Position",
        "layout_position", nil, nil, ROW_SECTION)

    if not positionCollapsed then
    -- LEFT column: the two points that have to be read together (mine,
    -- then the target's). RIGHT column: the offset pair applied on top of
    -- them. Cursor mode has no relative point, so the left side ends early.
    local positionLeft, positionRight = BeginRowGrid(container)

    AddAnchorDropdown(positionLeft, group.anchor, "point",
        targetMode == "cursor" and "BOTTOMLEFT" or "CENTER",
        refreshGroupAnchor,
        targetMode == "cursor" and "Panel Point" or "Anchor Point",
        { row = true })

    if targetMode ~= "cursor" then
        AddAnchorDropdown(positionLeft, group.anchor, "relativePoint", "CENTER",
            refreshGroupAnchor, "Relative Point", { row = true })
    end

    -- Screen position is not represented inside the pinned mirror. Store the
    -- drag value and re-anchor the live panel once on release.
    local xOffsetRow = AddSliderRow(positionRight, {
        label = "X Offset",
        min = -2000, max = 2000, step = 0.1,
        value = group.anchor.x or 0,
    })
    local function PreviewCursorOffset()
        if targetMode == "cursor" and CooldownCompanion.SetCursorAnchorLayoutPreviewOffset then
            CooldownCompanion:SetCursorAnchorLayoutPreviewOffset(
                CS.selectedGroup,
                group.anchor.x or 0,
                group.anchor.y or 0
            )
        end
    end
    local function CommitGroupOffset()
        if CooldownCompanion.ClearCursorAnchorLayoutPreviewOffset then
            CooldownCompanion:ClearCursorAnchorLayoutPreviewOffset(CS.selectedGroup)
        end
        refreshGroupAnchor()
    end

    WireMirrorFirstSlider(xOffsetRow, function(val)
        group.anchor.x = val
    end, CommitGroupOffset, targetMode == "cursor" and PreviewCursorOffset or false,
        group.anchor, "x")

    local yOffsetRow = AddSliderRow(positionRight, {
        label = "Y Offset",
        min = -2000, max = 2000, step = 0.1,
        value = group.anchor.y or 0,
    })
    WireMirrorFirstSlider(yOffsetRow, function(val)
        group.anchor.y = val
    end, CommitGroupOffset, targetMode == "cursor" and PreviewCursorOffset or false,
        group.anchor, "y")
    end -- not positionCollapsed

    -- ============================================================
    -- Arrangement (how the entries sit relative to each other)
    -- ============================================================
    local _, arrangementCollapsed = BuildCollapsibleSection(container, "Arrangement", "layout_arrangement", nil, nil, ROW_SECTION)

    if not arrangementCollapsed then
    -- Two settings have to be read together here whatever the mode: growth
    -- direction is relabelled by the orientation above it, so they always
    -- share a column and always sit adjacent.
    --
    -- LEFT column (most modes): that pair. RIGHT column: the wrap count and
    -- the one setting that is about other panels rather than this one.
    --
    -- Bar panels invert it. They own two rows nothing else has - which way a
    -- single bar's own fill runs - and a bar's left column is about the bar
    -- itself, so the fill pair takes the left and the arrangement pair moves
    -- across to join the wrap count. Either way both columns are populated,
    -- including the single-bar case where the orientation row is gated away.
    local arrangeLeft, arrangeRight = BeginRowGrid(container)
    local arrangeHost = isBarMode and arrangeRight or arrangeLeft

    -- An Aura BAR Panel is ONE vertical column by construction: the aura
    -- container's bars branch hard-codes the axis and takes no line ceiling, so
    -- neither the orientation question nor the wrap count has an answer to give
    -- here. Aura ICON Panels keep both - their grid follows the same style keys
    -- an ordinary icon panel's does.
    local auraBarPanel = isBarMode and CooldownCompanion:IsAuraPanel(group)

    -- Orientation is remembered per display mode (bar and text panels own
    -- their keys, unset = vertical), so a mode swap keeps every mode's
    -- layout. Same helper GetCompactGrowthDirectionLabels uses, because the
    -- Growth Direction labels below have to agree with it.
    local orientation = ST.GetPanelLayoutOrientation(group.displayMode, style)

    if isBarMode then
        -- Which way a bar's own fill runs is independent of how the bars are
        -- arranged, so these lead the section rather than hanging off it.
        AddCheckboxRow(arrangeLeft, {
            label = "Vertical Bar Fill",
            value = style.barFillVertical or false,
            onChange = function(val)
                style.barFillVertical = val or nil
                CooldownCompanion:RefreshGroupFrame(CS.selectedGroup)
                CooldownCompanion:RefreshConfigPanel()
            end,
        })

        AddCheckboxRow(arrangeLeft, {
            label = "Flip Fill/Drain Direction",
            value = style.barReverseFill or false,
            onChange = function(val)
                style.barReverseFill = val or nil
                CooldownCompanion:RefreshGroupFrame(CS.selectedGroup)
            end,
        })

        -- A bar panel's orientation is one question ("do the bars sit in a
        -- row?"), so it is a checkbox rather than the horizontal/vertical
        -- dropdown the other modes show. With a single bar there is nothing
        -- to lay out.
        if #group.buttons > 1 and not auraBarPanel then
            AddCheckboxRow(arrangeHost, {
                label = "Horizontal Bar Layout",
                value = orientation == "horizontal",
                onChange = function(val)
                    style.barOrientation = val and "horizontal" or "vertical"
                    CooldownCompanion:RefreshGroupFrame(CS.selectedGroup)
                    CooldownCompanion:RefreshConfigPanel()
                end,
            })
        end
    else
        AddDropdownRow(arrangeHost, {
            label = "Orientation",
            -- Owner ruling 2026-08-08 (supersedes 2026-07-28): the display
            -- reads the same per-mode helper the core lays out with, and
            -- text panels now default vertical like bars. Each mode writes
            -- its own key so swapping modes keeps every mode's layout.
            list = { horizontal = "Horizontal", vertical = "Vertical" },
            value = orientation,
            onChange = function(val)
                if isTextMode then
                    style.textOrientation = val
                else
                    style.orientation = val
                end
                CooldownCompanion:RefreshGroupFrame(CS.selectedGroup)
                CooldownCompanion:RefreshConfigPanel()
            end,
        })
    end

    if #group.buttons > 1 then
        local labels
        -- Same override the Collapse Direction row below applies: an Aura BAR
        -- Panel is one vertical column by construction, so its labels must not
        -- follow the barOrientation key (hidden for this subtype, still
        -- copyable, and never read by the engine here).
        if auraBarPanel or orientation == "vertical" then
            labels = { TOPLEFT = "Down, Right", TOPRIGHT = "Down, Left", BOTTOMLEFT = "Up, Right", BOTTOMRIGHT = "Up, Left" }
        else
            labels = { TOPLEFT = "Right, Down", TOPRIGHT = "Left, Down", BOTTOMLEFT = "Right, Up", BOTTOMRIGHT = "Left, Up" }
        end

        AddDropdownRow(arrangeHost, {
            label = "Growth Direction",
            list = labels,
            order = { "TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT" },
            value = style.growthOrigin or "TOPLEFT",
            onChange = function(val)
                style.growthOrigin = val
                CooldownCompanion:RefreshGroupFrame(CS.selectedGroup)
                CooldownCompanion:RefreshConfigPanel()
            end,
        })
    end

    -- An Aura Panel packs only its ACTIVE auras (Blizzard's aura container does
    -- the collapsing, so it is inherent and always on), which leaves one
    -- question Growth Direction cannot answer: which end of the panel the packed
    -- block holds as auras come and go. Same start/center/end key every other
    -- panel's compact mode writes, so it reads and writes through the compact
    -- helpers - but here it is simply how the panel arranges itself, so it sits
    -- under Growth Direction rather than behind a compact toggle this panel
    -- subtype does not have (owner ruling 2026-08-15).
    if CooldownCompanion:IsAuraPanel(group) then
        -- PanelFlowSpec hard-codes the Vertical axis for an Aura BAR Panel, so
        -- the labels follow that rather than the (gated-away, possibly stale)
        -- barOrientation key the row above still reads.
        local collapseOrientation = isBarMode and "vertical" or nil
        local collapseRow = AddDropdownRow(arrangeHost, {
            label = "Collapse Direction",
            list = GetCompactGrowthDirectionLabels(group, collapseOrientation),
            order = { "start", "center", "end" },
            value = NormalizeCompactGrowthDirection(group.compactGrowthDirection),
            onChange = function(val)
                group.compactGrowthDirection = NormalizeCompactGrowthDirection(val)
                -- The mount point is read at BIND time, so the display only
                -- moves on the next aura pass. RefreshGroupFrame ends in
                -- RequestAuraRebind("aura-panel", groupId) for exactly this
                -- panel subtype, which is the request that re-runs it.
                CooldownCompanion:RefreshGroupFrame(CS.selectedGroup)
            end,
        })

        -- Anchor args are a placeholder - AnchorRowBadge re-points the button
        -- onto the end of the row's label.
        AnchorRowBadge(collapseRow, CreateInfoButton(collapseRow.frame, collapseRow.frame, "LEFT", "LEFT", 0, 0, {
            "Collapse Direction",
            {"Active auras pack from the start of the panel, from its center, or from its end.", 1, 1, 1, true},
            {" ", 1, 1, 1},
            {"Inactive auras take no space here, so the block moves as auras come and go.", 1, 1, 1, true},
        }, tabInfoButtons))
    end

    -- Text mode calls its entries entries, and offers the wrap count only
    -- once there is something to wrap.
    if not auraBarPanel and (not isTextMode or #group.buttons > 1) then
        local numButtons = math.max(1, #group.buttons)
        local wrapRow = AddSliderRow(arrangeRight, {
            label = isTextMode and "Entries per Row/Column" or "Buttons Per Row/Column",
            min = 1, max = numButtons, step = 1,
            value = math.min(style.buttonsPerRow or 12, numButtons),
        })
        WireMirrorFirstSlider(wrapRow, function(val)
            style.buttonsPerRow = val
        end, function()
            CooldownCompanion:RefreshGroupFrame(CS.selectedGroup)
        end, nil, style, "buttonsPerRow")
    end

    -- Auto-Anchoring eligibility (icon-like modes only - others are never
    -- eligible). An Aura Panel is structurally excluded in
    -- IsGroupAvailableForAnchoring, so the checkbox has nothing to opt into.
    if CooldownCompanion:IsIconLikeDisplayMode(group.displayMode)
        and not CooldownCompanion:IsAuraPanel(group) then
        local anchorEligibleRow = AddCheckboxRow(arrangeRight, {
            label = "Include in Auto-Anchoring",
            value = group.anchorEligible ~= false,
            onChange = function(val)
                if val then
                    group.anchorEligible = nil
                else
                    group.anchorEligible = false
                end
                CooldownCompanion:EvaluateResourceBars()
                CooldownCompanion:UpdateAnchorStacking()
                CooldownCompanion:EvaluateCastBar()
                CooldownCompanion:EvaluateFrameAnchoring()
                CooldownCompanion:RefreshConfigPanel()
            end,
        })

        -- Badge chained off the end of the label; the anchor args below
        -- are a placeholder - AnchorRowBadge re-points the button.
        AnchorRowBadge(anchorEligibleRow, CreateInfoButton(anchorEligibleRow.frame, anchorEligibleRow.frame, "LEFT", "LEFT", 0, 0, {
            "Include in Auto-Anchoring",
            {"Resource Bars, the Cast Bar, and Unit Frames attach to the first available panel automatically. Uncheck this to skip this panel so they attach to the next eligible one instead.", 1, 1, 1, true},
        }, tabInfoButtons))
    end
    end -- not arrangementCollapsed

    -- ============================================================
    -- Strata
    -- ============================================================
    local _, strataCollapsed = BuildCollapsibleSection(container, "Strata", "layout_strata", nil, nil, ROW_SECTION)

    if not strataCollapsed then
    -- Per-icon layer ordering exists on icon panels only; the other modes
    -- have no stack of icon layers to reorder.
    --
    -- Nor does an Aura Panel: it materializes no CC buttons at all (GroupFrame's
    -- aura-panel branch), so seven of the eight layers this orders - the fill
    -- timer, cooldown swipe, ready glow, key press highlight, text overlay,
    -- assisted highlight and proc glow - do not exist here, and the eighth (Aura
    -- Display) IS the panel. There is no stack left to reorder.
    local showCustomStrata = isIconsMode and not CooldownCompanion:IsAuraPanel(group)
    local customStrataEnabled = showCustomStrata and type(style.strataOrder) == "table"

    -- LEFT column: the per-icon layer switch. RIGHT column: the whole
    -- panel's draw layer. One row each - the layer dropdowns below
    -- are a block of their own so the indent cannot read as belonging to
    -- Frame Strata. Without the layer switch the section is a single row, so
    -- Frame Strata moves left rather than leaving the left column empty.
    local strataLeft, strataRight = BeginRowGrid(container)
    local frameStrataHost = showCustomStrata and strataRight or strataLeft

    if showCustomStrata then
    local strataToggleRow = AddCheckboxRow(strataLeft, {
        label = "Custom Icon Strata",
        value = customStrataEnabled,
        onChange = function(val)
            if not val then
                style.strataOrder = nil
                CS.pendingStrataOrder = nil
                CS.pendingStrataGroup = nil
                CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
            else
                style.strataOrder = style.strataOrder or {}
                CS.pendingStrataOrder = nil
                CS.InitPendingStrataOrder(CS.selectedGroup)
            end
            local host = CS.groupSettingsActiveHost
            if host and host.tabGroup then
                -- Rebuild in place, not a tab choice: the helper keeps the
                -- remembered-tab bookkeeping from reading it as one.
                ST._SelectPanelSettingsTabProgrammatic(host.tabGroup, CS.selectedTab)
            end
        end,
    })

    AnchorRowBadge(strataToggleRow, CreateInfoButton(strataToggleRow.frame, strataToggleRow.frame, "LEFT", "LEFT", 0, 0, {
        "Custom Icon Strata",
        {"Sets the draw order of each icon's visual layers.", 1, 1, 1, true},
        " ",
        {"Layer 8 draws on top, Layer 1 on the bottom.", 1, 1, 1, true},
        " ",
        {"Aura Display moves the aura glow, pandemic glow, aura swipe and aura text together.", 1, 1, 1, true},
        " ",
        {"Put Cooldown Swipe above Aura Display to keep a spell's own cooldown visible while its aura runs.", 1, 1, 1, true},
        " ",
        {"Loss of Control and keybind text always draw on top.", 1, 1, 1, true},
    }, tabInfoButtons))
    end -- showCustomStrata (custom strata toggle)

    local frameStrataRow = AddDropdownRow(frameStrataHost, {
        label = "Frame Strata",
        list = {
            BACKGROUND = "Background",
            LOW = "Low",
            MEDIUM = "Default",
            HIGH = "High",
            DIALOG = "Highest",
        },
        order = { "BACKGROUND", "LOW", "MEDIUM", "HIGH", "DIALOG" },
        value = group.frameStrata or "MEDIUM",
        onChange = function(val)
            group.frameStrata = (val ~= "MEDIUM") and val or nil
            CooldownCompanion:RefreshGroupFrame(CS.selectedGroup)
        end,
    })

    AnchorRowBadge(frameStrataRow, CreateInfoButton(frameStrataRow.frame, frameStrataRow.frame, "LEFT", "LEFT", 0, 0, {
        "Frame Strata",
        {"Sets the rendering layer for this group.", 1, 1, 1, true},
        " ",
        {"Higher strata groups fully overlap lower ones.", 1, 1, 1, true},
        " ",
        {"Only change this if you need one group to overlap another.", 1, 1, 1, true},
    }, tabInfoButtons))

    if customStrataEnabled then
        CS.InitPendingStrataOrder(CS.selectedGroup)

        local ELEMENT_COUNT = #ST.DEFAULT_STRATA_ORDER

        -- Build dropdown list with unassigned entries highlighted in green
        local function BuildStrataList()
            local assigned = {}
            for i = 1, ELEMENT_COUNT do
                if CS.pendingStrataOrder[i] then
                    assigned[CS.pendingStrataOrder[i]] = true
                end
            end
            local list = {}
            for _, key in ipairs(CS.strataElementKeys) do
                if not assigned[key] then
                    list[key] = "|cff40ff40" .. CS.strataElementLabels[key] .. "|r"
                else
                    list[key] = CS.strataElementLabels[key]
                end
            end
            return list
        end

        local strataDropdowns = {}

        -- Refresh all dropdown lists and values
        local function RefreshAllDropdowns()
            local list = BuildStrataList()
            for i = 1, ELEMENT_COUNT do
                if strataDropdowns[i] then
                    strataDropdowns[i]:SetList(list)
                    strataDropdowns[i]:SetValue(CS.pendingStrataOrder[i])
                end
            end
        end

        -- The layers are one ordered stack, so they get their own grid and
        -- fill it top-down: the top half of the stack in the left column,
        -- the bottom half in the right.
        local layerLeft, layerRight = BeginRowGrid(container)
        local splitAt = math.ceil(ELEMENT_COUNT / 2)

        for displayIdx = 1, ELEMENT_COUNT do
            local pos = ELEMENT_COUNT + 1 - displayIdx
            local label
            if pos == ELEMENT_COUNT then
                label = "Layer " .. pos .. " (Top)"
            elseif pos == 1 then
                label = "Layer " .. pos .. " (Bottom)"
            else
                label = "Layer " .. pos
            end

            local drop = AddDropdownRow(displayIdx <= splitAt and layerLeft or layerRight, {
                label = label,
                indent = true,
                list = BuildStrataList(),
                value = CS.pendingStrataOrder[pos],
                onChange = function(val)
                    for i = 1, ELEMENT_COUNT do
                        if i ~= pos and CS.pendingStrataOrder[i] == val then
                            CS.pendingStrataOrder[i] = nil
                        end
                    end
                    CS.pendingStrataOrder[pos] = val

                    if CS.IsStrataOrderComplete(CS.pendingStrataOrder) then
                        style.strataOrder = {}
                        for i = 1, ELEMENT_COUNT do
                            style.strataOrder[i] = CS.pendingStrataOrder[i]
                        end
                    else
                        style.strataOrder = {}
                    end
                    CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)

                    RefreshAllDropdowns()
                end,
            })
            strataDropdowns[pos] = drop
        end
    end -- customStrataEnabled
    end -- not strataCollapsed

end

ST._BuildLayoutTab = BuildLayoutTab
