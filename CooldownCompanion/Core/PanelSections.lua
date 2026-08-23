--[[
    CooldownCompanion - Core/PanelSections.lua: panel section membership,
    per-section geometry, and the shared layout metrics Core/GroupFrame.lua
    positions its live buttons from.

    A SECTION is a small placed cluster of icons pinned to one of the eight
    anchor points of an icon panel's BASE GRID (four corners, four edge
    midpoints). Membership is EXPLICIT per entry (buttonData.section): nothing
    ever migrates on its own, so the base grid's wrap math, buttonsPerRow, and
    auto-max behavior are untouched by the feature. A section owns only its
    icon size, spacing, and X/Y offset; every other styling key stays panel-wide,
    text included.

    Sections apply to plain icon panels only. An Aura Panel renders through
    Blizzard's flow container, which assumes one cell size per line, and bar,
    text, texture, trigger, and Rotation Assistant panels are outside the model.
    Everywhere sections do not apply, GetSectionsForLayout returns nil and the
    panel lays out through the exact code it always did.

    The base grid is NOT re-derived here. A sectioned panel parks an invisible
    anchor frame over the base cluster's slot inside the (now larger) panel
    frame, and GroupFrame's existing corner/centered-edge arithmetic runs against
    that frame instead of the panel -- same expressions, same digits.
]]

local ADDON_NAME, ST = ...

local C_Spell = C_Spell
local CreateFrame = CreateFrame
local issecretvalue = issecretvalue
local ipairs = ipairs
local next = next
local pairs = pairs
local tonumber = tonumber
local type = type
local wipe = wipe
local math_ceil = math.ceil
local math_max = math.max
local math_min = math.min

------------------------------------------------------------------------
-- ANCHORS
------------------------------------------------------------------------

-- The eight placeable anchors. CENTER is deliberately absent: a cluster on
-- top of the base grid has no meaning, and leaving it out keeps "one anchor,
-- one section" a complete statement of the model.
ST.PANEL_SECTION_ANCHORS = {
    "TOPLEFT", "TOP", "TOPRIGHT",
    "LEFT", "RIGHT",
    "BOTTOMLEFT", "BOTTOM", "BOTTOMRIGHT",
}

local ANCHOR_SET = {}
for _, anchor in ipairs(ST.PANEL_SECTION_ANCHORS) do
    ANCHOR_SET[anchor] = true
end
ST.PANEL_SECTION_ANCHOR_SET = ANCHOR_SET

-- One place every surface that names an anchor to the owner reads its wording
-- from, so a menu row, a slider heading, and an entry badge cannot drift apart.
ST.PANEL_SECTION_ANCHOR_LABELS = {
    TOPLEFT     = "Top Left",
    TOP         = "Top",
    TOPRIGHT    = "Top Right",
    LEFT        = "Left",
    RIGHT       = "Right",
    BOTTOMLEFT  = "Bottom Left",
    BOTTOM      = "Bottom",
    BOTTOMRIGHT = "Bottom Right",
}

-- Anchor implies both the line's direction and which side of the base cluster
-- the line sits on -- there are no growth or orientation controls.
--   axis "h" = one horizontal line, "v" = one vertical line (never wraps).
--   side     = which outside face of the base cluster the line sits against.
--   from     = where entry 1 sits on that line: "low" is the left/top end,
--              "high" the right/bottom end, "center" the line's own start
--              after it has been centered on the cluster's edge.
-- Edge midpoints read the same in both orientations (a TOP section is a
-- centered horizontal line whether the panel grows sideways or downward).
-- Corners follow the panel's orientation and grow away from their corner.
local SECTION_PLACEMENT = {
    horizontal = {
        TOP         = { axis = "h", side = "above", from = "center" },
        BOTTOM      = { axis = "h", side = "below", from = "center" },
        LEFT        = { axis = "v", side = "left",  from = "center" },
        RIGHT       = { axis = "v", side = "right", from = "center" },
        TOPLEFT     = { axis = "h", side = "above", from = "low" },
        TOPRIGHT    = { axis = "h", side = "above", from = "high" },
        BOTTOMLEFT  = { axis = "h", side = "below", from = "low" },
        BOTTOMRIGHT = { axis = "h", side = "below", from = "high" },
    },
    vertical = {
        TOP         = { axis = "h", side = "above", from = "center" },
        BOTTOM      = { axis = "h", side = "below", from = "center" },
        LEFT        = { axis = "v", side = "left",  from = "center" },
        RIGHT       = { axis = "v", side = "right", from = "center" },
        TOPLEFT     = { axis = "v", side = "left",  from = "low" },
        TOPRIGHT    = { axis = "v", side = "right", from = "low" },
        BOTTOMLEFT  = { axis = "v", side = "left",  from = "high" },
        BOTTOMRIGHT = { axis = "v", side = "right", from = "high" },
    },
}

------------------------------------------------------------------------
-- MEMBERSHIP
------------------------------------------------------------------------

--- True for panels the section model covers at all.
function ST.PanelSupportsSections(group)
    return type(group) == "table"
        and group.displayMode == "icons"
        and not ST.IsAuraPanelGroup(group)
end

--- The anchor an entry belongs to, or nil for the base grid.
--- Defensive on purpose: an entry may still name an anchor whose section table
--- is gone (a dissolved section, an import, a hand-edited profile). That entry
--- is a base member, exactly like an entry that never joined one.
function ST.GetPanelSectionForEntry(group, buttonData)
    if type(buttonData) ~= "table" then return nil end
    local anchor = buttonData.section
    if not (anchor and ANCHOR_SET[anchor]) then return nil end
    local sections = group and group.sections
    if type(sections) ~= "table" or type(sections[anchor]) ~= "table" then
        return nil
    end
    return anchor
end

--- The panel's section table, but only when sections actually have something
--- to lay out. Every layout path early-outs on nil, so this is the single gate
--- that keeps a section-less panel on its original code.
function ST.GetSectionsForLayout(group)
    if not ST.PanelSupportsSections(group) then return nil end
    local sections = group.sections
    if type(sections) ~= "table" or not next(sections) then return nil end
    for _, buttonData in ipairs(group.buttons or {}) do
        if ST.GetPanelSectionForEntry(group, buttonData) then
            return sections
        end
    end
    return nil
end

--- Split an ordered button list into base members and per-anchor member lists.
--- Relative order inside a section is the entries' order in the master list,
--- which is what makes the entries list able to stay flat.
function ST.PartitionPanelSectionMembers(group, buttons, lists)
    lists = lists or {}

    local base = lists.base
    if base then wipe(base) else base = {}; lists.base = base end

    local members = lists.members
    if members then
        for _, list in pairs(members) do wipe(list) end
    else
        members = {}
        lists.members = members
    end

    for _, button in ipairs(buttons or {}) do
        local anchor = ST.GetPanelSectionForEntry(group, button.buttonData)
        if anchor then
            local list = members[anchor]
            if not list then list = {}; members[anchor] = list end
            list[#list + 1] = button
        else
            base[#base + 1] = button
        end
    end

    return lists
end

--- Drop a section that has nothing left in it.
--- A section IS its members: the last one leaving takes the placement with it,
--- so nothing invisible lingers in the profile waiting to surprise the owner.
--- Kept separate from the membership write below so a multi-entry move can
--- dissolve once at the end instead of after every entry.
--- Returns true when a section was removed.
function ST.DissolveEmptyPanelSection(group, anchor)
    local sections = group and group.sections
    if type(sections) ~= "table" or sections[anchor] == nil then return false end
    for _, buttonData in ipairs(group.buttons or {}) do
        if buttonData.section == anchor then return false end
    end
    sections[anchor] = nil
    if not next(sections) then
        group.sections = nil
    end
    return true
end

--- Move one entry into a section, or back to the base grid with anchor = nil.
--- A section created here stores only its offsets; every geometry key stays nil
--- so the section inherits the panel until something sets one.
--- Returns true when the entry's membership actually changed.
function ST.SetPanelSectionForEntry(group, buttonData, anchor)
    if type(group) ~= "table" or type(buttonData) ~= "table" then return false end
    if anchor ~= nil and not ANCHOR_SET[anchor] then return false end

    -- An AURA-ONLY destination admits aura entries only, and only of its own
    -- polarity. This is the single membership writer, so this one test covers
    -- every way an entry could arrive: a drag, a move menu, an import landing.
    -- It cannot fire for a normal section or for a brand-new anchor -- the
    -- predicate needs an existing section table already carrying the flag -- so
    -- no unsectioned or plainly sectioned panel reaches a new line of code here.
    -- Leaving an aura section is never restricted; only arriving is.
    if anchor and ST.IsAuraOnlyPanelSection(group, anchor)
        and CooldownCompanion:GetAuraSectionEntryRejectMessage(group, anchor, buttonData) then
        return false
    end

    -- The no-op test compares EFFECTIVE membership, not the raw key. An entry
    -- can still NAME an anchor whose section table is gone (a dissolved
    -- section, an import, a profile edited by hand), and GetPanelSectionForEntry
    -- already reads that entry as a base member. Testing the raw key would make
    -- dropping such an entry on that anchor's own pad a silent no-op: no table
    -- created, no `true` returned, so no refresh either.
    local rawPrevious = buttonData.section
    local previous = ST.GetPanelSectionForEntry(group, buttonData)
    if previous == anchor and rawPrevious == anchor then return false end
    buttonData.section = anchor

    if anchor then
        local sections = group.sections
        if type(sections) ~= "table" then
            sections = {}
            group.sections = sections
        end
        if type(sections[anchor]) ~= "table" then
            sections[anchor] = { offsetX = 0, offsetY = 0 }
        end
    end

    if rawPrevious then
        ST.DissolveEmptyPanelSection(group, rawPrevious)
    end
    -- Now that membership is written, an entry landing in an aura section owes
    -- the aura engine a key. Runs after the write because the stamp reads
    -- effective membership rather than being told about it.
    CooldownCompanion:StampAuraSectionEntryKey(group, buttonData)
    return true
end

--- Take one entry out of whatever section it names.
--- The pair -- clear the key, then dissolve the anchor it vacated -- is what
--- every structural mutation owes a section. A `buttonData.section` left on an
--- entry that is leaving keeps an empty `group.sections` table alive, and an
--- empty table is still a Layout-tab block, still a drop target that promises
--- offset (0,0) and then delivers the orphan's saved offsets.
--- Returns true when the entry was in a section.
function ST.DetachEntryFromPanelSection(group, buttonData)
    if type(buttonData) ~= "table" then return false end
    local anchor = buttonData.section
    if anchor == nil then return false end
    buttonData.section = nil
    ST.DissolveEmptyPanelSection(group, anchor)
    return true
end

--- Dissolve every section this panel has been left with nothing in.
--- A batch mutation -- a multi-delete, a multi-entry move, a wholesale
--- repopulate -- can empty several anchors at once, so it sweeps once at the
--- end instead of tracking each vacated anchor on the way through.
--- Returns true when anything was removed.
function ST.SweepEmptyPanelSections(group)
    if type(group) ~= "table" or type(group.sections) ~= "table" then return false end
    local changed = false
    for _, anchor in ipairs(ST.PANEL_SECTION_ANCHORS) do
        if ST.DissolveEmptyPanelSection(group, anchor) then
            changed = true
        end
    end
    return changed
end

--- Return every section member to the base grid and drop the sections.
--- Entries keep their place in the master list, which is exactly where the base
--- grid reads its order from, so flattening only ever subtracts. Leaving icon
--- mode calls this: placements are not remembered across a display-mode switch.
--- Returns true when anything changed.
function ST.FlattenPanelSections(group)
    if type(group) ~= "table" then return false end
    local changed = false
    for _, buttonData in ipairs(group.buttons or {}) do
        if buttonData.section ~= nil then
            buttonData.section = nil
            changed = true
        end
    end
    if group.sections ~= nil then
        group.sections = nil
        changed = true
    end
    return changed
end

------------------------------------------------------------------------
-- AURA SECTIONS
------------------------------------------------------------------------

--[[
    An AURA SECTION is one section whose members render through Blizzard's aura
    container instead of CC's own layout -- the Aura Panel treatment, scoped to a
    cluster rather than to a whole panel, so a mixed panel can carry a lane of
    auras that appears and collapses with aura activity while the base grid keeps
    its fixed slots.

    The flag lives on the SECTION TABLE (group.sections[anchor].auraOnly), never
    on the entries. That is what makes the rest of the model free: a section IS
    its members, so dissolving the last member out of it drops the table and the
    flag with it, and FlattenPanelSections drops group.sections wholesale. There
    is no separate state to sweep.

    Aura-ness is a TOGGLE, not a creation-time choice, and it never restructures
    anything on its own: turning it on with a non-aura member inside refuses and
    says why. Admission is primary aura entries only -- see the reject message in
    Core/Defaults.lua for the whole rule.
]]

--- True while this anchor's section renders through the aura container.
--- Needs the section table to exist: an entry naming a dissolved anchor is a
--- base member (GetPanelSectionForEntry), and a base member is never aura-only.
function ST.IsAuraOnlyPanelSection(group, anchor)
    if type(group) ~= "table" then return false end
    if not (anchor and ANCHOR_SET[anchor]) then return false end
    local sections = group.sections
    if type(sections) ~= "table" then return false end
    local section = sections[anchor]
    return type(section) == "table" and section.auraOnly == true
end

--- True while this panel carries at least one aura-only section.
--- Every gate that has to treat a mixed panel the way it treats an Aura Panel --
--- the rebind request, the rebuild signature, the populate skip -- reads this
--- one predicate, so they cannot drift apart. False for every panel the section
--- model does not cover, so a stray flag on a bar or text panel stays inert.
function ST.PanelHasAuraSection(group)
    if not ST.PanelSupportsSections(group) then return false end
    if type(group.sections) ~= "table" then return false end
    for _, anchor in ipairs(ST.PANEL_SECTION_ANCHORS) do
        if ST.IsAuraOnlyPanelSection(group, anchor) then return true end
    end
    return false
end

--- True for one entry that renders through an aura section rather than as a CC
--- button. The three places that decide the panel's live button list -- the
--- populate loop, the style fast path's expectation of it, and the rebuild
--- comparison against it -- all filter on this, so "this entry has no button" is
--- one answer rather than three.
function ST.IsAuraSectionEntry(group, buttonData)
    local anchor = ST.GetPanelSectionForEntry(group, buttonData)
    return anchor ~= nil and ST.IsAuraOnlyPanelSection(group, anchor)
end

--- How many members each aura section reserves a cell for, per anchor.
--- Counted from DATA, never from live buttons: an aura section materializes
--- none, and its footprint has to hold still while auras come and go -- aura
--- activity is secret, so a rectangle that followed it would move under the
--- player every time something expired.
--- Usability is the same question the base grid asks before it makes a button
--- and the bind pass asks before it binds an entry, so an untalented member
--- reserves nothing on either side.
--- Returns the (wiped and refilled) counts table; empty for every panel without
--- an aura section, which is the signal the layout uses to count live buttons.
function ST.CollectAuraSectionCounts(group, usability, counts)
    if counts then wipe(counts) else counts = {} end
    if not ST.PanelHasAuraSection(group) then return counts end
    for _, buttonData in ipairs(group.buttons or {}) do
        local anchor = ST.GetPanelSectionForEntry(group, buttonData)
        if anchor and ST.IsAuraOnlyPanelSection(group, anchor)
            and CooldownCompanion:IsButtonUsable(buttonData, group, usability) then
            counts[anchor] = (counts[anchor] or 0) + 1
        end
    end
    return counts
end

--- Why this section cannot be switched to aura-only right now, or nil when it
--- can. The first member that fails admission owns the message, so the owner is
--- told about one concrete entry instead of a count.
--- Asking is separate from doing on purpose: the config surface explains the
--- refusal on a disabled checkbox without attempting the write.
function ST.GetAuraSectionToggleBlocker(group, anchor)
    if type(group) ~= "table" or not (anchor and ANCHOR_SET[anchor]) then return nil end
    local sections = group.sections
    if type(sections) ~= "table" or type(sections[anchor]) ~= "table" then return nil end
    for _, buttonData in ipairs(group.buttons or {}) do
        if ST.GetPanelSectionForEntry(group, buttonData) == anchor then
            local message = CooldownCompanion:GetAuraSectionEntryRejectMessage(group, anchor, buttonData)
            if message then return message end
        end
    end
    return nil
end

--- Stamp every aura-section member that is still missing an aura key.
--- The membership writer covers entries as they arrive; this covers the entries
--- that were ALREADY sitting in a section when it became aura-only, and any
--- path that wrote membership without going through the writer.
--- Idempotent, and never renumbers a key that already exists.
--- Returns true when anything was stamped.
function ST.EnsureAuraSectionEntryKeys(group)
    if type(group) ~= "table" then return false end
    local stamped = false
    for _, buttonData in ipairs(group.buttons or {}) do
        if type(buttonData) == "table" and buttonData._auraKey == nil then
            CooldownCompanion:StampAuraSectionEntryKey(group, buttonData)
            if buttonData._auraKey ~= nil then
                stamped = true
            end
        end
    end
    return stamped
end

--- Switch one section's aura-only flag.
--- Turning it OFF always succeeds: the members go back to ordinary icons, and
--- their aura keys stay behind harmlessly (nothing reads a key off a non-aura
--- surface, and keeping them means switching back does not renumber a thing).
--- Turning it ON REFUSES rather than restructuring: if any current member fails
--- admission the flag does not move and the member's own message comes back for
--- the caller to show.
--- Returns:
---   true            -- the flag changed
---   false           -- nothing to do (already in that state, no such section)
---   false, message  -- refused; message is player-facing
function ST.SetPanelSectionAuraOnly(group, anchor, enabled)
    if type(group) ~= "table" or not (anchor and ANCHOR_SET[anchor]) then return false end
    local sections = group.sections
    local section = type(sections) == "table" and sections[anchor] or nil
    if type(section) ~= "table" then return false end

    if not enabled then
        if section.auraOnly == nil then return false end
        section.auraOnly = nil
        return true
    end

    if section.auraOnly == true then return false end
    local blocker = ST.GetAuraSectionToggleBlocker(group, anchor)
    if blocker then return false, blocker end

    section.auraOnly = true
    -- The full key repair, not just the missing-key sweep: an entry can arrive
    -- at this moment carrying a key another entry in the panel already holds
    -- (a profile hand-edit, or state minted before the adoption rule existed),
    -- and two entries sharing a key means one of them silently never renders.
    -- The import-door normalizer already owns exactly this repair -- preserve
    -- unique keys, replace duplicates, advance the counter past everything --
    -- so the toggle runs the same pass instead of a weaker private one.
    ST._NormalizeAuraSectionEntries(group)
    return true
end

------------------------------------------------------------------------
-- GEOMETRY
------------------------------------------------------------------------

--- A section's icon size and spacing, falling back to the panel's own resolved
--- values. panelWidth/panelHeight arrive already resolved by GroupFrame's
--- GetButtonDimensions, so the fallback can never drift from the panel's own
--- maintainAspectRatio / buttonSize / iconWidth / iconHeight rule.
--- A square panel stays square in its sections: one stored dimension drives
--- both, the same way style.buttonSize does for the base grid.
function ST.ResolvePanelSectionGeometry(style, section, panelWidth, panelHeight, panelSpacing)
    local width, height
    if style.maintainAspectRatio then
        local size = tonumber(section.iconWidth) or tonumber(section.iconHeight)
        width = size or panelWidth
        height = size or panelHeight
    else
        width = tonumber(section.iconWidth) or panelWidth
        height = tonumber(section.iconHeight) or panelHeight
    end
    return math_max(1, width), math_max(1, height), tonumber(section.spacing) or panelSpacing
end

--- Measure the base cluster and every non-empty section, and fold them into one
--- footprint. Everything is computed in BASE-CLUSTER space first (origin at the
--- cluster's TOPLEFT, +x right, +y up, WoW convention), then converted once to
--- offsets from the panel frame's TOPLEFT.
---
--- Returned layout:
---   baseCount, baseWidth, baseHeight  -- the base cluster's own rect
---   baseOffsetX, baseOffsetY          -- its TOPLEFT inside the frame
---                                        (offsetY measured downward)
---   totalWidth, totalHeight           -- the union the frame must span
---   sections[anchor] = { width, height, originX, originY, stepX, stepY }
---                                        member k sits at
---                                        (originX + (k-1)*stepX,
---                                         originY + (k-1)*stepY)
---                                        from the frame's TOPLEFT.
--- An AURA section adds spacing, axis, from and the whole line's rectangle
--- (lineX, lineY, lineWidth, lineHeight, also from the frame's TOPLEFT) under an
--- auraOnly flag. Blizzard's container lays the cells out inside that rectangle,
--- so the per-member steps mean nothing there -- the rect and the direction do.
function ST.BuildPanelSectionLayout(group, sections, lists, panelWidth, panelHeight, panelSpacing, headerHeight, layout)
    local style = group.style or {}
    local orientation = ST.GetPanelLayoutOrientation(group.displayMode, style)
    local buttonsPerRow = math_max(1, style.buttonsPerRow or 12)
    local placements = SECTION_PLACEMENT[orientation] or SECTION_PLACEMENT.horizontal

    layout = layout or {}
    local infos = layout.sections
    if infos then wipe(infos) else infos = {}; layout.sections = infos end

    -- The base cluster's rect, measured exactly the way ResizeGroupFrame
    -- measures a section-less panel -- over base members only.
    local baseCount = #lists.base
    local baseWidth, baseHeight = 0, 0
    if baseCount > 0 then
        local cols, rows
        if orientation == "horizontal" then
            cols = math_min(baseCount, buttonsPerRow)
            rows = math_ceil(baseCount / buttonsPerRow)
        else
            rows = math_min(baseCount, buttonsPerRow)
            cols = math_ceil(baseCount / buttonsPerRow)
        end
        baseWidth = cols * panelWidth + (cols - 1) * panelSpacing
        baseHeight = rows * panelHeight + (rows - 1) * panelSpacing + (headerHeight or 0)
    end

    local minX, maxX, minY, maxY = 0, baseWidth, -baseHeight, 0
    local auraCounts = lists.auraCounts

    for anchor, section in pairs(sections) do
        local members = lists.members[anchor]
        local count = members and #members or 0
        -- An AURA section has no live buttons to measure. Its line is the FULL
        -- expanded one over its data members, so the panel's footprint holds
        -- still while Blizzard's container packs whichever few are active.
        local auraCount = auraCounts and auraCounts[anchor]
        if auraCount then count = auraCount end
        local placement = placements[anchor]
        -- A section with no members in THIS pass's lists reserves no footprint;
        -- the section itself still exists in the profile. Whether a HIDDEN member
        -- counts is the caller's rule: compact reflow partitions visible buttons
        -- only, the ordinary pass every materialized one (hidden members keep
        -- their slots there, exactly as they do in the base row).
        if count > 0 and placement and type(section) == "table" then
            local width, height, spacing =
                ST.ResolvePanelSectionGeometry(style, section, panelWidth, panelHeight, panelSpacing)
            local offsetX = tonumber(section.offsetX) or 0
            local offsetY = tonumber(section.offsetY) or 0
            local info = { width = width, height = height }

            if placement.axis == "h" then
                local lineLength = count * width + (count - 1) * spacing
                local left
                if placement.from == "low" then
                    left = 0
                elseif placement.from == "high" then
                    left = baseWidth - lineLength
                else
                    left = (baseWidth - lineLength) / 2
                end
                -- The line sits OUTSIDE the cluster, one panel spacing clear of
                -- the face its anchor names.
                local top = (placement.side == "above")
                    and (panelSpacing + height)
                    or (-baseHeight - panelSpacing)
                left = left + offsetX
                top = top + offsetY

                info.lineX, info.lineY = left, top
                info.lineWidth, info.lineHeight = lineLength, height
                info.stepY = 0
                info.originY = top
                if placement.from == "high" then
                    -- The corner is the line's right end, so entry 1 sits there
                    -- and the cluster grows back toward the panel's far side.
                    info.stepX = -(width + spacing)
                    info.originX = left + lineLength - width
                else
                    info.stepX = width + spacing
                    info.originX = left
                end

                if left < minX then minX = left end
                if left + lineLength > maxX then maxX = left + lineLength end
                if top > maxY then maxY = top end
                if top - height < minY then minY = top - height end
            else
                local lineLength = count * height + (count - 1) * spacing
                local top
                if placement.from == "low" then
                    top = 0
                elseif placement.from == "high" then
                    top = -baseHeight + lineLength
                else
                    top = (lineLength - baseHeight) / 2
                end
                local left = (placement.side == "left")
                    and (-panelSpacing - width)
                    or (baseWidth + panelSpacing)
                left = left + offsetX
                top = top + offsetY

                info.lineX, info.lineY = left, top
                info.lineWidth, info.lineHeight = width, lineLength
                info.stepX = 0
                info.originX = left
                if placement.from == "high" then
                    -- Entry 1 sits at the bottom corner and the cluster climbs.
                    info.stepY = height + spacing
                    info.originY = top - lineLength + height
                else
                    info.stepY = -(height + spacing)
                    info.originY = top
                end

                if left < minX then minX = left end
                if left + width > maxX then maxX = left + width end
                if top > maxY then maxY = top end
                if top - lineLength < minY then minY = top - lineLength end
            end

            if auraCount then
                -- What the aura container needs, which is not what a live button
                -- needs: the rectangle above plus the direction the line runs.
                -- Taken from SECTION_PLACEMENT here rather than re-derived over
                -- there, so one table still answers "which way does this anchor
                -- grow" for both engines.
                info.auraOnly = true
                info.axis = placement.axis
                info.from = placement.from
                info.spacing = spacing
            end

            infos[anchor] = info
        end
    end

    layout.baseCount = baseCount
    layout.baseWidth = baseWidth
    layout.baseHeight = baseHeight
    layout.baseOffsetX = -minX
    layout.baseOffsetY = maxY
    layout.totalWidth = maxX - minX
    layout.totalHeight = maxY - minY

    -- ONE empty-panel convention, shared by every consumer of this layout.
    -- With every member hidden the union measures nothing, and the three places
    -- that need a rectangle used to invent three different ones: the frame took
    -- ResizeGroupFrame's numButtons == 0 branch (one button), the base anchor
    -- took max(1, 0) (1x1), and UpdateGroupLayout's footprint compare took
    -- max(0, 1) (1x1) -- so the compare always disagreed with the frame and
    -- re-resized it every pass, and a dependent glued to the body sat on a
    -- 1x1 dot. The frame's one-button size is the established behavior, so
    -- that is the one everything else adopts.
    local isEmpty = (layout.totalWidth <= 0 or layout.totalHeight <= 0)
    layout.isEmpty = isEmpty or nil
    layout.footprintWidth = isEmpty and panelWidth or layout.totalWidth
    layout.footprintHeight = isEmpty and panelHeight or layout.totalHeight

    -- One conversion from base-cluster space to frame-TOPLEFT offsets, so
    -- placement below is a straight SetPoint with no further arithmetic.
    for _, info in pairs(infos) do
        info.originX = info.originX + layout.baseOffsetX
        info.originY = info.originY - layout.baseOffsetY
        if info.auraOnly then
            info.lineX = info.lineX + layout.baseOffsetX
            info.lineY = info.lineY - layout.baseOffsetY
        end
    end

    return layout
end

------------------------------------------------------------------------
-- APPLYING THE LAYOUT
------------------------------------------------------------------------

--- Resize one live button to its section's icon size.
--- Every other region on an icon button is anchored to the button's own edges
--- and follows a resize for free. The two that do not are the icon's
--- aspect-ratio crop and the three flipbook overhang frames, which
--- FitHighlightFrame sizes from button:GetSize() -- and UpdateButtonStyle,
--- which runs BEFORE the layout pass, has just sized both from the PANEL's
--- dimensions. Re-run exactly those two here and nothing else.
function ST.ApplyPanelSectionButtonSize(button, width, height)
    if not (button and button.SetSize) then return end

    local currentWidth, currentHeight = button:GetSize()
    if currentWidth == width and currentHeight == height then return end

    button:SetSize(width, height)

    local style = button.style
    if button.icon and ST._ApplyIconTexCoord then
        ST._ApplyIconTexCoord(button.icon, width, height, style and style.iconZoom)
    end

    local FitHighlightFrame = ST._FitHighlightFrame
    if not (FitHighlightFrame and style) then return end

    local highlight = button.assistedHighlight
    if highlight then
        if highlight.blizzardFrame then
            FitHighlightFrame(highlight.blizzardFrame, button, style.assistedHighlightBlizzardOverhang)
        end
        if highlight.procFrame then
            FitHighlightFrame(highlight.procFrame, button, style.assistedHighlightProcOverhang)
        end
    end
    if button.procGlow and button.procGlow.procFrame then
        FitHighlightFrame(button.procGlow.procFrame, button, style.procGlowSize or 32)
    end
    if button.readyGlow and button.readyGlow.procFrame then
        FitHighlightFrame(button.readyGlow.procFrame, button, button.style.readyGlowSize or 32)
    end
end

-- The base cluster's stand-in inside a sectioned panel frame. GroupFrame's
-- corner and centered-edge formulas are handed this frame in place of the panel
-- frame, so a base member's arithmetic is byte-for-byte what it always was --
-- only the rectangle it is measured against moved.
local function AcquireBaseAnchorFrame(frame, layout)
    local anchorFrame = frame._sectionBaseAnchor
    if not anchorFrame then
        anchorFrame = CreateFrame("Frame", nil, frame)
        anchorFrame:EnableMouse(false)
        frame._sectionBaseAnchor = anchorFrame
    end
    -- Nothing visible anywhere on the panel: the body takes the same one-button
    -- rectangle the frame itself does, so a dependent anchored to it keeps
    -- measuring a panel rather than a 1x1 dot. A base row that is merely empty
    -- while a section still shows is a different case and keeps the 1x1 floor.
    if layout.isEmpty then
        anchorFrame:SetSize(math_max(1, layout.footprintWidth), math_max(1, layout.footprintHeight))
    else
        anchorFrame:SetSize(math_max(1, layout.baseWidth), math_max(1, layout.baseHeight))
    end
    anchorFrame:ClearAllPoints()
    anchorFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", layout.baseOffsetX, -layout.baseOffsetY)
    anchorFrame:Show()
    return anchorFrame
end

-- One parked frame per AURA section: the rectangle its aura container mounts on
-- and the panel-side handle for the whole cluster.
--
-- Created ONCE per panel frame per anchor and never destroyed, only moved,
-- resized and hidden. An aura container is welded to the frame it was created
-- under -- reparenting an AuraButton subtree errors even out of combat, and
-- there is no removal API -- so AuraDisplay ABANDONS a record whose host frame
-- changed. A host that came and went with the section's aura-only flag would
-- abandon one on every toggle.
local function AcquireAuraSectionHost(frame, anchor)
    local hosts = frame._auraSectionHosts
    if not hosts then
        hosts = {}
        frame._auraSectionHosts = hosts
    end
    local host = hosts[anchor]
    if not host then
        host = CreateFrame("Frame", nil, frame)
        host:EnableMouse(false)
        hosts[anchor] = host
    end
    return host
end

--- The rectangle anything anchored TO this panel must measure against.
--- A sectioned panel's frame spans the UNION of its base cluster and every
--- section, so a unit frame or another panel anchored to the frame would be
--- shoved around every time a section appeared on one side. The BASE ROW is
--- the anchoring body; an owner who wants a different spot uses the anchoring
--- module's own offsets. Unsectioned panels -- and every non-panel frame this
--- is handed -- come straight back out, so nothing else changes shape.
---
--- The base anchor is a child of the panel frame and is only ever HIDDEN when
--- sections go away (its rect goes stale), so callers must re-anchor across a
--- sectioned-state flip rather than trust a stored target.
function ST.GetPanelAnchorBodyFrame(frame)
    if type(frame) ~= "table" then return frame end
    if frame._sectionLayout and frame._sectionBaseAnchor then
        return frame._sectionBaseAnchor
    end
    return frame
end

--- True while the panel frame and its anchoring body are different frames.
function ST.IsPanelSectionAnchorBodyActive(frame)
    return (type(frame) == "table"
        and frame._sectionLayout ~= nil
        and frame._sectionBaseAnchor ~= nil) or false
end

local function PlaceSectionMembers(frame, lists, layout, panelWidth, panelHeight)
    for _, button in ipairs(lists.base) do
        -- An entry that just left a section is a base member again on this pass;
        -- put the panel's own size back on it.
        ST.ApplyPanelSectionButtonSize(button, panelWidth, panelHeight)
    end

    for anchor, info in pairs(layout.sections) do
        if info.auraOnly then
            -- Nothing to place: the members render through Blizzard's container,
            -- which lays its own cells out inside the host frame. The host IS the
            -- section here, spanning the FULL expanded line, exactly the way an
            -- Aura Panel's frame spans its full expanded grid.
            local host = AcquireAuraSectionHost(frame, anchor)
            host:SetSize(math_max(1, info.lineWidth), math_max(1, info.lineHeight))
            host:ClearAllPoints()
            host:SetPoint("TOPLEFT", frame, "TOPLEFT", info.lineX, info.lineY)
            host:Show()
        else
            local members = lists.members[anchor]
            for index, button in ipairs(members or {}) do
                ST.ApplyPanelSectionButtonSize(button, info.width, info.height)
                -- Section members never ride the compact slot cache: the cache keys
                -- on anchor/x/y alone and cannot tell the panel frame from the base
                -- anchor frame, so a member crossing that boundary would otherwise
                -- keep a stale relative frame.
                button._compactSlotAnchor = nil
                button._compactSlotX = nil
                button._compactSlotY = nil
                button:ClearAllPoints()
                button:SetPoint("TOPLEFT", frame, "TOPLEFT",
                    info.originX + (index - 1) * info.stepX,
                    info.originY + (index - 1) * info.stepY)
            end
        end
    end

    -- A section that stopped being aura-only, lost its last member, or has
    -- nothing usable left in it leaves its host behind. Hiding it takes the
    -- orphaned container dark with it (visibility rides parentage), which is the
    -- whole of "park it" from the panel side -- the rebind pass parks the groups.
    local hosts = frame._auraSectionHosts
    if hosts then
        for anchor, host in pairs(hosts) do
            local info = layout.sections[anchor]
            if not (info and info.auraOnly) then
                host:Hide()
            end
        end
    end
end

--- Undo a panel's sectioned state after its last section went away.
--- The base-cluster offsets are deliberately LEFT behind: the resize that
--- follows this pass still needs the outgoing offset to hold the base grid
--- still while the frame collapses back onto it. ResizeGroupFrame clears them
--- once it has used them.
function ST.ClearPanelSectionLayout(frame, group, panelWidth, panelHeight)
    if not frame._sectionLayout then return end

    frame._sectionLayout = nil
    if frame._sectionBaseAnchor then
        frame._sectionBaseAnchor:Hide()
    end
    -- Every section went away at once (flattened, emptied, display mode
    -- switched), so every aura host goes dark. Hidden, never destroyed -- see
    -- AcquireAuraSectionHost.
    if frame._auraSectionHosts then
        for _, host in pairs(frame._auraSectionHosts) do
            host:Hide()
        end
    end
    -- Put the panel's own icon size back on the members a section had resized.
    -- Only while this is still an icon panel: a display-mode switch reaches
    -- here too, and by then panelWidth/panelHeight are a bar length or a text
    -- grid pitch, and the buttons have already been rebuilt or restyled to
    -- their new mode's dimensions by the repopulate that brought us here.
    if ST.PanelSupportsSections(group) then
        for _, button in ipairs(frame.buttons or {}) do
            ST.ApplyPanelSectionButtonSize(button, panelWidth, panelHeight)
        end
    end
    if frame._sectionMemberLists then
        ST.PartitionPanelSectionMembers(nil, nil, frame._sectionMemberLists)
    end
end

--- The one entry point both live layout passes call.
--- Returns nil, nil, nil for every panel without sections, which is the signal
--- to run the panel's original code path untouched.
--- Otherwise it measures the footprint, sizes and places every section member,
--- parks the base anchor frame, and hands back the base member list plus the
--- frame the caller must lay that list out against.
function ST.PrepareSectionedPanelLayout(frame, group, buttons, panelWidth, panelHeight, panelSpacing, headerHeight, usability)
    local sections = ST.GetSectionsForLayout(group)
    if not sections then
        ST.ClearPanelSectionLayout(frame, group, panelWidth, panelHeight)
        return nil, nil, nil
    end

    local lists = ST.PartitionPanelSectionMembers(group, buttons, frame._sectionMemberLists)
    frame._sectionMemberLists = lists
    -- The one place aura sections are counted, so both live layout passes -- the
    -- ordinary one over materialized buttons and compact mode's over visible ones
    -- -- measure an aura line from the same data and cannot disagree about the
    -- footprint. Empty (and free) for a panel with no aura section.
    lists.auraCounts = ST.CollectAuraSectionCounts(group, usability, lists.auraCounts)

    local layout = ST.BuildPanelSectionLayout(
        group, sections, lists, panelWidth, panelHeight, panelSpacing, headerHeight, frame._sectionLayout)
    frame._sectionLayout = layout

    local baseAnchor = AcquireBaseAnchorFrame(frame, layout)
    PlaceSectionMembers(frame, lists, layout, panelWidth, panelHeight)

    return layout, lists, baseAnchor
end

------------------------------------------------------------------------
-- UNLOCK PLACEHOLDERS
------------------------------------------------------------------------

--[[
    An aura section's members materialize no CC button, so while the panel is
    unlocked the cluster is empty air: nothing to read the section's extent by,
    and on a panel whose every entry sits in one, nothing to grab the panel by
    either. An Aura Panel answers exactly this with one dim tile per reserved
    cell (CooldownCompanion:UpdateAuraPanelPlaceholders); a section takes the
    same answer, scoped to its own rectangle.

    Every number is READ off the layout pass that has just placed this panel --
    the same origin and step a plain section's live buttons are placed with --
    so a tile can never sit anywhere but where the aura container's cell goes.
    Icons only: a sectioned panel is an icon panel by definition, so there is no
    bar flavor of this the way there is for a whole Aura Panel.

    While the tiles are up the live container is suppressed through the frame
    flag the Aura Panel already uses (SetAuraPanelChromeSuppressed fans out to
    every record whose chromeFrame is this panel), so an aura that is actually up
    is never drawn twice.
]]

local function AcquireAuraSectionPlaceholderTile(root, tiles, index)
    local tile = tiles[index]
    if tile then return tile end
    tile = CreateFrame("Frame", nil, root, "BackdropTemplate")
    tile:EnableMouse(false)
    tile:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
    tile:SetBackdropColor(0.08, 0.08, 0.08, 0.6)
    tile.icon = tile:CreateTexture(nil, "ARTWORK")
    tile.icon:SetAlpha(0.6)
    tile.borderTextures = ST.CreateBorderTextureSet(tile, "OVERLAY")
    tiles[index] = tile
    return tile
end

--- Show or hide the section placeholder root, in step with the Aura Panel's.
--- Split out so the two callers -- the shared chrome switch and the geometry
--- re-fit -- cannot disagree about what "shown" means for this root.
function ST.SetAuraSectionPlaceholderRootShown(frame, shown)
    local root = frame and frame._auraSectionPlaceholderRoot
    if not root then return end
    shown = shown == true
    root:SetIgnoreParentAlpha(shown and frame._unlockGhost == true)
    root:SetShown(shown)
end

--- Re-fit every aura section's placeholder tiles.
--- Hides them all for a panel that no longer has an aura section, which is what
--- makes toggling the flag off put the live icons back with nothing left over.
function ST.UpdateAuraSectionPlaceholders(addon, groupId, frame, group)
    local tiles = frame._auraSectionPlaceholders
    local infos = frame._sectionLayout and frame._sectionLayout.sections or nil
    if not (infos and ST.PanelHasAuraSection(group)) then
        for _, tile in ipairs(tiles or {}) do
            tile:Hide()
        end
        return
    end

    local root = frame._auraSectionPlaceholderRoot
    if not root then
        root = CreateFrame("Frame", nil, frame)
        root:SetAllPoints(frame)
        root:EnableMouse(false)
        frame._auraSectionPlaceholderRoot = root
    end
    if not tiles then
        tiles = {}
        frame._auraSectionPlaceholders = tiles
    end

    local style = group.style or {}
    local usability = addon:GetGroupButtonUsabilityOptions(groupId, group)
    local used = 0
    for _, anchor in ipairs(ST.PANEL_SECTION_ANCHORS) do
        local info = infos[anchor]
        if info and info.auraOnly then
            -- Master order over USABLE members, which is exactly the order and
            -- the count CollectAuraSectionCounts measured this line from, so
            -- the tiles fill the rectangle without a cell left over.
            local cell = 0
            for _, buttonData in ipairs(group.buttons or {}) do
                if ST.GetPanelSectionForEntry(group, buttonData) == anchor
                    and addon:IsButtonUsable(buttonData, group, usability) then
                    cell = cell + 1
                    used = used + 1
                    local tile = AcquireAuraSectionPlaceholderTile(root, tiles, used)
                    tile:SetSize(info.width, info.height)
                    tile:ClearAllPoints()
                    tile:SetPoint("TOPLEFT", frame, "TOPLEFT",
                        info.originX + (cell - 1) * info.stepX,
                        info.originY + (cell - 1) * info.stepY)

                    local effectiveStyle = addon:GetEffectiveStyle(style, buttonData) or style
                    local borderSize = effectiveStyle.borderSize or ST.DEFAULT_BORDER_SIZE
                    local borderRenderMode = ST.GetBorderRenderMode(effectiveStyle)
                    local borderLayoutSize = ST.GetEffectiveBorderLayoutSize(
                        tile, borderSize, borderRenderMode)
                    ST.ApplyBorderTextures(tile.borderTextures, tile,
                        effectiveStyle.borderColor or { 0, 0, 0, 1 }, borderSize,
                        ST.GetEffectiveBorderRenderMode(borderRenderMode, nil, borderSize))

                    tile.icon:ClearAllPoints()
                    tile.icon:SetPoint("TOPLEFT", tile, "TOPLEFT",
                        borderLayoutSize, -borderLayoutSize)
                    tile.icon:SetPoint("BOTTOMRIGHT", tile, "BOTTOMRIGHT",
                        -borderLayoutSize, borderLayoutSize)
                    if ST._ApplyIconTexCoord then
                        ST._ApplyIconTexCoord(tile.icon,
                            math_max(1, info.width - (2 * borderLayoutSize)),
                            math_max(1, info.height - (2 * borderLayoutSize)),
                            effectiveStyle.iconZoom)
                    end

                    local icon = buttonData.type == "spell"
                        and C_Spell.GetSpellTexture(buttonData.id) or nil
                    if icon and not issecretvalue(icon) then
                        tile.icon:SetTexture(icon)
                        tile.icon:Show()
                    else
                        tile.icon:Hide()
                    end

                    tile:Show()
                end
            end
        end
    end

    for extra = used + 1, #tiles do
        tiles[extra]:Hide()
    end
end

------------------------------------------------------------------------
-- ANCHOR DRIFT
------------------------------------------------------------------------

--- Hold a sectioned panel's BASE CLUSTER still across a resize.
--- A section-less panel gets this for free: its frame IS its base cluster, so
--- whatever point the frame is anchored by (or the edge midpoint centered
--- growth and compact mode pin) is a point on the cluster. Once the frame spans
--- the union, those are different rectangles, and a section appearing on one
--- side would shove the base grid across the screen. So the same compensation
--- runs against the base cluster's rect instead of the frame's.
---
--- With no sections in play the arithmetic reduces to exactly the frame-based
--- form GroupFrame has always used, which is why the two are one function.
---
--- The compensation is DURABLE: the delta goes onto the frame's live points AND
--- onto the saved anchor offsets, which are the same coordinate space (both are
--- the x/y arguments of the frame's one SetPoint). Without that second write the
--- next AnchorGroupFrame -- which every membership and geometry commit runs --
--- would ClearAllPoints and put the panel back where the compensation had just
--- taken it from, and a /reload would do the same. There is no double
--- application: after this pass the live points and the saved anchor describe
--- one position, and the next resize measures old == new and computes a zero
--- delta.
--- Returns the updated saved anchor offsets when they moved, so the caller can
--- refresh the drag coordinate readout.
function ST.CompensatePanelSectionAnchorDrift(frame, group, layout, fixedPoint, canCompensate,
                                              oldWidth, oldHeight, newWidth, newHeight)
    local GetAnchorOffset = ST._GetPanelAnchorOffset
    local savedX, savedY
    local anchorPoint = (group.anchor and group.anchor.point) or "CENTER"
    -- Without a pinned edge the panel holds the point it is anchored by, which
    -- is what an unsectioned panel does on its own.
    local holdPoint = fixedPoint or anchorPoint

    local newBaseX, newBaseY = 0, 0
    local newBaseW, newBaseH = newWidth, newHeight
    if layout and layout.totalWidth > 0 then
        newBaseX, newBaseY = layout.baseOffsetX, layout.baseOffsetY
        newBaseW, newBaseH = layout.baseWidth, layout.baseHeight
    end

    -- Nothing stamped yet means the panel was unsectioned on its previous
    -- resize, and an unsectioned panel's base cluster IS its frame -- which is
    -- what these defaults say. That makes the very first section to appear
    -- compensate like every later change instead of jumping once.
    local oldBaseX = frame._sectionBaseOffsetX or 0
    local oldBaseY = frame._sectionBaseOffsetY or 0
    local oldBaseW = frame._sectionBaseWidth or oldWidth
    local oldBaseH = frame._sectionBaseHeight or oldHeight
    if canCompensate and GetAnchorOffset then
        local oldHoldX, oldHoldY = GetAnchorOffset(holdPoint, oldBaseW, oldBaseH)
        local newHoldX, newHoldY = GetAnchorOffset(holdPoint, newBaseW, newBaseH)
        local oldAnchorX, oldAnchorY = GetAnchorOffset(anchorPoint, oldWidth, oldHeight)
        local newAnchorX, newAnchorY = GetAnchorOffset(anchorPoint, newWidth, newHeight)

        -- The hold point measured from the frame's own anchor point, before and
        -- after. The difference is how far the base cluster just slid.
        local oldX = (-oldWidth / 2 + oldBaseX + oldBaseW / 2 + oldHoldX) - oldAnchorX
        local oldY = (oldHeight / 2 - oldBaseY - oldBaseH / 2 + oldHoldY) - oldAnchorY
        local newX = (-newWidth / 2 + newBaseX + newBaseW / 2 + newHoldX) - newAnchorX
        local newY = (newHeight / 2 - newBaseY - newBaseH / 2 + newHoldY) - newAnchorY

        local deltaX, deltaY = oldX - newX, oldY - newY
        if deltaX ~= 0 or deltaY ~= 0 then
            frame:AdjustPointsOffset(deltaX, deltaY)

            -- Persist it, but only onto an anchor that actually describes the
            -- point AdjustPointsOffset just moved. AnchorGroupFrame has three
            -- fallbacks -- the owning container's TOPLEFT, the force-center
            -- recovery, and the cursor anchor -- that place the frame by rules
            -- of their own and whose saved offsets mean something else; the
            -- point/relativePoint match is what tells them apart.
            local anchor = group.anchor
            if type(anchor) == "table" then
                local point, _, relativePoint = frame:GetPoint(1)
                if point == anchor.point and relativePoint == anchor.relativePoint then
                    savedX = (tonumber(anchor.x) or 0) + deltaX
                    savedY = (tonumber(anchor.y) or 0) + deltaY
                    anchor.x = savedX
                    anchor.y = savedY
                end
            end
        end
    end

    if layout then
        frame._sectionBaseOffsetX = newBaseX
        frame._sectionBaseOffsetY = newBaseY
        frame._sectionBaseWidth = newBaseW
        frame._sectionBaseHeight = newBaseH
    else
        -- The panel just collapsed back onto its base cluster; stop tracking so
        -- the plain frame-based compensation owns it again from here.
        frame._sectionBaseOffsetX = nil
        frame._sectionBaseOffsetY = nil
        frame._sectionBaseWidth = nil
        frame._sectionBaseHeight = nil
    end

    return savedX, savedY
end
