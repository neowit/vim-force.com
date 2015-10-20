" This file is part of vim-force.com plugin
"   https://github.com/neowit/vim-force.com
" File: visualforce.vim
" This file is part of vim-force.com plugin
" https://github.com/neowit/vim-force.com
" Author: Andrey Gavrikov 
" Last Modified: 2012-03-05
" Visualforce specific tags

" Language:	ApexCode		
"
"
if exists("b:current_syntax")
	unlet b:current_syntax
endif
runtime! syntax/html.vim

" higihlight visualforce tags as html tags
syn match htmlTagName contained "\(c\|apex\|chatter\|flow\|ideas\|knowledge\|messaging\|site\):[a-z]\+[A-Za-z_0-9]*"
" fix syntax breakage when using '&{'in the code looking something like this
" <apex:outputLink value="/path?param=1&{!mergeVar}">link</apex:outputLink>
syn match htmlSpecialChar contained "&{"
syn region htmlSpecialChar start=+{!+ end=+}+

" fix syntax breakage when using CSS url("{!merge expression}")
syn region cssURL contained matchgroup=cssFunctionName start="\<url\s*('{!" end="}')" oneline extend
syn region cssURL contained matchgroup=cssFunctionName start="\<url\s*(\"{!" end="}\")" oneline extend


