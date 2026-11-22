local _, note = ...
local public, clean, playerGUID = note.Public, note.Text, note.GUID
local driver = CreateFrame("Frame")
local plates = {}
local deathsByPlayer = {}
local deathSerial = 0
local duelling
local recycled = {}

local function inWorld()
    local inside, instance = IsInInstance()
    return not inside and instance == "none"
end

local function location()
    local place = {
        at = GetServerTime(),
        zone = clean(GetRealZoneText()),
        subzone = clean(GetSubZoneText()),
        actorLevel = note.PositiveInteger(UnitLevel("player"), 255),
        mapId = note.PositiveInteger(C_Map.GetBestMapForUnit("player"), 1000000),
    }
    local position = place.mapId and public(C_Map.GetPlayerMapPosition(place.mapId, "player"))
    if position then
        local x, y = position:GetXY()
        x, y = public(x), public(y)
        if x and y then place.x, place.y = x * 100, y * 100 end
    end
    return place
end

local function observe(unit, force)
    local guid = playerGUID(UnitGUID(unit))
    if not guid then return nil end
    local profile = note.db.profiles[guid]
    if force or not profile or GetTime() - (note.seen[guid] or 0) >= 15 then
        local _, class = UnitClass(unit)
        local level = note.PositiveInteger(UnitLevel(unit), 255)
        local race, raceFile = UnitRace(unit)
        local guildName, _, _, guildRealm = GetGuildInfo(unit)
        local guild = clean(guildName)
        if unit == "player" and not IsInGuild() then guild = false end
        local name = note.UnitName(unit)
        local faction = note.Faction(UnitFactionGroup(unit))
        note.Profile(guid, {
            name = name, class = clean(class), race = clean(race), raceFile = clean(raceFile),
            sex = public(UnitSex(unit)), guild = guild, faction = faction, level = level,
        })
        if note.CacheTerritoryTabard then note.CacheTerritoryTabard(unit, guild, faction, clean(guildRealm)) end
        note.seen[guid] = GetTime()
        note.recentLevels[guid] = level
    end
    return guid
end

local function identify(guid, fallback)
    local profile = note.Profile(guid)
    if not profile.name or not profile.class or not profile.raceFile or not profile.sex then
        local class, race, raceFile, sex, name
        if GetPlayerInfoByGUID then
            local ok, _, classFile, localRace, clientRace, body, given = pcall(GetPlayerInfoByGUID, guid)
            if ok then
                class, race, raceFile, name = clean(classFile), clean(localRace), clean(clientRace), clean(given)
                body = public(body)
                if body == 2 or body == 3 then sex = body end
            end
        end
        if not profile.name and UnitNameFromGUID then name = clean(UnitNameFromGUID(guid)) or name end
        note.Profile(guid, {
            name = profile.name or name or clean(fallback), class = profile.class or class,
            race = profile.race or race, raceFile = profile.raceFile or raceFile, sex = profile.sex or sex,
        })
    end
end

function note.VisiblePlayerUnit(guid, addedPlate, removedPlate)
    if not guid then return end
    if guid == note.owner then return "player" end
    if playerGUID(UnitGUID("target")) == guid then return "target" end
    if addedPlate and playerGUID(UnitGUID(addedPlate)) == guid then return addedPlate end
    for unit in pairs(plates) do
        if unit ~= removedPlate and playerGUID(UnitGUID(unit)) == guid then return unit end
    end
    if playerGUID(UnitGUID("mouseover")) == guid then return "mouseover" end
end

local function makeMark()
    local image = UIParent:CreateTexture(nil, "OVERLAY")
    image:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcon_8")
    image:SetSize(22, 22)
    image:Hide()
    return image
end

local function markUnit(unit, anchor, mark, force)
    if not anchor or anchor:IsForbidden() or not anchor:IsShown() then
        mark:Hide()
        return
    end
    local guid = observe(unit, force)
    local markType = guid and note.RivalTracking and note.RivalTracking(guid, deathsByPlayer[guid])
    if (markType ~= "rival" and markType ~= "kos") or not public(UnitCanAttack("player", unit))
        or public(UnitIsDeadOrGhost(unit)) ~= false then
        mark:Hide()
        return
    end
    mark:ClearAllPoints()
    mark:SetPoint("BOTTOM", anchor, "TOP", 0, 4)
    mark:Show()
end

local targetMark

local function refreshPlates(force)
    local active = note.db.marks ~= false and inWorld() and not InCombatLockdown()
    if not targetMark then targetMark = makeMark() end
    if active then
        markUnit("target", TargetFrame, targetMark, force)
    else
        targetMark:Hide()
    end
    for unit, mark in pairs(plates) do
        if active then
            markUnit(unit, public(C_NamePlate.GetNamePlateForUnit(unit)), mark, force)
        else
            mark:Hide()
        end
    end
end

function note.RefreshMarks()
    deathsByPlayer = {}
    for _, entry in ipairs(note.db.events) do
        if entry.kind == "D" then deathsByPlayer[entry.other] = (deathsByPlayer[entry.other] or 0) + 1 end
    end
    refreshPlates()
    if note.RefreshNearby then note.RefreshNearby(plates, deathsByPlayer) end
end

local function readDeath(place, observedTarget, observedLevel)
    if not C_DeathRecap or not C_DeathRecap.GetRecapEvents then return end
    local ok, recap = pcall(C_DeathRecap.GetRecapEvents)
    recap = ok and public(recap)
    if type(recap) ~= "table" then return end
    for _, raw in ipairs(recap) do
        local hit = public(raw)
        if type(hit) == "table" then
            local overkill, stamp = public(hit.overkill), public(hit.timestamp)
            if type(overkill) == "number" and overkill >= 0 and type(stamp) == "number"
                and math.abs(stamp - place.at) <= 5 then
                local flags = public(hit.sourceFlags)
                local source = public(hit.sourceGUID)
                local killer = playerGUID(source)
                if not killer and type(source) == "string" and note.petOwners[source] then
                    killer = note.petOwners[source]
                end
                if killer and type(flags) == "number" and bit.band(flags, 0x40) ~= 0 then
                    identify(killer, playerGUID(source) and hit.sourceName or nil)
                    place.killerClass = note.Profile(killer).class
                    if killer == observedTarget then place.killerLevel = observedLevel end
                    place.spellId = note.PositiveInteger(hit.spellId, 10000000)
                        or note.PositiveInteger(hit.spellID, 10000000)
                    local event = clean(hit.event)
                    place.spellName = note.SpellName(place.spellId, clean(hit.spellName))
                    if not place.spellName and event == "SWING_DAMAGE" then place.spellName = "Автоатака" end
                    note.Record("D", killer, place)
                    return true
                end
            end
        end
    end
end

local actions = {}
local huntWeekTicker

local function startHuntWeekWatch()
    if not note.HuntOverview or not C_Timer or not C_Timer.NewTicker or huntWeekTicker then return end
    local _, _, deadline = note.HuntOverview()
    huntWeekTicker = C_Timer.NewTicker(60, function()
        if note.db and GetServerTime() >= deadline then
            local _, _, nextDeadline = note.HuntOverview()
            deadline = nextDeadline
            if note.HuntPresentationChanged then note.HuntPresentationChanged() end
        end
    end)
end
function actions.PLAYER_LOGIN()
    note.Init()
    if not note.db then return end
    note.seen, note.petOwners, note.recentLevels = {}, {}, {}
    observe("player", true)
    note.Refresh()
    if note.StartSharing then note.StartSharing() end
    if note.StartTerritorySync then note.StartTerritorySync() end
    if note.StartMapRelay then note.StartMapRelay() end
    actions.PLAYER_GUILD_UPDATE("player")
    if note.DemoData then note.DemoData() end
    if note.HuntSync then note.HuntSync() end
    if note.StartRampage then note.StartRampage() end
    startHuntWeekWatch()
end

function actions.PARTY_KILL(attacker, target)
    if duelling or not inWorld() then return end
    local victim = playerGUID(target)
    attacker = public(attacker)
    local pet = public(UnitGUID("pet"))
    if not victim or not attacker or (attacker ~= note.owner and attacker ~= pet) then return end
    if not InCombatLockdown() then
        if playerGUID(UnitGUID("target")) == victim then observe("target", true) end
    end
    identify(victim)
    local place = location()
    if playerGUID(UnitGUID("target")) == victim then
        place.victimLevel = note.PositiveInteger(UnitLevel("target"), 255)
    end
    if not place.victimLevel and GetTime() - (note.seen[victim] or -1000) <= 60 then
        place.victimLevel = note.recentLevels[victim]
    end
    place.killerClass = note.Profile(note.owner).class
    note.Record("K", victim, place)
end

function actions.PLAYER_DEAD()
    deathSerial = deathSerial + 1
    if duelling or not inWorld() then return end
    local serial, place = deathSerial, location()
    if note.EndRampage then note.EndRampage(place.at) end
    if note.AssignSortie then note.AssignSortie(place) end
    place.victimLevel = note.PositiveInteger(UnitLevel("player"), 255)
    local observedTarget = playerGUID(UnitGUID("target"))
    local observedLevel = observedTarget and note.PositiveInteger(UnitLevel("target"), 255)
    local attempts = { 0.3, 0.7, 1.0, 1.5 }
    local function try(i)
        if serial ~= deathSerial or readDeath(place, observedTarget, observedLevel) or not attempts[i + 1] then return end
        C_Timer.After(attempts[i + 1], function() try(i + 1) end)
    end
    C_Timer.After(attempts[1], function() try(1) end)
end

function actions.DUEL_INBOUNDS() duelling = true end
function actions.DUEL_FINISHED() duelling = nil end

function actions.NAME_PLATE_UNIT_ADDED(unit)
    if not plates[unit] then plates[unit] = table.remove(recycled) or makeMark() end
    if note.db.marks ~= false and inWorld() and not InCombatLockdown() then
        markUnit(unit, public(C_NamePlate.GetNamePlateForUnit(unit)), plates[unit], true)
    elseif inWorld() and not InCombatLockdown() then
        observe(unit, true)
    end
    if note.RefreshNearby then note.RefreshNearby(plates, deathsByPlayer) end
end

function actions.NAME_PLATE_UNIT_REMOVED(unit)
    local mark = plates[unit]
    if not mark then return end
    mark:Hide()
    mark:ClearAllPoints()
    recycled[#recycled + 1] = mark
    plates[unit] = nil
    if note.RefreshNearby then note.RefreshNearby(plates, deathsByPlayer) end
end

local function refreshGuild()
    local guildName, _, _, guildRealm = GetGuildInfo("player")
    local guild = clean(guildName)
    local count = GetNumGuildMembers and note.PositiveInteger(GetNumGuildMembers(), 10000)
    if guild and count and IsInGuild() then
        note.db.roster = { guild = guild, count = count, at = GetServerTime() }
        if note.CacheTerritoryTabard then
            note.CacheTerritoryTabard("player", guild, note.Faction(UnitFactionGroup("player")), clean(guildRealm))
        end
    end
    if note.RefreshWindow then note.RefreshWindow() end
end

function actions.GUILD_ROSTER_UPDATE()
    refreshGuild()
end

function actions.PLAYER_GUILD_UPDATE(unit)
    if unit and unit ~= "player" then return end
    observe("player", true)
    if not IsInGuild() then note.db.roster = nil end
    if IsInGuild() and not InCombatLockdown() and C_GuildInfo and C_GuildInfo.GuildRoster then
        C_GuildInfo.GuildRoster()
    end
    if note.RefreshWindow then note.RefreshWindow() end
    if note.RefreshLadder then note.RefreshLadder() end
    if note.MaybeOfferGuildSharing then note.MaybeOfferGuildSharing() end
end

function actions.PLAYER_TARGET_CHANGED()
    if not InCombatLockdown() then observe("target", true) end
    refreshPlates(true)
    actions.UNIT_PET("target")
    if note.RefreshNearby then note.RefreshNearby(plates, deathsByPlayer) end
    if note.RefreshWindow then note.RefreshWindow() end
end

function actions.UNIT_FLAGS(unit)
    if unit == "target" or plates[unit] then
        refreshPlates()
        if note.RefreshNearby then note.RefreshNearby(plates, deathsByPlayer) end
    end
end

function actions.UPDATE_MOUSEOVER_UNIT()
    if inWorld() and not InCombatLockdown() then observe("mouseover") end
end

function actions.UNIT_PET(unit)
    if unit ~= "player" and unit ~= "target" then return end
    local token = unit == "player" and "pet" or "targetpet"
    local pet = public(UnitGUID(token))
    local owner = playerGUID(UnitGUID(unit))
    if type(pet) == "string" and owner then note.petOwners[pet] = owner end
end

actions.PLAYER_REGEN_DISABLED = function()
    refreshPlates()
    if note.RefreshNearby then note.RefreshNearby(plates, deathsByPlayer) end
end
actions.PLAYER_REGEN_ENABLED = function()
    refreshPlates()
    if note.RefreshNearby then note.RefreshNearby(plates, deathsByPlayer) end
    if note.Flush then note.Flush() end
    if note.MaybeOfferGuildSharing then note.MaybeOfferGuildSharing() end
    if note.MaybeStartGuide then note.MaybeStartGuide() end
end
actions.PLAYER_ENTERING_WORLD = function()
    if not note.db then actions.PLAYER_LOGIN() end
    if not note.db then return end
    duelling = nil
    refreshPlates()
    if note.RefreshNearby then note.RefreshNearby(plates, deathsByPlayer) end
    if note.Flush then note.Flush() end
    if note.MaybeOfferGuildSharing then note.MaybeOfferGuildSharing() end
    if note.MaybeStartGuide then note.MaybeStartGuide() end
end
actions.ZONE_CHANGED_NEW_AREA = function()
    refreshPlates()
    if note.RefreshNearby then note.RefreshNearby(plates, deathsByPlayer) end
end
actions.ZONE_CHANGED = actions.ZONE_CHANGED_NEW_AREA

for event in pairs(actions) do driver:RegisterEvent(event) end
driver:SetScript("OnEvent", function(_, event, ...)
    if event == "PLAYER_LOGIN" or event == "PLAYER_ENTERING_WORLD" or note.db then actions[event](...) end
end)
