local _, note = ...
local L = note.L
local window, repaint
local zones = {}
local lower = strlower or string.lower
local region, page, favoritesOnly = "all", 1, false
local pageSize, cardWidth, cardHeight = 6, 317, 134
local regions = {
    { id = "all", name = "Все зоны" },
    { id = 1414, name = "Калимдор" },
    { id = 1415, name = "Восточные королевства" },
}

local flat = "Interface\\Buttons\\WHITE8X8"
local mapIcon = "Interface\\Icons\\INV_Misc_Map_01"
local textColor = { 0.97, 0.90, 0.77 }
local muted = { 0.75, 0.68, 0.56 }
local brass = { 0.80, 0.63, 0.36 }
local horde = { 1.0, 0.58, 0.51 }
local alliance = { 0.60, 0.78, 1.0 }

local function favorites()
    if not note.db.fieldAtlasFavorites then note.db.fieldAtlasFavorites = {} end
    return note.db.fieldAtlasFavorites
end

local function label(parent, font, x, y, width, color)
    local text = note.CreateFontString(parent, nil, "OVERLAY", font)
    text:SetPoint("TOPLEFT", x, y)
    text:SetWidth(width)
    text:SetJustifyH("LEFT")
    text:SetTextColor(unpack(color or textColor))
    return text
end

local function button(parent, title, x, y, w, h, action)
    local control = CreateFrame("Button", nil, parent)
    control:SetPoint("TOPLEFT", x, y)
    control:SetSize(w, h)
    control.caption = label(control, "GameFontHighlightSmall", 5, 0, w - 10)
    control.caption:SetPoint("BOTTOMLEFT", 5, 0)
    control.caption:SetJustifyH("CENTER")
    control.caption:SetText(title)
    control:SetScript("OnClick", action)
    note.StyleWarcraftButton(control)
    local function paint(self)
        note.TintWarcraftButton(self, self.selected)
        self.caption:SetTextColor(unpack(self.selected and note.WarTable.gold or self:IsEnabled() and textColor or muted))
    end
    function control:SetSelected(value)
        self.selected = value
        paint(self)
    end
    control:HookScript("OnEnable", paint)
    control:HookScript("OnDisable", paint)
    paint(control)
    return control
end

local function markTooltip(star)
    local tile = star:GetParent()
    if not tile.zone or not GameTooltip then return end
    GameTooltip:SetOwner(star, "ANCHOR_RIGHT")
    GameTooltip:SetText(L[favorites()[tile.zone.id] and "Убрать из избранного" or "Добавить в избранное"])
    note.StyleLocaleTooltip(GameTooltip)
    GameTooltip:Show()
end

local function hideTooltip(control)
    if GameTooltip and GameTooltip:IsOwned(control) then GameTooltip:Hide() end
end

local function openZone(zone)
    note.WarTable.CloseMenu()
    window:Hide()
    note.OpenTerritories(zone.id, true)
end

local function icon(parent, path, size, layer)
    local texture = parent:CreateTexture(nil, layer or "ARTWORK")
    texture:SetSize(size, size)
    if path then texture:SetTexture(path) end
    return texture
end

local function createTile(parent, index)
    local row, column = math.floor((index - 1) / 2), (index - 1) % 2
    local tile = CreateFrame("Button", nil, parent, "BackdropTemplate")
    tile:SetPoint("TOPLEFT", 184 + column * (cardWidth + 10), -106 - row * (cardHeight + 8))
    tile:SetSize(cardWidth, cardHeight)
    note.WarTable.Panel(tile, 0.085, 0.072, 0.055)

    local host = CreateFrame("Frame", nil, tile)
    host:SetPoint("TOPLEFT", 4, -4)
    host:SetSize(cardWidth - 8, 91)
    local backing = host:CreateTexture(nil, "BACKGROUND")
    backing:SetAllPoints()
    backing:SetTexture("Interface\\AddOns\\ForeverDeathNote\\Art\\WarTable.tga")
    backing:SetVertexColor(0.38, 0.34, 0.28)
    tile.canvas = CreateFrame("Frame", nil, host)
    tile.canvas:SetPoint("CENTER")
    tile.canvas.host, tile.canvas.tiles = host, {}
    tile.noArt = icon(host, mapIcon, 30, "OVERLAY")
    tile.noArt:SetPoint("CENTER")
    tile.noArt:SetAlpha(0.85)

    local band = tile:CreateTexture(nil, "BACKGROUND")
    band:SetPoint("TOPLEFT", 4, -95)
    band:SetPoint("BOTTOMRIGHT", -4, 4)
    band:SetColorTexture(0.055, 0.046, 0.038, 1)
    tile.title = label(tile, "GameFontNormal", 11, -100, 288)
    tile.title:SetWordWrap(false)
    tile.count = label(tile, "GameFontHighlightSmall", 11, -117, 160, muted)
    tile.count:SetWordWrap(false)
    tile.horde = label(tile, "GameFontHighlight", 204, -111, 36, horde)
    note.StyleMapNumber(tile.horde, 17)
    tile.horde:SetJustifyH("RIGHT")
    tile.alliance = label(tile, "GameFontHighlight", 269, -111, 36, alliance)
    note.StyleMapNumber(tile.alliance, 17)
    tile.alliance:SetJustifyH("RIGHT")
    tile.hordeIcon = icon(tile, nil, 21)
    tile.hordeIcon:SetPoint("TOPLEFT", 178, -108)
    note.SetFactionEmblem(tile.hordeIcon, "Horde")
    tile.allianceIcon = icon(tile, nil, 21)
    tile.allianceIcon:SetPoint("TOPLEFT", 247, -108)
    note.SetFactionEmblem(tile.allianceIcon, "Alliance")
    tile.accent = tile:CreateTexture(nil, "ARTWORK")
    tile.accent:SetPoint("TOPLEFT", 4, -94)
    tile.accent:SetPoint("TOPRIGHT", -4, -94)
    tile.accent:SetHeight(1)

    local highlight = tile:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints()
    highlight:SetColorTexture(0.84, 0.72, 0.45, 0.10)

    tile.star = button(tile, "", 280, -7, 29, 27, function()
        if not tile.zone then return end
        local saved, id = favorites(), tile.zone.id
        saved[id] = not saved[id] or nil
        repaint()
        if tile:IsShown() and tile.zone and tile.zone.id == id then markTooltip(tile.star) end
    end)
    tile.star:SetFrameLevel(host:GetFrameLevel() + 3)
    tile.star.icon = icon(tile.star, "Interface\\TargetingFrame\\UI-RaidTargetingIcon_1", 16, "OVERLAY")
    tile.star.icon:SetPoint("CENTER")
    tile.star:SetScript("OnEnter", markTooltip)
    tile.star:SetScript("OnLeave", hideTooltip)
    tile.star:SetScript("OnHide", hideTooltip)
    tile:SetScript("OnClick", function(self)
        if self.zone then openZone(self.zone) end
    end)
    tile:SetScript("OnEnter", function(self)
        if not self.zone or not GameTooltip then return end
        local data = self.zone
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(data.name)
        GameTooltip:AddDoubleLine(L["Орда"], tostring(data.score.Horde), unpack(horde))
        GameTooltip:AddDoubleLine(L["Альянс"], tostring(data.score.Alliance), unpack(alliance))
        GameTooltip:AddLine(L["Боёв в зоне: %d"]:format(data.score.count))
        note.StyleLocaleTooltip(GameTooltip)
        GameTooltip:Show()
    end)
    tile:SetScript("OnLeave", hideTooltip)
    tile:SetScript("OnHide", hideTooltip)
    return tile
end

repaint = function()
    local filtered, query = {}, lower(window.search:GetText())
    local saved = favorites()
    for _, zone in ipairs(zones) do
        if (region == "all" or region == zone.region)
            and (not favoritesOnly or saved[zone.id])
            and (query == "" or lower(zone.name):find(query, 1, true)) then
            filtered[#filtered + 1] = zone
        end
    end
    window.filtered = filtered
    local lastPage = math.max(1, math.ceil(#filtered / pageSize))
    page = math.min(page, lastPage)
    for _, selector in ipairs(window.selectors) do selector:SetSelected(selector.region == region) end
    window.favorites:SetSelected(favoritesOnly)
    for index, tile in ipairs(window.tiles) do
        local zone = filtered[(page - 1) * pageSize + index]
        if tile.zone and (not zone or tile.zone.id ~= zone.id) then hideTooltip(tile.star) end
        tile.zone = zone
        tile:SetShown(zone ~= nil)
        if zone then
            tile.title:SetText(zone.name)
            tile.count:SetText(L["Боёв в зоне: %d"]:format(zone.score.count))
            tile.horde:SetText(tostring(zone.score.Horde))
            tile.alliance:SetText(tostring(zone.score.Alliance))
            tile.star:SetSelected(saved[zone.id] == true)
            tile.star.icon:SetDesaturated(not saved[zone.id])
            tile.star.icon:SetVertexColor(unpack(saved[zone.id] and note.WarTable.gold or muted))
            tile.star.icon:SetAlpha(saved[zone.id] and 1 or 0.7)
            local r, g, b = note.TerritoryColor(zone.score)
            tile.accent:SetColorTexture(r, g, b, zone.score.count > 0 and 0.85 or 0.26)
            local mapID = type(zone.id) == "number" and zone.id or nil
            tile.noArt:SetShown(not note.DrawMapTiles(tile.canvas, mapID))
        end
    end
    window.empty:SetShown(#filtered == 0)
    if #filtered == 0 then
        window.empty:SetText(L[#zones == 0 and "Атлас пока недоступен." or "Нет зон по этому фильтру."])
    end
    window.previous:SetEnabled(page > 1)
    window.next:SetEnabled(page < lastPage)
    window.openAll:SetEnabled(#filtered > 0 and note.OpenAllRecords ~= nil)
    window.pagination:SetText(page .. " / " .. lastPage)
end

local function build()
    local frame = CreateFrame("Frame", "ForeverDeathNoteFieldAtlas", UIParent, "BackdropTemplate")
    frame:SetSize(852, 573)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetToplevel(true)
    note.WarTable.Panel(frame, 0.065, 0.058, 0.050)
    frame:EnableMouse(true)
    local emblem = icon(frame, mapIcon, 31)
    emblem:SetPoint("TOPLEFT", 20, -16)
    local title = label(frame, "GameFontNormalLarge", 64, -16, 400, note.WarTable.gold)
    note.StyleHeadingFont(title)
    title:SetText(L["Боевой атлас"])
    frame.subtitle = label(frame, "GameFontHighlightSmall", 65, -39, 410, muted)
    local searchLabel = label(frame, "GameFontHighlightSmall", 184, -76, 111, muted)
    searchLabel:SetText(L["Поиск"])
    frame.search = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
    frame.search:SetPoint("TOPLEFT", 296, -69)
    frame.search:SetSize(532, 26)
    frame.search:SetAutoFocus(false)
    frame.search:SetMaxLetters(64)
    note.StyleLocaleFont(frame.search)
    frame.search:SetScript("OnTextChanged", function() if window then page = 1; repaint() end end)
    frame.search:SetScript("OnEscapePressed", frame.search.ClearFocus)
    frame.search:SetScript("OnEnterPressed", frame.search.ClearFocus)

    frame.selectors = {}
    for i, data in ipairs(regions) do
        local selector = button(frame, L[data.name], 20, -107 - (i - 1) * 40, 148, 31, function()
            if region == data.id then return end
            region, page = data.id, 1
            repaint()
        end)
        selector.region = data.id
        frame.selectors[#frame.selectors + 1] = selector
    end
    frame.favorites = button(frame, L["Избранные зоны"], 20, -236, 148, 31, function()
        favoritesOnly, page = not favoritesOnly, 1
        repaint()
    end)

    frame.tiles = {}
    for index = 1, pageSize do frame.tiles[index] = createTile(frame, index) end
    frame.empty = label(frame, "GameFontHighlight", 185, -130, 635)
    frame.previous = button(frame, "<", 184, -538, 36, 22, function()
        page = page - 1
        repaint()
    end)
    frame.pagination = label(frame, "GameFontHighlightSmall", 225, -542, 413, brass)
    frame.pagination:SetJustifyH("CENTER")
    frame.next = button(frame, ">", 643, -538, 36, 22, function()
        page = page + 1
        repaint()
    end)
    frame.openAll = button(frame, L["Открыть все"], 688, -538, 140, 22, function()
        note.OpenTerritoryRecords(L["Боевой атлас"], frame.subtitle:GetText(), frame.filtered,
            (page - 1) * pageSize + 1, function(zone, index)
                page = math.ceil(index / pageSize)
                repaint()
                openZone(zone)
            end)
    end)
    if note.StylePageButton then
        note.StylePageButton(frame.previous, "prev")
        note.StylePageButton(frame.next, "next")
        frame.previous.caption:Hide()
        frame.next.caption:Hide()
    end

    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -4, -3)
    close:SetScript("OnClick", function() frame:Hide() end)
    frame:HookScript("OnHide", function() frame.search:ClearFocus() end)
    tinsert(UISpecialFrames, "ForeverDeathNoteFieldAtlas")
    note.ManageWindow(frame, "fieldAtlas", note.WindowDragHandle(frame, 60, 790))
    return frame
end

function note.RefreshFieldAtlas()
    if not window or not window:IsShown() or not note.db then return end
    local scored, demo = note.TerritoryZoneGroups()
    local mode = note.db.territoryMode == "shared" and "Общий счёт" or "Мои бои"
    window.subtitle:SetText((demo and L["ТЕСТ • "] or "") .. L[mode] .. "  /  " .. L["Текущая неделя"])
    zones = {}
    for _, source in ipairs(regions) do
        for _, score in ipairs(scored[source.id] or {}) do
            local name = note.SampleText(score.title or score.name, demo) or L["Зона неизвестна"]
            zones[#zones + 1] = { id = score.key, region = source.id, name = name, score = score }
        end
    end
    table.sort(zones, function(a, b)
        if a.score.count ~= b.score.count then return a.score.count > b.score.count end
        if a.name ~= b.name then return a.name < b.name end
        return tostring(a.id) < tostring(b.id)
    end)
    repaint()
end

function note.OpenFieldAtlas()
    if not note.db then return end
    if not window then window = build() end
    window:Show()
    window:Raise()
    note.RefreshFieldAtlas()
end
