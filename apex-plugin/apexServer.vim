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
    
    return s:execBlocking(a:command)
    
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
    let mills = 100
    while !has_key(obj, "done")
        "sleep for NN milliseconds
        exec 'sleep ' .mills. 'm' 
        " redraw screen to reduce chances of accumulating '/ =>' progress characters in
        " status line/window
        redraw
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

    try
        let l:host = s:getServerHost()
        let l:port = s:getServerPort()
        let s:channel = ch_open(l:host . ':' . l:port, {"callback": a:callbackFuncRef, "close_cb": a:callbackFuncRef, "mode": "nl"})
        call ch_sendraw(s:channel, a:command . "\n") " each message must end with NL

        " get rid of any previous messages (e.g. server start) in status line
        redrawstatus! 
    catch /^Vim\%((\a\+)\)\=:E906/
        "echom 'server not started: ' v:exception
        if "shutdown" != a:command
            "call s:showProgress("Starting server...")
            call s:startServer(a:command, a:callbackFuncRef)
        endif
    catch /.*/
        call apexMessages#logError("Failed to execute command. " . v:exception)
        break
    endtry    
    
endfunction    

let s:callServerStartCallback = 0
function! s:closeChannelAndRunOriginalCommand(channel, command, callbackFuncRef)
    try 
        call ch_close(a:channel) 
    catch
        " ignore
    endtry
    let s:callServerStartCallback = 0
    echomsg "calling original command: ". a:command
    call s:execAsync(a:command, a:callbackFuncRef)
endfunction

function! s:serverStartCallback(command, callbackFuncRef, ...)
    " a:1 - channel, a:2 - message
    let l:channel = a:0 > 0 ? a:1 : -1
    let l:msg = a:0 > 1 ? a:2 : ""
    
    echomsg "serverStartCallback: channel=" . l:channel
    echomsg "serverStartCallback: msg=" . l:msg
    
    if l:msg =~? "java.net.BindException: Address already in use"
        " looks like multiple command have been called simultaneously and
        " tryed to start more than 1 instance of the server
        call s:closeChannelAndRunOriginalCommand(l:channel, a:command, a:callbackFuncRef)
    elseif l:msg =~ "Error"
        call apexMessages#logError("Failed to start server: " . l:msg)
        call apexMessages#open()
        call apexToolingAsync#stopProgressTimer()

    elseif l:msg =~ "Awaiting connection"
        " looks like server has started, can call the original command now
        call s:closeChannelAndRunOriginalCommand(l:channel, a:command, a:callbackFuncRef)
    else    
        try 
            call ch_close(l:channel) 
        catch
            " ignore
        endtry
        " generic error, report as is
        echoerr l:msg
        call apexMessages#log(l:msg)
        call apexMessages#open()
        call apexToolingAsync#stopProgressTimer()
    endif    

endfunction    

function! s:startServer(command, callbackFuncRef)
    "call ch_logfile(expand("$HOME") . '/temp/vim/_job-test/channel-startServer.log', 'w')

    let l:command = a:command
    let CallbackFuncRef = a:callbackFuncRef
    
    
    let l:java_command = s:getJavaCommand()
    let l:command = l:java_command . " --action=serverStart --port=" . s:getServerPort() . " --timeoutSec=" . s:getServerTimeoutSec()
    "echom "l:command=" . l:command
    let s:callServerStartCallback = 1
    call apexMessages#log("Trying to start server using command: " . l:command)
    let job = job_start(l:command, {"callback": function('s:serverStartCallback', [a:command, a:callbackFuncRef]), "stoponexit": "kill"})
    
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

