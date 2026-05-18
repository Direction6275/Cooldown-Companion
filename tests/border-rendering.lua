local ST = {}

PixelUtil = {
    nearestCalls = {},
    pointCalls = {},
}

function PixelUtil.GetNearestPixelSize(uiUnitSize, layoutScale, minPixels)
    table.insert(PixelUtil.nearestCalls, {
        uiUnitSize = uiUnitSize,
        layoutScale = layoutScale,
        minPixels = minPixels,
    })
    return 0.5
end

function PixelUtil.SetPoint(region, point, relativeTo, relativePoint, offsetX, offsetY, minOffsetXPixels, minOffsetYPixels)
    table.insert(PixelUtil.pointCalls, {
        region = region,
        point = point,
        relativeTo = relativeTo,
        relativePoint = relativePoint,
        offsetX = offsetX,
        offsetY = offsetY,
        minOffsetXPixels = minOffsetXPixels,
        minOffsetYPixels = minOffsetYPixels,
    })
    region:SetPoint(point, relativeTo, relativePoint, offsetX, offsetY)
end

local function assertEquals(actual, expected, label)
    if actual ~= expected then
        error(string.format("%s: expected %s, got %s", label, tostring(expected), tostring(actual)), 2)
    end
end

local function assertTrue(value, label)
    if not value then
        error(label, 2)
    end
end

local function NewTexture()
    return {
        shown = false,
        points = {},
        color = nil,
        SetColorTexture = function(self, r, g, b, a)
            self.color = { r, g, b, a }
        end,
        Hide = function(self)
            self.shown = false
        end,
        Show = function(self)
            self.shown = true
        end,
        ClearAllPoints = function(self)
            self.points = {}
        end,
        SetPoint = function(self, point, relativeTo, relativePoint, offsetX, offsetY)
            table.insert(self.points, {
                point = point,
                relativeTo = relativeTo,
                relativePoint = relativePoint,
                offsetX = offsetX,
                offsetY = offsetY,
            })
        end,
    }
end

local function NewRegion()
    local region = {
        textures = {},
        scale = 2,
    }
    function region:GetEffectiveScale()
        return self.scale
    end
    function region:CreateTexture()
        local texture = NewTexture()
        table.insert(self.textures, texture)
        return texture
    end
    return region
end

local chunk = assert(loadfile("Core/Utils.lua"))
chunk("CooldownCompanion", ST)

assertEquals(ST.GetBorderRenderMode(nil), ST.BORDER_RENDER_MODE_CUSTOM, "nil render mode defaults to custom")
assertEquals(ST.GetBorderRenderMode("unexpected"), ST.BORDER_RENDER_MODE_CUSTOM, "invalid render mode defaults to custom")
assertEquals(ST.GetBorderRenderMode(ST.BORDER_RENDER_MODE_CRISP), ST.BORDER_RENDER_MODE_CRISP, "crisp render mode is preserved")
assertEquals(ST.GetBorderRenderMode({ textBorderRenderMode = ST.BORDER_RENDER_MODE_CRISP }, "textBorderRenderMode"), ST.BORDER_RENDER_MODE_CRISP, "table render mode key is supported")

local region = NewRegion()
assertEquals(ST.GetBorderLayoutSize(region, 2.25, ST.BORDER_RENDER_MODE_CUSTOM), 2.25, "custom layout size uses configured value")
assertEquals(ST.GetBorderLayoutSize(region, 2.25, ST.BORDER_RENDER_MODE_CRISP), 0.5, "crisp layout size uses PixelUtil")
assertEquals(PixelUtil.nearestCalls[#PixelUtil.nearestCalls].layoutScale, 2, "crisp layout uses effective scale")

local textures = ST.CreateBorderTextureSet(region)
assertEquals(#textures, 4, "border texture set has numeric entries")
assertTrue(textures[1] == textures.TOP, "border texture set exposes named top alias")
assertTrue(textures[4] == textures.RIGHT, "border texture set exposes named right alias")

ST.ApplyBorderTextures(textures, region, { 1, 0.5, 0.25, 0.75 }, 0, ST.BORDER_RENDER_MODE_CUSTOM)
for index = 1, 4 do
    assertEquals(textures[index].shown, false, "custom zero border hides texture " .. index)
end

ST.ApplyBorderTextures(textures, region, { 0, 1, 0, 1 }, 0, ST.BORDER_RENDER_MODE_CRISP)
for index = 1, 4 do
    assertEquals(textures[index].shown, true, "crisp border shows texture " .. index)
end
assertTrue(#PixelUtil.pointCalls > 0, "crisp positioning uses PixelUtil.SetPoint")

print("border rendering helper tests passed")
