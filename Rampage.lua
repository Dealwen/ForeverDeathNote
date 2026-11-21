local _, note = ...
local L = note.L
local windows = { 300, 150, 40, 20 }
local victoryDuration, bannerDuration = 7, 3.5
local skull = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_8"
local backdrop = {
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border", edgeSize = 18,
    insets = { left = 5, right = 5, top = 5, bottom = 5 },
}
local tones = {
    { 0.98, 0.73, 0.40 },
    { 1.00, 0.66, 0.33 },
    { 1.00, 0.56, 0.27 },
    { 1.00, 0.47, 0.23 },
    { 1.00, 0.85, 0.46 },
}
local rays = { { 1, 0, 3 }, { -1, 0, 1 }, { 0.64, 0.77, 1 }, { -0.64, 0.77, 5 },
    { 0.64, -0.77, 7 }, { -0.64, -0.77, 3 } }
local frame, banner

local function liveState()
    local db = note.db
    if not db then return end
    db.rampage = db.rampage or { completed = 0 }
    return db.rampage
end

function note.RampageCount(source)
    local data = source or note.db
    return data and data.rampage and data.rampage.completed or 0
end

local function alive(state, now)
    return state and state.level and state.deadline > now and state
end

local function text(parent, font, width, top, left)
    local value = note.CreateFontString(parent, nil, "OVERLAY", font)
    if left then
        value:SetPoint("TOPLEFT", left, top)
        value:SetJustifyH("LEFT")
    else
        value:SetPoint("TOP", 0, top)
        value:SetJustifyH("CENTER")
    end
    value:SetWidth(width)
    value:SetWordWrap(false)
    return value
end

local function strip(parent, width, height, red, green, blue)
    local region = parent:CreateTexture(nil, "ARTWORK")
    region:SetSize(width, height)
    region:SetColorTexture(red, green, blue, 1)
    return region
end

local function placeIcon(self, level, size, lift)
    local icon = self.emblems[level]
    icon:SetSize(size, size)
    icon:SetPoint("CENTER", self, "TOP", (level - 3) * 46, -47 + lift)
end

local function finishSurge(self)
    if self.surge then
        local level = self.surge.level
        placeIcon(self, level, 30, 0)
        self.emblems[level]:SetAlpha(1)
    end
    self.surge = nil
    for _, mote in ipairs(self.motes) do mote:Hide() end
end

local function updateSurge(self, now)
    local surge = self.surge
    local progress = (now - surge.at) / surge.duration
    if progress >= 1 then finishSurge(self); return end
    local entry = math.min(1, progress * 3.8)
    local settle = math.max(0, (progress - 0.28) / 0.72)
    local carry = (1 - entry) ^ 2
    local swell = (1 - settle) ^ 2
    placeIcon(self, surge.level, 30 - 6 * carry + surge.size * entry * swell, 16 * carry + 4 * entry * swell)
    self.emblems[surge.level]:SetAlpha(1 - 0.58 * carry)
    local x = (surge.level - 3) * 46
    for index, mote in ipairs(self.motes) do
        local ray = rays[index]
        local outward = 13 + surge.distance * progress
        mote:SetPoint("CENTER", self, "TOP", x + ray[1] * outward, -47 + ray[2] * outward)
        mote:SetAlpha(0.82 * entry * (1 - progress))
    end
end

local function startSurge(self, level)
    if note.db.alertFlash == false then return end
    local tier = level == 5
    self.surge = { level = level, at = GetTime(), duration = tier and 0.95 or 0.64,
        size = tier and 20 or 11, distance = tier and 20 or 12 }
    for _, mote in ipairs(self.motes) do
        mote:SetColorTexture(unpack(tones[level]))
        mote:Show()
    end
    updateSurge(self, self.surge.at)
end

local function clockText(self, remaining, fraction)
    if self.remaining ~= remaining then
        self.remaining = remaining
        local value = ("%d:%02d"):format(math.floor(remaining / 60), remaining % 60)
        self.timer:SetText(L["До конца серии: %s"]:format(value))
        self.fill:SetWidth(math.max(1, self.track:GetWidth() * fraction))
    end
end

local function paint(self, level, animate)
    finishSurge(self)
    local tone = tones[level]
    for index, icon in ipairs(self.emblems) do
        local lit = index <= level
        icon:SetDesaturated(not lit)
        icon:SetAlpha(lit and 1 or 0.23)
        icon:SetVertexColor(unpack(lit and tones[index] or { 0.66, 0.61, 0.55 }))
        self.notches[index]:SetColorTexture(unpack(lit and tone or { 0.38, 0.27, 0.19 }))
    end
    self.title:SetText(L["Розыск"] .. "  ·  " .. level .. " / 5")
    self.title:SetTextColor(unpack(tone))
    self:SetBackdropBorderColor(tone[1] * 0.76, tone[2] * 0.76, tone[3] * 0.76, 1)
    self.fill:SetColorTexture(unpack(tone))
    self.track:SetShown(level < 5)
    self.fill:SetShown(level < 5)
    self.remaining = nil
    if level < 5 then
        clockText(self, windows[level], 1)
    else
        self.timer:SetText(L["Серии из пяти черепов: %d"]:format(note.RampageCount()))
    end
    self:Show()
    if animate then startSurge(self, level) end
end

local function showLive(self, animate)
    local now = GetServerTime()
    local state = alive(note.db and note.db.rampage, now)
    if not state or state.dismissed then
        self:Hide()
        return
    end
    paint(self, state.level, animate)
    if state.level < 5 then
        local remaining = state.deadline - now
        clockText(self, remaining, remaining / windows[state.level])
    end
end

local function close(self)
    local state = note.db and note.db.rampage
    if state then state.dismissed = true end
    self:Hide()
    if banner then banner:Hide() end
end

local function tick(self)
    if self.surge then updateSurge(self, GetTime()) end
    local serverTime = GetServerTime()
    local state = alive(note.db and note.db.rampage, serverTime)
    if not state or state.dismissed then
        self:Hide()
    elseif state.level < 5 then
        local remaining = state.deadline - serverTime
        clockText(self, remaining, remaining / windows[state.level])
    end
end

local function build()
    local panel = CreateFrame("Frame", "ForeverDeathNoteRampage", UIParent, "BackdropTemplate")
    panel:SetSize(296, 99)
    panel:SetPoint("TOP", UIParent, "TOP", 0, -142)
    panel:SetFrameStrata("HIGH")
    panel:SetClampedToScreen(true)
    panel:SetBackdrop(backdrop)
    panel:SetBackdropColor(0.16, 0.09, 0.047, 0.97)
    panel:SetBackdropBorderColor(0.69, 0.43, 0.22, 1)
    panel.title = text(panel, "GameFontNormal", 230, -12)
    note.StyleHeadingFont(panel.title)
    panel.timer = text(panel, "GameFontHighlightSmall", 250, -69)
    panel.timer:SetTextColor(0.92, 0.82, 0.68)
    panel.emblems, panel.notches = {}, {}
    for i = 1, 5 do
        local icon = panel:CreateTexture(nil, "ARTWORK")
        icon:SetTexture(skull)
        panel.emblems[i] = icon
        placeIcon(panel, i, 30, 0)
        local notch = strip(panel, 14, 2, 0.38, 0.27, 0.19)
        notch:SetPoint("CENTER", panel, "TOP", (i - 3) * 46, -65)
        panel.notches[i] = notch
    end
    panel.track = strip(panel, 216, 3, 0.35, 0.23, 0.15)
    panel.track:SetPoint("BOTTOM", 0, 11)
    panel.fill = strip(panel, 216, 3, 0.92, 0.60, 0.28)
    panel.fill:SetPoint("LEFT", panel.track, "LEFT")

    panel.motes = {}
    for i, ray in ipairs(rays) do
        local mote = strip(panel, 3, ray[3], 1, 0.84, 0.46)
        mote:SetDrawLayer("OVERLAY")
        mote:Hide()
        panel.motes[i] = mote
    end

    local dismiss = CreateFrame("Button", "ForeverDeathNoteRampageClose", panel, "UIPanelCloseButton")
    dismiss:SetSize(30, 30)
    dismiss:SetPoint("TOPRIGHT", -3, -3)
    dismiss:SetScript("OnClick", function() close(panel) end)
    panel:SetScript("OnHide", finishSurge)
    panel:SetScript("OnUpdate", tick)
    panel:Hide()
    return panel
end

local function placeBanner(self, progress)
    local initial = self.animate and math.min(1, progress * 8) or 1
    local rise = (1 - initial) ^ 3
    local top = math.min(249, UIParent:GetHeight() - 99)
    self:SetPoint("TOP", UIParent, "TOP", 0, -(top + 14 * rise))
    self:SetAlpha((1 - rise) * math.min(1, (1 - progress) * 5))
    local size = 56 + (self.animate and 16 * initial * math.max(0, 1 - progress * 2.6) or 0)
    self.medal:SetSize(size, size)
    self.light:SetAlpha(0.40 + (self.animate and 0.53 * math.max(0, 1 - progress * 3) or 0))
end

local function buildBanner()
    local notice = CreateFrame("Frame", "ForeverDeathNoteRampageMilestone", UIParent, "BackdropTemplate")
    notice:SetSize(356, 92)
    notice:SetFrameStrata("DIALOG")
    notice:SetClampedToScreen(true)
    notice:SetBackdrop(backdrop)
    notice:SetBackdropColor(0.20, 0.107, 0.034, 0.98)
    notice:SetBackdropBorderColor(0.98, 0.72, 0.28, 1)
    notice.title = text(notice, "GameFontNormalLarge", 245, -18, 91)
    notice.title:SetText(L["Пять черепов!"])
    notice.title:SetTextColor(1, 0.87, 0.49, 1)
    note.StyleHeadingFont(notice.title)
    notice.counter = text(notice, "GameFontHighlightSmall", 244, -50, 92)
    notice.counter:SetTextColor(0.95, 0.84, 0.64, 1)
    notice.medal = notice:CreateTexture(nil, "ARTWORK")
    notice.medal:SetPoint("CENTER", notice, "LEFT", 49, 0)
    notice.medal:SetTexture(skull)
    notice.medal:SetVertexColor(unpack(tones[5]))
    notice.light = strip(notice, 235, 2, 1, 0.70, 0.24)
    notice.light:SetPoint("TOPLEFT", 92, -42)
    local dismiss = CreateFrame("Button", "ForeverDeathNoteRampageMilestoneClose", notice, "UIPanelCloseButton")
    dismiss:SetSize(30, 30)
    dismiss:SetPoint("TOPRIGHT", -3, -3)
    dismiss:SetScript("OnClick", function() notice:Hide() end)
    notice:SetScript("OnUpdate", function(self)
        local progress = (GetTime() - self.started) / bannerDuration
        if progress >= 1 then self:Hide()
        else placeBanner(self, progress) end
    end)
    notice:Hide()
    return notice
end

local function celebrate()
    banner = banner or buildBanner()
    banner.started, banner.animate = GetTime(), note.db.alertFlash ~= false
    banner.counter:SetText(L["Серии из пяти черепов: %d"]:format(note.RampageCount()))
    placeBanner(banner, 0)
    banner:Show()
end

function note.StartRampage()
    local state = alive(note.db and note.db.rampage, GetServerTime())
    if not state or state.dismissed then return end
    frame = frame or build()
    showLive(frame, false)
end

function note.ShowRampage()
    local state = alive(note.db and note.db.rampage, GetServerTime())
    if not state then return false end
    state.dismissed = nil
    note.StartRampage()
    return true
end

function note.EndRampage(at)
    local state = note.db and note.db.rampage
    if not state then return end
    at = at or GetServerTime()
    if (state.at and at < state.at) or (state.deathAt and at <= state.deathAt) then return end
    state.deathAt, state.level, state.deadline, state.dismissed = at, nil, nil, nil
    if frame then frame:Hide() end
end

local function award(state, at)
    state.completed = state.completed + 1
    local db = note.db
    db.ladderAwards = db.ladderAwards or {}
    if not db.ladderAwards.rampage then
        db.ladderAwards.rampage = at
        if DEFAULT_CHAT_FRAME then
            DEFAULT_CHAT_FRAME:AddMessage(L["|cffffd276Тетрадь смерти|r • Получено: %s"]:format(L["Пять черепов"]))
        end
    end
end

function note.RecordRampage(entry)
    local at = entry.at
    if not note.db or type(at) ~= "number" or at ~= math.floor(at) or at <= 0 or at > GetServerTime() then return end
    if entry.kind == "D" then note.EndRampage(at); return end
    if entry.kind ~= "K" or not note.GUID(entry.other) or entry.other == note.owner then return end
    if IsInInstance and IsInInstance() then return end
    local state = liveState()
    if (state.at and at < state.at) or (state.deathAt and at <= state.deathAt) then return end
    if state.at ~= at then state.at, state.targets = at, {} end
    if state.targets[entry.other] then return end
    state.targets[entry.other] = true
    local old = alive(state, at)
    local level = old and old.level < 5 and old.level + 1 or 1
    state.level, state.deadline = level, at + (windows[level] or victoryDuration)
    if level == 1 then state.dismissed = nil end
    if level == 5 then award(state, at) end
    if not state.dismissed then
        frame = frame or build()
        showLive(frame, true)
        if level == 5 then celebrate() end
    end
    return level
end
