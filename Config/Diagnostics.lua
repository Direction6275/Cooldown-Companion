--[[
    CooldownCompanion - Config/Diagnostics
    Diagnostic snapshot system (bug report generation + decode panel).
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon
local CS = ST._configState

local AceGUI = LibStub("AceGUI-3.0")
local AceSerializer = LibStub("AceSerializer-3.0")
local LibDeflate = LibStub("LibDeflate")

-- File-local state
local decodedDiagnostic = nil
local diagnosticDecodeFrame = nil

local RESOURCE_NAMES = {
    [0] = "Mana", [1] = "Rage", [2] = "Focus", [3] = "Energy",
    [4] = "Combo Points", [5] = "Runes", [6] = "Runic Power",
    [7] = "Soul Shards", [8] = "Lunar Power", [9] = "Holy Power",
    [10] = "Alternate", [11] = "Maelstrom", [12] = "Chi",
    [13] = "Insanity", [16] = "Arcane Charges", [17] = "Fury",
    [18] = "Pain", [19] = "Essence", [100] = "Maelstrom Weapon",
}

local function BuildDiagnosticSnapshot()
    local db = CooldownCompanion.db
    local snapshot = { _v = 1 }

    -- Meta
    local _, classFilename, classID = UnitClass("player")
    local specIndex = C_SpecializationInfo.GetSpecialization()
    local specID, specName
    if specIndex then
        specID, specName = C_SpecializationInfo.GetSpecializationInfo(specIndex)
    end
    local buildVersion, _, _, interfaceVersion = GetBuildInfo()
    local addonVersion = C_AddOns.GetAddOnMetadata(ADDON_NAME, "Version") or "unknown"

    local totalButtons = 0
    local groupCount = 0
    for _, group in pairs(db.profile.groups) do
        groupCount = groupCount + 1
        if group.buttons then
            totalButtons = totalButtons + #group.buttons
        end
    end

    local charName = UnitName("player")

    snapshot.meta = {
        addonVersion = addonVersion,
        buildVersion = buildVersion,
        interfaceVersion = interfaceVersion,
        locale = GetLocale(),
        charName = charName,
        className = classFilename,
        classID = classID,
        specID = specID,
        specName = specName,
        realmName = GetRealmName(),
        timestamp = date("%Y-%m-%d %H:%M:%S"),
        groupCount = groupCount,
        totalButtons = totalButtons,
        instanceType = CooldownCompanion._currentInstanceType,
    }

    -- Runtime
    local viewerAuraSpells = {}
    for spellID in pairs(CooldownCompanion.viewerAuraFrames) do
        viewerAuraSpells[#viewerAuraSpells + 1] = spellID
    end
    table.sort(viewerAuraSpells)

    local procOverlaySpells = {}
    for spellID in pairs(CooldownCompanion.procOverlaySpells) do
        procOverlaySpells[#procOverlaySpells + 1] = spellID
    end
    table.sort(procOverlaySpells)

    local rangeCheckSpells = {}
    for spellID in pairs(CooldownCompanion._rangeCheckSpells) do
        rangeCheckSpells[#rangeCheckSpells + 1] = spellID
    end
    table.sort(rangeCheckSpells)

    local groupFrameStates = {}
    for groupId, frame in pairs(CooldownCompanion.groupFrames) do
        groupFrameStates[tostring(groupId)] = {
            exists = true,
            shown = frame:IsShown(),
        }
    end

    snapshot.runtime = {
        currentInstanceType = CooldownCompanion._currentInstanceType,
        currentSpecId = CooldownCompanion._currentSpecId,
        currentHeroSpecId = CooldownCompanion._currentHeroSpecId,
        isResting = CooldownCompanion._isResting,
        cdmHidden = db.profile.cdmHidden,
        assistedSpellID = CooldownCompanion.assistedSpellID,
        viewerAuraSpells = viewerAuraSpells,
        procOverlaySpells = procOverlaySpells,
        rangeCheckSpells = rangeCheckSpells,
        groupFrameStates = groupFrameStates,
    }

    -- Build spec name cache for all referenced spec IDs
    local specNameCache = {}
    for _, group in pairs(db.profile.groups) do
        if group.specs then
            for _, sid in ipairs(group.specs) do
                if not specNameCache[sid] then
                    specNameCache[sid] = GetSpecializationNameForSpecID(sid) or nil
                end
            end
        end
    end
    if db.profile.resourceBars and db.profile.resourceBars.customAuraBars then
        for sid in pairs(db.profile.resourceBars.customAuraBars) do
            if sid ~= 0 and not specNameCache[sid] then
                specNameCache[sid] = GetSpecializationNameForSpecID(sid) or nil
            end
        end
    end
    snapshot.meta.specNameCache = specNameCache

    -- Profile (full copy, same as profile export)
    snapshot.profile = db.profile

    return snapshot
end

local function FormatDiagnosticAsText(diag)
    local lines = {}
    local function add(s) lines[#lines + 1] = s end

    local function formatValue(v)
        if type(v) ~= "table" then return tostring(v) end
        local n = 0
        for _ in pairs(v) do n = n + 1 end
        if n == 0 then return "{}" end
        if n > 10 then return "{" .. n .. " entries}" end
        if #v > 0 and #v == n then
            local parts = {}
            for _, val in ipairs(v) do parts[#parts + 1] = tostring(val) end
            return "{" .. table.concat(parts, ",") .. "}"
        else
            local parts = {}
            for k, val in pairs(v) do
                parts[#parts + 1] = tostring(k) .. "=" .. tostring(val)
            end
            table.sort(parts)
            return "{" .. table.concat(parts, ", ") .. "}"
        end
    end

    local function dumpKV(t)
        local parts = {}
        for k, v in pairs(t) do
            parts[#parts + 1] = tostring(k) .. "=" .. formatValue(v)
        end
        table.sort(parts)
        return table.concat(parts, " ")
    end

    -- Explicitly include nil-valued keys that are important for debugging
    local function dumpKVWithNils(t, importantKeys)
        local parts = {}
        local seen = {}
        for k, v in pairs(t) do
            seen[k] = true
            parts[#parts + 1] = tostring(k) .. "=" .. formatValue(v)
        end
        if importantKeys then
            for _, k in ipairs(importantKeys) do
                if not seen[k] then
                    parts[#parts + 1] = k .. "=nil"
                end
            end
        end
        table.sort(parts)
        return table.concat(parts, " ")
    end

    local m = diag.meta or {}
    local r = diag.runtime or {}
    local p = diag.profile or {}
    local specNames = m.specNameCache or {}

    -- Build viewer aura set for cross-referencing with buttons
    local viewerAuraSet = {}
    if r.viewerAuraSpells then
        for _, sid in ipairs(r.viewerAuraSpells) do
            viewerAuraSet[sid] = true
        end
    end

    -- Build group visibility map from runtime groupFrameStates
    local groupFrameVisible = {}  -- [groupId number] = true/false, nil = no frame
    if r.groupFrameStates then
        for id, state in pairs(r.groupFrameStates) do
            groupFrameVisible[tonumber(id)] = state.shown
        end
    end

    -- Header
    add(("=== CDC BUG REPORT (v%s) ==="):format(tostring(diag._v or "?")))
    add(("Addon: %s | WoW: %s (%s) | Locale: %s"):format(
        tostring(m.addonVersion or "?"), tostring(m.buildVersion or "?"),
        tostring(m.interfaceVersion or "?"), tostring(m.locale or "?")))
    add(("Character: %s - %s | %s %s (class:%s spec:%s)"):format(
        tostring(m.charName or "?"), tostring(m.realmName or "?"),
        tostring(m.specName or "?"), tostring(m.className or "?"),
        tostring(m.classID or "?"), tostring(m.specID or "?")))
    add(("Instance: %s | Resting: %s | CDM Hidden: %s"):format(
        tostring(m.instanceType or "?"), tostring(r.isResting), tostring(r.cdmHidden)))
    add(("Timestamp: %s"):format(tostring(m.timestamp or "?")))
    add(("Groups: %s | Total Buttons: %s"):format(
        tostring(m.groupCount or "?"), tostring(m.totalButtons or "?")))

    -- Runtime
    add("")
    add("--- Runtime ---")
    add(("Cached Spec ID: %s"):format(tostring(r.currentSpecId or "nil")))
    add(("Assisted Spell: %s"):format(tostring(r.assistedSpellID or "none")))

    local function formatIDList(t)
        if not t or #t == 0 then return "none" end
        local parts = {}
        for _, v in ipairs(t) do parts[#parts + 1] = tostring(v) end
        return table.concat(parts, ", ")
    end

    add(("Viewer Aura Spells: %s"):format(formatIDList(r.viewerAuraSpells)))
    add(("Proc Overlay Spells: %s"):format(formatIDList(r.procOverlaySpells)))
    add(("Range Check Spells: %s"):format(formatIDList(r.rangeCheckSpells)))

    if r.groupFrameStates then
        local parts = {}
        local ids = {}
        for id in pairs(r.groupFrameStates) do ids[#ids + 1] = id end
        table.sort(ids, function(a, b) return tonumber(a) < tonumber(b) end)
        for _, id in ipairs(ids) do
            local state = r.groupFrameStates[id]
            parts[#parts + 1] = ("[%s] %s"):format(id, state.shown and "shown" or "hidden")
        end
        add("Group Frame States:")
        add("  " .. (#parts > 0 and table.concat(parts, "  ") or "none"))
    end

    -- Groups (sorted by display order, not ID)
    add("")
    add("--- Groups ---")
    if p.groups then
        local groupIds = {}
        for id in pairs(p.groups) do groupIds[#groupIds + 1] = id end
        table.sort(groupIds, function(a, b)
            local oa = p.groups[a] and p.groups[a].order or 999
            local ob = p.groups[b] and p.groups[b].order or 999
            if oa ~= ob then return oa < ob end
            return a < b
        end)

        for _, gid in ipairs(groupIds) do
            local g = p.groups[gid]

            -- Specs display: nil = no filter, {} = all specs, {71,72} = specific
            local specStr
            if not g.specs then
                specStr = "nil (no filter)"
            elseif #g.specs == 0 then
                specStr = "all"
            else
                local ss = {}
                for _, s in ipairs(g.specs) do
                    local name = specNames[s]
                    ss[#ss + 1] = name and (tostring(s) .. "(" .. name .. ")") or tostring(s)
                end
                specStr = table.concat(ss, ", ")
            end

            -- Visibility status from runtime frame states
            local visStr
            if groupFrameVisible[gid] == true then
                visStr = "VISIBLE"
            elseif groupFrameVisible[gid] == false then
                visStr = "HIDDEN"
            else
                visStr = "NO FRAME"
            end

            local btnCount = g.buttons and #g.buttons or 0

            -- Group header with all key info on one line
            add(("[%d] %q | %s | %s | %s | %d buttons | specs: %s"):format(
                gid, g.name or "?",
                g.displayMode or "icons",
                g.enabled ~= false and "enabled" or "DISABLED",
                visStr,
                btnCount,
                specStr))

            -- Anchor
            local a = g.anchor
            if a then
                add(("  anchor: %s > %s > %s (%.1f, %.1f)"):format(
                    a.point or "?", a.relativeTo or "?", a.relativePoint or "?",
                    a.x or 0, a.y or 0))
            end

            -- Style (all values)
            if g.style then
                add("  style: " .. dumpKV(g.style))
            end

            -- Alpha/visibility
            local alphaKeys = {
                "baselineAlpha", "forceAlphaInCombat", "forceAlphaOutOfCombat",
                "forceAlphaMounted", "forceAlphaTargetExists", "forceAlphaMouseover",
                "forceHideInCombat", "forceHideOutOfCombat", "forceHideMounted",
                "fadeDelay", "fadeInDuration", "fadeOutDuration",
            }
            local alphaParts = {}
            for _, k in ipairs(alphaKeys) do
                if g[k] ~= nil then
                    alphaParts[#alphaParts + 1] = k .. "=" .. tostring(g[k])
                end
            end
            if #alphaParts > 0 then
                add("  alpha: " .. table.concat(alphaParts, " "))
            end

            -- Load conditions
            if g.loadConditions then
                add("  load: " .. dumpKV(g.loadConditions))
            end

            -- Other group-level keys not handled above
            local groupHandledKeys = {
                name=1, buttons=1, style=1, anchor=1, loadConditions=1,
                specs=1, displayMode=1, enabled=1,
                baselineAlpha=1, forceAlphaInCombat=1, forceAlphaOutOfCombat=1,
                forceAlphaMounted=1, forceAlphaTargetExists=1, forceAlphaMouseover=1,
                forceHideInCombat=1, forceHideOutOfCombat=1, forceHideMounted=1,
                fadeDelay=1, fadeInDuration=1, fadeOutDuration=1,
            }
            local extraParts = {}
            for k, v in pairs(g) do
                if not groupHandledKeys[k] then
                    extraParts[#extraParts + 1] = tostring(k) .. "=" .. formatValue(v)
                end
            end
            table.sort(extraParts)
            if #extraParts > 0 then
                add("  other: " .. table.concat(extraParts, " "))
            end

            -- Buttons with annotations
            if g.buttons and #g.buttons > 0 then
                add("  buttons:")
                for i, btn in ipairs(g.buttons) do
                    local main = ("    %d. %s:%s %q"):format(
                        i, btn.type or "?", tostring(btn.id or "?"), btn.name or "?")
                    local extras = {}
                    for k, v in pairs(btn) do
                        if k ~= "type" and k ~= "id" and k ~= "name" then
                            extras[#extras + 1] = tostring(k) .. "=" .. formatValue(v)
                        end
                    end
                    -- Annotate: show default auraUnit when auraTracking is on but unit not specified
                    if btn.auraTracking and not btn.auraUnit then
                        extras[#extras + 1] = "auraUnit=player(default)"
                    end
                    -- Annotate: cross-reference with CDM viewer aura tracking
                    if btn.type == "spell" and btn.id and viewerAuraSet[btn.id] then
                        extras[#extras + 1] = "~viewerAura=yes"
                    end
                    table.sort(extras)
                    if #extras > 0 then
                        main = main .. " " .. table.concat(extras, " ")
                    end
                    add(main)
                end
            end
            add("")
        end
    end

    -- Resource Bars (with type names and explicit anchorGroupId)
    add("--- Resource Bars ---")
    local rb = p.resourceBars
    if rb then
        local rbSimple = {}
        local hasAnchorGroupId = false
        for k, v in pairs(rb) do
            if k == "anchorGroupId" then hasAnchorGroupId = true end
            if k ~= "resources" and k ~= "customAuraBars" then
                rbSimple[#rbSimple + 1] = tostring(k) .. "=" .. formatValue(v)
            end
        end
        if not hasAnchorGroupId then
            rbSimple[#rbSimple + 1] = "anchorGroupId=nil"
        end
        table.sort(rbSimple)
        add(table.concat(rbSimple, " "))

        if rb.resources then
            add("resources:")
            local rids = {}
            for id in pairs(rb.resources) do rids[#rids + 1] = id end
            table.sort(rids)
            for _, id in ipairs(rids) do
                local typeName = RESOURCE_NAMES[id]
                local label = typeName
                    and ("[%s] (%s)"):format(tostring(id), typeName)
                    or ("[%s]"):format(tostring(id))
                local kv = dumpKV(rb.resources[id])
                add(("  %s %s"):format(label, kv ~= "" and kv or "(default)"))
            end
        end

        if rb.customAuraBars then
            local hasAny = false
            for _ in pairs(rb.customAuraBars) do hasAny = true; break end
            if hasAny then
                add("customAuraBars:")
                local specIds = {}
                for sid in pairs(rb.customAuraBars) do specIds[#specIds + 1] = sid end
                table.sort(specIds)
                for _, sid in ipairs(specIds) do
                    local sName = sid == 0 and "Default" or specNames[sid]
                    local label = sName
                        and ("[%s] (%s)"):format(tostring(sid), sName)
                        or ("[%s]"):format(tostring(sid))
                    add(("  %s"):format(label))
                    local specBars = rb.customAuraBars[sid]
                    local slots = {}
                    for slot in pairs(specBars) do slots[#slots + 1] = slot end
                    table.sort(slots, function(a, b) return tostring(a) < tostring(b) end)
                    for _, slot in ipairs(slots) do
                        add(("    %s: %s"):format(tostring(slot), dumpKV(specBars[slot])))
                    end
                end
            end
        end
    end

    -- Cast Bar (with explicit anchorGroupId)
    add("")
    add("--- Cast Bar ---")
    if p.castBar then
        add(dumpKVWithNils(p.castBar, {"anchorGroupId"}))
    end

    -- Frame Anchoring (with explicit anchorGroupId)
    add("")
    add("--- Frame Anchoring ---")
    if p.frameAnchoring then
        local faSimple = {}
        local faComplex = {}
        local hasAnchorGroupId = false
        for k, v in pairs(p.frameAnchoring) do
            if k == "anchorGroupId" then hasAnchorGroupId = true end
            if type(v) == "table" then
                faComplex[k] = v
            else
                faSimple[#faSimple + 1] = tostring(k) .. "=" .. tostring(v)
            end
        end
        if not hasAnchorGroupId then
            faSimple[#faSimple + 1] = "anchorGroupId=nil"
        end
        table.sort(faSimple)
        add(table.concat(faSimple, " "))
        local cKeys = {}
        for k in pairs(faComplex) do cKeys[#cKeys + 1] = k end
        table.sort(cKeys)
        for _, k in ipairs(cKeys) do
            add(("  %s: %s"):format(k, dumpKV(faComplex[k])))
        end
    end

    -- Global Style
    add("")
    add("--- Global Style ---")
    if p.globalStyle then
        add(dumpKV(p.globalStyle))
    end

    -- Folders (with member group listing)
    if p.folders then
        local hasAny = false
        for _ in pairs(p.folders) do hasAny = true; break end
        if hasAny then
            add("")
            add("--- Folders ---")
            local folderIds = {}
            for id in pairs(p.folders) do folderIds[#folderIds + 1] = id end
            table.sort(folderIds)
            for _, fid in ipairs(folderIds) do
                local f = p.folders[fid]
                -- List which groups belong to this folder
                local memberGroups = {}
                if p.groups then
                    for gid, g in pairs(p.groups) do
                        if g.folderId == fid then
                            memberGroups[#memberGroups + 1] = ("%d(%q)"):format(gid, g.name or "?")
                        end
                    end
                end
                table.sort(memberGroups)
                local membersStr = #memberGroups > 0 and table.concat(memberGroups, ", ") or "empty"
                add(("[%s] %q section=%s order=%s | groups: %s"):format(
                    tostring(fid), f.name or "?", f.section or "?", tostring(f.order), membersStr))
            end
        end
    end

    -- Other top-level profile keys
    add("")
    add("--- Other ---")
    local skipTopLevel = {
        groups=1, resourceBars=1, castBar=1, frameAnchoring=1,
        globalStyle=1, folders=1,
    }
    local otherParts = {}
    for k, v in pairs(p) do
        if not skipTopLevel[k] then
            if k == "auraDurationCache" and type(v) == "table" then
                -- Show full cache contents for aura debugging
                local entries = {}
                for spellId, dur in pairs(v) do
                    entries[#entries + 1] = tostring(spellId) .. "=" .. tostring(dur)
                end
                table.sort(entries)
                if #entries == 0 then
                    otherParts[#otherParts + 1] = "auraDurationCache={}"
                else
                    otherParts[#otherParts + 1] = "auraDurationCache={" .. table.concat(entries, ", ") .. "}"
                end
            else
                otherParts[#otherParts + 1] = tostring(k) .. "=" .. formatValue(v)
            end
        end
    end
    table.sort(otherParts)
    for _, line in ipairs(otherParts) do
        add(line)
    end

    return table.concat(lines, "\n")
end

StaticPopupDialogs["CDC_DIAGNOSTIC_EXPORT"] = {
    text = "Bug report string (Ctrl+C to copy, paste in Discord):",
    button1 = "Close",
    hasEditBox = true,
    OnShow = function(self)
        local snapshot = BuildDiagnosticSnapshot()
        local serialized = AceSerializer:Serialize(snapshot)
        local compressed = LibDeflate:CompressDeflate(serialized)
        local encoded = LibDeflate:EncodeForPrint(compressed)
        self.EditBox:SetText("CDCdiag:" .. encoded)
        self.EditBox:HighlightText()
        self.EditBox:SetFocus()
    end,
    EditBoxOnEscapePressed = function(self)
        self:GetParent():Hide()
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

StaticPopupDialogs["CDC_DIAGNOSTIC_IMPORT_CONFIRM"] = {
    text = "Import this bug report's profile into your addon? Your current profile will be overwritten.",
    button1 = "Import",
    button2 = "Cancel",
    OnAccept = function()
        if decodedDiagnostic and decodedDiagnostic.profile then
            local db = CooldownCompanion.db
            for k, v in pairs(decodedDiagnostic.profile) do
                db.profile[k] = v
            end
            CS.selectedGroup = nil
            CS.selectedButton = nil
            wipe(CS.selectedButtons)
            wipe(CS.selectedGroups)
            if db.profile.groups then
                local charKey = db.keys.char
                for _, group in pairs(db.profile.groups) do
                    if not group.isGlobal then
                        group.createdBy = charKey
                    end
                end
            end
            CooldownCompanion:RefreshConfigPanel()
            CooldownCompanion:RefreshAllGroups()
            CooldownCompanion:Print("Diagnostic profile imported.")
        end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

local function OpenDiagnosticDecodePanel()
    if diagnosticDecodeFrame then
        diagnosticDecodeFrame:Show()
        return
    end

    local frame = AceGUI:Create("Window")
    frame:SetTitle("CDC Diagnostic Decode")
    frame:SetWidth(700)
    frame:SetHeight(600)
    frame:SetLayout("List")
    diagnosticDecodeFrame = frame

    local inputBox = AceGUI:Create("MultiLineEditBox")
    inputBox:SetLabel("Paste diagnostic string:")
    inputBox:SetFullWidth(true)
    inputBox:SetNumLines(6)
    inputBox.button:Hide()
    frame:AddChild(inputBox)

    local outputBox = AceGUI:Create("MultiLineEditBox")
    outputBox:SetLabel("Decoded report:")
    outputBox:SetFullWidth(true)
    outputBox:SetNumLines(20)
    outputBox.button:Hide()

    local btnGroup = AceGUI:Create("SimpleGroup")
    btnGroup:SetFullWidth(true)
    btnGroup:SetLayout("Flow")

    local decodeBtn = AceGUI:Create("Button")
    decodeBtn:SetText("Decode")
    decodeBtn:SetWidth(120)
    decodeBtn:SetCallback("OnClick", function()
        local text = inputBox:GetText()
        if not text or text == "" then return end
        text = text:gsub("%s+", "")
        if text:sub(1, 8) == "CDCdiag:" then
            text = text:sub(9)
        end
        local decoded = LibDeflate:DecodeForPrint(text)
        if not decoded then
            outputBox:SetText("Error: Failed to decode string.")
            return
        end
        local decompressed = LibDeflate:DecompressDeflate(decoded)
        if not decompressed then
            outputBox:SetText("Error: Failed to decompress.")
            return
        end
        local success, data = AceSerializer:Deserialize(decompressed)
        if not success or type(data) ~= "table" then
            outputBox:SetText("Error: Failed to deserialize.")
            return
        end
        decodedDiagnostic = data
        outputBox:SetText(FormatDiagnosticAsText(data))
    end)
    btnGroup:AddChild(decodeBtn)

    local copyBtn = AceGUI:Create("Button")
    copyBtn:SetText("Copy as Text")
    copyBtn:SetWidth(120)
    copyBtn:SetCallback("OnClick", function()
        if not decodedDiagnostic then return end
        outputBox.editBox:HighlightText()
        outputBox.editBox:SetFocus()
    end)
    btnGroup:AddChild(copyBtn)

    local importBtn = AceGUI:Create("Button")
    importBtn:SetText("Import Profile")
    importBtn:SetWidth(120)
    importBtn:SetCallback("OnClick", function()
        if not decodedDiagnostic or not decodedDiagnostic.profile then
            CooldownCompanion:Print("No diagnostic data to import.")
            return
        end
        StaticPopup_Show("CDC_DIAGNOSTIC_IMPORT_CONFIRM")
    end)
    btnGroup:AddChild(importBtn)

    frame:AddChild(btnGroup)
    frame:AddChild(outputBox)

    frame:SetCallback("OnClose", function(widget)
        AceGUI:Release(widget)
        diagnosticDecodeFrame = nil
        decodedDiagnostic = nil
    end)
end

function CooldownCompanion:OpenDiagnosticDecodePanel()
    OpenDiagnosticDecodePanel()
end
