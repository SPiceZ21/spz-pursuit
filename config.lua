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
    -- Gabz addon sports + super cars (gabz/gb_vehicles_*).
    robber = {
        "gbcomets2r", "gbsentinelgts", "gbargento2f", "gbcyphergts", "gbmilano", "gbmochi",
        "gbnexusrr", "gbretinueloz", "gbromulus", "gbronin", "gbrumina", "gbschlagensp",
        "gbschwartzers", "gbsolace", "gbtenfr", "gbvivantgrb",
        "gb811s2", "gbbanshees", "gbcheetahs", "gbemerussb1", "gbprospero", "gbtempestafs",
        "gbtr3s", "gbzeitgeist",
    },
    -- Gabz police fleet (gabz/gb_vehicles_pd_ems).
    cop = {
        "gbpolcomets2r", "gbpolbanshees", "gbpolsultanrsx", "gbpolargento7f", "gbpolcometcl",
        "gbpolsentinelgts", "gbpoltr3s", "gbpolturismogt", "gbpoltahomagt", "gbpolprospero",
        "gbpolclubxr", "gbpoldomgsx", "gbpolechelon", "gbpoleon", "gbpolesperta", "gbpolgresley",
        "gbpolhedra", "gbpolimpaler", "gbpoladmiral", "gbpolstanier", "gbpolstarlight",
        "gbpolsolace", "gbpolscoutgsx", "gbpolbisonhf", "gbpolbisonstx", "gbpolmojave",
        "gbpolterrorizer", "gbpolsteedvan",
    },
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

-- ── Head start ──────────────────────────────────────────────────────────────
-- When every cop has pressed ready, the robber is put straight into the
-- getaway car. For HeadStartSec after GO, police can't come within
-- HeadStartRadius of the robber (they're pushed back out) and can't bust.
Config.HeadStartSec    = 15
Config.HeadStartRadius = 60.0

-- ── Busting ─────────────────────────────────────────────────────────────────
-- AUTOMATIC, no key: while any cop is within BustDistance of a robber going
-- BustMaxSpeedKmh or slower, the bar fills (full in BustHoldSec). Otherwise it
-- drains at BustDrainPerSec, so a robber who gets moving again claws it back
-- gradually instead of it resetting instantly.
Config.BustMaxSpeedKmh = 10.0
Config.BustDistance    = 12.0
Config.BustHoldSec     = 6.0        -- seconds of a stopped robber to fill the bar
Config.BustDrainPerSec = 0.12       -- ~8 s to drain a full bar

-- ── Keys (polled while in a match) ──────────────────────────────────────────
Config.Keys = {
    ready = { control = 246, label = "Y" },    -- police: ready during setup
}

-- ── Vehicle damage ──────────────────────────────────────────────────────────
-- Cars take real damage in a match (spz-vehfunc godmode stands down). When the
-- robber's car is wrecked -- engine or body at/below this -- they are busted.
Config.VehicleDamage     = true
Config.WreckEngineHealth = 0.0      -- GTA engine health: 1000 new, <=0 dead
Config.WreckBodyHealth   = 0.0

-- ── Deaths ──────────────────────────────────────────────────────────────────
Config.CopRespawnSec = 5            -- dead cop comes back at their spawn, new car
-- A robber who dies is busted.

-- ── Reward ──────────────────────────────────────────────────────────────────
Config.WinReward = 600              -- credits to each winner (0 = none)
