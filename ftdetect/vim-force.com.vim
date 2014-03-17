" File: apexcode.vim
" Author: Andrey Gavrikov 
" Version: 1.2
" Last Modified: 2014-03-10
" Copyright: Copyright (C) 2010-2012 Andrey Gavrikov
"            Permission is hereby granted to use and distribute this code,
"            with or without modifications, provided that this copyright
"            notice is copied with it. Like anything else that's free,
"            this plugin is provided *as is* and comes with no warranty of any
"            kind, either expressed or implied. In no event will the copyright
"            holder be liable for any damages resulting from the use of this
"            software.
" filetype.vim - detect SFDC Filetypes
" Part of vim/force.com plugin
"

"force.com related file types
au! BufRead,BufNewFile *.cls,*.trigger,*.resource set filetype=apexcode
" set two file types for apex page: html (for syntax) and apexcode (for compilation and tags)
" use <C-0> for Javascript and <C-U> for html complete
au! BufRead,BufNewFile *.page,*.component,*.scf	set filetype=visualforce | setlocal omnifunc=htmlcomplete#CompleteTags | setlocal completefunc=visualforcecomplete#Complete
" scratch buffer needs 'apexcode' highlighting
au! BufRead,BufNewFile vim-force.com-scratch.txt set filetype=apexcode

" resources with name like *JS.resource are treated as plain javascript files, (i.e. non zip files)
au! BufRead,BufNewFile *JS.resource set filetype=apexcode.javascript | set syntax=javascript | setlocal omnifunc=javascriptcomplete#CompleteJS

" unpacked resources are stored in projet_root/resources_unpacked/... folder
au! BufRead,BufNewFile */resources_unpacked/*.js set filetype=apexcode.javascript | set syntax=javascript | setlocal omnifunc=javascriptcomplete#CompleteJS
au! BufRead,BufNewFile */resources_unpacked/*.html set filetype=apexcode.html | set syntax=html | setlocal omnifunc=htmlcomplete#CompleteTags

" see also end of apexResource, where handling of .resource and its unpacked content is defined

