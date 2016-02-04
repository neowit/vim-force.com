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
function! apexComplete#Complete(findstart, base) abort
	
	"throw "called complete"
	let l:column = col('.')
	let l:line = line('.')
	if a:findstart
		return l:column
	else
		let l:filePath = expand("%:p")
		let l:matches = s:listOptions(l:filePath, l:line, l:column)
		
		"return {'words': l:matches, 'refresh': 'always'}
		return {'words': l:matches}
	endif

endfunction

" Run local syntax check for given apex file
" Note - this is more a grammar debug/check function, not intended for use by
" end users
function! apexComplete#checkSyntax(filePath) abort
    let l:filePath = a:filePath
	let attributeMap = {}
	"save content of current buffer in a temporary file
	"let tempFilePath = tempname() . apexOs#splitPath(a:filePath).tail
	"silent exe ":w! " . tempFilePath
	
	let attributeMap["currentFilePath"] = a:filePath
	" let attributeMap["currentFileContentPath"] = tempFilePath
	let attributeMap["currentFileContentPath"] = a:filePath

	let responseFilePath = apexTooling#checkSyntax(a:filePath, attributeMap)

	" temp file is no longer needed
	"call delete(tempFilePath)
endfunction    

function! s:listOptions(filePath, line, column)
	let attributeMap = {}
	let attributeMap["line"] = a:line
	let attributeMap["column"] = a:column
	let attributeMap["currentFilePath"] = a:filePath
	let wrapDocAfterLen = winwidth(0) - 1 "

	"save content of current buffer in a temporary file
	let tempFilePath = tempname() . apexOs#splitPath(a:filePath).tail
	silent exe ":w! " . tempFilePath
	
	let attributeMap["currentFileContentPath"] = tempFilePath

	let responseFilePath = apexTooling#listCompletions(a:filePath, attributeMap)

	" temp file is no longer needed
	call delete(tempFilePath)

	let subtractLen = s:getSymbolLength(a:column) " this many characters user already entered
	
	let l:completionList = []
	if filereadable(responseFilePath)
		for jsonLine in readfile(responseFilePath)
			if jsonLine !~ "{"
				continue " skip not JSON line
			endif
			let l:option = eval(jsonLine)
			
			let item = {}
			let item["word"] = l:option["identity"]
			if subtractLen > 0
				let item["abbr"] = l:option["identity"]
				let item["word"] = strpart(l:option["identity"], subtractLen-1, len(l:option["identity"]) - subtractLen + 1)
			endif
			let item["menu"] = l:option["signature"]
			let item["info"] = s:insertLineBreaks(l:option["doc"], wrapDocAfterLen)
			"let item["info"] = l:option["doc"]
			" let item["kind"] = l:option[""] " TODO
			let item["icase"] = 1 " ignore case
			let item["dup"] = 1 " allow methods with different signatures but same name
			call add(l:completionList, item)
		endfor

		"echomsg "l:completionList=" . string(l:completionList)
	endif
	return l:completionList
endfunction

"Return: length of the symbol under cursor
"e.g. if we are completing: Integer.va|
"then return will be len("va") = 2
function! s:getSymbolLength(column)
	let l:column = a:column
	let l:line = getline('.')
	" move back until get to a character which can not be part of
	" identifier
	let i = l:column-1
	let keepGoing = 1
	
	while keepGoing && i > 0
		let chr = strpart(l:line, i-1, 1)
		
		if chr =~? "\\w\\|_"
			let i -= 1
		else
			let keepGoing = 0
		endif
	endwhile

	return l:column - i
endfunction

"check if line is longer than N characters, and if it is then break it into
"lines of no more than N characters each
"this is used to wrap doc text in preview buffer as I do not know any way to
"detect if a buffer is really 'preview' or just some other nofile '[Scratch]'
function! s:insertLineBreaks(str, maxLen)
	let maxlen = a:maxLen
	let str = a:str
	" do not modify string if it is short enough or contains line breaks
	if strdisplaywidth(str) <= maxlen || stridx(str, "\n") > 0
		return str
	endif

	let l:strLen = len(str)
	let index = 0
	while index < l:strLen
		" find first ' ' starting maxlen, backwards
		let breakAt = strridx(str, ' ', index + maxlen)
		if breakAt > 0 && breakAt > (index + 1) && (l:strLen - index) > maxlen
			let str = strpart(str, 0, index) . strpart(str, index, breakAt - index) . "\n" . strpart(str, breakAt+1)
			let index = breakAt + 1
		else
			let index = index + maxlen
		endif
	endwhile

	return str
endfunction

