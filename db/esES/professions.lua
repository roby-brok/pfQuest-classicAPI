-- Profession / skill-line names are read live from the client's SkillLine.dbc
-- via ClassicAPI's C_SpellBook.GetSkillLineName / GetSkillLineRank (see
-- GetPlayerSkill in database.lua), so the shipped name table has been removed.
-- This empty stub keeps the init include valid and gives pfQuest-turtle's
-- patchtable() a base table to merge its professions-turtle entries into.
pfDB["professions"]["esES"] = {}
