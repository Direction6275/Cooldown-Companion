--[[
    CooldownCompanion - ButtonPanelPreviewSections
    Section landing targets, lane feedback, and section/cursor-drop resolution.

    Part of the ButtonPanelPreview family; see its ordered block in the addon TOC.
    Private helpers are shared through ST._ButtonPanelPreview.
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon
local CS = ST._configState
local math_min = math.min
local math_max = math.max
local StartDragTracking = ST._StartDragTracking
local CancelDrag = ST._CancelDrag

local PP = ST._ButtonPanelPreview

-- ButtonPanelPreviewShared.lua
local PANEL_PREVIEW_RING_COLOR = PP.PANEL_PREVIEW_RING_COLOR
local QueuePreviewSlotTween = PP.QueuePreviewSlotTween
local EnsureGapFrame = PP.EnsureGapFrame
local PANEL_PREVIEW_HIGHLIGHT_LEVEL_OFFSET = PP.PANEL_PREVIEW_HIGHLIGHT_LEVEL_OFFSET

------------------------------------------------------------------------
-- PANEL SECTION DRAG
--
-- The drag model's second and third target families:
--   a FREE anchor's landing     -> dropping there creates a section there
--   an OCCUPIED anchor's cluster -> dropping there joins that section
-- THE GHOST IS THE WHOLE LANGUAGE (owner ruling 2026-09-02, after a docking
-- compass of arrow tiles proved to be a second thing to look at that never
-- said where the icon would go). Every anchor has one LANDING: the cell a
-- new section would start in, or the section's own icons. Come within a
-- cell of a landing and the ghost stands on it, with two gold chevrons
-- outside the cell pointing the way the line grows; a release there lands
-- it. Inside the base row's own region (its rect grown by half a cell) a
-- drag means exactly what it always did, and a drag ON an occupied
-- anchor's cluster (a LANE) still inserts at the position the cursor
-- names, with the members sliding to open the gap. Far from every
-- landing there is no section target at all: a quick drop lands in the
-- row, because that is what a quick drop means. When two landings share a
-- spot (a one- or two-icon row starts TOPLEFT, TOP and TOPRIGHT in the
-- same cell) the cursor's bearing from the row picks between them. No
-- tile sits on the preview, and no target pulls the cursor in from a
-- distance.
--
-- Not one number here is section geometry this file worked out. Free
-- anchors' cells come from ST.BuildPanelSectionLayout run over a SYNTHETIC
-- input (the real sections plus a one-phantom-member section at each free
-- anchor), and lanes come from the real layout table the live panel is placed
-- from. The preview may only ever READ the engine's arithmetic -- re-deriving
-- it is how a mirror starts lying.
--
-- Section-drag internals stay private to this block.
local SectionDrag = {}
do
    -- Read-only stand-ins handed to the engine for the synthetic pass.
    local ZERO_SECTION = { offsetX = 0, offsetY = 0 }
    local PHANTOM_MEMBERS = { { buttonData = {} } }

    -- ONE ACCENT LANGUAGE. Every target in this gesture wears exactly two
    -- looks: ring blue = a target that exists, gold = the target the drop is
    -- committed to. Nothing stacks the two, so the eye never has to work out
    -- which of two lit things wins.
    --
    -- Gold is this addon's "aligned" signal already (Core/GroupFrameDragSnap.lua's
    -- arrange-mode snap guides, SNAP_GUIDE_COLOR), and a resolved drop IS a
    -- snap, so the landing trail and the lane's gap tile both speak it.
    -- Screen pixels of clearance past the base row's region before a drag
    -- counts as leaving it. Small on purpose (see InBaseMargin).
    local BASE_EXIT_MARGIN = 6

    -- The lifted entry's own slot (or a moving section's members), standing
    -- on the cell a create target promises: the drop ghost's alpha
    -- (DropGhost's GHOST_ALPHA), so a landing reads the same whether a
    -- payload, an entry or a section is landing.
    SectionDrag.LANDING_ALPHA = 0.6
    local SNAP_COLOR = { 1, 0.82, 0 }
    local SNAP_EDGE_ALPHA = 0.95
    local SNAP_GAP_ALPHA = 0.28
    local GAP_ALPHA = 0.18

    -- EVERY hairline in this gesture is drawn by Core/Utils.lua's border
    -- texture set in CRISP mode, which is the house's own 1px chrome
    -- technique (the selection ring and the copy-target ring use it). Crisp
    -- means ONE PHYSICAL PIXEL measured through the region's effective scale,
    -- and preview.content carries the fit scale, so the same call reads
    -- identically at every preview size. A content-space thickness could not:
    -- the fit scale is <= 1, so a literal 1 always came out sub-pixel and
    -- washed out on anything but a full-size preview.
    --
    -- The mode is passed literally rather than through
    -- ST.GetEffectiveBorderRenderMode: this is config chrome, not a mirror of
    -- the panel's own border styling, so the profile's border settings have no
    -- say in it.
    local CRISP = ST.BORDER_RENDER_MODE_CRISP

    local function ApplyChromeBorder(textures, frame, color, alpha)
        ST.ApplyBorderTextures(textures, frame,
            { color[1], color[2], color[3], alpha }, 1, CRISP)
    end

    -- Growth direction is not worked out here either. The engine already
    -- handed back the line's own step vector, and the SIGN of that vector is
    -- the arrow to draw. Whether the line spreads from its middle is the
    -- engine's answer too: the fill direction (`from`) rides every free
    -- anchor's cell and every lane. The anchor-name table is only the
    -- fallback for a rect built
    -- before the engine carried it.
    local CENTERED_ANCHORS = {
        TOP = true, BOTTOM = true, LEFT = true, RIGHT = true,
    }
    -- One atlas, four directions. The config's flat chevron (the same glyph
    -- the preview command center's collapse control uses) takes a vertex
    -- colour cleanly, which a coloured arrow art asset would not, and
    -- Texture:SetRotation turns counterclockwise from the glyph's own DOWN.
    local PIP_ATLAS = "uitools-icon-chevron-down"
    local PIP_ROTATION = {
        down = 0,
        right = math.pi / 2,
        up = math.pi,
        left = -math.pi / 2,
    }

    -- The whole-section grab chip, in SCREEN pixels: it is chrome, so every
    -- one of these is divided by the preview's fit scale at use.
    local HANDLE_SCREEN_SIZE = 17
    local HANDLE_SCREEN_MARGIN = 6
    local HANDLE_DRAG_MEMBER_ALPHA = 0.25
    local HANDLE_BORDER_ALPHA = 0.75
    -- How long the cursor has to be off the section AND off the chip before
    -- the chip goes, and how much slack the corridor between them gets.
    local HANDLE_HIDE_DELAY = 0.25
    local HANDLE_CORRIDOR = 10
    -- Breathing room between the cluster and the "this grabs all of it" ring.
    local OUTLINE_SCREEN_INSET = 3
    local OUTLINE_ALPHA = 0.75

    -- The chip's glyph. There is no grip or move art in the uitools family
    -- (checked against UiTextureAtlasMember: chevrons, checkbox, close,
    -- refresh, search, plus/minus, window furniture -- nothing directional
    -- but the chevrons), so the four-way move motif is built from the SAME
    -- chevron the direction pips use, one per compass point, pointing out.
    -- That keeps one glyph vocabulary across the whole gesture.
    local HANDLE_ARROWS = {
        { rotation = math.pi, dx = 0, dy = 1 },
        { rotation = math.pi / 2, dx = 1, dy = 0 },
        { rotation = 0, dx = 0, dy = -1 },
        { rotation = -math.pi / 2, dx = -1, dy = 0 },
    }

    -- Content-TOPLEFT space -> the scaled screen coordinates raw cursor values
    -- live in. Same transform the base cell centers use.
    local function ToScreen(view, x, y)
        return view.left + x * view.factor, view.bottom + view.height + y * view.factor
    end

    --- A base cell's CENTER in content-TOPLEFT space, given the anchored offset
    --- cellXY hands back for it. One writer for that conversion: the insertion
    --- anchors below measure their candidate cells with it, and the empty-base
    --- floor builds its stand-in rect from the same numbers, so a hit region can
    --- never sit anywhere but where the cell is actually drawn.
    function SectionDrag.CellCenter(anchor, x, y, slotW, slotH, localW, localH)
        if anchor == "TOPLEFT" then
            return x + slotW / 2, y - slotH / 2
        elseif anchor == "TOPRIGHT" then
            return localW + x - slotW / 2, y - slotH / 2
        elseif anchor == "BOTTOMLEFT" then
            return x + slotW / 2, -localH + y + slotH / 2
        elseif anchor == "TOP" then
            return localW / 2 + x, y - slotH / 2
        elseif anchor == "BOTTOM" then
            return localW / 2 + x, -localH + y + slotH / 2
        elseif anchor == "LEFT" then
            return x + slotW / 2, -localH / 2 + y
        elseif anchor == "RIGHT" then
            return localW + x - slotW / 2, -localH / 2 + y
        end
        -- BOTTOMRIGHT
        return localW + x - slotW / 2, -localH + y + slotH / 2
    end

    -- Squared distance from the cursor to a content-space rect, 0 inside it,
    -- plus the squared distance to its center for a stable tie-break between
    -- rects that overlap (a narrow base grid can stack TOPLEFT/TOP/TOPRIGHT).
    local function RectDistances(view, rect, cursorX, cursorY)
        local left, top = ToScreen(view, rect.x, rect.y)
        local right = left + rect.width * view.factor
        local bottom = top - rect.height * view.factor
        local dx = 0
        if cursorX < left then dx = left - cursorX
        elseif cursorX > right then dx = cursorX - right end
        local dy = 0
        if cursorY > top then dy = cursorY - top
        elseif cursorY < bottom then dy = bottom - cursorY end
        local cx = (left + right) / 2 - cursorX
        local cy = (top + bottom) / 2 - cursorY
        return dx * dx + dy * dy, cx * cx + cy * cy
    end

    local function LanePosition(lane, position)
        local positions = lane.positions
        if positions then
            local cell = positions[position]
            if cell then return cell.x, cell.y end
            local last = positions[#positions]
            if last then
                -- One past the end: a step extrapolated from the last resting
                -- cell. Approximate for a wrapped or centered lane (the drop
                -- re-lays everything out for real), exactly as the linear
                -- extrapolation always was.
                return last.x + lane.stepX, last.y + lane.stepY
            end
        end
        return lane.originX + (position - 1) * lane.stepX,
            lane.originY + (position - 1) * lane.stepY
    end

    -- Where in a lane the cursor sits, 1 .. #members + 1, counted over the
    -- members' resting positions (never their in-flight frames). A lane can
    -- wrap, so this is two questions, both answered from the engine's own
    -- cells: which line is the cursor nearest (by the cross-axis coordinate),
    -- then how many of THAT line's cell centers has it passed along the fill
    -- direction. Unwrapped lanes are the one-line case of the same walk.
    local function LaneInsertPosition(lane, view, cursorX, cursorY)
        local count = #lane.members
        local positions = lane.positions
        if count == 0 or not (positions and positions[count]) then return 1 end
        local perLine = lane.perLine or count
        if perLine < 1 then perLine = 1 end
        local horizontal = lane.axis ~= "v"
        local halfW = lane.width * view.factor / 2
        local halfH = lane.height * view.factor / 2

        local lineCount = math.ceil(count / perLine)
        local bestLine, bestDist = 1, nil
        for line = 1, lineCount do
            local first = positions[(line - 1) * perLine + 1]
            local firstX, firstY = ToScreen(view, first.x, first.y)
            local distance
            if horizontal then
                distance = math.abs(cursorY - (firstY - halfH))
            else
                distance = math.abs(cursorX - (firstX + halfW))
            end
            if not bestDist or distance < bestDist then
                bestLine, bestDist = line, distance
            end
        end

        local firstIndex = (bestLine - 1) * perLine + 1
        local lastIndex = math_min(bestLine * perLine, count)
        local position = firstIndex
        for k = firstIndex, lastIndex do
            local cell = positions[k]
            local cellX, cellY = ToScreen(view, cell.x, cell.y)
            local passed
            if horizontal then
                local center = cellX + halfW
                passed = (lane.stepX >= 0) and (cursorX > center) or (lane.stepX < 0) and (cursorX < center)
            else
                local center = cellY - halfH
                passed = (lane.stepY <= 0) and (cursorY < center) or (lane.stepY > 0) and (cursorY > center)
            end
            if passed then position = k + 1 end
        end
        return position
    end

    --- Cache the free anchors' cells, the lane geometry, and the base cluster's own rect
    --- for one drag activation. None of the three can change while a drag is
    --- held (a rebuild cancels the drag), so this runs once per build, never
    --- per OnUpdate.
    function SectionDrag.Build(group, sections, lists, sectionLayout,
                               entryWidth, entryHeight, spacing, headerHeight,
                               contentWidth, contentHeight)
        local model = { free = {}, lanes = {} }

        -- The base cluster inside the content frame. Without sections the
        -- content frame IS the base cluster, which is what the zeros say.
        model.baseRect = {
            x = sectionLayout and sectionLayout.baseOffsetX or 0,
            y = sectionLayout and -sectionLayout.baseOffsetY or 0,
            width = sectionLayout and sectionLayout.baseWidth or contentWidth,
            height = sectionLayout and sectionLayout.baseHeight or contentHeight,
        }
        -- Half a cell, content units: how far the row's own region reaches
        -- past its rect (RowBounds). The base grid's pitch, not a section's
        -- own icon size, because it is the ROW being aimed at.
        model.rowSkirtX = entryWidth / 2
        model.rowSkirtY = entryHeight / 2
        -- One cell: how close to an anchor's landing the cursor has to come
        -- for it to claim the drop (ResolveLanding). Any farther and the
        -- gesture is aimed at nothing in particular, which the row takes.
        model.landingReach = math_max(entryWidth, entryHeight)

        for anchor, info in pairs(sectionLayout and sectionLayout.sections or {}) do
            local members = lists.members[anchor]
            if members and #members > 0 then
                local ids = {}
                for k, entry in ipairs(members) do ids[k] = entry.index end
                model.lanes[anchor] = {
                    members = ids,
                    -- Read from the PROFILE, not from the layout info: the
                    -- mirror never populates auraCounts (it draws the full
                    -- expanded cluster as its own slots), so the engine's own
                    -- auraOnly marker is not on this pass's info.
                    auraOnly = ST.IsAuraOnlyPanelSection(group, anchor) or nil,
                    originX = info.originX, originY = info.originY,
                    stepX = info.stepX, stepY = info.stepY,
                    width = info.width, height = info.height,
                    -- The engine's per-cell truth: resting positions, the wrap
                    -- count in force, the axis, and the fill direction.
                    positions = info.positions,
                    perLine = info.perLine,
                    axis = info.axis,
                    from = info.from,
                    -- The whole block's rect, straight off the layout -- a
                    -- wrapped section's bounding box is not its first and last
                    -- member's box, so nothing here derives it from the ends.
                    rect = {
                        x = info.lineX,
                        y = info.lineY,
                        width = info.lineWidth,
                        height = info.lineHeight,
                    },
                }
            end
        end

        -- The synthetic pass. Every free anchor is handed a section (its own
        -- saved one when a placement outlived its members, so the cell never
        -- promises an offset the drop will not honor) and one phantom member,
        -- and the rect the engine hands back for it IS the cell that anchor's
        -- first member will take: the landing the ghost stands on when that
        -- anchor is claimed, whose step vector the trail's chevrons read.
        -- Every LANE gets its real members plus one phantom in the same pass,
        -- and the phantom's cell is where a join appends: a wrapped or
        -- centered line puts it somewhere no step from the last member
        -- reaches, and the engine is the only one that knows where.
        local synthSections, synthMembers = {}, {}
        for _, anchor in ipairs(ST.PANEL_SECTION_ANCHORS) do
            if model.lanes[anchor] then
                synthSections[anchor] = sections[anchor]
                synthMembers[anchor] = SectionDrag.WithPhantom(lists.members[anchor])
            else
                synthSections[anchor] = (sections and sections[anchor]) or ZERO_SECTION
                synthMembers[anchor] = PHANTOM_MEMBERS
            end
        end
        local synth = ST.BuildPanelSectionLayout(group, synthSections,
            { base = lists.base, members = synthMembers },
            entryWidth, entryHeight, spacing, headerHeight)
        -- Both layouts place from the same base-cluster origin underneath;
        -- undoing the synthetic union's shift and applying the real one is
        -- the whole conversion.
        local realX = sectionLayout and sectionLayout.baseOffsetX or 0
        local realY = sectionLayout and sectionLayout.baseOffsetY or 0
        local dx, dy = realX - synth.baseOffsetX, synth.baseOffsetY - realY
        for anchor, info in pairs(synth.sections) do
            local lane = model.lanes[anchor]
            if lane then
                local cell = info.positions and info.positions[#lane.members + 1]
                if cell then
                    lane.appendCell = {
                        x = cell.x + dx,
                        y = cell.y + dy,
                        width = info.width,
                        height = info.height,
                    }
                end
            else
                model.free[anchor] = {
                    x = info.originX + dx,
                    y = info.originY + dy,
                    width = info.width,
                    height = info.height,
                    -- Carried, not computed: this is the step the second
                    -- member of that section would take, which is exactly
                    -- the line the landing trail's chevrons promise.
                    -- `from` is the fill direction, which decides whether
                    -- the chevrons point both ways.
                    stepX = info.stepX,
                    stepY = info.stepY,
                    from = info.from,
                }
            end
        end
        -- What MoveLayout needs to lay a whole section out somewhere else:
        -- asked per (from, to) on first need, never up front.
        model.inputs = { group, sections, lists, sectionLayout,
            entryWidth, entryHeight, spacing, headerHeight }
        model.moves = {}

        return model
    end

    --- `list` plus one phantom member, as a fresh list: the engine reads
    --- member lists positionally and the real one is not this pass's to grow.
    function SectionDrag.WithPhantom(list)
        local grown = {}
        for k, member in ipairs(list or {}) do grown[k] = member end
        grown[#grown + 1] = PHANTOM_MEMBERS[1]
        return grown
    end

    --- Where a whole section lands when its handle drops on `toAnchor`: the
    --- engine's positions for the section's REAL members laid out at the new
    --- anchor with the settings ApplyHandleDrop carries across (the section
    --- table itself: offsets, icon size, spacing, wrap), in the real
    --- layout's content space. A centered anchor centers the whole block
    --- and a wrap breaks the line, neither of which a step from a
    --- one-member cell can show. Built on first ask per (from, to) and
    --- cached on the model, which lives exactly one build; nil when the
    --- engine lays nothing out there (the free cell is the fallback).
    function SectionDrag.MoveLayout(model, fromAnchor, toAnchor)
        local key = fromAnchor .. ">" .. toAnchor
        local moves = model.moves
        local cached = moves and moves[key]
        if cached ~= nil then return cached or nil end
        local inputs = model.inputs
        if not (inputs and moves and model.lanes[fromAnchor]) then return nil end
        local group, sections, lists, sectionLayout = inputs[1], inputs[2], inputs[3], inputs[4]
        local synthSections, synthMembers = {}, {}
        for _, anchor in ipairs(ST.PANEL_SECTION_ANCHORS) do
            if anchor == toAnchor then
                synthSections[anchor] = (sections and sections[fromAnchor]) or ZERO_SECTION
                synthMembers[anchor] = lists.members[fromAnchor]
            elseif anchor ~= fromAnchor and model.lanes[anchor] then
                synthSections[anchor] = sections[anchor]
                synthMembers[anchor] = lists.members[anchor]
            end
        end
        local synth = ST.BuildPanelSectionLayout(group, synthSections,
            { base = lists.base, members = synthMembers },
            inputs[5], inputs[6], inputs[7], inputs[8])
        local info = synth.sections[toAnchor]
        local layout = false
        if info and info.positions and info.positions[1] then
            -- This pass has its own union (the moved block changes what it
            -- spans), so the conversion is this pass's, not the build's.
            local realX = sectionLayout and sectionLayout.baseOffsetX or 0
            local realY = sectionLayout and sectionLayout.baseOffsetY or 0
            local dx, dy = realX - synth.baseOffsetX, synth.baseOffsetY - realY
            local positions = {}
            for k, pos in ipairs(info.positions) do
                positions[k] = { x = pos.x + dx, y = pos.y + dy }
            end
            layout = {
                positions = positions,
                x = positions[1].x,
                y = positions[1].y,
                width = info.width,
                height = info.height,
                stepX = info.stepX,
                stepY = info.stepY,
                from = info.from,
            }
        end
        moves[key] = layout
        return layout or nil
    end

    --- Give an ALL-SECTIONED panel a base row worth aiming at.
    --- With no base members left, BuildPanelSectionLayout measures the base
    --- cluster as 0x0 (nothing to measure), so the rect above is a bare point
    --- and "drag it back to the base row" means hitting a few pixels that any
    --- lane out-competes. The floor is the cell the base grid would
    --- actually draw -- the same rect the insertion gap tile lands in, taken
    --- from cell 1 of this build's own grid -- so coming home is as big a target
    --- as leaving was, and the region the cursor claims is the region the tile
    --- appears in.
    ---
    --- Kept as its own field: model.baseRect stays the cluster's TRUE rect, and
    --- the whole-section handle goes on picking its side against that.
    function SectionDrag.FloorEmptyBase(model, layoutDrag, localW, localH)
        local rect = model.baseRect
        if rect.width > 0 and rect.height > 0 then return end
        local slotW, slotH = layoutDrag.slotW, layoutDrag.slotH
        local x, y = layoutDrag.cellXY(1)
        local cx, cy = SectionDrag.CellCenter(layoutDrag.anchor, x, y,
            slotW, slotH, localW, localH)
        model.baseHitRect = {
            x = cx - slotW / 2,
            y = cy + slotH / 2,
            width = slotW,
            height = slotH,
        }
    end

    --- The cursor's screen frame of reference for one resolve pass.
    function SectionDrag.View(content)
        local left, bottom, width, height = content:GetScaledRect()
        if not (left and bottom and width and height) then return nil end
        local localW = content:GetWidth() or 1
        return {
            left = left, bottom = bottom, height = height,
            factor = (localW > 0) and (width / localW) or 1,
        }
    end

    --- The base row's own region: its rect (the floored stand-in when there
    --- is one, see FloorEmptyBase) grown by HALF A CELL on every side, in
    --- screen space. Inside it a drag is a reorder and a cursor drop
    --- appends; outside it the landings are what the cursor can be near
    --- (ResolveLanding). Half a cell is the owner's ruling (2026-09-02): a
    --- skirt wide enough that aiming at the row's end never starts a
    --- section by accident, and narrow enough that every landing stays a
    --- short move away.
    local function RowBounds(model, view)
        local rect = model.baseHitRect or model.baseRect
        local left, top = ToScreen(view, rect.x, rect.y)
        local right = left + rect.width * view.factor
        local bottom = top - rect.height * view.factor
        local ix = (model.rowSkirtX or 0) * view.factor
        local iy = (model.rowSkirtY or 0) * view.factor
        return left - ix, right + ix, top + iy, bottom - iy
    end

    --- True while the cursor is still in reorder country (RowBounds).
    --- Leaving takes a few pixels of clearance past the region; coming back
    --- takes its real edge. A cursor parked on the boundary therefore sits in
    --- whichever country it last entered instead of flipping between reorder
    --- and section land frame after frame.
    ---
    --- Which country that is has to survive between OnUpdate frames, and the
    --- drag model is the only thing here that lives exactly as long as one
    --- gesture (a rebuild replaces it and cancels the drag), so it holds the
    --- flag. No reset is needed on a fresh drag: whichever side of the two
    --- rects the cursor is actually on decides the first frame outright, and
    --- only a cursor in the narrow band between them inherits the old answer.
    function SectionDrag.InBaseMargin(model, view, cursorX, cursorY)
        local left, right, top, bottom = RowBounds(model, view)
        local margin = model.inSectionLand and 0 or BASE_EXIT_MARGIN
        local inside = cursorX >= left - margin and cursorX <= right + margin
            and cursorY <= top + margin and cursorY >= bottom - margin
        model.inSectionLand = not inside
        return inside
    end

    --- The same region without the hysteresis, for the cursor drop: the
    --- overlay asks every frame and nothing on its side holds a flag.
    function SectionDrag.InRow(model, view, cursorX, cursorY)
        local left, right, top, bottom = RowBounds(model, view)
        return cursorX >= left and cursorX <= right
            and cursorY <= top and cursorY >= bottom
    end

    --- What landing on `anchor` means for the gesture that is open over
    --- `model` (BeginGesture): { create = anchor } on a free anchor,
    --- { section = anchor, memberPos } on an occupied one, nil on an anchor
    --- the gesture refuses, a nil anchor, an anchor with no landing, or
    --- with no gesture open. A join from outside the cluster appends (one
    --- past the last member), unless the lane is the one the entry in hand
    --- (`sourceIndex`) already belongs to: near its own section an entry is
    --- home, and its own position is a no-op drop, not a move to the end.
    --- The gesture's state function is the one place it says which anchors
    --- it will take (CursorAnchorState, EntryAnchorState, HandleAnchorState).
    function SectionDrag.AnchorTarget(preview, model, anchor, sourceIndex)
        local stateFn = preview.gestureState
        if not (anchor and stateFn and preview.gestureModel == model) then return nil end
        local lane = model.lanes[anchor]
        local rect = lane or model.free[anchor]
        if not rect or stateFn(anchor, lane, rect, preview.gestureContext) == "refused" then
            return nil
        end
        if lane then
            local home = sourceIndex and SectionDrag.MemberPosition(lane, sourceIndex)
            return { section = anchor, memberPos = home or (#lane.members + 1) }
        end
        return { create = anchor }
    end

    -- Which way each anchor lies from the row, unit length, for the one
    -- case two landings share a spot (a one- or two-icon row starts
    -- TOPLEFT, TOP and TOPRIGHT in the same cell): the cursor's bearing from
    -- the row's centre picks between them, straight up being TOP.
    local LANDING_BEARING = {
        TOPLEFT = { -0.7071, 0.7071 }, TOP = { 0, 1 }, TOPRIGHT = { 0.7071, 0.7071 },
        LEFT = { -1, 0 }, RIGHT = { 1, 0 },
        BOTTOMLEFT = { -0.7071, -0.7071 }, BOTTOM = { 0, -1 }, BOTTOMRIGHT = { 0.7071, -0.7071 },
    }
    -- Squared screen pixels within which two landings count as equally near.
    local LANDING_TIE = 1

    --- The target for the landing the cursor is nearest, within the model's
    --- reach (one cell from the landing's edge), or nil when no landing is
    --- that near. A landing is the cluster for an occupied anchor and the
    --- free cell for a free one; an anchor the gesture refuses is not a
    --- landing at all, so the next nearest one can still take the drop.
    --- Equally near landings (which only happens when they coincide) go to
    --- the one whose direction best matches the cursor's bearing from the
    --- row. Pure geometry, no hysteresis: the ghost follows the cursor.
    function SectionDrag.ResolveLanding(preview, model, view, cursorX, cursorY, sourceIndex)
        local stateFn = preview.gestureState
        if not (stateFn and preview.gestureModel == model) then return nil end
        local reach = (model.landingReach or 0) * view.factor
        local reachSq = reach * reach
        local base = model.baseHitRect or model.baseRect
        local baseLeft, baseTop = ToScreen(view, base.x, base.y)
        local bx = cursorX - (baseLeft + base.width * view.factor / 2)
        local by = cursorY - (baseTop - base.height * view.factor / 2)
        local best, bestDist, bestDot
        for _, anchor in ipairs(ST.PANEL_SECTION_ANCHORS) do
            local lane = model.lanes[anchor]
            local landing = lane and lane.rect or model.free[anchor]
            if landing and stateFn(anchor, lane, landing, preview.gestureContext) ~= "refused" then
                local dist = RectDistances(view, landing, cursorX, cursorY)
                if dist <= reachSq then
                    local dir = LANDING_BEARING[anchor]
                    local dot = bx * dir[1] + by * dir[2]
                    if not best or dist < bestDist - LANDING_TIE
                        or (dist <= bestDist + LANDING_TIE and dot > bestDot) then
                        best, bestDist, bestDot = anchor, dist, dot
                    end
                end
            end
        end
        return SectionDrag.AnchorTarget(preview, model, best, sourceIndex)
    end

    --- Is the cursor within `margin` screen pixels of the box the preview
    --- may use (the Live Preview host in the unified composition, the
    --- mirror's root otherwise)? A landing's reach can poke past a tightly
    --- fitted mirror; this is what bounds every resolve.
    function SectionDrag.CursorInBox(preview, cursorX, cursorY, margin)
        local box = preview.laneChromeHost or preview.root
        if not (box and box.GetScaledRect) then return false end
        local left, bottom, width, height = box:GetScaledRect()
        if not left then return false end
        margin = margin or 0
        return cursorX >= left - margin and cursorX <= left + width + margin
            and cursorY >= bottom - margin and cursorY <= bottom + height + margin
    end

    --- The offset that puts a slot anchored by `anchor` with its top-left at
    --- (tlX, tlY) in content-TOPLEFT space: the inverse of CellCenter, so a
    --- base slot can be tweened to a section's cell (which the engine hands
    --- back top-left) without changing the anchor it was placed with (a
    --- changed anchor makes QueuePreviewSlotTween jump instead of slide).
    function SectionDrag.AnchoredOffset(anchor, tlX, tlY, slotW, slotH, localW, localH)
        local x, y = tlX, tlY
        if anchor == "TOPRIGHT" or anchor == "RIGHT" or anchor == "BOTTOMRIGHT" then
            x = tlX + slotW - localW
        elseif anchor == "TOP" or anchor == "BOTTOM" then
            x = tlX + slotW / 2 - localW / 2
        end
        if anchor == "BOTTOMLEFT" or anchor == "BOTTOM" or anchor == "BOTTOMRIGHT" then
            y = tlY - slotH + localH
        elseif anchor == "LEFT" or anchor == "RIGHT" then
            y = tlY - slotH / 2 + localH / 2
        end
        return x, y
    end

    --- "Would an AURA lane at `anchor` refuse the entry this drag has in hand?"
    --- Memoized on the drag model, which lives exactly as long as one preview
    --- build: the resolve runs every frame of a gesture, and the answer can only
    --- change when a commit rebuilds the whole model anyway.
    --- Nil when there is nothing to ask - every panel with no aura section, and
    --- every gesture with no entry behind it - which is what keeps an ordinary
    --- sectioned panel on exactly the code it had.
    function SectionDrag.EntryLaneBlocker(model, panelId, state)
        local buttonData = state and state.slotData and state.slotData.buttonData
        if not buttonData then return nil end
        if model.blockerEntry == buttonData then return model.blockerFn end

        local group = panelId and CooldownCompanion.db.profile.groups[panelId]
        local blocker
        if group and ST.PanelHasAuraSection(group) then
            blocker = function(anchor)
                return CooldownCompanion:GetAuraSectionEntryRejectMessage(
                    group, anchor, buttonData) ~= nil
            end
        end
        model.blockerEntry = buttonData
        model.blockerFn = blocker
        return blocker
    end

    --- The lane whose cluster the cursor is ON, with the position in it the
    --- cursor names, or nil. Containment only: a cluster reached from nearby
    --- is ResolveLanding's (and appends), so nothing here pulls the cursor
    --- in. Two clusters sharing pixels tie-break on the nearer centre.
    ---
    --- laneBlocked (optional) drops AURA lanes the dragged entry cannot join out
    --- of the contest entirely. It is asked HERE rather than at the drop because
    --- everything downstream is a promise: an excluded lane opens no gap and
    --- lights no gold edge, so the gesture never offers a landing
    --- SetPanelSectionForEntry would refuse.
    function SectionDrag.ResolveLane(model, view, cursorX, cursorY, laneBlocked)
        local bestAnchor, bestLane, bestCenter
        for _, anchor in ipairs(ST.PANEL_SECTION_ANCHORS) do
            local lane = model.lanes[anchor]
            if lane and not (lane.auraOnly and laneBlocked and laneBlocked(anchor)) then
                local dist, center = RectDistances(view, lane.rect, cursorX, cursorY)
                if dist == 0 and (not bestCenter or center < bestCenter) then
                    bestAnchor, bestLane, bestCenter = anchor, lane, center
                end
            end
        end
        if not bestLane then return nil end
        return {
            section = bestAnchor,
            memberPos = LaneInsertPosition(bestLane, view, cursorX, cursorY),
        }
    end

    --- The lane gap borrows the base grid's own gap tile, so its colour has to
    --- be written by whichever target family is holding it this frame.
    function SectionDrag.SetGapAccent(preview, snapped)
        local gap = preview.gapFrame
        if not gap or preview.gapAccentSnapped == snapped then return end
        preview.gapAccentSnapped = snapped
        if snapped then
            gap.bg:SetColorTexture(SNAP_COLOR[1], SNAP_COLOR[2], SNAP_COLOR[3],
                SNAP_GAP_ALPHA)
            -- Same gold the landing trail wears: a lane target and a landing
            -- are the same commitment.
            ApplyChromeBorder(gap.border, gap, SNAP_COLOR, SNAP_EDGE_ALPHA)
        else
            gap.bg:SetColorTexture(PANEL_PREVIEW_RING_COLOR[1],
                PANEL_PREVIEW_RING_COLOR[2], PANEL_PREVIEW_RING_COLOR[3],
                GAP_ALPHA)
            ST.HideBorderTextures(gap.border)
        end
    end

    --- The unified anchor preview wraps this mirror in the attached bars'
    --- Layout & Order lanes, and a section gesture's landings can sit on
    --- the strip above or below the mirror where those lanes sit. Two
    --- affordances in one place read as a bug, so the lanes go quiet for
    --- the duration of a section gesture -- the same move arrange mode makes
    --- when it fades its mover chrome during a drag. Faded while a gesture
    --- is open (BeginGesture), restored when it ends. Idempotent, and a
    --- no-op for a mirror with no lanes around it; both directions early-out
    --- on the state they would write, since a gesture asks on every frame.
    local function SetLaneChromeFaded(preview, faded)
        if not (preview.laneChromeHost and ST._SetLayoutOrderLaneChromeFaded) then
            return
        end
        faded = faded and true or false
        if faded == (preview.laneChromeFaded == true) then return end
        preview.laneChromeFaded = faded or nil
        ST._SetLayoutOrderLaneChromeFaded(preview.laneChromeHost, faded)
    end

    SectionDrag.SetLaneChromeFaded = SetLaneChromeFaded

    ------------------------------------------------------------------
    -- Lanes

    local function MemberPosition(lane, index)
        for k, member in ipairs(lane.members) do
            if member == index then return k end
        end
        return nil
    end

    SectionDrag.MemberPosition = MemberPosition

    --- Every lane, every frame of a drag: the lifted member goes invisible and
    --- the lane the cursor claims opens a gap at the insertion position while
    --- its neighbours shift along their own line. Same vocabulary as the base
    --- grid's reorder, sized to the section's own icons.
    function SectionDrag.UpdateLanes(preview, layoutDrag, sourceIndex, dropTarget)
        local model = layoutDrag.sectionDrag
        local targetAnchor = dropTarget and dropTarget.section
        local gapLane, gapPos
        for _, anchor in ipairs(ST.PANEL_SECTION_ANCHORS) do
            local lane = model.lanes[anchor]
            if lane then
                local sourcePos = sourceIndex and MemberPosition(lane, sourceIndex)
                local position
                if anchor == targetAnchor then
                    -- The resolve counts positions over the lane as it stands,
                    -- so a member moving inside its own lane collapses the same
                    -- way the base grid's source cell does.
                    position = dropTarget.memberPos or 1
                    if sourcePos and position > sourcePos then position = position - 1 end
                    local maxPos = #lane.members + (sourcePos and 0 or 1)
                    if position > maxPos then position = maxPos end
                    if position < 1 then position = 1 end
                    gapLane, gapPos = lane, position
                end
                local renderIndex = 1
                for _, index in ipairs(lane.members) do
                    local slot = layoutDrag.slots[index]
                    if slot then
                        if index == sourceIndex then
                            slot:SetAlpha(0)
                        else
                            local displayIndex = renderIndex
                            if position and displayIndex >= position then
                                displayIndex = displayIndex + 1
                            end
                            QueuePreviewSlotTween(preview, slot, "TOPLEFT",
                                LanePosition(lane, displayIndex))
                            renderIndex = renderIndex + 1
                        end
                    end
                end
            end
        end
        if gapLane then
            local gap = EnsureGapFrame(preview)
            -- A lane target is a resolved drop, so the tile wears the snap
            -- colour; the base grid's own gap resets it on the way past.
            SectionDrag.SetGapAccent(preview, true)
            gap:SetSize(gapLane.width, gapLane.height)
            QueuePreviewSlotTween(preview, gap, "TOPLEFT", LanePosition(gapLane, gapPos))
            gap:Show()
        end
    end

    function SectionDrag.ResetLanes(preview, layoutDrag)
        for _, lane in pairs(layoutDrag.sectionDrag.lanes) do
            for k, index in ipairs(lane.members) do
                local slot = layoutDrag.slots[index]
                if slot then
                    QueuePreviewSlotTween(preview, slot, "TOPLEFT", LanePosition(lane, k))
                    slot:SetAlpha(slot._cdcBaseAlpha or 1)
                end
            end
        end
    end

    ------------------------------------------------------------------
    -- Whole-section handle
    --
    -- Moving one entry is a drag on that entry. Moving the WHOLE section is a
    -- drag on the section, and the only thing a section has to grab is the
    -- handle that appears beside its cluster on hover. It answers to FREE
    -- landings and nothing else: an occupied anchor is a lane, and the
    -- section's own anchor is the lane it came from, so every occupied one
    -- reads refused for it (HandleAnchorState).

    ------------------------------------------------------------------
    -- "This grabs all of it"
    --
    -- The chip is small and sits beside the cluster, so on its own it says
    -- nothing about how much it moves. Ringing the WHOLE cluster the moment
    -- the cursor reaches the chip is the answer, and it stays up for the
    -- length of the drag so the thing being moved is never in doubt. The UI
    -- teaches it; there is no tooltip.

    local function EnsureSectionOutline(preview)
        local outline = preview.sectionOutline
        if not outline then
            outline = CreateFrame("Frame", nil, preview.content)
            outline:EnableMouse(false)
            outline:SetFrameLevel((preview.content:GetFrameLevel() or 1)
                + PANEL_PREVIEW_HIGHLIGHT_LEVEL_OFFSET + 4)
            outline.border = ST.CreateBorderTextureSet(outline, "OVERLAY")
            outline:Hide()
            preview.sectionOutline = outline
        end
        return outline
    end

    function SectionDrag.HideSectionOutline(preview)
        local outline = preview and preview.sectionOutline
        if not outline then return end
        -- The redraw record goes even when nothing is up, so a ring can only
        -- ever be skipped for an ask this ring is still showing.
        outline._lane, outline._scale, outline._color = nil, nil, nil
        if not outline:IsShown() then return end
        ST.HideBorderTextures(outline.border)
        outline:Hide()
    end

    --- Ring one lane's cluster. The rect is the engine's; the inset is chrome
    --- and counter-scales; the colour is the caller's, because the ring answers
    --- two different questions (see the two callers).
    --- Redrawn only when the ask changes: the cursor gesture rings the same
    --- lane on every frame it hovers there, and one ring is one border set.
    local function OutlineLane(preview, lane, scale, color)
        if not scale or scale <= 0 then scale = 1 end
        local outline = EnsureSectionOutline(preview)
        if outline:IsShown() and outline._lane == lane
            and outline._scale == scale and outline._color == color then
            return
        end
        local inset = OUTLINE_SCREEN_INSET / scale
        local rect = lane.rect
        outline:SetSize(math_max(1, rect.width + inset * 2),
            math_max(1, rect.height + inset * 2))
        outline:ClearAllPoints()
        outline:SetPoint("TOPLEFT", preview.content, "TOPLEFT",
            rect.x - inset, rect.y + inset)
        ApplyChromeBorder(outline.border, outline, color, OUTLINE_ALPHA)
        outline:Show()
        outline._lane, outline._scale, outline._color = lane, scale, color
    end

    --- Ring the cluster at `anchor`. Ring blue, not gold: this is not a drop
    --- target, it is the answer to "what am I about to pick up".
    function SectionDrag.ShowSectionOutline(preview, layoutDrag, anchor)
        local model = layoutDrag and layoutDrag.sectionDrag
        local lane = anchor and model and model.lanes[anchor]
        if not lane then
            SectionDrag.HideSectionOutline(preview)
            return
        end
        OutlineLane(preview, lane, layoutDrag.scale, PANEL_PREVIEW_RING_COLOR)
    end

    function SectionDrag.HideHandle(preview)
        local handle = preview and preview.sectionHandle
        if not handle then return end
        -- The watcher exists only while the chip does. Nothing in this file
        -- runs an always-on OnUpdate.
        handle:SetScript("OnUpdate", nil)
        handle._outside = nil
        handle.anchor = nil
        handle:Hide()
        SectionDrag.HideSectionOutline(preview)
    end

    ------------------------------------------------------------------
    -- Keeping the chip alive
    --
    -- OnEnter/OnLeave cannot describe this shape. The chip sits a few pixels
    -- of empty preview away from the icons that offered it, so moving icon ->
    -- chip leaves BOTH regions for a frame or two and any leave-then-grace
    -- scheme is a race against the exact path the cursor took. Containment
    -- has no path dependence: the chip lives while the cursor is anywhere in
    -- the section's own rect, the chip's own rect, or the corridor around
    -- either, and it goes when the cursor has been out of all of that for a
    -- beat. The watcher is the chip's own OnUpdate and dies with it.

    local function ScreenRect(view, rect)
        local left, top = ToScreen(view, rect.x, rect.y)
        return left, top - rect.height * view.factor,
            left + rect.width * view.factor, top
    end

    local function CursorNear(left, bottom, right, top, slack, cursorX, cursorY)
        return cursorX >= left - slack and cursorX <= right + slack
            and cursorY >= bottom - slack and cursorY <= top + slack
    end

    local function HandleHoldsCursor(handle, cursorX, cursorY)
        local left, bottom, width, height = handle:GetScaledRect()
        if left and CursorNear(left, bottom, left + width, bottom + height,
            HANDLE_CORRIDOR, cursorX, cursorY) then
            return true
        end
        local layoutDrag = handle.layoutDrag
        local model = layoutDrag and layoutDrag.sectionDrag
        local lane = handle.anchor and model and model.lanes[handle.anchor]
        if not lane then return false end
        local preview = handle.preview
        local view = preview and SectionDrag.View(preview.content)
        -- Unmeasurable this frame (a collapsed or hidden host): hold rather
        -- than yank the chip out from under a cursor that may be right on it.
        if not view then return true end
        local l, b, r, t = ScreenRect(view, lane.rect)
        return CursorNear(l, b, r, t, HANDLE_CORRIDOR, cursorX, cursorY)
    end

    local function HandleWatch(handle, elapsed)
        -- A live drag owns every one of these frames, and the drag paths draw
        -- the outline themselves.
        if CS.dragState then return end
        local cursorX, cursorY = GetCursorPosition()
        if HandleHoldsCursor(handle, cursorX, cursorY) then
            handle._outside = 0
            if handle:IsMouseOver() then
                SectionDrag.ShowSectionOutline(handle.preview, handle.layoutDrag,
                    handle.anchor)
            else
                SectionDrag.HideSectionOutline(handle.preview)
            end
            return
        end
        handle._outside = (handle._outside or 0) + (elapsed or 0)
        if handle._outside >= HANDLE_HIDE_DELAY then
            SectionDrag.HideHandle(handle.preview)
        end
    end

    local function EnsureHandle(preview)
        local handle = preview.sectionHandle
        if handle then return handle end
        handle = CreateFrame("Frame", nil, preview.content)
        handle:EnableMouse(true)
        handle:SetFrameLevel((preview.content:GetFrameLevel() or 1)
            + PANEL_PREVIEW_HIGHLIGHT_LEVEL_OFFSET + 5)
        -- A chip, not a sticker: the same dark plate the drag ghost uses,
        -- a one-physical-pixel ring so it reads as a control at any preview
        -- scale, and the four-way move glyph inside it.
        handle.bg = handle:CreateTexture(nil, "BACKGROUND")
        handle.bg:SetAllPoints()
        handle.bg:SetColorTexture(0.05, 0.10, 0.18, 0.92)
        handle.border = ST.CreateBorderTextureSet(handle, "OVERLAY")
        handle.arrows = {}
        for k = 1, #HANDLE_ARROWS do
            local tex = handle:CreateTexture(nil, "ARTWORK")
            tex:SetAtlas(PIP_ATLAS, false)
            tex:SetVertexColor(PANEL_PREVIEW_RING_COLOR[1],
                PANEL_PREVIEW_RING_COLOR[2], PANEL_PREVIEW_RING_COLOR[3], 0.95)
            handle.arrows[k] = tex
        end
        handle:SetScript("OnMouseDown", function(self, mouseButton)
            if mouseButton ~= "LeftButton" or GetCursorInfo() then return end
            if CS.copyCustomization then return end
            local layoutDrag, anchor = self.layoutDrag, self.anchor
            local model = layoutDrag and layoutDrag.sectionDrag
            local lane = anchor and model and model.lanes[anchor]
            if not (lane and lane.members[1] and StartDragTracking) then return end
            local group = layoutDrag.panelId
                and CooldownCompanion.db.profile.groups[layoutDrag.panelId]
            local buttonData = group and group.buttons and group.buttons[lane.members[1]]
            local cursorX, cursorY = GetCursorPosition()
            GameTooltip:Hide()
            -- Started through the shared tracker exactly like an entry drag,
            -- with one marker on the state saying which gesture this is. Escape
            -- and the mouse-up both land in CancelDrag/FinishDrag for free.
            CS.dragState = {
                kind = "layout-slot",
                phase = "pending",
                previewSlot = self,
                scrollWidget = UIParent,
                startX = cursorX,
                startY = cursorY,
                layoutDrag = layoutDrag,
                sectionHandle = anchor,
                slotData = { index = lane.members[1], buttonData = buttonData },
            }
            StartDragTracking()
        end)
        handle:SetScript("OnMouseUp", function(self, mouseButton)
            if mouseButton ~= "LeftButton" then return end
            -- No click behaviour of its own, but it still claims the mark so an
            -- Escape-cancelled section drag cannot leave one behind.
            if ST._ConsumeDragEscapeMouseUp() then return end
            local state = CS.dragState
            if state and state.kind == "layout-slot" and state.phase == "pending"
                and state.previewSlot == self then
                if CancelDrag then CancelDrag() else CS.dragState = nil end
            end
        end)
        handle:Hide()
        preview.sectionHandle = handle
        return handle
    end

    --- The grab handle for a whole section, shown while the cursor is over its
    --- cluster and no drag is in hand. It sits just OUTSIDE the lane's rect on
    --- the face pointing away from the base cluster, so it never covers an
    --- icon; which face that is comes from comparing the two rects the engine
    --- produced, not from re-deciding what the anchor meant.
    function SectionDrag.ShowHandle(preview, layoutDrag, anchor)
        if CS.dragState or CS.copyCustomization then return end
        local model = layoutDrag and layoutDrag.sectionDrag
        local lane = model and model.lanes[anchor]
        if not lane then return end
        -- With every other anchor taken there is nowhere to move to, and a
        -- handle that can only ever snap back is noise.
        if not next(model.free) then return end

        local handle = EnsureHandle(preview)
        local scale = layoutDrag.scale
        if not scale or scale <= 0 then scale = 1 end
        -- Content-space sizes shrink with the preview's fit scale; the handle
        -- is chrome, so it counter-scales to a constant on-screen size.
        local size = HANDLE_SCREEN_SIZE / scale
        local margin = HANDLE_SCREEN_MARGIN / scale
        handle:SetSize(size, size)

        local rect, base = lane.rect, model.baseRect
        local hx, hy
        if math.abs(lane.stepX) >= math.abs(lane.stepY) then
            hx = rect.x + rect.width / 2
            if rect.y > base.y then
                hy = rect.y + margin + size / 2
            else
                hy = rect.y - rect.height - margin - size / 2
            end
        else
            hy = rect.y - rect.height / 2
            if rect.x < base.x then
                hx = rect.x - margin - size / 2
            else
                hx = rect.x + rect.width + margin + size / 2
            end
        end
        handle:ClearAllPoints()
        handle:SetPoint("CENTER", preview.content, "TOPLEFT", hx, hy)

        ApplyChromeBorder(handle.border, handle, PANEL_PREVIEW_RING_COLOR,
            HANDLE_BORDER_ALPHA)

        -- Four chevrons facing out from the centre: a move control, and one
        -- that says "every direction", which is the whole point of grabbing a
        -- section rather than an icon.
        local glyph = math_max(2, size * 0.36)
        local reach = size * 0.25
        for k, spec in ipairs(HANDLE_ARROWS) do
            local tex = handle.arrows[k]
            tex:SetSize(glyph, glyph)
            tex:SetRotation(spec.rotation)
            tex:ClearAllPoints()
            tex:SetPoint("CENTER", handle, "CENTER",
                spec.dx * reach, spec.dy * reach)
        end

        handle._outside = 0
        handle.anchor = anchor
        handle.layoutDrag = layoutDrag
        handle.preview = preview
        handle:Show()
        handle:SetScript("OnUpdate", HandleWatch)
    end

    --- The handle's drag, every frame: on a create target the section's
    --- members slide to the cells the engine lays out for them at the new
    --- anchor (MoveLayout; the free cell plus a step per member only when
    --- the engine lays nothing out) at the landing alpha with the trail out
    --- of the first cell; otherwise they sit home, dimmed, while the cursor
    --- ghost stands in for the cluster. The ring stays on the source
    --- cluster either way, so what is being moved is never in doubt.
    function SectionDrag.UpdateHandleDrag(preview, layoutDrag, anchor, dropTarget)
        local model = layoutDrag.sectionDrag
        if not model then return end
        SectionDrag.BeginGesture(preview, model, "handle:" .. tostring(anchor),
            SectionDrag.HandleAnchorState)
        if preview.gapFrame then
            preview.gapFrame:Hide()
        end
        local lane = model.lanes[anchor]
        if not lane then return end
        -- The chip itself is hidden for the drag, so the ring around the
        -- cluster is what keeps saying which section is in hand.
        SectionDrag.ShowSectionOutline(preview, layoutDrag, anchor)
        local create = dropTarget and dropTarget.create
        local landing = create and (SectionDrag.MoveLayout(model, anchor, create)
            or model.free[create]) or nil
        if landing then
            SectionDrag.ShowLandingTrail(preview, landing, create, layoutDrag.scale)
        else
            SectionDrag.HideLandingTrail(preview)
        end
        for k, index in ipairs(lane.members) do
            local slot = layoutDrag.slots[index]
            if slot then
                if landing then
                    local pos = landing.positions and landing.positions[k]
                    local x, y
                    if pos then
                        -- The engine's cell for this member, sized as the
                        -- section sizes it: the slot already is.
                        x, y = pos.x, pos.y
                    else
                        local sw, sh = slot:GetWidth() or 0, slot:GetHeight() or 0
                        x = landing.x + (landing.width - sw) / 2 + (k - 1) * (landing.stepX or 0)
                        y = landing.y - (landing.height - sh) / 2 + (k - 1) * (landing.stepY or 0)
                    end
                    QueuePreviewSlotTween(preview, slot, "TOPLEFT", x, y)
                    slot:SetAlpha(SectionDrag.LANDING_ALPHA)
                else
                    QueuePreviewSlotTween(preview, slot, "TOPLEFT", LanePosition(lane, k))
                    slot:SetAlpha(HANDLE_DRAG_MEMBER_ALPHA)
                end
            end
        end
    end

    --- Re-anchor a whole section. Membership moves member by member IN MASTER
    --- ORDER through the one membership writer, and master order is exactly
    --- where the section reads its own order back from, so the line arrives
    --- unchanged.
    ---
    --- The old section table DISSOLVES the instant its last member leaves, so
    --- its settings are captured FIRST and written onto the new anchor's table
    --- afterwards: re-anchoring MOVES a section, it does not reset it. The new
    --- table is mutated rather than replaced because the Layout tab's sliders
    --- hold a section table by upvalue.
    function SectionDrag.ApplyHandleDrop(panelId, layoutDrag, anchor, newAnchor)
        if not (anchor and newAnchor and newAnchor ~= anchor) then return end
        local model = layoutDrag.sectionDrag
        local lane = model and model.lanes[anchor]
        local group = panelId and CooldownCompanion.db.profile.groups[panelId]
        if not (lane and group) then return end

        local old = group.sections and group.sections[anchor]
        local offsetX, offsetY, iconWidth, iconHeight, spacing, maxPerLine, auraOnly
        if type(old) == "table" then
            offsetX, offsetY = old.offsetX, old.offsetY
            iconWidth, iconHeight, spacing = old.iconWidth, old.iconHeight, old.spacing
            maxPerLine = old.maxPerLine
            -- Aura-ness is one of the section's own settings, so it MOVES with
            -- it like the rest. Left out, a handle drop would quietly turn an
            -- aura section back into ordinary icons: the members arrive at a
            -- fresh table the writer created without the flag.
            auraOnly = old.auraOnly
        end

        local changed = false
        local buttons = group.buttons or {}
        for _, index in ipairs(lane.members) do
            local buttonData = buttons[index]
            if buttonData and ST.SetPanelSectionForEntry(group, buttonData, newAnchor) then
                changed = true
            end
        end
        if not changed then return end

        local fresh = group.sections and group.sections[newAnchor]
        if type(old) == "table" and type(fresh) == "table" then
            fresh.offsetX = offsetX
            fresh.offsetY = offsetY
            fresh.iconWidth = iconWidth
            fresh.iconHeight = iconHeight
            fresh.spacing = spacing
            fresh.maxPerLine = maxPerLine
            fresh.auraOnly = auraOnly
            if auraOnly then
                -- Cheap and idempotent: the members carry the keys they were
                -- stamped with on the way into the old section, and this only
                -- covers one that somehow arrived without one.
                ST.EnsureAuraSectionEntryKeys(group)
            end
        end
        -- Safe here and nowhere earlier: the drag is over, so the rebuild this
        -- pair triggers has no in-flight gesture to pull the frames out from.
        CooldownCompanion:RefreshGroupFrame(panelId)
        CooldownCompanion:RefreshConfigPanel()
    end

    ------------------------------------------------------------------
    -- The gesture record
    --
    -- Three gestures aim at the same model: the drop-to-add overlay in
    -- ButtonsWideColumn for a spell or item on the CURSOR (the spellbook, a
    -- bag, the config's own spellbook panel), the entry drag, and the
    -- whole-section handle drag. Each says which anchors it will take
    -- through a state function (free = "start a section here", join = "add
    -- to this one", refused = not a target) and names itself with a key, so
    -- the record is written once per (model, gesture) and read on every
    -- frame's resolve (AnchorTarget, ResolveLanding). The cursor's model is
    -- the entry drag's own when the build made one, or is built on first
    -- use from the inputs the build stashed as cursorPadInputs (see
    -- ST._BuildButtonPanelPreview) and kept on the preview as
    -- cursorPadModel.

    --- The three gestures' anchor states. Each answers (anchor, lane, rect,
    --- context) -> "free" | "join" | "refused".
    ---
    --- Cursor: a spell or item on the cursor is not an entry yet, and what it
    --- becomes is the add's decision after the release, so no aura-only lane
    --- is offered, and neither is a free anchor whose SAVED placement is
    --- aura-only (Build hands the synthetic pass the saved section so the
    --- offset holds; the add would refuse the section that promises).
    function SectionDrag.CursorAnchorState(anchor, lane, rect, group)
        if lane then
            return lane.auraOnly and "refused" or "join"
        end
        return ST.IsAuraOnlyPanelSection(group, anchor) and "refused" or "free"
    end

    --- Entry drag: the aura-lane blocker (EntryLaneBlocker, memoized on the
    --- model for the entry in hand) decides which lanes refuse it; every
    --- free anchor becomes an ordinary section, whatever lands on it.
    function SectionDrag.EntryAnchorState(anchor, lane, rect, blocker)
        if lane then
            if lane.auraOnly and blocker and blocker(anchor) then return "refused" end
            return "join"
        end
        return "free"
    end

    --- Whole-section handle: a section moves only onto a FREE anchor. Every
    --- occupied one, its own included, is refused.
    function SectionDrag.HandleAnchorState(anchor, lane)
        return lane and "refused" or "free"
    end

    --- Open (or keep open) gesture `key` over `model`, anchors judged by
    --- `stateFn(anchor, lane, rect, context)`. Once per (model, key): the
    --- record is written, whether any anchor is free is noted (the overlay
    --- words its line on it), and the hover chip goes (it offers a move
    --- while a gesture owns the cursor). Every frame: the attached bar
    --- lanes fade while the gesture is `engaged` (SetLaneChromeFaded), which
    --- the drags always are and a cursor payload is only while it is on the
    --- preview (a spell picked up for an action bar must not blank them).
    --- nil means engaged.
    function SectionDrag.BeginGesture(preview, model, key, stateFn, context, engaged)
        SetLaneChromeFaded(preview, engaged ~= false)
        if preview.gestureModel == model and preview.gestureKey == key then return end
        SectionDrag.HideHandle(preview)
        preview.gestureModel = model
        preview.gestureKey = key
        preview.gestureState = stateFn
        preview.gestureContext = context
        preview.cursorTarget = nil
        local hasFree = false
        for _, anchor in ipairs(ST.PANEL_SECTION_ANCHORS) do
            local lane = model.lanes[anchor]
            local rect = lane or model.free[anchor]
            if rect and stateFn(anchor, lane, rect, context) == "free" then
                hasFree = true
                break
            end
        end
        preview.gestureHasFree = hasFree
    end

    --- The record cleared; the attached bar lanes come back. The rebuild
    --- prologue calls here (the model it read is being replaced), the entry
    --- and handle drags' cancel does, and so does the overlay's hide. The
    --- section outline and the trail are the caller's to settle.
    function SectionDrag.EndGesture(preview)
        preview.gestureModel = nil
        preview.gestureKey = nil
        preview.gestureState = nil
        preview.gestureContext = nil
        preview.gestureHasFree = nil
        preview.cursorTarget = nil
        SetLaneChromeFaded(preview, false)
    end

    ------------------------------------------------------------------
    -- The landing
    ------------------------------------------------------------------
    -- The landing
    --
    -- A create target has no gap tile to land in (no line exists there
    -- yet), so the landing cell is drawn by what will fill it (the drop
    -- ghost for a cursor payload, the lifted entry's own slot for a drag)
    -- and two faint gold chevrons trail OUT of that cell along the step the
    -- section's next member would take. Outside the cell on purpose: the
    -- cursor's own icon sits on the cell, and the chevrons are the part the
    -- eye still gets. Same glyph as the section handle's arrows, in gold.

    local TRAIL_ALPHA = 0.55
    -- Screen pixels: the trail is chrome and counter-scales.
    local TRAIL_GLYPH = 12

    --- The unit direction of a step vector and the two chevron rotations for
    --- it, forward along the line and backward against it.
    function SectionDrag.StepDirection(stepX, stepY)
        stepX, stepY = stepX or 0, stepY or 0
        if math.abs(stepX) >= math.abs(stepY) then
            local ux = (stepX < 0) and -1 or 1
            return ux, 0,
                (ux < 0) and PIP_ROTATION.left or PIP_ROTATION.right,
                (ux < 0) and PIP_ROTATION.right or PIP_ROTATION.left
        end
        local uy = (stepY < 0) and -1 or 1
        return 0, uy,
            (uy < 0) and PIP_ROTATION.down or PIP_ROTATION.up,
            (uy < 0) and PIP_ROTATION.up or PIP_ROTATION.down
    end

    function SectionDrag.ShowLandingTrail(preview, cell, anchor, scale)
        local trail = preview.landingTrail
        if not trail then
            trail = CreateFrame("Frame", nil, preview.content)
            trail:EnableMouse(false)
            trail:SetSize(1, 1)
            trail:SetFrameLevel((preview.content:GetFrameLevel() or 1)
                + PANEL_PREVIEW_HIGHLIGHT_LEVEL_OFFSET + 3)
            trail.glyphs = {}
            for k = 1, 2 do
                local tex = trail:CreateTexture(nil, "OVERLAY")
                tex:SetAtlas(PIP_ATLAS, false)
                tex:SetVertexColor(SNAP_COLOR[1], SNAP_COLOR[2], SNAP_COLOR[3], TRAIL_ALPHA)
                trail.glyphs[k] = tex
            end
            preview.landingTrail = trail
        end
        if not scale or scale <= 0 then scale = 1 end
        -- Chrome: a constant on-screen glyph, counter-scaled like the handle.
        local glyph = TRAIL_GLYPH / scale
        local ux, uy, forward, backward = SectionDrag.StepDirection(cell.stepX, cell.stepY)
        local centered = (cell.from
            or (CENTERED_ANCHORS[anchor] and "center")) == "center"
        local half = ((ux ~= 0) and cell.width or cell.height) / 2
        trail:ClearAllPoints()
        trail:SetPoint("CENTER", preview.content, "TOPLEFT",
            cell.x + cell.width / 2, cell.y - cell.height / 2)
        for k = 1, 2 do
            local tex = trail.glyphs[k]
            local reach, rotation
            if centered then
                -- The line spreads from its middle: one chevron each way.
                local side = (k == 1) and -1 or 1
                reach = side * (half + glyph * 0.7)
                rotation = (side < 0) and backward or forward
            else
                reach = half + glyph * (0.7 + (k - 1) * 0.9)
                rotation = forward
            end
            tex:SetSize(glyph, glyph)
            tex:SetRotation(rotation)
            tex:ClearAllPoints()
            tex:SetPoint("CENTER", trail, "CENTER", ux * reach, uy * reach)
        end
        trail:Show()
    end

    function SectionDrag.HideLandingTrail(preview)
        local trail = preview and preview.landingTrail
        if trail and trail:IsShown() then trail:Hide() end
    end

    --- The entry drag's landing: on a create target the lifted entry's own
    --- slot slides to the anchor's cell (centred in it: a section may size
    --- its icons differently, and the slot keeps the size it was styled at)
    --- and shows at the ghost's alpha, with the trail out of the cell. On
    --- every other target it slides home, invisible, so the next landing
    --- starts from rest rather than from wherever the last one left it. The
    --- gap tile stays the language of a base reorder and a lane join.
    function SectionDrag.UpdateLanding(preview, layoutDrag, sourceIndex, sourceCell, dropTarget)
        local model = layoutDrag.sectionDrag
        local slot = sourceIndex and layoutDrag.slots[sourceIndex]
        if not (model and slot) then return end
        local create = dropTarget and dropTarget.create
        local cell = create and model.free[create]
        if cell then
            local content = preview.content
            local sw, sh = slot:GetWidth() or 0, slot:GetHeight() or 0
            local anchor = slot._cdcPrevAnchor or "TOPLEFT"
            local x, y = SectionDrag.AnchoredOffset(anchor,
                cell.x + (cell.width - sw) / 2, cell.y - (cell.height - sh) / 2,
                sw, sh, content:GetWidth() or 0, content:GetHeight() or 0)
            QueuePreviewSlotTween(preview, slot, anchor, x, y)
            slot:SetAlpha(SectionDrag.LANDING_ALPHA)
            SectionDrag.ShowLandingTrail(preview, cell, create, layoutDrag.scale)
            return
        end
        SectionDrag.HideLandingTrail(preview)
        if sourceCell then
            local x, y = layoutDrag.cellXY(sourceCell)
            QueuePreviewSlotTween(preview, slot, layoutDrag.anchor, x, y)
            return
        end
        for _, lane in pairs(model.lanes) do
            local pos = MemberPosition(lane, sourceIndex)
            if pos then
                QueuePreviewSlotTween(preview, slot, "TOPLEFT", LanePosition(lane, pos))
                return
            end
        end
    end

    ------------------------------------------------------------------
    -- Cursor drops
    --
    -- The drop-to-add overlay in ButtonsWideColumn owns the gesture and asks
    -- three questions here: track the cursor and say what it is on, end the
    -- gesture, and say what a release means.

    --- The mirror the Live Preview host is showing: the unified
    --- composition's inner mirror when attached bars are up (the host's own
    --- is released then), else the host's own. Same rule DropGhost.Mirror
    --- applies for the ghost; the drop overlay only ever knows the host.
    local function CursorMirror(host)
        local inner = host and host._cdcUnifiedMirrorHost
        local preview = inner and inner:IsShown() and inner._cdcPanelPreview or nil
        if preview and preview.root:IsVisible() then
            return preview
        end
        return host and host._cdcPanelPreview
    end

    --- The preview behind `host` and its cursor model, or nothing when this
    --- host offers no section landings: a released or hidden mirror (the
    --- model outlives a release, the root does not), a build with no model
    --- (a bar, text, Aura or empty panel, a read-only or filtered mirror),
    --- or a mirror of some panel other than the one the drop will add to.
    local function CursorPadModel(host)
        local preview = CursorMirror(host)
        if not (preview and preview.panelId == CS.selectedGroup
            and preview.root:IsVisible() and preview.content:IsShown()) then
            return nil
        end
        local model = preview.cursorPadModel
        if not model then
            local inputs = preview.cursorPadInputs
            if not inputs then return nil end
            -- First use: the build stashed its inputs (positionally, in
            -- Build's own order, the layoutDrag last) rather than pay for a
            -- model no payload might ever ask for. Indexed, never unpacked:
            -- `sections` is nil on every build that takes this path.
            model = SectionDrag.Build(inputs[1], inputs[2], inputs[3], inputs[4],
                inputs[5], inputs[6], inputs[7], inputs[8], inputs[9], inputs[10])
            SectionDrag.FloorEmptyBase(model, inputs[11], inputs[9], inputs[10])
            preview.cursorPadModel = model
            preview.cursorPadInputs = nil
        end
        return preview, model
    end

    --- "Would the AURA lane at `anchor` refuse what the cursor carries?"
    --- Always: what the cursor carries is not an entry yet
    --- (CursorAnchorState).
    local function CursorLaneBlocked()
        return true
    end

    --- What a release means: { create = anchor } starts a section there,
    --- { section = anchor } joins that one (a cursor join always appends),
    --- nil is a plain add. The answer is the one the last TrackCursorDrop
    --- resolved and showed (the ghost stood on it): what was seen is what
    --- lands. With no gesture open for this model (none tracked, or a
    --- rebuild since) it is a plain add.
    function SectionDrag.ResolveCursorDrop(host)
        local preview, model = CursorPadModel(host)
        if not (preview and preview.gestureModel == model) then return nil end
        return preview.cursorTarget
    end

    --- Every frame the overlay is up: the target resolved the entry drag's
    --- way (the cluster the cursor is on, else the row's own region for a
    --- plain add, else the landing the cursor is near), and a gold ring on
    --- the lane a join would enter. Returns the target, then whether this
    --- mirror offers landings at all, then whether any anchor is free, so
    --- the overlay can word its line.
    function SectionDrag.TrackCursorDrop(host, cursorX, cursorY)
        local preview, model = CursorPadModel(host)
        if not preview then return nil, false, false end
        local inside = SectionDrag.CursorInBox(preview, cursorX, cursorY, 0)
        SectionDrag.BeginGesture(preview, model, "cursor",
            SectionDrag.CursorAnchorState,
            CooldownCompanion.db.profile.groups[preview.panelId], inside)
        local target
        if inside then
            local view = SectionDrag.View(preview.content)
            local onLane = view and SectionDrag.ResolveLane(model, view, cursorX, cursorY,
                CursorLaneBlocked)
            if onLane then
                target = { section = onLane.section }
            elseif view and not SectionDrag.InRow(model, view, cursorX, cursorY) then
                target = SectionDrag.ResolveLanding(preview, model, view, cursorX, cursorY)
            end
        end
        preview.cursorTarget = target
        local lane = target and target.section and model.lanes[target.section]
        if lane then
            OutlineLane(preview, lane, preview.layoutDrag and preview.layoutDrag.scale,
                SNAP_COLOR)
        else
            SectionDrag.HideSectionOutline(preview)
        end
        return target, true, preview.gestureHasFree
    end

    --- The gesture ends when the overlay goes. The outline goes without
    --- asking: no gesture is live once the overlay hides, and a ring a drop
    --- left behind cannot be told from this frame's by identity.
    function SectionDrag.EndCursorDrop(host)
        local preview = CursorMirror(host)
        if not preview then return end
        SectionDrag.HideSectionOutline(preview)
        SectionDrag.EndGesture(preview)
    end
end

-- Private helpers consumed by later ButtonPanelPreview files.
PP.SectionDrag = SectionDrag
