local _, note = ...
local L = note.L
local markLabels = { watch = "Наблюдение", kos = "Помечен черепом", ignore = "Игнорируется" }
local indexedEvents, indexedSize, indexedTail, totals

function note.PlayerTooltipEnabled()
    return note.db ~= nil and note.db.playerTooltip == true
end

function note.SetPlayerTooltipEnabled(enabled)
    if note.db then note.db.playerTooltip = enabled == true end
end

local function personalTotals(id)
    local events = note.db.events
    local size = #events
    if indexedEvents ~= events or indexedSize ~= size or indexedTail ~= events[size] then
        totals = {}
        for _, encounter in ipairs(events) do
            local tally = totals[encounter.other] or { kills = 0, deaths = 0 }
            if encounter.kind == "K" then tally.kills = tally.kills + 1
            elseif encounter.kind == "D" then tally.deaths = tally.deaths + 1 end
            totals[encounter.other] = tally
        end
        indexedEvents, indexedSize, indexedTail = events, size, events[size]
    end
    return totals[id]
end

local function canShow(tooltip)
    return tooltip == GameTooltip and note.PlayerTooltipEnabled() and note.db.demoMode == false
        and not tooltip:IsForbidden() and note.Public(IsInInstance()) == false
end

local function appendPersonalHistory(tooltip, guid)
    local id = note.GUID(guid)
    if not id or id == note.owner then return end
    local preference = note.DossierPreference(id)
    local tally = not note.db.playerTooltipNotesOnly and personalTotals(id)
    local mark, text = L[markLabels[preference.mark]], note.Text(preference.text)
    if not (tally or mark or text) then return end
    local title = tally and (L["Тетрадь смерти · Добивания %d / Смерти %d"]):format(tally.kills, tally.deaths)
        or L["Тетрадь смерти"]
    local before = tooltip.NumLines and tooltip:NumLines()
    tooltip:AddLine(title, 1, 0.82, 0)
    if mark then tooltip:AddLine(mark, 0.84, 0.81, 0.72) end
    if text then tooltip:AddLine(text, 0.96, 0.94, 0.88, true) end
    if before then note.StyleLocaleTooltip(tooltip, before + 1) end
end

local unitType = Enum and Enum.TooltipDataType and Enum.TooltipDataType.Unit
if unitType and TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall then
    TooltipDataProcessor.AddTooltipPostCall(unitType, function(tooltip, data)
        if not canShow(tooltip) then return end
        data = note.Public(data)
        if type(data) == "table" then appendPersonalHistory(tooltip, data.guid) end
    end)
elseif GameTooltip and GameTooltip:HasScript("OnTooltipSetUnit") then
    GameTooltip:HookScript("OnTooltipSetUnit", function(tooltip)
        if not canShow(tooltip) then return end
        local _, unit = tooltip:GetUnit()
        unit = note.Public(unit)
        if type(unit) == "string" then appendPersonalHistory(tooltip, UnitGUID(unit)) end
    end)
end
