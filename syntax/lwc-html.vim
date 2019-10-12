" This file is part of vim-force.com plugin
"   https://github.com/neowit/vim-force.com
" File: lwc-html.vim
" This file is part of vim-force.com plugin
" https://github.com/neowit/vim-force.com
" Author: Andrey Gavrikov 
" Last Modified: 2019-10-12
" Lightning Web Component specific tags
"
" Language:	Lightning Web Component - HTML
"
"
if exists("b:current_syntax")
	unlet b:current_syntax
endif
runtime! syntax/html.vim

" higihlight web component tags as html tags
syn match htmlTagName "\<\([a-z]\+[A-Za-z]*\(-[a-z]\+[A-Za-z]*\)*\)" contained
"syn match htmlTagName "\(lightning\|ltng\)-[a-z]\+[A-Za-z]*" contained


