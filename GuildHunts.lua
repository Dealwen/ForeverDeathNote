local _, note = ...
local prefix = "FDN_HUNT1"
local day, week = 86400, 7 * 86400
local states = { A = "active", C = "cancelled", D = "completed", E = "expired" }
local stateOrder = { active = 1, completed = 2, cancelled = 3, expired = 4 }
local listener = CreateFrame("Frame")
local registered, currentGuild
local nextSend, nextQuery, announceAt, lastQuery, lastAnnouncement
local ownRequest, requestSerial, relayJob, relayAllowedAt = nil, 0, nil, 0
local relayCursor = {}
local lower = strlower or string.lower

local function hash(value)
    local result = 0
    for i = 1, #value do result = (result * 131 + value:byte(i)) % 2147483647 end
    return tostring(result)
end

local function context()
    if not note.db or not note.scope or not IsInGuild() then return end
    local guild = note.Text(GetGuildInfo("player"))
    if not guild then return end
    local faction = note.Faction(UnitFactionGroup("player")) or ""
    local key = note.scope .. "\31" .. lower(guild) .. "\31" .. faction
    return key, hash(key)
end

local function saved(key, create)
    local scopes = note.db.guildHunts
    if not scopes and create then
        scopes = {}
        note.db.guildHunts = scopes
    end
    if scopes and not scopes[key] and create then scopes[key] = { peers = {} } end
    return scopes and scopes[key]
end

local function senderKey(name)
    local realm = note.Text(GetRealmName()) or ""
    if not name:find("-", 1, true) and realm ~= "" then name = name .. "-" .. realm end
    return lower(name:gsub("%s+", ""))
end

local function playerName()
    return note.UnitName("player") or note.owner
end

local function displayStatus(hunt, now)
    if hunt.status == "active" and hunt.expires < now then return "expired" end
    return hunt.status
end

local function retain(hunt, now)
    return now < math.max(hunt.expires, hunt.updated) + day
end

local function visible(hunt, now)
    return now < (hunt.status == "active" and hunt.expires or hunt.updated) + day
end

local function refresh()
    if note.RefreshGuildHunts then note.RefreshGuildHunts() end
end

local function updateOwn(data, hunt, status, now)
    data.revision = math.max(now * 1000, (data.revision or 0) + 1)
    hunt.revision, hunt.updated, hunt.status = data.revision, now, states[status]
    hunt.code = status
    data.own = hunt
    announceAt = now
    refresh()
end

local function matchesContract(hunt, contract)
    return contract and hunt.target == contract.id and hunt.started == contract.started
end

local function reconcile(data, now)
    local hunt = data and data.own
    if not hunt then return end
    if not retain(hunt, now) then data.own = nil; refresh(); return end
    local contract = note.db.hunt and note.db.hunt.contract
    if (hunt.status == "active" or hunt.status == "expired") and matchesContract(hunt, contract) and contract.completed then
        updateOwn(data, hunt, "D", now)
    elseif hunt.status == "active" then
        if now > hunt.expires then updateOwn(data, hunt, "E", now)
        elseif not matchesContract(hunt, contract) then updateOwn(data, hunt, "C", now) end
    end
end

local function switchGuild(now)
    local key, token = context()
    if not note.db or not note.db.sharing then key = nil end
    if key ~= currentGuild then
        currentGuild, announceAt, nextSend, lastQuery, lastAnnouncement = key, nil, 0, nil, nil
        ownRequest, relayJob, relayAllowedAt = nil, nil, 0
        relayCursor = {}
        nextQuery = key and now + 2
        local data = key and saved(key)
        if data and data.own and retain(data.own, now) then announceAt = now + 2 end
        refresh()
    end
    return key, token
end

local function sendState(token, hunt, nonce)
    local fields = nonce and { "R", token, nonce, hunt.author } or { "S", token }
    for _, value in ipairs({ hunt.revision, hunt.target, hunt.started, hunt.expires,
        hunt.code, hunt.name or "" }) do
        fields[#fields + 1] = value
    end
    local wire = table.concat(fields, ";")
    if #wire > 240 then
        fields[#fields] = ""
        wire = table.concat(fields, ";")
    end
    if #wire > 240 then return false end
    C_ChatInfo.SendAddonMessage(prefix, wire, "GUILD")
    return true
end

local function pump()
    if not registered then return end
    local now = GetServerTime()
    local key, token = switchGuild(now)
    if not key then return end
    local data = saved(key)
    reconcile(data, now)
    if now < nextSend or InCombatLockdown() or IsInInstance() then return end
    local hunt = data and data.own
    if announceAt and announceAt <= now then
        announceAt = nil
        if hunt and sendState(token, hunt) then
            nextSend, lastAnnouncement = now + 2, now
            return
        end
    end
    if nextQuery and nextQuery <= now then
        nextQuery, nextSend, lastQuery = now + 600, now + 2, now
        requestSerial = requestSerial + 1
        ownRequest = { nonce = hash(note.owner .. "/" .. now .. "/" .. requestSerial), ends = now + 65 }
        C_ChatInfo.SendAddonMessage(prefix, "Q;" .. token .. ";" .. ownRequest.nonce, "GUILD")
        return
    end
    if relayJob and (now >= relayJob.ends or relayJob.sent >= 12) then relayJob = nil end
    if relayJob and now >= relayJob.ready then
        for i = relayJob.next, #relayJob.rows do
            relayJob.next = i + 1
            local author = relayJob.rows[i]
            local peer = data and data.peers[author]
            if peer and not peer.relay and retain(peer, now) and (relayJob.observed[author] or 0) < peer.revision
                and sendState(token, peer, relayJob.nonce) then
                relayJob.sent, nextSend = relayJob.sent + 1, now + 2
                return
            end
        end
        relayJob = nil
    end
end

function note.RequestGuildHunts()
    if not registered or not note.db or not note.db.sharing then return end
    local now = GetServerTime()
    local key = switchGuild(now)
    if key then
        local soon = math.max(now, (lastQuery or 0) + 15)
        nextQuery = math.min(nextQuery or soon, soon)
        pump()
    end
end

function note.GuildHuntSharingChanged()
    if not note.db then return end
    local now = GetServerTime()
    local key = context()
    if key and not note.db.sharing then
        local data = saved(key)
        reconcile(data, now)
        local hunt = data and data.own
        if hunt and hunt.status == "active" then updateOwn(data, hunt, "C", now) end
    end
    pump()
end

function note.GuildHuntContractChanged()
    pump()
end

function note.StartGuildHunts()
    if registered or not C_ChatInfo or not C_ChatInfo.RegisterAddonMessagePrefix
        or not C_ChatInfo.SendAddonMessage then return end
    local result = C_ChatInfo.RegisterAddonMessagePrefix(prefix)
    if result == false then return end
    registered = true
    listener:RegisterEvent("CHAT_MSG_ADDON")
    listener:RegisterEvent("PLAYER_ENTERING_WORLD")
    listener:RegisterEvent("PLAYER_GUILD_UPDATE")
    listener:RegisterEvent("PLAYER_REGEN_ENABLED")
    pump()
    if C_Timer and C_Timer.NewTicker then C_Timer.NewTicker(2, pump) end
end

function note.ToggleSharedHunt(demo)
    if demo or not registered or not note.db or not note.db.sharing then return false end
    local now = GetServerTime()
    local key = switchGuild(now)
    if not key then return false end
    local data = saved(key, true)
    reconcile(data, now)
    if data.own and data.own.status == "active" then
        updateOwn(data, data.own, "C", now)
    else
        local contract = note.db.hunt and note.db.hunt.contract
        if not contract or contract.completed or contract.expires < now then return false end
        local target = note.GUID(contract.id)
        if not target then return false end
        updateOwn(data, { target = target, name = note.Text(note.Profile(target).name),
            started = contract.started, expires = contract.expires }, "A", now)
    end
    pump()
    return true
end

local function queueRelay(data, author, nonce, now)
    if now < relayAllowedAt then return end
    local rows = {}
    for id, hunt in pairs(data.peers) do
        if id ~= author and not hunt.relay and retain(hunt, now) then rows[#rows + 1] = id end
    end
    if #rows == 0 then return end
    table.sort(rows, function(a, b)
        local left, right = data.peers[a], data.peers[b]
        if (left.status == "active") ~= (right.status == "active") then
            return left.status == "active"
        end
        if left.updated ~= right.updated then return left.updated > right.updated end
        return a < b
    end)
    local first, batch = (relayCursor[author] or 0) % #rows, {}
    for i = 1, math.min(#rows, 12) do batch[i] = rows[(first + i - 1) % #rows + 1] end
    relayCursor[author] = (first + #batch) % #rows
    relayAllowedAt = now + 25
    relayJob = { rows = batch, nonce = nonce, ends = now + 60, ready = now + 3 + (tonumber(hash(author .. playerName())) % 6),
        next = 1, sent = 0, observed = {} }
end

local function receive(text, sender)
    local now = GetServerTime()
    local key, token = switchGuild(now)
    if not key or type(text) ~= "string" or #text > 240 then return end
    local own = senderKey(playerName())
    local author = senderKey(sender)
    if author == own then return end
    local data = saved(key, true)
    local queryNonce = text:match("^Q;" .. token .. ";(%d+)$")
    if queryNonce and #queryNonce <= 10 then
        if data.own then
            reconcile(data, now)
            if data.own then
                local delay = (#author * 3 + #own) % 5
                local due = math.max(now + delay, (lastAnnouncement or 0) + 12)
                announceAt = math.min(announceAt or due, due)
                pump()
            end
        end
        queueRelay(data, author, queryNonce, now)
        return
    end
    local relayNonce, relayAuthor, relayText = text:match("^R;" .. token .. ";(%d+);([^;]+);(.+)$")
    local relay = relayNonce ~= nil
    if relay then
        relayAuthor = note.Text(relayAuthor)
        if not relayAuthor or senderKey(relayAuthor) == own or senderKey(relayAuthor) == author then return end
        author, text = senderKey(relayAuthor), relayText
    else
        text = text:match("^S;" .. token .. ";(.+)$")
        if not text then return end
    end
    local revision, target, started, expires, status, name =
        text:match("^(%d+);([^;]+);(%d+);(%d+);([ACDE]);([^;]*)$")
    if not revision or not note.GUID(target) then return end
    revision, started, expires = tonumber(revision), tonumber(started), tonumber(expires)
    local updated = math.floor(revision / 1000)
    if expires <= started or expires - started > week or started < now - week - day
        or updated < started or updated > now + 30 or (status == "E" and updated < expires) then return end
    local remote = { target = target, name = note.Text(name), author = relayAuthor or sender,
        started = started, expires = expires, revision = revision, updated = updated, status = states[status],
        code = status, relay = relay or nil }
    if not retain(remote, now) then return end
    if relay then
        if relayJob and relayJob.nonce == relayNonce and data.peers[author] then
            relayJob.observed[author] = math.max(relayJob.observed[author] or 0, revision)
        end
        if not ownRequest or ownRequest.nonce ~= relayNonce or now >= ownRequest.ends then return end
    end
    local existing = data.peers[author]
    if existing and (existing.revision > revision
        or (existing.revision == revision and (relay or not existing.relay))) then return end
    if not existing then
        local count = 0
        for id, row in pairs(data.peers) do
            if retain(row, now) then count = count + 1 else data.peers[id] = nil end
        end
        if count >= 1024 then return end
    end
    data.peers[author] = remote
    refresh()
end

listener:SetScript("OnEvent", function(_, event, tag, text, channel, sender)
    if event ~= "CHAT_MSG_ADDON" then pump(); return end
    if note.Public(tag) ~= prefix or note.Public(channel) ~= "GUILD" then return end
    sender = note.Text(sender)
    if sender then receive(note.Public(text), sender) end
end)

function note.GuildHuntList(demo)
    if demo then
        local list = {}
        for i, status in ipairs({ "active", "completed", "cancelled", "expired" }) do
            local target = ({ "ash", "bramble", "frost", "dusk" })[i]
            local author = ({ "self", "dusk", "bramble", "ash" })[i]
            if demo.profiles[target] and demo.profiles[author] then
                list[#list + 1] = { target = target, name = demo.profiles[target].name,
                    author = demo.profiles[author].name, status = status }
            end
        end
        return list
    end
    local key = context()
    local data = key and saved(key)
    local list = {}
    local now = GetServerTime()
    local function add(hunt, author)
        if hunt and visible(hunt, now) then
            list[#list + 1] = { target = hunt.target, name = hunt.name or note.Name(hunt.target),
                author = author, status = displayStatus(hunt, now), updated = hunt.updated, relay = hunt.relay }
        end
    end
    if data then
        add(data.own, playerName())
        for _, hunt in pairs(data.peers) do add(hunt, hunt.author) end
        table.sort(list, function(a, b)
            if a.status ~= b.status then return stateOrder[a.status] < stateOrder[b.status] end
            if a.updated ~= b.updated then return a.updated > b.updated end
            return a.author < b.author
        end)
    end
    return list, data and data.own, registered and key and note.db.sharing, key ~= nil
end
