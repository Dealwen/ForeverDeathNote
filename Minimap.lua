local _, note = ...
local L = note.L
local button
local loader = CreateFrame("Frame")

local rimColors = {
    Horde = { 0.98, 0.58, 0.48 },
    Alliance = { 0.64, 0.82, 1 },
}
local neutralRim = { 0.83, 0.75, 0.62 }

local function hideTooltip(self)
    if GameTooltip:IsOwned(self) then GameTooltip:Hide() end
end

local function showTooltip(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:SetText(L["Тетрадь смерти"])
    GameTooltip:AddLine(L["Левый клик — открыть или закрыть"], 0.96, 0.91, 0.82)
    GameTooltip:AddLine(L["Правый клик — настройки"], 0.80, 0.76, 0.68)
    note.StyleLocaleTooltip(GameTooltip)
    GameTooltip:Show()
end

local function build(map)
    local control = CreateFrame("Button", "ForeverDeathNoteMinimapButton", map)
    control:SetSize(40, 40)
    control:SetPoint("TOPRIGHT", map, "BOTTOMRIGHT", -5, -14)
    control:SetClampedToScreen(true)
    control:SetFrameLevel(map:GetFrameLevel() + 4)
    control:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    local face = control:CreateTexture(nil, "BACKGROUND")
    face:SetPoint("CENTER")
    face:SetSize(32, 32)
    face:SetAtlas("ui-hud-minimap-button", false)

    local mark = control:CreateTexture(nil, "ARTWORK")
    mark:SetPoint("CENTER", control, "CENTER", 0, 1)
    mark:SetSize(26, 26)
    mark:SetTexture(note.BrandIcon)
    mark:SetTexCoord(0.04, 0.96, 0.04, 0.96)

    local rim = control:CreateTexture(nil, "OVERLAY")
    rim:SetPoint("CENTER")
    rim:SetSize(36, 36)
    rim:SetAtlas("UI-HUD-Minimap-Frame-Cycle", false)
    control.rim = rim

    local glow = control:CreateTexture(nil, "HIGHLIGHT")
    glow:SetPoint("CENTER")
    glow:SetSize(35, 35)
    glow:SetTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    glow:SetBlendMode("ADD")
    glow:SetAlpha(0.58)

    control:SetScript("OnEnter", showTooltip)
    local function resetHover(self)
        mark:SetAlpha(1)
        hideTooltip(self)
    end
    control:SetScript("OnLeave", resetHover)
    control:SetScript("OnHide", resetHover)
    control:SetScript("OnMouseDown", function() mark:SetAlpha(0.6) end)
    control:SetScript("OnMouseUp", function() mark:SetAlpha(1) end)
    control:SetScript("OnClick", function(self, mouseButton)
        hideTooltip(self)
        if mouseButton == "RightButton" then
            note.OpenWindow("settings")
        elseif mouseButton == "LeftButton" then
            note.ToggleWindow()
        end
    end)
    return control
end

function note.RefreshMinimapButton()
    if not note.db then return end
    local enabled = note.db.minimapButton ~= false
    if enabled and not button and Minimap and not InCombatLockdown() then button = build(Minimap) end
    if not button then return end
    if enabled then
        local faction = note.Faction(UnitFactionGroup("player"))
        button.rim:SetVertexColor(unpack(rimColors[faction] or neutralRim))
    end
    button:SetShown(enabled)
end

loader:RegisterEvent("PLAYER_LOGIN")
loader:RegisterEvent("PLAYER_ENTERING_WORLD")
loader:RegisterEvent("PLAYER_REGEN_ENABLED")
loader:SetScript("OnEvent", note.RefreshMinimapButton)
