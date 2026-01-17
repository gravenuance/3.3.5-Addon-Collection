local addonName = ...
local DISPellableTypes = {
    Magic   = true,
    Curse   = true,
    Disease = true,
    Poison  = true,
}

local function CreateDispelIcon(frame)
    if frame.DispelIcon then return end

    local size = frame:GetHeight() * 0.8 -- slightly smaller than frame
    local icon = CreateFrame("Frame", nil, frame)
    icon:SetSize(size, size)
    icon:SetPoint("LEFT", frame, "RIGHT", 2, 0) -- right side

    local tex = icon:CreateTexture(nil, "ARTWORK")
    tex:SetAllPoints()
    tex:SetTexCoord(0.08, 0.92, 0.08, 0.92) -- zoomed in
    icon.icon = tex

    -- Simple blue border; replace with a textured border if desired
    local border = icon:CreateTexture(nil, "OVERLAY")
    border:SetPoint("TOPLEFT", -1, 1)
    border:SetPoint("BOTTOMRIGHT", 1, -1)
    border:SetColorTexture(0, 0.44, 1, 1)
    icon.border = border

    icon:Hide()
    frame.DispelIcon = icon
end

local function UpdateDispelIcon(frame)
    local iconFrame = frame.DispelIcon
    if not iconFrame then return end

    local unit = frame.displayedUnit or frame.unit
    if not unit or not UnitExists(unit) then
        iconFrame:Hide()
        return
    end

    local bestTexture
    local bestRemaining = -1

    local index = 1
    while true do
        -- On 3.3.5 you typically only have the classic UnitDebuff(unit, index) form.
        local name, _, texture, _, debuffType, duration, expirationTime = UnitDebuff(unit, index)
        if not name then break end

        if debuffType and DISPellableTypes[debuffType] then
            local remaining = 0
            if duration and duration > 0 and expirationTime then
                remaining = expirationTime - GetTime()
            end

            if remaining > bestRemaining then
                bestRemaining = remaining
                bestTexture = texture
            end
        end

        index = index + 1
    end

    if bestTexture then
        iconFrame.icon:SetTexture(bestTexture)
        iconFrame:Show()
    else
        iconFrame:Hide()
    end
end

local function DispelIcon_OnEvent(frame, event, unit)
    if unit and unit ~= frame.unit and unit ~= frame.displayedUnit then
        return
    end

    if event == "UNIT_AURA" or event == "UNIT_FLAGS" or event == "PLAYER_TALENT_UPDATE" then
        UpdateDispelIcon(frame)
    end
end

hooksecurefunc("CompactUnitFrame_OnLoad", function(frame)
    -- Only for frames that actually represent units
    if not frame or (not frame.unit and not frame.displayedUnit) then return end

    CreateDispelIcon(frame)
    frame:HookScript("OnEvent", DispelIcon_OnEvent)
end)

hooksecurefunc("CompactUnitFrame_UpdateAll", function(frame)
    if frame and frame.DispelIcon then
        UpdateDispelIcon(frame)
    end
end)
