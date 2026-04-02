--[[
    CooldownCompanion - Core/Changelog.lua
    Bundled changelog data service, version helpers, and lightweight markdown parsing.
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon

local rawData = ST._changelogData or {}
local orderedVersions = {}
local versionIndex = {}
local parsedCache = {}
local DEFAULT_FONT_SIZE = 13
local MIN_FONT_SIZE = 11
local MAX_FONT_SIZE = 18
local MAX_RECENT_DROPDOWN_VERSIONS = 5

local function Trim(text)
    text = tostring(text or "")
    text = text:gsub("^%s+", "")
    text = text:gsub("%s+$", "")
    return text
end

local BOLD_COLOR = "FFD100"
local ITALIC_COLOR = "9FD5E8"
local BOLD_ITALIC_COLOR = "FFE7A3"

local function WrapInlineColor(text, color)
    return "|cff" .. color .. text .. "|r"
end

local function ProcessInlineFormatting(text)
    if not text or text == "" then
        return text
    end

    text = text:gsub("%*%*%*(.-)%*%*%*", function(inner)
        return WrapInlineColor(inner, BOLD_ITALIC_COLOR)
    end)
    text = text:gsub("%*%*(.-)%*%*", function(inner)
        return WrapInlineColor(inner, BOLD_COLOR)
    end)
    text = text:gsub("%*(.-)%*", function(inner)
        return WrapInlineColor(inner, ITALIC_COLOR)
    end)

    return text
end

local function ExtractBulletStyle(text)
    text = Trim(text)
    if text == "" then
        return text, false
    end

    local bangText = text:match("^!%s+(.+)$")
    if bangText then
        return Trim(bangText), true
    end

    local bracketBangText = text:match("^%[!%]%s+(.+)$")
    if bracketBangText then
        return Trim(bracketBangText), true
    end

    return text, false
end

local function GetIndentWidth(leading)
    local width = 0
    for i = 1, #leading do
        local ch = leading:sub(i, i)
        if ch == "\t" then
            width = width + 2
        else
            width = width + 1
        end
    end
    return width
end

local function GetListDepth(leading)
    local width = GetIndentWidth(leading or "")
    if width <= 0 then
        return 0
    end
    return math.floor((width + 1) / 2)
end

local function BuildOrderedIndex()
    orderedVersions = {}
    versionIndex = {}

    local entries = rawData.entries or {}
    for _, version in ipairs(rawData.order or {}) do
        local entry = entries[version]
        if type(version) == "string" and type(entry) == "table" and type(entry.markdown) == "string" then
            orderedVersions[#orderedVersions + 1] = version
            versionIndex[version] = #orderedVersions
        end
    end
end

BuildOrderedIndex()

local function GetAddonVersion()
    return C_AddOns.GetAddOnMetadata(ADDON_NAME, "Version") or "unknown"
end

local function IsUnresolvedVersionToken(version)
    return type(version) == "string" and version:match("^@.+@$") ~= nil
end

local function ClampFontSize(size)
    size = tonumber(size)
    if not size then
        return DEFAULT_FONT_SIZE
    end
    size = math.floor(size + 0.5)
    if size < MIN_FONT_SIZE then
        return MIN_FONT_SIZE
    end
    if size > MAX_FONT_SIZE then
        return MAX_FONT_SIZE
    end
    return size
end

local function GetChangelogState()
    if not (CooldownCompanion and CooldownCompanion.db and CooldownCompanion.db.global) then
        return nil
    end

    local global = CooldownCompanion.db.global
    if type(global.changelog) ~= "table" then
        global.changelog = {}
    end

    return global.changelog
end

local function ParseMarkdown(markdown)
    local tokens = {}
    local paragraphLines = {}

    local function FlushParagraph()
        if #paragraphLines == 0 then
            return
        end

        local text = Trim(table.concat(paragraphLines, " "))
        paragraphLines = {}
        if text ~= "" then
            tokens[#tokens + 1] = {
                type = "paragraph",
                text = ProcessInlineFormatting(text),
            }
        end
    end

    markdown = tostring(markdown or "")
    markdown = markdown:gsub("\r\n", "\n")
    markdown = markdown:gsub("\r", "\n")

    for line in (markdown .. "\n"):gmatch("(.-)\n") do
        local trimmed = Trim(line)
        if trimmed == "" then
            FlushParagraph()
        else
            local heading3 = trimmed:match("^###%s+(.+)$")
            local heading2 = trimmed:match("^##%s+(.+)$")
            local bulletIndent, bullet = line:match("^(%s*)[-*]%s+(.+)$")
            local orderedIndent, orderedNumber, orderedBullet = line:match("^(%s*)(%d+)%.%s+(.+)$")

            if heading3 then
                FlushParagraph()
                tokens[#tokens + 1] = {
                    type = "heading3",
                    text = ProcessInlineFormatting(Trim(heading3)),
                }
            elseif heading2 then
                FlushParagraph()
                tokens[#tokens + 1] = {
                    type = "heading2",
                    text = ProcessInlineFormatting(Trim(heading2)),
                }
            elseif bullet then
                FlushParagraph()
                local bulletText, bulletImportant = ExtractBulletStyle(bullet)
                tokens[#tokens + 1] = {
                    type = "bullet",
                    depth = GetListDepth(bulletIndent),
                    important = bulletImportant,
                    text = ProcessInlineFormatting(bulletText),
                }
            elseif orderedBullet then
                FlushParagraph()
                local orderedText, orderedImportant = ExtractBulletStyle(orderedBullet)
                tokens[#tokens + 1] = {
                    type = "ordered_bullet",
                    depth = GetListDepth(orderedIndent),
                    index = tonumber(orderedNumber) or 1,
                    important = orderedImportant,
                    text = ProcessInlineFormatting(orderedText),
                }
            else
                paragraphLines[#paragraphLines + 1] = trimmed
            end
        end
    end

    FlushParagraph()

    return tokens
end

local Changelog = {}

function Changelog.GetAddonVersion()
    return GetAddonVersion()
end

function Changelog.GetDisplayAddonVersion()
    local version = GetAddonVersion()
    if IsUnresolvedVersionToken(version) then
        return "dev"
    end
    return version
end

function Changelog.GetOrderedVersions()
    local versions = {}
    for i, version in ipairs(orderedVersions) do
        versions[i] = version
    end
    return versions
end

function Changelog.GetDropdownVersions(selectedVersion)
    local versions = {}
    local seen = {}

    for i = 1, math.min(MAX_RECENT_DROPDOWN_VERSIONS, #orderedVersions) do
        local version = orderedVersions[i]
        versions[#versions + 1] = version
        seen[version] = true
    end

    if Changelog.HasEntry(selectedVersion) and not seen[selectedVersion] then
        versions[#versions + 1] = selectedVersion
    end

    return versions
end

function Changelog.HasEntry(version)
    version = tostring(version or "")
    return version ~= "" and rawData.entries and rawData.entries[version] ~= nil
end

function Changelog.GetNewestVersion()
    return orderedVersions[1]
end

function Changelog.GetEntry(version)
    if not Changelog.HasEntry(version) then
        return nil
    end
    return rawData.entries[version]
end

function Changelog.GetRenderTokens(version)
    if not Changelog.HasEntry(version) then
        return nil
    end
    if not parsedCache[version] then
        parsedCache[version] = ParseMarkdown(rawData.entries[version].markdown)
    end
    return parsedCache[version]
end

function Changelog.GetPreviousVersion(version)
    local idx = versionIndex[version]
    if not idx then
        return nil
    end
    return orderedVersions[idx + 1]
end

function Changelog.GetNextVersion(version)
    local idx = versionIndex[version]
    if not idx or idx <= 1 then
        return nil
    end
    return orderedVersions[idx - 1]
end

function Changelog.ShouldAutoOpen()
    local version = GetAddonVersion()
    if not Changelog.HasEntry(version) then
        return false, version
    end

    local state = GetChangelogState()
    local lastSeenVersion = state and state.lastSeenVersion or nil
    if lastSeenVersion == nil and state and not (CooldownCompanion and CooldownCompanion._hadSavedVariables) then
        state.lastSeenVersion = version
        return false, version
    end
    return lastSeenVersion ~= version, version
end

function Changelog.MarkSeen(version)
    version = tostring(version or GetAddonVersion() or "")
    if version == "" then
        return
    end

    local state = GetChangelogState()
    if not state then
        return
    end

    state.lastSeenVersion = version
end

function Changelog.GetFontSize()
    local state = GetChangelogState()
    return ClampFontSize(state and state.fontSize or nil)
end

function Changelog.SetFontSize(size)
    local state = GetChangelogState()
    if not state then
        return DEFAULT_FONT_SIZE
    end

    local clamped = ClampFontSize(size)
    state.fontSize = clamped
    return clamped
end

function Changelog.AdjustFontSize(delta)
    delta = tonumber(delta) or 0
    return Changelog.SetFontSize(Changelog.GetFontSize() + delta)
end

function Changelog.GetFontSizeBounds()
    return MIN_FONT_SIZE, MAX_FONT_SIZE
end

ST._GetAddonVersion = GetAddonVersion
ST._Changelog = Changelog
