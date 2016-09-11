" This file is part of vim-force.com plugin
"   https://github.com/neowit/vim-force.com
" File: apexcode.vim
" This file is part of vim-force.com plugin
" https://github.com/neowit/vim-force.com
" Author: Andrey Gavrikov
" Last Modified: 2012-03-05
" Vim syntax file

" Language:	ApexCode
" http://vim.wikia.com/wiki/Creating_your_own_syntax_files
" http://learnvimscriptthehardway.stevelosh.com/chapters/46.html
"
"""""""""""""""""""""""""""""""""""""""""
if !exists("main_syntax")
  if version < 600
    syntax clear
  elseif exists("b:current_syntax")
    finish
  endif
  let main_syntax = 'apex_messages'
endif

syn match ApexMessagesINFO '^INFO: .*$'
syn match ApexMessagesERROR '^ERROR:.*$'
syn match ApexMessagesERROR '^\s*\[ERROR\].*$'
syn match ApexMessagesWARN '^WARN: .*$'
syn match ApexMessagesDEBUG '^DEBUG:.*$'

":h group-name
highlight link ApexMessagesINFO Identifier
highlight link ApexMessagesERROR Error
highlight link ApexMessagesWARN Debug
highlight link ApexMessagesDEBUG Comment


let b:current_syntax = "apex_messages"
if main_syntax == 'apex_messages'
  unlet main_syntax
endif

" vim: ts=4

