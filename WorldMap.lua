local _, note = ...
local L = note.L

local window, demo, previewZone, selected, selectedGroup, selectedIndex
local liveFilters, demoFilters = {}, {}
local liveOwner, demoSource
local mapNames, frontScope
local periods = {
    { label = "Все даты" },
    { label = "24 часа", value = 86400 },
    { label = "7 дней", value = 7 * 86400 },
    { label = "30 дней", value = 30 * 86400 },
}
local classicZones = {
    ["Stranglethorn Vale"] = 1434, ["Тернистая долина"] = 1434,
    ["Tanaris"] = 1446, ["Танарис"] = 1446,
    ["Feralas"] = 1444, ["Фералас"] = 1444,
    ["Blasted Lands"] = 1419, ["Выжженные земли"] = 1419,
    ["Winterspring"] = 1452, ["Зимние Ключи"] = 1452,
    ["Thousand Needles"] = 1441, ["Тысяча Игл"] = 1441,
    ["Elwynn Forest"] = 1429, ["Элвиннский лес"] = 1429,
}
local icons = {
    K = "Interface\\Icons\\Ability_DualWield",
    D = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_8",
}
local unknownZone, unknownClass, unknownSpell = "Зона неизвестна", "Класс неизвестен", "Без данных о способности"

local function filtersFor(sample)
    if sample then
        if demoSource ~= sample then demoSource, demoFilters = sample, {} end
        return demoFilters
    end
    if liveOwner ~= note.owner then liveOwner, liveFilters = note.owner, {} end
    return liveFilters
end

local function otherClass(entry, profile)
    return (entry.kind == "D" and entry.killerClass) or profile.class or unknownClass
end

local function className(token)
    if token == unknownClass then return L[unknownClass] end
    return note.ClassLabel(token)
end

local function zoneName(value, sample)
    if value == unknownZone then return L[unknownZone] end
    return note.SampleText(value, sample)
end

local function spellName(entry, sample)
    local strike = note.KillingBlow(entry, sample)
    return note.SpellName(strike.spellId, strike.spellName, sample) or unknownSpell
end

local function matches(entry, profile, filters, now, sample)
    return (not filters.period or entry.at >= now - filters.period)
        and (not filters.zone or (entry.zone or unknownZone) == filters.zone)
        and (not filters.class or otherClass(entry, profile) == filters.class)
        and (not filters.spell or spellName(entry, sample) == filters.spell)
end

function note.JournalMatches(entry, profile, sample)
    local filters = filtersFor(sample)
    return matches(entry, profile or {}, filters, filters.period and GetServerTime() or 0, sample)
end

function note.MapFiltersActive(sample)
    return next(filtersFor(sample)) ~= nil
end

local function mapCatalog()
    if mapNames then return mapNames end
    local result = {}
    if not C_Map or not C_Map.GetMapChildrenInfo then return result end
    local zoneType = Enum and Enum.UIMapType and Enum.UIMapType.Zone
    for _, parent in ipairs({947, 1414, 1415}) do
        local descendants = C_Map.GetMapChildrenInfo(parent, zoneType, true)
        for _, info in ipairs(descendants or {}) do
            if info.name and info.mapID then
                local previous = result[info.name]
                if previous == nil then
                    result[info.name] = info.mapID
                elseif previous ~= info.mapID then
                    result[info.name] = false
                end
            end
        end
    end
    mapNames = result
    return result
end

local function validPosition(entry)
    return type(entry.x) == "number" and entry.x >= 0 and entry.x <= 100
        and type(entry.y) == "number" and entry.y >= 0 and entry.y <= 100
end

local function explicitMaps(events)
    local zones = {}
    for _, entry in ipairs(events) do
        if entry.zone and entry.mapId then
            if zones[entry.zone] == nil then zones[entry.zone] = entry.mapId
            elseif zones[entry.zone] ~= entry.mapId then zones[entry.zone] = false end
        end
    end
    return zones
end

function note.EncounterMapID(entry, known)
    if entry.mapId then return entry.mapId end
    if not entry.zone then return nil end
    local fromCatalog = mapCatalog()[entry.zone]
    if fromCatalog == false then return nil end
    local canonical = fromCatalog or classicZones[entry.zone]
    if canonical and (not known or known[entry.zone] == nil or known[entry.zone] == canonical) then return canonical end
end

local function mapID(entry, known)
    if validPosition(entry) then return note.EncounterMapID(entry, known) end
end

local function groupPins(events, id, known)
    local bins, groups = {}, {}
    for _, entry in ipairs(events) do
        if mapID(entry, known) == id then
            local key = math.floor(entry.x / 4) .. "/" .. math.floor(entry.y / 4)
            local group = bins[key]
            if not group then
                group = { entries = {}, kills = 0, deaths = 0, x = entry.x, y = entry.y }
                groups[#groups + 1], bins[key] = group, group
            end
            group.entries[#group.entries + 1] = entry
            if entry.kind == "K" then group.kills = group.kills + 1
            elseif entry.kind == "D" then group.deaths = group.deaths + 1 end
        end
    end
    return groups
end

local function label(parent, font, x, y, width, text)
    local element = note.CreateFontString(parent, nil, "OVERLAY", font)
    element:SetPoint("TOPLEFT", x, y)
    element:SetWidth(width)
    element:SetJustifyH("LEFT")
    element:SetText(text or "")
    return element
end

local function button(parent, title, x, y, width, onClick)
    local element = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    note.StyleLocaleButton(element)
    element:SetPoint("TOPLEFT", x, y)
    element:SetSize(width, 24)
    element:SetText(title)
    element:SetScript("OnClick", onClick)
    return element
end

local function filterChanged()
    note.RefreshFightMap()
    if note.RefreshWindow then note.RefreshWindow() end
end

local function filterButton(parent, title, field, choices, x, width)
    return button(parent, title, x, -70, width, function(self)
        if not MenuUtil or not MenuUtil.CreateContextMenu then return end
        MenuUtil.CreateContextMenu(self, function(_, root)
            local filters = frontScope and frontScope.filters or filtersFor(demo)
            note.StyleLocaleMenu(root:CreateTitle(title))
            root:SetScrollMode(295)
            for _, option in ipairs(choices()) do
                note.StyleLocaleMenu(root:CreateRadio(option.label, function(item)
                    return filters[item.field] == item.value
                end, function(item)
                    if frontScope and not frontScope.rival then previewZone, frontScope = nil, nil end
                    filters[item.field] = item.value
                    if item.field == "zone" then previewZone = nil end
                    selected = nil
                    filterChanged()
                end, {field = field, value = option.value}))
            end
        end)
    end)
end

local function dataset()
    return demo or note.db
end

local function choicesFor(field, emptyLabel)
    local data, seen = dataset(), {}
    if not data then return {{label = emptyLabel}} end
    local options = {}
    for _, entry in ipairs(data.events) do
        if not frontScope or not frontScope.rival or frontScope.entries[entry] then
            local profile = data.profiles[entry.other] or {}
            local value
            if field == "zone" then value = entry.zone or unknownZone
            elseif field == "class" then value = otherClass(entry, profile)
            else value = spellName(entry, demo) end
            if not seen[value] then
                seen[value] = true
                local name = value
                if field == "class" then name = className(value)
                elseif field == "zone" then name = zoneName(value, demo)
                elseif value == unknownSpell then name = L[unknownSpell] end
                options[#options + 1] = {label = name, value = value}
            end
        end
    end
    table.sort(options, function(a, b) return a.label < b.label end)
    table.insert(options, 1, {label = emptyLabel})
    return options
end

function note.DrawMapTiles(canvas, id)
    local art = id and C_Map and C_Map.GetMapArtID and C_Map.GetMapArtID(id)
    if canvas.mapID == id and canvas.artID == art and canvas.ready then return true end
    for _, tile in ipairs(canvas.tiles) do tile:Hide() end
    canvas.mapID, canvas.artID, canvas.ready = id, art, nil
    if not id or not C_Map or not C_Map.GetMapArtLayers or not C_Map.GetMapArtLayerTextures then return false end
    local layers = C_Map.GetMapArtLayers(id)
    local layer = layers and layers[1]
    if not layer or not layer.layerWidth or not layer.layerHeight or not layer.tileWidth or not layer.tileHeight then
        return false
    end
    local width, height = layer.layerWidth, layer.layerHeight
    local tw, th = layer.tileWidth, layer.tileHeight
    if width <= 0 or height <= 0 or tw <= 0 or th <= 0 then return false end
    local columns, rows = math.ceil(width / tw), math.ceil(height / th)
    local files = C_Map.GetMapArtLayerTextures(id, 1)
    if not files or #files < columns * rows then return false end
    local factor = math.min(canvas.host:GetWidth() / width, canvas.host:GetHeight() / height)
    canvas:SetSize(width * factor, height * factor)
    for row = 0, rows - 1 do
        for column = 0, columns - 1 do
            local index = row * columns + column + 1
            local tile = canvas.tiles[index] or canvas:CreateTexture(nil, "BACKGROUND")
            canvas.tiles[index] = tile
            local x, y = column * tw, row * th
            local tileWidth, tileHeight = math.min(tw, width - x), math.min(th, height - y)
            tile:ClearAllPoints()
            tile:SetPoint("TOPLEFT", canvas, "TOPLEFT", x * factor, -y * factor)
            tile:SetSize(tileWidth * factor, tileHeight * factor)
            tile:SetTexture(files[index], nil, nil, "TRILINEAR")
            tile:SetTexCoord(0, tileWidth / tw, 0, tileHeight / th)
            tile:Show()
        end
    end
    canvas.ready = true
    return true
end

local function entryName(entry)
    local profile = (dataset().profiles or {})[entry.other] or {}
    return profile.name or L["Имя неизвестно"], profile
end

local function updateDetail()
    local panel = window.detail
    local canCycle = selectedGroup and #selectedGroup.entries > 1
    panel.next:SetShown(canCycle and true or false)
    panel.previous:SetShown(canCycle and true or false)
    panel.identity:SetShown(selected ~= nil)
    panel.body:ClearAllPoints()
    panel.body:SetPoint("TOPLEFT", 12, selected and -130 or -42)
    if not selected then
        panel.title:SetText(L["Сведения о бое"])
        panel.body:SetText(L["Выберите метку на карте."])
        panel.position:SetText("")
        return
    end
    local entry, name, profile = selected, entryName(selected)
    panel.title:SetText(entry.kind == "D" and L["Ваша смерть"] or L["Ваше добивание"])
    local location = zoneName(entry.zone or unknownZone, demo)
    if entry.subzone and entry.subzone ~= entry.zone then location = location .. "\n" .. note.SampleText(entry.subzone, demo) end
    if validPosition(entry) then location = location .. ("\n%.1f, %.1f"):format(entry.x, entry.y) end
    local token = entry.kind == "D" and entry.killerClass or profile.class
    note.SetCharacterArt(panel.portrait, panel.raceIcon, panel.classIcon, not demo and entry.other, profile, token)
    panel.name:SetText(name)
    panel.race:SetText(note.RaceLabel(profile, demo) or L["Раса неизвестна"])
    panel.class:SetText(note.ClassLabel(token, profile.sex) or L["Класс неизвестен"])
    panel.body:SetText(date("%d.%m.%Y %H:%M", entry.at) .. "\n" .. location)
    local strike = note.KillingBlow(entry, demo)
    local spell = note.SpellName(strike.spellId, strike.spellName, demo)
    panel.spellName:SetText(spell or (strike.spellId and L["Способность #"] .. strike.spellId) or L["Способность неизвестна"])
    panel.spellIcon:SetTexture(note.KillingBlowTexture(strike.spellId, spell))
    panel.position:SetText(canCycle and ("%d / %d"):format(selectedIndex, #selectedGroup.entries) or "")
end

local function showSelection(group, index)
    selectedGroup, selectedIndex = group, index
    selected = group.entries[index]
    updateDetail()
end

local function pinFor(index)
    local canvas = window.canvas
    local pin = canvas.pins[index]
    if pin then return pin end
    pin = CreateFrame("Button", nil, canvas)
    pin:SetSize(23, 23)
    pin.icon = pin:CreateTexture(nil, "ARTWORK")
    pin.second = pin:CreateTexture(nil, "OVERLAY")
    pin.second:SetSize(20, 20)
    pin.second:SetPoint("LEFT", 16, 0)
    pin.second:SetTexture(icons.K)
    pin:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    pin.count = note.CreateFontString(pin, nil, "OVERLAY", "GameFontNormalSmall")
    pin.count:SetPoint("BOTTOMRIGHT", 5, -2)
    pin:SetScript("OnClick", function(self)
        local group = self.group
        local indexToShow = selectedGroup == group and selectedIndex % #group.entries + 1 or 1
        showSelection(group, indexToShow)
    end)
    pin:SetScript("OnEnter", function(self)
        local group = self.group
        local name = entryName(group.entries[1])
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(name)
        GameTooltip:AddLine((L["Добивания: %d   Смерти: %d"]):format(group.kills, group.deaths), 1, 1, 1)
        GameTooltip:AddLine(L["Нажмите, чтобы посмотреть события."], 0.92, 0.75, 0.37)
        note.StyleLocaleTooltip(GameTooltip)
        GameTooltip:Show()
    end)
    pin:SetScript("OnLeave", function() GameTooltip:Hide() end)
    canvas.pins[index] = pin
    return pin
end

local function refresh()
    local data, filters = dataset(), frontScope and (frontScope.filters or {}) or filtersFor(demo)
    if not data then return end
    local now, events, id, zone = GetServerTime(), {}, nil, nil
    local known = explicitMaps(data.events)
    local showZone = previewZone or filters.zone
    local withoutLocation = 0
    for index = #data.events, 1, -1 do
        local entry = data.events[index]
        if (not frontScope or frontScope.entries[entry]) and matches(entry, data.profiles[entry.other] or {}, filters, now, demo) then
            events[#events + 1] = entry
            local mapped = mapID(entry, known)
            if not mapped then withoutLocation = withoutLocation + 1 end
            if mapped and (entry == selected or (not id and (not showZone or (entry.zone or unknownZone) == showZone))) then
                id, zone = mapped, entry.zone
            end
        end
    end
    if not id and showZone and not filters.zone then
        previewZone = nil
        for _, entry in ipairs(events) do
            local mapped = mapID(entry, known)
            if mapped then id, zone = mapped, entry.zone; break end
        end
    end
    local options = { zoneName(filters.zone, demo) or L["Все зоны"], L["Все даты"],
        className(filters.class) or L["Все классы"],
        filters.spell == unknownSpell and L[unknownSpell] or filters.spell or L["Все способности"] }
    for _, period in ipairs(periods) do
        if period.value == filters.period then options[2] = L[period.label]; break end
    end
    for index, control in ipairs(window.filterButtons) do control:SetText(options[index]) end
    local context = frontScope and (frontScope.rival and (L["Досье • "] .. frontScope.rival) or L["Фронт недели"])
        or L["Места записанных боёв • Фильтры действуют и в журнале"]
    window.subtitle:SetText((demo and L["ТЕСТ • "] or "") .. context)
    window.clearRival:SetShown(frontScope and frontScope.rival ~= nil or false)
    local hasArt = note.DrawMapTiles(window.canvas, id)
    local groups = hasArt and groupPins(events, id, known) or {}
    local count = 0
    local old = selected
    selected, selectedGroup, selectedIndex = nil, nil, nil
    local canvas = window.canvas
    for index, group in ipairs(groups) do
        local pin = pinFor(index)
        local kind = group.kills > 0 and group.deaths > 0 and "mixed" or group.entries[1].kind
        pin.group = group
        pin:ClearAllPoints()
        pin:SetPoint("CENTER", canvas, "TOPLEFT", canvas:GetWidth() * group.x / 100, -canvas:GetHeight() * group.y / 100)
        pin.icon:ClearAllPoints()
        local mixed = kind == "mixed"
        pin:SetWidth(mixed and 38 or 23)
        pin.icon:SetPoint(mixed and "LEFT" or "CENTER")
        pin.icon:SetSize(23, 23)
        pin.icon:SetTexture(icons[mixed and "D" or kind])
        pin.second:SetShown(mixed)
        pin.count:SetText(#group.entries > 1 and #group.entries or "")
        pin:Show()
        count = count + #group.entries
        for groupIndex, entry in ipairs(group.entries) do
            if entry == old then selected, selectedGroup, selectedIndex = entry, group, groupIndex end
        end
    end
    for index = #groups + 1, #canvas.pins do canvas.pins[index]:Hide() end
    if not selected and old and not hasArt then
        for _, entry in ipairs(events) do if entry == old then selected = entry; break end end
    end
    window.mapTitle:SetText(zoneName(zone or filters.zone or previewZone, demo) or L["Карта зон"])
    window.empty:SetShown(not hasArt)
    window.empty:SetText(#events == 0 and L["Нет записей по выбранным фильтрам."] or L["Карта или координаты для этих записей недоступны."])
    window.summary:SetText((L["На карте: %d   •   Всего по фильтрам: %d   •   Без карты или координат: %d"]):format(count, #events, withoutLocation))
    updateDetail()
end

local function build()
    local frame = CreateFrame("Frame", "ForeverDeathNoteFightMap", UIParent, "BackdropTemplate")
    frame:SetSize(820, 555)
    frame:SetScale(math.min(1, UIParent:GetWidth() / 850, UIParent:GetHeight() / 575))
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        edgeSize = 32, insets = {left = 10, right = 10, top = 10, bottom = 10},
    })
    UISpecialFrames[#UISpecialFrames + 1] = frame:GetName()
    local title = label(frame, "GameFontNormalLarge", 27, -23, 650, L["Карта боёв"])
    title:SetTextColor(1, 0.82, 0.42)
    frame.subtitle = label(frame, "GameFontHighlightSmall", 28, -47, 650)
    local drag = CreateFrame("Frame", nil, frame)
    drag:SetPoint("TOPLEFT", 12, -10)
    drag:SetSize(760, 49)
    drag:EnableMouse(true)
    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -8, -8)
    close:SetScript("OnClick", function() frame:Hide() end)
    frame.filterButtons = {
        filterButton(frame, L["Зона"], "zone", function() return choicesFor("zone", L["Все зоны"]) end, 24, 170),
        filterButton(frame, L["Период"], "period", function() return periods end, 202, 115),
        filterButton(frame, L["Класс противника"], "class", function() return choicesFor("class", L["Все классы"]) end, 325, 145),
        filterButton(frame, L["Смертельная способность"], "spell", function() return choicesFor("spell", L["Все способности"]) end, 478, 195),
    }
    button(frame, L["Сбросить"], 681, -70, 115, function()
        local filters = frontScope and frontScope.filters or filtersFor(demo)
        for key in pairs(filters) do filters[key] = nil end
        previewZone, selected = nil, nil
        if frontScope and not frontScope.rival then frontScope = nil end
        filterChanged()
    end)
    frame.clearRival = button(frame, L["Все встречи"], 587, -105, 209, function()
        note.OpenFightMap(demo)
    end)
    frame.mapTitle = label(frame, "GameFontNormal", 26, -111, 529)
    local host = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    host:SetPoint("TOPLEFT", 24, -137)
    host:SetSize(549, 345)
    host:SetBackdrop({bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12})
    host:SetBackdropColor(0.1, 0.1, 0.1, 0.88)
    host:SetBackdropBorderColor(0.45, 0.36, 0.22, 1)
    local canvas = CreateFrame("Frame", nil, host)
    canvas:SetPoint("CENTER")
    canvas.host, canvas.tiles, canvas.pins = host, {}, {}
    frame.canvas = canvas
    frame.empty = label(host, "GameFontHighlight", 19, -30, 485)
    frame.legend = label(frame, "GameFontHighlightSmall", 26, -493, 766)
    frame.legend:SetText((L["|T%s:14:14|t Добивание     |T%s:14:14|t Смерть     |T%s:14:14|t|T%s:14:14|t Добивания и смерти рядом"]):format(icons.K, icons.D, icons.D, icons.K))
    frame.summary = label(frame, "GameFontHighlightSmall", 26, -518, 766)
    local panel = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    panel:SetPoint("TOPLEFT", 587, -137)
    panel:SetSize(209, 345)
    panel:SetBackdrop({bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12})
    if note.WarTable and note.WarTable.Refined() then
        panel:SetBackdropColor(unpack(note.WarTable.ink))
        panel:SetBackdropBorderColor(unpack(note.WarTable.bronze))
    else
        panel:SetBackdropColor(0.11, 0.09, 0.07, 0.94)
    end
    panel:SetBackdropBorderColor(0.54, 0.42, 0.26, 1)
    panel.title = label(panel, "GameFontNormal", 12, -14, 180)
    local identity = CreateFrame("Frame", nil, panel)
    identity:SetAllPoints()
    panel.identity = identity
    local function icon(parent, x, y, size)
        local image = parent:CreateTexture(nil, "ARTWORK")
        image:SetPoint("TOPLEFT", x, y)
        image:SetSize(size, size)
        return image
    end
    panel.portrait = icon(identity, 12, -40, 57)
    panel.name = label(identity, "GameFontNormal", 78, -42, 116)
    panel.name:SetMaxLines(2)
    panel.raceIcon = icon(identity, 78, -76, 15)
    panel.race = label(identity, "GameFontHighlightSmall", 98, -77, 99)
    panel.classIcon = icon(identity, 78, -98, 15)
    panel.class = label(identity, "GameFontHighlightSmall", 98, -99, 99)
    label(identity, "GameFontNormalSmall", 12, -215, 180):SetText(L["Смертельный удар"])
    local ability = CreateFrame("Frame", nil, identity)
    ability:SetPoint("TOPLEFT", 12, -233)
    ability:SetSize(31, 31)
    ability:EnableMouse(true)
    panel.spellIcon = icon(ability, 0, 0, 31)
    panel.spellName = label(identity, "GameFontHighlightSmall", 50, -239, 142)
    ability:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(panel.spellName:GetText())
        note.StyleLocaleTooltip(GameTooltip)
        GameTooltip:Show()
    end)
    ability:SetScript("OnLeave", function() GameTooltip:Hide() end)
    panel.body = label(panel, "GameFontHighlight", 12, -42, 180)
    panel.body:SetSpacing(4)
    panel.position = label(panel, "GameFontHighlightSmall", 82, -311, 62)
    panel.previous = button(panel, "", 12, -307, 34, function()
        if selectedGroup then showSelection(selectedGroup, (selectedIndex - 2) % #selectedGroup.entries + 1) end
    end)
    panel.next = button(panel, "", 162, -307, 34, function()
        if selectedGroup then showSelection(selectedGroup, selectedIndex % #selectedGroup.entries + 1) end
    end)
    note.StylePageButton(panel.previous, "prev")
    note.StylePageButton(panel.next, "next")
    frame.detail = panel
    note.ManageWindow(frame, "map", drag)
    window = frame
end

function note.RefreshFightMap()
    if window and window:IsShown() then
        local currentDemo = note.DemoData and note.DemoData() or nil
        if currentDemo ~= demo then
            demo, previewZone, selected, frontScope = currentDemo, nil, nil, nil
        end
        refresh()
    end
end

function note.OpenFightMap(sample, entry, scope)
    if not note.db then return end
    if not window then build() end
    frontScope = scope
    demo, previewZone, selected = sample, entry and entry.zone or nil, entry
    window:Show()
    window:Raise()
    refresh()
end

function note.OpenRivalMap(sample, guid)
    if not note.db or not guid then return end
    local source = sample or note.db
    local scope = { entries = {}, filters = {}, rival = note.Dossier(guid, sample).name }
    local known = explicitMaps(source.events)
    local fallback, recent
    for _, entry in ipairs(source.events) do
        if entry.other == guid then
            scope.entries[entry] = true
            if not fallback or entry.at >= fallback.at then fallback = entry end
            if mapID(entry, known) and (not recent or entry.at >= recent.at) then recent = entry end
        end
    end
    if not fallback then return end
    note.OpenFightMap(sample, recent or fallback, scope)
end
