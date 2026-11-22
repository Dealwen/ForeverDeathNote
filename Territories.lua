local _, note = ...
local L = note.L
local window, sample, catalog
local refreshOwnerBanner
local scores, shared
local hoverID, hoverRegion, hoverZone
local continent, selected
local requestedZone
local regions = {
    { id = 1414, name = "Калимдор" },
    { id = 1415, name = "Восточные королевства" },
}
local sides = {
    Horde = { color = { 1, 0.42, 0.31 } },
    Alliance = { color = { 0.38, 0.67, 1 } },
    tie = { color = { 0.95, 0.78, 0.42 } },
    empty = { color = { 0.53, 0.76, 0.47 } },
}
local ownerBannerArt = "Interface\\AddOns\\ForeverDeathNote\\Art\\TerritoryGuildBanner.tga"
local neutralFlag = "Interface\\AddOns\\ForeverDeathNote\\Art\\NeutralPennant.tga"
local guildAtlas = "Interface\\GuildFrame\\GuildFrame"
local unknownCrest = "Interface\\GuildFrame\\GuildLogo-NoLogo"
local flat = "Interface\\Buttons\\WHITE8X8"
local tabardLookups = {}
local terrainFiles = {
    [1414] = "Interface\\AddOns\\ForeverDeathNote\\Art\\TerritoryKalimdor.jpg",
    [1415] = "Interface\\AddOns\\ForeverDeathNote\\Art\\TerritoryEasternKingdoms.jpg",
}

local function tabardCache()
    local realms = ForeverDeathNoteDB and ForeverDeathNoteDB.territoryTabards
    return realms and realms[note.scope]
end

local function tabardColor(value)
    local color = note.Public(value)
    if type(color) ~= "table" then return end
    local r, g, b = note.Public(color.r), note.Public(color.g), note.Public(color.b)
    if type(r) == "number" and r >= 0 and r <= 1 and type(g) == "number" and g >= 0 and g <= 1
        and type(b) == "number" and b >= 0 and b <= 1 then
        return { r, g, b }
    end
end

local function setMarkerArt(marker, zone, size)
    local icon, owner = marker.icon, zone.owner
    icon:SetVertexColor(1, 1, 1)
    marker.crestField:SetShown(owner ~= nil)
    marker.crestRim:SetShown(owner ~= nil)
    if owner then
        local cache = tabardCache()
        local crest = cache and cache[owner.faction .. ":" .. owner.id]
        local r, g, b = unpack(sides[owner.faction].color)
        marker.crestField:SetSize(size, size)
        marker.crestRim:SetSize(size, size)
        if crest then
            marker.crestField:SetVertexColor(unpack(crest.background))
            marker.crestRim:SetVertexColor(unpack(crest.border))
            icon:SetTexture(crest.file)
            -- The emblem occupies the lower-left quarter of the tabard texture.
            icon:SetTexCoord(0, 0.5, 0.5, 1)
            icon:SetVertexColor(unpack(crest.emblem))
        else
            marker.crestField:SetVertexColor(r * 0.24, g * 0.24, b * 0.24)
            marker.crestRim:SetVertexColor(r, g, b)
            icon:SetTexture(unknownCrest)
            icon:SetTexCoord(0, 1, 0, 1)
        end
        icon:SetSize(size * 0.78, size * 0.78)
    else
        icon:SetSize(size, size)
        if zone.leadingFaction then
            note.SetFactionEmblem(icon, zone.leadingFaction)
        else
            icon:SetTexture(neutralFlag)
            icon:SetTexCoord(0, 1, 0, 1)
        end
    end
end

function note.CacheTerritoryTabard(unit, guild, faction, guildRealm)
    if not guild or not faction or not note.scope or not C_GuildInfo or not C_GuildInfo.GetGuildTabardInfo
        or InCombatLockdown() then return end
    if guildRealm and guildRealm:gsub("%s", "") ~= GetRealmName():gsub("%s", "") then return end
    local key = faction .. ":" .. (strlower or string.lower)(guild)
    local now = GetTime()
    local lookup = key .. ":" .. (unit:find("^nameplate") and "nameplate" or unit)
    if (tabardLookups[lookup] or 0) > now then return end
    if unit ~= "player" then tabardLookups[lookup] = now + 5 end

    local ok, raw = pcall(C_GuildInfo.GetGuildTabardInfo, unit)
    local info = ok and note.Public(raw)
    if type(info) ~= "table" then return end
    local file = note.PositiveInteger(info.emblemFileID, 2147483647)
    local background = tabardColor(info.backgroundColor)
    local border = tabardColor(info.borderColor)
    local emblem = tabardColor(info.emblemColor)
    if not file or not background or not border or not emblem then return end
    tabardLookups[lookup] = now + 60

    local realms = ForeverDeathNoteDB.territoryTabards or {}
    local cache = realms[note.scope] or {}
    cache[key] = { file = file, background = background, border = border, emblem = emblem }
    realms[note.scope], ForeverDeathNoteDB.territoryTabards = cache, realms
    if not window or not window:IsVisible() then return end
    local current = window.zone and window.zone.owner
    if current and current.faction .. ":" .. current.id == key then refreshOwnerBanner(window, window.zone) end
    for _, marker in ipairs(window.canvas.markers) do
        local owner = marker.zone and marker.zone.owner
        if marker:IsShown() and owner and owner.faction .. ":" .. owner.id == key then
            setMarkerArt(marker, marker.zone, marker:GetWidth())
        end
    end
end

function note.StyleMapNumber(region, size)
    note.StyleNumberFont(region)
    local file = region:GetFont()
    if file then region:SetFont(file, size, "OUTLINE") end
    region:SetShadowColor(0, 0, 0, 1)
    region:SetShadowOffset(1, -1)
end

local function zoneName(zone)
    return note.SampleText(zone.title, sample) or L["Зона неизвестна"]
end

local function ownerName(zone)
    if zone and zone.owner then return zone.owner.name end
    return L[zone and zone.ownerTie and "Ничья" or "Без владельца"]
end

local function topKillerName(zone)
    if not zone or not zone.topKills or zone.topKills == 0 then return L["Пока нет добиваний."] end
    return zone.topKillerTie and L["Ничья"] or zone.topKiller and zone.topKiller.name or L["Имя неизвестно"]
end

function note.OpenTerritoryRecords(title, subtitle, rows, startIndex, onSelect)
    if not note.OpenAllRecords then return end
    note.OpenAllRecords({
        title = title,
        subtitle = subtitle,
        rows = rows,
        startIndex = startIndex,
        columns = {
            { label = L["Зона"], weight = 5 },
            { label = L["Гильдия-владелец"], weight = 4 },
            { label = L["Добивания владельца"], weight = 2, justify = "RIGHT" },
            { label = L["Орда"], weight = 1.5, justify = "RIGHT" },
            { label = L["Альянс"], weight = 1.5, justify = "RIGHT" },
        },
        cells = function(row)
            local zone = row.score or row
            return { row.score and row.name or zoneName(zone), ownerName(zone), zone.ownerKills or 0,
                { text = zone.Horde, color = sides.Horde.color },
                { text = zone.Alliance, color = sides.Alliance.color } }
        end,
        onSelect = onSelect,
    })
end

local function standing(zone)
    if zone.leadingFaction then return sides[zone.leadingFaction] end
    return zone.ownerTie and sides.tie or sides.empty
end

local function territoryTint(zone)
    if zone.owner then return note.TerritoryGuildTint(zone.owner.name) end
    return unpack(standing(zone).color)
end

local function getCatalog()
    if catalog then return catalog end
    local index = {}
    local zoneType = Enum and Enum.UIMapType and Enum.UIMapType.Zone or 3
    if C_Map and C_Map.GetMapChildrenInfo then
        for _, region in ipairs(regions) do
            for _, info in ipairs(C_Map.GetMapChildrenInfo(region.id, zoneType, true) or {}) do
                if info.mapID and not index[info.mapID] then
                    index[info.mapID] = { region = region.id, title = info.name }
                end
            end
        end
    end
    if next(index) then catalog = index end
    return index
end

local function zoneMap(id, index)
    if not id then return nil end
    local best = id
    for _ = 1, 12 do
        if index[id] then return id, index[id].region, index[id].title end
        local info = C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(id)
        if not info then break end
        local mapType = Enum and Enum.UIMapType
        if info.mapType == (mapType and mapType.Zone or 3) then
            best = id
        elseif info.mapType == (mapType and mapType.Continent or 2) then
            if id == 1414 or id == 1415 then return best, id, best == id and info.name or nil end
            break
        end
        if not info.parentMapID or info.parentMapID == 0 or info.parentMapID == id then break end
        id = info.parentMapID
    end
    return best
end

local function mapCenter(id, region)
    if not C_Map then return end
    if C_Map.GetMapRectOnMap then
        local left, right, top, bottom = C_Map.GetMapRectOnMap(id, region)
        if left and right and top and bottom and right > left and bottom > top then
            local x, y = (left + right) / 2, (top + bottom) / 2
            if x > 0 and x < 1 and y > 0 and y < 1 then return x, y end
        end
    end
    if not (C_Map.GetWorldPosFromMapPos and C_Map.GetMapPosFromWorldPos and CreateVector2D) then return end
    local world, pos = C_Map.GetWorldPosFromMapPos(id, CreateVector2D(0.5, 0.5))
    if not world or not pos then return end
    local map, point = C_Map.GetMapPosFromWorldPos(world, pos, region)
    if map == region and point then
        local x, y = point:GetXY()
        if x > 0 and x < 1 and y > 0 and y < 1 then return x, y end
    end
end

local function collect(data, useShared)
    local index, mapped, locations = getCatalog(), {}, {}
    local function key(entry)
        local id = note.EncounterMapID(entry)
        if not id then return end
        if not mapped[id] then
            local mapID, region, name = zoneMap(id, index)
            mapped[id] = { mapID = mapID, region = region, title = name }
        end
        local location = mapped[id]
        locations[location.mapID] = location
        return location.mapID
    end
    local total, entries = note.FrontWeek(data, nil, key, useShared)
    local byRegion, included = { [0] = {}, [1414] = {}, [1415] = {} }, {}
    for _, zone in ipairs(entries) do
        local location = locations[zone.key]
        zone.title = location and location.title or zone.name
        if zone.pin and zone.pin.mapId ~= zone.key then
            local parentPin
            for entry in pairs(zone.entries) do
                if entry.mapId == zone.key and entry.x and entry.y and (not parentPin or entry.at > parentPin.at) then
                    parentPin = entry
                end
            end
            zone.pin = parentPin or zone.pin
        end
        local region = location and location.region or 0
        local list = byRegion[region]
        list[#list + 1] = zone
        included[zone.key] = true
    end
    local blank = { [1414] = {}, [1415] = {} }
    for id, info in pairs(index) do
        if info.region and info.title and not included[id] then
            local list = blank[info.region]
            list[#list + 1] = { key = id, title = info.title, Horde = 0, Alliance = 0, count = 0 }
        end
    end
    for region, zones in pairs(blank) do
        table.sort(zones, function(a, b)
            if a.title == b.title then return a.key < b.key end
            return a.title < b.title
        end)
        for _, zone in ipairs(zones) do
            local list = byRegion[region]
            list[#list + 1] = zone
        end
    end
    return total, byRegion
end

local function label(parent, font, x, y, width)
    local text = note.CreateFontString(parent, nil, "OVERLAY", font)
    text:SetPoint("TOPLEFT", x, y)
    text:SetWidth(width)
    text:SetJustifyH("LEFT")
    return text
end

local function sizeText(text, size)
    local file, _, flags = text:GetFont()
    if file then text:SetFont(file, size, flags or "") end
end

local function layoutBannerEmblem(banner, crest)
    banner.crestField:SetShown(crest ~= nil)
    banner.crestLeft:SetShown(crest ~= nil)
    banner.crestRight:SetShown(crest ~= nil)
    if not crest then return end

    -- Tabard files store half of the design at the left edge of a 512 x 1024 texture.
    local right, top, bottom = 360, 248, 816
    if crest.file == 414878 then
        -- The gnome emblem has a narrower silhouette than the common tabard crop.
        right, top, bottom = 240, 302, 738
    end
    local scale = math.min(15 / right, 31 / (bottom - top))
    local r, g, b = unpack(crest.emblem)
    local left, rightHalf = banner.crestLeft, banner.crestRight
    for _, half in ipairs(banner.crestHalves) do
        half:SetTexture(crest.file)
        half:SetSize(right * scale, (bottom - top) * scale)
        half:SetVertexColor(0.56 + 0.44 * r, 0.56 + 0.44 * g, 0.56 + 0.44 * b)
    end
    left:SetTexCoord(right / 512, 0, top / 1024, bottom / 1024)
    rightHalf:SetTexCoord(0, right / 512, top / 1024, bottom / 1024)
end

function refreshOwnerBanner(frame, zone)
    local banner, owner = frame.ownerBanner, zone and zone.owner
    banner:SetShown(owner ~= nil)
    frame.ownerStatus:SetShown(owner == nil)
    if not owner then
        frame.status:SetText(ownerName(zone))
        if zone then frame.status:SetTextColor(territoryTint(zone))
        else frame.status:SetTextColor(unpack(sides.empty.color)) end
        return
    end

    banner.name:SetText(owner.name)
    sizeText(banner.name, 18)
    local nameWidth = banner.name.GetUnboundedStringWidth and banner.name:GetUnboundedStringWidth()
        or banner.name:GetStringWidth()
    if nameWidth > banner.name:GetWidth() then
        sizeText(banner.name, math.max(10, math.floor(18 * banner.name:GetWidth() / nameWidth)))
    end
    banner.kills:SetText(L["Добивания гильдии: %d"]:format(zone.ownerKills or 0))

    local cache = tabardCache()
    layoutBannerEmblem(banner, cache and cache[owner.faction .. ":" .. owner.id])
end

local function button(parent, caption, x, y, width, action)
    local control = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    control:SetPoint("TOPLEFT", x, y)
    control:SetSize(width, 24)
    note.StyleLocaleButton(control)
    if note.StyleWarcraftButton then note.StyleWarcraftButton(control) end
    control:SetText(caption)
    control:SetScript("OnClick", action)
    return control
end

local function tooltip(control, target, anchor)
    local zone = target or control.zone
    if not zone then return end
    GameTooltip:SetOwner(control, anchor or "ANCHOR_RIGHT")
    GameTooltip:SetText(zoneName(zone))
    GameTooltip:AddDoubleLine(L["Гильдия-владелец"], ownerName(zone), 0.92, 0.80, 0.56, territoryTint(zone))
    if zone.ownerKills and zone.ownerKills > 0 then
        GameTooltip:AddDoubleLine(L["Добивания владельца"], tostring(zone.ownerKills), 0.92, 0.80, 0.56, 1, 1, 1)
    end
    local killer = topKillerName(zone)
    if zone.topKills and zone.topKills > 0 then killer = ("%s (%d)"):format(killer, zone.topKills) end
    GameTooltip:AddDoubleLine(L["Лидер по добиваниям"], killer, 0.92, 0.80, 0.56, 1, 1, 1)
    GameTooltip:AddDoubleLine(L["Орда"], tostring(zone.Horde), 1, 0.42, 0.31, 1, 1, 1)
    GameTooltip:AddDoubleLine(L["Альянс"], tostring(zone.Alliance), 0.38, 0.67, 1, 1, 1, 1)
    if shared and zone.shared and zone.shared > 0 then
        GameTooltip:AddLine(L["От других игроков: %d"]:format(zone.shared), 0.85, 0.84, 0.80)
    end
    note.StyleLocaleTooltip(GameTooltip)
    GameTooltip:Show()
end

local function hideTooltip(control)
    if GameTooltip:IsOwned(control) then GameTooltip:Hide() end
end

local function selectZone(id)
    for _, zone in ipairs(scores[continent]) do
        if zone.key == id then
            selected = id
            note.RefreshTerritories()
            return
        end
    end
end

local updateHover, wireMapInput
local function markerFor(canvas, index)
    local marker = canvas.markers[index]
    if marker then return marker end
    marker = CreateFrame("Button", nil, canvas)
    -- The GuildFrame sheet stores the tabard's tintable disk and rim separately.
    marker.crestField = marker:CreateTexture(nil, "ARTWORK", nil, -2)
    marker.crestField:SetPoint("CENTER")
    marker.crestField:SetTexture(guildAtlas)
    marker.crestField:SetTexCoord(0.63183594, 0.69238281, 0.61914063, 0.74023438)
    marker.crestRim = marker:CreateTexture(nil, "ARTWORK", nil, 1)
    marker.crestRim:SetPoint("CENTER")
    marker.crestRim:SetTexture(guildAtlas)
    marker.crestRim:SetTexCoord(0.63183594, 0.69238281, 0.74414063, 0.86523438)
    marker.icon = marker:CreateTexture(nil, "ARTWORK")
    marker.icon:SetPoint("CENTER")
    marker.zonePlate = marker:CreateTexture(nil, "BACKGROUND")
    marker.zonePlate:SetAllPoints()
    marker.zonePlate:SetColorTexture(0.035, 0.046, 0.058, 0.83)
    marker.zoneLabel = note.CreateFontString(marker, nil, "OVERLAY", "GameFontHighlightSmall")
    marker.zoneLabel:SetPoint("CENTER", 0, 1)
    marker.zoneLabel:SetTextColor(0.99, 0.93, 0.79)
    marker.zoneLabel:SetWordWrap(false)
    marker:SetSize(24, 20)
    marker.tint = canvas:CreateTexture(nil, "ARTWORK", nil, -2)
    marker.border = canvas:CreateTexture(nil, "ARTWORK", nil, 1)
    marker.badge = marker:CreateTexture(nil, "ARTWORK", nil, 2)
    marker.badge:SetHeight(18)
    marker.badge:SetPoint("TOP", marker, "BOTTOM", 0, -1)
    marker.badge:SetColorTexture(0.075, 0.047, 0.027, 0.93)
    marker.badgeEdge = marker:CreateTexture(nil, "ARTWORK", nil, 3)
    marker.badgeEdge:SetPoint("BOTTOMLEFT", marker.badge, "BOTTOMLEFT")
    marker.badgeEdge:SetPoint("BOTTOMRIGHT", marker.badge, "BOTTOMRIGHT")
    marker.badgeEdge:SetHeight(1)
    marker.count = note.CreateFontString(marker, nil, "OVERLAY", "GameFontNormal")
    note.StyleMapNumber(marker.count, 15)
    marker.count:SetPoint("CENTER", marker.badge, "CENTER", 0, 1)
    marker.count:SetJustifyH("CENTER")
    marker:SetScript("OnHide", hideTooltip)
    marker:SetScript("OnClick", function(self)
        if self.zone and not self.mapDragged and canvas.viewport:IsMouseOver() then
            selectZone(self.zone.key)
        end
    end)
    marker:SetScript("OnEnter", function(self)
        if canvas.drag or not canvas.viewport:IsMouseOver() then return end
        tooltip(self)
        local x, y = mapCenter(self.zone.key, continent)
        updateHover(canvas, self.zone, x, y)
    end)
    marker:SetScript("OnLeave", function(self)
        hideTooltip(self)
        updateHover(canvas)
    end)
    wireMapInput(marker, canvas)
    canvas.markers[index] = marker
    return marker
end

local function drawTerritoryTerrain(canvas)
    local file = terrainFiles[continent]
    if not file or (canvas.terrainMap ~= continent and canvas.terrain:SetTexture(file) == false) then
        canvas.terrainMap = nil
        canvas.terrain:Hide()
        return note.DrawMapTiles(canvas, continent)
    end
    if canvas.terrainMap ~= continent or not canvas.terrain:IsShown() then
        canvas.terrainMap = continent
        for _, tile in ipairs(canvas.tiles) do tile:Hide() end
        canvas.ready = nil
        local width = math.min(canvas.viewport:GetWidth(), canvas.viewport:GetHeight() * 1.5)
        canvas.baseWidth, canvas.baseHeight = width, width / 1.5
        -- The projected artwork is stored at 1024x1024 for the game texture loader.
        canvas.terrain:SetTexCoord(0, 1, 0, 683 / 1024)
        canvas.terrain:Show()
    end
    return true
end

local function mapOffset(offset, viewportSize, mapSize)
    if mapSize <= viewportSize then return (viewportSize - mapSize) / 2 end
    return math.max(viewportSize - mapSize, math.min(0, offset or 0))
end

local function positionMap(canvas, x, y)
    local viewport = canvas.viewport
    canvas.offsetX = mapOffset(x, viewport:GetWidth(), canvas:GetWidth())
    canvas.offsetY = mapOffset(y, viewport:GetHeight(), canvas:GetHeight())
    canvas:ClearAllPoints()
    canvas:SetPoint("TOPLEFT", viewport, "TOPLEFT", canvas.offsetX, -canvas.offsetY)
end

local function viewportCursor(viewport)
    local left, top = viewport:GetLeft(), viewport:GetTop()
    if not left or not top then return end
    local x, y = GetCursorPosition()
    local scale = viewport:GetEffectiveScale()
    return x / scale - left, top - y / scale
end

-- World Map highlights can have black padding. Additive blending keeps it invisible.
function note.DrawTerritoryTint(texture, canvas, mapID, zoneID, x, y, r, g, b, alpha)
    texture:Hide()
    if not (C_Map and C_Map.GetMapInfoAtPosition and C_Map.GetMapHighlightInfoAtPosition) then return end
    local hit = C_Map.GetMapInfoAtPosition(mapID, x, y)
    if not hit or zoneMap(hit.mapID, getCatalog()) ~= zoneID then return end
    local file, atlas, cropX, cropY, width, height, left, top = C_Map.GetMapHighlightInfoAtPosition(mapID, x, y)
    if not (width and height and left and top and width > 0 and height > 0) then return end
    local w, h = canvas:GetWidth(), canvas:GetHeight()
    texture:ClearAllPoints()
    if atlas and atlas ~= "" and (not C_Texture or not C_Texture.GetAtlasInfo or C_Texture.GetAtlasInfo(atlas)) then
        -- Reset positional UVs left by a file highlight before the game applies atlas UVs.
        texture:SetTexCoord(0, 1, 0, 1)
        if texture:SetAtlas(atlas, false) == false then return end
        texture:SetPoint("CENTER", canvas, "TOPLEFT", (left + width / 2) * w, -(top + height / 2) * h)
    elseif file and file > 0 and cropX and cropY then
        if texture:SetTexture(file, nil, nil, "TRILINEAR") == false then return end
        texture:SetTexCoord(0, cropX, 0, cropY)
        texture:SetPoint("TOPLEFT", canvas, "TOPLEFT", left * w, -top * h)
    else
        return
    end
    texture:SetSize(width * w, height * h)
    texture:SetBlendMode("ADD")
    texture:SetVertexColor(r, g, b)
    texture:SetAlpha(alpha)
    texture:Show()
    return true
end

local function paintZone(texture, canvas, zone, x, y, r, g, b, hovered)
    texture:Hide()
    if not hovered and zone.Horde + zone.Alliance == 0 then return end
    return note.DrawTerritoryTint(texture, canvas, continent, zone.key, x, y, r, g, b, hovered and 0.90 or 0.28)
end

local function cursorMapPoint(canvas)
    local left, top = canvas:GetLeft(), canvas:GetTop()
    if not left or not top then return end
    local x, y = GetCursorPosition()
    local scale = canvas:GetEffectiveScale()
    x, y = (x / scale - left) / canvas:GetWidth(), (top - y / scale) / canvas:GetHeight()
    if x >= 0 and x <= 1 and y >= 0 and y <= 1 then return x, y end
end

local function findZoneAt(x, y)
    if not x then return end
    if not (C_Map and C_Map.GetMapInfoAtPosition) then return end
    local info = C_Map.GetMapInfoAtPosition(continent, x, y)
    if not info then return end
    local id = zoneMap(info.mapID, getCatalog())
    for _, zone in ipairs(scores[continent]) do
        if zone.key == id then return zone end
    end
end

function note.TerritoryShape(cache, mapID, zoneID)
    local shapes = cache[mapID] or {}
    cache[mapID] = shapes
    if shapes[zoneID] then return shapes[zoneID] end
    local spans = {}
    shapes[zoneID] = spans
    if not (C_Map and C_Map.GetMapRectOnMap and C_Map.GetMapInfoAtPosition) then return spans end
    local left, right, top, bottom = C_Map.GetMapRectOnMap(zoneID, mapID)
    if not (left and top and right and bottom and left < right and top < bottom) then return spans end
    left, right, top, bottom = math.max(0, left), math.min(1, right), math.max(0, top), math.min(1, bottom)
    if left >= right or top >= bottom then return spans end
    local cols = math.max(8, math.ceil((right - left) * 160))
    local rows = math.max(8, math.ceil((bottom - top) * 120))
    local dx, dy = (right - left) / cols, (bottom - top) / rows
    local rectangular = true
    for row = 0, rows - 1 do
        local y, first = top + row * dy
        for column = 0, cols do
            local x = left + column * dx
            local hit = column < cols and C_Map.GetMapInfoAtPosition(mapID, x + dx / 2, y + dy / 2)
            local id = hit and zoneMap(hit.mapID, getCatalog())
            if id == zoneID then first = first or x
            elseif first then
                spans[#spans + 1] = { first, y, x - first, dy }
                first = nil
            end
            if column < cols and id ~= zoneID then rectangular = false end
        end
    end
    -- A rectangular map extent doesn't provide a boundary to paint.
    if rectangular then shapes[zoneID] = {} end
    return shapes[zoneID]
end

updateHover = function(canvas, zone, x, y)
    if hoverID == (zone and zone.key) and hoverRegion == continent then return end
    hoverID, hoverRegion, hoverZone = zone and zone.key, continent, zone
    canvas.hover:Hide()
    for _, strip in ipairs(canvas.shading) do strip:Hide() end
    if not zone then return end
    local r, g, b = unpack(standing(zone).color)
    if note.DrawTerritoryContour(canvas.hover, canvas, continent, zone.key, false, 1, 0.94, 0.70, 1) then return end
    if x and paintZone(canvas.hover, canvas, zone, x, y, r, g, b, true) then return end
    local w, h = canvas:GetWidth(), canvas:GetHeight()
    for i, span in ipairs(note.TerritoryShape(canvas.shapes, continent, zone.key)) do
        local strip = canvas.shading[i] or canvas:CreateTexture(nil, "ARTWORK", nil, 2)
        canvas.shading[i] = strip
        strip:ClearAllPoints()
        strip:SetPoint("TOPLEFT", canvas, "TOPLEFT", span[1] * w, -span[2] * h)
        strip:SetSize(span[3] * w, span[4] * h)
        strip:SetColorTexture(r, g, b, 0.42)
        strip:Show()
    end
end

local function refreshMap(zones)
    local canvas = window.canvas
    updateHover(canvas)
    if canvas.cameraMap ~= continent then
        canvas.cameraMap, canvas.zoom, canvas.offsetX, canvas.offsetY = continent, 1, nil, nil
        canvas.drag = nil
    end
    local hasArt = drawTerritoryTerrain(canvas)
    if canvas.terrainMap then
        canvas:SetSize(canvas.baseWidth * canvas.zoom, canvas.baseHeight * canvas.zoom)
    else
        canvas.zoom = 1
    end
    positionMap(canvas, canvas.offsetX, canvas.offsetY)
    canvas.zoomOut:SetEnabled(canvas.terrainMap ~= nil and canvas.zoom > 1)
    canvas.zoomIn:SetEnabled(canvas.terrainMap ~= nil and canvas.zoom < 4)
    canvas.zoomReset:SetEnabled(canvas.terrainMap ~= nil and canvas.zoom > 1)
    canvas.zoomReset:SetText(("%d%%"):format(math.floor(canvas.zoom * 100 + 0.5)))
    canvas:SetShown(hasArt == true)
    window.missing:SetShown(not hasArt)

    local count, labels = 0, {}
    local function showMarker(target, x, y)
        count = count + 1
        local marker = markerFor(canvas, count)
        local r, g, b = territoryTint(target)
        marker.zone = target
        if not target.owner or not note.DrawTerritoryContour(marker.tint, canvas, continent, target.key, true, r, g, b, 0.85) then
            paintZone(marker.tint, canvas, target, x, y, r, g, b)
        end
        if target.key == selected then
            note.DrawTerritoryContour(marker.border, canvas, continent, target.key, false, 1, 0.89, 0.54, 1)
        elseif target.owner or target.Horde + target.Alliance > 0 then
            note.DrawTerritoryContour(marker.border, canvas, continent, target.key, false, r, g, b, 0.78)
        else
            note.DrawTerritoryContour(marker.border, canvas, continent, target.key, false, 0.84, 0.72, 0.52, 0.4)
        end
        local px, py = x * canvas:GetWidth(), y * canvas:GetHeight()
        marker:ClearAllPoints()
        marker:SetPoint("CENTER", canvas, "TOPLEFT", px, -py)
        local total = target.ownerKills or 0
        local quiet = not target.owner and target.Horde + target.Alliance == 0
        marker.zonePlate:SetShown(quiet)
        marker.zoneLabel:SetShown(quiet)
        marker.icon:SetShown(not quiet)
        if quiet then
            marker.crestField:Hide()
            marker.crestRim:Hide()
            marker.badge:Hide()
            marker.badgeEdge:Hide()
            marker.count:Hide()
            marker.zoneLabel:SetText(zoneName(target))
            local width, height = marker.zoneLabel:GetStringWidth() + 8, 14
            marker:SetSize(width, height)
            marker:SetFrameLevel(canvas:GetFrameLevel() + 2)
            if px - width / 2 < 2 or px + width / 2 > canvas:GetWidth() - 2
                or py - height / 2 < 2 or py + height / 2 > canvas:GetHeight() - 2 then
                marker:Hide()
                return
            end
            for _, placed in ipairs(labels) do
                if math.abs(px - placed.x) < (width + placed.w) / 2 + 3
                    and math.abs(py - placed.y) < (height + placed.h) / 2 + 3 then
                    marker:Hide()
                    return
                end
            end
            labels[#labels + 1] = { x = px, y = py, w = width, h = height }
            marker:Show()
            return
        end
        local size = target.owner and (target.key == selected and 34 or 29) or total > 0 and 24 or 17
        marker:SetSize(math.max(size, 21), math.max(size, 21))
        marker:SetFrameLevel(canvas:GetFrameLevel() + (target.key == selected and 4 or total > 0 and 3 or 2))
        setMarkerArt(marker, target, size)
        marker.icon:SetAlpha(target.key == selected and 1 or total > 0 and 0.94 or 0.81)
        marker.badge:SetShown(total > 0)
        marker.badgeEdge:SetShown(total > 0)
        marker.badgeEdge:SetColorTexture(r, g, b, 0.88)
        marker.count:SetShown(total > 0)
        marker.count:SetTextColor(1, 0.97, 0.87)
        marker.count:SetText(tostring(total))
        marker.badge:SetWidth(math.max(22, marker.count:GetStringWidth() + 10))
        labels[#labels + 1] = { x = px, y = py + (total > 0 and 7 or 0),
            w = math.max(size, marker.badge:GetWidth()), h = size + (total > 0 and 16 or 0) }
        marker:Show()
    end
    if hasArt then
        -- Place scored zones first. They remain above quiet zones when markers overlap.
        for _, target in ipairs(zones) do
            if type(target.key) == "number" then
                local x, y = mapCenter(target.key, continent)
                if x and y then showMarker(target, x, y) end
            end
        end
    end
    for i = count + 1, #canvas.markers do
        canvas.markers[i]:Hide()
        canvas.markers[i].tint:Hide()
        canvas.markers[i].border:Hide()
    end
end

local function zoomMap(canvas, zoom, x, y)
    if not canvas.terrainMap or not scores or canvas.drag then return end
    zoom = math.max(1, math.min(4, zoom))
    if zoom == canvas.zoom then return end
    x, y = x or canvas.viewport:GetWidth() / 2, y or canvas.viewport:GetHeight() / 2
    local ratio = zoom / canvas.zoom
    canvas.offsetX = x - (x - canvas.offsetX) * ratio
    canvas.offsetY = y - (y - canvas.offsetY) * ratio
    canvas.zoom = zoom
    hideTooltip(canvas)
    for _, marker in ipairs(canvas.markers) do hideTooltip(marker) end
    refreshMap(scores[continent])
end

wireMapInput = function(control, canvas)
    control:EnableMouseWheel(true)
    control:RegisterForDrag("LeftButton")
    control:HookScript("OnMouseDown", function(self, mouseButton)
        if mouseButton == "LeftButton" then self.mapDragged = nil end
    end)
    control:SetScript("OnMouseWheel", function(_, delta)
        if not canvas.viewport:IsMouseOver() then return end
        zoomMap(canvas, canvas.zoom * 1.25 ^ delta, viewportCursor(canvas.viewport))
    end)
    control:SetScript("OnDragStart", function(self)
        if canvas.zoom <= 1 or not canvas.viewport:IsMouseOver() then return end
        local x, y = viewportCursor(canvas.viewport)
        if not x then return end
        self.mapDragged = true
        canvas.drag = { x = x, y = y, offsetX = canvas.offsetX, offsetY = canvas.offsetY }
        hideTooltip(self)
        hideTooltip(canvas)
        updateHover(canvas)
    end)
    control:SetScript("OnDragStop", function() canvas.drag = nil end)
end

function note.TerritoryZoneGroups(useShared)
    if useShared == nil then useShared = note.db.territoryMode == "shared" end
    local demo = note.DemoData()
    local _, zones = collect(demo, useShared)
    return zones, demo
end

function note.GuildTerritoryShare(guild)
    local groups = note.TerritoryZoneGroups()
    local owned, total = 0, 0
    for _, region in ipairs(regions) do
        for _, zone in ipairs(groups[region.id]) do
            total = total + 1
            if zone.owner and zone.owner.id == guild.id
                and (not guild.faction or guild.faction == "Mixed" or guild.faction == zone.owner.faction) then
                owned = owned + 1
            end
        end
    end
    return owned, total
end

function note.TerritoryZones(mapID)
    local region = mapID
    local wide = region == 1414 or region == 1415
    if not wide then
        mapID, region = zoneMap(mapID, getCatalog())
        if not region then return end
    end
    local zones, demo = note.TerritoryZoneGroups()
    if wide then return zones[region], demo end
    for _, zone in ipairs(zones[region]) do
        if zone.key == mapID then return { zone }, demo end
    end
end

function note.ZoneTerritoryScore(mapID)
    local zoneID, region, name = zoneMap(mapID, getCatalog())
    if not zoneID then return end
    local info = C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(zoneID)
    name = name or info and info.name
    local groups = note.TerritoryZoneGroups()
    for _, zone in ipairs(groups[region or 0]) do
        if zone.key == zoneID then return zone.title or name, zone.Horde, zone.Alliance end
    end
    return name, 0, 0
end

function note.TerritoryColor(zone)
    return unpack(standing(zone).color)
end

function note.TerritoryCenter(zoneID, mapID)
    return mapCenter(zoneID, mapID)
end

function note.RefreshTerritories()
    if note.InvalidateWorldTerritories then note.InvalidateWorldTerritories() end
    if note.QueueZoneScoreRefresh then note.QueueZoneScoreRefresh() end
    if note.RefreshFieldAtlas then note.RefreshFieldAtlas() end
    if note.RefreshGuildTerritoryStats then note.RefreshGuildTerritoryStats() end
    if not window or not window:IsVisible() then return end
    local demo = note.DemoData()
    if demo ~= sample then sample, continent, selected = demo, nil, nil end
    local total
    total, scores = collect(sample, shared)
    if requestedZone then
        for _, region in ipairs(regions) do
            for _, zone in ipairs(scores[region.id]) do
                if zone.key == requestedZone then
                    continent, selected = region.id, zone.key
                    break
                end
            end
            if selected == requestedZone then break end
        end
        requestedZone = nil
    end
    if not continent then
        local west, east = scores[1414][1], scores[1415][1]
        local westCount, eastCount = west and west.count or 0, east and east.count or 0
        continent = eastCount > westCount and 1415 or 1414
    end
    local zones = scores[continent]
    local zone
    for _, candidate in ipairs(zones) do
        if candidate.key == selected then
            zone = candidate
            break
        end
    end
    zone = zone or zones[1]
    selected = zone and zone.key
    window.zone = zone
    local source = shared and (L["Общий счёт"] .. " · " .. L["От других игроков: %d"]:format(total.shared))
        or L["Личный журнал"]
    window.source:SetText((sample and L["ТЕСТ • "] or "") .. source .. "  /  "
        .. date("!%d.%m", total.start) .. " – " .. date("!%d.%m", total.ends - 1) .. " UTC")
    window.mine:SetEnabled(shared and true or false)
    window.community:SetEnabled(not shared)
    window.exchange:SetShown(shared and true or false)
    for _, region in ipairs(regions) do
        local tab, active = window.tabs[region.id], region.id == continent
        tab:SetEnabled(not active)
        if note.TintWarcraftButton then note.TintWarcraftButton(tab, active) end
    end
    if note.TintWarcraftButton then
        note.TintWarcraftButton(window.mine, not shared)
        note.TintWarcraftButton(window.community, shared)
    end
    window.selection:SetText(zone and zoneName(zone) or L["За эту неделю пока нет боёв с известной зоной."])
    refreshOwnerBanner(window, zone)
    window.horde:SetText(tostring(zone and zone.Horde or 0))
    window.alliance:SetText(tostring(zone and zone.Alliance or 0))
    window.topKiller:SetText(topKillerName(zone))
    window.topKillerCount:SetText(zone and zone.topKills and zone.topKills > 0 and tostring(zone.topKills) or "")
    window.log:SetEnabled(zone ~= nil and zone.entries ~= nil and next(zone.entries) ~= nil)
    window.pinMap:SetEnabled(zone ~= nil and zone.pin ~= nil)
    refreshMap(zones)
end

function note.BuildEmbeddedTerritories(parent)
    local frame = CreateFrame("Frame", "ForeverDeathNoteTerritories", parent)
    frame:SetSize(742, 411)
    frame:SetPoint("TOPLEFT", 24, -117)
    frame:Hide()
    frame.source = label(frame, "GameFontHighlightSmall", 5, -6, 565)
    local function changeSource(useShared)
        shared = useShared
        note.db.territoryMode = useShared and "shared" or "personal"
        note.RefreshTerritories()
    end
    frame.mine = button(frame, L["Мои бои"], 457, -28, 114, function() changeSource(false) end)
    frame.community = button(frame, L["Общий счёт"], 580, -28, 161, function() changeSource(true) end)
    frame.exchange = button(frame, L["Обмен данными"], 318, -379, 158, function()
        note.OpenDataExchange()
    end)
    frame.tabs = {}
    for i, region in ipairs(regions) do
        frame.tabs[region.id] = button(frame, L[region.name], i == 1 and 0 or 144, -28, i == 1 and 136 or 163, function()
            continent, selected = region.id, nil
            note.RefreshTerritories()
        end)
    end

    local host = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    host:SetPoint("TOPLEFT", 0, -55)
    host:SetSize(477, 318)
    note.WarTable.Panel(host, 0.075, 0.052, 0.037)
    local viewport = CreateFrame("Frame", nil, host)
    viewport:SetPoint("CENTER")
    viewport:SetSize(467, 308)
    viewport:SetClipsChildren(true)
    local canvas = CreateFrame("Button", nil, viewport)
    canvas:SetPoint("TOPLEFT", viewport, "TOPLEFT")
    canvas:SetSize(467, 308)
    canvas.host, canvas.viewport, canvas.tiles, canvas.markers = viewport, viewport, {}, {}
    canvas.zoom = 1
    canvas.terrain = canvas:CreateTexture(nil, "BACKGROUND")
    canvas.terrain:SetAllPoints()
    canvas.terrain:Hide()
    canvas.hover = canvas:CreateTexture(nil, "ARTWORK", nil, 3)
    canvas.shading, canvas.shapes = {}, {}
    canvas:SetScript("OnClick", function(self)
        if self.mapDragged or not viewport:IsMouseOver() then return end
        local zone = findZoneAt(cursorMapPoint(self))
        if zone then selectZone(zone.key) end
    end)
    canvas:SetScript("OnUpdate", function(self, elapsed)
        if self.drag then
            if not IsMouseButtonDown("LeftButton") then self.drag = nil; return end
            local x, y = viewportCursor(viewport)
            local drag = self.drag
            if x then positionMap(self, drag.offsetX + x - drag.x, drag.offsetY + y - drag.y) end
            return
        end
        self.hoverElapsed = (self.hoverElapsed or 0) + elapsed
        if self.hoverElapsed < 0.055 then return end
        self.hoverElapsed = 0
        if not viewport:IsMouseOver() or not self:IsMouseOver() then return end
        for _, marker in ipairs(self.markers) do
            if marker:IsShown() and marker:IsMouseOver() then
                if hoverZone ~= marker.zone then
                    local x, y = mapCenter(marker.zone.key, continent)
                    updateHover(self, marker.zone, x, y)
                    tooltip(marker)
                end
                return
            end
        end
        local x, y = cursorMapPoint(self)
        local zone = findZoneAt(x, y)
        if zone ~= hoverZone or (zone and not GameTooltip:IsOwned(self)) then
            updateHover(self, zone, x, y)
            if zone then tooltip(self, zone, "ANCHOR_CURSOR") else hideTooltip(self) end
        end
    end)
    canvas:SetScript("OnLeave", function(self)
        hideTooltip(self)
        updateHover(self)
    end)
    canvas:SetScript("OnHide", function(self)
        self.drag = nil
        hideTooltip(self)
    end)
    wireMapInput(canvas, canvas)

    local controls = CreateFrame("Frame", nil, host)
    controls:SetSize(110, 24)
    controls:SetPoint("TOPRIGHT", -10, -10)
    controls:SetFrameLevel(canvas:GetFrameLevel() + 8)
    canvas.zoomOut = button(controls, "−", 0, 0, 26, function() zoomMap(canvas, canvas.zoom / 1.25) end)
    canvas.zoomReset = button(controls, "100%", 29, 0, 52, function() zoomMap(canvas, 1) end)
    canvas.zoomIn = button(controls, "+", 84, 0, 26, function() zoomMap(canvas, canvas.zoom * 1.25) end)
    frame.canvas = canvas
    frame.missing = label(host, "GameFontHighlight", 22, -134, 433)
    frame.missing:SetJustifyH("CENTER")
    frame.missing:SetText(L["Карта континента недоступна."])

    local panel = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    panel:SetPoint("TOPLEFT", 487, -55)
    panel:SetSize(255, 218)
    note.WarTable.Panel(panel, 0.077, 0.054, 0.041)
    frame.selection = label(panel, "GameFontNormal", 16, -12, 224)
    sizeText(frame.selection, 16)
    frame.selection:SetTextColor(1, 0.84, 0.49)
    frame.selection:SetWordWrap(false)

    local banner = CreateFrame("Frame", nil, panel)
    banner:SetPoint("TOPLEFT", 11, -33)
    banner:SetSize(234.5, 61)
    banner:Hide()
    frame.ownerBanner = banner
    local plate = banner:CreateTexture(nil, "BACKGROUND")
    plate:SetAllPoints()
    plate:SetTexture(ownerBannerArt)
    plate:SetTexCoord(0, 469 / 512, 0, 122 / 256)
    banner.crestField = banner:CreateTexture(nil, "ARTWORK")
    banner.crestField:SetPoint("TOPLEFT", 22, -5)
    banner.crestField:SetSize(44, 51)
    banner.crestField:SetTexture(ownerBannerArt)
    banner.crestField:SetTexCoord(0, 88 / 512, 128 / 256, 230 / 256)
    banner.crestField:SetVertexColor(0.14, 0.32, 0.61)
    banner.crestLeft = banner:CreateTexture(nil, "OVERLAY")
    banner.crestLeft:SetPoint("RIGHT", banner.crestField, "CENTER", 0, 1)
    banner.crestRight = banner:CreateTexture(nil, "OVERLAY")
    banner.crestRight:SetPoint("LEFT", banner.crestField, "CENTER", 0, 1)
    banner.crestHalves = { banner.crestLeft, banner.crestRight }
    local caption = label(banner, "GameFontHighlightSmall", 78, -7, 148)
    caption:SetText(L["Контроль территории"])
    caption:SetTextColor(0.88, 0.76, 0.56)
    caption:SetWordWrap(false)
    banner.name = label(banner, "GameFontNormalLarge", 77, -19, 151)
    banner.name:SetTextColor(0.51, 0.85, 1)
    banner.name:SetWordWrap(false)
    banner.kills = label(banner, "GameFontHighlightSmall", 78, -43, 146)
    banner.kills:SetTextColor(0.92, 0.83, 0.69)
    banner.kills:SetWordWrap(false)

    frame.ownerStatus = CreateFrame("Frame", nil, panel)
    frame.ownerStatus:SetAllPoints(banner)
    label(frame.ownerStatus, "GameFontHighlightSmall", 5, -10, 218):SetText(L["Гильдия-владелец"])
    frame.status = label(frame.ownerStatus, "GameFontNormal", 5, -25, 218)
    frame.status:SetWordWrap(false)
    for i, faction in ipairs({ { "Horde", "Орда", "horde" }, { "Alliance", "Альянс", "alliance" } }) do
        local field = CreateFrame("Frame", nil, panel, "BackdropTemplate")
        field:SetSize(110, 39)
        field:SetPoint("TOPLEFT", 14 + (i - 1) * 117, -99)
        if i == 1 then note.WarTable.Panel(field, 0.22, 0.077, 0.052)
        else note.WarTable.Panel(field, 0.053, 0.091, 0.16) end
        local crest = field:CreateTexture(nil, "ARTWORK")
        crest:SetSize(28, 28)
        crest:SetPoint("LEFT", 6, 0)
        note.SetFactionEmblem(crest, faction[1])
        local caption = label(field, "GameFontHighlightSmall", 37, -4, 70)
        caption:SetText(L[faction[2]])
        caption:SetTextColor(0.96, 0.86, 0.70)
        caption:SetWordWrap(false)
        local value = label(field, "GameFontHighlightLarge", 37, -16, 70)
        note.StyleMapNumber(value, 20)
        value:SetTextColor(1, 0.97, 0.87)
        frame[faction[3]] = value
    end
    local killerLabel = label(panel, "GameFontHighlightSmall", 16, -151, 70)
    killerLabel:SetText(L["Лидер по добиваниям"])
    killerLabel:SetTextColor(0.91, 0.79, 0.58)
    for _, y in ipairs({ -145, -168 }) do
        local divider = panel:CreateTexture(nil, "ARTWORK")
        divider:SetPoint("TOPLEFT", 11, y)
        divider:SetSize(234, 1)
        divider:SetColorTexture(0.65, 0.49, 0.29, 0.29)
    end
    for _, x in ipairs({ 85, 205 }) do
        local divider = panel:CreateTexture(nil, "ARTWORK")
        divider:SetPoint("TOPLEFT", x, -149)
        divider:SetSize(1, 15)
        divider:SetColorTexture(0.65, 0.49, 0.29, 0.36)
    end
    frame.topKiller = label(panel, "GameFontHighlightSmall", 92, -151, 108)
    frame.topKiller:SetWordWrap(false)
    frame.topKillerCount = label(panel, "GameFontHighlightSmall", 210, -149, 28)
    frame.topKillerCount:SetJustifyH("RIGHT")
    frame.topKillerCount:SetTextColor(1, 0.92, 0.73)
    note.StyleMapNumber(frame.topKillerCount, 13)
    frame.log = button(panel, L["Журнал зоны"], 11, -173, 114, function()
        if frame.zone and frame.zone.count > 0 then note.OpenFrontJournal(sample, frame.zone) end
    end)
    frame.pinMap = button(panel, L["Карта зоны"], 132, -173, 113, function()
        if frame.zone and frame.zone.pin then note.OpenFightMap(sample, frame.zone.pin, frame.zone) end
    end)
    local legend = label(frame, "GameFontHighlightSmall", 4, -380, 306)
    legend:SetText(L["Штриховка по гильдиям"] .. "\n|cffff6b4f" .. L["Орда"] .. "|r  /  |cff61abff" .. L["Альянс"]
        .. "|r  /  |cfff2c769" .. L["Ничья"] .. "|r")
    legend:SetMaxLines(2)
    window = frame
    shared = note.db.territoryMode == "shared"
    return frame
end

function note.OpenTerritories(zone)
    if not note.db then return end
    if type(zone) == "number" or type(zone) == "string" then requestedZone = zone end
    note.OpenWindow("territory")
end
