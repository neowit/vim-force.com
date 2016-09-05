" This file is part of vim-force.com plugin
"   https://github.com/neowit/vim-force.com
" File: aura.vim
" This file is part of vim-force.com plugin
" https://github.com/neowit/vim-force.com
" Author: Andrey Gavrikov 
" Last Modified: 2015-01-04
" Aura specific tags
"
" Language:	apexcode.aura
"
"
if exists("b:current_syntax")
	unlet b:current_syntax
endif
runtime! syntax/html.vim

" higihlight visualforce tags as html tags
syn match htmlTagName contained "\(aura\|ui\):[a-z]\+[A-Za-z]*"
" fix syntax breakage when using '&{'in the code looking something like this
" <apex:outputLink value="/path?param=1&{!mergeVar}">link</apex:outputLink>
syn match htmlSpecialChar contained "&{"
syn region htmlSpecialChar start=+{!+ end=+}+

