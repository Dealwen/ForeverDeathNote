local _, note = ...
local L = note.L

local window, currentDemo, selectedEntry
local regen, pendingEntry
local killNotice
local noticeLife, impactDuration = 6, 0.78
local killIconSize = 22
local killSparks = { { -11, 9 }, { -10, -8 }, { 6, 13 }, { 12, -9 }, { 15, 7 } }
local empty = {}
local questionIcon = "Interface\\Icons\\INV_Misc_QuestionMark"
local sourceNames = {
    own = "Личный журнал", guild = "Гильдейский обмен", imported = "Ручной импорт",
}

local function latestEvent(dataset)
    local latest
    for _, entry in ipairs(dataset.events) do
        if (entry.kind == "K" or entry.kind == "D") and entry.at and (not latest or entry.at >= latest.at) then
            latest = entry
        end
    end
    return latest
end

local function containsEvent(dataset, entry)
    for _, item in ipairs(dataset.events) do
        if item == entry then return true end
    end
    return false
end

local function combatant(dataset, id, name, class, guild, level)
    local profile = dataset.profiles[id] or empty
    if guild == nil then guild = profile.guild end
    return {
        id = id, name = name or profile.name or L["Имя неизвестно"],
        class = class or profile.class, guild = guild, level = level,
        race = profile.race, raceFile = profile.raceFile, sex = profile.sex,
    }
end

local function describeFight(entry, demo)
    local dataset = demo or note.db
    local owner = demo and "self" or note.owner
    local winner, victim, source, headline
    if entry.other then
        local lost = entry.kind == "D"
        local winnerId = lost and entry.other or owner
        local victimId = lost and owner or entry.other
        local winnerLevel = entry.killerLevel
        if not lost then winnerLevel = winnerLevel or entry.actorLevel end
        local victimLevel = entry.victimLevel
        if lost then victimLevel = victimLevel or entry.actorLevel end
        local winnerGuild, victimGuild = entry.killerGuild, entry.victimGuild
        if winnerGuild == nil and not lost then winnerGuild = entry.ownerGuild end
        if victimGuild == nil and lost then victimGuild = entry.ownerGuild end
        winner = combatant(dataset, winnerId, entry.killerName, entry.killerClass, winnerGuild, winnerLevel)
        victim = combatant(dataset, victimId, entry.victimName, entry.victimClass, victimGuild, victimLevel)
        source = L[sourceNames.own]
        headline = lost and L["Вас убили"] or L["Вы добили противника"]
    else
        winner = combatant(dataset, entry.killer, entry.killerName, entry.killerClass,
            entry.killerGuild, entry.killerLevel)
        victim = combatant(dataset, entry.victim, entry.victimName, entry.victimClass,
            entry.victimGuild, entry.victimLevel)
        local origin = entry.source or (entry.receivedGuild and "guild" or nil)
        source = L[sourceNames[origin]] or L["Источник неизвестен"]
        headline = L["Столкновение в открытом мире"]
    end
    local target = winner.id == owner and victim or winner
    return winner, victim, target, source, headline
end

local function label(parent, font, x, y, width)
    local value = note.CreateFontString(parent, nil, "OVERLAY", font)
    value:SetPoint("TOPLEFT", x, y)
    value:SetWidth(width)
    value:SetJustifyH("LEFT")
    return value
end

local function panel(parent, x, y, width, height, color, paper)
    local frame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    frame:SetPoint("TOPLEFT", x, y)
    frame:SetSize(width, height)
    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 10, insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    if paper then
        frame:SetBackdropColor(0.86, 0.75, 0.57, 1)
    else
        frame:SetBackdropColor(0.08, 0.065, 0.052, 0.91)
    end
    frame:SetBackdropBorderColor(color[1], color[2], color[3], 0.8)
    return frame
end

local function characterCard(parent, x, role, color, field)
    local width = field and 303 or 267
    local card = panel(parent, x, -8, width, field and 102 or 91, color)
    local icon = card:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT", 12, -32)
    local size = field and 49 or 40
    icon:SetSize(size, size)
    card.icon = icon
    if field then
        card.race = card:CreateTexture(nil, "ARTWORK")
        card.class = card:CreateTexture(nil, "OVERLAY")
        card.class:SetSize(17, 17)
        card.class:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 4, -2)
    end
    local heading = label(card, "GameFontNormalSmall", 12, -10, 243)
    heading:SetText(role)
    heading:SetTextColor(color[1], color[2], color[3])
    local textX = field and 73 or 62
    local textWidth = width - textX - 12
    card.name = label(card, field and "GameFontNormal" or "GameFontHighlight", textX, field and -33 or -24, textWidth)
    if field then card.name:SetTextColor(0.98, 0.92, 0.81) end
    card.details = label(card, "GameFontHighlightSmall", textX, field and -54 or -49, textWidth)
    card.guild = label(card, "GameFontHighlightSmall", textX, field and -73 or -67, textWidth)
    card.guild:SetTextColor(0.74, 0.68, 0.58)
    card.name:SetWordWrap(false)
    card.details:SetWordWrap(false)
    card.guild:SetWordWrap(false)
    return card
end

local function setClassIcon(icon, class)
    local atlas = class and "classicon-" .. class:lower()
    if atlas and C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas) then
        icon:SetAtlas(atlas)
        return
    end
    local coords = CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[class]
    if coords then
        icon:SetTexture("Interface\\Glues\\CharacterCreate\\UI-CharacterCreate-Classes")
        icon:SetTexCoord(unpack(coords))
    else
        icon:SetTexture(questionIcon)
        icon:SetTexCoord(0, 1, 0, 1)
    end
end

local function showCharacter(card, character)
    if card.race and note.SetCharacterArt then
        note.SetCharacterArt(card.icon, card.race, card.class, not currentDemo and character.id or nil, character)
    else
        setClassIcon(card.icon, character.class)
    end
    local class = note.ClassLabel(character.class, character.sex) or L["Класс неизвестен"]
    local level = note.PositiveInteger(character.level, 255)
    card.name:SetText(character.name)
    card.details:SetText(class .. "  •  " .. (level and (L["Ур. "] .. level) or L["Ур. неизвестен"]))
    card.guild:SetText(character.guild or (character.guild == false and L["Без гильдии"] or L["Гильдия неизвестна"]))
end

local function spellTexture(id, name)
    if (id or name) and C_Spell and C_Spell.GetSpellTexture then
        local texture = note.Public(C_Spell.GetSpellTexture(id or name))
        if texture and texture ~= 0 then return texture end
    end
    return name == L["Автоатака"] and "Interface\\Icons\\Ability_MeleeDamage" or questionIcon
end

local function tooltipStrike(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    if not currentDemo and self.spellId and GameTooltip.SetSpellByID then
        local ok = pcall(GameTooltip.SetSpellByID, GameTooltip, self.spellId)
        if ok and GameTooltip:IsShown() then return end
    end
    if self.spellName then
        GameTooltip:SetText(self.spellName)
    elseif self.spellId then
        GameTooltip:SetText(L["Способность #"] .. self.spellId)
    else
        GameTooltip:SetText(L["Последний удар не записан"])
        GameTooltip:AddLine(L["Клиент не передал способность для этого события."], 1, 1, 1, true)
    end
    note.StyleLocaleTooltip(GameTooltip)
    GameTooltip:Show()
end

local function build()
    local frame = CreateFrame("Frame", "ForeverDeathNoteFightReport", UIParent, "BackdropTemplate")
    frame.field = note.FieldJournal and note.FieldJournal.Enabled()
    local width, height = frame.field and 654 or 586, frame.field and 342 or 306
    frame.fullHeight = height
    frame:SetSize(width, height)
    frame:SetPoint("CENTER", 12, -9)
    frame:SetScale(math.min(1, UIParent:GetWidth() / (width + 20), UIParent:GetHeight() / (height + 20)))
    frame:SetFrameStrata("DIALOG")
    frame:SetFrameLevel(26)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border", edgeSize = 28,
        insets = { left = 7, right = 7, top = 7, bottom = 7 },
    })
    if frame.field then
        frame:SetBackdropColor(0.25, 0.17, 0.12, 1)
        frame:SetBackdropBorderColor(0.70, 0.51, 0.29, 1)
    else
        frame:SetBackdropColor(0.70, 0.60, 0.49, 1)
        frame:SetBackdropBorderColor(0.88, 0.72, 0.53, 1)
    end
    frame:Hide()
    tinsert(UISpecialFrames, "ForeverDeathNoteFightReport")

    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -4, -4)
    close:SetScript("OnClick", function() frame:Hide() end)
    local book = frame:CreateTexture(nil, "ARTWORK")
    book:SetPoint("TOPLEFT", 18, -18)
    book:SetSize(31, 31)
    book:SetTexture("Interface\\Icons\\INV_Misc_Book_09")
    local field = frame.field
    local header = label(frame, field and "GameFontHighlightSmall" or "GameFontNormalLarge", 59, field and -43 or -17, 328)
    header:SetText(L["Разбор боя"])
    if field then header:SetTextColor(0.80, 0.70, 0.58) end
    frame.headline = label(frame, field and "GameFontNormalLarge" or "GameFontHighlightSmall", 59, field and -18 or -38, width - 100)
    frame.message = label(frame, field and "GameFontHighlight" or "GameFontDisable", 22, -76, width - 44)
    local lineY = field and -65 or -58
    local line = frame:CreateTexture(nil, "ARTWORK")
    line:SetPoint("TOPLEFT", 17, lineY)
    line:SetPoint("TOPRIGHT", -17, lineY)
    line:SetHeight(1)
    line:SetColorTexture(0.76, 0.50, 0.27, 0.66)

    local card = CreateFrame("Frame", nil, frame)
    card:SetPoint("TOPLEFT", 17, lineY - 3)
    card:SetSize(width - 34, field and 253 or 222)
    frame.card = card
    card.winner = characterCard(card, 0, L["Нанёс добивающий удар"], { 0.94, 0.70, 0.35 }, field)
    card.victim = characterCard(card, field and 317 or 285, L["Пал в бою"], { 0.82, 0.48, 0.45 }, field)

    local strike = panel(card, 0, field and -120 or -109, field and 264 or 219, field and 90 or 79,
        { 0.60, 0.45, 0.28 }, field)
    local spell = CreateFrame("Frame", nil, strike)
    local spellSize = field and 53 or 43
    spell:SetSize(spellSize, spellSize)
    spell:SetPoint("TOPLEFT", 11, -17)
    spell:EnableMouse(true)
    spell:SetScript("OnEnter", tooltipStrike)
    spell:SetScript("OnLeave", function() GameTooltip:Hide() end)
    spell.icon = spell:CreateTexture(nil, "ARTWORK")
    spell.icon:SetAllPoints()
    spell.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    card.spell = spell
    local strikeTitle = label(strike, "GameFontNormalSmall", field and 76 or 62, -18, field and 174 or 147)
    strikeTitle:SetText(L["Последний удар"])
    card.spellName = label(strike, field and "GameFontNormal" or "GameFontHighlight", field and 76 or 62, -36, field and 174 or 147)

    local record = panel(card, field and 276 or 231, field and -120 or -109, field and 344 or 321, field and 90 or 79,
        { 0.60, 0.45, 0.28 }, field)
    card.when = label(record, "GameFontNormalSmall", 12, field and -56 or -12, field and 318 or 295)
    card.where = label(record, field and "GameFontNormal" or "GameFontHighlightSmall", 12, field and -13 or -30, field and 318 or 295)
    if field then
        for _, text in ipairs({ strikeTitle, card.spellName, card.when, card.where }) do
            text:SetTextColor(0.24, 0.15, 0.092)
            text:SetShadowColor(0, 0, 0, 0)
        end
        card.where:SetMaxLines(2)
        card.spellName:SetMaxLines(2)
        card.map = CreateFrame("Button", nil, card, "UIPanelButtonTemplate")
        note.StyleLocaleButton(card.map)
        card.map:SetPoint("TOPRIGHT", -194, -224)
        card.map:SetSize(112, 28)
        card.map:SetText(L["Карта"])
        card.map:SetScript("OnClick", function()
            if card.entry and note.OpenFightMap then
                frame:Hide()
                note.OpenFightMap(currentDemo, card.entry)
            end
        end)
    end

    card.source = label(card, "GameFontHighlightSmall", 3, field and -231 or -204, field and 280 or 334)
    card.source:SetTextColor(0.83, 0.77, 0.63)
    card.dossier = CreateFrame("Button", nil, card, "UIPanelButtonTemplate")
    note.StyleLocaleButton(card.dossier)
    card.dossier:SetPoint("TOPRIGHT", -1, field and -224 or -196)
    card.dossier:SetSize(185, field and 28 or 25)
    card.dossier:SetScript("OnClick", function()
        local subject = card.subject
        if subject then
            frame:Hide()
            note.OpenDossier(subject.id, currentDemo, subject)
        end
    end)
    frame:SetScript("OnHide", function()
        if GameTooltip:IsOwned(spell) then GameTooltip:Hide() end
    end)
    note.ManageWindow(frame, "recap", note.WindowDragHandle(frame, field and 52 or 44, width - 66))
    return frame
end

local function refresh()
    local dataset = currentDemo or note.db
    local entry = selectedEntry or latestEvent(dataset)
    window.card:SetShown(entry ~= nil)
    window.message:SetShown(entry == nil)
    window:SetHeight(entry and window.fullHeight or 112)
    if not entry then
        window.headline:SetText(currentDemo and L["Тестовый режим"] or L["Открытый мир"])
        window.message:SetText(L["В журнале пока нет записанных боёв."])
        return
    end

    local winner, victim, subject, source, headline = describeFight(entry, currentDemo)
    local card = window.card
    showCharacter(card.winner, winner)
    showCharacter(card.victim, victim)
    window.headline:SetText(headline)
    if window.field then
        window.headline:SetTextColor(unpack(entry.other and entry.kind == "D"
            and { 1, 0.64, 0.52 } or { 1, 0.84, 0.50 }))
    end
    card.when:SetText(entry.at and date("%d.%m.%Y  •  %H:%M", entry.at) or L["Время неизвестно"])
    local where = note.SampleText(entry.zone, currentDemo) or L["Место неизвестно"]
    if entry.subzone and entry.subzone ~= entry.zone then where = where .. "  •  " .. note.SampleText(entry.subzone, currentDemo) end
    if entry.x and entry.y then where = where .. ("  (%.1f, %.1f)"):format(entry.x, entry.y) end
    card.where:SetText(where)
    card.source:SetText((currentDemo and L["ТЕСТ  •  "] or L["Источник  •  "]) .. source)
    local strike = note.KillingBlow(entry, currentDemo)
    local name = note.SpellName(strike.spellId, strike.spellName, currentDemo)
    card.spell.spellId, card.spell.spellName = strike.spellId, name
    card.spell.icon:SetTexture(spellTexture(strike.spellId, name))
    card.spellName:SetText(name or (strike.spellId and L["Способность #"] .. strike.spellId) or L["Не записан"])
    card.subject = subject
    if card.map then
        local coords = type(entry.x) == "number" and type(entry.y) == "number"
            and entry.x >= 0 and entry.x <= 100 and entry.y >= 0 and entry.y <= 100
        card.entry = entry
        card.map:SetShown(note.OpenFightMap ~= nil and entry.other ~= nil and coords)
    end
    card.dossier:SetShown(subject.id ~= nil and note.OpenDossier ~= nil
        and (not currentDemo or currentDemo.profiles[subject.id] ~= nil))
    card.dossier:SetText(entry.other and L["Досье противника"] or L["Досье персонажа"])
end

function note.OpenFightReport(demo, entry)
    if not note.db then return end
    if not window then window = build() end
    currentDemo, selectedEntry = demo, entry
    refresh()
    window:Show()
    window:Raise()
end

function note.RefreshFightReport()
    if pendingEntry and not containsEvent(note.db, pendingEntry) then pendingEntry = nil end
    if not window or not window:IsShown() then return end
    if selectedEntry and selectedEntry.other and not containsEvent(currentDemo or note.db, selectedEntry) then
        selectedEntry = nil
    end
    refresh()
end

function note.UpdateFightReportDemo(demo)
    if demo then pendingEntry = nil end
    if not window or not window:IsShown() or currentDemo == demo then return end
    currentDemo, selectedEntry = demo, nil
    refresh()
end

local function autoEnabled()
    return note.db and note.db.autoFightReport == true
end

local function placeKillNotice(frame)
    local milestone, wanted = ForeverDeathNoteRampageMilestone, ForeverDeathNoteRampage
    local anchor = milestone and milestone:IsVisible() and milestone or wanted and wanted:IsVisible() and wanted or false
    if frame.lastAnchor == anchor then return end
    frame.lastAnchor = anchor
    frame:ClearAllPoints()
    if anchor then
        frame:SetPoint("TOP", anchor, "BOTTOM", 0, -8)
    else
        frame:SetPoint("TOP", UIParent, "TOP", 0, -142)
    end
end

local function finishKillImpact(frame)
    frame.impactAge = nil
    if frame.procAnimation then
        frame.procAnimation:Stop()
        frame.procBurst:Hide()
    end
    frame.glow:Hide()
    frame.ember:Hide()
    for _, spark in ipairs(frame.sparks) do spark:Hide() end
    frame.insignia:SetSize(killIconSize, killIconSize)
end

local function updateKillImpact(frame)
    local progress = math.min(1, frame.impactAge / impactDuration)
    if progress >= 1 then finishKillImpact(frame); return end
    local rise = math.min(1, progress * 10)
    local energy = (1 - progress) ^ 2
    local size = killIconSize + 5 * rise * energy
    frame.insignia:SetSize(size, size)
    local radius = 29 + 20 * (1 - energy)
    frame.glow:SetSize(radius, radius)
    frame.glow:SetAlpha(rise * energy * (frame.procAnimation and 0.46 or 0.95))
    frame.ember:SetPoint("TOPLEFT", 13 + 277 * (1 - energy), -30)
    frame.ember:SetAlpha(0.82 * rise * energy)
    for index, spark in ipairs(frame.sparks) do
        local ray = killSparks[index]
        local distance = 0.8 + 0.85 * (1 - energy)
        spark:SetPoint("CENTER", frame.insignia, "CENTER", ray[1] * distance, ray[2] * distance - 7 * progress ^ 2)
        spark:SetAlpha(rise * energy)
    end
end

local function addNativeKillBurst(frame)
    local atlas = "UI-HUD-ActionBar-Proc-Start-Flipbook"
    if not (C_Texture and C_Texture.GetAtlasInfo and note.Public(C_Texture.GetAtlasInfo(atlas))) then return end

    local burst = frame:CreateTexture(nil, "ARTWORK", nil, 1)
    burst:SetAtlas(atlas)
    burst:SetPoint("CENTER", frame.insignia)
    burst:SetSize(62, 62)
    burst:SetBlendMode("ADD")
    burst:SetVertexColor(1, 0.46, 0.20)
    burst:SetAlpha(0.65)
    frame.procBurst = burst

    local group = frame:CreateAnimationGroup()
    local flipbook = group:CreateAnimation("FlipBook")
    flipbook:SetChildKey("procBurst")
    flipbook:SetDuration(impactDuration)
    flipbook:SetFlipBookRows(6)
    flipbook:SetFlipBookColumns(5)
    flipbook:SetFlipBookFrames(30)
    flipbook:SetFlipBookFrameWidth(0)
    flipbook:SetFlipBookFrameHeight(0)
    frame.procAnimation = group
end

local function buildKillNotice()
    local frame = panel(UIParent, 0, 0, 352, 104, { 0.12, 0.073, 0.044 })
    frame:SetScale(math.min(1, (UIParent:GetWidth() - 20) / 352))
    frame:SetFrameStrata("HIGH")
    frame:SetClampedToScreen(true)
    local title = label(frame, "GameFontNormal", 43, -10, 270)
    title:SetTextColor(1, 0.80, 0.48)
    frame.title = title
    local insignia = frame:CreateTexture(nil, "ARTWORK", nil, 2)
    insignia:SetPoint("CENTER", frame, "TOPLEFT", 23, -17)
    insignia:SetSize(killIconSize, killIconSize)
    local texture = C_Spell and C_Spell.GetSpellTexture and note.Public(C_Spell.GetSpellTexture(18499))
    insignia:SetTexture(texture and texture ~= 0 and texture or "Interface\\Icons\\Spell_Nature_AncestralGuardian")
    frame.insignia = insignia
    local divider = frame:CreateTexture(nil, "BORDER")
    divider:SetPoint("TOPLEFT", 12, -30)
    divider:SetSize(327, 1)
    divider:SetColorTexture(0.43, 0.26, 0.13, 0.8)
    frame.glow = frame:CreateTexture(nil, "ARTWORK")
    frame.glow:SetPoint("CENTER", insignia)
    frame.glow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    frame.glow:SetBlendMode("ADD")
    frame.glow:SetVertexColor(1, 0.38, 0.11)
    frame.ember = frame:CreateTexture(nil, "OVERLAY")
    frame.ember:SetSize(43, 1)
    frame.ember:SetColorTexture(1, 0.62, 0.23, 1)
    frame.sparks = {}
    for index in ipairs(killSparks) do
        local spark = frame:CreateTexture(nil, "OVERLAY")
        spark:SetColorTexture(1, index % 2 == 0 and 0.44 or 0.73, 0.27, 1)
        spark:SetSize(2, 2)
        frame.sparks[index] = spark
    end
    addNativeKillBurst(frame)
    finishKillImpact(frame)
    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetSize(27, 27)
    close:SetPoint("TOPRIGHT", -2, -1)
    close:SetScript("OnClick", function() frame:Hide() end)
    frame.close = close

    label(frame, "GameFontHighlightSmall", 12, -34, 157):SetText(L["Добил"])
    label(frame, "GameFontHighlightSmall", 182, -34, 157):SetText(L["Погиб"])
    frame.winner = label(frame, "GameFontHighlight", 12, -48, 157)
    frame.victim = label(frame, "GameFontHighlight", 182, -48, 157)
    frame.winner:SetWordWrap(false)
    frame.victim:SetWordWrap(false)
    frame.when = label(frame, "GameFontHighlightSmall", 12, -70, 325)
    frame.where = label(frame, "GameFontHighlightSmall", 12, -86, 218)
    frame.where:SetWordWrap(false)
    frame.coords = label(frame, "GameFontHighlightSmall", 233, -86, 105)
    frame.coords:SetJustifyH("RIGHT")
    frame.coords:SetWordWrap(false)

    frame:SetScript("OnUpdate", function(self, elapsed)
        self.remaining = self.remaining - elapsed
        if self.remaining <= 0 then self:Hide(); return end
        placeKillNotice(self)
        if self.impactAge then
            self.impactAge = self.impactAge + elapsed
            updateKillImpact(self)
        end
        if self.fade and self.remaining < 0.16 then self:SetAlpha(self.remaining / 0.16) end
    end)
    frame:SetScript("OnHide", finishKillImpact)
    frame:Hide()
    return frame
end

local function showKillNotice(entry, preview)
    local winner, victim = describeFight(entry)
    killNotice = killNotice or buildKillNotice()
    local frame = killNotice
    frame.title:SetText(preview and (L["Добивание записано"] .. " / " .. L["Тестовый режим"]) or L["Добивание записано"])
    frame.winner:SetText(winner.name)
    frame.victim:SetText(victim.name)
    frame.when:SetText(entry.at and date("%d.%m.%Y  /  %H:%M:%S", entry.at) or L["Время неизвестно"])
    local where = entry.zone or L["Место неизвестно"]
    if entry.subzone and entry.subzone ~= entry.zone then where = where .. " / " .. entry.subzone end
    frame.where:SetText(where)
    local valid = type(entry.x) == "number" and type(entry.y) == "number"
        and entry.x >= 0 and entry.x <= 100 and entry.y >= 0 and entry.y <= 100
    frame.coords:SetText(valid and ("%.1f, %.1f"):format(entry.x, entry.y) or L["Координат нет"])
    frame.remaining, frame.lastAnchor = noticeLife, nil
    frame:SetAlpha(1)
    frame.fade = note.db.alertFlash ~= false
    finishKillImpact(frame)
    placeKillNotice(frame)
    frame:Show()
    if frame.fade then
        frame.impactAge = 0
        updateKillImpact(frame)
        frame.glow:Show()
        frame.ember:Show()
        for _, spark in ipairs(frame.sparks) do spark:Show() end
        if frame.procAnimation then
            frame.procBurst:Show()
            frame.procAnimation:Play()
        end
    end
end

function note.PreviewKillNotice()
    if not note.db then return end
    showKillNotice({
        kind = "K", other = "preview", killerName = "Ashenblade", victimName = "Ironbloom",
        at = GetServerTime(), zone = GetRealZoneText(), x = 61.3, y = 23.6,
    }, true)
end

function note.RecordFightReport(entry)
    if entry.kind == "K" then
        showKillNotice(entry)
        return
    end
    if not autoEnabled() then return end
    if not InCombatLockdown() then
        pendingEntry = nil
        note.OpenFightReport(nil, entry)
        return
    end
    pendingEntry = entry
    if not regen then
        regen = CreateFrame("Frame")
        regen:RegisterEvent("PLAYER_REGEN_ENABLED")
        regen:SetScript("OnEvent", function()
            local queued = pendingEntry
            pendingEntry = nil
            if queued and autoEnabled() and containsEvent(note.db, queued) then
                note.OpenFightReport(nil, queued)
            end
        end)
    end
end
