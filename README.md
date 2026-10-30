# spz-pursuit

> Hot Pursuit: one robber, up to 10 cops and a PD chopper.

![version](https://img.shields.io/badge/version-1.11.0-ff6200) ![SPiceZ-Core](https://img.shields.io/badge/SPiceZ--Core-beta-18181b)

## Overview

A host opens a room and players pick roles, cars and tuner setups. The robber breaks out of Pacific Standard, police set up, then chase; stop the robber and hold `E` to bust. The robber wins by surviving the timer.

## Features

- Rooms with roles: robber, 1–10 cops, PD chopper
- Per-role car and tuner setup
- Server-side bust meter
- Robber car in a random chameleon paint

## Requirements

| Resource | Type |
|---|---|
| `ox_lib` | third-party |
| `spz-minigames` | SPiceZ module |
| `spz-core` | SPiceZ module |
| `spz-identity` | SPiceZ module |
| `spz-tunners` | SPiceZ module |

## Installation

Included in the [txAdmin recipe](https://github.com/SPiceZ21/spz-txrecipe). Manual install:

1. Download `spz-pursuit` from GitHub (latest release, or the repository) into your `resources` folder.
2. Add to `server.cfg`, after its requirements:

```cfg
ensure spz-pursuit
```

## Configuration

- `config.lua`

See the file for every option.

## Commands

| Command | Who | Description |
|---|---|---|
| `/pursuit` | player | Open the Hot Pursuit room menu |

## Key binds

Rebindable in **Settings → Key Bindings → FiveM**.

| Action | Default |
|---|---|
| Hot Pursuit room menu | _unbound_ |

---

Part of **SPiceZ-Core** — [documentation](https://github.com/SPiceZ21/Docs) · [all modules](https://github.com/SPiceZ21/Docs/blob/main/modules/README.md)
