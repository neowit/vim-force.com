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

let s:BUFFER_NUMBER = -1

let s:tempFile = tempname() . ".apex_messages"
let g:tempFile = s:tempFile
augroup apex_messages
	au!
	au! BufRead,BufNewFile  *.apex_messages call s:setupBuffer()
	"exec 'au! BufRead,BufNewFile "'.s:tempFile.'" call s:setupBuffer()'
augroup END


function! apexMessages#open()
    if exists('g:APEX_MESSAGES_BUFFER_DISABLED') && g:APEX_MESSAGES_BUFFER_DISABLED
        call apexUtil#info("Message buffer is disabled by 'g:APEX_MESSAGES_BUFFER_DISABLED' valiable")
        return
    endif    

    if !filereadable(s:tempFile)
        call apexUtil#info("No messages to display")
        return
    endif    
    
    "call s:setupBuffer()

    "redraw
    " show content
	if s:BUFFER_NUMBER > 0 && bufloaded(s:BUFFER_NUMBER)
		execute 'b '.s:BUFFER_NUMBER
    else 
        call apexUtil#log("view: inside apexMessages#open")
        exec 'view ' . fnameescape(s:tempFile)
    endif
    " go to the last line
    normal G
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
    call s:dump(l:msgType . ' ' . a:msg)
    if s:isVisible()
        "redraw
        call apexUtil#log("view: inside logHeader")
        exec 'view ' . s:tempFile
        normal G
    endif    
endfunction    
function! s:logDetail(msgType, msg)
    "call append( line('$'), a:msgType . ':    ' . a:msg)
    let l:msgType = len(a:msgType) > 0? a:msgType . ':' : ''
    call s:dump(l:msgType . '    ' . a:msg)

    if s:isVisible()
        " scroll to the bottom of the file
        "redraw
        call apexUtil#log("view: inside logDetail")
        exec 'view ' . s:tempFile
        normal G
    endif    
endfunction    

function! s:dump(line)
    call writefile([a:line], s:tempFile, "a")
endfunction

function! apexMessages#logInfo(msg)
    call s:logHeader("INFO", a:msg)
    call apexUtil#info(a:msg)
endfunction    

function! apexMessages#logError(msg)
    call s:logHeader("ERROR", a:msg)
    call apexUtil#info(a:msg)
endfunction    

function! apexMessages#log(msg)
    call s:logHeader("", a:msg)
    "echo a:msg
endfunction    

let s:hintDisplayed = 0
"Variables:
"   g:APEX_MESSAGES_BUFFER_DISABLED - set to 1 if message buffer must NOT be
"   created/used
function! s:setupBuffer()
    if exists('g:APEX_MESSAGES_BUFFER_DISABLED') && g:APEX_MESSAGES_BUFFER_DISABLED
        return
    endif    
    
    call apexUtil#log("inside setupBuffer")
    if !s:isSetupCorrectly()
        let s:BUFFER_NUMBER = bufnr('%')
        " create new buffer
        "exec 'view ' fnameescape(s:tempFile)
        " set attributes
		"setlocal buftype=nofile
		setlocal buftype=nowrite
		setlocal bufhidden=hide " when user switches to another buffer, just hide meta buffer but do not delete
		setlocal nomodifiable
		setlocal noswapfile
		setlocal nobuflisted
        setlocal autoread
        
		" Define key mapping for current buffer
		exec 'nnoremap <buffer> <silent> q :call <SNR>'.s:sid.'_Close()<CR>'
        if !s:hintDisplayed
            let l:separator = "************************************"
            call writefile([l:separator," press 'q' to close this buffer",l:separator], s:tempFile, "a")
            let s:hintDisplayed = 1
            " reload with hint visible
            call apexUtil#log("view: inside setupBuffer")

            exec 'view ' fnameescape(s:tempFile)
        endif
        
        " syntax highlight
        if has("syntax")
            syntax on
            setlocal filetype=apex_messages
            setlocal syntax=apex_messages
        endif

    endif    
    
endfunction    

function! s:isVisible()
    call apexUtil#log("isVisible: s:BUFFER_NUMBER=" . s:BUFFER_NUMBER . "; bufwinnr(s:BUFFER_NUMBER)=" . bufwinnr(s:BUFFER_NUMBER))

	return bufwinnr(s:BUFFER_NUMBER) > 0
endfunction    

function! s:isSetupCorrectly()
	return s:BUFFER_NUMBER > 0 && 'apex_messages' && getbufvar(s:BUFFER_NUMBER, "&syntax")
endfunction    

"function! s:show()
"    if s:isVisible()
"       exec bnr . "wincmd w"
"    else
"       echo a:buffername . ' is not existent'
"       silent execute 'split ' . a:buffername
"    endif
"endfunction

function! s:SID()
  " Return the SID number for this file
  return matchstr(expand('<sfile>'), '<SNR>\zs\d\+\ze_SID$')
endfun
let s:sid = s:SID()

" close buffer
function! <SID>Close()
	if s:BUFFER_NUMBER > 0 && bufloaded(s:BUFFER_NUMBER)
        execute 'bdelete '.s:BUFFER_NUMBER
        "hide
    endif
    "exec 'buffer #'
endfunction    
