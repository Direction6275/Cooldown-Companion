--[[
    CooldownCompanion - ResourceBarLifecycle
    Resource bar event registration, hooks, and initialization.
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon

local math_abs = math.abs
local ipairs = ipairs

local RB = ST._RB

function RB.CreateResourceBarLifecycleModule(deps)
    local GetResourceBarSettings = deps.GetResourceBarSettings or RB.GetResourceBarSettings
    local GetSpecLayoutOrder = deps.GetSpecLayoutOrder or RB.GetSpecLayoutOrder
    local GetEffectiveAnchorGroupId = deps.GetEffectiveAnchorGroupId or RB.GetEffectiveAnchorGroupId
    local GetResourcePrimaryLength = deps.GetResourcePrimaryLength or RB.GetResourcePrimaryLength
    local GetLastAppliedPrimaryLength = deps.GetLastAppliedPrimaryLength
    local UpdateMWMaxStacks = deps.UpdateMWMaxStacks
    local hooksInstalled = false
    local eventFrame = nil
    local eventFrameEnabled = false
    local pendingSpecChange = false
    local pendingTalentResourceRefreshToken = 0
    local lifecycleEventsEnabled = false
    local InstallHooks

    local function RebuildResourceBarTalentEligibilityCache()
        if CooldownCompanion.CacheCurrentSpec then
            CooldownCompanion:CacheCurrentSpec()
        end
        if CooldownCompanion.RebuildTalentNodeCache then
            CooldownCompanion:RebuildTalentNodeCache()
        end
    end

    local function CancelQueuedTalentResourceRefresh()
        pendingTalentResourceRefreshToken = pendingTalentResourceRefreshToken + 1
    end

    local function QueueTalentResourceRefresh(refreshConfig)
        pendingTalentResourceRefreshToken = pendingTalentResourceRefreshToken + 1
        local token = pendingTalentResourceRefreshToken
        C_Timer.After(0.1, function()
            if pendingTalentResourceRefreshToken ~= token then return end
            if not CooldownCompanion:IsBarsAndFramesRuntimeFeatureEnabled("resourceBars") then return end

            RebuildResourceBarTalentEligibilityCache()
            local rebuilt = UpdateMWMaxStacks()
            if not rebuilt then
                CooldownCompanion:EvaluateResourceBars()
            end
            CooldownCompanion:UpdateAnchorStacking()
            if refreshConfig and CooldownCompanion.RefreshConfigPanel then
                CooldownCompanion:RefreshConfigPanel()
            end
        end)
    end

    ------------------------------------------------------------------------
    -- Event handling (must be defined before Apply/Revert which call these)
    ------------------------------------------------------------------------

    -- Lifecycle events: always registered while the feature is enabled.
    -- These trigger full re-evaluation (not just re-apply) so the bars
    -- come back after a form change that temporarily hides them.
    local lifecycleFrame = nil

    local function EnableLifecycleEvents()
        if lifecycleEventsEnabled then return end
        InstallHooks()
        if not lifecycleFrame then
            lifecycleFrame = CreateFrame("Frame")
            lifecycleFrame:SetScript("OnEvent", function(self, event, ...)
                if not CooldownCompanion:IsBarsAndFramesRuntimeFeatureEnabled("resourceBars") then return end
                if event == "UPDATE_SHAPESHIFT_FORM" then
                    CooldownCompanion:EvaluateResourceBars()
                    CooldownCompanion:UpdateAnchorStacking()
                elseif event == "ACTIVE_TALENT_GROUP_CHANGED"
                    or event == "PLAYER_SPECIALIZATION_CHANGED" then
                    if not pendingSpecChange then
                        pendingSpecChange = true
                        C_Timer.After(0.5, function()
                            if not CooldownCompanion:IsBarsAndFramesRuntimeFeatureEnabled("resourceBars") then
                                pendingSpecChange = false
                                return
                            end
                            pendingSpecChange = false
                            local rebuilt = UpdateMWMaxStacks()
                            if not rebuilt then
                                CooldownCompanion:EvaluateResourceBars()
                            end
                            CooldownCompanion:RepositionCastBar()
                            CooldownCompanion:UpdateAnchorStacking()
                        end)
                    end
                elseif event == "PLAYER_TALENT_UPDATE" then
                    RebuildResourceBarTalentEligibilityCache()
                    QueueTalentResourceRefresh(true)
                elseif event == "TRAIT_CONFIG_UPDATED" then
                    CancelQueuedTalentResourceRefresh()
                    RebuildResourceBarTalentEligibilityCache()
                    -- Core OnTalentsChanged already applies resource bars for this event.
                    UpdateMWMaxStacks()
                end
            end)
        end
        lifecycleFrame:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
        lifecycleFrame:RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED")
        lifecycleFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
        lifecycleFrame:RegisterEvent("PLAYER_TALENT_UPDATE")
        lifecycleFrame:RegisterEvent("TRAIT_CONFIG_UPDATED")
        lifecycleEventsEnabled = true
    end

    local function DisableLifecycleEvents()
        if not lifecycleFrame then return end
        lifecycleFrame:UnregisterAllEvents()
        pendingSpecChange = false
        CancelQueuedTalentResourceRefresh()
        lifecycleEventsEnabled = false
    end

    -- Update events: only registered while bars are applied.
    local function EnableEventFrame()
        if eventFrameEnabled then return end
        if not eventFrame then
            eventFrame = CreateFrame("Frame")
            eventFrame:SetScript("OnEvent", function(self, event, ...)
                if not CooldownCompanion:IsBarsAndFramesRuntimeFeatureEnabled("resourceBars") then return end
                if event == "UNIT_MAXPOWER" or event == "UNIT_MAXHEALTH" then
                    local unit = ...
                    if unit == "player" then
                        CooldownCompanion:ApplyResourceBars()
                    end
                end
            end)
        end
        eventFrame:RegisterUnitEvent("UNIT_MAXPOWER", "player")
        -- UNIT_MAXHEALTH: stagger bar max is health-based; only matters for Brewmaster
        -- but RegisterUnitEvent with "player" filter has negligible overhead for others
        eventFrame:RegisterUnitEvent("UNIT_MAXHEALTH", "player")
        eventFrameEnabled = true
    end

    local function DisableEventFrame()
        if not eventFrame then return end
        eventFrame:UnregisterAllEvents()
        eventFrameEnabled = false
    end


    ------------------------------------------------------------------------
    -- Hook installation (same pattern as CastBar)
    ------------------------------------------------------------------------

    InstallHooks = function()
        if hooksInstalled then return end
        hooksInstalled = true

        -- When anchor group refreshes — re-evaluate
        hooksecurefunc(CooldownCompanion, "RefreshGroupFrame", function(self, groupId)
            if not CooldownCompanion:IsBarsAndFramesRuntimeFeatureEnabled("resourceBars") then return end
            local s = GetResourceBarSettings()
            if s and s.enabled then
                C_Timer.After(0, function()
                    if not CooldownCompanion:IsBarsAndFramesRuntimeFeatureEnabled("resourceBars") then return end
                    CooldownCompanion:EvaluateResourceBars()
                end)
            end
        end)

        local function QueueResourceBarReevaluate()
            C_Timer.After(0.1, function()
                if not CooldownCompanion:IsBarsAndFramesRuntimeFeatureEnabled("resourceBars") then return end
                CooldownCompanion:EvaluateResourceBars()
            end)
        end

        -- When all groups refresh — re-evaluate
        hooksecurefunc(CooldownCompanion, "RefreshAllGroups", function()
            if not CooldownCompanion:IsBarsAndFramesRuntimeFeatureEnabled("resourceBars") then return end
            QueueResourceBarReevaluate()
        end)

        -- Visibility-only refresh path (zone/resting/pet-battle transitions)
        -- still needs resource bar anchoring re-evaluation.
        hooksecurefunc(CooldownCompanion, "RefreshAllGroupsVisibilityOnly", function()
            if not CooldownCompanion:IsBarsAndFramesRuntimeFeatureEnabled("resourceBars") then return end
            QueueResourceBarReevaluate()
        end)

        local function ReapplyIfPrimaryLengthChanged(groupId)
            local s = GetResourceBarSettings()
            if not s or not s.enabled then return end
            local layout = GetSpecLayoutOrder(s)
            if layout and layout.independentAnchorEnabled then return end  -- independent stack: width not tied to group
            local anchorGroupId = GetEffectiveAnchorGroupId(s)
            if anchorGroupId ~= groupId then return end
            local groupFrame = CooldownCompanion.groupFrames[groupId]
            local lastLength = GetLastAppliedPrimaryLength()
            if not groupFrame or not lastLength then return end
            local newLength = GetResourcePrimaryLength(groupFrame, s)
            if math_abs(newLength - lastLength) < 0.1 then
                return
            end
            CooldownCompanion:ApplyResourceBars()
        end

        -- When compact layout changes visible buttons — re-apply if primary length changed
        hooksecurefunc(CooldownCompanion, "UpdateGroupLayout", function(self, groupId)
            if not CooldownCompanion:IsBarsAndFramesRuntimeFeatureEnabled("resourceBars") then return end
            ReapplyIfPrimaryLengthChanged(groupId)
        end)

        -- When icon size / spacing / buttons-per-row changes — re-apply if primary length changed
        hooksecurefunc(CooldownCompanion, "ResizeGroupFrame", function(self, groupId)
            if not CooldownCompanion:IsBarsAndFramesRuntimeFeatureEnabled("resourceBars") then return end
            ReapplyIfPrimaryLengthChanged(groupId)
        end)

        local function QueueResourceBarApply()
            C_Timer.After(0, function()
                if not CooldownCompanion:IsBarsAndFramesRuntimeFeatureEnabled("resourceBars") then return end
                local settings = GetResourceBarSettings()
                if settings and settings.enabled then
                    CooldownCompanion:ApplyResourceBars()
                end
            end)
        end

        -- Re-apply when config visibility changes so independent drag state updates.
        hooksecurefunc(CooldownCompanion, "ToggleConfig", function()
            if not CooldownCompanion:IsBarsAndFramesRuntimeFeatureEnabled("resourceBars") then return end
            QueueResourceBarApply()
        end)

        -- Re-apply when switching between Buttons and Bars modes.
        if ST and ST._SetConfigPrimaryMode then
            hooksecurefunc(ST, "_SetConfigPrimaryMode", function()
                if not CooldownCompanion:IsBarsAndFramesRuntimeFeatureEnabled("resourceBars") then return end
                QueueResourceBarApply()
            end)
        end
    end

    ------------------------------------------------------------------------
    -- Initialization
    ------------------------------------------------------------------------

    local initFrame = CreateFrame("Frame")
    initFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    initFrame:SetScript("OnEvent", function(self, event)
        self:UnregisterEvent("PLAYER_ENTERING_WORLD")

        C_Timer.After(0.5, function()
            CooldownCompanion:EvaluateBarsAndFramesRuntime("resource-init")
        end)
    end)


    return {
        EnableLifecycleEvents = EnableLifecycleEvents,
        DisableLifecycleEvents = DisableLifecycleEvents,
        EnableEventFrame = EnableEventFrame,
        DisableEventFrame = DisableEventFrame,
        GetDebugInfo = function()
            return {
                hooksInstalled = hooksInstalled == true,
                lifecycleEventsActive = lifecycleEventsEnabled == true,
                updateEventsActive = eventFrameEnabled == true,
            }
        end,
    }
end
