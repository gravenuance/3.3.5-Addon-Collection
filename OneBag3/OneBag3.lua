local OneBag3 = LibStub('AceAddon-3.0'):NewAddon(
    'OneBag3',
    'OneCore-1.0',
    'OneFrame-1.0',
    'OneConfig-1.0',
    'OnePlugin-1.0',
    'AceHook-3.0',
    'AceEvent-3.0',
    'AceConsole-3.0'
)

local AceDB3 = LibStub('AceDB-3.0')
local L      = LibStub('AceLocale-3.0'):GetLocale('OneBag3')

OneBag3:InitializePluginSystem()

-- static config data
OneBag3.BagNames = {
    [0] = 'Backpack',
    [1] = 'First Bag',
    [2] = 'Second Bag',
    [3] = 'Third Bag',
    [4] = 'Fourth Bag',
}

-- helpers
local function IsManagedBag(bagid)
    return type(bagid) ~= 'number' or (bagid >= 0 and bagid <= 4)
end

-- lifecycle

function OneBag3:OnInitialize()
    self.db = AceDB3:New('OneBag3DB')
    self.db:RegisterDefaults(self.defaults)

    self.displayName = 'OneBag3'
    self.bagIndexes  = {0, 1, 2, 3, 4}

    self.frame = self:CreateMainFrame('OneBagFrame')
    self.frame.handler = self

    self.frame:ClearAllPoints()
    self.frame:SetPosition(self.db.profile.position)
    self.frame:CustomizeFrame(self.db.profile)
    self.frame:SetSize(200, 200)

    self.Show = self.OpenBag
    self.Hide = self.CloseBag

    self.frame:SetScript('OnShow', function()
        self:OnMainFrameShow()
    end)

    self.frame:SetScript('OnHide', function()
        self:OnMainFrameHide()
    end)

    local keyringButton = self:CreateKeyringButton(self.frame)
    keyringButton:ClearAllPoints()
    keyringButton:SetPoint('LEFT', self.frame.sidebarButton, 'RIGHT', -1, -8)
    keyringButton:SetScale(0.85)
    keyringButton:Show()
    self.frame.keyringButton = keyringButton

    self.frame.name:ClearAllPoints()
    self.frame.name:SetPoint('TOPLEFT', keyringButton, 'TOPRIGHT', -4, -4)

    self.sidebar = self:CreateSideBar('OneBagSideFrame', self.frame)
    self.sidebar.handler   = self
    self.frame.sidebar     = self.sidebar
    self.sidebar:CustomizeFrame(self.db.profile)

    self.sidebar:SetScript('OnShow', function()
        self:OnSidebarShow()
    end)

    self.sidebar:Hide()

    self:InitializeConfiguration()
    -- self:EnablePlugins()
    -- self:OpenConfig()
end

function OneBag3:OnEnable()
    self:SecureHook('IsBagOpen')
    self:RawHook('ToggleBag', true)
    self:RawHook('OpenBag', true)
    self:RawHook('CloseBag', true)
    self:RawHook('OpenBackpack', 'OpenBag', true)
    self:RawHook('CloseBackpack', 'CloseBag', true)
    self:RawHook('ToggleBackpack', 'ToggleBag', true)

    local open = function()
        self.wasOpened = self.isOpened
        if not self.isOpened then
            self:OpenBag()
        end
    end

    local close = function(event)
        if (event == 'MAIL_CLOSED' and not self.isReopened) or not self.wasOpened then
            self:CloseBag()
        end
    end

    local openEvents = {
        'AUCTION_HOUSE_SHOW',
        'BANKFRAME_OPENED',
        'MAIL_SHOW',
        'MERCHANT_SHOW',
        'TRADE_SHOW',
        'GUILDBANKFRAME_OPENED',
    }

    local closeEvents = {
        'AUCTION_HOUSE_CLOSED',
        'BANKFRAME_CLOSED',
        'MAIL_CLOSED',
        'MERCHANT_CLOSED',
        'TRADE_CLOSED',
        'GUILDBANKFRAME_CLOSED',
    }

    for _, ev in ipairs(openEvents) do
        self:RegisterEvent(ev, open)
    end
    for _, ev in ipairs(closeEvents) do
        self:RegisterEvent(ev, close)
    end
end

-- frame handlers

function OneBag3:OnMainFrameShow()
    if not self.frame.slots then
        self.frame.slots = {}
    end

    self:BuildFrame()
    self:OrganizeFrame()
    self:UpdateFrame()

    local UpdateBag = function(_, bag)
        self:UpdateBag(bag)
    end

    self:RegisterEvent('BAG_UPDATE', UpdateBag)
    self:RegisterEvent('BAG_UPDATE_COOLDOWN', UpdateBag)
    self:RegisterEvent('UPDATE_INVENTORY_ALERTS', 'UpdateFrame')
    self:RegisterEvent('ITEM_LOCK_CHANGED', 'UpdateItemLock')

    self.frame.name:SetText(L["%s's Bags"]:format(UnitName('player')))

    if self.frame.sidebarButton:GetChecked() then
        self.frame.sidebar:Show()
    end
end

function OneBag3:OnMainFrameHide()
    self:UnregisterEvent('BAG_UPDATE')
    self:UnregisterEvent('BAG_UPDATE_COOLDOWN')
    self:UnregisterEvent('UPDATE_INVENTORY_ALERTS')
    self:UnregisterEvent('ITEM_LOCK_CHANGED')

    self.sidebar:Hide()
    self:CloseBag()
end

function OneBag3:BuildSidebarButtons()
    if self.sidebar.buttons then return end

    self.sidebar.buttons = {}

    local backpack = self:CreateBackpackButton(self.sidebar)
    backpack:ClearAllPoints()
    backpack:SetPoint('TOP', self.sidebar, 'TOP', 0, -15)
    self.sidebar.buttons[-1] = backpack

    for bag = 0, 3 do
        local button = self:CreateBagButton(bag, self.sidebar)
        button:ClearAllPoints()
        button:SetPoint('TOP', self.sidebar, 'TOP', 0, (bag + 1) * -31 - 10)
        self.sidebar.buttons[bag] = button
    end
end

function OneBag3:OnSidebarShow()
    self:BuildSidebarButtons()
end

-- config

function OneBag3:LoadCustomConfig(baseconfig)
    local bagvisibility = {
        type  = 'group',
        name  = L['Specific Bag Filters'],
        order = 2,
        inline = true,
        args  = {},
    }

    for id, text in pairs(self.BagNames) do
        bagvisibility.args[tostring(id)] = {
            order = 5 * id + 5,
            type  = 'toggle',
            name  = L[text],
            desc  = L[('Toggles the display of your %s.'):format(text)],
            get   = function()
                return self.db.profile.show[id]
            end,
            set   = function(_, value)
                self.db.profile.show[id] = value
                self:OrganizeFrame(true)
            end,
        }
    end

    baseconfig.args.showbags.args.bag = bagvisibility
end

-- API hooks

function OneBag3:IsBagOpen(bagid)
    if type(bagid) == 'number' and (bagid < 0 or bagid > 4) then
        return
    end
    return self.isOpened and bagid or nil
end

function OneBag3:ToggleBag(bagid)
    if not IsManagedBag(bagid) then
        return self.hooks.ToggleBag(bagid)
    end

    if self.frame:IsVisible() then
        self:CloseBag()
    else
        self:OpenBag()
    end
end

function OneBag3:OpenBag(bagid)
    if not IsManagedBag(bagid) then
        return self.hooks.OpenBag(bagid)
    end

    self.frame:Show()
    self.isReopened = self.isOpened
    self.isOpened   = true
end

function OneBag3:CloseBag(bagid)
    if not IsManagedBag(bagid) then
        return self.hooks.CloseBag(bagid)
    end

    self.frame:Hide()
    self.isOpened = false
end

-- buttons

function OneBag3:CreateBackpackButton(parent)
    local button = CreateFrame('CheckButton', 'OBSideBarBackpackButton', parent, 'ItemButtonTemplate')
    button:SetID(0)

    local itemAnim = CreateFrame('Model', 'OBSideBarBackpackButtonItemAnim', button, 'ItemAnimTemplate')
    itemAnim:SetPoint('BOTTOMRIGHT', button, 'BOTTOMRIGHT', -10, 0)

    button:SetCheckedTexture('Interface\\Buttons\\CheckButtonHilight')
    button:RegisterForClicks('LeftButtonUp', 'RightButtonUp')

    OBSideBarBackpackButtonIconTexture:SetTexture('Interface\\Buttons\\Button-Backpack-Up')

    button:SetScript('OnEnter', function()
        self:HighlightBagSlots(0)

        GameTooltip:SetOwner(button, 'ANCHOR_LEFT')
        GameTooltip:SetText(BACKPACK_TOOLTIP, 1.0, 1.0, 1.0)

        local keyBinding = GetBindingKey('TOGGLEBACKPACK')
        if keyBinding then
            GameTooltip:AppendText(' '..NORMAL_FONT_COLOR_CODE..'('..keyBinding..')'..FONT_COLOR_CODE_CLOSE)
        end

        GameTooltip:AddLine(string.format(NUM_FREE_SLOTS, (MainMenuBarBackpackButton.freeSlots or 0)))
        GameTooltip:Show()
    end)

    button:SetScript('OnLeave', function(btn)
        if not btn:GetChecked() then
            self:UnhighlightBagSlots(0)
            self.frame.bags[0].colorLocked = false
        else
            self.frame.bags[0].colorLocked = true
        end
        GameTooltip:Hide()
    end)

    button:SetScript('OnReceiveDrag', function(_, mouseButton)
        BackpackButton_OnClick(button, mouseButton)
    end)

    return button
end

function OneBag3:CreateBagButton(bag, parent)
    local button = CreateFrame('CheckButton', 'OBSideBarBag'..bag..'Slot', parent, 'BagSlotButtonTemplate')
    button:SetScale(1.27)

    self:SecureHookScript(button, 'OnEnter', function(btn)
        self:HighlightBagSlots(btn:GetID() - 19)
    end)

    button:SetScript('OnLeave', function(btn)
        local id = btn:GetID() - 19
        if not btn:GetChecked() then
            self:UnhighlightBagSlots(id)
            self.frame.bags[id].colorLocked = false
        else
            self.frame.bags[id].colorLocked = true
        end
        GameTooltip:Hide()
    end)

    button:SetScript('OnClick', function(btn)
        local haditem = PutItemInBag(btn:GetID())
        if haditem then
            btn:SetChecked(not btn:GetChecked())
        end
    end)

    button:SetScript('OnReceiveDrag', function(btn)
        PutItemInBag(btn:GetID())
    end)

    return button
end
