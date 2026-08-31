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
local AddLensPanelScopeNote = ST._AddLensPanelScopeNote

-- Imports from SectionBuilders.lua
local AddSettingsSubheading = ST._AddSettingsSubheading
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

-- Populated at module load near the exports. Exact maps are passed through the
-- shared effects builders because many advanced panels intentionally reuse
-- labels such as Glow Style, Border Size, and Show Only In Combat.
local EFFECTS_FINDER = {
    icons = { spell = {}, aura = {}, interaction = {} },
    assistant = { spell = {}, interaction = {} },
    advanced = {},
}

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
        setting = EFFECTS_FINDER.icons.spell.proc,
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
            setting = EFFECTS_FINDER.advanced.proc and EFFECTS_FINDER.advanced.proc.combatOnly,
            value = procSec.write.procGlowCombatOnly or false,
            onChange = function(val)
                procSec.write.procGlowCombatOnly = val
                UpdateSelectedGroupStyle()
            end,
        })

        BuildProcGlowControls(panel, procSec.write, UpdateSelectedGroupStyle, {
            row = true,
            settings = EFFECTS_FINDER.advanced.proc,
        })

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
        setting = EFFECTS_FINDER.icons.aura.auraGlow,
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
        BuildAuraGlowControls(panel, auraSec.write, UpdateSelectedGroupStyle, {
            row = true,
            settings = EFFECTS_FINDER.advanced.auraGlow,
        })
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
-- tracked aura sits inside its refresh window. It shares the Pandemic
-- subheading, and the "pandemic" OVERRIDE section, with the marker below — one
-- feature, two rows.
--
-- The section's ONE scope chrome sits on the Pandemic SUBHEADING (owner
-- ruling), so neither half carries a row affordance of its own: both resolve
-- the same "pandemic" section and flip together, silently. The bars twin makes
-- the same ruling with the chrome on its enable row.
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
            setting = EFFECTS_FINDER.icons.aura.pandemicEffect,
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
                settings = EFFECTS_FINDER.advanced.pandemicGlow,
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
-- Hide this half while that effective text surface is off; the glow half above
-- remains live because it does not depend on duration text.
local function BuildPandemicMarkerSection(container, group, style, lens)
    local effectiveStyle = (lens and lens.effective) or style
    if effectiveStyle and effectiveStyle.showAuraText == false then
        if CS.CloseAdvancedSettingsPanel then
            CS.CloseAdvancedSettingsPanel({ settingKey = "pandemicMarker" })
        end
        return
    end
    if not container or not GroupHasAuraTrackingEntry(group) then
        return
    end

    -- Same override section as the effect row in the left column, so this half
    -- FOLLOWS that section's scope silently: one feature, one affordance, and
    -- the chrome for it is on the Pandemic subheading.
    local markerSec = BeginLensSection(lens, group, "pandemic", { column = container })

    local applyStyle = function() UpdateSelectedGroupStyle(false) end
    local markerRow = AddPandemicMarkerControls(container, markerSec.tbl, applyStyle, function()
        CooldownCompanion:RefreshConfigPanel()
    end, {
        enableOnly = true,
        setting = EFFECTS_FINDER.icons.aura.pandemicMarker,
        onModeChanged = function(mode)
            ReconcilePandemicMarkerPreview(lens, mode)
        end,
    })

    -- Single rail (AdvancedSettingsPanel.lua): the three styling rows fill the
    -- panel, so they carry no indent - childrenOnly drops it. The panel
    -- captures the section's WRITE table, and is only built while there is one.
    local function BuildPandemicMarkerAdvanced(panel)
        AddPandemicMarkerControls(panel, markerSec.write, applyStyle, RefreshActiveAdvancedSettingsPanel,
            {
                childrenOnly = true,
                settings = EFFECTS_FINDER.advanced.pandemicMarker,
            })
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
        setting = EFFECTS_FINDER.icons.spell.ready,
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
            setting = EFFECTS_FINDER.advanced.ready and EFFECTS_FINDER.advanced.ready.combatOnly,
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
            setting = EFFECTS_FINDER.advanced.ready and EFFECTS_FINDER.advanced.ready.cappedCharges,
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
            setting = EFFECTS_FINDER.advanced.ready and EFFECTS_FINDER.advanced.ready.autoHide,
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
                setting = EFFECTS_FINDER.advanced.ready and EFFECTS_FINDER.advanced.ready.duration,
                indent = true,
                min = 0.5, max = 5, step = 0.5,
                value = readySec.write.readyGlowDuration or 3,
            })
            WireMirrorFirstSlider(durationRow, function(val)
                readySec.write.readyGlowDuration = val
            end, UpdateSelectedGroupStyle, nil, readySec.write, "readyGlowDuration")
        end

        BuildReadyGlowControls(panel, readySec.write, UpdateSelectedGroupStyle, {
            row = true,
            settings = EFFECTS_FINDER.advanced.ready,
        })

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
        setting = EFFECTS_FINDER.icons.spell.keyPress,
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
            setting = EFFECTS_FINDER.advanced.keyPress and EFFECTS_FINDER.advanced.keyPress.combatOnly,
            value = kphSec.write.keyPressHighlightCombatOnly or false,
            onChange = function(val)
                kphSec.write.keyPressHighlightCombatOnly = val
                UpdateSelectedGroupStyle()
            end,
        })

        BuildKeyPressHighlightControls(panel, kphSec.write, UpdateSelectedGroupStyle, {
            row = true,
            settings = EFFECTS_FINDER.advanced.keyPress,
        })

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

-- The Indicators tab's row-grammar sections. They collapse like every
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
-- BAR MODE SHARES THESE KEYS. BarModeTabs draws its own Cooldown / Spell
-- Indicators / Aura Indicators / Interaction sections and deliberately reuses
-- these collapse keys, so one entry per advanced key covers both tabs. That is
-- why `barActiveAura` - a bars-only gear - lives in this icons-owned map: the
-- map is keyed by gear, and a key reached in a mode that has no such section
-- just clears a collapse state nothing is reading.
--
-- TWO sections hold every indicator now (owner ruling 2026-08-30): the tab
-- splits at the SECTION level between the cooldown/spell family and the aura
-- family, and what used to be the Glows / Timers / States / Pandemic
-- collapsibles are quiet SUBHEADINGS inside them. Subheadings own no collapse
-- state, so "effects_glows", "effects_timers", "effects_states" and
-- "effects_pandemic" are retired outright - nothing may name them again.
local EFFECTS_SPELL_SECTION = "effects_spell"
local EFFECTS_AURA_SECTION = "effects_aura"
local EFFECTS_INTERACTION_SECTION = "effects_interaction"

ST._INDICATORS_SECTION_BY_ADVANCED_KEY = {
    -- Everything the SPELL's own state drives - the four glows, the two
    -- cooldown timers, the unusable visual - is one section with subheadings
    -- inside it, so every spell gear names that one key.
    procGlow = EFFECTS_SPELL_SECTION,
    readyGlow = EFFECTS_SPELL_SECTION,
    keyPressHighlight = EFFECTS_SPELL_SECTION,
    assistedHighlight = EFFECTS_SPELL_SECTION,

    -- The aura family has a section of its own on BOTH Indicators tabs (owner
    -- ruling 2026-08-30: one aura toggle stranded in each spell section's right
    -- column read as a lopsided column, not as a family), so every aura gear
    -- names it - icons' aura glow and aura duration swipe, bars' active aura
    -- indicator.
    auraGlow = EFFECTS_AURA_SECTION,
    auraDurationSwipe = EFFECTS_AURA_SECTION,
    barActiveAura = EFFECTS_AURA_SECTION,

    -- The refresh window is aura-only, so its two gears name the Aura
    -- Indicators section that now holds the Pandemic subheading. The bars route
    -- reaches the section by name instead of by key (its fill rows have no gear
    -- of their own): PreviewCommandCenter's barPandemic `uncollapse`.
    pandemicGlow = EFFECTS_AURA_SECTION,
    pandemicMarker = EFFECTS_AURA_SECTION,
    barPandemicMarker = EFFECTS_AURA_SECTION,

    iconFillTimer = EFFECTS_SPELL_SECTION,
    cooldownSwipe = EFFECTS_SPELL_SECTION,

    unusableVisual = EFFECTS_SPELL_SECTION,

    -- Hover and click behavior sit in Interaction, at the foot of the tab -
    -- they are about the frame under the pointer rather than the spell's
    -- state. Bars and the rotation assistant path draw the same section under
    -- the same key, so this one entry covers every mode that offers the gear.
    tooltipBehavior = EFFECTS_INTERACTION_SECTION,

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
        -- Row grammar, reusing the icons tab's own spell-family and Interaction
        -- collapse keys (the bar-mode precedent stated above the section map):
        -- one entry per advanced key covers every mode that draws the section,
        -- so the `unusableVisual` and `tooltipBehavior` gears in here are
        -- queue-safe for free. A rotation assistant panel has no per-entry
        -- style, so no section in here carries scope chrome.
        --
        -- Every row this path offers reads spell state, so they all live under
        -- the one Cooldown / Spell Indicators section the icons tab draws, with
        -- the same Timers / States subheadings inside it. A rotation assistant
        -- has no aura rows at all, so it draws no Aura Indicators section.
        local _, raSpellCollapsed = BuildCollapsibleSection(container, "Cooldown / Spell Indicators", EFFECTS_SPELL_SECTION, nil, nil, ROW_SECTION)

        if not raSpellCollapsed then
        AddSettingsSubheading(container, "Timers")
        -- A single left rail: this path offers two of the icons Timers rows (the
        -- cooldown swipe and the chain hanging off it - one parent chain, so it
        -- never splits - then the GCD swipe) and no aura rows at all, so the
        -- standing fill rule puts both on the left rather than splitting two
        -- rows across two columns the way the icons tab's fuller set does.
        local raTimerLeft = BeginRowGrid(container)

        BuildCooldownSwipeControls(raTimerLeft, style, function()
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end, { row = true, settings = EFFECTS_FINDER.assistant.cooldownSwipe })
        BuildShowGCDSwipeControls(raTimerLeft, style, function()
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end, { row = true, setting = EFFECTS_FINDER.assistant.spell.gcd })

        AddSettingsSubheading(container, "States")
        -- A single left rail, for the same reason as Timers above: the four
        -- looks a spell's state gives the icon (on cooldown, unusable, out of
        -- range, locked out of control) all in source order, rather than the
        -- two-column split the icons States subheading makes of the same set.
        local raStateLeft = BeginRowGrid(container)

        BuildDesaturationControls(raStateLeft, style, function()
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end, { row = true, setting = EFFECTS_FINDER.assistant.spell.desaturate })
        BuildUnusableDimmingControls(raStateLeft, style, function()
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
            CooldownCompanion:RefreshConfigPanel()
        end, {
            row = true,
            setting = EFFECTS_FINDER.assistant.spell.unusable,
            settings = EFFECTS_FINDER.assistant.unusableAdvanced,
        })
        BuildShowOutOfRangeControls(raStateLeft, style, function()
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
            CooldownCompanion:RefreshConfigPanel()
        end, { row = true, setting = EFFECTS_FINDER.assistant.spell.outOfRange })
        BuildLossOfControlControls(raStateLeft, style, function()
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end, { row = true, setting = EFFECTS_FINDER.assistant.spell.lossOfControl })
        end -- not raSpellCollapsed

        -- Interaction: the same split-out the icons and bars tabs make, under
        -- the same collapse key, at this path's own fidelity (a rotation
        -- assistant panel has no per-entry style, so no section in here carries
        -- scope chrome). LEFT the hover behavior, RIGHT the click behavior.
        local _, raInteractionCollapsed = BuildCollapsibleSection(container, "Interaction", EFFECTS_INTERACTION_SECTION, nil, nil, ROW_SECTION)

        if not raInteractionCollapsed then
        local raInteractionLeft, raInteractionRight = BeginRowGrid(container)

        BuildShowTooltipsControls(raInteractionLeft, style, function()
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
            CooldownCompanion:RefreshConfigPanel()
        end, {
            row = true,
            advanced = true,
            setting = EFFECTS_FINDER.assistant.interaction.tooltips,
            settings = EFFECTS_FINDER.assistant.tooltipAdvanced,
        })
        BuildAllowPingsControls(raInteractionRight, style, function()
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end, { row = true, setting = EFFECTS_FINDER.assistant.interaction.pings })
        end -- not raInteractionCollapsed
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
    -- THREE sections, and all three collapse like every other row-grammar
    -- section: Cooldown / Spell Indicators, Aura Indicators, Interaction (owner
    -- ruling 2026-08-30). The families that used to be collapsibles of their
    -- own - Glows, Timers, States, Pandemic - are quiet SUBHEADINGS inside the
    -- two indicator sections, so they carry no collapse state at all.
    --
    -- The preview command center's quick-access gears queue advanced keys at
    -- the toggles below and a gear that never builds expires silently, so the
    -- collapse keys are declared alongside the gear-to-section map above and
    -- the gear route clears the right one before the rebuild.
    --
    -- Headers own the vertical air before their section, so nothing adds
    -- spacers of its own; subheadings own the same air before their subgroup.
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

    -- Named once here: the Aura Indicators section below is gated on it
    -- outright, and the missing-aura row inside that section names it again
    -- beside its own override gate.
    local groupHasAuraEntry = GroupHasAuraTrackingEntry(group)

    -- ================================================================
    -- Cooldown / Spell Indicators
    -- ================================================================
    -- ONE section for everything the spell's own state drives (owner ruling
    -- 2026-08-30): the tab splits at the SECTION level between the
    -- cooldown/spell family and the aura family, the same vocabulary the
    -- Appearance grids caption their columns with. What used to be the Glows,
    -- Timers and States collapsibles are quiet SUBHEADINGS inside it
    -- (AddSettingsSubheading, the shape the Appearance Text section uses), so
    -- the whole family folds under one key.
    --
    -- On an Aura Panel EVERY row in here is denied - the four glows, the three
    -- timers and the four state looks all read spell cooldown, castability,
    -- proc or GCD state its pure-aura entries do not have - so the section is
    -- skipped outright rather than re-columned, and the heading never stands
    -- over nothing. Each subgroup shares ONE denial
    -- (ST.CanGroupUseOverrideSection answers the panel, not the row), so each
    -- subgroup's lead predicate speaks for its set and the or-chain of the
    -- three speaks for the section. A subgroup whose rows are all denied is
    -- skipped with its subheading.
    local spellGlowsShown = CanGroupUseOverrideSection(group, "procGlow")
    local spellTimersShown = CanGroupUseOverrideSection(group, "cooldownSwipe")
    local spellStatesShown = CanGroupUseOverrideSection(group, "desaturation")

    if spellGlowsShown or spellTimersShown or spellStatesShown then
    local _, spellCollapsed = BuildCollapsibleSection(container, "Cooldown / Spell Indicators", EFFECTS_SPELL_SECTION, nil, nil, ROW_SECTION)

    if not spellCollapsed then

    -- ---------------------------------------------------------------
    -- Glows
    -- ---------------------------------------------------------------
    if spellGlowsShown then
    AddSettingsSubheading(container, "Glows")
    -- Two even columns of spell glows, split by what drives them: LEFT the two
    -- the SPELL's own cooldown/proc state raises, RIGHT the two the PLAYER's
    -- input raises (a held keybind, Blizzard's assisted-rotation hint). No
    -- family captions: both columns are the cooldown/spell family now.
    local glowLeft, glowRight = BeginRowGrid(container)

    if CanGroupUseOverrideSection(group, "procGlow") then
        BuildProcGlowSection(glowLeft, group, style, lens)
    end
    if CanGroupUseOverrideSection(group, "readyGlow") then
        BuildReadyGlowSection(glowLeft, group, style, lens)
    end
    if CanGroupUseOverrideSection(group, "keyPressHighlight") then
        BuildKeyPressHighlightSection(glowRight, group, style, lens)
    end

    -- Assisted Highlight is an override section like the three glows above, and
    -- gets its FIRST per-entry affordance here: it never carried a promote
    -- badge, so under the lens the scope chrome is the whole of it (the
    -- appearance tab's Icon Zoom row set the precedent).
    --
    -- Player-driven like the key press highlight above it (Blizzard highlights
    -- the next assisted-rotation cast), so it closes the RIGHT column.
    if CanGroupUseOverrideSection(group, "assistedHighlight") then
    local assistedSec = BeginLensSection(lens, group, "assistedHighlight", { column = glowRight })

    local assistedCb = AddCheckboxRow(glowRight, {
        label = "Show Assisted Highlight",
        setting = EFFECTS_FINDER.icons.spell.assisted,
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
            setting = EFFECTS_FINDER.advanced.assisted and EFFECTS_FINDER.advanced.assisted.combatOnly,
            value = assistedSec.write.assistedHighlightCombatOnly or false,
            onChange = function(val)
                assistedSec.write.assistedHighlightCombatOnly = val
                CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
            end,
        })

        BuildAssistedHighlightControls(panel, assistedSec.write, function()
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end, { row = true, settings = EFFECTS_FINDER.advanced.assisted })
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
    end -- Glows subheading

    -- ---------------------------------------------------------------
    -- Timers
    -- ---------------------------------------------------------------
    -- Spell-side only, now that the aura duration swipe has moved into the Aura
    -- Indicators section below. Same pre-check shape as Glows: on an Aura Panel
    -- the fill timer, the cooldown swipe and the GCD swipe all time a spell
    -- cooldown these entries do not have, so every row is denied and the
    -- subheading is skipped with them. One denial, so the first row's predicate
    -- speaks for the set.
    if spellTimersShown then
    AddSettingsSubheading(container, "Timers")
    -- LEFT column: the two timers that count this spell's OWN cooldown,
    -- adjacent because the fill timer disables the swipe.
    -- RIGHT column: the GCD, the timer every cast shares. No family captions:
    -- both columns are the cooldown/spell family now.
    local timerLeft, timerRight = BeginRowGrid(container)

    -- Each of the three sections below resolves its own scope against the lens.
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
        setting = EFFECTS_FINDER.icons.spell.iconFill,
        settings = EFFECTS_FINDER.advanced.iconFill,
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
            end, {
                row = true,
                indent = false,
                settings = EFFECTS_FINDER.advanced.iconFill,
            })
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
        setting = EFFECTS_FINDER.icons.spell.cooldownSwipe,
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
            swipeSec.scope == "customized" and swipeSec.write or nil,
            EFFECTS_FINDER.advanced.cooldownSwipe)

        AddAdvancedToggle(swipeCb, swipeAdvanced.settingKey, tabInfoButtons,
            swipeSec.read.showCooldownSwipe ~= false and not iconFillTimerActive, {
                title = swipeAdvanced.title,
                build = swipeAdvanced.build,
            })
    end
    swipeSec:Chrome(swipeCb)
    end -- showCooldownTimers

    -- One row, no gear: `disabled` is the whole gate, so no inert bracket is
    -- needed - the chrome that undoes it is attached after. Same shape the bars
    -- Timers section uses for this setting.
    --
    -- The GCD times every cast rather than this spell's own cooldown, so it is
    -- the whole of the RIGHT column beside the two that do.
    if CanGroupUseOverrideSection(group, "showGCDSwipe") then
    local gcdSec = BeginLensSection(lens, group, "showGCDSwipe")
    local gcdCb = AddCheckboxRow(timerRight, {
        label = "Show GCD Swipe",
        setting = EFFECTS_FINDER.icons.spell.gcd,
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
    end -- Timers subheading

    -- ---------------------------------------------------------------
    -- States
    -- ---------------------------------------------------------------
    -- Same pre-check shape Glows and Timers above use, for the same reason: on
    -- an Aura Panel EVERY row this subgroup can hold is denied - desaturate-on-
    -- cooldown, the unusable visual, out-of-range and loss-of-control all read
    -- spell cooldown or castability state these entries do not have - so the
    -- subheading would stand over nothing. They share one denial
    -- (ST.CanGroupUseOverrideSection answers the panel, not the row), so the
    -- first row's predicate speaks for the set.
    if spellStatesShown then
    AddSettingsSubheading(container, "States")
    -- Spell-side only, now that the missing-aura desaturate has moved into the
    -- Aura Indicators section below. Two even columns, split by what the state
    -- is about:
    -- LEFT whether the spell is READY to cast (on cooldown, unusable), RIGHT
    -- whether it can REACH its target (out of range, locked out of control). No
    -- family captions: both columns are the cooldown/spell family now.
    local stateLeft, stateRight = BeginRowGrid(container)

    -- Same per-section resolve the Timers section above states: the write table
    -- is the whole gate, and the scope chrome goes on LAST.
    if CanGroupUseOverrideSection(group, "desaturation") then
    local desatSec = BeginLensSection(lens, group, "desaturation")
    local desatCb = AddCheckboxRow(stateLeft, {
        label = "Desaturate On Cooldown",
        setting = EFFECTS_FINDER.icons.spell.desaturate,
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
        setting = EFFECTS_FINDER.icons.spell.unusable,
        settings = EFFECTS_FINDER.advanced.unusable,
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
    local oorCb = AddCheckboxRow(stateRight, {
        label = "Show Out of Range",
        setting = EFFECTS_FINDER.icons.spell.outOfRange,
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

    -- Loss of Control - inlined for the same reason as Out of Range. A lockout
    -- stops the cast reaching its target the way distance does, so it closes the
    -- RIGHT column after Out of Range.
    if CanGroupUseOverrideSection(group, "lossOfControl") then
    local locSec = BeginLensSection(lens, group, "lossOfControl")
    local locCb = AddCheckboxRow(stateRight, {
        label = "Show Loss of Control",
        setting = EFFECTS_FINDER.icons.spell.lossOfControl,
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
    end -- States subheading

    end -- not spellCollapsed
    end -- Cooldown / Spell Indicators has at least one subgroup

    -- ================================================================
    -- Aura Indicators
    -- ================================================================
    -- The aura family's own section (owner ruling 2026-08-30), the twin of the
    -- Cooldown / Spell Indicators section above. Every aura indicator on this
    -- tab used to hang alone in a spell section's right column - one toggle
    -- beside four - which read as a lopsided column rather than as a family;
    -- collected here they are the family. The refresh window is aura-only too,
    -- so Pandemic is a SUBHEADING at the foot of this section rather than a
    -- standalone collapsible of its own.
    --
    -- Every row here is aura-gated, so the whole section is: an "Aura
    -- Indicators" heading over nothing on a panel that tracks none would be a
    -- promise of nothing. The two toggles below draw on any panel that tracks an
    -- aura (an Aura Panel included), and so does Pandemic, so the group
    -- predicate speaks for the set - the missing-aura row on the right is the
    -- one an Aura Panel denies.
    local auraLeft, auraRight
    if groupHasAuraEntry then
        local _, auraCollapsed = BuildCollapsibleSection(container, "Aura Indicators", EFFECTS_AURA_SECTION, nil, nil, ROW_SECTION)
        if not auraCollapsed then
            -- LEFT the two looks the aura's PRESENCE gives the icon, RIGHT the
            -- look its ABSENCE does.
            auraLeft, auraRight = BeginRowGrid(container)
        end
    end

    -- Nil host on purpose when the group tracks no aura: the section is gone,
    -- and BuildAuraGlowSection's own gate returns early there after clearing a
    -- glow preview a deleted aura entry left running. A COLLAPSED section skips
    -- the call outright, exactly as every other row on this tab does.
    if auraLeft or not groupHasAuraEntry then
        BuildAuraGlowSection(auraLeft, group, style, lens)
    end

    if auraLeft then
    -- Aura duration swipe. The gate stays on the GROUP: an entry that tracks no
    -- aura still sees the row, and the lens resolves it "not available" for that
    -- entry rather than hiding it.
    if GroupHasAuraTrackingEntry(group) then
        local auraSwipeSec = BeginLensSection(lens, group, "auraDurationSwipe", { column = auraLeft })

        local auraDurationCb = BuildAuraDurationSwipeControls(auraLeft, auraSwipeSec.tbl, function()
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end, {
            row = true,
            setting = EFFECTS_FINDER.icons.aura.auraSwipe,
            settings = EFFECTS_FINDER.advanced.auraSwipe,
            showAdvancedControlsInline = false,
            fallbackStyle = auraSwipeSec.fallbackStyle,
        })
        -- Single rail (AdvancedSettingsPanel.lua): row mode, no rightColumn. The
        -- panel captures the section's WRITE table and is only built while there
        -- is one - an inert section has no gear to open it from.
        local function BuildAuraDurationSwipeAdvanced(panel)
            BuildAuraDurationSwipeAdvancedControls(panel, auraSwipeSec.write, function()
                CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
            end, { row = true, settings = EFFECTS_FINDER.advanced.auraSwipe })
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

    -- The missing-aura sibling of Desaturate On Cooldown, as its OWN section
    -- (owner ruling 2026-08-16: riding the desaturation section made it
    -- customizable only through the cooldown toggle's chrome). Static desat on
    -- the CC icon, meaningful only while the group tracks an aura; passives are
    -- not served here - they gray while missing by default, with the entry tab's
    -- Never Desaturate as their off switch - and the section is aura-entry-denied
    -- plus aura-tracking-config-only, so a lens on the wrong kind of entry reads
    -- it denied rather than misleadingly live.
    --
    -- It reads the aura's ABSENCE while the two rows on the left read its
    -- presence, so it is the whole of the RIGHT column.
    if groupHasAuraEntry and CanGroupUseOverrideSection(group, "auraMissingDesaturation") then
    local missingSec = BeginLensSection(lens, group, "auraMissingDesaturation")
    local missingCb = AddCheckboxRow(auraRight, {
        label = "Desaturate While Aura Missing",
        setting = EFFECTS_FINDER.icons.aura.missing,
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
    end -- Aura Indicators section open

    -- ---------------------------------------------------------------
    -- Pandemic
    -- ---------------------------------------------------------------
    -- Both halves are aura-only, like the rows above them, so the refresh
    -- window is a subheading INSIDE Aura Indicators rather than a collapsible
    -- of its own (owner ruling 2026-08-30). Its old "effects_pandemic" key is
    -- retired with it; a subheading owns no collapse state, so the section's
    -- key folds the whole aura family together.
    --
    -- Drawn under exactly the gate that opened the section (an aura-tracking
    -- entry, section expanded), which is the same gate this pair carried as a
    -- standalone header. The effect builder still runs with a nil host so it can
    -- reconcile its preview; the bars twin has carried that contract since PTR 8
    -- and this side needs it for the same reason.
    local pandemicLeft, pandemicRight
    if auraLeft then
        -- ONE scope chrome for the whole feature, on the SUBHEADING (owner
        -- ruling): the glow and the marker are two rows of one override
        -- section, so a per-row affordance would offer the same customize twice
        -- and revert from either would silently take the other with it. Both
        -- halves resolve "pandemic" and flip together, silently.
        --
        -- AddSettingsSubheading returns the same AceGUI Heading a collapsible
        -- builds, in the same left-aligned variant, so the heading chrome chains
        -- onto it exactly as it did onto the retired Pandemic collapsible - the
        -- badge chain and the fading rule are heading anatomy, not collapsible
        -- anatomy. Each half still brackets its own column.
        local pandemicHeading = AddSettingsSubheading(container, "Pandemic")
        BeginLensSection(lens, group, "pandemic"):HeadingChrome(pandemicHeading)
        -- LEFT the glow half, RIGHT the text half.
        pandemicLeft, pandemicRight = BeginRowGrid(container)
    end
    BuildPandemicGlowSection(pandemicLeft, group, style, lens)
    BuildPandemicMarkerSection(pandemicRight, group, style, lens)

    -- ================================================================
    -- Interaction
    -- ================================================================
    -- Show Tooltips and Allow Pings answer "what happens when I put a pointer
    -- on this", not "what does the icon look like right now", so they have
    -- their own section at the foot of the tab rather than trailing the States
    -- rows. Always drawn: Show Tooltips is offered on every icon panel - an
    -- Aura Panel included, where it is the section's only row - so this one
    -- needs no emptiness pre-check.
    local _, interactionCollapsed = BuildCollapsibleSection(container, "Interaction", EFFECTS_INTERACTION_SECTION, nil, nil, ROW_SECTION)

    if not interactionCollapsed then
    -- LEFT column: the hover behavior. RIGHT column: the click behavior, which
    -- an Aura Panel does not offer - and the fill-left-first rule is why the
    -- hover row is on the left rather than beside an empty column.
    local interactionLeft, interactionRight = BeginRowGrid(container)

    -- Show Tooltips (panel refresh: the advanced gear only shows while the
    -- toggle is on). Its gear is the builder's own, so it is bracketed rather
    -- than skipped - see the Unusable Visual note in States above.
    local tooltipSec = BeginLensSection(lens, group, "showTooltips", { column = interactionLeft })
    local tooltipCb = BuildShowTooltipsControls(interactionLeft, tooltipSec.tbl, function()
        CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        CooldownCompanion:RefreshConfigPanel()
    end, {
        row = true,
        advanced = true,
        setting = EFFECTS_FINDER.icons.interaction.tooltips,
        settings = EFFECTS_FINDER.advanced.tooltip,
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
    local pingsSec = BeginLensSection(lens, group, nil, { column = interactionRight })
    BuildAllowPingsControls(interactionRight, style, function()
        CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
    end, { row = true, setting = EFFECTS_FINDER.icons.interaction.pings })
    pingsSec:Finish()
    end
    end -- not interactionCollapsed

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

------------------------------------------------------------------------
-- SETTINGS FINDER CATALOG
------------------------------------------------------------------------

local EFFECTS_FINDER_SCOPE = { "panel", "entry" }

local function EffectsFinderIcons(context)
    return context and context.group and context.displayMode == "icons"
end

local function EffectsFinderAssistant(context)
    return context and context.group
        and context.displayMode == ST.DISPLAY_MODE_ROTATION_ASSISTANT
end

local function EffectsFinderTracksAura(context)
    return context and context.group and GroupHasAuraTrackingEntry(context.group)
end

local function EffectsFinderCanUse(context, sectionId)
    return context and context.group
        and CanGroupUseOverrideSection(context.group, sectionId)
end

local function EffectsFinderSectionState(context, sectionId)
    local group = context and context.group
    if not group then return nil, nil, nil end
    local lens = ST._ResolveStyleLens(group)
    return ResolveLensSection(lens, group, sectionId)
end

local function EffectsFinderEffectiveStyle(context)
    local group = context and context.group
    if not group then return nil end
    local lens = ST._ResolveStyleLens(group)
    return (lens and lens.effective) or group.style
end

local function EffectsFinderIconsRow(sectionId, needsAura)
    return function(context)
        return EffectsFinderIcons(context)
            and (not needsAura or EffectsFinderTracksAura(context))
            and (not sectionId or EffectsFinderCanUse(context, sectionId))
    end
end

local function EffectsFinderIconsAdvanced(sectionId, enabled, needsAura)
    return function(context)
        if not EffectsFinderIcons(context)
            or (needsAura and not EffectsFinderTracksAura(context))
            or (sectionId and not EffectsFinderCanUse(context, sectionId))
        then
            return false
        end
        local _, read, write = EffectsFinderSectionState(context, sectionId)
        return write ~= nil and (not enabled or enabled(read or {}, context))
    end
end

local function EffectsFinderNormalizeGlowStyle(style, fallback)
    style = style or fallback
    if style == "lcgProc" or style == "lcgButton" then
        return "glow"
    elseif style == "lcgAutoCast" then
        return "autocast"
    elseif style == "pulsingBorder" then
        return "pulse"
    end
    return style
end

local function EffectsFinderGlowStyleApplies(sectionId, styleKey, fallback, allowed)
    return function(context)
        local _, read = EffectsFinderSectionState(context, sectionId)
        local style = EffectsFinderNormalizeGlowStyle(read and read[styleKey], fallback)
        return allowed[style] == true
    end
end

local function EffectsFinderDefineGlowSettings(route, options)
    local sectionId = options.sectionId
    local styleKey = options.styleKey
    local fallback = options.fallback
    local supported = options.supported
    local function Uses(...)
        local allowed = {}
        for index = 1, select("#", ...) do
            allowed[select(index, ...)] = true
        end
        return EffectsFinderGlowStyleApplies(sectionId, styleKey, fallback, allowed)
    end

    local result = {
        style = route:Setting({ key = "style", label = "Glow Style" }),
        color = route:Setting({
            key = "color", label = options.colorLabel,
            applies = options.noColorStyle and function(context)
                local _, read = EffectsFinderSectionState(context, sectionId)
                return EffectsFinderNormalizeGlowStyle(read and read[styleKey], fallback)
                    ~= options.noColorStyle
            end or nil,
        }),
    }
    if options.color2 then
        result.color2 = route:Setting({ key = "color2", label = "Second Color", applies = Uses("colorShift") })
    end
    if supported.solid or supported.pulse or supported.colorShift then
        result.borderSize = route:Setting({
            key = "borderSize", label = "Border Size", applies = Uses("solid", "pulse", "colorShift"),
        })
    end
    if supported.pulse then
        result.pulseDuration = route:Setting({ key = "pulseDuration", label = "Pulse Duration", applies = Uses("pulse") })
    end
    if supported.pixel then
        result.lineLength = route:Setting({ key = "lineLength", label = "Line Length", applies = Uses("pixel") })
        result.lineThickness = route:Setting({ key = "lineThickness", label = "Line Thickness", applies = Uses("pixel") })
        result.speed = route:Setting({ key = "speed", label = "Speed", applies = Uses("pixel") })
        result.lineCount = route:Setting({ key = "lineCount", label = "Number of Lines", applies = Uses("pixel") })
    end
    if supported.glow or supported.ants or supported.proc then
        result.glowSize = route:Setting({ key = "glowSize", label = "Glow Size", applies = Uses("glow", "ants", "proc") })
    end
    if supported.colorShift then
        result.shiftDuration = route:Setting({ key = "shiftDuration", label = "Shift Duration", applies = Uses("colorShift") })
    end
    if supported.dashes then
        result.dashLength = route:Setting({ key = "dashLength", label = "Dash Length", applies = Uses("dashes") })
        result.dashThickness = route:Setting({ key = "dashThickness", label = "Dash Thickness", applies = Uses("dashes") })
        result.dashCount = route:Setting({ key = "dashCount", label = "Number of Dashes", applies = Uses("dashes") })
        result.lapDuration = route:Setting({ key = "lapDuration", label = "Lap Duration", applies = Uses("dashes") })
    end
    if supported.autocast then
        result.particleScale = route:Setting({ key = "particleScale", label = "Particle Scale", applies = Uses("autocast") })
        result.frequency = route:Setting({ key = "frequency", label = "Frequency", applies = Uses("autocast") })
    end
    return result
end

local EFFECTS_FINDER_ADVANCED_SECTION_LABELS = {
    procGlow = "Proc Glow",
    readyGlow = "Ready Glow",
    keyPressHighlight = "Key Press Highlight",
    auraGlow = "Aura Glow",
    pandemicGlow = "Pandemic Effect",
    assistedHighlight = "Assisted Highlight",
    iconFillTimer = "Icon Fill Timer",
    cooldownSwipe = "Cooldown Swipe",
    auraDurationSwipe = "Aura Duration Swipe",
    unusableVisual = "Unusable Visual",
    pandemicMarker = "Pandemic Marker",
    tooltipBehavior = "Tooltips",
}

local function EffectsFinderRoute(prefix, section, sectionLabel, applies, advancedKey, sectionId)
    return ST._DefineSettingRoute({
        idPrefix = prefix,
        scope = EFFECTS_FINDER_SCOPE,
        tab = "effects",
        tabLabel = "Indicators",
        section = section,
        sectionId = sectionId,
        sectionLabel = EFFECTS_FINDER_ADVANCED_SECTION_LABELS[advancedKey]
            or sectionLabel,
        collapseKeys = { section },
        rowScope = "primary",
        advancedKey = advancedKey,
        applies = applies,
    })
end

if ST._DefineSettingRoute then
    local spell = EffectsFinderRoute(
        "panel.icons.effects.spell", EFFECTS_SPELL_SECTION,
        "Cooldown / Spell Indicators", EffectsFinderIcons)
    EFFECTS_FINDER.icons.spell = spell:Settings({
        proc = { label = "Show Proc Glow", applies = EffectsFinderIconsRow("procGlow") },
        ready = { label = "Show Ready Glow", applies = EffectsFinderIconsRow("readyGlow") },
        keyPress = { label = "Show Key Press Highlight", applies = EffectsFinderIconsRow("keyPressHighlight") },
        assisted = { label = "Show Assisted Highlight", applies = EffectsFinderIconsRow("assistedHighlight") },
        iconFill = { label = "Icon Fill Timer", applies = EffectsFinderIconsRow("iconFillTimer") },
        cooldownSwipe = { label = "Show Cooldown Swipe", applies = EffectsFinderIconsRow("cooldownSwipe") },
        gcd = { label = "Show GCD Swipe", applies = EffectsFinderIconsRow("showGCDSwipe") },
        desaturate = { label = "Desaturate On Cooldown", applies = EffectsFinderIconsRow("desaturation") },
        unusable = { label = "Show Unusable Visual", applies = EffectsFinderIconsRow("unusableDimming") },
        outOfRange = { label = "Show Out of Range", applies = EffectsFinderIconsRow("showOutOfRange") },
        lossOfControl = { label = "Show Loss of Control", applies = EffectsFinderIconsRow("lossOfControl") },
    })

    local aura = EffectsFinderRoute(
        "panel.icons.effects.aura", EFFECTS_AURA_SECTION,
        "Aura Indicators", function(context)
            return EffectsFinderIcons(context) and EffectsFinderTracksAura(context)
        end)
    EFFECTS_FINDER.icons.aura = aura:Settings({
        auraGlow = { label = "Show Aura Glow" },
        auraSwipe = { label = "Show Aura Duration Swipe" },
        missing = { label = "Desaturate While Aura Missing", applies = EffectsFinderIconsRow("auraMissingDesaturation", true) },
        pandemicEffect = { label = "Show Pandemic Effect" },
        pandemicMarker = {
            label = "Pandemic Marker",
            applies = function(context)
                local style = EffectsFinderEffectiveStyle(context)
                return style and style.showAuraText ~= false
            end,
        },
    })

    local interaction = EffectsFinderRoute(
        "panel.icons.effects.interaction", EFFECTS_INTERACTION_SECTION,
        "Interaction", EffectsFinderIcons)
    EFFECTS_FINDER.icons.interaction = interaction:Settings({
        tooltips = { label = "Show Tooltips" },
        pings = {
            label = "Allow Pings",
            applies = function(context)
                return context and context.group
                    and not CooldownCompanion:IsAuraPanel(context.group)
            end,
        },
    })

    local assistantSpell = EffectsFinderRoute(
        "panel.assistant.effects.spell", EFFECTS_SPELL_SECTION,
        "Cooldown / Spell Indicators", EffectsFinderAssistant)
    EFFECTS_FINDER.assistant.spell = assistantSpell:Settings({
        gcd = { label = "Show GCD Swipe" },
        desaturate = { label = "Desaturate On Cooldown" },
        unusable = { label = "Show Unusable Visual" },
        outOfRange = { label = "Show Out of Range" },
        lossOfControl = { label = "Show Loss of Control" },
    })
    EFFECTS_FINDER.assistant.cooldownSwipe = assistantSpell:Settings({
        enabled = { label = "Show Cooldown Swipe" },
        reverse = { label = "Reverse Swipe" },
        fill = { label = "Show Swipe Fill" },
        fillOpacity = {
            label = "Swipe Fill Opacity",
            applies = function(context)
                local style = context and context.group and context.group.style
                return style and style.showCooldownSwipeFill ~= false
            end,
        },
        edge = { label = "Show Swipe Edge" },
        edgeColor = {
            label = "Swipe Edge Color",
            applies = function(context)
                local style = context and context.group and context.group.style
                return style and style.cooldownSwipeEdgeEnabled == true
            end,
        },
    })

    local assistantInteraction = EffectsFinderRoute(
        "panel.assistant.effects.interaction", EFFECTS_INTERACTION_SECTION,
        "Interaction", EffectsFinderAssistant)
    EFFECTS_FINDER.assistant.interaction = assistantInteraction:Settings({
        tooltips = { label = "Show Tooltips" },
        pings = { label = "Allow Pings" },
    })

    local function DefineGlowAdvanced(prefix, sectionId, advancedKey, enabled, needsAura, options)
        local route = EffectsFinderRoute(prefix, needsAura and EFFECTS_AURA_SECTION or EFFECTS_SPELL_SECTION,
            needsAura and "Aura Indicators" or "Cooldown / Spell Indicators",
            EffectsFinderIconsAdvanced(sectionId, enabled, needsAura), advancedKey, sectionId)
        options.sectionId = sectionId
        return EffectsFinderDefineGlowSettings(route, options), route
    end

    local proc, procRoute = DefineGlowAdvanced(
        "panel.icons.effects.proc", "procGlow", "procGlow",
        function(read) return read.procGlowStyle ~= "none" end, false, {
            styleKey = "procGlowStyle", fallback = "glow", colorLabel = "Glow Color",
            supported = { solid = true, pixel = true, glow = true, autocast = true },
        })
    proc.combatOnly = procRoute:Setting({ key = "combatOnly", label = "Show Only In Combat" })
    EFFECTS_FINDER.advanced.proc = proc

    local ready, readyRoute = DefineGlowAdvanced(
        "panel.icons.effects.ready", "readyGlow", "readyGlow",
        function(read) return read.readyGlowStyle and read.readyGlowStyle ~= "none" end, false, {
            styleKey = "readyGlowStyle", fallback = "solid", colorLabel = "Glow Color",
            supported = { solid = true, pixel = true, glow = true, autocast = true },
        })
    ready.combatOnly = readyRoute:Setting({ key = "combatOnly", label = "Show Only In Combat" })
    ready.cappedCharges = readyRoute:Setting({ key = "cappedCharges", label = "Glow When Charges Are Capped" })
    ready.autoHide = readyRoute:Setting({ key = "autoHide", label = "Auto-Hide After Duration" })
    ready.duration = readyRoute:Setting({
        key = "duration", label = "Duration (seconds)",
        applies = function(context)
            local _, read = EffectsFinderSectionState(context, "readyGlow")
            return read and (read.readyGlowDuration or 0) > 0
        end,
    })
    EFFECTS_FINDER.advanced.ready = ready

    local keyPress, keyPressRoute = DefineGlowAdvanced(
        "panel.icons.effects.keyPress", "keyPressHighlight", "keyPressHighlight",
        function(read) return read.keyPressHighlightStyle and read.keyPressHighlightStyle ~= "none" end, false, {
            styleKey = "keyPressHighlightStyle", fallback = "solid", colorLabel = "Highlight Color",
            supported = { solid = true, overlay = true },
        })
    keyPress.combatOnly = keyPressRoute:Setting({ key = "combatOnly", label = "Show Only In Combat" })
    EFFECTS_FINDER.advanced.keyPress = keyPress

    local auraGlow = DefineGlowAdvanced(
        "panel.icons.effects.auraGlow", "auraIndicator", "auraGlow",
        function(read) return (read.auraGlowStyle or "pulse") ~= "none" end, true, {
            styleKey = "auraGlowStyle", fallback = "pulse", colorLabel = "Glow Color", color2 = true,
            supported = {
                solid = true, pulse = true, colorShift = true, dashes = true,
                ants = true, proc = true, overlay = true,
            },
        })
    EFFECTS_FINDER.advanced.auraGlow = auraGlow

    local pandemicGlow = DefineGlowAdvanced(
        "panel.icons.effects.pandemicGlow", "pandemic", "pandemicGlow",
        function(read) return read.pandemicEffectEnabled == true end, true, {
            styleKey = "pandemicGlowStyle", fallback = "solid", colorLabel = "Effect Color",
            color2 = true, noColorStyle = "cdm",
            supported = {
                solid = true, pulse = true, colorShift = true, dashes = true,
                ants = true, proc = true, overlay = true, cdm = true,
            },
        })
    EFFECTS_FINDER.advanced.pandemicGlow = pandemicGlow

    local assistedRoute = EffectsFinderRoute(
        "panel.icons.effects.assisted", EFFECTS_SPELL_SECTION,
        "Cooldown / Spell Indicators",
        EffectsFinderIconsAdvanced("assistedHighlight", function(read)
            return read.showAssistedHighlight == true
        end), "assistedHighlight", "assistedHighlight")
    EFFECTS_FINDER.advanced.assisted = assistedRoute:Settings({
        combatOnly = { label = "Show Only In Combat" },
        hostileOnly = { label = "Hostile Target Only" },
        style = { label = "Highlight Style" },
        solidColor = {
            label = "Highlight Color",
            applies = function(context)
                local _, read = EffectsFinderSectionState(context, "assistedHighlight")
                return read and read.assistedHighlightStyle == "solid"
            end,
        },
        solidBorderSize = {
            label = "Border Size",
            applies = function(context)
                local _, read = EffectsFinderSectionState(context, "assistedHighlight")
                return read and read.assistedHighlightStyle == "solid"
            end,
        },
        blizzardGlowSize = {
            label = "Glow Size",
            applies = function(context)
                local _, read = EffectsFinderSectionState(context, "assistedHighlight")
                return not read or (read.assistedHighlightStyle or "blizzard") == "blizzard"
            end,
        },
        procColor = {
            label = "Glow Color",
            applies = function(context)
                local _, read = EffectsFinderSectionState(context, "assistedHighlight")
                return read and read.assistedHighlightStyle == "proc"
            end,
        },
        procGlowSize = {
            label = "Glow Size",
            applies = function(context)
                local _, read = EffectsFinderSectionState(context, "assistedHighlight")
                return read and read.assistedHighlightStyle == "proc"
            end,
        },
    })

    local iconFillRoute = EffectsFinderRoute(
        "panel.icons.effects.iconFill", EFFECTS_SPELL_SECTION,
        "Cooldown / Spell Indicators",
        EffectsFinderIconsAdvanced("iconFillTimer", function(read, context)
            return read.iconFillEnabled == true and context.group.masqueEnabled ~= true
        end), "iconFillTimer", "iconFillTimer")
    EFFECTS_FINDER.advanced.iconFill = iconFillRoute:Settings({
        orientation = { label = "Orientation" },
        anchorEdge = { label = "Anchor Edge" },
        motion = { label = "Timer Motion" },
        color = { label = "Cooldown Fill Color" },
    })

    local function CooldownSwipeAdvancedApplies(context)
        if not EffectsFinderIcons(context) or not EffectsFinderCanUse(context, "cooldownSwipe") then
            return false
        end
        local _, read, write = EffectsFinderSectionState(context, "cooldownSwipe")
        local fillStyle = EffectsFinderEffectiveStyle(context) or {}
        local fillActive = fillStyle.iconFillEnabled == true and context.group.masqueEnabled ~= true
        return write ~= nil and read and read.showCooldownSwipe ~= false and not fillActive
    end
    local cooldownSwipeRoute = EffectsFinderRoute(
        "panel.icons.effects.cooldownSwipe", EFFECTS_SPELL_SECTION,
        "Cooldown / Spell Indicators", CooldownSwipeAdvancedApplies,
        "cooldownSwipe", "cooldownSwipe")
    EFFECTS_FINDER.advanced.cooldownSwipe = cooldownSwipeRoute:Settings({
        reverse = { label = "Reverse Swipe" },
        fill = { label = "Show Swipe Fill" },
        fillOpacity = {
            label = "Swipe Fill Opacity",
            applies = function(context)
                local _, read = EffectsFinderSectionState(context, "cooldownSwipe")
                return read and read.showCooldownSwipeFill ~= false
            end,
        },
        edge = { label = "Show Swipe Edge" },
        edgeColor = {
            label = "Swipe Edge Color",
            applies = function(context)
                local _, read = EffectsFinderSectionState(context, "cooldownSwipe")
                return read and read.cooldownSwipeEdgeEnabled == true
            end,
        },
    })

    local auraSwipeRoute = EffectsFinderRoute(
        "panel.icons.effects.auraSwipe", EFFECTS_AURA_SECTION,
        "Aura Indicators",
        EffectsFinderIconsAdvanced("auraDurationSwipe", function(read)
            return read.showAuraDurationSwipe ~= false
        end, true), "auraDurationSwipe", "auraDurationSwipe")
    EFFECTS_FINDER.advanced.auraSwipe = auraSwipeRoute:Settings({
        blizzard = { label = "Blizzard Style Aura Swipe" },
        reverse = { label = "Reverse Swipe" },
        fill = { label = "Show Swipe Fill" },
        fillOpacity = {
            label = "Swipe Fill Opacity",
            applies = function(context)
                local _, read = EffectsFinderSectionState(context, "auraDurationSwipe")
                return read and read.showAuraDurationSwipeFill ~= false
            end,
        },
        edge = { label = "Show Swipe Edge" },
        edgeColor = {
            label = "Swipe Edge Color",
            applies = function(context)
                local _, read = EffectsFinderSectionState(context, "auraDurationSwipe")
                return read and read.auraDurationSwipeEdgeEnabled == true
            end,
        },
    })

    local unusableRoute = EffectsFinderRoute(
        "panel.icons.effects.unusable", EFFECTS_SPELL_SECTION,
        "Cooldown / Spell Indicators",
        EffectsFinderIconsAdvanced("unusableDimming", function(read)
            return read.showUnusable == true
        end), "unusableVisual", "unusableDimming")
    EFFECTS_FINDER.advanced.unusable = unusableRoute:Settings({
        dim = { label = "Dim Icon" },
        dimColor = {
            label = "Unusable Dim Color",
            applies = function(context)
                local _, read = EffectsFinderSectionState(context, "unusableDimming")
                return read and ST.UnusableVisualUsesDimTint(read)
            end,
        },
        desaturate = { label = "Desaturate Icon" },
    })

    local markerRoute = EffectsFinderRoute(
        "panel.icons.effects.pandemicMarker", EFFECTS_AURA_SECTION,
        "Aura Indicators",
        EffectsFinderIconsAdvanced("pandemic", function(read)
            return read.pandemicMarkerMode ~= "off" and read.showAuraText ~= false
        end, true), "pandemicMarker", "pandemic")
    EFFECTS_FINDER.advanced.pandemicMarker = markerRoute:Settings({
        text = { label = "Marker Text" },
        coloring = { label = "Marker Coloring" },
        color = {
            label = "Marker Color",
            applies = function(context)
                local _, read = EffectsFinderSectionState(context, "pandemic")
                return read and (read.pandemicMarkerColorMode or "marker") ~= "off"
            end,
        },
    })

    local tooltipRoute = EffectsFinderRoute(
        "panel.icons.effects.tooltip", EFFECTS_INTERACTION_SECTION,
        "Interaction",
        EffectsFinderIconsAdvanced("showTooltips", function(read)
            return read.showTooltips == true
        end), "tooltipBehavior", "showTooltips")
    EFFECTS_FINDER.advanced.tooltip = tooltipRoute:Settings({
        position = { label = "Tooltip Position" },
        hideInCombat = { label = "Hide Tooltips in Combat" },
    })

    local assistantUnusable = EffectsFinderRoute(
        "panel.assistant.effects.unusable", EFFECTS_SPELL_SECTION,
        "Cooldown / Spell Indicators", function(context)
            local style = context and context.group and context.group.style
            return EffectsFinderAssistant(context) and style and style.showUnusable == true
        end, "unusableVisual")
    EFFECTS_FINDER.assistant.unusableAdvanced = assistantUnusable:Settings({
        dim = { label = "Dim Icon" },
        dimColor = {
            label = "Unusable Dim Color",
            applies = function(context)
                local style = context and context.group and context.group.style
                return style and ST.UnusableVisualUsesDimTint(style)
            end,
        },
        desaturate = { label = "Desaturate Icon" },
    })

    local assistantTooltip = EffectsFinderRoute(
        "panel.assistant.effects.tooltip", EFFECTS_INTERACTION_SECTION,
        "Interaction", function(context)
            local style = context and context.group and context.group.style
            return EffectsFinderAssistant(context) and style and style.showTooltips == true
        end, "tooltipBehavior")
    EFFECTS_FINDER.assistant.tooltipAdvanced = assistantTooltip:Settings({
        position = { label = "Tooltip Position" },
        hideInCombat = { label = "Hide Tooltips in Combat" },
    })
end

ST._BuildEffectsTab = BuildEffectsTab
ST._EFFECTS_SPELL_SECTION = EFFECTS_SPELL_SECTION
ST._EFFECTS_AURA_SECTION = EFFECTS_AURA_SECTION
ST._EFFECTS_INTERACTION_SECTION = EFFECTS_INTERACTION_SECTION
