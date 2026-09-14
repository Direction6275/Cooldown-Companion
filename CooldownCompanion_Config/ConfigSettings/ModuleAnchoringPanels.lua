local _, ST = ...
local Addon = ST.Addon

local function AddHelp(row, title, text)
    ST._AnchorRowBadge(row, ST._CreateInfoButton(row.frame, row.frame, "LEFT", "LEFT", 0, 0,
        { title, { text, 1, 1, 1, true } }, row))
end

-- Shared module controls deliberately do not reuse the panel-to-panel picker:
-- that picker filters automatic group eligibility and requires live frames.
function ST._BuildModuleAnchoringControls(container, kind, finder)
    finder = finder or {}
    local list, order = ST._GetBarAttachmentOptions(kind)
    local modeRow = ST._AddDropdownRow(container, {
        label = "Anchoring Mode", setting = finder.mode,
        list = list, order = order, value = ST._GetBarAttachmentValue(kind),
        onChange = function(mode) ST._SetBarAttachment(kind, mode) end,
    })
    AddHelp(modeRow, "Anchoring Mode", "Saved for this specialization. Automatic uses the first eligible panel. Choose Panel temporarily uses Automatic when your selected panel is unavailable, then returns when it becomes available.")
    local attachment = Addon:GetModuleAttachment(kind)
    if attachment.mode == "panel" then
        local choices, keys, headers, containers = {}, {}, {}, {}
        for cid, group in pairs(Addon.db.profile.groupContainers or {}) do
            containers[#containers + 1] = { id = cid, group = group,
                order = Addon:GetOrderForSpec(group, Addon._currentSpecId, cid) }
        end
        table.sort(containers, function(a, b)
            if a.order ~= b.order then return a.order < b.order end
            local ai, bi = tonumber(a.id), tonumber(b.id)
            if ai and bi and ai ~= bi then return ai < bi end
            return tostring(a.id) < tostring(b.id)
        end)
        for _, containerInfo in ipairs(containers) do
            local header = "group:" .. containerInfo.id
            local added = false
            for _, entry in ipairs(Addon:GetPanels(containerInfo.id)) do
                local id, panel = entry.groupId, entry.group
                if Addon:CanModuleAnchorToPanel(id) and Addon:IsGroupVisibleToCurrentChar(id) then
                    if not added then
                        choices[header] = "|cffffd100" .. (containerInfo.group.name or "Group") .. "|r"
                        keys[#keys + 1], headers[#headers + 1] = header, header
                        added = true
                    end
                    local key = tostring(id)
                    local active = Addon:IsGroupActive(id, { checkCharVisibility = true, checkLoadConditions = true })
                    local frame = Addon.groupFrames and Addon.groupFrames[id]
                    local available = active and frame and frame:IsShown()
                    choices[key] = "   " .. (panel.name or ("Panel " .. key)) .. (available and "" or " (unavailable)")
                    keys[#keys + 1] = key
                end
            end
        end
        local selected = attachment.panelId and tostring(attachment.panelId) or "missing"
        if not choices[selected] then
            choices[selected] = attachment.panelId and "Unavailable panel" or "Choose a panel"
            table.insert(keys, 1, selected)
            headers[#headers + 1] = selected
        end
        local row = ST._AddDropdownRow(container, {
            label = "Anchor Panel", setting = finder.panel,
            list = choices, order = keys, value = selected, pulloutWidth = 300,
            onChange = function(value)
                if tonumber(value) then ST._SetBarAttachment(kind, "panel", tonumber(value)) end
            end,
        })
        AddHelp(row, "Anchor Panel", "Explicit selections ignore Include in Auto-Anchoring. Aura Panels, cursor-attached panels, and non-icon panels cannot be selected.")
        for _, key in ipairs(headers) do row.dropdown:SetItemDisabled(key, true) end
    end
    local target = Addon:ResolveModulePanel(kind)
    local status = Addon:GetModuleAnchorStatusText(target, kind)
    if status then
        local label = LibStub("AceGUI-3.0"):Create("Label")
        ST._ConfigureWrappedHelperLabel(label)
        label:SetText(status)
        label:SetFullWidth(true)
        container:AddChild(label)
    end
end
