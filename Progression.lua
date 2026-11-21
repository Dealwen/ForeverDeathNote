local _, note = ...
local L, day = note.L, 86400
local icons = "Interface\\Icons\\"

local ranks = {
    { name = "Безобидная овечка", kills = 0, victims = 0, color = { 0.83, 0.80, 0.74 }, icon = icons .. "Spell_Nature_Polymorph" },
    { name = "Прохожий с алиби", kills = 1, victims = 1, color = { 0.76, 0.85, 0.57 }, icon = icons .. "INV_Misc_Book_09" },
    { name = "Дежурный по кладбищу", kills = 5, victims = 3, color = { 0.60, 0.84, 0.92 }, icon = icons .. "Spell_Shadow_AnimateDead" },
    { name = "Инспектор добиваний", kills = 12, victims = 6, color = { 0.73, 0.71, 1 }, icon = icons .. "INV_Sword_27" },
    { name = "Причина закрыть таверну", kills = 25, victims = 12, color = { 0.91, 0.66, 1 }, icon = icons .. "INV_Drink_05" },
    { name = "Начальник отдела возмездия", kills = 50, victims = 22, color = { 0.99, 0.77, 0.45 }, icon = icons .. "Ability_Warrior_Revenge" },
    { name = "Повод для эвакуации", kills = 75, victims = 30, color = { 1, 0.65, 0.39 }, icon = icons .. "Spell_Fire_Incinerate" },
    { name = "Яростный гневный убийца", kills = 100, victims = 40, color = { 1, 0.55, 0.37 }, icon = icons .. "Ability_Warrior_Rampage" },
}
local achievements = {
    { id = "kills", name = "Первый протокол", text = "Сделайте первое добивание в открытом мире.", target = 1,
        icon = icons .. "INV_Misc_Book_09" },
    { id = "revenge", name = "Долг закрыт", text = "Добейте соперника после того, как он убил вас.", target = 1,
        icon = icons .. "Ability_Warrior_Revenge" },
    { id = "victims", name = "Знакомые лица", text = "Добейте 5 разных противников.", target = 5,
        icon = icons .. "Ability_DualWield" },
    { id = "zones", name = "Тур по кладбищам", text = "Добейтесь победы в 3 разных зонах.", target = 3,
        icon = icons .. "INV_Misc_Map_01" },
    { id = "fair", name = "По всем правилам", text = "Добейте 3 разных соперников с разницей в уровне не больше 5.", target = 3,
        icon = icons .. "Ability_Parry" },
    { id = "streak", name = "Третий лишний", text = "Добейте 3 разных соперников за одну серию без смертей в PvP.", target = 3,
        icon = icons .. "Ability_Warrior_Cleave" },
    { id = "days", name = "Посещаемость отличная", text = "Запишите добивания в 5 разных днях по UTC.", target = 5,
        icon = icons .. "INV_Misc_Note_02" },
    { id = "rivals", name = "Отдел по возврату долгов", text = "Возьмите реванш у 3 разных игроков, ранее убивших вас.", target = 3,
        icon = icons .. "INV_Misc_Coin_02" },
    { id = "shift", name = "Рабочая смена", text = "Запишите 25 личных добиваний.", target = 25,
        icon = icons .. "INV_Misc_Tool_01" },
    { id = "rampage", name = "Пять черепов", text = "Совершите пять добиваний подряд до истечения таймеров серии.", target = 1,
        icon = icons .. "Ability_Warrior_Rampage" },
}

note.LadderRanks = ranks
note.LadderAchievementRules = achievements

function note.LadderRank(kills, victims)
    for i = #ranks, 1, -1 do
        local rank = ranks[i]
        if kills >= rank.kills and victims >= rank.victims then return rank, ranks[i + 1], i end
    end
end

function note.LadderPersonal(sample, now)
    now = now or GetServerTime()
    local cutoff = now - 30 * day
    local kills, unique, victims = 0, 0, {}
    for _, event in ipairs((sample or note.db).events) do
        if event.kind == "K" and (sample or (event.at >= cutoff and event.at <= now)) then
            kills = kills + 1
            if not victims[event.other] then
                victims[event.other], unique = true, unique + 1
            end
        end
    end
    return kills, unique
end

local cache = setmetatable({}, { __mode = "k" })

local function credit(state, id, value)
    if value ~= nil and not state.seen[id][value] then
        state.seen[id][value] = true
        state.progress[id] = state.progress[id] + 1
    end
end

local function countEvent(state, event, liveEntry, earned)
    local progress, other = state.progress, event.other
    if event.kind == "D" then
        state.firstDeathTo[other] = state.firstDeathTo[other] or event.at
        state.streak, state.streakVictims = 0, {}
        return
    end
    if event.kind ~= "K" then return end
    progress.kills, progress.shift = progress.kills + 1, progress.shift + 1
    credit(state, "victims", other)
    credit(state, "zones", note.EncounterMapID(event) or event.zone)
    credit(state, "days", math.floor(event.at / day))
    local ownLevel, victimLevel = event.actorLevel, event.victimLevel
    if ownLevel and victimLevel and ownLevel > 0 and victimLevel > 0 and math.abs(ownLevel - victimLevel) <= 5 then
        credit(state, "fair", other)
    end
    if state.firstDeathTo[other] and state.firstDeathTo[other] < event.at then
        credit(state, "rivals", other)
        progress.revenge = 1
    end
    if not state.streakVictims[other] then
        state.streakVictims[other] = true
        state.streak = state.streak + 1
        progress.streak = math.max(progress.streak, state.streak)
    end
    for _, rule in ipairs(achievements) do
        if not state.awards[rule.id] and progress[rule.id] >= rule.target then
            state.awards[rule.id] = event.at
            if event == liveEntry then earned[#earned + 1] = L[rule.name] end
        end
    end
end

local function evaluate(source, liveEntry, earned)
    local events, state = source.events, cache[source]
    source.ladderAwards = source.ladderAwards or {}
    local awards = source.ladderAwards
    if state and state.events == events and state.awards == awards and state.count <= #events
        and events[state.count] == state.tail then
        local last = state.lastAt
        local append = true
        for i = state.count + 1, #events do
            if events[i].at < last then append = false; break end
            last = events[i].at
        end
        if append then
            for i = state.count + 1, #events do countEvent(state, events[i], liveEntry, earned) end
            state.count, state.tail, state.lastAt = #events, events[#events], last
            return awards, state.progress
        end
    end

    state = { events = events, awards = awards, count = #events, tail = events[#events],
        lastAt = 0, seen = { victims = {}, zones = {}, days = {}, fair = {}, rivals = {} },
        progress = {}, firstDeathTo = {}, streak = 0, streakVictims = {} }
    for _, rule in ipairs(achievements) do state.progress[rule.id] = 0 end
    local outOfOrder = false
    for _, event in ipairs(events) do
        if event.at < state.lastAt then outOfOrder = true end
        state.lastAt = math.max(state.lastAt, event.at)
    end
    if outOfOrder then
        local order = {}
        for i = 1, #events do order[i] = i end
        table.sort(order, function(a, b)
            if events[a].at ~= events[b].at then return events[a].at < events[b].at end
            return a < b
        end)
        for _, i in ipairs(order) do countEvent(state, events[i], liveEntry, earned) end
    else
        for _, event in ipairs(events) do countEvent(state, event, liveEntry, earned) end
    end
    cache[source] = state
    return awards, state.progress
end

function note.LadderAchievements(sample)
    local awards, progress = evaluate(sample or note.db)
    if note.RampageCount then progress.rampage = note.RampageCount(sample) end
    return awards, progress
end

function note.RecordLadderAchievement(entry)
    if entry.kind ~= "K" then return end
    local earned = {}
    evaluate(note.db, entry, earned)
    if #earned > 0 and DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage(L["|cffffd276Тетрадь смерти|r • Получено: %s"]:format(table.concat(earned, ", ")))
    end
end

function note.LadderEntries(sample, scope)
    local guild = scope == "guild"
    local players
    if guild then
        players = note.GuildLadderPlayers(sample) or {}
    else
        players = note.Ranking(sample)
    end
    local list, owner = {}, sample and "self" or note.owner
    local wins, unique
    if not guild then wins, unique = note.LadderPersonal(sample) end
    local personal
    for _, player in ipairs(players) do
        local kills, victims = player.kills, #player.victims
        if not guild and player.id == owner then kills, victims = wins, unique end
        if kills > 0 then
            local rank, nextRank, tier = note.LadderRank(kills, victims)
            local row = { player = player, rank = rank, nextRank = nextRank, tier = tier, kills = kills, victims = victims }
            list[#list + 1] = row
            if player.id == owner then personal = row end
        end
    end
    table.sort(list, function(a, b)
        if a.tier ~= b.tier then return a.tier > b.tier end
        if a.kills ~= b.kills then return a.kills > b.kills end
        if a.victims ~= b.victims then return a.victims > b.victims end
        if not guild and a.player.name ~= b.player.name then return a.player.name < b.player.name end
        return a.player.id < b.player.id
    end)
    return list, personal
end
