local _, note = ...
local L, theme = note.L, note.WarTable
local ranks, achievements = note.LadderRanks, note.LadderAchievementRules
local progressView, syncView
local muted, green = { 0.78, 0.72, 0.64 }, { 0.68, 0.88, 0.58 }
local syncLabels = {
    disabled = "Гильдия: обмен выключён",
    no_guild = "Вы вне гильдии",
    syncing = "Сверяем историю гильдии…",
    ready = "История гильдии обновлена",
    waiting = "Согильдейцы не ответили",
    partial = "Сверка завершена частично",
    unavailable = "Обмен недоступен",
}

local function label(parent, font, x, y, width)
    local value = note.CreateFontString(parent, nil, "OVERLAY", font)
    value:SetPoint("TOPLEFT", x, y)
    value:SetWidth(width)
    value:SetJustifyH("LEFT")
    return value
end

function note.RefreshGuildSyncStatus()
    local view = syncView
    if not view or not view:IsVisible() then return end
    local sync = note.GuildSyncStatus and note.GuildSyncStatus() or {}
    local state = sync.state
    local status = state == "waiting" and not sync.lastSuccess and "Ожидаем данные от согильдейцев"
        or syncLabels[state] or syncLabels.unavailable
    view.status:SetText(L[status])
    view.status:SetTextColor(unpack(state == "ready" and green or theme.gold))
    local last = sync.lastSuccess and L["Последний обмен: %s"]:format(date("%d.%m %H:%M", sync.lastSuccess))
        or L["Обмен ещё не завершался"]
    view.last:SetText(last .. "  /  " .. L["Новых: %d"]:format(sync.added or 0))
    view.refresh:SetEnabled(sync.canRefresh == true)
    view.refresh.icon:SetAlpha(sync.canRefresh and 1 or 0.45)
end

function note.BuildRankingSync(parent)
    local view = CreateFrame("Frame", nil, parent)
    view:SetPoint("TOPRIGHT", -13, -6)
    view:SetSize(430, 31)
    local shade = view:CreateTexture(nil, "BACKGROUND")
    shade:SetPoint("TOPLEFT")
    shade:SetSize(299, 30)
    shade:SetColorTexture(0.10, 0.061, 0.031, 0.85)
    view.status = label(view, "GameFontNormalSmall", 8, -2, 283)
    view.last = label(view, "GameFontHighlightSmall", 8, -16, 283)
    view.status:SetWordWrap(false)
    view.last:SetWordWrap(false)
    view.refresh = CreateFrame("Button", nil, view, "UIPanelButtonTemplate")
    view.refresh:SetPoint("TOPRIGHT", 0, -2)
    view.refresh:SetSize(122, 26)
    view.refresh:SetText(L["Обновить"])
    note.StyleLocaleButton(view.refresh)
    local caption = view.refresh:GetFontString()
    if caption then
        caption:ClearAllPoints()
        caption:SetPoint("LEFT", 28, 0)
        caption:SetPoint("RIGHT", -5, 0)
    end
    view.refresh.icon = view.refresh:CreateTexture(nil, "OVERLAY")
    view.refresh.icon:SetSize(16, 16)
    view.refresh.icon:SetPoint("LEFT", 8, 0)
    view.refresh.icon:SetTexture("Interface\\Buttons\\UI-RefreshButton")
    view.refresh:SetScript("OnClick", function()
        if note.RequestGuildSync then note.RequestGuildSync() end
        note.RefreshGuildSyncStatus()
    end)
    view:SetScript("OnShow", note.RefreshGuildSyncStatus)
    syncView = view
    return view
end

local function panel(parent, kind, x, y, w, h)
    local frame = CreateFrame(kind, nil, parent, "BackdropTemplate")
    frame:SetPoint("TOPLEFT", x, y)
    frame:SetSize(w, h)
    theme.Panel(frame, unpack(theme.paper))
    return frame
end

local function icon(parent, left, top, size, texture)
    local art = parent:CreateTexture(nil, "ARTWORK")
    art:SetPoint("TOPLEFT", left, top)
    art:SetSize(size, size)
    art:SetTexture(texture)
    art:SetTexCoord(0.06, 0.94, 0.06, 0.94)
    return art
end

local function status(rule, saved, progress)
    return saved[rule.id] and L["Получено %s"]:format(date("%d.%m.%Y", saved[rule.id]))
        or ("%d / %d"):format(math.min(progress[rule.id] or 0, rule.target), rule.target)
end

function note.RefreshLadder()
    local view = progressView
    if not view or not view:IsVisible() then return end
    local sample = note.DemoData()
    if view.titles:IsShown() then
        local kills, victims = note.LadderPersonal(sample)
        local active, nextRank = note.LadderRank(kills, victims)
        view.titleSummary:SetText(L["Звания за последние 30 дней"] .. "  /  "
            .. L["Добивания: %d • Разных жертв: %d"]:format(kills, victims))
        for i, step in ipairs(ranks) do
            local row = view.titleRows[i]
            row.state:SetText(step == active and L["Текущее"] or step == nextRank and L["Следующее звание"] or "")
            row:SetBackdropBorderColor(unpack(step == active and theme.gold or theme.bronze))
        end
        return
    end
    local saved, progress = note.LadderAchievements(sample)
    local earned = 0
    for i, rule in ipairs(achievements) do
        local card = view.cards[i]
        card.timestamp = saved[rule.id]
        card.status:SetText(status(rule, saved, progress))
        card.status:SetTextColor(unpack(card.timestamp and green or muted))
        card.art:SetDesaturated(card.timestamp == nil)
        card:SetBackdropBorderColor(unpack(card.timestamp and green or theme.bronze))
        if card.timestamp then earned = earned + 1 end
    end
    view.awardSummary:SetText(("%s  /  %d / %d"):format(L["Личные достижения"], earned, #achievements))
end

function note.BuildJournalProgress(parent)
    local view = CreateFrame("Frame", nil, parent)
    view:SetPoint("TOPLEFT", 24, -153)
    view:SetSize(742, 375)
    progressView = view
    view:Hide()
    view.titles = CreateFrame("Frame", nil, view)
    view.titles:SetAllPoints()
    view.awards = CreateFrame("Frame", nil, view)
    view.awards:SetAllPoints()
    view.titleSummary = label(view.titles, "GameFontNormal", 8, -4, 726)
    view.awardSummary = label(view.awards, "GameFontNormal", 8, -4, 726)
    view.titleRows, view.cards = {}, {}
    for i, step in ipairs(ranks) do
        local row = panel(view.titles, "Frame", 0, -31 - (i - 1) * 40, 742, 36)
        icon(row, 10, -5, 26, step.icon)
        local name = label(row, "GameFontNormal", 46, -11, 270)
        name:SetText(L[step.name])
        name:SetTextColor(unpack(step.color))
        local requirement = label(row, "GameFontHighlightSmall", 325, -12, 255)
        requirement:SetText(L["Нужно добиваний %d • Разных жертв %d"]:format(step.kills, step.victims))
        row.state = label(row, "GameFontNormalSmall", 582, -11, 145)
        row.state:SetJustifyH("RIGHT")
        view.titleRows[i] = row
    end
    for i, rule in ipairs(achievements) do
        local card = panel(view.awards, "Button", 4 + ((i - 1) % 5) * 149, -37 - math.floor((i - 1) / 5) * 151, 140, 140)
        card.art = icon(card, 47, -12, 46, rule.icon)
        local name = label(card, "GameFontNormal", 8, -67, 124)
        name:SetJustifyH("CENTER")
        name:SetMaxLines(3)
        name:SetText(L[rule.name])
        card.status = label(card, "GameFontHighlightSmall", 6, -115, 128)
        card.status:SetJustifyH("CENTER")
        card:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(L[rule.name])
            GameTooltip:AddLine(L[rule.text], 1, 1, 1, true)
            GameTooltip:AddLine(self.status:GetText(), unpack(self.timestamp and green or muted))
            note.StyleLocaleTooltip(GameTooltip)
            GameTooltip:Show()
        end)
        local function hide(self) if GameTooltip:IsOwned(self) then GameTooltip:Hide() end end
        card:SetScript("OnLeave", hide)
        card:SetScript("OnHide", hide)
        view.cards[i] = card
    end
    function view:ShowSection(section)
        self.titles:SetShown(section == "titles")
        self.awards:SetShown(section == "achievements")
        self:SetShown(section == "titles" or section == "achievements")
    end
    return view
end
