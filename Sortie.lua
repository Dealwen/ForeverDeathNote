local _, note = ...
local L = note.L

local historyLimit = 10
local backdropTexture = "Interface\\Tooltips\\UI-Tooltip-Background"
local borderTexture = "Interface\\Tooltips\\UI-Tooltip-Border"
local gold = { 0.98, 0.76, 0.37 }
local warm = { 0.92, 0.87, 0.73 }
local muted = { 0.72, 0.67, 0.57 }
local green = { 0.58, 0.87, 0.52 }
local red = { 1, 0.55, 0.48 }
local window
local demoStates = setmetatable({}, { __mode = "k" })
local pendingDeaths = setmetatable({}, { __mode = "k" })
local finishedReports = setmetatable({}, { __mode = "k" })

local function newSortie(started)
    return { started = started, kills = 0, deaths = 0, foes = {}, unique = 0, zones = {}, topCount = 0 }
end

local function addFight(sortie, entry)
    if entry.kind == "K" then
        sortie.kills = sortie.kills + 1
    elseif entry.kind == "D" then
        sortie.deaths = sortie.deaths + 1
    else
        return
    end
    if entry.other and not sortie.foes[entry.other] then
        sortie.foes[entry.other] = true
        sortie.unique = sortie.unique + 1
    end
    local zone = entry.zone
    if not zone or zone == "" then return end
    local count = (sortie.zones[zone] or 0) + 1
    sortie.zones[zone] = count
    if count > sortie.topCount or count == sortie.topCount and zone < sortie.topZone then
        sortie.topZone, sortie.topCount = zone, count
    end
end

local function copyTotals(sortie, report)
    report.kills, report.deaths, report.unique = sortie.kills, sortie.deaths, sortie.unique
    report.topZone, report.topCount = sortie.topZone, sortie.topCount
    return report
end

local function snapshot(sortie, ended)
    return copyTotals(sortie, { started = sortie.started, ended = math.max(sortie.started, ended) })
end

local function addDemoSession(history, events, started, ended)
    local sortie = newSortie(started)
    for _, entry in ipairs(events) do
        if entry.at >= started and entry.at <= ended then addFight(sortie, entry) end
    end
    if sortie.kills + sortie.deaths > 0 then history[#history + 1] = snapshot(sortie, ended) end
end

local function demoState(demo)
    if demoStates[demo] then return demoStates[demo] end
    local state = { history = {} }
    local events = demo.events or {}
    local newest
    for _, entry in ipairs(events) do
        if not newest or entry.at > newest then newest = entry.at end
    end
    if newest then
        addDemoSession(state.history, events, newest - 55 * 60, math.min(GetServerTime(), newest + 4 * 60))
        addDemoSession(state.history, events, newest - 6 * 3600, newest - 4 * 3600)
    end
    demoStates[demo] = state
    return state
end

local function stateFor(demo)
    return demo and demoState(demo) or note.db.sorties
end

function note.AssignSortie(entry)
    local state = note.db and note.db.sorties
    pendingDeaths[entry] = state and state.active or false
end

function note.RecordSortie(entry)
    local state = note.db and note.db.sorties
    local active = state and state.active
    local sortie = pendingDeaths[entry]
    pendingDeaths[entry] = nil
    if sortie == nil then
        if not active or entry.at < active.started then return end
        sortie = active
    end
    if not sortie then return end
    -- The death recap may finish loading after the player ends this sortie.
    local report = finishedReports[sortie]
    if sortie ~= active and not report then return end
    addFight(sortie, entry)
    if report then copyTotals(sortie, report) end
    if window and window:IsShown() and not window.demo then note.RefreshSortie(false) end
end

local function duration(seconds)
    local span = math.max(0, seconds)
    local hours, minutes, rest = math.floor(span / 3600), math.floor(span % 3600 / 60), span % 60
    if hours >= 24 then return (L["%dд %02d:%02d"]):format(math.floor(hours / 24), hours % 24, minutes) end
    if hours > 0 then return ("%02d:%02d:%02d"):format(hours, minutes, rest) end
    return ("%02d:%02d"):format(minutes, rest)
end

local function label(parent, font, x, y, width, color, alignment)
    local value = note.CreateFontString(parent, nil, "OVERLAY", font)
    value:SetPoint("TOPLEFT", x, y)
    value:SetWidth(width)
    value:SetJustifyH(alignment or "LEFT")
    value:SetWordWrap(false)
    value:SetTextColor(unpack(color))
    return value
end

local function tint(parent, x, y, width, height, r, g, b, alpha)
    local image = parent:CreateTexture(nil, "BACKGROUND")
    image:SetPoint("TOPLEFT", x, y)
    image:SetSize(width, height)
    image:SetColorTexture(r, g, b, alpha)
    return image
end

local function panel(parent, x, y, width, height)
    local frame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    frame:SetPoint("TOPLEFT", x, y)
    frame:SetSize(width, height)
    frame:SetBackdrop({ bgFile = backdropTexture, edgeFile = borderTexture, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    frame:SetBackdropColor(0.11, 0.077, 0.052, 1)
    frame:SetBackdropBorderColor(0.53, 0.37, 0.21, 1)
    return frame
end

local function metric(parent, x, caption, color)
    label(parent, "GameFontHighlightSmall", x, -55, 131, muted):SetText(caption)
    return label(parent, "GameFontNormalLarge", x, -72, 131, color)
end

local function clockLabel(sortie, stamp)
    if not sortie then return "—" end
    return duration((sortie.ended or stamp) - sortie.started)
end

local function refresh(demo)
    local state = stateFor(demo)
    local history = state and state.history or {}
    local active = state and state.active
    local summary = active or history[1]
    local current = window.current
    window.demo, window.running = demo, active
    window.caption:SetText(demo and L["ТЕСТ • Примеры личных вылазок"] or L["Добивания и смерти в открытом мире"])
    window.status:SetText(active and L["Вылазка идёт"] or summary and L["Последняя вылазка"] or L["Первая вылазка"])
    window.status:SetTextColor(unpack(active and green or gold))
    current.action:SetText(active and L["Завершить"] or L["Начать вылазку"])
    window.lastSecond = GetServerTime()
    current.timer:SetText(clockLabel(summary, window.lastSecond))
    current.kills:SetText(summary and tostring(summary.kills) or "—")
    current.deaths:SetText(summary and tostring(summary.deaths) or "—")
    current.unique:SetText(summary and tostring(summary.unique) or "—")
    if summary and summary.topZone then
        current.zone:SetText((L["Основная зона: %s · %d"]):format(note.SampleText(summary.topZone, demo), summary.topCount))
    elseif summary then
        current.zone:SetText(L["Пока нет записей с известной зоной"])
    else
        current.zone:SetText(L["Счётчики начнутся с нуля. Вы сами выбираете, когда завершить вылазку."])
    end
    for i, row in ipairs(window.rows) do
        local report = history[i]
        if report then
            row.started:SetText(date("%d.%m  %H:%M", report.started))
            row.duration:SetText(clockLabel(report))
            row.kills:SetText(tostring(report.kills))
            row.deaths:SetText(tostring(report.deaths))
            row.unique:SetText(tostring(report.unique))
            row.zone:SetText(note.SampleText(report.topZone, demo) or "—")
            row:Show()
        else
            row:Hide()
        end
    end
    window.empty:SetShown(#history == 0)
end

local function toggleSortie()
    local state = stateFor(window.demo)
    if not state then
        state = { history = {} }
        note.db.sorties = state
    end
    if state.active then
        local report = snapshot(state.active, GetServerTime())
        if not window.demo then finishedReports[state.active] = report end
        table.insert(state.history, 1, report)
        state.history[historyLimit + 1] = nil
        state.active = nil
    else
        state.active = newSortie(GetServerTime())
    end
    refresh(window.demo)
end

local columns = {
    { "started", "Начало", 13, 100, warm },
    { "duration", "Время", 119, 81, warm },
    { "kills", "Добили", 201, 57, green },
    { "deaths", "Погибли", 261, 60, red },
    { "unique", "Противники", 324, 84, warm },
    { "zone", "Основная зона", 420, 175, warm },
}

local function build()
    window = CreateFrame("Frame", "ForeverDeathNoteSortie", UIParent, "BackdropTemplate")
    window:SetPoint("CENTER", 28, -18)
    window:SetSize(640, 498)
    window:SetScale(math.min(1, UIParent:GetWidth() / 675, UIParent:GetHeight() / 535))
    window:SetFrameStrata("FULLSCREEN_DIALOG")
    window:SetClampedToScreen(true)
    window:SetMovable(true)
    window:EnableMouse(true)
    window:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border", edgeSize = 28,
        insets = { left = 8, right = 8, top = 8, bottom = 8 } })
    window:SetBackdropColor(0.69, 0.59, 0.47, 1)
    table.insert(UISpecialFrames, "ForeverDeathNoteSortie")
    window:SetScript("OnUpdate", function()
        if not window.running then return end
        local stamp = GetServerTime()
        if window.lastSecond == stamp then return end
        window.lastSecond = stamp
        window.current.timer:SetText(clockLabel(window.running, stamp))
    end)

    local icon = window:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT", 22, -19)
    icon:SetSize(35, 35)
    icon:SetTexture("Interface\\Icons\\INV_Misc_Book_09")
    label(window, "GameFontNormalLarge", 67, -17, 416, gold):SetText(L["Полевые вылазки"])
    window.caption = label(window, "GameFontHighlightSmall", 67, -40, 460, muted)
    local close = CreateFrame("Button", nil, window, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -4, -4)
    close:SetScript("OnClick", function() window:Hide() end)

    local current = panel(window, 18, -63, 604, 128)
    window.current = current
    window.status = label(current, "GameFontNormalLarge", 19, -15, 360, gold)
    tint(current, 18, -44, 568, 1, 0.70, 0.48, 0.25, 0.55)
    current.action = CreateFrame("Button", nil, current, "UIPanelButtonTemplate")
    note.StyleLocaleButton(current.action)
    current.action:SetPoint("TOPRIGHT", -17, -12)
    current.action:SetSize(151, 24)
    current.action:SetScript("OnClick", toggleSortie)
    current.timer = metric(current, 19, L["Длительность"], gold)
    current.kills = metric(current, 161, L["Вы добили"], green)
    current.deaths = metric(current, 303, L["Вы погибли"], red)
    current.unique = metric(current, 445, L["Разные противники"], warm)
    current.zone = label(current, "GameFontHighlightSmall", 19, -103, 565, muted)

    label(window, "GameFontNormal", 23, -205, 365, gold):SetText(L["Последние 10 вылазок"])
    local archive = panel(window, 18, -225, 604, 241)
    tint(archive, 10, -24, 584, 1, 0.70, 0.48, 0.25, 0.45)
    for _, column in ipairs(columns) do
        label(archive, "GameFontNormalSmall", column[3], -8, column[4], gold):SetText(L[column[2]])
    end
    window.rows = {}
    for i = 1, historyLimit do
        local row = CreateFrame("Frame", nil, archive)
        row:SetPoint("TOPLEFT", 0, -26 - (i - 1) * 21)
        row:SetSize(604, 20)
        if i % 2 == 1 then tint(row, 10, 0, 584, 20, 0.55, 0.38, 0.24, 0.14) end
        for _, column in ipairs(columns) do
            row[column[1]] = label(row, "GameFontHighlightSmall", column[3], -4, column[4], column[5])
        end
        window.rows[i] = row
    end
    window.empty = label(archive, "GameFontHighlight", 33, -102, 538, muted, "CENTER")
    window.empty:SetText(L["Итоги появятся после завершения вылазки."])
    note.ManageWindow(window, "sortie", note.WindowDragHandle(window, 44, 560))
    label(window, "GameFontHighlightSmall", 25, -478, 590, muted):SetText(L["Таймер идёт до нажатия «Завершить», даже вне игры."])
end

function note.RefreshSortie(demo)
    if not note.db or not window or not window:IsShown() then return end
    if demo == nil and note.DemoData then demo = note.DemoData() end
    refresh(demo)
end

function note.OpenSortie(demo)
    if not note.db then return end
    if not window then build() end
    window:Show()
    note.RefreshSortie(demo)
end
