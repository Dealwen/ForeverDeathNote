local _, note = ...
local L = note.L

-- Preserve the live-only pane interfaces used by older saved layouts.
function note.DemoData() return nil end

function note.Public(value)
    if issecretvalue and issecretvalue(value) then return nil end
    return value
end

function note.Text(value)
    value = note.Public(value)
    if type(value) ~= "string" then return nil end
    value = value:gsub("[|;%z\1-\31\127]", ""):match("^ *(.-) *$")
    if value ~= "" and #value <= 96 then return value end
end

function note.GUID(value)
    value = note.Public(value)
    if type(value) == "string" and #value <= 64 and value:match("^Player%-%d+%-%x+$") then
        return value
    end
end

function note.PositiveInteger(value, maximum)
    value = note.Public(value)
    if type(value) == "number" and value >= 1 and value <= maximum and value == math.floor(value) then
        return value
    end
end

function note.Faction(value)
    value = note.Public(value)
    if value == "Horde" or value == "Alliance" then return value end
end

function note.UnitName(unit)
    local given, surname = UnitName(unit)
    given, surname = note.Text(given), note.Text(surname)
    if given and surname and not given:find(" ", 1, true) then
        return note.Text(given .. " " .. surname) or given
    end
    return given
end

function note.Class(value)
    value = note.Text(value)
    if value and #value <= 20 and value:match("^[A-Z]+$") then return value end
end

function note.SpellName(id, fallback, demo)
    if demo and fallback then return L[fallback] end
    if fallback == "Автоатака" then return L[fallback] end
    if id and C_Spell and C_Spell.GetSpellName then
        local name = note.Text(C_Spell.GetSpellName(id))
        if name then return name end
    end
    return fallback
end

function note.Init()
    local owner = note.GUID(UnitGUID("player"))
    if not owner then return end
    local realm = note.Text(GetRealmName()) or "Forever"
    note.scope = (GetCurrentRegion() or 0) .. "/" .. realm
    note.owner = owner
    ForeverDeathNoteDB = ForeverDeathNoteDB or {}
    local root = ForeverDeathNoteDB
    if not root.fieldThemeIntroduced then
        if root.windowTheme == "wartable" then root.windowTheme = nil end
        root.fieldThemeIntroduced = true
    end
    note.InitLocale()
    if note.WarTable then note.WarTable.RefreshPalette() end
    root.characters = root.characters or {}
    root.realms = root.realms or {}
    root.characters[owner] = root.characters[owner] or { events = {}, profiles = {}, sharing = false, firstJournal = true }
    root.realms[note.scope] = root.realms[note.scope] or {}
    note.db = root.characters[owner]
    note.realmEvents = root.realms[note.scope]
    for _, character in pairs(root.characters) do
        character.demo, character.demoMode = nil, nil
    end
    if note.db.autoFightReport == nil then note.db.autoFightReport = true end
end

function note.Profile(guid, info)
    local profile = note.db.profiles[guid]
    if info then
        profile = profile or {}
        for key, value in pairs(info) do
            profile[key] = value
        end
        note.db.profiles[guid] = profile
    end
    return profile or {}
end

function note.Name(guid)
    return note.Profile(guid).name or L["Имя неизвестно"]
end

function note.Refresh()
    if note.InvalidateRankHeader then note.InvalidateRankHeader() end
    if note.RefreshFront then note.RefreshFront() end
    if note.RefreshWindow then note.RefreshWindow() end
    if note.RefreshLadder then note.RefreshLadder() end
    if note.RefreshMarks then note.RefreshMarks() end
    if note.RefreshFightMap then note.RefreshFightMap() end
    if note.RefreshTerritories then note.RefreshTerritories() end
    if note.UpdateDossierDemo and note.DemoData then note.UpdateDossierDemo(note.DemoData()) end
    if note.RefreshHuntTracker then note.RefreshHuntTracker() end
    if note.RefreshFightReport then note.RefreshFightReport() end
end

function note.HuntPresentationChanged(demo)
    if note.RefreshFront then note.RefreshFront() end
    if note.RefreshTerritories then note.RefreshTerritories() end
    if note.RefreshWindow then note.RefreshWindow() end
    if note.UpdateDossierDemo and note.DemoData then note.UpdateDossierDemo(note.DemoData()) end
    if not demo and note.RefreshAlert then note.RefreshAlert() end
    if note.RefreshHuntTracker then note.RefreshHuntTracker() end
end

function note.Record(kind, other, place)
    if not other or other == note.owner then return end
    local events = note.db.events
    for index = #events, math.max(1, #events - 20), -1 do
        local old = events[index]
        if old.kind == kind and old.other == other and old.at == place.at then return end
    end
    place.kind, place.other = kind, other
    local guild = note.Profile(note.owner).guild
    place.ownerGuild = guild or false
    place.otherGuild = note.Profile(other).guild
    place.ownerFaction = note.Profile(note.owner).faction
    place.otherFaction = note.Profile(other).faction
    events[#events + 1] = place
    if note.HuntRecord then note.HuntRecord(place) end
    if note.RecordRampage then note.RecordRampage(place) end
    if note.RecordLadderAchievement then note.RecordLadderAchievement(place) end
    if note.RecordSortie then note.RecordSortie(place) end
    if note.RecordFightReport then note.RecordFightReport(place) end
    if note.Publish then note.Publish(place) end
    if note.PublishTerritory then note.PublishTerritory(place) end
    note.Refresh()
end

function note.Count(other)
    local kills, deaths = 0, 0
    for _, entry in ipairs(note.db.events) do
        if not other or entry.other == other then
            if entry.kind == "K" then kills = kills + 1 else deaths = deaths + 1 end
        end
    end
    return kills, deaths
end

function note.Forget(other)
    local events = note.db.events
    for i = #events, 1, -1 do
        if events[i].other == other then table.remove(events, i) end
    end
    if note.db.dossier then note.db.dossier[other] = nil end
    local contract = note.db.hunt and note.db.hunt.contract
    if contract and contract.id == other and not contract.completed then note.db.hunt.contract = nil end
    note.Refresh()
end
