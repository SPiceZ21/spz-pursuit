-- client/lobby.lua — room menus (ox_lib context)
--
-- No room:  Create room · pending invites
-- In room:  role · car · customise · ready · invite · start (host) · members
--           Host can set anyone's role or remove them from a member's row.
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

local function roleOptions(target, current)
    local c, l = Room.counts, Room.limits
    local function opt(role, label, used, max)
        local full = used >= max and current ~= role
        return {
            title = label, icon = ROLE_ICON[role],
            description = ("%d / %d%s"):format(used, max, current == role and " · current" or ""),
            disabled = full,
            onSelect = function() call("setRole", role, target); openLobby() end,
        }
    end
    return {
        opt("robber", "Robber", c.robber, 1),
        opt("cop", "Cop", c.cop, l.cops),
        opt("pilot", "PD Chopper (optional)", c.pilot, l.pilots),
        { title = "No role", icon = "xmark", onSelect = function() call("setRole", "none", target); openLobby() end },
    }
end

local function openRoleMenu(target, current, name)
    lib.registerContext({
        id = "spz_pursuit_role", title = name and ("Role · " .. name) or "Pick your role",
        menu = ROOM_MENU, options = roleOptions(target, current),
    })
    lib.showContext("spz_pursuit_role")
end

local function openCarMenu()
    local me = Room.me
    local role = me.role
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
            { title = "Set role", description = Pursuit.RoleLabel(m.role), icon = "user-tag", arrow = true,
                onSelect = function() openRoleMenu(m.src, m.role, m.name) end },
            { title = "Remove from room", icon = "user-xmark", iconColor = "#e05252",
                onSelect = function() call("kick", m.src); openLobby() end },
        },
    })
    lib.showContext("spz_pursuit_member")
end

-- ── Main ─────────────────────────────────────────────────────────────────────

local function noRoomMenu(invites)
    local options = {
        { title = "Create room", description = "Host a pursuit and invite players", icon = "plus", iconColor = "#ff6200",
            onSelect = function() if call("create") then openLobby() end end },
    }
    for _, inv in ipairs(invites or {}) do
        options[#options + 1] = {
            title = ("Join %s's room"):format(inv.host), description = ("%d player(s) in the room"):format(inv.size),
            icon = "envelope-open-text",
            onSelect = function() if call("join", inv.id) then openLobby() end end,
        }
    end
    options[#options + 1] = { title = "How it works", icon = "circle-info", readOnly = true,
        description = "1 robber vs 1–10 cops (+ optional PD chopper). Robber starts in Pacific Standard; police set up, then chase. Stop the robber and hold E to bust." }
    lib.registerContext({ id = ROOM_MENU, title = "🚓 Hot Pursuit", options = options })
    lib.showContext(ROOM_MENU)
end

local function roomMenu()
    local me, c = Room.me, Room.counts
    local role = me.role
    local options = {}

    if Room.state == "match" then
        options[#options + 1] = { title = "Match in progress", icon = "flag-checkered", readOnly = true }
    else
        options[#options + 1] = {
            title = "Role: " .. Pursuit.RoleLabel(role), icon = ROLE_ICON[role] or "user-tag", arrow = true,
            description = ("Robber %d/1 · Cops %d/%d · Chopper %d/%d"):format(c.robber, c.cop, Room.limits.cops, c.pilot, Room.limits.pilots),
            onSelect = function() openRoleMenu(nil, role) end,
        }
        options[#options + 1] = {
            title = "Car: " .. (role and Pursuit.CarLabel(me.cars[role]) or "—"), icon = "car", arrow = true,
            disabled = not role,
            onSelect = openCarMenu,
        }
        options[#options + 1] = {
            title = "Customize car", icon = "wrench",
            description = role and (me.tuned[me.cars[role]] and "Tuned · open the tuner again" or "Open the tuner on your car") or "Pick a role first",
            disabled = not role,
            onSelect = function()
                local model = me.cars[role]
                Pursuit.Customize(model, openLobby)
            end,
        }
        options[#options + 1] = {
            title = me.ready and "Ready ✔" or "Ready up", icon = me.ready and "circle-check" or "circle",
            iconColor = me.ready and "#3dbf7a" or nil,
            description = me.ready and "Tap to un-ready" or "Tap when you're set",
            disabled = not role,
            onSelect = function() call("ready"); openLobby() end,
        }
        if Room.isHost then
            options[#options + 1] = { title = "Invite players", icon = "user-plus", arrow = true,
                description = ("%d / %d in room"):format(c.total, Room.limits.size), onSelect = openInviteMenu }

            local blocker
            if c.robber ~= 1 then blocker = "Need exactly 1 robber"
            elseif c.cop < Room.limits.minCops then blocker = "Need at least 1 cop"
            else
                for _, m in ipairs(Room.members) do
                    if not m.role then blocker = m.name .. " has no role"; break end
                    if not m.ready then blocker = m.name .. " isn't ready"; break end
                end
            end
            options[#options + 1] = {
                title = "Start match", icon = "play", iconColor = not blocker and "#ff6200" or nil,
                description = blocker or "Everyone's ready — go",
                disabled = blocker ~= nil,
                onSelect = function() call("start") end,
            }
        end
    end

    options[#options + 1] = { title = ("── Players %d/%d ──"):format(c.total, Room.limits.size), readOnly = true }
    for _, m in ipairs(Room.members) do
        local line = ("%s%s"):format(Pursuit.RoleLabel(m.role), m.car and (" · " .. Pursuit.CarLabel(m.car)) or "")
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
        options[#options + 1] = { title = "Leave room", icon = "right-from-bracket", iconColor = "#e05252",
            onSelect = function() if call("leave") then Room = nil end end }
    end

    lib.registerContext({ id = ROOM_MENU, title = ("🚓 Hot Pursuit · Room %d"):format(Room.id), options = options })
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
