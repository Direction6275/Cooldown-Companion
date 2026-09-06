--[[
    CooldownCompanion - SettingsNavigation
    Settings jump highlighting and scroll-anchor preservation across lens rebuilds.

    Part of the Helpers family; see its ordered block in the addon TOC.
    Private helpers are shared through ST._SettingsHelpers.
]]

local ADDON_NAME, ST = ...
local CS = ST._configState

local SH = {}
ST._SettingsHelpers = SH

-- Helper: build a class-colored collapsible section Heading wired to a
-- collapse-state store. store defaults to CS.collapsedSections (the config
-- columns' store); resource-bar panels pass their own. refreshFn defaults to
-- a full config-panel refresh. Returns the heading, its collapsed state, and
-- the collapse button (for callers that anchor extra controls to it).
--
-- opts.leftAligned opts into the row-grammar header shape (caret, then a
-- left-aligned label, then a rule fading right). Omitting opts keeps the
-- stock centered heading every existing call site draws today.
local RegisterLensAnchorHeading

------------------------------------------------------------------------
-- Navigated-setting highlight
--
-- A gear or name link that routes the user to a setting (the preview command
-- center's gear, the Customizations list's name link and gear, the Resources
-- object routes) stashes a one-shot request in CS.pendingSettingHighlight
-- before it refreshes:
--   collapseKeys - the section collapse keys the route force-opens (both the
--                  raw key and its lens-resolved variant)
--   sectionId    - the override section the route is about, when it is one
--   settingKey   - an exact Settings Finder descriptor id
--   rowKey       - the setting row's advanced key, when the route names one
-- The rebuild the navigation triggers consumes it, most specific match first:
-- BindSettingWidget records the exact finder row (settingKey),
-- AddAdvancedToggle records the row wearing the matching gear (rowKey),
-- LensSection:Chrome records the section's anchor row (sectionId - attached
-- in every lens mode, so an entry-lens destination still lands on its row),
-- and BuildCollapsibleSection records the first heading whose collapse key
-- matches as the fallback. One frame later, with layout settled (the same
-- deferred seam AceGUI's own FixScroll rides), the scheduled fire scrolls
-- the target into view and pulses a gold wash over it.
--
-- One-shot by construction: the fire consumes the request, and any OTHER
-- rebuild starting first discards it (BeginNavSettingHighlightRefresh below)
-- because that rebuild releases the recorded widgets back to the pool.
------------------------------------------------------------------------

-- Peak intensity lives in the textures' baked alpha; the animation only takes
-- the frame from 0 to 1 and back, so the two knobs stay independent.
local NAV_FLASH_ALPHA = 0.30
-- The wash hugs the row: a slight vertical inset so it sits on the text line
-- rather than bridging into its neighbours, and ends that fade out over this
-- many pixels instead of cutting off (SetGradient, live-verified signature -
-- Blizzard_NamePlates does the same underline fade).
local NAV_FLASH_INSET_V = 1
local NAV_FLASH_EDGE_FADE = 28
-- Padding above a target that has to be scrolled to, so it lands just under
-- the tab's top edge rather than flush against it.
local NAV_SCROLL_PAD = 24

local navFlashFrame

-- SettingsFinder.lua calls this from its widget-binding seam. It lives here
-- with the rest of the pending-highlight consumer so the finder does not need
-- to know anything about AceGUI's pooled row anatomy.
local function RecordSettingHighlightWidget(widget, settingKey)
    local pending = CS.pendingSettingHighlight
    if pending and pending.settingKey == settingKey and not pending.settingWidget then
        pending.settingWidget = widget
    end
end

local function EnsureNavFlashFrame()
    if navFlashFrame then
        return navFlashFrame
    end
    local f = CreateFrame("Frame")
    f:EnableMouse(false)
    f:Hide()
    local gold = CreateColor(1, 0.82, 0, NAV_FLASH_ALPHA)
    local goldFaded = CreateColor(1, 0.82, 0, 0)
    local left = f:CreateTexture(nil, "OVERLAY")
    left:SetPoint("TOPLEFT")
    left:SetPoint("BOTTOMLEFT")
    left:SetWidth(NAV_FLASH_EDGE_FADE)
    left:SetColorTexture(1, 1, 1, 1)
    left:SetGradient("HORIZONTAL", goldFaded, gold)
    local right = f:CreateTexture(nil, "OVERLAY")
    right:SetPoint("TOPRIGHT")
    right:SetPoint("BOTTOMRIGHT")
    right:SetWidth(NAV_FLASH_EDGE_FADE)
    right:SetColorTexture(1, 1, 1, 1)
    right:SetGradient("HORIZONTAL", gold, goldFaded)
    local mid = f:CreateTexture(nil, "OVERLAY")
    mid:SetPoint("TOPLEFT", left, "TOPRIGHT")
    mid:SetPoint("BOTTOMRIGHT", right, "BOTTOMLEFT")
    mid:SetColorTexture(1, 0.82, 0, NAV_FLASH_ALPHA)
    local ag = f:CreateAnimationGroup()
    local function AddPulse(order, from, to, duration)
        local anim = ag:CreateAnimation("Alpha")
        anim:SetOrder(order)
        anim:SetFromAlpha(from)
        anim:SetToAlpha(to)
        anim:SetDuration(duration)
    end
    -- Two pulses, then gone (~1.5s total).
    AddPulse(1, 0, 1, 0.15)
    AddPulse(2, 1, 0.25, 0.3)
    AddPulse(3, 0.25, 1, 0.3)
    AddPulse(4, 1, 0, 0.7)
    ag:SetScript("OnFinished", function()
        f:Hide()
    end)
    f._animation = ag
    navFlashFrame = f
    return f
end

local function StopNavSettingFlash()
    if navFlashFrame then
        navFlashFrame._animation:Stop()
        navFlashFrame:Hide()
        navFlashFrame:ClearAllPoints()
        navFlashFrame:SetParent(nil)
    end
end

-- The AceGUI scroll container the target widget lives in, found by walking
-- the widget parent chain AceGUI maintains - generic on purpose, so the same
-- fire path serves the buttons workspace and the resource-bar panes.
local function FindOwningScrollWidget(widget)
    if widget and widget.type == "ScrollFrame" then return widget end
    local cur = widget
    for _ = 1, 12 do
        cur = cur.parent
        if not cur then
            return nil
        end
        if cur.type == "ScrollFrame" then
            return cur
        end
    end
    return nil
end

ST._FindOwningSettingsScroll = FindOwningScrollWidget

local function ScrollNavTargetIntoView(widget)
    local scroll = FindOwningScrollWidget(widget)
    if not (scroll and scroll.content and scroll.scrollframe) then
        return
    end
    local frame = widget.frame
    local contentTop = scroll.content:GetTop()
    local targetTop = frame:GetTop()
    local targetHeight = frame:GetHeight()
    local viewHeight = scroll.scrollframe:GetHeight()
    local maxOffset = (scroll.content:GetHeight() or 0) - (viewHeight or 0)
    if not (contentTop and targetTop and targetHeight and viewHeight) or maxOffset <= 0 then
        return
    end

    -- Where the target sits inside the content, in pixels from the content
    -- top. Rect-based but offset-independent: the content and the target move
    -- together, so however far the pane is scrolled right now cancels out.
    local targetOffset = contentTop - targetTop

    -- Visibility is judged against the scroll's PENDING offset, not the
    -- screen: a restored offset can still be waiting on AceGUI's deferred
    -- FixScroll, which runs this same frame in no defined order with this
    -- fire, and the rects only show whichever applied first.
    local status = scroll.status or scroll.localstatus
    local pendingOffset = (status and status.offset) or 0
    if targetOffset >= pendingOffset
        and (targetOffset + targetHeight) <= (pendingOffset + viewHeight) then
        -- Ends up fully in view: the flash alone is the pointer.
        return
    end

    local desired = targetOffset - NAV_SCROLL_PAD
    if desired < 0 then desired = 0 end
    if desired > maxOffset then desired = maxOffset end
    local value = desired / maxOffset * 1000
    -- SetScroll writes the anchor AND the status, so a FixScroll landing
    -- after this rederives the same place; the scrollbar is synced so the
    -- knob tracks the jump (its OnValueChanged re-runs SetScroll, same value).
    scroll:SetScroll(value)
    if scroll.scrollBarShown and scroll.scrollbar then
        scroll.scrollbar:SetValue(value)
    end
end

------------------------------------------------------------------------
-- Place-preserving Panel <-> Entry lens handoff
------------------------------------------------------------------------

local function NormalizeLensAnchorKey(key)
    if type(key) == "string" and key:sub(1, 5) == "lens_" then
        return key:sub(6)
    end
    return key
end

local function BeginLensAnchorBuild(scroll)
    CS.lensAnchorRegistry = {
        scroll = scroll,
        panelId = CS.selectedGroup,
        tab = CS.selectedTab,
        headings = {},
        building = true,
    }
end

local function EndLensAnchorBuild()
    local registry = CS.lensAnchorRegistry
    if registry then
        registry.building = false
    end
end

RegisterLensAnchorHeading = function(widget, key)
    local registry = CS.lensAnchorRegistry
    if not (registry and registry.building and widget and key) then
        return
    end
    registry.headings[#registry.headings + 1] = {
        widget = widget,
        semanticKey = NormalizeLensAnchorKey(key),
    }
end

local function GetLensAnchorHeadingOffset(scroll, heading)
    local contentTop = scroll and scroll.content and scroll.content:GetTop()
    local frame = heading and heading.widget and heading.widget.frame
    local headingTop = frame and frame:GetTop()
    if not (contentTop and headingTop) then
        return nil
    end
    return contentTop - headingTop
end

local function CaptureLensAnchor()
    CS.pendingLensAnchor = nil
    if CS.pendingSettingHighlight then
        return nil
    end

    local registry = CS.lensAnchorRegistry
    local scroll = CS.col4Scroll
    if not (registry and registry.scroll == scroll and scroll and scroll.scrollframe) then
        return nil
    end

    local status = scroll.status or scroll.localstatus
    local offset = (status and status.offset) or 0
    local anchorIndex
    local anchorOffset
    local orderKeys = {}
    for index, heading in ipairs(registry.headings or {}) do
        orderKeys[index] = heading.semanticKey
        local headingOffset = GetLensAnchorHeadingOffset(scroll, heading)
        if headingOffset ~= nil then
            if not anchorIndex then
                anchorIndex = index
                anchorOffset = headingOffset
            end
            if headingOffset <= offset then
                anchorIndex = index
                anchorOffset = headingOffset
            end
        end
    end
    if not anchorIndex then
        return nil
    end

    CS.pendingLensAnchor = {
        panelId = registry.panelId,
        tab = registry.tab,
        semanticKey = orderKeys[anchorIndex],
        anchorIndex = anchorIndex,
        orderKeys = orderKeys,
        relativeOffset = anchorOffset - offset,
        rawOffset = offset,
    }
    return CS.pendingLensAnchor
end

local function FindLensAnchorDestination(registry, pending)
    local byKey = {}
    for _, heading in ipairs(registry.headings or {}) do
        if heading.semanticKey ~= nil and byKey[heading.semanticKey] == nil then
            byKey[heading.semanticKey] = heading
        end
    end
    if byKey[pending.semanticKey] then
        return byKey[pending.semanticKey]
    end

    local keys = pending.orderKeys or {}
    local index = pending.anchorIndex or 1
    for i = index + 1, #keys do
        if byKey[keys[i]] then
            return byKey[keys[i]]
        end
    end
    for i = index - 1, 1, -1 do
        if byKey[keys[i]] then
            return byKey[keys[i]]
        end
    end
    return nil
end

local function RestoreLensAnchor()
    local pending = CS.pendingLensAnchor
    CS.pendingLensAnchor = nil
    if not pending or CS.pendingSettingHighlight then
        return
    end

    local registry = CS.lensAnchorRegistry
    local scroll = registry and registry.scroll
    if not (registry and scroll and scroll.scrollframe and scroll.content
        and registry.panelId == pending.panelId
        and registry.tab == pending.tab
        and CS.selectedGroup == pending.panelId
        and CS.selectedTab == pending.tab) then
        return
    end

    local viewHeight = scroll.scrollframe:GetHeight() or 0
    local maxOffset = math.max(0, (scroll.content:GetHeight() or 0) - viewHeight)
    local desired = pending.rawOffset or 0
    local destination = FindLensAnchorDestination(registry, pending)
    local destinationOffset = destination
        and GetLensAnchorHeadingOffset(scroll, destination) or nil
    if destinationOffset ~= nil then
        desired = destinationOffset - (pending.relativeOffset or 0)
    end
    desired = math.max(0, math.min(desired, maxOffset))

    local value = maxOffset > 0 and (desired / maxOffset * 1000) or 0
    scroll:SetScroll(value)
    if scroll.scrollBarShown and scroll.scrollbar then
        scroll.scrollbar:SetValue(value)
    end
end

local function ScheduleLensAnchorRestore()
    local pending = CS.pendingLensAnchor
    if not pending or pending.scheduled then
        return
    end
    pending.scheduled = true
    C_Timer.After(0, RestoreLensAnchor)
end

local function FireNavSettingHighlight()
    local pending = CS.pendingSettingHighlight
    CS.pendingSettingHighlight = nil
    if not pending then
        return
    end
    local widget = pending.settingWidget or pending.rowWidget
        or pending.sectionRowWidget or pending.headingWidget
    local frame = widget and widget.frame
    if not (frame and frame:IsVisible()) then
        return
    end
    ScrollNavTargetIntoView(widget)

    local flash = EnsureNavFlashFrame()
    flash._animation:Stop()
    flash:SetParent(frame)
    flash:SetFrameLevel(frame:GetFrameLevel() + 5)
    flash:ClearAllPoints()
    flash:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -NAV_FLASH_INSET_V)
    flash:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, NAV_FLASH_INSET_V)
    flash:Show()
    flash._animation:Play()

    -- The row can be released out from under a playing flash by any rebuild
    -- (a tab click does not pass through the config refresh entry points), and
    -- its frame goes straight back into the pool for the next tenant. Chain,
    -- don't replace - and this registration is one-shot by nature: release
    -- wipes the widget's callbacks along with it.
    local prevOnRelease = widget.events and widget.events["OnRelease"]
    widget:SetCallback("OnRelease", function(w, event, ...)
        if prevOnRelease then
            prevOnRelease(w, event, ...)
        end
        if navFlashFrame and navFlashFrame:GetParent() == frame then
            StopNavSettingFlash()
        end
    end)
end

-- Called by the navigation writers AFTER their RefreshConfigPanel: the build
-- has recorded the target widgets, and one frame from now layout has settled.
local function ScheduleNavSettingHighlight()
    if CS.pendingSettingHighlight then
        C_Timer.After(0, FireNavSettingHighlight)
    end
end

-- Called at the top of every config rebuild. The rebuild the navigation
-- itself triggered is the request's first, and consumes it; any LATER rebuild
-- releases the recorded widgets back to the pool, so the request dies there
-- instead of flashing a recycled frame's next tenant.
local function BeginNavSettingHighlightRefresh()
    StopNavSettingFlash()
    local pending = CS.pendingSettingHighlight
    if pending then
        -- Explicit setting navigation owns this rebuild's semantic scroll.
        CS.pendingLensAnchor = nil
        pending.refreshCount = (pending.refreshCount or 0) + 1
        if pending.refreshCount > 1 then
            CS.pendingSettingHighlight = nil
        end
    end
end

ST._ScheduleNavSettingHighlight = ScheduleNavSettingHighlight
ST._BeginNavSettingHighlightRefresh = BeginNavSettingHighlightRefresh
ST._RecordSettingHighlightWidget = RecordSettingHighlightWidget
ST._BeginLensAnchorBuild = BeginLensAnchorBuild
ST._EndLensAnchorBuild = EndLensAnchorBuild
ST._CaptureLensAnchor = CaptureLensAnchor
ST._ScheduleLensAnchorRestore = ScheduleLensAnchorRestore

-- Private helpers consumed by later Helpers files.
SH.RegisterLensAnchorHeading = RegisterLensAnchorHeading
