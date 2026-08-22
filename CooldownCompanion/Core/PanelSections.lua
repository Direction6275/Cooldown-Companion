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

local CreateFrame = CreateFrame
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

    for anchor, section in pairs(sections) do
        local members = lists.members[anchor]
        local count = members and #members or 0
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
        for index, button in ipairs(lists.members[anchor]) do
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
function ST.PrepareSectionedPanelLayout(frame, group, buttons, panelWidth, panelHeight, panelSpacing, headerHeight)
    local sections = ST.GetSectionsForLayout(group)
    if not sections then
        ST.ClearPanelSectionLayout(frame, group, panelWidth, panelHeight)
        return nil, nil, nil
    end

    local lists = ST.PartitionPanelSectionMembers(group, buttons, frame._sectionMemberLists)
    frame._sectionMemberLists = lists

    local layout = ST.BuildPanelSectionLayout(
        group, sections, lists, panelWidth, panelHeight, panelSpacing, headerHeight, frame._sectionLayout)
    frame._sectionLayout = layout

    local baseAnchor = AcquireBaseAnchorFrame(frame, layout)
    PlaceSectionMembers(frame, lists, layout, panelWidth, panelHeight)

    return layout, lists, baseAnchor
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
