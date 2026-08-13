-- config.lua — Hot Pursuit
Config = {}

Config.Command      = "pursuit"
Config.StartCommand = "purstart"

-- ── Reward (FREE to join — no entry fee) ────────────────────────────────────
Config.WinReward = 600     -- flat credits paid to each winner (0 = no reward)

-- ── Lobby ───────────────────────────────────────────────────────────────────
Config.MinPlayers   = 2     -- 1 runner + 1 chaser minimum
Config.MaxPlayers   = 7     -- 1 runner + up to 6 chasers
Config.LobbyWaitSec = 30

-- ── Round ───────────────────────────────────────────────────────────────────
Config.HeadStartSec = 20    -- runner escapes while chasers are frozen
Config.RoundTimeSec = 240   -- runner survives this long to win

-- Bust meter (proximity-based — global no-collision means no ramming).
Config.BustDist       = 18.0   -- a chaser within this range fills the meter
Config.BustFillPerSec = 22     -- meter %/s while any chaser is in range
Config.BustDrainPerSec = 9     -- meter %/s draining when clear
-- meter hits 100 → runner is busted, chasers win.

Config.Arena       = vector3(340.0, -1400.0, 32.5)   -- city/industrial spread
Config.SpawnSpread = 60.0

Config.RunnerModel = "sultan"   -- nimble getaway car
Config.ChaserModel = "police"   -- cop cruiser
