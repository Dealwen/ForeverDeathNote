local _, note = ...
local L = note.L
local steps = {
    { "hunt", "Охота", "Выберите соперника и отследите недельную цель. Трекер останется на экране, когда журнал закрыт." },
    { "ranking", "Рейтинги", "Откройте рейтинг игроков и гильдий. Карта находится во вкладке «Территории», а звания и достижения — в журнале." },
    { "journal", "Журнал", "Здесь автоматически сохраняются ваши добивания и смерти в PvP открытого мира. Нажмите на запись для подробностей." },
    { "rivals", "Обидчики", "Откройте досье соперника, чтобы увидеть личный счёт, поставить метку или выбрать цель для реванша." },
}

local function button(frame, title, point, x, width, action)
    local control = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    control:SetSize(width, 24)
    control:SetPoint(point, x, 13)
    control:SetText(title)
    note.StyleLocaleButton(control)
    control:SetScript("OnClick", action)
    return control
end

function note.ShowOnboarding(window, tabs, navigate)
    if window.guide then window.guide:Show(); window.guide:Select(1); return end
    local frame = CreateFrame("Frame", nil, window, "BackdropTemplate")
    frame:SetSize(388, 138)
    frame:SetPoint("TOP", window, "TOP", 0, -143)
    frame:SetFrameLevel(window:GetFrameLevel() + 45)
    frame:SetToplevel(true)
    frame:EnableMouse(true)
    note.WarTable.Panel(frame, 0.12, 0.074, 0.044)

    local focus = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    focus:SetBackdrop({ edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 14 })
    focus:SetBackdropBorderColor(1, 0.76, 0.33, 1)
    focus:EnableMouse(false)
    local arrow = focus:CreateTexture(nil, "OVERLAY")
    arrow:SetSize(23, 23)
    arrow:SetPoint("TOP", focus, "BOTTOM", 0, 2)
    arrow:SetTexture("Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up")
    arrow:SetRotation(math.pi / 2)
    arrow:SetVertexColor(1, 0.80, 0.53)

    local title = note.CreateFontString(frame, nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -13)
    local number = note.CreateFontString(frame, nil, "OVERLAY", "GameFontHighlightSmall")
    number:SetPoint("TOPRIGHT", -16, -18)
    number:SetWidth(48)
    number:SetJustifyH("RIGHT")
    local body = note.CreateFontString(frame, nil, "OVERLAY", "GameFontHighlight")
    body:SetPoint("TOPLEFT", 16, -44)
    body:SetSize(356, 51)
    body:SetJustifyH("LEFT")
    body:SetJustifyV("TOP")
    body:SetWordWrap(true)

    local nextButton = button(frame, L["Далее"], "BOTTOMRIGHT", -13, 112, function()
        if frame.step == #steps then frame:Hide() else frame:Select(frame.step + 1) end
    end)
    button(frame, L["Пропустить"], "BOTTOMLEFT", 13, 112, function() frame:Hide() end)
    function frame:Select(i)
        self.step = i
        local step = steps[i]
        if navigate then navigate(step[1]) end
        title:SetText(L[step[2]])
        number:SetText(i .. " / " .. #steps)
        body:SetText(L[step[3]])
        nextButton:SetText(L[i == #steps and "Готово" or "Далее"])
        local anchor = tabs[step[1]]
        focus:ClearAllPoints()
        focus:SetPoint("TOPLEFT", anchor, "TOPLEFT", -3, 3)
        focus:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", 3, -3)
    end
    window.guide = frame
    window:HookScript("OnHide", function() frame:Hide() end)
    frame:SetScript("OnHide", function()
        if note.MaybeOfferGuildSharing then note.MaybeOfferGuildSharing() end
    end)
    frame:Select(1)
end
