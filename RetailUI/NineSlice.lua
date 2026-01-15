--[[
NineSlice helper (3.3.5 compatible)

Usage:
local frame, slices = NineSlice:Create({
    parent  = UIParent,
    width   = 200,
    height  = 100,
    scale   = 1,
    offsets = { top = 5, bottom = -5, left = -4, right = 4 },
    textures = {
        TOP        = "UI-Frame-TOP",
        BOTTOM     = "UI-Frame-BOTTOM",
        LEFT       = "UI-Frame-LEFT",
        RIGHT      = "UI-Frame-RIGHT",
        TOPLEFT    = "UI-Frame-TOPLEFT",
        TOPRIGHT   = "UI-Frame-TOPRIGHT",
        BOTTOMLEFT = "UI-Frame-BOTTOMLEFT",
        BOTTOMRIGHT= "UI-Frame-BOTTOMRIGHT",
    },
})
]]

local NineSlice = {}
_G.NineSlice = NineSlice -- optional global export

local function SetAtlasTexture(texture, atlas)
    -- assumes you have your own atlas resolver elsewhere
    -- here we just support a raw texture path string
    if type(atlas) == "string" and atlas ~= "" then
        texture:SetTexture(atlas)
    end
end

local function CreateEdgeTexture(frame, layer, point, relPoint, x, y, atlas)
    local tex = frame:CreateTexture(nil, layer)
    tex:SetPoint(point, frame, relPoint or point, x or 0, y or 0)
    SetAtlasTexture(tex, atlas)
    return tex
end

function NineSlice:Create(config)
    local parent   = config.parent or UIParent
    local width    = config.width or 128
    local height   = config.height or 64
    local scale    = config.scale or 1
    local textures = config.textures or {}
    local offsets  = config.offsets or {}

    local topOffset    = offsets.top    or 0
    local bottomOffset = offsets.bottom or 0
    local leftOffset   = offsets.left   or 0
    local rightOffset  = offsets.right  or 0

    local frame = CreateFrame("Frame", nil, parent)
    frame:SetSize(width, height)

    local slices = {}

    -- Corners
    slices.TOPLEFT = CreateEdgeTexture(frame, "BORDER", "TOPLEFT", nil, leftOffset,  topOffset,    textures.TOPLEFT)
    slices.TOPRIGHT = CreateEdgeTexture(frame, "BORDER", "TOPRIGHT", nil, rightOffset, topOffset,   textures.TOPRIGHT)
    slices.BOTTOMLEFT = CreateEdgeTexture(frame, "BORDER", "BOTTOMLEFT", nil, leftOffset, bottomOffset, textures.BOTTOMLEFT)
    slices.BOTTOMRIGHT = CreateEdgeTexture(frame, "BORDER", "BOTTOMRIGHT", nil, rightOffset, bottomOffset, textures.BOTTOMRIGHT)

    slices.TOPLEFT:SetSize(slices.TOPLEFT:GetWidth() * scale, slices.TOPLEFT:GetHeight() * scale)
    slices.TOPRIGHT:SetSize(slices.TOPRIGHT:GetWidth() * scale, slices.TOPRIGHT:GetHeight() * scale)
    slices.BOTTOMLEFT:SetSize(slices.BOTTOMLEFT:GetWidth() * scale, slices.BOTTOMLEFT:GetHeight() * scale)
    slices.BOTTOMRIGHT:SetSize(slices.BOTTOMRIGHT:GetWidth() * scale, slices.BOTTOMRIGHT:GetHeight() * scale)

    -- Edges
    slices.TOP = CreateEdgeTexture(frame, "BORDER", "TOP", nil, 0, topOffset, textures.TOP)
    slices.TOP:SetHorizTile(true)
    slices.TOP:SetSize(width - slices.TOPLEFT:GetWidth() - slices.TOPRIGHT:GetWidth(), slices.TOP:GetHeight() * scale)
    slices.TOP:ClearAllPoints()
    slices.TOP:SetPoint("TOPLEFT", slices.TOPLEFT, "TOPRIGHT", 0, 0)
    slices.TOP:SetPoint("TOPRIGHT", slices.TOPRIGHT, "TOPLEFT", 0, 0)

    slices.BOTTOM = CreateEdgeTexture(frame, "BORDER", "BOTTOM", nil, 0, bottomOffset, textures.BOTTOM)
    slices.BOTTOM:SetHorizTile(true)
    slices.BOTTOM:SetSize(width - slices.BOTTOMLEFT:GetWidth() - slices.BOTTOMRIGHT:GetWidth(), slices.BOTTOM:GetHeight() * scale)
    slices.BOTTOM:ClearAllPoints()
    slices.BOTTOM:SetPoint("BOTTOMLEFT", slices.BOTTOMLEFT, "BOTTOMRIGHT", 0, 0)
    slices.BOTTOM:SetPoint("BOTTOMRIGHT", slices.BOTTOMRIGHT, "BOTTOMLEFT", 0, 0)

    slices.LEFT = CreateEdgeTexture(frame, "BORDER", "LEFT", nil, leftOffset, 0, textures.LEFT)
    slices.LEFT:SetSize(slices.LEFT:GetWidth() * scale, height - slices.TOPLEFT:GetHeight() - slices.BOTTOMLEFT:GetHeight())
    slices.LEFT:ClearAllPoints()
    slices.LEFT:SetPoint("TOPLEFT", slices.TOPLEFT, "BOTTOMLEFT", 0, 0)
    slices.LEFT:SetPoint("BOTTOMLEFT", slices.BOTTOMLEFT, "TOPLEFT", 0, 0)

    slices.RIGHT = CreateEdgeTexture(frame, "BORDER", "RIGHT", nil, rightOffset, 0, textures.RIGHT)
    slices.RIGHT:SetSize(slices.RIGHT:GetWidth() * scale, height - slices.TOPRIGHT:GetHeight() - slices.BOTTOMRIGHT:GetHeight())
    slices.RIGHT:ClearAllPoints()
    slices.RIGHT:SetPoint("TOPRIGHT", slices.TOPRIGHT, "BOTTOMRIGHT", 0, 0)
    slices.RIGHT:SetPoint("BOTTOMRIGHT", slices.BOTTOMRIGHT, "TOPRIGHT", 0, 0)

    frame.slices = slices
    return frame, slices
end

-- Backwards‑compatible helper to match the original signature
function CreateNineSliceFrame(width, height, textureInfos, scale)
    local frame = NineSlice:Create({
        parent   = UIParent,
        width    = width,
        height   = height,
        textures = textureInfos,
        scale    = scale or 1,
        offsets  = { top = 5, bottom = -5, left = -4, right = 4 },
    })
    return frame
end
