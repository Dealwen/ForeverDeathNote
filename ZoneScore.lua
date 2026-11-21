local _, note = ...
local L = note.L
local hud, queued
local width, height = 222, 56
local factions = {
    { key = "Horde", label = "Орда", color = { 0.96, 0.46, 0.36 } },
    { key = "Alliance", label = "Альянс", color = { 0.48, 0.73, 1 } },
}

local function build()
    local frame = CreateFrame("Frame", "ForeverDeathNoteZoneScoreHUD", UIParent, "BackdropTemplate")
    frame:Hide()
    frame:SetSize(width, height)
    frame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 24, -104)
    frame:SetFrameStrata("LOW")
    frame:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    frame:SetBackdropColor(0.04, 0.033, 0.027, 0.89)
    frame:SetBackdropBorderColor(0.42, 0.32, 0.22, 0.88)

    frame.zone = note.CreateFontString(frame, nil, "OVERLAY", "GameFontHighlightSmall")
    frame.zone:SetPoint("TOPLEFT", 9, -6)
    frame.zone:SetWidth(width - 18)
    frame.zone:SetJustifyH("LEFT")
    frame.zone:SetWordWrap(false)
    frame.zone:SetTextColor(0.94, 0.84, 0.70)
    frame.counts = {}

    for i, faction in ipairs(factions) do
        local left = 9 + (i - 1) * 105
        local emblem = frame:CreateTexture(nil, "ARTWORK")
        emblem:SetSize(23, 24)
        emblem:SetPoint("TOPLEFT", left, -22)
        note.SetFactionEmblem(emblem, faction.key)
        local count = note.CreateFontString(frame, nil, "OVERLAY", "GameFontHighlight")
        count:SetPoint("LEFT", emblem, "RIGHT", 7, 0)
        count:SetWidth(55)
        count:SetJustifyH("LEFT")
        note.StyleMapNumber(count, 21)
        count:SetTextColor(unpack(faction.color))
        frame.counts[faction.key] = count
        local rule = frame:CreateTexture(nil, "ARTWORK")
        rule:SetPoint("BOTTOMLEFT", left, 4)
        rule:SetSize(i == 1 and 93 or 81, 1)
        rule:SetColorTexture(faction.color[1], faction.color[2], faction.color[3], 0.60)
    end

    frame:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
        GameTooltip:SetText(self.zone:GetText())
        for _, faction in ipairs(factions) do
            GameTooltip:AddDoubleLine(L[faction.label], self.counts[faction.key]:GetText(), 1, 1, 1, unpack(faction.color))
        end
        GameTooltip:AddLine(L[note.db.territoryMode == "shared" and "Общий счёт" or "Мои бои"])
        GameTooltip:AddLine(L["Перетащите счётчик за рамку. Потяните за правый нижний угол, чтобы изменить размер."], 0.78, 0.73, 0.66, true)
        note.StyleLocaleTooltip(GameTooltip)
        GameTooltip:Show()
    end)
    local function hideTooltip(self) if GameTooltip:IsOwned(self) then GameTooltip:Hide() end end
    frame:SetScript("OnLeave", hideTooltip)
    frame:HookScript("OnHide", hideTooltip)
    note.ManageWindow(frame, "zoneScoreHUD")
    return frame
end

function note.RefreshZoneScoreHUD()
    if not note.db or note.db.zoneScoreHUD == false or note.Public(IsInInstance()) ~= false then
        if hud then hud:Hide() end
        return
    end
    local mapID = C_Map and C_Map.GetBestMapForUnit and note.PositiveInteger(C_Map.GetBestMapForUnit("player"), 1000000)
    local zone, horde, alliance
    if mapID then zone, horde, alliance = note.ZoneTerritoryScore(mapID) end
    if not zone then
        if hud then hud:Hide() end
        return
    end
    hud = hud or build()
    hud.zone:SetText(zone)
    hud.counts.Horde:SetText(tostring(horde))
    hud.counts.Alliance:SetText(tostring(alliance))
    hud:Show()
end

function note.QueueZoneScoreRefresh()
    if queued or not note.db or note.db.zoneScoreHUD == false then return end
    queued = true
    C_Timer.After(0.12, function()
        queued = nil
        note.RefreshZoneScoreHUD()
    end)
end

local watcher = CreateFrame("Frame")
for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA", "ZONE_CHANGED", "ZONE_CHANGED_INDOORS" }) do
    watcher:RegisterEvent(event)
end
watcher:SetScript("OnEvent", note.QueueZoneScoreRefresh)

-- Handle a weekly reset even when the player stays in one zone.
if C_Timer.NewTicker then
    local week
    C_Timer.NewTicker(30, function()
        local current = note.WeekStart(GetServerTime())
        if week ~= current then
            week = current
            note.QueueZoneScoreRefresh()
        end
    end)
end
