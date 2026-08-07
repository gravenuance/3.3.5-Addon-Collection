if ( C_NamePlate ) then return end -- (https://github.com/FrostAtom/awesome_wotlk)

-- NOTE: this only creates the namespace so `C_NamePlate` is a safe table to
-- index instead of a nil global. It does not implement GetNamePlates() et al.
-- (3.3.5 nameplates have no unit-token API to back that with); nothing in
-- this addon compilation currently calls into C_NamePlate.
local C_NamePlate = C_NamePlate or {}

-- Global
_G.C_NamePlate = C_NamePlate