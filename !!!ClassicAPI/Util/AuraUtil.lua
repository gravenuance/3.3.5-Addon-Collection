local AuraUtil = AuraUtil or {}

local UnitAura = UnitAura

local function FindAuraRecurse(predicate, unit, filter, auraIndex, predicateArg1, predicateArg2, predicateArg3, ...)
    if ... == nil then
        return nil; -- Not found
    end
    if predicate(predicateArg1, predicateArg2, predicateArg3, ...) then
        return ...;
    end
    auraIndex = auraIndex + 1;
    local name, rank, icon, count, type, duration, expire, caster, steal, consolidate, id = UnitAura(unit, auraIndex, filter);
    return FindAuraRecurse(predicate, unit, filter, auraIndex, predicateArg1, predicateArg2, predicateArg3, name, icon, count, type, duration, expire, caster, steal, consolidate, id);
end

-- Find an aura by any predicate, you can pass in up to 3 predicate specific parameters
-- The predicate will also receive all aura params, if the aura data matches return true
function AuraUtil.FindAura(predicate, unit, filter, predicateArg1, predicateArg2, predicateArg3)
    local auraIndex = 1;
    local name, rank, icon, count, type, duration, expire, caster, steal, consolidate, id = UnitAura(unit, auraIndex, filter);
    return FindAuraRecurse(predicate, unit, filter, auraIndex, predicateArg1, predicateArg2, predicateArg3, name, icon, count, type, duration, expire, caster, steal, consolidate, id);
end

do

    local function NamePredicate(auraNameToFind, _, _, auraName)
        return auraNameToFind == auraName;
    end
    -- Finds the first aura that matches the name
    -- Notes:
    --		aura names are not unique!
    --		aura names are localized, what works in one locale might not work in another
    --			consider that in English two auras might have different names, but once localized they have the same name, so even using the localized aura name in a search it could result in different behavior
    --		the unit could have multiple auras with the same name, this will only find the first
    function AuraUtil.FindAuraByName(auraName, unit, filter)
        return AuraUtil.FindAura(NamePredicate, unit, filter, auraName);
    end

end

do

    -- NOTE: retail's ForEachAura is slot-based (UnitAuraSlots/UnitAuraBySlot),
    -- which doesn't exist pre-Legion. 3.3.5 only has index-based UnitAura, so
    -- this walks auras by index instead - same external contract (func gets
    -- called with each aura's data, stops early if func returns truthy).
    function AuraUtil.ForEachAura(unit, filter, maxCount, func)
        if maxCount and maxCount <= 0 then
            return;
        end

        local index = 1;
        while not maxCount or index <= maxCount do
            local name, rank, icon, count, auraType, duration, expire, caster, steal, consolidate, id = UnitAura(unit, index, filter);
            if not name then
                break;
            end
            if func(name, rank, icon, count, auraType, duration, expire, caster, steal, consolidate, id) then
                break;
            end
            index = index + 1;
        end
    end

end

-- Global
_G.AuraUtil = AuraUtil