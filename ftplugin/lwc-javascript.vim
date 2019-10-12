" Vim filetype plugin file
" Language: javascript
" Maintainer:	Andrey Gavrikov
" setup environment for Apex Code development
"

"load all force.com/apex-plugin scripts after vim starts and when one of
"supported apex filetypes is detected
runtime! ftplugin/apexcode.vim

" when using gf motion - vim changes path "./modulename" to "/modulename"
" so we have to change it back to "./modulename"
function! LwcModulePath(fName)
    let res = substitute(a:fName, "^/", "./" ,'' )
    return res
endfunction

set includeexpr=LwcModulePath(v:fname)
