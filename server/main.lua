-- server/main.lua — Hot Pursuit
-- 1 runner vs up to 6 chasers. Free lobby → roles → isolated bucket → runner
-- head start → server-authoritative BUST METER: it fills while any chaser is
-- within range of the runner (proximity, since the global no-collision rules out
-- ramming). Meter full = busted (chasers win); survive the timer = runner wins.

local Log = SPZ and SPZ.Logger and SPZ.Logger("spz-pursuit") or nil
local function log(m) if Log then Log.info(m) else print("[pursuit] " .. m) end end

local lobby = {}
local lobbyArmed = false
local lobbyArmedAt = nil
local round = nil

local function notify(src, msg, t) TriggerClientEvent("spz-pursuit:notify", src, msg, t or "info") end

local function pidOf(src)
    local ok, p = pcall(function() return exports["spz-identity"]:GetProfile(src) end)
    return ok and p and p.id or nil, ok and p or nil
end
local function srcFromPid(pid)
    for _, s in ipairs(GetPlayers()) do if pidOf(tonumber(s)) == pid then return tonumber(s) end end
    return nil
end
local function payPid(pid, amt, reason)
    if amt <= 0 then return end
    local s = srcFromPid(pid)
    if s then exports["spz-progression"]:GrantBonus(s, { credits = amt, reason = reason })
    else MySQL.update.await("UPDATE players SET credits = credits + ? WHERE id = ?", { amt, pid }) end
end
local function shuffle(t) for i = #t, 2, -1 do local j = math.random(i); t[i], t[j] = t[j], t[i] end end
local function lobbyCount() local n = 0; for _ in pairs(lobby) do n = n + 1 end; return n end

local function inList(list, v)
    for _, x in ipairs(list) do if x == v then return true end end
    return false
end

-- Snapshot the lobby/round for a given viewer — feeds the queue menu.
local function lobbyStateFor(src)
    local roster = {}
    for s, e in pairs(lobby) do roster[#roster + 1] = { name = e.name, isMe = (s == src) } end
    table.sort(roster, function(a, b) return a.name < b.name end)

    return {
        inRound = round ~= nil and round.players[src] ~= nil,
        roundLive = round ~= nil,
        inLobby = lobby[src] ~= nil,
        count = lobbyCount(),
        min = Config.MinPlayers,
        max = Config.MaxPlayers,
        armed = lobbyArmed,
        armedRemain = lobbyArmed and math.max(0, (Config.LobbyWaitSec or 30) - math.floor((GetGameTimer() - lobbyArmedAt) / 1000)) or nil,
        roster = roster,
        carPref = lobby[src] and lobby[src].carPref or nil,
        runnerModels = Config.RunnerModels or { Config.RunnerModel },
        chaserModels = Config.ChaserModels or { Config.ChaserModel },
    }
end

local function cancelLobby(reason)
    for src in pairs(lobby) do
        notify(src, ("Lobby cancelled — %s"):format(reason), "warning")
    end
    lobby = {}; lobbyArmed = false; lobbyArmedAt = nil
end

local function endRound(winnerRole, reason)
    if not round then return end
    local r = round; round = nil

    local winners = {}
    for _, p in pairs(r.players) do if p.role == winnerRole then winners[#winners + 1] = p end end
    local reward = Config.WinReward or 0
    for _, p in ipairs(winners) do if reward > 0 then payPid(p.pid, reward, "Hot Pursuit won") end end

    for src, p in pairs(r.players) do
        TriggerClientEvent("spz-pursuit:over", src, {
            winner = winnerRole, reason = reason, won = (p.role == winnerRole), payout = (p.role == winnerRole) and reward or 0,
        })
    end

    SetTimeout(1500, function()
        if r.bucketId and r.bucketId ~= 0 and GetResourceState("spz-core") == "started" then
            exports["spz-core"]:DeleteBucket(r.bucketId)
        end
    end)
    pcall(function()
        exports["spz-log"]:Log("minigame", "Hot Pursuit",
            ("%s won (%s). %d winner(s) @ %d each."):format(winnerRole, reason, #winners, reward), "success")
    end)
    log(("round over: %s (%s)"):format(winnerRole, reason))
end

local function startRound()
    lobbyArmed = false; lobbyArmedAt = nil
    if lobbyCount() < Config.MinPlayers then cancelLobby("not enough players"); return end

    local roster = {}
    for src, e in pairs(lobby) do roster[#roster + 1] = { src = src, pid = e.pid, name = e.name, stake = e.stake, carPref = e.carPref } end
    shuffle(roster)

    local bucketId = 0
    if GetResourceState("spz-core") == "started" then
        bucketId = exports["spz-core"]:CreateBucket("pursuit")
        SetRoutingBucketPopulationEnabled(bucketId, true)   -- traffic for cover
    end

    round = {
        bucketId = bucketId, players = {}, phase = "head", meter = 0,
        headEndsAt = GetGameTimer() + (Config.HeadStartSec * 1000),
        endsAt = GetGameTimer() + ((Config.HeadStartSec + Config.RoundTimeSec) * 1000),
        runner = roster[1].src, chasers = {},
    }

    local runnerPool = Config.RunnerModels or { Config.RunnerModel }
    local chaserPool = Config.ChaserModels or { Config.ChaserModel }

    for i, m in ipairs(roster) do
        local isRunner = (i == 1)
        local pool = isRunner and runnerPool or chaserPool
        local picked = m.carPref and (isRunner and m.carPref.runner or m.carPref.chaser)
        local model = (picked and inList(pool, picked)) and picked or pool[1]

        round.players[m.src] = { pid = m.pid, name = m.name, role = isRunner and "runner" or "chaser", model = model }
        if not isRunner then round.chasers[#round.chasers + 1] = m.src end
        if bucketId ~= 0 then exports["spz-core"]:AssignPlayerToBucket(m.src, bucketId) end
    end
    lobby = {}

    local roles = {}
    for src, p in pairs(round.players) do roles[#roles + 1] = { src = src, role = p.role } end

    for src, p in pairs(round.players) do
        TriggerClientEvent("spz-pursuit:start", src, {
            role = p.role, arena = Config.Arena, spread = Config.SpawnSpread,
            headTime = Config.HeadStartSec, roundTime = Config.RoundTimeSec,
            runnerModel = p.role == "runner" and p.model or Config.RunnerModel,
            chaserModel = p.role == "chaser" and p.model or Config.ChaserModel,
            runner = round.runner, roles = roles,
        })
    end
    log(("round start: 1 runner + %d chasers (free)"):format(#round.chasers))
end

-- ── Tick ────────────────────────────────────────────────────────────────────
CreateThread(function()
    while true do
        Wait(500)
        if round then
            local now = GetGameTimer()

            if round.phase == "head" and now >= round.headEndsAt then
                round.phase = "chase"
                for src in pairs(round.players) do TriggerClientEvent("spz-pursuit:release", src) end
            end

            if round.phase == "chase" then
                local rped = GetPlayerPed(round.runner)
                local inRange = false
                if rped ~= 0 then
                    local rp = GetEntityCoords(rped)
                    for _, c in ipairs(round.chasers) do
                        local cped = GetPlayerPed(c)
                        if cped ~= 0 and #(rp - GetEntityCoords(cped)) < (Config.BustDist or 18.0) then inRange = true; break end
                    end
                end

                if inRange then round.meter = math.min(100, round.meter + (Config.BustFillPerSec or 22) * 0.5)
                else round.meter = math.max(0, round.meter - (Config.BustDrainPerSec or 9) * 0.5) end

                if round.meter >= 100 then endRound("chaser", "runner busted")
                elseif now >= round.endsAt then endRound("runner", "escaped") end
            end

            if round then
                local remain = math.max(0, math.floor((round.endsAt - GetGameTimer()) / 1000))
                local headRemain = math.max(0, math.floor((round.headEndsAt - GetGameTimer()) / 1000))
                for src in pairs(round.players) do
                    TriggerClientEvent("spz-pursuit:state", src, {
                        phase = round.phase, remain = remain, headRemain = headRemain, meter = math.floor(round.meter),
                    })
                end
            end
        end
    end
end)

-- ── Join / leave ──────────────────────────────────────────────────────────────
-- Shared by the /pursuit command and the queue menu's Join/Leave button.
local function toggleJoin(src)
    if round and round.players[src] then notify(src, "You're in a round.", "error"); return end
    if round then notify(src, "A round is in progress.", "warning"); return end
    if lobby[src] then lobby[src] = nil; notify(src, "Left the lobby.", "info"); return end
    if lobbyCount() >= Config.MaxPlayers then notify(src, "Lobby full.", "error"); return end

    local pid, prof = pidOf(src)
    if not pid then notify(src, "Profile not ready.", "error"); return end

    lobby[src] = { pid = pid, name = prof.username or GetPlayerName(src), carPref = {} }
    notify(src, ("Joined Hot Pursuit (free). %d in lobby."):format(lobbyCount()), "success")

    if not lobbyArmed then
        lobbyArmed = true
        lobbyArmedAt = GetGameTimer()
        SetTimeout((Config.LobbyWaitSec or 30) * 1000, function()
            if not round and lobbyArmed then startRound() end
        end)
    end
end

-- ── Commands ──────────────────────────────────────────────────────────────────
RegisterCommand(Config.Command, function(source) toggleJoin(source) end, false)

RegisterCommand(Config.StartCommand, function(source)
    local src = source
    if round then return end
    if not lobby[src] then notify(src, "Join first with /" .. Config.Command, "error"); return end
    if lobbyCount() < Config.MinPlayers then notify(src, ("Need %d players."):format(Config.MinPlayers), "error"); return end
    startRound()
end, false)

-- ── Queue menu callbacks ────────────────────────────────────────────────────

lib.callback.register("spz-pursuit:lobbyState", function(src)
    return lobbyStateFor(src)
end)

lib.callback.register("spz-pursuit:joinToggle", function(src)
    toggleJoin(src)
    return lobbyStateFor(src)
end)

lib.callback.register("spz-pursuit:setCar", function(src, role, model)
    local e = lobby[src]
    if not e then return { ok = false, error = "Join the lobby first." } end
    if role ~= "runner" and role ~= "chaser" then return { ok = false, error = "Bad role." } end

    local pool = role == "runner" and (Config.RunnerModels or { Config.RunnerModel }) or (Config.ChaserModels or { Config.ChaserModel })
    if not inList(pool, model) then return { ok = false, error = "Not an available car." } end

    e.carPref = e.carPref or {}
    e.carPref[role] = model
    return { ok = true }
end)

-- Online players eligible to invite: not already queued, not in a live round.
lib.callback.register("spz-pursuit:online", function(src)
    local list = {}
    for _, pid in ipairs(GetPlayers()) do
        local sid = tonumber(pid)
        if sid ~= src and not lobby[sid] and not (round and round.players[sid]) then
            local ok, profile = pcall(function() return exports["spz-identity"]:GetProfile(sid) end)
            local name = (ok and profile and profile.username) or GetPlayerName(sid) or ("Racer" .. sid)
            list[#list + 1] = { source = sid, name = name }
        end
    end
    table.sort(list, function(a, b) return a.name < b.name end)
    return list
end)

-- ── Invites ───────────────────────────────────────────────────────────────────

RegisterNetEvent("spz-pursuit:invite", function(targetSrc)
    local src = source
    targetSrc = tonumber(targetSrc)
    if not lobby[src] then notify(src, "Join the lobby before inviting.", "error"); return end
    if not targetSrc or not GetPlayerName(targetSrc) then notify(src, "That player isn't online.", "error"); return end
    if lobby[targetSrc] then notify(src, "They're already queued.", "info"); return end
    if round and round.players[targetSrc] then notify(src, "They're in a round.", "error"); return end
    if lobbyCount() >= Config.MaxPlayers then notify(src, "Lobby full.", "error"); return end

    local fromName = lobby[src].name
    TriggerClientEvent("spz-pursuit:invited", targetSrc, { fromSrc = src, fromName = fromName })
    notify(src, ("Invite sent to %s."):format(GetPlayerName(targetSrc) or "player"), "success")
end)

RegisterNetEvent("spz-pursuit:acceptInvite", function()
    local src = source
    if not lobby[src] then toggleJoin(src) end
end)

AddEventHandler("playerDropped", function()
    local src = source
    if lobby[src] then lobby[src] = nil; return end
    if round and round.players[src] then
        -- Runner disconnects → chasers win; a chaser leaving just thins the pack.
        if round.players[src].role == "runner" then endRound("chaser", "runner left") end
    end
end)
