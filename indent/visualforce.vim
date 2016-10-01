" File: visualforce.vim
" This file is part of vim-force.com plugin
" https://github.com/neowit/vim-force.com
" Author: Andrey Gavrikov 
" Last Modified: 2016-09-11
"
" indent config for visualforce code files

" Loading XML indent script, that works well with HTML and VF tags
silent! unlet b:did_indent
runtime indent/xml.vim
let s:xmlIndentExpr = &l:indentexpr

" Loading HTML indent script, for indent between script/style tags
silent! unlet b:did_indent
runtime indent/html.vim
let s:htmlIndentExpr = &l:indentexpr

setlocal indentexpr=VisualforceIndentExpr(v:lnum)

function! VisualforceIndentExpr(curlinenum)
  let scriptlnum = searchpair('<script.\{-}>', '',
  \                           '</script>', 'bWn')
  let stylelnum = searchpair('<style.\{-}>', '',
  \                           '</style>', 'bWn')
  let prevlnum = prevnonblank(a:curlinenum)

  " If we are between script / style tags, use html indentation
  if scriptlnum && scriptlnum+1 != prevlnum || stylelnum && stylelnum+1 != prevlnum
	exec 'return ' s:htmlIndentExpr
  endif

  " Otherwise we use XML indentation
  exec 'return ' s:xmlIndentExpr
endfunction
