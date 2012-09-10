" File: apexRetrieve.vim
" Author: Andrey Gavrikov 
" Version: 0.1
" Last Modified: 2012-09-07
" Copyright: Copyright (C) 2010-2012 Andrey Gavrikov
"            Permission is hereby granted to use and distribute this code,
"            with or without modifications, provided that this copyright
"            notice is copied with it. Like anything else that's free,
"            this plugin is provided *as is* and comes with no warranty of any
"            kind, either expressed or implied. In no event will the copyright
"            holder be liable for any damages resulting from the use of this
"            software.
"
" apexRetrieve.vim - part of vim-force.com plugin
" Selective Metadata retrieval methods

if exists("g:loaded_apex_retrieve") || &compatible || stridx(&cpo, "<") >=0
	"<SID> requires that the '<' flag is not present in 'cpoptions'.
	finish
endif
"let g:loaded_apex_retrieve = 1

let s:header = [
  \ "vim-force.com: mark/select types to retrieve, then give command :ApexRetrieve\n" ,
  \ " T=toggle Select/Deselect, E=expand current, :Ret = expand all selected\n",
  \ "=============================================================================\n"
  \ ]
let s:headerLineCount = len(s:header) + 2 " + 2 because of extra lines added later

let s:MARK_SELECTED = "*"

" open existing or load new file with metadata types
function! apexRetrieve#open(projectName, projectPath)

endfunction
" mark entry as Selected/Deselected
function! <SID>ToggleSelected()
  " Toggle type selection
	" let lineNum = line('.')
	" let lineStr = getline(lineNum)
	let lineStr = s:getCurrentLine()
	if s:isSelected(lineStr)
		"remove mark
		let lineStr = lineStr[1:]
	else
		"add mark
		let lineStr = s:MARK_SELECTED . lineStr
	endif
	call s:setCurrentLine(lineStr)
endfunction

" retrieve children of selected component
function! <SID>ExpandCurrent()
	echo "load children of current line"
endfunction

function! <SID>ExpandSelected()
	echo "Expand children of all selected items"
	let lines = getline(1, line("$"))
	let selectedLines = []
	let l:count = 0

	for line in lines
		echo "line=".line
		if s:isSelected(line)
			echo "selected line=".line
		endif
		let l:count = l:count +1
	endfor
endfunction

function! <SID>RetrieveSelected()
	echo "Retrieve all selected items"
endfunction

function! s:isSelected(lineStr)
	let markIndex = stridx(a:lineStr, s:MARK_SELECTED)
	return 0 == markIndex
endfunction
function! s:getCurrentLine()
	let lineNum = line('.')
	let lineStr = getline(lineNum)
	return lineStr
endfunction

function! s:setCurrentLine(line)
	let lineNum = line('.')
	let lineStr = setline(lineNum, a:line)
endfunction

function! s:SID()
  " Return the SID number for a file
  return matchstr(expand('<sfile>'), '<SNR>\zs\d\+\ze_SID$')
endfun
let s:sid = s:SID()

" Define key mapping for current buffer
exec 'nnoremap <buffer> <silent> t :call <SNR>'.s:sid.'_ToggleSelected()<CR>'
exec 'nnoremap <buffer> <silent> e :call <SNR>'.s:sid.'_ExpandCurrent()<CR>'
" Define commands for current buffer
exec 'command! -buffer -bang -nargs=0 Expand :call <SNR>'.s:sid.'_ExpandSelected()'
exec 'command! -buffer -bang -nargs=0 Retrieve :call <SNR>'.s:sid.'_RetrieveSelected()'

"source % | call TestRetrieve()
function! TestRetrieve()

	"call <SID>ToggleSelected()
	"call <SID>ExpandCurrent()
	"call <SID>RetrieveSelected()

endfunction
