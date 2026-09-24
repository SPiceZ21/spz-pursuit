# spz-pursuit

> Hot Pursuit — robber vs police, from Pacific Standard · `v1.0.0`

## How a match goes

1. **Room.** A host opens `/pursuit` (or radial → Pursuit), creates a room, and invites players.
2. **Soft launch.** In the room, everyone:
   - picks a role: 1 **Robber**, 1–10 **Cops**, and optionally 1 **PD Chopper**. The host
     can set anyone's role or remove them;
   - picks a car for that role;
   - opens **Customize car**, which is the full spz-tunners menu on a preview of that car,
     in a private bucket. The setup is saved to the room and applied when the car spawns;
   - presses **Ready**.

   The host presses **Start match** once there's exactly 1 robber, at least 1 cop, and
   everyone is ready.
3. **Setup.** Everyone moves to a private bucket at Pacific Standard:
   - The robber is held inside the bank, with the getaway car parked outside. The car is
     locked to everyone else.
   - Cops spawn in their cars on 5 fixed points (a 6th+ cop gets the same point one
     car-width over). The chopper spawns on the pad.
   - Police drive off, set up, and press **Y**.
   - The chase starts when every cop and the pilot is ready, or after `SetupMaxSec`.
4. **Chase.** The robber is released: "GO!". Run to the car and lose them. Police see the
   robber's blip; the robber sees theirs.
5. **Bust.**
   - A robber at walking pace (≤ `BustMaxSpeedKmh`, default 5 km/h) can be busted.
   - The robber's HUD shows their speed, and warns in red when they're slow enough.
   - A cop within `BustDistance` sees **HOLD E TO BUST**. Holding fills the bar over
     `BustHoldSec`, and it drains if the robber gets moving.
   - The bar is computed by the server from real positions and speeds.
6. **Result.**
   - Police win if the robber is busted, dies, or leaves.
   - The robber wins by surviving `ChaseSec`, or if all police leave.
   - Winners get `WinReward` credits. Everyone is put back where they were, and the room
     returns to the lobby for another round.

Cops who die respawn at their spawn point with a new car after `CopRespawnSec`.

## Contact

Players are normally phased (spz-core). Everyone in a match carries the `spz:contact`
statebag, and spz-core's phasing leaves pairs where **both** players have it to collide.
So cops can PIT and box the robber in, while the rest of the server stays ghosted.

## Structure

| Side | File | Purpose |
|---|---|---|
| Shared | `config.lua` | Spawns, role limits, cars, timers, bust rules, keys, reward |
| Server | `server/rooms.lua` | Rooms, invites, roles, cars, tuner presets, ready, start, preview bucket |
| Server | `server/match.lua` | Bucket, spawns, setup → chase → over, server-side bust bar, result |
| Client | `client/lobby.lua` | Room menus (ox_lib context), invite prompt |
| Client | `client/customize.lua` | Tuner preview in a private bucket |
| Client | `client/match.lua` | Spawning, HUD, ready / bust input, blips, deaths, return |
| Client | `client/util.lua` | Car spawn with tuner preset, labels |

## Commands

| Command | Effect |
|---|---|
| `/pursuit`, `pursuitmenu` | Room menu (radial → Pursuit) |

In a match: **Y** police ready during setup · **E** hold to bust.

## Dependencies

`ox_lib` · `spz-core` · `spz-identity` · `spz-tunners` · optional `spz-progression` (rewards), `spz-log`
