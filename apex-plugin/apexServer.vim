" File: apexServer.vim
" This file is part of vim-force.com plugin
"   https://github.com/neowit/vim-force.com
" Author: Andrey Gavrikov 
" Maintainers: 
" Last Modified: 2016-08-10
"
" apexServer.vim - "logic for calling tooling-force.com.jar in 'server' mode"
"
if exists("g:loaded_apexServer") || &compatible
      finish
endif
let g:loaded_apexServer = 1


function! s:getServerHost()
	return apexUtil#getOrElse("g:apex_server_host", "127.0.0.1")
endfunction

function! s:getServerPort()
	return apexUtil#getOrElse("g:apex_server_port", 8888)
endfunction

function! s:getServerTimeoutSec()
	return apexUtil#getOrElse("g:apex_server_timeoutSec", 60)
endfunction


" blocking call: collects all response and waits till channels os closed
" Param: paramsMap - dictionary
function! apexServer#eval(command, paramsMap) abort
	let l:host = s:getServerHost()
	let l:port = s:getServerPort()
    
    return a:execBlocking(a:command)
    
endfunction

" async call: does not wait for channel to close
" Param: paramsMap - dictionary
function! apexServer#send(command, callbackFuncRef, paramsMap) abort
	let l:host = s:getServerHost()
	let l:port = s:getServerPort()

    call s:execAsync(a:command, a:callbackFuncRef)
    
endfunction

function! s:execBlocking(command) abort
    let obj = {}
    let obj.responseLines = []
    function! obj.callbackInternal(channel, ...)
        if a:0 > 0
            " channel and msg
            let l:msg = a:1 
            call add(self.responseLines, l:msg)
            return
        elseif 0 == a:0
            " channel only. assume that channel has been closed
            let self.done = 1
        endif    
    endfunction    
    call s:execAsync(a:command, function(obj.callbackInternal))
    
    " wait for response to become available
    let mills = 3
    while !has_key(obj, "done")
        "sleep for NN milliseconds
        exec 'sleep ' .mills. 'm' 
        if mills < 100
            let mills += 1
        endif
    endwhile    

    echo "obj.responseLines=" . string(obj.responseLines)
    return obj.responseLines
endfunction    

function! s:execAsync(command, callbackFuncRef) abort
    "call ch_logfile('/Users/andrey/temp/vim/_job-test/channel.log', 'w')

    let l:reEnableMore = &more
    set nomore
    call apexMessages#log("")
    call apexMessages#log(a:command)
    if l:reEnableMore
        set more
    endif

    let attempts = 15
    while attempts > 0 
        let attempts -= 1
        try
            let l:host = s:getServerHost()
            let l:port = s:getServerPort()
            let s:channel = ch_open(l:host . ':' . l:port, {"callback": a:callbackFuncRef, "close_cb": a:callbackFuncRef, "mode": "nl"})
            call ch_sendraw(s:channel, a:command . "\n") " each message must end with NL
            
            " get rid of any previous messages (e.g. server start) in status line
            redrawstatus! 
            
            break
        catch /^Vim\%((\a\+)\)\=:E906/
            "echom 'server not started: ' v:exception
            if "shutdown" != a:command
                "call s:showProgress("Starting server...")
                call s:startServer()
                sleep 1000m
            endif
        catch /.*/
            call apexMessages#logError("Failed to execute command. " . v:exception)
            break
        endtry    
    endwhile
    
endfunction    

function! s:startServer()
    "call ch_logfile('/Users/andrey/temp/vim/_job-test/channel-startServer.log', 'w')

    let obj = {}
    
    function obj.callback(channel, msg)
        "echomsg "callback: msg=" . a:msg
        if a:msg =~ "Error"
            call apexMessages#logError("Failed to start server: " . a:msg)
        elseif a:msg =~ "Awaiting connection"    
            try 
                call ch_close(a:channel) 
            catch
                " ignore
            endtry
        endif    

    endfunction    
    
    let l:java_command = s:getJavaCommand()
    let l:command = l:java_command . " --action=serverStart --port=" . s:getServerPort() . " --timeoutSec=" . s:getServerTimeoutSec()
    "echom "l:command=" . l:command
    let job = job_start(l:command, {"callback": obj.callback})
    
endfunction    

function! s:getJavaCommand()

	let l:java_command = "java "
	if exists("g:apex_java_cmd")
		" set user defined path to java
		let l:java_command = g:apex_java_cmd
	endif
	if exists('g:apex_tooling_force_dot_com_java_params')
		" if defined then add extra JVM params
		let l:java_command = l:java_command  . " " . g:apex_tooling_force_dot_com_java_params
	else
		let l:java_command = l:java_command  . " -Dorg.apache.commons.logging.simplelog.showlogname=false "
		let l:java_command = l:java_command  . " -Dorg.apache.commons.logging.simplelog.showShortLogname=false "
		let l:java_command = l:java_command  . " -Dorg.apache.commons.logging.simplelog.defaultlog=info "
	endif
    if l:java_command !~ "-Dfile.encoding"
        " force UTF-8 encoding if user did not set an alternative explicitly
		let l:java_command = l:java_command  . " -Dfile.encoding=UTF-8 "
    endif    
	let l:java_command = l:java_command  . " -jar " . fnameescape(g:apex_tooling_force_dot_com_path)

    return l:java_command

endfunction

