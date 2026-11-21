local _, note = ...
local L = note.L
local prefix, metadataPrefix = "FDN_V1", "FDN_META"
local retention = 30 * 86400
local pending = {}
local sending, registered, metadataRegistered
local listener = CreateFrame("Frame")
local seededHistories = {}
local lower = strlower or string.lower
local metadata = {
    "killerName", "victimName", "killerGuild", "victimGuild",
    "victimLevel", "killerFaction", "victimFaction", "rosterCount", "rosterAt",
    "killerClass", "spellId", "spellName",
}
local fieldCount = { 2, 4, 9, 12 }
local strength = { own = 3, guild = 2, imported = 1 }

local function source(event)
    if event then return event.source or (event.receivedGuild and "guild" or "imported") end
end

local function report(entry, useGuildSnapshot)
    local killer, victim = note.owner, entry.other
    if entry.kind == "D" then killer, victim = victim, killer end
    local killerProfile, victimProfile = note.Profile(killer), note.Profile(victim)
    local killerFaction, victimFaction = entry.ownerFaction, entry.otherFaction
    local killerGuild, victimGuild = entry.ownerGuild, entry.otherGuild
    if entry.kind == "D" then
        killerFaction, victimFaction = victimFaction, killerFaction
        killerGuild, victimGuild = victimGuild, killerGuild
    end
    if not useGuildSnapshot then
        if killerGuild == nil then killerGuild = killerProfile.guild end
        if victimGuild == nil then victimGuild = victimProfile.guild end
    end
    local event = {
        at = entry.at, kind = entry.kind, killer = killer, victim = victim,
        killerName = killerProfile.name, victimName = victimProfile.name,
        killerGuild = killerGuild, victimGuild = victimGuild,
        killerFaction = killerFaction or killerProfile.faction, victimFaction = victimFaction or victimProfile.faction,
        victimLevel = entry.victimLevel, killerClass = entry.killerClass or killerProfile.class,
        spellId = entry.spellId, spellName = entry.spellName,
    }
    local roster = note.db.roster
    if roster and roster.guild == note.Profile(note.owner).guild then
        event.rosterCount, event.rosterAt = roster.count, roster.at
    end
    return event
end

local function reportKey(event)
    return table.concat({event.kind, event.at, event.killer, event.victim}, ";")
end

local function encode(event, version, compact)
    local parts = { note.scope, reportKey(event) }
    local fields = fieldCount[version]
    for i = 1, fields do
        local include = not compact or i > compact
        parts[#parts + 1] = include and event[metadata[i]] or ""
    end
    return table.concat(parts, ";")
end

local function decode(line, now, version)
    if type(line) ~= "string" or #line > 880 then return end
    local parts = {}
    for field in (line .. ";"):gmatch("(.-);") do parts[#parts + 1] = field end
    if not version then version = #parts == 17 and 4 or 3 end
    if #parts ~= fieldCount[version] + 5 then return end
    local realm, kind, stamp, killer, victim = unpack(parts, 1, 5)
    local at = tonumber(stamp)
    if realm ~= note.scope or (kind ~= "K" and kind ~= "D")
        or not at or at ~= math.floor(at) or at < now - retention or at > now + 30
        or not note.GUID(killer) or not note.GUID(victim) or killer == victim then return end
    local rosterAt = tonumber(parts[14])
    local rosterCount = note.PositiveInteger(tonumber(parts[13]), 10000)
    if not rosterAt or rosterAt < now - retention or rosterAt > now + 30 then
        rosterAt, rosterCount = nil, nil
    end
    return { at = at, kind = kind, killer = killer, victim = victim,
        killerName = note.Text(parts[6]), victimName = note.Text(parts[7]),
        killerGuild = note.Text(parts[8]), victimGuild = note.Text(parts[9]),
        victimLevel = note.PositiveInteger(tonumber(parts[10]), 255),
        killerFaction = note.Faction(parts[11]), victimFaction = note.Faction(parts[12]),
        rosterCount = rosterCount, rosterAt = rosterCount and rosterAt or nil,
        killerClass = note.Class(parts[15]), spellId = note.PositiveInteger(tonumber(parts[16]), 10000000),
        spellName = note.Text(parts[17]) }
end

local function mergeMetadata(existing, event)
    local changed = false
    for _, field in ipairs(metadata) do
        if field ~= "rosterAt" and field ~= "rosterCount" and event[field] ~= nil and existing[field] == nil then
            existing[field], changed = event[field], true
        end
    end
    if event.rosterAt and event.rosterAt > (existing.rosterAt or 0) then
        existing.rosterAt, existing.rosterCount, changed = event.rosterAt, event.rosterCount, true
    end
    return changed
end

local function receive(event)
    local key = reportKey(event)
    local existing = note.realmEvents[key]
    if not existing then
        note.realmEvents[key] = event
        return true, true
    end
    if event.receivedGuild and not existing.receivedGuild then
        note.realmEvents[key] = event
        return false, true
    end
    if existing.receivedGuild and not event.receivedGuild then return false, false end
    local changed = false
    if event.receivedGuild and existing.receivedGuild ~= event.receivedGuild then
        existing.receivedGuild, changed = event.receivedGuild, true
    end
    return false, mergeMetadata(existing, event) or changed
end

function note.CurrentGuild()
    if IsInGuild() then return note.Text(GetGuildInfo("player")) end
end

local function sameGuild(a, b)
    return type(a) == "string" and type(b) == "string" and lower(a) == lower(b)
end

local function guildHistory(guild)
    local db = ForeverDeathNoteDB
    db.guildHistory = db.guildHistory or {}
    local realm = db.guildHistory[note.scope] or {}
    db.guildHistory[note.scope] = realm
    local key = lower(guild)
    realm[key] = realm[key] or {}
    return realm[key]
end

local function mergeGuildReport(history, event, guild)
    local key = reportKey(event)
    local existing = history[key]
    if not existing then
        event.receivedGuild = guild
        history[key] = event
        return true, true
    end
    return false, mergeMetadata(existing, event)
end

local function currentHistory(guild, now)
    local history = guildHistory(guild)
    if seededHistories[history] then return history end
    seededHistories[history] = true
    local start = now - retention
    for key, event in pairs(history) do
        if event.at < start then history[key] = nil end
    end
    for _, event in pairs(note.realmEvents) do
        if event.at >= start and sameGuild(event.receivedGuild, guild) then
            local copy = {}
            for key, value in pairs(event) do copy[key] = value end
            mergeGuildReport(history, copy, guild)
        end
    end
    if note.db.sharing then
        for _, entry in ipairs(note.db.events) do
            if entry.at >= start and sameGuild(entry.ownerGuild, guild) then
                mergeGuildReport(history, report(entry, true), guild)
            end
        end
    end
    return history
end

function note.GuildHistoryRecords(guild, now)
    local records = {}
    if not note.db.sharing or not sameGuild(guild, note.CurrentGuild()) then return records end
    now = now or GetServerTime()
    local start = now - retention
    local history = currentHistory(guild, now)
    for key, event in pairs(history) do
        if event.at < start then
            history[key] = nil
        elseif event.at <= now then
            records[key] = encode(event, 4)
        end
    end
    return records
end

function note.ReceiveGuildHistory(payload, guild)
    if not note.db.sharing or not sameGuild(guild, note.CurrentGuild()) then return end
    local now = GetServerTime()
    local event = decode(payload, now, 4)
    if not event then return end
    local reportingGuild = event.victimGuild
    if event.kind == "K" then reportingGuild = event.killerGuild end
    if not sameGuild(reportingGuild, guild) then return end
    local added, changed = mergeGuildReport(currentHistory(guild, now), event, guild)
    local worldReport = {}
    for key, value in pairs(event) do worldReport[key] = value end
    worldReport.receivedGuild = guild
    -- Preserve the world journal's original guild evidence when a relay repeats the same fight.
    local existing = note.realmEvents[reportKey(worldReport)]
    if not existing or not existing.receivedGuild or sameGuild(existing.receivedGuild, guild) then
        local _, updated = receive(worldReport)
        changed = changed or updated
    end
    return added, changed
end

function note.RefreshGuildHistory()
    if note.InvalidateRankHeader then note.InvalidateRankHeader() end
    if note.HuntSync then note.HuntSync() end
    if note.RefreshWindow then note.RefreshWindow() end
    if note.RefreshLadder then note.RefreshLadder() end
    if note.RefreshHuntTracker then note.RefreshHuntTracker() end
end

function note.Export()
    local now, lines = GetServerTime(), { "FDN4" }
    local events = note.db.events
    for i = #events, math.max(1, #events - 99), -1 do
        local entry = events[i]
        if entry.at >= now - retention then lines[#lines + 1] = encode(report(entry), 4) end
    end
    return table.concat(lines, "\n"), #lines - 1
end

function note.Import(text)
    if #text > 90000 then return nil end
    local header, body = text:match("^FDN([1234])\r?\n(.*)$")
    if not header then return nil end
    local events, now = {}, GetServerTime()
    for line in body:gmatch("[^\r\n]+") do
        local event = decode(line, now, tonumber(header))
        if not event or #events >= 100 then return nil end
        events[#events + 1] = event
    end
    if #events == 0 then return nil end
    local added, changed = 0, false
    for _, event in ipairs(events) do
        local isNew, updated = receive(event)
        if isNew then added = added + 1 end
        changed = changed or updated
    end
    if changed and note.InvalidateRankHeader then note.InvalidateRankHeader() end
    if changed and note.RefreshWindow then note.RefreshWindow() end
    if changed and note.RefreshLadder then note.RefreshLadder() end
    return added
end

function note.Flush()
    if sending or #pending == 0 or InCombatLockdown() or IsInInstance() then return end
    if not note.db.sharing or not IsInGuild() then pending = {}; return end
    local event = table.remove(pending, 1)
    if event.guild == GetGuildInfo("player") and GetServerTime() - event.at < 120 then
        C_ChatInfo.SendAddonMessage(prefix, event.text, "GUILD")
        if event.extra then C_ChatInfo.SendAddonMessage(metadataPrefix, event.extra, "GUILD") end
    end
    if #pending > 0 then
        sending = true
        C_Timer.After(1, function() sending = false; note.Flush() end)
    end
end

function note.Publish(entry)
    if not registered or not note.db.sharing then return end
    local guild = note.CurrentGuild()
    if not sameGuild(entry.ownerGuild, guild) then return end
    local history = currentHistory(guild, GetServerTime())
    mergeGuildReport(history, report(entry, true), guild)
    if #pending >= 30 then return end
    local event = report(entry)
    local text = encode(event, 1)
    if #text > 240 then text = encode(event, 1, 2) end
    if #text > 240 then return end
    local extra
    if metadataRegistered then
        extra = encode(event, 4, 2)
        if #extra > 240 then extra = encode(event, 4, 4) end
        if #extra > 240 then extra = nil end
    end
    pending[#pending + 1] = { text = text, extra = extra, at = entry.at, guild = guild }
    note.Flush()
end

function note.StartSharing()
    if not C_ChatInfo or not C_ChatInfo.RegisterAddonMessagePrefix or not C_ChatInfo.SendAddonMessage then return end
    C_ChatInfo.RegisterAddonMessagePrefix(prefix)
    registered = true
    C_ChatInfo.RegisterAddonMessagePrefix(metadataPrefix)
    metadataRegistered = true
    listener:RegisterEvent("CHAT_MSG_ADDON")
    local cutoff = GetServerTime() - retention
    for key, event in pairs(note.realmEvents) do
        if event.at < cutoff then note.realmEvents[key] = nil end
    end
    if note.StartGuildSync then note.StartGuildSync() end
    if note.StartGuildHunts then note.StartGuildHunts() end
    if note.StartGuildProfiles then note.StartGuildProfiles() end
    note.MaybeOfferGuildSharing()
end

function note.ToggleSharing()
    if not registered then return end
    note.db.sharing = not note.db.sharing
    note.db.guildSharingPrompted = true
    if note.db.sharing then seededHistories = {} else pending = {} end
    if note.GuildSharingChanged then note.GuildSharingChanged() end
    if note.GuildHuntSharingChanged then note.GuildHuntSharingChanged() end
    if note.GuildProfilesSharingChanged then note.GuildProfilesSharingChanged() end
    if note.RefreshLadder then note.RefreshLadder() end
end

function note.MaybeOfferGuildSharing()
    if not registered or note.db.sharing or note.db.guildSharingPrompted or not note.CurrentGuild()
        or InCombatLockdown() or not StaticPopupDialogs or not StaticPopup_Show then return end
    if note.MaybeStartGuide and (not ForeverDeathNoteDB.guideSeen or note.GuideVisible()) then return end
    local popup = "FOREVER_DEATH_NOTE_GUILD_SHARING"
    StaticPopupDialogs[popup] = {
        text = L["Включить обмен с гильдией? Согильдейцы с аддоном смогут получить ваши записи PvP за последние 30 дней."],
        button1 = L["Включить обмен с гильдией"],
        button2 = L["Позже"],
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        OnAccept = function()
            if not note.db.sharing and note.CurrentGuild() then note.ToggleSharing() end
        end,
    }
    if StaticPopup_Show(popup) then note.db.guildSharingPrompted = true end
end

listener:SetScript("OnEvent", function(_, _, incomingPrefix, text, channel)
    incomingPrefix = note.Public(incomingPrefix)
    if not note.db.sharing or note.Public(channel) ~= "GUILD"
        or (incomingPrefix ~= prefix and incomingPrefix ~= metadataPrefix) then return end
    local event = decode(note.Public(text), GetServerTime(), incomingPrefix == prefix and 1 or nil)
    if not event then return end
    local reporter = event.kind == "K" and event.killer or event.victim
    if reporter == note.owner then return end
    local guild = note.CurrentGuild()
    if not guild then return end
    event.receivedGuild = guild
    if event.kind == "K" then event.killerGuild = guild else event.victimGuild = guild end
    local copy = {}
    for key, value in pairs(event) do copy[key] = value end
    local _, historyChanged = mergeGuildReport(currentHistory(guild, GetServerTime()), copy, guild)
    local _, changed = receive(event)
    if changed or historyChanged then note.RefreshGuildHistory() end
end)

-- A kill notification can lack spell details. Use the victim's matching death report.
function note.KillingBlow(entry, demo)
    if entry.spellId or entry.spellName or entry.kind ~= "K" or not entry.other or demo then return entry end
    for delta = 0, 3 do
        local first = reportKey({ kind = "D", at = entry.at - delta, killer = note.owner, victim = entry.other })
        local second = reportKey({ kind = "D", at = entry.at + delta, killer = note.owner, victim = entry.other })
        local a, b = note.realmEvents[first], note.realmEvents[second]
        if a and (a.spellId or a.spellName) then return a end
        if b and (b.spellId or b.spellName) then return b end
    end
    return entry
end

function note.ForEachMatchedFight(pair, visit)
    local function earlier(a, b) return a.at < b.at end
    table.sort(pair.K, earlier)
    table.sort(pair.D, earlier)
    local i, j = 1, 1
    while pair.K[i] or pair.D[j] do
        local kill, death = pair.K[i], pair.D[j]
        if kill and death and math.abs(kill.at - death.at) <= 3 then
            i, j = i + 1, j + 1
        elseif kill and (not death or kill.at < death.at) then
            i, death = i + 1, nil
        else
            j, kill = j + 1, nil
        end
        visit(kill, death)
    end
end

local function playerOrder(a, b)
    if a.kills ~= b.kills then return a.kills > b.kills end
    if a.name ~= b.name then return a.name < b.name end
    return a.id < b.id
end

local function victimOrder(a, b)
    if a.count ~= b.count then return a.count > b.count end
    if a.player.name ~= b.player.name then return a.player.name < b.player.name end
    return a.player.id < b.player.id
end

local function guildMember(player, guildName, corroboratedGuild, faction)
    if guildName == nil then guildName = corroboratedGuild end
    if guildName == nil then guildName = player.guild end
    if type(guildName) ~= "string" then return end
    local id = (strlower or string.lower)(guildName)
    local member = player.guildActivity[id]
    if not member then
        member = { id = player.id, name = player.name, guild = guildName, profile = player.profile,
            class = player.class, faction = faction or player.faction, kills = 0, deaths = 0, victims = {} }
        player.guildActivity[id] = member
    elseif faction and member.faction ~= faction then
        member.faction = member.faction and "Mixed" or faction
    end
    return member
end

function note.Ranking(demo, filter, includeGuilds)
    local combined, now = {}, GetServerTime()
    if demo then
        for _, event in ipairs(demo.reports) do combined[reportKey(event)] = event end
    else
        for _, event in pairs(note.realmEvents) do
            if event.at >= now - retention then combined[reportKey(event)] = event end
        end
        for _, entry in ipairs(note.db.events) do
            if entry.at >= now - retention then
                local event = report(entry, true)
                event.source = "own"
                combined[reportKey(event)] = event
            end
        end
    end
    local pairsByID, profiles, rosters = {}, {}, {}
    local lower = strlower or string.lower
    local function keepRoster(guild, count, at)
        if type(guild) ~= "string" or not count or not at or at < now - retention then return end
        local id = lower(guild)
        if not rosters[id] or at >= rosters[id].at then rosters[id] = { count = count, at = at } end
    end
    local roster = not demo and note.db.roster
    if roster then keepRoster(roster.guild, roster.count, roster.at) end
    local function remember(guid, name, guild, faction, at, firsthand, class)
        local profile = profiles[guid] or {}
        if name and (not profile.nameAt or at > profile.nameAt) then
            profile.name, profile.nameAt = name, at
        end
        if type(guild) == "string" and (not profile.guildAt or at > profile.guildAt
            or (at == profile.guildAt and firsthand and not profile.firsthand)) then
            profile.guild, profile.guildAt, profile.firsthand = guild, at, firsthand
        end
        if faction and (not profile.factionAt or at > profile.factionAt) then
            profile.faction, profile.factionAt = faction, at
        end
        if class and (not profile.classAt or at >= profile.classAt) then
            profile.class, profile.classAt = class, at
        end
        profiles[guid] = profile
    end
    for _, event in pairs(combined) do
        local key = event.killer .. ";" .. event.victim
        local pair = pairsByID[key] or { K = {}, D = {}, killer = event.killer, victim = event.victim }
        pair[event.kind][#pair[event.kind] + 1] = event
        pairsByID[key] = pair
    end
    local function rememberEvent(event)
        remember(event.killer, event.killerName, event.killerGuild, event.killerFaction, event.at,
            event.kind == "K", event.killerClass)
        remember(event.victim, event.victimName, event.victimGuild, event.victimFaction, event.at, event.kind == "D")
        local reporterGuild = event.kind == "K" and event.killerGuild or event.victimGuild
        keepRoster(reporterGuild, event.rosterCount, event.rosterAt)
    end

    local players, result, total = {}, {}, 0
    local function player(guid)
        if not players[guid] then
            local profile = demo and (demo.profiles[guid] or {}) or note.Profile(guid)
            local reported = profiles[guid] or {}
            local guild = profile.guild
            if guild == nil then guild = reported.guild end
            local record = { id = guid, profile = profile,
                name = profile.name or reported.name or L["Имя неизвестно"],
                guild = guild or nil, faction = profile.faction or reported.faction,
                class = profile.class or reported.class, kills = 0, deaths = 0, victims = {},
                sources = { own = 0, guild = 0, imported = 0 }, guildActivity = includeGuilds and {} or nil }
            players[guid] = record
            result[#result + 1] = record
        end
        return players[guid]
    end
    local stats = { classes = {}, unknown = 0, withSpell = 0,
        factions = { Horde = 0, Alliance = 0, unknown = 0 },
        factionSources = { Horde = { own = 0, guild = 0, imported = 0 },
            Alliance = { own = 0, guild = 0, imported = 0 } } }
    local sources = { own = 0, guild = 0, imported = 0 }
    local function killingSpell(report, corroboration)
        local spell = note.SpellName(report.spellId, report.spellName, demo)
        if not spell and corroboration then
            report = corroboration
            spell = note.SpellName(report.spellId, report.spellName, demo)
        end
        return spell, report.spellId
    end
    local function countClass(class, spell, spellId)
        if spell then stats.withSpell = stats.withSpell + 1 end
        if not class then stats.unknown = stats.unknown + 1; return end
        local row = stats.classes[class] or { class = class, kills = 0, known = 0, spells = {}, spellIds = {} }
        stats.classes[class] = row
        row.kills = row.kills + 1
        if spell then
            row.known = row.known + 1
            row.spells[spell] = (row.spells[spell] or 0) + 1
            if spellId then row.spellIds[spell] = row.spellIds[spell] or spellId end
        end
    end
    for _, pair in pairs(pairsByID) do
        local fights = {}
        note.ForEachMatchedFight(pair, function(kill, death)
            local killSource, deathSource = source(kill), source(death)
            local primary = (strength[killSource] or 0) > (strength[deathSource] or 0) and killSource or deathSource
            sources[primary] = sources[primary] + 1
            if not filter or filter == primary then
                if filter and killSource ~= primary then kill = nil end
                if filter and deathSource ~= primary then death = nil end
                if kill then rememberEvent(kill) end
                if death then rememberEvent(death) end
                local first, second = death, kill
                if (strength[killSource] or 0) > (strength[deathSource] or 0) then first, second = kill, death end
                fights[#fights + 1] = { first = first, second = second, source = primary }
            end
        end)
        pair.fights = fights
    end
    for _, pair in pairs(pairsByID) do
        local count = #pair.fights
        if count > 0 then
            local killer, victim = player(pair.killer), player(pair.victim)
            local levels = {}
            for _, fight in ipairs(pair.fights) do
                local first, second = fight.first, fight.second
                local level = first.victimLevel or second and second.victimLevel or 0
                levels[level] = (levels[level] or 0) + 1
                local spell, spellId = killingSpell(first, second)
                local class = first.killerClass or (second and second.killerClass) or killer.class
                countClass(class, spell, spellId)
                if spell then
                    local at = math.max(first.at, second and second.at or first.at)
                    local latest = killer.latestStrike
                    if not latest or at > latest.at or (at == latest.at and spell < latest.name) then
                        killer.latestStrike = { at = at, name = spell, id = spellId }
                    end
                end
                local faction = note.Faction(first.killerFaction)
                    or (second and note.Faction(second.killerFaction)) or note.Faction(killer.faction) or "unknown"
                stats.factions[faction] = stats.factions[faction] + 1
                local bySource = stats.factionSources[faction]
                if bySource then bySource[fight.source] = bySource[fight.source] + 1 end
                killer.sources[fight.source] = killer.sources[fight.source] + 1
                if includeGuilds then
                    local member = guildMember(killer, first.killerGuild, second and second.killerGuild,
                        faction ~= "unknown" and faction or nil)
                    if member then
                        member.kills = member.kills + 1
                        local defeated = member.victims[victim.id]
                        if not defeated then
                            defeated = { player = victim, count = 0, levels = {} }
                            member.victims[victim.id] = defeated
                        end
                        defeated.count = defeated.count + 1
                        defeated.levels[level] = (defeated.levels[level] or 0) + 1
                    end
                    member = guildMember(victim, first.victimGuild, second and second.victimGuild,
                        note.Faction(first.victimFaction) or second and note.Faction(second.victimFaction))
                    if member then member.deaths = member.deaths + 1 end
                end
            end
            killer.kills, victim.deaths = killer.kills + count, victim.deaths + count
            killer.victims[#killer.victims + 1] = { player = victim, count = count, levels = levels }
            total = total + count
        end
    end
    for _, row in ipairs(result) do
        table.sort(row.victims, victimOrder)
        if includeGuilds then
            for _, member in pairs(row.guildActivity) do
                local victims = {}
                for _, defeated in pairs(member.victims) do victims[#victims + 1] = defeated end
                table.sort(victims, victimOrder)
                member.victims = victims
            end
        end
    end
    table.sort(result, playerOrder)
    return result, total, rosters, stats, sources
end

function note.GuildRanking(players, rosters)
    local groups, result = {}, {}
    local function addMember(id, member)
        local guild = groups[id]
        if not guild then
            guild = { id = id, name = member.guild, kills = 0, deaths = 0, members = {} }
            local roster = rosters and rosters[id]
            if roster then guild.rosterCount, guild.rosterAt = roster.count, roster.at end
            groups[id] = guild
            result[#result + 1] = guild
        end
        if member.faction then
            if not guild.faction then
                guild.faction = member.faction
            elseif guild.faction ~= member.faction then
                guild.faction = "Mixed"
            end
        end
        guild.kills = guild.kills + member.kills
        guild.deaths = guild.deaths + member.deaths
        guild.members[#guild.members + 1] = member
    end
    for _, player in ipairs(players) do
        if player.guildActivity then
            for id, member in pairs(player.guildActivity) do addMember(id, member) end
        elseif player.guild then
            addMember((strlower or string.lower)(player.guild), player)
        end
    end
    for _, guild in ipairs(result) do table.sort(guild.members, playerOrder) end
    table.sort(result, function(a, b)
        if a.kills ~= b.kills then return a.kills > b.kills end
        if a.deaths ~= b.deaths then return a.deaths < b.deaths end
        return a.name < b.name
    end)
    return result
end

function note.GuildKillLeaders(guild)
    local leaders = {}
    for _, member in ipairs(guild.members) do
        if member.kills <= 0 or #leaders == 3 then break end
        leaders[#leaders + 1] = member
    end
    return leaders
end

function note.GuildLadderPlayers(sample)
    local guild = sample and sample.profiles.self.guild or note.CurrentGuild()
    local list = {}
    if not guild then return list end
    local now = GetServerTime()
    local history = sample and sample.reports or currentHistory(guild, now)
    local byPlayer, victimsByPlayer, counted = {}, {}, {}
    for _, event in pairs(history) do
        -- A member's kill report is the scoring record. Death reports can accompany the same fight.
        if event.kind == "K" and sameGuild(event.killerGuild, guild)
            and (sample or event.at >= now - retention and event.at <= now) then
            local key = reportKey(event)
            if not counted[key] then
                counted[key] = true
                local id = event.killer
                local player = byPlayer[id]
                if not player then
                    player = { id = id, name = L["Имя неизвестно"], class = nil, guild = guild, kills = 0,
                        victims = {}, profile = { guild = guild } }
                    byPlayer[id], victimsByPlayer[id] = player, {}
                    list[#list + 1] = player
                end
                if event.killerName and (not player.nameAt or event.at > player.nameAt
                    or event.at == player.nameAt and event.killerName < player.name) then
                    player.nameAt, player.name, player.profile.name = event.at, event.killerName, event.killerName
                end
                if event.killerClass and (not player.classAt or event.at > player.classAt
                    or event.at == player.classAt and event.killerClass < player.class) then
                    player.classAt, player.class, player.profile.class = event.at, event.killerClass, event.killerClass
                end
                if event.killerFaction and (not player.factionAt or event.at > player.factionAt
                    or event.at == player.factionAt and event.killerFaction < player.profile.faction) then
                    player.factionAt, player.profile.faction = event.at, event.killerFaction
                end
                player.kills = player.kills + 1
                local victim = victimsByPlayer[id][event.victim]
                if not victim then
                    local name = note.Text(event.victimName) or L["Имя неизвестно"]
                    victim = { player = { id = event.victim, name = name, guild = event.victimGuild,
                        profile = { name = name, guild = event.victimGuild, faction = event.victimFaction } },
                        count = 0, levels = {} }
                    victimsByPlayer[id][event.victim] = victim
                    player.victims[#player.victims + 1] = victim
                end
                victim.count = victim.count + 1
                local level = event.victimLevel or 0
                victim.levels[level] = (victim.levels[level] or 0) + 1
            end
        end
    end
    for _, player in ipairs(list) do table.sort(player.victims, victimOrder) end
    table.sort(list, playerOrder)
    return list
end
