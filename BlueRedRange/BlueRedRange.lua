-- BlueRedRange: simple out-of-range / out-of-power overlays for 3.3.5

local UPDATE_DELAY            = 0.15

local ActionButton_GetPagedID = ActionButton_GetPagedID
local HasAction               = HasAction
local ActionHasRange          = ActionHasRange
local IsActionInRange         = IsActionInRange
local IsUsableAction          = IsUsableAction

local _G                      = _G
local buttons                 = {}
local elapsedSinceUpdate      = 0

local function GetButtonIcon(button)
    local icon = button.icon
    if not icon and button.GetName then
        icon = _G[button:GetName() .. "Icon"]
    end
    return icon
end

local function CreateOverlay(button)
    if button.BRR_Overlay then return button.BRR_Overlay end

    local icon = GetButtonIcon(button)
    if not icon then return nil end

    -- create the overlay on the button (a frame), not on the texture
    local tex = button:CreateTexture(nil, "ARTWORK")
    tex:SetAllPoints(icon)
    tex:SetTexture(0, 0, 0, 0) -- fully transparent initially

    button.BRR_Overlay = tex
    return tex
end

local function UpdateButtonState(button)
    local action  = ActionButton_GetPagedID(button)
    local overlay = CreateOverlay(button)

    if not overlay then
        return
    end

    if not action or not HasAction(action) then
        overlay:SetTexture(0, 0, 0, 0)
        return
    end

    local isUsable, notEnoughMana = IsUsableAction(action)

    if not isUsable and notEnoughMana then
        overlay:SetTexture(0, 0, 1, 0.4)
    else
        if not ActionHasRange(action) then
            overlay:SetTexture(0, 0, 0, 0)
            return
        end

        local inRange = IsActionInRange(action)
        if inRange == 0 then
            overlay:SetTexture(1, 0, 0, 0.4)
        else
            overlay:SetTexture(0, 0, 0, 0)
        end
    end
end

local function UpdateAllButtons(delta)
    if not next(buttons) then return end

    elapsedSinceUpdate = elapsedSinceUpdate + delta
    if elapsedSinceUpdate < UPDATE_DELAY then return end
    elapsedSinceUpdate = 0

    for button in pairs(buttons) do
        if button:IsVisible() then
            UpdateButtonState(button)
        end
    end
end

-- hook any action button as it updates
local function RegisterButton(button)
    if buttons[button] then return end

    buttons[button] = true

    button:HookScript("OnShow", function(self)
        UpdateButtonState(self)
    end)
    button:HookScript("OnHide", function(self)
        local overlay = self.BRR_Overlay
        if overlay then
            overlay:SetTexture(0, 0, 0, 0)
        end
    end)

    UpdateButtonState(button)
end

hooksecurefunc("ActionButton_OnUpdate", function(button)
    RegisterButton(button)
end)

hooksecurefunc("ActionButton_Update", function(button)
    if buttons[button] then
        UpdateButtonState(button)
    end
end)

hooksecurefunc("ActionButton_UpdateUsable", function(button)
    if buttons[button] then
        UpdateButtonState(button)
    end
end)

-- heartbeat frame
local f = CreateFrame("Frame")
f:SetScript("OnUpdate", function(_, delta)
    UpdateAllButtons(delta)
end)
