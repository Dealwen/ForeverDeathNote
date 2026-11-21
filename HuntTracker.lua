local _, note = ...
local L = note.L
local tracker, toast
local background = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark"
local border = "Interface\\DialogFrame\\UI-DialogBox-Border"
local rune = "Interface\\Icons\\INV_Misc_Rune_08"
local scroll = "Interface\\Icons\\INV_Scroll_03"
local compactHeight, expandedHeight = 35, 92

local function panel(name, width, height)
    local frame = CreateFrame("Frame", name, UIParent, "BackdropTemplate")
    frame:SetSize(width, height)
    frame:SetFrameStrata("HIGH")
    frame:SetClampedToScreen(true)
    frame:SetBackdrop({
        bgFile = background, edgeFile = border, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    frame:SetBackdropColor(0.13, 0.085, 0.046, 0.96)
    frame:SetBackdropBorderColor(0.72, 0.49, 0.21, 1)
    return frame
end

local function label(parent, font, width, x, y)
    local text = note.CreateFontString(parent, nil, "OVERLAY", font)
    text:SetPoint("TOPLEFT", x, y)
    text:SetWidth(width)
    text:SetJustifyH("LEFT")
    text:SetWordWrap(false)
    return text
end

local function addClose(frame, closeName, action)
    local close = CreateFrame("Button", closeName, frame, "UIPanelCloseButton")
    close:SetSize(22, 22)
    close:SetPoint("TOPRIGHT", -5, -5)
    close:SetScript("OnClick", action)
end

local function currentDemo()
    if note.db then return note.DemoData and note.DemoData() end
end

function note.IsHuntTrackerVisible(demo)
    local source = demo or note.db
    return source and source.huntTrackerVisible == true or false
end

local function buildTracker()
    tracker = panel("ForeverDeathNoteHuntTracker", 348, expandedHeight)
    tracker:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -25, -418)

    local open = CreateFrame("Button", nil, tracker)
    open:SetPoint("TOPLEFT", 6, -3)
    open:SetSize(288, 27)
    open:SetHighlightTexture("Interface\\Buttons\\UI-Listbox-Highlight2")
    open:SetScript("OnClick", function()
        if note.OpenWindow then note.OpenWindow("hunt") end
    end)

    local icon = open:CreateTexture(nil, "ARTWORK")
    icon:SetSize(18, 18)
    icon:SetPoint("LEFT", 4, 0)
    tracker.icon = icon
    tracker.title = label(open, "GameFontNormalSmall", 195, 27, -8)
    tracker.progress = label(open, "GameFontHighlightSmall", 55, 226, -8)
    tracker.progress:SetJustifyH("RIGHT")

    local toggle = CreateFrame("Button", nil, tracker, "UIPanelButtonTemplate")
    note.StyleLocaleButton(toggle)
    if note.StyleWarcraftButton then note.StyleWarcraftButton(toggle) end
    toggle:SetPoint("TOPRIGHT", -28, -6)
    toggle:SetSize(23, 20)
    toggle:SetScript("OnClick", function(self)
        local source = currentDemo() or note.db
        source.huntTrackerExpanded = not source.huntTrackerExpanded
        if GameTooltip and GameTooltip:IsOwned(self) then GameTooltip:Hide() end
        note.RefreshHuntTracker()
    end)
    toggle:SetScript("OnEnter", function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText(L[tracker.expanded and "Свернуть трекер" or "Развернуть трекер"])
        note.StyleLocaleTooltip(GameTooltip)
        GameTooltip:Show()
    end)
    local function hideToggleHint(self)
        if GameTooltip and GameTooltip:IsOwned(self) then GameTooltip:Hide() end
    end
    toggle:SetScript("OnLeave", hideToggleHint)
    toggle:SetScript("OnHide", hideToggleHint)
    tracker.toggle = toggle

    local details = CreateFrame("Frame", nil, tracker)
    details:SetPoint("TOPLEFT", 8, -34)
    details:SetSize(330, 49)
    tracker.details = details
    tracker.description = label(details, "GameFontHighlightSmall", 321, 6, 0)
    tracker.description:SetWordWrap(true)
    tracker.description:SetMaxLines(2)
    tracker.deadline = label(details, "GameFontNormalSmall", 315, 6, -33)

    local fill = CreateFrame("StatusBar", nil, tracker)
    fill:SetPoint("BOTTOMLEFT", 8, 5)
    fill:SetSize(316, 3)
    fill:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    fill:SetStatusBarColor(0.82, 0.61, 0.26, 0.9)
    tracker.bar = fill
    addClose(tracker, "ForeverDeathNoteHuntTrackerClose", function()
        note.SetHuntTrackerVisible(false, currentDemo())
        if note.RefreshWindow then note.RefreshWindow() end
    end)
    local nextRefresh = 0
    tracker:SetScript("OnUpdate", function(_, elapsed)
        nextRefresh = nextRefresh + elapsed
        if nextRefresh >= 30 then
            nextRefresh = 0
            note.RefreshHuntTracker()
        end
    end)
    note.ManageWindow(tracker, "tracker", open)
    tracker:Hide()
end

function note.RefreshHuntTracker()
    local demo = currentDemo()
    if not note.IsHuntTrackerVisible(demo) then
        if tracker then tracker:Hide() end
        return
    end
    if not tracker then buildTracker() end
    local source, now = demo or note.db, GetServerTime()
    local goal = note.GetTrackedHuntGoal and note.GetTrackedHuntGoal(demo, now)
    local expanded = source.huntTrackerExpanded == true
    if tracker.expanded ~= expanded then
        tracker.expanded = expanded
        tracker:SetHeight(expanded and expandedHeight or compactHeight)
        tracker.details:SetShown(expanded)
        tracker.toggle:SetText(expanded and "−" or "+")
    end
    local prefix = demo and L["ТЕСТ • "] or ""
    tracker.title:SetText(prefix .. (goal and goal.name or L["Выбрать цель в «Охоте»"]))
    tracker.icon:SetTexture(goal and goal.earned and rune or scroll)
    tracker.bar:SetShown(goal ~= nil)
    if goal then
        local amount = goal.earned and goal.target or goal.amount
        tracker.progress:SetText(goal.expired and L["Истёк"] or ("%d / %d"):format(amount, goal.target))
        tracker.bar:SetMinMaxValues(0, goal.target)
        tracker.bar:SetValue(amount)
    else
        tracker.progress:SetText("")
    end
    if expanded then
        tracker.description:SetText(goal and goal.description or "")
        local deadline = ""
        if goal and goal.expires and not goal.earned and not goal.expired then
            local span = note.HuntTimeRemaining(goal.expires, now)
            deadline = (goal.contract and L["До завершения"] .. " " .. span or L["До сброса: %s"]:format(span))
        end
        tracker.deadline:SetText(deadline)
    end
    tracker:Show()
end

function note.SetHuntTrackerVisible(visible, demo)
    local source = demo or note.db
    if not source then return end
    source.huntTrackerVisible = visible == true
    note.RefreshHuntTracker()
end

local function buildToast()
    toast = panel("ForeverDeathNoteRevengeToast", 372, 70)
    toast:SetPoint("TOP", UIParent, "TOP", 0, -70)
    toast:SetFrameStrata("DIALOG")
    toast:SetBackdropColor(0.23, 0.13, 0.069, 1)
    toast:SetBackdropBorderColor(0.96, 0.69, 0.29, 1)

    local icon = toast:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT", 13, -15)
    icon:SetSize(36, 36)
    icon:SetTexture(rune)

    local title = label(toast, "GameFontNormalLarge", 274, 61, -13)
    title:SetText(L["Реванш завершён"])
    toast.result = label(toast, "GameFontHighlightSmall", 279, 61, -39)
    addClose(toast, "ForeverDeathNoteRevengeToastClose", function() toast:Hide() end)
    toast:SetScript("OnUpdate", function(self)
        local remaining = self.expiresAt - GetTime()
        if remaining <= 0 then self:Hide()
        else self:SetAlpha(math.min(1, remaining * 2.5)) end
    end)
    toast:Hide()
end

function note.NotifyHuntRevenge(id, kills, deaths)
    if not note.db or currentDemo() then return end
    if not toast then buildToast() end
    toast.result:SetText((L["%s · %d:%d · +1 печать"]):format(note.Name(id), kills, deaths))
    toast.expiresAt = GetTime() + 6
    toast:SetAlpha(1)
    toast:Show()
end
