local _, note = ...
note.BrandIcon = "Interface\\AddOns\\ForeverDeathNote\\Art\\Identity.tga"

local buttonStates = { "Normal", "Pushed", "Disabled", "Highlight" }
local artRoot = "Interface\\AddOns\\ForeverDeathNote\\Art\\"

local function paintButton(button)
    local art = button.fdnNativeArt
    if not art then return end
    local palette = note.WarTable and note.WarTable.Palette()
    local normal = palette and palette.button or { 0.78, 0.64, 0.49 }
    local selected = palette and palette.active or { 1, 0.80, 0.52 }
    local primary = palette and palette.primary or { 1, 0.62, 0.43 }
    local tint = art.selected and selected or art.primary and primary or normal
    local strength = button:IsEnabled() or art.selected
    strength = strength and (art.pressed and 0.74 or 1) or 0.54
    for _, texture in ipairs(art) do
        texture:SetVertexColor(tint[1] * strength, tint[2] * strength, tint[3] * strength)
    end
end

function note.StyleWarcraftButton(button, variant)
    if not button or button.fdnNativeArt then return end
    local art = {}
    button.fdnNativeArt = art
    if button.GetBackdrop and button:GetBackdrop() then button:SetBackdrop(nil) end
    for _, state in ipairs(buttonStates) do
        local old = button["Get" .. state .. "Texture"](button)
        if old and old.SetTexture then
            old:SetTexture(nil)
            old:Hide()
        end
    end
    -- The UIPanel template also draws its frame from three independent regions.
    for _, key in ipairs({ "Left", "Middle", "Right" }) do
        local region = button[key]
        if (type(region) == "table" or type(region) == "userdata") and region.Hide then region:Hide() end
    end
    local asset = artRoot .. (variant == "bookmark" and "RankBookmark.tga" or "ForgedButton.tga")
    for index, coords in ipairs({ { 0, 0.125 }, { 0.125, 0.875 }, { 0.875, 1 } }) do
        local texture = button:CreateTexture(nil, "BACKGROUND", nil, 0)
        texture:SetTexture(asset)
        texture:SetTexCoord(coords[1], coords[2], 0, 1)
        art[index] = texture
    end
    art[1]:SetPoint("TOPLEFT")
    art[1]:SetPoint("BOTTOMLEFT")
    art[1]:SetWidth(7)
    art[2]:SetPoint("TOPLEFT", 7, 0)
    art[2]:SetPoint("BOTTOMRIGHT", -7, 0)
    art[3]:SetPoint("TOPRIGHT")
    art[3]:SetPoint("BOTTOMRIGHT")
    art[3]:SetWidth(7)
    local hover = button:CreateTexture(nil, "HIGHLIGHT")
    hover:SetPoint("TOPLEFT", 3, -3)
    hover:SetPoint("BOTTOMRIGHT", -3, 3)
    hover:SetColorTexture(1, 0.83, 0.57, 0.12)
    button:SetHighlightTexture(hover)
    local function release(self)
        if not self.fdnNativeArt then return end
        self.fdnNativeArt.pressed = false
        paintButton(self)
    end
    button:HookScript("OnMouseDown", function(self)
        if not self.fdnNativeArt or not self:IsEnabled() then return end
        self.fdnNativeArt.pressed = true
        paintButton(self)
    end)
    button:HookScript("OnMouseUp", release)
    button:HookScript("OnLeave", release)
    button:HookScript("OnEnable", paintButton)
    button:HookScript("OnDisable", release)
    paintButton(button)
end

function note.TintWarcraftButton(button, selected, prominent)
    local art = button.fdnNativeArt
    if not art then return end
    art.selected, art.primary = selected, prominent
    paintButton(button)
end

function note.StylePageButton(button, direction)
    for _, texture in ipairs(button.fdnNativeArt or {}) do texture:Hide() end
    local stem = "Interface\\Buttons\\UI-SpellbookIcon-" .. (direction == "prev" and "Prev" or "Next") .. "Page-"
    button:SetNormalTexture(stem .. "Up")
    button:SetPushedTexture(stem .. "Down")
    button:SetDisabledTexture(stem .. "Disabled")
    button:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight")
    button.fdnNativeArt = nil
    local caption = button:GetFontString()
    if caption then caption:Hide() end
end

function note.SetFactionEmblem(texture, faction)
    texture:SetTexture("Interface\\TargetingFrame\\UI-PVP-" .. faction)
    -- These unit-frame textures store the crests in the upper-left of their sheet.
    if faction == "Alliance" then
        texture:SetTexCoord(0.10, 0.55, 0.025, 0.65)
    else
        texture:SetTexCoord(0.07, 0.58, 0.025, 0.57)
    end
end
