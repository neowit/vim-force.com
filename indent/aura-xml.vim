" File: visualforce.vim
" This file is part of vim-force.com plugin
" https://github.com/neowit/vim-force.com
" Author: Andrey Gavrikov 
" Last Modified: 2017-12-13
"
" indent config for aura .cmp code files

silent! unlet b:did_indent
runtime indent/xml.vim
let s:xmlIndentRef=function("XmlIndentGet")

silent! unlet b:did_indent
runtime indent/html.vim
let s:htmlIndentRef=function("HtmlIndent")

silent! unlet b:did_indent
runtime indent/css.vim
let s:cssIndentExpr=function("GetCSSIndent")

setlocal indentexpr=VFIndent()

function! VFIndent()
  let scriptlnum = searchpair('<script.\{-}>','','</script>','bWn')
  let stylelnum = searchpair('<style.\{-}>','','</style>','bWn')
  let prevlnum = prevnonblank(v:lnum)

  if scriptlnum && scriptlnum!=prevlnum
	return s:htmlIndentRef()
  endif

  if stylelnum && stylelnum!=prevlnum
	return s:cssIndentExpr()
  endif

  return s:xmlIndentRef(v:lnum,0)
endfunction

