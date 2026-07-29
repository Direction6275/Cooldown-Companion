--[[
    CooldownCompanion - Config/DragReorder
    Split shell for drag-and-drop reordering.

    Concern modules:
    - DragReorderTargets.lua: drop-target resolution, indicators, and reorder primitives.
    - DragReorderLifecycle.lua: drag lifecycle, drop application, and public exports.

    Navigator drags are shown with a single insertion line, not an animated
    preview. The previous DragReorderPreview.lua rebuilt a proxy copy of the
    whole column because AceGUI owns the real rows' positions and they cannot be
    moved; keeping that copy in step with the widgets it mirrored was the source
    of its bugs. Do not reintroduce one while Column 1 is built from AceGUI
    widgets.
]]
