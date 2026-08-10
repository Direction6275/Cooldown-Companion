--[[
    CooldownCompanion - ResourceBarLayoutOrderPreview
    Dedicated layout/order preview renderer for attached resource bars.
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon
local CS = ST._configState
local RB = ST._RB
local RBP = ST._RBP

local math_floor = math.floor
local math_min = math.min
local math_max = math.max
local table_insert = table.insert
local table_sort = table.sort

local GetConfigActiveResources = RBP.GetConfigActiveResources
local IsResourceBarVerticalConfig = RBP.IsResourceBarVerticalConfig

local StartDragTracking = ST._StartDragTracking
local CancelDrag = ST._CancelDrag
local HideDragIndicator = ST._HideDragIndicator
local ApplyIconTexCoord = ST._ApplyIconTexCoord
local SetStatusBarSmoothRange = ST.SetStatusBarSmoothRange
local SetStatusBarSmoothValue = ST.SetStatusBarSmoothValue
local SetStatusBarImmediateValue = ST.SetStatusBarImmediateValue

local POWER_NAMES = RB.POWER_NAMES
local SEGMENTED_TYPES = RB.SEGMENTED_TYPES
local RESOURCE_HEALTH = RB.RESOURCE_HEALTH
local RESOURCE_MAELSTROM_WEAPON = RB.RESOURCE_MAELSTROM_WEAPON
local DEFAULT_RESOURCE_TEXT_FONT = RB.DEFAULT_RESOURCE_TEXT_FONT
local DEFAULT_RESOURCE_TEXT_SIZE = RB.DEFAULT_RESOURCE_TEXT_SIZE
local DEFAULT_RESOURCE_TEXT_OUTLINE = RB.DEFAULT_RESOURCE_TEXT_OUTLINE

local IsTruthyConfigFlag = RB.IsTruthyConfigFlag
local IsAuraBlockEntry = RB.IsAuraBlockEntry
local GetResolvedCustomAuraBarAuraUnit = RB.GetResolvedCustomAuraBarAuraUnit
local IsVerticalFillReversed = RB.IsVerticalFillReversed
local GetResourceGlobalThickness = RB.GetResourceGlobalThickness
local GetResourceColors = RB.GetResourceColors
local CreateContinuousBar = RB.CreateContinuousBar
local CreateSegmentedBar = RB.CreateSegmentedBar
local LayoutSegments = RB.LayoutSegments
local CreateOverlayBar = RB.CreateOverlayBar
local LayoutOverlaySegments = RB.LayoutOverlaySegments
local StyleContinuousBar = RB.StyleContinuousBar
local StyleHealthBar = RB.StyleHealthBar
local StyleSegmentedBar = RB.StyleSegmentedBar
local PrepareCustomAuraBar = RB.PrepareCustomAuraBar
local EnsureCustomBarId = RB.EnsureCustomBarId
local EnsureCustomBarLayout = RB.EnsureCustomBarLayout
local GetCustomBarLayout = RB.GetCustomBarLayout
local ApplyPreviewBarState = RB.ApplyPreviewBarState
local GetMWMaxStacks = RB.GetMWMaxStacks
local CreatePixelBorders = RB.CreatePixelBorders
local ApplyPixelBorders = RB.ApplyPixelBorders
local HidePixelBorders = RB.HidePixelBorders
local POWER_SHORT_NAMES = RB.POWER_SHORT_NAMES or {}

-- The bars workspace draws ONE canvas for every object it configures: the
-- resource stack, the attached cast bar, and the unit-frame badges. Its
-- composition does not depend on the selection — selecting an object moves
-- the highlight and swaps the settings below, nothing else. Outside the
-- workspace this same renderer draws the buttons view's unified anchor
-- preview, which owns its own selection model.
local function IsBarsWorkspaceActive()
    return CS.barsEntrySelected == true
end

local LAYOUT_PREVIEW_PADDING = 12
local LAYOUT_PREVIEW_SECTION_GAP = 18
local LAYOUT_PREVIEW_GAP = 4
local LAYOUT_PREVIEW_DRAG_KIND = "layout-slot"
local LAYOUT_PREVIEW_ICON_FALLBACK = "Interface\\Icons\\INV_Misc_QuestionMark"
local LAYOUT_PREVIEW_ANIM_DURATION = 0.08
local LAYOUT_PREVIEW_EMPTY_DROP_SIZE = 8

-- The cast facsimile. A cast bar has no ready state, so the resting slot
-- shows a cast frozen part-way — enough to judge and to drag. The preview
-- state runs the same cast on a loop.
local CAST_PREVIEW_DURATION = 1.5
local CAST_PREVIEW_REST_FILL = 0.65
local CAST_PREVIEW_SPELL_NAME = "Preview Cast"

-- Custom-bar identity, revealed on hover (owner ruling 2026-07-26, after
-- seeing a permanent label in game). The preview must be clean at rest AND
-- identify every bar at a glance; those only conflict if identity is
-- visible at rest, so it is not. Hovering any bar names them ALL at once —
-- one mouse movement, no clicks, the whole map — and moving away leaves
-- bars only.
--
-- A permanent label was tried first and rejected: anything drawn inside the
-- bar's rect reads as the bar's own content no matter how it is styled,
-- because that rect is exactly where bar text lives. A transient overlay
-- has the opposite problem to solve — it reads as an affordance on sight,
-- so it can be properly legible instead of apologetically dim, and it is
-- never present while the owner is judging their design.
-- Custom bars only; resources are identified by their well-known colors.
local LAYOUT_PREVIEW_IDENTITY_FONT_SCREEN_SIZE = 10
local LAYOUT_PREVIEW_IDENTITY_INSET = 4
local LAYOUT_PREVIEW_IDENTITY_FONT_OUTLINE = "OUTLINE, SLUG"
-- Shell (Show Only While Aura Active) bars carry the bar-mode panel
-- mirror's crossed-eye badge, same atlas and counter-scale convention, so
-- the two previews say "this one only shows while its aura runs" the same
-- way. The atlas has substantial transparent padding around its glyph.
local LAYOUT_PREVIEW_VISIBILITY_BADGE_ATLAS = "GM-icon-visibleDis-pressed"
local LAYOUT_PREVIEW_VISIBILITY_BADGE_SCREEN_SIZE = 18
-- Aura-block members get their own badge: they leave the stack in play and
-- the bars past them close up, which the expanded preview cannot show.
local LAYOUT_PREVIEW_AURA_BLOCK_BADGE_ATLAS = "QuestRepeatableTurnin"
local LAYOUT_PREVIEW_AURA_BLOCK_BADGE_SCREEN_SIZE = 14

-- The handle on the seam between a lane's two aura-block buckets. One table
-- rather than a run of file-level functions: this chunk sits on Lua 5.1's
-- 200-local ceiling, so a feature's worth of names has to fold into a single
-- one. Its members are filled in further down, where the lane geometry they
-- read is in scope.
--
-- The size is a SCREEN size, counter-scaled against the fit-to-host scale
-- exactly like the identity marks: a hit target that shrank with the
-- composition would stop being one.
--
-- One flat glyph, no plate: it hangs over the bars the owner is judging, so
-- anything with a filled background of its own reads as part of the
-- composition. The glyph is orientation-neutral, which is why nothing here
-- keys off the lane axis.
local SwapSeam = {
    SCREEN_SIZE = 16,
    -- Cross-axis clearance between the bars' outer edge and the handle's
    -- NEAR edge: the handle sits wholly outside the bars (owner ruling; a
    -- centre-on-edge hang clipped them), close enough to stay attached to
    -- the seam it names. The hover plate overhangs the frame by 10% a side,
    -- so this must stay above that overhang.
    HANG = 3,
    GLYPH_ATLAS = "uitools-icon-refresh",
    HOVER_ATLAS = "uitools-icon-highlight",
    HOVER_SCALE = 1.2,
    REST = { 0.62, 0.64, 0.70, 1 },
    HOVER = { 1, 1, 1, 1 },
}

local GetLayoutPreviewIcon

local function CloneColor(color, fallback)
    if type(color) ~= "table" then
        return fallback and { fallback[1], fallback[2], fallback[3], fallback[4] } or nil
    end
    return {
        color[1] or (fallback and fallback[1]) or 0,
        color[2] or (fallback and fallback[2]) or 0,
        color[3] or (fallback and fallback[3]) or 0,
        color[4] ~= nil and color[4] or (fallback and fallback[4]) or 1,
    }
end

local function TintColor(color, amount, alpha)
    color = CloneColor(color, { 0.12, 0.12, 0.12, 1 })
    local mul = amount or 0
    return {
        math_max(0, math_min(1, color[1] + mul)),
        math_max(0, math_min(1, color[2] + mul)),
        math_max(0, math_min(1, color[3] + mul)),
        alpha ~= nil and alpha or color[4],
    }
end

local function ApplyBackdrop(frame, bg, border, edgeSize)
    if not frame then return end
    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = edgeSize or 1,
    })
    frame:SetBackdropColor((bg and bg[1]) or 0, (bg and bg[2]) or 0, (bg and bg[3]) or 0, (bg and bg[4]) or 1)
    frame:SetBackdropBorderColor((border and border[1]) or 0, (border and border[2]) or 0, (border and border[3]) or 0, (border and border[4]) or 1)
end

local function ResolvePreviewSkin(host)
    local frames = {
        host,
        host and host:GetParent(),
        CS.configFrame and CS.configFrame.col3 and CS.configFrame.col3.frame,
        CS.configFrame and CS.configFrame.col3 and CS.configFrame.col3.content,
    }

    local baseBg
    local baseBorder
    for _, frame in ipairs(frames) do
        if frame and frame.GetBackdropColor then
            local r, g, b, a = frame:GetBackdropColor()
            if r then
                baseBg = { r, g, b, a }
                break
            end
        end
    end
    for _, frame in ipairs(frames) do
        if frame and frame.GetBackdropBorderColor then
            local r, g, b, a = frame:GetBackdropBorderColor()
            if r then
                baseBorder = { r, g, b, a }
                break
            end
        end
    end

    baseBg = baseBg or { 0.08, 0.08, 0.10, 0.92 }
    baseBorder = baseBorder or { 0.25, 0.25, 0.28, 1 }

    return {
        slotBg = TintColor(baseBg, 0.01, 0.94),
        slotBorder = TintColor(baseBorder, 0.02, 1),
        slotHover = { 0.38, 0.60, 0.92, 1 },
        gapBg = TintColor(baseBg, 0.03, 0.28),
        gapBorder = { 0.38, 0.60, 0.92, 0.95 },
        ghostBg = TintColor(baseBg, 0.03, 0.96),
        ghostBorder = TintColor(baseBorder, 0.04, 1),
    }
end

-- Bottom chrome on the host claims a band the composition must stay clear
-- of. Two owners can claim it, each from its own corner: the preview
-- command center (bottom-left, on every workspace that has one) and the
-- bars workspace's module-enable cluster (bottom-right). They share one
-- band, so the reserve is whichever needs more. Hosts with neither report 0.
local function GetHostBottomReserve(host)
    if not host then return 0 end
    return math_max(host._cdcPreviewReserveBottom or 0,
        host._cdcBarsCornerReserveBottom or 0)
end

local function ApplyHostBottomReserve(host, root)
    root:ClearAllPoints()
    root:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0)
    root:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", 0, GetHostBottomReserve(host))
end

local function EnsurePreviewState(host)
    local preview = host._cdcLayoutPreview
    if preview then
        preview.buildId = (preview.buildId or 0) + 1
        preview.skin = ResolvePreviewSkin(host)
        ApplyHostBottomReserve(host, preview.root)
        return preview
    end

    preview = {
        buildId = 1,
        pools = {
            containers = {},
            slots = {},
            gaps = {},
            pills = {},
            swaps = {},
        },
        used = {},
        tweens = {},
        -- Slots whose rendered state is time-driven: the Active Aura
        -- stand-in's pulse and colour shift, the low-health alert, the cast
        -- sweep. Rebuilt every pass, ticked by TickPreview while non-empty.
        animated = {},
        skin = ResolvePreviewSkin(host),
    }
    host._cdcLayoutPreview = preview

    -- The root already carries the host's bottom reserve, so the content
    -- block centers into it with a zero offset - which stays exact under
    -- the fit-to-host scale, where a non-zero anchor offset would be
    -- measured in the scaled frame's own coordinate space and have to be
    -- divided back out.
    local root = CreateFrame("Frame", nil, host)
    root:SetClipsChildren(false)
    root:Hide()
    ApplyHostBottomReserve(host, root)
    preview.root = root

    local ghost = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    ghost:SetFrameStrata("TOOLTIP")
    ghost:SetFrameLevel(2000)
    ghost:SetClipsChildren(false)
    ghost:EnableMouse(false)
    ghost:Hide()
    preview.ghost = ghost

    return preview
end

local function ResetPreviewState(preview)
    preview.used.containers = 0
    preview.used.slots = 0
    preview.used.gaps = 0
    preview.used.pills = 0
    preview.used.swaps = 0
    preview.renderedSelectionKeys = {}
    preview.independentResources = false
    preview.layoutDrag = nil
    preview.animated = preview.animated or {}
    wipe(preview.animated)
    preview.root:Show()
    preview.root:SetScript("OnUpdate", nil)
end

local function FinalizePreviewState(preview)
    for poolName, pool in pairs(preview.pools) do
        local used = preview.used[poolName] or 0
        for index = used + 1, #pool do
            local frame = pool[index]
            frame:Hide()
            frame:ClearAllPoints()
            frame:SetParent(preview.root)
            frame:SetScript("OnMouseDown", nil)
            frame:SetScript("OnMouseUp", nil)
            frame:SetScript("OnEnter", nil)
            frame:SetScript("OnLeave", nil)
        end
    end
end

local function AcquireContainer(preview, parent)
    local pool = preview.pools.containers
    local index = (preview.used.containers or 0) + 1
    preview.used.containers = index
    local frame = pool[index]
    if not frame then
        frame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
        frame:SetClipsChildren(false)
        pool[index] = frame
    end
    frame:SetParent(parent)
    frame:Show()
    return frame
end

local function ApplyPreviewEdgeBorder(frame, size, color)
    if not (frame and frame.borderTextures) then return end
    local renderMode = ST.GetEffectiveBorderRenderMode(frame._previewBorderRenderMode, nil, size)
    ST.ApplyBorderTextures(frame.borderTextures, frame, color or { 0, 0, 0, 1 }, size or 1, renderMode)
end

local function HidePreviewEdgeBorder(frame)
    if not (frame and frame.borderTextures) then return end
    for i = 1, 4 do
        frame.borderTextures[i]:Hide()
    end
end

local function GetSourceIconBorderSize(button, fallback)
    -- Live icon geometry can be secret-sensitive in config context, so do not
    -- derive inset size from GetLeft()/GetRight()-style measurements here.
    -- Use the configured border size as the safe preview fallback instead.
    return fallback
end

local function StyleMirroredIconFrame(iconFrame, button, group)
    if not iconFrame then return end

    local style = group and group.style or {}
    if button and button.buttonData and CooldownCompanion.GetEffectiveStyle then
        style = CooldownCompanion:GetEffectiveStyle(style, button.buttonData) or style
    end

    local borderSize = GetSourceIconBorderSize(button, style.borderSize or ST.DEFAULT_BORDER_SIZE or 1)
    local borderRenderMode = ST.GetBorderRenderMode(style)
    local borderLayoutSize = ST.GetEffectiveBorderLayoutSize(iconFrame, borderSize, borderRenderMode)
    local bgColor = CloneColor(style.backgroundColor, { 0, 0, 0, 0.5 })
    local borderColor = CloneColor(style.borderColor, { 0, 0, 0, 1 })
    local showBorder = (borderSize > 0 or ST.IsEffectiveCrispBorderRenderMode(borderRenderMode, nil, borderSize)) and ((borderColor[4] ~= nil and borderColor[4] > 0) or borderColor[4] == nil)

    if button and button.borderTextures then
        local anyShown = false
        for i = 1, 4 do
            local tex = button.borderTextures[i]
            if tex and tex:IsShown() then
                anyShown = true
                break
            end
        end
        showBorder = anyShown and showBorder
    end

    iconFrame.bg:SetColorTexture(bgColor[1] or 0, bgColor[2] or 0, bgColor[3] or 0, bgColor[4] ~= nil and bgColor[4] or 1)
    iconFrame.icon:ClearAllPoints()
    iconFrame.icon:SetPoint("TOPLEFT", iconFrame, "TOPLEFT", borderLayoutSize, -borderLayoutSize)
    iconFrame.icon:SetPoint("BOTTOMRIGHT", iconFrame, "BOTTOMRIGHT", -borderLayoutSize, borderLayoutSize)
    iconFrame.icon:SetTexture((button and button.icon and button.icon:GetTexture()) or GetLayoutPreviewIcon(button and button.buttonData))
    iconFrame.icon:Show()
    iconFrame.countText:Hide()

    if button and button.icon and button.icon.GetTexCoord then
        iconFrame.icon:SetTexCoord(button.icon:GetTexCoord())
    else
        ApplyIconTexCoord(iconFrame.icon, iconFrame:GetWidth(), iconFrame:GetHeight(), style.iconZoom)
    end

    if showBorder then
        iconFrame._previewBorderRenderMode = borderRenderMode
        ApplyPreviewEdgeBorder(iconFrame, borderSize, borderColor)
    else
        HidePreviewEdgeBorder(iconFrame)
    end
end

local function CreateSlotFrame(parent)
    local frame = CreateFrame("Button", nil, parent, "BackdropTemplate")
    frame:SetClipsChildren(false)
    frame:RegisterForClicks("LeftButtonDown", "AnyUp")

    frame.titleIcon = frame:CreateTexture(nil, "ARTWORK")
    frame.titleIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    frame.titleText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frame.titleText:SetJustifyH("LEFT")
    frame.titleText:SetWordWrap(false)

    frame.shortText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frame.shortText:SetJustifyH("CENTER")
    frame.shortText:SetWordWrap(false)

    frame.previewCanvas = CreateFrame("Frame", nil, frame)
    frame.previewCanvas:SetClipsChildren(false)

    frame.grip = frame:CreateTexture(nil, "OVERLAY")
    frame.grip:SetColorTexture(1, 1, 1, 0.14)

    frame.hoverHighlight = CreateFrame("Frame", nil, frame)
    frame.hoverHighlight:SetAllPoints(frame.previewCanvas)
    frame.hoverHighlight:EnableMouse(false)
    frame.hoverHighlight.tex = frame.hoverHighlight:CreateTexture(nil, "OVERLAY")
    frame.hoverHighlight.tex:SetAllPoints()
    frame.hoverHighlight.tex:SetColorTexture(1, 1, 1, 0.10)
    frame.hoverHighlight.tex:SetBlendMode("ADD")
    frame.hoverHighlight:Hide()

    -- Selection marker: the hover-style glow held on while the bar is
    -- selected, plus inward-pointing arrows flanking it. Elevated like
    -- hoverHighlight so it renders above the bar visuals.
    frame.selectedHighlight = CreateFrame("Frame", nil, frame)
    frame.selectedHighlight:SetAllPoints(frame.previewCanvas)
    frame.selectedHighlight:EnableMouse(false)
    frame.selectedHighlight.tex = frame.selectedHighlight:CreateTexture(nil, "OVERLAY")
    frame.selectedHighlight.tex:SetAllPoints()
    frame.selectedHighlight.tex:SetColorTexture(1, 1, 1, 0.10)
    frame.selectedHighlight.tex:SetBlendMode("ADD")
    frame.selectedHighlight.side1 = frame.selectedHighlight:CreateTexture(nil, "OVERLAY")
    frame.selectedHighlight.side2 = frame.selectedHighlight:CreateTexture(nil, "OVERLAY")
    frame.selectedHighlight:Hide()

    -- Config-chrome identity marks (custom bars only), above the bar
    -- visuals but below the hover/selection highlights so those still read
    -- as the topmost state.
    frame.identityLayer = CreateFrame("Frame", nil, frame)
    frame.identityLayer:SetAllPoints(frame.previewCanvas)
    frame.identityLayer:EnableMouse(false)
    frame.identityLayer.label = frame.identityLayer:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frame.identityLayer.label:SetWordWrap(false)
    frame.identityLayer.badge = frame.identityLayer:CreateTexture(nil, "OVERLAY", nil, 7)
    frame.identityLayer:Hide()

    return frame
end

local function AcquireSlot(preview, parent)
    local pool = preview.pools.slots
    local index = (preview.used.slots or 0) + 1
    preview.used.slots = index
    local frame = pool[index]
    if not frame then
        frame = CreateSlotFrame(parent)
        pool[index] = frame
    end
    frame:SetParent(parent)
    frame:Show()
    frame:SetScript("OnMouseDown", nil)
    frame:SetScript("OnEnter", nil)
    frame:SetScript("OnLeave", nil)
    return frame
end

local function AcquireGap(preview, parent)
    local pool = preview.pools.gaps
    local index = (preview.used.gaps or 0) + 1
    preview.used.gaps = index
    local frame = pool[index]
    if not frame then
        frame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
        frame.text = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        frame.text:SetPoint("CENTER")
        frame.text:SetText("Drop")
        pool[index] = frame
    end
    frame:SetParent(parent)
    frame:Show()
    frame.text:Hide()
    return frame
end

-- Mouse-enabled on its own small rect alone, so it never takes a drag off
-- the bars it sits over. The hover plate is created below the glyph and
-- anchored once: ApplyScale only ever resizes, so the CENTER anchor keeps
-- both on the seam.
function SwapSeam.Acquire(preview, parent)
    local pool = preview.pools.swaps
    if not pool then
        pool = {}
        preview.pools.swaps = pool
    end
    local index = (preview.used.swaps or 0) + 1
    preview.used.swaps = index
    local frame = pool[index]
    if not frame then
        frame = CreateFrame("Button", nil, parent)
        frame:SetClipsChildren(false)
        frame:RegisterForClicks("LeftButtonUp")
        pool[index] = frame
    end
    if not frame.glyph then
        frame.hover = frame:CreateTexture(nil, "ARTWORK")
        frame.hover:SetAtlas(SwapSeam.HOVER_ATLAS, false)
        frame.hover:SetPoint("CENTER")
        frame.hover:Hide()
        frame.glyph = frame:CreateTexture(nil, "OVERLAY")
        frame.glyph:SetAtlas(SwapSeam.GLYPH_ATLAS, false)
        frame.glyph:SetPoint("CENTER")
    end
    frame:SetParent(parent)
    frame:EnableMouse(true)
    frame:Show()
    return frame
end

-- The bars workspace's pills. One visual family for two kinds of item:
-- the unit-frame badges, which are canvas objects riding under the bar
-- stack as part of the composition, and the module-enable pills pinned to
-- the pane's bottom-right corner. Everything else this workspace can
-- configure but is not drawing right now goes to the quiet text-chip strip
-- below the editing divider, not here.
--
-- The badges are deliberately not facsimile unit frames. The frame
-- anchoring module re-anchors the player's real unit frames and draws
-- nothing of its own, so a mocked-up health bar would promise a look
-- Cooldown Companion never renders. A badge promises only what it is: a
-- handle on that frame's anchoring settings.
local BARS_PILL_HEIGHT = 26
local BARS_PILL_MIN_WIDTH = 112
local BARS_PILL_GAP = 10
local BARS_PILL_LINE_GAP = 6
local BARS_PILL_INSET = 9
local BARS_PILL_ACCENT_WIDTH = 3
local BARS_PILL_ICON_SIZE = 16
local BARS_PILL_ICON_GAP = 5
local BARS_PILL_TEXT_COLOR = { 0.70, 0.68, 0.64 }
local BARS_PILL_SELECTED_TEXT_COLOR = { 1, 1, 1 }
local BARS_PILL_NEUTRAL_ACCENT = { 0.46, 0.48, 0.53 }
local BARS_PILL_ENABLE_ACCENT = { 0.36, 0.72, 0.45 }
-- Selection border: the same blue the canvas slots use for hover/selection.
local BARS_PILL_SELECTED_BORDER = { 0.38, 0.60, 0.92, 1 }
local BARS_PILL_TARGET_ICON = "groupfinder-icon-friend"

-- The badge pair sits under the bar stack with a modest gap, inside the
-- content block and therefore inside the fit-to-host scale.
local BARS_BADGE_GAP = 15

-- The module-enable cluster mirrors the preview command center across the
-- pane: same bottom band, same insets off its own corner, so the two read
-- as one line of chrome framing the canvas. Matching that band is why
-- these pills are the bar's height rather than the badges' - level with
-- the command center matters more here than a shared pill height.
-- Its lines stack upward when the pane is too narrow for one row.
local BARS_CORNER_PILL_HEIGHT = 20
local BARS_CORNER_BOTTOM_INSET = 3
local BARS_CORNER_SIDE_INSET = 4
local BARS_CORNER_COMMAND_GAP = 12

-- Re-attached on every acquire: FinalizePreviewState strips these from
-- pooled frames it parks, so a pill reused by a later build would come back
-- without its hover state or tooltip.
local function BarsPillOnEnter(self)
    self.hover:Show()
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(self._cdcTooltip or "", 1, 1, 1)
    if self._cdcTooltipLine then
        GameTooltip:AddLine(self._cdcTooltipLine, 0.75, 0.82, 0.92, true)
    end
    if self._cdcTooltipNote then
        GameTooltip:AddLine(self._cdcTooltipNote, 0.62, 0.62, 0.66, true)
    end
    GameTooltip:Show()
end

local function BarsPillOnLeave(self)
    self.hover:Hide()
    GameTooltip:Hide()
end

local function CreateBarsPill(parent)
    local frame = CreateFrame("Button", nil, parent, "BackdropTemplate")
    frame:RegisterForClicks("AnyUp")
    frame:SetClipsChildren(false)

    frame.accent = frame:CreateTexture(nil, "ARTWORK")
    frame.accent:SetWidth(BARS_PILL_ACCENT_WIDTH)
    frame.accent:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -1)
    frame.accent:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 1, 1)

    frame.icon = frame:CreateTexture(nil, "ARTWORK")
    frame.icon:SetSize(BARS_PILL_ICON_SIZE, BARS_PILL_ICON_SIZE)
    frame.icon:SetPoint("LEFT", frame, "LEFT", BARS_PILL_ACCENT_WIDTH + BARS_PILL_ICON_GAP, 0)
    frame.icon:Hide()

    frame.label = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frame.label:SetJustifyH("CENTER")
    frame.label:SetJustifyV("MIDDLE")
    frame.label:SetWordWrap(false)

    frame.hover = frame:CreateTexture(nil, "OVERLAY")
    frame.hover:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -1)
    frame.hover:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -1, 1)
    frame.hover:SetColorTexture(1, 1, 1, 0.10)
    frame.hover:SetBlendMode("ADD")
    frame.hover:Hide()

    frame.selected = frame:CreateTexture(nil, "OVERLAY", nil, 1)
    frame.selected:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -1)
    frame.selected:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -1, 1)
    frame.selected:SetColorTexture(1, 1, 1, 0.10)
    frame.selected:SetBlendMode("ADD")
    frame.selected:Hide()

    return frame
end

local function AcquireBarsPill(preview, parent)
    local pool = preview.pools.pills
    local index = (preview.used.pills or 0) + 1
    preview.used.pills = index
    local frame = pool[index]
    if not frame then
        frame = CreateBarsPill(parent)
        pool[index] = frame
    end
    frame:SetParent(parent)
    frame:SetScript("OnEnter", BarsPillOnEnter)
    frame:SetScript("OnLeave", BarsPillOnLeave)
    frame.hover:Hide()
    frame:Show()
    return frame
end

-- The root already stops short of the host's bottom band, so a message
-- centered in it never collides with the chrome pinned down there.
local function SetPreviewMessage(preview, message)
    local label = preview.messageLabel
    if not label then
        label = preview.root:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        label:SetJustifyH("CENTER")
        label:SetJustifyV("MIDDLE")
        label:SetWordWrap(true)
        preview.messageLabel = label
    end
    label:ClearAllPoints()
    label:SetPoint("TOPLEFT", preview.root, "TOPLEFT", 18, -18)
    label:SetPoint("BOTTOMRIGHT", preview.root, "BOTTOMRIGHT", -18, 18)
    label:SetText(message or "")
    label:Show()
end

local function HidePreviewMessage(preview)
    if preview.messageLabel then
        preview.messageLabel:Hide()
    end
end

GetLayoutPreviewIcon = function(buttonData)
    if not buttonData then
        return LAYOUT_PREVIEW_ICON_FALLBACK
    end

    local icon
    if buttonData.type == "spell" then
        icon = C_Spell.GetSpellTexture(buttonData.id)
    elseif CooldownCompanion.IsEquipmentSlotEntry
        and CooldownCompanion.IsEquipmentSlotEntry(buttonData) then
        local effectiveItem = CooldownCompanion.ResolveEffectiveItem
            and CooldownCompanion.ResolveEffectiveItem(buttonData, true) or nil
        if effectiveItem and effectiveItem.trackable then
            icon = effectiveItem.icon
        end
    elseif buttonData.type == "item" then
        icon = C_Item.GetItemIconByID(buttonData.id)
    end

    if buttonData.manualIcon then
        icon = buttonData.manualIcon
    end

    return icon or LAYOUT_PREVIEW_ICON_FALLBACK
end

local function GetConfiguredPreviewIconSize(group)
    local style = group and group.style or {}

    if style.maintainAspectRatio then
        local size = style.buttonSize or ST.BUTTON_SIZE or 36
        return size, size
    end

    local width = style.iconWidth or style.buttonSize or ST.BUTTON_SIZE or 36
    local height = style.iconHeight or style.buttonSize or ST.BUTTON_SIZE or 36
    return width, height
end

local function GetSavedPreviewButtons(group)
    if CooldownCompanion:IsRotationAssistantGroup(group) then
        local spellID = CooldownCompanion:GetRotationAssistantActionSpellID()
        return {
            {
                buttonData = {
                    type = "spell",
                    id = spellID,
                    name = ST.ROTATION_ASSISTANT_NAME,
                    manualIcon = CooldownCompanion:GetRotationAssistantFallbackIcon(spellID),
                    _rotationAssistantVirtual = true,
                    _rotationAssistantMissing = true,
                },
            },
        }
    end

    local buttons = {}
    local fallbackButtons = {}

    for _, buttonData in ipairs(group.buttons or {}) do
        if buttonData and buttonData.enabled ~= false then
            fallbackButtons[#fallbackButtons + 1] = { buttonData = buttonData }
            if not CooldownCompanion.IsButtonUsable or CooldownCompanion:IsButtonUsable(buttonData, group) then
                buttons[#buttons + 1] = { buttonData = buttonData }
            end
        end
    end

    if #buttons == 0 then
        buttons = fallbackButtons
    end

    local maxVisibleButtons = tonumber(group.maxVisibleButtons) or 0
    if maxVisibleButtons > 0 and #buttons > maxVisibleButtons then
        local trimmed = {}
        for i = 1, maxVisibleButtons do
            trimmed[#trimmed + 1] = buttons[i]
        end
        buttons = trimmed
    end

    return buttons
end

-- Two questions, and only two: is there an icon panel worth wrapping (and if
-- not, which message says so), and which panel is it. The canvas used to draw
-- its own facsimile of that panel from this table, so it carried a full grid
-- description; every owner now lends the real read-only mirror instead and
-- builds it from `groupId` alone. `iconHeight` survives that as the fallback
-- bar thickness for the one case with no configured resource thickness to
-- read - the configured size rather than the live frame's measured one,
-- which is also what the mirror lays itself out from.
local function BuildSourcePanelData(groupId, group, visibleButtons)
    if not group or not CooldownCompanion:IsIconLikeDisplayMode(group.displayMode) then
        return nil, "The current attached anchor panel is not an icon-like panel, so there is no icon row to mirror."
    end

    if #visibleButtons == 0 then
        return nil, "The current anchor panel has no saved icon buttons to mirror."
    end

    local _, iconHeight = GetConfiguredPreviewIconSize(group)

    return {
        groupId = groupId,
        iconHeight = iconHeight,
    }
end

local function IsGroupConfigAvailableForPreview(groupId, checkLoadConditions)
    local group = CooldownCompanion.db.profile.groups and CooldownCompanion.db.profile.groups[groupId]
    if not group then return false end
    if not group.parentContainerId then return false end
    if not CooldownCompanion:IsIconLikeDisplayMode(group.displayMode) then return false end
    if group.anchorEligible == false then return false end
    if CooldownCompanion.DoesAnchorTargetReachCursorRoot
        and CooldownCompanion:DoesAnchorTargetReachCursorRoot("CooldownCompanionGroup" .. tostring(groupId)) then
        return false
    end

    local container = CooldownCompanion:GetParentContainer(group)
    if container and container.isGlobal and not container.anchorEligible then return false end
    if container and not container.isGlobal and container.anchorEligible == false then return false end

    return CooldownCompanion:IsGroupActive(groupId, {
        group = group,
        requireButtons = true,
        checkCharVisibility = true,
        checkLoadConditions = checkLoadConditions,
    })
end

local function GetFirstConfiguredAnchorGroup()
    local db = CooldownCompanion.db and CooldownCompanion.db.profile
    local groups = db and db.groups
    local containers = db and db.groupContainers
    if not groups or not containers then return nil end

    local specId = CooldownCompanion._currentSpecId
    local orderedContainers = {}

    for containerId, container in pairs(containers) do
        orderedContainers[#orderedContainers + 1] = {
            id = containerId,
            order = CooldownCompanion:GetOrderForSpec(container, specId, containerId),
        }
    end
    table_sort(orderedContainers, function(a, b)
        return a.order < b.order
    end)

    for _, containerInfo in ipairs(orderedContainers) do
        local panels = CooldownCompanion:GetPanels(containerInfo.id)
        for _, panelInfo in ipairs(panels) do
            if IsGroupConfigAvailableForPreview(panelInfo.groupId, false) then
                return panelInfo.groupId
            end
        end
    end

    return nil
end

local function ResolveLayoutPreviewSourcePanel()
    local liveGroupId = CooldownCompanion:GetFirstAvailableAnchorGroup()
    if liveGroupId then
        local liveGroup = CooldownCompanion.db.profile.groups and CooldownCompanion.db.profile.groups[liveGroupId]
        local liveFrame = CooldownCompanion.groupFrames and CooldownCompanion.groupFrames[liveGroupId]
        if liveGroup and liveFrame and liveFrame:IsShown() then
            local liveButtons = {}
            for _, button in ipairs(liveFrame.buttons or {}) do
                if button and button:IsShown() and button.buttonData then
                    table_insert(liveButtons, button)
                end
            end
            if #liveButtons > 0 then
                return BuildSourcePanelData(liveGroupId, liveGroup, liveButtons)
            end
        end
    end

    local groupId = liveGroupId or GetFirstConfiguredAnchorGroup()
    if not groupId then
        return nil, "No attached icon panel is configured to mirror. Enable or create an icon-mode panel first."
    end

    local group = CooldownCompanion.db.profile.groups and CooldownCompanion.db.profile.groups[groupId]
    local savedButtons = group and GetSavedPreviewButtons(group) or nil
    if not savedButtons or #savedButtons == 0 then
        return nil, "The current attached anchor panel has no saved icon buttons to mirror."
    end

    return BuildSourcePanelData(groupId, group, savedButtons)
end

local function GetShortLabel(label)
    if not label or label == "" then
        return "Bar"
    end
    local first = string.match(label, "^(%S+)")
    if not first then
        return label
    end
    if #first > 4 then
        return string.sub(first, 1, 4)
    end
    return first
end

local function CollectPreviewSlots(rbSettings, cbSettings, layout, isVerticalLayout, includeResourceSlots,
    requireRuntimeEligibleSlots)
    includeResourceSlots = includeResourceSlots == true
    local activeResources = includeResourceSlots
        and (requireRuntimeEligibleSlots and RB.DetermineActiveResources() or GetConfigActiveResources())
        or {}
    local customBars = includeResourceSlots and CooldownCompanion:GetSpecCustomAuraBars() or {}
    local primarySlots = {}
    local castSlots = {}
    local resourceBarsEnabled = includeResourceSlots and rbSettings and rbSettings.enabled

    if includeResourceSlots then
        layout.resources = layout.resources or {}
        layout.customAuraBarSlots = layout.customAuraBarSlots or {}
        layout.customBars = layout.customBars or {}
        rbSettings = rbSettings or {}
        rbSettings.resources = rbSettings.resources or {}
    end

    -- Per-slot thickness, resolved exactly as the apply pass resolves it
    -- (ResourceBar.lua, the customBarHeights branch): the override only
    -- applies when that layout flag is on, and the axis decides which
    -- stored key wins. Without this every slot rendered at one uniform
    -- thickness, so a bar with an override previewed at the wrong size.
    local globalThickness = includeResourceSlots
        and tonumber(GetResourceGlobalThickness(rbSettings)) or nil

    local function ResolveSlotThickness(slotLayout)
        if not (layout.customBarHeights and type(slotLayout) == "table") then
            return globalThickness
        end
        local override
        if isVerticalLayout then
            override = slotLayout.barWidth or slotLayout.barHeight
        else
            override = slotLayout.barHeight or slotLayout.barWidth
        end
        return tonumber(override) or globalThickness
    end

    local function GetSlotColor(powerType)
        if powerType == RESOURCE_HEALTH then
            local health = rbSettings.resources and rbSettings.resources[RESOURCE_HEALTH]
            local color = CloneColor(health and health.healthBarColor, RB.DEFAULT_HEALTH_BAR_COLOR)
            color[4] = tonumber(health and health.healthBarOpacity) or RB.DEFAULT_HEALTH_BAR_OPACITY
            return color
        end

        local color = { GetResourceColors(powerType, rbSettings) }
        if color[1] == nil then
            return { 1, 1, 1, 1 }
        end
        return {
            color[1] or 1,
            color[2] or 1,
            color[3] or 1,
            color[4] ~= nil and color[4] or 1,
        }
    end

    for _, powerType in ipairs(activeResources) do
        if powerType == RESOURCE_HEALTH and type(rbSettings.resources[powerType]) ~= "table" then
            rbSettings.resources[powerType] = { enabled = false }
        else
            rbSettings.resources[powerType] = rbSettings.resources[powerType] or {}
        end
        local resourceConfig = rbSettings.resources[powerType]
        local showResource = resourceBarsEnabled and (
            powerType == RESOURCE_HEALTH and resourceConfig.enabled == true
            or resourceConfig.enabled ~= false
        )
        if showResource and powerType == 0 and rbSettings.hideManaForNonHealer then
            local specIndex = C_SpecializationInfo.GetSpecialization()
            if specIndex then
                local specID, _, _, _, role = C_SpecializationInfo.GetSpecializationInfo(specIndex)
                if specID ~= 62 and role ~= "HEALER" then
                    showResource = false
                end
            end
        end

        if showResource then
            local function EnsureLayoutResource()
                layout.resources[powerType] = layout.resources[powerType] or {}
                return layout.resources[powerType]
            end

            table_insert(primarySlots, {
                id = "resource:" .. tostring(powerType),
                slotCategory = "primary",
                kind = "resource",
                powerType = powerType,
                label = POWER_NAMES[powerType] or ("Power " .. powerType),
                shortLabel = POWER_SHORT_NAMES[powerType] or GetShortLabel(POWER_NAMES[powerType] or ("Power " .. powerType)),
                thickness = ResolveSlotThickness(layout.resources[powerType]),
                color = GetSlotColor(powerType),
                icon = resourceConfig.previewIcon or LAYOUT_PREVIEW_ICON_FALLBACK,
                getPos = function()
                    local slot = layout.resources[powerType]
                    if isVerticalLayout then
                        local pos = slot and slot.verticalPosition
                        if pos == "left" or pos == "right" then
                            return pos
                        end
                        return (slot and slot.position == "above") and "left" or "right"
                    end
                    return (slot and slot.position) or "below"
                end,
                getOrder = function()
                    local slot = layout.resources[powerType]
                    if isVerticalLayout then
                        return (slot and slot.verticalOrder) or (slot and slot.order) or (900 + powerType)
                    end
                    return (slot and slot.order) or (900 + powerType)
                end,
                setPos = function(value)
                    local slot = EnsureLayoutResource()
                    if isVerticalLayout then
                        slot.verticalPosition = value
                    else
                        slot.position = value
                    end
                end,
                setOrder = function(value)
                    local slot = EnsureLayoutResource()
                    if isVerticalLayout then
                        slot.verticalOrder = value
                    else
                        slot.order = value
                    end
                end,
            })
        end
    end

    if resourceBarsEnabled then
        for customIndex, customAura in ipairs(customBars or {}) do
            if customAura and customAura.enabled and customAura.spellID
                and (not requireRuntimeEligibleSlots
                    or CooldownCompanion:IsCustomBarRuntimeEligible(customAura)) then
                local customBarId = EnsureCustomBarId(rbSettings, customAura)
                local spellInfo = C_Spell.GetSpellInfo(customAura.spellID)
                local label = spellInfo and spellInfo.name or customAura.label or ("Custom Bar " .. customIndex)
                local slotName = "Custom Bar: " .. label
                local function EnsureLayoutSlot()
                    return EnsureCustomBarLayout(rbSettings, nil, customBarId, 1000 + customIndex)
                end

                table_insert(primarySlots, {
                    id = "custom:" .. tostring(customBarId),
                    slotCategory = "primary",
                    kind = "custom",
                    customAuraIndex = customIndex,
                    customBarId = customBarId,
                    customEntry = {
                        kind = "custom",
                        customBarIndex = customIndex,
                        customBarId = customBarId,
                        config = customAura,
                    },
                    label = slotName,
                    shortLabel = GetShortLabel(label),
                    thickness = ResolveSlotThickness(
                        GetCustomBarLayout(rbSettings, nil, customAura, false)),
                    color = CloneColor(customAura.barColor, { 0.52, 0.64, 1.0, 1 }),
                    icon = C_Spell.GetSpellTexture(customAura.spellID) or LAYOUT_PREVIEW_ICON_FALLBACK,
                    getPos = function()
                        local slot = GetCustomBarLayout(rbSettings, nil, customAura, false)
                        if isVerticalLayout then
                            local pos = slot and slot.verticalPosition
                            if pos == "left" or pos == "right" then
                                return pos
                            end
                            return (slot and slot.position == "above") and "left" or "right"
                        end
                        return (slot and slot.position) or "below"
                    end,
                    getOrder = function()
                        local slot = GetCustomBarLayout(rbSettings, nil, customAura, false)
                        if isVerticalLayout then
                            return (slot and slot.verticalOrder) or (slot and slot.order) or (1000 + customIndex)
                        end
                        return (slot and slot.order) or (1000 + customIndex)
                    end,
                    setPos = function(value)
                        local slot = EnsureLayoutSlot()
                        if isVerticalLayout then
                            slot.verticalPosition = value
                        else
                            slot.position = value
                        end
                    end,
                    setOrder = function(value)
                        local slot = EnsureLayoutSlot()
                        if isVerticalLayout then
                            slot.verticalOrder = value
                        else
                            slot.order = value
                        end
                    end,
                })
            end
        end
    end

    if cbSettings and cbSettings.enabled and not IsTruthyConfigFlag(cbSettings.independentAnchorEnabled) then
        table_insert(castSlots, {
            id = "cast",
            slotCategory = "cast",
            kind = "cast",
            label = "Cast Bar",
            shortLabel = "Cast",
            -- The cast bar's own height, not the stack's: it used to be
            -- folded into one max with the resource thickness, which
            -- clamped every bar up to whichever was taller.
            thickness = tonumber(cbSettings.height) or 15,
            color = CloneColor(cbSettings.barColor, { 1.0, 0.72, 0.18, 1 }),
            icon = LAYOUT_PREVIEW_ICON_FALLBACK,
            getPos = function()
                return (layout.castBar and layout.castBar.position) or "below"
            end,
            getOrder = function()
                return (layout.castBar and layout.castBar.order) or 2000
            end,
            setPos = function(value)
                layout.castBar = layout.castBar or { position = "below", order = 2000 }
                layout.castBar.position = value
            end,
            setOrder = function(value)
                layout.castBar = layout.castBar or { position = "below", order = 2000 }
                layout.castBar.order = value
            end,
        })
    end

    return primarySlots, castSlots
end

-- Stack sections. The live stack packs aura-block entries into collapsing
-- containers at the far end of the side, past every fixed bar, and the cast
-- bar anchors past everything: the stack reserves no space for an
-- interleaved cast bar, so the far end is the only slot live geometry can
-- honour (owner ruling 2026-08-09). Order values alone cannot express any
-- of that, so the sort ranks sections first and orders within a section
-- second — ALWAYS, so this canvas can never show an arrangement the live
-- stack cannot render. A lane of only fixed bars has one rank and still
-- sorts purely on order.
--
-- A container tracks exactly ONE unit, so the block is really two chained
-- buckets: the bars watching YOUR auras nearest the panel, the bars watching
-- the TARGET past them. Each bucket is its own rank, which is all the sort
-- and the section-local drag math need to keep them from interleaving.
local STACK_RANK_FIXED = 0
local STACK_RANK_AURA_BLOCK_PLAYER = 1
local STACK_RANK_AURA_BLOCK_TARGET = 2
local STACK_RANK_CAST = 3

-- One test for the sort, the badge and the tooltip: the preview must not
-- carry its own copy of what counts as a block entry.
local function IsAuraBlockCustomBar(config)
    return type(config) == "table" and IsAuraBlockEntry(config) == true
end

local function IsAuraBlockSlot(slot)
    return slot.kind == "custom"
        and IsAuraBlockCustomBar(slot.customEntry and slot.customEntry.config)
end

-- Derived exactly the way the live partition derives it, so the canvas can
-- never draw a bucket the stack does not build.
local function GetAuraBlockSlotUnit(slot)
    local config = slot.customEntry and slot.customEntry.config
    if type(config) ~= "table" then
        return "player"
    end
    return GetResolvedCustomAuraBarAuraUnit(config, tonumber(config.spellID)) or "player"
end

-- Which bucket a slot belongs to, or nil for anything outside the block.
-- IDENTITY, never order: the wash colours key off this, so a flipped side
-- still draws your auras blue and the target's gold.
local function GetSlotBucketId(slot)
    if not IsAuraBlockSlot(slot) then
        return nil
    end
    if GetAuraBlockSlotUnit(slot) == "target" then
        return STACK_RANK_AURA_BLOCK_TARGET
    end
    return STACK_RANK_AURA_BLOCK_PLAYER
end

-- ORDER, not identity. The two bucket ranks trade places when the side is
-- flipped (auraBlockTargetFirst), which is what makes the sort, the seam
-- runs and the drag containment agree with the live bind order.
local function GetSlotStackRank(slot, targetFirst)
    local bucket = GetSlotBucketId(slot)
    if bucket then
        if not targetFirst then
            return bucket
        end
        if bucket == STACK_RANK_AURA_BLOCK_TARGET then
            return STACK_RANK_AURA_BLOCK_PLAYER
        end
        return STACK_RANK_AURA_BLOCK_TARGET
    end
    if slot.kind == "cast" then
        return STACK_RANK_CAST
    end
    return STACK_RANK_FIXED
end

-- Resolved ONCE per sort or layout pass and carried on the lane, never
-- re-read per comparator call: every rank in a pass has to answer to the same
-- flag or the comparator stops being a total order.
--
-- Reached through RB rather than through a file-level alias: this chunk sits
-- on Lua 5.1's 200-local ceiling, so the two bucket-order helpers are the
-- ones that pay for it.
local function GetPreviewTargetFirst(preview, side)
    return RB.IsAuraBlockTargetFirst(preview and preview.rbSettings, side) == true
end

-- The saved side a lane's block bars share, or nil plus a split marker when
-- they straddle two sides — which only the merged independent lane can
-- render. The bucket-order flag belongs to THIS side: the merged lane's own
-- label is just the dominant side and can disagree with where the bars are
-- actually saved, and the live stack builds its containers per saved side.
local function GetLaneBlockFlagSide(slots)
    local flagSide
    for _, slot in ipairs(slots or {}) do
        if IsAuraBlockSlot(slot) then
            local pos = slot.getPos()
            if flagSide == nil then
                flagSide = pos
            elseif flagSide ~= pos then
                return nil, true
            end
        end
    end
    return flagSide, false
end

-- Bucket membership is worn by the MEMBER BARS themselves, never by a shared
-- frame around them: anything drawn around the run has to shrink when a bar
-- lifts out of the stack, and a bucket that shrinks mid-drag reads as one
-- with no room for the bar in flight. Both colors are already in this
-- canvas's vocabulary - the slot-hover blue for your own auras, the
-- aura-block tooltip's gold for the target's.
--
-- `wash` is applied with ADD, the same blend the hover and selection glows
-- use, so it can only lift the bar and never mutes the colour the owner is
-- judging. The two alphas are not equal on purpose: they are matched by the
-- LUMA each hue adds (blue 0.14 and gold 0.10 both land at ~0.08), so neither
-- bucket reads louder than the other.
--
-- `gap*` is the drop cue and is drawn over empty lane, not over a bar, so it
-- is a plain translucent fill a step stronger than the wash. The inner fill
-- is part of the same cue and moves with it, or a target-bucket drop would
-- open a blue gap inside a gold run.
local LAYOUT_PREVIEW_BUCKET_TINTS = {
    [STACK_RANK_AURA_BLOCK_PLAYER] = {
        wash = { 0.38, 0.60, 0.92, 0.14 },
        gapBg = { 0.38, 0.60, 0.92, 0.26 },
        gapBorder = { 0.38, 0.60, 0.92, 0.95 },
        gapInner = { 0.38, 0.60, 0.92, 0.22 },
    },
    [STACK_RANK_AURA_BLOCK_TARGET] = {
        wash = { 1.00, 0.82, 0.20, 0.10 },
        gapBg = { 1.00, 0.82, 0.20, 0.20 },
        gapBorder = { 1.00, 0.82, 0.20, 0.95 },
        gapInner = { 1.00, 0.82, 0.20, 0.18 },
    },
}

-- Sections run the same direction the lane does: on a reversed lane index 1
-- is the slot furthest from the panel, so the block has to come first there
-- and last everywhere else.
local function CompareStackRank(a, b, reversed, targetFirst)
    local aRank = GetSlotStackRank(a, targetFirst)
    local bRank = GetSlotStackRank(b, targetFirst)
    if aRank == bRank then
        return nil
    end
    if reversed then
        return aRank > bRank
    end
    return aRank < bRank
end

local function SortSlotsForSide(slots, side, reversed, targetFirst)
    local out = {}
    for _, slot in ipairs(slots) do
        if slot.getPos() == side then
            table_insert(out, slot)
        end
    end
    table_sort(out, function(a, b)
        local rankResult = CompareStackRank(a, b, reversed, targetFirst)
        if rankResult ~= nil then
            return rankResult
        end
        if reversed then
            return a.getOrder() > b.getOrder()
        end
        return a.getOrder() < b.getOrder()
    end)
    return out
end

local function SortSlotsForIndependentStack(slots, firstSide, secondSide, preview)
    local firstCount = 0
    local secondCount = 0
    local out = {}
    for _, slot in ipairs(slots) do
        local side = slot.getPos()
        if side == firstSide then
            firstCount = firstCount + 1
        elseif side == secondSide then
            secondCount = secondCount + 1
        end
        table_insert(out, slot)
    end

    -- Preserve the visual direction of the side that already owns the
    -- stack. Ties use the normal below/right direction.
    local side = firstCount > secondCount and firstSide or secondSide
    local reversed = side == firstSide
    -- The flag comes from the side the block bars are SAVED on, not from the
    -- dominant side this merged lane happens to be labelled with.
    local targetFirst = GetPreviewTargetFirst(preview,
        GetLaneBlockFlagSide(out) or side)
    table_sort(out, function(a, b)
        local rankResult = CompareStackRank(a, b, reversed, targetFirst)
        if rankResult ~= nil then
            return rankResult
        end
        local aOrder = a.getOrder()
        local bOrder = b.getOrder()
        if aOrder ~= bOrder then
            -- Not `reversed and a>b or a<b`: that parses as `(reversed and
            -- a>b) or (a<b)`, which answers true for BOTH orderings of an
            -- unequal pair when reversed, and table.sort rejects such a
            -- comparator ("invalid order function").
            if reversed then return aOrder > bOrder end
            return aOrder < bOrder
        end
        return tostring(a.id) < tostring(b.id)
    end)
    return out, side, reversed
end

local function ApplySlotGeometry(frame, parent, x, y, width, height, alpha)
    frame:SetParent(parent)
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    frame:SetSize(width, height)
    frame:SetAlpha(alpha or 1)
    frame._cdcPreviewParent = parent
    frame._cdcPreviewX = x
    frame._cdcPreviewY = y
    frame._cdcPreviewW = width
    frame._cdcPreviewH = height
    frame._cdcPreviewA = alpha or 1
end

local function QueueSlotTween(preview, frame, parent, x, y, width, height, alpha, duration)
    local currentParent = frame._cdcPreviewParent
    if currentParent ~= parent or not frame._cdcPreviewX then
        ApplySlotGeometry(frame, parent, x, y, width, height, alpha)
        preview.tweens[frame] = nil
        return
    end

    local currentX = frame._cdcPreviewX
    local currentY = frame._cdcPreviewY
    local currentW = frame._cdcPreviewW
    local currentH = frame._cdcPreviewH
    local currentA = frame._cdcPreviewA

    if math.abs(currentX - x) < 0.5
        and math.abs(currentY - y) < 0.5
        and math.abs(currentW - width) < 0.5
        and math.abs(currentH - height) < 0.5
        and math.abs((currentA or 1) - (alpha or 1)) < 0.02 then
        ApplySlotGeometry(frame, parent, x, y, width, height, alpha)
        preview.tweens[frame] = nil
        return
    end

    preview.tweens[frame] = {
        parent = parent,
        sx = currentX,
        sy = currentY,
        sw = currentW,
        sh = currentH,
        sa = currentA or 1,
        tx = x,
        ty = y,
        tw = width,
        th = height,
        ta = alpha or 1,
        t0 = GetTime(),
        dur = duration or LAYOUT_PREVIEW_ANIM_DURATION,
    }
end

local function EaseInOut(t)
    return t < 0.5 and (2 * t * t) or (1 - (((-2 * t + 2) ^ 2) / 2))
end

local function Interpolate(a, b, t)
    return a + ((b - a) * t)
end

local function UpdateGhostPosition(ghost)
    if not (ghost and ghost:IsShown()) then
        return
    end
    local scale = UIParent:GetEffectiveScale()
    local cursorX, cursorY = GetCursorPosition()
    cursorX = cursorX / scale
    cursorY = cursorY / scale
    local offsetX = math_floor((ghost:GetWidth() or 0) / 2)
    local offsetY = math_floor((ghost:GetHeight() or 0) / 2)
    ghost:ClearAllPoints()
    ghost:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", cursorX - offsetX, cursorY + offsetY)
end

local function TickPreview(preview)
    local activeTween = false
    local now = GetTime()

    for frame, tween in pairs(preview.tweens) do
        local progress = math_min(1, math_max(0, (now - tween.t0) / tween.dur))
        local eased = EaseInOut(progress)
        ApplySlotGeometry(
            frame,
            tween.parent,
            Interpolate(tween.sx, tween.tx, eased),
            Interpolate(tween.sy, tween.ty, eased),
            Interpolate(tween.sw, tween.tw, eased),
            Interpolate(tween.sh, tween.th, eased),
            Interpolate(tween.sa, tween.ta, eased)
        )
        if progress >= 1 then
            preview.tweens[frame] = nil
        else
            activeTween = true
        end
    end

    UpdateGhostPosition(preview.ghost)

    for _, entry in ipairs(preview.animated) do
        entry.Tick(entry, now)
    end

    if not activeTween and not preview.ghostActive and #preview.animated == 0 then
        preview.root:SetScript("OnUpdate", nil)
    end
end

-- A running preview keeps the ticker alive on its own, independently of the
-- drag tweens that otherwise own it.
local function StartPreviewAnimationDriver(preview)
    if #preview.animated == 0 then
        return
    end
    preview.root:SetScript("OnUpdate", function()
        TickPreview(preview)
    end)
end

local function ConfigureSlotChrome(frame, slot, skin, isVertical)
    ApplyBackdrop(frame, { 0, 0, 0, 0 }, { 0, 0, 0, 0 })
    frame.titleIcon:Hide()
    frame.titleText:Hide()
    frame.shortText:Hide()
    frame.grip:Hide()
    if frame.hoverHighlight then
        frame.hoverHighlight:SetFrameLevel(frame:GetFrameLevel() + 20)
        frame.hoverHighlight:Hide()
    end
    if frame.selectedHighlight then
        frame.selectedHighlight:SetFrameLevel(frame:GetFrameLevel() + 19)
        frame.selectedHighlight:Hide()
    end
    if frame.identityLayer then
        frame.identityLayer:SetFrameLevel(frame:GetFrameLevel() + 18)
        frame.identityLayer:Hide()
    end

    -- Aura-block membership, worn by the bar itself. Elevated above the bar
    -- composition (a texture at the slot's own level renders UNDER the bar
    -- frames inside previewCanvas) but under the identity marks and the
    -- hover/selection glows, so those stay the topmost read.
    --
    -- Runs on EVERY configure, both legs: a pooled slot arrives wearing
    -- whatever its last owner left on it, so the non-bucket case has to clear
    -- the wash rather than skip it.
    local tint = LAYOUT_PREVIEW_BUCKET_TINTS[GetSlotBucketId(slot)]
    local wash = frame.bucketWash
    if tint then
        if not wash then
            wash = CreateFrame("Frame", nil, frame)
            wash:SetAllPoints(frame.previewCanvas)
            wash:EnableMouse(false)
            wash.tex = wash:CreateTexture(nil, "OVERLAY")
            wash.tex:SetAllPoints()
            wash.tex:SetBlendMode("ADD")
            frame.bucketWash = wash
        end
        wash:SetFrameLevel(frame:GetFrameLevel() + 17)
        wash.tex:SetColorTexture(tint.wash[1], tint.wash[2], tint.wash[3], tint.wash[4])
        -- Full-rect is the default shape; the slot render re-shapes the wash
        -- onto the capacity blocks when the bar renders as segments (pooled
        -- slots may arrive block-shaped from their last owner, so both legs
        -- reset here every configure).
        wash.color = tint.wash
        wash.tex:Show()
        if wash.blockTexes then
            for _, blockTex in ipairs(wash.blockTexes) do
                blockTex:Hide()
            end
        end
        wash:Show()
    elseif wash then
        wash:Hide()
    end

    frame.previewCanvas:ClearAllPoints()
    frame.previewCanvas:SetAllPoints(frame)
end

-- Identity marks for one custom-bar slot. Runs AFTER the content scale is
-- known so both marks can counter-scale and stay legible on a preview that
-- has been shrunk to fit. The badge is permanent (a small corner glyph
-- reads as chrome, and the setting it stands for has no other visual); the
-- name is laid out here but only shown while the preview is hovered.
-- widthOverride: for the drag ghost, whose slot takes its size from anchors
-- and would measure nothing until the next layout pass.
local function ApplySlotIdentityMarks(preview, frame, scale, widthOverride)
    local layer = frame and frame.identityLayer
    if not layer then return end
    local slot = frame.slotData
    if not (slot and slot.kind == "custom") then
        layer:Hide()
        return
    end

    scale = math_max(scale or 1, 0.01)
    local isVertical = frame._cdcIdentityVertical == true

    -- A narrow vertical bar cannot carry a name, so it gets the same short
    -- label the drag chrome uses; its plate is allowed to overhang the thin
    -- bar, which a transient overlay can afford to do.
    local text = isVertical and slot.shortLabel or slot.label
    -- Slot labels are stored as "Custom Bar: <name>"; the prefix is noise
    -- when every labelled bar in the canvas is a custom bar.
    if type(text) == "string" then
        text = string.gsub(text, "^Custom Bar:%s*", "")
    end

    local label = layer.label
    if text and text ~= "" then
        local fontFile = label:GetFont()
        -- Slug outline instead of a backing plate: it keeps the name
        -- legible over any bar color without laying an opaque rectangle
        -- across the bar the owner is trying to look at.
        label:SetFont(fontFile,
            math_max(8, math_min(14, LAYOUT_PREVIEW_IDENTITY_FONT_SCREEN_SIZE / scale)),
            LAYOUT_PREVIEW_IDENTITY_FONT_OUTLINE)
        ST.ApplyFontShadowForOutline(label, LAYOUT_PREVIEW_IDENTITY_FONT_OUTLINE)
        label:SetText(text)
        label:SetTextColor(1, 1, 1, 1)
        label:SetJustifyH("CENTER")
        label:ClearAllPoints()
        label:SetPoint("CENTER", layer, "CENTER", 0, 0)
        if isVertical then
            label:SetWidth(0)
        else
            -- Snug to the text, but never wider than the bar: a long name
            -- truncates with an ellipsis instead of overflowing. Measured
            -- off the slot frame, which was explicitly sized; the layer
            -- inherits its size by anchor and reports nothing until the
            -- next layout pass.
            local available = math_max(1,
                (widthOverride or frame:GetWidth() or 0) - (LAYOUT_PREVIEW_IDENTITY_INSET * 2))
            label:SetWidth(math_min(label:GetStringWidth() + 1, available))
        end
        layer._cdcHasLabel = true
        label:SetShown(preview.identityLabelsShown == true)
    else
        layer._cdcHasLabel = nil
        label:Hide()
    end

    local badge = layer.badge
    local config = slot.customEntry and slot.customEntry.config
    if type(config) == "table" and config.hideWhenInactive == true then
        local isAuraBlockBadge = IsAuraBlockCustomBar(config)
        local screenSize = isAuraBlockBadge
            and LAYOUT_PREVIEW_AURA_BLOCK_BADGE_SCREEN_SIZE
            or LAYOUT_PREVIEW_VISIBILITY_BADGE_SCREEN_SIZE
        local size = math_min(24, math_max(12,
            screenSize / scale))
        badge:SetAtlas(isAuraBlockBadge
            and LAYOUT_PREVIEW_AURA_BLOCK_BADGE_ATLAS
            or LAYOUT_PREVIEW_VISIBILITY_BADGE_ATLAS, false)
        badge:SetSize(size, size)
        badge:ClearAllPoints()
        if isVertical then
            badge:SetPoint("TOP", layer, "TOP", 0, 0)
        else
            badge:SetPoint("RIGHT", layer, "RIGHT", 0, 0)
        end
        badge:Show()
    else
        badge:Hide()
    end

    layer:Show()
end

-- Only a CUSTOM bar reveals the names: resources are identified by their
-- own well-known colors and never carry a label, so passing over one has
-- no reason to light the set up.
local function AnyCustomPreviewSlotHovered(preview)
    local pool = preview.pools and preview.pools.slots
    if not pool then return false end
    for index = 1, (preview.used.slots or 0) do
        local frame = pool[index]
        if frame and frame.slotData and frame.slotData.kind == "custom"
            and frame:IsShown() and frame:IsMouseOver() then
            return true
        end
    end
    return false
end

-- A reorder freezes the reveal wherever it was when the drag began. Slots
-- tween out from under the cursor while dragging, so enter/leave fire
-- continuously and the names flickered; and mid-reorder is precisely when
-- a stable read of which bar is which is worth the most.
local function IsLayoutDragActive()
    return CS.dragState ~= nil and CS.dragState.kind == LAYOUT_PREVIEW_DRAG_KIND
end

-- Reveal or hide every custom bar's name at once. Hovering ONE bar names
-- them ALL: the point is the whole map in one glance, which naming only the
-- hovered bar would not give (the tooltip already does that).
local function SetIdentityLabelsShown(preview, shown)
    shown = shown == true
    if IsLayoutDragActive() or preview.identityLabelsShown == shown then
        return
    end
    preview.identityLabelsShown = shown
    local pool = preview.pools and preview.pools.slots
    if not pool then return end
    for index = 1, (preview.used.slots or 0) do
        local layer = pool[index] and pool[index].identityLayer
        if layer and layer._cdcHasLabel then
            layer.label:SetShown(shown)
        end
    end
end

local function HideUnusedSlotVisuals(frame)
    if frame.previewBarInfo and frame.previewBarInfo.frame then
        frame.previewBarInfo.frame:Hide()
    end
    if frame.castPreview and frame.castPreview.root then
        frame.castPreview.root:Hide()
    end
end

local function EnsureResourcePreview(frame, slot, preview, width, height)
    HideUnusedSlotVisuals(frame)

    local barInfo = frame.previewBarInfo
    local rbSettings = preview.rbSettings
    local layout = preview.layout
    local segmentGap = (layout and layout.segmentGap) or rbSettings.segmentGap or 4

    if slot.kind == "custom" then
        local customBars = CooldownCompanion:GetSpecCustomAuraBars()
        barInfo = PrepareCustomAuraBar(
            frame.previewCanvas,
            barInfo,
            slot.customEntry,
            customBars,
            rbSettings,
            preview.isVerticalLayout,
            IsVerticalFillReversed(rbSettings),
            width,
            height,
            segmentGap
        )
        frame._cdcCustomBarLength = preview.isVerticalLayout and height or width
        -- The Active Aura preview state, on the canvas rather than out in the
        -- world (owner ruling 2026-07-26). Written every pass so stopping the
        -- preview clears it from a recycled frame.
        local cabConfig = slot.customEntry and slot.customEntry.config
        -- The pandemic recolor renders over the aura fill, so its preview
        -- arms the Active Aura stand-in too (union), while the pandemic
        -- flag itself stays owned by its own command-center control. Gated
        -- on the entry's own enable, like the recolor itself: a stale map
        -- entry left by unchecking Show Pandemic Color must not keep the
        -- stand-in armed after its control disappeared.
        local pandemicPreview = cabConfig
            and cabConfig.pandemicEffect == true
            and CooldownCompanion:IsCustomAuraBarPandemicPreviewActive(cabConfig)
        -- The marker rides the duration text the Active Aura stand-in writes,
        -- so it unions into that flag the same way the recolor does. Gated on
        -- the same predicate the command-center control offers itself on, or
        -- the stand-in strands armed with no toggle left to stop it.
        local markerPreview = cabConfig
            and CooldownCompanion:IsCustomAuraBarMarkerPreviewActive(cabConfig)
            and CooldownCompanion:IsPandemicMarkerPreviewWanted(cabConfig, cabConfig)
        barInfo.frame._barAuraActivePreview = (cabConfig
            and (CooldownCompanion:IsCustomAuraBarActivePreviewActive(cabConfig)
                or pandemicPreview or markerPreview))
            or nil
        barInfo.frame._barPandemicPreview = pandemicPreview or nil
        barInfo.frame._barMarkerPreview = markerPreview or nil
        -- The Cooldown preview state for spell custom bars, same canvas-only
        -- model: the kind ("cooldown"/"recharge") or nil, written every pass
        -- so stopping the preview clears it from a recycled frame. Gated on
        -- the same charge resolve the command-center control offers itself
        -- on, or a "recharge" stand-in strands armed after a talent or spec
        -- change takes the spell's extra charge — and its control — away.
        local cooldownPreviewKind = cabConfig
            and CooldownCompanion:GetCustomBarCooldownPreviewKind(cabConfig)
            or nil
        if cooldownPreviewKind == "recharge"
            and not (RB.GetCustomBarReadyChargeCount
                and RB.GetCustomBarReadyChargeCount(cabConfig)) then
            cooldownPreviewKind = nil
        end
        barInfo.frame._barCooldownPreview = cooldownPreviewKind
    elseif slot.powerType == 101 then
        if not barInfo or barInfo.barType ~= "stagger_continuous" then
            if barInfo and barInfo.frame then
                barInfo.frame:Hide()
            end
            barInfo = {
                frame = CreateContinuousBar(frame.previewCanvas),
                barType = "stagger_continuous",
                powerType = slot.powerType,
            }
        end
        barInfo.frame:SetSize(width, height)
        StyleContinuousBar(barInfo.frame, slot.powerType, rbSettings)
    elseif slot.powerType == RESOURCE_HEALTH then
        if not barInfo or barInfo.barType ~= "health_continuous" then
            if barInfo and barInfo.frame then
                barInfo.frame:Hide()
            end
            barInfo = {
                frame = CreateContinuousBar(frame.previewCanvas),
                barType = "health_continuous",
                powerType = slot.powerType,
            }
        end
        barInfo.frame:SetSize(width, height)
        StyleHealthBar(barInfo.frame, rbSettings)
    elseif slot.powerType == RESOURCE_MAELSTROM_WEAPON then
        -- Mirrors the three real MW shapes exactly (ResourceBar.lua's apply
        -- branch); the canvas must show the shape the bar will actually be.
        local mwMaxStacks = GetMWMaxStacks() or 5
        local mwStyle = RB.GetMWDisplayStyle(rbSettings)
        if mwStyle == "continuous" then
            if not barInfo or barInfo.barType ~= "mw_continuous" then
                if barInfo and barInfo.frame then
                    barInfo.frame:Hide()
                end
                barInfo = {
                    frame = CreateContinuousBar(frame.previewCanvas),
                    barType = "mw_continuous",
                    powerType = slot.powerType,
                }
            end
            barInfo.frame:SetSize(width, height)
            StyleContinuousBar(barInfo.frame, slot.powerType, rbSettings)
        elseif mwStyle == "segments" then
            if not barInfo or barInfo.barType ~= "mw_segments"
                or #barInfo.frame.segments ~= mwMaxStacks then
                if barInfo and barInfo.frame then
                    barInfo.frame:Hide()
                end
                barInfo = {
                    frame = CreateSegmentedBar(frame.previewCanvas, mwMaxStacks),
                    barType = "mw_segments",
                    powerType = slot.powerType,
                }
            end
            barInfo.frame:SetSize(width, height)
            LayoutSegments(barInfo.frame, width, height, segmentGap, rbSettings)
            local baseColor = GetResourceColors(RESOURCE_MAELSTROM_WEAPON, rbSettings)
            for i = 1, mwMaxStacks do
                barInfo.frame.segments[i]:SetStatusBarColor(baseColor[1], baseColor[2], baseColor[3], 1)
            end
            RB.StyleSegmentedText(barInfo.frame, slot.powerType, rbSettings)
        else
            local halfSegments = (mwMaxStacks <= 5) and mwMaxStacks or (mwMaxStacks / 2)
            if not barInfo or barInfo.barType ~= "mw_segmented" or #barInfo.frame.segments ~= halfSegments then
                if barInfo and barInfo.frame then
                    barInfo.frame:Hide()
                end
                barInfo = {
                    frame = CreateOverlayBar(frame.previewCanvas, halfSegments),
                    barType = "mw_segmented",
                    powerType = slot.powerType,
                }
            end
            barInfo.frame:SetSize(width, height)
            LayoutOverlaySegments(barInfo.frame, width, height, segmentGap, rbSettings, halfSegments)
            local baseColor, overlayColor = GetResourceColors(RESOURCE_MAELSTROM_WEAPON, rbSettings)
            for i = 1, halfSegments do
                barInfo.frame.segments[i]:SetStatusBarColor(baseColor[1], baseColor[2], baseColor[3], 1)
                barInfo.frame.overlaySegments[i]:SetStatusBarColor(overlayColor[1], overlayColor[2], overlayColor[3], 1)
                barInfo.frame.overlaySegments[i]:Show()
            end
            RB.StyleSegmentedText(barInfo.frame, slot.powerType, rbSettings)
        end
    elseif SEGMENTED_TYPES[slot.powerType] then
        local maxValue = UnitPowerMax("player", slot.powerType)
        if slot.powerType == 5 then
            maxValue = 6
        end
        if not maxValue or maxValue < 1 then
            maxValue = 5
        end
        if not barInfo or barInfo.barType ~= "segmented" or barInfo.frame._numSegments ~= maxValue then
            if barInfo and barInfo.frame then
                barInfo.frame:Hide()
            end
            barInfo = {
                frame = CreateSegmentedBar(frame.previewCanvas, maxValue),
                barType = "segmented",
                powerType = slot.powerType,
            }
        end
        barInfo.frame:SetSize(width, height)
        LayoutSegments(barInfo.frame, width, height, segmentGap, rbSettings)
        StyleSegmentedBar(barInfo.frame, slot.powerType, rbSettings)
    else
        if not barInfo or barInfo.barType ~= "continuous" then
            if barInfo and barInfo.frame then
                barInfo.frame:Hide()
            end
            barInfo = {
                frame = CreateContinuousBar(frame.previewCanvas),
                barType = "continuous",
                powerType = slot.powerType,
            }
        end
        barInfo.frame:SetSize(width, height)
        StyleContinuousBar(barInfo.frame, slot.powerType, rbSettings)
    end

    frame.previewBarInfo = barInfo
    if barInfo and barInfo.frame then
        barInfo.frame:SetParent(frame.previewCanvas)
        barInfo.frame:ClearAllPoints()
        barInfo.frame:SetPoint("TOPLEFT", frame.previewCanvas, "TOPLEFT", 0, 0)
        barInfo.frame:SetPoint("BOTTOMRIGHT", frame.previewCanvas, "BOTTOMRIGHT", 0, 0)
        barInfo.frame:Show()
        -- The resource overlay's Active Aura preview state, on the canvas
        -- rather than out in the world (owner ruling 2026-07-26). Keyed by
        -- power type, and written every pass so stopping the preview clears
        -- it from a recycled frame. Set before the render, which reads it.
        barInfo.frame._resourceAuraActivePreview = barInfo.powerType ~= nil
            and CooldownCompanion:IsResourceAuraActivePreviewActive(barInfo.powerType)
            or nil
        ApplyPreviewBarState(barInfo, rbSettings)
        -- The aura-absent layer for stacks-mode aura bars: the real
        -- capacity blocks and their per-block rings, the same call the live
        -- apply pass makes. Without it a stack bar previewed as one
        -- continuous fill — the headline fidelity gap.
        --
        -- includeShell because the canvas renders hide-while-inactive bars
        -- (they must stay visible to edit); barLength because the bar frame
        -- has not been through a layout pass this frame, so the block layout
        -- cannot measure it; maxStacks because a bar the config shows may
        -- have no live slot running and therefore no cached max.
        if slot.kind == "custom" and RB.ApplyCustomBarAbsentStackVisuals then
            -- One resolved max for the blocks AND for the stand-in's lit run
            -- and stack text, so the number of blocks drawn and the number
            -- the text quotes can never disagree.
            local standInMax = RB.GetCustomBarStandInStackMax
                and RB.GetCustomBarStandInStackMax(barInfo, rbSettings) or nil
            RB.ApplyCustomBarAbsentStackVisuals(barInfo, rbSettings, {
                includeShell = true,
                barLength = frame._cdcCustomBarLength,
                maxStacks = standInMax,
                -- The Active Aura stand-in on a stacks bar: the blocks are
                -- the bar, so the lit run is painted here rather than as a
                -- fill over the top of them.
                litStacks = RB.GetCustomBarStandInLitStacks
                    and RB.GetCustomBarStandInLitStacks(barInfo, rbSettings, standInMax) or nil,
            })
            -- Bucket wash containment: on a stacks bar the blocks ARE the
            -- bar and the gaps are genuinely empty, so the full-rect wash
            -- read as one solid tinted bar over them. Re-shape the wash onto
            -- the block rects; every other shape keeps the whole-canvas wash
            -- ConfigureSlotChrome laid down.
            local wash = frame.bucketWash
            if wash and wash:IsShown() and RB.GetCustomBarActiveStackBlocks then
                local blocks = RB.GetCustomBarActiveStackBlocks(barInfo)
                if blocks then
                    local texes = wash.blockTexes
                    if not texes then
                        texes = {}
                        wash.blockTexes = texes
                    end
                    local color = wash.color
                    for i, block in ipairs(blocks) do
                        local blockTex = texes[i]
                        if not blockTex then
                            blockTex = wash:CreateTexture(nil, "OVERLAY")
                            blockTex:SetBlendMode("ADD")
                            texes[i] = blockTex
                        end
                        blockTex:ClearAllPoints()
                        blockTex:SetAllPoints(block)
                        blockTex:SetColorTexture(color[1], color[2], color[3], color[4])
                        -- Blocks past the resolved max stay laid out at
                        -- alpha 0; mirror it so the wash never outlines a
                        -- block the bar is not drawing.
                        blockTex:SetAlpha(block:GetAlpha())
                        blockTex:Show()
                    end
                    for i = #blocks + 1, #texes do
                        texes[i]:Hide()
                    end
                    wash.tex:Hide()
                end
            end
        end
        if barInfo.frame._barAuraActivePreview and RB.AnimatePreviewBarAura then
            table_insert(preview.animated, {
                barInfo = barInfo,
                Tick = function(entry)
                    RB.AnimatePreviewBarAura(entry.barInfo)
                end,
            })
        elseif barInfo.barType == "health_continuous"
            and RB.IsHealthEffectPreviewAnimated
            and RB.IsHealthEffectPreviewAnimated() then
            table_insert(preview.animated, {
                barInfo = barInfo,
                -- Resolved here rather than per tick; see the exporter.
                config = RB.GetHealthPreviewAnimationConfig
                    and RB.GetHealthPreviewAnimationConfig(rbSettings) or nil,
                Tick = function(entry)
                    RB.AnimatePreviewHealthEffects(entry.barInfo, entry.config)
                end,
            })
        end
    end
end

local function EnsureCastPreview(frame)
    local castPreview = frame.castPreview
    if castPreview then
        return castPreview
    end

    local root = CreateFrame("Frame", nil, frame.previewCanvas)
    root:SetClipsChildren(false)

    local bar = CreateFrame("StatusBar", nil, root)
    bar:SetPoint("TOPLEFT", root, "TOPLEFT", 0, 0)
    bar:SetPoint("BOTTOMRIGHT", root, "BOTTOMRIGHT", 0, 0)

    local bg = bar:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bar.bg = bg

    local spark = bar:CreateTexture(nil, "OVERLAY", nil, 2)
    spark:SetTexture("Interface\\CastingBar\\UI-CastingBar-Spark")
    spark:SetBlendMode("ADD")
    bar.spark = spark

    local nameText = bar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    nameText:SetJustifyH("LEFT")
    bar.nameText = nameText

    local timeText = bar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    timeText:SetJustifyH("RIGHT")
    bar.timeText = timeText

    local iconFrame = CreateFrame("Frame", nil, root)
    local icon = iconFrame:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT", 1, -1)
    icon:SetPoint("BOTTOMRIGHT", -1, 1)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    iconFrame.icon = icon

    castPreview = {
        root = root,
        bar = bar,
        iconFrame = iconFrame,
        icon = icon,
        border = bar:CreateTexture(nil, "ARTWORK", nil, 6),
        pixelBorders = CreatePixelBorders(bar),
        iconBorders = CreatePixelBorders(iconFrame),
    }
    frame.castPreview = castPreview
    return castPreview
end

local function HideCastPixelBorders(castPreview)
    if castPreview.pixelBorders then
        HidePixelBorders(castPreview.pixelBorders)
    end
    if castPreview.iconBorders then
        HidePixelBorders(castPreview.iconBorders)
    end
end

-- Place the fill, the spark and the countdown for one moment of a cast.
-- `progress` is 0..1; the resting facsimile sits at CAST_PREVIEW_REST_FILL
-- because a cast bar has no ready state to show and the slot still has to be
-- visible and draggable.
local function SetCastPreviewProgress(castPreview, progress)
    local bar = castPreview.bar
    SetStatusBarSmoothRange(bar, 0, 100)
    -- Immediate, not smoothed: the sweep advances every tick, and smoothing
    -- toward a moving target would drag visibly backwards at the wrap.
    SetStatusBarImmediateValue(bar, progress * 100)
    if bar.spark:IsShown() then
        -- The measured length is the fallback, not the source: the slot is
        -- built and laid out in the same frame, so the anchor chain may not
        -- have resolved yet on the first pass.
        local barLength = castPreview.barLength or bar:GetWidth() or 0
        bar.spark:ClearAllPoints()
        bar.spark:SetPoint("CENTER", bar, "LEFT", barLength * progress, 0)
    end
    if bar.timeText:IsShown() then
        bar.timeText:SetFormattedText("%.1f s", CAST_PREVIEW_DURATION * (1 - progress))
    end
end

local function ConfigureCastPreview(frame, slot, preview, width, height)
    HideUnusedSlotVisuals(frame)

    local settings = preview.cbSettings
    local castPreview = EnsureCastPreview(frame)
    local root = castPreview.root
    local bar = castPreview.bar
    local iconFrame = castPreview.iconFrame
    local icon = castPreview.icon
    local border = castPreview.border

    root:SetParent(frame.previewCanvas)
    root:ClearAllPoints()
    root:SetPoint("TOPLEFT", frame.previewCanvas, "TOPLEFT", 0, 0)
    root:SetPoint("BOTTOMRIGHT", frame.previewCanvas, "BOTTOMRIGHT", 0, 0)
    root:Show()

    -- Styling is always on for the CC-owned bar: the old Blizzard-visuals
    -- fallback died with the frame replacement, so the facsimile paints the
    -- configured settings unconditionally. The resolutions below keep
    -- CastBar.lua's shape but are NOT pixel-exact: this facsimile pads an
    -- inline icon with a 4px gap where the live bar uses none, reserves
    -- in-bar footprint for an offset icon the live bar draws outside the
    -- fill, and rings only the bar where the live pixel border wraps bar
    -- and inline icon together.
    local styled = true

    local iconShown = styled and settings.showIcon ~= false
    local iconSize = height
    local iconGap = 4
    local barLeft = 0
    local barRight = 0

    if iconShown then
        if settings.iconOffset then
            iconSize = math_min(height, settings.iconSize or height)
        end
        iconFrame:SetSize(iconSize, iconSize)
        iconFrame:Show()
        icon:SetTexture(slot.icon or LAYOUT_PREVIEW_ICON_FALLBACK)
        -- Zoom is a styling-layer setting like everything else here: with
        -- Styling off the live bar wears Blizzard visuals, so the facsimile
        -- falls back to the plain trim.
        ApplyIconTexCoord(icon, 1, 1, styled and settings.iconZoom or 0)
        if settings.iconFlipSide then
            iconFrame:ClearAllPoints()
            iconFrame:SetPoint("TOPRIGHT", root, "TOPRIGHT", 0, 0)
            barRight = -(iconSize + iconGap)
        else
            iconFrame:ClearAllPoints()
            iconFrame:SetPoint("TOPLEFT", root, "TOPLEFT", 0, 0)
            barLeft = iconSize + iconGap
        end
    else
        iconFrame:Hide()
    end

    bar:ClearAllPoints()
    bar:SetPoint("TOPLEFT", root, "TOPLEFT", barLeft, 0)
    bar:SetPoint("BOTTOMRIGHT", root, "BOTTOMRIGHT", barRight, 0)
    castPreview.barLength = math_max(0, width + barRight - barLeft)
    bar:SetStatusBarTexture(CooldownCompanion:FetchEffectiveBarTexture(
        (styled and settings.barTexture) or "Solid"))
    -- The configured colour, not the live cast bar's current one: this is the
    -- cast bar as configured, and reading the world bar would mirror whatever
    -- the last real cast happened to leave behind.
    local barColor = (styled and settings.barColor) or { 1, 0.72, 0.18, 1 }
    bar:SetStatusBarColor(barColor[1], barColor[2], barColor[3], barColor[4] ~= nil and barColor[4] or 1)
    local backgroundColor = (styled and settings.backgroundColor) or { 0, 0, 0, 0.5 }
    bar.bg:SetColorTexture(backgroundColor[1], backgroundColor[2], backgroundColor[3], backgroundColor[4] ~= nil and backgroundColor[4] or 1)

    border:Hide()
    HideCastPixelBorders(castPreview)

    -- Mirrors CastBar.lua's own resolution verbatim.
    local borderStyle = styled and (settings.borderStyle or "pixel") or "blizzard"
    if borderStyle == "pixel" then
        ApplyPixelBorders(castPreview.pixelBorders, bar, settings.borderColor or { 0, 0, 0, 1 }, settings.borderSize or 1, ST.GetBorderRenderMode(settings))
        if iconFrame:IsShown() and settings.iconOffset then
            ApplyPixelBorders(castPreview.iconBorders, iconFrame, settings.borderColor or { 0, 0, 0, 1 }, settings.iconBorderSize or 1, ST.GetBorderRenderMode(settings, "iconBorderRenderMode"))
        else
            HidePixelBorders(castPreview.iconBorders)
        end
    elseif borderStyle == "blizzard" then
        border:SetAllPoints(bar)
        border:SetAtlas("ui-castingbar-frame")
        border:Show()
    end

    -- Text and spark visibility follow the live contract too: with Styling
    -- off the real bar shows all three unconditionally (ApplyPreview and the
    -- spark resolution in CastBar.lua), so the per-element toggles are
    -- dormant along with the fonts.
    if styled and settings.showNameText == false then
        bar.nameText:Hide()
    else
        local font = CooldownCompanion:FetchFont(
            (styled and settings.nameFont) or DEFAULT_RESOURCE_TEXT_FONT)
        local nameOutline = ST.GetEffectiveFontOutline(
            (styled and settings.nameFontOutline) or DEFAULT_RESOURCE_TEXT_OUTLINE)
        bar.nameText:SetFont(font,
            (styled and settings.nameFontSize) or DEFAULT_RESOURCE_TEXT_SIZE, nameOutline)
        ST.ApplyFontShadowForOutline(bar.nameText, nameOutline)
        bar.nameText:ClearAllPoints()
        bar.nameText:SetPoint("LEFT", bar, "LEFT", 4, 0)
        bar.nameText:SetPoint("RIGHT", bar, "RIGHT", -4, 0)
        bar.nameText:SetText(CAST_PREVIEW_SPELL_NAME)
        bar.nameText:Show()
    end

    if styled and settings.showCastTimeText == false then
        bar.timeText:Hide()
    else
        local font = CooldownCompanion:FetchFont(
            (styled and settings.castTimeFont) or DEFAULT_RESOURCE_TEXT_FONT)
        local timeOutline = ST.GetEffectiveFontOutline(
            (styled and settings.castTimeFontOutline) or DEFAULT_RESOURCE_TEXT_OUTLINE)
        bar.timeText:SetFont(font,
            (styled and settings.castTimeFontSize) or DEFAULT_RESOURCE_TEXT_SIZE, timeOutline)
        ST.ApplyFontShadowForOutline(bar.timeText, timeOutline)
        bar.timeText:ClearAllPoints()
        bar.timeText:SetPoint("RIGHT", bar, "RIGHT",
            -4 + (styled and settings.castTimeXOffset or 0),
            styled and settings.castTimeYOffset or 0)
        bar.timeText:Show()
    end

    if styled and settings.showSpark == false then
        bar.spark:Hide()
    else
        bar.spark:SetWidth(8)
        bar.spark:SetHeight(math_max(8, height * 1.66))
        bar.spark:Show()
    end

    -- The cast bar's preview state: a cast in progress, looping. Nothing on
    -- the resting bar can stand in for one, which is what makes it worth a
    -- control in the first place.
    if CooldownCompanion:IsCastBarPreviewActive() then
        castPreview.startedAt = GetTime()
        table_insert(preview.animated, {
            castPreview = castPreview,
            Tick = function(entry, now)
                local elapsed = (now - entry.castPreview.startedAt) % CAST_PREVIEW_DURATION
                SetCastPreviewProgress(entry.castPreview, elapsed / CAST_PREVIEW_DURATION)
            end,
        })
        SetCastPreviewProgress(castPreview, 0)
    else
        castPreview.startedAt = nil
        SetCastPreviewProgress(castPreview, CAST_PREVIEW_REST_FILL)
    end
end

local function ConfigureSlotPreview(frame, slot, preview, width, height, isVerticalSlot)
    ConfigureSlotChrome(frame, slot, preview.skin, isVerticalSlot)
    if slot.kind == "cast" then
        ConfigureCastPreview(frame, slot, preview, width, height)
    else
        EnsureResourcePreview(frame, slot, preview, width, height)
    end
end

-- The drag ghost runs through the same slot renderer, which would enrol its
-- throwaway frames in the animation list. That list is only emptied by a
-- full rebuild, and cancelling a drag does not rebuild — so each cancelled
-- drag left an entry ticking a hidden ghost, and they accumulated.
local function ConfigureGhostSlotPreview(frame, slot, preview, width, height, isVerticalSlot)
    local enrolled = #preview.animated
    ConfigureSlotPreview(frame, slot, preview, width, height, isVerticalSlot)
    for index = #preview.animated, enrolled + 1, -1 do
        preview.animated[index] = nil
    end
end

-- This canvas arranges BARS; the icon row inside it is scenery. Every frame
-- that stands in for that row - the real button-panel mirror an owner lends
-- us, or the placeholder rect below when there is nothing to lend - wears the
-- same refusal, so the answer to "can I drag an icon here" never depends on
-- which one happens to be on screen.
local function ApplyIconPanelClickShield(frame)
    frame:EnableMouse(true)
    frame:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Icons stay in place.", 1, 1, 1)
        GameTooltip:AddLine("Drag the attached bars around the icon row instead.", 0.75, 0.82, 0.92, true)
        GameTooltip:Show()
    end)
    frame:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    frame:SetScript("OnMouseDown", function()
        if UIErrorsFrame and UIErrorsFrame.AddMessage then
            UIErrorsFrame:AddMessage("Icons are fixed. Drag the bars around them.", 1, 0.25, 0.25, 1)
        end
    end)
end

-- The defensive leg, NOT a supported render mode. The lanes have to wrap
-- something, and every owner that reaches this renderer has already agreed
-- there is a panel worth wrapping, so an owner that answers "no frame" has
-- disagreed with the canvas about an emptied panel between one build and the
-- next. There is nothing honest to draw for that, so this draws nothing:
-- a neutral rect at the buttons view's message-state minimum, wearing the
-- same click refusal a real mirror wears, that the lanes size themselves to.
-- Degenerate by design - the next build that is not a reuse recovers.
local LAYOUT_PREVIEW_PLACEHOLDER_WIDTH = 220
local LAYOUT_PREVIEW_PLACEHOLDER_HEIGHT = 90

local function RenderPanelPlaceholder(preview, parent)
    local frame = AcquireContainer(preview, parent)
    ApplyBackdrop(frame, preview.skin.slotBg, preview.skin.slotBorder, 1)
    frame:SetSize(LAYOUT_PREVIEW_PLACEHOLDER_WIDTH, LAYOUT_PREVIEW_PLACEHOLDER_HEIGHT)
    ApplyIconPanelClickShield(frame)
    return frame
end

-- Lent panel frames belong to whoever handed them over, not to this canvas's
-- pools, so FinalizePreviewState cannot put them away. Every build therefore
-- starts by hiding what the last build borrowed: the message-only states
-- render no panel at all, and a lent frame left showing would float over the
-- message.
local function ReleaseLentPanelFrames(preview)
    local lent = preview.lentPanelFrames
    if not lent then
        preview.lentPanelFrames = {}
        return
    end
    for index = #lent, 1, -1 do
        lent[index]:Hide()
        lent[index] = nil
    end
end

-- Panel-frame injection, and the only way this canvas gets an icon panel to
-- wrap. An owner lends the REAL read-only button-panel mirror, so the
-- previewed panel width - and every attached bar that inherits it - matches
-- the panel the bars actually anchor to. Instance 1 is the panel the primary
-- lanes wrap; instance 2 is the second copy the vertical layout's cast
-- section draws its own lane around, because one frame cannot sit in two
-- places.
--
-- Two ways in, and they compose: `opts.externalPanel` lends instance 1 as an
-- already-built frame, while `opts.panelFrameProvider(index, panelData)` is
-- asked for whichever instance is still unclaimed. The provider is called
-- from the render path that wraps a panel and nowhere else, which is the
-- point of it: a message-only build asks for nothing, so an owner never pays
-- to mirror a panel this canvas was not going to wrap. Returning nil is the
-- defensive leg only (see RenderPanelPlaceholder).
local function AcquirePanelFrame(preview, parent, panelData, index)
    local external
    if index == 1 then
        external = preview.externalPanelFrame
    end
    if not external and preview.panelFrameProvider then
        external = preview.panelFrameProvider(index, panelData)
    end
    if external then
        external:SetParent(parent)
        external:Show()
        local lent = preview.lentPanelFrames
        lent[#lent + 1] = external
        return external
    end
    return RenderPanelPlaceholder(preview, parent)
end

-- Bars are not all the same thickness: the layout supports a per-slot
-- override and the cast bar carries its own height. The lane therefore
-- positions from an ordered list of extents rather than from one repeated
-- slot size, and `sizes` lets a caller pass a hypothetical order (drag
-- hit-testing works against the list with the dragged slot removed).
-- The configured thickness verbatim. The thickness sliders run 4-40 in 0.1
-- steps and the live layout uses the saved value directly, so flooring it
-- and clamping it up to 8 made every bar under 8px preview at the wrong
-- size and threw away every fractional value — inside the pass whose whole
-- point is that the preview matches. A thin bar is a thin drag target; that
-- is handled by expanding the hit rect, not by drawing the bar wrong.
local function GetSlotExtent(slot, fallback)
    local thickness = tonumber(slot and slot.thickness)
    if thickness and thickness > 0 then
        return thickness
    end
    return fallback
end

-- Smallest comfortable grab area for a reorder drag. Thin bars keep their
-- true size and borrow the empty space around them instead, capped at half
-- the inter-bar gap so neighbouring slots never claim the same pixels.
local LAYOUT_PREVIEW_MIN_HIT_EXTENT = 10

local function ApplySlotHitExpansion(frame, extent, gap, isVerticalSlot)
    local missing = LAYOUT_PREVIEW_MIN_HIT_EXTENT - (tonumber(extent) or 0)
    local pad = 0
    if missing > 0 then
        pad = math_min(missing / 2, math_max(0, (tonumber(gap) or 0) / 2))
    end
    -- Negative insets EXPAND the mouse rect beyond the frame.
    if isVerticalSlot then
        frame:SetHitRectInsets(-pad, -pad, 0, 0)
    else
        frame:SetHitRectInsets(0, 0, -pad, -pad)
    end
end

local function BuildSlotExtents(slots, fallback)
    local sizes = {}
    for index, slot in ipairs(slots) do
        sizes[index] = GetSlotExtent(slot, fallback)
    end
    return sizes
end

local function GetExtentTotal(sizes, gap, fallbackSize)
    local count = sizes and #sizes or 0
    if count <= 0 then
        return math_max(LAYOUT_PREVIEW_EMPTY_DROP_SIZE, fallbackSize or LAYOUT_PREVIEW_EMPTY_DROP_SIZE)
    end
    local total = 0
    for _, size in ipairs(sizes) do
        total = total + size
    end
    return total + ((count - 1) * gap)
end

local function BuildLaneSlotGeometry(lane, index, sizes)
    sizes = sizes or lane.renderSizes or {}
    local gap = lane.slotGap or LAYOUT_PREVIEW_GAP
    local laneWidth = lane.frame:GetWidth() or lane.slotWidth or 1
    local laneHeight = lane.frame:GetHeight() or lane.slotHeight or 1
    local defaultExtent = lane.defaultExtent
        or (lane.axis == "x" and lane.slotWidth or lane.slotHeight)
        or LAYOUT_PREVIEW_EMPTY_DROP_SIZE

    local offset = 0
    for i = 1, index - 1 do
        offset = offset + (sizes[i] or defaultExtent) + gap
    end
    local extent = sizes[index] or defaultExtent

    if lane.axis == "x" then
        local y = -math_floor(math_max(0, laneHeight - lane.slotHeight) / 2)
        return offset, y, extent, lane.slotHeight
    end
    local x = math_floor(math_max(0, laneWidth - lane.slotWidth) / 2)
    return x, -offset, lane.slotWidth, extent
end

-- The contiguous run of slots each aura-block bucket owns, in render order.
-- The sort already guarantees the buckets do not interleave, so a run is
-- simply the stretch of one bucket IDENTITY; everything else breaks the run.
-- Only the seam handle needs this: membership itself is drawn per bar.
function SwapSeam.BuildRuns(slotModels)
    local runs = {}
    local current
    for index, slot in ipairs(slotModels or {}) do
        local bucket = GetSlotBucketId(slot)
        if bucket then
            if current and current.bucket == bucket then
                current.last = index
            else
                current = { bucket = bucket, first = index, last = index }
                table_insert(runs, current)
            end
        else
            current = nil
        end
    end
    return runs
end

-- Sized against the fit-to-host scale, like the identity marks. Both textures
-- are anchored by CENTER at creation, so resizing alone keeps them on the
-- seam.
function SwapSeam.ApplyScale(frame, scale)
    if not (frame and frame.glyph) then return end
    scale = math_max(scale or 1, 0.01)
    local size = math_min(26, math_max(13, SwapSeam.SCREEN_SIZE / scale))
    frame:SetSize(size, size)
    frame.glyph:SetSize(size, size)
    frame.hover:SetSize(size * SwapSeam.HOVER_SCALE, size * SwapSeam.HOVER_SCALE)
end

function SwapSeam.OnEnter(self)
    local color = SwapSeam.HOVER
    self.glyph:SetVertexColor(color[1], color[2], color[3], color[4])
    self.hover:Show()
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText("Swap Group Order", 1, 1, 1)
    GameTooltip:AddLine("Blue bars track your auras. Gold bars track the target's.", 0.7, 0.7, 0.7, true)
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Bars cannot move between the groups. Swapping moves the other group next to the panel.", 0.7, 0.7, 0.7, true)
    GameTooltip:Show()
end

function SwapSeam.ApplyRestingLook(self)
    local color = SwapSeam.REST
    self.glyph:SetVertexColor(color[1], color[2], color[3], color[4])
    self.hover:Hide()
end

function SwapSeam.OnLeave(self)
    SwapSeam.ApplyRestingLook(self)
    GameTooltip:Hide()
end

-- The handle on the seam between a lane's two aura-block buckets, and the
-- only place the bucket order can be changed: containment forbids dragging a
-- bar out of its own bucket, so the ORDER OF THE BUCKETS needs its own
-- control. Drawn only when the lane holds both buckets, which is the only
-- time there is an order to swap.
--
-- It rides the seam ALONG the stack and hangs just off the bars' outer edge
-- ACROSS it: clear of the bar centre, where the identity name sits, and of
-- the far edge, where the aura-block badge does.
function SwapSeam.Build(preview, lane)
    lane.swapButton = nil
    local runs = SwapSeam.BuildRuns(lane.slotModels)
    if #runs ~= 2 then
        return
    end

    -- Which side's flag this seam owns: the side the bucket bars are SAVED
    -- on. The merged independent lane renders BOTH saved sides at once, and
    -- buckets living on different saved sides are separate one-bucket
    -- containers live — a swap would flip one side's flag and change nothing
    -- in play, so the handle only appears when every bucket bar shares one
    -- saved side, and it reads/writes THAT side's flag.
    local flagSide, split = GetLaneBlockFlagSide(lane.slotModels)
    if split then
        return
    end
    flagSide = flagSide or lane.side

    -- No drag is open on the build path, so display index is model index.
    local xa, ya, wa, ha = BuildLaneSlotGeometry(lane, runs[1].last)
    local xb, yb, wb, hb = BuildLaneSlotGeometry(lane, runs[2].first)
    local hang = SwapSeam.HANG

    -- Anchored by its bars-facing EDGE, not its centre: the handle sits
    -- wholly outside the bars, and the fit-to-host re-scale grows it away
    -- from them instead of into them.
    local point, px, py
    if lane.axis == "x" then
        point = "TOP"
        px = ((xa + wa) + xb) / 2
        py = (yb - hb) - hang
    else
        point = "RIGHT"
        px = xb - hang
        py = ((ya - ha) + yb) / 2
    end

    local frame = SwapSeam.Acquire(preview, lane.frame)
    frame:SetFrameLevel(lane.frame:GetFrameLevel() + 3)
    -- Provisional size; the fit-to-host pass re-runs ApplyScale once the
    -- composition's scale is known.
    SwapSeam.ApplyScale(frame, 1)
    -- The resting look, NOT OnLeave: a rebuild can land while the cursor is
    -- on a bar, and hiding the tooltip here would take that bar's away.
    SwapSeam.ApplyRestingLook(frame)
    frame:ClearAllPoints()
    frame:SetPoint(point, lane.frame, "TOPLEFT", px, py)

    local side = flagSide
    frame:SetScript("OnEnter", SwapSeam.OnEnter)
    frame:SetScript("OnLeave", SwapSeam.OnLeave)
    frame:SetScript("OnClick", function()
        local settings = preview.rbSettings
        RB.SetAuraBlockTargetFirst(settings, side, not RB.IsAuraBlockTargetFirst(settings, side))
        GameTooltip:Hide()
        -- The drop-commit refresh, verbatim: the flag reorders the live
        -- buckets, and the rebuild is what re-ranks this canvas.
        CooldownCompanion:ApplyResourceBars()
        -- In combat the block rebind defers, but its internal reason never
        -- prints the "applies when combat ends" notice. This edit is
        -- config-originated, so say so; out of combat the apply above
        -- already rebound and this would only run a redundant pass.
        if InCombatLockdown() then
            CooldownCompanion:RequestAuraRebind("config")
        end
        CooldownCompanion:RepositionCastBar()
        CooldownCompanion:UpdateAnchorStacking()
        CooldownCompanion:RefreshConfigPanel()
    end)

    lane.swapButton = frame
end

-- The insert index a drop is ALLOWED to take, clamped out of the raw one.
-- `filtered` is the destination lane's slots with the dragged one lifted out.
--
-- One rule covers every case: the drop may not break the lane's rank order.
-- A block bar therefore cannot leave its own bucket's run, and a fixed bar or
-- the cast bar cannot land inside one. Cross-lane drops read the DESTINATION
-- lane's bucket order, so a bar dropped on the other side lands inside that
-- side's same-unit bucket, or - when that side has no such bucket yet - at
-- the position that bucket would occupy there.
--
-- Ranks always bind: a lane of only fixed bars has one rank and stays a
-- free reorder, while the cast bar is confined to the far end everywhere —
-- the stack reserves no space for an interleaved cast bar, so the far end
-- is the only slot live geometry can honour.
local function ClampLaneInsertIndex(lane, slotData, filtered, insertIndex)
    local count = #filtered
    if not slotData then
        return math_max(1, math_min(count + 1, insertIndex or 1))
    end

    local targetFirst = lane.targetFirst == true
    -- Sections run the lane's own direction: on a reversed lane index 1 is
    -- the slot furthest from the panel, so ranks descend there.
    local reversed = lane.reversed == true
    local rank = GetSlotStackRank(slotData, targetFirst)

    local lower = 1
    for index = 1, count do
        local other = GetSlotStackRank(filtered[index], targetFirst)
        local precedes
        if reversed then precedes = other > rank else precedes = other < rank end
        if not precedes then
            break
        end
        lower = index + 1
    end

    local upper = count + 1
    for index = count, 1, -1 do
        local other = GetSlotStackRank(filtered[index], targetFirst)
        local follows
        if reversed then follows = other < rank else follows = other > rank end
        if not follows then
            break
        end
        upper = index
    end

    -- A lane the sort never ranked can hold slots out of rank order, which
    -- collapses the window; the lower bound wins and the post-drop sort
    -- settles the rest.
    if upper < lower then
        upper = lower
    end
    return math_max(lower, math_min(upper, insertIndex or lower))
end

local function GetScaledFrameRect(frame)
    if not (frame and frame.GetScaledRect) then
        return nil
    end

    local left, bottom, width, height = frame:GetScaledRect()
    if not (left and bottom and width and height) then
        return nil
    end

    return left, left + width, bottom + height, bottom, width, height
end

local function GetLaneScale(lane)
    local left, right, top, bottom, scaledWidth, scaledHeight = GetScaledFrameRect(lane.frame)
    if not (left and right and top and bottom and scaledWidth and scaledHeight) then
        return nil
    end

    local laneWidth = lane.frame:GetWidth() or lane.slotWidth or 1
    local laneHeight = lane.frame:GetHeight() or lane.slotHeight or 1
    local scaleX = (laneWidth > 0) and (scaledWidth / laneWidth) or 1
    local scaleY = (laneHeight > 0) and (scaledHeight / laneHeight) or 1

    return {
        left = left,
        right = right,
        top = top,
        bottom = bottom,
        width = scaledWidth,
        height = scaledHeight,
        scaleX = scaleX,
        scaleY = scaleY,
    }
end

-- Returns the lane's scale, the hit rects, and the slot models those rects
-- belong to. The models come back because the drag containment has to clamp
-- against the same list the rects were measured from.
local function BuildStableLaneSlots(lane, draggedSlotId)
    local laneScale = GetLaneScale(lane)
    if not laneScale then
        return nil, nil, nil
    end

    local filtered = {}
    for _, slot in ipairs(lane.slotModels or {}) do
        if slot.id ~= draggedSlotId then
            table_insert(filtered, slot)
        end
    end
    -- Hit-test against the order WITHOUT the dragged slot, so the rects
    -- match what the lane would look like if it were dropped elsewhere.
    local filteredSizes = BuildSlotExtents(filtered, lane.defaultExtent)

    local slotRects = {}
    for index = 1, #filtered do
        local x, y, w, h = BuildLaneSlotGeometry(lane, index, filteredSizes)
        local left = laneScale.left + (x * laneScale.scaleX)
        local top = laneScale.top + (y * laneScale.scaleY)
        local right = left + (w * laneScale.scaleX)
        local bottom = top - (h * laneScale.scaleY)
        slotRects[index] = {
            left = left,
            right = right,
            top = top,
            bottom = bottom,
        }
    end

    return laneScale, slotRects, filtered
end

local function SelectPreviewSlot(slot, modifierMulti)
    if type(slot) ~= "table" then
        return false
    end

    -- Unified anchor preview (buttons view): route to the unified bar
    -- selection, which owns the entry-vs-bar exclusivity and cast support.
    if not IsBarsWorkspaceActive() then
        if ST._SelectUnifiedAnchorBar then
            return ST._SelectUnifiedAnchorBar(slot)
        end
        return false
    end

    -- Every slot on the workspace canvas is click-to-edit, whatever is
    -- selected right now. The State.lua setters own the exclusivity between
    -- the three selection families, so there is nothing to clear here.
    if slot.kind == "cast" then
        if ST._SelectConfigCastFramesItem then
            ST._SelectConfigCastFramesItem("castbar")
        else
            CS.castFramesSelectedItem = "castbar"
        end
        return true
    end

    if slot.kind == "resource" and slot.powerType ~= nil and ST._SelectConfigResource then
        ST._SelectConfigResource(slot.powerType, { toggle = true })
        return true
    end

    if slot.kind == "custom" and slot.customBarId ~= nil and ST._SelectConfigCustomBar then
        if modifierMulti and ST._ToggleConfigCustomBarMultiSelect then
            if not CS.selectedCustomBarId then
                ST._SelectConfigCustomBar(slot.customBarId)
            end
            ST._ToggleConfigCustomBarMultiSelect(slot.customBarId)
        else
            ST._SelectConfigCustomBar(slot.customBarId, {
                toggle = true,
            })
        end
        return true
    end

    return false
end

local function BuildLane(preview, parent, layoutDrag, title, width, height, axis, side, reversed, slotModels, slotWidth, slotHeight, acceptedCategory)
    local laneFrame = AcquireContainer(preview, parent)
    laneFrame:SetSize(width, height)
    ApplyBackdrop(laneFrame, { 0, 0, 0, 0 }, { 0, 0, 0, 0 })

    local lane = {
        frame = laneFrame,
        axis = axis,
        side = side,
        reversed = reversed,
        -- Resolved once, here: the sort that produced `slotModels` used this
        -- same answer, and the drag containment has to agree with it. Flag
        -- side, not lane side: on the merged independent lane the two can
        -- disagree (a split-side lane falls back to the lane side, where the
        -- flag is moot — the seam never builds there).
        targetFirst = GetPreviewTargetFirst(preview,
            GetLaneBlockFlagSide(slotModels) or side),
        slotModels = slotModels,
        baseWidth = width,
        baseHeight = height,
        slotWidth = slotWidth,
        slotHeight = slotHeight,
        -- Along-axis fallback for a slot with no resolved thickness; the
        -- cross-axis size stays uniform (attached bars stretch to the
        -- anchor, exactly as the live stack does).
        defaultExtent = axis == "x" and slotWidth or slotHeight,
        slotGap = preview.slotGap or LAYOUT_PREVIEW_GAP,
        baseExtent = axis == "x" and width or height,
        acceptedCategory = acceptedCategory,
        visualSlots = {},
        slotFramesById = {},
    }
    lane.naturalSizes = BuildSlotExtents(slotModels, lane.defaultExtent)
    lane.renderSizes = lane.naturalSizes

    for index, slotModel in ipairs(slotModels) do
        local slotFrame = AcquireSlot(preview, laneFrame)
        -- Explicit, and before the chrome pass reads it: the drop gap rides
        -- at the lane's level + 1 and the bucket wash is offset from this
        -- one, so a pooled slot must not come back carrying a level from
        -- another lane.
        slotFrame:SetFrameLevel(laneFrame:GetFrameLevel() + 2)
        local slotExtent = lane.naturalSizes[index]
        ConfigureSlotPreview(
            slotFrame, slotModel, preview,
            axis == "x" and slotExtent or slotWidth,
            axis == "x" and slotHeight or slotExtent,
            axis == "x")
        slotFrame.slotData = slotModel
        ApplySlotHitExpansion(slotFrame, slotExtent, lane.slotGap, axis == "x")
        -- Read by the identity-mark pass, which runs after the content
        -- scale is known and no longer has the lane in hand.
        slotFrame._cdcIdentityVertical = axis == "x"
        preview.renderedSelectionKeys[slotModel.id] = true

        -- Mark the bar currently being configured: held hover-style glow
        -- plus inward-pointing arrows. In the workspace exactly one object
        -- is selected across all three families, so one slot lights up
        -- whichever kind it is; in the buttons view (unified anchor preview)
        -- the highlight follows the unified bar selection, so a stale
        -- workspace selection can't light a bar up.
        local isSelected
        if IsBarsWorkspaceActive() then
            isSelected = (slotModel.kind == "cast" and CS.castFramesSelectedItem == "castbar")
                or (slotModel.kind == "resource" and slotModel.powerType ~= nil
                    and tostring(CS.selectedResourcePowerType) == tostring(slotModel.powerType))
                or (slotModel.kind == "custom" and slotModel.customBarId ~= nil
                    and (tostring(CS.selectedCustomBarId) == tostring(slotModel.customBarId)
                        or (CS.selectedCustomBars and CS.selectedCustomBars[slotModel.customBarId] == true)))
        else
            local kind = CS.unifiedBarKind
            isSelected = (kind == "resource" and slotModel.kind == "resource"
                    and slotModel.powerType ~= nil
                    and tostring(CS.selectedResourcePowerType) == tostring(slotModel.powerType))
                or (kind == "custom" and slotModel.kind == "custom"
                    and slotModel.customBarId ~= nil
                    and tostring(CS.selectedCustomBarId) == tostring(slotModel.customBarId))
                or (kind == "cast" and slotModel.kind == "cast")
        end
        if isSelected and slotFrame.selectedHighlight then
            local marker = slotFrame.selectedHighlight
            local arrowSize = math_max(14, math_min(28, slotExtent + 6))
            marker.side1:SetSize(arrowSize, arrowSize)
            marker.side2:SetSize(arrowSize, arrowSize)
            marker.side1:ClearAllPoints()
            marker.side2:ClearAllPoints()
            if axis == "x" then
                -- Tall vertical bar: arrows above and below, pointing inward
                marker.side1:SetAtlas("npe_arrowdown", false)
                marker.side1:SetPoint("BOTTOM", marker, "TOP", 0, 2)
                marker.side2:SetAtlas("npe_arrowup", false)
                marker.side2:SetPoint("TOP", marker, "BOTTOM", 0, -2)
            else
                -- Wide horizontal bar: arrows at the sides, pointing inward
                marker.side1:SetAtlas("npe_arrowright", false)
                marker.side1:SetPoint("RIGHT", marker, "LEFT", -2, 0)
                marker.side2:SetAtlas("npe_arrowleft", false)
                marker.side2:SetPoint("LEFT", marker, "RIGHT", 2, 0)
            end
            marker:Show()
        end
        slotFrame:SetScript("OnMouseDown", function(self, button)
            if button ~= "LeftButton" or GetCursorInfo() then return end
            layoutDrag.slotCategory = slotModel.slotCategory
            local cursorX, cursorY = GetCursorPosition()
            CS.dragState = {
                kind = LAYOUT_PREVIEW_DRAG_KIND,
                phase = "pending",
                widget = self,
                scrollWidget = UIParent,
                startX = cursorX,
                startY = cursorY,
                layoutDrag = layoutDrag,
                slotData = slotModel,
            }
            StartDragTracking()
        end)
        slotFrame:SetScript("OnMouseUp", function(self, button)
            if button == "RightButton" then
                if IsBarsWorkspaceActive() and slotModel.kind == "custom"
                    and slotModel.customBarId ~= nil then
                    ST._SelectConfigCustomBar(slotModel.customBarId)
                    CooldownCompanion:RefreshConfigPanel()
                    if ST._OpenConfigCustomBarMenu then
                        ST._OpenConfigCustomBarMenu(slotModel.customBarId)
                    end
                end
                return
            end

            local state = CS.dragState
            if button ~= "LeftButton"
                or not state
                or state.kind ~= LAYOUT_PREVIEW_DRAG_KIND
                or state.phase ~= "pending"
                or state.widget ~= self then
                return
            end

            if CancelDrag then
                CancelDrag()
            else
                CS.dragState = nil
            end

            if SelectPreviewSlot(slotModel, IsControlKeyDown and IsControlKeyDown()) then
                CooldownCompanion:RefreshConfigPanel()
            end
        end)
        slotFrame:SetScript("OnEnter", function(self)
            if self.hoverHighlight then
                self.hoverHighlight:Show()
            end
            -- Names every custom bar, not just this one — and only a
            -- custom bar triggers it.
            if slotModel.kind == "custom" then
                SetIdentityLabelsShown(preview, true)
            end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(slotModel.label or "Bar", 1, 1, 1)
            local dragHelp = preview.independentResources
                and "Click to edit. Drag to reorder this independent bar."
                or "Click to edit. Drag to reorder this attached bar."
            GameTooltip:AddLine(dragHelp, 0.75, 0.82, 0.92, true)
            if IsBarsWorkspaceActive() and slotModel.kind == "custom" then
                GameTooltip:AddLine("Ctrl+Click to multi-select. Right-click for actions.", 0.75, 0.82, 0.92, true)
            end
            local customConfig = slotModel.customEntry and slotModel.customEntry.config
            if IsAuraBlockCustomBar(customConfig) then
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine(
                    ("|A:%s:14:14|a Leaves the stack while its aura is down")
                        :format(LAYOUT_PREVIEW_AURA_BLOCK_BADGE_ATLAS),
                    1, 0.82, 0.2)
                GameTooltip:AddLine(
                    "In play the bars past it close up. This preview keeps every bar in its slot.",
                    0.7, 0.7, 0.7, true)
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine(
                    "Blue bars track your auras, gold bars the target's. Each group collapses on its own.",
                    0.7, 0.7, 0.7, true)
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine(
                    "A group whose bars are all hidden still holds one bar gap of space. Splitting the groups onto different sides avoids this.",
                    0.7, 0.7, 0.7, true)
            elseif type(customConfig) == "table"
                and customConfig.hideWhenInactive == true
                and customConfig.auraTracking == true then
                -- Spell bars never join the block, so their slot really does
                -- stay reserved while the bar is hidden. Aura tracking is
                -- what makes them hide at all.
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine(
                    ("|A:%s:14:14|a Hidden, but its slot stays reserved")
                        :format(LAYOUT_PREVIEW_VISIBILITY_BADGE_ATLAS),
                    1, 0.82, 0.2)
            end
            GameTooltip:Show()
        end)
        slotFrame:SetScript("OnLeave", function(self)
            if self.hoverHighlight then
                self.hoverHighlight:Hide()
            end
            -- Next frame, so sliding from one bar straight onto its
            -- neighbour does not flicker the whole set off and back on:
            -- by then the neighbour's OnEnter has fired and this reports
            -- the cursor still inside the stack.
            C_Timer.After(0, function()
                SetIdentityLabelsShown(preview, AnyCustomPreviewSlotHovered(preview))
            end)
            GameTooltip:Hide()
        end)
        local x, y, w, h = BuildLaneSlotGeometry(lane, index)
        ApplySlotGeometry(slotFrame, laneFrame, x, y, w, h, 1)
        lane.visualSlots[index] = slotFrame
        lane.slotFramesById[slotModel.id] = slotFrame
    end

    SwapSeam.Build(preview, lane)

    lane.gapFrame = AcquireGap(preview, laneFrame)
    lane.gapFrame:SetFrameLevel(laneFrame:GetFrameLevel() + 1)
    lane.gapFrame:Hide()
    ApplyBackdrop(lane.gapFrame, preview.skin.gapBg, preview.skin.gapBorder)
    lane.gapFrame:SetAlpha(0.95)
    lane.gapFrame.text:SetText("")
    if not lane.gapFrame.inner then
        lane.gapFrame.inner = lane.gapFrame:CreateTexture(nil, "BACKGROUND")
        lane.gapFrame.inner:SetPoint("TOPLEFT", lane.gapFrame, "TOPLEFT", 2, -2)
        lane.gapFrame.inner:SetPoint("BOTTOMRIGHT", lane.gapFrame, "BOTTOMRIGHT", -2, 2)
    end
    lane.gapFrame.inner:SetColorTexture(preview.skin.slotHover[1], preview.skin.slotHover[2], preview.skin.slotHover[3], 0.22)

    table_insert(layoutDrag.lanes, lane)
    return lane
end

-- The lane's along-axis size for a set of slots, honoring each slot's own
-- thickness and the configured inter-bar spacing.
local function GetLaneExtent(preview, slots, slotSize)
    return GetExtentTotal(
        BuildSlotExtents(slots, slotSize),
        preview.slotGap or LAYOUT_PREVIEW_GAP,
        slotSize)
end

local function RenderHorizontalLayout(preview, content, layoutDrag, sourcePanel, slots, slotHeight)
    local panelFrame = AcquirePanelFrame(preview, content, sourcePanel, 1)
    local panelWidth = panelFrame:GetWidth()
    local panelHeight = panelFrame:GetHeight()
    local aboveSlots = SortSlotsForSide(slots, "above", true, GetPreviewTargetFirst(preview, "above"))
    local belowSlots = SortSlotsForSide(slots, "below", false, GetPreviewTargetFirst(preview, "below"))
    local slotFrameHeight = math_max(8, slotHeight)
    local aboveHeight = GetLaneExtent(preview, aboveSlots, slotFrameHeight)
    local belowHeight = GetLaneExtent(preview, belowSlots, slotFrameHeight)
    -- Live attached bars stretch to the anchor frame's width, so slots
    -- follow the acquired panel frame's measured width rather than any
    -- size this canvas precomputed for itself.
    local slotWidth = panelWidth

    local aboveLane = BuildLane(preview, content, layoutDrag, nil, panelWidth, aboveHeight, "y", "above", true, aboveSlots, slotWidth, slotFrameHeight, nil)
    aboveLane.frame:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)

    aboveLane.setPreviewOverflow = function(extra)
        aboveLane.frame:ClearAllPoints()
        aboveLane.frame:SetPoint("TOPLEFT", content, "TOPLEFT", 0, extra)
        aboveLane.frame:SetSize(aboveLane.baseWidth or panelWidth, (aboveLane.baseHeight or aboveHeight) + extra)
    end
    aboveLane.setPreviewOverflow(0)

    panelFrame:ClearAllPoints()
    panelFrame:SetPoint("TOPLEFT", aboveLane.frame, "BOTTOMLEFT", 0, -LAYOUT_PREVIEW_GAP)

    local belowLane = BuildLane(preview, content, layoutDrag, nil, panelWidth, belowHeight, "y", "below", false, belowSlots, slotWidth, slotFrameHeight, nil)
    belowLane.frame:SetPoint("TOPLEFT", panelFrame, "BOTTOMLEFT", 0, -LAYOUT_PREVIEW_GAP)

    local iconCenterOffsetY = aboveHeight + LAYOUT_PREVIEW_GAP + (panelHeight / 2)
    return panelWidth, aboveHeight + panelHeight + belowHeight + (LAYOUT_PREVIEW_GAP * 2), iconCenterOffsetY
end

local function RenderIndependentHorizontalLayout(preview, content, layoutDrag, slots, slotWidth, slotHeight)
    local stackSlots, stackSide, reversed = SortSlotsForIndependentStack(slots, "above", "below", preview)
    local slotFrameHeight = math_max(8, slotHeight)
    local stackHeight = GetLaneExtent(preview, stackSlots, slotFrameHeight)

    local lane = BuildLane(
        preview,
        content,
        layoutDrag,
        nil,
        slotWidth,
        stackHeight,
        "y",
        stackSide,
        reversed,
        stackSlots,
        slotWidth,
        slotFrameHeight,
        "primary"
    )
    lane.frame:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)

    return slotWidth, stackHeight
end

local function RenderIndependentVerticalLayout(preview, content, layoutDrag, slots, slotHeight, slotWidth)
    local stackSlots, stackSide, reversed = SortSlotsForIndependentStack(slots, "left", "right", preview)
    local stackWidth = GetLaneExtent(preview, stackSlots, slotWidth)

    local lane = BuildLane(
        preview,
        content,
        layoutDrag,
        nil,
        stackWidth,
        slotHeight,
        "x",
        stackSide,
        reversed,
        stackSlots,
        slotWidth,
        slotHeight,
        "primary"
    )
    lane.frame:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)

    return stackWidth, slotHeight
end

local function RenderVerticalLayout(preview, content, layoutDrag, sourcePanel, primarySlots, castSlots, horizontalBarHeight, verticalBarWidth)
    if #primarySlots == 0 and #castSlots > 0 then
        -- The cast section is the ONLY section here, so it takes the primary
        -- instance rather than the second copy.
        local castPanel = AcquirePanelFrame(preview, content, sourcePanel, 1)
        local panelWidth = castPanel:GetWidth()
        local panelHeight = castPanel:GetHeight()
        local castSlotFrameHeight = math_max(8, horizontalBarHeight)
        local castAbove = SortSlotsForSide(castSlots, "above", true, GetPreviewTargetFirst(preview, "above"))
        local castBelow = SortSlotsForSide(castSlots, "below", false, GetPreviewTargetFirst(preview, "below"))
        local castAboveHeight = GetLaneExtent(preview, castAbove, castSlotFrameHeight)
        local castBelowHeight = GetLaneExtent(preview, castBelow, castSlotFrameHeight)

        local castAboveLane = BuildLane(preview, content, layoutDrag, nil, panelWidth, castAboveHeight, "y", "above", true, castAbove, panelWidth, castSlotFrameHeight, "cast")
        castAboveLane.frame:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)

        castAboveLane.setPreviewOverflow = function(extra)
            castAboveLane.frame:ClearAllPoints()
            castAboveLane.frame:SetPoint("TOPLEFT", content, "TOPLEFT", 0, extra)
            castAboveLane.frame:SetSize(castAboveLane.baseWidth or panelWidth, (castAboveLane.baseHeight or castAboveHeight) + extra)
        end
        castAboveLane.setPreviewOverflow(0)

        castPanel:ClearAllPoints()
        castPanel:SetPoint("TOPLEFT", castAboveLane.frame, "BOTTOMLEFT", 0, -LAYOUT_PREVIEW_GAP)

        local castBelowLane = BuildLane(preview, content, layoutDrag, nil, panelWidth, castBelowHeight, "y", "below", false, castBelow, panelWidth, castSlotFrameHeight, "cast")
        castBelowLane.frame:SetPoint("TOPLEFT", castPanel, "BOTTOMLEFT", 0, -LAYOUT_PREVIEW_GAP)

        local iconCenterOffsetY = castAboveHeight + LAYOUT_PREVIEW_GAP + (panelHeight / 2)
        return panelWidth, castAboveHeight + panelHeight + castBelowHeight + (LAYOUT_PREVIEW_GAP * 2), iconCenterOffsetY
    end

    local panelFrame = AcquirePanelFrame(preview, content, sourcePanel, 1)
    local panelWidth = panelFrame:GetWidth()
    local panelHeight = panelFrame:GetHeight()
    local leftSlots = SortSlotsForSide(primarySlots, "left", true, GetPreviewTargetFirst(preview, "left"))
    local rightSlots = SortSlotsForSide(primarySlots, "right", false, GetPreviewTargetFirst(preview, "right"))
    local leftWidth = GetLaneExtent(preview, leftSlots, verticalBarWidth)
    local rightWidth = GetLaneExtent(preview, rightSlots, verticalBarWidth)
    local verticalBarHeight = panelHeight

    local leftLane = BuildLane(preview, content, layoutDrag, nil, leftWidth, panelHeight, "x", "left", true, leftSlots, verticalBarWidth, verticalBarHeight, "primary")
    leftLane.frame:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)

    leftLane.setPreviewOverflow = function(extra)
        leftLane.frame:ClearAllPoints()
        leftLane.frame:SetPoint("TOPLEFT", content, "TOPLEFT", -extra, 0)
        leftLane.frame:SetSize((leftLane.baseWidth or leftWidth) + extra, leftLane.baseHeight or panelHeight)
    end
    leftLane.setPreviewOverflow(0)

    panelFrame:ClearAllPoints()
    panelFrame:SetPoint("TOPLEFT", leftLane.frame, "TOPRIGHT", LAYOUT_PREVIEW_GAP, 0)

    local rightLane = BuildLane(preview, content, layoutDrag, nil, rightWidth, panelHeight, "x", "right", false, rightSlots, verticalBarWidth, verticalBarHeight, "primary")
    rightLane.frame:SetPoint("TOPLEFT", panelFrame, "TOPRIGHT", LAYOUT_PREVIEW_GAP, 0)

    local totalWidth = leftWidth + panelWidth + rightWidth + (LAYOUT_PREVIEW_GAP * 2)
    local totalHeight = panelHeight

    if #castSlots > 0 then
        -- The vertical layout draws the cast lane around its own copy of the
        -- panel below the primary section, so this is instance 2.
        local castPanel = AcquirePanelFrame(preview, content, sourcePanel, 2)
        local castSlotFrameHeight = math_max(8, horizontalBarHeight)
        local castAbove = SortSlotsForSide(castSlots, "above", true, GetPreviewTargetFirst(preview, "above"))
        local castBelow = SortSlotsForSide(castSlots, "below", false, GetPreviewTargetFirst(preview, "below"))
        local castAboveHeight = GetLaneExtent(preview, castAbove, castSlotFrameHeight)
        local castBelowHeight = GetLaneExtent(preview, castBelow, castSlotFrameHeight)

        local castAboveLane = BuildLane(preview, content, layoutDrag, nil, panelWidth, castAboveHeight, "y", "above", true, castAbove, panelWidth, castSlotFrameHeight, "cast")
        castAboveLane.frame:SetPoint("TOPLEFT", content, "TOPLEFT", leftWidth + LAYOUT_PREVIEW_GAP, -(panelHeight + LAYOUT_PREVIEW_SECTION_GAP))

        castAboveLane.setPreviewOverflow = function(extra)
            castAboveLane.frame:ClearAllPoints()
            castAboveLane.frame:SetPoint("TOPLEFT", content, "TOPLEFT", leftWidth + LAYOUT_PREVIEW_GAP, -(panelHeight + LAYOUT_PREVIEW_SECTION_GAP) + extra)
            castAboveLane.frame:SetSize(castAboveLane.baseWidth or panelWidth, (castAboveLane.baseHeight or castAboveHeight) + extra)
        end
        castAboveLane.setPreviewOverflow(0)

        castPanel:ClearAllPoints()
        castPanel:SetPoint("TOPLEFT", castAboveLane.frame, "BOTTOMLEFT", 0, -LAYOUT_PREVIEW_GAP)

        local castBelowLane = BuildLane(preview, content, layoutDrag, nil, panelWidth, castBelowHeight, "y", "below", false, castBelow, panelWidth, castSlotFrameHeight, "cast")
        castBelowLane.frame:SetPoint("TOPLEFT", castPanel, "BOTTOMLEFT", 0, -LAYOUT_PREVIEW_GAP)

        totalHeight = panelHeight + LAYOUT_PREVIEW_SECTION_GAP + castAboveHeight + castPanel:GetHeight() + castBelowHeight + (LAYOUT_PREVIEW_GAP * 2)
        totalWidth = math_max(totalWidth, leftWidth + LAYOUT_PREVIEW_GAP + panelWidth)
    end

    local iconCenterOffsetY = panelHeight / 2
    return totalWidth, totalHeight, iconCenterOffsetY
end

local function SelectPreviewCastFramesItem(item)
    if ST._SelectConfigCastFramesItem then
        ST._SelectConfigCastFramesItem(item)
    else
        CS.castFramesSelectedItem = item
    end
    CooldownCompanion:RefreshConfigPanel()
end

local function ConfigureBarsPill(preview, frame, item)
    local skin = preview.skin
    local selected = item.selected == true
    local accent = item.accent or BARS_PILL_NEUTRAL_ACCENT

    frame.label:SetText(item.label or "")
    frame.label:ClearAllPoints()
    if item.icon then
        frame.icon:SetAtlas(item.icon, false)
        frame.icon:SetVertexColor(1, 1, 1, 1)
        frame.icon:Show()
        frame.label:SetPoint("LEFT", frame.icon, "RIGHT", BARS_PILL_ICON_GAP, 0)
    else
        frame.icon:Hide()
        frame.label:SetPoint("LEFT", frame, "LEFT", BARS_PILL_ACCENT_WIDTH + BARS_PILL_INSET, 0)
    end
    frame.label:SetPoint("RIGHT", frame, "RIGHT", -BARS_PILL_INSET, 0)

    ApplyBackdrop(frame, skin.slotBg,
        selected and BARS_PILL_SELECTED_BORDER or skin.slotBorder, 1)
    frame.accent:SetColorTexture(accent[1], accent[2], accent[3], selected and 1 or 0.85)
    frame.selected:SetShown(selected)
    local color = selected and BARS_PILL_SELECTED_TEXT_COLOR or BARS_PILL_TEXT_COLOR
    frame.label:SetTextColor(color[1], color[2], color[3])

    frame._cdcTooltip = item.tooltip or item.label
    frame._cdcTooltipLine = item.tooltipLine
    frame._cdcTooltipNote = item.tooltipNote
    frame:SetScript("OnClick", function(_, mouseButton)
        if mouseButton == "RightButton" then
            if item.onRightClick then
                item.onRightClick()
            end
            return
        end
        if mouseButton == "LeftButton" and item.onClick then
            item.onClick()
        end
    end)
end

-- Mirrors ConfigureBarsPill's anchors exactly, so a pill sized from this is
-- the natural width of what it draws and the label's centering has no slack
-- to absorb.
local function GetBarsPillWidth(frame, item)
    local lead = item.icon
        and (BARS_PILL_ICON_GAP + BARS_PILL_ICON_SIZE + BARS_PILL_ICON_GAP)
        or BARS_PILL_INSET
    local width = BARS_PILL_ACCENT_WIDTH + lead
        + math_floor((frame.label:GetStringWidth() or 0) + 0.5) + BARS_PILL_INSET
    return math_max(BARS_PILL_MIN_WIDTH, width)
end

-- Lays the items out as centered lines, wrapping onto another line when
-- `maxWidth` runs out, and returns the row plus its measured size. A single
-- item wider than `maxWidth` keeps its line to itself rather than being
-- clipped; the caller's fit-to-host scale absorbs the overflow.
local function BuildBarsPillRow(preview, parent, items, maxWidth)
    local row = AcquireContainer(preview, parent)
    row:ClearAllPoints()

    local frames = {}
    local widths = {}
    for index, item in ipairs(items) do
        local frame = AcquireBarsPill(preview, row)
        ConfigureBarsPill(preview, frame, item)
        frames[index] = frame
        widths[index] = GetBarsPillWidth(frame, item)
    end

    local lines = {}
    local current = { width = 0, first = 1, last = 0 }
    for index = 1, #frames do
        local candidate = current.width > 0
            and (current.width + BARS_PILL_GAP + widths[index])
            or widths[index]
        if current.width > 0 and candidate > maxWidth then
            lines[#lines + 1] = current
            current = { width = widths[index], first = index, last = index }
        else
            current.width = candidate
            current.last = index
        end
    end
    if current.last >= current.first then
        lines[#lines + 1] = current
    end

    local rowWidth = 0
    for _, line in ipairs(lines) do
        rowWidth = math_max(rowWidth, line.width)
    end

    local top = 0
    for lineIndex, line in ipairs(lines) do
        local x = math_floor((rowWidth - line.width) / 2)
        for index = line.first, line.last do
            local frame = frames[index]
            frame:SetSize(widths[index], BARS_PILL_HEIGHT)
            frame:ClearAllPoints()
            frame:SetPoint("TOPLEFT", row, "TOPLEFT", x, -top)
            x = x + widths[index] + BARS_PILL_GAP
        end
        top = top + BARS_PILL_HEIGHT
            + (lineIndex < #lines and BARS_PILL_LINE_GAP or 0)
    end

    row:SetSize(math_max(1, rowWidth), math_max(1, top))
    return row, rowWidth, top
end

-- The two unit-frame badges: canvas objects, so their selection keys
-- register as rendered. Called only when frame anchoring is on; the
-- caller has already tested that, since it also decides whether the
-- composition has anything at all to draw.
local function BuildBarsUnitFrameBadgeItems(preview)
    local items = {}
    local accent = BARS_PILL_NEUTRAL_ACCENT
    local _, classKey = UnitClass("player")
    local classColor = classKey and C_ClassColor.GetClassColor(classKey)
    if classColor then
        accent = { classColor.r, classColor.g, classColor.b }
    end

    local anchoringNote = "Stands in for your real unit frame, which "
        .. "Cooldown Companion re-anchors rather than draws."

    items[#items + 1] = {
        label = "Player Frame",
        icon = classKey and ("classicon-" .. string.lower(classKey)) or BARS_PILL_TARGET_ICON,
        accent = accent,
        selected = CS.castFramesSelectedItem == "player",
        tooltip = "Player Frame",
        tooltipLine = "Click to edit this frame's anchoring.",
        tooltipNote = anchoringNote,
        onClick = function()
            SelectPreviewCastFramesItem("player")
        end,
    }
    preview.renderedSelectionKeys["frame:player"] = true

    items[#items + 1] = {
        label = "Target Frame",
        icon = BARS_PILL_TARGET_ICON,
        accent = BARS_PILL_NEUTRAL_ACCENT,
        selected = CS.castFramesSelectedItem == "target",
        tooltip = "Target Frame",
        tooltipLine = "Click to edit this frame's anchoring.",
        tooltipNote = anchoringNote,
        onClick = function()
            SelectPreviewCastFramesItem("target")
        end,
    }
    preview.renderedSelectionKeys["frame:target"] = true

    return items
end

-- The module-enable cluster, pinned to the pane's bottom-right corner: one
-- pill per module of this workspace that is switched off entirely. It is
-- host chrome rather than canvas content, built on every bars build before
-- anything measures itself, so it is on screen in the message-only states
-- too - those are exactly the states whose way out is turning a module on.
--
-- It claims its own share of the host's bottom reserve (see
-- GetHostBottomReserve), which is why a wrap costs the composition height
-- instead of drawing over it. One line matches the command center's band
-- exactly, so the common case costs nothing.
--
-- Never more than two pills: with all three modules off the workspace
-- shows its overview pane instead and no canvas is built at all.
local function BuildBarsEnableCluster(preview)
    local host = preview.host
    if not host then
        return
    end

    local items = IsBarsWorkspaceActive()
        and ST._CollectBarsEnableItems
        and ST._CollectBarsEnableItems()
        or nil
    if not (items and #items > 0) then
        if preview.enableCluster then
            preview.enableCluster:Hide()
        end
        host._cdcBarsCornerReserveBottom = nil
        return
    end

    local cluster = preview.enableCluster
    if not cluster then
        cluster = CreateFrame("Frame", nil, host)
        cluster:SetClipsChildren(false)
        -- Level with the command center, above the composition's own
        -- frames, so neither corner is ever buried by an overhanging slot.
        cluster:SetFrameLevel(host:GetFrameLevel() + 20)
        preview.enableCluster = cluster
    end
    cluster:Show()

    local frames = {}
    local widths = {}
    for index, item in ipairs(items) do
        item.accent = BARS_PILL_ENABLE_ACCENT
        item.label = "+ " .. tostring(item.label or "")
        local frame = AcquireBarsPill(preview, cluster)
        ConfigureBarsPill(preview, frame, item)
        frames[index] = frame
        widths[index] = GetBarsPillWidth(frame, item)
    end

    -- The command center owns the left of this band. Leave it its width
    -- plus a gap and wrap into what is left; when even one pill will not
    -- fit that, the cluster takes the room it needs and the command center
    -- keeps the left edge it is anchored to.
    local hostWidth = host:GetWidth() or 0
    if hostWidth < 40 then
        hostWidth = 340
    end
    local occupied = ST._GetPreviewCommandCenterOccupiedWidth
        and ST._GetPreviewCommandCenterOccupiedWidth(host) or 0
    local budget = hostWidth - BARS_CORNER_SIDE_INSET - occupied
    if occupied > 0 then
        budget = budget - BARS_CORNER_COMMAND_GAP
    end
    budget = math_max(BARS_PILL_MIN_WIDTH, budget)

    local lines = {}
    local current = { width = 0, first = 1, last = 0 }
    for index = 1, #frames do
        local candidate = current.width > 0
            and (current.width + BARS_PILL_GAP + widths[index])
            or widths[index]
        if current.width > 0 and candidate > budget then
            lines[#lines + 1] = current
            current = { width = widths[index], first = index, last = index }
        else
            current.width = candidate
            current.last = index
        end
    end
    if current.last >= current.first then
        lines[#lines + 1] = current
    end

    local clusterWidth = 0
    for _, line in ipairs(lines) do
        clusterWidth = math_max(clusterWidth, line.width)
    end

    local top = 0
    for lineIndex, line in ipairs(lines) do
        local right = 0
        for index = line.last, line.first, -1 do
            local frame = frames[index]
            frame:SetSize(widths[index], BARS_CORNER_PILL_HEIGHT)
            frame:ClearAllPoints()
            frame:SetPoint("TOPRIGHT", cluster, "TOPRIGHT", -right, -top)
            right = right + widths[index] + BARS_PILL_GAP
        end
        top = top + BARS_CORNER_PILL_HEIGHT
            + (lineIndex < #lines and BARS_PILL_LINE_GAP or 0)
    end

    cluster:SetSize(math_max(1, clusterWidth), math_max(1, top))
    cluster:ClearAllPoints()
    cluster:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT",
        -BARS_CORNER_SIDE_INSET, BARS_CORNER_BOTTOM_INSET)

    host._cdcBarsCornerReserveBottom = BARS_CORNER_BOTTOM_INSET + top
end

local function FinishPreviewWithMessage(preview, message)
    SetPreviewMessage(preview, message)
    FinalizePreviewState(preview)
end

local function GetLayoutOrderForInsertion(laneSlots, reversed, insertIndex)
    local beforeSlot = laneSlots[insertIndex - 1]
    local afterSlot = laneSlots[insertIndex]
    if beforeSlot and afterSlot then
        local beforeOrder = beforeSlot.getOrder()
        local afterOrder = afterSlot.getOrder()
        if beforeOrder == afterOrder then
            return beforeOrder + (reversed and -0.5 or 0.5)
        end
        return (beforeOrder + afterOrder) / 2
    end
    if beforeSlot then
        return beforeSlot.getOrder() + (reversed and -1 or 1)
    end
    if afterSlot then
        return afterSlot.getOrder() + (reversed and 1 or -1)
    end
    return 1
end

-- The cursor's raw landing spot, CLAMPED into the positions the drop is
-- allowed to take. Clamping here rather than at commit time is what makes the
-- drag teach the rule: the gap indicator reads this same index, so a block
-- bar dragged past the end of its bucket shows the gap holding at the
-- bucket's edge instead of opening somewhere it would only snap back from.
local function GetLaneInsertIndex(lane, cursorX, cursorY, draggedSlotId, draggedSlot)
    local _, slots, models = BuildStableLaneSlots(lane, draggedSlotId)
    if not slots then
        return 1
    end

    local raw
    if #slots == 0 then
        raw = 1
    elseif lane.axis == "x" then
        raw = #slots + 1
        for index, slotRect in ipairs(slots) do
            if cursorX < ((slotRect.left + slotRect.right) / 2) then
                raw = index
                break
            end
        end
    else
        raw = #slots + 1
        for index, slotRect in ipairs(slots) do
            if cursorY > ((slotRect.top + slotRect.bottom) / 2) then
                raw = index
                break
            end
        end
    end

    return ClampLaneInsertIndex(lane, draggedSlot, models or {}, raw)
end

local function GetDistanceToLane(laneScale, cursorX, cursorY)
    if not laneScale then
        return nil
    end

    local left, right = laneScale.left, laneScale.right
    local top, bottom = laneScale.top, laneScale.bottom
    local dx = 0
    if cursorX < left then
        dx = left - cursorX
    elseif cursorX > right then
        dx = cursorX - right
    end

    local dy = 0
    if cursorY > top then
        dy = cursorY - top
    elseif cursorY < bottom then
        dy = bottom - cursorY
    end

    return (dx * dx) + (dy * dy)
end

local function ResolveDropTarget(layoutDrag, cursorX, cursorY, draggedSlot)
    local closestLane
    local closestLaneScale
    local closestDistance
    draggedSlot = draggedSlot or layoutDrag.draggedSlotData

    for _, lane in ipairs(layoutDrag.lanes or {}) do
        local frame = lane.frame
        if frame and frame:IsShown()
            and (not layoutDrag.slotCategory or not lane.acceptedCategory or lane.acceptedCategory == layoutDrag.slotCategory) then
            local laneScale = GetLaneScale(lane)
            local left = laneScale and laneScale.left
            local right = laneScale and laneScale.right
            local top = laneScale and laneScale.top
            local bottom = laneScale and laneScale.bottom
            local distance = GetDistanceToLane(laneScale, cursorX, cursorY)
            if distance ~= nil and (not closestDistance or distance < closestDistance) then
                closestDistance = distance
                closestLane = lane
                closestLaneScale = laneScale
            end
            if left and right and top and bottom
                and cursorX >= left and cursorX <= right
                and cursorY <= top and cursorY >= bottom then
                return {
                    lane = lane,
                    insertIndex = GetLaneInsertIndex(lane, cursorX, cursorY, layoutDrag.draggedSlotId, draggedSlot),
                }
            end
        end
    end

    if closestLane and closestDistance then
        local scaledSlotWidth = ((closestLane.slotWidth or 0) * ((closestLaneScale and closestLaneScale.scaleX) or 1))
        local scaledSlotHeight = ((closestLane.slotHeight or 0) * ((closestLaneScale and closestLaneScale.scaleY) or 1))
        local threshold = math_max(scaledSlotWidth, scaledSlotHeight, 24) + 60
        if closestDistance <= (threshold ^ 2) then
            return {
                lane = closestLane,
                insertIndex = GetLaneInsertIndex(closestLane, cursorX, cursorY, layoutDrag.draggedSlotId, draggedSlot),
            }
        end
    end

    return nil
end

-- `draggedSlot` is the model behind `draggedSlotId`, carried in for the drop
-- cue alone: a bucket bar in flight has to leave a bucket-coloured hole
-- behind, or the run it came out of reads as having lost the room for it.
local function UpdateLanePreview(preview, lane, draggedSlotId, dropTarget, draggedSlot)
    local gapIndex = (dropTarget and dropTarget.lane == lane and dropTarget.insertIndex) or nil

    -- Render order for this frame: the lane's slots with the dragged one
    -- lifted out, and the drop gap (sized to the bar being dragged)
    -- inserted where it would land. Positions come from this list, so bars
    -- of different thicknesses shuffle correctly.
    local ordered = {}
    local sizes = {}
    for _, slot in ipairs(lane.slotModels or {}) do
        local slotFrame = lane.slotFramesById[slot.id]
        if slotFrame and slot.id ~= draggedSlotId then
            ordered[#ordered + 1] = slotFrame
            sizes[#sizes + 1] = GetSlotExtent(slot, lane.defaultExtent)
        end
    end
    if gapIndex then
        gapIndex = math_max(1, math_min(#ordered + 1, gapIndex))
        table_insert(sizes, gapIndex, preview.draggedSlotExtent or lane.defaultExtent)
    end
    lane.renderSizes = sizes

    local visibleFrames = {}
    for _, slot in ipairs(lane.slotModels or {}) do
        local slotFrame = lane.slotFramesById[slot.id]
        if slotFrame and slot.id == draggedSlotId then
            slotFrame:SetAlpha(0)
        end
    end
    for index, slotFrame in ipairs(ordered) do
        local displayIndex = index
        if gapIndex and displayIndex >= gapIndex then
            displayIndex = displayIndex + 1
        end
        local x, y, w, h = BuildLaneSlotGeometry(lane, displayIndex)
        QueueSlotTween(preview, slotFrame, lane.frame, x, y, w, h, 1, LAYOUT_PREVIEW_ANIM_DURATION)
        slotFrame:SetShown(true)
        slotFrame:SetAlpha(1)
        table_insert(visibleFrames, slotFrame)
    end

    lane.visualSlots = visibleFrames
    local requiredExtent = GetExtentTotal(sizes, lane.slotGap or LAYOUT_PREVIEW_GAP, lane.defaultExtent)
    local overflow = math_max(0, requiredExtent - (lane.baseExtent or requiredExtent))
    if lane.setPreviewOverflow then
        lane.setPreviewOverflow(overflow)
    end

    if gapIndex then
        local x, y, w, h = BuildLaneSlotGeometry(lane, gapIndex)
        -- Containment already clamps a bucket bar's landing inside its own
        -- bucket, so the bar's identity decides the cue's colour. Re-applied
        -- on both legs every update: the gap frame is pooled per lane and a
        -- previous drag can have left the other bucket's colours on it.
        local tint = draggedSlot and LAYOUT_PREVIEW_BUCKET_TINTS[GetSlotBucketId(draggedSlot)]
        if tint then
            ApplyBackdrop(lane.gapFrame, tint.gapBg, tint.gapBorder)
            lane.gapFrame.inner:SetColorTexture(tint.gapInner[1], tint.gapInner[2],
                tint.gapInner[3], tint.gapInner[4])
        else
            ApplyBackdrop(lane.gapFrame, preview.skin.gapBg, preview.skin.gapBorder)
            lane.gapFrame.inner:SetColorTexture(preview.skin.slotHover[1],
                preview.skin.slotHover[2], preview.skin.slotHover[3], 0.22)
        end
        lane.gapFrame:SetAlpha(0.95)
        QueueSlotTween(preview, lane.gapFrame, lane.frame, x, y, w, h, 1, LAYOUT_PREVIEW_ANIM_DURATION)
        lane.gapFrame:Show()
    else
        lane.gapFrame:Hide()
    end

    -- The seam moves while the stack shuffles, and a handle chasing it would
    -- read as a drop target. It comes back when the drag ends.
    if lane.swapButton then
        lane.swapButton:Hide()
    end
end

local function ResetLanePreview(preview, lane)
    lane.renderSizes = lane.naturalSizes
    for index, slot in ipairs(lane.slotModels or {}) do
        local slotFrame = lane.slotFramesById[slot.id]
        if slotFrame then
            local x, y, w, h = BuildLaneSlotGeometry(lane, index)
            QueueSlotTween(preview, slotFrame, lane.frame, x, y, w, h, 1, LAYOUT_PREVIEW_ANIM_DURATION)
            slotFrame:SetShown(true)
            slotFrame:SetAlpha(1)
            lane.visualSlots[index] = slotFrame
        end
    end
    lane.gapFrame:Hide()
    if lane.swapButton then
        lane.swapButton:Show()
    end
    if lane.setPreviewOverflow then
        lane.setPreviewOverflow(0)
    end
end

local function ConfigureGhost(preview, slotData, slotFrame)
    local ghost = preview.ghost
    ghost:SetFrameStrata("TOOLTIP")
    ghost:SetFrameLevel(2000)
    ApplyBackdrop(ghost, preview.skin.ghostBg, preview.skin.ghostBorder)
    ghost:SetSize(slotFrame:GetWidth(), slotFrame:GetHeight())

    if not ghost._cdcSlot then
        ghost._cdcSlot = CreateSlotFrame(ghost)
        ghost._cdcSlot:SetAllPoints(ghost)
        ghost._cdcSlot:EnableMouse(false)
    end

    local ghostSlot = ghost._cdcSlot
    ghostSlot.previewBarInfo = ghost.previewBarInfo
    ghostSlot.castPreview = ghost.castPreview
    ConfigureGhostSlotPreview(ghostSlot, slotData, preview, ghost:GetWidth(), ghost:GetHeight(), slotFrame.shortText:IsShown())
    ghost.previewBarInfo = ghostSlot.previewBarInfo
    ghost.castPreview = ghostSlot.castPreview

    -- The ghost carries the dragged bar's name too. Its own slot is at
    -- alpha 0 for the duration, so without this the one bar you are
    -- actually moving is the only one left unnamed. Scale 1: the ghost
    -- hangs off UIParent, not off the scaled preview content.
    ghostSlot.slotData = slotData
    ghostSlot._cdcIdentityVertical = slotFrame._cdcIdentityVertical
    ApplySlotIdentityMarks(preview, ghostSlot, 1, ghost:GetWidth())
    ghost:SetAlpha(0.92)
    ghost:Show()
    preview.ghostActive = true
    UpdateGhostPosition(ghost)
end

local function ClearGhost(preview)
    preview.ghostActive = false
    if preview.ghost then
        preview.ghost:Hide()
    end
end

local function CreateLayoutDragModel(preview)
    local layoutDrag = { host = preview.host, lanes = {} }

    -- The lifecycle hands the drag state through, and the dragged bar's model
    -- is what the containment clamp needs: which bucket it belongs to decides
    -- where the gap is allowed to open.
    layoutDrag.resolveDropTarget = function(cursorX, cursorY, state)
        return ResolveDropTarget(layoutDrag, cursorX, cursorY, state and state.slotData)
    end

    layoutDrag.onActivate = function(state)
        if not (state and state.widget and state.slotData) then return end
        layoutDrag.draggedSlotId = state.slotData.id
        layoutDrag.draggedSlotData = state.slotData
        preview.draggedSlotExtent = GetSlotExtent(state.slotData, nil)
        ConfigureGhost(preview, state.slotData, state.widget)
        for _, lane in ipairs(layoutDrag.lanes) do
            UpdateLanePreview(preview, lane, state.slotData.id, state.dropTarget, state.slotData)
        end
        preview.root:SetScript("OnUpdate", function()
            TickPreview(preview)
        end)
    end

    layoutDrag.onUpdate = function(state, cursorX, cursorY, dropTarget)
        if not (state and state.slotData) then return end
        layoutDrag.draggedSlotId = state.slotData.id
        layoutDrag.draggedSlotData = state.slotData
        preview.draggedSlotExtent = GetSlotExtent(state.slotData, nil)
        for _, lane in ipairs(layoutDrag.lanes) do
            UpdateLanePreview(preview, lane, state.slotData.id, dropTarget, state.slotData)
        end
        if not preview.ghostActive then
            ConfigureGhost(preview, state.slotData, state.widget)
        else
            UpdateGhostPosition(preview.ghost)
        end
        preview.root:SetScript("OnUpdate", function()
            TickPreview(preview)
        end)
    end

    layoutDrag.onCancel = function()
        layoutDrag.draggedSlotId = nil
        layoutDrag.draggedSlotData = nil
        preview.draggedSlotExtent = nil
        -- Thaw the reveal once the drag really is over. Deferred because
        -- this runs while CS.dragState is still set (CancelDrag clears it
        -- immediately after), which is what the freeze keys on.
        C_Timer.After(0, function()
            SetIdentityLabelsShown(preview, AnyCustomPreviewSlotHovered(preview))
        end)
        for _, lane in ipairs(layoutDrag.lanes) do
            ResetLanePreview(preview, lane)
        end
        ClearGhost(preview)
        HideDragIndicator()
        preview.root:SetScript("OnUpdate", function()
            TickPreview(preview)
        end)
    end

    layoutDrag.applyDrop = function(state)
        local dropTarget = state and state.dropTarget
        local slotData = state and state.slotData
        if not dropTarget or not slotData or not dropTarget.lane then
            return
        end

        local lane = dropTarget.lane
        local filtered = {}
        for _, slot in ipairs(lane.slotModels or {}) do
            if slot.id ~= slotData.id then
                table_insert(filtered, slot)
            end
        end

        -- Re-clamped here, not just trusted from the drop target: the commit
        -- and the gap indicator must land on the same index, and this is the
        -- last point that can guarantee it.
        local adjustedIndex = ClampLaneInsertIndex(lane, slotData, filtered,
            math_max(1, math_min(#filtered + 1, dropTarget.insertIndex or 1)))
        local changed = false
        if preview.independentResources then
            -- Independent Resources is one continuous stack. Normalize every
            -- rendered slot to the chosen lane so the saved runtime layout
            -- matches the order shown after a drop.
            table_insert(filtered, adjustedIndex, slotData)
            local slotCount = #filtered
            for index, slot in ipairs(filtered) do
                local normalizedOrder = lane.reversed and (slotCount - index + 1) or index
                if slot.getPos() ~= lane.side or slot.getOrder() ~= normalizedOrder then
                    changed = true
                end
                slot.setPos(lane.side)
                slot.setOrder(normalizedOrder)
            end
        else
            local oldPos = slotData.getPos()
            local oldOrder = slotData.getOrder()
            -- Order values interleave across a section boundary once the
            -- aura block is in play, so the new order has to be midpointed
            -- against the dropped slot's OWN section. Measured against the
            -- whole lane, a within-block move lands on a fixed bar's order
            -- and re-renders on the wrong side of its own block. Each aura
            -- bucket is its own rank, so this is what orders a block entry
            -- inside the bucket containment already confined it to.
            local peers = filtered
            local peerIndex = adjustedIndex
            do
                local targetFirst = lane.targetFirst == true
                local rank = GetSlotStackRank(slotData, targetFirst)
                local section = {}
                local sectionIndex = 0
                for index, slot in ipairs(filtered) do
                    if GetSlotStackRank(slot, targetFirst) == rank then
                        table_insert(section, slot)
                        if index < adjustedIndex then
                            sectionIndex = #section
                        end
                    end
                end
                if #section > 0 then
                    peers = section
                    peerIndex = sectionIndex + 1
                end
            end
            local newOrder = (#peers == 0 and oldPos == lane.side)
                and oldOrder
                or GetLayoutOrderForInsertion(peers, lane.reversed, peerIndex)
            slotData.setPos(lane.side)
            slotData.setOrder(newOrder)
            changed = oldPos ~= lane.side or oldOrder ~= newOrder
        end

        if changed then
            CooldownCompanion:ApplyResourceBars()
            -- A block bar's order only lands at the deferred aura rebind in
            -- combat, and the rebind's internal reason never prints the
            -- "applies when combat ends" notice. This drop is a config edit,
            -- so say so; out of combat the apply above already rebound.
            if InCombatLockdown() and IsAuraBlockSlot(slotData) then
                CooldownCompanion:RequestAuraRebind("config")
            end
            CooldownCompanion:RepositionCastBar()
            CooldownCompanion:UpdateAnchorStacking()
            CooldownCompanion:RefreshConfigPanel()
        end
    end

    return layoutDrag
end

function ST._BuildLayoutOrderPreviewPanel(container, opts)
    if CS.dragState and CS.dragState.kind == LAYOUT_PREVIEW_DRAG_KIND and CancelDrag then
        CancelDrag()
    end

    local preview = EnsurePreviewState(container)
    preview.host = container
    -- Panel-frame injection (see AcquirePanelFrame): the caller either hands
    -- over the real button-panel mirror outright, or stands ready to build
    -- one per instance the render path asks for. Everything lent is hidden
    -- up front and re-shown only by the render path that uses it, so
    -- message-only builds don't leave a mirror floating.
    preview.externalPanelFrame = opts and opts.externalPanel or nil
    preview.panelFrameProvider = opts and opts.panelFrameProvider or nil
    ReleaseLentPanelFrames(preview)
    if preview.externalPanelFrame then
        preview.externalPanelFrame:Hide()
    end
    preview.rbSettings = CooldownCompanion:GetResourceBarSettings()
    preview.cbSettings = CooldownCompanion:GetCastBarSettings()
    local layout = CooldownCompanion:GetSpecLayoutOrder()
    preview.isVerticalLayout = preview.rbSettings
        and preview.rbSettings.enabled == true
        and IsResourceBarVerticalConfig(preview.rbSettings, layout)
        or false

    ResetPreviewState(preview)
    -- Corner chrome first: it claims part of the host's bottom reserve, and
    -- everything below - the composition's fit box and the message box
    -- alike - is measured against what that reserve leaves. Every exit from
    -- this function is downstream of here, so the cluster is on screen in
    -- the message-only states too.
    BuildBarsEnableCluster(preview)
    ApplyHostBottomReserve(container, preview.root)
    preview.layout = layout
    -- The real spacing between stacked bars, not a fixed 4px. (The gap
    -- between the icon panel and the lanes is a different setting,
    -- GetResourceAnchorGap, and still renders as the fixed chrome gap.)
    preview.slotGap = math_max(0, tonumber(layout and layout.barSpacing)
        or tonumber(preview.rbSettings and preview.rbSettings.barSpacing)
        or LAYOUT_PREVIEW_GAP)
    preview.draggedSlotExtent = nil
    HidePreviewMessage(preview)

    local rbSettings = preview.rbSettings
    local cbSettings = preview.cbSettings
    local resourceBarsEnabled = rbSettings and rbSettings.enabled == true
    local castBarEnabled = cbSettings and cbSettings.enabled == true
    local frameAnchoringSettings = CooldownCompanion.GetFrameAnchoringSettings
        and CooldownCompanion:GetFrameAnchoringSettings()
    local hasUnitFrameBadges = IsBarsWorkspaceActive()
        and frameAnchoringSettings
        and frameAnchoringSettings.enabled == true
    if not (resourceBarsEnabled or castBarEnabled or hasUnitFrameBadges) then
        FinishPreviewWithMessage(preview,
            "Nothing to show yet. Switch on Resource Bars, the cast bar, or unit frames to start.")
        return
    end

    local independentResourcesPreview = IsBarsWorkspaceActive()
        and resourceBarsEnabled
        and layout
        and IsTruthyConfigFlag(layout.independentAnchorEnabled)
    preview.independentResources = independentResourcesPreview == true
    local supportsAttachedResourceBars = resourceBarsEnabled
        and not (layout and IsTruthyConfigFlag(layout.independentAnchorEnabled))
    local hasAttachedCastBar = castBarEnabled and not IsTruthyConfigFlag(cbSettings.independentAnchorEnabled)
    local includeResourceSlots = supportsAttachedResourceBars or independentResourcesPreview
    local includeCastSlots = not independentResourcesPreview
    local hasAttachedBarContext = not independentResourcesPreview
        and (includeResourceSlots or hasAttachedCastBar)
    local hasBarContext = independentResourcesPreview or hasAttachedBarContext
    if not hasBarContext and not hasUnitFrameBadges then
        FinishPreviewWithMessage(preview,
            "Nothing is anchored to a panel right now. Pick an object below to edit it.")
        return
    end

    if hasBarContext and not layout then
        FinishPreviewWithMessage(preview, "Specialization data loading...")
        return
    end

    local primarySlots = {}
    local castSlots = {}
    local sourcePanel
    local sourceMessage
    if hasBarContext then
        primarySlots, castSlots = CollectPreviewSlots(
            rbSettings,
            includeCastSlots and cbSettings or nil,
            layout,
            preview.isVerticalLayout,
            includeResourceSlots,
            independentResourcesPreview == true
        )
        if not preview.isVerticalLayout then
            for _, castSlot in ipairs(castSlots) do
                table_insert(primarySlots, castSlot)
            end
        end

        if hasAttachedBarContext and (#primarySlots > 0 or #castSlots > 0) then
            sourcePanel, sourceMessage = ResolveLayoutPreviewSourcePanel()
            if not sourcePanel and not hasUnitFrameBadges then
                FinishPreviewWithMessage(preview, sourceMessage)
                return
            end
            if not sourcePanel then
                wipe(primarySlots)
                wipe(castSlots)
            end
        end
    end

    if #primarySlots == 0 and #castSlots == 0 and not hasUnitFrameBadges then
        if independentResourcesPreview then
            FinishPreviewWithMessage(preview,
                "No active resources to order. Enable a resource or Custom Bar first.")
        else
            FinishPreviewWithMessage(preview,
                "No active bars to order. Enable resources, Custom Bars, or cast bar first.")
        end
        return
    end

    local layoutDrag
    if #primarySlots > 0 or #castSlots > 0 then
        layoutDrag = CreateLayoutDragModel(preview)
        preview.layoutDrag = layoutDrag
    end

    local root = preview.root
    -- Two frames, not one: `block` is everything the pane centers and
    -- scales, `content` is the bar composition alone. The unit-frame badges
    -- are the other member of the block, and nesting is what keeps a badge
    -- pair wider than the bar stack from dragging the stack off the pane's
    -- axis - each member centers inside the block, and the block centers on
    -- the pane.
    local block = AcquireContainer(preview, root)
    block:SetClipsChildren(false)
    local content = AcquireContainer(preview, block)
    content:SetClipsChildren(false)

    local contentWidth = 0
    local contentHeight = 0
    if independentResourcesPreview and layoutDrag then
        local resourceThickness = math_max(8, tonumber(GetResourceGlobalThickness(rbSettings)) or 12)
        local independentLength = math_max(
            20,
            tonumber(layout.independentWidth or rbSettings.independentWidth) or 200
        )
        if preview.isVerticalLayout then
            contentWidth, contentHeight = RenderIndependentVerticalLayout(
                preview,
                content,
                layoutDrag,
                primarySlots,
                independentLength,
                resourceThickness
            )
        else
            contentWidth, contentHeight = RenderIndependentHorizontalLayout(
                preview,
                content,
                layoutDrag,
                primarySlots,
                independentLength,
                resourceThickness
            )
        end
    elseif sourcePanel and layoutDrag then
        local resourceThickness = (rbSettings and tonumber(GetResourceGlobalThickness(rbSettings)))
            or math_floor(sourcePanel.iconHeight * 0.56)
        -- Fallback thickness only: every slot now carries its own (the cast
        -- bar its configured height, resources and custom bars their
        -- per-slot override). This used to be one max across both, which
        -- clamped every bar up to whichever was tallest.
        local horizontalBarHeight = math_max(8, math_floor(resourceThickness))
        local verticalBarWidth = math_max(8, math_floor(resourceThickness))

        if preview.isVerticalLayout then
            contentWidth, contentHeight = RenderVerticalLayout(
                preview,
                content,
                layoutDrag,
                sourcePanel,
                primarySlots,
                castSlots,
                horizontalBarHeight,
                verticalBarWidth
            )
        else
            contentWidth, contentHeight = RenderHorizontalLayout(
                preview,
                content,
                layoutDrag,
                sourcePanel,
                primarySlots,
                horizontalBarHeight
            )
        end
    end

    local hostWidth = container:GetWidth() or 0
    local hostHeight = (container:GetHeight() or 0) - GetHostBottomReserve(container)
    if hostWidth < 40 then hostWidth = 340 end
    if hostHeight < 40 then hostHeight = 520 end
    local maxWidth = math_max(120, hostWidth - (LAYOUT_PREVIEW_PADDING * 2))
    local maxHeight = math_max(120, hostHeight - (LAYOUT_PREVIEW_PADDING * 2))

    content:SetSize(contentWidth, contentHeight)
    content:ClearAllPoints()
    content:SetPoint("TOP", block, "TOP", 0, 0)

    -- The badges join the composition rather than docking to the pane: they
    -- are objects this canvas draws, so they belong inside the block that
    -- gets measured, scaled and centered with the bars.
    local blockWidth = contentWidth
    local blockHeight = contentHeight
    if hasUnitFrameBadges then
        local badgeRow, badgeWidth, badgeHeight = BuildBarsPillRow(
            preview, block, BuildBarsUnitFrameBadgeItems(preview), maxWidth)
        local gap = contentHeight > 0 and BARS_BADGE_GAP or 0
        badgeRow:ClearAllPoints()
        badgeRow:SetPoint("TOP", content, "BOTTOM", 0, -gap)
        blockWidth = math_max(blockWidth, badgeWidth)
        blockHeight = blockHeight + gap + badgeHeight
    end

    block:SetSize(math_max(1, blockWidth), math_max(1, blockHeight))

    local scale = math_min(1, maxWidth / math_max(1, blockWidth), maxHeight / math_max(1, blockHeight))

    -- Center the whole visual block in the pane so dead space stays
    -- symmetric regardless of how bars split across their configured
    -- sides. The root already stops short of the host's bottom band, so
    -- this stays a zero anchor offset - which is what keeps it exact under
    -- the scale above.
    block:SetScale(scale)
    block:ClearAllPoints()
    block:SetPoint("CENTER", root, "CENTER", 0, 0)

    -- Identity marks last: they counter-scale against the fit above, so
    -- they can only be laid out once it is known. A rebuild can happen with
    -- the cursor already resting on a bar (a value change repaints the
    -- preview under it), so the reveal state is re-derived rather than
    -- assumed off.
    preview.identityLabelsShown = AnyCustomPreviewSlotHovered(preview)
    for index = 1, (preview.used.slots or 0) do
        ApplySlotIdentityMarks(preview, preview.pools.slots[index], scale)
    end
    -- Same reason, same pass: the seam handle is a hit target, so it is sized
    -- in screen pixels rather than in the composition's.
    for index = 1, (preview.used.swaps or 0) do
        SwapSeam.ApplyScale(preview.pools.swaps[index], scale)
    end

    FinalizePreviewState(preview)
    StartPreviewAnimationDriver(preview)
end

-- True when the Layout & Order lanes would actually render bars around an
-- anchored panel: something enabled and attached, spec layout loaded, and
-- at least one active slot. The unified anchor preview gates on this so it
-- never trades the real mirror for a message-only pane.
function ST._HasAttachedBarLanesToRender()
    local rbSettings = CooldownCompanion:GetResourceBarSettings()
    local cbSettings = CooldownCompanion:GetCastBarSettings()
    local layout = CooldownCompanion:GetSpecLayoutOrder()
    if not layout then
        return false
    end
    local resourceBarsEnabled = rbSettings and rbSettings.enabled == true
    local castBarEnabled = cbSettings and cbSettings.enabled == true
    local supportsAttachedResourceBars = resourceBarsEnabled
        and not IsTruthyConfigFlag(layout.independentAnchorEnabled)
    local hasAttachedCastBar = castBarEnabled
        and not IsTruthyConfigFlag(cbSettings.independentAnchorEnabled)
    if not supportsAttachedResourceBars and not hasAttachedCastBar then
        return false
    end
    local isVertical = resourceBarsEnabled
        and IsResourceBarVerticalConfig(rbSettings, layout)
        or false
    local primarySlots, castSlots = CollectPreviewSlots(
        rbSettings,
        cbSettings,
        layout,
        isVertical,
        supportsAttachedResourceBars
    )
    return #primarySlots > 0 or #castSlots > 0
end

-- Does the Resources / Cast Bar canvas actually draw a cast lane right now?
-- The command center asks before offering the cast preview, because "the
-- cast bar is attached" is not the same question: an INDEPENDENT resource
-- stack drops the cast slot from this home entirely (includeCastSlots
-- below), and offering a preview whose destination is not on screen means
-- pressing play visibly does nothing.
--
-- Answered by re-deriving the build's own preconditions rather than by
-- reporting what the last build drew: the command center runs BEFORE the
-- renderer on every rebuild (it owns the host's bottom reserve, which the
-- renderer then measures), so a recorded answer would always be one change
-- stale. The source-panel resolve is the same one _BuildLayoutOrderPreview-
-- Panel makes and _HasAttachedBarLanesToRender already pays for; config
-- time, once per rebuild.
--
-- Deliberately an OFFER test only. It must not feed the stranded-preview
-- stop: `layout` is briefly nil across a spec change, and stopping on that
-- would kill a running preview for a transient live condition.
function ST._ResourcesPreviewRendersCastSlot()
    local cbSettings = CooldownCompanion:GetCastBarSettings()
    if not (cbSettings and cbSettings.enabled == true) then
        return false
    end
    if IsTruthyConfigFlag(cbSettings.independentAnchorEnabled) then
        return false
    end
    local layout = CooldownCompanion:GetSpecLayoutOrder()
    if not layout then
        -- "Specialization data loading..." - the canvas is a message.
        return false
    end
    local rbSettings = CooldownCompanion:GetResourceBarSettings()
    local independentResourcesPreview = IsBarsWorkspaceActive()
        and rbSettings and rbSettings.enabled == true
        and IsTruthyConfigFlag(layout.independentAnchorEnabled)
    if independentResourcesPreview then
        return false
    end
    -- An attached cast lane is drawn around the mirrored icon panel, so no
    -- resolvable panel means no lane: either the canvas is a message, or the
    -- unit-frame-proxy path wiped the slots and rendered proxies alone.
    return ResolveLayoutPreviewSourcePanel() ~= nil
end

-- Which resource power types the canvas draws lanes for right now: the SAME
-- three-way choice CollectPreviewSlots makes, exported so the preview command
-- center can offer a resource-aura toggle exactly when its destination lane is
-- on screen. Re-deriving the list over there is what put the two out of step
-- in BOTH directions — the runtime list is form-dependent (a druid out of cat
-- form has no Combo Points bar) while the config list is spec-based, and each
-- is the right answer for a different anchor mode.
--
-- Offer test only, like the cast-slot sibling above: a nil layout is the
-- transient spec-change state, not a reason to stop a running preview.
function ST._ResourcesPreviewResourceLanePowerTypes()
    local rbSettings = CooldownCompanion:GetResourceBarSettings()
    if not (rbSettings and rbSettings.enabled == true) then
        return {}
    end
    local layout = CooldownCompanion:GetSpecLayoutOrder()
    if not layout then
        -- "Specialization data loading..." - the canvas is a message.
        return {}
    end
    if IsTruthyConfigFlag(layout.independentAnchorEnabled) then
        -- An independent stack is drawn on the bars workspace alone, and
        -- from the runtime-eligible list; anywhere else it has no lanes.
        if not IsBarsWorkspaceActive() then
            return {}
        end
        return RB.DetermineActiveResources and RB.DetermineActiveResources() or {}
    end
    return GetConfigActiveResources()
end

-- The selection keys the canvas drew on its most recent build for `host`.
-- Read by the bars workspace as it builds the "Not currently shown:" chip
-- strip below the editing divider, so the strip and the canvas can never
-- disagree about which objects are on screen. Call it AFTER the build.
function ST._GetLayoutPreviewRenderedSelectionKeys(host)
    local preview = host and host._cdcLayoutPreview
    return preview and preview.renderedSelectionKeys or nil
end

-- Shared with ButtonPanelPreview.lua: config-safe icon resolution and the
-- mirrored icon styling both previews use. StyleMirroredIconFrame expects an
-- icon frame carrying bg, icon, countText, and borderTextures[4]; pass
-- button as { buttonData = ... } to style purely from saved settings.
ST._GetLayoutPreviewIcon = GetLayoutPreviewIcon
ST._StyleMirroredIconFrame = StyleMirroredIconFrame

-- Owners that lend this canvas a real mirror wear the same "icons stay in
-- place" refusal the canvas's own placeholder wears, so the strings have one
-- home.
ST._ApplyLayoutPreviewIconPanelClickShield = ApplyIconPanelClickShield
