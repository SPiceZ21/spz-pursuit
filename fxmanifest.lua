fx_version 'cerulean'
game 'gta5'

name 'spz-pursuit'
description 'SPiceZ Minigame — Hot Pursuit. Host a room, pick roles (1 robber, 1-10 cops, optional PD chopper), cars and tuner setups; robber breaks out of Pacific Standard, police set up then chase; stop the robber and hold to bust.'
version '1.0.0'
author 'SPiceZ-Core'
lua54 'yes'

shared_scripts {
  '@ox_lib/init.lua',
  'config.lua',
}

client_scripts {
  'client/util.lua',
  'client/customize.lua',
  'client/lobby.lua',
  'client/match.lua',
}

server_scripts {
  'server/rooms.lua',
  'server/match.lua',
}

dependencies {
  'ox_lib',
  'spz-core',
  'spz-identity',
  'spz-tunners',
}
