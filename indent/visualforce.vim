" File: visualforce.vim
" This file is part of vim-force.com plugin
" https://github.com/neowit/vim-force.com
" Maintainer: Kamil Grzywacz 
" Last Modified: 2016-10-11
"
" indent config for visualforce code files

silent! unlet b:did_indent
runtime indent/xml.vim
if !exists("*XmlIndentGet")
    finish " looks like another plugin does something custom with XmlIndentGet
endif
let s:xmlIndentRef=function("XmlIndentGet")

silent! unlet b:did_indent
runtime indent/html.vim
if !exists("*HtmlIndent")
    finish " looks like another plugin does something custom with HtmlIndent
endif
let s:htmlIndentRef=function("HtmlIndent")

silent! unlet b:did_indent
runtime indent/css.vim
if !exists("*GetCSSIndent")
    finish " looks like another plugin does something custom with GetCSSIndent
endif
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
