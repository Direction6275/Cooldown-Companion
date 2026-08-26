--[[
    CooldownCompanion - ResourceBarCustomBars
    Custom aura bars, spell custom bars, styling, and frame preparation.
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon
local EntryRuntime = ST.EntryRuntime

local issecretvalue = issecretvalue

local RB = ST._RB
local CUSTOM_AURA_BAR_BASE = RB.CUSTOM_AURA_BAR_BASE
local DEFAULT_RESOURCE_TEXT_FONT = RB.DEFAULT_RESOURCE_TEXT_FONT
local DEFAULT_RESOURCE_TEXT_SIZE = RB.DEFAULT_RESOURCE_TEXT_SIZE
local DEFAULT_RESOURCE_TEXT_OUTLINE = RB.DEFAULT_RESOURCE_TEXT_OUTLINE
local DEFAULT_RESOURCE_TEXT_COLOR = RB.DEFAULT_RESOURCE_TEXT_COLOR

local GetResourceDisplayValue = RB.GetResourceDisplayValue
local ApplyPixelBorders = RB.ApplyPixelBorders
local HidePixelBorders = RB.HidePixelBorders
local CreateContinuousBar = RB.CreateContinuousBar

local BindDurationText = CooldownCompanion.BindDurationText
local UnbindDurationText = CooldownCompanion.UnbindDurationText
local SetStatusBarImmediateValue = ST.SetStatusBarImmediateValue
local SetStatusBarSmoothRange = ST.SetStatusBarSmoothRange
local SetStatusBarSmoothValue = ST.SetStatusBarSmoothValue
local SetStatusBarElapsedDuration = ST.SetStatusBarElapsedDuration

local function SetManualDurationText(fontString, text)
    if not fontString then return end
    UnbindDurationText(fontString)
    fontString:SetText(text)
end

local function UnbindFrameDurationText(frame)
    if frame and frame.text then
        UnbindDurationText(frame.text)
    end
end

function RB.CreateResourceBarCustomBarsModule(deps)
    local resourceBarFrames = deps.resourceBarFrames
    local GetUnlockAssistActive = deps.GetUnlockAssistActive
    local ClearStaleRecycledBarRuntimeState = deps.ClearStaleRecycledBarRuntimeState
    local ClearCustomAuraBarIndicatorState = deps.ClearCustomAuraBarIndicatorState
    local ClearCustomAuraBarIndicatorVisualState = deps.ClearCustomAuraBarIndicatorVisualState
        or ClearCustomAuraBarIndicatorState
    local UpdateCustomAuraBarIndicatorVisuals = deps.UpdateCustomAuraBarIndicatorVisuals

    -- Defined with the shell-composition block below; referenced by the
    -- per-tick spell-bar update above them.
    local ApplyCustomBarShellAlpha, GetCustomBarRuleAlpha

    ------------------------------------------------------------------------
    -- Update logic: Custom aura bars (aura-based, secret-safe)
    ------------------------------------------------------------------------

    local function UpdateCustomAuraBar(barInfo)
        local cabConfig = barInfo.cabConfig
        if not cabConfig or not cabConfig.spellID then return end
        if barInfo.barType ~= "custom_continuous" then return end

        -- The aura pass (12.1): aura state is never evaluated here — the kit
        -- renders the entire aura-present look, Blizzard-shown, and this is
        -- the absent-state layer beneath it, so the bar always renders empty.
        -- Aura sounds are native (AddAuraSound); the CC transition player
        -- can never fire aura legs.
        local bar = barInfo.frame
        local isActive = cabConfig.trackingMode == "active"
        -- OOC-cached automatic max, dormant manual key as harmless fallback.
        local maxStacks = RB.GetCustomBarCachedStackMax(barInfo) or cabConfig.maxStacks or 1

        if CooldownCompanion.UpdateCustomBarSoundAlerts then
            CooldownCompanion:UpdateCustomBarSoundAlerts(barInfo, false)
        end

        if isActive then
            SetStatusBarSmoothRange(bar, 0, 1)
            SetStatusBarImmediateValue(bar, 0)
        else
            SetStatusBarSmoothRange(bar, 0, maxStacks)
            SetStatusBarSmoothValue(bar, 0)
        end

        if bar.text and bar.text:IsShown() then
            SetManualDurationText(bar.text, "")
        elseif bar.text then
            UnbindDurationText(bar.text)
        end

        if bar.stackText and bar.stackText:IsShown() then
            bar.stackText:SetText("")
        end

        if isActive then
            UpdateCustomAuraBarIndicatorVisuals(barInfo, cabConfig)
        else
            ClearCustomAuraBarIndicatorVisualState(barInfo, true)
        end
    end

    local function UpdateSpellCustomBarChargeText(bar, cooldownResult)
        if not (bar and bar.stackText and bar.stackText:IsShown()) then
            return
        end

        local currentCharges = cooldownResult and cooldownResult.currentCharges
        local maxCharges = cooldownResult and cooldownResult.maxCharges
        if currentCharges ~= nil and maxCharges and maxCharges > 1 then
            bar.stackText:SetFormattedText("%d / %d", currentCharges, maxCharges)
        elseif cooldownResult and cooldownResult.chargeDisplayCount ~= nil then
            local displayCount = cooldownResult.chargeDisplayCount
            if issecretvalue and issecretvalue(displayCount) then
                bar.stackText:SetText(displayCount)
            else
                local numericCount = tonumber(displayCount)
                if numericCount and maxCharges and maxCharges > 1 then
                    bar.stackText:SetFormattedText("%d / %d", numericCount, maxCharges)
                elseif displayCount and displayCount ~= "" then
                    bar.stackText:SetText(displayCount)
                else
                    bar.stackText:SetText("")
                end
            end
        else
            bar.stackText:SetText("")
        end
    end

    function RB.UpdateCustomCooldownBar(barInfo)
        local cabConfig = barInfo and barInfo.cabConfig
        local bar = barInfo and barInfo.frame
        if not (cabConfig and cabConfig.spellID and bar) then return end

        -- The aura pass (12.1): aura state is never evaluated here — a
        -- tracked spell bar renders its cooldown only, and the kit's
        -- Blizzard-shown display occludes it while the aura runs.
        local cooldownResult = EntryRuntime.EvaluateSpellCooldownStateForCustomBar(cabConfig, bar)
        local durationObj = cooldownResult and cooldownResult.renderDurationObj
        local cooldownActive = cooldownResult
            and cooldownResult.state == ST.CooldownLogic.STATE_COOLDOWN

        local barColor = cabConfig.barColor or {0.5, 0.5, 1, 1}
        local cooldownColor = cabConfig.barCooldownColor or {0.6, 0.13, 0.18, 1}
        local rechargeColor = cabConfig.barChargeColor or {1.0, 0.82, 0.0, 1}
        local chargeState = cooldownResult and cooldownResult.chargeState
        local fillColor = barColor
        if cooldownResult and cooldownResult.hasCharges == true then
            if chargeState == ST.CooldownLogic.CHARGE_STATE_ZERO then
                fillColor = cooldownColor
            elseif cooldownActive then
                fillColor = rechargeColor
            end
        elseif cooldownActive then
            fillColor = cooldownColor
        end

        ClearCustomAuraBarIndicatorState(barInfo, false)

        SetStatusBarSmoothRange(bar, 0, 1)
        bar:SetStatusBarColor(fillColor[1], fillColor[2], fillColor[3], fillColor[4] ~= nil and fillColor[4] or 1)
        if cooldownActive and durationObj then
            if not SetStatusBarElapsedDuration(bar, durationObj) then
                SetStatusBarSmoothValue(bar, durationObj:GetElapsedPercent())
            end
        elseif cooldownActive then
            SetStatusBarImmediateValue(bar, 0)
        else
            SetStatusBarImmediateValue(bar, 1)
        end

        if bar.text and bar.text:IsShown() then
            if cooldownActive and durationObj then
                -- allowLowTime: custom-bar cooldown lane text.
                BindDurationText(bar.text, durationObj, cabConfig, true)
            else
                SetManualDurationText(bar.text, "")
            end
        elseif bar.text then
            UnbindDurationText(bar.text)
        end

        UpdateSpellCustomBarChargeText(bar, cooldownResult)

        -- Show & hide rules ride this same evaluation. Sounds keep running
        -- below regardless of alpha (panel parity: hidden buttons still
        -- alert).
        ApplyCustomBarShellAlpha(barInfo, GetCustomBarRuleAlpha(barInfo, cooldownResult))

        if CooldownCompanion.UpdateCustomBarSoundAlerts then
            local soundCooldownActive = cooldownActive
            if cooldownResult and cooldownResult.hasCharges == true then
                soundCooldownActive = cooldownResult.chargeState == ST.CooldownLogic.CHARGE_STATE_ZERO
                    or (cooldownResult.chargeState == nil and cooldownActive)
            end
            CooldownCompanion:UpdateCustomBarSoundAlerts(barInfo, false, soundCooldownActive, cooldownResult)
        end
    end

    function CooldownCompanion:RecordCustomBarSpellCast(spellID)
        if not spellID then return end

        for _, barInfo in ipairs(resourceBarFrames) do
            local bar = barInfo and barInfo.frame
            local cabConfig = barInfo and barInfo.cabConfig
            if barInfo
                and barInfo.barType == "custom_cooldown"
                and bar
                and cabConfig
                and cabConfig.entryType == "spell"
            then
                local baseSpellID = tonumber(cabConfig.spellID)
                local runtimeSpellID = baseSpellID and C_Spell.GetOverrideSpell(baseSpellID)
                if not runtimeSpellID or runtimeSpellID == 0 then
                    runtimeSpellID = baseSpellID
                end

                local charges = runtimeSpellID and C_Spell.GetSpellCharges(runtimeSpellID)
                local maxCharges = charges and tonumber(charges.maxCharges)
                if (maxCharges or 0) > 1
                    and (spellID == baseSpellID or spellID == runtimeSpellID) then
                    EntryRuntime.RecordChargeSpent(bar)
                end
            end
        end
    end

    ------------------------------------------------------------------------
    -- Styling: Custom aura bars
    ------------------------------------------------------------------------

    local function StyleCustomAuraBar(barInfo, cabConfig)
        local barColor = cabConfig.barColor or {0.5, 0.5, 1}
        local isSpellCustomBar = RB.IsSpellCustomBarConfig(cabConfig)

        if barInfo.barType == "custom_continuous" or barInfo.barType == "custom_cooldown" then
            local bar = barInfo.frame
            bar.style = cabConfig
            local isVertical = bar._isVertical == true
            bar:SetStatusBarColor(barColor[1], barColor[2], barColor[3], 1)

            -- Determine visibility for both text elements
            local spellAuraStackDisplay = RB.IsSpellCustomBarAuraStackDisplay(cabConfig)
            local spellAuraStackActive = spellAuraStackDisplay and barInfo.barType ~= "custom_cooldown"
            local isActive = isSpellCustomBar and not spellAuraStackActive
                or ((not isSpellCustomBar) and cabConfig.trackingMode == "active")
            local showDuration = cabConfig.showDurationText == true and not spellAuraStackActive
            local showStack = cabConfig.showStackText
            if isSpellCustomBar then
                showStack = showStack == true
            elseif showStack == nil then
                -- Backwards compat: fall back to showText for stacks mode
                if not isActive then
                    showStack = cabConfig.showText == true
                else
                    showStack = false
                end
            end

            -- Duration text (bar.text)
            if bar.text then
                bar.text:SetShown(showDuration)
                if showDuration then
                    bar.text:ClearAllPoints()
                    if showStack then
                        if isVertical then
                            bar.text:SetPoint("BOTTOM", bar, "BOTTOM", 0, 2)
                        else
                            bar.text:SetPoint("LEFT", bar, "LEFT", 4, 0)
                        end
                    else
                        bar.text:SetPoint("CENTER")
                    end
                else
                    UnbindDurationText(bar.text)
                end
            end

            -- Stack text (bar.stackText)
            if bar.stackText then
                bar.stackText:SetShown(showStack)
                if showStack then
                    bar.stackText:ClearAllPoints()
                    if showDuration then
                        if isVertical then
                            bar.stackText:SetPoint("TOP", bar, "TOP", 0, -2)
                        else
                            bar.stackText:SetPoint("RIGHT", bar, "RIGHT", -4, 0)
                        end
                    else
                        bar.stackText:SetPoint("CENTER")
                    end
                end
            end
        end
    end

    -- Shell composition (hideWhenInactive/auraShellDim, 12.1): the CC frame
    -- stays SHOWN as the layout member and aura host but renders nothing (or
    -- renders dimmed) — the kit's shell replicas (bg + border ring + fill +
    -- texts) are the entire visible bar, Blizzard-shown only while the aura
    -- runs. The slot stays reserved in combat (no reflow) — documented,
    -- accepted. Whole-frame alpha, not per-region: the kit lives in a
    -- separate holder subtree, and abandoned frames are never reused so a
    -- zeroed alpha cannot leak into another bar type. The unlock assist
    -- lifts the shell so the bar can be dragged at all: nothing else raises
    -- a zeroed whole-frame alpha, and an invisible drag target is not a
    -- target.
    local function GetCustomBarShellAlpha(cabConfig)
        local auraTracked = not RB.IsSpellCustomBarConfig(cabConfig)
            or cabConfig.auraTracking == true
        if not auraTracked then
            return 1
        end
        -- Aura entries reach the zeroed branch only on an unlock-assist pass
        -- or as drifted group/pet config: the aura block partition
        -- (RB.IsAuraBlockEntry) keeps them out of the stack otherwise. Spell
        -- bars with aura tracking still shell here. Hide wins over dim when
        -- both keys drift on (panel parity: GetAuraShellRestingAlpha).
        if cabConfig.hideWhenInactive == true then
            return 0
        end
        if cabConfig.auraShellDim == true then
            return CooldownCompanion.DIM_FALLBACK_ALPHA
        end
        return 1
    end

    -- Show & hide rules (spell custom bars): computed from the same
    -- per-tick cooldown evaluation the fill uses, so hiding costs nothing
    -- new. Panel semantics (ButtonFrame/Visibility.lua): charge spells
    -- treat zero/missing charges as "on cooldown" and full charges as "not
    -- on cooldown"; no-cooldown spells skip both directional rules. An
    -- unreadable (secret) charge state matches no branch, so every rule
    -- fails open to shown.
    function GetCustomBarRuleAlpha(barInfo, cooldownResult)
        local cabConfig = barInfo.cabConfig
        if not (cabConfig.hideWhileOnCooldown
            or cabConfig.hideWhileNotOnCooldown
            or cabConfig.hideWhileZeroCharges) then
            return 1
        end
        if not cooldownResult then
            return 1
        end

        local CL = ST.CooldownLogic
        local hasCharges = cooldownResult.hasCharges == true
        local chargeState = cooldownResult.chargeState
        local cooldownActive = cooldownResult.state == CL.STATE_COOLDOWN
        -- Panel parity (IsNoCooldownForVisibility): a spell with no real
        -- cooldown is permanently "not on cooldown", so hiding on either
        -- direction would stick forever — skip both. Read from the result,
        -- not the frame cache: a recycled frame's base classification is
        -- only refreshed when an override diverges, so the cached field can
        -- belong to another spell.
        local noCooldown = cooldownResult.noCooldownForVisibility == true

        if cabConfig.hideWhileOnCooldown and not noCooldown then
            if hasCharges then
                if chargeState == CL.CHARGE_STATE_ZERO
                    or chargeState == CL.CHARGE_STATE_MISSING then
                    return 0
                end
            elseif cooldownActive then
                return 0
            end
        end

        if cabConfig.hideWhileNotOnCooldown and not noCooldown then
            if hasCharges then
                if cabConfig.showOnlyAtZeroCharges then
                    if chargeState == CL.CHARGE_STATE_FULL
                        or chargeState == CL.CHARGE_STATE_MISSING then
                        return 0
                    end
                elseif chargeState == CL.CHARGE_STATE_FULL then
                    return 0
                end
            elseif not cooldownActive and cooldownResult.fetchOk == true then
                -- fetchOk gate: an unavailable fetch leaves state at its
                -- READY default, and unknown must fail open to shown (the
                -- section tooltip promises exactly that). Charge branches
                -- key off concrete charge states and need no extra gate.
                return 0
            end
        end

        if cabConfig.hideWhileZeroCharges
            and chargeState == CL.CHARGE_STATE_ZERO then
            return 0
        end

        return 1
    end

    function ApplyCustomBarShellAlpha(barInfo, ruleAlpha)
        local bar = barInfo.frame
        local cabConfig = barInfo.cabConfig
        if not (bar and cabConfig) then return end
        local unlockAssist = GetUnlockAssistActive()
        local alpha = 1
        if not unlockAssist then
            alpha = GetCustomBarShellAlpha(cabConfig)
            if ruleAlpha and ruleAlpha < alpha then
                alpha = ruleAlpha
            end
        end
        bar:SetAlpha(alpha)
        -- Rule alpha ONLY on the kit holder: the aura shell keeps the kit
        -- at full strength by design (it IS the visible bar there).
        if RB.SetCustomBarAuraHostRuleAlpha then
            RB.SetCustomBarAuraHostRuleAlpha(barInfo,
                (not unlockAssist) and ruleAlpha or 1)
        end
    end

    local function FinalizeAppliedBarVisibility(barInfo)
        if barInfo and type(barInfo.customBarId) == "string" then
            -- The aura pass (12.1): aura-state visibility is gone by design;
            -- custom bars always show. hideWhenInactive renders as the kit
            -- shell (the CC frame stays as the layout shell and aura host).
            barInfo.frame:Show()
            ApplyCustomBarShellAlpha(barInfo)
            if barInfo.barType == "custom_cooldown" then
                RB.UpdateCustomCooldownBar(barInfo)
            else
                UpdateCustomAuraBar(barInfo)
            end
            -- CC-side absent-state stack blocks re-lay from the OOC-cached
            -- max (this runs after ClearStaleRecycledBarRuntimeState hid the
            -- pools for the apply pass). Late-bound: the aura host module
            -- loads after this file.
            if RB.ApplyCustomBarAbsentStackVisuals then
                RB.ApplyCustomBarAbsentStackVisuals(barInfo)
            end
            -- Follow the bar if the stack handed it a different frame (a
            -- form change adding or removing a resource does exactly that).
            -- In combat this is the only thing that can repair it — the
            -- rebind pass is deferred to combat end.
            if RB.SyncCustomBarAuraHostAnchor then
                RB.SyncCustomBarAuraHostAnchor(barInfo)
            end
        else
            barInfo.frame:Show()
            -- Resource-bar overlay holders ride the same frame-identity
            -- repair (the stack recycles resource slots just as readily on
            -- a form change, and in combat this is the only repair path).
            if RB.SyncResourceBarAuraHostAnchor then
                RB.SyncResourceBarAuraHostAnchor(barInfo)
            end
        end
    end

    local function HideUnusedResourceBarFrames(firstHiddenIndex)
        for i = firstHiddenIndex, #resourceBarFrames do
            local barInfo = resourceBarFrames[i]
            if barInfo and barInfo.frame then
                UnbindFrameDurationText(barInfo.frame)
                ClearStaleRecycledBarRuntimeState(barInfo.frame)
                ClearCustomAuraBarIndicatorState(barInfo, true)
                barInfo.frame:Hide()
                barInfo.cabConfig = nil
                barInfo.powerType = nil
                barInfo.customBarId = nil
                barInfo.customBarIndex = nil
                barInfo._sndInitialized = nil
                barInfo._sndPrevAuraActive = nil
                barInfo._sndPrevCooldownActive = nil
                barInfo._sndPrevCharges = nil
                barInfo._sndPrevChargeRecharging = nil
                barInfo._sndPrevChargeCooldownStart = nil
                barInfo._side = nil
                barInfo._order = nil
                barInfo._effectiveThickness = nil
                if barInfo.frame.brightnessOverlay then
                    barInfo.frame.brightnessOverlay:Hide()
                end
            end
        end
    end

    local function PrepareCustomAuraBar(
        targetContainer,
        barInfo,
        customEntry,
        customBars,
        settings,
        isVerticalLayout,
        reverseVerticalFill,
        effectiveWidth,
        effectiveHeight,
        segmentGap
    )
        local cabIndex
        local cabConfig
        local customBarId
        local legacyPowerType
        if type(customEntry) == "table" then
            cabIndex = customEntry.customBarIndex or customEntry.index
            cabConfig = customEntry.config or (customBars and cabIndex and customBars[cabIndex])
            customBarId = customEntry.customBarId or (cabConfig and cabConfig.customBarId)
        else
            legacyPowerType = customEntry
            cabIndex = legacyPowerType - CUSTOM_AURA_BAR_BASE + 1
            cabConfig = customBars[cabIndex]
            customBarId = cabConfig and cabConfig.customBarId
        end
        if not cabConfig then
            return barInfo
        end
        customBarId = customBarId or RB.EnsureCustomBarId(settings, cabConfig)
        local isSpellCustomBar = RB.IsSpellCustomBarConfig(cabConfig)
        -- The aura pass (12.1): every custom bar materializes as a single
        -- continuous CC frame — spell bars as the cooldown bar, aura bars as
        -- the absent-state layer. The kit owns stack segmentation (the CC
        -- segmented/overlay StatusBar stacks can't be driven; the count is
        -- secret), so custom_segmented/custom_overlay are never produced —
        -- old frames of those types recreate as continuous on the barType
        -- mismatch below. No manual max: stack capacity is game-data
        -- resolved at OOC bind time (ResourceBarAuraHost / AuraDisplay).
        local targetBarType = isSpellCustomBar and "custom_cooldown" or "custom_continuous"
        local customOrientation = isVerticalLayout and "vertical" or "horizontal"
        local customIsVertical = customOrientation == "vertical"
        local customReverseFill = false
        if customIsVertical then
            customReverseFill = reverseVerticalFill
        end
        local customWidth = effectiveWidth
        local customHeight = effectiveHeight

        local needsRecreate = not barInfo or barInfo.barType ~= targetBarType

        if needsRecreate then
            if barInfo and barInfo.frame then
                UnbindFrameDurationText(barInfo.frame)
                ClearCustomAuraBarIndicatorState(barInfo, true)
                barInfo.frame:Hide()
            end
            local bar = CreateContinuousBar(targetContainer)
            SetStatusBarSmoothRange(bar, 0, 1)
            barInfo = { frame = bar, barType = targetBarType }
        end

        if barInfo.customBarId ~= customBarId then
            barInfo._sndInitialized = nil
            barInfo._sndPrevAuraActive = nil
            barInfo._sndPrevCooldownActive = nil
            barInfo._sndPrevCharges = nil
            barInfo._sndPrevChargeRecharging = nil
            barInfo._sndPrevChargeCooldownStart = nil
        end
        barInfo.cabConfig = cabConfig
        barInfo.powerType = legacyPowerType
        barInfo.customBarId = customBarId
        barInfo.customBarIndex = cabIndex
        barInfo.frame:SetSize(customWidth, customHeight)
        barInfo.frame._isVertical = customIsVertical
        barInfo.frame._reverseFill = customReverseFill
        do
            local barTextureName = GetResourceDisplayValue(settings, "barTexture", "Solid")
            local barTexture = CooldownCompanion:FetchEffectiveBarTexture(barTextureName)
            barInfo.frame:SetStatusBarTexture(barTexture)
            barInfo.frame:SetOrientation(customIsVertical and "VERTICAL" or "HORIZONTAL")
            barInfo.frame:SetReverseFill(customIsVertical and customReverseFill or false)
            barInfo.frame._isVertical = customIsVertical
            barInfo.frame._reverseFill = customReverseFill
            local bgc = GetResourceDisplayValue(settings, "backgroundColor", { 0, 0, 0, 0.5 })
            barInfo.frame.bg:ClearAllPoints()
            barInfo.frame.bg:SetAllPoints(barInfo.frame)
            barInfo.frame.bg:SetColorTexture(bgc[1], bgc[2], bgc[3], bgc[4])
            local borderStyle = GetResourceDisplayValue(settings, "borderStyle", "pixel")
            local borderColor = GetResourceDisplayValue(settings, "borderColor", { 0, 0, 0, 1 })
            local borderSize = GetResourceDisplayValue(settings, "borderSize", 1)
            local borderRenderMode = GetResourceDisplayValue(settings, "borderRenderMode", ST.BORDER_RENDER_MODE_CUSTOM)
            if borderStyle == "pixel" then
                ApplyPixelBorders(barInfo.frame.borders, barInfo.frame, borderColor, borderSize, borderRenderMode)
            else
                HidePixelBorders(barInfo.frame.borders)
            end
            local durationTextFontName = cabConfig.durationTextFont or DEFAULT_RESOURCE_TEXT_FONT
            local durationTextSize = tonumber(cabConfig.durationTextFontSize) or DEFAULT_RESOURCE_TEXT_SIZE
            local durationTextOutline = ST.GetEffectiveFontOutline(cabConfig.durationTextFontOutline or DEFAULT_RESOURCE_TEXT_OUTLINE)
            local durationTextColor = cabConfig.durationTextFontColor or DEFAULT_RESOURCE_TEXT_COLOR
            if type(durationTextColor) ~= "table" or durationTextColor[1] == nil or durationTextColor[2] == nil or durationTextColor[3] == nil then
                durationTextColor = DEFAULT_RESOURCE_TEXT_COLOR
            end
            local durationTextFont = CooldownCompanion:FetchFont(durationTextFontName)
            barInfo.frame.text:SetFont(durationTextFont, durationTextSize, durationTextOutline)
            ST.ApplyFontShadowForOutline(barInfo.frame.text, durationTextOutline)
            barInfo.frame.text:SetTextColor(durationTextColor[1], durationTextColor[2], durationTextColor[3], durationTextColor[4] ~= nil and durationTextColor[4] or 1)
            if not barInfo.frame.stackText then
                barInfo.frame.stackText = (barInfo.frame.textLayer or barInfo.frame):CreateFontString(nil, "OVERLAY")
                barInfo.frame.stackText:SetTextColor(1, 1, 1, 1)
            end
            local stackTextFontName = cabConfig.stackTextFont or DEFAULT_RESOURCE_TEXT_FONT
            local stackTextSize = tonumber(cabConfig.stackTextFontSize) or DEFAULT_RESOURCE_TEXT_SIZE
            local stackTextOutline = ST.GetEffectiveFontOutline(cabConfig.stackTextFontOutline or DEFAULT_RESOURCE_TEXT_OUTLINE)
            local stackTextColor = cabConfig.stackTextFontColor or DEFAULT_RESOURCE_TEXT_COLOR
            if type(stackTextColor) ~= "table" or stackTextColor[1] == nil or stackTextColor[2] == nil or stackTextColor[3] == nil then
                stackTextColor = DEFAULT_RESOURCE_TEXT_COLOR
            end
            local stackTextFont = CooldownCompanion:FetchFont(stackTextFontName)
            barInfo.frame.stackText:SetFont(stackTextFont, stackTextSize, stackTextOutline)
            ST.ApplyFontShadowForOutline(barInfo.frame.stackText, stackTextOutline)
            barInfo.frame.stackText:SetTextColor(stackTextColor[1], stackTextColor[2], stackTextColor[3], stackTextColor[4] ~= nil and stackTextColor[4] or 1)
            barInfo.frame.brightnessOverlay:Hide()
        end
        StyleCustomAuraBar(barInfo, cabConfig)

        return barInfo
    end

    RB.PrepareCustomAuraBar = PrepareCustomAuraBar

    return {
        UpdateCustomAuraBar = UpdateCustomAuraBar,
        FinalizeAppliedBarVisibility = FinalizeAppliedBarVisibility,
        HideUnusedResourceBarFrames = HideUnusedResourceBarFrames,
        PrepareCustomAuraBar = PrepareCustomAuraBar,
    }
end
