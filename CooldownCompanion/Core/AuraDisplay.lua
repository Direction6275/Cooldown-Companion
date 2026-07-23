--[[
    CooldownCompanion - Core/AuraDisplay.lua: 12.1 AuraContainer-based aura
    display (rebuild Phase 1+).

    THE SINGLE-WRITER RULE: this file is the ONLY code in the addon allowed to
    hold or touch aura slot buttons or the regions created under them. Once
    auras are secret (combat), the entire slot subtree is FORBIDDEN to addon
    code — reads and writes both error, an error freezes the display, and
    IsForbidden() does NOT report the state. Safety is structural, not checked:
      * All slot work happens in the OOC rebind pass (RequestAuraRebind).
      * Slot buttons live under button.auraLayer (_ccNoTouch = true); frame
        sweeps never recurse into flagged frames.
      * In combat the only permitted aura-system calls are container-level
        (UpdateAllAuras, SetAuraSlotCandidateFilters).
    Evidence: docs/12.1-aura-tracking-research.md; validation matrix V1-V18 and
    Phase 0 probes P1-P11.
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon

local ipairs = ipairs
local pairs = pairs
local InCombatLockdown = InCombatLockdown
local UnitExists = UnitExists
local UnitAffectingCombat = UnitAffectingCombat
local CreateFrame = CreateFrame

-- Parking (P1b/P1c): slots can never be removed; unbound slots get a sentinel
-- filter + a hidden parent. Empty includeSpellIDs is BANNED — it wedges the
-- slot permanently. Sentinels are POLARITY-CROSSED so they are structurally
-- never-match: a HELPFUL slot parked on a debuff spellID (debuffs can never
-- appear in HELPFUL results) and a HARMFUL slot parked on a buff spellID.
local PARK_SENTINEL = {
    player = 155722, -- Rake (a bleed debuff; never matches a HELPFUL filter)
    target = 5217,   -- Tiger's Fury (a self buff; never matches a HARMFUL filter)
}

local UNIT_FILTER = { player = "HELPFUL", target = "HARMFUL" }

-- Module state. Slot records deliberately live only here — no slot-button
-- references are ever stored on CC buttons, so no sweep or diagnostic walk
-- can reach the forbidden subtree by accident.
local holder, park
local containers = {}     -- unit -> AuraContainer
local slots = { player = {}, target = {} } -- unit -> array of slot records
local slotCounter = 0
local pendingRebind = false
local rebindQueued = false

-- Deferred-rebind retry events: PLAYER_REGEN_ENABLED for player combat, and
-- target-scoped UNIT_FLAGS for the case where ONLY target combat blocks (an
-- OOC player never gets a regen event, so the target's own combat-flag change
-- must wake the retry). The handler re-checks the gate, so extra fires are
-- harmless; PLAYER_TARGET_CHANGED retries live on the target watcher.
local rebindDeferFrame = CreateFrame("Frame")

local function ArmRebindRetry()
    pendingRebind = true
    rebindDeferFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    rebindDeferFrame:RegisterUnitEvent("UNIT_FLAGS", "target")
end

local function DisarmRebindRetry()
    rebindDeferFrame:UnregisterEvent("PLAYER_REGEN_ENABLED")
    rebindDeferFrame:UnregisterEvent("UNIT_FLAGS")
end

------------------------------------------------------------------------
-- Containers
------------------------------------------------------------------------

local targetWatcher
local RunAuraRebind

local function CanRunRebindNow()
    if InCombatLockdown() then return false end
    -- P11 (conservative): secrecy follows the unit's state, so target slots
    -- are only touchable while the target is also out of combat.
    local hasTargetSlots = #slots.target > 0
    if hasTargetSlots and UnitExists("target") and UnitAffectingCombat("target") then
        return false
    end
    return true
end

local function EnsureTargetWatcher()
    if targetWatcher then return end
    targetWatcher = CreateFrame("Frame")
    targetWatcher:RegisterEvent("PLAYER_TARGET_CHANGED")
    targetWatcher:SetScript("OnEvent", function()
        -- Container-level call: combat-safe (V13, re-validated V18). Without
        -- it the target container never re-parses on same-token target swaps.
        local container = containers.target
        if container then
            container:UpdateAllAuras()
        end
        -- A deferred rebind may have been blocked only by target combat.
        if pendingRebind and CanRunRebindNow() then
            pendingRebind = false
            DisarmRebindRetry()
            RunAuraRebind()
        end
    end)
end

local function EnsureContainer(unit)
    local container = containers[unit]
    if container then return container end
    if not holder then
        -- P1a: the holder must stay SHOWN — a hidden parent makes the
        -- container unregister UNIT_AURA (AuraContainerPrivateMixin:
        -- ShouldRegisterForDynamicEvents requires IsVisible()). It is 2px in
        -- the corner and owns no textures; nothing ever renders from it
        -- because slot buttons are reparented out into CC buttons.
        holder = CreateFrame("Frame", nil, UIParent)
        holder:SetSize(2, 2)
        holder:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 2, 2)
        -- The park frame IS hidden: parked slot buttons must never render,
        -- and slot visibility does not affect the container's registration.
        park = CreateFrame("Frame", nil, UIParent)
        park:SetSize(2, 2)
        park:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 2, 2)
        park:Hide()
    end
    -- Direct call, no pcall: the TOC pins this client generation, so the
    -- AuraContainer API always exists — a failure here is a real setup error
    -- that must surface, not read as "feature unavailable".
    local created = CreateFrame("AuraContainer", nil, holder, "CustomAuraContainerTemplate")
    created:SetUnit(unit)
    containers[unit] = created
    if unit == "target" then
        EnsureTargetWatcher()
    end
    return created
end

------------------------------------------------------------------------
-- Slot kit — built ONCE per slot, inside initializeFrame (the sanctioned
-- setup window). Regions cover every configuration because slots are reused
-- across entries; per-entry enable/disable is alpha at bind time (P6).
------------------------------------------------------------------------

local function BuildSlotKit(slotButton)
    local kit = {}

    -- Shell composition (show-only-while-active entries): background and
    -- border replicas let the slot render the ENTIRE visible button while the
    -- CC frame underneath is an invisible layout shell. They deliberately
    -- overhang the slot (which covers only the icon rect); geometry is
    -- anchored to the host button at bind time and they stay alpha-0 for
    -- ordinary entries.
    kit.bg = slotButton:CreateTexture(nil, "BACKGROUND")
    kit.bg:SetAlpha(0)
    kit.border = {}
    for i = 1, 4 do
        local tex = slotButton:CreateTexture(nil, "OVERLAY")
        tex:SetAlpha(0)
        kit.border[i] = tex
    end

    -- Static occluder (two-layer compositing): while the aura runs, this
    -- covers the CC button's own icon + cooldown swipe, so the aura display
    -- REPLACES the cooldown display instead of stacking on it. CC-authored,
    -- never registered with the button.
    kit.iconCover = slotButton:CreateTexture(nil, "ARTWORK", nil, 1)
    kit.iconCover:SetAllPoints(slotButton)
    kit.iconCover:SetAlpha(0)

    kit.auraIcon = slotButton:CreateTexture(nil, "ARTWORK", nil, 2)
    kit.auraIcon:SetAllPoints(slotButton)
    slotButton:SetIcon(kit.auraIcon)

    kit.swipe = CreateFrame("Cooldown", nil, slotButton, "CooldownFrameTemplate")
    kit.swipe:SetAllPoints(slotButton)
    kit.swipe:SetHideCountdownNumbers(true)
    kit.swipe:SetDrawBling(false)
    slotButton:SetDurationCooldown(kit.swipe)

    -- Bar-mode composition. On bar hosts the slot covers the bar rect: an
    -- opaque backdrop occludes the CC fill and per-tick bar texts underneath
    -- (the iconCover analog), and Blizzard drains the registered StatusBar
    -- while the aura runs (V8b: keeps animating in combat). Alpha-0 until a
    -- bar bind.
    kit.barBackdrop = slotButton:CreateTexture(nil, "BACKGROUND", nil, 2)
    kit.barBackdrop:SetAllPoints(slotButton)
    kit.barBackdrop:SetAlpha(0)
    if slotButton.SetDurationBar then
        kit.barFill = CreateFrame("StatusBar", nil, slotButton)
        kit.barFill:SetAllPoints(slotButton)
        kit.barFill:EnableMouse(false)
        kit.barFill:SetAlpha(0)
        slotButton:SetDurationBar(kit.barFill, {
            interpolation = ST.STATUS_BAR_INTERPOLATION_SMOOTH,
            direction = ST.STATUS_BAR_TIMER_DIRECTION_REMAINING,
        })

        -- Fill effects for the bar aura indicator: alpha pulse on the fill
        -- frame, color shift on the fill texture. Write-once AnimationGroups
        -- (forbidden-subtree rule), configured at bar bind time. The texture
        -- region is materialized here so the VertexColor anim has its target;
        -- later SetStatusBarTexture calls swap the file on the same region.
        kit.barFillPulseAG = kit.barFill:CreateAnimationGroup()
        kit.barFillPulseAG:SetLooping("BOUNCE")
        kit.barFillPulseAnim = kit.barFillPulseAG:CreateAnimation("Alpha")
        kit.barFillPulseAnim:SetFromAlpha(1.0)
        kit.barFillPulseAnim:SetToAlpha(0.3)
        kit.barFill:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
        local fillTex = kit.barFill:GetStatusBarTexture()
        kit.barFillCsAG = fillTex:CreateAnimationGroup()
        kit.barFillCsAG:SetLooping("BOUNCE")
        kit.barFillCsAnim = kit.barFillCsAG:CreateAnimation("VertexColor")
    end

    -- Bar shell composition (show-only-while-active bar entries): the bar's
    -- icon square carries its own background and border ring, so the kit
    -- needs a second replica set beside kit.bg/kit.border.
    kit.iconBg = slotButton:CreateTexture(nil, "BACKGROUND", nil, 1)
    kit.iconBg:SetAlpha(0)
    kit.iconBorder = {}
    for i = 1, 4 do
        local tex = slotButton:CreateTexture(nil, "OVERLAY")
        tex:SetAlpha(0)
        kit.iconBorder[i] = tex
    end

    -- Aura active glow: shares the slot's Blizzard-driven visibility, so it
    -- glows exactly while the aura runs. Animated styles are AnimationGroup-
    -- driven (P3: they keep playing on the forbidden subtree in combat).
    -- Above the swipe, below the texts.
    kit.glow = ST._BuildKitGlowRegions(slotButton)
    kit.glow.host:SetFrameLevel(kit.swipe:GetFrameLevel() + 1)

    kit.textOverlay = CreateFrame("Frame", nil, slotButton)
    kit.textOverlay:SetAllPoints(slotButton)
    kit.textOverlay:SetFrameLevel(kit.swipe:GetFrameLevel() + 2)

    -- Default formatter ONLY: custom formatters/curves error on secret values
    -- mid-refresh and freeze the button (V14/V15 — banned until Blizzard fixes).
    kit.durationText = kit.textOverlay:CreateFontString(nil, "OVERLAY", "GameFontHighlightOutline")
    kit.durationText:SetPoint("BOTTOM", slotButton, "BOTTOM", 0, 1)
    slotButton:SetDurationText(kit.durationText)

    kit.stackText = kit.textOverlay:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmallOutline")
    kit.stackText:SetPoint("TOPRIGHT", slotButton, "TOPRIGHT", -1, -1)
    slotButton:SetApplicationCount(kit.stackText)

    -- Bar name replica: the bar backdrop occludes the CC name text along with
    -- everything else on the bar, so the kit re-renders the entry name.
    -- CC-authored, bind-time text (live aura names via SetSpellName are an
    -- unvalidated future option). The template is a base font only: SetText
    -- errors on a FontString with no font, and icon-host binds clear the text
    -- before ApplyFontStyle ever runs (bar binds restyle it).
    kit.barNameText = kit.textOverlay:CreateFontString(nil, "OVERLAY", "GameFontHighlightOutline")
    kit.barNameText:SetAlpha(0)

    -- Keybind replica (icon shells): show-only-while-active entries hide CC's
    -- overlayFrame — and CC can't re-show it with aura state (secret in
    -- combat) — so the kit re-renders the keybind text while the aura display
    -- is the whole visible button. Base font template only; styled at bind.
    kit.keybindText = kit.textOverlay:CreateFontString(nil, "OVERLAY", "GameFontHighlightOutline")
    kit.keybindText:SetAlpha(0)

    return kit
end

-- Position contract for the aura duration text: it shares the Cooldown Text
-- position unless separateTextPositions switches it to the aura keys. Shared
-- with the config preview, which renders a CC-side stand-in FontString from
-- the same keys (the preview never touches the aura slot subtree).
function CooldownCompanion:GetAuraDurationTextPlacement(style)
    style = style or {}
    if style.separateTextPositions == true then
        return style.auraTextAnchor or "TOPLEFT", style.auraTextXOffset or 2, style.auraTextYOffset or -2
    end
    return style.cooldownTextAnchor or "CENTER", style.cooldownTextXOffset or 0, style.cooldownTextYOffset or 0
end

-- Blizzard-style aura swipe preset (pre-12.1 parity): the bright highlight
-- overlay Blizzard draws for tracked auras, rendered in aura display time.
local BLIZZARD_AURA_SWIPE_TEXTURE = "Interface\\HUD\\UI-HUD-CoolDownManager-Icon-Swipe"
local BLIZZARD_AURA_SWIPE_TEX_LOW = { x = 0.15, y = 0.15 }
local BLIZZARD_AURA_SWIPE_TEX_HIGH = { x = 0.85, y = 0.85 }
-- Solid-fill restore texture: CooldownFrameTemplate's default swipe is a
-- file-less solid color, which SetSwipeTexture cannot return to directly;
-- a white fill under the black swipe color renders identically.
local DEFAULT_SWIPE_TEXTURE = "Interface\\Buttons\\WHITE8X8"
local DEFAULT_SWIPE_TEX_LOW = { x = 0, y = 0 }
local DEFAULT_SWIPE_TEX_HIGH = { x = 1, y = 1 }

-- Duration swipe styling: draw flags and colors from the aura swipe keys,
-- mirroring the CC cooldown swipe's ApplyDefaultCooldownSwipeStyle semantics.
-- Shared with the config preview, which styles a CC-side stand-in Cooldown
-- widget from the same keys (the preview never touches the aura slot subtree).
function CooldownCompanion:ApplyAuraDurationSwipeStyle(swipe, style)
    style = style or {}
    local swipeEnabled = style.showAuraDurationSwipe ~= false

    if swipeEnabled and style.auraUseBlizzardSwipe == true then
        -- Fixed preset: the normal swipe settings below do not apply.
        swipe:SetUseAuraDisplayTime(true)
        swipe:SetDrawSwipe(true)
        swipe:SetDrawEdge(false)
        swipe:SetReverse(false)
        swipe:SetSwipeTexture(BLIZZARD_AURA_SWIPE_TEXTURE, 1, 1, 1, 1)
        swipe:SetSwipeColor(1, 0.95, 0.57, 0.7)
        swipe:SetTexCoordRange(BLIZZARD_AURA_SWIPE_TEX_LOW, BLIZZARD_AURA_SWIPE_TEX_HIGH)
        return
    end

    local fillEnabled = style.showAuraDurationSwipeFill ~= false
    local edgeEnabled = style.showAuraDurationSwipeEdge ~= false
    swipe:SetUseAuraDisplayTime(false)
    swipe:SetSwipeTexture(DEFAULT_SWIPE_TEXTURE, 1, 1, 1, 1)
    swipe:SetTexCoordRange(DEFAULT_SWIPE_TEX_LOW, DEFAULT_SWIPE_TEX_HIGH)
    swipe:SetDrawSwipe(swipeEnabled and fillEnabled)
    swipe:SetDrawEdge(swipeEnabled and edgeEnabled)
    swipe:SetReverse(swipeEnabled and style.auraDurationSwipeReverse ~= false)
    swipe:SetSwipeColor(0, 0, 0, style.auraDurationSwipeAlpha or 0.8)
    local edgeColor = style.auraDurationSwipeEdgeColor
    swipe:SetEdgeColor(edgeColor and edgeColor[1] or 1, edgeColor and edgeColor[2] or 1,
        edgeColor and edgeColor[3] or 1, edgeColor and edgeColor[4] or 1)
end

-- Parity predicate (pre-12.1 ShouldUseActiveAuraIcon): standalone and passive
-- entries always show the live aura icon (Blizzard writes the aura instance's
-- icon, so snapshot-empowered DoT icons flip in combat); ordinary entries opt
-- in via auraShowAuraIcon.
local function ShouldShowAuraIcon(buttonData)
    return buttonData.auraShowAuraIcon == true
        or buttonData.addedAs == "aura"
        or buttonData.isPassive == true
end

local function StyleSlotKit(slot, button, buttonData, style)
    local kit = slot.kit
    if not kit then return end
    style = style or {}

    local slotButton = slot.slotButton
    local isBar = button._isBar == true
    local shellEntry = buttonData.hideWhileAuraNotActive == true
    local barIconShown = isBar and style.showBarIcon ~= false and button.icon ~= nil
    local showAuraIcon = ShouldShowAuraIcon(buttonData)

    -- Icon regions cover the slot rect on icon hosts. Bar hosts mount the
    -- slot on the bar rect, so the aura icon and its cover re-anchor onto the
    -- bar's icon square instead (host regions are sanctioned anchor targets;
    -- the duration text has host-anchored since Phase 3). Slots are reused
    -- across entries and modes, so both anchorings reset every bind.
    local iconAnchor = barIconShown and button.icon or slotButton
    kit.auraIcon:ClearAllPoints()
    kit.auraIcon:SetPoint("TOPLEFT", iconAnchor, "TOPLEFT", 0, 0)
    kit.auraIcon:SetPoint("BOTTOMRIGHT", iconAnchor, "BOTTOMRIGHT", 0, 0)
    kit.iconCover:ClearAllPoints()
    kit.iconCover:SetPoint("TOPLEFT", iconAnchor, "TOPLEFT", 0, 0)
    kit.iconCover:SetPoint("BOTTOMRIGHT", iconAnchor, "BOTTOMRIGHT", 0, 0)

    local auraIconShown = showAuraIcon and (not isBar or barIconShown)
    kit.auraIcon:SetAlpha(auraIconShown and 1 or 0)
    -- The cover occludes the CC icon underneath: always on icon hosts; on bar
    -- hosts only when the icon square participates (aura icon swap enabled,
    -- or a shell entry whose hidden CC icon needs the static replica).
    local coverWanted = (not isBar) or (barIconShown and (showAuraIcon or shellEntry))
    local coverShown = false

    -- Occluding cover: the entry's icon, cropped like the CC icon underneath
    -- (read at bind time — CC-owned texture, OOC-safe). Known edge: a combat
    -- icon override (form swap) can't refresh the cover until the next rebind.
    -- The aura icon gets the same crop: Blizzard writes only the texture into
    -- it (SetIconTextureForAura), so bind-time texcoords persist, and slots
    -- are reused across entries so the crop must be reset every bind.
    local ccIcon = button.icon
    if ccIcon and ccIcon.GetTexture and ccIcon:GetTexture() then
        kit.iconCover:SetTexture(ccIcon:GetTexture())
        kit.iconCover:SetTexCoord(ccIcon:GetTexCoord())
        kit.auraIcon:SetTexCoord(ccIcon:GetTexCoord())
        coverShown = coverWanted
    else
        local ApplyIconTexCoord = ST._ApplyIconTexCoord
        if ApplyIconTexCoord then
            ApplyIconTexCoord(kit.iconCover, button:GetWidth(), button:GetHeight())
            ApplyIconTexCoord(kit.auraIcon, button:GetWidth(), button:GetHeight())
        end
        if buttonData.type == "spell" and buttonData.id then
            kit.iconCover:SetTexture(C_Spell.GetSpellTexture(buttonData.id))
            coverShown = coverWanted
        end
    end
    kit.iconCover:SetAlpha(coverShown and 1 or 0)

    -- Aura-active icon tint lives on the aura layer now (the layer IS the
    -- aura-active state); the CC icon keeps its own tint pipeline. With no
    -- aura tint configured, carry the user's base icon tint so the icon
    -- doesn't visibly un-tint whenever an aura activates.
    local tint = style.iconAuraTintEnabled and style.iconAuraTintColor or style.iconTintColor
    local tr = tint and tint[1] or 1
    local tg = tint and tint[2] or 1
    local tb = tint and tint[3] or 1
    local ta = tint and tint[4] or 1
    -- The color's own alpha carries each region's visibility: a 4-arg
    -- SetVertexColor write REPLACES the region alpha through a non-SetAlpha
    -- C path (Phase 2 gotcha), so a plain tint alpha here would resurrect
    -- regions the alpha writes above just hid.
    kit.auraIcon:SetVertexColor(tr, tg, tb, auraIconShown and ta or 0)
    kit.iconCover:SetVertexColor(tr, tg, tb, coverShown and ta or 0)

    -- Inverted passive desaturation ("desaturate while active") desaturates
    -- the aura layer; the default "desaturate while missing" is a static
    -- desaturate on the CC icon (Tracking.lua) that this layer occludes.
    local kitDesat = buttonData.isPassive == true
        and buttonData.invertAuraDesaturationLogic == true
        and not buttonData.neverDesaturate
    kit.auraIcon:SetDesaturated(kitDesat)
    kit.iconCover:SetDesaturated(kitDesat)

    -- Duration/stack text: font/color from the aura text style keys (same
    -- helper the CC texts use), anchored to the HOST BUTTON rect so positions
    -- match the CC-side texts (the slot itself covers only the icon rect).
    -- Position contract (pre-12.1 parity, promised by the config tooltips):
    -- the duration text shares the Cooldown Text position unless the user
    -- enables separateTextPositions, which switches it to the aura keys.
    local ApplyFontStyle = CooldownCompanion.ApplyFontStyle
    if ApplyFontStyle then
        ApplyFontStyle(kit.durationText, style, "auraText")
        ApplyFontStyle(kit.stackText, style, "auraStack")
    end
    kit.durationText:ClearAllPoints()
    kit.stackText:ClearAllPoints()
    if isBar then
        -- Bar texts replicate the CC bar's own placement conventions (the
        -- backdrop occludes the originals): duration text at the bar
        -- time-text spot, stack text against the icon square like the old
        -- aura stack count.
        local cdOffX = style.barCdTextOffsetX or 0
        local cdOffY = style.barCdTextOffsetY or 0
        local timeReverse = style.barTimeTextReverse
        if button._isVertical then
            if timeReverse then
                kit.durationText:SetPoint("BOTTOM", slotButton, "BOTTOM", cdOffX, 3 + cdOffY)
            else
                kit.durationText:SetPoint("TOP", slotButton, "TOP", cdOffX, -3 + cdOffY)
            end
            kit.durationText:SetJustifyH("CENTER")
        else
            if timeReverse then
                kit.durationText:SetPoint("LEFT", slotButton, "LEFT", 3 + cdOffX, cdOffY)
                kit.durationText:SetJustifyH("LEFT")
            else
                kit.durationText:SetPoint("RIGHT", slotButton, "RIGHT", -3 + cdOffX, cdOffY)
                kit.durationText:SetJustifyH("RIGHT")
            end
        end
        kit.durationText:SetAlpha(style.showAuraText ~= false and 1 or 0)
        local asAnchor = style.auraStackAnchor or "BOTTOMLEFT"
        local stackAnchorTo = barIconShown and button.icon or slotButton
        kit.stackText:SetPoint(asAnchor, stackAnchorTo, asAnchor,
            style.auraStackXOffset or 2, style.auraStackYOffset or 2)
        kit.stackText:SetAlpha(style.showAuraStackText ~= false and 1 or 0)
    else
        local durAnchor, durX, durY = CooldownCompanion:GetAuraDurationTextPlacement(style)
        kit.durationText:SetPoint(durAnchor, button, durAnchor, durX, durY)
        kit.durationText:SetJustifyH("CENTER")
        kit.durationText:SetAlpha(style.showAuraText ~= false and 1 or 0)
        kit.stackText:SetPoint(style.auraStackAnchor or "BOTTOMLEFT",
            button, style.auraStackAnchor or "BOTTOMLEFT",
            style.auraStackXOffset or 2, style.auraStackYOffset or 2)
        kit.stackText:SetAlpha(style.showAuraStackText ~= false and 1 or 0)
    end

    -- Bar name replica: bind-time entry name in the bar name-text style (the
    -- backdrop occludes CC's name text; a live aura-name override would need
    -- the unvalidated SetSpellName registration).
    kit.barNameText:ClearAllPoints()
    if isBar and (style.showBarNameText ~= false or buttonData.customName) then
        if ApplyFontStyle then
            ApplyFontStyle(kit.barNameText, style, "barName", 10)
        end
        local nameOffX = style.barNameTextOffsetX or 0
        local nameOffY = style.barNameTextOffsetY or 0
        local nameReverse = style.barNameTextReverse
        if button._isVertical then
            if nameReverse then
                kit.barNameText:SetPoint("TOP", slotButton, "TOP", nameOffX, -3 + nameOffY)
            else
                kit.barNameText:SetPoint("BOTTOM", slotButton, "BOTTOM", nameOffX, 3 + nameOffY)
            end
            kit.barNameText:SetJustifyH("CENTER")
        else
            if nameReverse then
                kit.barNameText:SetPoint("RIGHT", slotButton, "RIGHT", -3 + nameOffX, nameOffY)
                kit.barNameText:SetJustifyH("RIGHT")
            else
                kit.barNameText:SetPoint("LEFT", slotButton, "LEFT", 3 + nameOffX, nameOffY)
                kit.barNameText:SetJustifyH("LEFT")
            end
            -- Same-side truncation guard, replicated from CreateBarFrame:
            -- when the visible duration text shares the name's side, pin the
            -- name against it so the two can't overlap.
            if style.barNameTextReverse == style.barTimeTextReverse
                and kit.durationText:GetAlpha() > 0 then
                if nameReverse then
                    kit.barNameText:SetPoint("LEFT", kit.durationText, "RIGHT", 4, 0)
                else
                    kit.barNameText:SetPoint("RIGHT", kit.durationText, "LEFT", -4, 0)
                end
            end
        end
        local displayName = buttonData.customName
        if not displayName and buttonData.type == "spell" and buttonData.id then
            -- Same resolution as the CC name text underneath: the live
            -- override spell when one is displayed (bind-time CC field read).
            displayName = C_Spell.GetSpellName(button._displaySpellId or buttonData.id)
        end
        kit.barNameText:SetText(displayName or buttonData.name or "")
        kit.barNameText:SetAlpha(1)
    else
        kit.barNameText:SetText("")
        kit.barNameText:SetAlpha(0)
    end

    -- Duration swipe: Blizzard drives the swipe's cooldown; draw flags and
    -- colors are CC styling and persist across those writes. Bars have no
    -- aura swipe — the draining bar is the timer.
    if isBar then
        kit.swipe:SetDrawSwipe(false)
        kit.swipe:SetDrawEdge(false)
    else
        CooldownCompanion:ApplyAuraDurationSwipeStyle(kit.swipe, style)
    end

    -- Bar composition: opaque backdrop occludes the CC bar underneath
    -- (skipped for shell entries — nothing visible to occlude); Blizzard
    -- drains the registered fill while the aura runs. Color writes carry
    -- their own alpha and only happen in the enabled branch
    -- (SetVertexColor-alpha gotcha: a 4-arg color write after SetAlpha(0)
    -- would resurrect the region).
    if isBar then
        if shellEntry then
            kit.barBackdrop:SetAlpha(0)
        else
            local bg = style.barBgColor or { 0.1, 0.1, 0.1, 0.8 }
            -- Backdrop alpha forced opaque: a translucent backdrop would let
            -- the CC fill bleed through as the aura bar drains.
            kit.barBackdrop:SetColorTexture(bg[1] or 0.1, bg[2] or 0.1, bg[3] or 0.1, 1)
            kit.barBackdrop:SetAlpha(1)
        end
        if kit.barFill then
            local auraColor = style.barAuraColor or { 0.2, 1.0, 0.2, 1.0 }
            kit.barFill:SetOrientation(button._isVertical and "VERTICAL" or "HORIZONTAL")
            kit.barFill:SetReverseFill(style.barReverseFill or false)
            kit.barFill:SetStatusBarTexture(CooldownCompanion:FetchEffectiveBarTexture(style.barTexture or "Solid"))
            kit.barFill:SetAlpha(1)
            kit.barFill:SetStatusBarColor(auraColor[1], auraColor[2], auraColor[3], auraColor[4] or 1)

            -- Bar aura fill effects: pulse breathes the fill alpha; color
            -- shift bounces the fill tint between the aura color and the
            -- shift color. While shifting, the base color stays white so the
            -- VertexColor animation owns the full color range (same trick as
            -- the kit border colorShift).
            kit.barFillPulseAG:Stop()
            kit.barFillCsAG:Stop()
            kit.barFill:GetStatusBarTexture():SetVertexColor(1, 1, 1, 1)
            local indicatorOn = ST.IsBarAuraIndicatorEnabled(style)
            if indicatorOn and style.barAuraPulseEnabled then
                kit.barFillPulseAnim:SetDuration(style.barAuraPulseSpeed or 0.5)
                kit.barFillPulseAG:Play()
            end
            if indicatorOn and style.barAuraColorShiftEnabled then
                kit.barFill:SetStatusBarColor(1, 1, 1, auraColor[4] or 1)
                local shift = style.barAuraColorShiftColor or { 1, 1, 1, 1 }
                kit.barFillCsAnim:SetStartColor(CreateColor(auraColor[1], auraColor[2], auraColor[3], auraColor[4] or 1))
                kit.barFillCsAnim:SetEndColor(CreateColor(shift[1], shift[2], shift[3], shift[4] or 1))
                kit.barFillCsAnim:SetDuration(style.barAuraColorShiftSpeed or 0.5)
                kit.barFillCsAG:Play()
            end
        end
    else
        kit.barBackdrop:SetAlpha(0)
        if kit.barFill then
            kit.barFillPulseAG:Stop()
            kit.barFillCsAG:Stop()
            kit.barFill:GetStatusBarTexture():SetVertexColor(1, 1, 1, 1)
            kit.barFill:SetAlpha(0)
        end
    end

    -- Aura active glow: icon hosts style from the auraGlow* keys, bar hosts
    -- from the barAura* keys (whole-bar anchor). Style resolution and the
    -- "none"/enable gates live in the builders; the config preview renders
    -- equivalent visuals CC-side (Glows.lua NormalizeAuraGlowPreviewStyle /
    -- NormalizeBarAuraEffectStyle), never here.
    if isBar then
        ST._StyleKitBarGlowRegions(kit.glow, style, button, true)
    else
        ST._StyleKitGlowRegions(kit.glow, style, button, true)
    end

    -- Full-button composition for show-only-while-active entries: bg + border
    -- replicas anchored to the host frames (pixel-identical to the CC shell).
    -- Bars carry two chrome sets — the bar ring and the icon square's own
    -- background/border — so bar shells style the second replica set too.
    if shellEntry and not isBar then
        kit.bg:ClearAllPoints()
        kit.bg:SetPoint("TOPLEFT", button, "TOPLEFT", 0, 0)
        kit.bg:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 0, 0)
        local bgColor = style.backgroundColor or { 0, 0, 0, 0.5 }
        kit.bg:SetColorTexture(bgColor[1] or 0, bgColor[2] or 0, bgColor[3] or 0, bgColor[4] or 0.5)
        kit.bg:SetAlpha(1)
        local borderSize = style.borderSize or ST.DEFAULT_BORDER_SIZE
        -- Effective mode, not raw: the profile one-pixel-borders option
        -- promotes CUSTOM to CRISP exactly like ApplyBorderEdgePositions.
        local renderMode = ST.GetEffectiveBorderRenderMode(ST.GetBorderRenderMode(style), nil, borderSize)
        ST.ApplyBorderTexturesBetween(kit.border, button, button,
            style.borderColor or { 0, 0, 0, 1 }, borderSize, renderMode)
        for _, tex in ipairs(kit.border) do
            tex:SetAlpha(1)
        end
        kit.iconBg:SetAlpha(0)
        for _, tex in ipairs(kit.iconBorder) do
            tex:SetAlpha(0)
        end
    elseif shellEntry and isBar then
        local bgColor = style.barBgColor or { 0.1, 0.1, 0.1, 0.8 }
        local barBounds = button._barBounds or button
        -- CC parity: with the icon square shown the background covers only
        -- the bar area (the square has its own), otherwise the whole button.
        local bgAnchor = barIconShown and barBounds or button
        kit.bg:ClearAllPoints()
        kit.bg:SetPoint("TOPLEFT", bgAnchor, "TOPLEFT", 0, 0)
        kit.bg:SetPoint("BOTTOMRIGHT", bgAnchor, "BOTTOMRIGHT", 0, 0)
        kit.bg:SetColorTexture(bgColor[1] or 0.1, bgColor[2] or 0.1, bgColor[3] or 0.1, bgColor[4] or 0.8)
        kit.bg:SetAlpha(1)
        local borderSize = style.borderSize or ST.DEFAULT_BORDER_SIZE
        local renderMode = ST.GetEffectiveBorderRenderMode(ST.GetBorderRenderMode(style), nil, borderSize)
        local borderColor = style.borderColor or { 0, 0, 0, 1 }
        ST.ApplyBorderTexturesBetween(kit.border, barBounds, barBounds,
            borderColor, borderSize, renderMode)
        for _, tex in ipairs(kit.border) do
            tex:SetAlpha(1)
        end
        if barIconShown and button._iconBounds then
            kit.iconBg:ClearAllPoints()
            kit.iconBg:SetPoint("TOPLEFT", button._iconBounds, "TOPLEFT", 0, 0)
            kit.iconBg:SetPoint("BOTTOMRIGHT", button._iconBounds, "BOTTOMRIGHT", 0, 0)
            kit.iconBg:SetColorTexture(bgColor[1] or 0.1, bgColor[2] or 0.1, bgColor[3] or 0.1, bgColor[4] or 0.8)
            kit.iconBg:SetAlpha(1)
            ST.ApplyBorderTexturesBetween(kit.iconBorder, button._iconBounds, button._iconBounds,
                borderColor, borderSize, renderMode)
            for _, tex in ipairs(kit.iconBorder) do
                tex:SetAlpha(1)
            end
        else
            kit.iconBg:SetAlpha(0)
            for _, tex in ipairs(kit.iconBorder) do
                tex:SetAlpha(0)
            end
        end
    else
        kit.bg:SetAlpha(0)
        for _, tex in ipairs(kit.border) do
            tex:SetAlpha(0)
        end
        kit.iconBg:SetAlpha(0)
        for _, tex in ipairs(kit.iconBorder) do
            tex:SetAlpha(0)
        end
    end

    -- Keybind replica (icon shells only): same style keys, placement, and
    -- text resolution as CC's own keybindText (IconMode), read at bind time.
    -- Keybind edits are config-time and every restyle re-requests a rebind,
    -- so bind-time reads stay current. Bars keep their CC-side conventions
    -- (bar hosts never showed keybind text).
    local keybindText
    if shellEntry and not isBar and style.showKeybindText then
        keybindText = CooldownCompanion.GetDisplayedKeybindText
            and CooldownCompanion:GetDisplayedKeybindText(buttonData, button._resolvedItemId, button)
    end
    if keybindText and keybindText ~= "" then
        if ApplyFontStyle then
            ApplyFontStyle(kit.keybindText, style, "keybind", 10)
        end
        kit.keybindText:ClearAllPoints()
        local kbAnchor = style.keybindAnchor or "TOPRIGHT"
        kit.keybindText:SetPoint(kbAnchor, button, kbAnchor,
            style.keybindXOffset or -2, style.keybindYOffset or -2)
        kit.keybindText:SetText(keybindText)
        kit.keybindText:SetAlpha(1)
    else
        kit.keybindText:SetText("")
        kit.keybindText:SetAlpha(0)
    end
end

------------------------------------------------------------------------
-- Aura sounds — the compliant aura sound events in 12.1:
-- C_UnitAuras.AddAuraSound (PTR 6 rename of AddAuraAppliedSound, now with
-- applied / stack gained / removed triggers) plays a sound file whenever
-- the spellID's aura hits the trigger on the unit, entirely Blizzard-side
-- (validated in combat). Registered at bind, released at park. Refcounted
-- because entries can share candidate spellIDs (linked-aura sets) and the
-- same trigger + sound.
------------------------------------------------------------------------

local auraSounds = {} -- key -> { id = auraSoundID, count = n }

-- Config event key -> Enum.UnitAuraSoundTrigger name, resolved at
-- registration time (the enum ships with AddAuraSound, which the
-- capability guard below already requires).
local AURA_SOUND_EVENT_TRIGGERS = {
    { eventKey = "onAuraApplied", triggerName = "Added" },
    { eventKey = "onAuraStackGained", triggerName = "ApplicationsIncreased" },
    { eventKey = "onAuraRemoved", triggerName = "Removed" },
}

local function RegisterSlotAuraSounds(slot, buttonData, spellSet)
    if not (C_UnitAuras.AddAuraSound and C_UnitAuras.RemoveAuraSound) then return end
    local keys
    for _, eventInfo in ipairs(AURA_SOUND_EVENT_TRIGGERS) do
        local soundFile, channel = CooldownCompanion:GetAuraSoundFileForButton(buttonData, eventInfo.eventKey)
        if soundFile then
            local trigger = Enum.UnitAuraSoundTrigger[eventInfo.triggerName]
            for spellID in pairs(spellSet) do
                local key = slot.unit .. ":" .. spellID .. ":" .. trigger .. ":" .. soundFile .. ":" .. (channel or "")
                local entry = auraSounds[key]
                if entry then
                    entry.count = entry.count + 1
                else
                    local id = C_UnitAuras.AddAuraSound(trigger, {
                        unitToken = slot.unit,
                        spellID = spellID,
                        soundFileName = soundFile,
                        outputChannel = channel,
                    })
                    if id then
                        entry = { id = id, count = 1 }
                        auraSounds[key] = entry
                    end
                end
                if entry then
                    keys = keys or {}
                    keys[#keys + 1] = key
                end
            end
        end
    end
    slot.auraSoundKeys = keys
end

local function ReleaseSlotAuraSounds(slot)
    local keys = slot.auraSoundKeys
    if not keys then return end
    slot.auraSoundKeys = nil
    for _, key in ipairs(keys) do
        local entry = auraSounds[key]
        if entry then
            entry.count = entry.count - 1
            if entry.count <= 0 then
                auraSounds[key] = nil
                C_UnitAuras.RemoveAuraSound(entry.id)
            end
        end
    end
end

------------------------------------------------------------------------
-- Slot lifecycle
------------------------------------------------------------------------

local function BuildCandidateFilters(unit, spellSet)
    local filters = { includeSpellIDs = spellSet }
    if unit == "target" then
        -- Match today's behavior: only the player's own debuffs.
        filters.isFromPlayerOrPlayerPet = true
    end
    return filters
end

local function CreateSlot(unit)
    local container = EnsureContainer(unit)
    if not container then return nil end
    slotCounter = slotCounter + 1
    local record = {
        key = "cc" .. slotCounter,
        unit = unit,
    }
    -- Direct call, no pcall: a real AddAuraSlot error must surface (repo
    -- rule); the nil check below covers the documented soft-failure return.
    local slotButton = container:AddAuraSlot(record.key, UNIT_FILTER[unit], {
        candidateFilters = BuildCandidateFilters(unit, { [PARK_SENTINEL[unit]] = true }),
        initializeFrame = function(frame)
            record.kit = BuildSlotKit(frame)
        end,
    })
    if not slotButton then
        CooldownCompanion:Print("Aura slot creation failed.")
        return nil
    end
    record.slotButton = slotButton
    record.container = container
    local unitSlots = slots[unit]
    unitSlots[#unitSlots + 1] = record
    return record
end

local function ParkSlot(slot)
    if slot.hostButton then
        slot.hostButton._auraSlotHostToken = nil
        slot.hostButton = nil
    end
    if not slot.parked then
        slot.parked = true
        slot.boundEntry = nil
        ReleaseSlotAuraSounds(slot)
        slot.slotButton:SetParent(park)
        slot.slotButton:ClearAllPoints()
        slot.slotButton:SetPoint("CENTER", park, "CENTER")
        slot.container:SetAuraSlotCandidateFilters(slot.key,
            BuildCandidateFilters(slot.unit, { [PARK_SENTINEL[slot.unit]] = true }))
    end
end

-- The auraLayer is the CC-owned mount point for the slot subtree. It (and
-- everything under it) is excluded from every recursive frame sweep via the
-- _ccNoTouch flag; the layer itself is safe to touch, its children are not.
local function EnsureAuraLayer(button)
    local layer = button.auraLayer
    if not layer then
        layer = CreateFrame("Frame", nil, button)
        layer._ccNoTouch = true
        button.auraLayer = layer
    end
    -- Re-anchored every call: idempotent, and frame-relative anchoring tracks
    -- geometry restyles for free. Bar hosts mount the slot on the bar rect
    -- (statusBar is already inset by the border layout, so the CC border ring
    -- stays visible around the aura display).
    local anchorTo = (button._isBar and button.statusBar) or button.icon or button
    layer:ClearAllPoints()
    layer:SetPoint("TOPLEFT", anchorTo, "TOPLEFT", 0, 0)
    layer:SetPoint("BOTTOMRIGHT", anchorTo, "BOTTOMRIGHT", 0, 0)
    if button._isBar and button.barTextFrame then
        -- Above barTextFrame (statusBar+20): CC keeps writing cooldown time
        -- text per tick with no way to know an aura is showing, so the kit
        -- backdrop must occlude it. Charge/count text hoists above the kit's
        -- textOverlay (slot+3) to stay readable. UpdateBarStyle re-sets
        -- barTextFrame's level on restyles, and UpdateGroupStyle always
        -- re-requests a rebind, so this ordering re-converges after every
        -- style edit.
        layer:SetFrameLevel(button.barTextFrame:GetFrameLevel() + 1)
        if button.overlayFrame then
            button.overlayFrame:SetFrameLevel(layer:GetFrameLevel() + 10)
        end
    else
        -- Above every configurable button element (LoC sits at baseLevel+7).
        -- ApplyStrataOrder (ButtonFrame/Helpers.lua) keeps these two levels in
        -- sync on restyles: CC's text overlay rides ABOVE the aura display so
        -- count/keybind text stays readable while an aura is showing.
        layer:SetFrameLevel(button:GetFrameLevel() + 8)
        if button.overlayFrame then
            button.overlayFrame:SetFrameLevel(button:GetFrameLevel() + 9)
        end
    end
    return layer
end

local function BindSlot(slot, button, buttonData, spellSet, style)
    local layer = EnsureAuraLayer(button)
    local slotButton = slot.slotButton
    slotButton:SetParent(layer)
    slotButton:ClearAllPoints()
    slotButton:SetPoint("TOPLEFT", layer, "TOPLEFT", 0, 0)
    slotButton:SetPoint("BOTTOMRIGHT", layer, "BOTTOMRIGHT", 0, 0)
    slot.container:SetAuraSlotCandidateFilters(slot.key, BuildCandidateFilters(slot.unit, spellSet))
    StyleSlotKit(slot, button, buttonData, style)
    RegisterSlotAuraSounds(slot, buttonData, spellSet)
    -- Tooltip suppression follows the click-through sweep's recorded motion
    -- state (the sweep itself never reaches the slot subtree). P7-validated.
    slotButton:SetMouseMotionEnabled(not button._cdcClickThroughMotion)
    slot.parked = nil
    slot.boundEntry = buttonData
    slot.hostButton = button
    -- Combat pool lock: while this button is pooled in combat it may only be
    -- re-acquired for the same entry (GroupFrame.AcquireButtonFromPool).
    button._auraSlotHostToken = buttonData
end

------------------------------------------------------------------------
-- The rebind pass — the single place slot subtrees are touched. Idempotent,
-- coalesced, OOC-only: park everything, then bind every aura-tracking entry
-- currently materialized as a button.
------------------------------------------------------------------------

-- Derive the tracked unit from spell polarity every pass (the anti-cheat gate
-- allows only buffs-on-player and own-debuffs-on-target); the stored auraUnit
-- is a fallback for uncached spells, so config/migration/runtime can't drift.
local function ResolveEntryAuraUnit(self, buttonData)
    local first = self:ResolveAuraSpellID(buttonData)
    if first and C_Spell.DoesSpellExist(first) then
        return C_Spell.IsSpellHarmful(first) and "target" or "player"
    end
    return buttonData.auraUnit == "target" and "target" or "player"
end

-- One combat-defer note per deferral window: config edits made in combat keep
-- applying to CC-side visuals immediately, but the aura display (slot kit)
-- only restyles at the deferred rebind, so the player is told once why the
-- aura visuals lag. Cleared when a rebind actually runs.
local deferNoteShown = false

local function HasBoundSlots(groupId)
    for _, unitSlots in pairs(slots) do
        for _, slot in ipairs(unitSlots) do
            if slot.boundEntry then
                if groupId == nil then return true end
                local host = slot.hostButton
                if host and host._groupId == groupId then return true end
            end
        end
    end
    return false
end

local function NoteDeferredConfigEdit(reason, groupId)
    if deferNoteShown then return end
    -- Only config-originated requests note the deferral: "config" is always an
    -- aura settings edit; "style" is any style edit, so it only matters when
    -- the edited group actually has an aura display. Automatic requests defer
    -- silently.
    if reason == "config" or (reason == "style" and HasBoundSlots(groupId)) then
        deferNoteShown = true
        CooldownCompanion:Print("Aura display changes will apply when combat ends.")
    end
end

function RunAuraRebind()
    local self = CooldownCompanion
    if not (self.db and self.groupFrames) then return end
    deferNoteShown = false

    -- Collect wanted bindings from live buttons (icon/bar groups only — text
    -- mode has no compliant aura display; trigger/texture panels lost aura
    -- conditions by design; dormant flags there stay dormant).
    local wanted = { player = {}, target = {} }
    for groupId, frame in pairs(self.groupFrames) do
        local group = self.db.profile.groups[groupId]
        local displayMode = group and (group.displayMode or "icons")
        if (displayMode == "icons" or displayMode == "bars") and frame.buttons then
            for _, button in ipairs(frame.buttons) do
                local buttonData = button.buttonData
                if buttonData and buttonData.type == "spell"
                    and (buttonData.auraTracking or buttonData.addedAs == "aura") then
                    local spellSet = self:GetAuraCandidateSpellIDSet(buttonData)
                    if spellSet then
                        local unit = ResolveEntryAuraUnit(self, buttonData)
                        local list = wanted[unit]
                        list[#list + 1] = {
                            button = button,
                            buttonData = buttonData,
                            spellSet = spellSet,
                            style = self:GetEffectiveStyle(group.style, buttonData),
                        }
                    end
                end
            end
        end
    end

    -- Authoritative P11 gate: CanRunRebindNow only sees EXISTING target slots,
    -- so the very first target bind could otherwise slip into the forbidden
    -- window (target fighting while the player is OOC). Existing target slots
    -- can't reach here blocked — every caller checks CanRunRebindNow first —
    -- so skipping the target unit skips only the first-bind case; player
    -- binds proceed and the armed retry re-runs the full pass.
    local targetBlocked = #wanted.target > 0
        and UnitExists("target") and UnitAffectingCombat("target")

    for unit, list in pairs(wanted) do
        if not (unit == "target" and targetBlocked) then
            local unitSlots = slots[unit]
            -- Park everything first (also clears host tokens), then bind fresh —
            -- simple and idempotent; runs at config-change frequency, never per tick.
            for _, slot in ipairs(unitSlots) do
                ParkSlot(slot)
            end
            for i, want in ipairs(list) do
                local slot = unitSlots[i] or CreateSlot(unit)
                if not slot then break end
                BindSlot(slot, want.button, want.buttonData, want.spellSet, want.style)
            end
        end
    end

    if targetBlocked then
        ArmRebindRetry()
    end
end

rebindDeferFrame:SetScript("OnEvent", function()
    -- Unregister BEFORE running so an error can't leave the events stuck
    -- (FrameAnchoring's combat-defer pattern).
    DisarmRebindRetry()
    pendingRebind = false
    if CanRunRebindNow() then
        -- RunAuraRebind re-arms itself if a first target bind is still blocked.
        RunAuraRebind()
    else
        -- Still blocked (target fighting while we left combat): re-arm; the
        -- target watcher also retries on target changes.
        ArmRebindRetry()
    end
end)

-- Single entry point. OOC requests coalesce into one next-frame pass (group
-- populates arrive once per group on a reload); the timer callback re-checks
-- combat and re-defers if a pull started in between.
function CooldownCompanion:RequestAuraRebind(reason, groupId)
    if not self.db then return end
    if not CanRunRebindNow() then
        NoteDeferredConfigEdit(reason, groupId)
        if pendingRebind then return end
        ArmRebindRetry()
        return
    end
    if rebindQueued then return end
    rebindQueued = true
    C_Timer.After(0, function()
        rebindQueued = false
        if CanRunRebindNow() then
            RunAuraRebind()
        elseif not pendingRebind then
            NoteDeferredConfigEdit(reason, groupId)
            ArmRebindRetry()
        end
    end)
end

-- Read-only status for validation/DevBridge (module state is otherwise local).
function CooldownCompanion:GetAuraDisplayStatus()
    local auraSoundCount = 0
    for _ in pairs(auraSounds) do
        auraSoundCount = auraSoundCount + 1
    end
    local status = { pendingRebind = pendingRebind, auraSounds = auraSoundCount, units = {} }
    for unit, unitSlots in pairs(slots) do
        local bound = 0
        for _, slot in ipairs(unitSlots) do
            if slot.boundEntry then bound = bound + 1 end
        end
        status.units[unit] = { slots = #unitSlots, bound = bound }
    end
    return status
end
