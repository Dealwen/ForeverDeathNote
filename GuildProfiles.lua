local _, note = ...
local prefix = "FDN_CARD1"
local listener = CreateFrame("Frame")
local lower = strlower or string.lower
local registered, session, serial = false, nil, 0

local function refresh()
    if note.RefreshWindow then note.RefreshWindow() end
end

local function context()
    local guild = registered and note.db and note.db.sharing and note.CurrentGuild()
    local key = guild and note.scope .. "\31" .. lower(guild) .. "\31" .. note.owner
    if not key then session = nil; return end
    if not session or session.key ~= key then
        session = { key = key, profiles = {}, requests = {}, lastReply = {},
            nextRequest = 0, nextReply = 0 }
    end
    return session
end

local function memberName(raw)
    local name = note.Text(raw)
    if not name then return end
    local character, realm = name:match("^([^%-]+)%-(.+)$")
    if not realm then
        character = name
        realm = note.Text(GetNormalizedRealmName and GetNormalizedRealmName()) or note.Text(GetRealmName())
    end
    if realm then return lower((character .. "-" .. realm):gsub("%s+", "")) end
end

local function legacyMember(index)
    local name, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, guid = GetGuildRosterInfo(index)
    return name, guid
end

local function indexRoster(active)
    if active.byGuid then return end
    local names, guids = {}, {}
    active.byGuid, active.byName = names, guids
    local function add(rawName, rawGuid)
        local guid, name = note.GUID(rawGuid), memberName(rawName)
        if guid and name then
            names[guid], guids[name] = name, guid
        end
    end
    if GetNumGuildMembers and GetGuildRosterInfo then
        local count = note.PositiveInteger(GetNumGuildMembers(), 10000) or 0
        for index = 1, count do
            local ok, name, guid = pcall(legacyMember, index)
            if ok then add(name, guid) end
        end
    end
    if C_Club and C_Club.GetGuildClubId and C_Club.GetClubMembers and C_Club.GetMemberInfo then
        local ok, club = pcall(C_Club.GetGuildClubId)
        club = ok and note.Public(club)
        if club then
            local fetched, members = pcall(C_Club.GetClubMembers, club)
            members = fetched and note.Public(members)
            if type(members) == "table" then
                for _, memberId in ipairs(members) do
                    local found, info = pcall(C_Club.GetMemberInfo, club, memberId)
                    info = found and note.Public(info)
                    if type(info) == "table" then add(info.name, info.guid) end
                end
            end
        end
    end
end

local function ownProfile()
    local wins, victims = note.LadderPersonal()
    local _, _, tier = note.LadderRank(wins, victims)
    local awards, earned = note.LadderAchievements(), 0
    for _, rule in ipairs(note.LadderAchievementRules) do
        if awards[rule.id] then earned = earned + 1 end
    end
    return { tier = tier, earned = earned, rampages = note.RampageCount and note.RampageCount() or 0 }
end

local function canSend()
    return not InCombatLockdown() and not IsInInstance()
end

local function request(active, id)
    if not canSend() then return end
    indexRoster(active)
    local member = active.byGuid[id]
    if not member or active.byName[member] ~= id then return end
    local now = GetTime()
    local previous = active.requests[id]
    if previous and now < previous.retryAt then return end
    if now < active.nextRequest then
        active.queued = id
        if not active.waiting and C_Timer and C_Timer.After then
            active.waiting = true
            C_Timer.After(active.nextRequest - now + 0.05, function()
                if context() ~= active then return end
                local queued = active.queued
                active.queued, active.waiting = nil, nil
                if queued and not active.profiles[queued] then request(active, queued) end
            end)
        end
        return
    end
    serial = serial + 1
    local nonce = ("%x.%x"):format(math.floor(now * 1000), serial)
    active.nextRequest = now + 2
    active.requests[id] = { nonce = nonce, expires = now + 15, retryAt = now + 25 }
    C_ChatInfo.SendAddonMessage(prefix, table.concat({ "Q", note.owner, id, nonce }, ";"), "GUILD")
end

function note.GetRankingProfile(id)
    id = note.GUID(id)
    if not id or not note.db then return end
    if id == note.owner then return ownProfile() end
    local active = context()
    if not active then return end
    indexRoster(active)
    local member = active.byGuid[id]
    if not member or active.byName[member] ~= id then return end
    local result = active.profiles[id]
    if result and GetTime() < result.expires then return result end
    active.profiles[id] = nil
    request(active, id)
end

local function safeCount(value, minimum, maximum)
    if not value or #value > 10 then return end
    local num = tonumber(value)
    if num and num >= minimum and num <= maximum then return num end
end

local function validNonce(value)
    return value and #value <= 30 and value:match("^%x+%.%x+$")
end

local function answer(active, requester, nonce)
    if not canSend() then return end
    local now = GetTime()
    if active.lastReply[requester] and now < active.lastReply[requester] + 3 then return end
    local sendAt = math.max(active.nextReply, now)
    if sendAt - now > 6 then return end
    active.nextReply, active.lastReply[requester] = sendAt + 1, now

    local function send()
        if context() ~= active or not canSend() then return end
        indexRoster(active)
        local member = active.byGuid[requester]
        if not member or active.byName[member] ~= requester then return end
        local snapshot = ownProfile()
        local packet = table.concat({ "A", note.owner, requester, nonce, snapshot.tier, snapshot.earned, snapshot.rampages }, ";")
        C_ChatInfo.SendAddonMessage(prefix, packet, "GUILD")
    end
    if sendAt == now then send()
    elseif C_Timer and C_Timer.After then C_Timer.After(sendAt - now, send) end
end

local function receive(text, author)
    text = note.Public(text)
    if type(text) ~= "string" or #text > 240 then return end
    local active, name = context(), memberName(author)
    if not active or not name then return end
    indexRoster(active)
    local sender = active.byName[name]
    if not sender or sender == note.owner or active.byGuid[sender] ~= name then return end

    local asking, target, queryNonce = text:match("^Q;([^;]+);([^;]+);([^;]+)$")
    if asking then
        if asking == sender and target == note.owner and validNonce(queryNonce) then
            answer(active, sender, queryNonce)
        end
        return
    end

    local authorId, requester, nonce, tierText, earnedText, rampageText =
        text:match("^A;([^;]+);([^;]+);([^;]+);(%d+);(%d+);(%d+)$")
    local pending = active.requests[sender]
    if authorId ~= sender or requester ~= note.owner or not pending
        or GetTime() >= pending.expires or nonce ~= pending.nonce then return end
    local tier = safeCount(tierText, 1, #note.LadderRanks)
    local earned = safeCount(earnedText, 0, 10000)
    local rampages = safeCount(rampageText, 0, 2147483647)
    if not tier or not earned or not rampages then return end
    active.requests[sender] = nil
    active.profiles[sender] = { tier = tier, earned = earned, rampages = rampages, expires = GetTime() + 600 }
    refresh()
end

function note.GuildProfilesSharingChanged()
    context()
    refresh()
end

function note.StartGuildProfiles()
    if registered or not C_ChatInfo or not C_ChatInfo.RegisterAddonMessagePrefix
        or not C_ChatInfo.SendAddonMessage then return end
    local result = C_ChatInfo.RegisterAddonMessagePrefix(prefix)
    if result == false then return end
    registered = true
    listener:RegisterEvent("CHAT_MSG_ADDON")
    listener:RegisterEvent("GUILD_ROSTER_UPDATE")
    listener:RegisterEvent("PLAYER_GUILD_UPDATE")
    listener:RegisterEvent("PLAYER_REGEN_ENABLED")
    listener:RegisterEvent("PLAYER_ENTERING_WORLD")
end

listener:SetScript("OnEvent", function(_, event, tag, text, channel, sender)
    if event == "CHAT_MSG_ADDON" then
        if note.Public(tag) == prefix and note.Public(channel) == "GUILD" then receive(text, sender) end
        return
    end
    local active = context()
    if active and event ~= "PLAYER_REGEN_ENABLED" then active.byGuid, active.byName = nil, nil end
    refresh()
end)
