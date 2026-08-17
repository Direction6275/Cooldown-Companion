local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon
local CS = ST._configState

-- Core/Defaults.lua. "Can this PANEL ever use this override section?" - false
-- only on an Aura Panel, for the sections that read spell cooldown, castability,
-- proc, charge, cast or GCD state its pure-aura entries do not have.
local CanGroupUseOverrideSection = ST.CanGroupUseOverrideSection

-- Imports from Helpers.lua
local BuildCollapsibleSection = ST._BuildCollapsibleSection
local AddAdvancedToggle = ST._AddAdvancedToggle
local CreateInfoButton = ST._CreateInfoButton
local AddPandemicMarkerControls = ST._AddPandemicMarkerControls
local ReconcilePandemicMarkerPreview = ST._ReconcilePandemicMarkerPreview
local ResolveLensSection = ST._ResolveLensSection
local BeginLensSection = ST._BeginLensSection
local ResolveLensCollapseKey = ST._ResolveLensCollapseKey
local AddLensPanelScopeNote = ST._AddLensPanelScopeNote

-- Imports from SectionBuilders.lua
local BuildDesaturationControls = ST._BuildDesaturationControls
local BuildShowTooltipsControls = ST._BuildShowTooltipsControls
local BuildShowOutOfRangeControls = ST._BuildShowOutOfRangeControls
local BuildAllowPingsControls = ST._BuildAllowPingsControls
local BuildShowGCDSwipeControls = ST._BuildShowGCDSwipeControls
local BuildCooldownSwipeControls = ST._BuildCooldownSwipeControls
local BuildAuraDurationSwipeControls = ST._BuildAuraDurationSwipeControls
local BuildAuraDurationSwipeAdvancedControls = ST._BuildAuraDurationSwipeAdvancedControls
local BuildIconFillTimerControls = ST._BuildIconFillTimerControls
local BuildIconFillTimerAdvancedControls = ST._BuildIconFillTimerAdvancedControls
local BuildLossOfControlControls = ST._BuildLossOfControlControls
local BuildUnusableDimmingControls = ST._BuildUnusableDimmingControls
local BuildAssistedHighlightControls = ST._BuildAssistedHighlightControls
local BuildProcGlowControls = ST._BuildProcGlowControls
local BuildAuraGlowControls = ST._BuildAuraGlowControls
local BuildPandemicGlowControls = ST._BuildPandemicGlowControls
local BuildReadyGlowControls = ST._BuildReadyGlowControls
local BuildKeyPressHighlightControls = ST._BuildKeyPressHighlightControls

-- Imports from RowWidgets.lua (the row grammar)
local AddCheckboxRow = ST._AddCheckboxRow
local AddSliderRow = ST._AddSliderRow
local AnchorRowBadge = ST._AnchorRowBadge
local BeginRowGrid = ST._BeginRowGrid

-- Imports from GroupTabsShared.lua
local WireMirrorFirstSlider = ST._WireMirrorFirstSlider
local RefreshActiveAdvancedSettingsPanel = ST._RefreshActiveAdvancedSettingsPanel
local UpdateSelectedGroupStyle = ST._UpdateSelectedGroupStyle
local MakeCooldownSwipeAdvancedDescriptor = ST._MakeCooldownSwipeAdvancedDescriptor

-- Imports from GroupTabsSpecial.lua
local BuildTriggerEffectsTab = ST._BuildTriggerEffectsTab
local BuildTextureEffectsTab = ST._BuildTextureEffectsTab
local EFFECTS_TEXTURE_INDICATORS_SECTION = ST._EFFECTS_TEXTURE_INDICATORS_SECTION

-- Imports from BarModeTabs.lua
local BuildBarEffectsTab = ST._BuildBarEffectsTab

-- Owner ruling (aura rebuild plan): group-level aura style sections are shown
-- only while the group actually has an aura-tracking entry. Shared helper
-- (Helpers.lua) so BarModeTabs can gate its aura section too.
local GroupHasAuraTrackingEntry = ST._GroupHasAuraTrackingEntry

-- Row-grammar section headers: caret far left, label, then a class-colored
-- rule fading right.
local ROW_SECTION = { leftAligned = true }

local tabInfoButtons = CS.tabInfoButtons
local appearanceTabElements = CS.appearanceTabElements

-- Both primers take an optional entry: the transition state they re-arm is
-- per-BUTTON runtime state, so an edit made through the entry lens re-arms
-- only the entry it changed. nil primes the whole panel (a panel-scope edit
-- changed every entry's config).
local function PrimeReadyGlowCappedChargeTransitions(groupId, onlyButtonData)
    local frame = CooldownCompanion.groupFrames and CooldownCompanion.groupFrames[groupId]
    if not (frame and frame.buttons) then
        return
    end

    for _, button in ipairs(frame.buttons) do
        local buttonData = button.buttonData
        if buttonData
           and (onlyButtonData == nil or buttonData == onlyButtonData)
           and buttonData.type == "spell"
           and buttonData.hasCharges == true
           and not buttonData._hasDisplayCount then
            button._readyGlowMaxChargesSpellID = button._displaySpellId or buttonData.id
            button._readyGlowMaxChargesStartTime = nil
            button._readyGlowMaxChargesActive = false
        end
    end
end

local function PrimeReadyGlowNormalTransitions(groupId, onlyButtonData)
    local frame = CooldownCompanion.groupFrames and CooldownCompanion.groupFrames[groupId]
    if not (frame and frame.buttons) then
        return
    end

    local now = GetTime()
    for _, button in ipairs(frame.buttons) do
        local buttonData = button.buttonData
        if buttonData
           and (onlyButtonData == nil or buttonData == onlyButtonData)
           and not buttonData.isPassive
           and button._noCooldown ~= true
           and button._visibilityHidden ~= true
           and button._desatCooldownActive ~= true then
            button._readyGlowStartTime = now
        end
    end
end

local function ClearEffectsTabWidgets()
    for _, btn in ipairs(tabInfoButtons) do
        btn:ClearAllPoints()
        btn:Hide()
        btn:SetParent(nil)
    end
    wipe(tabInfoButtons)
    for _, elem in ipairs(appearanceTabElements) do
        elem:ClearAllPoints()
        elem:Hide()
        elem:SetParent(nil)
    end
    wipe(appearanceTabElements)
end

local function ResetEffectsTabPreviews()
    CooldownCompanion:ClearAllTextureIndicatorPreviews()
    if CooldownCompanion.ClearAllTriggerPanelEffectPreviews then
        CooldownCompanion:ClearAllTriggerPanelEffectPreviews()
    end
end

-- Arriving at a different panel or display mode must not inherit the last
-- one's running glow preview. Rebuilds of the SAME tab must NOT stop it:
-- these previews are started from the preview command center, and
-- previewing is a "turn it on, then adjust until it looks right"
-- workflow - so any settings change that refreshes the config would
-- otherwise kill the preview mid-adjustment. Same context gate the
-- texture/trigger reset above uses.
local function BuildBarModeEffects(container, group, style, previewContextChanged)
    if previewContextChanged then
        CooldownCompanion:SetGroupProcGlowPreview(CS.selectedGroup, false)
        CooldownCompanion:SetGroupAuraGlowPreview(CS.selectedGroup, false)
        CooldownCompanion:SetGroupReadyGlowPreview(CS.selectedGroup, false)
        CooldownCompanion:SetGroupKeyPressHighlightPreview(CS.selectedGroup, false)
        CooldownCompanion:SetGroupBarAuraEffectPreview(CS.selectedGroup, false)
        -- The bar variant also owns the staged aura drain conditional.
        CooldownCompanion:SetGroupBarPandemicPreview(CS.selectedGroup, false)
    end
    BuildBarEffectsTab(container, group, style)
end

-- The four glow sections below are icons-mode only and are each called exactly
-- once, from BuildEffectsTab's icons path, so they were converted to the row
-- grammar outright rather than growing an opts.row mode. `container` is the
-- grid column the row belongs to.
--
-- STYLE LENS (Helpers.lua): each takes the tab's lens, resolved ONCE in
-- BuildEffectsTab and handed down, and resolves its OWN section against it -
-- the same shape the bars twins use. With an entry selected the rows read that
-- entry's effective values and write only where the entry owns the section; a
-- nil write table is the inert marker, and the scope chrome attached last is
-- the only way back out of it.
local function BuildProcGlowSection(container, group, style, lens)
    -- Passive entries are not special-cased here. The retired promote badge on
    -- this row skipped itself for them, which no other surface did:
    -- CanButtonUseConfigOverrideSection allows Proc Glow on a passive entry.
    -- The lens asks that same question, so an entry that genuinely cannot use
    -- the section resolves "denied" and renders inert with no Customize
    -- affordance.
    local procSec = BeginLensSection(lens, group, "procGlow", { column = container })

    local procEnableCb = AddCheckboxRow(container, {
        label = "Show Proc Glow",
        value = procSec.read.procGlowStyle ~= "none",
        disabled = procSec.disabled,
        onChange = function(val)
            if not procSec.write then return end
            procSec.write.procGlowStyle = val and "glow" or "none"
            UpdateSelectedGroupStyle(true)
        end,
    })

    -- Single rail (AdvancedSettingsPanel.lua): a panel is one narrow column, so
    -- the shared glow builder runs in row mode with NO rightColumn - its row
    -- path puts the extras in `container` when none is given.
    --
    -- The panel captures the section's WRITE table, which is the group style or
    -- the selected entry's override store depending on scope. Only built while
    -- there is one: an inert section has no gear to open it from.
    local function BuildProcGlowAdvanced(panel)
        AddCheckboxRow(panel, {
            label = "Show Only In Combat",
            value = procSec.write.procGlowCombatOnly or false,
            onChange = function(val)
                procSec.write.procGlowCombatOnly = val
                UpdateSelectedGroupStyle()
            end,
        })

        BuildProcGlowControls(panel, procSec.write, UpdateSelectedGroupStyle, { row = true })

    end

    if procSec.write then
        AddAdvancedToggle(procEnableCb, "procGlow", tabInfoButtons, procSec.read.procGlowStyle ~= "none", {
            title = "Proc Glow Advanced",
            build = BuildProcGlowAdvanced,
        })
    end
    procSec:Chrome(procEnableCb)

    procSec:Finish()

    -- Preview reconciliation follows the same READ the row does, so a group
    -- preview is cleared whenever what is on screen would not render. Clearing
    -- is the safe direction; nothing here ever starts a preview.
    if procSec.read.procGlowStyle == "none" then
        CooldownCompanion:SetGroupProcGlowPreview(CS.selectedGroup, false)
    end
end

-- Aura glow: kit-rendered on the aura slot button, so it appears exactly
-- while the tracked aura is active. Shown only when the group has an
-- aura-tracking entry (Phase 3 gating pattern).
local function BuildAuraGlowSection(container, group, style, lens)
    -- The gate stays on the GROUP: with an entry selected that tracks no aura
    -- the row is still drawn and the lens resolves it "not available" for that
    -- entry, which states the reason rather than hiding it.
    if not GroupHasAuraTrackingEntry(group) then
        -- The section owning an active preview just disappeared (last aura
        -- entry removed); don't leave the preview glow orphaned.
        CooldownCompanion:SetGroupAuraGlowPreview(CS.selectedGroup, false)
        return
    end

    local auraSec = BeginLensSection(lens, group, "auraIndicator", { column = container })

    local auraGlowEnabled = (auraSec.read.auraGlowStyle or "pulse") ~= "none"
    local auraEnableCb = AddCheckboxRow(container, {
        label = "Show Aura Glow",
        value = auraGlowEnabled,
        disabled = auraSec.disabled,
        onChange = function(val)
            if not auraSec.write then return end
            auraSec.write.auraGlowStyle = val and "pulse" or "none"
            if val then
                -- Re-enabling forces the pulse style; reset its per-style keys
                -- so a leftover proc-scale size can't render as a 30px border.
                auraSec.write.auraGlowSize = 2
                auraSec.write.auraGlowSpeed = 0.5
            end
            UpdateSelectedGroupStyle(true)
        end,
    })

    -- Single rail (AdvancedSettingsPanel.lua): row mode, no rightColumn. The
    -- panel captures the section's WRITE table and is only built while there is
    -- one - an inert section has no gear to open it from.
    local function BuildAuraGlowAdvanced(panel)
        BuildAuraGlowControls(panel, auraSec.write, UpdateSelectedGroupStyle, { row = true })
    end

    if auraSec.write then
        AddAdvancedToggle(auraEnableCb, "auraGlow", tabInfoButtons, auraGlowEnabled, {
            title = "Aura Glow Advanced",
            build = BuildAuraGlowAdvanced,
        })
    end
    -- Second badge in the chain: gear, then this, then the scope chrome the lens
    -- attaches last. The anchor args are a placeholder - AnchorRowBadge
    -- re-points the button onto the chain's end.
    AnchorRowBadge(auraEnableCb, CreateInfoButton(auraEnableCb.frame, auraEnableCb.frame, "LEFT", "LEFT", 0, 0, {
        "Aura Glow",
        {"Adds a glow to a button while its tracked aura is active.", 1, 1, 1, true},
    }, tabInfoButtons))
    auraSec:Chrome(auraEnableCb)

    auraSec:Finish()

    if not auraGlowEnabled then
        CooldownCompanion:SetGroupAuraGlowPreview(CS.selectedGroup, false)
    end
end

-- Pandemic effect (PTR 8): a second kit glow the game reveals only while the
-- tracked aura sits inside its refresh window. It shares the Pandemic section,
-- and the "pandemic" OVERRIDE section, with the marker below — one feature,
-- two rows.
--
-- The section's ONE scope chrome sits on the Pandemic HEADING (owner ruling),
-- so neither half carries a row affordance of its own: both resolve the same
-- "pandemic" section and flip together, silently. The bars twin makes the same
-- ruling with the chrome on its enable row.
--
-- Nil-container contract, copied from the bars twin (BarModeTabs' Glows note):
-- the builder runs with whatever host it ends up with, because a glow left
-- running by a deleted aura entry - or by a collapsed section - still has to
-- be cleared. Guarding the CALL instead would strand the preview.
local function BuildPandemicGlowSection(container, group, style, lens)
    local function ClearPandemicPreview()
        if CooldownCompanion.SetGroupPandemicPreview then
            CooldownCompanion:SetGroupPandemicPreview(CS.selectedGroup, false)
        end
    end
    if not GroupHasAuraTrackingEntry(group) then
        ClearPandemicPreview()
        return
    end

    local pandemicSec = BeginLensSection(lens, group, "pandemic")
    local pandemicEnabled = pandemicSec.read.pandemicEffectEnabled == true
    if container then
        -- The host only exists on this path, so the section's bracket is taken
        -- here rather than at Begin.
        pandemicSec:Mark(container)

        local pandemicCb = AddCheckboxRow(container, {
            label = "Show Pandemic Effect",
            value = pandemicEnabled,
            disabled = pandemicSec.disabled,
            onChange = function(val)
                if not pandemicSec.write then return end
                pandemicSec.write.pandemicEffectEnabled = val and true or false
                UpdateSelectedGroupStyle(true)
            end,
        })

        -- Single rail (AdvancedSettingsPanel.lua): row mode, no rightColumn.
        -- The panel captures the section's WRITE table with the panel style
        -- behind it: this glow family resolves its enable from an explicit-true
        -- key, so an override store that has not stored one yet reads the
        -- panel's. The section's enable toggle lives on the row above, never in
        -- the shared builder.
        local function BuildPandemicAdvanced(panel)
            BuildPandemicGlowControls(panel, pandemicSec.write, UpdateSelectedGroupStyle, {
                row = true,
                fallbackStyle = pandemicSec.fallbackStyle,
            })
        end

        if pandemicSec.write then
            AddAdvancedToggle(pandemicCb, "pandemicGlow", tabInfoButtons, pandemicEnabled, {
                title = "Pandemic Effect Advanced",
                build = BuildPandemicAdvanced,
            })
        end
        AnchorRowBadge(pandemicCb, CreateInfoButton(pandemicCb.frame, pandemicCb.frame, "LEFT", "LEFT", 0, 0, {
            "Pandemic Effect",
            {"Glows a button while its tracked aura is in the refresh window, where recasting adds bonus time.", 1, 1, 1, true},
            {" ", 1, 1, 1, true},
            {"Auras that gain no time when refreshed never show it.", 1, 1, 1, true},
            {" ", 1, 1, 1, true},
            {"Draws over the Aura Glow when both are on.", 1, 1, 1, true},
        }, tabInfoButtons))

        pandemicSec:Finish()
    end

    if not pandemicEnabled then
        ClearPandemicPreview()
    end
end

-- Pandemic marker: the text half of the same window. Rows only — no preview
-- surface renders the marker in any mode (every duration-text stand-in writes
-- a bare countdown), so there is deliberately no command-center control to
-- reconcile here and no nil-container contract to honour.
--
-- The marker rides the aura duration text, which lives on the Appearance tab.
-- The rows stay visible when that text is off and the info tooltip says what
-- happens; a control that vanishes onto another tab is harder to find than an
-- inert one.
local function BuildPandemicMarkerSection(container, group, style, lens)
    if not container or not GroupHasAuraTrackingEntry(group) then
        return
    end

    -- Same override section as the effect row in the left column, so this half
    -- FOLLOWS that section's scope silently: one feature, one affordance, and
    -- the chrome for it is on the section's heading.
    local markerSec = BeginLensSection(lens, group, "pandemic", { column = container })

    local applyStyle = function() UpdateSelectedGroupStyle(false) end
    local markerRow = AddPandemicMarkerControls(container, markerSec.tbl, applyStyle, function()
        CooldownCompanion:RefreshConfigPanel()
    end, {
        enableOnly = true,
        onModeChanged = function(mode)
            ReconcilePandemicMarkerPreview(lens, mode)
        end,
    })

    -- Single rail (AdvancedSettingsPanel.lua): the three styling rows fill the
    -- panel, so they carry no indent - childrenOnly drops it. The panel
    -- captures the section's WRITE table, and is only built while there is one.
    local function BuildPandemicMarkerAdvanced(panel)
        AddPandemicMarkerControls(panel, markerSec.write, applyStyle, RefreshActiveAdvancedSettingsPanel,
            { childrenOnly = true })
    end

    if markerSec.write then
        AddAdvancedToggle(markerRow, "pandemicMarker", tabInfoButtons,
            markerSec.read.pandemicMarkerMode ~= "off", {
                title = "Pandemic Marker Advanced",
                build = BuildPandemicMarkerAdvanced,
            })
    end

    -- The shared helper takes no `disabled`, so the inert bracket is what makes
    -- this half read-only along with the rest of the section.
    markerSec:Finish()
end

local function BuildReadyGlowSection(container, group, style, lens)
    local readySec = BeginLensSection(lens, group, "readyGlow", { column = container })

    local readyEnableCb = AddCheckboxRow(container, {
        label = "Show Ready Glow",
        value = readySec.read.readyGlowStyle and readySec.read.readyGlowStyle ~= "none",
        disabled = readySec.disabled,
        onChange = function(val)
            if not readySec.write then return end
            readySec.write.readyGlowStyle = val and "solid" or "none"
            UpdateSelectedGroupStyle(true)
        end,
    })

    -- Single rail (AdvancedSettingsPanel.lua): a panel is one narrow column, so
    -- every row goes straight onto the panel scroll and the shared glow builder
    -- runs in row mode with NO rightColumn.
    --
    -- The panel captures the section's WRITE table, which is the group style or
    -- the selected entry's override store depending on scope; the whole
    -- when-it-shows chain below follows the section it belongs to. Only built
    -- while there is a write table: an inert section has no gear to open it
    -- from. The Prime* calls follow the same scope: an entry-lens edit changed
    -- ONE entry's glow config, so only that entry's per-button transition
    -- state re-arms - re-priming the panel would restart auto-hide windows on
    -- entries the edit never touched.
    local primeTarget = (lens and lens.mode == "entry") and lens.buttonData or nil
    local function BuildReadyGlowAdvanced(panel)
        AddCheckboxRow(panel, {
            label = "Show Only In Combat",
            value = readySec.write.readyGlowCombatOnly or false,
            onChange = function(val)
                readySec.write.readyGlowCombatOnly = val
                UpdateSelectedGroupStyle()
            end,
        })

        -- The longest label in the panel: it fills the label half of a ~330px
        -- panel almost exactly, so the row also states it on hover rather than
        -- risking a silent truncation at a narrower config width.
        local readyChargesRow = AddCheckboxRow(panel, {
            label = "Glow When Charges Are Capped",
            value = readySec.write.readyGlowOnlyAtMaxCharges or false,
            tooltip = { "Glow When Charges Are Capped" },
            onChange = function(val)
                readySec.write.readyGlowOnlyAtMaxCharges = val == true
                UpdateSelectedGroupStyle()
                if (readySec.write.readyGlowDuration or 0) > 0 then
                    if val then
                        PrimeReadyGlowCappedChargeTransitions(CS.selectedGroup, primeTarget)
                    else
                        PrimeReadyGlowNormalTransitions(CS.selectedGroup, primeTarget)
                    end
                end
                CooldownCompanion:UpdateAllCooldowns()
            end,
        })
        -- Anchor args are a placeholder - AnchorRowBadge re-points the button
        -- onto the end of the row's label.
        AnchorRowBadge(readyChargesRow, CreateInfoButton(readyChargesRow.frame, readyChargesRow.frame, "LEFT", "LEFT", 0, 0, {
            "Glow When Charges Are Capped",
            {"When this toggle is enabled, the glow will only appear for charge based spells when at max charges.", 1, 1, 1, true},
        }, tabInfoButtons))

        AddCheckboxRow(panel, {
            label = "Auto-Hide After Duration",
            value = (readySec.write.readyGlowDuration or 0) > 0,
            onChange = function(val)
                readySec.write.readyGlowDuration = val and 3 or 0
                UpdateSelectedGroupStyle()
                if val then
                    if readySec.write.readyGlowOnlyAtMaxCharges then
                        PrimeReadyGlowCappedChargeTransitions(CS.selectedGroup, primeTarget)
                    else
                        PrimeReadyGlowNormalTransitions(CS.selectedGroup, primeTarget)
                    end
                end
                CooldownCompanion:UpdateAllCooldowns()
                -- Rebuilds THIS panel, not the whole config, which is what
                -- makes the duration slider below appear and disappear in place.
                RefreshActiveAdvancedSettingsPanel()
            end,
        })

        if (readySec.write.readyGlowDuration or 0) > 0 then
            local durationRow = AddSliderRow(panel, {
                label = "Duration (seconds)",
                indent = true,
                min = 0.5, max = 5, step = 0.5,
                value = readySec.write.readyGlowDuration or 3,
            })
            WireMirrorFirstSlider(durationRow, function(val)
                readySec.write.readyGlowDuration = val
            end, UpdateSelectedGroupStyle, nil, readySec.write, "readyGlowDuration")
        end

        BuildReadyGlowControls(panel, readySec.write, UpdateSelectedGroupStyle, { row = true })

    end

    if readySec.write then
        AddAdvancedToggle(readyEnableCb, "readyGlow", tabInfoButtons, readySec.read.readyGlowStyle and readySec.read.readyGlowStyle ~= "none", {
            title = "Ready Glow Advanced",
            build = BuildReadyGlowAdvanced,
        })
    end
    -- Second badge in the chain: gear, then this, then the scope chrome the lens
    -- attaches last. The anchor args are a placeholder.
    AnchorRowBadge(readyEnableCb, CreateInfoButton(readyEnableCb.frame, readyEnableCb.frame, "LEFT", "LEFT", 0, 0, {
        "Ready Glow",
        {"Adds a glow to spells/items that are not on cooldown.", 1, 1, 1, true},
    }, tabInfoButtons))
    readySec:Chrome(readyEnableCb)

    readySec:Finish()

    if not (readySec.read.readyGlowStyle and readySec.read.readyGlowStyle ~= "none") then
        CooldownCompanion:SetGroupReadyGlowPreview(CS.selectedGroup, false)
    end
end

local function BuildKeyPressHighlightSection(container, group, style, lens)
    local kphSec = BeginLensSection(lens, group, "keyPressHighlight", { column = container })

    local kphEnableCb = AddCheckboxRow(container, {
        label = "Show Key Press Highlight",
        value = kphSec.read.keyPressHighlightStyle and kphSec.read.keyPressHighlightStyle ~= "none",
        disabled = kphSec.disabled,
        onChange = function(val)
            if not kphSec.write then return end
            kphSec.write.keyPressHighlightStyle = val and "solid" or "none"
            UpdateSelectedGroupStyle(true)
        end,
    })

    -- Single rail (AdvancedSettingsPanel.lua): row mode, no rightColumn. The
    -- panel captures the section's WRITE table and is only built while there is
    -- one - an inert section has no gear to open it from.
    local function BuildKeyPressHighlightAdvanced(panel)
        AddCheckboxRow(panel, {
            label = "Show Only In Combat",
            value = kphSec.write.keyPressHighlightCombatOnly or false,
            onChange = function(val)
                kphSec.write.keyPressHighlightCombatOnly = val
                UpdateSelectedGroupStyle()
            end,
        })

        BuildKeyPressHighlightControls(panel, kphSec.write, UpdateSelectedGroupStyle, { row = true })

    end

    if kphSec.write then
        AddAdvancedToggle(kphEnableCb, "keyPressHighlight", tabInfoButtons, kphSec.read.keyPressHighlightStyle and kphSec.read.keyPressHighlightStyle ~= "none", {
            title = "Key Press Highlight Advanced",
            build = BuildKeyPressHighlightAdvanced,
        })
    end
    -- Second badge in the chain: gear, then this, then the scope chrome the lens
    -- attaches last. The anchor args are a placeholder.
    AnchorRowBadge(kphEnableCb, CreateInfoButton(kphEnableCb.frame, kphEnableCb.frame, "LEFT", "LEFT", 0, 0, {
        "Key Press Highlight",
        {"Shows a glow overlay on buttons while their action bar keybind is physically held down.", 1, 1, 1, true},
    }, tabInfoButtons))
    kphSec:Chrome(kphEnableCb)

    kphSec:Finish()

    if not (kphSec.read.keyPressHighlightStyle and kphSec.read.keyPressHighlightStyle ~= "none") then
        CooldownCompanion:SetGroupKeyPressHighlightPreview(CS.selectedGroup, false)
    end
end

-- The Indicators tab's three row-grammar sections. They collapse like every
-- other row-grammar section, which means the advanced gears inside them only
-- build while their section is open - and a queued advanced key with no gear
-- left to consume it expires silently (ConsumeQueuedAdvancedSettingsPanelOpen).
--
-- So this file, which owns both the sections and the AddAdvancedToggle keys
-- below, also states which section each gear sits in. The preview command
-- center reads the map before it queues and clears that collapse key on the
-- way past (PreviewCommandCenter's ApplyGearRoute). Keep the two in step: a
-- gear added to one of these sections belongs here the same day.
--
-- BAR MODE SHARES THESE KEYS. BarModeTabs draws its own Glows / Timers /
-- States sections and deliberately reuses these three collapse keys, so one
-- entry per advanced key covers both tabs. That is why `barActiveAura` - a
-- bars-only gear - lives in this icons-owned map: the map is keyed by gear,
-- and a key reached in a mode that has no such section just clears a collapse
-- state nothing is reading.
local EFFECTS_GLOWS_SECTION = "effects_glows"
local EFFECTS_PANDEMIC_SECTION = "effects_pandemic"
local EFFECTS_TIMERS_SECTION = "effects_timers"
local EFFECTS_STATES_SECTION = "effects_states"

ST._INDICATORS_SECTION_BY_ADVANCED_KEY = {
    procGlow = EFFECTS_GLOWS_SECTION,
    readyGlow = EFFECTS_GLOWS_SECTION,
    keyPressHighlight = EFFECTS_GLOWS_SECTION,
    auraGlow = EFFECTS_GLOWS_SECTION,
    assistedHighlight = EFFECTS_GLOWS_SECTION,
    barActiveAura = EFFECTS_GLOWS_SECTION,

    -- The refresh window owns both its visuals, so both gears sit in the
    -- Pandemic section rather than beside unrelated glows and unrelated text.
    -- The bars route reaches this section by name instead of by key (it has
    -- no gear of its own): PreviewCommandCenter's barPandemic `uncollapse`.
    pandemicGlow = EFFECTS_PANDEMIC_SECTION,
    pandemicMarker = EFFECTS_PANDEMIC_SECTION,
    barPandemicMarker = EFFECTS_PANDEMIC_SECTION,

    iconFillTimer = EFFECTS_TIMERS_SECTION,
    cooldownSwipe = EFFECTS_TIMERS_SECTION,
    auraDurationSwipe = EFFECTS_TIMERS_SECTION,

    unusableVisual = EFFECTS_STATES_SECTION,
    tooltipBehavior = EFFECTS_STATES_SECTION,

    -- Textures mode's own section (BuildTextureEffectsTab above). Its constant
    -- is declared beside that builder because the builder reads it.
    textureIndicator_proc = EFFECTS_TEXTURE_INDICATORS_SECTION,
    textureIndicator_ready = EFFECTS_TEXTURE_INDICATORS_SECTION,
    textureIndicator_unusable = EFFECTS_TEXTURE_INDICATORS_SECTION,
}

-- The icons Indicators tab's advanced gears, by the OVERRIDE SECTION each one
-- belongs to. A SECOND map for the same gears, because it answers a different
-- question than the collapse map directly above: that one says "which
-- COLLAPSE section is this gear inside", this one says "which OVERRIDE section
-- owns this gear's values". Shaped and named after the appearance, bars and
-- text maps (ST._APPEARANCE_SECTION_BY_ADVANCED_KEY and friends) - never feed
-- one map's values to the other's consumer.
--
-- The style lens reads it at the foot of BOTH icons builders: a section the
-- selected entry only INHERITS builds no gear at all, so nothing rebinds or
-- closes an advanced panel that was already open on it, and that panel's
-- controls still point at the table the previous build handed them. Only one
-- panel tab is ever built at a time, so each icons builder sweeps this map AND
-- ST._APPEARANCE_SECTION_BY_ADVANCED_KEY (GroupTabsAppearance.lua).
--
-- It lists every icons-mode gear on the tab. Bars-only gears (barActiveAura,
-- barPandemicMarker) are NOT here - BarModeTabs owns and sweeps its own map -
-- and neither are the textures gears, which have no override sections at all.
--
-- A gear added to any section on this tab belongs here the same day.
ST._INDICATORS_OVERRIDE_SECTION_BY_ADVANCED_KEY = {
    procGlow = "procGlow",
    readyGlow = "readyGlow",
    keyPressHighlight = "keyPressHighlight",
    auraGlow = "auraIndicator",
    assistedHighlight = "assistedHighlight",

    -- One section for the whole refresh window, so both gears name it.
    pandemicGlow = "pandemic",
    pandemicMarker = "pandemic",

    iconFillTimer = "iconFillTimer",
    cooldownSwipe = "cooldownSwipe",
    auraDurationSwipe = "auraDurationSwipe",

    -- Named by the shared builders themselves (SectionBuilders.lua), which is
    -- why these two keys read differently from their section ids.
    unusableVisual = "unusableDimming",
    tooltipBehavior = "showTooltips",
}

local function BuildEffectsTab(container)
    ClearEffectsTabWidgets()

    if not CS.selectedGroup then return end
    local group = CooldownCompanion.db.profile.groups[CS.selectedGroup]
    if not group then return end
    local style = group.style

    local displayMode = group.displayMode
    local previewContextChanged = CS.lastEffectsPreviewGroup ~= CS.selectedGroup
        or CS.lastEffectsPreviewMode ~= displayMode
    if previewContextChanged then
        ResetEffectsTabPreviews()
        CS.lastEffectsPreviewGroup = CS.selectedGroup
        CS.lastEffectsPreviewMode = displayMode
    end

    if displayMode == "trigger" then
        BuildTriggerEffectsTab(container, group)
        return
    end

    if displayMode == ST.DISPLAY_MODE_ROTATION_ASSISTANT then
        -- Row grammar, reusing the icons tab's own Timers/States collapse keys
        -- (the bar-mode precedent stated above the section map): one entry per
        -- advanced key covers every mode that draws the section, so the
        -- `unusableVisual` and `tooltipBehavior` gears in here are queue-safe
        -- for free. A rotation assistant panel has no per-entry style, so no
        -- section in here carries scope chrome.
        local _, raTimersCollapsed = BuildCollapsibleSection(container, "Timers", EFFECTS_TIMERS_SECTION, nil, nil, ROW_SECTION)

        if not raTimersCollapsed then
        -- LEFT column: the cooldown swipe and the chain hanging off it - one
        -- parent chain, so it never splits. RIGHT column: the GCD swipe.
        local raTimerLeft, raTimerRight = BeginRowGrid(container)

        BuildCooldownSwipeControls(raTimerLeft, style, function()
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end, { row = true })
        BuildShowGCDSwipeControls(raTimerRight, style, function()
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end, { row = true })
        end -- not raTimersCollapsed

        local _, raStatesCollapsed = BuildCollapsibleSection(container, "States", EFFECTS_STATES_SECTION, nil, nil, ROW_SECTION)

        if not raStatesCollapsed then
        -- Same split the icons States section uses: LEFT the three looks an
        -- icon can take (on cooldown, unusable, out of range), RIGHT the
        -- situational state and the hover behavior.
        local raStateLeft, raStateRight = BeginRowGrid(container)

        BuildDesaturationControls(raStateLeft, style, function()
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end, { row = true })
        BuildUnusableDimmingControls(raStateLeft, style, function()
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
            CooldownCompanion:RefreshConfigPanel()
        end, { row = true })
        BuildShowOutOfRangeControls(raStateLeft, style, function()
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
            CooldownCompanion:RefreshConfigPanel()
        end, { row = true })

        BuildLossOfControlControls(raStateRight, style, function()
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end, { row = true })
        BuildShowTooltipsControls(raStateRight, style, function()
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
            CooldownCompanion:RefreshConfigPanel()
        end, { row = true, advanced = true })
        BuildAllowPingsControls(raStateRight, style, function()
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end, { row = true })
        end -- not raStatesCollapsed
        return
    end

    if displayMode == "textures" then
        BuildTextureEffectsTab(container, group)
        return
    end

    if displayMode == "bars" then
        BuildBarModeEffects(container, group, style, previewContextChanged)
        return
    end

    -- ================================================================
    -- Row grammar (RowWidgets.lua) - icons mode only; every other display
    -- mode returned above. Each setting is a fixed-height row (label left,
    -- control right-aligned in a 140px column, gear/info/scope badges
    -- chained off the end of the label), and each section splits its rows
    -- into a curated two-column grid from BeginRowGrid.
    --
    -- All four sections collapse, like every other row-grammar section. The
    -- preview command center's quick-access gears queue advanced keys at the
    -- toggles below and a gear that never builds expires silently, so the
    -- collapse keys are declared alongside the gear-to-section map above and
    -- the gear route clears the right one before the rebuild.
    --
    -- Headers own the vertical air before their section, so nothing adds
    -- spacers of its own.
    --
    -- Every badge-bearing row here ends in a checkbox, so no badge had to
    -- move off a wide control.
    -- ================================================================

    -- STYLE LENS (Helpers.lua). With an entry selected these sections stop
    -- being the panel's settings and become a view of that entry's EFFECTIVE
    -- ones, with per-section scope deciding where - or whether - they write.
    -- Resolved ONCE here and handed to every section below, so one tab cannot
    -- disagree with itself about which entry it is showing.
    local lens = ST._ResolveStyleLens(group)

    -- Under a multi selection these sections edit the PANEL, and only this line
    -- says so - the per-section scope chrome speaks under an entry lens alone.
    -- No-op in every other lens mode. The trigger, texture, assistant and
    -- bar-mode paths returned above, so only the standard icons path carries
    -- it; the modes with their own builders add their own.
    AddLensPanelScopeNote(container, lens)

    -- ================================================================
    -- Glows
    -- ================================================================
    -- On an Aura Panel the aura glow is the only row this section can hold, and
    -- that one is gated on the group tracking an aura - so an Aura Panel with no
    -- entries yet would draw the heading over nothing. The two gates that empty
    -- it are named once here and once at Timers below.
    local groupHasAuraEntry = GroupHasAuraTrackingEntry(group)
    -- COLUMN ROUTING on an Aura Panel (owner ruling 2026-08-15). Three sections
    -- below lose their whole LEFT column to the panel predicate and keep a row
    -- on the right; the standing fill rule (stated in full in the recipe comment
    -- at the top of BuildAppearanceTab's icons path, rule 3) says a filtered row
    -- set fills the left column first, so those survivors move across. Each host
    -- below is picked from this predicate alone, so an ordinary panel's columns
    -- are byte-identical to before.
    local isAuraPanel = ST.IsAuraPanelGroup(group)
    if CanGroupUseOverrideSection(group, "procGlow") or groupHasAuraEntry then
    local _, glowsCollapsed = BuildCollapsibleSection(container, "Glows", EFFECTS_GLOWS_SECTION, nil, nil, ROW_SECTION)

    if not glowsCollapsed then
    -- LEFT column: the glows every icon panel can show.
    -- RIGHT column: the conditional one (aura) and the Blizzard-driven extra.
    --
    -- On an Aura Panel the left column empties out: proc, ready and key-press
    -- glows all read spell state this panel's entries do not have, so the aura
    -- glow is the whole section (ST.CanGroupUseOverrideSection).
    local glowLeft, glowRight = BeginRowGrid(container)

    if CanGroupUseOverrideSection(group, "procGlow") then
        BuildProcGlowSection(glowLeft, group, style, lens)
    end
    if CanGroupUseOverrideSection(group, "readyGlow") then
        BuildReadyGlowSection(glowLeft, group, style, lens)
    end
    if CanGroupUseOverrideSection(group, "keyPressHighlight") then
        BuildKeyPressHighlightSection(glowLeft, group, style, lens)
    end

    -- Gated on the group tracking an aura, so this column can run a row short;
    -- the grid top-aligns its columns, so a short side just ends early.
    --
    -- On an Aura Panel it is the section's ONLY row (the three above are denied
    -- and Assisted Highlight below is too), so it takes the left column instead
    -- of stranding itself beside an empty one.
    BuildAuraGlowSection(isAuraPanel and glowLeft or glowRight, group, style, lens)

    -- Assisted Highlight is an override section like the four glows above, and
    -- gets its FIRST per-entry affordance here: it never carried a promote
    -- badge, so under the lens the scope chrome is the whole of it (the
    -- appearance tab's Icon Zoom row set the precedent).
    if CanGroupUseOverrideSection(group, "assistedHighlight") then
    local assistedSec = BeginLensSection(lens, group, "assistedHighlight", { column = glowRight })

    local assistedCb = AddCheckboxRow(glowRight, {
        label = "Show Assisted Highlight",
        value = assistedSec.read.showAssistedHighlight or false,
        disabled = assistedSec.disabled,
        onChange = function(val)
            if not assistedSec.write then return end
            assistedSec.write.showAssistedHighlight = val
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
            CooldownCompanion:RefreshConfigPanel()
        end,
    })

    -- Single rail (AdvancedSettingsPanel.lua): row mode, no rightColumn - the
    -- builder's row path falls back to `container` for its right-hand rows. The
    -- panel captures the section's WRITE table and is only built while there is
    -- one - an inert section has no gear to open it from.
    local function BuildAssistedHighlightAdvanced(panel)
        AddCheckboxRow(panel, {
            label = "Show Only In Combat",
            value = assistedSec.write.assistedHighlightCombatOnly or false,
            onChange = function(val)
                assistedSec.write.assistedHighlightCombatOnly = val
                CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
            end,
        })

        BuildAssistedHighlightControls(panel, assistedSec.write, function()
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end, { row = true })
    end

    if assistedSec.write then
        AddAdvancedToggle(assistedCb, "assistedHighlight", tabInfoButtons, assistedSec.read.showAssistedHighlight or false, {
            title = "Assisted Highlight Advanced",
            build = BuildAssistedHighlightAdvanced,
        })
    end
    assistedSec:Chrome(assistedCb)

    assistedSec:Finish()
    end -- CanGroupUseOverrideSection assistedHighlight
    end -- not glowsCollapsed
    end -- Glows section has at least one row

    -- ================================================================
    -- Pandemic
    -- ================================================================
    -- Both halves are aura-only, so unlike Glows the whole header is gated -
    -- an empty "Pandemic" heading on a group with no aura entry would be a
    -- promise of nothing. The effect builder still runs with a nil host so it
    -- can reconcile its preview; the bars twin has carried that contract
    -- since PTR 8 and this side needs it for the same reason.
    local pandemicLeft, pandemicRight
    if GroupHasAuraTrackingEntry(group) then
        -- Both halves are the one "pandemic" section, so the collapsible's key
        -- follows that section's scope through ST._ResolveLensCollapseKey.
        local pandemicHeading, pandemicCollapsed = BuildCollapsibleSection(container, "Pandemic",
            ResolveLensCollapseKey(lens, group, "pandemic", EFFECTS_PANDEMIC_SECTION), nil, nil, ROW_SECTION)
        -- ONE scope chrome for the whole feature, on the HEADING (owner ruling):
        -- the glow and the marker are two rows of one override section, so a
        -- per-row affordance would offer the same customize twice and revert
        -- from either would silently take the other with it. Both halves resolve
        -- "pandemic" and flip together, silently. This section exists only to
        -- carry the heading chrome; each half brackets its own column.
        BeginLensSection(lens, group, "pandemic"):HeadingChrome(pandemicHeading)
        if not pandemicCollapsed then
            -- LEFT the glow half, RIGHT the text half.
            pandemicLeft, pandemicRight = BeginRowGrid(container)
        end
    end
    BuildPandemicGlowSection(pandemicLeft, group, style, lens)
    BuildPandemicMarkerSection(pandemicRight, group, style, lens)

    -- ================================================================
    -- Timers
    -- ================================================================
    -- Same shape as Glows above: on an Aura Panel the aura duration swipe is the
    -- only timer left, and it needs an aura-tracking entry to exist.
    if CanGroupUseOverrideSection(group, "cooldownSwipe") or groupHasAuraEntry then
    local _, timersCollapsed = BuildCollapsibleSection(container, "Timers", EFFECTS_TIMERS_SECTION, nil, nil, ROW_SECTION)

    if not timersCollapsed then
    -- LEFT column: the two cooldown timers, adjacent because the fill timer
    -- disables the swipe.
    -- RIGHT column: the aura timer (gated on an aura-tracking entry) and the
    -- GCD swipe, which is ungated - on a group with no aura entry this column
    -- is the GCD swipe alone.
    local timerLeft, timerRight = BeginRowGrid(container)

    -- Each of the four sections below resolves its own scope against the lens.
    -- The write table is the whole gate: nil means the section is INERT, so its
    -- rows go in read-only, it builds no gear, and no callback of its own can
    -- reach a saved table. The scope chrome is attached LAST on the row (after
    -- the gear, after any info button, after the row's disabled state is
    -- final), because it is the one control that stays live in an inert section
    -- - the way back out of it.
    -- The shared builder takes no `disabled` option of its own, so an inert
    -- scope is applied by bracketing its rows instead - the same shape the bars
    -- States section uses for its two shared builders. The gear below is
    -- caller-built, so it is gated the ordinary way.
    --
    -- On an Aura Panel the left column empties out and the GCD swipe leaves the
    -- right one: the fill timer, the cooldown swipe and the GCD swipe all time a
    -- spell cooldown these entries do not have, so the aura duration swipe is
    -- the whole section (ST.CanGroupUseOverrideSection).
    local showCooldownTimers = CanGroupUseOverrideSection(group, "cooldownSwipe")

    -- The interlock derives from the RESOLVED READ table, not the panel style:
    -- an entry whose effective fill timer differs from the panel's has to see
    -- its own swipe row greyed (or not). Masque is GROUP data with no override
    -- section, so that half of the gate stays group-level. Nothing to interlock
    -- once the cooldown timers are gone.
    local iconFillTimerActive = false

    if showCooldownTimers then
    local fillSec = BeginLensSection(lens, group, "iconFillTimer", { column = timerLeft })

    iconFillTimerActive = fillSec.read.iconFillEnabled == true and group.masqueEnabled ~= true
    local iconFillCb = BuildIconFillTimerControls(timerLeft, fillSec.tbl, function()
        CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
    end, {
        row = true,
        masqueEnabled = group.masqueEnabled == true,
        showAdvancedControlsInline = false,
        fallbackStyle = fillSec.fallbackStyle,
        onEnabled = function()
            if CS.QueueAdvancedSettingsPanelOpen then
                CS.QueueAdvancedSettingsPanelOpen("iconFillTimer")
            end
        end,
    })
    -- Single rail (AdvancedSettingsPanel.lua): row mode, no rightColumn. The
    -- panel captures the section's WRITE table and is only built while there is
    -- one - an inert section has no gear to open it from.
    local function BuildIconFillAdvanced(panel)
        if BuildIconFillTimerAdvancedControls then
            BuildIconFillTimerAdvancedControls(panel, fillSec.write, function()
                CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
            end, { row = true, indent = false })
        end
    end

    if fillSec.write then
        AddAdvancedToggle(iconFillCb, "iconFillTimer", tabInfoButtons, iconFillTimerActive, {
            title = "Icon Fill Timer Advanced",
            build = BuildIconFillAdvanced,
        })
    end
    -- Second badge in the chain: gear, then this, then the scope chrome the
    -- lens attaches last. AnchorRowBadge appends to whatever the chain actually
    -- ends at (the gear is not chained while it is hidden or unbuilt), so the
    -- anchor args below are a placeholder.
    AnchorRowBadge(iconFillCb, CreateInfoButton(iconFillCb.frame, iconFillCb.frame, "LEFT", "LEFT", 0, 0, {
        "Icon Fill Timer",
        {"Shows cooldowns as a rectangular fill over the icon instead of radial swipes.", 1, 1, 1, true},
        " ",
        {"Does not work while Masque is enabled.", 1, 1, 1, true},
        " ",
        {"Show Cooldown Swipe is unavailable while Icon Fill Timer is active.", 0.7, 0.7, 0.7, true},
    }, tabInfoButtons))
    fillSec:Chrome(iconFillCb)

    fillSec:Finish()

    -- One row, no gear of its own to bracket: `disabled` is the whole gate, and
    -- the chrome that undoes it is attached after.
    local swipeSec = BeginLensSection(lens, group, "cooldownSwipe")
    local swipeCb = AddCheckboxRow(timerLeft, {
        label = "Show Cooldown Swipe",
        value = swipeSec.read.showCooldownSwipe ~= false,
        disabled = swipeSec.disabled or iconFillTimerActive,
        onChange = function(val)
            if not swipeSec.write or iconFillTimerActive then return end
            swipeSec.write.showCooldownSwipe = val
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
            CooldownCompanion:RefreshConfigPanel()
        end,
    })

    if swipeSec.write then
        -- Panel scope hands the descriptor NO table, so it keeps resolving the
        -- live group style itself (see the factory's note). An entry's override
        -- store has no such resolver, so that one is handed over explicitly.
        local swipeAdvanced = MakeCooldownSwipeAdvancedDescriptor(
            swipeSec.scope == "customized" and swipeSec.write or nil)

        AddAdvancedToggle(swipeCb, swipeAdvanced.settingKey, tabInfoButtons,
            swipeSec.read.showCooldownSwipe ~= false and not iconFillTimerActive, {
                title = swipeAdvanced.title,
                build = swipeAdvanced.build,
            })
    end
    swipeSec:Chrome(swipeCb)
    end -- showCooldownTimers

    -- Aura duration swipe (shown only while the group has an aura-tracking
    -- entry). The gate stays on the GROUP: an entry that tracks no aura still
    -- sees the row, and the lens resolves it "not available" for that entry
    -- rather than hiding it.
    --
    -- On an Aura Panel it is the section's ONLY row (the fill timer, the
    -- cooldown swipe and the GCD swipe are all denied), so it takes the left
    -- column instead of stranding itself beside an empty one.
    if GroupHasAuraTrackingEntry(group) then
        local auraSwipeHost = isAuraPanel and timerLeft or timerRight
        local auraSwipeSec = BeginLensSection(lens, group, "auraDurationSwipe", { column = auraSwipeHost })

        local auraDurationCb = BuildAuraDurationSwipeControls(auraSwipeHost, auraSwipeSec.tbl, function()
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end, {
            row = true,
            showAdvancedControlsInline = false,
            fallbackStyle = auraSwipeSec.fallbackStyle,
        })
        -- Single rail (AdvancedSettingsPanel.lua): row mode, no rightColumn. The
        -- panel captures the section's WRITE table and is only built while there
        -- is one - an inert section has no gear to open it from.
        local function BuildAuraDurationSwipeAdvanced(panel)
            BuildAuraDurationSwipeAdvancedControls(panel, auraSwipeSec.write, function()
                CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
            end, { row = true })
        end
        if auraSwipeSec.write then
            AddAdvancedToggle(auraDurationCb, "auraDurationSwipe", tabInfoButtons, auraSwipeSec.read.showAuraDurationSwipe ~= false, {
                title = "Aura Duration Swipe Advanced",
                build = BuildAuraDurationSwipeAdvanced,
            })
        end
        auraSwipeSec:Chrome(auraDurationCb)

        auraSwipeSec:Finish()
    end

    -- One row, no gear: `disabled` is the whole gate, so no inert bracket is
    -- needed - the chrome that undoes it is attached after. Same shape the bars
    -- Timers section uses for this setting.
    if CanGroupUseOverrideSection(group, "showGCDSwipe") then
    local gcdSec = BeginLensSection(lens, group, "showGCDSwipe")
    local gcdCb = AddCheckboxRow(timerRight, {
        label = "Show GCD Swipe",
        value = gcdSec.read.showGCDSwipe == true,
        disabled = gcdSec.disabled,
        onChange = function(val)
            if not gcdSec.write then return end
            gcdSec.write.showGCDSwipe = val
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end,
    })
    gcdSec:Chrome(gcdCb)
    end -- CanGroupUseOverrideSection showGCDSwipe
    end -- not timersCollapsed
    end -- Timers section has at least one row

    -- ================================================================
    -- States
    -- ================================================================
    local _, statesCollapsed = BuildCollapsibleSection(container, "States", EFFECTS_STATES_SECTION, nil, nil, ROW_SECTION)

    if not statesCollapsed then
    -- LEFT column: the three looks every icon has (on cooldown, unusable,
    -- out of range).
    -- RIGHT column: the situational state and the hover behavior.
    local stateLeft, stateRight = BeginRowGrid(container)

    -- On an Aura Panel the left column empties out and Loss of Control leaves
    -- the right one: desaturate-on-cooldown, the unusable visual, out-of-range
    -- and loss-of-control all read spell cooldown or castability state these
    -- entries do not have, and pings refuse aura entries by their own rule. What
    -- is left is Show Tooltips, which is about the frame rather than the spell.
    --
    -- Same per-section resolve the Timers section above states: the write table
    -- is the whole gate, and the scope chrome goes on LAST.
    if CanGroupUseOverrideSection(group, "desaturation") then
    local desatSec = BeginLensSection(lens, group, "desaturation")
    local desatCb = AddCheckboxRow(stateLeft, {
        label = "Desaturate On Cooldown",
        value = desatSec.read.desaturateOnCooldown or false,
        disabled = desatSec.disabled,
        onChange = function(val)
            if not desatSec.write then return end
            desatSec.write.desaturateOnCooldown = val
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end,
    })
    desatSec:Chrome(desatCb)
    end -- CanGroupUseOverrideSection desaturation

    -- The missing-aura sibling of the row above, as its OWN section (owner
    -- ruling 2026-08-16: riding the desaturation section made it customizable
    -- only through the cooldown toggle's chrome). Static desat on the CC icon,
    -- meaningful only while the group tracks an aura; passives are not served
    -- here - they gray while missing by default, with the entry tab's Never
    -- Desaturate as their off switch - and the section is aura-entry-denied
    -- plus aura-tracking-config-only, so a lens on the wrong kind of entry
    -- reads it denied rather than misleadingly live.
    if groupHasAuraEntry and CanGroupUseOverrideSection(group, "auraMissingDesaturation") then
    local missingSec = BeginLensSection(lens, group, "auraMissingDesaturation")
    local missingCb = AddCheckboxRow(stateLeft, {
        label = "Desaturate While Aura Missing",
        value = missingSec.read.desaturateWhileAuraNotActive == true,
        disabled = missingSec.disabled,
        onChange = function(val)
            if not missingSec.write then return end
            missingSec.write.desaturateWhileAuraNotActive = missingSec:BoolValue(val)
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end,
    })
    -- Anchor args are a placeholder - AnchorRowBadge re-points the button onto
    -- the end of the row's label. Passive-sourced auras never read this key
    -- (Tracking.lua's passive branch desaturates by default), which the owner
    -- found surprising in game; the badge states the split once.
    AnchorRowBadge(missingCb, CreateInfoButton(missingCb.frame, missingCb.frame, "LEFT", "LEFT", 0, 0, {
        "Desaturate While Aura Missing",
        {"Grays the icon while the tracked aura is not active.", 1, 1, 1, true},
        {" ", 1, 1, 1, true},
        {"Passive auras already do this by default and ignore this setting. Use Never Desaturate on the entry to turn theirs off.", 1, 1, 1, true},
    }, tabInfoButtons))
    missingSec:Chrome(missingCb)
    end -- CanGroupUseOverrideSection auraMissingDesaturation

    -- Unusable Visual. This shared builder owns its OWN gear, so an inert scope
    -- cannot skip building one the way the hand-written sections do: the inert
    -- pass gates the gear it finds on the row (_cdcAdvancedBtn), and the sweep
    -- at the foot of this builder closes a panel it rebound.
    if CanGroupUseOverrideSection(group, "unusableDimming") then
    local unusableSec = BeginLensSection(lens, group, "unusableDimming", { column = stateLeft })
    local unusableCb = BuildUnusableDimmingControls(stateLeft, unusableSec.tbl, function()
        CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        CooldownCompanion:RefreshConfigPanel()
    end, {
        row = true,
        fallbackStyle = unusableSec.fallbackStyle,
    })
    unusableSec:Chrome(unusableCb)
    unusableSec:Finish()
    end -- CanGroupUseOverrideSection unusableDimming

    -- Inlined rather than given an opts.row mode: BuildShowOutOfRangeControls
    -- is one checkbox with no file-private state, the same call the Duration
    -- Format dropdown made on the Appearance tab. The shared builder is
    -- untouched for the override editor and the other display modes.
    if CanGroupUseOverrideSection(group, "showOutOfRange") then
    local oorSec = BeginLensSection(lens, group, "showOutOfRange")
    local oorCb = AddCheckboxRow(stateLeft, {
        label = "Show Out of Range",
        value = oorSec.read.showOutOfRange or false,
        disabled = oorSec.disabled,
        onChange = function(val)
            if not oorSec.write then return end
            oorSec.write.showOutOfRange = val
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
            CooldownCompanion:RefreshConfigPanel()
        end,
    })
    oorSec:Chrome(oorCb)
    end -- CanGroupUseOverrideSection showOutOfRange

    -- Loss of Control - inlined for the same reason as Out of Range.
    if CanGroupUseOverrideSection(group, "lossOfControl") then
    local locSec = BeginLensSection(lens, group, "lossOfControl")
    local locCb = AddCheckboxRow(stateRight, {
        label = "Show Loss of Control",
        value = locSec.read.showLossOfControl or false,
        disabled = locSec.disabled,
        onChange = function(val)
            if not locSec.write then return end
            locSec.write.showLossOfControl = val
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end,
    })
    locSec:Chrome(locCb)
    end -- CanGroupUseOverrideSection lossOfControl

    -- Show Tooltips (panel refresh: the advanced gear only shows while the
    -- toggle is on). Its gear is the builder's own, so it is bracketed rather
    -- than skipped - see the Unusable Visual note above.
    --
    -- On an Aura Panel it is the section's ONLY row (everything above is denied,
    -- and Allow Pings below is not offered), so it takes the left column instead
    -- of stranding itself beside an empty one.
    local tooltipHost = isAuraPanel and stateLeft or stateRight
    local tooltipSec = BeginLensSection(lens, group, "showTooltips", { column = tooltipHost })
    local tooltipCb = BuildShowTooltipsControls(tooltipHost, tooltipSec.tbl, function()
        CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        CooldownCompanion:RefreshConfigPanel()
    end, {
        row = true,
        advanced = true,
        infoButtons = tabInfoButtons,
        fallbackStyle = tooltipSec.fallbackStyle,
    })
    tooltipSec:Chrome(tooltipCb)
    tooltipSec:Finish()

    -- Allow Pings is a PANEL setting with no override section of its own
    -- (ST.OVERRIDE_SECTIONS), so under an entry lens it goes read-only with the
    -- rest of the panel-only content instead of letting a panel-wide edit be
    -- made from an entry's page - no scope chrome, and its reads and writes
    -- stay on the group style. A nil sectionId is how that is said to the lens:
    -- it resolves to no write table exactly under an entry lens. The shared
    -- builder takes no `disabled` option, so the bracket is what greys it. Its
    -- "?" badge stays readable: the inert walk only reaches AceGUI children and
    -- the gear.
    --
    -- Not offered on an Aura Panel: the row's own tooltip already says entries
    -- added as auras cannot be pinged, and every entry here is one. It has no
    -- override section of its own, so the gate is the panel predicate directly
    -- rather than CanGroupUseOverrideSection.
    if not CooldownCompanion:IsAuraPanel(group) then
    local pingsSec = BeginLensSection(lens, group, nil, { column = stateRight })
    BuildAllowPingsControls(stateRight, style, function()
        CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
    end, { row = true })
    pingsSec:Finish()
    end
    end -- not statesCollapsed

    -- Inert-section sweep, over BOTH icons gear maps. A section the lens
    -- resolved read-only builds no gear, so nothing rebound or closed an
    -- advanced panel that was already open on that gear - and its controls
    -- still write to the table the PREVIOUS build handed them. Close those here.
    --
    -- Scope-driven, not collapse-driven: a collapsed section builds no gear
    -- either, and a panel left over from before an entry was selected is just
    -- as live behind a closed section as behind an open one.
    --
    -- Both maps, not just this tab's: only one panel tab is ever built at a
    -- time, so a stale panel whose gear lives on the icons Appearance tab is
    -- just as live from here as one of this tab's own. The bars pair has swept
    -- across its two tabs the same way since they were converted.
    --
    -- OVERRIDE maps, never the collapse map beside them: they are keyed the
    -- same and answer different questions, and a collapse key handed to the lens
    -- would resolve as a section no entry can own and close every gear on the
    -- tab.
    if CS.CloseAdvancedSettingsPanel then
        local gearMaps = { ST._INDICATORS_OVERRIDE_SECTION_BY_ADVANCED_KEY, ST._APPEARANCE_SECTION_BY_ADVANCED_KEY }
        for i = 1, #gearMaps do
            for advancedKey, sectionId in pairs(gearMaps[i]) do
                local _, _, sectionWrite = ResolveLensSection(lens, group, sectionId)
                if sectionWrite == nil then
                    CS.CloseAdvancedSettingsPanel({ settingKey = advancedKey })
                end
            end
        end
    end
end

ST._BuildEffectsTab = BuildEffectsTab
ST._EFFECTS_GLOWS_SECTION = EFFECTS_GLOWS_SECTION
ST._EFFECTS_PANDEMIC_SECTION = EFFECTS_PANDEMIC_SECTION
ST._EFFECTS_TIMERS_SECTION = EFFECTS_TIMERS_SECTION
ST._EFFECTS_STATES_SECTION = EFFECTS_STATES_SECTION
