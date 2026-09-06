--[[
    CooldownCompanion - Core/PanelSections.lua: panel section membership,
    per-section geometry, and the shared layout metrics Core/GroupFrame.lua
    positions its live buttons from.

    A SECTION is a small placed cluster of icons pinned to one of the eight
    anchor points of an icon panel's BASE GRID (four corners, four edge
    midpoints). Membership is EXPLICIT per entry (buttonData.section): nothing
    ever migrates on its own, so the base grid's wrap math, buttonsPerRow, and
    auto-max behavior are untouched by the feature. A section owns only its
    icon size, spacing, X/Y offset, and wrap count; every other styling key
    stays panel-wide, text included.

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
local math_floor = math.floor
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

-- Anchor implies the lines' direction and which side of the base cluster they
-- sit on. The owner can cap the line length (section.maxPerLine); direction
-- itself is the anchor's alone -- there are no growth or orientation controls.
--   axis "h" = horizontal lines, "v" = vertical lines.
--   side     = which outside face of the base cluster the cluster sits against.
--   from     = where entry 1 sits on a line: "low" is the left/top end,
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

--- One anchor's placement under the panel's current orientation: axis, side,
--- and fill direction. The config surface words its per-section controls off
--- this so the one table above stays the only authority on which way an
--- anchor grows.
function ST.GetPanelSectionPlacement(group, anchor)
    local style = (group and group.style) or {}
    local orientation = ST.GetPanelLayoutOrientation(
        (group and group.displayMode) or "icons", style)
    local placements = SECTION_PLACEMENT[orientation] or SECTION_PLACEMENT.horizontal
    local placement = placements[anchor]
    if not placement then return nil end
    return placement.axis, placement.side, placement.from
end

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

--- Drop a wrap count that no longer wraps. A stored maxPerLine at or above
--- the member count is indistinguishable from "one line" on screen and in
--- the wrap slider (whose top-of-range stores nil), but left behind it
--- silently revives as a cap when members are added later. Departures only:
--- an arrival can only make an existing cap MORE real.
local function NormalizePanelSectionWrap(group, anchor)
    local sections = group and group.sections
    local section = type(sections) == "table" and anchor and sections[anchor] or nil
    if type(section) ~= "table" or section.maxPerLine == nil then return end
    local count = 0
    for _, buttonData in ipairs(group.buttons or {}) do
        if ST.GetPanelSectionForEntry(group, buttonData) == anchor then
            count = count + 1
        end
    end
    if (tonumber(section.maxPerLine) or 0) >= count then
        section.maxPerLine = nil
    end
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
        NormalizePanelSectionWrap(group, rawPrevious)
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
    NormalizePanelSectionWrap(group, anchor)
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
---   sections[anchor] = {
---       width, height,                -- one member's cell
---       positions = { {x, y}, ... },  -- member k's TOPLEFT from the frame's
---                                        TOPLEFT; the ONLY per-member truth
---                                        (a wrapped section is not a line, so
---                                        no origin+step can describe it)
---       originX, originY, stepX, stepY, -- line 1 as origin+step, kept for the
---                                        config preview's lane math; describes
---                                        the whole section only while unwrapped
---       axis, side, from, spacing,    -- the anchor's placement actually used
---       perLine,                      -- resolved wrap count (nil = unwrapped)
---       lineX, lineY,                 -- the whole block's rectangle, also
---       lineWidth, lineHeight,           from the frame's TOPLEFT
---   }
--- An AURA section additionally carries auraOnly = true. Blizzard's container
--- lays its cells out inside the block rectangle following axis/side/from, so
--- the per-member positions serve only the unlock placeholder tiles there.
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
    -- An empty base retains one cell; sections never become its anchor body.
    local baseWidth, baseHeight = panelWidth, panelHeight
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

            -- The fill direction and the SIDE the cluster sits on are the
            -- anchor's alone (owner ruling 2026-08-28: a per-section fill
            -- override was built, seen, and removed -- do not revive it).
            local from = placement.from

            -- Wrap count. nil is the founding behavior: one unbroken line.
            -- Extra lines stack AWAY from the base cluster with line 1 nearest
            -- it, and a partial line aligns to the same end (or center) the
            -- fill direction names -- exactly how Blizzard's flow layout packs
            -- an aura section's cells, so the two engines cannot disagree.
            local maxPerLine = tonumber(section.maxPerLine)
            local perLine = count
            if maxPerLine then
                maxPerLine = math_max(1, math_floor(maxPerLine))
                if maxPerLine < perLine then perLine = maxPerLine end
            end
            local lineCount = math_ceil(count / perLine)

            local positions = {}
            local info = {
                width = width, height = height,
                positions = positions,
                -- The placement actually used, override folded in. Taken from
                -- SECTION_PLACEMENT here rather than re-derived by a consumer,
                -- so one table still answers "which way does this anchor grow"
                -- for both engines.
                axis = placement.axis,
                side = placement.side,
                from = from,
                spacing = spacing,
                perLine = maxPerLine and perLine or nil,
            }

            if placement.axis == "h" then
                local blockWidth = perLine * width + (perLine - 1) * spacing
                local blockHeight = lineCount * height + (lineCount - 1) * spacing
                local left
                if from == "low" then
                    left = 0
                elseif from == "high" then
                    left = baseWidth - blockWidth
                else
                    left = (baseWidth - blockWidth) / 2
                end
                -- The block sits OUTSIDE the cluster, one panel spacing clear
                -- of the face its anchor names.
                local top = (placement.side == "above")
                    and (panelSpacing + blockHeight)
                    or (-baseHeight - panelSpacing)
                left = left + offsetX
                top = top + offsetY

                info.lineX, info.lineY = left, top
                info.lineWidth, info.lineHeight = blockWidth, blockHeight

                for index = 1, count do
                    local line = math_ceil(index / perLine)
                    local slot = index - (line - 1) * perLine
                    local inLine = math_min(perLine, count - (line - 1) * perLine)
                    local lineLength = inLine * width + (inLine - 1) * spacing
                    local lineLeft
                    if from == "low" then
                        lineLeft = left
                    elseif from == "high" then
                        lineLeft = left + blockWidth - lineLength
                    elseif auraCount then
                        -- Blizzard's flow layout packs a centered section's
                        -- PARTIAL line from the flow origin, not centered, so
                        -- an aura section's reserved cells must promise the
                        -- same spots its container will fill. Full lines are
                        -- unaffected (lineLength == blockWidth); ordinary
                        -- icon sections keep their centered partial lines.
                        lineLeft = left
                    else
                        lineLeft = left + (blockWidth - lineLength) / 2
                    end
                    local x
                    if from == "high" then
                        -- Entry 1 holds the line's right end and the line grows
                        -- back toward the panel's far side.
                        x = lineLeft + lineLength - slot * width - (slot - 1) * spacing
                    else
                        x = lineLeft + (slot - 1) * (width + spacing)
                    end
                    local y
                    if placement.side == "above" then
                        -- Line 1 nearest the cluster; later lines climb away.
                        y = top - blockHeight + line * height + (line - 1) * spacing
                    else
                        y = top - (line - 1) * (height + spacing)
                    end
                    positions[index] = { x = x, y = y }
                end

                info.stepX = (from == "high") and -(width + spacing) or (width + spacing)
                info.stepY = 0

                if left < minX then minX = left end
                if left + blockWidth > maxX then maxX = left + blockWidth end
                if top > maxY then maxY = top end
                if top - blockHeight < minY then minY = top - blockHeight end
            else
                local blockHeight = perLine * height + (perLine - 1) * spacing
                local blockWidth = lineCount * width + (lineCount - 1) * spacing
                local top
                if from == "low" then
                    top = 0
                elseif from == "high" then
                    top = -baseHeight + blockHeight
                else
                    top = (blockHeight - baseHeight) / 2
                end
                local left = (placement.side == "left")
                    and (-panelSpacing - blockWidth)
                    or (baseWidth + panelSpacing)
                left = left + offsetX
                top = top + offsetY

                info.lineX, info.lineY = left, top
                info.lineWidth, info.lineHeight = blockWidth, blockHeight

                for index = 1, count do
                    local line = math_ceil(index / perLine)
                    local slot = index - (line - 1) * perLine
                    local inLine = math_min(perLine, count - (line - 1) * perLine)
                    local lineLength = inLine * height + (inLine - 1) * spacing
                    local lineTop
                    if from == "low" then
                        lineTop = top
                    elseif from == "high" then
                        lineTop = top - blockHeight + lineLength
                    elseif auraCount then
                        -- The vertical twin of the aura partial-line rule
                        -- above: pack from the flow origin, never centered.
                        lineTop = top
                    else
                        lineTop = top - (blockHeight - lineLength) / 2
                    end
                    local y
                    if from == "high" then
                        -- Entry 1 sits at the column's bottom end and climbs.
                        y = lineTop - lineLength + slot * height + (slot - 1) * spacing
                    else
                        y = lineTop - (slot - 1) * (height + spacing)
                    end
                    local x
                    if placement.side == "left" then
                        -- Column 1 nearest the cluster; later columns step away.
                        x = left + blockWidth - line * width - (line - 1) * spacing
                    else
                        x = left + (line - 1) * (width + spacing)
                    end
                    positions[index] = { x = x, y = y }
                end

                info.stepX = 0
                info.stepY = (from == "high") and (height + spacing) or -(height + spacing)

                if left < minX then minX = left end
                if left + blockWidth > maxX then maxX = left + blockWidth end
                if top > maxY then maxY = top end
                if top - blockHeight < minY then minY = top - blockHeight end
            end

            -- Line 1 restated as origin+step for the config preview's lane
            -- math, which still reasons about a section as one segment. True
            -- for the whole section exactly while it is unwrapped.
            info.originX = positions[1].x
            info.originY = positions[1].y

            if auraCount then
                info.auraOnly = true
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
        info.lineX = info.lineX + layout.baseOffsetX
        info.lineY = info.lineY - layout.baseOffsetY
        for _, position in ipairs(info.positions) do
            position.x = position.x + layout.baseOffsetX
            position.y = position.y - layout.baseOffsetY
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
    anchorFrame:SetSize(math_max(1, layout.baseWidth), math_max(1, layout.baseHeight))
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
--- The one exception (owner ruling 2026-09-03): the attached resource-bar
--- stack and cast bar anchor to the panel FRAME, the union, so they sit past
--- every section instead of across one -- what the Live Preview's lanes have
--- always shown. They do not call this.
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
            -- section here, spanning the FULL expanded block, exactly the way an
            -- Aura Panel's frame spans its full expanded grid.
            local host = AcquireAuraSectionHost(frame, anchor)
            host:SetSize(math_max(1, info.lineWidth), math_max(1, info.lineHeight))
            host:ClearAllPoints()
            host:SetPoint("TOPLEFT", frame, "TOPLEFT", info.lineX, info.lineY)
            host:Show()
        else
            local members = lists.members[anchor]
            for index, button in ipairs(members or {}) do
                local position = info.positions[index]
                if position then
                    ST.ApplyPanelSectionButtonSize(button, info.width, info.height)
                    -- Section members never ride the compact slot cache: the cache keys
                    -- on anchor/x/y alone and cannot tell the panel frame from the base
                    -- anchor frame, so a member crossing that boundary would otherwise
                    -- keep a stale relative frame.
                    button._compactSlotAnchor = nil
                    button._compactSlotX = nil
                    button._compactSlotY = nil
                    button:ClearAllPoints()
                    button:SetPoint("TOPLEFT", frame, "TOPLEFT", position.x, position.y)
                end
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
--- The outer-frame correction is deliberately left behind: the resize that
--- follows this pass still needs it to hold the base grid
--- still while the frame collapses back onto it. UpdatePanelBaseAnchor clears it
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
    the same per-cell positions a plain section's live buttons are placed with --
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
                    local position = info.positions[cell]
                    tile:SetSize(info.width, info.height)
                    tile:ClearAllPoints()
                    tile:SetPoint("TOPLEFT", frame, "TOPLEFT",
                        position and position.x or info.originX,
                        position and position.y or info.originY)

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
-- UNLOCK SECTION MOVERS
------------------------------------------------------------------------

--[[
    While a panel's drag chrome is up, every section wears a thin clickable
    overlay spanning its block rectangle. Clicking one selects the SECTION
    (CooldownCompanion:ActivateArrangeSection), and the panel's ONE chrome
    kit -- wheel, size and coord readouts, grip, nudger -- retargets to it
    and goes gold to say so (owner ruling 2026-08-29: selection recolors the
    existing chrome; never grow a second chrome surface for a section).

    The overlays are pure unlock chrome: created once per frame per anchor,
    shown on the aura placeholder preview's wide gate (drag controls up, or
    any member of an active container preview -- unlock-all must reveal what
    is addressable), forced down for combat alongside that preview, and
    positioned only ever from the layout pass's own block rect
    (lineX/lineY/lineWidth/lineHeight) -- no geometry is derived here.
    _ccNoTouch keeps the strata and click-through walks out of them, exactly
    like the aura hosts; drags that start on one are forwarded to the panel
    frame so grabbing a section's air still moves the panel.
]]

-- The container member overlay's blue for hover, the house gold for selected
-- (the arrange tree's selected row and the drag grammar's snap accent).
local SECTION_OVERLAY_COLOR = { 0.6, 0.8, 1 }
local SECTION_OVERLAY_SELECTED_COLOR = { 1, 0.82, 0 }
local SECTION_OVERLAY_IDLE_BORDER_ALPHA = 0.35
local SECTION_OVERLAY_HOVER_FILL_ALPHA = 0.12
local SECTION_OVERLAY_SELECTED_FILL_ALPHA = 0.18
local SECTION_OVERLAY_SELECTED_BORDER_ALPHA = 0.9

local function PaintSectionOverlay(overlay)
    local selected = overlay._selected == true
    local color = selected and SECTION_OVERLAY_SELECTED_COLOR or SECTION_OVERLAY_COLOR
    local fillAlpha = 0
    if selected then
        fillAlpha = SECTION_OVERLAY_SELECTED_FILL_ALPHA
    elseif overlay._hovered then
        fillAlpha = SECTION_OVERLAY_HOVER_FILL_ALPHA
    end
    overlay.bg:SetColorTexture(color[1], color[2], color[3], fillAlpha)
    ST.ApplyBorderTextures(overlay.border, overlay,
        { color[1], color[2], color[3],
          selected and SECTION_OVERLAY_SELECTED_BORDER_ALPHA or SECTION_OVERLAY_IDLE_BORDER_ALPHA },
        1, ST.BORDER_RENDER_MODE_CRISP)
end

------------------------------------------------------------------
-- The SELECTED section's own resize grabber (owner ruling 2026-08-29,
-- twice asked: a section resizes by a grabber on ITS corner, the way a
-- panel resizes by the grabber on its corner). The panel's grip stays
-- base-cluster-scoped always. One small gold grabber appears on the
-- selected overlay's outward corner and scales the section's cells.
------------------------------------------------------------------

local function ClampSectionSize(value)
    return math_max(10, math_min(150, ST.RoundToTenths(tonumber(value) or 10)))
end

local function ResolveOverlaySection(overlay)
    local frame = overlay:GetParent()
    local groupId = frame and frame.groupId
    local group = groupId and CooldownCompanion.db.profile.groups[groupId]
    local sections = group and group.sections
    local section = type(sections) == "table"
        and sections[overlay._sectionAnchor] or nil
    if type(section) ~= "table" then return nil end
    return groupId, group, section
end

local function RefreshConfigPanelIfShown()
    local configState = ST._configState
    local configFrame = configState and configState.configFrame
    local shownFrame = configFrame and configFrame.frame
    if shownFrame and shownFrame:IsShown() then
        CooldownCompanion:RefreshConfigPanel()
    end
end

local function EndSectionGripGesture(grip, applyFinal)
    if not grip._resizeActive then
        grip:SetScript("OnUpdate", nil)
        return
    end
    grip._resizeActive = nil
    grip:SetScript("OnUpdate", nil)
    if applyFinal then
        RefreshConfigPanelIfShown()
    end
    grip._resizeStartX, grip._resizeStartY = nil, nil
    grip._resizeStartW, grip._resizeStartH = nil, nil
    grip._resizeCols, grip._resizeRows = nil, nil
    grip._resizeSignX, grip._resizeSignY = nil, nil
    grip._resizeSingle = nil
end

local function UpdateSectionGripGesture(grip)
    if not grip._resizeActive then return end
    if InCombatLockdown() or CooldownCompanion._combatForcedLock then
        EndSectionGripGesture(grip, false)
        return
    end
    local overlay = grip:GetParent()
    local groupId, _, section = ResolveOverlaySection(overlay)
    if not groupId then
        EndSectionGripGesture(grip, false)
        return
    end
    local cursorX, cursorY = GetCursorPosition()
    local scale = UIParent:GetEffectiveScale()
    if not (cursorX and scale and scale > 0) then return end
    cursorX, cursorY = cursorX / scale, cursorY / scale

    -- Per-cell deltas: the drag scales every cell of the block, so the
    -- travel divides by the block's cell counts on each axis.
    local dw = grip._resizeSignX * (cursorX - grip._resizeStartX) / grip._resizeCols
    local dh = grip._resizeSignY * (cursorY - grip._resizeStartY) / grip._resizeRows
    local changed = false
    if grip._resizeSingle then
        local newSize = ClampSectionSize(grip._resizeStartW + (dw + dh) / 2)
        if section.iconWidth ~= newSize then
            section.iconWidth = newSize
            changed = true
        end
    else
        local newWidth = ClampSectionSize(grip._resizeStartW + dw)
        local newHeight = ClampSectionSize(grip._resizeStartH + dh)
        if section.iconWidth ~= newWidth then
            section.iconWidth = newWidth
            changed = true
        end
        if section.iconHeight ~= newHeight then
            section.iconHeight = newHeight
            changed = true
        end
    end
    if changed then
        CooldownCompanion:UpdateGroupStyle(groupId)
    end
end

local function BeginSectionGripGesture(grip)
    if grip._resizeActive or InCombatLockdown()
        or CooldownCompanion._combatForcedLock then
        return
    end
    local overlay = grip:GetParent()
    local groupId, group = ResolveOverlaySection(overlay)
    if not groupId then return end
    local cursorX, cursorY = GetCursorPosition()
    local scale = UIParent:GetEffectiveScale()
    if not (cursorX and scale and scale > 0) then return end

    grip._resizeStartX = cursorX / scale
    grip._resizeStartY = cursorY / scale
    grip._resizeStartW = ClampSectionSize(overlay._cellWidth)
    grip._resizeStartH = ClampSectionSize(overlay._cellHeight)
    grip._resizeCols = math_max(1, overlay._resizeCols or 1)
    grip._resizeRows = math_max(1, overlay._resizeRows or 1)
    -- Dragging the outward corner away from the cluster grows the cells.
    grip._resizeSignX = (grip._cornerX == "LEFT") and -1 or 1
    grip._resizeSignY = (grip._cornerY == "TOP") and 1 or -1
    grip._resizeSingle = (group.style and group.style.maintainAspectRatio) == true
    grip._resizeActive = true
    grip:SetScript("OnUpdate", UpdateSectionGripGesture)
end

local function AcquireSectionOverlayGrip(overlay)
    local grip = overlay._grip
    if grip then return grip end
    grip = CreateFrame("Button", nil, overlay)
    grip:SetSize(16, 16)
    -- The house corner bracket (see ST.ApplyCornerBracketGrip), permanently
    -- GOLD: this grabber only exists while its section is selected, and gold
    -- is the selected-section contract everywhere else in the chrome.
    ST.ApplyCornerBracketGrip(grip, "RIGHT", "BOTTOM")
    ST.SetCornerBracketGripColor(grip, 1, 0.82, 0)
    grip:SetScript("OnMouseDown", function(self, mouseButton)
        if mouseButton == "LeftButton" then
            BeginSectionGripGesture(self)
        end
    end)
    grip:SetScript("OnMouseUp", function(self, mouseButton)
        if mouseButton == "LeftButton" then
            EndSectionGripGesture(self,
                not CooldownCompanion._combatForcedLock and not InCombatLockdown())
        end
    end)
    grip:SetScript("OnHide", function(self)
        GameTooltip:Hide()
        EndSectionGripGesture(self,
            not CooldownCompanion._combatForcedLock and not InCombatLockdown())
    end)
    grip:SetScript("OnEnter", function(self)
        -- Brighter gold, never white: gold is what says "acts on the section".
        ST.SetCornerBracketGripColor(self, 1, 0.92, 0.4, 1)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Resize Section")
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Mouse wheel over the panel also resizes the selected section.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    grip:SetScript("OnLeave", function(self)
        ST.SetCornerBracketGripColor(self, 1, 0.82, 0)
        GameTooltip:Hide()
    end)
    grip:Hide()
    overlay._grip = grip
    return grip
end

-- The grabber lives on the SECTION's bottom-right corner, always -- the
-- exact grammar the panel's own corner grabber taught (owner ruling
-- 2026-08-29; an "outward corner" placement moved with the anchor and read
-- as noise).
local function PositionSectionOverlayGrip(overlay, grip)
    grip._cornerX, grip._cornerY = "RIGHT", "BOTTOM"
    -- Above the panel's labels (chrome band +4/+5 vs the overlay's +3), so
    -- the grabber stays clickable when a bottom section overlaps them.
    grip:SetFrameLevel(overlay:GetFrameLevel() + 3)
    grip:ClearAllPoints()
    grip:SetPoint("BOTTOMRIGHT", overlay, "BOTTOMRIGHT", -1, 1)
end

local function AcquireSectionMoverOverlay(frame, anchor)
    local overlays = frame._sectionMoverOverlays
    if not overlays then
        overlays = {}
        frame._sectionMoverOverlays = overlays
    end
    local overlay = overlays[anchor]
    if overlay then return overlay end

    overlay = CreateFrame("Frame", nil, frame)
    overlay._ccNoTouch = true
    overlay._sectionAnchor = anchor
    overlay:EnableMouse(true)
    overlay:RegisterForDrag("LeftButton")
    overlay.bg = overlay:CreateTexture(nil, "BACKGROUND")
    overlay.bg:SetAllPoints()
    overlay.border = ST.CreateBorderTextureSet(overlay, "OVERLAY")
    overlay:SetScript("OnEnter", function(self)
        self._hovered = true
        PaintSectionOverlay(self)
    end)
    overlay:SetScript("OnLeave", function(self)
        self._hovered = nil
        PaintSectionOverlay(self)
    end)
    overlay:SetScript("OnMouseUp", function(self, mouseButton)
        local parent = self:GetParent()
        if not (parent and parent.groupId) then return end
        -- Release-suppression contract, OVERLAY-OWNED: a drag forwarded from
        -- here must never read as a click on release, regardless of which
        -- panel drag branch ran (the container-preview branch does not set
        -- the panel's own suppression flag). Both flags are consumed here so
        -- a stale one can never eat the next deliberate click; the panel's
        -- flag is still honored for the ordinary body-drag branch.
        local forwarded = self._forwardedDrag or self._suppressNextClick
        self._forwardedDrag = nil
        self._suppressNextClick = nil
        local suppressed = parent._arrangeSelectClickSuppressed
        parent._arrangeSelectClickSuppressed = nil
        if forwarded or suppressed
            or mouseButton ~= "LeftButton" or parent._dragInProgress then
            return
        end
        CooldownCompanion:ActivateArrangeSection(parent.groupId, self._sectionAnchor, true)
    end)
    -- A drag that starts on the overlay is a drag of the PANEL, selected or
    -- not (owner ruling 2026-08-29, reversed same day after trying a
    -- drag-to-move: sections position by nudger, typed offsets, and sliders
    -- only -- do not revive an offset drag). Forwarding keeps the panel
    -- grabbable by its sections.
    overlay:SetScript("OnDragStart", function(self)
        self._forwardedDrag = true
        local parent = self:GetParent()
        -- In a container preview the panel's own drag handler refuses an
        -- UNSELECTED member (the container's member overlay normally selects
        -- it first, but this overlay sits above that one and takes the
        -- gesture). Select the panel the same way before forwarding, so the
        -- first drag moves it instead of dying.
        local groupId = parent and parent.groupId
        local group = groupId and CooldownCompanion.db.profile.groups[groupId]
        local containerId = group and group.parentContainerId
        if containerId
            and CooldownCompanion:IsContainerUnlockPreviewActive(containerId)
            and not CooldownCompanion:IsContainerPanelSelected(containerId, groupId) then
            CooldownCompanion:ActivateArrangePanel(containerId, groupId, false)
        end
        local handler = parent and parent:GetScript("OnDragStart")
        if handler then handler(parent) end
    end)
    overlay:SetScript("OnDragStop", function(self)
        -- Either release order is safe: stop-then-up consumes the pending
        -- flag, up-then-stop already consumed _forwardedDrag.
        if self._forwardedDrag then
            self._forwardedDrag = nil
            self._suppressNextClick = true
        end
        local parent = self:GetParent()
        local handler = parent and parent:GetScript("OnDragStop")
        if handler then handler(parent) end
    end)
    overlay:Hide()
    overlays[anchor] = overlay
    return overlay
end

--- Re-fit, repaint, or hide every section overlay from the current layout and
--- selection. Safe to call from every geometry pass: a frame whose overlays
--- were never shown pays one flag test.
function ST.UpdateSectionMoverOverlays(addon, frame, group)
    if not frame then return end
    local overlays = frame._sectionMoverOverlays
    local infos = frame._sectionLayout and frame._sectionLayout.sections or nil
    local shown = frame._sectionMoverOverlaysShown == true
        and infos ~= nil
        and ST.PanelSupportsSections(group)
    if not shown then
        if overlays then
            for _, overlay in pairs(overlays) do overlay:Hide() end
        end
        return
    end

    local selectedAnchor = addon.GetArrangeSelectedSectionAnchor
        and addon:GetArrangeSelectedSectionAnchor(frame.groupId) or nil
    -- Stacking: while the panel's own chrome is up, the overlays join ITS
    -- band just under the resize grip (SyncGroupControlLevels puts the grip
    -- at handle+4), so the grip and labels stay clickable when a section
    -- overlaps them. With no chrome up -- an unselected container-preview
    -- member -- they pin high instead: the wrapper's chrome would otherwise
    -- draw over them (P3 finding).
    local handle = frame.dragHandle
    local chromeUp = handle and handle:IsShown() or false
    for _, anchor in ipairs(ST.PANEL_SECTION_ANCHORS) do
        local info = infos[anchor]
        local overlay = overlays and overlays[anchor]
        if info then
            overlay = overlay or AcquireSectionMoverOverlay(frame, anchor)
            overlays = frame._sectionMoverOverlays
            if chromeUp then
                overlay:SetFrameStrata(handle:GetFrameStrata())
                overlay:SetFrameLevel((handle:GetFrameLevel() or 1) + 3)
            else
                overlay:SetFrameStrata("FULLSCREEN_DIALOG")
                overlay:SetFrameLevel(85)
            end
            overlay:SetSize(math_max(1, info.lineWidth), math_max(1, info.lineHeight))
            overlay:ClearAllPoints()
            overlay:SetPoint("TOPLEFT", frame, "TOPLEFT", info.lineX, info.lineY)
            -- What the selected-section grabber reads: the placement, the
            -- resolved cell, and the block's cell counts per axis (its drag
            -- divides the travel by these).
            overlay._axis = info.axis
            overlay._side = info.side
            overlay._cellWidth = info.width
            overlay._cellHeight = info.height
            local count = math_max(1, #info.positions)
            local perLine = math_max(1, math_min(info.perLine or count, count))
            local lineCount = math_ceil(count / perLine)
            if info.axis == "h" then
                overlay._resizeCols, overlay._resizeRows = perLine, lineCount
            else
                overlay._resizeCols, overlay._resizeRows = lineCount, perLine
            end
            overlay._selected = selectedAnchor == anchor
            PaintSectionOverlay(overlay)
            if overlay._selected then
                local grip = AcquireSectionOverlayGrip(overlay)
                PositionSectionOverlayGrip(overlay, grip)
                grip:Show()
            elseif overlay._grip then
                overlay._grip:Hide()
            end
            overlay:Show()
        elseif overlay then
            overlay:Hide()
        end
    end
end

--- The one visibility switch, driven by the same paths that raise and drop the
--- panel's drag controls (and the combat forced lock, which bypasses them).
function ST.SetSectionMoverOverlaysShown(addon, frame, group, shown)
    if not frame then return end
    frame._sectionMoverOverlaysShown = (shown == true) or nil
    ST.UpdateSectionMoverOverlays(addon, frame, group)
end

------------------------------------------------------------------------
-- BASE-GRID ANCHORING
------------------------------------------------------------------------

-- Offset of a point on the base grid from the same point on the outer frame.
-- These are exact layout dimensions, never rounded frame measurements.
local function BasePointOffset(point, width, height, baseX, baseY, baseWidth, baseHeight)
    local GetAnchorOffset = ST._GetPanelAnchorOffset
    local ax, ay = GetAnchorOffset(point, width, height)
    local bx, by = GetAnchorOffset(point, baseWidth, baseHeight)
    return -width / 2 + baseX + baseWidth / 2 + bx - ax,
        height / 2 - baseY - baseHeight / 2 + by - ay
end

function ST.GetPanelBasePointOffset(frame, point)
    local layout = frame._sectionLayout
    if not layout then return 0, 0 end
    return BasePointOffset(point, layout.footprintWidth, layout.footprintHeight,
        layout.baseOffsetX, layout.baseOffsetY, layout.baseWidth, layout.baseHeight)
end

function ST.SetPanelBasePoint(frame, point, relativeFrame, relativePoint, x, y)
    local group = ST.Addon.db.profile.groups[frame.groupId]
    local dx, dy = 0, 0
    -- Legacy positions are converted once the first real layout is available.
    if group and group.baseRowAnchorVersion == 1 then
        dx, dy = ST.GetPanelBasePointOffset(frame, point)
    end
    frame:SetPoint(point, relativeFrame, relativePoint, x - dx, y - dy)
    frame._panelBaseCorrectionX, frame._panelBaseCorrectionY = -dx, -dy
    frame._panelBasePoint = point
    local anchor = group and group.anchor
    local target = anchor and _G[anchor.relativeTo or "UIParent"]
    frame._panelBaseUsesSavedAnchor = anchor and point == anchor.point
        and ((relativeFrame == ST.GetPanelAnchorBodyFrame(target) and relativePoint == anchor.relativePoint)
            or ST.Addon:IsCursorAnchor(anchor)) or false
end

function ST.UpdatePanelBaseAnchor(frame, group, layout, fixedPoint, newWidth, newHeight)
    -- A compact refresh first measures all materialized entries. Only its
    -- final visible layout may migrate or update the saved base coordinates.
    if frame._deferPanelBaseAnchor then return end
    local anchor = group.anchor
    if not anchor then return end
    local point = frame._panelBasePoint or anchor.point or "CENTER"
    local dx, dy = ST.GetPanelBasePointOffset(frame, point)
    local migrationX, migrationY = 0, 0
    if group.baseRowAnchorVersion ~= 1 then
        -- Old offsets positioned the union. Convert its base point once, using
        -- the saved footprint from the earlier compensation fix when present.
        local geometry = anchor.sectionGeometry
        if type(geometry) == "table" then
            migrationX, migrationY = BasePointOffset(anchor.point or "CENTER", geometry.width, geometry.height,
                geometry.baseX, geometry.baseY, geometry.baseWidth, geometry.baseHeight)
        else
            migrationX, migrationY = ST.GetPanelBasePointOffset(frame, anchor.point or "CENTER")
        end
        anchor.x = (anchor.x or 0) + migrationX
        anchor.y = (anchor.y or 0) + migrationY
        if type(geometry) == "table" then
            anchor.baseWidth, anchor.baseHeight = geometry.baseWidth, geometry.baseHeight
        end
        anchor.sectionGeometry = nil
        group.baseRowAnchorVersion = 1
        if not frame._panelBaseUsesSavedAnchor then migrationX, migrationY = 0, 0 end
    end

    local baseWidth = layout and layout.baseWidth or newWidth
    local baseHeight = layout and layout.baseHeight or newHeight
    local growthX, growthY = 0, 0
    -- Coordinates and their exact base dimensions travel together, including
    -- through refreshes and reloads. A fresh anchor has no dimensions yet and
    -- establishes its baseline here. Section dimensions never participate.
    local oldBaseW, oldBaseH = anchor.baseWidth, anchor.baseHeight
    if fixedPoint and oldBaseW and oldBaseH and frame._panelBaseUsesSavedAnchor then
        local oldFx, oldFy = ST._GetPanelAnchorOffset(fixedPoint, oldBaseW, oldBaseH)
        local oldAx, oldAy = ST._GetPanelAnchorOffset(point, oldBaseW, oldBaseH)
        local newFx, newFy = ST._GetPanelAnchorOffset(fixedPoint, baseWidth, baseHeight)
        local newAx, newAy = ST._GetPanelAnchorOffset(point, baseWidth, baseHeight)
        growthX, growthY = oldFx - oldAx - newFx + newAx, oldFy - oldAy - newFy + newAy
    end
    if growthX ~= 0 or growthY ~= 0 then
        anchor.x = (anchor.x or 0) + growthX
        anchor.y = (anchor.y or 0) + growthY
    end
    local moveX = -dx - (frame._panelBaseCorrectionX or 0) + migrationX + growthX
    local moveY = -dy - (frame._panelBaseCorrectionY or 0) + migrationY + growthY
    if moveX ~= 0 or moveY ~= 0 then frame:AdjustPointsOffset(moveX, moveY) end
    frame._panelBaseCorrectionX, frame._panelBaseCorrectionY = -dx, -dy
    if frame._panelBaseUsesSavedAnchor then
        anchor.baseWidth, anchor.baseHeight = baseWidth, baseHeight
    end
    return anchor.x, anchor.y
end