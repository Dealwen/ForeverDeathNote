local _, note = ...
local L = note.L
local theme = {}
note.WarTable = theme

local white = "Interface\\Buttons\\WHITE8X8"
local border = "Interface\\Tooltips\\UI-Tooltip-Border"
local parchment = "Interface\\AddOns\\ForeverDeathNote\\Art\\WarTable.tga"
local palettes = {
    field = { label = "Полевой журнал", window = { 0.061, 0.043, 0.030 }, ink = { 0.075, 0.053, 0.038 },
        paper = { 0.115, 0.081, 0.053 }, bronze = { 0.58, 0.402, 0.217 },
        button = { 0.75, 0.62, 0.49 }, active = { 1.00, 0.78, 0.43 }, primary = { 0.97, 0.57, 0.35 } },
    wartable = { label = "Военный совет", window = { 0.075, 0.052, 0.026 }, ink = { 0.085, 0.058, 0.034 },
        paper = { 0.145, 0.097, 0.047 }, bronze = { 0.69, 0.50, 0.28 },
        button = { 0.83, 0.70, 0.54 }, active = { 1.00, 0.83, 0.47 }, primary = { 1.00, 0.68, 0.36 } },
    ember = { label = "Красная кузня", window = { 0.099, 0.041, 0.033 }, ink = { 0.111, 0.048, 0.034 },
        paper = { 0.168, 0.065, 0.043 }, bronze = { 0.70, 0.38, 0.24 },
        button = { 0.83, 0.47, 0.36 }, active = { 1.00, 0.69, 0.42 }, primary = { 1.00, 0.53, 0.35 } },
    watch = { label = "Синий дозор", window = { 0.041, 0.061, 0.097 }, ink = { 0.049, 0.075, 0.112 },
        paper = { 0.070, 0.115, 0.167 }, bronze = { 0.40, 0.57, 0.72 },
        button = { 0.56, 0.69, 0.88 }, active = { 0.77, 0.87, 1.00 }, primary = { 0.51, 0.77, 1.00 } },
    classic = { label = "Классическая тема", window = { 0.037, 0.046, 0.061 }, ink = { 0.063, 0.078, 0.093 },
        paper = { 0.093, 0.109, 0.126 }, bronze = { 0.44, 0.52, 0.61 },
        button = { 0.62, 0.70, 0.77 }, active = { 0.78, 0.88, 0.97 }, primary = { 0.90, 0.72, 0.52 } },
    legacy = { label = "Старый пергамент", window = { 0.38, 0.26, 0.17 }, ink = { 0.105, 0.065, 0.042 },
        paper = { 0.152, 0.104, 0.064 }, bronze = { 0.64, 0.47, 0.29 },
        button = { 0.86, 0.72, 0.54 }, active = { 1.00, 0.86, 0.47 }, primary = { 0.78, 0.78, 1.00 } },
}
theme.order = { "field", "wartable", "ember", "watch", "classic", "legacy" }

function theme.Preference()
    local current = ForeverDeathNoteDB and ForeverDeathNoteDB.windowTheme
    return palettes[current] and current or "field"
end

function theme.Palette(id)
    return palettes[id or theme.Preference()]
end

function theme.Enabled()
    return theme.Preference() ~= "classic"
end

function theme.Refined()
    return theme.Enabled() and theme.Preference() ~= "legacy"
end

function theme.RefreshPalette()
    local palette = theme.Palette()
    theme.ink, theme.paper, theme.bronze = palette.ink, palette.paper, palette.bronze
end

theme.RefreshPalette()
theme.gold = { 0.98, 0.79, 0.47 }

function theme.SetPreference(preference)
    if not palettes[preference] or theme.Preference() == preference then return end
    if InCombatLockdown() then return L["Сменить тему можно после выхода из боя."] end
    ForeverDeathNoteDB.windowTheme = preference
    if ReloadUI then ReloadUI() end
end

function theme.Change(classic, legacy, field)
    return theme.SetPreference(classic and "classic" or legacy and "legacy" or field and "field" or "wartable")
end

function theme.Panel(frame, red, green, blue)
    frame:SetBackdrop({
        bgFile = white, edgeFile = border, edgeSize = 14,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    frame:SetBackdropColor(red, green, blue, 1)
    local rim = theme.Palette().bronze
    frame:SetBackdropBorderColor(rim[1], rim[2], rim[3], 1)
end

local flyout
function theme.CloseMenu()
    if flyout then flyout:Hide() end
end

function theme.ShowMenu(anchor, entries)
    if MenuUtil and MenuUtil.CreateContextMenu then
        MenuUtil.CreateContextMenu(anchor, function(_, root)
            for _, entry in ipairs(entries) do
                note.StyleLocaleMenu(root:CreateButton(entry[1], entry[2]))
            end
        end)
        return
    end
    if flyout and flyout:IsShown() and flyout.anchor == anchor then theme.CloseMenu(); return end
    if not flyout then
        flyout = CreateFrame("Frame", nil, anchor, "BackdropTemplate")
        flyout:SetFrameStrata("DIALOG")
        theme.Panel(flyout, unpack(theme.ink))
        flyout.buttons = {}
    end
    flyout.anchor = anchor
    flyout:SetParent(anchor)
    flyout:SetFrameLevel(anchor:GetFrameLevel() + 12)
    flyout:SetSize(226, #entries * 26 + 12)
    flyout:ClearAllPoints()
    flyout:SetPoint("BOTTOMRIGHT", anchor, "TOPRIGHT", 0, 3)
    for index, entry in ipairs(entries) do
        local row = flyout.buttons[index]
        if not row then
            row = CreateFrame("Button", nil, flyout, "UIPanelButtonTemplate")
            row:SetSize(214, 24)
            row:SetPoint("TOPLEFT", 6, -6 - (index - 1) * 26)
            note.StyleLocaleButton(row)
            flyout.buttons[index] = row
        end
        row:SetText(entry[1])
        row:SetScript("OnClick", function() theme.CloseMenu(); entry[2]() end)
        row:Show()
    end
    for index = #entries + 1, #flyout.buttons do flyout.buttons[index]:Hide() end
    flyout:Show()
end

local function pennant(parent, faction, x)
    local flag = parent:CreateTexture(nil, "ARTWORK")
    flag:SetSize(65, 76)
    flag:SetPoint("TOPLEFT", x, 7)
    flag:SetTexture("Interface\\AddOns\\ForeverDeathNote\\Art\\" .. faction .. ".tga")
    local emblem = parent:CreateTexture(nil, "OVERLAY")
    emblem:SetSize(30, 30)
    emblem:SetPoint("TOPLEFT", x + 18, -11)
    note.SetFactionEmblem(emblem, faction)
    emblem:SetVertexColor(1, 0.92, 0.72)
end

function theme.Header(parent)
    local holder = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    holder:SetPoint("TOP", 0, 4)
    holder:SetSize(360, 44)
    holder:SetFrameLevel(parent:GetFrameLevel())
    theme.Panel(holder, 0.105, 0.066, 0.034)
    local ornament = holder:CreateTexture(nil, "ARTWORK")
    ornament:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Header")
    ornament:SetPoint("TOPLEFT", -20, 8)
    ornament:SetPoint("BOTTOMRIGHT", 20, -10)
    ornament:SetVertexColor(0.94, 0.72, 0.43)
    pennant(holder, "Horde", -174)
    pennant(holder, "Alliance", 418)
    return holder
end

function theme.Map(parent)
    local frame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    frame:SetPoint("TOPLEFT", 24, -116)
    frame:SetSize(742, 98)
    if theme.Refined() then frame:SetHeight(54) end
    theme.Panel(frame, 0.18, 0.11, 0.052)
    local art = frame:CreateTexture(nil, "ARTWORK")
    art:SetPoint("TOPLEFT", 5, -5)
    art:SetPoint("BOTTOMRIGHT", -5, 5)
    art:SetTexture(parchment)
    if theme.Refined() then
        art:SetTexCoord(0, 1, 0.23, 0.80)
        art:SetVertexColor(0.88, 0.73, 0.54)
    end
    frame:SetFrameLevel(parent:GetFrameLevel())
    return frame
end
