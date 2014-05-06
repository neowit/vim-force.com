" File: globalCommands.vim
" Author: Alejandro De Gregorio
" Version: 1.0
" Last Modified: 2014-05-05
" Copyright: Copyright (C) 2014 Alejandro De Gregorio
"            Permission is hereby granted to use and distribute this code,
"            with or without modifications, provided that this copyright
"            notice is copied with it. Like anything else that's free,
"            this plugin is provided *as is* and comes with no warranty of any
"            kind, either expressed or implied. In no event will the copyright
"            holder be liable for any damages resulting from the use of this
"            software.
"
" Add global commands not restricted to Force.com files
" Part of vim/force.com plugin
"

command! ApexInitProject :call ApexInitProject()

function! ApexInitProject()
    setfiletype apexcode
    call apexProject#init()
endfunction

