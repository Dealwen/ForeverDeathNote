local _, note = ...
local L = note.L
local field = {}
note.FieldJournal = field

local ink = { 0.19, 0.107, 0.068 }
local inkMuted = { 0.29, 0.16, 0.096 }
local blood = { 0.44, 0.096, 0.062 }
local olive = { 0.17, 0.24, 0.10 }
field.binding = { 0.065, 0.051, 0.042 }
field.boards = { 0.093, 0.075, 0.057 }

function field.Enabled()
    local current = ForeverDeathNoteDB and ForeverDeathNoteDB.windowTheme
    return current == nil or current == "field"
end

function field.BoundPage(frame)
    local paper = frame:CreateTexture(nil, "BORDER")
    paper:SetPoint("TOPLEFT", 5, -5)
    paper:SetPoint("BOTTOMRIGHT", -5, 5)
    paper:SetTexture("Interface\\AddOns\\ForeverDeathNote\\Art\\FieldPaper.tga")
    local wash = frame:CreateTexture(nil, "BORDER", nil, 1)
    wash:SetAllPoints(paper)
    wash:SetColorTexture(1, 0.91, 0.73, 0.60)
    frame.fieldPaper, frame.fieldWash = paper, wash
    paper:Hide()
    wash:Hide()
end

function field.ShowPage(frame, show)
    frame.fieldPaper:SetShown(show)
    frame.fieldWash:SetShown(show)
end

local function line(parent, layer, x, y, w, h, r, g, b, alpha)
    local texture = parent:CreateTexture(nil, layer)
    texture:SetPoint("TOPLEFT", x, y)
    texture:SetSize(w, h)
    texture:SetColorTexture(r, g, b, alpha)
    return texture
end

local function label(parent, style, x, y, w)
    local value = note.CreateFontString(parent, nil, "OVERLAY", style)
    value:SetPoint("TOPLEFT", x, y)
    value:SetWidth(w)
    value:SetJustifyH("LEFT")
    value:SetWordWrap(false)
    value:SetShadowOffset(0, 0)
    return value
end

function field.PrepareRecord(row)
    row.stamp = label(row, "GameFontNormalSmall", 8, -4, 45)
    row.stamp:SetTextColor(unpack(inkMuted))
    row.time = label(row, "GameFontHighlightSmall", 8, -20, 45)
    row.time:SetTextColor(unpack(inkMuted))
    row.place = label(row, "GameFontHighlightSmall", 91, -20, 242)
    row.place:SetTextColor(unpack(inkMuted))
    row.rule = line(row, "ARTWORK", 5, 0, 450, 1, 0.33, 0.22, 0.13, 0.28)
    row.outcome = row:CreateTexture(nil, "ARTWORK")
    row.outcome:SetPoint("TOPRIGHT", -109, -9)
    row.outcome:SetSize(16, 16)
    row.outcome:Hide()
    row.markIcon = row:CreateTexture(nil, "ARTWORK")
    row.markIcon:SetPoint("TOPLEFT", 319, -5)
    row.markIcon:SetSize(12, 12)
    row.markIcon:Hide()
end

function field.LayoutRecord(row, paper)
    if not row.stamp then return end
    row.place:SetShown(paper)
    row.time:SetShown(paper)
    row.stamp:Hide()
    row.rule:Hide()
    row.outcome:Hide()
    row.markIcon:Hide()
    row.name:SetShadowOffset(paper and 0 or 1, paper and 0 or -1)
    row.caption:SetShadowOffset(paper and 0 or 1, paper and 0 or -1)
    row.name:SetTextColor(unpack(paper and ink or { 1, 0.98, 0.94 }))
end

function field.StyleRecord(row, data, preceding, mode, demo, selected, index)
    if not row.stamp or not data.entry then return end
    local encounter = data.entry
    local day = date("%d.%m", encounter.at)
    local showDay = mode == "journal" and (not preceding or date("%d.%m", preceding.entry.at) ~= day)
    row.stamp:SetShown(showDay)
    row.stamp:SetText(day)
    row.time:SetText(mode == "journal" and date("%H:%M", encounter.at) or day)
    row.rule:SetShown(showDay)
    row.tint:SetColorTexture(0.48, 0.31, 0.14, selected and 0.24 or index % 2 == 0 and 0.10 or 0.025)
    row.selected:SetColorTexture(0.52, 0.18, 0.105, 1)
    row.caption:SetTextColor(unpack(ink))
    local zone = note.SampleText(encounter.zone, demo) or L["Зона неизвестна"]
    if mode == "rivals" then
        local preference = note.DossierPreference(data.guid, demo)
        if preference and preference.mark and preference.mark ~= "" then
            local marks = { watch = "Наблюдать", kos = "Пометить черепом", ignore = "Игнорировать" }
            if marks[preference.mark] then zone = zone .. "  ·  " .. L[marks[preference.mark]] end
        end
    else
        local death = encounter.kind == "D"
        row.caption:SetText(L[death and "Смерть" or "Добивание"])
        row.caption:SetTextColor(unpack(death and blood or olive))
        row.outcome:SetTexture(death and "Interface\\TargetingFrame\\UI-RaidTargetingIcon_8"
            or "Interface\\Icons\\Ability_DualWield")
        row.outcome:Show()
        local mark = note.DossierPreference(data.guid, demo).mark
        row.markIcon:SetShown(mark == "watch" or mark == "kos")
        if row.markIcon:IsShown() then
            row.markIcon:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcon_" .. (mark == "kos" and "8" or "1"))
        end
    end
    row.place:SetText(zone)
end

local lower = strlower or string.lower

function field.MatchesRecord(query, name, profile, entry, demo)
    if query == "" then return true end
    local class = entry.kind == "D" and entry.killerClass or profile.class
    local function matches(value) return value and lower(value):find(query, 1, true) end
    return matches(name) or matches(note.ClassLabel(class, profile.sex)) or matches(class)
        or matches(note.SampleText(entry.zone, demo)) or matches(note.SampleText(entry.subzone, demo))
end

local function coordinates(entry)
    if type(entry.x) == "number" and type(entry.y) == "number"
        and entry.x >= 0 and entry.x <= 100 and entry.y >= 0 and entry.y <= 100 then
        return L["Координаты: %.1f, %.1f"]:format(entry.x, entry.y)
    end
end

function field.RecordTooltip(item, demo)
    local row = item.data
    if not row or not row.guid or not GameTooltip then return end
    local entry = row.entry
    GameTooltip:SetOwner(item, "ANCHOR_RIGHT")
    GameTooltip:SetText(row.name)
    local zone, subzone = note.SampleText(entry.zone, demo), note.SampleText(entry.subzone, demo)
    if zone then GameTooltip:AddLine(zone, 1, 1, 1, true) end
    if subzone and subzone ~= zone then GameTooltip:AddLine(subzone, 0.85, 0.79, 0.69, true) end
    local position = coordinates(entry)
    if position then GameTooltip:AddLine(position, 1, 0.83, 0.57) end
    GameTooltip:AddLine(date("%d.%m.%Y  %H:%M:%S", entry.at), 0.85, 0.79, 0.69)
    GameTooltip:AddLine(L["ПКМ: действия с записью"], 0.85, 0.79, 0.69, true)
    note.StyleLocaleTooltip(GameTooltip)
    GameTooltip:Show()
end

function field.RecordMenu(item, demo)
    local row = item.data
    if not row or not row.guid then return end
    if GameTooltip:IsOwned(item) then GameTooltip:Hide() end
    local id, entry = row.guid, row.entry
    if not MenuUtil or not MenuUtil.CreateContextMenu then
        note.OpenDossier(id, demo)
        return
    end
    MenuUtil.CreateContextMenu(item, function(_, root)
        note.StyleLocaleMenu(root:CreateTitle(row.name))
        local function action(key, open)
            note.StyleLocaleMenu(root:CreateButton(L[key], function()
                if note.DemoData() == demo then open() end
            end))
        end
        action("Досье", function() note.OpenDossier(id, demo) end)
        action("Разбор боя", function() note.OpenFightReport(demo, entry) end)
        if coordinates(entry) and note.EncounterMapID(entry) then
            action("Карта", function() note.OpenFightMap(demo, entry) end)
        end
        root:CreateDivider()
        for _, choice in ipairs({
            { "watch", "Наблюдать" }, { "kos", "Пометить черепом" }, { "ignore", "Игнорировать" },
            { nil, "Снять метку" },
        }) do
            local mark = choice[1]
            note.StyleLocaleMenu(root:CreateRadio(L[choice[2]], function()
                return note.DossierPreference(id, demo).mark == mark
            end, function()
                if note.DemoData() ~= demo then return end
                local preference = note.DossierPreference(id, demo)
                note.SaveDossier(id, preference.text, mark, demo)
            end))
        end
    end)
end

