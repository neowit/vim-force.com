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
    
    " check if this file is inside 'src' folder
    try | call apex#getSFDCProjectPathAndName(l:filePath) | catch /.*/ | return | endtry    

	let attributeMap = {}
	"save content of current buffer in a temporary file
	"let tempFilePath = tempname() . apexOs#splitPath(a:filePath).tail
	"silent exe ":w! " . tempFilePath
	
	let attributeMap["currentFilePath"] = a:filePath
	" let attributeMap["currentFileContentPath"] = tempFilePath
	let attributeMap["currentFileContentPath"] = a:filePath

	let responseFilePath = apexToolingAsync#checkSyntax(a:filePath, attributeMap)

	" temp file is no longer needed
	"call delete(tempFilePath)
endfunction    

" navigate to the definition of symbol under cursor
function! apexComplete#goToSymbol()
	let l:column = col('.') + 1 " +1 is not a mistake here
	let l:line = line('.')
    let l:filePath = expand("%:p")

    let obj = {}
    let obj["filePath"] = l:filePath
    function! obj.callbackFuncRef(locations)
        let l:locations = a:locations
        if empty(l:locations)
            call apexUtil#warning("Symbol location not found")

        elseif 1 == len(l:locations)
            " there is only 1 location, can go there directly
            call s:navigateToLocation(self.filePath, l:locations[0])
        else 
            " there is more than 1 location    
            call s:displayListOfLocations(self.filePath, l:locations)
        endif    

    endfunction    

    call s:findSymbol(l:filePath, l:column, l:line, obj)

endfunction    

function! s:navigateToLocation(currentBufferFilePath, location)
    let l:symbolDefinition = a:location
    let l:filePath = a:currentBufferFilePath
    if has_key(l:symbolDefinition, "filePath")
        let targetFilePath = l:symbolDefinition["filePath"]
        let targetLine = l:symbolDefinition["line"]
        let targetColumn = l:symbolDefinition["column"]
        let targetIdentity = l:symbolDefinition["identity"]

        let bufnum = bufnr("%") " by default assume current buffer
        " add current position to jump list (setpos() does not do that)
        exe "normal m'"
        if targetFilePath != l:filePath
            silent execute "edit " . fnameescape(targetFilePath)
            let bufnum = bufnr(targetFilePath)
        endif    
        if bufnum >= 0
            " place cursor on the line with target idenity
            call setpos(".", [bufnum, targetLine, targetColumn])
            if len(targetIdentity) > 0
                " move cursor at the start of identifier
                call search(targetIdentity)
            endif
            redraw
        endif    
    else
        call apexUtil#warning("Symbol location not found")
    endif
endfunction    

function! s:displayListOfLocations(currentBufferFilePath, locations)
    let l:filePath = a:currentBufferFilePath
    "clear quickfix
    call setqflist([])
    let l:locationList = []
    for l:location in a:locations
        let line = {}

        let line.filename = l:location["filePath"]
        let line.text = l:location["identity"]
        let line.lnum = l:location["line"]
        let line.col = l:location["column"]
        call add(l:locationList, line)
    endfor
    " sort by file name
    "call sort(l:locationList, "s:fileNameComparator")

    call setqflist(l:locationList)
    if len(l:locationList) > 0
        copen
    endif
endfunction    

function! s:findSymbol(filePath, column, line, callbackObj)
	let l:column = a:column
	let l:line = a:line
    let l:filePath = a:filePath

	let attributeMap = {}
	let attributeMap["line"] = l:line
	let attributeMap["column"] = l:column
	let attributeMap["currentFilePath"] = l:filePath
    let tempBufferContentFile = s:getBufContentAsTempFile(l:filePath)
	let attributeMap["currentFileContentPath"] = tempBufferContentFile

	call apexToolingAsync#findSymbol(l:filePath, attributeMap, a:callbackObj)
endfunction    

function! s:getBufContentAsTempFile(filePath)
	"save content of current buffer in a temporary file
	let tempFilePath = tempname() . apexOs#splitPath(a:filePath).tail
	silent exe ":w! " . tempFilePath
    return tempFilePath
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
    let l:isPreviewOpen = 0
	if filereadable(responseFilePath)
		for jsonLine in readfile(responseFilePath)
			if jsonLine !~ "^{"
				continue " skip not JSON line
			endif
			let l:option = eval(jsonLine)
			
			let item = {}
            let symbolInsertText =  empty(l:option["symbolInsertText"])? l:option["identity"] : l:option["symbolInsertText"]
			let item["word"] = symbolInsertText " text to insert
			if subtractLen > 0
				let item["abbr"] = l:option["identity"]
				let item["word"] = strpart(symbolInsertText, subtractLen-1, len(symbolInsertText) - subtractLen + 1)
			endif
			let item["menu"] = l:option["signature"]
            let l:info = s:insertLineBreaks(l:option["doc"], wrapDocAfterLen)

            " blank out item["info"] if doc is empty
            if (!empty(l:info))
                let item["info"] = l:info
                let l:isPreviewOpen = 1 " signal that this item will cause preview window to open
            else    
                " :h complete-items
                " Use a single space for "info" to remove existing text in the preview window.
                if l:isPreviewOpen
                    " assign ' ' to info *only* if we know that preview window
                    " will be open for other (preceding) items which have documentation
                    let item["info"] = ' '
                endif    
            endif    
			" let item["kind"] = l:option[""] " TODO
			let item["kind"] = has_key(l:option, "kind") ? l:option["kind"] : ""
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

