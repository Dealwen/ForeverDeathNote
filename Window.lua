local _, note = ...
local L = note.L
local theme = note.WarTable
local field = note.FieldJournal
local warLayout
local window, content, detail, exchange, huntBoard, summary, heading, search, pager, previous, nextPage
local allRecords, openAll
local forget, detailAction, dossierButton, fightReportButton, guildFilter, victimFilter, sharing, marks, rows, tabs
local nearbyButton, mapButton, guildThreatButton, guildThreatMode, guildThreatId
local sourceButton, sourceCount, sourceIndex = nil, nil, 1
local mode, page, selection = "hunt", 1, nil
local alertToggle, soundToggle, flashToggle, tooltipToggle, tooltipMode, pauseAlert, autoReportToggle
local zoneScoreToggle
local settingsButton, minimapToggle, rankingBar, rankTabs, searchLabel, factionBadges
local activeRanking = "realm"
local guildRankingOnly = false
local journalBar, journalTabs, journalScope, clearScope, journalNavigation
local journalFilters = { { "all", "Все" }, { "K", "Мои добивания" }, { "D", "Мои смерти" }, { "revenge", "Реванши" } }
local rankingModes = { realm = true, guild = true, front = true }
local progressModes = { titles = true, achievements = true }
local headerStats, headerStatsAt
local visibleRows = 8
local podiumColors = {
    { 1.00, 0.80, 0.39 },
    { 0.82, 0.88, 0.97 },
    { 0.86, 0.56, 0.36 },
}
local podiumCrown = "Interface\\AddOns\\ForeverDeathNote\\Art\\PodiumCrown.tga"
local choose
local rankingSources = {
    { label = "Все источники" },
    { id = "own", label = "Личный журнал" },
    { id = "guild", label = "Гильдейский обмен" },
    { id = "imported", label = "Ручной импорт" },
}
local questionIcon = "Interface\\Icons\\INV_Misc_QuestionMark"
local meleeIcon = "Interface\\Icons\\Ability_MeleeDamage"
local guildIcon = "Interface\\Icons\\INV_BannerPVP_01"
local factionIcon = {
    Horde = "Interface\\Icons\\INV_BannerPvP_01",
    Alliance = "Interface\\Icons\\INV_BannerPvP_02",
}
local factionName = { Horde = "Орда", Alliance = "Альянс", Mixed = "Орда и Альянс" }
local factionColor = { Horde = { 0.95, 0.55, 0.47 }, Alliance = { 0.53, 0.75, 0.98 } }
local panelColor, borderColor = { 0.055, 0.073, 0.091 }, { 0.29, 0.33, 0.37 }
local writing, muted, gold = { 0.94, 0.90, 0.84 }, { 0.76, 0.78, 0.80 }, { 0.99, 0.83, 0.55 }
local flat = "Interface\\Buttons\\WHITE8X8"
local dialogBorder = "Interface\\DialogFrame\\UI-DialogBox-Border"
local tooltipBorder = "Interface\\Tooltips\\UI-Tooltip-Border"
local raceArt = { scourge = "undead", highmountaintauren = "highmountain",
    lightforgeddraenei = "lightforged", zandalaritroll = "zandalari", skyborne = "bloodelf" }

local raceNames = {
    Human = "human", Dwarf = "dwarf", Gnome = "gnome", ["Night Elf"] = "nightelf",
    Tauren = "tauren", Undead = "scourge", Troll = "troll", Orc = "orc", Skyborne = "skyborne",
    ["Человек"] = "human", ["Дворф"] = "dwarf", ["Гном"] = "gnome", ["Ночной эльф"] = "nightelf",
    ["Таурен"] = "tauren", ["Нежить"] = "scourge", ["Тролль"] = "troll", ["Орк"] = "orc",
}
local classicRaceCells = {
    human = 0, dwarf = 1, gnome = 2, nightelf = 3, tauren = 4, scourge = 5, troll = 6, orc = 7,
}

local function fill(parent, r, g, b, a)
    local texture = parent:CreateTexture(nil, "BACKGROUND")
    texture:SetAllPoints()
    texture:SetColorTexture(r, g, b, a or 1)
    return texture
end

local function label(parent, style, width, x, y)
    local text = note.CreateFontString(parent, nil, "ARTWORK", style)
    text:SetPoint("TOPLEFT", x, y)
    text:SetWidth(width)
    text:SetJustifyH("LEFT")
    return text
end

local function button(parent, caption, width, x, y, action, style, height, icon)
    local control = CreateFrame("Button", nil, parent)
    control:SetSize(width, height or 26)
    control:SetPoint("TOPLEFT", x, y)
    note.StyleWarcraftButton(control, style)
    local text = note.CreateFontString(control, nil, "OVERLAY", style == "major" and "GameFontNormal" or "GameFontHighlightSmall")
    text:SetPoint("TOPLEFT", icon and 43 or 6, 0)
    text:SetPoint("BOTTOMRIGHT", -6, 0)
    text:SetJustifyH(icon and "LEFT" or "CENTER")
    text:SetWordWrap(false)
    if icon then
        control.icon = control:CreateTexture(nil, "OVERLAY", nil, 2)
        control.icon:SetSize(22, 22)
        control.icon:SetPoint("LEFT", 12, 0)
        control.icon:SetTexture(icon)
        if not icon:find("UI%-RaidTargetingIcon") then control.icon:SetTexCoord(0.06, 0.94, 0.06, 0.94) end
    end
    local primary = style == "primary" or style == "dossier"
    local selected, accent
    local function paint(self)
        local awake = self:IsEnabled() ~= false or selected
        text:SetTextColor(unpack(awake and (selected and (accent or gold) or writing) or muted))
        text:SetAlpha(awake and 1 or 0.55)
        if self.icon then self.icon:SetAlpha(awake and 1 or 0.58) end
        note.TintWarcraftButton(self, selected, primary)
    end
    function control:SetPrimary(value)
        primary = value
        paint(self)
    end
    function control:SetText(value) text:SetText(value) end
    function control:GetText() return text:GetText() end
    function control:GetFontString() return text end
    function control:SetSelected(value, color)
        selected, accent = value, color
        self:SetEnabled(not value or style == "toggle")
        paint(self)
    end
    control:HookScript("OnEnable", paint)
    control:HookScript("OnDisable", paint)
    control:SetScript("OnClick", action)
    control:SetText(caption)
    paint(control)
    return control
end

local function textHint(control, text)
    control:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(text)
        note.StyleLocaleTooltip(GameTooltip)
        GameTooltip:Show()
    end)
    control:SetScript("OnLeave", function(self) if GameTooltip:IsOwned(self) then GameTooltip:Hide() end end)
end

local function backdrop(frame, background, edge, size, inset, r, g, b)
    frame:SetBackdrop({
        bgFile = background, edgeFile = edge, edgeSize = size,
        insets = { left = inset, right = inset, top = inset, bottom = inset },
    })
    frame:SetBackdropColor(r, g, b, 1)
end

local function framedIcon(parent, size, x, y)
    local frame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    frame:SetSize(size, size)
    frame:SetPoint("TOPLEFT", x, y)
    frame:SetBackdrop({ edgeFile = tooltipBorder, edgeSize = 8 })
    frame:SetBackdropBorderColor(0.52, 0.52, 0.47, 1)
    local image = frame:CreateTexture(nil, "BACKGROUND")
    image:SetPoint("TOPLEFT", 3, -3)
    image:SetPoint("BOTTOMRIGHT", -3, 3)
    return image, frame
end

local function factionBadge(parent, faction, x)
    local color = factionColor[faction]
    local plate = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    plate:SetSize(101, 40)
    plate:SetPoint("TOPLEFT", x, -13)
    plate:SetBackdrop({ bgFile = flat, edgeFile = flat, edgeSize = 1 })
    plate:SetBackdropColor(0.05 + color[1] * 0.11, 0.05 + color[2] * 0.11, 0.067 + color[3] * 0.11, 1)
    plate:SetBackdropBorderColor(color[1] * 0.39, color[2] * 0.39, color[3] * 0.39, 1)
    local insignia = plate:CreateTexture(nil, "ARTWORK")
    insignia:SetPoint("LEFT", 5, 0)
    insignia:SetSize(30, 32)
    note.SetFactionEmblem(insignia, faction)
    local name = label(plate, "GameFontNormalSmall", 61, 39, -5)
    name:SetTextColor(unpack(color))
    name:SetText(L[factionName[faction]])
    name:SetWordWrap(false)
    local edge = plate:CreateTexture(nil, "ARTWORK")
    edge:SetPoint("BOTTOMLEFT", 0, 0)
    edge:SetPoint("BOTTOMRIGHT", 0, 0)
    edge:SetHeight(2)
    edge:SetColorTexture(color[1], color[2], color[3], 1)
    plate.edge, plate.name, plate.insignia = edge, name, insignia
    plate.count = label(plate, "GameFontHighlight", 59, 39, -19)
    note.StyleNumberFont(plate.count)
    local numberFace = plate.count:GetFont()
    if numberFace then plate.count:SetFont(numberFace, 17, "OUTLINE") end
    plate.count:SetWordWrap(false)
    plate:EnableMouse(true)
    plate:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText(L[factionName[faction]] .. " / " .. L["Добивания за 30 дней"])
        if self.evidence then
            for _, origin in ipairs(rankingSources) do
                if origin.id then
                    GameTooltip:AddDoubleLine(L[origin.label], tostring(self.evidence[origin.id]), 1, 1, 1, 1, 0.82, 0)
                end
            end
        end
        GameTooltip:AddLine(L["Рейтинг отражает доступные записи. Данные ручного импорта могут быть изменены."], 0.83, 0.78, 0.68, true)
        note.StyleLocaleTooltip(GameTooltip)
        GameTooltip:Show()
    end)
    local function hideTooltip(self) if GameTooltip:IsOwned(self) then GameTooltip:Hide() end end
    plate:SetScript("OnLeave", hideTooltip)
    plate:SetScript("OnHide", hideTooltip)
    return plate
end

local function raceIcon(image, profile)
    local race = profile.raceFile and profile.raceFile:lower() or raceNames[profile.race]
    local female = profile.sex == 3
    if race and C_Texture and C_Texture.GetAtlasInfo then
        local atlas = "raceicon-" .. (raceArt[race] or race) .. "-" .. (female and "female" or "male")
        if C_Texture.GetAtlasInfo(atlas) then
            image:SetAtlas(atlas)
            return
        end
    end
    local cell = classicRaceCells[race]
    if cell then
        local left = (cell % 4) / 4
        local top = (math.floor(cell / 4) + (female and 2 or 0)) / 4
        image:SetTexture("Interface\\Glues\\CharacterCreate\\UI-CharacterCreate-Races")
        image:SetTexCoord(left, left + 0.25, top, top + 0.25)
        return
    end
    image:SetTexture(questionIcon)
    image:SetTexCoord(0, 1, 0, 1)
end

local function classIcon(image, class)
    local atlas = class and "classicon-" .. class:lower()
    if atlas and C_Texture and C_Texture.GetAtlasInfo(atlas) then
        image:SetAtlas(atlas)
        return
    end
    local coords = CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[class]
    if coords then
        image:SetTexture("Interface\\Glues\\CharacterCreate\\UI-CharacterCreate-Classes")
        image:SetTexCoord(unpack(coords))
    else
        image:SetTexture(questionIcon)
        image:SetTexCoord(0, 1, 0, 1)
    end
end

function note.SetCharacterArt(portrait, race, class, guid, profile, classToken)
    raceIcon(race, profile)
    classIcon(class, classToken or profile.class)
    if guid and not InCombatLockdown() and note.GUID(UnitGUID("target")) == guid and SetPortraitTexture then
        portrait:SetTexCoord(0, 1, 0, 1)
        SetPortraitTexture(portrait, "target")
    else
        raceIcon(portrait, profile)
    end
end

local function journalRows(query, source, demo)
    local result, counts, kills, deaths = {}, {}, 0, 0
    local events = source.events
    local folio = field.Enabled()
    for _, event in ipairs(events) do
        local countsForPlayer = counts[event.other] or { kills = 0, deaths = 0 }
        if event.kind == "K" then
            countsForPlayer.kills = countsForPlayer.kills + 1
        else
            countsForPlayer.deaths = countsForPlayer.deaths + 1
        end
        counts[event.other] = countsForPlayer
    end
    local filter = mode == "journal" and not journalScope and note.db.journalFilter or nil
    local markedOnly = folio and mode == "journal" and not journalScope and source.journalMarkedOnly
    local revenges = {}
    if filter == "revenge" then
        for id in pairs(counts) do
            for _, event in ipairs(note.Dossier(id, demo).history) do
                if event.revenge then revenges[event.entry] = true end
            end
        end
    end
    for i = #events, 1, -1 do
        local event = events[i]
        local profile = source.profiles[event.other] or {}
        local name = profile.name or L["Имя неизвестно"]
        local matchesSearch
        if folio then
            matchesSearch = field.MatchesRecord(query, name, profile, event, demo)
        else
            matchesSearch = query == "" or (strlower or string.lower)(name):find(query, 1, true)
        end
        local matches = mode ~= "journal" or (
            (not filter or filter == "all" or event.kind == filter or revenges[event])
            and (journalScope and journalScope.entries[event] or not journalScope and note.JournalMatches(event, profile, demo))
        )
        if matches and markedOnly then
            local mark = note.DossierPreference(event.other, demo).mark
            matches = mark == "watch" or mark == "kos"
        end
        if matches then
            if event.kind == "K" then kills = kills + 1 else deaths = deaths + 1 end
        end
        if matches and (mode ~= "rivals" or event.kind == "D") and
            matchesSearch then
            local count = counts[event.other]
            if mode ~= "rivals" or not count.listed then
                result[#result + 1] = { guid = event.other, name = name, entry = event,
                    kills = count.kills, deaths = count.deaths, profile = profile, recordIndex = i }
                count.listed = true
            end
        end
    end
    if mode == "rivals" then
        table.sort(result, function(a, b)
            if a.deaths ~= b.deaths then return a.deaths > b.deaths end
            return a.entry.at > b.entry.at
        end)
    elseif folio then
        table.sort(result, function(a, b)
            if a.entry.at ~= b.entry.at then return a.entry.at > b.entry.at end
            return a.recordIndex > b.recordIndex
        end)
    end
    return result, kills, deaths
end

local function placeText(entry, demo)
    local zone = note.SampleText(entry.zone, demo) or L["Зона неизвестна"]
    if entry.subzone and entry.subzone ~= entry.zone then zone = zone .. " • " .. note.SampleText(entry.subzone, demo) end
    if type(entry.x) == "number" and type(entry.y) == "number" then
        zone = zone .. (" (%.1f, %.1f)"):format(entry.x, entry.y)
    end
    return zone
end

local function levelLines(levels)
    local order, lines = {}, {}
    for level in pairs(levels) do if level > 0 then order[#order + 1] = level end end
    table.sort(order)
    for _, level in ipairs(order) do
        lines[#lines + 1] = (L["Ур. %d ×%d"]):format(level, levels[level])
    end
    if levels[0] then lines[#lines + 1] = (L["Уровень неизвестен ×%d"]):format(levels[0]) end
    return lines
end

local function openFullTable()
    local data = allRecords
    if not data or #data.list == 0 then return end
    local function col(key, weight, justify)
        return { label = L[key], weight = weight, justify = justify }
    end
    local function count(key) return col(key, 1.7, "RIGHT") end
    local columns, cells
    if mode == "journal" then
        columns = { col("Игрок", 2.8), col("Зона", 3.4), col("Событие", 1.6), count("Время") }
        cells = function(row)
            local event = row.entry
            local death = event.kind == "D"
            return { row.name, placeText(event, note.DemoData()),
                { text = L[death and "Смерть" or "Добивание"],
                    color = death and { 1, 0.48, 0.43 } or { 0.62, 0.86, 0.65 } },
                date("%d.%m  %H:%M", event.at) }
        end
    elseif mode == "guild" and guildThreatId then
        columns = { col("Согильдеец", 4), col("Событие", 2), count("Время") }
        cells = function(row)
            local event = row.incident
            return { row.name, L[event.kind == "D" and "Гибель" or "Реванш"], date("%d.%m  %H:%M", event.at) }
        end
    elseif mode == "guild" and guildThreatMode then
        columns = { col("Обидчик", 4), count("Нападения"), count("Реванши") }
        cells = function(row) return { row.name, row.deaths, row.revenge } end
    elseif victimFilter then
        columns = { col("Игрок", 3), count("Добивания"), col("Уровни", 4) }
        cells = function(row) return { row.name, row.kills, table.concat(levelLines(row.levels), ", ") } end
    elseif mode == "realm" then
        columns = { col("#", 0.6, "CENTER"), col("Игрок", 3), col("Звание", 3), count("Добивания"), count("Разные жертвы") }
        cells = function(row)
            local title = note.LadderRank(row.kills, #row.victims)
            return { row.rank, row.name, { text = L[title.name], color = title.color }, row.kills, #row.victims }
        end
    elseif mode == "stats" then
        columns = { col("Классы", 4), count("Добивания") }
        cells = function(row) return { row.name, row.kills } end
    else
        local player = mode ~= "guild" or guildFilter
        columns = { col(player and "Игрок" or "Гильдия", 4), count("Добивания"), count("Смерти") }
        cells = function(row)
            local emblem = not player and factionIcon[row.faction]
            return { { text = row.rank and (row.rank .. ".  " .. row.name) or row.name, icon = emblem },
                row.kills, row.deaths }
        end
    end
    note.OpenAllRecords({
        title = L[mode == "realm" and "Рейтинг мира" or mode == "guild" and "Гильдии"
            or mode == "journal" and "Журнал" or "Обидчики"],
        subtitle = summary:GetText(),
        rows = data.list,
        startIndex = (page - 1) * data.pageSize + 1,
        columns = columns,
        cells = cells,
        onSelect = function(row)
            for index, current in ipairs(allRecords.list) do
                if current.id and current.id == row.id or current.entry and current.entry == row.entry then
                    page, selection = math.ceil(index / allRecords.pageSize), current
                    note.RefreshWindow()
                    return
                end
            end
        end,
    })
end

function note.KillingBlowTexture(id, name)
    if C_Spell and C_Spell.GetSpellTexture then
        local spell = id or name
        local texture = spell and note.Public(C_Spell.GetSpellTexture(spell))
        if texture and texture ~= 0 then return texture end
    end
    return name == L["Автоатака"] and meleeIcon or questionIcon
end

local function setDetail()
    local row, demo = selection, note.DemoData()
    local leaders = row and row.members and note.GuildKillLeaders(row)
    detail.guildLeaders:SetShown(leaders ~= nil and leaders ~= false)
    if leaders then
        detail.guildLeaders.empty:SetShown(#leaders == 0)
        for index, item in ipairs(detail.guildLeaders.rows) do
            local member = leaders[index]
            item.member = member
            item:SetShown(member ~= nil)
            if member then
                item.name:SetText(member.name)
                item.kills:SetText(tostring(member.kills))
                classIcon(item.icon, member.class)
            end
        end
    end
    local strike = row and row.entry and row.entry.kind == "D" and row.entry or nil
    local world = warLayout and mode == "realm"
    local refined = warLayout and warLayout.refined
    local latest = world and row and row.latestStrike or nil
    if detail.playerModel then
        if world and row and row.profile then
            detail.playerModel:Present(row.id, row.profile, demo)
        else
            detail.playerModel:Dismiss()
        end
    end
    detail.strike:SetShown(strike ~= nil or latest ~= nil)
    if latest then
        detail.strike.spellId = latest.id
        detail.strike.spellName = latest.name
        detail.strike.icon:SetTexture(note.KillingBlowTexture(latest.id, latest.name))
    end
    detail.revenge:SetShown(strike ~= nil and row.guid ~= nil)
    detail.guildReport:SetShown(mode == "rivals" and strike ~= nil and row.guid ~= nil and not demo)
    detail.guildReport:SetEnabled(IsInGuild() == true)
    if detail.evidence then
        detail.evidence:SetShown(refined and world and row and row.sources and sourceIndex == 1 and true or false)
    end
    if fightReportButton then
        fightReportButton:SetShown(row ~= nil and row.entry ~= nil)
        fightReportButton:ClearAllPoints()
        fightReportButton:SetPoint("TOPLEFT", refined and 16 or strike and 131 or 16, refined and -290 or -311)
    end
    detail.revengeError:Hide()
    if strike then
        local target = note.GetHuntTarget and note.GetHuntTarget(note.DemoData())
        local tracked = target and target.id == row.guid and not target.completed and not target.expired
        detail.revenge:SetText(tracked and L["Открыть цель"] or L["Взять реванш"])
        local name = note.SpellName(strike.spellId, strike.spellName, demo)
        detail.strike.spellId = strike.spellId
        detail.strike.spellName = name
        detail.strike.icon:SetTexture(note.KillingBlowTexture(strike.spellId, name))
    end
    local character = row and row.profile
    local subject = row and (row.guid or row.guildThreat and row.id or row.profile and row.id)
    dossierButton:SetShown(subject ~= nil and note.OpenDossier ~= nil)
    forget:SetShown(not demo and row and row.guid ~= nil or false)
    if refined then
        detail.revenge:SetPrimary(mode == "rivals")
        if fightReportButton then fightReportButton:SetPrimary(mode == "journal") end
        dossierButton:SetPrimary(rankingModes[mode] or (mode == "rivals" and not strike))
    end
    local action
    if mode == "guild" then
        if guildThreatId then action = L["К обидчикам гильдии"]
        elseif guildThreatMode and row and row.guildThreat then action = L["История нападений"]
        elseif guildFilter then action = L["К списку гильдий"]
        elseif row and row.members then action = L["Рейтинг участников"] end
    elseif mode == "realm" then
        if victimFilter then action = L["К рейтингу мира"]
        elseif row and row.victims and #row.victims > 0 then action = L["Все жертвы"] end
    end
    detailAction:SetShown(action ~= nil)
    if action then
        detailAction:SetText(action)
        detailAction:SetWidth(world and (subject and 160 or 300) or (subject and 133 or 225))
    end
    detail.identity:SetShown(character ~= nil)
    detail.name:ClearAllPoints()
    detail.name:SetPoint("TOPLEFT", character and (world and 151 or 85) or 16, world and -16 or -19)
    detail.name:SetWidth(world and (character and 146 or 302) or (character and 163 or 232))
    detail.body:ClearAllPoints()
    detail.body:SetPoint("TOPLEFT", 16, character and (world and -180 or -157) or -56)
    if leaders then
        detail.body:ClearAllPoints()
        detail.body:SetPoint("TOPLEFT", 16, -101 - #leaders * 35)
    end
    if refined and not world and character then
        detail.body:ClearAllPoints()
        detail.body:SetPoint("TOPLEFT", 16, -157)
    end
    detail.body:SetMaxLines(world and (character and 6 or 14) or 0)
    if refined then
        detail.body:SetHeight(leaders and 124 or world and (character and 104 or 230)
            or (character and (strike and 76 or 129) or 235))
        detail.body:SetJustifyV("TOP")
    end
    if not row then
        detail.name:SetText(mode == "guild" and L["Карточка гильдии"] or L["Карточка персонажа"])
        detail.body:SetText(L["Выберите строку, чтобы открыть подробности."])
        return
    end
    detail.name:SetText(row.name)
    if row.incident then
        local incident = row.incident
        local lines = { date("%d.%m.%Y %H:%M:%S", incident.at) }
        if incident.kind == "D" then
            lines[#lines + 1] = L["Погиб: "] .. row.name
        else
            lines[#lines + 1] = L["Отомстил: "] .. row.name
            if incident.victimName then lines[#lines + 1] = L["За: "] .. incident.victimName end
        end
        if incident.zone then lines[#lines + 1] = L["Зона: "] .. note.SampleText(incident.zone, demo) end
        detail.body:SetText(table.concat(lines, "\n"))
        return
    end
    if row.spellRows then
        local lines = {
            (L["Добивания: %d"]):format(row.kills),
            (L["Способность известна: %d из %d"]):format(row.known, row.kills), "",
            L["|cffffd276Чем добивает чаще всего|r"],
        }
        if #row.spellRows == 0 then lines[#lines + 1] = L["Пока нет данных о способностях."] end
        for i = 1, math.min(10, #row.spellRows) do
            local spell = row.spellRows[i]
            local texture = note.KillingBlowTexture(spell.id, spell.name)
            lines[#lines + 1] = ("|T%s:16:16|t  %s  ×%d"):format(texture, spell.name, spell.count)
        end
        detail.body:SetText(table.concat(lines, "\n"))
        return
    end
    local text = {}
    if character then
        local profile = row.profile
        note.SetCharacterArt(detail.portrait, detail.raceIcon, detail.classIcon, row.guid or row.id, profile)
        if world then raceIcon(detail.portrait, profile) end
        local classToken = row.entry and row.entry.kind == "D" and row.entry.killerClass or row.class or profile.class
        local class = note.ClassLabel(classToken, profile.sex) or L["Класс неизвестен"]
        if classToken and classToken ~= profile.class then classIcon(detail.classIcon, classToken) end
        detail.className:SetText(class)
        local color = RAID_CLASS_COLORS and RAID_CLASS_COLORS[classToken]
        if color then detail.className:SetTextColor(color.r, color.g, color.b) else detail.className:SetTextColor(1, 0.82, 0) end
        detail.raceName:SetText(note.RaceLabel(profile, demo) or L["Раса неизвестна"])
        if row.levels then
            detail.level:SetText(L["Уровни на момент боя"])
        else
            detail.level:SetText(profile.level and (L["Уровень "] .. profile.level) or L["Уровень неизвестен"])
        end
        local guild = profile.guild or row.guild
        detail.guildName:SetText(guild and ("<" .. guild .. ">") or (profile.guild == false and L["Без гильдии"] or L["Гильдия неизвестна"]))
    end
    if row.guildThreat then
        text[#text + 1] = (L["Потерь гильдии: %d"]):format(row.deaths)
        text[#text + 1] = (L["Разных погибших: %d"]):format(row.distinctVictims or row.deaths)
        text[#text + 1] = (L["Реваншей: %d"]):format(row.revenge)
        if row.lastDeath then text[#text + 1] = L["Последнее нападение: "] .. date("%d.%m %H:%M", row.lastDeath.at) end
        if row.lastRevenge then text[#text + 1] = L["Последний реванш: "] .. date("%d.%m %H:%M", row.lastRevenge.at) end
    elseif row.guid then
        local personal = (L["Вы убили: %d    Вас убил: %d"]):format(row.kills, row.deaths)
        local outcome = row.entry.kind == "D" and L["|cffff756bВаша смерть|r"] or L["|cff9ddd8fВаше добивание|r"]
        local stamp, place = date("%d.%m.%Y  %H:%M:%S", row.entry.at), placeText(row.entry, demo)
        if refined and mode == "journal" then
            text = { outcome, place, stamp }
        elseif field.Enabled() and mode == "rivals" then
            text = { personal, outcome .. "  •  " .. date("%d.%m %H:%M", row.entry.at),
                note.SampleText(row.entry.zone, demo) or L["Зона неизвестна"] }
        else
            text = { personal, "", outcome, stamp, place }
        end
    elseif row.levels then
        text[#text + 1] = (L["Добиваний этого игрока: %d"]):format(row.kills)
        for _, line in ipairs(levelLines(row.levels)) do text[#text + 1] = line end
    else
        if mode == "realm" then
            text[#text + 1] = (L["Добивания: %d • Разных жертв: %d"]):format(row.kills, #row.victims)
            if not refined and sourceIndex == 1 and row.sources then
                local s = row.sources
                text[#text + 1] = (L["Личные %d · Гильдия %d · Импорт %d"]):format(s.own, s.guild, s.imported)
            end
        else
            text[#text + 1] = (L["Добивания: %d    Смерти: %d"]):format(row.kills, row.deaths)
        end
        if row.profile and (mode == "realm" or mode == "guild" and guildFilter) then
            local sharedProfile = note.GetRankingProfile and note.GetRankingProfile(row.id)
            local rank = sharedProfile and note.LadderRanks[sharedProfile.tier]
                or note.LadderRank(row.kills, #(row.victims or {}))
            if rank then text[#text + 1] = "|cffffd276" .. L[rank.name] .. "|r" end
            if sharedProfile then
                text[#text + 1] = L["Достижения: %d · Серии: %d"]:format(sharedProfile.earned, sharedProfile.rampages)
            else
                text[#text + 1] = L["Достижения: нет данных"]
            end
        end
        if row.members then
            local faction = L[factionName[row.faction]] or L["Неизвестна"]
            local icon = factionIcon[row.faction]
            if icon then faction = ("|T%s:15:15|t %s"):format(icon, faction) end
            text[#text + 1] = L["Фракция: "] .. faction
            text[#text + 1] = row.rosterCount and (L["Всего в составе: %d (%s)"]):format(
                row.rosterCount, date("%d.%m", row.rosterAt)) or L["Всего в составе: нет данных"]
            text[#text + 1] = (L["Участников в записях: %d"]):format(#row.members)
            local owned, total = note.GuildTerritoryShare(row)
            text[#text + 1] = total > 0 and L["Территории: %d/%d (%.1f%%)"]:format(owned, total, owned * 100 / total)
                or L["Территории: нет данных"]
        elseif #row.victims > 0 then
            local victimsHeading = L["\n|cffffd276Кого убивал чаще всего|r"]
            text[#text + 1] = field.Enabled() and victimsHeading:gsub("^\n", "") or victimsHeading
            for i = 1, math.min(world and 1 or mode == "realm" and 3 or 4, #row.victims) do
                local victim = row.victims[i]
                text[#text + 1] = ("%s  ×%d"):format(victim.player.name, victim.count)
                if mode == "realm" then
                    local levels = levelLines(victim.levels)
                    local snippet = table.concat(levels, ", ", 1, math.min(2, #levels))
                    text[#text + 1] = snippet .. (#levels > 2 and " ..." or "")
                end
            end
        end
    end
    detail.body:SetText(table.concat(text, "\n"))
end

function note.RefreshGuildTerritoryStats()
    if mode == "guild" and selection and selection.members and window and window:IsShown() then setDetail() end
end

function note.InvalidateRankHeader()
    headerStats = nil
end

function note.RefreshWindow()
    if not window or not window:IsShown() then return end
    local demo = note.DemoData()
    local faction = note.Profile(note.owner).faction
    local refined = warLayout and warLayout.refined
    local ranking, totalFights, rosters, worldStats, evidence
    local rankedList = mode == "realm" or mode == "guild"
    local palette = theme.Palette()
    local now = GetServerTime()
    if rankedList or not headerStats or now - headerStatsAt >= 60 then
        ranking, totalFights, rosters, worldStats, evidence = note.Ranking(demo, nil, mode == "guild" and not guildThreatMode)
        headerStats, headerStatsAt = worldStats, now
    end
    worldStats = headerStats
    for side, badge in pairs(factionBadges) do
        badge.edge:SetAlpha(side == faction and 1 or 0.4)
        if worldStats then
            badge.count:SetText(tostring(worldStats.factions[side]))
            badge.evidence = worldStats.factionSources[side]
        end
    end
    local style = note.GetHuntStyle and note.GetHuntStyle(demo)
    local cover = style and style.cover and style.cover.palette
    if theme.Enabled() then
        local rim = palette.bronze
        window:SetBackdropBorderColor(math.min(1, rim[1] + 0.21), math.min(1, rim[2] + 0.18),
            math.min(1, rim[3] + 0.14), 1)
    elseif cover then
        window:SetBackdropBorderColor(0.56 + cover[1] * 0.30, 0.54 + cover[2] * 0.30, 0.53 + cover[3] * 0.30, 1)
    else
        window:SetBackdropBorderColor(0.69, 0.65, 0.59, 1)
    end
    if mode == "hunt" then
        local title = style and style.title and style.title.id ~= "plain" and L[style.title.name]
        summary:SetText(title or L["PvP в открытом мире"])
        note.RefreshHuntBoard(demo)
        return
    end
    if mode == "settings" then
        summary:SetText(L["Оповещения, подсказки и обмен"])
        pauseAlert:SetText(note.AlertsSnoozed() and L["Возобновить алерты"] or L["Пауза алертов · 10 мин"])
        if tooltipMode then
            tooltipMode:SetText(note.db.playerTooltipNotesOnly and L["Метка и заметка"] or L["Со счётом боёв"])
            tooltipMode:SetEnabled(note.PlayerTooltipEnabled())
        end
        return
    end
    if mode == "territory" then
        summary:SetText(L["Карта территорий"])
        note.RefreshTerritories()
        return
    end
    if progressModes[mode] then
        summary:SetText(L[mode == "titles" and "Звания" or "Достижения"])
        note.RefreshLadder()
        return
    end
    if mode == "front" then
        summary:SetText(L["Фронт недели"])
        note.RefreshFront()
        return
    end
    note.RefreshGuildSyncStatus()
    local query = (strlower or string.lower)(search:GetText()):match("^%s*(.-)%s*$")
    local list, total
    local localMode = mode == "journal" or mode == "rivals"
    local folio = field.Enabled() and localMode
    local showMarked = folio and mode == "journal" and not journalScope
    local markedOnly = showMarked and (demo or note.db).journalMarkedOnly == true
    if localMode then heading:SetShown(true) end
    if folio and mode == "journal" then
        heading:ClearAllPoints()
        heading:SetPoint("TOPLEFT", showMarked and 31 or 290, showMarked and -211 or -179)
    end
    if journalBar.marked then
        journalBar.marked:SetShown(showMarked)
        journalBar.marked:SetSelected(markedOnly)
    end
    journalBar:SetShown(mode == "journal" and not journalScope)
    clearScope:SetShown(mode == "journal" and journalScope ~= nil)
    for key, control in pairs(journalTabs) do
        control:SetSelected(key == (note.db.journalFilter or "all"), factionColor[faction] or gold)
    end
    local rankingMode = mode == "realm" or mode == "stats" or (mode == "guild" and not guildThreatMode)
    nearbyButton:SetShown(localMode and (not refined or mode == "rivals"))
    mapButton:SetShown(localMode)
    sourceButton:SetShown(rankingMode and not (mode == "realm" and guildRankingOnly))
    sourceButton:SetText(refined and ((sourceIndex == 1 and L["Источники"] or L[rankingSources[sourceIndex].label]) .. "  +")
        or (L[rankingSources[sourceIndex].label]))
    guildThreatButton:SetShown(mode == "guild" and note.GuildThreats ~= nil)
    guildThreatButton:ClearAllPoints()
    guildThreatButton:SetPoint("TOPLEFT", guildThreatMode and 305 or 518, guildThreatMode and -482 or -493)
    guildThreatButton:SetText(guildThreatMode and L["Рейтинг гильдий"] or L["Обидчики гильдии"])
    local filters = note.MapFiltersActive and note.MapFiltersActive(demo)
    mapButton:SetText(filters and L["Карта • фильтр"] or L["Карта"])
    if mode == "guild" and guildThreatMode then
        local threats, guild = note.GuildThreats(demo)
        local guildName = guild or L["Вы вне гильдии"]
        list = {}
        for _, threat in ipairs(threats) do
            if guildThreatId == threat.id then
                for i, incident in ipairs(threat.history) do
                    local name = incident.memberName or L["Игрок не определён"]
                    if query == "" or (strlower or string.lower)(name):find(query, 1, true) then
                        list[#list + 1] = { id = threat.id .. "#" .. i, name = name, incident = incident }
                    end
                end
                break
            elseif not guildThreatId and (query == "" or (strlower or string.lower)(threat.name):find(query, 1, true)) then
                threat.guildThreat = true
                list[#list + 1] = threat
            end
        end
        if guildThreatId then
            summary:SetText(guildName .. L[" • История нападений и реваншей"])
            heading:SetText(#list > 0 and L["Согильдеец • Событие"] or L["По вашему запросу записей нет."])
        else
            summary:SetText(guildName .. L[" • Обидчики гильдии за 30 дней"])
            heading:SetText(#list > 0 and L["Обидчик • Нападения / реванши"] or L["По вашему запросу записей нет."])
        end
    elseif mode == "stats" then
        local fights, stats = totalFights, worldStats
        if sourceIndex ~= 1 then
            local _, filtered, _, filteredStats = note.Ranking(demo, rankingSources[sourceIndex].id)
            fights, stats = filtered, filteredStats
        end
        sourceCount = evidence
        list = {}
        for token, class in pairs(stats.classes) do
            local name = note.ClassLabel(token)
            if query == "" or (strlower or string.lower)(name):find(query, 1, true) then
                local spellRows = {}
                for spell, count in pairs(class.spells) do
                    spellRows[#spellRows + 1] = { name = spell, count = count, id = class.spellIds[spell] }
                end
                table.sort(spellRows, function(a, b)
                    if a.count ~= b.count then return a.count > b.count end
                    return a.name < b.name
                end)
                list[#list + 1] = { id = token, name = name, class = token,
                    kills = class.kills, known = class.known, spellRows = spellRows }
            end
        end
        table.sort(list, function(a, b)
            if a.kills ~= b.kills then return a.kills > b.kills end
            return a.name < b.name
        end)
        summary:SetText((L["За 30 дней • Добивания: %d • Без класса: %d • Со способностью: %d"]):format(
            fights, stats.unknown, stats.withSpell))
        heading:SetText(#list > 0 and L["Класс • Добивания"] or L["Пока нет данных о классах."])
        if demo and not selection and page == 1 and query == "" then selection = list[1] end
    elseif mode == "realm" or mode == "guild" then
        local entries, fights, guildRosters = ranking, totalFights, rosters
        if sourceIndex ~= 1 then
            entries, fights, guildRosters = note.Ranking(demo, rankingSources[sourceIndex].id, mode == "guild")
        end
        local ranking, rosters = entries, guildRosters
        total = fights
        if mode == "realm" and guildRankingOnly then
            ranking, total = note.GuildLadderPlayers(demo), 0
            for _, player in ipairs(ranking) do total = total + player.kills end
        end
        sourceCount = evidence
        local guildName, killerName
        if mode == "guild" then
            ranking = note.GuildRanking(ranking, rosters)
            if guildFilter then
                local members = {}
                for _, guild in ipairs(ranking) do
                    if guild.id == guildFilter then
                        members, guildName = guild.members, guild.name
                        break
                    end
                end
                ranking = members
            end
        elseif victimFilter then
            local victims = {}
            for _, player in ipairs(ranking) do
                if player.id == victimFilter then
                    killerName = player.name
                    for _, victim in ipairs(player.victims) do
                        local target = victim.player
                        victims[#victims + 1] = { id = target.id, name = target.name, profile = target.profile,
                            guild = target.guild, class = target.class, kills = victim.count, levels = victim.levels }
                    end
                    break
                end
            end
            ranking = victims
        else
            local killers = {}
            for _, player in ipairs(ranking) do
                if player.kills > 0 then killers[#killers + 1] = player end
            end
            ranking = killers
        end
        list = {}
        for i, row in ipairs(ranking) do
            if query == "" or (strlower or string.lower)(row.name):find(query, 1, true) then
                row.rank = i
                list[#list + 1] = row
            end
        end
        if victimFilter then
            summary:SetText((L["%s • За 30 дней • Разных жертв: %d"]):format(killerName or L["Игрок"], #ranking))
            heading:SetText(L["Жертвы • Добивания"])
        elseif guildFilter then
            summary:SetText((L["%s • За 30 дней • Участников в записях: %d"]):format(guildName or L["Гильдия"], #ranking))
            heading:SetText(L["Участник • Добивания / смерти"])
        elseif mode == "guild" then
            summary:SetText((L["За 30 дней • %d гильдий в записях"]):format(#ranking))
            heading:SetText(#list > 0 and L["Гильдия • Добивания / смерти"] or L["Пока нет данных о гильдиях."])
        else
            summary:SetText((L["За 30 дней • %d добиваний • %d игроков с добиваниями"]):format(total, #ranking))
            if guildRankingOnly then
                summary:SetText(L["Моя гильдия"] .. "  /  " .. summary:GetText())
            end
            heading:SetText(#list > 0 and L["Игрок • Добивания / разные жертвы"] or L["Пока нет записей по этому запросу."])
        end
    else
        local kills, deaths
        list, kills, deaths = journalRows(query, demo or note.db, demo)
        local hasFilter = mode == "journal" and (filters or markedOnly or query ~= "")
        summary:SetText((L["Личный журнал • Добивания: %d • Смерти: %d%s"]):format(
            kills, deaths, hasFilter and (L[" • Показано: "] .. #list) or ""))
        if mode == "journal" and journalScope then
            summary:SetText(L["Фронт недели"] .. " / " .. (note.SampleText(journalScope.name, demo) or L["Зона неизвестна"]))
        end
        if demo and not selection and page == 1 and query == "" then selection = list[1] end
        heading:SetText(#list > 0 and (mode == "rivals" and L["Обидчики • Добивания / смерти"] or L["Последние события"])
            or L["Пока нет записей по этому запросу."])
        if showMarked then heading:SetShown(#list == 0) end
    end
    local pageSize = mode == "journal" and 7 or warLayout and rankedList and (refined and 7 or 5) or visibleRows
    allRecords = { list = list, pageSize = pageSize }
    openAll:SetShown(#list > 0)
    local pages = math.max(1, math.ceil(#list / pageSize))
    page = math.min(page, pages)
    if (warLayout and mode == "realm") or refined then
        local first = (page - 1) * pageSize + 1
        local onPage
        for index = first, math.min(first + pageSize - 1, #list) do
            local row = list[index]
            if selection and (row.id and row.id == selection.id or row.entry and row.entry == selection.entry) then
                onPage = true
                break
            end
        end
        if not onPage then selection = list[first] end
    end
    if refined then
        previous:SetShown(pages > 1)
        nextPage:SetShown(pages > 1)
        pager:SetShown(pages > 1)
        local groupReturn = mode == "guild" and (guildFilter or guildThreatId) or mode == "realm" and victimFilter
        detail:SetShown(#list > 0 or groupReturn ~= nil and groupReturn ~= false or not localMode)
    end
    pager:SetText(page .. " / " .. pages)
    previous:SetEnabled(page > 1)
    nextPage:SetEnabled(page < pages)
    local selected
    for index, item in ipairs(rows) do
        local row = index <= pageSize and list[(page - 1) * pageSize + index]
        item.data = row
        item:SetShown(row and true or false)
        if row then
            local same = selection and ((row.guid and selection.entry == row.entry)
                or (row.id and row.id == selection.id))
            if same then selected = row end
            local accent = not warLayout and factionColor[faction] or gold
            if warLayout then
                if same then
                    local active = palette.active
                    item.tint:SetColorTexture(active[1] * 0.27, active[2] * 0.21, active[3] * 0.19, 1)
                else
                    local paper = palette.paper
                    item.tint:SetColorTexture(paper[1], paper[2], paper[3], index % 2 == 0 and 0.82 or 0.51)
                end
            elseif same then
                item.tint:SetColorTexture(0.085 + accent[1] * 0.14, 0.10 + accent[2] * 0.14, 0.12 + accent[3] * 0.14, 1)
            else
                item.tint:SetColorTexture(panelColor[1], panelColor[2], panelColor[3], index % 2 == 0 and 0.84 or 1)
            end
            item.selected:SetColorTexture(accent[1], accent[2], accent[3], 1)
            local tableRow = warLayout and (mode == "realm" or refined and mode == "guild")
            local podium = refined and row.rank and (mode == "realm" and not victimFilter
                or mode == "guild" and not guildFilter and not guildThreatMode) and podiumColors[row.rank]
            item.selected:SetShown(same and not tableRow and true or false)
            if item.rank then
                item.rank:SetShown(tableRow and row.rank ~= nil and true or false)
                if tableRow then
                    item.rank:ClearAllPoints()
                    item.rank:SetPoint("TOPLEFT", 5, podium and -17 or -10)
                    item.rank:SetText(row.rank and tostring(row.rank) or "")
                    item.rank:SetTextColor(unpack(podium or gold))
                end
                if item.crown then
                    item.crown:SetShown(podium ~= nil and podium ~= false)
                    if podium then item.crown:SetVertexColor(unpack(podium)) end
                end
                item.outline:SetShown(tableRow and same and true or false)
            end
            local title = mode == "realm" and not victimFilter and row.victims and note.LadderRank(row.kills, #row.victims)
            item.title:SetShown(title and true or false)
            if title then
                item.title:SetText(L[title.name])
                item.title:SetTextColor(unpack(title.color))
            end
            item.name:ClearAllPoints()
            item.name:SetPoint("TOPLEFT", folio and 91 or tableRow and 70 or 39, title and -1 or folio and -3 or -10)
            item.name:SetText(not tableRow and row.rank and (row.rank .. ".  " .. row.name) or row.name)
            if row.profile or row.class then
                local recordedClass = row.entry and row.entry.kind == "D" and row.entry.killerClass
                classIcon(item.icon, recordedClass or row.class or row.profile.class)
            else
                item.icon:SetTexture(factionIcon[row.faction] or guildIcon)
                item.icon:SetTexCoord(0, 1, 0, 1)
            end
            local caption, r, g, b
            if row.incident then
                local indicator = row.incident.kind == "D" and L["Гибель"] or L["Реванш"]
                caption, r, g, b = indicator .. "  " .. date("%d.%m %H:%M", row.incident.at), 0.93, 0.78, 0.49
            elseif row.guildThreat then
                caption, r, g, b = ("%d / %d"):format(row.deaths, row.revenge), 0.82, 0.73, 0.58
            elseif mode == "realm" or mode == "stats" then
                caption = tostring(row.kills)
                if mode == "realm" and row.victims then
                    caption = ("%d / %d"):format(row.kills, #row.victims)
                end
                r, g, b = 0.93, 0.78, 0.49
            elseif mode == "rivals" or mode == "guild" then
                caption, r, g, b = ("%d / %d"):format(row.kills, row.deaths), 0.82, 0.73, 0.58
            else
                local death = row.entry.kind == "D"
                caption = (death and L["Смерть"] or L["Добивание"]) .. "   " .. date("%d.%m  %H:%M", row.entry.at)
                r, g, b = 0.57, 0.80, 0.58
                if death then r, g, b = 1, 0.48, 0.43 end
            end
            item.caption:SetText(caption)
            item.caption:SetTextColor(r, g, b)
            if folio then
                local previousIndex = (page - 1) * pageSize + index - 1
                field.StyleRecord(item, row, index > 1 and list[previousIndex], mode, demo, same, index)
            end
        end
    end
    selection = selected
    setDetail()
end

local feedbackUrl = "https://docs.google.com/forms/d/e/1FAIpQLSeC0CEuHCn_eo5GS3CMOH1Saq1KZtjnhgZN1MGxaLR42VXgrQ/viewform"
StaticPopupDialogs.FDN_FEEDBACK_LINK = {
    button1 = CLOSE,
    hasEditBox = true,
    editBoxWidth = 315,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    OnShow = function(self)
        local edit = self.GetEditBox and self:GetEditBox() or self.EditBox or self.editBox
        edit:SetMaxLetters(0)
        edit:SetText(feedbackUrl)
        edit:SetFocus()
        edit:HighlightText()
    end,
    EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
}

local function showFeedbackLink(category)
    StaticPopupDialogs.FDN_FEEDBACK_LINK.text = L["Скопируйте ссылку, откройте её в браузере и выберите «%s»."]
    StaticPopup_Show("FDN_FEEDBACK_LINK", category)
end

local function buildSettings()
    exchange = CreateFrame("Frame", nil, window)
    exchange:SetPoint("TOPLEFT", 24, -120)
    exchange:SetSize(742, 400)

    local general = CreateFrame("Frame", nil, exchange, "BackdropTemplate")
    general:SetPoint("TOPLEFT", 0, -38)
    general:SetSize(742, 360)
    theme.Panel(general, unpack(theme.ink))
    local transfer = CreateFrame("Frame", nil, exchange, "BackdropTemplate")
    transfer:SetAllPoints(general)
    theme.Panel(transfer, unpack(theme.ink))

    local overviewTab, transferTab
    function exchange:SelectOptions(showTransfer)
        overviewTab:SetSelected(not showTransfer)
        transferTab:SetSelected(showTransfer)
        general:SetShown(not showTransfer)
        transfer:SetShown(showTransfer)
    end
    overviewTab = button(exchange, L["Интерфейс"], 153, 0, 0, function() exchange:SelectOptions(false) end)
    transferTab = button(exchange, L["Обмен данными"], 153, 160, 0, function() exchange:SelectOptions(true) end)

    local function section(text, y)
        local heading = label(general, "GameFontNormal", 360, 16, y)
        heading:SetTextColor(unpack(gold))
        heading:SetText(text)
    end
    local function option(key, text, x, y, onChange)
        local control = CreateFrame("CheckButton", nil, general, "UICheckButtonTemplate")
        control:SetPoint("TOPLEFT", x, y)
        control:SetScript("OnClick", function(self)
            note.db[key] = self:GetChecked() and true or false
            if onChange then onChange() end
        end)
        label(general, "GameFontHighlight", x == 14 and 315 or 320, x + 30, y - 8):SetText(text)
        return control
    end

    local draft = note.LanguagePreference()
    local languageMenu, applyLanguage
    local languageStatus = label(general, "GameFontHighlightSmall", 690, 16, -47)
    section(L["Язык интерфейса"], -19)
    local function selectLanguage(locale)
        draft = locale
        languageMenu:SetText(note.LanguageLabel(draft))
        applyLanguage:SetEnabled(draft ~= note.LanguagePreference())
        languageStatus:SetText("")
    end
    languageMenu = button(general, "", 173, 177, -12, function(self)
        if not MenuUtil or not MenuUtil.CreateContextMenu then
            for i, candidate in ipairs(note.languages) do
                if candidate[1] == draft then
                    selectLanguage(note.languages[i % #note.languages + 1][1])
                    break
                end
            end
            return
        end
        MenuUtil.CreateContextMenu(self, function(_, root)
            note.StyleLocaleMenu(root:CreateTitle(L["Укажите язык интерфейса."]))
            for _, candidate in ipairs(note.languages) do
                local locale = candidate[1]
                note.StyleLocaleMenu(root:CreateRadio(note.LanguageLabel(locale), function()
                    return draft == locale
                end, function() selectLanguage(locale) end), true)
            end
        end)
    end)
    local baseText = languageMenu:GetFontString()
    note.StyleLocaleFont(baseText, true)
    applyLanguage = button(general, L["Применить и перезагрузить"], 189, 358, -12, function()
        local _, feedback = note.ApplyLanguage(draft)
        languageStatus:SetText(feedback or "")
    end)
    selectLanguage(draft)

    section(L["Оповещения и виджеты"], -78)
    marks = option("marks", L["Показывать череп над обидчиками вне боя"], 14, -101, note.RefreshMarks)
    alertToggle = option("alerts", L["Показывать алерт об обидчике рядом"], 365, -101, note.RefreshAlert)
    soundToggle = option("alertSound", L["Звук алерта"], 14, -135)
    flashToggle = option("alertFlash", L["Мигание алерта"], 166, -135)
    tooltipToggle = option("playerTooltip", L["Подсказки игроков"], 365, -135, note.RefreshWindow)
    tooltipMode = button(general, "", 149, 565, -139, function()
        note.db.playerTooltipNotesOnly = not note.db.playerTooltipNotesOnly
        note.RefreshWindow()
    end)
    minimapToggle = option("minimapButton", L["Кнопка под миникартой"], 14, -170, note.RefreshMinimapButton)
    autoReportToggle = option("autoFightReport", L["Открывать разбор после гибели"], 365, -170)
    pauseAlert = button(general, "", 180, 16, -211, function()
        note.ToggleAlertPause()
        note.RefreshWindow()
    end)
    zoneScoreToggle = option("zoneScoreHUD", L["Показывать счёт текущей зоны"], 365, -208, note.RefreshZoneScoreHUD)

    section(L["Оформление"], -242)
    local themeStatus = label(general, "GameFontHighlightSmall", 686, 16, -302)
    local switch = button(general, L[theme.Palette().label], 265, 16, -272, function(self)
        local prefs = {}
        for _, id in ipairs(theme.order) do
            local choice = id
            local caption = L[theme.Palette(choice).label]
            if choice == theme.Preference() then caption = "•  " .. caption end
            prefs[#prefs + 1] = { caption, function()
                themeStatus:SetText(theme.SetPreference(choice) or "")
            end }
        end
        if GameTooltip:IsOwned(self) then GameTooltip:Hide() end
        theme.ShowMenu(self, prefs)
    end)
    textHint(switch, L["Смена темы перезагружает интерфейс."])
    local fontLabels = { warcraft = "Шрифт WoW", compact = "Компактный шрифт" }
    local function applyFont(preset)
        local _, feedback = note.ApplyFontPreference(preset)
        themeStatus:SetText(feedback or "")
    end
    local fontPicker = button(general, L[fontLabels[note.FontPreference()]], 200, 294, -272, function(self)
        if not MenuUtil or not MenuUtil.CreateContextMenu then
            applyFont(note.FontPreference() == "warcraft" and "compact" or "warcraft")
            self:SetText(L[fontLabels[note.FontPreference()]])
            return
        end
        MenuUtil.CreateContextMenu(self, function(_, root)
            for _, preset in ipairs({ "warcraft", "compact" }) do
                local choice = preset
                note.StyleLocaleMenu(root:CreateRadio(L[fontLabels[choice]], function()
                    return note.FontPreference() == choice
                end, function()
                    applyFont(choice)
                    self:SetText(L[fontLabels[note.FontPreference()]])
                end))
            end
        end)
    end)
    textHint(fontPicker, L["Смена шрифта перезагружает интерфейс."])

    button(general, L["Как пользоваться"], 200, 16, -323, note.OpenGuide)
    button(general, L["Мой профиль"], 200, 226, -323, function() note.OpenDossier(note.owner) end)
    button(general, L["Сообщить о баге"], 143, 435, -323, function()
        showFeedbackLink("Bug report")
    end)
    button(general, L["Оставить отзыв"], 143, 583, -323, function()
        showFeedbackLink("Feedback")
    end)

    local intro = label(transfer, "GameFontHighlight", 708, 16, -17)
    intro:SetText(L["Гильдейский обмен передаёт время, имена и ID участников. При наличии передаются уровни, классы, способности и данные гильдий."])
    sharing = button(transfer, "", 206, 16, -58, function()
        note.ToggleSharing()
        sharing:SetText(note.db.sharing and L["Гильдия: обмен включён"] or L["Гильдия: обмен выключен"])
    end)
    local zoneSharing
    local function updateZoneSharing()
        zoneSharing:SetText(note.db.territorySharing and L["Территории: обмен включён"] or L["Территории: обмен выключен"])
    end
    zoneSharing = button(transfer, "", 248, 232, -58, function()
        note.SetTerritorySharing(not note.db.territorySharing)
        updateZoneSharing()
    end)
    updateZoneSharing()
    textHint(zoneSharing, L["Обмен по зонам в гильдии, группе и рейде."])

    local hint = label(transfer, "GameFontHighlightSmall", 460, 16, -95)
    hint:SetText(L["Для обмена вне гильдии скопируйте экспорт. Для импорта вставьте полученные записи того же мира."])
    local mapSync = button(transfer, "", 197, 490, -91, function()
        note.SetMapSync(not note.MapSyncEnabled())
    end)
    function note.RefreshMapSyncOption()
        mapSync:SetText(L[note.MapSyncEnabled() and "PvP-карта: вкл." or "PvP-карта: выкл."])
    end
    note.RefreshMapSyncOption()
    textHint(mapSync, L["Готовит будущие PvP-убийства открытого мира для отправки на сайт через Sync после выхода или /reload."])
    local scroll = CreateFrame("ScrollFrame", nil, transfer, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 16, -132)
    local editHeight = 151
    scroll:SetSize(686, editHeight)
    fill(scroll, 0.03, 0.045, 0.06)
    local edit = CreateFrame("EditBox", nil, scroll)
    edit:SetMultiLine(true)
    edit:SetAutoFocus(false)
    edit:SetFontObject(ChatFontNormal)
    note.StyleLocaleFont(edit)
    edit:SetTextInsets(10, 10, 7, 7)
    edit:SetSize(686, editHeight)
    edit:SetMaxBytes(90000)
    scroll:SetScrollChild(edit)
    edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    edit:SetScript("OnTextChanged", function(self)
        local _, breaks = self:GetText():gsub("\n", "")
        self:SetHeight(math.max(editHeight, (breaks + 2) * 23))
    end)
    scroll:EnableMouse(true)
    scroll:SetScript("OnMouseDown", function() edit:SetFocus() end)
    local status = label(transfer, "GameFontHighlightSmall", 468, 16, -328)
    local webExport = button(transfer, L["Экспорт для сайта"], 197, 490, -58, function()
        local text, players, guilds, zones = note.ExportWebSnapshot()
        if not text then return end
        edit:SetMaxBytes(math.max(90000, #text))
        edit:SetText(text)
        edit:SetFocus()
        edit:HighlightText()
        status:SetText(L["Скопируйте для сайта: %d игроков, %d гильдий, %d зон."]:format(players, guilds, zones))
    end)
    textHint(webExport, L["Скопируйте снимок и вставьте его на сайте."])
    local webAutosave = button(transfer, "", 197, 490, -321, function(self)
        note.SetWebAutosave(not note.WebAutosaveEnabled())
        self:SetText(L[note.WebAutosaveEnabled() and "Автоснимок: вкл." or "Автоснимок: выкл."])
    end)
    webAutosave:SetText(L[note.WebAutosaveEnabled() and "Автоснимок: вкл." or "Автоснимок: выкл."])
    textHint(webAutosave, L["Сохраняет снимок при выходе и /reload для локального помощника."])
    button(transfer, L["Подготовить экспорт"], 175, 16, -291, function()
        local text, count = note.Export()
        edit:SetMaxBytes(90000)
        edit:SetText(count > 0 and text or "")
        edit:SetFocus()
        edit:HighlightText()
        status:SetText((L["Готово записей: %d. Скопируйте выделенный текст."]):format(count))
    end)
    button(transfer, L["Импортировать"], 136, 200, -291, function()
        local text = edit:GetText()
        local count
        if text:match("^FDNZ1[\r\n]") then count = note.ImportTerritories(text)
        else count = note.Import(text) end
        status:SetText(count and (L["Добавлено записей: "] .. count)
            or L["Вставьте экспорт этого мира. Для карты принимается FDNZ1 за текущую неделю."])
        edit:ClearFocus()
    end)
    button(transfer, L["Очистить поле"], 130, 345, -291, function()
        edit:SetMaxBytes(90000)
        edit:SetText("")
        status:SetText("")
    end)
    button(transfer, L["Экспорт карты"], 203, 484, -291, function()
        local text, count = note.ExportTerritories()
        edit:SetMaxBytes(90000)
        edit:SetText(count > 0 and text or "")
        edit:SetFocus()
        edit:HighlightText()
        status:SetText((L["Готово записей: %d. Скопируйте выделенный текст."]):format(count))
    end)
    exchange:SelectOptions(false)
    exchange:Hide()
end

local function position(control, x, y, parent)
    control:ClearAllPoints()
    if parent then control:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    else control:SetPoint("TOPLEFT", x, y) end
end

local function applyWarLayout(world)
    if not warLayout then return end
    local folio = field.Enabled() and (mode == "journal" or mode == "rivals")
    local refined = warLayout.refined
    local ranked = rankingModes[mode] == true
    if warLayout.list.fieldPaper then field.ShowPage(warLayout.list, folio) end
    heading:SetTextColor(unpack(folio and { 0.27, 0.145, 0.075 } or gold))
    heading:SetShadowOffset(folio and 0 or 1, folio and 0 or -1)
    searchLabel:SetTextColor(unpack(folio and { 0.27, 0.145, 0.075 } or writing))
    searchLabel:SetShadowOffset(folio and 0 or 1, folio and 0 or -1)
    pager:SetTextColor(unpack(folio and { 0.27, 0.145, 0.075 } or writing))
    pager:SetShadowOffset(folio and 0 or 1, folio and 0 or -1)
    warLayout.list:SetShown(world or refined and (mode == "journal" or mode == "rivals" or ranked))
    warLayout.skull:Show()
    position(warLayout.title, 70, -12)
    position(summary, 70, -37)
    for _, badge in pairs(factionBadges) do badge:Show() end
    local journal = mode == "journal"
    position(warLayout.list, 20, world and -197 or journal and -145 or -116)
    warLayout.list:SetSize(world and 398 or 470, world and 332 or journal and 383 or 412)
    if world then
        heading:SetWidth(133)
        position(heading, 283, -205)
        position(searchLabel, 31, -208)
        position(search, 106, -202)
        for index, item in ipairs(rows) do
            position(item, 24, -228 - (index - 1) * 34)
            if refined then item:SetHeight(31) end
        end
    else
        heading:SetWidth(191)
    end
    position(detail, world and 428 or 502, world and -197 or journal and -149 or -123)
    detail:SetSize(world and 338 or 264, world and 326 or journal and 376 or 402)
    detail.body:SetWidth(world and 302 or 232)
    position(detail.portraitFrame, 15, world and -49 or -13)
    detail.portraitFrame:SetSize(world and 119 or 60, world and 119 or 60)
    position(detail.level, world and 151 or 85, -51)
    detail.level:SetWidth(world and 167 or 160)
    position(detail.raceFrame, world and 151 or 16, world and -69 or -83)
    position(detail.raceName, world and 181 or 46, world and -75 or -88)
    detail.raceName:SetWidth(world and 133 or 198)
    position(detail.classFrame, world and 151 or 16, world and -95 or -110)
    position(detail.className, world and 181 or 46, world and -101 or -115)
    detail.className:SetWidth(world and 133 or 198)
    position(detail.guildName, world and 151 or 16, world and -118 or -138)
    detail.guildName:SetWidth(world and 166 or 231)
    detail.body:SetSpacing(world and 2 or refined and 4 or 6)
    position(detail.strike, world and 151 or 16, world and -135 or (refined and -241 or -272))
    detail.strike:SetWidth(world and 167 or 232)
    position(detail.strike.title, 44, world and -5 or -12)
    detail.strike.title:SetWidth(world and 123 or 190)
    detail.strike.title:SetText(L[world and "Последний известный смертельный удар" or "Смертельный удар"])
    position(detailAction, 16, world and -286 or -340)
    position(dossierButton, world and 202 or 157, world and -286 or -340)
    if refined then
        position(detail.revenge, 135, -290)
        detail.revenge:SetWidth(107)
        position(forget, 16, -340)
    end
    dossierButton:SetWidth(world and 116 or 85)
    local rankColumn = world or refined and mode == "guild"
    for _, item in ipairs(rows) do
        item:SetWidth(world and 390 or 460)
        item.rank:SetShown(rankColumn and true or false)
        position(item.iconFrame, folio and 57 or rankColumn and 36 or 5, -5)
        position(item.name, folio and 91 or rankColumn and 70 or 39, folio and -3 or -10)
        item.name:SetWidth(folio and 226 or 225)
        position(item.caption, folio and 351 or world and 278 or 269, -11)
        item.caption:SetWidth(folio and 97 or world and 100 or 180)
        field.LayoutRecord(item, folio)
    end
    position(sourceButton, world and 252 or 305, -482)
    sourceButton:SetWidth(world and 162 or 179)
end

choose = function(tab)
    theme.CloseMenu()
    if tab == "stats" or tab == "ladder" then tab = "realm" end
    mode, page, selection, guildFilter, victimFilter = tab, 1, nil, nil, nil
    guildThreatMode, guildThreatId = false, nil
    if rankingModes[tab] then activeRanking = tab end
    local accent = factionColor[note.Profile(note.owner).faction] or gold
    local primary = rankingModes[tab] and "ranking" or progressModes[tab] and "journal" or tab
    for key, control in pairs(tabs) do control:SetSelected(key == primary, accent) end
    for key, control in pairs(rankTabs) do
        control:SetSelected(key == tab, gold)
        control.seam:SetShown(key == tab)
    end
    settingsButton:SetSelected(tab == "settings", accent)
    local inJournal = tab == "journal" or progressModes[tab]
    journalNavigation:SetShown(inJournal and true or false)
    for key, control in pairs(journalNavigation.tabs) do control:SetSelected(key == tab, accent) end
    window.progress:ShowSection(tab)
    local ranked = rankingModes[tab] == true
    journalScope = nil
    rankingBar:SetShown(ranked)
    journalBar:SetShown(tab == "journal")
    heading:ClearAllPoints()
    local searchTop = tab == "journal" and -176 or -122
    heading:SetPoint("TOPLEFT", 290, searchTop - 3)
    heading:Show()
    searchLabel:ClearAllPoints()
    searchLabel:SetPoint("TOPLEFT", 31, searchTop - 6)
    search:ClearAllPoints()
    search:SetPoint("TOPLEFT", 106, searchTop)
    for index, item in ipairs(rows) do
        item:ClearAllPoints()
        item:SetPoint("TOPLEFT", 24, (tab == "journal" and -203 or -149) - (index - 1) * (tab == "journal" and 35 or 40))
        item:SetHeight(tab == "journal" and 33 or 36)
    end
    local rankList = tab == "realm" or tab == "guild"
    applyWarLayout(rankList)
    window.rankingMap:SetShown(ranked)
    window.rankingMap.guildScope:SetShown(tab == "realm")
    for key, body in pairs(window.rankingBodies) do body:SetShown(tab == key) end
    window.territory:SetShown(tab == "territory")
    content:SetShown(tab ~= "settings" and tab ~= "hunt" and tab ~= "territory" and not progressModes[tab] and not window.rankingBodies[tab])
    exchange:SetShown(tab == "settings")
    huntBoard:SetShown(tab == "hunt")
    search:SetText("")
    search:ClearFocus()
    if tab == "settings" then
        exchange:SelectOptions(false)
        marks:SetChecked(note.db.marks ~= false)
        alertToggle:SetChecked(note.db.alerts ~= false)
        soundToggle:SetChecked(note.db.alertSound ~= false)
        flashToggle:SetChecked(note.db.alertFlash ~= false)
        minimapToggle:SetChecked(note.db.minimapButton ~= false)
        zoneScoreToggle:SetChecked(note.db.zoneScoreHUD ~= false)
        if tooltipToggle then tooltipToggle:SetChecked(note.PlayerTooltipEnabled()) end
        if autoReportToggle then autoReportToggle:SetChecked(note.db.autoFightReport == true) end
        sharing:SetText(note.db.sharing and L["Гильдия: обмен включён"] or L["Гильдия: обмен выключен"])
    end
    note.RefreshWindow()
end

local function buildJournalFilters()
    journalBar = CreateFrame("Frame", nil, content)
    journalBar:SetPoint("TOPLEFT", 24, -148)
    journalBar:SetSize(460, 27)
    journalTabs = {}
    for index, item in ipairs(journalFilters) do
        local key = item[1]
        journalTabs[key] = button(journalBar, L[item[2]], 109, (index - 1) * 117, 0, function()
            note.db.journalFilter, page, selection = key, 1, nil
            note.RefreshWindow()
        end)
    end
    if field.Enabled() then
        journalBar.marked = button(journalBar, L["Только с меткой"], 146, 278, -26, function()
            local source = note.DemoData() or note.db
            source.journalMarkedOnly = not source.journalMarkedOnly
            page, selection = 1, nil
            note.RefreshWindow()
        end, "toggle", 22)
    end
    clearScope = button(content, L["Сбросить зону"], 143, 518, -493, function()
        journalScope, page, selection = nil, 1, nil
        note.RefreshWindow()
    end)
end

-- These display IDs are the base appearances of the eight original playable races.
local raceDisplays = {
    human = { 49, 50 }, orc = { 51, 52 }, dwarf = { 53, 54 }, nightelf = { 55, 56 },
    scourge = { 57, 58 }, tauren = { 59, 60 }, gnome = { 1563, 1564 }, troll = { 1478, 1479 },
}

local function buildPlayerModel(portraitFrame, portrait)
    local model = CreateFrame("PlayerModel", nil, portraitFrame)
    model:SetPoint("TOPLEFT", 4, -4)
    model:SetPoint("BOTTOMRIGHT", -4, 4)
    model:Hide()
    if type(model.SetUnit) ~= "function" then return end

    local rotation = 0.15
    local marker = note.CreateFontString(model, nil, "OVERLAY", "GameFontHighlightSmall")
    marker:SetPoint("BOTTOMLEFT", 2, 4)
    marker:SetPoint("BOTTOMRIGHT", -2, 4)
    marker:SetText(L["Типовая модель"])
    marker:SetJustifyH("CENTER")
    marker:SetShadowOffset(1, -1)

    local hasLoadedEvent = model.HasScript and model:HasScript("OnModelLoaded") == true
    local function showModel(self)
        if not self.guid or not self.loading then return end
        self.ready = true
        self.loading = false
        portrait:Hide()
        self:SetAlpha(1)
        self:EnableMouse(self.SetRotation ~= nil)
        marker:SetShown(self.loadedDisplay ~= nil)
        if self.SetPortraitZoom then self:SetPortraitZoom(0.22) end
        if self.SetRotation then self:SetRotation(rotation, false) end
    end

    if hasLoadedEvent then model:SetScript("OnModelLoaded", showModel) end

    local function refresh(self, force, addedPlate, removedPlate)
        local unit
        if not self.demo then
            if not InCombatLockdown() then
                unit = note.VisiblePlayerUnit(self.guid, addedPlate, removedPlate)
            elseif self.ready and self.loadedUnit == "player" and self.guid == note.owner then
                return
            end
        end
        local display = self.display
        if not force and self.tried and self.requestUnit == unit and self.requestDisplay == display then return end
        self.tried, self.requestUnit, self.requestDisplay = true, unit, display
        self.ready, self.loading, self.loadedUnit, self.loadedDisplay = false, false, nil, nil
        if self.ClearModel then self:ClearModel() end
        portrait:Show()
        self:SetAlpha(0)
        self:EnableMouse(false)
        marker:Hide()

        local ok, accepted
        if unit then
            self.loading, self.loadedUnit = true, unit
            ok, accepted = pcall(self.SetUnit, self, unit, false)
        end
        if not ok or accepted == false then
            self.loading, self.loadedUnit = false, nil
            if display and self.SetDisplayInfo then
                self.loading, self.loadedDisplay = true, display
                ok, accepted = pcall(self.SetDisplayInfo, self, display)
            end
        end
        if not ok or accepted == false then
            self.loading, self.loadedDisplay = false, nil
        elseif not hasLoadedEvent then
            local file = self.GetModelFileID and note.Public(self:GetModelFileID())
            if (type(file) == "number" and file > 0) or accepted == true then showModel(self) end
        end
    end

    function model:Present(guid, profile, demo)
        local race = profile.raceFile and profile.raceFile:lower() or raceNames[profile.race]
        local displays = raceDisplays[race == "undead" and "scourge" or race]
        local display = displays and (profile.sex == 2 and displays[1] or profile.sex == 3 and displays[2])
        local different = guid ~= self.guid or demo ~= self.demo or display ~= self.display
        if different then
            self:SetScript("OnUpdate", nil)
            rotation = 0.15
        end
        self.guid, self.display, self.demo = guid, display or nil, demo
        self:Show()
        if self:IsVisible() then refresh(self, different) end
    end

    function model:Dismiss()
        self:Hide()
        self.guid, self.display, self.demo = nil, nil, nil
        portrait:Show()
    end

    model:SetScript("OnShow", function(self) refresh(self, true) end)
    model:SetScript("OnHide", function(self)
        self:SetScript("OnUpdate", nil)
        self:EnableMouse(false)
        self.ready, self.loading, self.tried, self.loadedUnit, self.loadedDisplay = nil, nil, nil, nil, nil
        portrait:Show()
    end)
    for _, event in ipairs({ "PLAYER_TARGET_CHANGED", "UPDATE_MOUSEOVER_UNIT",
        "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED", "UNIT_MODEL_CHANGED",
        "PLAYER_EQUIPMENT_CHANGED", "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED" }) do
        model:RegisterEvent(event)
    end
    model:SetScript("OnEvent", function(self, event, unit)
        if not self:IsVisible() then return end
        if event == "UNIT_MODEL_CHANGED" and unit ~= self.loadedUnit then return end
        if event == "PLAYER_EQUIPMENT_CHANGED" and self.loadedUnit ~= "player" then return end
        local force = event == "UNIT_MODEL_CHANGED" or event == "PLAYER_EQUIPMENT_CHANGED"
        refresh(self, force, event == "NAME_PLATE_UNIT_ADDED" and unit or nil,
            event == "NAME_PLATE_UNIT_REMOVED" and unit or nil)
    end)
    if model.SetRotation then
        model:SetScript("OnMouseDown", function(self, buttonName)
            if buttonName ~= "LeftButton" or not self.ready then return end
            local lastX = GetCursorPosition()
            self:SetScript("OnUpdate", function(frame)
                if not IsMouseButtonDown("LeftButton") then frame:SetScript("OnUpdate", nil); return end
                local x = GetCursorPosition()
                rotation = rotation + (x - lastX) * 0.015 / frame:GetEffectiveScale()
                lastX = x
                frame:SetRotation(rotation, false)
            end)
        end)
        model:SetScript("OnMouseUp", function(self) self:SetScript("OnUpdate", nil) end)
    end
    return model
end

local function buildWarLayout(title, skull)
    local map = theme.Map(window)
    position(map, 24, -116, window)
    map:SetSize(742, 72)
    map.guildScope = button(map, L["Моя гильдия"], 182, 13, -8, function(self)
        guildRankingOnly = not guildRankingOnly
        self:SetText(L[guildRankingOnly and "Все игроки" or "Моя гильдия"])
        self:SetSelected(guildRankingOnly)
        page, selection, victimFilter, sourceIndex = 1, nil, nil, 1
        note.RefreshWindow()
    end, "toggle", 26, "Interface\\GuildFrame\\GuildLogo-NoLogo")
    map.sync = note.BuildRankingSync(map)
    window.rankingMap = map
    map:Hide()
    title:SetDrawLayer("OVERLAY")
    local refined = theme.Refined()
    warLayout = { title = title, skull = skull, list = content.listWell, refined = refined }
    if field.Enabled() then
        theme.Panel(detail, unpack(field.boards))
    elseif theme.Enabled() then
        theme.Panel(detail, unpack(theme.paper))
    end
    detail.portraitFrame:SetBackdropBorderColor(0.85, 0.63, 0.31, 1)
    detail.playerModel = buildPlayerModel(detail.portraitFrame, detail.portrait)
    if refined then
        local function showEvidence(self)
            local sources = selection and selection.sources
            if not sources then return end
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(L["Источники за 30 дней"])
            for i = 2, #rankingSources do
                local origin = rankingSources[i]
                GameTooltip:AddDoubleLine(L[origin.label], tostring(sources[origin.id]), 1, 1, 1, 1, 0.82, 0)
            end
            note.StyleLocaleTooltip(GameTooltip)
            GameTooltip:Show()
        end
        detail.evidence = button(detail, "", 25, 299, -13, showEvidence, nil, 23)
        local evidenceIcon = detail.evidence:CreateTexture(nil, "ARTWORK")
        evidenceIcon:SetSize(16, 16)
        evidenceIcon:SetPoint("CENTER")
        evidenceIcon:SetTexture("Interface\\Icons\\INV_Misc_Note_01")
        detail.evidence:HookScript("OnEnter", showEvidence)
        detail.evidence:SetScript("OnLeave", function(self) if GameTooltip:IsOwned(self) then GameTooltip:Hide() end end)
        detail.evidence:SetScript("OnHide", function(self) if GameTooltip:IsOwned(self) then GameTooltip:Hide() end end)
    end
end

local function buildRowRank(item)
    if field.Enabled() then field.PrepareRecord(item) end
    item.rank = label(item, "GameFontNormal", 26, 6, -10)
    item.rank:SetJustifyH("CENTER")
    item.rank:Hide()
    item.outline = CreateFrame("Frame", nil, item, "BackdropTemplate")
    item.outline:SetAllPoints()
    item.outline:SetBackdrop({ edgeFile = tooltipBorder, edgeSize = 9 })
    item.outline:SetBackdropBorderColor(1, 0.76, 0.26, 1)
    item.outline:Hide()
    if theme.Refined() then
        item.crown = item:CreateTexture(nil, "OVERLAY")
        item.crown:SetSize(21, 16)
        item.crown:SetPoint("TOPLEFT", 7, -2)
        item.crown:SetTexture(podiumCrown)
        item.crown:Hide()
    end
end

function note.BuildGuildLeaders(detail)
    local guildLeaders = CreateFrame("Frame", nil, detail)
    detail.guildLeaders = guildLeaders
    guildLeaders:SetPoint("TOPLEFT", 16, -56)
    guildLeaders:SetSize(232, 128)
    local leaderHeading = label(guildLeaders, "GameFontNormal", 232, 0, 0)
    leaderHeading:SetText(L["Топ-3 по добиваниям"])
    guildLeaders.empty = label(guildLeaders, "GameFontHighlightSmall", 232, 0, -23)
    guildLeaders.empty:SetTextColor(unpack(muted))
    guildLeaders.empty:SetText(L["Пока нет добиваний."])
    guildLeaders.rows = {}
    for index, color in ipairs(podiumColors) do
        local item = CreateFrame("Button", nil, guildLeaders, "BackdropTemplate")
        item:SetSize(232, 31)
        item:SetPoint("TOPLEFT", 0, -20 - (index - 1) * 35)
        backdrop(item, flat, flat, 1, 1, 0.11, 0.084, 0.062)
        item:SetBackdropBorderColor(color[1] * 0.52, color[2] * 0.52, color[3] * 0.52, 1)
        local crown = item:CreateTexture(nil, "ARTWORK")
        crown:SetTexture(podiumCrown)
        crown:SetPoint("LEFT", 8, 0)
        crown:SetSize(19, 14)
        crown:SetVertexColor(unpack(color))
        item.icon = framedIcon(item, 26, 32, -2)
        item.name = label(item, "GameFontHighlightSmall", 124, 63, 0)
        item.name:SetHeight(31)
        item.name:SetMaxLines(2)
        item.name:SetJustifyV("MIDDLE")
        item.kills = label(item, "GameFontNormal", 34, 187, -8)
        item.kills:SetTextColor(unpack(color))
        item.kills:SetJustifyH("RIGHT")
        local highlight = item:CreateTexture(nil, "HIGHLIGHT")
        highlight:SetPoint("TOPLEFT", 1, -1)
        highlight:SetPoint("BOTTOMRIGHT", -1, 1)
        highlight:SetColorTexture(color[1], color[2], color[3], 0.12)
        item:SetHighlightTexture(highlight)
        item:SetScript("OnClick", function(self)
            local member = self.member
            if member and note.OpenDossier then
                note.OpenDossier(member.id, note.DemoData(), {
                    name = member.name, class = member.class, faction = member.faction, guild = member.guild,
                })
            end
        end)
        item:SetScript("OnEnter", function(self)
            local member = self.member
            if not member then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(member.name)
            GameTooltip:AddLine((L["Добивания: %d"]):format(member.kills), 1, 1, 1)
            GameTooltip:AddLine(L["Досье"], color[1], color[2], color[3])
            note.StyleLocaleTooltip(GameTooltip)
            GameTooltip:Show()
        end)
        local function hideTooltip(self)
            if GameTooltip:IsOwned(self) then GameTooltip:Hide() end
        end
        item:SetScript("OnLeave", hideTooltip)
        item:SetScript("OnHide", hideTooltip)
        guildLeaders.rows[index] = item
    end
    guildLeaders:Hide()
end

function note.BuildRankingNavigation()
    rankingBar = CreateFrame("Frame", nil, window.rankingMap)
    rankingBar:SetPoint("BOTTOMLEFT", 13, 4)
    rankingBar:SetSize(716, 29)
    rankTabs = {}
    for index, item in ipairs({
        { "realm", "Рейтинг мира", podiumCrown },
        { "guild", "Гильдии", "Interface\\GuildFrame\\GuildLogo-NoLogo" },
        { "front", "Фронт недели", "Interface\\Icons\\INV_Misc_Horn_01" },
    }) do
        local key = item[1]
        local tab = button(rankingBar, L[item[2]], 234, (index - 1) * 241, 0,
            function() choose(key) end, "bookmark", 29, item[3])
        local seam = tab:CreateTexture(nil, "OVERLAY")
        seam:SetPoint("BOTTOMLEFT", 4, 1)
        seam:SetPoint("BOTTOMRIGHT", -4, 1)
        seam:SetHeight(2)
        seam:SetColorTexture(1, 0.74, 0.34, 1)
        seam:Hide()
        tab.seam = seam
        rankTabs[key] = tab
    end
    local function body(builder)
        local slot = CreateFrame("Frame", nil, window)
        slot:SetPoint("TOPLEFT", 24, -192)
        slot:SetSize(742, 329)
        return builder(slot)
    end
    window.rankingBodies = { front = body(note.BuildEmbeddedFront) }
end

local function build()
    window = CreateFrame("Frame", "ForeverDeathNoteWindow", UIParent, "BackdropTemplate")
    window:SetSize(790, 540)
    window:SetPoint("CENTER")
    window:SetScale(math.min(1, UIParent:GetWidth() / 820, UIParent:GetHeight() / 570))
    window:SetFrameStrata("DIALOG")
    window:SetClampedToScreen(true)
    window:SetMovable(true)
    window:EnableMouse(true)
    tinsert(UISpecialFrames, "ForeverDeathNoteWindow")
    local palette = theme.Palette()
    local background = theme.Preference() == "legacy" and "Interface\\DialogFrame\\UI-DialogBox-Background-Dark" or flat
    backdrop(window, background, dialogBorder, 29, 8, unpack(palette.window))
    local header = CreateFrame("Frame", nil, window)
    header:SetPoint("TOPLEFT", 12, -8)
    header:SetSize(766, 66)
    local seam = header:CreateTexture(nil, "ARTWORK")
    seam:SetPoint("BOTTOMLEFT", 12, 0)
    seam:SetPoint("BOTTOMRIGHT", -12, 0)
    seam:SetHeight(1)
    seam:SetColorTexture(0.38, 0.42, 0.49, 0.74)
    header:EnableMouse(true)
    local skull, skullPlate = framedIcon(header, 46, 12, -9)
    skull:SetTexture(note.BrandIcon)
    skullPlate:SetBackdropBorderColor(0.77, 0.64, 0.43, 1)
    local title = label(header, "GameFontNormalLarge", 285, 70, -12)
    note.StyleHeadingFont(title)
    title:SetTextColor(unpack(gold))
    title:SetText(L["Тетрадь смерти"])
    summary = label(header, "GameFontHighlightSmall", 399, 70, -37)
    summary:SetMaxLines(2)
    summary:SetTextColor(unpack(muted))
    factionBadges = { Horde = factionBadge(header, "Horde", 470), Alliance = factionBadge(header, "Alliance", 578) }
    settingsButton = button(header, "", 31, 689, -16, function() choose("settings") end, nil, 31)
    local gear = settingsButton:CreateTexture(nil, "OVERLAY", nil, 2)
    gear:SetSize(24, 24)
    gear:SetPoint("CENTER")
    gear:SetTexture("Interface\\Icons\\Trade_Engineering")
    gear:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    textHint(settingsButton, L["Настройки"])
    local close = CreateFrame("Button", nil, header, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -6, -16)
    close:SetScript("OnClick", function() window:Hide() end)

    tabs = {
        hunt = button(window, L["Охота"], 143, 24, -78, function() choose("hunt") end,
            "major", 32, "Interface\\Icons\\Ability_DualWield"),
        journal = button(window, L["Журнал"], 143, 325, -78, function() choose("journal") end,
            "major", 32, "Interface\\Icons\\INV_Misc_Book_09"),
        rivals = button(window, L["Обидчики"], 143, 476, -78, function() choose("rivals") end,
            "major", 32, "Interface\\TargetingFrame\\UI-RaidTargetingIcon_8"),
        ranking = button(window, L["Рейтинги"], 142, 175, -78, function() choose(activeRanking) end,
            "major", 32, "Interface\\Icons\\INV_BannerPvP_01"),
        territory = button(window, L["Территории"], 139, 627, -78, function() choose("territory") end,
            "major", 32, "Interface\\Icons\\INV_Misc_Map_01"),
    }
    content = CreateFrame("Frame", nil, window)
    content:SetAllPoints()
    do
        local well = CreateFrame("Frame", nil, content, "BackdropTemplate")
        well:SetPoint("TOPLEFT", 20, -218)
        well:SetSize(398, 310)
        well:SetFrameLevel(window:GetFrameLevel())
        theme.Panel(well, unpack(palette.ink))
        if note.FieldJournal.Enabled() then note.FieldJournal.BoundPage(well) end
        content.listWell = well
    end
    buildJournalFilters()
    searchLabel = label(content, "GameFontHighlightSmall", 66, 31, -128)
    searchLabel:SetText(L["Поиск"])
    search = CreateFrame("EditBox", nil, content, "InputBoxTemplate")
    search:SetSize(174, 22)
    search:SetPoint("TOPLEFT", 354, -122)
    search:SetAutoFocus(false)
    note.StyleLocaleFont(search)
    search:SetMaxLetters(50)
    search:SetScript("OnTextChanged", function()
        page, selection = 1, nil
        if mode ~= "settings" then note.RefreshWindow() end
    end)
    search:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    search:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    heading = label(content, "GameFontNormalSmall", 241, 31, -127)
    heading:SetMaxLines(2)
    rows = {}
    for i = 1, visibleRows do
        local item = CreateFrame("Button", nil, content)
        item:SetPoint("TOPLEFT", 24, -149 - (i - 1) * 40)
        item:SetSize(460, 36)
        item.tint = fill(item, unpack(panelColor))
        item.selected = item:CreateTexture(nil, "ARTWORK")
        item.selected:SetPoint("TOPLEFT", 0, 0)
        item.selected:SetPoint("BOTTOMLEFT", 0, 0)
        item.selected:SetWidth(2)
        item:SetHighlightTexture("Interface\\Buttons\\UI-Listbox-Highlight2")
        item.icon, item.iconFrame = framedIcon(item, 26, 5, -5)
        buildRowRank(item)
        item.name = label(item, "GameFontHighlight", 225, 39, -10)
        item.name:SetWordWrap(false)
        local file, size, flags = item.name:GetFont()
        if file and size then item.name:SetFont(file, size + 1, flags or "") end
        item.title = label(item, "GameFontHighlightSmall", 196, 70, -16)
        item.title:SetWordWrap(false)
        item.title:Hide()
        item.caption = label(item, "GameFontHighlightSmall", 180, 269, -11)
        item.caption:SetJustifyH("RIGHT")
        if note.FieldJournal.Enabled() then item:RegisterForClicks("LeftButtonUp", "RightButtonUp") end
        item:SetScript("OnClick", function(self, mouseButton)
            if mouseButton == "RightButton" then
                if note.FieldJournal.Enabled() and (mode == "journal" or mode == "rivals") then
                    note.FieldJournal.RecordMenu(self, note.DemoData())
                end
                return
            end
            selection = self.data
            note.RefreshWindow()
        end)
        if note.FieldJournal.Enabled() then
            item:SetScript("OnEnter", function(self)
                if mode == "journal" or mode == "rivals" then note.FieldJournal.RecordTooltip(self, note.DemoData()) end
            end)
            local function hideTooltip(self) if GameTooltip:IsOwned(self) then GameTooltip:Hide() end end
            item:SetScript("OnLeave", hideTooltip)
            item:SetScript("OnHide", hideTooltip)
        end
        rows[i] = item
    end
    previous = button(content, L["Назад"], 28, 24, -482, function() page = page - 1; note.RefreshWindow() end)
    pager = label(content, "GameFontHighlight", 49, 53, -488)
    pager:SetJustifyH("CENTER")
    nextPage = button(content, L["Далее"], 28, 102, -482, function() page = page + 1; note.RefreshWindow() end)
    openAll = button(content, L["Открыть все"], 111, 137, -482, openFullTable)
    note.StylePageButton(previous, "prev")
    note.StylePageButton(nextPage, "next")
    textHint(previous, L["Назад"])
    textHint(nextPage, L["Далее"])
    nearbyButton = button(content, L["Рядом"], 73, 305, -482, function()
        if note.ToggleNearby then
            note.ToggleNearby(note.DemoData(), function(id) note.OpenDossier(id, note.DemoData()) end)
        end
    end)
    mapButton = button(content, L["Карта"], 101, 383, -482, function()
        if note.FieldJournal.Enabled() and mode == "rivals" and selection and selection.guid then
            note.OpenRivalMap(note.DemoData(), selection.guid)
        elseif note.OpenFightMap then
            note.OpenFightMap(note.DemoData(), selection and selection.entry)
        end
    end)
    local function selectSource(index)
        sourceIndex, page, selection = index, 1, nil
        guildFilter, victimFilter = nil, nil
        note.RefreshWindow()
    end
    sourceButton = button(content, L[rankingSources[1].label], 179, 305, -482, function(self)
        if not MenuUtil or not MenuUtil.CreateContextMenu then
            selectSource(sourceIndex % #rankingSources + 1)
            return
        end
        if GameTooltip:IsOwned(self) then GameTooltip:Hide() end
        MenuUtil.CreateContextMenu(self, function(_, root)
            note.StyleLocaleMenu(root:CreateTitle(L["Источник добиваний"]))
            for i, origin in ipairs(rankingSources) do
                local index = i
                local amount = sourceCount and (origin.id and sourceCount[origin.id]
                    or sourceCount.own + sourceCount.guild + sourceCount.imported)
                note.StyleLocaleMenu(root:CreateRadio(L[origin.label] .. (amount and ("  ·  " .. amount) or ""),
                    function() return sourceIndex == index end, function() selectSource(index) end))
            end
        end)
    end)
    sourceButton:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(L["Источники за 30 дней"])
        if sourceCount then
            for i = 2, #rankingSources do
                local origin = rankingSources[i]
                GameTooltip:AddDoubleLine(L[origin.label], tostring(sourceCount[origin.id]), 1, 1, 1, 1, 0.82, 0)
            end
        end
        GameTooltip:AddLine(L["Один бой учитывается один раз. Приоритет у личной записи, затем у гильдейской."], 0.83, 0.78, 0.68, true)
        GameTooltip:AddLine(L["Рейтинг отражает доступные записи. Данные ручного импорта могут быть изменены."], 0.83, 0.78, 0.68, true)
        note.StyleLocaleTooltip(GameTooltip)
        GameTooltip:Show()
    end)
    sourceButton:SetScript("OnLeave", function(self) if GameTooltip:IsOwned(self) then GameTooltip:Hide() end end)
    sourceButton:SetScript("OnHide", function(self) if GameTooltip:IsOwned(self) then GameTooltip:Hide() end end)
    guildThreatButton = button(content, L["Обидчики гильдии"], 179, 305, -482, function()
        guildThreatMode, guildThreatId, guildFilter = not guildThreatMode, nil, nil
        page, selection = 1, nil
        search:SetText("")
        search:ClearFocus()
        note.RefreshWindow()
    end)

    detail = CreateFrame("Frame", nil, content, "BackdropTemplate")
    detail:SetPoint("TOPLEFT", 502, -123)
    detail:SetSize(264, 402)
    guildThreatButton:SetFrameLevel(detail:GetFrameLevel() + 3)
    backdrop(detail, flat, flat, 1, 1, unpack(panelColor))
    detail:SetBackdropBorderColor(unpack(borderColor))
    detail.identity = CreateFrame("Frame", nil, detail)
    detail.identity:SetAllPoints()
    detail.portrait, detail.portraitFrame = framedIcon(detail.identity, 60, 15, -13)
    detail.level = label(detail.identity, "GameFontHighlightSmall", 160, 85, -51)
    detail.raceIcon, detail.raceFrame = framedIcon(detail.identity, 24, 16, -83)
    detail.raceName = label(detail.identity, "GameFontHighlightSmall", 198, 46, -88)
    detail.classIcon, detail.classFrame = framedIcon(detail.identity, 24, 16, -110)
    detail.className = label(detail.identity, "GameFontHighlightSmall", 198, 46, -115)
    detail.guildName = label(detail.identity, "GameFontNormalSmall", 231, 16, -138)
    detail.guildName:SetWordWrap(false)
    detail.name = label(detail, "GameFontNormal", 160, 85, -19)
    detail.name:SetMaxLines(2)
    detail.body = label(detail, "GameFontHighlight", 232, 16, -157)
    detail.body:SetSpacing(6)
    note.BuildGuildLeaders(detail)
    detail.strike = CreateFrame("Frame", nil, detail)
    detail.strike:SetPoint("TOPLEFT", 16, -272)
    detail.strike:SetSize(232, 40)
    local strikeIcon, strikeFrame = framedIcon(detail.strike, 36, 0, 0)
    detail.strike.icon = strikeIcon
    detail.strike.title = label(detail.strike, "GameFontNormalSmall", 190, 44, -5)
    strikeFrame:EnableMouse(true)
    strikeFrame:SetScript("OnEnter", function(self)
        local entry = detail.strike
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if not note.DemoData() and entry.spellId and note.SpellName(entry.spellId) and GameTooltip.SetSpellByID then
            GameTooltip:SetSpellByID(entry.spellId)
        else
            GameTooltip:SetText(entry.spellName or L["Способность неизвестна"])
        end
        note.StyleLocaleTooltip(GameTooltip)
        GameTooltip:Show()
    end)
    strikeFrame:SetScript("OnLeave", function() GameTooltip:Hide() end)
    strikeFrame:SetScript("OnHide", function(self)
        if GameTooltip:IsOwned(self) then GameTooltip:Hide() end
    end)
    detail.strike:Hide()
    detail.revenge = button(detail, L["Взять реванш"], note.OpenFightReport and 108 or 225, 16, -311, function()
        local row = selection
        if not row or not row.guid then return end
        local ok, message = note.TrackHuntRival(row.guid, note.DemoData())
        if ok then
            choose("hunt")
        else
            detail.revengeError:SetText(message or L["Выбор цели недоступен."])
            detail.revengeError:Show()
        end
    end, "primary")
    if note.OpenFightReport then
        fightReportButton = button(detail, L["Разбор боя"], 111, 131, -311, function()
            if selection and selection.entry then note.OpenFightReport(note.DemoData(), selection.entry) end
        end)
    end
    detail.guildReport = button(detail, L["Сообщить гильдии"], 225, 16, -365, function(self)
        local row = selection
        if mode ~= "rivals" or not row or not row.guid or not row.entry or row.entry.kind ~= "D"
            or note.DemoData() or not IsInGuild() then return end
        local send = C_ChatInfo and C_ChatInfo.SendChatMessage or SendChatMessage
        if not send then return end
        local name = note.Text(row.name) or "Unknown player"
        local level = note.PositiveInteger(row.entry.killerLevel, 255)
        local zone = note.Text(row.entry.zone) or "unknown zone"
        local message = ("[Forever Death Note] Blood feud! I was slain by %s (%s) in %s. The hunt is on!"):format(
            name, level and "Lv. " .. level or "level unknown", zone)
        if #message > 255 then
            local cut = 250
            while (message:byte(cut + 1) or 0) >= 128 and (message:byte(cut + 1) or 0) <= 191 do cut = cut - 1 end
            message = message:sub(1, cut) .. "..."
        end
        send(message, "GUILD")
    end)
    detail.guildReport:Hide()
    detail.revengeError = label(detail, "GameFontHighlightSmall", 230, 16, -321)
    detail.revengeError:SetTextColor(1, 0.76, 0.45)
    detail.revenge:Hide()
    detail.revengeError:Hide()
    local popupFonts = {}
    StaticPopupDialogs.FOREVER_DEATH_NOTE_FORGET = {
        text = L["Удалить из личной тетради все записи об игроке %s?"],
        button1 = L["Удалить"], button2 = L["Отмена"], timeout = 0, whileDead = true, hideOnEscape = true,
        OnShow = function(dialog)
            local styles = {}
            popupFonts[dialog] = styles
            local regions = { dialog:GetTextFontString(), dialog:GetButton1():GetFontString(), dialog:GetButton2():GetFontString() }
            for _, region in ipairs(regions) do
                local file, size, flags = note.StyleLocaleFont(region)
                if file then styles[region] = { file, size, flags } end
            end
            if next(styles) then dialog:Resize() end
        end,
        OnHide = function(dialog)
            for region, font in pairs(popupFonts[dialog] or {}) do region:SetFont(unpack(font)) end
            popupFonts[dialog] = nil
        end,
        OnAccept = function(_, guid)
            selection = nil
            note.Forget(guid)
        end,
    }
    dossierButton = button(detail, L["Досье"], 85, 157, -340, function()
        local row = selection
        local id = row and (row.guid or row.guildThreat and row.id or row.profile and row.id)
        if id and note.OpenDossier then
            local fallback = { name = row.name, class = row.class, guild = row.guild }
            for key, value in pairs(row.profile or {}) do fallback[key] = value end
            note.OpenDossier(id, note.DemoData(), fallback)
        end
    end, "dossier")
    forget = button(detail, L["Ещё"], 91, 16, -340, function(self)
        if not selection or not selection.guid then return end
        local player = selection
        local function confirm()
            StaticPopup_Show("FOREVER_DEATH_NOTE_FORGET", player.name, nil, player.guid)
        end
        if MenuUtil and MenuUtil.CreateContextMenu then
            MenuUtil.CreateContextMenu(self, function(_, root)
                note.StyleLocaleMenu(root:CreateButton(L["Удалить игрока"], confirm))
            end)
        else
            confirm()
        end
    end)
    detailAction = button(detail, "", 225, 16, -340, function()
        if mode == "guild" and guildThreatMode then
            if guildThreatId then guildThreatId = nil
            elseif selection and selection.guildThreat then guildThreatId = selection.id end
        elseif mode == "realm" then
            if victimFilter then victimFilter = nil
            elseif selection and selection.victims then victimFilter = selection.id end
        elseif guildFilter then
            guildFilter = nil
        elseif selection and selection.members then
            guildFilter = selection.id
        end
        page, selection = 1, nil
        search:SetText("")
        search:ClearFocus()
        note.RefreshWindow()
    end)
    detail.strike.title:SetText(L["Смертельный удар"])
    position(detail.strike.title, 44, -12)
    buildWarLayout(title, skullPlate)
    note.BuildRankingNavigation()
    window.territory = note.BuildEmbeddedTerritories(window)
    journalNavigation = CreateFrame("Frame", nil, window)
    journalNavigation:SetPoint("TOPLEFT", 24, -116)
    journalNavigation:SetSize(742, 27)
    journalNavigation.tabs = {}
    for index, item in ipairs({ { "journal", "История боёв" }, { "titles", "Звания" }, { "achievements", "Достижения" } }) do
        local key = item[1]
        journalNavigation.tabs[key] = button(journalNavigation, L[item[2]], 228, (index - 1) * 244, 0,
            function() choose(key) end, "bookmark")
    end
    journalNavigation:Hide()
    window.progress = note.BuildJournalProgress(window)
    buildSettings()
    huntBoard = note.BuildHuntBoard(window, {
        rivals = function() choose("rivals") end,
        journal = function() choose("journal") end,
        profile = function(id, demo) note.OpenDossier(id, demo) end,
        map = function(demo, entry) note.OpenFightMap(demo, entry) end,
        nearby = function(demo)
            note.ShowNearby(demo, function(id) note.OpenDossier(id, note.DemoData()) end)
        end,
        tracker = function(id, demo)
            local selected = note.GetTrackedHuntGoal(demo)
            local showing = note.IsHuntTrackerVisible(demo)
            if selected and selected.id == id then
                note.SetHuntTrackerVisible(not showing, demo)
            elseif note.TrackHuntGoal(id, demo) then
                note.SetHuntTrackerVisible(true, demo)
            end
            note.RefreshWindow()
        end,
    })
    window:HookScript("OnHide", function()
        theme.CloseMenu()
        note.CloseAllRecords()
    end)
    note.ManageWindow(window, "main", header)
    choose(note.db.firstJournal and "journal" or "hunt")
end

function note.OpenWindow(tab)
    if not note.db then return end
    if not window then build() end
    window:Show()
    if tab then choose(tab) else note.RefreshWindow() end
    note.db.firstJournal = nil
end

function note.OpenGuide()
    note.OpenWindow("hunt")
    if window and note.ShowOnboarding then
        ForeverDeathNoteDB.guideSeen = true
        note.ShowOnboarding(window, tabs, function(tab) choose(tab == "ranking" and "realm" or tab) end)
    end
end

function note.GuideVisible()
    return window and window.guide and window.guide:IsVisible()
end

function note.MaybeStartGuide()
    if note.db and not ForeverDeathNoteDB.guideSeen and not InCombatLockdown() then note.OpenGuide() end
end

function note.OpenDataExchange()
    note.OpenWindow("settings")
    if exchange then exchange:SelectOptions(true) end
end

function note.OpenFrontJournal(sample, zone)
    if note.DemoData() ~= sample then return end
    note.OpenWindow("journal")
    journalScope = zone
    note.RefreshWindow()
end

function note.ToggleWindow()
    if window and window:IsShown() then window:Hide() else note.OpenWindow() end
end

SLASH_FOREVER_DEATH_NOTE1 = "/deathnote"
SLASH_FOREVER_DEATH_NOTE2 = "/fdn"
SlashCmdList.FOREVER_DEATH_NOTE = function(message)
    if not note.db then return end
    local mapSyncOption = message and message:match("^%s*mapsync%s+(%w+)%s*$")
    if mapSyncOption or (message and message:match("^%s*mapsync%s*$")) then
        if mapSyncOption == "on" or mapSyncOption == "off" then note.SetMapSync(mapSyncOption == "on") end
        print("Forever Death Note · " .. L[note.MapSyncEnabled() and "PvP-карта: вкл." or "PvP-карта: выкл."]
            .. " · /fdn mapsync on | off")
        return
    end
    local command = message and message:match("^%s*(%w+)%s*$")
    if command == "help" then
        note.OpenGuide()
    elseif command == "log" or command == "journal" then
        note.OpenWindow("journal")
    elseif command == "near" then
        note.ToggleNearby(note.DemoData(), function(id) note.OpenDossier(id, note.DemoData()) end)
    elseif command == "map" then
        note.OpenFightMap(note.DemoData())
    elseif command == "sortie" and note.OpenSortie then
        note.OpenSortie(note.DemoData())
    elseif command == "recap" and note.OpenFightReport then
        note.OpenFightReport(note.DemoData())
    elseif command == "testkill" then
        note.PreviewKillNotice()
    elseif command == "hunt" then
        note.OpenWindow("hunt")
    elseif command == "lang" or command == "font" or command == "settings" then
        note.OpenWindow("settings")
    elseif command == "theme" or command == "classic" or command == "wartable" or command == "legacy" or command == "field" then
        local status = theme.Change(command == "classic" or command == "theme" and theme.Enabled(), command == "legacy", command == "field" or command == "theme" and not theme.Enabled())
        if status then print(status) end
    elseif command == "territory" then
        note.OpenTerritories()
    elseif command == "front" then
        note.OpenFront()
    elseif command == "ladder" then
        note.OpenWindow("realm")
    elseif command == "guildhunt" and note.OpenGuildHuntBoard then
        note.OpenGuildHuntBoard()
    elseif command == "rank" then
        note.OpenWindow(activeRanking)
    elseif command == "track" then
        local demo = note.DemoData()
        note.SetHuntTrackerVisible(not note.IsHuntTrackerVisible(demo), demo)
        note.RefreshWindow()
    elseif window and window:IsShown() then
        window:Hide()
    else
        note.OpenWindow(note.db.firstJournal and "journal" or "hunt")
    end
end
