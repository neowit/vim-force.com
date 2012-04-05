" File: apexcode.vim
" Author: Andrey Gavrikov 
" Version: 1.0
" Last Modified: 2012-03-05
" Copyright: Copyright (C) 2010-2012 Andrey Gavrikov
"            Permission is hereby granted to use and distribute this code,
"            with or without modifications, provided that this copyright
"            notice is copied with it. Like anything else that's free,
"            this plugin is provided *as is* and comes with no warranty of any
"            kind, either expressed or implied. In no event will the copyright
"            holder be liable for any damamges resulting from the use of this
"            software.
" filetype.vim - detect SFDC Filetypes
" Part of vim/force.com plugin
"

"force.com related file types
au! BufRead,BufNewFile *.cls,*.trigger set filetype=apexcode.java
" set two file types for apex page: html (for syntax) and apexcode (for compilation and tags)
" use <C-0> for Javascript and <C-U> for html complete
au! BufRead,BufNewFile *.page,*.component,*.scf	set filetype=apexcode.html | set syntax=html | setlocal omnifunc=htmlcomplete#CompleteTags | setlocal completefunc=visualforcecomplete#Complete
au! BufRead,BufNewFile *JS.resource set filetype=apexcode.javascript | set syntax=javascript | setlocal omnifunc=javascriptcomplete#CompleteJS


