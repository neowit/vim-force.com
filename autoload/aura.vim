" This file is part of vim-force.com plugin
"   https://github.com/neowit/vim-force.com
" File: autoload/aura.vim
" Author: Andrey Gavrikov 
" Maintainers: 
"
" utility functions for working with aura files inside single bundle

" make sure the rest of the file is not loaded unnecessarily
if exists("g:loaded_aura_autoload_customisations")
    finish
endif


" Aura bundle file switcher
" Allows to switch between controller/helper/css/component files within aura
" bundle
let s:aura_files = ['controller.js', 'helper.js', '.cmp', '.css']
function! aura#alternateFile(switchToType)
    let currentFileName = tolower(expand("%:t"))
    let targetFileName = ''

    let targetSuffix = ''
    if 'controller' == a:switchToType
        let targetSuffix = 'Controller.js'
    elseif 'helper' == a:switchToType
        let targetSuffix = 'Helper.js'
    elseif 'component' == a:switchToType
        let targetSuffix = '.cmp'
    elseif 'css' == a:switchToType
        let targetSuffix = '.css'
    endif    
    
    for ext in s:aura_files
        if match(currentFileName, ext.'$') > 0
            let targetFileName = strpart(currentFileName, 0, match(currentFileName, ext."$")) . targetSuffix
            break
        endif   
    endfor  
    "echomsg "targetFileName=".targetFileName
    if '' != targetFileName && targetFileName != currentFileName
        let l:bufNr = bufnr(targetFileName)
        if l:bufNr >= 0
            execute "b ". l:bufNr
        else    
            execute 'edit ' . targetFileName
        endif
    endif    
endfunction    

let g:loaded_aura_autoload_customisations = 1
