local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon

local CooldownLogic = ST.CooldownLogic or {}
local STATE_COOLDOWN = CooldownLogic.STATE_COOLDOWN

local DEFAULT_MAX_ROWS = 16

local function IsTrue(value)
    return value == true
end

local function IsFrameShown(frame)
    if frame and type(frame.IsShown) == "function" then
        return frame:IsShown() == true
    end
    return frame ~= nil
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

local function CountRows(rows)
    return type(rows) == "table" and #rows or 0
end

local function SortIds(a, b)
    local an = tonumber(a)
    local bn = tonumber(b)
    if an and bn then
        return an < bn
    end
    return tostring(a) < tostring(b)
end

local function GetSortedFrameIds(frames)
    local ids = {}
    if type(frames) == "table" then
        for groupId in pairs(frames) do
            ids[#ids + 1] = groupId
        end
        table.sort(ids, SortIds)
    end
    return ids
end

local function GetButtonIndex(button, fallbackIndex)
    return button and (button.index or button._buttonIndex) or fallbackIndex
end

local function GetDisplayMode(addon, groupId, button, frame)
    local group = addon
        and addon.db
        and addon.db.profile
        and addon.db.profile.groups
        and addon.db.profile.groups[groupId]

    return group and group.displayMode
        or button and button._displayMode
        or frame and frame.displayMode
end

local function ResolveSelection(options)
    options = options or {}
    local selectedGroupId = options.groupId
    local selectedButtonIndex = options.buttonIndex
    local CS = ST._configState

    if selectedGroupId == nil and CS then
        selectedGroupId = CS.selectedGroup
    end
    if selectedButtonIndex == nil and CS then
        selectedButtonIndex = CS.selectedButton
    end

    return selectedGroupId, selectedButtonIndex
end

local function BuildRow(addon, groupId, frame, button, fallbackIndex, source)
    local row = {
        groupId = groupId,
        buttonIndex = GetButtonIndex(button, fallbackIndex),
        source = source,
        frameShown = IsFrameShown(frame),
        buttonShown = IsFrameShown(button),
    }

    local buttonData = button and button.buttonData
    if type(buttonData) == "table" then
        row.buttonType = buttonData.type
        row.buttonId = buttonData.id or buttonData.spellID or buttonData.itemID
        row.buttonName = buttonData.name
    end

    row.displayMode = GetDisplayMode(addon, groupId, button, frame)

    local state = button and button._visualState
    if type(state) ~= "table" then
        row.missingSnapshot = true
        AddMismatch(row, "snapshot.missing")
        return row
    end

    row.snapshotVersion = state.version
    row.phase = state.phase

    local cooldown = state.cooldown or {}
    local presentation = state.presentation or {}
    local charges = state.charges or {}
    local visibility = state.visibility or {}
    local desaturation = state.desaturation or {}
    local icon = state.icon or {}
    local iconDesaturation = icon.desaturation or {}
    local tint = state.tint or {}
    local iconFill = state.iconFill or {}
    local ready = state.ready or {}
    local glows = state.glows or {}
    local text = state.text or {}
    local textureEffects = state.textureEffects or {}
    local tintActive
    if tint.intentAvailable == true then
        tintActive = IsTrue(tint.intentActive)
    else
        tintActive = IsTrue(tint.unusableActive)
    end

    row.cooldown = {
        state = cooldown.state,
        active = cooldown.active,
        visualActive = state.cooldownVisualActive,
        source = cooldown.source,
        presentationState = cooldown.presentationState or presentation.presentationState,
        durationObj = cooldown.durationObj ~= nil,
        gcdOnly = presentation.gcdOnly,
        isOnGCD = presentation.isOnGCD,
        showGCDSwipe = presentation.showGCDSwipe,
    }
    row.charges = {
        state = charges.state,
        zero = charges.zero,
        recharging = charges.recharging,
        durationObj = charges.durationObj ~= nil,
        currentReadable = charges.currentReadable,
    }
    row.visibility = {
        hidden = visibility.hidden,
        alphaOverride = visibility.alphaOverride,
        rawHidden = visibility.rawHidden,
        rawAlphaOverride = visibility.rawAlphaOverride,
        reasonBits = visibility.reasonBits,
        reasonMode = visibility.reasonMode,
        lastAlpha = visibility.lastAlpha,
    }
    row.visuals = {
        desaturationActive = desaturation.active,
        desaturationIntentActive = iconDesaturation.active,
        desaturationIntentReason = iconDesaturation.reason,
        desaturationApplied = desaturation.applied,
        desaturationReason = desaturation.reason,
        tintActive = tintActive,
        tintUnusableActive = tint.unusableActive,
        tintIntentAvailable = tint.intentAvailable,
        tintIntentActive = tint.intentActive,
        tintIntentReason = tint.intentReason,
        tintIntentUnusableActive = tint.intentUnusableActive,
        tintIntentR = tint.intentR,
        tintIntentG = tint.intentG,
        tintIntentB = tint.intentB,
        tintIntentA = tint.intentA,
        tintR = tint.r,
        tintG = tint.g,
        tintB = tint.b,
        tintA = tint.a,
        iconFillActive = iconFill.active,
        iconFillMode = iconFill.mode,
        iconFillAuraActive = iconFill.auraActive,
        iconFillOnUpdateInstalled = iconFill.onUpdateInstalled,
        iconFillR = iconFill.r,
        iconFillG = iconFill.g,
        iconFillB = iconFill.b,
        iconFillA = iconFill.a,
        iconFillIntentAvailable = iconFill.intentAvailable,
        iconFillIntentFillAvailable = iconFill.intentFillAvailable,
        iconFillIntentActive = iconFill.intentActive,
        iconFillIntentMode = iconFill.intentMode,
        iconFillIntentReason = iconFill.intentReason,
        iconFillIntentAuraActive = iconFill.intentAuraActive,
        iconFillIntentStatic = iconFill.intentStatic,
        iconFillIntentUsesOnUpdate = iconFill.intentUsesOnUpdate,
        iconFillIntentSuppressCooldownSwipe = iconFill.intentSuppressCooldownSwipe,
        iconFillIntentSuppressAuraBlizzardSwipe = iconFill.intentSuppressAuraBlizzardSwipe,
        iconFillIntentR = iconFill.intentR,
        iconFillIntentG = iconFill.intentG,
        iconFillIntentB = iconFill.intentB,
        iconFillIntentA = iconFill.intentA,
        readyEligible = ready.eligible,
        readyGlowActive = ready.glowActive,
        procGlowActive = glows.procActive,
        auraGlowActive = glows.auraActive,
    }
    row.text = {
        available = text.available,
        unusable = text.unusable,
        outOfRange = text.outOfRange,
        chargeState = text.chargeState,
        durationObj = text.durationObj ~= nil,
    }
    row.textureEffects = {
        ready = textureEffects.ready,
        cooldownActive = textureEffects.cooldownActive,
        chargeState = textureEffects.chargeState,
        procActive = textureEffects.procActive,
    }

    CompareValue(row, "cooldown.state", cooldown.state, button._cooldownState)
    CompareValue(row, "cooldown.active", cooldown.active, button._cooldownState == STATE_COOLDOWN)
    CompareValue(row, "cooldown.durationObj", cooldown.durationObj ~= nil, button._durationObj ~= nil)
    CompareValue(row, "cooldown.visualActive", state.cooldownVisualActive, IsTrue(button._desatCooldownActive))
    CompareValue(row, "presentation.barGCDSuppressed", presentation.barGCDSuppressed, IsTrue(button._barGCDSuppressed))
    CompareValue(row, "charges.state", charges.state, button._chargeState)
    CompareValue(row, "visibility.hidden", visibility.hidden, IsTrue(button._visibilityHidden))
    CompareValue(row, "visibility.alphaOverride", visibility.alphaOverride, button._visibilityAlphaOverride)
    CompareValue(row, "visibility.lastAlpha", visibility.lastAlpha, button._lastVisAlpha)
    local compareVisibleIconIntent = row.displayMode == "icons"
        and row.phase == "post-dispatch"
        and visibility.hidden ~= true
    if compareVisibleIconIntent then
        CompareValue(row, "desaturation.intent", iconDesaturation.active, IsTrue(button._desaturated))
    end
    CompareValue(row, "desaturation.applied", desaturation.applied, IsTrue(button._desaturated))
    CompareValue(row, "tint.unusableActive", tint.unusableActive, IsTrue(button._unusableTintActive))
    CompareValue(row, "tint.r", tint.r, button._vertexR)
    CompareValue(row, "tint.g", tint.g, button._vertexG)
    CompareValue(row, "tint.b", tint.b, button._vertexB)
    CompareValue(row, "tint.a", tint.a, button._vertexA)
    if compareVisibleIconIntent and tint.intentAvailable == true then
        CompareValue(row, "tint.intent.unusableActive", tint.intentUnusableActive, tint.unusableActive)
        CompareValue(row, "tint.intent.r", tint.intentR, tint.r)
        CompareValue(row, "tint.intent.g", tint.intentG, tint.g)
        CompareValue(row, "tint.intent.b", tint.intentB, tint.b)
        CompareValue(row, "tint.intent.a", tint.intentA, tint.a)
    end
    CompareValue(row, "iconFill.active", iconFill.active, IsTrue(button._iconFillActive))
    CompareValue(row, "iconFill.mode", iconFill.mode, button._iconFillMode)
    CompareValue(row, "iconFill.auraActive", iconFill.auraActive, IsTrue(button._iconFillAuraActive))
    CompareValue(row, "iconFill.onUpdateInstalled", iconFill.onUpdateInstalled, IsTrue(button._iconFillOnUpdateInstalled))
    if compareVisibleIconIntent and iconFill.intentAvailable == true then
        CompareValue(row, "iconFill.intent.active", iconFill.intentActive, iconFill.active)
        CompareValue(row, "iconFill.intent.mode", iconFill.intentMode, iconFill.mode)
        CompareValue(row, "iconFill.intent.auraActive", iconFill.intentAuraActive, iconFill.auraActive)
        CompareValue(row, "iconFill.intent.usesOnUpdate", iconFill.intentUsesOnUpdate, iconFill.onUpdateInstalled)
        if iconFill.intentActive == true then
            CompareValue(row, "iconFill.intent.r", iconFill.intentR, iconFill.r)
            CompareValue(row, "iconFill.intent.g", iconFill.intentG, iconFill.g)
            CompareValue(row, "iconFill.intent.b", iconFill.intentB, iconFill.b)
            CompareValue(row, "iconFill.intent.a", iconFill.intentA, iconFill.a)
        end
    end
    CompareValue(row, "ready.glowActive", ready.glowActive, IsTrue(button._readyGlowActive))
    CompareValue(row, "glows.procActive", glows.procActive, IsTrue(button._procGlowActive))
    CompareValue(row, "glows.auraActive", glows.auraActive, IsTrue(button._auraGlowActive))
    CompareValue(row, "text.unusable", text.unusable, IsTrue(button._isUnusable))
    CompareValue(row, "text.outOfRange", text.outOfRange, IsTrue(button._isOutOfRange))
    CompareValue(row, "text.durationObj", text.durationObj ~= nil, button._durationObj ~= nil)
    CompareValue(row, "textureEffects.cooldownActive", textureEffects.cooldownActive, IsTrue(button._desatCooldownActive))
    CompareValue(row, "textureEffects.chargeState", textureEffects.chargeState, button._chargeState)
    CompareValue(row, "textureEffects.procActive", textureEffects.procActive, IsTrue(button._procOverlayActive))

    return row
end

local function AddButtonRow(addon, result, seen, groupId, frame, button, fallbackIndex, source)
    if CountRows(result.rows) >= result.maxRows then
        result.truncated = true
        return false
    end

    if type(button) ~= "table" then
        return true
    end

    local buttonIndex = GetButtonIndex(button, fallbackIndex)
    local key = tostring(groupId or "?") .. ":" .. tostring(buttonIndex or fallbackIndex or "?")
    if seen[key] then
        return true
    end
    seen[key] = true

    local row = BuildRow(addon, groupId, frame, button, fallbackIndex, source)
    result.rows[#result.rows + 1] = row
    result.rowCount = #result.rows
    if row.missingSnapshot then
        result.missingSnapshots = result.missingSnapshots + 1
    end
    if type(row.mismatches) == "table" and #row.mismatches > 0 then
        result.mismatchCount = result.mismatchCount + 1
    end

    return true
end

local function RefreshFrames(addon, selectedGroupId, options)
    local frames = addon and addon.groupFrames
    if type(frames) ~= "table" then
        return 0
    end

    local refreshed = 0
    for _, groupId in ipairs(GetSortedFrameIds(frames)) do
        local frame = frames[groupId]
        local isSelected = selectedGroupId ~= nil and groupId == selectedGroupId
        local shouldRefresh = frame
            and type(frame.UpdateCooldowns) == "function"
            and (options.includeHiddenFrames or isSelected or IsFrameShown(frame))
        if shouldRefresh then
            frame:UpdateCooldowns()
            refreshed = refreshed + 1
        end
    end
    return refreshed
end

local function ClearCapturedSnapshots(addon, selectedGroupId, options)
    local ClearButtonVisualState = ST._ClearButtonVisualState
    if type(ClearButtonVisualState) ~= "function" then
        return 0
    end

    local frames = addon and addon.groupFrames
    if type(frames) ~= "table" then
        return 0
    end

    local cleared = 0
    for _, groupId in ipairs(GetSortedFrameIds(frames)) do
        local frame = frames[groupId]
        local isSelected = selectedGroupId ~= nil and groupId == selectedGroupId
        if frame and type(frame.buttons) == "table" and (options.includeHiddenFrames or isSelected or IsFrameShown(frame)) then
            for _, button in ipairs(frame.buttons) do
                ClearButtonVisualState(button)
                cleared = cleared + 1
            end
        end
    end

    return cleared
end

local function CollectButtonVisualStateDiagnostics(addon, options)
    options = options or {}

    local maxRows = tonumber(options.maxRows) or DEFAULT_MAX_ROWS
    if maxRows < 1 then
        maxRows = 1
    end

    local result = {
        enabled = true,
        maxRows = maxRows,
        rowCount = 0,
        missingSnapshots = 0,
        mismatchCount = 0,
        refreshedFrames = options.refreshedFrames or 0,
        rows = {},
    }

    local frames = addon and addon.groupFrames
    if type(frames) ~= "table" then
        return result
    end

    local selectedGroupId, selectedButtonIndex = ResolveSelection(options)
    local seen = {}

    if selectedGroupId ~= nil then
        local selectedFrame = frames[selectedGroupId]
        if selectedFrame and type(selectedFrame.buttons) == "table" then
            if selectedButtonIndex ~= nil then
                for fallbackIndex, button in ipairs(selectedFrame.buttons) do
                    if GetButtonIndex(button, fallbackIndex) == selectedButtonIndex then
                        AddButtonRow(addon, result, seen, selectedGroupId, selectedFrame, button, fallbackIndex, "selected")
                        break
                    end
                end
            end
            if selectedButtonIndex == nil or options.includeSelectedPanel == true then
                for fallbackIndex, button in ipairs(selectedFrame.buttons) do
                    if not AddButtonRow(addon, result, seen, selectedGroupId, selectedFrame, button, fallbackIndex, "selected-panel") then
                        return result
                    end
                end
            end
        end
    end

    for _, groupId in ipairs(GetSortedFrameIds(frames)) do
        local frame = frames[groupId]
        if frame and type(frame.buttons) == "table" and (options.includeHiddenFrames or IsFrameShown(frame)) then
            for fallbackIndex, button in ipairs(frame.buttons) do
                if not AddButtonRow(addon, result, seen, groupId, frame, button, fallbackIndex, "visible") then
                    return result
                end
            end
        end
    end

    return result
end

local function CaptureButtonVisualStateDiagnostics(addon, options)
    options = options or {}

    local AreSnapshotsEnabled = ST._AreButtonVisualStateSnapshotsEnabled
    local SetSnapshotsEnabled = ST._SetButtonVisualStateSnapshotsEnabled
    if type(AreSnapshotsEnabled) ~= "function" or type(SetSnapshotsEnabled) ~= "function" then
        return {
            enabled = false,
            reason = "snapshot-helpers-missing",
            maxRows = tonumber(options.maxRows) or DEFAULT_MAX_ROWS,
            rowCount = 0,
            missingSnapshots = 0,
            mismatchCount = 0,
            rows = {},
        }
    end

    local selectedGroupId = ResolveSelection(options)
    local wasEnabled = AreSnapshotsEnabled()
    SetSnapshotsEnabled(true)

    local refreshed = RefreshFrames(addon, selectedGroupId, options)
    local result = CollectButtonVisualStateDiagnostics(addon, options)
    result.refreshedFrames = refreshed
    result.captureWasEnabled = wasEnabled
    if not wasEnabled and options.preserveSnapshots ~= true then
        result.clearedSnapshots = ClearCapturedSnapshots(addon, selectedGroupId, options)
    end

    SetSnapshotsEnabled(wasEnabled)
    result.captureRestored = AreSnapshotsEnabled() == wasEnabled

    return result
end

function CooldownCompanion:CollectButtonVisualStateDiagnostics(options)
    return CollectButtonVisualStateDiagnostics(self, options)
end

function CooldownCompanion:CaptureButtonVisualStateDiagnostics(options)
    return CaptureButtonVisualStateDiagnostics(self, options)
end

ST._CollectButtonVisualStateDiagnostics = CollectButtonVisualStateDiagnostics
ST._CaptureButtonVisualStateDiagnostics = CaptureButtonVisualStateDiagnostics
