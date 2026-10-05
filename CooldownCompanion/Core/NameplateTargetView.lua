--[[
    CooldownCompanion - Core/NameplateTargetView.lua: nameplate reminders
    drawn on your hostile target's real nameplate, out of combat.

    Two callers want the same picture (owner rulings 2026-10-04):
      * the config's Live Preview of a nameplate Indicator (SetPreview), and
      * unlock mode: every unlocked nameplate Indicator (NoteUnlocked, from
        the Indicator visibility state), with mover chrome: a name and
        padlock header and the plate offset under the row. Drag the row or
        its header to move it; right-click opens its Layout settings.
    Plain CC copies, never watchers, always the missing look. Never in combat:
    unlock is force-locked and the config closes then. Nothing runs while
    neither caller wants it.

    Enemy nameplates are restricted regions (CC_PlateDragProbe v1-v2, live
    12.1, 2026-10-04): nothing positioned off a plate can be measured, so this
    chrome never measures (no GetCenter, no IsMouseOver hover fades, no
    UIDropDownMenu, which measures its list and taints Blizzard's shared one).
    Dragging reads only the cursor and the frame's effective scale.
]]

local _, ST = ...
local CooldownCompanion = ST.Addon

local V = {}
ST._NameplateTargetView = V

local CHROME_WIDTH = 120

local preview = { group = nil, groupId = nil, onPlaced = nil }
local unlocked = {}   -- groupId -> true while that nameplate Indicator is unlocked
local rows = {}       -- "preview" or groupId -> row
local events = CreateFrame("Frame")
local eventsOn, pending, inCombat = false, false, false
local drawnPlate   -- the plate the rows hang off, or nil
local unlockHint   -- screen label while unlocked with no hostile target
local toolbarHooked = false

local function TargetPlate()
    if inCombat or InCombatLockdown() then return nil end
    if not UnitExists("target") or not UnitCanAttack("player", "target") then return nil end
    return C_NamePlate.GetNamePlateForUnit("target")
end

local function SavedGroup(groupId)
    return groupId and CooldownCompanion.db.profile.groups[groupId] or nil
end

------------------------------------------------------------------------
-- Mover chrome (unlocked Indicators only)
------------------------------------------------------------------------

local function UpdateCoordText(row)
    local group = SavedGroup(row.groupId)
    local placement = group and ST.Indicator.NameplatePlacement(group)
    if placement and row.coordLabel then
        row.coordLabel.text:SetText(("x:%.1f, y:%.1f"):format(placement.x, placement.y))
    end
end

local function Commit(row)
    local groupId = row.groupId
    if not SavedGroup(groupId) then return end
    CooldownCompanion:RequestAuraRebind("style", groupId)
    if ST._RefreshButtonsPreviewMirror then ST._RefreshButtonsPreviewMirror(groupId) end
end

-- Re-anchor the row box from the saved offset (during a drag: no redraw).
local function AnchorHolder(row, group)
    local plate = row.holder:GetParent()
    local point, x, y = ST._NameplateReminders.RowBox(group, #ST.Indicator.AuraList(group))
    row.holder:ClearAllPoints()
    row.holder:SetPoint("CENTER", plate, point, x, y)
end

-- New plate offset, rounded like every coordinate label.
local function SetOffset(row, x, y)
    local group = SavedGroup(row.groupId)
    if not group then return end
    local placement = ST.Indicator.NameplatePlacement(group)
    placement.x = math.floor(x * 10 + 0.5) / 10
    placement.y = math.floor(y * 10 + 0.5) / 10
    -- The preview row draws the config's staged copy: keep it in step.
    if preview.group and preview.groupId == row.groupId then
        local staged = ST.Indicator.NameplatePlacement(preview.group)
        staged.x, staged.y = placement.x, placement.y
    end
    UpdateCoordText(row)
    AnchorHolder(row, preview.groupId == row.groupId and preview.group or group)
end

local function DragUpdate(row)
    local drag = row.drag
    if not drag then return end
    local x, y = GetCursorPosition()
    SetOffset(row, drag.x + (x - drag.cursorX) / drag.scale, drag.y + (y - drag.cursorY) / drag.scale)
end

local function BeginDrag(row)
    local group = SavedGroup(row.groupId)
    if not group or row.drag then return end
    local placement = ST.Indicator.NameplatePlacement(group)
    local cursorX, cursorY = GetCursorPosition()
    row.drag = { cursorX = cursorX, cursorY = cursorY, x = placement.x, y = placement.y,
        scale = row.holder:GetEffectiveScale() }
    row.holder:SetScript("OnUpdate", function() DragUpdate(row) end)
end

local function EndDrag(row)
    if not row.drag then return end
    DragUpdate(row)
    row.drag = nil
    row.holder:SetScript("OnUpdate", nil)
    Commit(row)
end

local function OpenSettings(row)
    local group = SavedGroup(row.groupId)
    if not group then return end
    CooldownCompanion:OpenMoverLayoutSettings({
        kind = "panel",
        id = row.groupId,
        containerId = group.parentContainerId,
    })
end

-- Left-drag moves the row, right-click opens its settings: for the row box
-- and its header alike.
local function WireMouse(frame, row)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function() BeginDrag(row) end)
    frame:SetScript("OnDragStop", function() EndDrag(row) end)
    frame:SetScript("OnMouseUp", function(_, button)
        if button == "RightButton" and not row.drag then OpenSettings(row) end
    end)
end

local function EnsureChrome(row)
    if row.header then return end
    local holder = row.holder
    -- MoverChrome.CreateHeader's menu button opens a UIDropDownMenu, so the
    -- header is built from the plain label plus the padlock.
    local header = ST.MoverChrome.CreateLabel(holder)
    header:SetWidth(CHROME_WIDTH)
    header:SetPoint("BOTTOM", holder, "TOP", 0, 2)
    header.lockButton = ST.CreateMoverLockBadge(header, 12, function()
        ST._LockIndicatorPanel(row.groupId)
    end)
    header.lockButton:SetPoint("RIGHT", header, "RIGHT", -2, 0)
    header.text:ClearAllPoints()
    header.text:SetPoint("LEFT", header, "LEFT", 16, 0)
    header.text:SetPoint("RIGHT", header.lockButton, "LEFT", -2, 0)
    WireMouse(header, row)
    row.header = header

    row.coordLabel = ST.MoverChrome.CreateLabel(holder)
    row.coordLabel:SetWidth(CHROME_WIDTH)
    row.coordLabel:SetPoint("TOP", holder, "BOTTOM", 0, -2)
end

local function SetChrome(row, groupId)
    if row.drag and row.groupId ~= groupId then EndDrag(row) end
    row.groupId = groupId
    if groupId then
        EnsureChrome(row)
        local group = SavedGroup(groupId)
        row.header.text:SetText(group and group.name or "Indicator")
        UpdateCoordText(row)
        row.header:Show()
        row.coordLabel:Show()
        WireMouse(row.holder, row)
    else
        if row.header then
            row.header:Hide()
            row.coordLabel:Hide()
        end
        row.holder:EnableMouse(false)
        row.holder:RegisterForDrag()
    end
end

-- Unlocked with nowhere to draw (no hostile target): say what's needed
-- rather than show nothing, which reads as broken. A plain screen label,
-- never on a plate.
local ShowUnlockHint
function ShowUnlockHint(shown)
    if not shown then
        if unlockHint then unlockHint:Hide() end
        return
    end
    if not unlockHint then
        unlockHint = ST.MoverChrome.CreateLabel(UIParent)
        unlockHint:SetWidth(260)
        unlockHint:SetFrameStrata("FULLSCREEN_DIALOG")
        unlockHint.text:SetText("Target an enemy to place nameplate reminders")
    end
    -- Re-placed whenever the unlock toolbar refreshes too: the bar can show
    -- after this label does.
    if not toolbarHooked and CooldownCompanion.RefreshUnlockToolbar then
        toolbarHooked = true
        hooksecurefunc(CooldownCompanion, "RefreshUnlockToolbar", function()
            if unlockHint and unlockHint:IsShown() then ShowUnlockHint(true) end
        end)
    end
    -- Just under the "Panels unlocked" bar, which sits at the top, can be
    -- dragged and grows downward (owner report 2026-10-05: a fixed spot hid
    -- behind it).
    local pill = CooldownCompanion._arrangeModePill
    unlockHint:ClearAllPoints()
    if pill and pill:IsShown() then
        unlockHint:SetPoint("TOP", pill, "BOTTOM", 0, -4)
    else
        unlockHint:SetPoint("TOP", UIParent, "TOP", 0, -120)
    end
    unlockHint:Show()
end

------------------------------------------------------------------------
-- Rows
------------------------------------------------------------------------

local function NewRow()
    local row = { copies = {} }
    row.holder = CreateFrame("Frame", nil, UIParent)
    row.holder:Hide()
    return row
end

local function HideRow(row)
    if row.drag then EndDrag(row) end
    for _, copy in ipairs(row.copies) do CooldownCompanion:ApplyNameplateEffects(copy, nil) end
    row.holder:Hide()
    row.holder:SetParent(UIParent)
end

-- The row as one box on the plate, each DoT at its spot inside it, so the
-- chrome frames the whole row.
local function DrawRow(row, group, plate, chromeId)
    local I = ST.Indicator
    local auras = I.AuraList(group)
    local count = #auras
    local point, x, y, width, height, center = ST._NameplateReminders.RowBox(group, count)
    local holder = row.holder
    holder:SetParent(plate)
    holder:SetSize(math.max(width, 1), math.max(height, 1))
    holder:ClearAllPoints()
    holder:SetPoint("CENTER", plate, point, x, y)
    holder:Show()
    -- The missing look's effects, as the reminders play them (no measuring:
    -- this row hangs off a real nameplate).
    local effects = I.NameplateEffects(group, "missing")
    for index = 1, math.max(count, #row.copies) do
        local aura = auras[index]
        local copy = row.copies[index]
        if aura and not copy then
            copy = CooldownCompanion.CreateIndicatorPresenceHost(holder)
            row.copies[index] = copy
        end
        if aura and I.Render(copy, nil, group, true, 0.5, nil, I.NameplateIconSettings(group, aura)) then
            copy:ClearAllPoints()
            copy:SetPoint("CENTER", holder, "CENTER", I.NameplateSpotOffset(group, index, count) - center, 0)
            copy:Show()
            CooldownCompanion:ApplyNameplateEffects(copy, effects, height)
        elseif copy then
            CooldownCompanion:ApplyNameplateEffects(copy, nil)
            copy:Hide()
        end
    end
    SetChrome(row, chromeId)
end

local function Place()
    pending = false
    local plate = TargetPlate()
    drawnPlate = plate
    local wanted = {}
    -- An entry that stopped being a nameplate Indicator drops out here.
    for groupId in pairs(unlocked) do
        local group = SavedGroup(groupId)
        if not group or not ST.Indicator.IsNameplate(group) then unlocked[groupId] = nil end
    end
    if plate then
        if preview.group then
            wanted.preview = { group = preview.group, chromeId = unlocked[preview.groupId] and preview.groupId or nil }
        end
        for groupId in pairs(unlocked) do
            if groupId ~= preview.groupId then
                wanted[groupId] = { group = SavedGroup(groupId), chromeId = groupId }
            end
        end
    end
    for key, row in pairs(rows) do
        if not wanted[key] then HideRow(row) end
    end
    for key, want in pairs(wanted) do
        local row = rows[key]
        if not row then
            row = NewRow()
            rows[key] = row
        end
        DrawRow(row, want.group, plate, want.chromeId)
    end
    ShowUnlockHint(next(unlocked) ~= nil and not plate and not inCombat and not InCombatLockdown())
    if preview.onPlaced then preview.onPlaced(plate ~= nil) end
end

------------------------------------------------------------------------
-- Events: only while a caller wants the view
------------------------------------------------------------------------

local function SyncEvents()
    local wanted = preview.group ~= nil or next(unlocked) ~= nil
    if wanted == eventsOn then return end
    eventsOn = wanted
    if wanted then
        inCombat = InCombatLockdown()
        events:RegisterEvent("PLAYER_TARGET_CHANGED")
        events:RegisterEvent("NAME_PLATE_UNIT_ADDED")
        events:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
        events:RegisterEvent("PLAYER_REGEN_DISABLED")
        events:RegisterEvent("PLAYER_REGEN_ENABLED")
    else
        events:UnregisterAllEvents()
    end
end

events:SetScript("OnEvent", function(_, event, unit)
    -- InCombatLockdown can still read false inside PLAYER_REGEN_DISABLED.
    if event == "PLAYER_REGEN_DISABLED" then inCombat = true
    elseif event == "PLAYER_REGEN_ENABLED" then inCombat = false
    -- Other mobs' plates come and go all the time: only a plate arriving
    -- while none is drawn, or the drawn one leaving, changes the view.
    elseif event == "NAME_PLATE_UNIT_ADDED" then
        if drawnPlate then return end
    elseif event == "NAME_PLATE_UNIT_REMOVED" then
        if not drawnPlate then return end
        if not issecretvalue(unit) and C_NamePlate.GetNamePlateForUnit(unit) ~= drawnPlate then return end
    end
    Place()
end)

-- Coalesced: many Indicators can report in one refresh.
function V.Refresh()
    SyncEvents()
    if pending then return end
    pending = true
    C_Timer.After(0, Place)
end

-- From the Indicator visibility state (Core/AuraTexturesDisplay.lua), on
-- every refresh of a nameplate Indicator: a table compare unless it changed.
function V.NoteUnlocked(groupId, isUnlocked)
    if not groupId then return end
    isUnlocked = isUnlocked or nil
    if unlocked[groupId] == isUnlocked then return end
    unlocked[groupId] = isUnlocked
    V.Refresh()
end

-- The Indicator was unloaded (NameplateReminders.ReleaseGroup).
function V.Forget(groupId)
    if unlocked[groupId] then
        unlocked[groupId] = nil
        V.Refresh()
    end
end

-- The config's Live Preview: its staged copy of the Indicator, or nil when
-- the preview goes away. `onPlaced(hasPlate)` hears whether the copy found a
-- hostile target's plate, after each placement.
function V.SetPreview(group, groupId, onPlaced)
    preview.group, preview.groupId = group, group and groupId or nil
    preview.onPlaced = group and onPlaced or nil
    V.Refresh()
end
