-- client/lobby.lua — room menus (ox_lib context)
--
-- No room:  Create room · pending invites
-- In room:  cars (one per role) · ready · invite · members
--           Roles are dealt at random by the server once everyone is ready;
--           the match then starts on its own. Host can remove members.
-- The server pushes the room on every change; an open room menu redraws.

local Room = nil          -- latest room view from the server
local ROOM_MENU = "spz_pursuit_room"

local ROLE_ICON = { robber = "mask", cop = "car-on", pilot = "helicopter" }

local function call(name, ...)
    local ok, msg = lib.callback.await("spz-pursuit:" .. name, false, ...)
    if not ok and msg then Pursuit.Notify(msg, "error") end
    if ok and type(msg) == "string" then Pursuit.Notify(msg, "success") end
    return ok
end

local openLobby

-- ── Submenus ─────────────────────────────────────────────────────────────────

local ROLES = { "robber", "cop", "pilot" }

local function openCarMenu(role)
    local me = Room.me
    local options = {}
    for _, model in ipairs(Room.cars[role] or {}) do
        local picked = me.cars[role] == model
        options[#options + 1] = {
            title = Pursuit.CarLabel(model),
            description = (picked and "Selected" or "Select") .. (me.tuned[model] and " · tuned" or ""),
            icon = picked and "check" or "car",
            onSelect = function() call("setCar", role, model); openLobby() end,
        }
    end
    options[#options + 1] = {
        title = "Customize " .. Pursuit.CarLabel(me.cars[role]), icon = "wrench",
        description = me.tuned[me.cars[role]] and "Tuned · open the tuner again" or "Open the tuner on this car",
        onSelect = function() Pursuit.Customize(me.cars[role], openLobby) end,
    }
    lib.registerContext({ id = "spz_pursuit_car", title = "Car · " .. Pursuit.RoleLabel(role), menu = ROOM_MENU, options = options })
    lib.showContext("spz_pursuit_car")
end

local function openInviteMenu()
    local online = lib.callback.await("spz-pursuit:onlinePlayers", false) or {}
    local options = {}
    for _, p in ipairs(online) do
        options[#options + 1] = {
            title = p.name, icon = "user-plus",
            description = p.busy and ("Busy — " .. p.busy) or "Send invite",
            disabled = p.busy ~= nil,
            onSelect = function() call("invite", p.src); openInviteMenu() end,
        }
    end
    if #options == 0 then options[1] = { title = "No one else is free", disabled = true } end
    lib.registerContext({ id = "spz_pursuit_invite", title = "Invite players", menu = ROOM_MENU, search = #online > 6, options = options })
    lib.showContext("spz_pursuit_invite")
end

local function openMemberMenu(m)
    lib.registerContext({
        id = "spz_pursuit_member", title = m.name, menu = ROOM_MENU,
        options = {
            { title = "Remove from room", icon = "user-xmark", iconColor = "#e05252",
                onSelect = function() call("kick", m.src); openLobby() end },
        },
    })
    lib.showContext("spz_pursuit_member")
end

-- ── Main ─────────────────────────────────────────────────────────────────────

local function noRoomMenu(invites)
    local options = {
        { title = "Join public lobby", description = "Jump into the busiest open lobby (or open one)", icon = "users", iconColor = "#ff6200",
            onSelect = function() if call("quickJoin") then openLobby() end end },
        { title = "Create new lobby", description = "Open a fresh public lobby", icon = "plus",
            onSelect = function() if call("create") then openLobby() end end },
    }
    if #(invites or {}) > 0 then
        options[#options + 1] = { title = "── Open lobbies ──", readOnly = true }
    end
    for _, inv in ipairs(invites or {}) do
        options[#options + 1] = {
            title = ("%s's lobby%s"):format(inv.host, inv.invited and " · invited" or ""),
            description = ("%d/%d players%s"):format(inv.size, inv.max or 0, inv.size > Config.ChopperAbove and " · chopper on" or ""),
            icon = inv.invited and "envelope-open-text" or "door-open",
            onSelect = function() if call("join", inv.id) then openLobby() end end,
        }
    end
    options[#options + 1] = { title = "How it works", icon = "circle-info", readOnly = true,
        description = "Roles are random: 1 robber, the rest cops (6+ players: one flies the PD chopper). Everyone readies up and it starts by itself. Robber starts in Pacific Standard; police set up, then chase. Box the robber in under 10 km/h and the bust bar fills automatically." }
    lib.registerContext({ id = ROOM_MENU, title = "🚓 Hot Pursuit", options = options })
    lib.showContext(ROOM_MENU)
end

local function roomMenu()
    local me, c = Room.me, Room.counts
    local options = {}

    if Room.state == "match" then
        options[#options + 1] = { title = "Match in progress", icon = "flag-checkered", readOnly = true }
    else
        for _, r in ipairs(ROLES) do
            options[#options + 1] = {
                title = ("%s car: %s"):format(Pursuit.RoleLabel(r), Pursuit.CarLabel(me.cars[r])),
                icon = ROLE_ICON[r], arrow = true,
                description = me.tuned[me.cars[r]] and "Tuned" or "Used if you're dealt this role",
                onSelect = function() openCarMenu(r) end,
            }
        end
        options[#options + 1] = {
            title = me.ready and "Ready ✔" or "Ready up", icon = me.ready and "circle-check" or "circle",
            iconColor = me.ready and "#3dbf7a" or nil,
            description = Room.countdown and "Starting — roles are being dealt"
                or (me.ready and "Tap to un-ready" or ("Starts when all %d are ready (min %d)"):format(c.total, 1 + Room.limits.minCops)),
            onSelect = function() call("ready"); openLobby() end,
        }
        -- Public lobby: anyone in it can invite friends.
        options[#options + 1] = { title = "Invite players", icon = "user-plus", arrow = true,
            description = ("%d / %d in lobby"):format(c.total, Room.limits.size), onSelect = openInviteMenu }
    end

    options[#options + 1] = { title = ("── Players %d/%d ──"):format(c.total, Room.limits.size), readOnly = true }
    for _, m in ipairs(Room.members) do
        local line = m.role and Pursuit.RoleLabel(m.role) or "Role dealt at start"
        local opt = {
            title = (m.host and "★ " or "") .. m.name .. (m.me and " (you)" or ""),
            description = line .. (m.ready and " · ready" or ""),
            icon = m.ready and "circle-check" or (ROLE_ICON[m.role] or "user"),
            iconColor = m.ready and "#3dbf7a" or nil,
        }
        if Room.isHost and not m.me and Room.state == "lobby" then
            opt.arrow = true
            opt.onSelect = function() openMemberMenu(m) end
        else
            opt.readOnly = true
        end
        options[#options + 1] = opt
    end

    if Room.state == "lobby" then
        options[#options + 1] = { title = "Leave lobby", icon = "right-from-bracket", iconColor = "#e05252",
            onSelect = function() if call("leave") then Room = nil end end }
    end

    lib.registerContext({ id = ROOM_MENU, title = ("🚓 Hot Pursuit · Public lobby %d"):format(Room.id), options = options })
    lib.showContext(ROOM_MENU)
end

openLobby = function()
    local st = lib.callback.await("spz-pursuit:state", false)
    if not st then return end
    Room = st.room
    if Room and Room.me then roomMenu() else noRoomMenu(st.invites) end
end

function Pursuit.OpenLobby()
    if Pursuit.InMatch and Pursuit.InMatch() then return Pursuit.Notify("You're in a match", "error") end
    openLobby()
end

-- ── Server pushes ────────────────────────────────────────────────────────────

RegisterNetEvent("spz-pursuit:room", function(view)
    Room = view
    -- Redraw the room menu if it's the one on screen (not a submenu).
    if lib.getOpenContextMenu() == ROOM_MENU then
        if Room and Room.me then roomMenu() else lib.hideContext(false) end
    end
end)

RegisterNetEvent("spz-pursuit:invited", function(inv)
    local resp = lib.alertDialog({
        header = "Hot Pursuit invite",
        content = ("**%s** invited you to their pursuit room."):format(inv.host),
        centered = true, cancel = true,
        labels = { cancel = "Later", confirm = "Join" },
    })
    if resp == "confirm" then
        if call("join", inv.room) then openLobby() end
    else
        Pursuit.Notify("You can still join from /" .. Config.Command, "inform")
    end
end)

RegisterCommand(Config.Command, function() Pursuit.OpenLobby() end, false)
RegisterCommand("pursuitmenu", function() Pursuit.OpenLobby() end, false)   -- radial → Pursuit
RegisterKeyMapping("pursuitmenu", "Hot Pursuit room menu", "keyboard", "")
