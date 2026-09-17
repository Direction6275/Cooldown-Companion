-- Bar composition is chosen from entry identity, never live aura activity.
local _, ST = ...
local Addon = ST.Addon
local Layers = {}
ST.BarLayers = Layers

function Layers.HasPersistentAuraName(entry, customBar)
    return entry and entry.addedAs == "aura" and (customBar or entry.isPassive == true)
        and not Addon:IsAuraShellEntry(entry)
end

function Layers.IsUncoveredAura(button, entry)
    return button._isBar == true
        and button._ccAuraHostKind ~= "auraPanel"
        and Layers.HasPersistentAuraName(entry, button._ccAuraHostKind == "customBar")
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
