fx_version 'cerulean'
game 'gta5'

name 'spz-pursuit'
description 'SPiceZ Minigame — Hot Pursuit. 1 runner vs up to 6 chasers; proximity bust meter; survive to escape or get busted. Credit wager, pot to the winning side.'
version '1.0.0'
author 'SPiceZ-Core'
lua54 'yes'

shared_scripts {
  '@ox_lib/init.lua',
  'config.lua',
}

client_scripts {
  'client/main.lua',
}

server_scripts {
  '@oxmysql/lib/MySQL.lua',
  'server/main.lua',
}

dependencies {
  'ox_lib',
  'oxmysql',
  'spz-core',
  'spz-identity',
  'spz-progression',
}
