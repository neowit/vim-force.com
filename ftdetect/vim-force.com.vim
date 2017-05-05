" This file is part of vim-force.com plugin
"   https://github.com/neowit/vim-force.com
" File:  vim-force.com.vim
" Author: Andrey Gavrikov 
" Last Modified: 2015-01-04
"
" filetype.vim - detect SFDC Filetypes
"

"force.com related file types
au BufRead,BufNewFile *.cls,*.trigger,*.resource set filetype=apexcode
" set two file types for apex page: html (for syntax) and apexcode (for compilation and tags)
au BufRead,BufNewFile *.page,*.component,*.scf	set filetype=visualforce | setlocal omnifunc=htmlcomplete#CompleteTags | setlocal completefunc=visualforcecomplete#Complete
" scratch buffer needs 'apexcode' highlighting
au BufRead,BufNewFile vim-force.com-scratch.txt set filetype=apexcode

" resources with name like *JS.resource are treated as plain javascript files, (i.e. non zip files)
au BufRead,BufNewFile *JS.resource set filetype=apexcode.javascript | set syntax=javascript

" basic detection for non code files (detecting these allows loading the
" plugin when one of such files is opened)
augroup apexXml 
	au!
    au BufRead,BufNewFile */src/objects/*.object set filetype=apexcode.xml | set syntax=xml
    au BufRead,BufNewFile */src/profiles/*.profile set filetype=apexcode.xml | set syntax=xml
    au BufRead,BufNewFile */src/layouts/*.layout set filetype=apexcode.xml | set syntax=xml
    au BufRead,BufNewFile */src/workflows/*.workflow set filetype=apexcode.xml | set syntax=xml
    au BufRead,BufNewFile */src/package.xml set filetype=apexcode.xml | set syntax=xml
    au BufRead,BufNewFile */src/customMetadata/*.md set filetype=apexcode.xml | set syntax=xml
augroup END

" unpacked resources are stored in projet_root/resources_unpacked/... folder
" see also end of apexResource.vim, where handling of .resource and its unpacked content is defined
au BufRead,BufNewFile */resources_unpacked/*.js set filetype=apexcode.javascript | set syntax=javascript
au BufRead,BufNewFile */resources_unpacked/*.html set filetype=apexcode.html | set syntax=html | setlocal omnifunc=htmlcomplete#CompleteTags

" aura files
augroup aura
	au!
	au BufRead,BufNewFile */src/aura/*.app set filetype=aura-xml | set syntax=aura-xml
	au BufRead,BufNewFile */src/aura/*.cmp set filetype=aura-xml | set syntax=aura-xml
	au BufRead,BufNewFile */src/aura/*.evt set filetype=aura-xml | set syntax=aura-xml
	au BufRead,BufNewFile */src/aura/*.intf set filetype=apexcode.aura.html | set syntax=html
	au BufRead,BufNewFile */src/aura/*.js set filetype=aura-javascript | set syntax=javascript
	au BufRead,BufNewFile */src/aura/*.css set filetype=aura-css | set syntax=css
	au BufRead,BufNewFile */src/aura/*.auradoc set filetype=apexcode.aura.html | set syntax=html
augroup END

" check if we shall let tern_for_vim to become javascript 'omnifunc'
if &runtimepath !~ 'tern_for_vim'
	au BufRead,BufNewFile *JS.resource setlocal omnifunc=javascriptcomplete#CompleteJS
	au BufRead,BufNewFile */resources_unpacked/*.js setlocal omnifunc=javascriptcomplete#CompleteJS
endif

if !exists('&omnifunc') || len(&omnifunc) < 1
	autocmd FileType apexcode setlocal omnifunc=apexComplete#Complete
endif

