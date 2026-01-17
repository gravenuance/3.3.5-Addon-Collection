local ADDONNAME, addon = ...

local _, class = UnitClass("player")
if class ~= "ROGUE" and class ~= "DRUID" then
    return
end

local NUMPOINTS   = 5
local SIZE        = 14
local GAP         = 1

local ComboPoints = {}
addon.ComboPoints = ComboPoints

function ComboPoints:Create(parent)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetSize(SIZE * NUMPOINTS + GAP * (NUMPOINTS - 1), SIZE)
    frame:SetFrameLevel(parent:GetFrameLevel() + 10)
    local points, fills = {}, {}

    for i = 1, NUMPOINTS do
        local bg = frame:CreateTexture(nil, "BACKGROUND")
        bg:SetSize(SIZE, SIZE)
        if i == 1 then
            bg:SetPoint("LEFT", frame, "LEFT", 0, -4)
        else
            bg:SetPoint("LEFT", points[i - 1], "RIGHT", GAP, 0)
        end
        bg:SetTexture("Interface\\Addons\\CompactNameplates\\Textures\\round-empty")
        bg:SetVertexColor(0.1, 0.1, 0.1, 0.8)
        points[i] = bg

        local fill = frame:CreateTexture(nil, "ARTWORK")
        fill:SetAllPoints(bg)
        fill:SetTexture("Interface\\Addons\\CompactNameplates\\Textures\\round")
        fill:SetVertexColor(1, 0.8, 0, 1)
        fill:Hide()
        fills[i] = fill
    end

    frame.points = points
    frame.fills  = fills
    frame:Hide()

    return frame
end

function ComboPoints:Update(frame, isTarget)
    if not isTarget or not UnitExists("target") or UnitIsDead("target") then
        frame:Hide()
        return
    end

    local cp = GetComboPoints("player", "target") or 0

    for i = 1, #frame.fills do
        if i <= cp and cp > 0 then
            frame.fills[i]:Show()
        else
            frame.fills[i]:Hide()
        end
    end

    -- Always show on a valid target, even at 0 combo points
    frame:Show()
end
