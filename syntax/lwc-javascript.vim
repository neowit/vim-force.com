" This file is part of vim-force.com plugin
"   https://github.com/neowit/vim-force.com
" File: aura.vim
" This file is part of vim-force.com plugin
" https://github.com/neowit/vim-force.com
" Author: Andrey Gavrikov 
" Last Modified: 2019-10-12
" Aura specific tags
"
" Language:	lwc-javascript
"
"
if exists("b:current_syntax")
	unlet b:current_syntax
endif
runtime! syntax/javascript.vim

" exta highlighting for LWC specific keywords
syn match PreProc "@\(api\|track\)\>"
syn match javaScriptStatement "\<\(get\|set\)\>"

