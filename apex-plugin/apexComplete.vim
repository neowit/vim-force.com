" File: apexComplete.vim
" This file is part of vim-force.com plugin
"   https://github.com/neowit/vim-force.com
" Author: Andrey Gavrikov 
" Maintainers: 
" Last Modified: 2014-09-18
"
" apexComplete.vim - "description goes here"
"
if exists("g:loaded_apexComplete") || &compatible
	  finish
endif
let g:loaded_apexComplete = 1

" This function is used for the 'omnifunc' option.		{{{1
" :h complete-functions
" :h complete-items - description of matches list
function! apexComplete#Complete(findstart, base)
	"throw "called complete"
	let l:column = col('.')
	let l:line = line('.')
	if a:findstart
		let l:start = reltime()
		return l:column
	else
		let l:filePath = expand("%:p")
		let l:matches = s:listOptions(l:filePath, l:line, l:column)
		
		"return {'words': l:matches, 'refresh': 'always'}
		return {'words': l:matches}
	endif

endfunction

function! s:listOptions(filePath, line, column)
	let attributeMap = {}
	let attributeMap["line"] = a:line
	let attributeMap["column"] = a:column
	let attributeMap["currentFilePath"] = a:filePath
	let attributeMap["currentFileContentPath"] = a:filePath "TODO

	let responseFilePath = apexTooling#listCompletions(a:filePath, attributeMap)

	let l:completionList = []
	if filereadable(responseFilePath)
		for jsonLine in readfile(responseFilePath)
			if jsonLine !~ "{"
				continue " skip not JSON line
			endif
			let l:option = eval(jsonLine)
			"echomsg string(l:option)
			let item = {}
			let item["word"] = l:option["identity"]
			let item["menu"] = l:option["signature"]
			" let item["kind"] = l:option[""] " TODO
			let item["icase"] = 1 " ignore case
			let item["dup"] = 1 " allow methods with different signatures but same name
			call add(l:completionList, item)
		endfor

		"echomsg "l:completionList=" . string(l:completionList)
	endif
	return l:completionList
endfunction
