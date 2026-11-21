local _, note = ...
local L = note.L
local window, selected, dataset
local week = 7 * 86400
local recentSeconds = 300
local factions = { "Horde", "Alliance" }
local colors = { Horde = {0.98, 0.52, 0.44}, Alliance = {0.52, 0.75, 1} }
local names = { Horde = "Орда", Alliance = "Альянс" }
local canvasArt = "Interface\\AddOns\\ForeverDeathNote\\Art\\WarTable.tga"
local flat = "Interface\\Buttons\\WHITE8X8"

local function writing(parent, x, y, w, h, color, layer, opacity)
    local texture = parent:CreateTexture(nil, layer or "ARTWORK")
    texture:SetPoint("TOPLEFT", x, y)
    texture:SetSize(w, h)
    texture:SetColorTexture(color[1], color[2], color[3], opacity or 1)
    return texture
end

function note.BuildFieldMap(parent, x, y, width, height, onClick)
    local map = CreateFrame(onClick and "Button" or "Frame", nil, parent, "BackdropTemplate")
    map:SetPoint("TOPLEFT", x, y)
    map:SetSize(width, height)
    map:SetBackdrop({ bgFile = flat, edgeFile = flat, edgeSize = 1 })
    map:SetBackdropColor(0.095, 0.068, 0.046, 1)
    map:SetBackdropBorderColor(0.43, 0.31, 0.18, 1)
    local inset = CreateFrame("Frame", nil, map)
    inset:SetPoint("CENTER")
    inset:SetSize(width - 4, height - 4)
    local paper = inset:CreateTexture(nil, "BACKGROUND")
    paper:SetAllPoints()
    paper:SetTexture(canvasArt)
    paper:SetTexCoord(0.25, 0.72, 0, 1)
    paper:SetVertexColor(0.35, 0.27, 0.19)
    local canvas = CreateFrame("Frame", nil, inset)
    canvas:SetPoint("CENTER")
    canvas.host, canvas.tiles = inset, {}
    local pin = canvas:CreateTexture(nil, "OVERLAY")
    pin:SetSize(20, 20)
    map.canvas, map.pin = canvas, pin
    if onClick then
        map:SetHighlightTexture("Interface\\Buttons\\UI-Listbox-Highlight2")
        map:SetScript("OnClick", function(self) if self.entry then onClick(self.entry) end end)
        map:SetScript("OnEnter", function(self)
            if not self.entry then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(L["Карта"])
            note.StyleLocaleTooltip(GameTooltip)
            GameTooltip:Show()
        end)
        map:SetScript("OnLeave", function(self) if GameTooltip:IsOwned(self) then GameTooltip:Hide() end end)
        map:SetScript("OnHide", function(self) if GameTooltip:IsOwned(self) then GameTooltip:Hide() end end)
    end
    return map
end

function note.UpdateFieldMap(map, entry, id)
    map.entry = entry
    local canvas = map.canvas
    local hasMap = note.DrawMapTiles(canvas, id or (entry and note.EncounterMapID(entry)))
    canvas:SetShown(hasMap == true)
    local x, y = entry and entry.x, entry and entry.y
    local hasPin = hasMap and type(x) == "number" and type(y) == "number"
        and x >= 0 and y >= 0 and x <= 100 and y <= 100
    map.pin:SetShown(hasPin and true or false)
    if hasPin then
        map.pin:ClearAllPoints()
        map.pin:SetPoint("CENTER", canvas, "TOPLEFT", canvas:GetWidth() * x / 100, -canvas:GetHeight() * y / 100)
        map.pin:SetTexture(entry.kind == "D" and "Interface\\TargetingFrame\\UI-RaidTargetingIcon_8"
            or "Interface\\Icons\\Ability_DualWield")
    end
end

local function frontTime(sample, now)
    -- Keep the sample week available even after the real week rolls over.
    local last = sample and sample.events[#sample.events]
    return last and last.at or now or GetServerTime()
end

local function collectFront(sample, now, start, zoneKey, shared)
    local source = sample or note.db
    local zones, byZone, maps = {}, {}, {}
    for _, entry in ipairs(source.events) do
        if entry.zone and entry.mapId then maps[entry.zone] = entry.mapId end
    end
    local total = { Horde = 0, Alliance = 0, count = 0, unknown = 0, unplaced = 0, shared = 0,
        start = start, ends = start + week }
    local function add(entry, side, personal, guild, killer, name)
        if entry.at < start or entry.at > now then return end
        if side then total[side] = total[side] + 1
        else total.unknown = total.unknown + 1 end
        total.count = total.count + 1
        if not personal then total.shared = total.shared + 1 end
        local key = zoneKey and zoneKey(entry) or entry.mapId or maps[entry.zone] or entry.zone
        if not key then total.unplaced = total.unplaced + 1; return end
        if not total.firstAt or entry.at < total.firstAt then total.firstAt = entry.at end
        local zone = byZone[key]
        if not zone then
            zone = { key = key, name = entry.zone, count = 0, Horde = 0, Alliance = 0,
                entries = {}, shared = 0, guilds = { Horde = {}, Alliance = {} }, killers = {} }
            zones[#zones + 1], byZone[key] = zone, zone
        end
        zone.count = zone.count + 1
        if side then zone[side] = zone[side] + 1 end
        if side and guild then
            local id = (strlower or string.lower)(guild)
            local groups = zone.guilds[side]
            local group = groups[id] or { id = id, name = guild, kills = 0, faction = side }
            groups[id] = group
            group.kills = group.kills + 1
            if guild < group.name then group.name = guild end
        end
        if killer then
            local player = zone.killers[killer] or { id = killer, kills = 0 }
            zone.killers[killer] = player
            player.kills = player.kills + 1
            if name and (not player.nameAt or entry.at >= player.nameAt) then
                player.name, player.nameAt = name, entry.at
            end
        end
        if not zone.latest or entry.at >= zone.latest.at then zone.latest = entry end
        if personal then
            zone.entries[personal] = true
            if personal.x and personal.y and (not zone.pin or personal.at >= zone.pin.at) then zone.pin = personal end
        else zone.shared = zone.shared + 1 end
    end
    if shared then
        note.ForEachTerritoryFight(sample, start, now, add)
    else
        for _, entry in ipairs(source.events) do
            if entry.kind == "K" or entry.kind == "D" then
                local fight = note.PersonalTerritoryReport(entry, sample)
                if fight then
                    add(entry, fight.victimFaction and fight.killerFaction, entry,
                        fight.killerGuild, fight.killer)
                end
            end
        end
    end
    for _, zone in ipairs(zones) do
        local bestKill, tiedKill = 0, false
        for _, player in pairs(zone.killers) do
            if player.kills > bestKill then
                bestKill, zone.topKiller, tiedKill = player.kills, player, false
            elseif player.kills == bestKill then
                tiedKill = true
            end
        end
        zone.topKills, zone.topKillerTie = bestKill, tiedKill
        if tiedKill then zone.topKiller = nil end
        zone.killers = nil
        if zone.Horde ~= zone.Alliance then
            zone.leadingFaction = zone.Horde > zone.Alliance and "Horde" or "Alliance"
            local best, tied = 0, false
            for _, group in pairs(zone.guilds[zone.leadingFaction]) do
                if group.kills > best then
                    best, zone.owner, tied = group.kills, group, false
                elseif group.kills == best then
                    tied = true
                end
            end
            zone.ownerKills, zone.ownerTie = best, tied
            if tied then zone.owner = nil end
        else
            zone.ownerTie = zone.Horde > 0
        end
        zone.guilds = nil
    end
    local missing, resolved = {}, {}
    for _, zone in ipairs(zones) do
        local player = zone.topKiller
        if player then
            player.name = note.Text(player.name) or note.Text((source.profiles[player.id] or {}).name)
            if not player.name then missing[player.id] = true end
        end
    end
    if next(missing) then
        local function remember(id, name, at)
            name = missing[id] and note.Text(name)
            if name and (not resolved[id] or at > resolved[id].at) then resolved[id] = { name = name, at = at } end
        end
        for _, event in pairs(sample and sample.reports or not sample and note.realmEvents or {}) do
            remember(event.killer, event.killerName, event.at)
            remember(event.victim, event.victimName, event.at)
        end
        for _, zone in ipairs(zones) do
            local player = zone.topKiller
            if player and not player.name then
                local cached = resolved[player.id]
                player.name = cached and cached.name
                if not player.name and GetPlayerInfoByGUID then
                    local ok, _, _, _, _, _, name = pcall(GetPlayerInfoByGUID, player.id)
                    if ok then player.name = note.Text(name) end
                end
            end
        end
    end
    return total, zones
end

function note.FrontWeek(sample, now, zoneKey, shared)
    now = frontTime(sample, now)
    local total, zones = collectFront(sample, now, note.WeekStart(now), zoneKey, shared)
    table.sort(zones, function(a, b)
        if a.count ~= b.count then return a.count > b.count end
        if a.latest.at ~= b.latest.at then return a.latest.at > b.latest.at end
        return tostring(a.key) < tostring(b.key)
    end)
    return total, zones
end

local function label(parent, font, x, y, width)
    local text = note.CreateFontString(parent, nil, "OVERLAY", font)
    text:SetPoint("TOPLEFT", x, y)
    text:SetWidth(width)
    text:SetJustifyH("LEFT")
    return text
end

local function button(parent, text, x, y, width, action)
    local control = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    control:SetPoint("TOPLEFT", x, y)
    control:SetSize(width, 26)
    note.StyleLocaleButton(control)
    if note.StyleWarcraftButton then note.StyleWarcraftButton(control) end
    control:SetText(text)
    control:SetScript("OnClick", action)
    return control
end

local function zoneCaption(zone)
    local info = type(zone.key) == "number" and C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(zone.key)
    return note.SampleText(zone.name, dataset) or (info and info.name) or L["Зона неизвестна"]
end

local function recentLabel(age)
    if age < 60 then return L["%d сек назад"]:format(age) end
    return L["%d мин назад"]:format(math.floor(age / 60))
end

local function lastZone(now)
    if not window.recent then return #window.zones end
    for index, zone in ipairs(window.zones) do
        if now - zone.latest.at >= recentSeconds then return index - 1 end
    end
    return #window.zones
end

local function refreshDispatchList(now)
    local recent = window.recent
    local count = lastZone(now)
    local size = #window.rows
    local pages = math.max(1, math.ceil(count / size))
    if selected then
        for index = 1, count do
            if window.zones[index].key == selected then window.page = math.ceil(index / size); break end
        end
    end
    window.page = math.max(1, math.min(window.page, pages))
    local offset = (window.page - 1) * size
    local visible, selection = {}, nil
    for index = offset + 1, math.min(count, offset + size) do
        local zone = window.zones[index]
        visible[index - offset] = zone
        if zone.key == selected then selection = zone end
    end
    selection = selection or visible[1]
    selected = selection and selection.key
    for index, row in ipairs(window.rows) do
        local zone = visible[index]
        if zone and row.zone ~= zone then row.name:SetText(zoneCaption(zone)) end
        row.zone = zone
        row:SetShown(zone ~= nil)
        if zone then
            row.age:SetShown(recent)
            if recent then row.age:SetText(recentLabel(math.max(0, now - zone.latest.at))) end
            for _, faction in ipairs(factions) do
                row[faction]:SetShown(not recent)
                if not recent then row[faction]:SetText(tostring(zone[faction])) end
            end
            row.tint:SetShown(zone == selection)
        end
    end
    window.empty:SetShown(#visible == 0)
    window.openAll:SetShown(count > 0)
    window.previous:SetShown(pages > 1)
    window.next:SetShown(pages > 1)
    window.previous:SetEnabled(window.page > 1)
    window.next:SetEnabled(window.page < pages)
    if #visible == 0 then
        window.empty:SetText(L[recent and "За последние 5 минут нет боёв с известной зоной."
            or "За эту неделю пока нет боёв с известной зоной."])
    end
    window.detail:SetShown(selection ~= nil)
    if window.zone == selection then return end
    window.zone = selection
    if not selection then return end
    window.place:SetText(zoneCaption(selection))
    local leader = selection.Horde > selection.Alliance and "Лидирует Орда"
        or selection.Alliance > selection.Horde and "Лидирует Альянс"
        or selection.Horde > 0 and "Ничья"
    window.leader:SetText(leader and L[leader] or "")
    window.latestAt:SetText(L["Последний бой"] .. "  /  " .. date("%d.%m %H:%M", selection.latest.at))
    window.map:SetEnabled(selection.pin ~= nil)
    window.log:SetEnabled(next(selection.entries) ~= nil)
    note.UpdateFieldMap(window.preview, selection.pin, type(selection.key) == "number" and selection.key)
end

local function openAll(frame)
    if not note.OpenAllRecords then return end
    local now, rows, selectedIndex = frontTime(dataset), {}, nil
    for index = 1, lastZone(now) do
        local zone = frame.zones[index]
        rows[index] = zone
        if zone.key == selected then selectedIndex = index end
    end
    local recent = frame.recent
    note.OpenAllRecords({
        title = L[recent and "Последние 5 минут" or "Фронт недели"],
        subtitle = frame.source:GetText(),
        rows = rows,
        startIndex = (frame.page - 1) * #frame.rows + 1,
        selectedIndex = selectedIndex,
        columns = {
            { label = L["Зона"], weight = 3.6 },
            { label = L["Орда"], weight = 1.1, justify = "RIGHT" },
            { label = L["Альянс"], weight = 1.1, justify = "RIGHT" },
            { label = L["Последний бой"], weight = 1.7, justify = "RIGHT" },
        },
        cells = function(zone)
            local latest = recent and recentLabel(math.max(0, now - zone.latest.at))
                or date("%d.%m %H:%M", zone.latest.at)
            return { zoneCaption(zone), { text = zone.Horde, color = colors.Horde },
                { text = zone.Alliance, color = colors.Alliance }, latest }
        end,
        onSelect = function(zone)
            local current = frontTime(dataset)
            for index = 1, lastZone(current) do
                if frame.zones[index].key == zone.key then
                    frame.page, selected = math.ceil(index / #frame.rows), zone.key
                    refreshDispatchList(current)
                    return
                end
            end
        end,
    })
end

local function refreshDispatch()
    local now = frontTime(dataset)
    local total, zones = note.FrontWeek(dataset, now, nil, window.shared)
    if window.recent then
        local recentTotal, recentZones = collectFront(dataset, now, now - recentSeconds + 1, nil, window.shared)
        window.recentExpires = recentTotal.firstAt and recentTotal.firstAt + recentSeconds
        zones = recentZones
        table.sort(zones, function(a, b)
            if a.latest.at ~= b.latest.at then return a.latest.at > b.latest.at end
            if a.count ~= b.count then return a.count > b.count end
            return tostring(a.key) < tostring(b.key)
        end)
    end
    window.zones, window.weekEnds = zones, total.ends
    local known = total.Horde + total.Alliance
    local source = window.shared and L["Общий счёт"] or L["Личный журнал"]
    window.mine:SetEnabled(window.shared)
    window.sharedButton:SetEnabled(not window.shared)
    window.source:SetText((dataset and L["ТЕСТ • "] or "") .. source .. "  /  "
        .. date("!%d.%m", total.start) .. " – " .. date("!%d.%m", total.ends - 1) .. " UTC")
    window.coverage:SetText(L["Фронт: %d записей / без фракции: %d / без зоны: %d"]:format(total.count, total.unknown, total.unplaced))
    for _, faction in ipairs(factions) do window[faction]:SetText(tostring(total[faction])) end
    window.score:SetShown(known > 0)
    if known > 0 then
        local redWidth = window.score:GetWidth() * total.Horde / known
        window.score.Horde:SetShown(total.Horde > 0)
        window.score.Alliance:SetShown(total.Alliance > 0)
        window.score.Horde:SetWidth(math.max(1, redWidth))
        window.score.Alliance:SetWidth(math.max(1, window.score:GetWidth() - redWidth))
    end
    local percent = known > 0 and math.floor(total.Horde * 100 / known + 0.5)
    window.balance:SetText(percent and ("%d%%   /   %d%%"):format(percent, 100 - percent) or "")
    window.hotButton:SetEnabled(window.recent == true)
    window.recentButton:SetEnabled(not window.recent)
    if note.TintWarcraftButton then
        note.TintWarcraftButton(window.mine, not window.shared)
        note.TintWarcraftButton(window.sharedButton, window.shared)
        note.TintWarcraftButton(window.hotButton, not window.recent)
        note.TintWarcraftButton(window.recentButton, window.recent)
    end
    window.hotHeadings:SetShown(not window.recent)
    window.recentHeading:SetShown(window.recent == true)
    refreshDispatchList(now)
end

function note.RefreshFront()
    if not window or not window:IsVisible() then return end
    local sample = note.DemoData()
    if dataset ~= sample then dataset, selected, window.page = sample, nil, 1 end
    refreshDispatch()
end

local function section(parent, x, y, width, height, raised)
    local frame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    frame:SetPoint("TOPLEFT", x, y)
    frame:SetSize(width, height)
    frame:SetBackdrop({ bgFile = flat, edgeFile = flat, edgeSize = 1 })
    frame:SetBackdropColor(raised and 0.14 or 0.105, raised and 0.099 or 0.077, raised and 0.067 or 0.057, 1)
    frame:SetBackdropBorderColor(0.40, 0.29, 0.174, 1)
    return frame
end

function note.BuildEmbeddedFront(parent)
    if window then return window end
    local frame = CreateFrame("Frame", "ForeverDeathNoteFront", parent)
    frame:SetAllPoints(parent)
    frame:Hide()
    window = frame
    frame.shared, frame.recent, frame.page = note.db.territoryMode == "shared", false, 1
    frame.source = label(frame, "GameFontHighlight", 8, -12, 422)
    frame.mine = button(frame, L["Мои бои"], 458, -3, 128, function()
        frame.shared, selected, frame.page = false, nil, 1
        note.RefreshFront()
    end)
    frame.sharedButton = button(frame, L["Общий счёт"], 596, -3, 146, function()
        frame.shared, selected, frame.page = true, nil, 1
        note.RefreshFront()
    end)
    local banner = section(frame, 0, -34, 742, 61, true)
    for i, faction in ipairs(factions) do
        local left = i == 1
        local crest = banner:CreateTexture(nil, "ARTWORK")
        crest:SetPoint(left and "TOPLEFT" or "TOPRIGHT", left and 15 or -15, -4)
        crest:SetSize(28, 28)
        note.SetFactionEmblem(crest, faction)
        local caption = label(banner, "GameFontNormalSmall", left and 48 or 569, -9, 125)
        caption:SetJustifyH(left and "LEFT" or "RIGHT")
        caption:SetText(L[names[faction]])
        frame[faction] = label(banner, "GameFontNormalLarge", left and 139 or 478, -7, 125)
        note.StyleNumberFont(frame[faction])
        frame[faction]:SetJustifyH(left and "LEFT" or "RIGHT")
        frame[faction]:SetTextColor(unpack(colors[faction]))
    end
    writing(banner, 15, -33, 712, 6, { 0.37, 0.29, 0.21 }, "ARTWORK", 0.92)
    frame.score = CreateFrame("Frame", nil, banner)
    frame.score:SetPoint("TOPLEFT", 15, -33)
    frame.score:SetSize(712, 6)
    frame.score.Horde = writing(frame.score, 0, 0, 1, 6, colors.Horde)
    frame.score.Alliance = writing(frame.score, 0, 0, 1, 6, colors.Alliance)
    frame.score.Alliance:ClearAllPoints()
    frame.score.Alliance:SetPoint("TOPRIGHT")
    frame.balance = label(banner, "GameFontHighlight", 235, -10, 272)
    frame.balance:SetJustifyH("CENTER")
    frame.coverage = label(banner, "GameFontHighlightSmall", 15, -45, 712)

    local list = section(frame, 0, -103, 332, 225)
    local function chooseRecent(showRecent)
        frame.recent, frame.page = showRecent, 1
        note.RefreshFront()
    end
    frame.hotButton = button(list, L["Горячие зоны"], 9, -8, 150, function() chooseRecent(false) end)
    frame.recentButton = button(list, L["Последние 5 минут"], 171, -8, 152, function() chooseRecent(true) end)
    frame.hotHeadings = CreateFrame("Frame", nil, list)
    frame.hotHeadings:SetAllPoints()
    local left = label(frame.hotHeadings, "GameFontNormalSmall", 202, -41, 44)
    left:SetJustifyH("RIGHT")
    left:SetText("|TInterface\\TargetingFrame\\UI-PVP-Horde:13:13|t")
    local right = label(frame.hotHeadings, "GameFontNormalSmall", 263, -41, 44)
    right:SetJustifyH("RIGHT")
    right:SetText("|TInterface\\TargetingFrame\\UI-PVP-Alliance:13:13|t")
    frame.recentHeading = label(list, "GameFontNormalSmall", 172, -41, 142)
    frame.recentHeading:SetJustifyH("RIGHT")
    frame.recentHeading:SetText(L["Последний бой"])
    frame.empty = label(list, "GameFontHighlight", 13, -68, 304)
    frame.empty:SetWordWrap(true)
    frame.rows = {}
    for i = 1, 4 do
        local row = CreateFrame("Button", nil, list)
        row:SetPoint("TOPLEFT", 9, -57 - (i - 1) * 33)
        row:SetSize(314, 31)
        writing(row, 0, 0, 314, 31, { 0.22, 0.16, 0.11 }, "BACKGROUND", i % 2 == 0 and 0.74 or 0.44)
        writing(row, 1, -30, 312, 1, { 0.36, 0.27, 0.17 }, "ARTWORK", 0.65)
        row.tint = writing(row, 0, 0, 314, 31, { 0.45, 0.31, 0.17 }, "BORDER", 0.54)
        row:SetHighlightTexture("Interface\\Buttons\\UI-Listbox-Highlight2")
        row.name = label(row, "GameFontHighlight", 6, -9, 179)
        row.name:SetWordWrap(false)
        row.age = label(row, "GameFontHighlightSmall", 185, -9, 121)
        row.age:SetJustifyH("RIGHT")
        row.age:SetTextColor(0.84, 0.76, 0.64)
        for j, faction in ipairs(factions) do
            local value = label(row, "GameFontHighlight", 193 + (j - 1) * 61, -9, 44)
            value:SetJustifyH("RIGHT")
            value:SetTextColor(unpack(colors[faction]))
            row[faction] = value
        end
        row:SetScript("OnClick", function(self)
            if self.zone then
                selected = self.zone.key
                refreshDispatchList(frontTime(dataset))
            end
        end)
        frame.rows[i] = row
    end
    local function pageBy(delta)
        frame.page, selected = frame.page + delta, nil
        refreshDispatchList(frontTime(dataset))
    end
    frame.previous = button(list, "<", 9, -193, 28, function() pageBy(-1) end)
    frame.next = button(list, ">", 295, -193, 28, function() pageBy(1) end)
    if note.StylePageButton then
        note.StylePageButton(frame.previous, "prev")
        note.StylePageButton(frame.next, "next")
    end
    frame.openAll = button(list, L["Открыть все"], 77, -193, 178, function() openAll(frame) end)

    local detail = section(frame, 342, -103, 400, 225)
    frame.detail = detail
    frame.place = label(detail, "GameFontNormalLarge", 12, -11, 375)
    frame.place:SetWordWrap(false)
    frame.leader = label(detail, "GameFontNormalSmall", 13, -33, 374)
    frame.preview = note.BuildFieldMap(detail, 12, -52, 376, 106)
    frame.latestAt = label(detail, "GameFontHighlightSmall", 13, -168, 374)
    frame.log = button(detail, L["Журнал зоны"], 12, -186, 180, function()
        if frame.zone and next(frame.zone.entries) then
            note.OpenFrontJournal(dataset, frame.zone)
        end
    end)
    frame.map = button(detail, L["Карта зоны"], 208, -186, 180, function()
        if frame.zone and frame.zone.pin then
            note.OpenFightMap(dataset, frame.zone.pin, frame.zone)
        end
    end)
    local elapsed = 0
    frame:SetScript("OnUpdate", function(self, since)
        if not self.recent or dataset then return end
        elapsed = elapsed + since
        if elapsed >= 1 then
            elapsed = 0
            local now = GetServerTime()
            if now >= self.weekEnds or (self.recentExpires and now >= self.recentExpires) then
                refreshDispatch()
            else
                refreshDispatchList(now)
            end
        end
    end)
    frame:SetScript("OnShow", note.RefreshFront)
    return frame
end

function note.OpenFront()
    if note.db and note.OpenWindow then note.OpenWindow("front") end
end
