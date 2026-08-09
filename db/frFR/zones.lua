-- Zone/area names are read live from the client's AreaTable.dbc via ClassicAPI's
-- C_Map.GetAreas (see database.lua, which repoints pfDB["zones"]["loc"] to it),
-- so the shipped name table has been removed. This empty stub keeps the init
-- include valid and gives pfQuest-turtle's patchtable() a base to merge into.
pfDB["zones"]["frFR"] = {}
