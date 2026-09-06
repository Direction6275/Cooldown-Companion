--[[
    CooldownCompanion - GroupMedia
    Shared-media lookup and profile-wide font, texture, and border controls.

    Part of the GroupOperations family; see its ordered block in the addon TOC.
    Public methods attach to ST.Addon; local state stays with its owner.
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon
local type = type

-- LibSharedMedia for font/texture selection
local LSM = LibStub("LibSharedMedia-3.0")

function CooldownCompanion:FetchFont(name)
    local effectiveName = ST.GetEffectiveFontName and ST.GetEffectiveFontName(name) or name
    if effectiveName and (not LSM.IsValid or LSM:IsValid("font", effectiveName)) then
        local font = LSM:Fetch("font", effectiveName)
        if font then
            return font
        end
    end
    return LSM:Fetch("font", ST.DEFAULT_FONT_NAME or "Friz Quadrata TT") or STANDARD_TEXT_FONT
end

function CooldownCompanion:FetchStatusBar(name)
    return LSM:Fetch("statusbar", name) or LSM:Fetch("statusbar", "Solid") or [[Interface\BUTTONS\WHITE8X8]]
end

function CooldownCompanion:FetchEffectiveBarTexture(name)
    local effectiveName = ST.GetEffectiveBarTextureName and ST.GetEffectiveBarTextureName(name) or name
    return self:FetchStatusBar(effectiveName)
end

-- Re-apply all media after a SharedMedia pack registers new fonts/textures
function CooldownCompanion:RefreshAllMedia()
    -- SharedMedia registrations from other addons can fire during startup before
    -- the aura texture runtime has finished attaching its visual methods.
    if type(self.UpdateAuraTextureVisual) ~= "function"
        or type(self.HideAuraTextureVisual) ~= "function" then
        return
    end

    self:RefreshAllGroups()
    self:EvaluateBarsAndFramesRuntime("shared-media")
end

local function RefreshProfileWideVisuals(addon, reason, opts, refreshAuraTextures)
    if addon.RefreshAllGroups then
        addon:RefreshAllGroups()
    end
    if addon.EvaluateBarsAndFramesRuntime then
        addon:EvaluateBarsAndFramesRuntime(reason)
    end
    if refreshAuraTextures ~= false and addon.RefreshAllAuraTextureVisuals then
        addon:RefreshAllAuraTextureVisuals()
    end
    if not opts or opts.refreshConfig ~= false then
        if addon.RefreshConfigPanel then
            addon:RefreshConfigPanel()
        end
    end
end

function CooldownCompanion:ApplyProfileOnePixelBorderMode(opts)
    RefreshProfileWideVisuals(self, "profile-border-mode", opts)
end

function CooldownCompanion:SetProfileOnePixelBordersEnabled(enabled, opts)
    local profile = self.db and self.db.profile
    if not profile then return false end
    profile.profileOnePixelBorders = enabled == true
    self:ApplyProfileOnePixelBorderMode(opts)
    return true
end

function CooldownCompanion:ApplyProfileWideFontMode(opts)
    RefreshProfileWideVisuals(self, "profile-font-mode", opts)
end

local function InitializeProfileWideFontDefaults(profile)
    local initialized = false
    if type(profile.profileWideFontName) ~= "string" or profile.profileWideFontName == "" then
        profile.profileWideFontName = ST.DEFAULT_FONT_NAME or "Friz Quadrata TT"
        initialized = true
    end
    if type(profile.profileWideFontOutline) ~= "string" then
        profile.profileWideFontOutline = ST.DEFAULT_FONT_OUTLINE or "OUTLINE"
        initialized = true
    end
    return initialized
end

function CooldownCompanion:SetProfileWideFontEnabled(enabled, opts)
    local profile = self.db and self.db.profile
    if not profile then return false end

    local target = enabled == true
    local changed = profile.profileWideFontEnabled ~= target
    profile.profileWideFontEnabled = target

    local initialized = target and InitializeProfileWideFontDefaults(profile)

    if changed or initialized then
        self:ApplyProfileWideFontMode(opts)
    end
    return true
end

function CooldownCompanion:SetProfileWideFontName(fontName, opts)
    local profile = self.db and self.db.profile
    if not profile or type(fontName) ~= "string" or fontName == "" then
        return false
    end

    local changed = profile.profileWideFontName ~= fontName
    if changed then
        profile.profileWideFontName = fontName
    end

    local enableChanged = false
    if opts and opts.enable == true and profile.profileWideFontEnabled ~= true then
        profile.profileWideFontEnabled = true
        enableChanged = true
        InitializeProfileWideFontDefaults(profile)
    end

    if changed or enableChanged then
        self:ApplyProfileWideFontMode(opts)
    end
    return true
end

function CooldownCompanion:SetProfileWideFontOutline(outline, opts)
    local profile = self.db and self.db.profile
    if not profile or type(outline) ~= "string" then
        return false
    end
    outline = ST.NormalizeFontOutline(outline)

    local changed = profile.profileWideFontOutline ~= outline
    if changed then
        profile.profileWideFontOutline = outline
    end

    local enableChanged = false
    if opts and opts.enable == true and profile.profileWideFontEnabled ~= true then
        profile.profileWideFontEnabled = true
        enableChanged = true
        InitializeProfileWideFontDefaults(profile)
    end

    if changed or enableChanged then
        self:ApplyProfileWideFontMode(opts)
    end
    return true
end

function CooldownCompanion:ApplyProfileWideBarTextureMode(opts)
    RefreshProfileWideVisuals(self, "profile-bar-texture-mode", opts, false)
end

local function InitializeProfileWideBarTextureDefaults(profile)
    if type(profile.profileWideBarTextureName) ~= "string" or profile.profileWideBarTextureName == "" then
        profile.profileWideBarTextureName = "Solid"
        return true
    end
    return false
end

function CooldownCompanion:SetProfileWideBarTextureEnabled(enabled, opts)
    local profile = self.db and self.db.profile
    if not profile then return false end

    local target = enabled == true
    local changed = profile.profileWideBarTextureEnabled ~= target
    profile.profileWideBarTextureEnabled = target

    local initialized = target and InitializeProfileWideBarTextureDefaults(profile)

    if changed or initialized then
        self:ApplyProfileWideBarTextureMode(opts)
    end
    return true
end

function CooldownCompanion:SetProfileWideBarTextureName(textureName, opts)
    local profile = self.db and self.db.profile
    if not profile or type(textureName) ~= "string" or textureName == "" then
        return false
    end

    local changed = profile.profileWideBarTextureName ~= textureName
    if changed then
        profile.profileWideBarTextureName = textureName
    end

    local enableChanged = false
    if opts and opts.enable == true and profile.profileWideBarTextureEnabled ~= true then
        profile.profileWideBarTextureEnabled = true
        enableChanged = true
        InitializeProfileWideBarTextureDefaults(profile)
    end

    if changed or enableChanged then
        self:ApplyProfileWideBarTextureMode(opts)
    end
    return true
end
