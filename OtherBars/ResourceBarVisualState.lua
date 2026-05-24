--[[
    CooldownCompanion - ResourceBarVisualState
    Pull-based visual-state capture for OtherBars resource, health, and custom bars.

    This module is intentionally separate from ButtonFrame visual state. Resource
    bars are stack-owned and OnUpdate-driven, so diagnostics capture renderer-owned
    facts only when an explicit report asks for them.
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon

local RB = ST._RB
local DEFAULT_MAX_ROWS = 16
local SNAPSHOT_VERSION = 1

local function WipeTable(tbl)
    if wipe then
        wipe(tbl)
        return tbl
    end
    for key in pairs(tbl) do
        tbl[key] = nil
    end
    return tbl
end

local function IsTrue(value)
    return value == true
end

local function IsFrameShown(frame)
    if frame and type(frame.IsShown) == "function" then
        return frame:IsShown() == true
    end
    return frame ~= nil
end

local function CopyPlainTable(source, depth)
    if type(source) ~= "table" then
        return source
    end
    if depth and depth <= 0 then
        return nil
    end

    local nextDepth = depth and (depth - 1) or nil
    local copy = {}
    for key, value in pairs(source) do
        if type(value) == "table" then
            copy[key] = CopyPlainTable(value, nextDepth)
        elseif type(value) ~= "function" and type(value) ~= "userdata" and type(value) ~= "thread" then
            copy[key] = value
        end
    end
    return copy
end

local function AddMismatch(row, key)
    local mismatches = row.mismatches
    if type(mismatches) ~= "table" then
        mismatches = {}
        row.mismatches = mismatches
    end
    mismatches[#mismatches + 1] = key
end

local function CompareValue(row, key, actual, expected)
    if actual ~= expected then
        AddMismatch(row, key)
    end
end

local function ResolveRowKind(barInfo)
    local barType = barInfo and barInfo.barType
    if barType == "health_continuous" then
        return "health"
    end
    if barInfo and (barInfo.customBarId ~= nil or barInfo.cabConfig ~= nil) then
        return "custom"
    end
    return "resource"
end

local function GetCustomBarId(barInfo)
    if not barInfo then
        return nil
    end
    local customBarId = barInfo.customBarId
    if customBarId ~= nil then
        return customBarId
    end
    local config = barInfo.cabConfig
    return config and config.customBarId or nil
end

local function GetSpellID(barInfo)
    local config = barInfo and barInfo.cabConfig
    if not config then
        return nil
    end
    return tonumber(config.spellID) or config.spellID
end

local function StoreOtherBarsVisualState(frame, details)
    if not IsTrue(RB._otherBarsVisualStateCaptureEnabled) or not frame then
        return nil
    end

    local state = frame._otherBarsVisualState
    if type(state) ~= "table" then
        state = {}
        frame._otherBarsVisualState = state
    else
        WipeTable(state)
    end

    details = details or {}
    state.version = SNAPSHOT_VERSION
    state.phase = details.phase
    state.rowKind = details.rowKind
    state.identity = CopyPlainTable(details.identity, 2)
    state.visibility = CopyPlainTable(details.visibility, 2)
    state.resource = CopyPlainTable(details.resource, 3)
    state.health = CopyPlainTable(details.health, 3)
    state.custom = CopyPlainTable(details.custom, 3)
    state.text = CopyPlainTable(details.text, 3)
    state.effects = CopyPlainTable(details.effects, 3)
    state.bar = CopyPlainTable(details.bar, 3)
    return state
end

local function ClearOtherBarsVisualState(frame)
    if frame then
        frame._otherBarsVisualState = nil
    end
end

local function SetOtherBarsVisualStateCaptureEnabled(enabled)
    RB._otherBarsVisualStateCaptureEnabled = enabled == true
end

local function AreOtherBarsVisualStateCaptureEnabled()
    return RB._otherBarsVisualStateCaptureEnabled == true
end

local function BuildRow(barInfo, index, source)
    local frame = barInfo and barInfo.frame
    local rowKind = ResolveRowKind(barInfo)
    local row = {
        index = index,
        source = source,
        rowKind = rowKind,
        barType = barInfo and barInfo.barType,
        powerType = barInfo and barInfo.powerType,
        customBarId = GetCustomBarId(barInfo),
        customBarIndex = barInfo and barInfo.customBarIndex,
        spellID = GetSpellID(barInfo),
        shown = IsFrameShown(frame),
    }

    local config = barInfo and barInfo.cabConfig
    if config then
        row.hideWhenInactive = config.hideWhenInactive == true
        row.hideWhileAuraActive = config.hideWhileAuraActive == true
        row.trackingMode = config.trackingMode
        row.auraTracking = config.auraTracking == true
    end

    local state = frame and frame._otherBarsVisualState
    if type(state) ~= "table" then
        row.missingState = true
        AddMismatch(row, "state.missing")
        return row
    end

    row.snapshotVersion = state.version
    row.phase = state.phase
    row.visibility = CopyPlainTable(state.visibility, 2)
    row.resource = CopyPlainTable(state.resource, 3)
    row.health = CopyPlainTable(state.health, 3)
    row.custom = CopyPlainTable(state.custom, 3)
    row.text = CopyPlainTable(state.text, 3)
    row.effects = CopyPlainTable(state.effects, 3)
    row.bar = CopyPlainTable(state.bar, 3)

    CompareValue(row, "snapshot.version", state.version, SNAPSHOT_VERSION)
    if state.rowKind then
        CompareValue(row, "row.kind", state.rowKind, rowKind)
    end
    if type(state.identity) == "table" then
        CompareValue(row, "identity.barType", state.identity.barType, row.barType)
        CompareValue(row, "identity.powerType", state.identity.powerType, row.powerType)
        CompareValue(row, "identity.customBarId", state.identity.customBarId, row.customBarId)
    end
    if type(state.visibility) == "table" and state.visibility.shown ~= nil then
        CompareValue(row, "visibility.shown", state.visibility.shown, row.shown)
    end

    return row
end

local function RowKey(index)
    return tostring(index or "?")
end

local function AddRow(result, seen, barInfo, index, source)
    if result.rowCount >= result.maxRows then
        result.truncated = true
        return false
    end

    local key = RowKey(index)
    if seen[key] then
        return true
    end
    seen[key] = true

    local row = BuildRow(barInfo, index, source)
    result.rows[#result.rows + 1] = row
    result.rowCount = result.rowCount + 1
    if row.missingState then
        result.missingStates = result.missingStates + 1
    end
    if type(row.mismatches) == "table" and #row.mismatches > 0 then
        result.mismatchCount = result.mismatchCount + 1
    end
    return true
end

local function ResolveSelection(options)
    options = options or {}
    local selectedIndex = tonumber(options.resourceBarIndex)
    local selectedCustomBarId = options.customBarId
    local CS = ST._configState
    if selectedCustomBarId == nil and CS then
        selectedCustomBarId = CS.selectedCustomBarId or CS.selectedCustomBar
    end
    return selectedIndex, selectedCustomBarId
end

local function CollectOtherBarsVisualStateDiagnostics(addon, options)
    options = options or {}
    local maxRows = tonumber(options.maxRows) or DEFAULT_MAX_ROWS
    if maxRows < 1 then
        maxRows = 1
    end

    local result = {
        enabled = true,
        maxRows = maxRows,
        rowCount = 0,
        missingStates = 0,
        mismatchCount = 0,
        refreshedRows = tonumber(options.refreshedRows) or 0,
        captureRestored = options.captureRestored,
        stack = CopyPlainTable(options.stack, 2),
        rows = {},
    }

    local frames = options.resourceBarFrames
    if type(frames) ~= "table" then
        return result
    end

    local seen = {}
    local selectedIndex, selectedCustomBarId = ResolveSelection(options)
    if selectedIndex then
        local barInfo = frames[selectedIndex]
        if barInfo and not AddRow(result, seen, barInfo, selectedIndex, "selected") then
            return result
        end
    elseif selectedCustomBarId ~= nil then
        for index, barInfo in ipairs(frames) do
            if GetCustomBarId(barInfo) == selectedCustomBarId then
                if not AddRow(result, seen, barInfo, index, "selected-custom-bar") then
                    return result
                end
                break
            end
        end
    end

    for index, barInfo in ipairs(frames) do
        if not AddRow(result, seen, barInfo, index, "stack") then
            return result
        end
    end

    return result
end

local function ClearCapturedOtherBarsVisualStates(resourceBarFrames)
    local cleared = 0
    if type(resourceBarFrames) ~= "table" then
        return cleared
    end
    for _, barInfo in ipairs(resourceBarFrames) do
        local frame = barInfo and barInfo.frame
        if frame and frame._otherBarsVisualState then
            frame._otherBarsVisualState = nil
            cleared = cleared + 1
        end
    end
    return cleared
end

RB.StoreOtherBarsVisualState = StoreOtherBarsVisualState
RB.ClearOtherBarsVisualState = ClearOtherBarsVisualState
RB.SetOtherBarsVisualStateCaptureEnabled = SetOtherBarsVisualStateCaptureEnabled
RB.AreOtherBarsVisualStateCaptureEnabled = AreOtherBarsVisualStateCaptureEnabled
RB.CollectOtherBarsVisualStateDiagnostics = CollectOtherBarsVisualStateDiagnostics
RB.ClearCapturedOtherBarsVisualStates = ClearCapturedOtherBarsVisualStates

ST._StoreOtherBarsVisualState = StoreOtherBarsVisualState
ST._ClearOtherBarsVisualState = ClearOtherBarsVisualState
ST._CollectOtherBarsVisualStateDiagnostics = CollectOtherBarsVisualStateDiagnostics
