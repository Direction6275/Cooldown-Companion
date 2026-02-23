--[[
    CooldownCompanion - ButtonFrame/IconMode
    Icon-mode button creation, styling, visuals, and glow updates
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon

-- Localize frequently-used globals
local pairs = pairs
local ipairs = ipairs
local unpack = unpack

-- Imports from Helpers
local ApplyStrataOrder = ST._ApplyStrataOrder
local ApplyEdgePositions = ST._ApplyEdgePositions
local ApplyIconTexCoord = ST._ApplyIconTexCoord
local FitHighlightFrame = ST._FitHighlightFrame

-- Imports from Glows
local CreateGlowContainer = ST._CreateGlowContainer
local CreateAssistedHighlight = ST._CreateAssistedHighlight
local SetupTooltipScripts = ST._SetupTooltipScripts
local SetAssistedHighlight = ST._SetAssistedHighlight
local SetProcGlow = ST._SetProcGlow
local SetAuraGlow = ST._SetAuraGlow

-- Imports from Visibility
local UpdateLossOfControl = ST._UpdateLossOfControl

-- Imports from Tracking
local UpdateIconTint = ST._UpdateIconTint

-- Shared click-through helpers from Utils.lua
local SetFrameClickThroughRecursive = ST.SetFrameClickThroughRecursive

-- IsItemEquippable from Helpers (exported on CooldownCompanion)
local IsItemEquippable = CooldownCompanion.IsItemEquippable

function CooldownCompanion:CreateButtonFrame(parent, index, buttonData, style)
    local width, height

    if style.maintainAspectRatio then
        -- Square mode: use buttonSize for both dimensions
        local size = style.buttonSize or ST.BUTTON_SIZE
        width = size
        height = size
    else
        -- Non-square mode: use separate width/height
        width = style.iconWidth or style.buttonSize or ST.BUTTON_SIZE
        height = style.iconHeight or style.buttonSize or ST.BUTTON_SIZE
    end

    -- Create main button frame
    local button = CreateFrame("Frame", parent:GetName() .. "Button" .. index, parent)
    button:SetSize(width, height)
    local baseLevel = button:GetFrameLevel()

    -- Background
    button.bg = button:CreateTexture(nil, "BACKGROUND")
    button.bg:SetAllPoints()
    local bgColor = style.backgroundColor or {0, 0, 0, 0.5}
    button.bg:SetColorTexture(unpack(bgColor))

    -- Icon
    button.icon = button:CreateTexture(nil, "ARTWORK")
    local borderSize = style.borderSize or ST.DEFAULT_BORDER_SIZE
    button.icon:SetPoint("TOPLEFT", borderSize, -borderSize)
    button.icon:SetPoint("BOTTOMRIGHT", -borderSize, borderSize)

    ApplyIconTexCoord(button.icon, width, height)

    -- Border using textures (not BackdropTemplate which captures mouse)
    local borderColor = style.borderColor or {0, 0, 0, 1}
    button.borderTextures = {}

    -- Create 4 edge textures for border using shared anchor spec
    for i = 1, 4 do
        local tex = button:CreateTexture(nil, "OVERLAY")
        tex:SetColorTexture(unpack(borderColor))
        button.borderTextures[i] = tex
    end
    ApplyEdgePositions(button.borderTextures, button, borderSize)

    -- Assisted highlight overlays (multiple styles, all hidden by default)
    button.assistedHighlight = CreateAssistedHighlight(button, style)

    -- Cooldown frame (standard radial swipe)
    button.cooldown = CreateFrame("Cooldown", button:GetName() .. "Cooldown", button, "CooldownFrameTemplate")
    button.cooldown:SetAllPoints(button.icon)
    local swipeEnabled = style.showCooldownSwipe ~= false
    button.cooldown:SetDrawSwipe(swipeEnabled)
    button.cooldown:SetDrawEdge(swipeEnabled and style.showCooldownSwipeEdge ~= false)
    button.cooldown:SetReverse(swipeEnabled and (style.cooldownSwipeReverse or false))
    button.cooldown:SetSwipeColor(0, 0, 0, 0.8)
    button.cooldown:SetHideCountdownNumbers(false) -- Always allow; visibility controlled via text alpha
    -- Recursively disable mouse on cooldown and all its children (CooldownFrameTemplate has children)
    -- Always fully non-interactive: disable both clicks and motion
    SetFrameClickThroughRecursive(button.cooldown, true, true)

    -- Loss of control cooldown frame (red swipe showing lockout duration)
    button.locCooldown = CreateFrame("Cooldown", button:GetName() .. "LocCooldown", button, "CooldownFrameTemplate")
    button.locCooldown:SetAllPoints(button.icon)
    button.locCooldown:SetDrawEdge(true)
    button.locCooldown:SetDrawSwipe(true)
    button.locCooldown:SetSwipeColor(0.17, 0, 0, 0.8)
    button.locCooldown:SetHideCountdownNumbers(true)
    SetFrameClickThroughRecursive(button.locCooldown, true, true)

    -- Suppress bling (cooldown-end flash) on all icon buttons
    button.cooldown:SetDrawBling(false)
    button.locCooldown:SetDrawBling(false)

    -- Proc glow elements (solid border + animated glow + pixel glow)
    button.procGlow = CreateGlowContainer(button, style.procGlowSize or 32)

    -- Aura active glow elements (solid border + animated glow + pixel glow)
    button.auraGlow = CreateGlowContainer(button, 32)

    -- Frame levels: just above cooldown
    local auraGlowLevel = button.cooldown:GetFrameLevel() + 1
    button.auraGlow.solidFrame:SetFrameLevel(auraGlowLevel)
    button.auraGlow.procFrame:SetFrameLevel(auraGlowLevel)
    button.auraGlow.pixelFrame:SetFrameLevel(auraGlowLevel)

    -- Apply custom cooldown text font settings
    local cooldownFont = CooldownCompanion:FetchFont(style.cooldownFont or "Friz Quadrata TT")
    local cooldownFontSize = style.cooldownFontSize or 12
    local cooldownFontOutline = style.cooldownFontOutline or "OUTLINE"
    local region = button.cooldown:GetRegions()
    if region and region.SetFont then
        region:SetFont(cooldownFont, cooldownFontSize, cooldownFontOutline)
        local cdColor = style.cooldownFontColor or {1, 1, 1, 1}
        region:SetTextColor(cdColor[1], cdColor[2], cdColor[3], cdColor[4])
        region:ClearAllPoints()
        local cdAnchor = style.cooldownTextAnchor or "CENTER"
        local cdXOff = style.cooldownTextXOffset or 0
        local cdYOff = style.cooldownTextYOffset or 0
        region:SetPoint(cdAnchor, cdXOff, cdYOff)
        button._cdTextRegion = region
    end

    -- Stack count text (for items) — on overlay frame so it renders above cooldown swipe
    button.overlayFrame = CreateFrame("Frame", nil, button)
    button.overlayFrame:SetAllPoints()
    button.overlayFrame:EnableMouse(false)
    button.count = button.overlayFrame:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    button.count:SetText("")

    -- Apply custom count text font/anchor settings from effective style
    if buttonData.hasCharges or buttonData.isPassive then
        local chargeFont = CooldownCompanion:FetchFont(style.chargeFont or "Friz Quadrata TT")
        local chargeFontSize = style.chargeFontSize or 12
        local chargeFontOutline = style.chargeFontOutline or "OUTLINE"
        button.count:SetFont(chargeFont, chargeFontSize, chargeFontOutline)
        local chColor = style.chargeFontColor or {1, 1, 1, 1}
        button.count:SetTextColor(chColor[1], chColor[2], chColor[3], chColor[4])

        local chargeAnchor = style.chargeAnchor or "BOTTOMRIGHT"
        local chargeXOffset = style.chargeXOffset or -2
        local chargeYOffset = style.chargeYOffset or 2
        button.count:SetPoint(chargeAnchor, chargeXOffset, chargeYOffset)
    elseif buttonData.type == "item" and not IsItemEquippable(buttonData) then
        local itemFont = CooldownCompanion:FetchFont(buttonData.itemCountFont or "Friz Quadrata TT")
        local itemFontSize = buttonData.itemCountFontSize or 12
        local itemFontOutline = buttonData.itemCountFontOutline or "OUTLINE"
        button.count:SetFont(itemFont, itemFontSize, itemFontOutline)
        local icColor = buttonData.itemCountFontColor or {1, 1, 1, 1}
        button.count:SetTextColor(icColor[1], icColor[2], icColor[3], icColor[4])

        local itemAnchor = buttonData.itemCountAnchor or "BOTTOMRIGHT"
        local itemXOffset = buttonData.itemCountXOffset or -2
        local itemYOffset = buttonData.itemCountYOffset or 2
        button.count:SetPoint(itemAnchor, itemXOffset, itemYOffset)
    else
        button.count:SetPoint("BOTTOMRIGHT", -2, 2)
    end

    -- Aura stack count text — separate FontString for aura stacks, independent of charge text
    if buttonData.auraTracking or buttonData.isPassive then
        button.auraStackCount = button.overlayFrame:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
        button.auraStackCount:SetText("")
        local asFont = CooldownCompanion:FetchFont(style.auraStackFont or "Friz Quadrata TT")
        local asFontSize = style.auraStackFontSize or 12
        local asFontOutline = style.auraStackFontOutline or "OUTLINE"
        button.auraStackCount:SetFont(asFont, asFontSize, asFontOutline)
        local asColor = style.auraStackFontColor or {1, 1, 1, 1}
        button.auraStackCount:SetTextColor(asColor[1], asColor[2], asColor[3], asColor[4])
        local asAnchor = style.auraStackAnchor or "BOTTOMLEFT"
        local asXOff = style.auraStackXOffset or 2
        local asYOff = style.auraStackYOffset or 2
        button.auraStackCount:SetPoint(asAnchor, asXOff, asYOff)
    end

    -- Keybind text overlay
    button.keybindText = button.overlayFrame:CreateFontString(nil, "OVERLAY")
    do
        local kbFont = CooldownCompanion:FetchFont(style.keybindFont or "Friz Quadrata TT")
        local kbSize = style.keybindFontSize or 10
        local kbOutline = style.keybindFontOutline or "OUTLINE"
        button.keybindText:SetFont(kbFont, kbSize, kbOutline)
        local kbColor = style.keybindFontColor or {1, 1, 1, 1}
        button.keybindText:SetTextColor(kbColor[1], kbColor[2], kbColor[3], kbColor[4])
        local anchor = style.keybindAnchor or "TOPRIGHT"
        local xOff = style.keybindXOffset or -2
        local yOff = style.keybindYOffset or -2
        button.keybindText:SetPoint(anchor, xOff, yOff)
        local text = CooldownCompanion:GetKeybindText(buttonData)
        button.keybindText:SetText(text or "")
        button.keybindText:SetShown(style.showKeybindText and text ~= nil)
    end

    -- Apply configurable strata ordering (LoC always on top)
    ApplyStrataOrder(button, style.strataOrder)

    -- Store button data
    button.buttonData = buttonData
    button.index = index
    button.style = style

    -- Cache spell cooldown secrecy level (static per-spell: NeverSecret=0, ContextuallySecret=2)
    if buttonData.type == "spell" then
        buttonData._cooldownSecrecy = C_Secrets.GetSpellCooldownSecrecy(buttonData.id)
    end

    -- Aura tracking runtime state
    button._auraSpellID = CooldownCompanion:ResolveAuraSpellID(buttonData)
    button._auraUnit = buttonData.auraUnit or "player"
    button._auraActive = false

    button._auraInstanceID = nil

    -- Per-button visibility runtime state
    button._visibilityHidden = false
    button._prevVisibilityHidden = false
    button._visibilityAlphaOverride = nil
    button._lastVisAlpha = 1
    button._groupId = parent.groupId

    -- Set icon
    self:UpdateButtonIcon(button)

    -- Methods
    button.UpdateCooldown = function(self)
        CooldownCompanion:UpdateButtonCooldown(self)
    end

    button.UpdateStyle = function(self, newStyle)
        CooldownCompanion:UpdateButtonStyle(self, newStyle)
    end

    -- Click-through is always enabled (clicks always pass through for camera movement)
    -- Motion (hover) is only enabled when tooltips are on
    local showTooltips = style.showTooltips == true
    local disableClicks = true
    local disableMotion = not showTooltips

    -- Apply to the button frame and all children recursively
    SetFrameClickThroughRecursive(button, disableClicks, disableMotion)
    -- Re-apply full click-through on overlay frames (the recursive call above
    -- re-enables motion on them when tooltips are on, causing them to steal hover events)
    SetFrameClickThroughRecursive(button.cooldown, true, true)
    SetFrameClickThroughRecursive(button.locCooldown, true, true)
    if button.procGlow then
        SetFrameClickThroughRecursive(button.procGlow.solidFrame, true, true)
        SetFrameClickThroughRecursive(button.procGlow.procFrame, true, true)
        if button.procGlow.pixelFrame then
            SetFrameClickThroughRecursive(button.procGlow.pixelFrame, true, true)
        end
    end
    if button.overlayFrame then
        SetFrameClickThroughRecursive(button.overlayFrame, true, true)
    end
    if button.assistedHighlight then
        if button.assistedHighlight.solidFrame then
            SetFrameClickThroughRecursive(button.assistedHighlight.solidFrame, true, true)
        end
        if button.assistedHighlight.blizzardFrame then
            SetFrameClickThroughRecursive(button.assistedHighlight.blizzardFrame, true, true)
        end
        if button.assistedHighlight.procFrame then
            SetFrameClickThroughRecursive(button.assistedHighlight.procFrame, true, true)
        end
    end
    if button.auraGlow then
        if button.auraGlow.solidFrame then
            SetFrameClickThroughRecursive(button.auraGlow.solidFrame, true, true)
        end
        if button.auraGlow.procFrame then
            SetFrameClickThroughRecursive(button.auraGlow.procFrame, true, true)
        end
        if button.auraGlow.pixelFrame then
            SetFrameClickThroughRecursive(button.auraGlow.pixelFrame, true, true)
        end
    end

    -- Set tooltip scripts when tooltips are enabled (regardless of click-through)
    if showTooltips then
        SetupTooltipScripts(button)
    end

    return button
end

function CooldownCompanion:UpdateButtonIcon(button)
    local buttonData = button.buttonData
    local icon
    local displayId = buttonData.id

    if buttonData.type == "spell" then
        -- Look up viewer child for current override info (icon, display name).
        -- For override spells (ability→buff mapping), viewerAuraFrames may point
        -- to a BuffIcon/BuffBar child whose spellID is the buff, not the ability.
        -- Scan for an Essential/Utility child that tracks the transforming spell.
        local child
        if buttonData.cdmChildSlot then
            local allChildren = CooldownCompanion.viewerAuraAllChildren[buttonData.id]
            child = allChildren and allChildren[buttonData.cdmChildSlot]
        else
            child = CooldownCompanion.viewerAuraFrames[buttonData.id]
        end
        if child and child.cooldownInfo then
            -- For multi-slot buttons, keep the slot-specific buff viewer child —
            -- FindCooldownViewerChild is not slot-aware and would lose differentiation.
            if not buttonData.cdmChildSlot then
                local parentName = child:GetParent() and child:GetParent():GetName()
                if parentName == "BuffIconCooldownViewer" or parentName == "BuffBarCooldownViewer" then
                    -- This is a buff viewer — look for a cooldown viewer instead for icon/name
                    local cdChild = CooldownCompanion:FindCooldownViewerChild(buttonData.id)
                    if cdChild then child = cdChild end
                end
            end
            -- Track the current override for display name and aura lookups
            if child.cooldownInfo.overrideSpellID then
                displayId = child.cooldownInfo.overrideSpellID
            end
            -- For multi-slot buttons, read the CDM's already-rendered icon texture
            -- directly from the viewer child's Icon widget. This avoids secret
            -- values (child.auraSpellID is secret in combat) and guarantees the
            -- icon matches what the CDM viewer displays.
            -- BuffIcon children: child.Icon is a Texture.
            -- BuffBar children: child.Icon is a Frame containing child.Icon.Icon.
            -- For single-child buttons, use the base spellID — GetSpellTexture on
            -- a base spell dynamically returns the current override's icon.
            if buttonData.cdmChildSlot then
                local iconTexture = child.Icon
                if iconTexture and not iconTexture.GetTextureFileID then
                    iconTexture = iconTexture.Icon
                end
                if iconTexture and iconTexture.GetTextureFileID then
                    -- GetTextureFileID may return a secret value in combat;
                    -- pass it straight through — do not test or branch on it.
                    icon = iconTexture:GetTextureFileID()
                else
                    -- No icon widget found — use spell API fallback
                    local fallbackId = child.cooldownInfo.overrideSpellID
                        or child.cooldownInfo.spellID
                    if fallbackId then
                        icon = C_Spell.GetSpellTexture(fallbackId)
                    end
                end
            else
                local baseSpellId = child.cooldownInfo.spellID
                if baseSpellId then
                    icon = C_Spell.GetSpellTexture(baseSpellId)
                end
            end
        end
        -- Fallback: if no viewer child provided an override, ask the Spell API directly
        if displayId == buttonData.id and buttonData.type == "spell" then
            local overrideId = C_Spell.GetOverrideSpell(buttonData.id)
            if overrideId and overrideId ~= buttonData.id then
                displayId = overrideId
            end
        end
        if not icon then
            icon = C_Spell.GetSpellTexture(displayId)
        end
    elseif buttonData.type == "item" then
        icon = C_Item.GetItemIconByID(buttonData.id)
    end

    local prevDisplayId = button._displaySpellId
    button._displaySpellId = displayId

    if icon then
        button.icon:SetTexture(icon)
    else
        button.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
    end

    -- Update cooldown secrecy when override spell changes (e.g. Command Demon → pet ability)
    if displayId ~= prevDisplayId and buttonData.type == "spell" then
        buttonData._cooldownSecrecy = C_Secrets.GetSpellCooldownSecrecy(displayId)
    end

    -- Update bar name text when the display spell changes (e.g. transform)
    if button.nameText and buttonData.type == "spell" and displayId ~= prevDisplayId then
        local spellName = C_Spell.GetSpellName(displayId)
        if spellName then
            button.nameText:SetText(spellName)
        end
    end
end

-- Update icon-mode visuals: GCD suppression, cooldown text, desaturation, and vertex color.
local function UpdateIconModeVisuals(button, buttonData, style, fetchOk, isOnGCD, gcdJustEnded)
    -- GCD suppression (isOnGCD is NeverSecret, always readable)
    -- Passives never suppress — always show cooldown widget for aura swipe
    if fetchOk and not buttonData.isPassive then
        local suppressGCD = not style.showGCDSwipe and isOnGCD

        if suppressGCD then
            button.cooldown:Hide()
        else
            if not button.cooldown:IsShown() then
                button.cooldown:Show()
            end
        end
    end

    -- Cooldown/aura text: pick font + visibility based on current state.
    -- Color is reapplied each tick because WoW's CooldownFrame may reset it.
    if button._cdTextRegion then
        local showText, fontColor, wantFont, wantSize, wantOutline
        if button._auraActive then
            showText = style.showAuraText ~= false
            fontColor = style.auraTextFontColor or {0, 0.925, 1, 1}
            wantFont = CooldownCompanion:FetchFont(style.auraTextFont or "Friz Quadrata TT")
            wantSize = style.auraTextFontSize or 12
            wantOutline = style.auraTextFontOutline or "OUTLINE"
        elseif buttonData.isPassive then
            -- Inactive passive aura: no text (cooldown frame hidden)
            button._cdTextRegion:SetTextColor(0, 0, 0, 0)
        else
            showText = style.showCooldownText
            fontColor = style.cooldownFontColor or {1, 1, 1, 1}
            wantFont = CooldownCompanion:FetchFont(style.cooldownFont or "Friz Quadrata TT")
            wantSize = style.cooldownFontSize or 12
            wantOutline = style.cooldownFontOutline or "OUTLINE"
        end
        if showText then
            local cc = fontColor
            button._cdTextRegion:SetTextColor(cc[1], cc[2], cc[3], cc[4])
            -- Only call SetFont when mode changes to avoid per-tick overhead
            local mode = button._auraActive and "aura" or "cd"
            if button._cdTextMode ~= mode then
                button._cdTextMode = mode
                button._cdTextRegion:SetFont(wantFont, wantSize, wantOutline)
            end
        else
            button._cdTextRegion:SetTextColor(0, 0, 0, 0)
        end
        -- Properly hide/show countdown numbers via API (alpha=0 alone is unreliable
        -- because WoW's CooldownFrame animation resets text color each tick)
        local wantHide = not showText
        if button._cdTextHidden ~= wantHide then
            button._cdTextHidden = wantHide
            button.cooldown:SetHideCountdownNumbers(wantHide)
        end
    end

    -- Desaturation: aura-tracked buttons desaturate when aura absent;
    -- cooldown buttons desaturate based on DurationObject / item CD state.
    if buttonData.auraTracking then
        local wantDesat
        if buttonData.isPassive then
            wantDesat = not button._auraActive
        else
            wantDesat = buttonData.desaturateWhileAuraNotActive and not button._auraActive
        end
        if not wantDesat and not button._auraActive
            and style.desaturateOnCooldown and fetchOk and not isOnGCD and not gcdJustEnded then
            if buttonData.hasCharges then
                if buttonData.type == "item" then
                    wantDesat = button._itemCdDuration and button._itemCdDuration > 0
                else
                    wantDesat = button._mainCDShown
                end
            elseif button._durationObj then
                wantDesat = true
            elseif buttonData.type == "item" then
                wantDesat = button._itemCdDuration and button._itemCdDuration > 0
            end
        end
        if not wantDesat and button._isEquippableNotEquipped then
            wantDesat = true
        end
        if button._desaturated ~= wantDesat then
            button._desaturated = wantDesat
            button.icon:SetDesaturated(wantDesat)
        end
    elseif style.desaturateOnCooldown or buttonData.desaturateWhileZeroCharges
        or buttonData.desaturateWhileZeroStacks or button._isEquippableNotEquipped then
        local wantDesat = false
        if style.desaturateOnCooldown and fetchOk and not isOnGCD and not gcdJustEnded then
            if buttonData.hasCharges then
                if buttonData.type == "item" then
                    wantDesat = button._itemCdDuration and button._itemCdDuration > 0
                else
                    wantDesat = button._mainCDShown
                end
            elseif button._durationObj then
                wantDesat = true
            elseif buttonData.type == "item" then
                wantDesat = button._itemCdDuration and button._itemCdDuration > 0
            end
        end
        if not wantDesat and buttonData.desaturateWhileZeroCharges and button._mainCDShown then
            wantDesat = true
        end
        if not wantDesat and buttonData.desaturateWhileZeroStacks and (button._itemCount or 0) == 0 then
            wantDesat = true
        end
        if not wantDesat and button._isEquippableNotEquipped then
            wantDesat = true
        end
        if button._desaturated ~= wantDesat then
            button._desaturated = wantDesat
            button.icon:SetDesaturated(wantDesat)
        end
    else
        if button._desaturated ~= false then
            button._desaturated = false
            button.icon:SetDesaturated(false)
        end
    end

    UpdateIconTint(button, buttonData, style)
end

-- Update icon-mode glow effects: loss of control, assisted highlight, proc glow, aura glow.
local function UpdateIconModeGlows(button, buttonData, style)
    -- Loss of control overlay
    UpdateLossOfControl(button)

    -- Assisted highlight glow
    if button.assistedHighlight then
        local assistedSpellID = CooldownCompanion.assistedSpellID
        local displayId = button._displaySpellId or buttonData.id
        local showHighlight = style.showAssistedHighlight
            and buttonData.type == "spell"
            and assistedSpellID
            and (displayId == assistedSpellID
                 or buttonData.id == assistedSpellID
                 or C_Spell.GetOverrideSpell(buttonData.id) == assistedSpellID)

        SetAssistedHighlight(button, showHighlight)
    end

    -- Proc glow (spell activation overlay)
    if button.procGlow then
        local showProc = false
        if button._procGlowPreview then
            showProc = true
        elseif style.procGlowStyle ~= "none" and buttonData.type == "spell"
               and not buttonData.isPassive and not buttonData.auraTracking then
            showProc = CooldownCompanion.procOverlaySpells[buttonData.id] or false
        end
        SetProcGlow(button, showProc)
    end

    -- Aura active glow indicator
    if button.auraGlow then
        local showAuraGlow = false
        local pandemicOverride = false
        if button._pandemicPreview then
            showAuraGlow = true
            pandemicOverride = true
        elseif button._auraGlowPreview then
            showAuraGlow = true
        elseif button._auraActive then
            if button._inPandemic and style.showPandemicGlow ~= false then
                showAuraGlow = true
                pandemicOverride = true
            elseif buttonData.auraIndicatorEnabled or style.auraGlowStyle ~= "none" then
                showAuraGlow = true
            end
        end
        SetAuraGlow(button, showAuraGlow, pandemicOverride)
    end
end

function CooldownCompanion:UpdateButtonStyle(button, style)
    local width, height

    if style.maintainAspectRatio then
        -- Square mode: use buttonSize for both dimensions
        local size = style.buttonSize or ST.BUTTON_SIZE
        width = size
        height = size
    else
        -- Non-square mode: use separate width/height
        width = style.iconWidth or style.buttonSize or ST.BUTTON_SIZE
        height = style.iconHeight or style.buttonSize or ST.BUTTON_SIZE
    end

    local borderSize = style.borderSize or ST.DEFAULT_BORDER_SIZE

    -- Store updated style reference
    button.style = style

    -- Invalidate cached widget state so next tick reapplies everything
    button._desaturated = nil
    button._vertexR = nil
    button._vertexG = nil
    button._vertexB = nil
    button._chargeText = nil
    button._nilConfirmPending = nil
    button._procGlowActive = nil
    button._auraGlowActive = nil
    button._displaySpellId = nil
    button._spellOutOfRange = nil
    button._itemCount = nil
    button._auraActive = nil

    button._auraInstanceID = nil
    button._inPandemic = nil
    button._auraSpellID = CooldownCompanion:ResolveAuraSpellID(button.buttonData)
    button._auraUnit = button.buttonData.auraUnit or "player"
    button._auraStackText = nil
    if button.auraStackCount then button.auraStackCount:SetText("") end
    button._visibilityHidden = false
    button._prevVisibilityHidden = false
    button._visibilityAlphaOverride = nil
    button._lastVisAlpha = 1

    button:SetSize(width, height)

    -- Update icon position
    button.icon:ClearAllPoints()
    button.icon:SetPoint("TOPLEFT", borderSize, -borderSize)
    button.icon:SetPoint("BOTTOMRIGHT", -borderSize, borderSize)

    ApplyIconTexCoord(button.icon, width, height)

    -- Update border textures
    local borderColor = style.borderColor or {0, 0, 0, 1}
    if button.borderTextures then
        ApplyEdgePositions(button.borderTextures, button, borderSize)
        for _, tex in ipairs(button.borderTextures) do
            tex:SetColorTexture(unpack(borderColor))
        end
    end

    local bgColor = style.backgroundColor or {0, 0, 0, 0.5}
    button.bg:SetColorTexture(unpack(bgColor))

    -- Countdown number visibility is controlled per-tick via SetHideCountdownNumbers
    button.cooldown:SetHideCountdownNumbers(false)
    local swipeEnabled = style.showCooldownSwipe ~= false
    button.cooldown:SetDrawSwipe(swipeEnabled)
    button.cooldown:SetDrawEdge(swipeEnabled and style.showCooldownSwipeEdge ~= false)
    button.cooldown:SetReverse(swipeEnabled and (style.cooldownSwipeReverse or false))

    -- Update cooldown font settings (default state; per-tick logic handles aura mode)
    local cooldownFont = CooldownCompanion:FetchFont(style.cooldownFont or "Friz Quadrata TT")
    local cooldownFontSize = style.cooldownFontSize or 12
    local cooldownFontOutline = style.cooldownFontOutline or "OUTLINE"
    local region = button.cooldown:GetRegions()
    if region and region.SetFont then
        region:SetFont(cooldownFont, cooldownFontSize, cooldownFontOutline)
        local cdColor = style.cooldownFontColor or {1, 1, 1, 1}
        region:SetTextColor(cdColor[1], cdColor[2], cdColor[3], cdColor[4])
        region:ClearAllPoints()
        local cdAnchor = style.cooldownTextAnchor or "CENTER"
        local cdXOff = style.cooldownTextXOffset or 0
        local cdYOff = style.cooldownTextYOffset or 0
        region:SetPoint(cdAnchor, cdXOff, cdYOff)
    end
    -- Clear cached text mode so per-tick logic re-applies the correct font
    button._cdTextMode = nil
    button._cdTextHidden = nil

    -- Update count text font/anchor settings from effective style
    button.count:ClearAllPoints()
    if button.buttonData and (button.buttonData.hasCharges or button.buttonData.isPassive) then
        local chargeFont = CooldownCompanion:FetchFont(style.chargeFont or "Friz Quadrata TT")
        local chargeFontSize = style.chargeFontSize or 12
        local chargeFontOutline = style.chargeFontOutline or "OUTLINE"
        button.count:SetFont(chargeFont, chargeFontSize, chargeFontOutline)
        local chColor = style.chargeFontColor or {1, 1, 1, 1}
        button.count:SetTextColor(chColor[1], chColor[2], chColor[3], chColor[4])

        local chargeAnchor = style.chargeAnchor or "BOTTOMRIGHT"
        local chargeXOffset = style.chargeXOffset or -2
        local chargeYOffset = style.chargeYOffset or 2
        button.count:SetPoint(chargeAnchor, chargeXOffset, chargeYOffset)
    elseif button.buttonData and button.buttonData.type == "item"
       and not IsItemEquippable(button.buttonData) then
        local itemFont = CooldownCompanion:FetchFont(button.buttonData.itemCountFont or "Friz Quadrata TT")
        local itemFontSize = button.buttonData.itemCountFontSize or 12
        local itemFontOutline = button.buttonData.itemCountFontOutline or "OUTLINE"
        button.count:SetFont(itemFont, itemFontSize, itemFontOutline)
        local icColor = button.buttonData.itemCountFontColor or {1, 1, 1, 1}
        button.count:SetTextColor(icColor[1], icColor[2], icColor[3], icColor[4])

        local itemAnchor = button.buttonData.itemCountAnchor or "BOTTOMRIGHT"
        local itemXOffset = button.buttonData.itemCountXOffset or -2
        local itemYOffset = button.buttonData.itemCountYOffset or 2
        button.count:SetPoint(itemAnchor, itemXOffset, itemYOffset)
    else
        button.count:SetPoint("BOTTOMRIGHT", -2, 2)
    end

    -- Update aura stack count font/anchor settings
    if button.auraStackCount then
        button.auraStackCount:ClearAllPoints()
        local asFont = CooldownCompanion:FetchFont(style.auraStackFont or "Friz Quadrata TT")
        local asFontSize = style.auraStackFontSize or 12
        local asFontOutline = style.auraStackFontOutline or "OUTLINE"
        button.auraStackCount:SetFont(asFont, asFontSize, asFontOutline)
        local asColor = style.auraStackFontColor or {1, 1, 1, 1}
        button.auraStackCount:SetTextColor(asColor[1], asColor[2], asColor[3], asColor[4])
        local asAnchor = style.auraStackAnchor or "BOTTOMLEFT"
        local asXOff = style.auraStackXOffset or 2
        local asYOff = style.auraStackYOffset or 2
        button.auraStackCount:SetPoint(asAnchor, asXOff, asYOff)
    end

    -- Update keybind text overlay
    if button.keybindText then
        local kbFont = CooldownCompanion:FetchFont(style.keybindFont or "Friz Quadrata TT")
        local kbSize = style.keybindFontSize or 10
        local kbOutline = style.keybindFontOutline or "OUTLINE"
        button.keybindText:SetFont(kbFont, kbSize, kbOutline)
        local kbColor = style.keybindFontColor or {1, 1, 1, 1}
        button.keybindText:SetTextColor(kbColor[1], kbColor[2], kbColor[3], kbColor[4])
        button.keybindText:ClearAllPoints()
        local anchor = style.keybindAnchor or "TOPRIGHT"
        local xOff = style.keybindXOffset or -2
        local yOff = style.keybindYOffset or -2
        button.keybindText:SetPoint(anchor, xOff, yOff)
        local text = CooldownCompanion:GetKeybindText(button.buttonData)
        button.keybindText:SetText(text or "")
        button.keybindText:SetShown(style.showKeybindText and text ~= nil)
    end

    -- Update highlight overlay positions and hide all
    if button.assistedHighlight then
        local highlightSize = style.assistedHighlightBorderSize or 2
        ApplyEdgePositions(button.assistedHighlight.solidTextures, button, highlightSize)
        if button.assistedHighlight.blizzardFrame then
            FitHighlightFrame(button.assistedHighlight.blizzardFrame, button, style.assistedHighlightBlizzardOverhang)
        end
        if button.assistedHighlight.procFrame then
            FitHighlightFrame(button.assistedHighlight.procFrame, button, style.assistedHighlightProcOverhang)
        end
        button.assistedHighlight.currentState = nil -- reset so next tick re-applies
        SetAssistedHighlight(button, false)
    end

    -- Update loss of control cooldown frame
    if button.locCooldown then
        button.locCooldown:SetSwipeColor(0.17, 0, 0, 0.8)
        button.locCooldown:Clear()
    end

    -- Update proc glow frames
    if button.procGlow then
        button.procGlow.solidFrame:SetAllPoints()
        ApplyEdgePositions(button.procGlow.solidTextures, button, style.procGlowSize or 2)
        FitHighlightFrame(button.procGlow.procFrame, button, style.procGlowSize or 32)
        if button.procGlow.pixelFrame then
            button.procGlow.pixelFrame:SetAllPoints()
        end
        SetProcGlow(button, false)
    end

    -- Update aura glow frames
    if button.auraGlow then
        button.auraGlow.solidFrame:SetAllPoints()
        ApplyEdgePositions(button.auraGlow.solidTextures, button, button.style.auraGlowSize or 2)
        FitHighlightFrame(button.auraGlow.procFrame, button, button.style.auraGlowSize or 32)
        if button.auraGlow.pixelFrame then
            button.auraGlow.pixelFrame:SetAllPoints()
        end
        SetAuraGlow(button, false)
    end

    -- Apply configurable strata ordering (LoC always on top)
    ApplyStrataOrder(button, style.strataOrder)

    -- Click-through is always enabled (clicks always pass through for camera movement)
    -- Motion (hover) is only enabled when tooltips are on
    local showTooltips = style.showTooltips == true
    local disableClicks = true
    local disableMotion = not showTooltips

    -- Apply to the button frame and all children recursively
    SetFrameClickThroughRecursive(button, disableClicks, disableMotion)
    -- Re-apply full click-through on overlay frames (the recursive call above
    -- re-enables motion on them when tooltips are on, causing them to steal hover events)
    SetFrameClickThroughRecursive(button.cooldown, true, true)
    SetFrameClickThroughRecursive(button.locCooldown, true, true)
    if button.procGlow then
        SetFrameClickThroughRecursive(button.procGlow.solidFrame, true, true)
        SetFrameClickThroughRecursive(button.procGlow.procFrame, true, true)
        if button.procGlow.pixelFrame then
            SetFrameClickThroughRecursive(button.procGlow.pixelFrame, true, true)
        end
    end
    if button.overlayFrame then
        SetFrameClickThroughRecursive(button.overlayFrame, true, true)
    end
    if button.assistedHighlight then
        if button.assistedHighlight.solidFrame then
            SetFrameClickThroughRecursive(button.assistedHighlight.solidFrame, true, true)
        end
        if button.assistedHighlight.blizzardFrame then
            SetFrameClickThroughRecursive(button.assistedHighlight.blizzardFrame, true, true)
        end
        if button.assistedHighlight.procFrame then
            SetFrameClickThroughRecursive(button.assistedHighlight.procFrame, true, true)
        end
    end
    if button.auraGlow then
        if button.auraGlow.solidFrame then
            SetFrameClickThroughRecursive(button.auraGlow.solidFrame, true, true)
        end
        if button.auraGlow.procFrame then
            SetFrameClickThroughRecursive(button.auraGlow.procFrame, true, true)
        end
        if button.auraGlow.pixelFrame then
            SetFrameClickThroughRecursive(button.auraGlow.pixelFrame, true, true)
        end
    end

    -- Re-set aura glow frame levels after strata order
    if button.auraGlow then
        local auraGlowLevel = button.cooldown:GetFrameLevel() + 1
        button.auraGlow.solidFrame:SetFrameLevel(auraGlowLevel)
        button.auraGlow.procFrame:SetFrameLevel(auraGlowLevel)
        button.auraGlow.pixelFrame:SetFrameLevel(auraGlowLevel)
    end

    -- Set tooltip scripts when tooltips are enabled (regardless of click-through)
    if showTooltips then
        button:SetScript("OnEnter", function(self)
            GameTooltip_SetDefaultAnchor(GameTooltip, UIParent)
            if self.buttonData.type == "spell" then
                GameTooltip:SetSpellByID(self._displaySpellId or self.buttonData.id)
            elseif self.buttonData.type == "item" then
                GameTooltip:SetItemByID(self.buttonData.id)
            end
            GameTooltip:Show()
        end)
        button:SetScript("OnLeave", function(self)
            GameTooltip:Hide()
        end)
    end
end

-- Exports
ST._UpdateIconModeVisuals = UpdateIconModeVisuals
ST._UpdateIconModeGlows = UpdateIconModeGlows
