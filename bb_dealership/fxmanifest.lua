fx_version 'cerulean'
lua54 'yes'
game 'gta5'

author 'Custom Dealership Generator'
description 'Standalone dealership script: browse + test drive for everyone, purchase only via dealer job with commissions.'
version '0.1.0'

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua'
}

client_scripts {
    'client/main.lua'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/main.lua'
}

dependency 'ox_lib'
