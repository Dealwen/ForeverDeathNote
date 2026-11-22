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

local mapReportLimit = 2000
local mapReportAge = 30 * 86400

local function mapPlayerKey(realm, guid)
    return playerKey(realm, "Player-" .. guid:sub(8):upper())
end

function note.MapSyncEnabled()
    return ForeverDeathNoteDB.mapSyncEnabled == true
end

function note.SetMapSync(enabled)
    local root = ForeverDeathNoteDB
    if enabled then
        root.mapSyncEnabled = true
    else
        root.mapSyncEnabled, root.mapObservations, ForeverDeathNoteMapExport = nil, nil, nil
    end
    if note.RefreshMapSyncOption then note.RefreshMapSyncOption() end
end

local function mapCoordinate(value)
    if type(value) == "number" and value >= 0 and value <= 100 then
        return math.floor(value * 100 + 0.5)
    end
end

function note.RecordMapObservation(entry)
    local root = ForeverDeathNoteDB
    if not root.mapSyncEnabled or (entry.kind ~= "K" and entry.kind ~= "D") then return end
    local region = note.PositiveInteger(GetCurrentRegion(), 5)
    local realm = note.Text(GetRealmName())
    if not region or not realm then return end
    local kill = entry.kind == "K"
    local killer, victim = kill and note.owner or entry.other, kill and entry.other or note.owner
    local mapId = note.PositiveInteger(entry.mapId, 1000000)
    local x, y = mapCoordinate(entry.x), mapCoordinate(entry.y)
    local rows = root.mapObservations or {}
    root.mapObservations = rows
    rows[#rows + 1] = {
        region = region, realm = realm, at = entry.at, kind = entry.kind,
        killerId = mapPlayerKey(realm, killer), victimId = mapPlayerKey(realm, victim),
        killer = note.Text(note.Profile(killer).name), victim = note.Text(note.Profile(victim).name),
        killerFaction = kill and entry.ownerFaction or (not kill and entry.otherFaction or nil),
        mapId = mapId, zone = note.Text(entry.zone),
        x = mapId and x and y and x or nil, y = mapId and x and y and y or nil,
    }
    if #rows > mapReportLimit then table.remove(rows, 1) end
end

local function saveMapObservations()
    local root = ForeverDeathNoteDB
    if not root or not root.mapSyncEnabled then
        ForeverDeathNoteMapExport = nil
        return
    end
    local cutoff, rows = GetServerTime() - mapReportAge, {}
    for _, row in ipairs(root.mapObservations or {}) do
        if row.at >= cutoff then rows[#rows + 1] = row end
    end
    root.mapObservations = rows
    ForeverDeathNoteMapExport = "FDNPVP1\n" .. encode({ version = 1, reports = rows })
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
        local profile = player.profile or {}
        snapshot.players[#snapshot.players + 1] = {
            id = playerKey(realm, player.id), name = note.Text(player.name) or "Unknown",
            class = note.Class(player.class), guild = note.Text(player.guild), faction = rankingFaction(player.faction),
            kills = player.kills, deaths = player.deaths, uniqueVictims = #player.victims,
            race = note.Text(profile.race), level = note.PositiveInteger(profile.level, 100),
        }
    end
    for _, guild in ipairs(note.GuildRanking(players, rosters)) do
        local id, name = note.Text(guild.id), note.Text(guild.name)
        if id and name then
            local topPlayers = {}
            for _, member in ipairs(note.GuildKillLeaders(guild)) do
                topPlayers[#topPlayers + 1] = {
                    id = playerKey(realm, member.id), kills = member.kills, deaths = member.deaths,
                }
            end
            snapshot.guilds[#snapshot.guilds + 1] = {
                id = id, name = name, faction = rankingFaction(guild.faction),
                kills = guild.kills, deaths = guild.deaths, members = #guild.members,
                rosterCount = guild.rosterCount, topPlayers = topPlayers,
            }
        end
    end

    return rootHeader .. encode(snapshot), #snapshot.players, #snapshot.guilds, #snapshot.zones
end

function note.WebAutosaveEnabled()
    return ForeverDeathNoteDB.webSnapshotEnabled == true
end

local function save()
    saveMapObservations()
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
