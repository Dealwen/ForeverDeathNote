local _, note = ...
-- Native map coordinates and texture regions derived from Waymark's MIT zone shapes.
-- See Art/Waymark-LICENSE.txt.
local width, height = 1024, 1024
local zones = {
    [1411] = { 1414, 425, 228, 79, 72, 99, 244, 180, 244 },
    [1412] = { 1414, 306, 264, 86, 83, 556, 144, 644, 144 },
    [1413] = { 1414, 354, 233, 147, 141, 1, 1, 150, 1 },
    [1416] = { 1415, 335, 129, 58, 43, 123, 514, 183, 514 },
    [1417] = { 1415, 369, 170, 78, 48, 697, 459, 777, 459 },
    [1418] = { 1415, 394, 294, 56, 35, 637, 514, 695, 514 },
    [1419] = { 1415, 392, 393, 56, 49, 441, 459, 499, 459 },
    [1420] = { 1415, 285, 81, 97, 58, 137, 394, 236, 394 },
    [1421] = { 1415, 286, 126, 66, 63, 1, 394, 69, 394 },
    [1422] = { 1415, 362, 88, 61, 65, 489, 320, 552, 320 },
    [1423] = { 1415, 397, 80, 95, 65, 615, 320, 712, 320 },
    [1424] = { 1415, 327, 155, 69, 47, 857, 459, 928, 459 },
    [1425] = { 1415, 387, 132, 80, 56, 517, 394, 599, 394 },
    [1426] = { 1415, 310, 249, 100, 72, 261, 244, 363, 244 },
    [1427] = { 1415, 354, 294, 51, 36, 531, 514, 584, 514 },
    [1428] = { 1415, 354, 322, 67, 35, 753, 514, 822, 514 },
    [1429] = { 1415, 315, 335, 76, 53, 1, 459, 79, 459 },
    [1430] = { 1415, 380, 378, 27, 37, 365, 514, 394, 514 },
    [1431] = { 1415, 331, 376, 59, 38, 243, 514, 304, 514 },
    [1432] = { 1415, 395, 259, 59, 44, 1, 514, 62, 514 },
    [1433] = { 1415, 385, 349, 50, 34, 1, 560, 53, 560 },
    [1434] = { 1415, 304, 406, 132, 90, 116, 144, 250, 144 },
    [1435] = { 1415, 397, 370, 52, 37, 423, 514, 477, 514 },
    [1436] = { 1415, 282, 368, 65, 52, 157, 459, 224, 459 },
    [1437] = { 1415, 359, 211, 90, 56, 681, 394, 773, 394 },
    [1438] = { 1414, 280, 22, 97, 68, 291, 320, 390, 320 },
    [1439] = { 1414, 314, 93, 84, 90, 384, 144, 470, 144 },
    [1440] = { 1414, 320, 175, 122, 72, 465, 244, 589, 244 },
    [1441] = { 1414, 369, 353, 89, 58, 335, 394, 426, 394 },
    [1442] = { 1414, 290, 204, 97, 71, 93, 320, 192, 320 },
    [1443] = { 1414, 274, 258, 79, 64, 809, 320, 890, 320 },
    [1444] = { 1414, 255, 315, 126, 99, 577, 1, 705, 1 },
    [1445] = { 1414, 407, 311, 70, 72, 713, 244, 785, 244 },
    [1446] = { 1414, 377, 388, 113, 98, 833, 1, 1, 144 },
    [1447] = { 1414, 431, 154, 96, 74, 880, 144, 1, 244 },
    [1448] = { 1414, 337, 117, 72, 80, 732, 144, 806, 144 },
    [1449] = { 1414, 354, 390, 61, 55, 865, 394, 928, 394 },
    [1450] = { 1414, 386, 88, 45, 35, 891, 514, 938, 514 },
    [1451] = { 1414, 302, 390, 73, 52, 291, 459, 366, 459 },
    [1452] = { 1414, 370, 88, 137, 100, 299, 1, 438, 1 },
    [2482] = { 1414, 380, 137, 68, 49, 557, 459, 627, 459 },
    [2548] = { 1415, 405, 303, 90, 72, 857, 244, 1, 320 },
    [2652] = { 1414, 320, 309, 33, 28, 105, 560, 140, 560 },
}

function note.DrawTerritoryContour(texture, canvas, mapID, zoneID, hatch, r, g, b, alpha)
    local zone = zones[zoneID]
    texture:Hide()
    if not zone or zone[1] ~= mapID then return end
    local _, x, y, w, h, left, top = unpack(zone)
    if hatch then left, top = zone[8], zone[9] end
    if texture:SetTexture("Interface\\AddOns\\ForeverDeathNote\\Art\\TerritoryContours.tga") == false then return end
    texture:ClearAllPoints()
    texture:SetPoint("TOPLEFT", canvas, "TOPLEFT", x / 768 * canvas:GetWidth(), -y / 512 * canvas:GetHeight())
    texture:SetSize(w / 768 * canvas:GetWidth(), h / 512 * canvas:GetHeight())
    texture:SetTexCoord(left / width, (left + w) / width, top / height, (top + h) / height)
    texture:SetBlendMode("BLEND")
    texture:SetVertexColor(r, g, b)
    texture:SetAlpha(alpha)
    texture:Show()
    return true
end

local guildColors = {}

-- The website colors guilds using FNV-1a and a fixed saturation/lightness.
-- Split the multiplication to keep every intermediate exact in Lua's doubles.
function note.TerritoryGuildTint(guildName)
    local name = (strlower or string.lower)(guildName)
    local cached = guildColors[name]
    if cached then return unpack(cached) end
    local hash = 2166136261
    for letter in name:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
        local first = letter:byte()
        local point = #letter == 1 and first or first % (2 ^ (7 - #letter))
        for i = 2, #letter do point = point * 64 + letter:byte(i) - 128 end
        if point >= 0x410 and point <= 0x42F then point = point + 32
        elseif point == 0x401 then point = 0x451 end
        local mixed = bit.bxor(hash, point) % 4294967296
        local low = mixed % 65536
        hash = (low * 16777619 + (mixed - low) * 403) % 4294967296
    end
    local hue = (hash % 360) / 60
    local chroma = 0.5984
    local middle = chroma * (1 - math.abs(hue % 2 - 1))
    local floor = 0.56 - chroma / 2
    local values = {
        { chroma, middle, 0 }, { middle, chroma, 0 }, { 0, chroma, middle },
        { 0, middle, chroma }, { middle, 0, chroma }, { chroma, 0, middle },
    }
    local color = values[math.floor(hue) + 1]
    for i = 1, 3 do color[i] = floor + color[i] end
    guildColors[name] = color
    return unpack(color)
end
