" This file is part of vim-force.com plugin
"   https://github.com/neowit/vim-force.com
" File: apexInitProject.vim
" Author: Alejandro De Gregorio
" Last Modified: 2014-05-06
"
" Add global commands not restricted to Force.com files
"

command! ApexInitProject :call apexInitProject#init()

function! apexInitProject#init()
    setfiletype apexcode
    call apexProject#init()
endfunction

