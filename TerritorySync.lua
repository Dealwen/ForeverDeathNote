local _, note = ...
local prefix, header = "FDN_ZONE1", "FDNZ1"
local guildPrefix = "FDN_ZONE3"
local maxImport, maxStored = 400, 6000
local retention = 7 * 86400
local pending, stored, storedCount = {}, nil, 0
local nextPrune, registered, sending = 0, false, false
local listener = CreateFrame("Frame")
local channels = { GUILD = true, PARTY = true, RAID = true }
local sourcePriority = { own = 3, peer = 2, imported = 1 }

local function weekStart(now)
    return math.floor((now + 3 * 86400) / retention) * retention - 3 * 86400
end
note.WeekStart = weekStart

function note.TerritoryFactions(entry, sample)
    local profiles = (sample or note.db).profiles
    local own = note.Faction(entry.ownerFaction or (profiles[sample and "self" or note.owner] or {}).faction)
    local other = note.Faction(entry.otherFaction or (profiles[entry.other] or {}).faction)
    if entry.kind == "D" then return other, own end
    return own, other
end

local function personalReport(entry, sample)
    local killer, victim = sample and "self" or note.owner, entry.other
    local guild = entry.ownerGuild
    if entry.kind == "D" then killer, victim, guild = victim, killer, entry.otherGuild end
    local killerFaction, victimFaction = note.TerritoryFactions(entry, sample)
    if killerFaction and killerFaction == victimFaction then return end
    return {
        kind = entry.kind, killer = killer, victim = victim, at = entry.at,
        killerGuild = note.Text(guild),
        killerFaction = killerFaction, victimFaction = victimFaction,
        mapId = note.EncounterMapID(entry), zone = entry.zone, personal = entry, source = "own",
    }
end

note.PersonalTerritoryReport = personalReport

local function reportKey(event)
    return table.concat({event.kind, event.at, event.killer, event.victim}, ";")
end

local function encode(event)
    if not event or not event.mapId or not event.killerFaction or not event.victimFaction then return end
    local text = table.concat({ note.scope, reportKey(event), event.mapId, event.killerFaction, event.victimFaction }, ";")
    if #text <= 240 then return text end
end

local function decode(text, now, origin)
    if type(text) ~= "string" or #text > 240 then return end
    local realm, kind, stamp, killer, victim, map, kf, vf =
        text:match("^([^;]+);([KD]);(%d+);([^;]+);([^;]+);(%d+);([%a]+);([%a]+)$")
    if realm ~= note.scope then return end
    local at, mapId = tonumber(stamp), note.PositiveInteger(tonumber(map), 1000000)
    if not at or at < weekStart(now) or at > now + 30 or not mapId
        or not note.GUID(killer) or not note.GUID(victim) or killer == victim
        or not note.Faction(kf) or not note.Faction(vf) or kf == vf then return end
    return { kind = kind, at = at, killer = killer, victim = victim, mapId = mapId,
        killerFaction = kf, victimFaction = vf, source = origin }
end

local function prune(now)
    if now < nextPrune and storedCount <= maxStored then return end
    local start, ordered = weekStart(now), {}
    for key, event in pairs(stored) do
        if event.at < start then stored[key] = nil
        else ordered[#ordered + 1] = { key = key, at = event.at } end
    end
    storedCount = #ordered
    if storedCount > maxStored then
        table.sort(ordered, function(a, b)
            if a.at ~= b.at then return a.at < b.at end
            return a.key < b.key
        end)
        local excess = storedCount - maxStored + 128
        for i = 1, excess do stored[ordered[i].key] = nil end
        storedCount = storedCount - excess
    end
    nextPrune = start + retention
end

local function receive(event, now)
    prune(now)
    local key = reportKey(event)
    local old = stored[key]
    if old and not old.killerGuild and event.killerGuild then
        old.killerGuild = event.killerGuild
        if sourcePriority[old.source] >= sourcePriority[event.source] then return false, true end
    elseif old then
        event.killerGuild = event.killerGuild or old.killerGuild
    end
    if old and sourcePriority[old.source] >= sourcePriority[event.source] then return false, false end
    stored[key] = event
    if not old then storedCount = storedCount + 1 end
    return not old, true
end

function note.StartTerritorySync()
    local root = ForeverDeathNoteDB
    root.territoryReports = root.territoryReports or {}
    root.territoryReports[note.scope] = root.territoryReports[note.scope] or {}
    stored, storedCount, nextPrune = root.territoryReports[note.scope], 0, 0
    prune(GetServerTime())
    if not C_ChatInfo or not C_ChatInfo.RegisterAddonMessagePrefix or not C_ChatInfo.SendAddonMessage then return end
    registered = C_ChatInfo.RegisterAddonMessagePrefix(prefix) ~= false
    if registered then
        C_ChatInfo.RegisterAddonMessagePrefix(guildPrefix)
        listener:RegisterEvent("CHAT_MSG_ADDON")
        listener:RegisterEvent("PLAYER_REGEN_ENABLED")
        listener:RegisterEvent("PLAYER_ENTERING_WORLD")
        listener:RegisterEvent("GROUP_ROSTER_UPDATE")
    end
end

local function groupChannel()
    if IsInRaid and IsInRaid() then return "RAID" end
    if IsInGroup and IsInGroup() then return "PARTY" end
end

local function flush()
    if sending or #pending == 0 then return end
    if not note.db.territorySharing then pending = {}; return end
    if InCombatLockdown() or IsInInstance() then return end
    local event = table.remove(pending, 1)
    local function send(channel)
        C_ChatInfo.SendAddonMessage(prefix, event.text, channel)
        if event.withGuild then C_ChatInfo.SendAddonMessage(guildPrefix, event.withGuild, channel) end
    end
    if GetServerTime() - event.at <= 600 then
        if event.guild and IsInGuild() and event.guild == note.Text(GetGuildInfo("player")) then
            send("GUILD")
        end
        if event.channel and event.channel == groupChannel() then
            send(event.channel)
        end
    end
    if #pending > 0 then
        sending = true
        C_Timer.After(1, function() sending = false; flush() end)
    end
end

local function refreshTerritoryViews()
    if note.RefreshTerritories then note.RefreshTerritories() end
    if note.RefreshFront then note.RefreshFront() end
end

function note.SetTerritorySharing(enabled)
    if not registered then return end
    note.db.territorySharing = enabled and true or false
    if not enabled then pending = {} end
    refreshTerritoryViews()
end

function note.PublishTerritory(entry)
    if not registered or not note.db.territorySharing or #pending >= 30 then return end
    local channel = groupChannel()
    if not IsInGuild() and not channel then return end
    local report = personalReport(entry)
    local text = encode(report)
    if not text then return end
    local guild = report.killerGuild
    local withGuild = guild and #text + #guild < 240 and text .. ";" .. guild or nil
    pending[#pending + 1] = { text = text, withGuild = withGuild, at = entry.at, guild = note.Text(GetGuildInfo("player")), channel = channel }
    flush()
end

listener:SetScript("OnEvent", function(_, name, incoming, text, channel)
    if name == "GROUP_ROSTER_UPDATE" then
        for _, queued in ipairs(pending) do queued.channel = nil end
        return
    end
    if name ~= "CHAT_MSG_ADDON" then flush(); return end
    incoming, text = note.Public(incoming), note.Public(text)
    if not note.db.territorySharing or (incoming ~= prefix and incoming ~= guildPrefix)
        or not channels[note.Public(channel)] or type(text) ~= "string" or #text > 240 then return end
    local now = GetServerTime()
    local killerGuild
    if incoming == guildPrefix then
        text, killerGuild = text:match("^(.*);([^;]+)$")
        killerGuild = note.Text(killerGuild)
        if not killerGuild then return end
    end
    local report = decode(text, now, "peer")
    if not report or (report.kind == "K" and report.killer or report.victim) == note.owner then return end
    report.killerGuild = killerGuild
    local _, changed = receive(report, now)
    if changed then refreshTerritoryViews() end
end)

function note.ExportTerritories()
    local now, recent, lines = GetServerTime(), {}, { header }
    local start = weekStart(now)
    for key, event in pairs(stored or {}) do
        if event.at >= start and event.at <= now then recent[key] = event end
    end
    for _, entry in ipairs(note.db.events) do
        if entry.at >= start and entry.at <= now then
            local report = personalReport(entry)
            if report and encode(report) then recent[reportKey(report)] = report end
        end
    end
    local ordered = {}
    for _, event in pairs(recent) do ordered[#ordered + 1] = event end
    table.sort(ordered, function(a, b)
        if a.at ~= b.at then return a.at > b.at end
        return reportKey(a) < reportKey(b)
    end)
    for i = 1, math.min(#ordered, maxImport) do lines[#lines + 1] = encode(ordered[i]) end
    return table.concat(lines, "\n"), #lines - 1
end

function note.ImportTerritories(text)
    if not stored or type(text) ~= "string" or #text > 90000 then return end
    local body = text:match("^" .. header .. "\r?\n(.*)$")
    if not body then return end
    local now, accepted = GetServerTime(), {}
    for line in body:gmatch("[^\r\n]+") do
        local event = decode(line, now, "imported")
        if not event or #accepted >= maxImport then return end
        accepted[#accepted + 1] = event
    end
    if #accepted == 0 then return end
    local count, changed = 0, false
    for _, event in ipairs(accepted) do
        local added, updated = receive(event, now)
        if added then count = count + 1 end
        changed = changed or updated
    end
    if changed then refreshTerritoryViews() end
    return count
end

function note.ForEachTerritoryFight(sample, start, now, visit)
    local reports, pairsByID = {}, {}
    local function add(report)
        if not report or report.at < start or report.at > now or not report.killer or not report.victim then return end
        local key = reportKey(report)
        local prior = reports[key]
        if prior and report.personal then report.killerGuild = report.killerGuild or prior.killerGuild end
        if prior and report.personal and not report.mapId then
            report.mapId = prior.mapId
            report.killerFaction = report.killerFaction or prior.killerFaction
            report.victimFaction = report.victimFaction or prior.victimFaction
        end
        reports[key] = report
    end
    for _, event in pairs(sample and sample.territoryReports or not sample and stored or {}) do add(event) end
    for _, entry in ipairs((sample or note.db).events) do
        if entry.at >= start and entry.at <= now then add(personalReport(entry, sample)) end
    end
    for _, event in pairs(reports) do
        local key = event.killer .. ";" .. event.victim
        local pair = pairsByID[key] or { K = {}, D = {} }
        pairsByID[key] = pair
        pair[event.kind][#pair[event.kind] + 1] = event
    end
    local guilds = {}
    for _, event in pairs(sample and sample.reports or not sample and note.realmEvents or {}) do
        local guild = note.Text(event.killerGuild)
        if guild and event.at >= start and event.at <= now then
            local key = table.concat({event.at, event.killer, event.victim}, ";")
            local previous = guilds[key]
            guilds[key] = (previous == nil or previous == guild) and guild or false
        end
    end
    local function guildFor(event)
        return event.killerGuild or guilds[table.concat({event.at, event.killer, event.victim}, ";")]
    end
    for _, pair in pairs(pairsByID) do
        note.ForEachMatchedFight(pair, function(kill, death)
            local first, second = death, kill
            if kill and (not death or sourcePriority[kill.source] > sourcePriority[death.source]) then
                first, second = kill, death
            end
            local killer = first.killerFaction or (second and second.killerFaction)
            local victim = first.victimFaction or (second and second.victimFaction)
            if killer and killer == victim then return end
            local location = (first.mapId or not second) and first or second
            if location.mapId and not location.zone and C_Map and C_Map.GetMapInfo then
                local info = C_Map.GetMapInfo(location.mapId)
                location = { at = location.at, mapId = location.mapId, zone = info and info.name }
            end
            visit(location, killer and victim and killer or nil, first.personal or second and second.personal,
                guildFor(first) or second and guildFor(second), first.killer, first.killerName or second and second.killerName)
        end)
    end
end
