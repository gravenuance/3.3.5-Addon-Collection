-- BlizzMove, move the Blizzard frames by yess

local addonName = ...
local BlizzMove = {}
_G.BlizzMove = BlizzMove

local db
local frame       = CreateFrame("Frame")
local optionPanel = nil

-- default settings for frames that should be saved by default
local defaultDB = {
    AchievementFrame = { save = true },
    CalendarFrame    = { save = true },
    AuctionFrame     = { save = true },
    GuildBankFrame   = { save = true },
}

-------------------------------------------------
-- Utility / debugging
-------------------------------------------------

local function Print(...)
    local s = "BlizzMove:"
    for i = 1, select("#", ...) do
        local x = select(i, ...)
        s = strjoin(" ", s, tostring(x))
    end
    DEFAULT_CHAT_FRAME:AddMessage(s)
end

local debug = false

local function Debug(...)
    if debug then
        Print(...)
    end
end

-------------------------------------------------
-- Frame movement helpers
-------------------------------------------------

local function OnShow(self)
    local settings = self.settings
    if settings and settings.point and settings.save then
        self:ClearAllPoints()
        self:SetPoint(
            settings.point,
            settings.relativeTo,
            settings.relativePoint,
            settings.xOfs,
            settings.yOfs
        )

        local scale = settings.scale
        if scale then
            self:SetScale(scale)
        end
    end
end

local function OnMouseWheel(self, delta)
    if not IsControlKeyDown() then
        return
    end

    local frameToMove = self.frameToMove
    if not frameToMove then
        return
    end

    local scale = frameToMove:GetScale() or 1
    if delta == 1 then
        scale = scale + 0.1
        if scale > 1.5 then
            scale = 1.5
        end
    else
        scale = scale - 0.1
        if scale < 0.5 then
            scale = 0.5
        end
    end

    frameToMove:SetScale(scale)

    if self.settings then
        self.settings.scale = scale
    end
end

local function OnDragStart(self)
    local frameToMove = self.frameToMove
    if not frameToMove then return end

    local settings = frameToMove.settings
    if settings and not settings.default then
        settings.default = {}
        local def = settings.default
        def.point, def.relativeTo, def.relativePoint, def.xOfs, def.yOfs =
            frameToMove:GetPoint()

        if def.relativeTo then
            def.relativeTo = def.relativeTo:GetName()
        end
    end

    frameToMove:StartMoving()
    frameToMove.isMoving = true
end

local function OnDragStop(self)
    local frameToMove = self.frameToMove
    if not frameToMove then return end

    local settings = frameToMove.settings

    frameToMove:StopMovingOrSizing()
    frameToMove.isMoving = false

    if settings then
        settings.point, settings.relativeTo, settings.relativePoint,
        settings.xOfs, settings.yOfs = frameToMove:GetPoint()
    end
end

local function OnMouseUp(self)
    if not IsControlKeyDown() then
        return
    end

    local frameToMove = self.frameToMove
    if not frameToMove then
        return
    end

    local settings = frameToMove.settings

    -- toggle save
    if settings then
        settings.save = not settings.save
        if settings.save then
            Print("Frame:", frameToMove:GetName(), "will be saved.")
        else
            Print("Frame:", frameToMove:GetName(), "will be not saved.")
        end
    else
        Print("Frame:", frameToMove:GetName(), "will be saved.")
        local name = frameToMove:GetName()
        db[name] = {}
        settings = db[name]
        settings.save = true
        settings.point, settings.relativeTo, settings.relativePoint,
        settings.xOfs, settings.yOfs = frameToMove:GetPoint()

        if settings.relativeTo then
            settings.relativeTo = settings.relativeTo:GetName()
        end

        frameToMove.settings = settings
    end
end

local function SetMoveHandler(frameToMove, handler)
    if not frameToMove then
        return
    end

    handler = handler or frameToMove

    local name = frameToMove:GetName()
    if not name then
        return
    end

    local settings = db[name]
    if not settings then
        settings = defaultDB[name] or {}
        db[name] = settings
    end

    frameToMove.settings = settings
    handler.frameToMove  = frameToMove
    handler.settings     = settings

    if not frameToMove.EnableMouse then
        return
    end

    frameToMove:EnableMouse(true)
    frameToMove:SetMovable(true)

    handler:RegisterForDrag("LeftButton")
    handler:SetScript("OnDragStart", OnDragStart)
    handler:SetScript("OnDragStop", OnDragStop)

    -- override frame position according to settings when shown
    frameToMove:HookScript("OnShow", OnShow)

    -- hook OnMouseUp
    handler:HookScript("OnMouseUp", OnMouseUp)

    -- hook Scroll for setting scale
    handler:EnableMouseWheel(true)
    handler:HookScript("OnMouseWheel", OnMouseWheel)
end

-------------------------------------------------
-- Reset database
-------------------------------------------------

local function resetDB()
    for k, _ in pairs(db) do
        local f = _G[k]
        if f and f.settings then
            f.settings.save = false
            local def = f.settings.default
            if def then
                f:ClearAllPoints()
                f:SetPoint(def.point, def.relativeTo, def.relativePoint, def.xOfs, def.yOfs)
            end
        end
    end
end

-------------------------------------------------
-- Options panel
-------------------------------------------------

local function createOptionPanel()
    optionPanel = CreateFrame("Frame", "BlizzMovePanel", UIParent)

    local title = optionPanel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)

    local version = GetAddOnMetadata("BlizzMove", "Version") or ""
    title:SetText("BlizzMove " .. version)

    local subtitle = optionPanel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    subtitle:SetHeight(35)
    subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    subtitle:SetPoint("RIGHT", optionPanel, -32, 0)
    subtitle:SetNonSpaceWrap(true)
    subtitle:SetJustifyH("LEFT")
    subtitle:SetJustifyV("TOP")
    subtitle:SetText("Click the button below to reset all frames.")

    local button = CreateFrame("Button", nil, optionPanel, "UIPanelButtonTemplate")
    button:SetWidth(100)
    button:SetHeight(30)
    button:SetScript("OnClick", resetDB)
    button:SetText("Reset")
    button:SetPoint("TOPLEFT", 20, -60)

    optionPanel.name = "BlizzMove"
    InterfaceOptions_AddCategory(optionPanel)
end

-------------------------------------------------
-- Event handler
-------------------------------------------------

local function OnEvent(self, event, arg1)
    Debug(event, arg1)

    if event == "PLAYER_ENTERING_WORLD" then
        self:RegisterEvent("ADDON_LOADED") -- for Blizzard LoD addons

        db = BlizzMoveDB or defaultDB
        BlizzMoveDB = db

        -- core frames
        SetMoveHandler(CharacterFrame, PaperDollFrame)
        SetMoveHandler(CharacterFrame, TokenFrame)
        SetMoveHandler(CharacterFrame, SkillFrame)
        SetMoveHandler(CharacterFrame, ReputationFrame)
        SetMoveHandler(CharacterFrame, PetPaperDollFrameCompanionFrame)

        SetMoveHandler(SpellBookFrame)
        SetMoveHandler(QuestLogFrame)
        SetMoveHandler(FriendsFrame)
        SetMoveHandler(PVPParentFrame)
        SetMoveHandler(LFGParentFrame)
        SetMoveHandler(GameMenuFrame)
        SetMoveHandler(GossipFrame)
        SetMoveHandler(DressUpFrame)
        SetMoveHandler(QuestFrame)
        SetMoveHandler(MerchantFrame)
        SetMoveHandler(HelpFrame)
        SetMoveHandler(PlayerTalentFrame)
        SetMoveHandler(ClassTrainerFrame)
        SetMoveHandler(MailFrame)
        SetMoveHandler(BankFrame)
        SetMoveHandler(VideoOptionsFrame)
        SetMoveHandler(InterfaceOptionsFrame)
        SetMoveHandler(LootFrame)
        SetMoveHandler(LFDParentFrame)
        SetMoveHandler(LFRParentFrame)
        SetMoveHandler(TradeFrame)

        InterfaceOptionsFrame:HookScript("OnShow", function()
            if not optionPanel then
                createOptionPanel()
            end
        end)

        self:UnregisterEvent("PLAYER_ENTERING_WORLD")

    elseif event == "ADDON_LOADED" then
        -- Blizzard LoD addons
        if arg1 == "Blizzard_InspectUI" then
            SetMoveHandler(InspectFrame)
        elseif arg1 == "Blizzard_GuildBankUI" then
            SetMoveHandler(GuildBankFrame)
        elseif arg1 == "Blizzard_TradeSkillUI" then
            SetMoveHandler(TradeSkillFrame)
        elseif arg1 == "Blizzard_ItemSocketingUI" then
            SetMoveHandler(ItemSocketingFrame)
        elseif arg1 == "Blizzard_BarbershopUI" then
            SetMoveHandler(BarberShopFrame)
        elseif arg1 == "Blizzard_GlyphUI" then
            SetMoveHandler(SpellBookFrame, GlyphFrame)
        elseif arg1 == "Blizzard_MacroUI" then
            SetMoveHandler(MacroFrame)
        elseif arg1 == "Blizzard_AchievementUI" then
            SetMoveHandler(AchievementFrame, AchievementFrameHeader)
        elseif arg1 == "Blizzard_TalentUI" then
            SetMoveHandler(PlayerTalentFrame)
        elseif arg1 == "Blizzard_Calendar" then
            SetMoveHandler(CalendarFrame)
        elseif arg1 == "Blizzard_TrainerUI" then
            SetMoveHandler(ClassTrainerFrame)
        elseif arg1 == "Blizzard_BindingUI" then
            SetMoveHandler(KeyBindingFrame)
        elseif arg1 == "Blizzard_AuctionUI" then
            SetMoveHandler(AuctionFrame)
        end
    end
end

frame:SetScript("OnEvent", OnEvent)
frame:RegisterEvent("PLAYER_ENTERING_WORLD")

-------------------------------------------------
-- User API
-------------------------------------------------

function BlizzMove:Toggle(handler)
    handler = handler or GetMouseFocus()
    if not handler or handler:GetName() == "WorldFrame" then
        return
    end

    local lastParent = handler
    local frameToMove = handler
    local i = 0

    -- get the parent attached to UIParent from handler
    while lastParent and lastParent ~= UIParent and i < 100 do
        frameToMove = lastParent
        lastParent = lastParent:GetParent()
        i = i + 1
    end

    if not frameToMove then
        Print("Error parent not found.")
        return
    end

    if handler:GetScript("OnDragStart") then
        handler:SetScript("OnDragStart", nil)
        Print("Frame:", frameToMove:GetName(), "locked.")
    else
        Print("Frame:", frameToMove:GetName(), "to move with handler", handler:GetName())
        SetMoveHandler(frameToMove, handler)
    end
end

BINDING_HEADER_BLIZZMOVE = "BlizzMove"
BINDING_NAME_MOVEFRAME   = "Move/Lock a Frame"
