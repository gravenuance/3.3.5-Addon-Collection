local ADDON_NAME, addon = ...

local Units = {}
addon.Units = Units

-- per GUID: { name = ..., health = ..., class = ... }
local unitData = {}

-- reverse lookup: key "name|health" -> guid, or false once two GUIDs share the key
local unitGUIDs = {}

local function MakeKey(name, health)
    if not name or not health then
        return nil
    end
    return name .. "|" .. health
end

function Units:GetGUID(name, health)
    local key = MakeKey(name, health)
    return key and unitGUIDs[key] or nil
end

function Units:SetGUID(guid, name, health, class)
    if not guid then
        return
    end

    -- Always keep per-GUID data
    local data = unitData[guid]
    if not data then
        data = {}
        unitData[guid] = data
    end

    if name then data.name = name end
    if health then data.health = health end
    if class then data.class = class end

    -- Only update reverse lookup if we have both pieces
    local key = MakeKey(name, health)
    if key then
        local known = unitGUIDs[key]
        if known == nil then
            unitGUIDs[key] = guid
        elseif known ~= guid then
            unitGUIDs[key] = false
        end
    end
end

function Units:Get(guid)
    return guid and unitData[guid] or nil
end
