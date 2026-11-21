local _, note = ...
local L = note.L
local panel, rows, onOpenProfile, demo
local seen = {}
local page, totalPages = 1, 1
local shownRows, keepSeconds = 4, 300
local panelOffsetX, panelOffsetY, rowTop, rowStep, targetX = -25, -155, -57, 36, 275
local markLabels = { kos = "Помечен черепом", watch = "Наблюдение" }
local markActions = {
    { key = "watch", label = "Наблюдать без алерта" },
    { key = "kos", label = "Пометить черепом" },
    { key = "ignore", label = "Игнорировать" },
}

local function label(parent, font, x, y, width)
    local text = note.CreateFontString(parent, nil, "OVERLAY", font)
    text:SetPoint("TOPLEFT", x, y)
    text:SetWidth(width)
    text:SetJustifyH("LEFT")
    text:SetWordWrap(false)
    return text
end

local function setIcon(image, code)
    local class = code and "classicon-" .. code:lower()
    if class and C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(class) then
        image:SetAtlas(class)
    elseif code and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[code] then
        image:SetTexture("Interface\\Glues\\CharacterCreate\\UI-CharacterCreate-Classes")
        image:SetTexCoord(unpack(CLASS_ICON_TCOORDS[code]))
    else
        image:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcon_8")
        image:SetTexCoord(0, 1, 0, 1)
    end
end

local function prune(now)
    for id, entry in pairs(seen) do
        if not entry.unit and now - entry.at >= keepSeconds then seen[id] = nil end
    end
end

local function demoEntries()
    local entries = {}
    local deaths, recent = {}, {}
    for _, event in ipairs(demo.events) do
        local count = deaths[event.other] or 0
        deaths[event.other] = count + (event.kind == "D" and 1 or 0)
        if not recent[event.other] or event.at > recent[event.other].at then recent[event.other] = event end
    end
    local ids = {}
    for id in pairs(deaths) do ids[#ids + 1] = id end
    table.sort(ids)
    for i, id in ipairs(ids) do
        if demo.profiles[id] then
            local preference = note.DossierPreference and note.DossierPreference(id, demo)
            local mark = preference and preference.mark
            if mark ~= "ignore" then
                local event = recent[id]
                entries[#entries + 1] = { id = id, deaths = deaths[id], mark = mark,
                    visible = i <= 2, fightKind = deaths[id] == 0 and "K" or nil, age = i * 12,
                    zone = event.zone, latestKind = event.kind }
            end
        end
    end
    return entries
end

local function liveEntries(now)
    local entries = {}
    if note.Public(IsInInstance()) ~= false then return entries end
    prune(now)
    local index, serverNow = {}, GetServerTime()
    for id, entry in pairs(seen) do
        local item = { id = id, guid = id, unit = entry.unit,
            deaths = entry.deaths, mark = entry.mark, visible = entry.unit ~= nil, age = now - entry.at }
        index[id] = item
        entries[#entries + 1] = item
    end
    local events = note.db.events
    for i = #events, 1, -1 do
        local event = events[i]
        local age = serverNow - event.at
        -- Death recap retries can append an earlier fight a few seconds later.
        if age >= keepSeconds + 4 then break end
        if age < keepSeconds then
            local id = event.other
            local item = index[id]
            local mark = not item and note.DossierPreference(id).mark
            if not item and mark ~= "ignore" then
                item = { id = id, guid = id, deaths = 0, mark = mark, visible = false,
                    fightKind = event.kind, age = math.max(0, age) }
                index[id] = item
                entries[#entries + 1] = item
            end
            if item and (not item.latestAt or event.at > item.latestAt) then
                item.zone, item.latestKind, item.latestAt = event.zone, event.kind, event.at
            end
        end
    end
    return entries
end

local function contextMenuAvailable()
    return MenuUtil and MenuUtil.CreateContextMenu
end

local function buildTarget(row, i)
    local button = CreateFrame("Button", "ForeverDeathNoteNearbyTarget" .. i, UIParent,
        "UIPanelButtonTemplate,SecureActionButtonTemplate,SecureHandlerStateTemplate")
    note.StyleLocaleButton(button)
    button:SetSize(82, 22)
    -- Separate anchors prevent combat lockdown from protecting the informational panel.
    note.PlaceTargetControl(button, panel, targetX, rowTop - (i - 1) * rowStep - 6)
    button:SetFrameStrata("HIGH")
    button:SetFrameLevel(panel:GetFrameLevel() + 5)
    button:SetText(L["В цель"])
    note.PrepareRivalTarget(button, function()
        return panel:IsShown() and not demo and row.entry or nil
    end, nil, function()
        panel.footer:SetText(L["Нажмите Enter, чтобы взять игрока в цель."])
    end)
    button:Hide()
    row.target = button
end

local openRow
local function render()
    if not panel or not panel:IsShown() then return end
    local combat = InCombatLockdown()
    local list = demo and demoEntries() or liveEntries(GetTime())
    local visible = 0
    for _, entry in ipairs(list) do if entry.visible then visible = visible + 1 end end
    table.sort(list, function(a, b)
        if a.visible ~= b.visible then return a.visible end
        if a.visible and a.deaths ~= b.deaths then return a.deaths > b.deaths end
        if a.age ~= b.age then return a.age < b.age end
        return a.id < b.id
    end)
    totalPages = math.max(1, math.ceil(#list / shownRows))
    page = math.min(page, totalPages)
    panel.entries = list
    panel.openAll:SetShown(#list > 0)
    panel.heading:SetText(demo and L["Рядом · Примеры"] or L["Рядом · Противники"])
    panel.status:SetText(#list == 0 and L["Пока нет недавних встреч."] or
        (L["В поле зрения: %d · Встречено недавно: %d"]):format(visible, #list - visible))
    panel.pager:SetText(page .. "/" .. totalPages)
    panel.previous:SetEnabled(page > 1)
    panel.next:SetEnabled(page < totalPages)
    if panel.field then
        local showPages = totalPages > 1
        panel.previous:SetShown(showPages)
        panel.next:SetShown(showPages)
        panel.pager:SetShown(showPages)
        panel.tableName:SetShown(#list > 0)
        panel.tableTime:SetShown(#list > 0)
    end
    for i, row in ipairs(rows) do
        if not demo and not combat and not row.target then buildTarget(row, i) end
        local entry = list[(page - 1) * shownRows + i]
        row.entry = entry
        row:SetShown(entry ~= nil)
        local clickable = entry and not demo and not combat and note.CanTargetRival(entry.unit, entry.guid)
        if row.dossier then row.dossier:SetShown(entry ~= nil and not clickable) end
        if row.target and not combat then
            note.PlaceTargetControl(row.target, panel, targetX, rowTop - (i - 1) * rowStep - 6)
            if clickable then row.target:Show() else note.HideRivalTarget(row.target) end
        end
        if entry then
            local profile = (demo and demo.profiles[entry.id]) or note.Profile(entry.id)
            local level = profile.level and (L[" · ур. "] .. profile.level) or ""
            row.playerName = profile.name or L["Имя неизвестно"]
            row.name:SetText(row.playerName .. level)
            local color = RAID_CLASS_COLORS and profile.class and RAID_CLASS_COLORS[profile.class]
            if color then row.name:SetTextColor(color.r, color.g, color.b)
            else row.name:SetTextColor(1, 0.82, 0) end
            setIcon(row.icon, profile.class)
            local status = entry.visible and L["Сейчас"] or (math.floor(entry.age) .. L[" с назад"])
            if entry.fightKind then status = L["Бой · "] .. status end
            local shortMark = entry.mark == "kos" and L["Череп"] or L[markLabels[entry.mark]]
            if shortMark then status = status .. " · " .. shortMark end
            local guild = profile.guild or L["Гильдия неизвестна"]
            if panel.field then
                local timestamp = entry.visible and L["Сейчас"] or (math.floor(math.max(0, entry.age)) .. L[" с назад"])
                row.evidence:SetText(timestamp)
                row.evidence:SetTextColor(unpack(entry.visible and { 0.77, 0.90, 0.63 } or { 0.84, 0.76, 0.63 }))
                local zone = note.SampleText(entry.zone, demo)
                local outcome = L[entry.latestKind == "K" and "Добивание" or entry.latestKind == "D" and "Смерть"]
                row.detail:SetText(zone and outcome and (outcome .. " · " .. zone) or guild)
                row.tooltipZone, row.tooltipGuild, row.tooltipTime = zone, profile.guild, timestamp
            else
                row.detail:SetText(status .. " · " .. guild)
            end
            row.hint = L[markLabels[entry.mark]] or (entry.fightKind == "K" and L["Недавнее добивание"])
                or (entry.fightKind == "D" and L["Недавняя смерть"]) or (L["Ваших смертей: "] .. entry.deaths)
            row:SetAlpha((panel.field or entry.visible) and 1 or 0.7)
        end
    end
    if #list == 0 then
        panel.footer:SetText(L["Обидчики в поле зрения и бои за 5 минут."])
    elseif combat then
        panel.footer:SetText(contextMenuAvailable() and L["Правый клик — метки · Выбор цели вне боя"]
            or L["Выбор цели доступен вне боя."])
    elseif contextMenuAvailable() then
        panel.footer:SetText(L["Левый клик — карточка · Правый — метки"])
    else
        panel.footer:SetText(L["Нажмите на имя, чтобы открыть карточку."])
    end
end

local function openProfile(id, sample, callback)
    if not panel:IsShown() or demo ~= sample then return end
    if callback then callback(id) else note.OpenDossier(id, sample) end
end

local function openAllNearby()
    if not panel.entries or #panel.entries == 0 or not note.OpenAllRecords then return end
    local sample, callback = demo, onOpenProfile
    note.OpenAllRecords({
        title = panel.heading:GetText(),
        subtitle = panel.status:GetText(),
        rows = panel.entries,
        startIndex = (page - 1) * shownRows + 1,
        columns = {
            { label = L["Игрок"], weight = 2.5 },
            { label = L["Гильдия"], weight = 2.3 },
            { label = L["Зона"], weight = 2.3 },
            { label = L["Время"], weight = 1.25, justify = "RIGHT" },
        },
        cells = function(entry)
            local profile = (sample and sample.profiles[entry.id]) or note.Profile(entry.id)
            local color = RAID_CLASS_COLORS and profile.class and RAID_CLASS_COLORS[profile.class]
            local level = profile.level and L[" · ур. "] .. profile.level or ""
            local stamp = entry.visible and L["Сейчас"] or (math.floor(math.max(0, entry.age)) .. L[" с назад"])
            return { { text = (profile.name or L["Имя неизвестно"]) .. level,
                color = color and { color.r, color.g, color.b } },
                profile.guild or L["Гильдия неизвестна"], note.SampleText(entry.zone, sample) or "—", stamp }
        end,
        onSelect = function(entry) openProfile(entry.id, sample, callback) end,
    })
end

openRow = function(row, mouseButton)
    local entry, menuDemo, callback = row.entry, demo, onOpenProfile
    if not entry then return end
    local id = entry.id
    local function openEntry() openProfile(id, menuDemo, callback) end
    if mouseButton ~= "RightButton" or not contextMenuAvailable() then
        openEntry()
        return
    end
    if GameTooltip and GameTooltip:IsOwned(row) then GameTooltip:Hide() end
    local playerName = row.playerName
    MenuUtil.CreateContextMenu(row, function(_, root)
        note.StyleLocaleMenu(root:CreateTitle(playerName))
        note.StyleLocaleMenu(root:CreateButton(L["Открыть историю встреч"], openEntry))
        local function addMarkAction(label, mark)
            note.StyleLocaleMenu(root:CreateRadio(label, function()
                return note.DossierPreference(id, menuDemo).mark == mark
            end, function()
                if not panel:IsShown() or demo ~= menuDemo then return end
                local preference = note.DossierPreference(id, menuDemo)
                if note.SaveDossier(id, preference.text, mark, menuDemo) then render() end
            end))
        end
        for _, action in ipairs(markActions) do addMarkAction(L[action.label], action.key) end
        addMarkAction(L["Обычная отметка"], nil)
    end)
end

local function buildPanel()
    panel = CreateFrame("Frame", "ForeverDeathNoteRivalsNearby", UIParent, "BackdropTemplate")
    panel.field = note.FieldJournal and note.FieldJournal.Enabled()
    local width, height = 374, 255
    if panel.field then width, height, rowTop, rowStep, targetX = 444, 299, -72, 43, 342 end
    panel:SetSize(width, height)
    panel:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", panelOffsetX, panelOffsetY)
    panel:SetFrameStrata("HIGH")
    panel:EnableMouse(true)
    panel:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border", edgeSize = 24,
        insets = {left = 6, right = 6, top = 6, bottom = 6},
    })
    if panel.field then
        panel:SetBackdropColor(0.13, 0.088, 0.059, 1)
        panel:SetBackdropBorderColor(0.70, 0.50, 0.29, 1)
    elseif note.WarTable and note.WarTable.Refined() then
        panel:SetBackdropColor(unpack(note.WarTable.ink))
        panel:SetBackdropBorderColor(unpack(note.WarTable.bronze))
    else
        panel:SetBackdropColor(0.055, 0.075, 0.10, 1)
    end
    panel.heading = label(panel, "GameFontNormalLarge", 17, panel.field and -16 or -12, width - 65)
    panel.status = label(panel, "GameFontHighlightSmall", 17, panel.field and -39 or -35, width - 34)
    panel.footer = label(panel, "GameFontHighlightSmall", 17, panel.field and -276 or -233, width - 42)
    panel.pager = label(panel, "GameFontHighlightSmall", panel.field and 199 or 156, panel.field and -254 or -211, 37)
    if panel.field then
        panel.tableName = label(panel, "GameFontNormalSmall", 18, -56, 192)
        panel.tableName:SetText(L["Игрок"])
        panel.tableTime = label(panel, "GameFontNormalSmall", 225, -56, 105)
        panel.tableTime:SetJustifyH("RIGHT")
        panel.tableTime:SetText(L["Дата и время"])
        local ruler = panel:CreateTexture(nil, "ARTWORK")
        ruler:SetSize(width - 34, 1)
        ruler:SetPoint("TOPLEFT", 17, -69)
        ruler:SetColorTexture(0.58, 0.39, 0.22, 0.8)
    end
    panel.pager:SetJustifyH("CENTER")
    local close = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -5, -4)
    close:SetScript("OnClick", function() panel:Hide() end)
    panel.previous = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    note.StyleLocaleButton(panel.previous)
    panel.previous:SetSize(28, 21)
    panel.previous:SetPoint("TOPLEFT", panel.field and 163 or 120, panel.field and -248 or -205)
    panel.previous:SetText("<")
    panel.previous:SetScript("OnClick", function()
        if page > 1 then page = page - 1; render() end
    end)
    panel.next = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    note.StyleLocaleButton(panel.next)
    panel.next:SetSize(28, 21)
    panel.next:SetPoint("TOPLEFT", panel.field and 242 or 199, panel.field and -248 or -205)
    panel.next:SetText(">")
    panel.next:SetScript("OnClick", function()
        if page < totalPages then page = page + 1; render() end
    end)
    panel.openAll = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    note.StyleLocaleButton(panel.openAll)
    panel.openAll:SetSize(125, 21)
    panel.openAll:SetPoint("TOPLEFT", width - 143, panel.field and -248 or -205)
    panel.openAll:SetText(L["Открыть все"])
    panel.openAll:SetScript("OnClick", openAllNearby)
    rows = {}
    for i = 1, shownRows do
        local row = CreateFrame("Button", nil, panel)
        row:SetPoint("TOPLEFT", 16, rowTop - (i - 1) * rowStep)
        row:SetSize(panel.field and 319 or 250, panel.field and 39 or 32)
        row:SetHighlightTexture("Interface\\Buttons\\UI-Listbox-Highlight2")
        row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetPoint("TOPLEFT", panel.field and 5 or 0, panel.field and -8 or -4)
        row.icon:SetSize(23, 23)
        if panel.field then
            local wash = row:CreateTexture(nil, "BACKGROUND")
            wash:SetAllPoints()
            wash:SetColorTexture(0.63, 0.47, 0.31, i % 2 == 0 and 0.11 or 0.065)
            row.name = label(row, "GameFontNormal", 38, -5, 166)
            row.detail = label(row, "GameFontHighlightSmall", 38, -22, 270)
            row.detail:SetTextColor(0.84, 0.75, 0.64)
            row.evidence = label(row, "GameFontHighlightSmall", 203, -5, 111)
            row.evidence:SetJustifyH("RIGHT")
        else
            row.name = label(row, "GameFontNormal", 30, -1, 220)
            row.detail = label(row, "GameFontHighlightSmall", 30, -17, 220)
        end
        row:SetScript("OnClick", openRow)
        if panel.field then
            row.dossier = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
            note.StyleLocaleButton(row.dossier)
            row.dossier:SetSize(82, 22)
            row.dossier:SetPoint("TOPLEFT", targetX - 16, -6)
            row.dossier:SetText(L["Досье"])
            row.dossier:SetScript("OnClick", function() openRow(row, "LeftButton") end)
        end
        row:SetScript("OnEnter", function(self)
            if not self.entry or not self.hint or not GameTooltip then return end
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
            if panel.field then
                GameTooltip:SetText(self.playerName)
                GameTooltip:AddLine(self.hint, 1, 0.83, 0.56)
                if self.tooltipZone then GameTooltip:AddLine(self.tooltipZone, 0.87, 0.78, 0.62) end
                if self.tooltipGuild then GameTooltip:AddLine(self.tooltipGuild, 0.87, 0.78, 0.62) end
                GameTooltip:AddLine(self.tooltipTime, 0.87, 0.78, 0.62)
            else
                GameTooltip:SetText(self.hint)
            end
            if contextMenuAvailable() then GameTooltip:AddLine(L["Правый клик — метки игрока"], 0.88, 0.82, 0.68) end
            note.StyleLocaleTooltip(GameTooltip)
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function(self)
            if GameTooltip and GameTooltip:IsOwned(self) then GameTooltip:Hide() end
        end)
        rows[i] = row
    end
    panel:SetScript("OnHide", function()
        panel.entries = nil
        for _, row in ipairs(rows) do
            row.entry = nil
            note.HideRivalTarget(row.target)
        end
    end)
    local elapsed = 0
    panel:SetScript("OnUpdate", function(_, since)
        elapsed = elapsed + since
        if elapsed >= 1 then elapsed = 0; render() end
    end)
    local function align()
        for i, row in ipairs(rows) do
            note.PlaceTargetControl(row.target, panel, targetX, rowTop - (i - 1) * rowStep - 6)
        end
    end
    note.ManageWindow(panel, "nearby", note.WindowDragHandle(panel, panel.field and 48 or 46, width - 60), align)
    panel:Hide()
end

function note.UpdateNearbySightings(active, rivals, inInstance)
    if inInstance then
        seen = {}
    else
        local now = GetTime()
        for id, entry in pairs(seen) do
            local mark = note.RivalTracking(id, rivals[id])
            if not mark then
                seen[id] = nil
            elseif not active[id] then
                if entry.unit then entry.at = now end
                entry.unit, entry.mark, entry.deaths = nil, mark, rivals[id] or 0
            end
        end
        for id, entry in pairs(active) do
            seen[id] = { at = now, unit = entry.unit, mark = entry.mark, deaths = entry.deaths }
        end
        prune(now)
    end
    if not demo then render() end
end

function note.ShowNearby(demoOrNil, callback)
    if not note.db then return end
    if not panel then buildPanel() end
    demo, onOpenProfile, page = demoOrNil, callback, 1
    panel:Show()
    render()
end

function note.UpdateNearbyDemo(demoOrNil)
    if demo == demoOrNil then return end
    demo, page = demoOrNil, 1
    render()
end

function note.ToggleNearby(demoOrNil, callback)
    if panel and panel:IsShown() then panel:Hide()
    else note.ShowNearby(demoOrNil, callback) end
end
