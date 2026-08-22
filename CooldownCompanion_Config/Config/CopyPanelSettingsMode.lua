--[[
    CooldownCompanion - Config/CopyPanelSettingsMode.lua

    "Copy Panel Settings To...": armed from the Navigator's panel context
    menu. While armed, a banner rides the top of the Navigator, eligible
    panel rows ring green, and left-clicking one copies the armed scope
    (Appearance / Indicators / All Panel Settings) onto it. The mode
    survives panel switches and Browse Other Classes and stays armed after
    each apply; Esc (Panel.lua's key chain) or right-clicking a Navigator
    row cancels. The SOURCE row is the one row that still navigates
    normally while armed (owner ruling), so the user can get back to the
    source panel without disarming.

    The copy itself is Core's CooldownCompanion:CopyPanelSettings; this
    file owns only the mode state and the Navigator-side presentation.
    Column1.lua reaches everything here lazily through ST._ at call time
    (this file loads after it in the .toc).
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon
local CS = ST._configState

local COPY_PANEL_COLOR = { 0.30, 0.90, 0.45, 1 }
local COPY_PANEL_BANNER_HEIGHT = 20

local SCOPE_LABELS = {
    appearance = "Appearance",
    indicators = "Indicators",
    all = "All Panel Settings",
}

local function GetCopyPanelSettingsLabel(state)
    return state and SCOPE_LABELS[state.scope] or ""
end

-- The armed source, re-resolved from its id at call time: the mode outlives
-- arbitrary user actions, so the panel may be gone (deleted, profile
-- switched under us). Anything unresolvable is nil.
local function ResolveCopyPanelSettingsSource(state)
    if not state then return nil end
    local groups = CooldownCompanion.db.profile.groups
    local group = groups and groups[state.sourceGroupId]
    if not group then return nil end
    if not (CooldownCompanion.GetPanelCopyMode and CooldownCompanion:GetPanelCopyMode(group)) then
        return nil
    end
    return group
end

local function CancelCopyPanelSettings(options)
    if not CS.copyPanelSettings then return end
    CS.copyPanelSettings = nil
    if not (options and options.skipRefresh) then
        CooldownCompanion:RefreshConfigPanel()
    end
end

local function ArmCopyPanelSettings(sourceGroupId, scope)
    -- Rival exclusive modes own the same Navigator and selection stores.
    if CS.exportMode and ST._ExitExportMode then
        ST._ExitExportMode({ skipRefresh = true })
    end
    if CS.importMode and ST._ExitImportMode then
        ST._ExitImportMode({ skipRefresh = true })
    end
    if CS.copyCustomization and ST._CancelCopyCustomization then
        ST._CancelCopyCustomization({ skipRefresh = true })
    end
    CS.copyPanelSettings = {
        sourceGroupId = tonumber(sourceGroupId),
        scope = scope,
    }
    CooldownCompanion:RefreshConfigPanel()
end

-- "Container - Panel", the same label shape the retired pull-copy list used,
-- so the applied feedback names a panel the way the Navigator does.
local function GetPanelCopyTargetLabel(panelId)
    local db = CooldownCompanion.db.profile
    local panel = db.groups and db.groups[panelId]
    if not panel then return "panel" end
    local panelName = panel.name or ("Panel " .. tostring(panelId))
    local parentContainer = CooldownCompanion.GetParentContainer
        and CooldownCompanion:GetParentContainer(panel) or nil
    local containerName = parentContainer and parentContainer.name
    if containerName and containerName ~= panelName then
        return containerName .. " - " .. panelName
    end
    return panelName
end

local function IsEligibleCopyPanelTarget(panelId)
    local state = CS.copyPanelSettings
    if not state then return false end
    if panelId == state.sourceGroupId then return false end
    return CooldownCompanion:CanCopyPanelSettings(state.sourceGroupId, panelId, state.scope) == true
end

-- Returns true when the click was consumed by the armed mode. The source
-- row deliberately returns false: it keeps navigating normally.
local function HandleCopyPanelSettingsClick(panelId)
    local state = CS.copyPanelSettings
    if not state then return false end
    if not ResolveCopyPanelSettingsSource(state) then
        -- The armed source no longer exists; nothing sane to copy.
        CancelCopyPanelSettings()
        return true
    end
    if panelId == state.sourceGroupId then
        return false
    end
    if not IsEligibleCopyPanelTarget(panelId) then
        -- Ineligible panel: stay armed and consume the click, so a stray
        -- click on a wrong-mode panel never navigates away mid-gesture.
        return true
    end

    local ok = CooldownCompanion:CopyPanelSettings(state.sourceGroupId, panelId, state.scope)
    if not ok then
        return true
    end

    state.lastAppliedText = "Applied to " .. GetPanelCopyTargetLabel(panelId)
    CooldownCompanion:RefreshConfigPanel()
    return true
end

------------------------------------------------------------------------
-- Banner: slim full-width strip at the top of the Navigator column, the
-- entry copy banner's recipe on a different host.
------------------------------------------------------------------------

local function EnsureCopyPanelSettingsBanner()
    local scroll = CS.col1Scroll
    local host = scroll and scroll.frame and scroll.frame:GetParent()
    if not host then return nil end

    local banner = CS.copyPanelSettingsBanner
    if banner then
        banner:SetParent(host)
        banner:ClearAllPoints()
        banner:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0)
        banner:SetPoint("TOPRIGHT", host, "TOPRIGHT", 0, 0)
        return banner
    end

    banner = CreateFrame("Frame", nil, host)
    banner:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0)
    banner:SetPoint("TOPRIGHT", host, "TOPRIGHT", 0, 0)
    banner:SetHeight(COPY_PANEL_BANNER_HEIGHT)

    local clear = CreateColor(0, 0, 0, 0)
    local fill = CreateColor(0, 0, 0, 0.7)
    local accent = CreateColor(COPY_PANEL_COLOR[1], COPY_PANEL_COLOR[2], COPY_PANEL_COLOR[3], 0.8)
    banner.bgLeft = banner:CreateTexture(nil, "BACKGROUND")
    banner.bgLeft:SetPoint("TOPLEFT")
    banner.bgLeft:SetPoint("BOTTOMRIGHT", banner, "BOTTOM", 0, 0)
    banner.bgLeft:SetTexture("Interface/Buttons/WHITE8x8")
    banner.bgLeft:SetGradient("HORIZONTAL", clear, fill)
    banner.bgRight = banner:CreateTexture(nil, "BACKGROUND")
    banner.bgRight:SetPoint("TOPLEFT", banner, "TOP", 0, 0)
    banner.bgRight:SetPoint("BOTTOMRIGHT")
    banner.bgRight:SetTexture("Interface/Buttons/WHITE8x8")
    banner.bgRight:SetGradient("HORIZONTAL", fill, clear)

    banner.lineLeft = banner:CreateTexture(nil, "BORDER")
    banner.lineLeft:SetPoint("BOTTOMLEFT")
    banner.lineLeft:SetPoint("BOTTOMRIGHT", banner, "BOTTOM", 0, 0)
    banner.lineLeft:SetHeight(1)
    banner.lineLeft:SetTexture("Interface/Buttons/WHITE8x8")
    banner.lineLeft:SetGradient("HORIZONTAL", clear, accent)
    banner.lineRight = banner:CreateTexture(nil, "BORDER")
    banner.lineRight:SetPoint("BOTTOMLEFT", banner, "BOTTOM", 0, 0)
    banner.lineRight:SetPoint("BOTTOMRIGHT")
    banner.lineRight:SetHeight(1)
    banner.lineRight:SetTexture("Interface/Buttons/WHITE8x8")
    banner.lineRight:SetGradient("HORIZONTAL", accent, clear)

    banner.text = banner:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    banner.text:SetPoint("CENTER", banner, "CENTER", 9, 0)
    banner.text:SetJustifyH("LEFT")
    banner.text:SetWordWrap(false)

    banner.crosshair = banner:CreateTexture(nil, "OVERLAY")
    banner.crosshair:SetSize(12, 12)
    banner.crosshair:SetPoint("RIGHT", banner.text, "LEFT", -5, 0)
    banner.crosshair:SetAtlas("Crosshair_VehichleCursor_32")
    banner.crosshair:SetVertexColor(COPY_PANEL_COLOR[1], COPY_PANEL_COLOR[2], COPY_PANEL_COLOR[3])

    banner:Hide()
    CS.copyPanelSettingsBanner = banner
    return banner
end

-- The banner does not float over the tree: while it is shown, the Navigator
-- scroll starts below it (Panel.lua's LayoutColumns reads the armed state and
-- ST._COPY_PANEL_BANNER_HEIGHT). Re-run the column layout exactly when the
-- shown state flips, so arming reserves the strip and cancelling returns it.
local lastBannerShown = false
local function SyncNavigatorBannerInset(shown)
    if shown == lastBannerShown then return end
    lastBannerShown = shown
    if CS.configFrame and CS.configFrame.LayoutColumns then
        CS.configFrame.LayoutColumns()
    end
end

-- Called from RefreshColumn1 on every Navigator rebuild: the mode survives
-- navigation, so whatever the column shows carries the banner.
local function UpdateCopyPanelSettingsBanner()
    local state = CS.copyPanelSettings
    if state and not ResolveCopyPanelSettingsSource(state) then
        -- The armed source is gone (deleted, profile changed). Clear
        -- silently - we're already mid-rebuild.
        CS.copyPanelSettings = nil
        state = nil
    end

    if not state then
        if CS.copyPanelSettingsBanner then
            CS.copyPanelSettingsBanner:Hide()
        end
        SyncNavigatorBannerInset(false)
        return
    end

    local banner = EnsureCopyPanelSettingsBanner()
    if not banner then return end
    local text = "Click a panel to apply |cffffd100"
        .. GetCopyPanelSettingsLabel(state) .. "|r"
    if state.lastAppliedText then
        text = text .. "  |cff99e6a3" .. state.lastAppliedText .. "|r"
    end
    banner.text:SetText(text)
    banner:SetFrameLevel(banner:GetParent():GetFrameLevel() + 40)
    banner:Show()
    SyncNavigatorBannerInset(true)
end

------------------------------------------------------------------------
-- Row visuals: a soft green wash under the row plus a green label on the
-- panel rows an armed click can land on - the Navigator's own selection
-- idiom (a tinted label over a flat wash), never a bordered overlay.
--
-- The wash textures live on the row FRAME, which AceGUI recycles across
-- every surface that acquires an InteractiveLabel - so every decorated
-- frame is remembered in a weak-keyed set and ResetCopyPanelRowVisuals
-- (called at the top of every RefreshColumn1) hides them all before the
-- rebuild re-applies to whatever is eligible now. That is what keeps a
-- pooled row from resurfacing elsewhere still wearing the wash after a
-- Group is collapsed, expanded, or re-rendered.
------------------------------------------------------------------------

local decoratedRowFrames = setmetatable({}, { __mode = "k" })

local function HideCopyPanelRowWash(frame)
    if frame._cdcCopyPanelWash then
        frame._cdcCopyPanelWash:Hide()
    end
    if frame._cdcCopyPanelWashLine then
        frame._cdcCopyPanelWashLine:Hide()
    end
end

local function ResetCopyPanelRowVisuals()
    for frame in pairs(decoratedRowFrames) do
        HideCopyPanelRowWash(frame)
    end
end

local function ApplyCopyPanelRowVisuals(panelEntry, panelId)
    local frame = panelEntry and panelEntry.frame
    if not frame then return end

    if not (CS.copyPanelSettings ~= nil and IsEligibleCopyPanelTarget(panelId)) then
        -- The reset sweep already hid every wash this rebuild; nothing to do.
        return
    end

    local wash = frame._cdcCopyPanelWash
    if not wash then
        wash = frame:CreateTexture(nil, "BACKGROUND", nil, 2)
        wash:SetAllPoints(frame)
        wash:SetTexture("Interface/Buttons/WHITE8x8")
        frame._cdcCopyPanelWash = wash

        local line = frame:CreateTexture(nil, "BACKGROUND", nil, 3)
        line:SetHeight(1)
        line:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
        line:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
        line:SetTexture("Interface/Buttons/WHITE8x8")
        frame._cdcCopyPanelWashLine = line
    end
    wash:SetVertexColor(COPY_PANEL_COLOR[1], COPY_PANEL_COLOR[2], COPY_PANEL_COLOR[3], 0.10)
    wash:Show()
    frame._cdcCopyPanelWashLine:SetVertexColor(
        COPY_PANEL_COLOR[1], COPY_PANEL_COLOR[2], COPY_PANEL_COLOR[3], 0.45)
    frame._cdcCopyPanelWashLine:Show()
    decoratedRowFrames[frame] = true
    panelEntry:SetColor(COPY_PANEL_COLOR[1], COPY_PANEL_COLOR[2], COPY_PANEL_COLOR[3])
end

------------------------------------------------------------------------
-- ST._ exports (Column1.lua, Panel.lua, the rival modes)
------------------------------------------------------------------------
ST._COPY_PANEL_BANNER_HEIGHT = COPY_PANEL_BANNER_HEIGHT
ST._ArmCopyPanelSettings = ArmCopyPanelSettings
ST._CancelCopyPanelSettings = CancelCopyPanelSettings
ST._GetCopyPanelSettingsLabel = GetCopyPanelSettingsLabel
ST._IsEligibleCopyPanelTarget = IsEligibleCopyPanelTarget
ST._HandleCopyPanelSettingsClick = HandleCopyPanelSettingsClick
ST._UpdateCopyPanelSettingsBanner = UpdateCopyPanelSettingsBanner
ST._ResetCopyPanelRowVisuals = ResetCopyPanelRowVisuals
ST._ApplyCopyPanelRowVisuals = ApplyCopyPanelRowVisuals
