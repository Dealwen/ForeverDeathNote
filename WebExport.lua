local _, note = ...
local rootHeader = "FDNWEB1\n"
local continents = { 1414, 1415 }
local escapes = { ['"'] = '\\"', ['\\'] = '\\\\', ['\n'] = '\\n', ['\r'] = '\\r', ['\t'] = '\\t' }

local function encode(value)
    local kind = type(value)
    if kind == "string" then
        return '"' .. value:gsub('[%z\1-\31\\"]', function(character)
            return escapes[character] or ("\\u%04x"):format(character:byte())
        end) .. '"'
    end
    if kind == "number" or kind == "boolean" then return tostring(value) end
    local fields = {}
    if value[1] ~= nil or not next(value) then
        for _, item in ipairs(value) do fields[#fields + 1] = encode(item) end
        return "[" .. table.concat(fields, ",") .. "]"
    end
    local keys = {}
    for key in pairs(value) do keys[#keys + 1] = key end
    table.sort(keys)
    for _, key in ipairs(keys) do fields[#fields + 1] = encode(key) .. ":" .. encode(value[key]) end
    return "{" .. table.concat(fields, ",") .. "}"
end

-- Give each character a stable display key without exporting its original game GUID.
local function playerKey(realm, id)
    local text = realm .. "/" .. tostring(id)
    local first, second = 0, 17
    for i = 1, #text do
        local byte = text:byte(i)
        first = (first * 31 + byte) % 2147483647
        second = (second * 131 + byte) % 2147483629
    end
    return ("p-%08x%08x"):format(first, second)
end

local function rankingFaction(faction)
    return faction == "Mixed" and faction or note.Faction(faction)
end

function note.ExportWebSnapshot()
    if not note.db then return end
    local now = GetServerTime()
    local realm = note.Text(GetRealmName()) or "Forever"
    local snapshot = {
        version = 1, realm = realm, generatedAt = now, weekStart = note.WeekStart(now),
        region = GetCurrentRegion and GetCurrentRegion(), zoneSource = "shared",
        zones = {}, players = {}, guilds = {},
    }

    local groups = note.TerritoryZoneGroups(true)
    for _, continent in ipairs(continents) do
        for _, zone in ipairs(groups[continent] or {}) do
            local owner = zone.owner
            local name = note.Text(zone.title or zone.name)
            if type(zone.key) == "number" and name then
                snapshot.zones[#snapshot.zones + 1] = {
                    id = zone.key, name = name, continent = continent, horde = zone.Horde or 0,
                    alliance = zone.Alliance or 0, leadingFaction = note.Faction(zone.leadingFaction),
                    ownerGuild = owner and note.Text(owner.name), ownerFaction = owner and note.Faction(owner.faction),
                    ownerKills = zone.ownerKills or 0, ownerTie = zone.ownerTie == true,
                    topKiller = zone.topKiller and note.Text(zone.topKiller.name), topKills = zone.topKills or 0,
                    topKillerTie = zone.topKillerTie == true,
                }
            end
        end
    end

    local players, _, rosters = note.Ranking(nil, nil, true)
    for _, player in ipairs(players) do
        snapshot.players[#snapshot.players + 1] = {
            id = playerKey(realm, player.id), name = note.Text(player.name) or "Unknown",
            class = note.Class(player.class), guild = note.Text(player.guild), faction = rankingFaction(player.faction),
            kills = player.kills, deaths = player.deaths, uniqueVictims = #player.victims,
        }
    end
    for _, guild in ipairs(note.GuildRanking(players, rosters)) do
        local id, name = note.Text(guild.id), note.Text(guild.name)
        if id and name then
            snapshot.guilds[#snapshot.guilds + 1] = {
                id = id, name = name, faction = rankingFaction(guild.faction),
                kills = guild.kills, deaths = guild.deaths, members = #guild.members, rosterCount = guild.rosterCount,
            }
        end
    end

    return rootHeader .. encode(snapshot), #snapshot.players, #snapshot.guilds, #snapshot.zones
end

function note.WebAutosaveEnabled()
    return ForeverDeathNoteDB.webSnapshotEnabled == true
end

local function save()
    if not note.db or not note.WebAutosaveEnabled() then return end
    ForeverDeathNoteWebSnapshot = note.ExportWebSnapshot()
end

function note.SetWebAutosave(enabled)
    ForeverDeathNoteDB.webSnapshotEnabled = enabled and true or nil
    if enabled then save() else ForeverDeathNoteWebSnapshot = nil end
end

local listener = CreateFrame("Frame")
listener:RegisterEvent("PLAYER_LOGOUT")
listener:SetScript("OnEvent", save)
