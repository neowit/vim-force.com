" This file is part of vim-force.com plugin
"   https://github.com/neowit/vim-force.com
" File: apexUtil.vim
" Author: Andrey Gavrikov 
" Maintainers: 
"
" Various utility methods used by different parts of force.com plugin 
"
if exists("g:loaded_apexMessages") || &compatible
  finish
endif
let g:loaded_apexMessages = 1

function! apexMessages#open(...)
    let displayMode = get(g:, 'apex_messages_split_type', 'vsplit')
    if a:0 > 0
        let displayMode = a:1
    endif    

    if exists('g:APEX_MESSAGES_BUFFER_DISABLED') && g:APEX_MESSAGES_BUFFER_DISABLED
        call apexUtil#info("Message buffer is disabled by 'g:APEX_MESSAGES_BUFFER_DISABLED' valiable")
        return
    endif    
    
    call s:setupBuffer(displayMode)
    " show content
    call s:dumpCached()
    call s:showHint()
    " go to the last line
    call s:execInBuffer("normal G")
endfunction    

"Param: displayMessageTypes list of message types to display, other types will
"be ignored, e.g. ['ERROR'] - will display only errors
"Returns: number of messages displayed
function! apexMessages#process(logFilePath, projectPath, displayMessageTypes)
    
	let prefix = 'MESSAGE: '
	let l:lines = apexUtil#grepFile(a:logFilePath, '^' . prefix)
	let l:index = 0
    
	for line in l:lines
		let line = substitute(line, prefix, "", "")
		let message = eval(line)
		let msgType = has_key(message, "type")? message["type"] : "INFO"
		if len(a:displayMessageTypes) > 0
			if index(a:displayMessageTypes, msgType) < 0
				" this msgType is disabled
				continue
			endif
		endif
		let text = message["text"]
		if "ERROR" == msgType
			call apexUtil#error(text)
		elseif "WARN" == msgType
			call apexUtil#warning(text)
		elseif "INFO" == msgType
			call apexUtil#info(text)
		elseif "DEBUG" == msgType
			echo text
		else
			echo text
		endif
        call s:logHeader(msgType, text)
		let l:index = l:index + 1 + s:processMessageDetails(a:logFilePath, a:projectPath, message)
		"let l:index += 1
	endfor
    
	return l:index
endfunction

" using Id of specific message check if log file has details and display if
" details found
function! s:processMessageDetails(logFilePath, projectPath, message)
	let prefix = 'MESSAGE DETAIL: '
	silent let l:lines = apexUtil#grepFile(a:logFilePath, '^' . prefix)
	let l:index = 0
	while l:index < len(l:lines)
		let line = substitute(l:lines[l:index], prefix, "", "")
		let detail = eval(line)
		if detail["messageId"] == a:message["id"]
			let text = "  " . detail["text"]
			if has_key(detail, "echoText")
				" for messages we do not need to display full text if short
				" version is available
				let text = "  " . detail["echoText"]
			endif
			let msgType = has_key(detail, "type")? detail.type : a:message["type"]
			if "ERROR" == msgType
				call apexUtil#error(text)
			elseif "WARN" == msgType
				call apexUtil#warning(text)
			elseif "INFO" == msgType
				call apexUtil#info(text)
			elseif "DEBUG" == msgType
				echo text
			else
				echo text
			endif
            call s:logDetail(msgType, text)
		endif
		let l:index = l:index + 1
	endwhile
	return l:index
endfunction

function! s:logHeader(msgType, msg)
    let l:msgType = len(a:msgType) > 0? a:msgType . ':' : ''
    "call append( line('$'), l:msgType . ' ' . a:msg )
    call s:cacheLines(l:msgType . ' ' . a:msg)
    if s:isVisible()
        "redraw
        call apexUtil#log("view: inside logHeader")
    endif    
endfunction    
function! s:logDetail(msgType, msg)
    "call append( line('$'), a:msgType . ':    ' . a:msg)
    let l:msgType = len(a:msgType) > 0? a:msgType . ':' : ''
    call s:cacheLines(l:msgType . '    ' . a:msg)

    if s:isVisible()
        " scroll to the bottom of the file
        "redraw
        call apexUtil#log("view: inside logDetail")
    endif    
endfunction    

let s:cachedLines = []
function! s:cacheLines(lines)
    if type(a:lines) == type([])
        call extend(s:cachedLines, a:lines)
    else " add single string
        call add(s:cachedLines, a:lines)
    endif
    if s:isVisible()
        call s:dumpCached()
    endif    
endfunction

function! s:dumpCached()
    if s:setupBuffer()
        call s:execInBuffer("call append(line('$'), s:cachedLines)")
        let s:cachedLines = []
        call s:scrollToBottomIfInactive()
    endif
endfunction

function! s:scrollToBottomIfInactive()
    " go to the last line
    call s:execInBuffer("normal G")
endfunction

" execute give comamnd in "apex_messages" buffer
function! s:execInBuffer(command)
    let l:bufNumber = s:getBufNumber()
    if l:bufNumber >=0
        " briefly switch to ApexMessage window, dump content and get back
        let currentWinNr = winnr()
        "call apexUtil#log('s:execInBuffer('.a:command.')')
        "call apexUtil#log('currentWinNr='.currentWinNr)
        if !bufloaded(l:bufNumber)
            execute 'noautocmd b '.l:bufNumber
        endif    
        let targetWinNr = bufwinnr(l:bufNumber)
        "call apexUtil#log('targetWinNr='.targetWinNr)
        execute 'noautocmd ' . targetWinNr . 'wincmd w'
        try
            execute a:command
            let s:cachedLines = []
        finally
            silent execute 'noautocmd ' . currentWinNr . 'wincmd w'
        endtry
    endif

endfunction    


function! apexMessages#logInfo(msg)
    call s:logHeader("INFO", a:msg)
    call apexUtil#info(a:msg)
endfunction    

function! apexMessages#logError(msg)
    call s:logHeader("ERROR", a:msg)
    call apexUtil#error(a:msg)
endfunction    

function! apexMessages#log(msg)
    call s:logHeader("", a:msg)
    "echo a:msg
endfunction    


function! s:isEnabled()
    return !exists('g:APEX_MESSAGES_BUFFER_DISABLED') || !g:APEX_MESSAGES_BUFFER_DISABLED
endfunction    

" Variables:
"   g:APEX_MESSAGES_BUFFER_DISABLED - set to 1 if message buffer must NOT be
"   created/used
function! s:setupBuffer(...)
    if !s:isEnabled()
        return 0
    endif    
    
    " record current window number
    let currentWinNr = winnr()
    try 
        call apexUtil#log("inside setupBuffer")

        let splitSize = get(g:, 'apex_messages_split_size', 0)
        let displayMode = get(g:, 'apex_messages_split_type', 'vsplit')

        if a:0 > 0
            let displayMode = a:1
        endif    

        let buffer_name = s:getBufferName()

        let l:winNum = s:getWinNumber()
        let splitSizeStr = splitSize <=0 ? '' : string(splitSize)

        if ( l:winNum > 0)
            silent execute 'keepalt noautocmd ' . l:winNum . "wincmd w"
        elseif ( displayMode == 'vsplit' )
            silent execute "keepalt rightbelow ".splitSizeStr." vnew " . buffer_name
        else "if ( displayMode == 'hsplit' )
            silent execute "keepalt rightbelow ".splitSizeStr." new " . buffer_name
        endif

        "silent execute "buffer " . buffer_name

        setlocal buftype=nofile
        setlocal bufhidden=hide " when user switches to another buffer, just hide 'apex_messages' buffer but do not delete
        setlocal noswapfile
        setlocal nobuflisted 

        "setlocal buftype=nowrite
        "setlocal nomodifiable
        "setlocal autoread

        " Define key mapping for current buffer
        exec 'nnoremap <buffer> <silent> q :call <SNR>'.s:sid.'_Close()<CR>'

        " syntax highlight
        if has("syntax")
            syntax on
            setlocal filetype=apex_messages
            setlocal syntax=apex_messages
        endif

    finally
        " switch back to original window if it still exists
        if winbufnr(currentWinNr) >=0 
            silent execute 'noautocmd ' . currentWinNr . 'wincmd w'
        endif
    endtry    

    return 1
    
endfunction    

let s:hintDisplayed = 0
function! s:showHint()
    if !s:hintDisplayed
        let l:separator = "************************************"
        call s:cacheLines([l:separator," press 'q' to close this buffer",l:separator])
        let s:hintDisplayed = 1
    endif
endfunction    

function! s:isVisible()
    call apexUtil#log("isVisible: s:getBufNumber=" . s:getBufNumber() . "; bufwinnr(s:getBufNumber())=" . bufwinnr(s:getBufNumber()))

	return bufwinnr(s:getBufNumber()) > 0
endfunction    

"function! s:isActive()
"	return bufwinnr(s:getBufNumber()) == bufwinnr("%")
"endfunction    

" function! s:isSetupCorrectly()
" 	return s:getBufNumber() > 0 && getbufvar(s:getBufNumber(), '&syntax') == 'apex_messages'
" endfunction    

function! s:getBufNumber()
    let buffer_name = s:getBufferName()
    return bufnr(buffer_name)
endfunction    

function! s:getWinNumber()
    let l:bufNumber = s:getBufNumber()
    return l:bufNumber > 0 ? bufwinnr(l:bufNumber) : 0
endfunction    

function! apexMessages#BufNumber()
    return s:getBufNumber()
endfunction    

"let b:projectDir = ''
function! s:getBufferName()
    "let b:projectDir = get(b:, 'projectDir', apex#getApexProjectSrcPath()) 
    "let buffer_name = 'apex_messages://' . fnameescape(projectDir)
    let buffer_name = 'apex_messages'
    return buffer_name
endfunction    

function! s:SID()
  " Return the SID number for this file
  return matchstr(expand('<sfile>'), '<SNR>\zs\d\+\ze_SID$')
endfun
let s:sid = s:SID()

" close buffer
function! <SID>Close()
    let l:winNumber = s:getWinNumber()
	if l:winNumber > 0
        execute 'close '.l:winNumber
        "hide
    endif
    "exec 'buffer #'
endfunction    


"function! s:openBufInSplit(num, splitType )
"    if a:num != bufnr("%")
"        let l:originalSplitBelow = &splitbelow
"        if "splitbelow" == a:splitType
"            set splitbelow
"        endif
"        execute 'b '.a:num
"        if !l:originalSplitBelow
"            set nosplitbelow
"        endif    
"    endif    
"endf    
