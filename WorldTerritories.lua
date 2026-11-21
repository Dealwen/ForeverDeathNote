local _, note = ...
local L = note.L
local map, toggle, layer, canvas, zoneScore
local mapID, width, height, badgeScale
local dirty = true
local flat = "Interface\\Buttons\\WHITE8X8"
local badges, highlights, strips, shapes = {}, {}, {}, {}
local continent = { [1414] = true, [1415] = true }

local function enabled()
    return ForeverDeathNoteDB and ForeverDeathNoteDB.worldTerritories ~= false
end

local factions = {
    { key = "Horde", background = { 0.24, 0.059, 0.042 }, line = { 0.96, 0.42, 0.32 } },
    { key = "Alliance", background = { 0.054, 0.115, 0.24 }, line = { 0.45, 0.69, 0.99 } },
}

local function scoreText(parent, style, size)
    local value = note.CreateFontString(parent, nil, "OVERLAY", style)
    local file, _, flags = value:GetFont()
    if file then value:SetFont(file, size, flags or "") end
    value:SetWordWrap(false)
    value:SetTextColor(1, 0.98, 0.92)
    value:SetShadowColor(0, 0, 0, 1)
    value:SetShadowOffset(1, -1)
    return value
end

local function makeBadge(parent, detailed)
    local badge = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    badge:SetBackdrop({ bgFile = flat, edgeFile = flat, edgeSize = 1 })
    badge:SetBackdropColor(0.058, 0.036, 0.027, 1)
    badge:SetFrameLevel(parent:GetFrameLevel() + 1)
    badge.sides = {}
    for _, faction in ipairs(factions) do
        local field = CreateFrame("Frame", nil, badge)
        local background = field:CreateTexture(nil, "BACKGROUND")
        background:SetAllPoints()
        background:SetColorTexture(unpack(faction.background))
        local line = field:CreateTexture(nil, "ARTWORK")
        line:SetPoint("BOTTOMLEFT")
        line:SetPoint("BOTTOMRIGHT")
        line:SetHeight(detailed and 3 or 2)
        line:SetColorTexture(unpack(faction.line))
        field.digits = scoreText(field, "GameFontHighlight", detailed and 26 or 16)
        note.StyleMapNumber(field.digits, detailed and 26 or 16)
        field.digits:SetPoint("CENTER", detailed and 13 or 0, 1)
        if detailed then
            local crest = field:CreateTexture(nil, "ARTWORK")
            crest:SetSize(24, 24)
            crest:SetPoint("LEFT", 6, 1)
            note.SetFactionEmblem(crest, faction.key)
        end
        badge.sides[faction.key] = field
    end
    return badge
end

local function sizeBadge(badge, zone, detailed, demo)
    local x, h = 2, detailed and 40 or 23
    for _, faction in ipairs(factions) do
        local field = badge.sides[faction.key]
        field.digits:SetText(tostring(zone[faction.key]))
        local w = math.max(detailed and 63 or 23, math.ceil(field.digits:GetStringWidth()) + (detailed and 41 or 9))
        field:ClearAllPoints()
        field:SetPoint("TOPLEFT", x, -2)
        field:SetSize(w, h - 4)
        x = x + w + 2
    end
    if detailed and demo then
        badge.demo:Show()
        h = h + 14
    elseif detailed then
        badge.demo:Hide()
    end
    local r, g, b = note.TerritoryColor(zone)
    badge:SetBackdropBorderColor(r * 0.74, g * 0.74, b * 0.74, 1)
    badge:SetSize(x + 1, h)
    return x + 1, h
end

local function badgeFor(index)
    if not badges[index] then badges[index] = makeBadge(layer, false) end
    return badges[index]
end

local offsets = {
    { 0, 0 }, { 0, -1 }, { 0, 1 }, { 0.55, -0.5 }, { -0.55, -0.5 },
    { 0.55, 0.5 }, { -0.55, 0.5 }, { 1, 0 }, { -1, 0 }, { 0, -1.75 }, { 0, 1.75 },
    { 0.75, -1.35 }, { -0.75, -1.35 }, { 0.75, 1.35 }, { -0.75, 1.35 },
}

local function badgePosition(x, y, w, h, placed)
    for _, offset in ipairs(offsets) do
        local px = math.max(w / 2 + 2, math.min(width - w / 2 - 2, x + offset[1] * (w + 3)))
        local py = math.max(h / 2 + 2, math.min(height - h / 2 - 2, y + offset[2] * (h + 3)))
        local clear = true
        for _, other in ipairs(placed) do
            if math.abs(px - other.x) < (w + other.w) / 2 + 2 and math.abs(py - other.y) < (h + other.h) / 2 + 2 then
                clear = false
                break
            end
        end
        if clear then return px, py end
    end
end

local function paintBoundary(zone, n, numStrips, x, y, r, g, b)
    local texture = highlights[n] or layer:CreateTexture(nil, "ARTWORK")
    highlights[n] = texture
    if not note.DrawTerritoryTint(texture, layer, mapID, zone.key, x, y, r, g, b, 0.57) then
        for _, span in ipairs(note.TerritoryShape(shapes, mapID, zone.key)) do
            numStrips = numStrips + 1
            local strip = strips[numStrips] or layer:CreateTexture(nil, "ARTWORK")
            strips[numStrips] = strip
            strip:ClearAllPoints()
            strip:SetPoint("TOPLEFT", layer, "TOPLEFT", span[1] * width, -span[2] * height)
            strip:SetSize(span[3] * width, span[4] * height)
            strip:SetColorTexture(r, g, b, 0.26)
            strip:Show()
        end
    end
    return numStrips
end

local function render()
    local zones, demo = note.TerritoryZones(mapID)
    local placements, count, paints, numStrips = {}, 0, 0, 0
    local wide = continent[mapID]
    zoneScore:SetShown(not wide and zones and zones[1] ~= nil or false)
    if not wide and zones and zones[1] then
        sizeBadge(zoneScore, zones[1], true, demo)
    end
    if wide then
        for _, zone in ipairs(zones or {}) do
            local x, y
            if type(zone.key) == "number" then x, y = note.TerritoryCenter(zone.key, mapID) end
            if x and y then
                local r, g, b = note.TerritoryColor(zone)
                local hasScore = zone.Horde + zone.Alliance > 0
                if hasScore then
                    paints = paints + 1
                    numStrips = paintBoundary(zone, paints, numStrips, x, y, r, g, b)
                end
                local badge = badgeFor(count + 1)
                local w, h = sizeBadge(badge, zone, false)
                w, h = w * badgeScale, h * badgeScale
                local px, py = badgePosition(x * width, y * height, w, h, placements)
                if not px and hasScore then
                    px = math.max(w / 2 + 2, math.min(width - w / 2 - 2, x * width))
                    py = math.max(h / 2 + 2, math.min(height - h / 2 - 2, y * height))
                end
                if px then
                    count = count + 1
                    placements[#placements + 1] = { x = px, y = py, w = w, h = h }
                    badge:ClearAllPoints()
                    badge:SetScale(badgeScale)
                    badge:SetPoint("CENTER", layer, "TOPLEFT", px / badgeScale, -py / badgeScale)
                    badge:Show()
                end
            end
        end
    end
    for i = count + 1, #badges do badges[i]:Hide() end
    for i = paints + 1, #highlights do highlights[i]:Hide() end
    for i = numStrips + 1, #strips do strips[i]:Hide() end
    layer:SetShown(count > 0 or paints > 0)
end

local function refresh()
    if not note.db then return end
    if not enabled() then
        zoneScore:Hide()
        if layer then layer:Hide() end
        return
    end
    local currentCanvas, currentID = map:GetCanvas(), map:GetMapID()
    if not currentCanvas or not currentID then
        zoneScore:Hide()
        if layer then layer:Hide() end
        dirty = true
        return
    end
    local w, h = currentCanvas:GetWidth(), currentCanvas:GetHeight()
    if w <= 0 or h <= 0 then return end
    local relativeScale = map:GetEffectiveScale() / currentCanvas:GetEffectiveScale()
    local scale = math.max(0.50, math.min(2, math.floor(relativeScale * 20 + 0.5) / 20))
    if not dirty and canvas == currentCanvas and mapID == currentID
        and width == w and height == h and scale == badgeScale then return end
    if not layer then layer = CreateFrame("Frame", nil, currentCanvas); layer:EnableMouse(false) end
    if canvas ~= currentCanvas then
        layer:SetParent(currentCanvas)
        layer:ClearAllPoints()
        layer:SetAllPoints(currentCanvas)
        layer:SetFrameLevel(currentCanvas:GetFrameLevel() + 20)
    end
    canvas, mapID, width, height, badgeScale, dirty = currentCanvas, currentID, w, h, scale, false
    render()
end

function note.InvalidateWorldTerritories()
    dirty = true
end

local function updateButton()
    local on = enabled()
    toggle.state:SetText(on and L["Вкл."] or L["Выкл."])
    toggle.state:SetTextColor(on and 0.83 or 0.78, on and 0.98 or 0.75, on and 0.72 or 0.69)
    note.TintWarcraftButton(toggle, on)
    toggle.statePlate:SetColorTexture(on and 0.16 or 0.15, on and 0.27 or 0.12, on and 0.10 or 0.09, 1)
    toggle.icon:SetDesaturated(not on)
end

local function attach()
    if toggle then return end
    local frame = WorldMapFrame
    if not frame or not frame.GetCanvas or not frame.GetMapID then return end
    map = frame
    toggle = CreateFrame("Button", "ForeverDeathNoteWorldTerritoriesToggle", frame)
    toggle:SetPoint("TOPRIGHT", frame.ScrollContainer or frame, "TOPRIGHT", -46, -7)
    toggle:SetSize(123, 30)
    toggle:SetFrameLevel(frame:GetFrameLevel() + 60)
    toggle.icon = toggle:CreateTexture(nil, "ARTWORK")
    toggle.icon:SetSize(20, 20)
    toggle.icon:SetPoint("LEFT", 7, 0)
    toggle.icon:SetTexture("Interface\\Icons\\Ability_DualWield")
    toggle.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    local title = scoreText(toggle, "GameFontNormal", 13)
    title:SetPoint("LEFT", 33, 0)
    title:SetText("PvP")
    title:SetTextColor(1, 0.80, 0.44)
    toggle.statePlate = toggle:CreateTexture(nil, "ARTWORK")
    toggle.statePlate:SetPoint("TOPLEFT", 63, -6)
    toggle.statePlate:SetPoint("BOTTOMRIGHT", -6, 6)
    toggle.state = scoreText(toggle, "GameFontHighlightSmall", 12)
    toggle.state:SetPoint("CENTER", toggle.statePlate)
    note.StyleWarcraftButton(toggle)
    updateButton()

    zoneScore = makeBadge(frame, true)
    zoneScore:SetFrameLevel(toggle:GetFrameLevel())
    zoneScore:SetPoint("TOPRIGHT", toggle, "BOTTOMRIGHT", 0, -5)
    zoneScore.demo = scoreText(zoneScore, "GameFontHighlightSmall", 10)
    zoneScore.demo:SetPoint("BOTTOM", 0, 2)
    zoneScore.demo:SetText(L["Тестовый режим"])
    zoneScore:Hide()
    toggle:SetScript("OnClick", function()
        if not ForeverDeathNoteDB then return end
        ForeverDeathNoteDB.worldTerritories = not enabled()
        dirty = true
        updateButton()
        refresh()
    end)
    toggle:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText(L["Карта территорий"])
        GameTooltip:AddLine(L[enabled() and "Скрыть слой территорий" or "Показать слой территорий"], 1, 1, 1)
        GameTooltip:AddLine(L["Красный — Орда, синий — Альянс."], 0.85, 0.83, 0.78)
        GameTooltip:AddLine(L[note.db and note.db.territoryMode == "shared" and "Общий счёт" or "Мои бои"], 0.9, 0.78, 0.52)
        if note.db and note.DemoData() then GameTooltip:AddLine(L["Тестовый режим"], 0.9, 0.78, 0.52) end
        note.StyleLocaleTooltip(GameTooltip)
        GameTooltip:Show()
    end)
    local function hideTooltip(self)
        if GameTooltip:IsOwned(self) then GameTooltip:Hide() end
    end
    toggle:SetScript("OnLeave", hideTooltip)
    toggle:SetScript("OnHide", hideTooltip)
    frame:HookScript("OnShow", function() dirty = true; refresh() end)
    local elapsed = 0
    toggle:SetScript("OnUpdate", function(_, delta)
        if not enabled() then return end
        elapsed = elapsed + delta
        if elapsed >= 0.13 then
            elapsed = 0
            refresh()
        end
    end)
    if frame:IsShown() then refresh() end
end

local listener = CreateFrame("Frame")
listener:RegisterEvent("ADDON_LOADED")
listener:RegisterEvent("PLAYER_LOGIN")
listener:SetScript("OnEvent", function(self, event, addon)
    if event == "PLAYER_LOGIN" or addon == "Blizzard_WorldMap" then
        attach()
        if toggle then self:UnregisterAllEvents() end
    end
end)
