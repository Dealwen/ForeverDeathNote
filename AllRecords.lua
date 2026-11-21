local _, note = ...
local L = note.L
local window
local margin, inset, gutter = 24, 23, 16
local listTop, listBottom, rowHeight = 92, 40, 32
local light, muted = { 0.96, 0.92, 0.85 }, { 0.78, 0.74, 0.67 }

local function font(parent, template, justify)
    local label = note.CreateFontString(parent, nil, "OVERLAY", template)
    label:SetJustifyH(justify or "LEFT")
    label:SetWordWrap(false)
    return label
end

local function scroll(_, delta)
    local slider = window.slider
    if slider:IsShown() then slider:SetValue(window.first - delta * 3) end
end

local function addRow(frame, slot)
    local row = CreateFrame("Button", nil, frame)
    row:SetPoint("TOPLEFT", inset, -listTop - rowHeight * (slot - 1))
    row:SetHeight(rowHeight - 1)
    row.background = row:CreateTexture(nil, "BACKGROUND")
    row.background:SetAllPoints()
    row.hover = row:CreateTexture(nil, "HIGHLIGHT")
    row.hover:SetAllPoints()
    row.cells = {}
    row:EnableMouseWheel(true)
    row:SetScript("OnMouseWheel", scroll)
    row:SetScript("OnClick", function()
        local config, index = frame.config, row.index
        if not config or not config.onSelect or not index then return end
        frame:Hide()
        config.onSelect(config.rows[index], index)
    end)
    return row
end

local function render(frame)
    local config = frame.config
    if not config then return end
    local palette = note.WarTable.Palette()
    local paper, highlight = palette.paper, palette.active
    local selectedRed = paper[1] + (highlight[1] - paper[1]) * 0.18
    local selectedGreen = paper[2] + (highlight[2] - paper[2]) * 0.18
    local selectedBlue = paper[3] + (highlight[3] - paper[3]) * 0.18
    frame:SetBackdropColor(unpack(palette.ink))
    frame:SetBackdropBorderColor(unpack(palette.bronze))
    frame.title:SetTextColor(unpack(highlight))
    frame.line:SetColorTexture(unpack(palette.bronze))
    frame.track:SetColorTexture(paper[1], paper[2], paper[3], 1)
    frame.thumb:SetColorTexture(unpack(palette.bronze))
    for i, header in ipairs(frame.headers) do
        if frame.columns[i] then header:SetTextColor(unpack(highlight)) end
    end
    local first, total = frame.first, #config.rows
    local last = math.min(total, first + frame.visibleCount - 1)
    frame.empty:SetShown(total == 0)
    frame.count:SetText(total > 0 and L["Строки %d–%d из %d"]:format(first, last, total) or "")
    for slot, row in ipairs(frame.rows) do
        local index = first + slot - 1
        local item = slot <= frame.visibleCount and config.rows[index]
        row.index = item and index or nil
        row:SetShown(item and true or false)
        if item then
            local lines = config.cells(item, index)
            local selected = config.selectedIndex == index
            row.background:SetColorTexture(selected and selectedRed or paper[1], selected and selectedGreen or paper[2],
                selected and selectedBlue or paper[3], selected and 1 or slot % 2 == 0 and 0.98 or 0.50)
            row.hover:SetColorTexture(highlight[1], highlight[2], highlight[3], 0.14)
            row.hover:SetShown(config.onSelect ~= nil)
            for column, cell in ipairs(row.cells) do
                local geometry, line = frame.columns[column], lines[column]
                cell.label:SetShown(geometry ~= nil)
                if geometry then
                    local special = type(line) == "table"
                    local value, color, icon
                    if special then value, color, icon = line.text, line.color, line.icon
                    else value = line end
                    cell.icon:SetShown(icon ~= nil)
                    if icon then cell.icon:SetTexture(icon) end
                    local offset = icon and 25 or 0
                    cell.label:ClearAllPoints()
                    cell.label:SetPoint("LEFT", geometry.x + offset, 0)
                    cell.label:SetWidth(math.max(1, geometry.width - offset))
                    cell.label:SetText(value == nil and "" or tostring(value))
                    cell.label:SetTextColor(unpack(color or light))
                else
                    cell.icon:Hide()
                end
            end
        end
    end
end

local function layout(frame, first)
    local config = frame.config
    local width, height = UIParent:GetWidth() - margin * 2, UIParent:GetHeight() - margin * 2
    frame:SetSize(width, height)
    frame.title:SetWidth(width - inset - 42)
    frame.subtitle:SetWidth(width - inset * 2)
    frame.visibleCount = math.max(1, math.floor((height - listTop - listBottom) / rowHeight))
    frame.maximum = math.max(1, #config.rows - frame.visibleCount + 1)
    local scrollable = frame.maximum > 1
    local rowWidth = width - inset * 2 - (scrollable and 21 or 0)
    local availableWidth = rowWidth - 20 - gutter * (#config.columns - 1)
    local totalWeight, x = 0, 10
    for _, column in ipairs(config.columns) do totalWeight = totalWeight + (column.weight or 1) end
    frame.columns = {}
    for i, column in ipairs(config.columns) do
        local header = frame.headers[i] or font(frame, "GameFontHighlightSmall")
        frame.headers[i] = header
        local columnWidth = math.max(1, availableWidth * (column.weight or 1) / totalWeight)
        frame.columns[i] = { x = x, width = columnWidth }
        header:ClearAllPoints()
        header:SetPoint("TOPLEFT", inset + x, -72)
        header:SetWidth(columnWidth)
        header:SetJustifyH(column.justify or "LEFT")
        header:SetText(column.label)
        header:Show()
        x = x + columnWidth + gutter
    end
    for i = #frame.columns + 1, #frame.headers do frame.headers[i]:Hide() end
    for i = 1, frame.visibleCount do
        local row = frame.rows[i] or addRow(frame, i)
        frame.rows[i] = row
        row:SetWidth(rowWidth)
        for j, column in ipairs(config.columns) do
            local cell = row.cells[j]
            if not cell then
                local icon = row:CreateTexture(nil, "ARTWORK")
                icon:SetSize(20, 20)
                cell = { label = font(row, "GameFontHighlight"), icon = icon }
                row.cells[j] = cell
            end
            cell.icon:ClearAllPoints()
            cell.icon:SetPoint("LEFT", frame.columns[j].x, 0)
            cell.label:SetJustifyH(column.justify or "LEFT")
        end
    end
    frame.layout = true
    frame.first = math.max(1, math.min(frame.maximum, math.floor(first or 1)))
    frame.slider:SetShown(scrollable)
    frame.slider:SetMinMaxValues(1, math.max(2, frame.maximum))
    frame.slider:SetValue(frame.first)
    frame.layout = nil
    render(frame)
end

local function create()
    local frame = CreateFrame("Frame", "ForeverDeathNoteAllRecords", UIParent, "BackdropTemplate")
    frame:Hide()
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    frame:SetToplevel(true)
    frame:EnableMouse(true)
    frame:EnableMouseWheel(true)
    frame:SetScript("OnMouseWheel", scroll)
    frame:SetScript("OnHide", function(self)
        self.config = nil
        for _, row in ipairs(self.rows) do row.index = nil end
    end)
    frame:RegisterEvent("DISPLAY_SIZE_CHANGED")
    frame:RegisterEvent("UI_SCALE_CHANGED")
    frame:SetScript("OnEvent", function(self)
        if self:IsShown() and self.config then layout(self, self.first) end
    end)
    note.WarTable.Panel(frame, unpack(note.WarTable.Palette().ink))
    frame.rows, frame.headers = {}, {}
    tinsert(UISpecialFrames, "ForeverDeathNoteAllRecords")

    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -6, -6)
    close:SetScript("OnClick", function() frame:Hide() end)
    frame.title = font(frame, "GameFontNormalHuge")
    note.StyleHeadingFont(frame.title)
    frame.title:SetPoint("TOPLEFT", inset, -21)
    frame.subtitle = font(frame, "GameFontHighlightSmall")
    frame.subtitle:SetPoint("TOPLEFT", inset, -49)
    frame.subtitle:SetTextColor(unpack(muted))
    local line = frame:CreateTexture(nil, "ARTWORK")
    line:SetPoint("TOPLEFT", inset, -64)
    line:SetPoint("TOPRIGHT", -inset, -64)
    line:SetHeight(1)
    frame.line = line
    frame.empty = font(frame, "GameFontHighlight")
    frame.empty:SetPoint("TOPLEFT", inset + 10, -listTop - 12)
    frame.empty:SetText(L["Пока нет записей по этому запросу."])
    frame.count = font(frame, "GameFontHighlightSmall")
    frame.count:SetPoint("BOTTOMLEFT", inset, 17)
    frame.count:SetTextColor(unpack(muted))

    local slider = CreateFrame("Slider", nil, frame)
    slider:SetPoint("TOPRIGHT", -inset, -listTop)
    slider:SetPoint("BOTTOMRIGHT", -inset, listBottom)
    slider:SetWidth(12)
    slider:SetOrientation("VERTICAL")
    slider:SetValueStep(1)
    slider:SetObeyStepOnDrag(true)
    local track = slider:CreateTexture(nil, "BACKGROUND")
    track:SetPoint("TOPLEFT", 4, 0)
    track:SetPoint("BOTTOMRIGHT", -4, 0)
    local thumb = slider:CreateTexture(nil, "OVERLAY")
    thumb:SetSize(12, 30)
    slider:SetThumbTexture(thumb)
    slider:EnableMouseWheel(true)
    slider:SetScript("OnMouseWheel", scroll)
    slider:SetScript("OnValueChanged", function(_, value)
        if not frame.config or frame.layout then return end
        local first = math.max(1, math.min(frame.maximum, math.floor(value + 0.5)))
        if frame.first == first then return end
        frame.first = first
        render(frame)
    end)
    frame.slider, frame.track, frame.thumb = slider, track, thumb
    return frame
end

function note.CloseAllRecords()
    if window then window:Hide() end
end

function note.OpenAllRecords(config)
    window = window or create()
    window.config = config
    window.title:SetText(config.title)
    window.subtitle:SetText(config.subtitle or "")
    layout(window, config.startIndex)
    window:Show()
    window:Raise()
end
