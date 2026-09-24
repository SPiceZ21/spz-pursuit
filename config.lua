-- config.lua — Hot Pursuit
Config = {}

Config.Command = "pursuit"          -- /pursuit opens the room menu (also radial → Pursuit)

-- ── Roles ───────────────────────────────────────────────────────────────────
-- Picked by the players in the room (soft launch). The host can reassign.
Config.MaxCops   = 10
Config.MinCops   = 1
Config.MaxPilots = 1                -- PD chopper, optional
Config.MaxRoomSize = 1 + Config.MaxCops + Config.MaxPilots

-- ── Cars ────────────────────────────────────────────────────────────────────
-- First entry is the default when a player never picks.
Config.Cars = {
    robber = { "sultan", "sultanrs", "kuruma", "buffalo", "elegy2", "jester", "comet2", "ruston" },
    cop    = { "police", "police2", "police3", "police4", "sheriff", "sheriff2", "fbi" },
    pilot  = { "polmav" },
}

-- ── Pacific Standard ────────────────────────────────────────────────────────
Config.Robber = {
    spawn = vec4(235.70, 217.21, 106.29, 116.38),   -- inside the bank, on foot
    car   = vec4(227.27, 210.85, 104.94, 137.87),   -- getaway car, parked outside
}

-- Cops spawn in their cars on these points (round-robin; a 6th+ cop takes the
-- same point shifted sideways). They can drive off and set up before the go.
Config.CopSpawns = {
    vec4(184.37, 216.28, 105.02, 250.12),
    vec4(207.67, 171.60, 104.91, 14.02),
    vec4(239.03, 195.79, 104.53, 69.11),
    vec4(255.10, 162.34, 104.07, 49.40),
    vec4(173.33, 191.33, 105.11, 250.61),
}
Config.PilotSpawn = vec4(189.21, 228.56, 143.56, 210.19)

-- ── Phases ──────────────────────────────────────────────────────────────────
-- SETUP: robber held inside the bank, police position themselves and press
-- ready. Starts the chase when every cop/pilot is ready, or when this runs out.
Config.SetupMaxSec = 120
-- CHASE: the robber wins by not being busted before this runs out.
Config.ChaseSec    = 300

Config.Traffic     = true           -- ambient traffic in the match bucket (cover)

-- ── Busting ─────────────────────────────────────────────────────────────────
-- A cop within BustDistance of a robber who is going BustMaxSpeedKmh or slower
-- holds the bust key; the bar fills over BustHoldSec. If the robber gets going
-- again, or every holding cop drops off, the bar drains.
Config.BustMaxSpeedKmh = 5.0
Config.BustDistance    = 10.0
Config.BustHoldSec     = 10.0
Config.BustDrainPerSec = 1.0        -- full bars per second when nobody is busting

-- ── Keys (polled while in a match) ──────────────────────────────────────────
Config.Keys = {
    bust  = { control = 38,  label = "E" },    -- hold to bust
    ready = { control = 246, label = "Y" },    -- police: ready during setup
}

-- ── Deaths ──────────────────────────────────────────────────────────────────
Config.CopRespawnSec = 5            -- dead cop comes back at their spawn, new car
-- A robber who dies is busted.

-- ── Reward ──────────────────────────────────────────────────────────────────
Config.WinReward = 600              -- credits to each winner (0 = none)
