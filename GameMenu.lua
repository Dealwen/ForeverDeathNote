local _, note = ...
local L = note.L
local button
local hookedMenu
local loader = CreateFrame("Frame")

local function insertButton(menu)
    local anchor, last
    local pool = menu.buttonPool
    if not pool or not pool.EnumerateActive then return end
    local indexes = {}
    for item in pool:EnumerateActive() do
        local index = item.layoutIndex
        if type(index) == "number" then
            indexes[#indexes + 1] = index
            if not last or index > last.layoutIndex then last = item end
            local text = item:GetText()
            if text and (text == ADDONS or text == ADDONS_BUTTON) then anchor = item end
        end
    end
    anchor = anchor or last
    if not anchor then return end

    local index, nextIndex = anchor.layoutIndex, nil
    for _, candidate in ipairs(indexes) do
        if candidate > index and (not nextIndex or candidate < nextIndex) then
            nextIndex = candidate
        end
    end

    if not button then
        button = CreateFrame("Button", "ForeverDeathNoteGameMenuButton", UIParent, menu.buttonTemplate)
        button:SetParent(menu)
        -- Keep the Game Menu template's own textures and interaction states.
        note.StyleLocaleFont(button:GetFontString())
        button:SetScript("OnClick", function()
            if note.db then
                HideUIPanel(menu)
                note.OpenWindow("settings")
            else
                print(L["Тетрадь смерти: журнал станет доступен после входа в мир."])
            end
        end)
    end
    button:SetText(L["Тетрадь смерти"])
    -- Keep the new button inside the AddOns section without moving other addons' buttons.
    button.layoutIndex = index + ((nextIndex or index + 1) - index) / 2
    button:SetSize(anchor:GetWidth(), anchor:GetHeight())
    button:Show()
end

local function hookMenu()
    local menu = GameMenuFrame
    if hookedMenu or not menu or type(menu.InitButtons) ~= "function"
        or type(menu.buttonTemplate) ~= "string" then return end
    hookedMenu = menu
    hooksecurefunc(menu, "InitButtons", insertButton)
    loader:UnregisterAllEvents()
end

loader:RegisterEvent("ADDON_LOADED")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", hookMenu)
hookMenu()
