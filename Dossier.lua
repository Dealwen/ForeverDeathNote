local _, note = ...
local L = note.L
local marks = {
    { label = "Обычная отметка" },
    { key = "watch", label = "Наблюдать" },
    { key = "kos", label = "Пометить черепом" },
    { key = "ignore", label = "Игнорировать" },
}
local marksByKey = { watch = marks[2], kos = marks[3], ignore = marks[4] }
local empty = {}
local guildHistoryDays = 30
local function unknownName() return L["Имя неизвестно"] end

function note.DossierPreference(id, demo)
    local source = demo or note.db
    return source.dossier and source.dossier[id] or empty
end

function note.SaveDossier(id, text, mark, demo)
    if not id or (mark ~= nil and not marksByKey[mark]) then return false end
    if not (demo and demo.profiles[id] or not demo and note.GUID(id)) then return false end
    text = note.Text(text)
    local source = demo or note.db
    source.dossier = source.dossier or {}
    source.dossier[id] = (text or mark) and { text = text, mark = mark } or nil
    if demo then
        if note.RefreshWindow then note.RefreshWindow() end
    else
        note.Refresh()
    end
    return true
end

function note.Dossier(id, demo, fallback)
    local source = demo or note.db
    local profile = source.profiles[id] or empty
    if fallback then
        local merged = {}
        for key, value in pairs(fallback) do merged[key] = value end
        for key, value in pairs(profile) do merged[key] = value end
        profile = merged
    end
    local result = {
        id = id, name = profile.name or unknownName(), profile = profile,
        kills = 0, deaths = 0, revenge = 0, history = {},
        preference = note.DossierPreference(id, demo),
    }
    for i, entry in ipairs(source.events) do
        if entry.other == id and (entry.kind == "D" or entry.kind == "K") then
            result.history[#result.history + 1] = {
                kind = entry.kind, at = entry.at, index = i, entry = entry,
            }
        end
    end
    table.sort(result.history, function(a, b)
        if a.at ~= b.at then return a.at < b.at end
        return a.index < b.index
    end)
    local unresolved, history = 0, result.history
    for _, event in ipairs(history) do
        if event.kind == "D" then
            result.deaths, unresolved = result.deaths + 1, unresolved + 1
            result.lastDeath = event
        elseif event.kind == "K" then
            result.kills = result.kills + 1
            if unresolved > 0 then
                unresolved = unresolved - 1
                result.revenge = result.revenge + 1
                event.revenge = true
                result.lastRevenge = event
            end
        end
    end
    result.pending = unresolved
    result.lastEncounter = history[#history]
    for i = 1, math.floor(#history / 2) do
        local j = #history - i + 1
        history[i], history[j] = history[j], history[i]
    end
    return result
end

local function sameGuild(left, right)
    local lower = strlower or string.lower
    return type(left) == "string" and type(right) == "string" and lower(left) == lower(right)
end

local function knownName(source, id, fallback)
    local profile = source.profiles[id]
    return fallback or (profile and profile.name) or unknownName()
end

local function currentGuild(demo)
    if demo then return demo.profiles.self.guild end
    if IsInGuild and not IsInGuild() then return nil end
    return note.Text(GetGuildInfo("player"))
end

local function reportEvent(report, source, guild)
    local lost = report.kind == "D"
    local enemy = lost and report.killer or report.victim
    local member = lost and report.victim or report.killer
    local enemyGuild = report.victimGuild
    if lost then enemyGuild = report.killerGuild end
    local enemyProfile = source.profiles[enemy] or empty
    if not enemy or not member or enemy == member
        or sameGuild(enemyGuild or enemyProfile.guild, guild) then return end
    return {
        kind = report.kind, at = report.at,
        enemy = enemy, member = member,
        enemyName = knownName(source, enemy, lost and report.killerName or not lost and report.victimName),
        memberName = knownName(source, member, lost and report.victimName or not lost and report.killerName),
        enemyGuild = enemyGuild or enemyProfile.guild,
        enemyClass = lost and report.killerClass or enemyProfile.class,
        zone = report.zone, spellId = report.spellId, spellName = report.spellName,
        localEntry = report.localEntry,
    }
end

local function mergeReports(first, second)
    local fields = { "enemyName", "memberName", "enemyGuild", "enemyClass", "zone", "spellId", "spellName" }
    for _, field in ipairs(fields) do
        if second[field] and second[field] ~= unknownName()
            and (second.localEntry or first[field] == nil or first[field] == unknownName()) then
            first[field] = second[field]
        end
    end
    first.paired = true
end

local function removeNearbyDuplicates(sorted)
    local unmatched, result = {}, {}
    for _, event in ipairs(sorted) do
        local key = table.concat({ event.enemy, event.member, event.kind }, ";")
        local sources = unmatched[key]
        if not sources then
            sources = { own = { first = 1 }, shared = { first = 1 } }
            unmatched[key] = sources
        end
        local own = event.localEntry and sources.own or sources.shared
        local opposite = event.localEntry and sources.shared or sources.own
        local other = opposite[opposite.first]
        while other and event.at - other.at > 3 do
            opposite.first = opposite.first + 1
            other = opposite[opposite.first]
        end
        if other and not event.paired then
            mergeReports(other, event)
            opposite.first = opposite.first + 1
        else
            result[#result + 1] = event
            if not event.paired then own[#own + 1] = event end
        end
    end
    return result
end

local function threatEvents(demo, guild)
    local source = demo or note.db
    local cutoff = GetServerTime() - guildHistoryDays * 86400
    local exact, events = {}, {}
    local function include(report)
        if not report.at or report.at < cutoff or (report.kind ~= "D" and report.kind ~= "K") then return end
        local event = reportEvent(report, source, guild)
        if not event then return end
        local key = table.concat({ event.enemy, event.member, event.kind, event.at }, ";")
        local duplicate = exact[key]
        if not duplicate then
            exact[key] = event
            events[#events + 1] = event
        elseif duplicate.localEntry ~= event.localEntry then
            mergeReports(duplicate, event)
        end
    end
    if demo then
        for _, report in ipairs(demo.reports) do
            local reportingGuild = report.kind == "D" and report.victimGuild or report.killerGuild
            if sameGuild(reportingGuild, guild) then include(report) end
        end
    else
        -- Imported FDN reports can supply world statistics. Threats are based
        -- on the guild channel or on the player's own guild at observation.
        for _, report in pairs(note.realmEvents) do
            if sameGuild(report.receivedGuild, guild) then include(report) end
        end
        for _, entry in ipairs(source.events) do
            if sameGuild(entry.ownerGuild, guild) then
                local other = source.profiles[entry.other] or empty
                local report = {
                    at = entry.at, kind = entry.kind, zone = entry.zone, localEntry = true,
                    spellId = entry.spellId, spellName = entry.spellName, killerClass = entry.killerClass,
                }
                if entry.kind == "D" then
                    report.killer, report.victim = entry.other, note.owner
                    report.killerGuild, report.victimGuild = other.guild, guild
                else
                    report.killer, report.victim = note.owner, entry.other
                    report.killerGuild, report.victimGuild = guild, other.guild
                end
                include(report)
            end
        end
    end
    table.sort(events, function(a, b)
        if a.at ~= b.at then return a.at < b.at end
        if a.kind ~= b.kind then return a.kind == "K" end
        if a.member ~= b.member then return a.member < b.member end
        return a.enemy < b.enemy
    end)
    return removeNearbyDuplicates(events)
end

function note.GuildThreats(demo)
    local guild = currentGuild(demo)
    if not guild then return {}, nil end
    local source = demo or note.db
    local byEnemy, rows = {}, {}
    for _, event in ipairs(threatEvents(demo, guild)) do
        local row = byEnemy[event.enemy]
        if not row then
            local profile = {}
            for key, value in pairs(source.profiles[event.enemy] or empty) do profile[key] = value end
            profile.class = profile.class or event.enemyClass
            profile.guild = profile.guild or event.enemyGuild
            row = {
                id = event.enemy, name = event.enemyName, profile = profile,
                kills = 0, deaths = 0, revenge = 0, history = {}, unanswered = {},
                victims = {}, distinctVictims = 0,
            }
            byEnemy[event.enemy] = row
        end
        if row.name == unknownName() then row.name = event.enemyName end
        row.profile.class = row.profile.class or event.enemyClass
        row.profile.guild = row.profile.guild or event.enemyGuild
        if event.kind == "D" then
            row.deaths = row.deaths + 1
            row.lastDeath = event
            if not row.victims[event.member] then
                row.victims[event.member] = true
                row.distinctVictims = row.distinctVictims + 1
            end
            row.unanswered[#row.unanswered + 1] = event
            row.history[#row.history + 1] = event
        else
            row.kills = row.kills + 1
            local victim = table.remove(row.unanswered)
            if victim then
                row.revenge = row.revenge + 1
                event.victim, event.victimName = victim.member, victim.memberName
                event.revenge = true
                row.lastRevenge = event
                row.history[#row.history + 1] = event
            end
        end
    end
    for _, row in pairs(byEnemy) do
        if row.deaths > 0 then
            row.pending = #row.unanswered
            row.unanswered, row.victims = nil, nil
            local history = row.history
            for i = 1, math.floor(#history / 2) do
                local j = #history - i + 1
                history[i], history[j] = history[j], history[i]
            end
            rows[#rows + 1] = row
        end
    end
    table.sort(rows, function(a, b)
        if a.deaths ~= b.deaths then return a.deaths > b.deaths end
        if a.lastDeath.at ~= b.lastDeath.at then return a.lastDeath.at > b.lastDeath.at end
        if a.name ~= b.name then return a.name < b.name end
        return a.id < b.id
    end)
    return rows, guild
end

local dossierWindow, dossierId, dossierDemo, dossierFallback, page, markIndex
local pageSize = 7
local activeFilter = "all"
local palette = {
    D = { "Смерть", 1, 0.54, 0.50 },
    K = { "Добивание", 0.68, 0.85, 0.65 },
    revenge = { "Реванш", 1, 0.76, 0.37 },
}
local fieldColors = {
    D = { 0.50, 0.14, 0.11 },
    K = { 0.15, 0.33, 0.23 },
    revenge = { 0.48, 0.29, 0.10 },
}
local eventIcons = {
    D = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_8",
    K = "Interface\\Icons\\Ability_DualWield",
    revenge = "Interface\\Icons\\INV_Misc_Rune_08",
}
local historyFilters = {
    { id = "all", label = "Все", width = 75 },
    { id = "K", label = "Мои добивания", width = 123 },
    { id = "D", label = "Мои смерти", width = 116 },
    { id = "revenge", label = "Реванши", width = 96 },
}
local ink, mutedInk = { 0.20, 0.13, 0.088 }, { 0.33, 0.23, 0.16 }
local unknownClassIcon = "Interface\\Icons\\INV_Misc_QuestionMark"
local scoreInk = {
    gain = { 0.63, 0.88, 0.65 },
    loss = { 1, 0.56, 0.49 },
    neutral = { 0.88, 0.80, 0.68 },
}

local function label(parent, template, x, y, width)
    local text = note.CreateFontString(parent, nil, "OVERLAY", template)
    text:SetPoint("TOPLEFT", x, y)
    text:SetWidth(width)
    text:SetJustifyH("LEFT")
    text:SetWordWrap(false)
    return text
end

local function button(parent, text, x, y, width, action)
    local result = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    note.StyleLocaleButton(result)
    result:SetSize(width, 24)
    result:SetPoint("TOPLEFT", x, y)
    result:SetText(text)
    result:SetScript("OnClick", action)
    return result
end

local function renderRivalScore(score, state)
    local kills, deaths = state.kills, state.deaths
    local total, lead = kills + deaths, kills - deaths
    score.kills:SetText(total > 0 and tostring(kills) or "—")
    score.deaths:SetText(total > 0 and tostring(deaths) or "—")
    local tone = scoreInk.neutral
    local status = L[total == 0 and "Нет личных встреч" or "Ничья"]
    if lead > 0 then
        tone, status = scoreInk.gain, L["Ваш перевес: %d"]:format(lead)
    elseif lead < 0 then
        tone, status = scoreInk.loss, L["Перевес соперника: %d"]:format(-lead)
    end
    score.status:SetText(status)
    score.status:SetTextColor(unpack(tone))
    score.revenge:SetText(L["Реванши: %d"]:format(state.revenge))
    score.revenge:SetShown(total > 0)
    score.gain:SetShown(kills > 0)
    score.loss:SetShown(deaths > 0)
    if total > 0 then
        local width = score.track:GetWidth()
        if kills > 0 then score.gain:SetWidth(width * kills / total) end
        if deaths > 0 then score.loss:SetWidth(width * deaths / total) end
    end
end

local function renderDossier(reset)
    local state = note.Dossier(dossierId, dossierDemo, dossierFallback)
    local window = dossierWindow
    window.title:SetText(window.field and state.name or L["Досье • "] .. state.name)
    local style = note.GetHuntStyle and note.GetHuntStyle(dossierDemo)
    local tint = style and style.cover and style.cover.palette or {0.51, 0.34, 0.20}
    if not window.field then
        window:SetBackdropColor(0.58 + 0.21 * tint[1], 0.45 + 0.23 * tint[2], 0.34 + 0.22 * tint[3], 1)
    end
    window:SetBackdropBorderColor(0.58 + 0.34 * tint[1], 0.47 + 0.30 * tint[2], 0.32 + 0.26 * tint[3], 1)
    window.coverLine:SetColorTexture(tint[1], tint[2], tint[3], 0.9)
    if window.stamp then
        local earned = style and style.firstRevenge and state.revenge > 0 or false
        window.stamp:SetShown(earned)
        window.stampIcon:SetShown(earned)
    end
    local profile = state.profile
    local subtitle = note.ClassLabel(profile.class, profile.sex) or ""
    if profile.level then subtitle = subtitle .. L["  •  Ур. "] .. profile.level end
    if profile.guild then subtitle = subtitle .. "  •  " .. profile.guild end
    if dossierDemo then subtitle = L["ТЕСТ  •  "] .. subtitle end
    dossierWindow.subtitle:SetText(subtitle)
    local own = not dossierDemo and state.id == note.owner and note.RampageCount
    window.rampages:SetShown(own ~= nil and own ~= false)
    window.subtitle:SetWidth(own and (window.field and 402 or 315) or 525)
    if own then window.rampages:SetText(L["Серии из пяти черепов: %d"]:format(note.RampageCount())) end
    local tex = profile.class and ("classicon-" .. profile.class:lower())
    if window.field and note.SetCharacterArt then
        note.SetCharacterArt(window.icon, window.race, window.class, not dossierDemo and state.id or nil, profile)
    elseif tex and C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(tex) then
        window.icon:SetAtlas(tex)
    else
        window.icon:SetTexture(unknownClassIcon)
        window.icon:SetTexCoord(0, 1, 0, 1)
    end
    local history = state.history
    if window.field then
        renderRivalScore(window.rivalScore, state)
        if activeFilter ~= "all" then
            history = {}
            for _, event in ipairs(state.history) do
                if event.kind == activeFilter or (activeFilter == "revenge" and event.revenge) then
                    history[#history + 1] = event
                end
            end
        end
        for id, control in pairs(window.filters) do
            control:SetEnabled(id ~= activeFilter)
        end
        local hasPin = false
        if note.OpenRivalMap and note.EncounterMapID then
            for _, event in ipairs(state.history) do
                local entry = event.entry
                if type(entry.x) == "number" and type(entry.y) == "number"
                    and entry.x >= 0 and entry.x <= 100 and entry.y >= 0 and entry.y <= 100
                    and note.EncounterMapID(entry) then
                    hasPin = true
                    break
                end
            end
        end
        window.map:SetShown(hasPin)
    else
        window.summary:SetText((L["Добивания: %d   •   Смерти: %d   •   Реванши: %d"]):format(
            state.kills, state.deaths, state.revenge))
        for i, cell in ipairs(window.timeline) do
            local event = state.history[math.min(5, #state.history) + 1 - i]
            cell.entry = event and event.entry
            cell:SetShown(event ~= nil)
            if event then
                local meta = palette[event.revenge and "revenge" or event.kind]
                cell:SetText(L[meta[1]])
                cell:GetFontString():SetTextColor(meta[2], meta[3], meta[4])
            end
        end
        window.timelineTitle:SetShown(#state.history > 0)
    end
    local pageCount = math.max(1, math.ceil(#history / pageSize))
    page = math.max(1, math.min(page, pageCount))
    window.listedHistory, window.rivalName = history, state.name
    window.openAll:SetShown(#history > 0)
    window.empty:SetShown(#history == 0)
    if window.field then
        window.empty:SetText(L[#state.history == 0 and "С этим игроком ещё нет записанных встреч." or "Нет записей по выбранным фильтрам."])
    end
    local previousDay
    for i, row in ipairs(window.rows) do
        local event = history[(page - 1) * pageSize + i]
        row.entry = event and event.entry
        row:SetShown(event ~= nil)
        if event then
            local outcome = event.revenge and "revenge" or event.kind
            local meta = palette[outcome]
            row.kind:SetText(L[meta[1]])
            row.zone:SetText(note.SampleText(event.entry.zone, dossierDemo) or L["Зона неизвестна"])
            if window.field then
                local day = date("%d.%m.%Y", event.at)
                row.day:SetText(day ~= previousDay and day or "")
                row.when:SetText(date("%H:%M", event.at))
                previousDay = day
                row.kind:SetTextColor(unpack(fieldColors[outcome]))
                row.icon:SetTexture(eventIcons[outcome])
                local strike = note.KillingBlow(event.entry, dossierDemo)
                row.spell:SetText(note.SpellName(strike.spellId, strike.spellName, dossierDemo) or L["Последний удар не записан"])
            else
                row.when:SetText(date("%d.%m %H:%M", event.at))
                row.kind:SetTextColor(meta[2], meta[3], meta[4])
                row.spell:SetText(note.SpellName(event.entry.spellId, event.entry.spellName, dossierDemo) or "")
            end
        end
    end
    window.prev:SetEnabled(page > 1)
    window.next:SetEnabled(page < pageCount)
    window.pages:SetText((L["%d из %d"]):format(page, pageCount))
    if window.field then
        window.prev:SetShown(pageCount > 1)
        window.next:SetShown(pageCount > 1)
        window.pages:SetShown(pageCount > 1)
    end
    dossierWindow.hunt:SetShown(state.deaths > 0 and note.TrackHuntRival ~= nil)
    local target = note.GetHuntTarget and note.GetHuntTarget(dossierDemo)
    local tracked = target and target.id == state.id and not target.completed and not target.expired
    dossierWindow.hunt:SetText(tracked and L["Открыть цель"] or L["Взять реванш"])
    if reset then
        markIndex = 1
        for i, mark in ipairs(marks) do
            if mark.key == state.preference.mark then markIndex = i; break end
        end
        dossierWindow.mark:SetText(L[marks[markIndex].label])
        dossierWindow.comment:SetText(note.SampleText(state.preference.text, dossierDemo) or "")
        dossierWindow.comment:ClearFocus()
        dossierWindow.status:SetText("")
    end
end

local function openAllHistory()
    local window = dossierWindow
    local history = window and window.listedHistory
    if not history or #history == 0 or not note.OpenAllRecords then return end
    local sample = dossierDemo
    local filterLabel = L["Последние встречи"]
    for _, filter in ipairs(historyFilters) do
        if activeFilter == filter.id and filter.id ~= "all" then filterLabel = L[filter.label]; break end
    end
    note.OpenAllRecords({
        title = L["Досье • "] .. window.rivalName,
        subtitle = filterLabel,
        rows = history,
        startIndex = (page - 1) * pageSize + 1,
        columns = {
            { label = L["Дата и время"], weight = 2.05 },
            { label = L["Итог"], weight = 1.5 },
            { label = L["Зона"], weight = 2.3 },
            { label = L["Способность"], weight = 2.4 },
        },
        cells = function(event)
            local outcome = event.revenge and "revenge" or event.kind
            local meta = palette[outcome]
            local strike = note.KillingBlow(event.entry, sample)
            local spell = note.SpellName(strike.spellId, strike.spellName, sample)
            return { date("%d.%m.%Y %H:%M", event.at),
                { text = L[meta[1]], color = { meta[2], meta[3], meta[4] }, icon = eventIcons[outcome] },
                note.SampleText(event.entry.zone, sample) or L["Зона неизвестна"],
                { text = spell or L["Последний удар не записан"],
                    icon = spell and note.KillingBlowTexture(strike.spellId, spell) } }
        end,
        onSelect = function(event) note.OpenFightReport(sample, event.entry) end,
    })
end

local function editSection(frame, parent, x, y, field)
    local noteWidth = field and 200 or 290
    local markX, markY = field and x or 324, field and y - 70 or -381
    label(parent, "GameFontNormalSmall", x, y, noteWidth):SetText(L["Личная заметка"])
    label(parent, "GameFontNormalSmall", markX, field and y - 50 or -367, noteWidth):SetText(L["Метка при встрече"])
    frame.comment = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    frame.comment:SetSize(noteWidth, 25)
    frame.comment:SetPoint("TOPLEFT", x + 5, y - 14)
    frame.comment:SetAutoFocus(false)
    note.StyleLocaleFont(frame.comment)
    frame.comment:SetMaxBytes(96)
    frame.comment:SetScript("OnEscapePressed", frame.comment.ClearFocus)
    frame.comment:SetScript("OnEnterPressed", frame.comment.ClearFocus)
    frame.mark = button(parent, "", markX, markY, field and 200 or 191, function(self)
        if field and MenuUtil and MenuUtil.CreateContextMenu then
            MenuUtil.CreateContextMenu(self, function(_, root)
                for i, mark in ipairs(marks) do
                    note.StyleLocaleMenu(root:CreateRadio(L[mark.label], function()
                        return markIndex == i
                    end, function()
                        markIndex = i
                        self:SetText(L[mark.label])
                    end))
                end
            end)
        else
            markIndex = markIndex % #marks + 1
            self:SetText(L[marks[markIndex].label])
        end
    end)
    frame.save = button(parent, L["Сохранить"], field and x or 522, field and y - 105 or -381, field and 200 or 101, function()
        if note.SaveDossier(dossierId, frame.comment:GetText(), marks[markIndex].key, dossierDemo) then
            frame.comment:ClearFocus()
            frame.status:SetText(dossierDemo and L["Сохранено в тестовых данных."] or L["Личная заметка и метка сохранены."])
        end
    end)
    frame.status = label(parent, "GameFontHighlightSmall", field and x or 22, field and y - 136 or -419, field and 202 or 598)
    if field then frame.status:SetWordWrap(true) end
end

local function pickRival(frame)
    local success, message = note.TrackHuntRival(dossierId, dossierDemo)
    if success and note.OpenWindow then
        frame:Hide()
        note.OpenWindow("hunt")
    else
        frame.status:SetText(message or (success and L["Цель выбрана для реванша."] or L["Выбор цели недоступен."]))
    end
end

local function openEncounter(self)
    if self.entry then note.OpenFightReport(dossierDemo, self.entry) end
end

local function paperText(parent, font, x, y, width, color)
    local text = label(parent, font, x, y, width)
    text:SetTextColor(unpack(color or ink))
    text:SetShadowColor(0, 0, 0, 0)
    return text
end

local function dossierSurface(parent, x, y, w, h, paper)
    local panel = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    panel:SetPoint("TOPLEFT", x, y)
    panel:SetSize(w, h)
    panel:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 11,
        insets = { left = 4, top = 4, right = 4, bottom = 4 } })
    if paper then
        panel:SetBackdropColor(0.86, 0.75, 0.58, 1)
        if note.FieldJournal.BoundPage then
            note.FieldJournal.BoundPage(panel)
            note.FieldJournal.ShowPage(panel, true)
        end
    else
        panel:SetBackdropColor(0.15, 0.101, 0.070, 1)
    end
    panel:SetBackdropBorderColor(0.53, 0.37, 0.23, 1)
    return panel
end

local function buildRivalScore(panel)
    local function centered(font, x, y, width, caption, color)
        local value = label(panel, font, x, y, width)
        value:SetJustifyH("CENTER")
        if caption then value:SetText(L[caption]) end
        if color then value:SetTextColor(unpack(color)) end
        return value
    end
    local function count(x, color)
        local value = centered("GameFontNormalLarge", x, -44, 91, nil, color)
        note.StyleNumberFont(value)
        local font, _, flags = value:GetFont()
        if font then value:SetFont(font, 24, flags or "") end
        return value
    end
    centered("GameFontNormal", 14, -14, 192, "Личный счёт")
    centered("GameFontHighlightSmall", 14, -33, 91, "Вы добили", scoreInk.neutral)
    centered("GameFontHighlightSmall", 115, -33, 91, "Вас добили", scoreInk.neutral)
    local track = panel:CreateTexture(nil, "BORDER")
    track:SetSize(192, 6)
    track:SetPoint("TOPLEFT", 14, -93)
    track:SetColorTexture(0.33, 0.25, 0.19, 1)
    local gain = panel:CreateTexture(nil, "ARTWORK")
    gain:SetHeight(6)
    gain:SetPoint("TOPLEFT", track, "TOPLEFT")
    gain:SetColorTexture(0.36, 0.68, 0.40, 1)
    local loss = panel:CreateTexture(nil, "ARTWORK")
    loss:SetHeight(6)
    loss:SetPoint("TOPRIGHT", track, "TOPRIGHT")
    loss:SetColorTexture(0.82, 0.26, 0.22, 1)
    local score = {
        kills = count(14, scoreInk.gain),
        deaths = count(115, scoreInk.loss),
        status = centered("GameFontHighlightSmall", 14, -76, 192, nil, scoreInk.neutral),
        revenge = centered("GameFontHighlightSmall", 14, -105, 192, nil, scoreInk.neutral),
        track = track, gain = gain, loss = loss,
    }
    return score
end

local function buildFieldDossier(frame)
    local annotations = dossierSurface(frame, 17, -73, 220, 384)
    frame.rivalScore = buildRivalScore(annotations)
    editSection(frame, annotations, 10, -126, true)
    frame.map = button(annotations, L["Карта"], 10, -303, 200, function()
        if note.OpenRivalMap then
            frame:Hide()
            note.OpenRivalMap(dossierDemo, dossierId)
        end
    end)
    frame.hunt = button(annotations, L["Взять реванш"], 10, -338, 200, function() pickRival(frame) end)

    local chronicle = dossierSurface(frame, 247, -73, 471, 384, true)
    local title = paperText(chronicle, "GameFontNormal", 15, -14, 420)
    title:SetText(L["Последние встречи"])
    frame.filters = {}
    local filterX = 14
    for _, filter in ipairs(historyFilters) do
        frame.filters[filter.id] = button(chronicle, L[filter.label], filterX, -37, filter.width, function()
            activeFilter, page = filter.id, 1
            renderDossier()
        end)
        filterX = filterX + filter.width + 11
    end
    frame.rows = {}
    for i = 1, pageSize do
        local row = CreateFrame("Button", nil, chronicle)
        row:SetPoint("TOPLEFT", 12, -72 - (i - 1) * 38)
        row:SetSize(443, 36)
        local background = row:CreateTexture(nil, "BACKGROUND")
        background:SetAllPoints()
        background:SetColorTexture(0.32, 0.20, 0.11, i % 2 == 1 and 0.10 or 0.044)
        row.day = paperText(row, "GameFontHighlightSmall", 7, -4, 80, mutedInk)
        row.when = paperText(row, "GameFontHighlightSmall", 7, -20, 80)
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(18, 18)
        row.icon:SetPoint("TOPLEFT", 88, -9)
        row.kind = paperText(row, "GameFontNormalSmall", 112, -12, 101)
        row.zone = paperText(row, "GameFontHighlight", 215, -3, 220)
        row.spell = paperText(row, "GameFontHighlightSmall", 215, -20, 220, mutedInk)
        row:SetHighlightTexture("Interface\\Buttons\\UI-Listbox-Highlight2")
        row:SetScript("OnClick", openEncounter)
        frame.rows[i] = row
    end
    frame.empty = paperText(chronicle, "GameFontHighlight", 15, -91, 426)
    frame.empty:SetWordWrap(true)
    frame.prev = button(chronicle, L["Назад"], 132, -350, 67, function() page = page - 1; renderDossier() end)
    frame.pages = paperText(chronicle, "GameFontHighlightSmall", 201, -356, 69)
    frame.pages:SetJustifyH("CENTER")
    frame.next = button(chronicle, L["Далее"], 272, -350, 67, function() page = page + 1; renderDossier() end)
    frame.openAll = button(chronicle, L["Открыть все"], 12, -350, 112, openAllHistory)
    frame.race = frame:CreateTexture(nil, "ARTWORK")
    frame.class = frame:CreateTexture(nil, "ARTWORK")
    frame.class:SetPoint("BOTTOMRIGHT", frame.icon, "BOTTOMRIGHT", 5, -4)
    frame.class:SetSize(18, 18)
end

local function createDossier()
    local frame = CreateFrame("Frame", "ForeverDeathNoteDossier", UIParent, "BackdropTemplate")
    frame.field = note.FieldJournal and note.FieldJournal.Enabled()
    local width, height = frame.field and 736 or 642, frame.field and 474 or 456
    frame:SetSize(width, height)
    frame:SetPoint("CENTER")
    frame:SetScale(math.min(1, UIParent:GetWidth() / (width + 20), UIParent:GetHeight() / (height + 20)))
    frame:SetFrameStrata("DIALOG")
    frame:SetFrameLevel(24)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        edgeSize = 28,
        insets = { left = 7, right = 7, top = 7, bottom = 7 },
    })
    if frame.field then
        frame:SetBackdropColor(0.25, 0.17, 0.12, 1)
    else
        frame:SetBackdropColor(0.64, 0.57, 0.48, 1)
    end
    note.ManageWindow(frame, "dossier", note.WindowDragHandle(frame, frame.field and 57 or 49, width - 64))
    frame:Hide()
    local dismiss = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    dismiss:SetPoint("TOPRIGHT", -4, -4)
    dismiss:SetScript("OnClick", function() frame:Hide() end)
    tinsert(UISpecialFrames, "ForeverDeathNoteDossier")

    frame.icon = frame:CreateTexture(nil, "ARTWORK")
    frame.icon:SetPoint("TOPLEFT", 18, -17)
    frame.icon:SetSize(37, 37)
    frame.title = label(frame, "GameFontNormalLarge", 65, -17, 525)
    frame.subtitle = label(frame, "GameFontHighlightSmall", 65, -41, 525)
    frame.rampages = label(frame, "GameFontHighlightSmall", width - 260, -41, 223)
    frame.rampages:SetJustifyH("RIGHT")
    frame.coverLine = frame:CreateTexture(nil, "ARTWORK")
    local lineY = frame.field and -64 or -89
    frame.coverLine:SetPoint("TOPLEFT", 18, lineY)
    frame.coverLine:SetPoint("TOPRIGHT", -18, lineY)
    frame.coverLine:SetHeight(1)
    if frame.field then
        buildFieldDossier(frame)
        return frame
    end
    frame.summary = label(frame, "GameFontHighlight", 18, -68, 420)
    frame.stampIcon = frame:CreateTexture(nil, "ARTWORK")
    frame.stampIcon:SetPoint("TOPLEFT", 497, -66)
    frame.stampIcon:SetSize(16, 16)
    frame.stampIcon:SetTexture("Interface\\Icons\\INV_Misc_Rune_08")
    frame.stamp = label(frame, "GameFontNormal", 519, -68, 93)
    frame.stamp:SetText(L["Отомщено"])
    frame.stamp:SetTextColor(1, 0.73, 0.44)

    frame.timelineTitle = label(frame, "GameFontNormalSmall", 24, -99, 530)
    frame.timelineTitle:SetText(L["Последние встречи"])
    frame.timeline = {}
    for i = 1, 5 do
        local cell = button(frame, "", 19 + (i-1)*122, -116, 116, openEncounter)
        frame.timeline[i] = cell
    end
    label(frame, "GameFontNormalSmall", 24, -152, 110):SetText(L["Дата и время"])
    label(frame, "GameFontNormalSmall", 133, -152, 93):SetText(L["Итог"])
    label(frame, "GameFontNormalSmall", 233, -152, 208):SetText(L["Зона"])
    label(frame, "GameFontNormalSmall", 449, -152, 150):SetText(L["Способность"])

    frame.rows = {}
    for i = 1, pageSize do
        local row = CreateFrame("Button", nil, frame)
        row:SetPoint("TOPLEFT", 17, -169 - (i - 1) * 22)
        row:SetSize(606, 21)
        local background = row:CreateTexture(nil, "BACKGROUND")
        background:SetAllPoints()
        background:SetColorTexture(0.34, 0.26, 0.18, i % 2 == 1 and 0.33 or 0.18)
        row.when = label(row, "GameFontHighlightSmall", 7, -4, 102)
        row.kind = label(row, "GameFontHighlightSmall", 116, -4, 95)
        row.zone = label(row, "GameFontHighlightSmall", 216, -4, 208)
        row.spell = label(row, "GameFontHighlightSmall", 432, -4, 166)
        row:SetHighlightTexture("Interface\\Buttons\\UI-Listbox-Highlight2")
        row:SetScript("OnClick", openEncounter)
        frame.rows[i] = row
    end
    frame.empty = label(frame, "GameFontDisable", 24, -185, 580)
    frame.empty:SetText(L["С этим игроком ещё нет записанных встреч."])
    frame.prev = button(frame, L["Назад"], 18, -330, 86, function() page = page - 1; renderDossier() end)
    frame.pages = label(frame, "GameFontHighlightSmall", 112, -336, 67)
    frame.next = button(frame, L["Далее"], 183, -330, 86, function() page = page + 1; renderDossier() end)
    frame.openAll = button(frame, L["Открыть все"], 285, -330, 142, openAllHistory)
    frame.hunt = button(frame, L["Взять реванш"], 488, -330, 135, function() pickRival(frame) end)
    editSection(frame, frame, 19, -367, false)
    return frame
end

function note.CloseDossier()
    if dossierWindow then dossierWindow:Hide() end
end

function note.UpdateDossierDemo(demo)
    if not dossierWindow or not dossierWindow:IsShown() then return end
    if dossierDemo ~= demo then
        note.CloseDossier()
    else
        renderDossier()
    end
end

function note.OpenDossier(id, demo, fallback)
    if not id or (demo and not demo.profiles[id]) or (not demo and not note.GUID(id)) then return end
    if not dossierWindow then dossierWindow = createDossier() end
    dossierId, dossierDemo, dossierFallback, page, activeFilter = id, demo, fallback, 1, "all"
    dossierWindow:Show()
    dossierWindow:Raise()
    renderDossier(true)
end
