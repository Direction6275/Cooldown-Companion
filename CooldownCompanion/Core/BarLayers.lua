-- Bar composition is chosen from entry identity, never live aura activity.
local _, ST = ...
local Addon = ST.Addon
local Layers = {}
ST.BarLayers = Layers

function Layers.HasPersistentAuraName(entry)
    return entry and entry.addedAs == "aura" and entry.isPassive == true
        and not Addon:IsAuraShellEntry(entry)
end

function Layers.IsUncoveredAura(button, entry)
    return button._isBar == true
        and button._ccAuraHostKind ~= "auraPanel"
        and Layers.HasPersistentAuraName(entry)
end

-- Final background opacity and the aura layer's contribution. The base and
-- aura backgrounds have the same RGB. Account for the dimmed base using
-- source-over alpha: combined = overlay + base * (1 - overlay).
-- Only a visible spell fill requires an opaque cover. Use saved resting
-- opacity: Arrange Mode can end in combat, when the bound aura layer cannot
-- be restyled. Temporary preview exposure must not change its contribution.
function Layers.GetAuraBackgroundAlpha(entry, style, hostKind)
    local bg = style.barBgColor
    local configuredAlpha = bg and (bg[4] or 1) or 0.8
    local native = hostKind == "auraPanel"
    local auraOnly = native or (entry and entry.addedAs == "aura"
        and entry.isPassive == true)
    local baseVisualAlpha = native and 0 or (Addon:IsAuraShellEntry(entry)
        and Addon:GetAuraShellRestingAlpha(entry) or 1)
    if not auraOnly and baseVisualAlpha > 0 then
        return 1, 1
    end
    local baseAlpha = configuredAlpha * baseVisualAlpha
    if baseAlpha >= configuredAlpha then
        return configuredAlpha, 0
    end
    return configuredAlpha, (configuredAlpha - baseAlpha) / (1 - baseAlpha)
end

-- Sole owner of ordinary bars' text and aura-mount levels. The stable CC
-- statusBar is the base; deriving the mount from a raised name would make
-- every restyle/rebind lift the whole stack again. No aura-child reads.
function Layers.Apply(button)
    if not button.barTextFrame then return end
    local base = button.statusBar:GetFrameLevel()
    button.barTextFrame:SetFrameLevel(base + 20)
    if button.auraLayer then
        -- A mount-level write cascades into native children. Use the same
        -- combat AND aura-secrecy gate as their existing binding lifecycle.
        if Addon:CanRunAuraRebindNow() then
            button.auraLayer:SetFrameLevel(base + 21)
            button._barAuraLayerOwner, button._barAuraLayerBase = button.auraLayer, base
        elseif button._barAuraLayerOwner ~= button.auraLayer or button._barAuraLayerBase ~= base then
            -- Geometry-only restyles do not change this composition. Remember
            -- our last safe write; never read restricted native descendants.
            Addon:RequestAuraRebind("bar-layers")
        end
    end
    if button.barNameFrame then
        -- Spell names belong under the opaque aura cover. Pure Aura names
        -- remain above its fill; native shells keep their own active label.
        local foreground = Layers.IsUncoveredAura(button, button.buttonData)
        button.barNameFrame:SetFrameLevel(base + (foreground and 31 or 20))
    end
    if button.overlayFrame then button.overlayFrame:SetFrameLevel(base + 31) end
end
