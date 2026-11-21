local _, note = ...
local L = note.L
local day, week = 86400, 7 * 86400
local weeklyGoals = {
    { id = "peers", name = "Равный бой", target = 3,
        description = "Добейте 3 разных противников. Разница в уровнях не больше пяти." },
    { id = "revenge", name = "Долги уплачены", target = 2,
        description = "Возьмите реванш у 2 разных игроков, убивших вас на этой неделе." },
    { id = "zones", name = "Следопыт", target = 2,
        description = "Добейте разных противников в 2 разных зонах открытого мира." },
    { id = "guild", name = "Ответ гильдии", target = 1,
        description = "Лично отомстите за согильдейца из гильдейского журнала." },
}

local cosmetics = {
    { id = "classic", kind = "cover", name = "Полевой журнал", palette = { 0.64, 0.48, 0.25 },
        description = "Классическая золотая рамка.", requirement = "Доступно сразу" },
    { id = "ember", kind = "cover", name = "Угли войны", palette = { 0.84, 0.38, 0.19 },
        description = "Медное оформление страниц.", requirement = "Получить 3 печати", seals = 3 },
    { id = "night", kind = "cover", name = "Ночная стража", palette = { 0.51, 0.63, 0.88 },
        description = "Серебристо-синее оформление страниц.", requirement = "Выполнить цели в 3 разных неделях", weeks = 3 },
    { id = "plain", kind = "title", name = "Без титула", palette = { 0.87, 0.77, 0.58 },
        description = "Имя без дополнительных подписей.", requirement = "Доступно сразу" },
    { id = "hunter", kind = "title", name = "Охотник за долгами", palette = { 0.90, 0.66, 0.34 },
        description = "Подпись в личной книге охоты.", requirement = "Получить 5 печатей", seals = 5 },
    { id = "warden", kind = "title", name = "Хранитель тетради", palette = { 0.66, 0.77, 0.98 },
        description = "Подпись в личной книге охоты.", requirement = "Выполнить цели в 6 разных неделях", weeks = 6 },
    { id = "avenged", kind = "stamp", name = "Отомщено", palette = { 0.84, 0.38, 0.27 },
        description = "Штамп в досье обидчика после реванша.", requirement = "Завершить первый реванш", revenge = true },
}

local cosmeticsById = {}
for _, item in ipairs(cosmetics) do cosmeticsById[item.id] = item end

local function weekStart(timestamp)
    return math.floor((timestamp + 3 * day) / week) * week - 3 * day
end

function note.HuntTimeRemaining(stamp, now)
    local span = math.max(0, stamp - now)
    if span >= 86400 then
        return (L["%dд %dч"]):format(math.floor(span / 86400), math.floor(span % 86400 / 3600))
    elseif span >= 3600 then
        return (L["%dч %dм"]):format(math.floor(span / 3600), math.floor(span % 3600 / 60))
    end
    return (L["%dм"]):format(math.ceil(span / 60))
end

local function huntState(source)
    if not source.hunt then source.hunt = { seals = 0, awarded = {} } end
    local state = source.hunt
    state.seals = state.seals or 0
    state.awarded = state.awarded or {}
    state.archive = state.archive or {}
    state.unlocked = state.unlocked or {}
    return state
end

local function countNew(seen, key)
    if key and not seen[key] then seen[key] = true; return 1 end
    return 0
end

local function countAwards(awarded)
    local count = 0
    for _, value in pairs(awarded) do
        if value then count = count + 1 end
    end
    return count
end

local function importantGuildRevenge(demo, start, now)
    if not note.GuildThreats then return 0 end
    local threats = note.GuildThreats(demo)
    local player = demo and "self" or note.owner
    for _, threat in ipairs(threats) do
        for _, entry in ipairs(threat.history) do
            if entry.kind == "K" and entry.revenge and entry.member == player and entry.victim
                and entry.victim ~= player and entry.at >= start and entry.at <= now then return 1 end
        end
    end
    return 0
end

local function rangeEntries(events, start, now)
    local entries = {}
    for _, entry in ipairs(events) do
        if entry.at >= start and entry.at <= now then entries[#entries + 1] = entry end
    end
    return entries
end

local function orderedBefore(a, b)
    if a.at ~= b.at then return a.at < b.at end
    if a.kind ~= b.kind then return a.kind == "K" end
    return a.other < b.other
end

local function weeklyProgress(entries, start, contractEvents)
    local mapByZone = {}
    for _, entry in ipairs(entries) do
        if entry.zone and entry.mapId then mapByZone[entry.zone] = entry.mapId end
    end
    table.sort(entries, orderedBefore)

    local progress = { peers = 0, revenge = 0, zones = 0, guild = 0 }
    local report = { start = start, ends = start + week, uniqueVictims = 0, revenges = 0,
        zoneFights = 0, contracts = 0, seals = 0, goalsCompleted = 0 }
    local peers, defeated, avenged, outstanding, locations = {}, {}, {}, {}, {}
    local firstZone, firstOpponent, otherZone, otherOpponent
    for _, entry in ipairs(entries) do
        local other = entry.other
        local zone = entry.mapId or mapByZone[entry.zone] or entry.zone
        if zone then
            local location = locations[zone] or { count = 0 }
            location.count = location.count + 1
            location.name = entry.zone or location.name
            locations[zone] = location
        end

        if entry.kind == "D" then
            outstanding[other] = (outstanding[other] or 0) + 1
        elseif entry.kind == "K" then
            report.uniqueVictims = report.uniqueVictims + countNew(defeated, other)
            local level, foeLevel = entry.actorLevel, entry.victimLevel
            if type(level) == "number" and type(foeLevel) == "number" and math.abs(level - foeLevel) <= 5 then
                progress.peers = progress.peers + countNew(peers, other)
            end
            local debt = outstanding[other] or 0
            if debt > 0 then
                report.revenges = report.revenges + 1
                progress.revenge = progress.revenge + countNew(avenged, other)
                outstanding[other] = debt - 1
            elseif contractEvents and contractEvents[other] == entry.at then
                report.revenges = report.revenges + 1
            end
            if zone and not firstZone then
                firstZone, firstOpponent, progress.zones = zone, other, 1
            elseif zone and progress.zones == 1 then
                otherZone = otherZone or zone ~= firstZone
                otherOpponent = otherOpponent or other ~= firstOpponent
                if otherZone and otherOpponent then progress.zones = 2 end
            end
        end
    end
    for _, location in pairs(locations) do
        if location.name and (location.count > report.zoneFights
            or location.count == report.zoneFights and location.name < report.busiestZone) then
            report.busiestZone, report.zoneFights = location.name, location.count
        end
    end
    return progress, report
end

local function firstRecordedRevenge(events, now)
    local firstDeath = {}
    for _, entry in ipairs(events) do
        if entry.kind == "D" and (not firstDeath[entry.other] or entry.at < firstDeath[entry.other]) then
            firstDeath[entry.other] = entry.at
        end
    end
    local first
    for _, entry in ipairs(events) do
        local death = firstDeath[entry.other]
        if entry.kind == "K" and entry.at <= now and death and entry.at > death
            and (not first or entry.at < first) then first = entry.at end
    end
    return first
end

local function historicalContractEvents(state, start)
    local events = {}
    for id, at in pairs(state.lastContractReward or {}) do
        if type(at) == "number" and at >= start and at < start + week then events[id] = at end
    end
    return events
end

local function extraReportTotals(report, awarded, contracts)
    local count = 0
    for _ in pairs(contracts) do count = count + 1 end
    report.goalsCompleted = countAwards(awarded)
    report.contracts = count
    report.seals = report.goalsCompleted + report.contracts
end

local function backfillArchive(source, state, start)
    if state.archiveReady then return end
    local byWeek = {}
    for _, entry in ipairs(source.events) do
        local entryWeek = weekStart(entry.at)
        if entryWeek < start and entryWeek ~= state.week and not state.archive[entryWeek] then
            local bucket = byWeek[entryWeek] or {}
            bucket[#bucket + 1] = entry
            byWeek[entryWeek] = bucket
        end
    end
    for entryWeek, entries in pairs(byWeek) do
        local contracts = historicalContractEvents(state, entryWeek)
        local _, report = weeklyProgress(entries, entryWeek, contracts)
        extraReportTotals(report, {}, contracts)
        state.archive[entryWeek] = report
    end
    state.archiveReady = true
end

local function updateCosmetics(state)
    local weeks = 0
    for _, report in pairs(state.archive) do
        if (report.goalsCompleted or 0) > 0 then weeks = weeks + 1 end
    end
    if countAwards(state.awarded) > 0 then weeks = weeks + 1 end
    for _, item in ipairs(cosmetics) do
        if (not item.seals or state.seals >= item.seals)
            and (not item.weeks or weeks >= item.weeks)
            and (not item.revenge or state.firstRevenge) then
            state.unlocked[item.id] = true
        end
    end
end

local cache = setmetatable({}, { __mode = "k" })

local function evaluate(source, demo, now)
    local state = huntState(source)
    local start = weekStart(now)
    local previous = cache[source]
    local count = #source.events
    local guild = (source.profiles[demo and "self" or note.owner] or {}).guild
    if previous and now >= previous.at and now - previous.at <= 2 and previous.report.start == start
        and previous.events == source.events and previous.count == count
        and previous.last == source.events[count] and previous.guild == guild then
        return state, previous.progress, previous.report
    end

    backfillArchive(source, state, start)
    if not state.firstRevenge then
        state.firstRevenge = firstRecordedRevenge(source.events, now)
        if not state.firstRevenge and state.contract then state.firstRevenge = state.contract.completed end
    end
    if state.week and state.week < start then
        local closed = state.week
        local contracts = historicalContractEvents(state, closed)
        local entries = rangeEntries(source.events, closed, closed + week - 1)
        local _, report = weeklyProgress(entries, closed, contracts)
        extraReportTotals(report, state.awarded, contracts)
        if not state.archive[closed] and (#entries > 0 or report.seals > 0) then
            state.archive[closed] = report
        end
        state.week, state.awarded = start, {}
    elseif not state.week then
        state.week = start
    end

    local contracts = historicalContractEvents(state, start)
    local progress, report = weeklyProgress(rangeEntries(source.events, start, now), start, contracts)
    if state.week == start then
        progress.guild = state.awarded.guild and 1 or importantGuildRevenge(demo, start, now)
        for _, goal in ipairs(weeklyGoals) do
            if progress[goal.id] >= goal.target and not state.awarded[goal.id] then
                state.awarded[goal.id] = true
                state.seals = state.seals + 1
            end
        end
        extraReportTotals(report, state.awarded, contracts)
    elseif state.archive[start] then
        report = state.archive[start]
    end
    updateCosmetics(state)
    cache[source] = { at = now, events = source.events, count = count, last = source.events[count],
        progress = progress, report = report, guild = guild }
    return state, progress, report
end

function note.HuntOverview(demo, now)
    local source = demo or note.db
    now = now or GetServerTime()
    local state, progress, report = evaluate(source, demo, now)
    local result = {}
    for _, goal in ipairs(weeklyGoals) do
        local id = "hunt:" .. goal.id
        local earned = state.week == report.start and state.awarded[goal.id] or false
        result[#result + 1] = {
            id = id, name = L[goal.name], description = L[goal.description],
            amount = earned and goal.target or math.min(goal.target, progress[goal.id]),
            target = goal.target, earned = earned, tracked = state.tracked == id, expires = report.ends,
        }
    end
    local contract = state.contract
    if contract then
        local profile = source.profiles[contract.id]
        result[#result + 1] = {
            id = "hunt:contract", name = profile and profile.name or L["Неизвестный обидчик"],
            description = L["Личная цель на семь дней. Добивание засчитывается после выбора цели."],
            amount = contract.completed and 1 or 0, target = 1,
            earned = contract.completed ~= nil, contract = true,
            expires = contract.expires, expired = not contract.completed and now > contract.expires,
            rivalId = contract.id, started = contract.started, death = contract.death,
            completed = contract.completed, tracked = state.tracked == "hunt:contract",
        }
    end
    return result, state.seals, report.ends, report
end

local function present(demo)
    if note.HuntPresentationChanged then
        note.HuntPresentationChanged(demo)
    else
        if note.RefreshWindow then note.RefreshWindow() end
        if note.RefreshHuntTracker then note.RefreshHuntTracker() end
    end
end

local function eligibility(state, id, death, now)
    if not death then return L["Эта цель ещё не убивала вас."] end
    if state.lastContractReward and (state.lastContractReward[id] or 0) >= weekStart(now) then
        return L["За этого обидчика уже получена печать на этой неделе."]
    end
    if state.lastContractDeath and (state.lastContractDeath[id] or 0) >= death then
        return L["Реванш за эту смерть уже засчитан."]
    end
end

local targetCache = setmetatable({}, { __mode = "k" })

local function targetDetails(source, id)
    local events = source.events
    local count, last = #events, events[#events]
    local detail = targetCache[source]
    if not detail or detail.id ~= id or detail.events ~= events or detail.count ~= count or detail.last ~= last then
        detail = { id = id, events = events, count = count, last = last, kills = 0, deaths = 0 }
        for _, entry in ipairs(events) do
            if entry.other == id then
                if entry.kind == "K" then
                    detail.kills = detail.kills + 1
                elseif entry.kind == "D" then
                    detail.deaths = detail.deaths + 1
                    if not detail.lastDeath or entry.at >= detail.lastDeath.at then detail.lastDeath = entry end
                end
                if not detail.entry or entry.at >= detail.entry.at then detail.entry = entry end
            end
        end
        targetCache[source] = detail
    end
    local profile = source.profiles[id] or {}
    return { id = id, profile = profile, name = profile.name or L["Неизвестный обидчик"],
        kills = detail.kills, deaths = detail.deaths, entry = detail.entry, lastDeath = detail.lastDeath }
end

function note.ActiveHuntRival(demo, now)
    local source = demo or note.db
    local state = source and source.hunt
    local contract = state and state.contract
    now = now or GetServerTime()
    if contract and not contract.completed and now <= contract.expires then return contract.id end
end

function note.GetHuntTarget(demo, now)
    local source = demo or note.db
    local state = source and source.hunt
    local contract = state and state.contract
    if not contract then return nil end
    local result = targetDetails(source, contract.id)
    result.started, result.death, result.expires = contract.started, contract.death, contract.expires
    result.completed = contract.completed
    result.expired = not contract.completed and (now or GetServerTime()) > contract.expires
    if not demo and note.GetHuntSighting then
        result.sighting = note.GetHuntSighting(contract.id)
        if result.sighting then result.lastSeen = (now or GetServerTime()) - (result.sighting.age or 0) end
    end
    return result
end

function note.HasHiddenHuntRivals(demo)
    local source = demo or note.db
    local hidden = source and source.hunt and source.hunt.hiddenRivals
    return hidden ~= nil and next(hidden) ~= nil
end

function note.SetHuntRivalHidden(id, hidden, demo)
    local source = demo or note.db
    if not source or not id then return false end
    local state = huntState(source)
    state.hiddenRivals = state.hiddenRivals or {}
    state.hiddenRivals[id] = hidden and true or nil
    if hidden and state.contract and state.contract.id == id then
        state.contract = nil
        if state.tracked == "hunt:contract" then
            state.tracked = nil
            source.huntTrackerVisible = false
        end
        if not demo and note.GuildHuntContractChanged then note.GuildHuntContractChanged() end
    end
    present(demo)
    return true
end

function note.HuntCandidates(demo, now, view)
    local source = demo or note.db
    if not source then return {} end
    local state = huntState(source)
    now = now or GetServerTime()
    local byId, result = {}, {}
    local hidden = state.hiddenRivals or {}
    local hiddenOnly = view == "hidden"
    local function candidate(id)
        local row = byId[id]
        if not row then
            local profile = source.profiles[id] or {}
            row = { id = id, profile = profile, name = profile.name or L["Неизвестный обидчик"],
                kills = 0, deaths = 0 }
            byId[id] = row
        end
        return row
    end
    for _, entry in ipairs(source.events) do
        if (hidden[entry.other] == true) == hiddenOnly then
            local row = candidate(entry.other)
            if entry.kind == "D" then
                row.deaths = row.deaths + 1
                if not row.lastDeath or entry.at >= row.lastDeath.at then row.lastDeath = entry end
            elseif entry.kind == "K" then
                row.kills = row.kills + 1
            end
            if not row.entry or entry.at >= row.entry.at then row.entry = entry end
        end
    end
    if hiddenOnly then
        for id in pairs(hidden) do candidate(id) end
    end
    for _, row in pairs(byId) do
        if hiddenOnly or not eligibility(state, row.id, row.lastDeath and row.lastDeath.at, now) then
            result[#result + 1] = row
        end
    end
    table.sort(result, function(a, b)
        if a.deaths ~= b.deaths then return a.deaths > b.deaths end
        local aDeath = a.lastDeath and a.lastDeath.at or 0
        local bDeath = b.lastDeath and b.lastDeath.at or 0
        if aDeath ~= bDeath then return aDeath > bDeath end
        return a.id < b.id
    end)
    if not view then
        for i = #result, 6, -1 do result[i] = nil end
    end
    return result
end

function note.TrackHuntRival(id, demo)
    local source = demo or note.db
    local details = targetDetails(source, id)
    local now = GetServerTime()
    local state = huntState(source)
    local current = state.contract
    if current and current.id == id and not current.completed and now <= current.expires then
        return true, L["Цель уже отслеживается во вкладке «Охота»."]
    end
    local latest = details.lastDeath and details.lastDeath.at
    local reason = eligibility(state, id, latest, now)
    if reason then return false, reason end
    state.contract = { id = id, death = latest, started = now, expires = now + week }
    if state.hiddenRivals then state.hiddenRivals[id] = nil end
    state.tracked = "hunt:contract"
    if not demo and note.GuildHuntContractChanged then note.GuildHuntContractChanged() end
    present(demo)
    return true, L["Цель добавлена во вкладку «Охота»."]
end

function note.TrackHuntGoal(id, demo)
    local source = demo or note.db
    local state = huntState(source)
    if not id or state.tracked == id then
        state.tracked = nil
        present(demo)
        return true
    end
    local goals = note.HuntOverview(demo)
    for _, goal in ipairs(goals) do
        if goal.id == id then
            state.tracked = id
            present(demo)
            return true
        end
    end
    return false
end

function note.GetTrackedHuntGoal(demo, now)
    local source = demo or note.db
    local state = source and source.hunt
    if not state or not state.tracked then return nil end
    local goals = note.HuntOverview(demo, now)
    for _, goal in ipairs(goals) do
        if goal.id == state.tracked then return goal end
    end
end

note.HuntTrackedGoal = note.GetTrackedHuntGoal

function note.HuntArchive(demo, now)
    local source = demo or note.db
    local state = evaluate(source, demo, now or GetServerTime())
    local reports = {}
    for _, report in pairs(state.archive) do reports[#reports + 1] = report end
    table.sort(reports, function(a, b) return a.start > b.start end)
    return reports
end

function note.HuntCollection(demo, now)
    local source = demo or note.db
    local state = evaluate(source, demo, now or GetServerTime())
    local cover, title = state.cover or "classic", state.title or "plain"
    local rows = {}
    for _, item in ipairs(cosmetics) do
        rows[#rows + 1] = {
            id = item.id, kind = item.kind, name = L[item.name], description = L[item.description],
            requirement = L[item.requirement], palette = item.palette, unlocked = state.unlocked[item.id] == true,
            selected = item.id == cover or item.id == title or (item.revenge and state.firstRevenge ~= nil),
        }
    end
    return rows
end

function note.SelectHuntCosmetic(id, demo)
    local source = demo or note.db
    local state = evaluate(source, demo, GetServerTime())
    local cosmetic = cosmeticsById[id]
    if not cosmetic or cosmetic.kind == "stamp" or not state.unlocked[id] then return false end
    state[cosmetic.kind] = id
    present(demo)
    return true
end

function note.GetHuntStyle(demo)
    local source = demo or note.db
    local state = source and source.hunt
    return {
        cover = cosmeticsById[state and state.cover or "classic"] or cosmeticsById.classic,
        title = cosmeticsById[state and state.title or "plain"] or cosmeticsById.plain,
        firstRevenge = state and state.firstRevenge,
    }
end

function note.HuntSync()
    if not note.db then return end
    cache[note.db] = nil
    note.HuntOverview(nil)
end

function note.HuntRecord(entry)
    local source = note.db
    local state = huntState(source)
    local previousSeals = state.seals
    cache[source] = nil
    local now = GetServerTime()
    evaluate(source, nil, now)

    local contract = state.contract
    local completed = entry.kind == "K" and contract and contract.id == entry.other and not contract.completed
        and entry.at > contract.started and entry.at <= contract.expires
    if completed then
        contract.completed = entry.at
        state.seals = state.seals + 1
        state.firstRevenge = state.firstRevenge or entry.at
        state.lastContractDeath = state.lastContractDeath or {}
        state.lastContractDeath[entry.other] = contract.death
        state.lastContractReward = state.lastContractReward or {}
        state.lastContractReward[entry.other] = entry.at
        cache[source] = nil
        evaluate(source, nil, now)
        if note.GuildHuntContractChanged then note.GuildHuntContractChanged() end
    end

    local earned = state.seals - previousSeals
    if completed and note.NotifyHuntRevenge then
        local details = targetDetails(source, entry.other)
        note.NotifyHuntRevenge(entry.other, details.kills, details.deaths, {
            entry = entry, at = entry.at, seals = 1, totalEarned = earned,
        })
    elseif earned > 0 and DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage((L["|cffffd276Тетрадь смерти|r • Охота: печати +%d"]):format(earned))
    end
    if note.RefreshHuntTracker then note.RefreshHuntTracker() end
end
