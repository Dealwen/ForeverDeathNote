local _, note = ...
local L = note.L
local board
local borderTexture = "Interface\\Tooltips\\UI-Tooltip-Border"
local fillTexture = "Interface\\Buttons\\WHITE8X8"
local defaultPortrait = "Interface\\Icons\\INV_Misc_Bone_HumanSkull_01"
local gold, warm, muted = { 0.98, 0.80, 0.51 }, { 0.95, 0.91, 0.84 }, { 0.72, 0.76, 0.79 }
local green, red = { 0.63, 0.88, 0.62 }, { 0.90, 0.44, 0.38 }
local steel, raised, edge = { 0.06, 0.082, 0.098 }, { 0.09, 0.118, 0.14 }, { 0.26, 0.33, 0.38 }
local blue = { 0.45, 0.68, 0.92 }
local factionColors = { Horde = red, Alliance = blue }
local factionNames = { Horde = "Орда", Alliance = "Альянс" }
local factionPath = "Interface\\TargetingFrame\\UI-PVP-"
local swords = "Interface\\Icons\\Ability_DualWield"
local heroWidth, goalWidth, panelHeight = 448, 280, 349
local coverColors = {
    default = { 0.76, 0.55, 0.30 },
    crimson = { 0.91, 0.38, 0.30 },
    midnight = { 0.55, 0.62, 0.89 },
    jade = { 0.53, 0.79, 0.56 },
}
local raceAtlas = { scourge = "undead", skyborne = "bloodelf" }
local goalIcons = {
    ["hunt:peers"] = "Interface\\Icons\\Ability_DualWield",
    ["hunt:revenge"] = "Interface\\Icons\\Ability_Rogue_FeignDeath",
    ["hunt:zones"] = "Interface\\Icons\\INV_Misc_Map_01",
    ["hunt:guild"] = "Interface\\Icons\\INV_BannerPVP_01",
}

local function refined()
    return note.WarTable and note.WarTable.Refined()
end

local function fieldTheme()
    return note.FieldJournal and note.FieldJournal.Enabled()
end

local function label(parent, font, x, y, width, color)
    local value = note.CreateFontString(parent, nil, "OVERLAY", font)
    value:SetPoint("TOPLEFT", x, y)
    value:SetWidth(width)
    value:SetJustifyH("LEFT")
    value:SetWordWrap(false)
    if color then value:SetTextColor(unpack(color)) end
    return value
end

local function stripe(parent, x, y, width, height, color, opacity)
    local image = parent:CreateTexture(nil, "ARTWORK")
    image:SetPoint("TOPLEFT", x, y)
    image:SetSize(width, height)
    image:SetColorTexture(color[1], color[2], color[3], opacity or 1)
    return image
end

local function artwork(parent, x, y, width, height)
    local image = parent:CreateTexture(nil, "ARTWORK")
    image:SetPoint("TOPLEFT", x, y)
    image:SetSize(width, height)
    return image
end

local function applySkin(frame, bg, edge)
    frame:SetBackdrop({
        bgFile = fillTexture, edgeFile = borderTexture, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    frame:SetBackdropColor(bg[1], bg[2], bg[3], bg[4] or 1)
    frame:SetBackdropBorderColor(edge[1], edge[2], edge[3], edge[4] or 1)
end

local function panel(parent, x, y, width, height, bg, border)
    local frame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    frame:SetSize(width, height)
    frame:SetPoint("TOPLEFT", x, y)
    if fieldTheme() then
        bg = bg == raised and { 0.15, 0.112, 0.083 } or { 0.11, 0.085, 0.068 }
        border = border or { 0.43, 0.32, 0.21 }
    elseif refined() then
        local theme = note.WarTable
        bg = bg == raised and theme.paper or theme.ink
        border = border or theme.bronze
    end
    applySkin(frame, bg or steel, border or edge)
    return frame
end

local function button(parent, caption, x, y, width, onClick)
    local control = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    note.StyleLocaleButton(control)
    if note.StyleWarcraftButton then note.StyleWarcraftButton(control) end
    control:SetSize(width, 24)
    control:SetPoint("TOPLEFT", x, y)
    control:SetText(caption)
    control:SetScript("OnClick", onClick)
    return control
end

local function textButton(parent, caption, x, y, width, onClick, height, primary, font, isRow)
    local control = CreateFrame("Button", nil, parent, "BackdropTemplate")
    height = height or 26
    control:SetSize(width, height)
    control:SetPoint("TOPLEFT", x, y)
    local surface = primary and { 0.30, 0.105, 0.09 } or raised
    local border = primary and red or edge
    if fieldTheme() then
        surface = primary and { 0.30, 0.20, 0.10 } or { 0.13, 0.095, 0.069 }
        border = primary and { 0.79, 0.60, 0.37 } or { 0.46, 0.33, 0.22 }
    elseif refined() then
        surface = primary and { 0.265, 0.126, 0.052 } or note.WarTable.paper
        border = primary and { 0.80, 0.55, 0.26 } or { 0.35, 0.25, 0.16 }
    end
    applySkin(control, surface, border)
    control:SetHighlightTexture("Interface\\Buttons\\UI-Listbox-Highlight2")
    control.caption = label(control, font or "GameFontNormal", 5, -math.floor((height - 12) / 2), width - 10, warm)
    control.caption:SetJustifyH("CENTER")
    control.caption:SetText(caption)
    control:SetScript("OnMouseDown", function(self)
        if self:IsEnabled() then self.caption:SetTextColor(unpack(gold)) end
    end)
    control:SetScript("OnMouseUp", function(self)
        self.caption:SetTextColor(unpack(self.active and gold or warm))
    end)
    control:SetScript("OnDisable", function(self) self:SetAlpha(0.48) end)
    control:SetScript("OnEnable", function(self) self:SetAlpha(1) end)
    control:SetScript("OnClick", onClick)
    if note.StyleWarcraftButton and not isRow then
        note.StyleWarcraftButton(control)
        if note.TintWarcraftButton then note.TintWarcraftButton(control, false, primary) end
    end
    return control
end

local function setChoice(control, active)
    control.active = active
    if control.fdnNativeArt and note.TintWarcraftButton then
        note.TintWarcraftButton(control, active)
        control.caption:SetTextColor(unpack(active and gold or warm))
        return
    end
    if refined() then
        local theme = note.WarTable
        if active then
            control:SetBackdropColor(0.24, 0.15, 0.071, 1)
            control:SetBackdropBorderColor(unpack(theme.bronze))
        else
            control:SetBackdropColor(unpack(theme.ink))
            control:SetBackdropBorderColor(0.35, 0.25, 0.16, 1)
        end
        control.caption:SetTextColor(unpack(active and gold or warm))
    elseif active then
        control:SetBackdropColor(0.15, 0.22, 0.29, 1)
        control:SetBackdropBorderColor(0.44, 0.62, 0.78, 1)
        control.caption:SetTextColor(unpack(gold))
    else
        control:SetBackdropColor(raised[1], raised[2], raised[3], 1)
        control:SetBackdropBorderColor(edge[1], edge[2], edge[3], 1)
        control.caption:SetTextColor(unpack(warm))
    end
end

local function setPrimaryTint(control, color)
    if control.fdnNativeArt and note.TintWarcraftButton then
        note.TintWarcraftButton(control, false, true)
        return
    end
    control:SetBackdropColor(0.064 + color[1] * 0.26, 0.062 + color[2] * 0.12, 0.085 + color[3] * 0.24, 1)
    control:SetBackdropBorderColor(color[1], color[2], color[3], 1)
end

local function makeBar(parent, x, y, width)
    local bar = CreateFrame("StatusBar", nil, parent)
    bar:SetPoint("TOPLEFT", x, y)
    bar:SetSize(width, 5)
    bar:SetStatusBarTexture(fillTexture)
    local base = bar:CreateTexture(nil, "BACKGROUND")
    base:SetAllPoints()
    base:SetColorTexture(0.27, 0.33, 0.39, 0.85)
    return bar
end

local function weekLabel(week)
    if not week or not week.start or not week.ends then return L["Неделя без дат"] end
    return date("%d.%m", week.start) .. "–" .. date("%d.%m", week.ends - 1)
end

local function setPortrait(texture, profile, id, demo)
    texture:SetTexCoord(0, 1, 0, 1)
    if not demo and id and SetPortraitTexture and not InCombatLockdown()
        and note.GUID(UnitGUID("target")) == id then
        SetPortraitTexture(texture, "target")
        return
    end
    local race = profile.raceFile and profile.raceFile:lower()
    local raceIcon = race and ("raceicon-" .. (raceAtlas[race] or race) .. (profile.sex == 3 and "-female" or "-male"))
    local classIcon = profile.class and "classicon-" .. profile.class:lower()
    if C_Texture and C_Texture.GetAtlasInfo then
        if raceIcon and C_Texture.GetAtlasInfo(raceIcon) then
            texture:SetAtlas(raceIcon)
            return
        elseif classIcon and C_Texture.GetAtlasInfo(classIcon) then
            texture:SetAtlas(classIcon)
            return
        end
    end
    if profile.class and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[profile.class] then
        texture:SetTexture("Interface\\Glues\\CharacterCreate\\UI-CharacterCreate-Classes")
        texture:SetTexCoord(unpack(CLASS_ICON_TCOORDS[profile.class]))
    else
        texture:SetTexture(defaultPortrait)
    end
end

local function palette(cosmetic)
    local color = cosmetic and cosmetic.palette
    if type(color) == "table" then
        if color[1] and color[2] and color[3] then return color end
        if color.r and color.g and color.b then return { color.r, color.g, color.b } end
    end
    return cosmetic and coverColors[cosmetic.id] or coverColors.default
end

local function refresh()
    if note.RefreshHuntBoard then note.RefreshHuntBoard(board.demo) end
end

local function setRivalView(view)
    board.rivalView, board.rivalPage = view, 1
    board.hero.feedback:SetText("")
    refresh()
end

local function actionHint(control, key)
    control:SetScript("OnEnter", function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(key and L[key] or self.caption:GetText())
        note.StyleLocaleTooltip(GameTooltip)
        GameTooltip:Show()
    end)
    local function hideHint(self)
        if GameTooltip and GameTooltip:IsOwned(self) then GameTooltip:Hide() end
    end
    control:SetScript("OnLeave", hideHint)
    control:SetScript("OnHide", hideHint)
end

local function call(action, ...)
    local callback = board.actions[action]
    if callback then return callback(...) end
end

local function openProfile(id)
    if board.actions.profile then call("profile", id, board.demo)
    elseif note.OpenDossier then note.OpenDossier(id, board.demo) end
end

local function openMap(entry)
    if board.actions.map then call("map", board.demo, entry)
    elseif note.OpenFightMap then note.OpenFightMap(board.demo, entry) end
end

local function openNearby()
    if board.actions.nearby then call("nearby", board.demo)
    elseif note.ToggleNearby then note.ToggleNearby(board.demo, openProfile) end
end

local function chooseTracker(id)
    local demo = board.demo
    if board.actions.tracker then
        call("tracker", id, demo)
    else
        local goal = note.GetTrackedHuntGoal(demo)
        local same = goal and goal.id == id
        if not note.SetHuntTrackerVisible then
            note.TrackHuntGoal(id, demo)
        elseif same then
            note.SetHuntTrackerVisible(not note.IsHuntTrackerVisible(demo), demo)
        elseif note.TrackHuntGoal(id, demo) then
            note.SetHuntTrackerVisible(true, demo)
        end
    end
    refresh()
end

local function tile(parent, title, x, width)
    local frame = panel(parent, x, -142, width, 49, { 0.13, 0.095, 0.058 }, { 0.38, 0.29, 0.18 })
    frame.caption = label(frame, "GameFontHighlightSmall", 4, -9, width - 8, muted)
    frame.caption:SetJustifyH("CENTER")
    frame.caption:SetText(title)
    frame.value = label(frame, "GameFontNormalLarge", 4, -24, width - 8, warm)
    frame.value:SetJustifyH("CENTER")
    return frame
end

local function makeCandidate(parent, hero, index)
    local first = index == 1
    local row = panel(parent, 18, -89 - (index - 1) * 61, heroWidth - 36, 56, raised)
    row.portrait = artwork(row, 8, -8, 40, 40)
    row.name = label(row, "GameFontNormal", 60, -13, 176, warm)
    row.score = label(row, "GameFontHighlightSmall", 60, -33, 176, muted)
    row.select = textButton(row, L["Взять реванш"], 244, -12, 122, function()
        if not row.rival then return end
        if board.rivalView == "hidden" then
            note.SetHuntRivalHidden(row.rival.id, false, board.demo)
            return
        end
        local ok, message = note.TrackHuntRival(row.rival.id, board.demo)
        hero.feedback:SetText(message or (ok and L["Цель выбрана."] or L["Выберите другого обидчика."]))
        if ok then board.rivalView, board.rivalPage = nil, 1 end
        refresh()
    end, 32, first)
    row.hide = textButton(row, "×", 373, -12, 29, function()
        if row.rival then note.SetHuntRivalHidden(row.rival.id, true, board.demo) end
    end, 32)
    actionHint(row.hide, "Убрать цель")
    return row
end

local function buildHero(parent)
    local field = fieldTheme()
    local hero = panel(parent, 0, 0, heroWidth, panelHeight, steel)
    hero.crest = artwork(hero, heroWidth - 146, -22, 122, 122)
    hero.crest:SetAlpha(refined() and 0.09 or 0.19)
    hero.edge = stripe(hero, 18, -12, heroWidth - 36, refined() and 1 or 2, gold, 0.87)
    label(hero, refined() and "GameFontNormal" or "GameFontHighlightSmall", 20, -24, 205, refined() and gold or warm):SetText(L["Личный реванш"])
    hero.state = label(hero, "GameFontHighlightSmall", 235, -24, 193, muted)
    hero.state:SetJustifyH("RIGHT")

    hero.active = CreateFrame("Frame", nil, hero)
    hero.active:SetAllPoints()
    hero.dismiss = textButton(hero.active, "×", 401, -18, 27, function()
        if hero.target then note.SetHuntRivalHidden(hero.target.id, true, board.demo) end
    end, 25)
    actionHint(hero.dismiss, "Убрать цель")
    local portraitSize = field and 59 or 78
    local portrait = panel(hero.active, 19, -54, portraitSize, portraitSize, raised)
    hero.portrait = artwork(portrait, 4, -4, portraitSize - 8, portraitSize - 8)
    hero.name = label(hero.active, "GameFontNormalLarge", field and 88 or 111, -58, field and 127 or 310, warm)
    hero.class = label(hero.active, "GameFontHighlight", field and 19 or 112, field and -129 or -83,
        field and 193 or 307, warm)
    hero.guild = label(hero.active, "GameFontHighlightSmall", field and 19 or 112, field and -150 or -107,
        field and 193 or 308, muted)
    if field then
        hero.name:SetWordWrap(true)
        hero.name:SetMaxLines(3)
        hero.fieldPreview = note.BuildFieldMap(hero.active, 226, -51, 203, 112, openMap)
        hero.fieldPlace = label(hero.active, "GameFontHighlightSmall", 228, -169, 199, muted)
        hero.fieldPlace:SetJustifyH("CENTER")
    end
    local stats = panel(hero.active, 19, field and -191 or -146, heroWidth - 38, field and 48 or 54, raised)
    local function metric(caption, x, color)
        local value = label(stats, "GameFontNormalLarge", x, -7, 126, color)
        value:SetJustifyH("CENTER")
        local tag = label(stats, "GameFontHighlightSmall", x, field and -29 or -32, 126, muted)
        tag:SetJustifyH("CENTER")
        tag:SetText(caption)
        return { value = value, caption = tag }
    end
    stripe(stats, 136, -10, 1, 34, edge)
    stripe(stats, 272, -10, 1, 34, edge)
    hero.wins = metric(L["Вы добили"], 5, blue)
    hero.losses = metric(L["Вас добили"], 142, red)
    hero.timer = metric(L["До завершения"], 279, warm)
    local actionsY = field and -249 or -215
    hero.dossier = textButton(hero.active, L["Досье"], 19, actionsY, 115, function()
        openProfile(hero.target.id)
    end, 31, true)
    hero.track = textButton(hero.active, L["Трекер"], 144, actionsY, 108, function()
        chooseTracker("hunt:contract")
    end, 31)
    hero.change = textButton(hero.active, L["Сменить цель"], 262, actionsY, 167, function()
        setRivalView("all")
    end, 31)
    if refined() then
        hero.dossier:SetSize(141, 31)
        hero.dossier.caption:SetWidth(131)
        hero.track:ClearAllPoints()
        hero.track:SetPoint("TOPLEFT", 173, actionsY)
        hero.change:ClearAllPoints()
        hero.change:SetPoint("TOPLEFT", 295, actionsY)
        hero.change:SetWidth(134)
        hero.change.caption:SetWidth(124)
    end
    hero.sighting = label(hero.active, "GameFontHighlightSmall", field and 88 or 20, field and -108 or -258,
        field and 134 or 408, muted)

    hero.empty = CreateFrame("Frame", nil, hero)
    hero.empty:SetAllPoints()
    hero.prompt = label(hero.empty, "GameFontNormalLarge", 19, -51, 379, warm)
    hero.prompt:SetWordWrap(true)
    hero.prompt:SetMaxLines(2)
    hero.candidates = {}
    for i = 1, 3 do hero.candidates[i] = makeCandidate(hero.empty, hero, i) end
    hero.emptyHelp = label(hero.empty, "GameFontHighlight", 19, -87, 378, muted)
    hero.emptyHelp:SetWordWrap(true)
    hero.emptyHelp:SetMaxLines(3)
    hero.journal = textButton(hero.empty, L["Журнал"], 18, -149, 141, function()
        if note.OpenWindow then note.OpenWindow("journal") end
    end, 31, true)
    hero.other = textButton(hero.empty, L["Другие обидчики"], 18, -157, 196, function()
        setRivalView("all")
    end, 30)
    hero.hidden = textButton(hero.empty, L["Скрытые цели"], 230, -157, 198, function()
        setRivalView("hidden")
    end, 30)
    hero.feedback = label(hero.empty, "GameFontHighlightSmall", 19, -205, 405, muted)
    hero.feedback:SetWordWrap(true)
    hero.feedback:SetMaxLines(2)
    hero.cancel = textButton(hero.empty, L["Назад"], 18, -302, 122, function()
        setRivalView(board.rivalView == "hidden" and "all" or nil)
    end, 32)
    hero.rivalBack = textButton(hero.empty, "<", 149, -302, 30, function()
        board.rivalPage = board.rivalPage - 1
        refresh()
    end, 32)
    hero.rivalNext = textButton(hero.empty, ">", 231, -302, 30, function()
        board.rivalPage = board.rivalPage + 1
        refresh()
    end, 32)
    if note.StylePageButton then
        note.StylePageButton(hero.rivalBack, "prev")
        note.StylePageButton(hero.rivalNext, "next")
        hero.rivalBack.caption:Hide()
        hero.rivalNext.caption:Hide()
        actionHint(hero.rivalBack, "Назад")
        actionHint(hero.rivalNext, "Далее")
    end
    hero.rivalPages = label(hero.empty, "GameFontHighlightSmall", 45, 183, -311, muted)
    hero.rivalPages:SetJustifyH("CENTER")

    local latest = panel(hero, 18, field and -287 or -280, heroWidth - 36, 53, raised)
    latest.icon = artwork(latest, 10, -11, 31, 31)
    latest.title = label(latest, "GameFontHighlightSmall", 52, -9, 200, muted)
    latest.title:SetText(L["Последний бой"])
    latest.event = label(latest, "GameFontNormal", 52, -28, 211, warm)
    latest.open = textButton(latest, L["Разбор боя"], 269, -12, 132, function()
        if note.OpenFightReport and latest.entry then note.OpenFightReport(board.demo, latest.entry) end
    end, 29)
    hero.latest = latest
    return hero
end

local function buildGoals(parent)
    local field = fieldTheme()
    local goals = panel(parent, heroWidth + 14, 0, goalWidth, panelHeight, steel)
    label(goals, "GameFontNormalLarge", 17, -19, 195, warm):SetText(L["Цели недели"])
    goals.progress = label(goals, "GameFontNormal", 215, -23, 47, gold)
    goals.progress:SetJustifyH("RIGHT")
    goals.deadline = label(goals, "GameFontHighlightSmall", 17, -44, 245, muted)
    stripe(goals, 17, -61, 246, 1, edge)
    goals.rows = {}
    for i = 1, 4 do
        local row = textButton(goals, "", 15, (field and -67 or -70) - (i - 1) * (field and 39 or 45), 250, function(self)
            goals.expanded = goals.expanded ~= self.goal.id and self.goal.id or nil
            refresh()
        end, field and 39 or 40, nil, nil, true)
        row.icon = artwork(row, 7, -7, 25, 25)
        row.caption:ClearAllPoints()
        row.caption:SetPoint("TOPLEFT", 40, -5)
        row.caption:SetWidth(181)
        row.caption:SetJustifyH("LEFT")
        row.count = label(row, "GameFontHighlightSmall", 119, -22, 36, muted)
        row.count:SetJustifyH("RIGHT")
        row.arrow = label(row, "GameFontHighlight", 225, -4, 17, warm)
        row.arrow:SetJustifyH("CENTER")
        row.bar = makeBar(row, 41, -29, 80)
        row.bar:SetHeight(3)
        row.track = textButton(row, L["Отследить"], 158, -18, 85, function()
            if row.goal then chooseTracker(row.goal.id) end
        end, 18, nil, "GameFontHighlightSmall")
        actionHint(row.track)
        if refined() then
            row:SetBackdrop(nil)
            stripe(row, 4, field and -38 or -39, 242, 1, note.WarTable.bronze, 0.48)
        end
        row:SetScript("OnEnter", function(self)
            if not self.goal or not GameTooltip then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(self.goal.name, unpack(gold))
            GameTooltip:AddLine(self.goal.description, warm[1], warm[2], warm[3], true)
            GameTooltip:AddLine(goals.expanded == self.goal.id and L["Свернуть задачу"] or L["Показать задачу"],
                muted[1], muted[2], muted[3], true)
            note.StyleLocaleTooltip(GameTooltip)
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
        goals.rows[i] = row
    end
    local detail = CreateFrame("Frame", nil, goals)
    detail:SetPoint("TOPLEFT", 15, field and -227 or -252)
    detail:SetSize(250, 86)
    stripe(detail, 2, -1, 246, 1, edge)
    detail.description = label(detail, "GameFontHighlightSmall", 2, -10, 247, warm)
    detail.description:SetWordWrap(true)
    detail.description:SetMaxLines(3)
    goals.detail = detail
    goals.help = label(goals, "GameFontHighlightSmall", 17, -269, 246, muted)
    goals.help:SetWordWrap(true)
    goals.help:SetMaxLines(2)
    if field then
        local activity = CreateFrame("Frame", nil, goals)
        activity:SetPoint("TOPLEFT", 17, -226)
        activity:SetSize(246, 110)
        label(activity, "GameFontNormal", 0, 0, 242, gold):SetText(L["Последние встречи"])
        activity.empty = label(activity, "GameFontHighlightSmall", 1, -30, 242, muted)
        activity.empty:SetText(L["В журнале нет записи"])
        activity.rows = {}
        for i = 1, 2 do
            local row = CreateFrame("Button", nil, activity)
            row:SetPoint("TOPLEFT", 0, -24 - (i - 1) * 41)
            row:SetSize(246, 37)
            row:SetHighlightTexture("Interface\\Buttons\\UI-Listbox-Highlight2")
            stripe(row, 0, -36, 246, 1, note.WarTable.bronze, 0.45)
            row.icon = artwork(row, 3, -7, 22, 22)
            row.name = label(row, "GameFontHighlight", 33, -4, 209, warm)
            row.where = label(row, "GameFontHighlightSmall", 33, -21, 209, muted)
            row:SetScript("OnClick", function(self)
                if self.event and note.OpenFightReport then note.OpenFightReport(board.demo, self.event) end
            end)
            activity.rows[i] = row
        end
        goals.activity = activity
    end
    return goals
end

local function updateSighting(hero, demo)
    local target = hero.target
    if not target then return end
    local sight = not demo and note.GetHuntSighting and note.GetHuntSighting(target.id) or nil
    if sight and sight.visible then
        hero.sighting:SetText(L["Замечен рядом"])
        hero.sighting:SetTextColor(unpack(green))
    elseif sight and sight.age then
        hero.sighting:SetText((L["Замечен %d с назад"]):format(math.floor(math.max(0, sight.age))))
        hero.sighting:SetTextColor(unpack(muted))
    else
        hero.sighting:SetText(demo and L["Пример из журнала"] or L["Не обнаружен рядом"])
        hero.sighting:SetTextColor(unpack(muted))
    end
end

local function mostRecent(source)
    local latest = source.events[#source.events]
    if not latest then return end
    -- Death Recap can resolve after a newer killing blow has been added to the log.
    for i = #source.events - 1, 1, -1 do
        local event = source.events[i]
        if event.at > latest.at then latest = event end
    end
    return latest
end

local function updateLatest(hero, source, demo, entry)
    local recent = hero.latest
    recent.entry = entry or mostRecent(source)
    recent:SetShown(not board.rivalView)
    recent.open:SetShown(recent.entry ~= nil and note.OpenFightReport ~= nil)
    if not recent.entry then
        recent.title:SetText(L["Последний бой"])
        recent.icon:SetTexture(swords)
        recent.event:SetText(L["В журнале нет записи"])
        recent.event:SetTextColor(unpack(muted))
        return
    end
    local fight = recent.entry
    local profile = source.profiles[fight.other] or {}
    recent.icon:SetTexture(fight.kind == "D" and defaultPortrait or swords)
    local dateText = date("%d.%m %H:%M", fight.at)
    local where = note.SampleText(fight.subzone or fight.zone, demo)
    recent.title:SetText(L["Последний бой"] .. "  /  " .. dateText)
    recent.event:SetText(where or profile.name or L["Место не записано"])
    recent.event:SetTextColor(unpack(warm))
end

local function updateHero(hero, demo, now, cover)
    local source = demo or note.db
    local target = note.GetHuntTarget and note.GetHuntTarget(demo, now)
    hero.target = target
    local view = board.rivalView
    local hiddenView = view == "hidden"
    local active = target ~= nil and not view
    hero.cancel:SetShown(view ~= nil)
    hero.active:SetShown(active)
    hero.empty:SetShown(not active)
    hero.state:SetWidth(active and 159 or 193)
    local candidates = not active and note.HuntCandidates and note.HuntCandidates(demo, now, view) or nil
    local pages = math.max(1, math.ceil((candidates and #candidates or 0) / #hero.candidates))
    local page = math.max(1, math.min(board.rivalPage or 1, pages))
    board.rivalPage = page
    hero.rivalBack:SetShown(view ~= nil and pages > 1)
    hero.rivalNext:SetShown(view ~= nil and pages > 1)
    hero.rivalPages:SetShown(view ~= nil and pages > 1)
    hero.rivalBack:SetEnabled(page > 1)
    hero.rivalNext:SetEnabled(page < pages)
    hero.rivalPages:SetText(("%d / %d"):format(page, pages))
    local hasHidden = not active and not hiddenView and note.HasHiddenHuntRivals and note.HasHiddenHuntRivals(demo)
    hero.hidden:SetShown(hasHidden == true)
    hero.hidden:ClearAllPoints()
    hero.hidden:SetPoint("TOPLEFT", view and 271 or 230, view and -302 or -157)
    hero.hidden:SetWidth(view and 157 or 198)
    hero.hidden.caption:SetWidth(view and 147 or 188)
    local focused = active and target or candidates and candidates[1]
    local profile = focused and focused.profile or {}
    local own = source.profiles[demo and "self" or note.owner] or {}
    local faction = factionColors[profile.faction] and profile.faction or own.faction
    local accent = factionColors[faction] or gold
    local coverTone = palette(cover)
    local rim = refined() and note.WarTable.bronze or edge
    local weight = refined() and 0.20 or 0.35
    hero:SetBackdropBorderColor(rim[1] * (1 - weight) + coverTone[1] * weight,
        rim[2] * (1 - weight) + coverTone[2] * weight, rim[3] * (1 - weight) + coverTone[3] * weight, 1)
    hero.edge:SetColorTexture(accent[1], accent[2], accent[3], 0.90)
    hero.crest:SetShown(factionColors[faction] ~= nil)
    if factionColors[faction] then hero.crest:SetTexture(factionPath .. faction) end
    hero.latest:ClearAllPoints()
    hero.latest:SetPoint("TOPLEFT", 18, active and (fieldTheme() and -287 or -280) or -212)
    updateLatest(hero, source, demo, active and target.entry or nil)

    if not active then
        local count = candidates and #candidates or 0
        hero.state:SetText(view == "all" and L["Выбор цели"] or "")
        hero.state:SetTextColor(unpack(muted))
        hero.emptyHelp:SetShown(count == 0)
        hero.journal:SetShown(count == 0 and not view)
        hero.other:SetShown(count > 1 and not view)
        hero.prompt:SetText(hiddenView and L["Скрытые цели"] or L["Выберите обидчика"])
        hero.emptyHelp:SetText(hiddenView and L["Нет скрытых целей."] or (#source.events == 0
            and L["Первый обидчик появится после записанной смерти в PvP."] or L["В журнале пока нет подходящих встреч."]))
        hero.feedback:ClearAllPoints()
        hero.feedback:SetPoint("TOPLEFT", 19, -275)
        for i, row in ipairs(hero.candidates) do
            row.rival = candidates and (i == 1 or view) and candidates[(page - 1) * #hero.candidates + i] or nil
            row:SetShown(row.rival ~= nil)
            row.select:SetEnabled(row.rival ~= nil)
            row.hide:SetShown(not hiddenView)
            row.select:SetWidth(hiddenView and 158 or 122)
            row.select.caption:SetWidth(hiddenView and 148 or 112)
            row.select.caption:SetText(hiddenView and L["Вернуть в список"] or L["Взять реванш"])
            if row.rival then
                row.name:SetText(row.rival.name)
                local details = (L["Вы %d · Вас %d"]):format(row.rival.kills or 0, row.rival.deaths or 0)
                    :gsub(" · ", " / ")
                local rivalProfile = row.rival.profile or {}
                local label = factionNames[rivalProfile.faction]
                row.score:SetText(label and (L[label] .. "  /  " .. details) or details)
                if i == 1 then setPrimaryTint(row.select, accent) end
                setPortrait(row.portrait, rivalProfile, row.rival.id, demo)
            end
        end
        return
    end
    local phase = target.completed and L["Реванш завершён"] or (target.expired and L["Срок истёк"] or L["Активная цель"])
    hero.state:SetText(phase)
    if not refined() then setPrimaryTint(hero.dossier, accent) end
    hero.change.caption:SetText((target.completed or target.expired) and L["Новая цель"] or L["Сменить цель"])
    local trackedGoal = note.GetTrackedHuntGoal(demo, now)
    local tracked = trackedGoal and trackedGoal.id == "hunt:contract"
        and (not note.IsHuntTrackerVisible or note.IsHuntTrackerVisible(demo))
    hero.track.caption:SetText(tracked and L["Скрыть"] or L["Трекер"])
    hero.track:SetEnabled(tracked and true or not (target.completed or target.expired))
    setChoice(hero.track, tracked)
    hero.state:SetTextColor(unpack(target.completed and green or (target.expired and muted or warm)))
    setPortrait(hero.portrait, profile, target.id, demo)
    hero.name:SetText(target.name or profile.name or L["Неизвестный обидчик"])
    local class = note.ClassLabel(profile.class, profile.sex)
    local level = profile.level and (L["Ур. "] .. profile.level) or L["Уровень неизвестен"]
    hero.class:SetText(class and (class .. "  /  " .. level) or level)
    local guild = profile.guild and ("«" .. profile.guild .. "»") or L["Гильдия не указана"]
    local side = factionNames[profile.faction]
    hero.guild:SetText(side and (L[side] .. "  /  " .. guild) or guild)
    if hero.fieldPreview then
        note.UpdateFieldMap(hero.fieldPreview, target.entry)
        local where = target.entry and note.SampleText(target.entry.zone, demo)
        hero.fieldPlace:SetText(where or L["Зона неизвестна"])
    end
    hero.wins.value:SetText(tostring(target.kills or 0))
    hero.losses.value:SetText(tostring(target.deaths or 0))
    hero.timer.caption:SetText(target.completed and L["Завершено"] or L["До завершения"])
    hero.timer.value:SetText(target.completed and date("%d.%m", target.completed)
        or (target.expires and note.HuntTimeRemaining(target.expires, now) or "-"))
    updateSighting(hero, demo)
end

local function updateActivity(activity, demo)
    local source = demo or note.db
    local first, second
    for _, event in ipairs(source.events) do
        if not first or event.at >= first.at then
            second, first = first, event
        elseif not second or event.at >= second.at then
            second = event
        end
    end
    activity.empty:SetShown(not first)
    for i, row in ipairs(activity.rows) do
        local entry = i == 1 and first or i == 2 and second
        row.event = entry
        row:SetShown(entry and true or false)
        if entry then
            local profile = source.profiles[entry.other] or {}
            local zone = note.SampleText(entry.zone, demo) or L["Зона неизвестна"]
            row.name:SetText(profile.name or L["Имя неизвестно"])
            row.where:SetText(date("%d.%m %H:%M", entry.at) .. "  /  " .. zone)
            row.icon:SetTexture(entry.kind == "D" and defaultPortrait or swords)
        end
    end
end

local function updateGoals(pane, overview, reset, demo)
    local visible, earned = {}, 0
    for _, goal in ipairs(overview) do
        if not goal.contract then
            visible[#visible + 1] = goal
            if goal.earned then earned = earned + 1 end
        end
    end
    local trackerVisible = not note.IsHuntTrackerVisible or note.IsHuntTrackerVisible(demo)
    local detail = pane.detail
    detail.goal = nil
    for i, row in ipairs(pane.rows) do
        local goal = visible[i]
        row.goal = goal
        row:SetShown(goal ~= nil)
        if goal then
            row.icon:SetTexture(goalIcons[goal.id] or defaultPortrait)
            row.caption:SetText(goal.name)
            row.count:SetText(("%d/%d"):format(goal.amount or 0, goal.target or 1))
            row.count:SetTextColor(unpack(goal.earned and green or muted))
            row.bar:SetMinMaxValues(0, goal.target or 1)
            row.bar:SetValue(goal.amount or 0)
            row.bar:SetStatusBarColor(unpack(goal.earned and green or refined() and gold or blue))
            local expanded = pane.expanded == goal.id
            if refined() then
                row.caption:SetTextColor(unpack(expanded and gold or warm))
            else
                setChoice(row, expanded)
            end
            row.arrow:SetText(expanded and "-" or "+")
            local pinned = goal.tracked and trackerVisible
            row.track.caption:SetText(pinned and L["Скрыть"] or (goal.earned and L["Готово"] or L["Отследить"]))
            row.track:SetEnabled(not goal.earned or pinned)
            setChoice(row.track, pinned)
            if expanded then detail.goal = goal end
        end
    end
    pane.progress:SetText(("%d/%d"):format(earned, #visible))
    pane.deadline:SetText(reset and (L["Сброс "] .. date("%d.%m  %H:%M", reset)) or "")
    detail:SetShown(detail.goal ~= nil)
    pane.help:SetShown(detail.goal == nil and not pane.activity)
    if pane.activity then
        pane.activity:SetShown(detail.goal == nil)
        if detail.goal == nil then updateActivity(pane.activity, demo) end
    end
    if detail.goal then
        detail.description:SetText(detail.goal.description)
    else
        local tracked = trackerVisible and note.GetTrackedHuntGoal(demo)
        pane.help:SetText(tracked and (L["Трекер: "] .. tracked.name) or "")
    end
end

local function buildArchive(parent)
    local pane = CreateFrame("Frame", nil, parent)
    pane:SetAllPoints()
    local history = panel(pane, 0, 0, 269, panelHeight)
    label(history, "GameFontNormalLarge", 16, -16, 230, gold):SetText(L["Недельные итоги"])
    history.hint = label(history, "GameFontHighlightSmall", 16, -44, 232, muted)
    history.hint:SetWordWrap(true)
    history.rows = {}
    for i = 1, 5 do
        local row = textButton(history, "", 15, -69 - (i - 1) * 44, 237, function(self)
            pane.selected = self.week.start
            refresh()
        end)
        row:SetHeight(37)
        row.caption:ClearAllPoints()
        row.caption:SetPoint("TOPLEFT", 12, -10)
        row.caption:SetWidth(140)
        row.caption:SetJustifyH("LEFT")
        row.reward = label(row, "GameFontHighlightSmall", 144, -12, 80, muted)
        row.reward:SetJustifyH("RIGHT")
        history.rows[i] = row
    end
    history.back = button(history, "", 15, -309, 27, function()
        pane.page = math.max(1, pane.page - 1)
        refresh()
    end)
    history.page = label(history, "GameFontHighlightSmall", 47, -316, 49, warm)
    history.page:SetJustifyH("CENTER")
    history.forward = button(history, "", 100, -309, 27, function()
        pane.page = pane.page + 1
        refresh()
    end)
    note.StylePageButton(history.back, "prev")
    note.StylePageButton(history.forward, "next")
    actionHint(history.back, "Назад")
    actionHint(history.forward, "Далее")
    history.all = button(history, L["Открыть все"], 142, -309, 111, function()
        note.OpenAllRecords({
            title = L["Недельные итоги"],
            rows = history.weeks,
            startIndex = (pane.page - 1) * 5 + 1,
            columns = { { label = L["Неделя"], weight = 2 },
                { label = L["Разные противники"], weight = 2.5, justify = "RIGHT" },
                { label = L["Реванши"], justify = "RIGHT" },
                { label = L["Получено печатей"], weight = 2, justify = "RIGHT" } },
            cells = function(week) return {
                weekLabel(week), week.uniqueVictims or 0, week.revenges or 0, week.seals or 0 } end,
            onSelect = function(week, index)
                pane.selected, pane.page = week.start, math.ceil(index / 5)
                refresh()
            end,
        })
    end)
    pane.history = history
    pane.page = 1

    local report = panel(pane, 281, 0, 461, panelHeight)
    stripe(report, 14, -12, 433, 2, gold, 0.64)
    report.period = label(report, "GameFontNormalLarge", 20, -26, 420, gold)
    report.scope = label(report, "GameFontHighlightSmall", 21, -49, 420, muted)
    report.victims = tile(report, L["Разные противники"], 20, 132)
    report.revenge = tile(report, L["Реванши"], 164, 132)
    report.seals = tile(report, L["Получено печатей"], 308, 132)
    for i, stat in ipairs({report.victims, report.revenge, report.seals}) do
        stat:ClearAllPoints()
        stat:SetPoint("TOPLEFT", 20 + (i - 1) * 144, -80)
        stat:SetHeight(62)
        stat.value:ClearAllPoints()
        stat.value:SetPoint("TOPLEFT", 4, -31)
    end
    label(report, "GameFontNormal", 21, -167, 350, gold):SetText(L["Самая активная зона"])
    report.zone = label(report, "GameFontHighlight", 21, -193, 400, warm)
    report.zoneFights = label(report, "GameFontHighlightSmall", 21, -215, 400, muted)
    stripe(report, 20, -242, 420, 1, gold, 0.19)
    report.contracts = label(report, "GameFontHighlight", 21, -264, 400, warm)
    report.description = label(report, "GameFontHighlightSmall", 21, -308, 419, muted)
    report.description:SetWordWrap(true)
    pane.report = report
    return pane
end

local function updateArchive(pane, current, oldWeeks)
    local history = pane.history
    local weeks = {}
    if current then weeks[1] = current end
    for _, old in ipairs(oldWeeks) do weeks[#weeks + 1] = old end
    history.weeks = weeks
    history.all:SetShown(#weeks > 0)
    local pageCount = math.max(1, math.ceil(#weeks / 5))
    pane.page = math.max(1, math.min(pane.page, pageCount))
    history.page:SetText(("%d / %d"):format(pane.page, pageCount))
    history.hint:SetText(#oldWeeks == 0 and L["Завершённые недели появятся здесь."] or L["Выберите неделю для просмотра."])
    history.back:SetEnabled(pane.page > 1)
    history.forward:SetEnabled(pane.page < pageCount)
    local selected = current
    for _, week in ipairs(weeks) do if week.start == pane.selected then selected = week end end
    for i, row in ipairs(history.rows) do
        local week = weeks[(pane.page - 1) * 5 + i]
        row.week = week
        row:SetShown(week ~= nil)
        if week then
            row.caption:SetText((week == current and L["Сейчас · "] or "") .. weekLabel(week))
            row.reward:SetText((L["%d печ."]):format(week.seals or 0))
            setChoice(row, selected == week)
        end
    end
    local report = pane.report
    if not selected then selected = {} end
    report.period:SetText(weekLabel(selected))
    report.scope:SetText(selected == current and L["Текущая неделя"] or L["Завершённая неделя"])
    report.victims.value:SetText(tostring(selected.uniqueVictims or 0))
    report.revenge.value:SetText(tostring(selected.revenges or 0))
    report.seals.value:SetText(tostring(selected.seals or 0))
    report.zone:SetText(note.SampleText(selected.busiestZone, board.demo) or L["Нет записей по зонам"])
    report.zoneFights:SetText(selected.zoneFights and selected.zoneFights > 0
        and (L["Боёв в зоне: %d"]):format(selected.zoneFights) or "")
    report.contracts:SetText((L["Выполнено личных целей: %d"]):format(selected.contracts or 0))
    report.description:SetText(selected == current and L["Итог сохранится после недельного сброса."]
        or L["Итог сохранён в архиве персонажа."])
end

local kindLabels = { cover = "Обложка", title = "Титул", stamp = "Штамп" }
local kinds = { "cover", "title", "stamp" }

local function buildCollection(parent)
    local pane = panel(parent, 0, 0, 742, panelHeight)
    label(pane, "GameFontNormalLarge", 17, -17, 490, gold):SetText(L["Коллекция охотника"])
    pane.summary = label(pane, "GameFontHighlightSmall", 519, -21, 202, muted)
    pane.summary:SetJustifyH("RIGHT")
    local narrative = label(pane, "GameFontHighlightSmall", 18, -44, 688, warm)
    narrative:SetText(L["Печати открывают обложки и титулы. Отметки о реванше остаются в досье."])
    stripe(pane, 17, -61, 706, 1, gold, 0.24)
    pane.tiles = {}
    for i = 1, 6 do
        local x = 17 + ((i - 1) % 2) * 358
        local y = -75 - math.floor((i - 1) / 2) * 76
        local item = panel(pane, x, y, 348, 68, raised)
        item.swatch = stripe(item, 9, -10, 32, 48, gold, 0.72)
        local emblem = artwork(item, 13, -22, 24, 24)
        emblem:SetTexture("Interface\\Icons\\INV_Misc_Note_03")
        item.kind = label(item, "GameFontHighlightSmall", 52, -9, 195, muted)
        item.name = label(item, "GameFontNormal", 52, -23, 201, gold)
        item.requirement = label(item, "GameFontHighlightSmall", 52, -49, 281, warm)
        item.apply = button(item, L["Применить"], 248, -22, 89, function()
            if item.cosmetic and note.SelectHuntCosmetic(item.cosmetic.id, board.demo) then
                call("skinChanged", board.demo)
                refresh()
            end
        end)
        item:EnableMouse(true)
        item:SetScript("OnEnter", function(self)
            local cosmetic = self.cosmetic
            if not cosmetic or not GameTooltip then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(cosmetic.name, unpack(gold))
            if cosmetic.description then GameTooltip:AddLine(cosmetic.description, 0.91, 0.87, 0.76, true) end
            note.StyleLocaleTooltip(GameTooltip)
            GameTooltip:Show()
        end)
        item:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
        pane.tiles[i] = item
    end
    pane.back = button(pane, "", 292, -309, 28, function()
        pane.page = math.max(1, pane.page - 1)
        refresh()
    end)
    pane.pageLabel = label(pane, "GameFontHighlightSmall", 337, -316, 68, warm)
    pane.pageLabel:SetJustifyH("CENTER")
    pane.forward = button(pane, "", 412, -309, 28, function()
        pane.page = pane.page + 1
        refresh()
    end)
    note.StylePageButton(pane.back, "prev")
    note.StylePageButton(pane.forward, "next")
    pane.page = 1
    return pane
end

local function updateCollection(pane, cosmetics)
    local ordered, unlocked = {}, 0
    for _, kind in ipairs(kinds) do
        for _, row in ipairs(cosmetics) do
            if row.kind == kind then
                ordered[#ordered + 1] = row
                if row.unlocked then unlocked = unlocked + 1 end
            end
        end
    end
    local pageCount = math.max(1, math.ceil(#ordered / 6))
    pane.page = math.max(1, math.min(pane.page, pageCount))
    pane.summary:SetText((L["Открыто: %d / %d"]):format(unlocked, #ordered))
    pane.pageLabel:SetText(("%d / %d"):format(pane.page, pageCount))
    pane.back:SetEnabled(pane.page > 1)
    pane.forward:SetEnabled(pane.page < pageCount)
    for i, tileFrame in ipairs(pane.tiles) do
        local item = ordered[(pane.page - 1) * 6 + i]
        tileFrame.cosmetic = item
        tileFrame:SetShown(item ~= nil)
        if item then
            local tint = palette(item)
            tileFrame.swatch:SetColorTexture(tint[1], tint[2], tint[3], item.unlocked and 0.8 or 0.28)
            tileFrame:SetBackdropBorderColor(item.selected and gold[1] or tint[1] * 0.6,
                item.selected and gold[2] or tint[2] * 0.6, item.selected and gold[3] or tint[3] * 0.6, 1)
            tileFrame.kind:SetText(L[kindLabels[item.kind]] or "")
            tileFrame.name:SetText(item.name)
            local requirement = item.requirement
            if type(requirement) == "number" then requirement = (L["%d печатей"]):format(requirement) end
            tileFrame.requirement:SetText(item.unlocked and (item.kind == "stamp" and L["Получен"] or L["Открыто"])
                or requirement or L["Пока недоступно"])
            tileFrame.apply:SetShown(item.kind ~= "stamp")
            tileFrame.apply:SetText(item.selected and L["Выбрано"] or (item.unlocked and L["Применить"] or L["Закрыто"]))
            tileFrame.apply:SetEnabled(item.unlocked and not item.selected)
        end
    end
end

local guildHuntStatus = {
    active = { label = "Активна", color = gold },
    completed = { label = "Завершена", color = green },
    cancelled = { label = "Отменена", color = red },
    expired = { label = "Истекла", color = muted },
}

local function buildGuildHuntBoard(parent)
    local pane = panel(parent, 0, 0, 742, panelHeight, steel)
    pane.page = 1
    pane.title = label(pane, "GameFontNormalLarge", 18, -14, 450, gold)
    pane.target = label(pane, "GameFontNormal", 18, -46, 465, warm)
    pane.own = label(pane, "GameFontHighlightSmall", 18, -69, 690, muted)
    pane.share = textButton(pane, L["Поделиться целью"], 488, -42, 237, function()
        note.ToggleSharedHunt(board.demo)
        refresh()
    end, 30, true)
    pane.update = textButton(pane, L["Обновить"], 607, -10, 118, function()
        note.RequestGuildHunts()
        refresh()
    end, 27)
    stripe(pane, 16, -91, 710, 1, edge)
    label(pane, "GameFontNormal", 20, -101, 208, gold):SetText(L["Охотник"])
    label(pane, "GameFontNormal", 250, -101, 260, gold):SetText(L["Цель"])
    pane.rows = {}
    for i = 1, 6 do
        local row = CreateFrame("Button", nil, pane)
        row:SetSize(708, 26)
        row:SetPoint("TOPLEFT", 17, -122 - (i - 1) * 28)
        if i % 2 == 1 then stripe(row, 0, 0, 708, 26, raised, 0.82) end
        row:SetHighlightTexture("Interface\\Buttons\\UI-Listbox-Highlight2")
        row.author = label(row, "GameFontHighlight", 4, -6, 215, warm)
        row.target = label(row, "GameFontHighlight", 233, -6, 260, warm)
        row.relay = label(row, "GameFontHighlightSmall", 503, -7, 94, muted)
        row.status = label(row, "GameFontHighlight", 604, -6, 98)
        row.status:SetJustifyH("RIGHT")
        row:SetScript("OnClick", function(self)
            if self.data then note.OpenDossier(self.data.target, board.demo, { name = self.data.name }) end
        end)
        pane.rows[i] = row
    end
    pane.empty = label(pane, "GameFontHighlight", 20, -134, 685, muted)
    pane.empty:SetText(L["Нет объявленных целей."])
    pane.back = textButton(pane, L["Назад"], 16, -313, 104, function()
        pane.page = pane.page - 1
        refresh()
    end, 26)
    pane.pager = label(pane, "GameFontHighlightSmall", 299, -321, 144, muted)
    pane.pager:SetJustifyH("CENTER")
    pane.next = textButton(pane, L["Далее"], 620, -313, 104, function()
        pane.page = pane.page + 1
        refresh()
    end, 26)
    pane.all = button(pane, L["Открыть все"], 536, -313, 128, function()
        note.OpenAllRecords({
            title = L["Общая охота"],
            rows = pane.entries,
            startIndex = (pane.page - 1) * #pane.rows + 1,
            columns = { { label = L["Охотник"], weight = 3 }, { label = L["Цель"], weight = 3 },
                { label = L["Статус"], weight = 2, justify = "RIGHT" } },
            cells = function(entry)
                local status = guildHuntStatus[entry.status]
                return { entry.author, entry.name, { text = L[status.label], color = status.color } }
            end,
            onSelect = function(entry) note.OpenDossier(entry.target, board.demo, { name = entry.name }) end,
        })
    end)
    if note.StylePageButton then
        pane.back:SetWidth(31)
        pane.next:ClearAllPoints()
        pane.next:SetPoint("TOPLEFT", 693, -313)
        pane.next:SetWidth(31)
        note.StylePageButton(pane.back, "prev")
        note.StylePageButton(pane.next, "next")
        pane.back.caption:Hide()
        pane.next.caption:Hide()
        actionHint(pane.back, "Назад")
        actionHint(pane.next, "Далее")
    end
    pane:Hide()
    return pane
end

local function updateGuildHuntBoard(demo, now)
    local pane = board.guildHunts
    local rows, own, enabled, inGuild = note.GuildHuntList(demo)
    pane.entries = rows
    pane.all:SetShown(#rows > 0)
    local target = note.GetHuntTarget(demo, now)
    local canShare = target and not target.completed and not target.expired
    local sharing = own and own.status == "active" and own.expires >= now
    pane.title:SetText(L[demo and "Общая охота · тестовые данные" or "Общая охота"])
    pane.target:SetText(target and L["Личная цель: %s"]:format(target.name) or L["Цель не выбрана"])
    local hint
    if not demo and not inGuild then
        hint = L["Общая охота доступна только в гильдии."]
    elseif not demo and not enabled then
        hint = L["Для общей охоты включите обмен с гильдией."]
    elseif own then
        local status = own.status == "active" and own.expires < now and "expired" or own.status
        hint = L["Ваша общая цель: %s · %s"]:format(own.name or note.Name(own.target), L[guildHuntStatus[status].label])
    end
    pane.own:SetText(hint or "")
    pane.share:SetEnabled(enabled and (sharing or canShare) and true or false)
    pane.share.caption:SetText(L[sharing and "Отменить общую цель" or "Поделиться целью"])
    pane.update:SetEnabled(enabled and true or false)
    local pageSize = #pane.rows
    local pages = math.max(1, math.ceil(#rows / pageSize))
    pane.page = math.max(1, math.min(pages, pane.page))
    pane.pager:SetText(("%d / %d"):format(pane.page, pages))
    pane.back:SetEnabled(pane.page > 1)
    pane.next:SetEnabled(pane.page < pages)
    pane.back:SetShown(pages > 1)
    pane.next:SetShown(pages > 1)
    pane.pager:SetShown(pages > 1)
    pane.empty:SetShown(#rows == 0)
    for i, row in ipairs(pane.rows) do
        local entry = rows[i + (pane.page - 1) * pageSize]
        row.data = entry
        row:SetShown(entry ~= nil)
        if entry then
            local status = guildHuntStatus[entry.status]
            row.author:SetText(entry.author)
            row.target:SetText(entry.name)
            row.relay:SetText(entry.relay and L["Из кэша"] or "")
            row.status:SetText(L[status.label])
            row.status:SetTextColor(unpack(status.color))
        end
    end
    pane.refreshAt = now + 10
end

function note.RefreshGuildHunts()
    if board and board:IsVisible() and board.tab == "guildHunts" then
        updateGuildHuntBoard(board.demo, GetServerTime())
    end
end

local function openGuildHunts()
    board.tab = "guildHunts"
    refresh()
    if not board.demo then note.RequestGuildHunts() end
end

function note.OpenGuildHuntBoard()
    note.OpenWindow("hunt")
    if board then openGuildHunts() end
end

function note.BuildHuntBoard(parent, actions)
    board = CreateFrame("Frame", nil, parent)
    board:SetSize(742, 400)
    board:SetPoint("TOPLEFT", 24, -116)
    board:SetFrameLevel(parent:GetFrameLevel() + 3)
    board.actions = actions or {}
    board.tab = "hunt"

    local well = CreateFrame("Frame", nil, board)
    well:SetPoint("TOPLEFT", 0, 0)
    well:SetSize(742, panelHeight)
    board.today = CreateFrame("Frame", nil, well)
    board.today:SetAllPoints()
    board.hero = buildHero(board.today)
    board.goals = buildGoals(board.today)
    board.archive = buildArchive(well)
    board.collection = buildCollection(well)
    board.guildHunts = buildGuildHuntBoard(well)
    local footer = CreateFrame("Frame", nil, board)
    footer:SetPoint("TOPLEFT", 0, -361)
    footer:SetSize(742, 33)
    local shortcuts = CreateFrame("Frame", nil, footer)
    shortcuts:SetAllPoints()
    textButton(shortcuts, L["Рядом"], 0, 0, 91, openNearby, 31)
    textButton(shortcuts, L["Карта"], 101, 0, 89, function()
        openMap(board.hero.latest.entry)
    end, 31)
    if note.OpenSortie and not refined() then
        textButton(shortcuts, L["Вылазки"], 200, 0, 116, function() note.OpenSortie(board.demo) end, 31)
    end
    board.shortcuts = shortcuts
    board.back = textButton(footer, L["Назад"], 0, 0, 113, function()
        board.tab = "hunt"
        refresh()
    end, 31)
    textButton(shortcuts, L["Фронт недели"], refined() and 200 or 325, 0, 173, note.OpenFront, 31, not refined())
    local seal = artwork(footer, 128, -5, 21, 21)
    seal:SetTexture("Interface\\Icons\\INV_Misc_Rune_08")
    board.seal = seal
    board.balance = label(footer, "GameFontNormal", 155, -7, 151, gold)
    if refined() then
        textButton(footer, L["Ещё"] .. "  +", 592, 0, 150, function(self)
            local function openTab(tab)
                board.tab = tab
                refresh()
            end
            local entries = {
                { L["Архив недель"], function() openTab("archive") end },
                { L["Коллекция"], function() openTab("collection") end },
                { L["Общая охота"], openGuildHunts },
            }
            if note.OpenSortie then
                entries[#entries + 1] = { L["Вылазки"], function() note.OpenSortie(board.demo) end }
            end
            note.WarTable.ShowMenu(self, entries)
        end, 31)
    else
        textButton(footer, L["Архив и коллекция"] .. "  +", 525, 0, 217, function(self)
            if not MenuUtil or not MenuUtil.CreateContextMenu then
                board.tab = ({ hunt = "archive", archive = "collection", collection = "guildHunts" })[board.tab] or "archive"
                refresh()
                return
            end
            MenuUtil.CreateContextMenu(self, function(_, root)
                note.StyleLocaleMenu(root:CreateRadio(L["Архив недель"], function() return board.tab == "archive" end,
                    function() board.tab = "archive"; refresh() end))
                note.StyleLocaleMenu(root:CreateRadio(L["Коллекция"], function() return board.tab == "collection" end,
                    function() board.tab = "collection"; refresh() end))
                note.StyleLocaleMenu(root:CreateRadio(L["Общая охота"], function() return board.tab == "guildHunts" end,
                    openGuildHunts))
            end)
        end, 31)
    end
    local elapsed = 0
    board:SetScript("OnUpdate", function(self, delta)
        elapsed = elapsed + delta
        if elapsed < 1 then return end
        elapsed = 0
        if self.tab == "guildHunts" then
            if GetServerTime() >= (self.guildHunts.refreshAt or 0) then note.RefreshGuildHunts() end
            return
        end
        if self.tab ~= "hunt" then return end
        local hero = self.hero
        if hero.target and not self.rivalView then
            local now = GetServerTime()
            if not hero.target.completed and hero.target.expires and hero.target.expires < now and not hero.target.expired then
                refresh()
                return
            end
            updateSighting(hero, self.demo)
            if not hero.target.completed and hero.target.expires then
                hero.timer.value:SetText(note.HuntTimeRemaining(hero.target.expires, now))
            end
        end
    end)
    board:Hide()
    return board
end

function note.RefreshHuntBoard(demo)
    if not board then return end
    if board.demo ~= demo then
        board.archive.selected, board.archive.page, board.collection.page = nil, 1, 1
        board.guildHunts.page = 1
        board.rivalView, board.rivalPage = nil, 1
        board.goals.expanded = nil
        board.hero.feedback:SetText("")
    end
    board.demo = demo
    local now = GetServerTime()
    local goals, seals, reset, weekly = note.HuntOverview(demo, now)
    board.balance:SetText((L["Печати: %d"]):format(seals or 0))
    board.today:SetShown(board.tab == "hunt")
    board.archive:SetShown(board.tab == "archive")
    board.collection:SetShown(board.tab == "collection")
    board.guildHunts:SetShown(board.tab == "guildHunts")
    board.shortcuts:SetShown(board.tab == "hunt")
    board.back:SetShown(board.tab ~= "hunt")
    board.balance:SetShown(board.tab ~= "hunt")
    board.seal:SetShown(board.tab ~= "hunt")
    if board.tab == "hunt" then
        local style = note.GetHuntStyle and note.GetHuntStyle(demo) or {}
        updateHero(board.hero, demo, now, style.cover)
        updateGoals(board.goals, goals, reset, demo)
    elseif board.tab == "archive" then
        updateArchive(board.archive, weekly, note.HuntArchive(demo, now))
    elseif board.tab == "guildHunts" then
        updateGuildHuntBoard(demo, now)
    else
        updateCollection(board.collection, note.HuntCollection(demo))
    end
end
