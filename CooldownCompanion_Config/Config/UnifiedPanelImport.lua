-- Normalize supported legacy bar payloads before the ordinary import review.
local _, ST = ...
local Addon, Migration = ST.Addon, ST.UnifiedPanelMigration
local LibDeflate = LibStub("LibDeflate")

function ST._ConvertUnifiedPanelImport(data)
    local context = Addon:GetUnifiedPanelConversionContext()
    context.defaultClass = nil -- An export must identify its own class.
    local canonical = Migration.Fingerprint(data)
    context.originPrefix = ("import:%d:%08x:"):format(#canonical, LibDeflate:Adler32(canonical))
    return Migration.ConvertImport(data, context)
end

-- Normal imports remain additive. Converted legacy entries carry their
-- source identity so replaying an old import cannot multiply migrated bars.
function ST._FilterConvertedPanelImport(data)
    if type(data) ~= "table" or not data.type then return data end
    local existing = {}
    for groupId, group in pairs(Addon.db.profile.groups or {}) do
        for _, entry in ipairs(group.buttons or {}) do
            local key = entry._legacyBarImportKey
            if key and (not existing[key] or groupId < existing[key]) then existing[key] = groupId end
        end
    end
    local result = CopyTable(data)
    local existingPanelIds = {}
    local function FilterPacket(packet)
        local panels, removed = {}, false
        for _, panel in ipairs(packet.panels or {}) do
            local entries, dropped, destinations = {}, false, {}
            for _, entry in ipairs(panel.buttons or {}) do
                local destination = entry._legacyBarImportKey and existing[entry._legacyBarImportKey]
                if destination then
                    dropped = true
                    destinations[destination] = (destinations[destination] or 0) + 1
                else entries[#entries + 1] = entry end
            end
            panel.buttons = entries
            if dropped and #entries == 0 then
                removed = true
                -- Retain attachment targets even when no new panel is needed.
                -- If the user split the entries, prefer the panel containing
                -- most of them; stable IDs break ties deterministically.
                local target, matches
                for id, count in pairs(destinations) do
                    if not matches or count > matches or (count == matches and id < target) then
                        target, matches = id, count
                    end
                end
                local sourceId = tonumber(panel._originalGroupId)
                if sourceId then existingPanelIds[sourceId] = target end
            else panels[#panels + 1] = panel end
        end
        packet.panels = panels
        return not (removed and #panels == 0)
    end
    if result.containers then
        local packets = {}
        for _, packet in ipairs(result.containers) do if FilterPacket(packet) then packets[#packets + 1] = packet end end
        result.containers = packets
    elseif result.container and not FilterPacket(result) then
        result.type, result.container, result.panels, result.containers = "containers", nil, nil, {}
    end
    return result, existingPanelIds
end
