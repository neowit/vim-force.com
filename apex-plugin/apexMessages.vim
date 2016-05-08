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

let s:BUFFER_NAME = 'vim-force.com-Messages'

let s:tempFile = tempname() 
let g:tempFile = s:tempFile

function! apexMessages#open()
    if exists('g:APEX_MESSAGES_BUFFER_DISABLED') && g:APEX_MESSAGES_BUFFER_DISABLED
        call apexUtil#info("Message buffer is disabled by 'g:APEX_MESSAGES_BUFFER_DISABLED' valiable")
        return
    endif    

    if !filereadable(s:tempFile)
        call apexUtil#info("No messages to display")
        return
    endif    
    
    call s:ensureBufferExists()
	" syntax highlight
	if has("syntax")
		syntax on
        set filetype=apex_messages
        set syntax=apex_messages
	endif

    "redraw
    edit
    normal G
endfunction    

"Param: displayMessageTypes list of message types to display, other types will
"be ignored, e.g. ['ERROR'] - will display only errors
"Param: ... flags string
"       'N' = suppress new/empty line after last message
"Returns: number of messages displayed
function! apexMessages#display(logFilePath, projectPath, displayMessageTypes, ...)
    call s:ensureBufferExists()
    
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
		let l:index = l:index + 1 + s:displayMessageDetails(a:logFilePath, a:projectPath, message)
		"let l:index += 1
	endfor
    
	return l:index
endfunction

" using Id of specific message check if log file has details and display if
" details found
function! s:displayMessageDetails(logFilePath, projectPath, message)
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
    "setlocal modifiable
    let l:msgType = len(a:msgType) > 0? a:msgType . ':' : ''
    "call append( line('$'), l:msgType . ' ' . a:msg )
    call s:dump(l:msgType . ' ' . a:msg)
    "setlocal nomodifiable
    if s:isVisible()
        "redraw
        edit
        normal G
    endif    
endfunction    
function! s:logDetail(msgType, msg)
    "setlocal modifiable
    "call append( line('$'), a:msgType . ':    ' . a:msg)
    let l:msgType = len(a:msgType) > 0? a:msgType . ':' : ''
    call s:dump(l:msgType . '    ' . a:msg)

    "setlocal nomodifiable
    if s:isVisible()
        " scroll to the bottom of the file
        "redraw
        edit
        normal G
    endif    
endfunction    

function! s:dump(line)
    call writefile([a:line], s:tempFile, "a")
endfunction

function! apexMessages#logInfo(msg)
    "call s:ensureBufferExists()
    call s:logHeader("INFO", a:msg)
    call apexUtil#info(a:msg)
endfunction    

function! apexMessages#logError(msg)
    "call s:ensureBufferExists()
    call s:logHeader("ERROR", a:msg)
    call apexUtil#info(a:msg)
endfunction    

function! apexMessages#log(msg)
    "call s:ensureBufferExists()
    call s:logHeader("", a:msg)
    "echo a:msg
endfunction    

"Variables:
"   g:APEX_MESSAGES_BUFFER_DISABLED - set to 1 if message buffer must NOT be
"   created/used
function! s:ensureBufferExists()
    if exists('g:APEX_MESSAGES_BUFFER_DISABLED') && g:APEX_MESSAGES_BUFFER_DISABLED
        return
    endif    
	if exists("g:_apex_messages_buf_num") && bufloaded(g:_apex_messages_buf_num)
		execute 'b '.g:_apex_messages_buf_num
        "echomsg "switch to existing buffer: " . g:_apex_messages_buf_num
    else
        "echomsg "creating message buffer"
        let l:currentBufNum = bufnr('%')
        " create new buffer
        exec 'edit ' fnameescape(s:tempFile)
        " set attributes
		"setlocal buftype=nofile
		setlocal buftype=nowrite
		setlocal bufhidden=hide " when user switches to another buffer, just hide meta buffer but do not delete
		setlocal nomodifiable
		setlocal noswapfile
		setlocal nobuflisted
        setlocal autoread
        
        echomsg 'file: ' . s:tempFile
        let s:BUFFER_NAME = bufname('%')
		let g:_apex_messages_buf_num = bufnr("%")

		" Define key mapping for current buffer
		exec 'nnoremap <buffer> <silent> q :call <SNR>'.s:sid.'_Close()<CR>'

        " switch back to original buffer
        if l:currentBufNum > 0
            "exec 'b ' . l:currentBufNum
        endif
    endif    
    "if bufname('%') != s:BUFFER_NAME
    "    exec 'file ' . fnameescape(s:BUFFER_NAME)
    "endif
    
endfunction    

function! s:isVisible()
	return bufwinnr(s:BUFFER_NAME) > 0
endfunction    

function! s:show()
    if s:isVisible()
       exec bnr . "wincmd w"
    else
       echo a:buffername . ' is not existent'
       silent execute 'split ' . a:buffername
    endif
 endfunction

function! s:SID()
  " Return the SID number for this file
  return matchstr(expand('<sfile>'), '<SNR>\zs\d\+\ze_SID$')
endfun
let s:sid = s:SID()

" close buffer
function! <SID>Close()
	if exists("g:_apex_messages_buf_num") && bufloaded(g:_apex_messages_buf_num)
        execute 'bdelete '.g:_apex_messages_buf_num
        "hide
    endif
    "exec 'buffer #'
endfunction    
