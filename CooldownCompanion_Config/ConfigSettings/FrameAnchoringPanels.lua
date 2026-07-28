local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon
local AceGUI = LibStub("AceGUI-3.0")
local CS = ST._configState

-- Imports from Helpers.lua
local BuildCollapsibleSection = ST._BuildCollapsibleSection
local CreateCharacterCopyButton = ST._CreateCharacterCopyButton

-- Imports from RowWidgets.lua (the row grammar). The rules every row-grammar
-- section follows are stated once, in the recipe comment at the top of
-- BuildAppearanceTab's icons path (GroupTabs.lua); this file conforms to them
-- rather than restating them.
local AddCheckboxRow = ST._AddCheckboxRow
local AddSliderRow = ST._AddSliderRow
local AddDropdownRow = ST._AddDropdownRow
local AddEditBoxRow = ST._AddEditBoxRow
local BeginRowGrid = ST._BeginRowGrid

-- Row-grammar section headers: caret far left, label, then a class-colored
-- rule fading right.
local ROW_SECTION = { leftAligned = true }

-- The unit-frame addon names run well past the 140px control column, and a
-- dropdown sizes its menu from the control.
local UNIT_FRAME_PULLOUT_WIDTH = 300

------------------------------------------------------------------------
-- Frame Anchoring panels
------------------------------------------------------------------------

local ANCHOR_POINTS = {
    "TOPLEFT", "TOP", "TOPRIGHT",
    "LEFT", "CENTER", "RIGHT",
    "BOTTOMLEFT", "BOTTOM", "BOTTOMRIGHT",
}
local ANCHOR_POINT_LABELS = {}
for _, p in ipairs(ANCHOR_POINTS) do ANCHOR_POINT_LABELS[p] = p end

local UNIT_FRAME_OPTIONS = {
    [""]         = "Auto-detect",
    blizzard     = "Blizzard Default",
    uuf          = "UnhaltedUnitFrames",
    elvui        = "ElvUI",
    ellesmere    = "EllesmereUI Unit Frames",
    msuf         = "Midnight Simple Unit Frames",
    custom       = "Custom",
}
local UNIT_FRAME_ORDER = { "", "blizzard", "uuf", "elvui", "ellesmere", "msuf", "custom" }

local function ValidateCustomUnitFrameName(frameName)
    if not frameName or frameName == "" then
        return true
    end
    if not _G[frameName] then
        CooldownCompanion:Print("Frame '" .. frameName .. "' not found.")
        return false
    end
    local options = { domain = "external" }
    local ok = CooldownCompanion:ValidateAddonFrameAnchorTarget(frameName, options)
    if not ok then
        CooldownCompanion:PrintInvalidAnchorTargetReason(frameName, options)
        return false
    end
    return true
end

local function SetCustomUnitFrameName(settings, key, frameName)
    frameName = frameName or ""
    if frameName ~= "" and not ValidateCustomUnitFrameName(frameName) then
        return false
    end
    settings[key] = frameName
    CooldownCompanion:EvaluateFrameAnchoring()
    return true
end

-- A frame name needs the whole 140px control column to stay readable, so Pick
-- does not share it: the name row sits in the grid's LEFT column and its Pick
-- button on the matching line of the RIGHT one. Both columns are List-layout,
-- so line N on the left meets line N on the right across the 16px gutter.
local function AddCustomFrameNameRow(nameLeft, nameRight, settings, key, label)
    AddEditBoxRow(nameLeft, {
        label = label,
        indent = true,
        value = settings[key] or "",
        onEnterPressed = function(text)
            if not SetCustomUnitFrameName(settings, key, text) then
                CooldownCompanion:RefreshConfigPanel()
            end
        end,
    })

    -- Exactly one grammar row tall so the button's centre lands on the
    -- editbox's: Flow insets its single row by 3px and the button is 24 tall,
    -- so 3 + 24 + 3 fills the 30px band. noAutoHeight keeps Flow's own 27px
    -- report from shrinking it back.
    local pickRow = AceGUI:Create("SimpleGroup")
    pickRow:SetFullWidth(true)
    pickRow:SetLayout("Flow")
    pickRow:SetHeight(ST._RowGrammar and ST._RowGrammar.ROW_HEIGHT or 30)
    pickRow.noAutoHeight = true

    local pickBtn = AceGUI:Create("Button")
    pickBtn:SetText("Pick")
    pickBtn:SetAutoWidth(true)
    pickBtn:SetCallback("OnClick", function()
        CS.StartPickFrame(function(name)
            if CS.configFrame then
                CS.configFrame.frame:Show()
            end
            if name then
                SetCustomUnitFrameName(settings, key, name)
            end
            CooldownCompanion:RefreshConfigPanel()
        end, nil, { domain = "external" })
    end)
    pickRow:AddChild(pickBtn)

    -- Added last so the List-layout column measures a populated row.
    nameRight:AddChild(pickRow)
end

-- The nine anchor points, as the two dropdown rows every position section
-- opens with: mine first, then the target's.
local function AddFramePositionRows(posLeft, posRight, frameSettings, anchorDefault, relativeDefault, onChanged)
    AddDropdownRow(posLeft, {
        label = "Anchor Point",
        list = ANCHOR_POINT_LABELS,
        order = ANCHOR_POINTS,
        value = frameSettings.anchorPoint or anchorDefault,
        onChange = function(val)
            frameSettings.anchorPoint = val
            onChanged()
        end,
    })

    AddDropdownRow(posLeft, {
        label = "Relative Anchor Point",
        list = ANCHOR_POINT_LABELS,
        order = ANCHOR_POINTS,
        value = frameSettings.relativePoint or relativeDefault,
        onChange = function(val)
            frameSettings.relativePoint = val
            onChanged()
        end,
    })

    AddSliderRow(posRight, {
        label = "X Offset",
        min = -200, max = 200, step = 0.1,
        value = frameSettings.xOffset or 0,
        onChange = function(val)
            frameSettings.xOffset = val
            CooldownCompanion:ApplyFrameAnchoring()
        end,
    })

    AddSliderRow(posRight, {
        label = "Y Offset",
        min = -200, max = 200, step = 0.1,
        value = frameSettings.yOffset or 0,
        onChange = function(val)
            frameSettings.yOffset = val
            CooldownCompanion:ApplyFrameAnchoring()
        end,
    })
end

local function BuildFrameAnchoringPlayerPanel(container)
    local db = CooldownCompanion.db.profile
    local settings = CooldownCompanion:GetFrameAnchoringSettings()

    -- ================================================================
    -- Frame Anchoring (the module switch, which unit frames it drives, and
    -- what the anchored frames inherit)
    -- ================================================================
    -- The module switch lives INSIDE this section rather than above it: every
    -- row-grammar tab opens on a section header, and a free-standing control
    -- over the first caret has nowhere to belong. Disabling the module ends
    -- the section after one row and builds nothing below it, exactly as the
    -- pre-row panel returned early after the same checkbox.
    local _, anchoringCollapsed = BuildCollapsibleSection(container, "Frame Anchoring",
        "unitframe_player_anchoring", nil, nil, ROW_SECTION)

    if not anchoringCollapsed then
        -- LEFT column: the switch and which unit frames it drives. RIGHT
        -- column: what the target frame and the anchored group take from
        -- elsewhere. The right side is empty until the module is on.
        local generalLeft, generalRight = BeginRowGrid(container)

        local enableRow = AddCheckboxRow(generalLeft, {
            label = "Enable Frame Anchoring",
            value = settings.enabled,
            onChange = function(val)
                settings.enabled = val
                CooldownCompanion:EvaluateFrameAnchoring()
                CooldownCompanion:RefreshConfigPanel()
            end,
        })

        CreateCharacterCopyButton(enableRow, "frameAnchoring", "Frame Anchoring", function()
            CooldownCompanion:EvaluateFrameAnchoring()
            CooldownCompanion:RefreshConfigPanel()
        end)

        if settings.enabled then
            -- Unit-frame addon names run past the control column, so the menu
            -- is widened - a 140px control would otherwise open a 140px menu.
            AddDropdownRow(generalLeft, {
                label = "Unit Frames",
                pulloutWidth = UNIT_FRAME_PULLOUT_WIDTH,
                list = UNIT_FRAME_OPTIONS,
                order = UNIT_FRAME_ORDER,
                value = settings.unitFrameAddon or "",
                onChange = function(val)
                    settings.unitFrameAddon = val ~= "" and val or nil
                    CooldownCompanion:EvaluateFrameAnchoring()
                    CooldownCompanion:RefreshConfigPanel()
                end,
            })

            AddCheckboxRow(generalRight, {
                label = "Mirror target from player",
                value = settings.mirroring,
                onChange = function(val)
                    settings.mirroring = val
                    CooldownCompanion:ApplyFrameAnchoring()
                    CooldownCompanion:RefreshConfigPanel()
                end,
            })

            AddCheckboxRow(generalRight, {
                label = "Inherit group alpha",
                value = settings.inheritAlpha,
                onChange = function(val)
                    settings.inheritAlpha = val
                    CooldownCompanion:ApplyFrameAnchoring()
                end,
            })
        end

        -- Custom frame names (only when "Custom" is selected). Their own grid,
        -- so each name row's Pick button lands beside it rather than under
        -- whatever the section grid above happened to end on.
        if settings.enabled and settings.unitFrameAddon == "custom" then
            local nameLeft, nameRight = BeginRowGrid(container)
            AddCustomFrameNameRow(nameLeft, nameRight, settings, "customPlayerFrame", "Player Frame Name")
            AddCustomFrameNameRow(nameLeft, nameRight, settings, "customTargetFrame", "Target Frame Name")
        end
    end

    if not settings.enabled then return end

    -- ================================================================
    -- Player Frame Position
    -- ================================================================
    local _, positionCollapsed = BuildCollapsibleSection(container, "Player Frame Position",
        "unitframe_player_position", nil, nil, ROW_SECTION)

    if not positionCollapsed then
        -- LEFT column: the two points that have to be read together (mine,
        -- then the frame's). RIGHT column: the offset applied on top of them.
        local posLeft, posRight = BeginRowGrid(container)
        AddFramePositionRows(posLeft, posRight, settings.player, "RIGHT", "LEFT", function()
            CooldownCompanion:ApplyFrameAnchoring()
            CooldownCompanion:RefreshConfigPanel()
        end)
    end
end

local function BuildFrameAnchoringTargetPanel(container)
    local settings = CooldownCompanion:GetFrameAnchoringSettings()

    -- The module switch, as on the Player Frame panel: either frame can be
    -- selected on its own in the workspace, so each one has to be able to
    -- turn frame anchoring on rather than pointing at the other.
    local _, anchoringCollapsed = BuildCollapsibleSection(container, "Frame Anchoring",
        "unitframe_target_anchoring", nil, nil, ROW_SECTION)

    if not anchoringCollapsed then
        -- One switch with nothing to pair it against, so the left column
        -- carries it alone.
        local generalLeft = BeginRowGrid(container)

        AddCheckboxRow(generalLeft, {
            label = "Enable Frame Anchoring",
            value = settings.enabled,
            onChange = function(val)
                settings.enabled = val
                CooldownCompanion:EvaluateFrameAnchoring()
                CooldownCompanion:RefreshConfigPanel()
            end,
        })
    end

    if not settings.enabled then return end

    if settings.mirroring then
        -- Mirrored: there is no independent position to show, so the notice
        -- takes the place of the position section rather than sitting in it.
        local infoLabel = AceGUI:Create("Label")
        ST._ConfigureWrappedHelperLabel(infoLabel)
        infoLabel:SetText("Target frame is mirrored from player frame settings.")
        infoLabel:SetFullWidth(true)
        container:AddChild(infoLabel)
        return
    end

    -- ================================================================
    -- Target Frame Position
    -- ================================================================
    local _, positionCollapsed = BuildCollapsibleSection(container, "Target Frame Position",
        "unitframe_target_position", nil, nil, ROW_SECTION)

    if not positionCollapsed then
        -- Same split as the player panel: the two points on the left, the
        -- offset applied on top of them on the right.
        local posLeft, posRight = BeginRowGrid(container)
        AddFramePositionRows(posLeft, posRight, settings.target, "LEFT", "RIGHT", function()
            CooldownCompanion:ApplyFrameAnchoring()
        end)
    end
end

-- Expose for ButtonSettings.lua and Config.lua
ST._BuildFrameAnchoringPlayerPanel = BuildFrameAnchoringPlayerPanel
ST._BuildFrameAnchoringTargetPanel = BuildFrameAnchoringTargetPanel
