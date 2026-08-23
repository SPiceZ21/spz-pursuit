-- client/main.lua — Hot Pursuit
-- TP into the arena, spawn role car (runner = getaway, chaser = cop), show the
-- HUD + bust meter, and blip the other side. Server owns the meter & result.

local active  = false
local role    = nil        -- "runner" | "chaser"
local phase   = "head"
local state   = { remain = 0, headRemain = 0, meter = 0 }
local myBack  = nil
local myVeh   = 0
local runnerSrc = nil
local roster  = {}         -- { {src, role} }
local blips   = {}         -- [serverId] = blip

RegisterNetEvent("spz-pursuit:notify", function(msg, t) lib.notify({ description = msg, type = t or "info" }) end)

-- ── Queue / invite / car-select menu (ox_lib context) ─────────────────────────

local function prettyModelLabel(model)
    local hash = GetHashKey(model)
    local nameGxt = GetDisplayNameFromVehicleModel(hash)
    local nameText = (nameGxt and nameGxt ~= "") and GetLabelText(nameGxt) or ""
    if nameText == "NULL" or nameText == "" then nameText = model end
    return nameText
end

local function openLobbyMenu()
    local st = lib.callback.await("spz-pursuit:lobbyState", false)
    if not st then return end

    if st.roundLive then
        lib.notify({ description = "A round is already in progress.", type = "warning" })
        return
    end

    -- Runner car submenu
    local runnerOptions = {}
    for _, m in ipairs(st.runnerModels) do
        local isPicked = st.carPref and st.carPref.runner == m
        runnerOptions[#runnerOptions + 1] = {
            title = prettyModelLabel(m),
            description = isPicked and "Selected" or "Tap to select",
            icon = isPicked and "check" or "car",
            onSelect = function()
                lib.callback.await("spz-pursuit:setCar", false, "runner", m)
                openLobbyMenu()
            end,
        }
    end
    lib.registerContext({ id = "spz_pursuit_runner_car", title = "Runner Car", menu = "spz_pursuit_lobby", options = runnerOptions })

    -- Chaser car submenu
    local chaserOptions = {}
    for _, m in ipairs(st.chaserModels) do
        local isPicked = st.carPref and st.carPref.chaser == m
        chaserOptions[#chaserOptions + 1] = {
            title = prettyModelLabel(m),
            description = isPicked and "Selected" or "Tap to select",
            icon = isPicked and "check" or "car-side",
            onSelect = function()
                lib.callback.await("spz-pursuit:setCar", false, "chaser", m)
                openLobbyMenu()
            end,
        }
    end
    lib.registerContext({ id = "spz_pursuit_chaser_car", title = "Chaser Car", menu = "spz_pursuit_lobby", options = chaserOptions })

    -- Invite submenu
    local online = lib.callback.await("spz-pursuit:online", false) or {}
    local inviteOptions = {}
    if #online == 0 then
        inviteOptions[1] = { title = "No one else online", disabled = true }
    else
        for _, p in ipairs(online) do
            inviteOptions[#inviteOptions + 1] = {
                title = p.name,
                icon = "user-plus",
                onSelect = function()
                    TriggerServerEvent("spz-pursuit:invite", p.source)
                end,
            }
        end
    end
    lib.registerContext({ id = "spz_pursuit_invite", title = "Invite Player", menu = "spz_pursuit_lobby", search = #online > 6, options = inviteOptions })

    -- Read-only roster
    local mainOptions = {
        {
            title = st.inLobby and "Leave Queue" or "Join Queue",
            description = st.inLobby and "You're queued — tap to leave" or "Free to join",
            icon = st.inLobby and "right-from-bracket" or "right-to-bracket",
            iconColor = st.inLobby and "#ff4d5e" or "#ff6200",
            onSelect = function()
                lib.callback.await("spz-pursuit:joinToggle", false)
                openLobbyMenu()
            end,
        },
        {
            title = "Runner Car",
            description = (st.carPref and st.carPref.runner and prettyModelLabel(st.carPref.runner)) or ("Default: " .. prettyModelLabel(st.runnerModels[1])),
            icon = "car",
            arrow = true,
            menu = "spz_pursuit_runner_car",
        },
        {
            title = "Chaser Car",
            description = (st.carPref and st.carPref.chaser and prettyModelLabel(st.carPref.chaser)) or ("Default: " .. prettyModelLabel(st.chaserModels[1])),
            icon = "car-side",
            arrow = true,
            menu = "spz_pursuit_chaser_car",
        },
        {
            title = "Invite Player",
            description = #online .. " online",
            icon = "user-plus",
            arrow = true,
            menu = "spz_pursuit_invite",
        },
        {
            title = ("── Queue %d/%d%s ──"):format(st.count, st.max, st.armed and (" · starts in " .. (st.armedRemain or 0) .. "s") or ""),
            disabled = true,
        },
    }

    if #st.roster == 0 then
        mainOptions[#mainOptions + 1] = { title = "Queue is empty", disabled = true }
    else
        for _, r in ipairs(st.roster) do
            mainOptions[#mainOptions + 1] = { title = (r.isMe and "★ " or "") .. r.name, disabled = true }
        end
    end

    lib.registerContext({ id = "spz_pursuit_lobby", title = "🚓 Hot Pursuit", options = mainOptions })
    lib.showContext("spz_pursuit_lobby")
end

RegisterCommand("pursuitmenu", function() openLobbyMenu() end, false)
RegisterKeyMapping("pursuitmenu", "Hot Pursuit queue menu", "keyboard", "")

RegisterNetEvent("spz-pursuit:invited", function(d)
    local resp = lib.alertDialog({
        header = "Hot Pursuit Invite",
        content = ("**%s** invited you to join Hot Pursuit."):format(d.fromName or "Someone"),
        centered = true,
        cancel = true,
        labels = { cancel = "Dismiss", confirm = "Join" },
    })
    if resp == "confirm" then
        TriggerServerEvent("spz-pursuit:acceptInvite")
    end
end)

local function fmt(s) return ("%d:%02d"):format(math.floor(s / 60), s % 60) end

local function clearBlips()
    for _, b in pairs(blips) do if DoesBlipExist(b) then RemoveBlip(b) end end
    blips = {}
end

local function spawnCar(model, cop)
    local ped = PlayerPedId()
    local hash = GetHashKey(model)
    RequestModel(hash)
    local dl = GetGameTimer() + 5000
    while not HasModelLoaded(hash) and GetGameTimer() < dl do Wait(20) end
    if not HasModelLoaded(hash) then return end
    local c = GetEntityCoords(ped)
    local v = CreateVehicle(hash, c.x, c.y, c.z, GetEntityHeading(ped), true, false)
    SetModelAsNoLongerNeeded(hash)
    SetPedIntoVehicle(ped, v, -1)
    SetVehicleOnGroundProperly(v)
    if cop then SetVehicleLivery(v, 0) end
    myVeh = v
end

local function cleanup()
    active = false; role = nil; runnerSrc = nil; roster = {}
    clearBlips()
    if myVeh ~= 0 and DoesEntityExist(myVeh) then DeleteEntity(myVeh) end
    myVeh = 0
    local ped = PlayerPedId()
    FreezeEntityPosition(ped, false); SetEntityInvincible(ped, false)
    if myBack then SetEntityCoords(ped, myBack.x, myBack.y, myBack.z, false, false, false, false); myBack = nil end
end

RegisterNetEvent("spz-pursuit:start", function(d)
    active = true; role = d.role; phase = "head"; runnerSrc = d.runner; roster = d.roles or {}

    local ped = PlayerPedId()
    myBack = GetEntityCoords(ped)

    local ang = math.random() * math.pi * 2
    local dist = math.random() * (d.spread or 60.0)
    -- Runner spawns at the centre; chasers ring the edge so there's real distance.
    if role == "runner" then
        SetEntityCoords(ped, d.arena.x, d.arena.y, d.arena.z + 1.0, false, false, false, false)
    else
        SetEntityCoords(ped, d.arena.x + math.cos(ang) * (d.spread or 60), d.arena.y + math.sin(ang) * (d.spread or 60), d.arena.z + 1.0, false, false, false, false)
    end
    SetEntityInvincible(ped, true)

    if role == "runner" then
        spawnCar(d.runnerModel or "sultan", false)
        lib.notify({ title = "RUNNER", description = "Escape! Survive the timer, don't let the meter fill.", type = "success", duration = 6000 })
    else
        spawnCar(d.chaserModel or "police", true)
        FreezeEntityPosition(PlayerPedId(), true)   -- frozen during runner's head start
        lib.notify({ title = "CHASER", description = "Runner's getting a head start… then hunt them down.", type = "warning", duration = 6000 })
    end

    DoScreenFadeIn(400)
end)

RegisterNetEvent("spz-pursuit:release", function()
    phase = "chase"
    if role == "chaser" then
        FreezeEntityPosition(PlayerPedId(), false)
        lib.notify({ title = "GO", description = "Bust the runner!", type = "info" })
    end
end)

RegisterNetEvent("spz-pursuit:state", function(s) phase = s.phase or phase; state = s end)

RegisterNetEvent("spz-pursuit:over", function(r)
    local msg = (r.winner == "runner") and "Runner escaped!" or "Runner busted!"
    if r.won then msg = msg .. (" +%d credits"):format(r.payout or 0) end
    DoScreenFadeOut(400); Wait(400); cleanup()
    lib.notify({ title = "HOT PURSUIT", description = msg, type = r.won and "success" or "info", duration = 8000 })
    DoScreenFadeIn(600)
end)

-- ── HUD (timer + bust meter) ─────────────────────────────────────────────────
CreateThread(function()
    while true do
        if active then
            local label = (phase == "head")
                and (role == "runner" and "RUN — HEAD START" or "HOLD")
                or  (role == "runner" and "ESCAPE" or "CHASE")
            local timer = (phase == "head") and fmt(state.headRemain or 0) or fmt(state.remain or 0)

            SetTextFont(4); SetTextScale(0.0, 0.5); SetTextCentre(true)
            SetTextColour(255, 255, 255, 220); SetTextOutline()
            BeginTextCommandDisplayText("STRING")
            AddTextComponentSubstringPlayerName(("HOT PURSUIT  ·  %s  ·  %s"):format(label, timer))
            EndTextCommandDisplayText(0.5, 0.03)

            -- bust meter bar
            if phase == "chase" then
                local m = (state.meter or 0) / 100
                DrawRect(0.5, 0.075, 0.20, 0.022, 10, 11, 14, 200)
                DrawRect(0.4 + 0.10 * m, 0.075, 0.20 * m, 0.014, 255, 60, 60, 230)
                SetTextFont(4); SetTextScale(0.0, 0.32); SetTextCentre(true)
                SetTextColour(255, 255, 255, 200); SetTextOutline()
                BeginTextCommandDisplayText("STRING")
                AddTextComponentSubstringPlayerName(("BUST %d%%"):format(state.meter or 0))
                EndTextCommandDisplayText(0.5, 0.088)
            end
            Wait(0)
        else
            Wait(500)
        end
    end
end)

-- ── Blips (chasers ↔ runner) ─────────────────────────────────────────────────
CreateThread(function()
    while true do
        if active then
            if role == "chaser" and runnerSrc then
                local lp = GetPlayerFromServerId(runnerSrc)
                local ped = (lp ~= -1) and GetPlayerPed(lp) or 0
                if ped ~= 0 and not (blips[runnerSrc] and DoesBlipExist(blips[runnerSrc])) then
                    local b = AddBlipForEntity(ped); SetBlipSprite(b, 1); SetBlipColour(b, 1); SetBlipScale(b, 0.9)
                    BeginTextCommandSetBlipName("STRING"); AddTextComponentSubstringPlayerName("Runner"); EndTextCommandSetBlipName(b)
                    blips[runnerSrc] = b
                end
            elseif role == "runner" then
                for _, e in ipairs(roster) do
                    if e.role == "chaser" then
                        local lp = GetPlayerFromServerId(e.src)
                        local ped = (lp ~= -1) and GetPlayerPed(lp) or 0
                        if ped ~= 0 and not (blips[e.src] and DoesBlipExist(blips[e.src])) then
                            local b = AddBlipForEntity(ped); SetBlipSprite(b, 1); SetBlipColour(b, 3); SetBlipScale(b, 0.85)
                            BeginTextCommandSetBlipName("STRING"); AddTextComponentSubstringPlayerName("Chaser"); EndTextCommandSetBlipName(b)
                            blips[e.src] = b
                        end
                    end
                end
            end
            Wait(1000)
        else
            if next(blips) then clearBlips() end
            Wait(600)
        end
    end
end)

AddEventHandler("onResourceStop", function(res)
    if res == GetCurrentResourceName() and active then cleanup() end
end)
