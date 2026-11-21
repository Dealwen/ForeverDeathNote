local _, note = ...
local L = note.L
local banner, targetButton, current, quietUntil
local dismissed = {}
local background = "Interface\\Buttons\\WHITE8X8"
local border = "Interface\\DialogFrame\\UI-DialogBox-Border"

local function targetName(unit)
    local name = note.UnitName(unit)
    if not name or not name:match("^[%a\128-\255 '%-]+$") then return nil end
    return name
end

local function eligible(unit)
    if not unit then return nil end
    local guid = note.GUID(UnitGUID(unit))
    if guid and note.Public(UnitCanAttack("player", unit)) == true
        and note.Public(UnitIsDeadOrGhost(unit)) == false then
        return guid
    end
end

function note.RivalTracking(guid, deaths)
    local preference = note.DossierPreference and note.DossierPreference(guid)
    local mark = preference and preference.mark
    if mark == "ignore" then return nil end
    if mark == "watch" or mark == "kos" then return mark end
    if deaths and deaths > 0 then return "rival" end
end

function note.PrepareRivalTarget(button, getSelection, onPreview, onFallback)
    button:RegisterForClicks("LeftButtonUp")
    button:SetAttribute("useOnKeyDown", false)
    button:SetAttribute("_onstate-fdncombat", [[
        if newstate == "combat" then
            self:SetAttribute("type1", nil)
            self:SetAttribute("macrotext1", nil)
            self:Hide()
        end
    ]])
    RegisterStateDriver(button, "fdncombat", "[combat] combat; peace")
    local function commandFor(data)
        if not data or not data.unit or not data.guid or eligible(data.unit) ~= data.guid then return end
        local name = targetName(data.unit)
        if name then return "/targetexact " .. name end
    end
    button:SetScript("PreClick", function(self)
        if InCombatLockdown() then return end
        local command = commandFor(getSelection())
        self:SetAttribute("type1", command and "macro" or nil)
        self:SetAttribute("macrotext1", command)
    end)
    button:SetScript("PostClick", function()
        if InCombatLockdown() then return end
        local data = getSelection()
        if not data then return end
        if data.preview and not data.guid then
            if onPreview then onPreview(data) end
        elseif data.guid and note.GUID(UnitGUID("target")) ~= data.guid then
            local command = commandFor(data)
            local openChat = ChatFrameUtil and ChatFrameUtil.OpenChat or ChatFrame_OpenChat
            if command and openChat then
                openChat(command)
                if onFallback then onFallback(data) end
            end
        end
    end)
end

function note.HideRivalTarget(button)
    if InCombatLockdown() or not button then return end
    button:SetAttribute("type1", nil)
    button:SetAttribute("macrotext1", nil)
    button:Hide()
end

function note.CanTargetRival(unit, guid)
    return guid ~= nil and eligible(unit) == guid and targetName(unit) ~= nil
end

local function hide()
    current = nil
    if banner then banner:Hide() end
    note.HideRivalTarget(targetButton)
end

local function addLabel(parent, font, width, x, y)
    local label = note.CreateFontString(parent, nil, "OVERLAY", font)
    label:SetPoint("TOPLEFT", x, y)
    label:SetWidth(width)
    label:SetJustifyH("LEFT")
    label:SetWordWrap(false)
    return label
end

local function buildBanner()
    banner = CreateFrame("Frame", "ForeverDeathNoteNearby", UIParent, "BackdropTemplate")
    banner:SetSize(422, 171)
    banner:SetPoint("TOP", UIParent, "TOP", 0, -148)
    banner:SetFrameStrata("DIALOG")
    banner:SetBackdrop({
        bgFile = background, edgeFile = border, edgeSize = 24,
        insets = {left = 6, right = 6, top = 6, bottom = 6},
    })
    banner:SetBackdropColor(0.06, 0.08, 0.11, 1)
    local icon = banner:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT", 16, -17)
    icon:SetSize(34, 34)
    banner.icon = icon
    banner.title = addLabel(banner, "GameFontNormal", 294, 59, -16)
    banner.name = addLabel(banner, "GameFontHighlightLarge", 300, 59, -34)
    banner.description = addLabel(banner, "GameFontHighlightSmall", 381, 19, -65)
    banner.memo = addLabel(banner, "GameFontHighlightSmall", 381, 19, -85)
    banner.memo:SetTextColor(0.80, 0.82, 0.85)
    local strike = CreateFrame("Frame", nil, banner)
    strike:SetSize(22, 22)
    strike:SetPoint("TOPLEFT", 19, -103)
    strike.icon = strike:CreateTexture(nil, "ARTWORK")
    strike.icon:SetAllPoints()
    strike:EnableMouse(true)
    strike:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(self.name)
        note.StyleLocaleTooltip(GameTooltip)
        GameTooltip:Show()
    end)
    strike:SetScript("OnLeave", function() GameTooltip:Hide() end)
    banner.strike = strike
    banner.strikeName = addLabel(banner, "GameFontHighlightSmall", 345, 49, -108)
    local dossier = CreateFrame("Button", nil, banner, "UIPanelButtonTemplate")
    dossier:SetPoint("TOPLEFT", 185, -133)
    dossier:SetSize(129, 24)
    note.StyleLocaleButton(dossier)
    dossier:SetText(L["Досье"])
    dossier:SetScript("OnClick", function()
        if current and current.id then note.OpenDossier(current.id, current.sample) end
    end)
    banner.dossier = dossier
    local close = CreateFrame("Button", "ForeverDeathNoteAlertClose", banner, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -6, -5)
    close:SetScript("OnClick", function()
        if current and current.guid then
            dismissed[current.guid] = current.unit
        end
        hide()
    end)
    banner:SetScript("OnUpdate", function(self)
        local elapsed = GetTime() - self.started
        local flash = note.db.alertFlash ~= false and elapsed < 2.4
            and (0.63 + 0.37 * math.abs(math.sin(elapsed * 8.5))) or 0.74
        if current and current.revenge then
            self:SetBackdropBorderColor(1, 0.49 + flash * 0.37, flash * 0.42, 1)
        else
            self:SetBackdropBorderColor(1, flash * 0.46, flash * 0.27, 1)
        end
    end)
    local function align()
        note.PlaceTargetControl(targetButton, banner, 19, -133)
    end
    banner.align = align
    note.ManageWindow(banner, "alert", note.WindowDragHandle(banner, 54, 351), align)
    banner:HookScript("OnHide", function()
        if GameTooltip and GameTooltip:IsOwned(strike) then GameTooltip:Hide() end
    end)
    banner:Hide()
end

local function buildTargetButton()
    -- Independent protected button. The card never inherits combat lockdown.
    targetButton = CreateFrame("Button", "ForeverDeathNoteTargetRival", UIParent,
        "UIPanelButtonTemplate,SecureActionButtonTemplate,SecureHandlerStateTemplate")
    note.StyleLocaleButton(targetButton)
    targetButton:SetSize(155, 24)
    banner.align()
    targetButton:SetFrameStrata("DIALOG")
    targetButton:SetFrameLevel(banner:GetFrameLevel() + 3)
    note.PrepareRivalTarget(targetButton, function() return current end, function()
        banner.description:SetText(L["Клик сработал. Цель в тесте вымышленная."])
    end, function()
        banner.description:SetText(L["Нажмите Enter для команды выбора цели."])
    end)
    targetButton:Hide()
end

local function show(data)
    if not banner then buildBanner() end
    local combat = InCombatLockdown()
    if not combat and not targetButton then buildTargetButton() end
    data.combat = combat and true or false
    local new = not current or current.key ~= data.key
        or (data.revenge and not current.revenge)
    current = data
    banner.icon:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcon_8")
    banner.icon:SetTexCoord(0, 1, 0, 1)
    local class = data.class and "classicon-" .. data.class:lower()
    if class and C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(class) then
        banner.icon:SetAtlas(class)
    end
    banner.title:SetText(L[data.revenge and "Цель реванша рядом!" or "Обидчик рядом!"])
    if data.revenge then banner:SetBackdropColor(0.16, 0.10, 0.065, 1)
    elseif note.WarTable and note.WarTable.Refined() then banner:SetBackdropColor(unpack(note.WarTable.ink))
    else banner:SetBackdropColor(0.06, 0.08, 0.11, 1) end
    banner.name:SetText(data.name)
    local dossier = data.id and note.Dossier(data.id, data.sample)
    local className = note.ClassLabel(data.class) or L["Класс неизвестен"]
    local score = L["Вы %d · Вас %d"]:format(dossier and dossier.kills or 0, dossier and dossier.deaths or 0):gsub(" · ", " / ")
    banner.description:SetText(className .. "  /  " .. score .. (combat and L[" • Выбор цели вне боя"] or ""))
    local memo = dossier and note.SampleText(dossier.preference.text, data.sample)
    banner.memo:SetText(memo and (L["Личная заметка"] .. ": " .. memo) or "")
    local death = dossier and dossier.lastDeath and dossier.lastDeath.entry
    local spell = death and note.SpellName(death.spellId, death.spellName, data.sample)
    local texture = death and death.spellId and C_Spell and C_Spell.GetSpellTexture
        and note.Public(C_Spell.GetSpellTexture(death.spellId))
    banner.strike.icon:SetTexture(texture or (spell == L["Автоатака"] and "Interface\\Icons\\Ability_MeleeDamage")
        or "Interface\\Icons\\INV_Misc_QuestionMark")
    banner.strike.name = spell or L["Способность неизвестна"]
    banner.strike:SetShown(death ~= nil)
    banner.strikeName:SetText(death and (L["Последний удар"] .. ": " .. banner.strike.name) or "")
    banner.dossier:SetShown(dossier ~= nil)
    if new then
        banner.started = GetTime()
        if note.db.alertSound ~= false and SOUNDKIT and SOUNDKIT.RAID_WARNING and PlaySound then
            PlaySound(SOUNDKIT.RAID_WARNING)
        end
    end
    banner:Show()
    banner.align()
    note.HideRivalTarget(targetButton)
    local canTarget = not combat and note.CanTargetRival(data.unit, data.guid)
    if canTarget then
        targetButton:SetText(L["Взять в цель"])
        targetButton:Show()
    end
end

local lastPlates, lastRivals, observed

function note.GetHuntSighting(id)
    local entry = observed and observed[id]
    if entry and not IsInInstance() and eligible(entry.unit) == id then
        return { visible = true, age = 0 }
    end
end

function note.RefreshNearby(plates, rivals)
    lastPlates, lastRivals = plates, rivals
    local combat = InCombatLockdown() and true or false
    local inInstance = IsInInstance()
    local dead = note.Public(UnitIsDeadOrGhost("player"))
    local active, best = {}
    local revengeId = note.ActiveHuntRival and note.ActiveHuntRival()
    if not inInstance and not dead then
        for unit in pairs(plates) do
            local who = eligible(unit)
            local count = who and (rivals[who] or 0)
            local mark = who and note.RivalTracking(who, count)
            if mark then
                local revenge = who == revengeId
                local entry = {guid = who, unit = unit, deaths = count, mark = mark, revenge = revenge}
                active[who] = entry
                if mark ~= "watch" and not dismissed[who] then
                    local outranks = not best or (revenge and not best.revenge)
                        or (revenge == best.revenge and (count > best.deaths
                            or (count == best.deaths and who < best.guid)))
                    if outranks then best = entry end
                end
            end
        end
    end
    observed = active
    if note.UpdateNearbySightings then note.UpdateNearbySightings(active, rivals, inInstance) end
    if note.db.alerts == false or inInstance or dead then
        dismissed = {}
        hide()
        return
    end
    for who, unit in pairs(dismissed) do
        local atPlate = plates[unit] and note.GUID(UnitGUID(unit))
        if not active[who] and (not plates[unit] or (atPlate and atPlate ~= who)) then
            dismissed[who] = nil
        end
    end
    if (quietUntil and quietUntil > GetTime()) or not best then hide(); return end
    if current and current.guid == best.guid and current.unit == best.unit
        and current.combat == combat and current.mark == best.mark and current.deaths == best.deaths
        and current.revenge == best.revenge and banner:IsShown() then return end
    local profile = note.Profile(best.guid)
    local description = best.revenge and (L["Активная цель · Ваших смертей: "] .. best.deaths)
        or (best.mark == "kos" and L["Личная метка: атаковать при встрече"]
            or (L["Ваших смертей от игрока: "] .. best.deaths))
    show({ key = best.guid, guid = best.guid, id = best.guid, unit = best.unit,
        name = profile.name or targetName(best.unit) or L["Имя неизвестно"],
        mark = best.mark, deaths = best.deaths, class = profile.class, revenge = best.revenge,
        description = description })
end

function note.RefreshAlert()
    if lastPlates and note.db then note.RefreshNearby(lastPlates, lastRivals) else hide() end
end

function note.AlertsSnoozed()
    return quietUntil ~= nil and quietUntil > GetTime()
end

function note.ToggleAlertPause()
    if note.AlertsSnoozed() then
        quietUntil = nil
    else
        quietUntil = GetTime() + 600
        local expires = quietUntil
        C_Timer.After(600, function()
            if quietUntil ~= expires then return end
            quietUntil = nil
            note.RefreshAlert()
            if note.RefreshWindow then note.RefreshWindow() end
        end)
    end
    note.RefreshAlert()
end

