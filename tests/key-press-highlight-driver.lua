local function ReadFile(path)
    local file = assert(io.open(path, "rb"))
    local text = file:read("*a")
    file:close()
    return text:gsub("\r\n", "\n"):gsub("\r", "\n")
end

local function Count(text, needle)
    local found = 0
    local index = 1
    while true do
        local startIndex = text:find(needle, index, true)
        if not startIndex then
            return found
        end
        found = found + 1
        index = startIndex + #needle
    end
end

local iconMode = ReadFile("CooldownCompanion/ButtonFrame/IconMode.lua")
local keybinds = ReadFile("CooldownCompanion/Core/Keybinds.lua")
local preview = ReadFile("CooldownCompanion/ButtonFrame/Preview.lua")
local groupFrame = ReadFile("CooldownCompanion/Core/GroupFrame.lua")
local groupOperations = ReadFile("CooldownCompanion/Core/GroupOperations.lua")

assert(iconMode:find("local kphButtons = {}", 1, true),
    "KPH driver should track enrolled buttons directly")
assert(iconMode:find("local kphButtonIndexes = {}", 1, true),
    "KPH driver should keep O(1) enrollment lookups")
assert(iconMode:find("local function KeyPressHighlightOnUpdate", 1, true),
    "KPH driver should have a named OnUpdate handler")
assert(iconMode:find("while index <= #kphButtons do", 1, true),
    "KPH driver should iterate the enrolled button registry")
assert(iconMode:find("kphUpdateFrame:SetScript(\"OnUpdate\", KeyPressHighlightOnUpdate)", 1, true),
    "KPH driver should start only when enrollment is non-empty")
assert(iconMode:find("kphUpdateFrame:SetScript(\"OnUpdate\", nil)", 1, true),
    "KPH driver should stop when enrollment becomes empty")
assert(iconMode:find("if #kphButtons == 0 then", 1, true),
    "KPH unregister should check for an empty registry")
assert(iconMode:find("StopKeyPressHighlightDriver()", 1, true),
    "KPH unregister should stop the driver after the last button leaves")
assert(not iconMode:find("kphUpdateFrame:SetScript(\"OnUpdate\", function", 1, true),
    "KPH driver should not install a permanent anonymous module-load OnUpdate")
assert(not iconMode:find("local groupFrames = CooldownCompanion.groupFrames", 1, true),
    "KPH driver should not scan every visible group frame each tick")

assert(iconMode:find("ST._RefreshKeyPressHighlightEnrollment = RefreshKeyPressHighlightEnrollment", 1, true),
    "IconMode should export button enrollment refresh")
assert(iconMode:find("ST._UnregisterKeyPressHighlightButton = UnregisterKeyPressHighlightButton", 1, true),
    "IconMode should export button unregister")
assert(not iconMode:find("ST._RefreshKeyPressHighlightFrame", 1, true),
    "IconMode should keep KPH frame iteration out of the shared API surface")
assert(not iconMode:find("ST._UnregisterKeyPressHighlightFrame", 1, true),
    "IconMode should keep KPH frame unregister out of the shared API surface")

assert(keybinds:find("local refresh = ST._RefreshKeyPressHighlightEnrollment", 1, true),
    "Keybind changes should notify KPH enrollment")
assert(keybinds:find("button._bindingKeyInfos = infos\n    RefreshKeyPressHighlightEnrollment(button)", 1, true),
    "Binding-key cache writes should refresh KPH enrollment")
assert(Count(keybinds, "button._bindingKeyInfos = infos") == 1,
    "Binding-key cache should write binding infos through one path")

assert(preview:find("local function RefreshKeyPressHighlightPreview(button)", 1, true),
    "Preview state changes should use a KPH-specific callback")
assert(preview:find("button._keyPressHighlightActive = false", 1, true),
    "KPH preview refresh should invalidate the cache without suppressing the hide path")
assert(not preview:find("RefreshKeyPressHighlightPreviewEnrollment", 1, true),
    "Generic preview helpers should not special-case KPH")
assert(Count(preview, "RefreshKeyPressHighlightPreview") >= 4,
    "KPH preview start, clear, and config preview paths should refresh enrollment")
assert(preview:find("local function ClearDormantKeyPressHighlightPreviews(self, groupId)", 1, true),
    "KPH preview clear should reconcile dormant-frame preview flags")
assert(preview:find("ClearDormantKeyPressHighlightPreviews(self, groupId)", 1, true),
    "Group KPH preview clear should clear dormant-frame preview flags")
assert(preview:find("ClearDormantKeyPressHighlightPreviews(self)", 1, true),
    "Global KPH preview clear should clear dormant-frame preview flags")
assert(Count(preview, "\"_keyPressHighlightActive\", false") >= 2,
    "KPH preview clear paths should use false cache invalidation so off calls hide")

assert(groupFrame:find("local unregister = ST._UnregisterKeyPressHighlightButton", 1, true),
    "Button repopulation should reach the KPH unregister hook")
assert(groupFrame:find("UnregisterKeyPressHighlightButton(button)", 1, true),
    "Existing buttons should leave KPH enrollment before release")

assert(groupOperations:find("local unregisterButton = ST._UnregisterKeyPressHighlightButton", 1, true),
    "Group unload/discard should reach the KPH button unregister hook")
assert(groupOperations:find("local cacheButtonBindingKeys = ST._CacheButtonBindingKeys", 1, true),
    "Dormant-frame recovery should rebuild cached binding keys before KPH enrollment")
assert(groupOperations:find("local refreshButton = ST._RefreshKeyPressHighlightEnrollment", 1, true),
    "Dormant-frame recovery should reach the KPH button refresh hook")
assert(groupOperations:find("cacheButtonBindingKeys(button, button.buttonData)", 1, true),
    "Recovered dormant buttons should refresh binding cache before enrollment")
assert(groupOperations:find("UnregisterKeyPressHighlightFrame(frame)", 1, true),
    "Unloaded or discarded frames should unregister KPH buttons")
assert(groupOperations:find("RefreshKeyPressHighlightFrame(frame)", 1, true),
    "Recovered dormant frames should refresh KPH enrollment")
assert(not groupOperations:find("if not self.db.profile.groups[groupId] then\n                self._dormantFrames[groupId] = nil", 1, true),
    "Deleted dormant groups should be discarded through the unregister-aware path")

print("key-press-highlight-driver ok")
