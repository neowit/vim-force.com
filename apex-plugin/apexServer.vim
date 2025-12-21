" File: apexServer.vim
" This file is part of vim-force.com plugin
"   https://github.com/neowit/vim-force.com
" Author: Andrey Gavrikov 
" File: apexServer.vim
"
" apexServer.vim - "logic for calling tooling-force.com.jar in 'server' mode"
"
if exists("g:loaded_apexServer") || &compatible
      finish
endif
let g:loaded_apexServer = 1


function! s:isNvim()
    return has('nvim')
endfunction

function! s:getServerHost()
	return apexUtil#getOrElse("g:apex_server_host", "127.0.0.1")
endfunction

function! s:getServerPort()
	return apexUtil#getOrElse("g:apex_server_port", 8888)
endfunction

function! s:getServerTimeoutSec()
	return apexUtil#getOrElse("g:apex_server_timeoutSec", 60)
endfunction

" blocking call: collects all response and waits till channel is closed
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

" for debug purposes only
function! apexServer#evalRaw(command, paramsMap) abort
    return s:evalRaw(a:command)
endfunction    

" blocking call
" use this method to send a blocking command like 'ping' to already running server
" no attempt to start a server is done
" this function is not suitable for apex commands because does not collect all
" server output, but only first line
function! s:evalRaw(command)
    let obj = {}
    function! obj.dummyCallback(...)
    endfunction
    try
        let l:host = s:getServerHost()
        let l:port = s:getServerPort()
        let l:address = l:host . ':' . l:port
        
        " echomsg "# s:channelOpen l:address=" l:address
        let s:channel = s:channelOpen(l:address, {"callback": obj.dummyCallback, "close_cb": obj.dummyCallback, "mode": "nl"})
        
        let l:result = s:channelEvalRaw(s:channel, a:command . "\n")
        " echomsg "# s:evalRaw l:result=" l:result
        call s:channelClose(s:channel)
        " get rid of any previous messages (e.g. server start) in status line
        redrawstatus! 
        return l:result
    catch /^Vim\%((\a\+)\)\=:E906/
        "echom 'server not started: ' v:exception
    catch /.*/
        call apexMessages#logError("Failed to execute command. " .a:command. "; " . v:exception)
    endtry    
    return ''
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
    "call ch_logfile("$HOME/temp/vim/_job-test/channel.log", 'w')
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
        let l:address = l:host . ':' . l:port
        
        let s:channel = s:channelOpen(l:address, {"callback": a:callbackFuncRef, "close_cb": a:callbackFuncRef, "mode": "nl"})
        call s:channelSend(s:channel, a:command . "\n") " each message must end with NL
        " get rid of any previous messages (e.g. server start) in status line
        redrawstatus! 
    catch /^Vim\%((\a\+)\)\=:E906/
        "echom 'server not started: ' v:exception
        if "shutdown" != a:command
            "call s:showProgress("Starting server...")
            call s:startServer(a:command, a:callbackFuncRef)
        endif
    catch /Vim(let):connection failed/
        " echom 'nvim: server not started: ' v:exception "attempting to start..."
        if "shutdown" != a:command
            "call s:showProgress("Starting server...")
            call s:startServer(a:command, a:callbackFuncRef)
        endif
    catch /.*/
        call apexMessages#logError("Failed to execute command. " . v:exception)
        throw "Process aborted due to exception"
    endtry    
    
endfunction    

let s:callServerStartCallback = 0
let s:serverStartTime = 0
let s:serverStartTimeoutSec = exists("g:apex_server_start_timeout") ? eval("g:apex_server_start_timeout") : 7

function! s:isServerStarting()
    if 0 != s:serverStartTime && s:serverStartTimeoutSec > (localtime() - s:serverStartTime)
        return 1
    endif    
    return 0
endfunction    

function! s:closeChannelAndRunOriginalCommand(channel, command, callbackFuncRef)
    call s:channelClose(a:channel)
    let s:callServerStartCallback = 0
    " echomsg "calling original command: ". a:command
    call s:execAsync(a:command, a:callbackFuncRef)
endfunction

function! s:waitForServerToStartAndRunOriginalCommand(command, callbackFuncRef)
    let l:count = s:serverStartTimeoutSec " wait no more than N seconds
    while s:isServerStarting() && l:count > 0
        sleep
        let l:count -= 1
    endwhile    
    if !s:isServerStarting() && s:evalRaw("ping") =~? "pong"
        call s:execAsync(a:command, a:callbackFuncRef)
    endif
endfunction    

function! s:serverStartCallback(command, callbackFuncRef, ...)
    let s:serverStartTime = 0
    " a:1 - channel, a:2 - message
    let l:channel = a:0 > 0 ? a:1 : -1
    let l:msg = a:0 > 1 ? a:2 : ""
    
    " echomsg "serverStartCallback: channel=" . l:channel
    " echomsg "serverStartCallback: msg=" . l:msg
    
    if l:msg =~? "java.net.BindException: Address already in use"
        " looks like multiple command have been called simultaneously and
        " tried to start more than 1 instance of the server
        call s:closeChannelAndRunOriginalCommand(l:channel, a:command, a:callbackFuncRef)
    elseif l:msg =~ "Error"
        call apexMessages#logError("Failed to start server: " . l:msg)
        call apexMessages#open()
        call apexToolingAsync#stopProgressTimer()
    elseif l:msg =~ "Awaiting connection"
        " looks like server has started, can call the original command now
        call s:closeChannelAndRunOriginalCommand(l:channel, a:command, a:callbackFuncRef)
    else    
        call s:channelClose(l:channel)
        " generic error, report as is
        echoerr l:msg
        call apexMessages#log(l:msg)
        call apexMessages#open()
        call apexToolingAsync#stopProgressTimer()
    endif    
endfunction    

function! s:startServer(command, callbackFuncRef)
    "call ch_logfile(expand("$HOME") . '/temp/vim/_job-test/channel-startServer.log', 'w')
    if s:isServerStarting()
        " looks like two or more commands have been called simultaneously but
        " server was not running, let's wait
        call s:waitForServerToStartAndRunOriginalCommand(a:command, a:callbackFuncRef)
        return
    endif    
    let s:serverStartTime = localtime()
    let l:java_command = s:getJavaCommand()
    let l:command = l:java_command . " --action=serverStart --port=" . s:getServerPort() . " --timeoutSec=" . s:getServerTimeoutSec()
    let s:callServerStartCallback = 1
    call apexMessages#log("Trying to start server using command: " . l:command)
    
    let job = s:jobStart(l:command, {"callback": function('s:serverStartCallback', [a:command, a:callbackFuncRef]), "stoponexit": "kill"})
    
endfunction

" used to test if "java" and "tooling-force.com.jar" config is valid
function! apexServer#validateJavaConfig() abort
    let l:java_command = s:getJavaCommand()
    let l:command = l:java_command . " --action=version "
    if apexOs#isWindows()
        " change all '\' in path to '/'
        let l:command = substitute(l:command, '\', '/', "g")
    endif    
    let projectPath = apexOs#createTempDir()
    let responseFilePath = tempname() . "-test.txt"
    execute "!".l:command . " --projectPath=".shellescape(projectPath) . " --responseFilePath=".shellescape(responseFilePath)
    if filereadable(responseFilePath) && len(apexUtil#grepFile(responseFilePath, 'RESULT=SUCCESS')) > 0
        call apexUtil#info("Config looks OK")
        "exec "view ".fnameescape(responseFilePath)
    else
        call apexUtil#error("At first glance it does not look like your config is correct. Check error messages. On MS Windows also check messages in cmd.exe popup window.")
    endif    
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
		let l:java_command = l:java_command  . " -Dlog.level.root=error "
	endif
    if l:java_command !~ "-Dfile.encoding"
        " force UTF-8 encoding if user did not set an alternative explicitly
		let l:java_command = l:java_command  . " -Dfile.encoding=UTF-8 "
    endif    
	let l:java_command = l:java_command  . " -jar " . fnameescape(g:apex_tooling_force_dot_com_path)
    return l:java_command
endfunction


"=========================================================================
" now includes Compatibility layer for Vim/Neovim
" https://neovim.io/doc/user/job_control.html
" https://neovim.io/doc/user/vimfn.html#sockconnect()
"=========================================================================

" Store channel data buffers for Neovim (since it sends data in chunks)
let s:nvim_buffers = {}

" Wrapper for channel/socket opening
function! s:channelOpen(address, options)

    if s:isNvim()
        let l:nvim_opts = {}
        
        " Convert Vim callback to Neovim on_data callback
        if has_key(a:options, 'callback')
            let l:Callback = get(a:options, 'callback')
            let l:nvim_opts.on_data = function('s:nvimOnData', [l:Callback])
        endif
        
        " Handle close callback
        if has_key(a:options, 'close_cb')
            let l:CloseCb = get(a:options, 'close_cb')
            let l:nvim_opts.on_close = function('s:nvimOnClose', [l:CloseCb])
        endif
        
        " sockconnect accepts address in host:port format directly
        let l:chan_id = sockconnect('tcp', a:address, l:nvim_opts)
        let s:nvim_buffers[l:chan_id] = ''
        return l:chan_id
    else
        " Vim implementation
        return ch_open(a:address, a:options)
    endif
endfunction

" Neovim callback adapter for data reception
function! s:nvimOnData(Vim_callback, chan_id, data, event) abort

    " Neovim sends data as list of lines
    " Buffer incomplete lines until we get a complete message
    if [''] == a:data
        " single-item list [''] indicates EOF (stream closed)
        call a:Vim_callback(a:chan_id)
        return
    endif
    
    " TODO - test code below (e.g. using omni completion)
    " echomsg " s:nvimOnData: data=" . string(a:data) . "; event=" . a:event
    if !has_key(s:nvim_buffers, a:chan_id)
        let s:nvim_buffers[a:chan_id] = ''
    endif
    
    " Join all data chunks
    let l:text = join(a:data, "\n")
    let s:nvim_buffers[a:chan_id] .= l:text
    
    " Process complete lines (mode: "nl" equivalent)
    let l:lines = split(s:nvim_buffers[a:chan_id], "\n", 1)
    
    " Keep last incomplete line in buffer
    if s:nvim_buffers[a:chan_id] !~ "\n$"
        let s:nvim_buffers[a:chan_id] = l:lines[-1]
        let l:lines = l:lines[0:-2]
    else
        let s:nvim_buffers[a:chan_id] = ''
    endif
    
    " Call Vim-style callback for each complete line
    for l:line in l:lines
        if !empty(l:line)
            call a:Vim_callback(a:chan_id, l:line)
        endif
    endfor
endfunction

" Neovim callback adapter for channel close
" TODO - is this ever happening?
function! s:nvimOnClose(Vim_callback, chan_id) abort
    throw "inside s:nvimOnClose"
    call apexMessages#log("\n  s:nvimOnClose: chan_id:". a:chan_id . "; Vim_callback: ". string(a:Vim_callback) )
    call apexMessages#log("Vim_callback: " . string(a:Vim_callback))

    " Clean up buffer
    if has_key(s:nvim_buffers, a:chan_id)
        unlet s:nvim_buffers[a:chan_id]
    endif
    
    " Call Vim-style close callback (with just channel)
    call a:Vim_callback(a:chan_id)
endfunction

" Wrapper for sending data
function! s:channelSend(channel, data)
    if s:isNvim()
        call chansend(a:channel, a:data)
    else
        call ch_sendraw(a:channel, a:data)
    endif
endfunction

" Wrapper for closing channel
function! s:channelClose(channel)
    if s:isNvim()
        try
            call chanclose(a:channel)
        catch
            " ignore errors
        endtry
        " Clean up buffer
        if has_key(s:nvim_buffers, a:channel)
            unlet s:nvim_buffers[a:channel]
        endif
    else
        try
            call ch_close(a:channel)
        catch
            " ignore errors
        endtry
    endif
endfunction

" Wrapper for synchronous eval (blocking read)
" Note: This is tricky in Neovim - we need to implement blocking behavior
function! s:channelEvalRaw(channel, data)
    if s:isNvim()
        " Neovim doesn't have ch_evalraw, need to simulate with send + wait
        " For ping/pong type commands, send and wait for response
        call chansend(a:channel, a:data)
        
        " Give it time to respond
        sleep 200m
        
        " Try to get response from buffer
        let l:result = get(s:nvim_buffers, a:channel, '')
        return l:result
    else
        return ch_evalraw(a:channel, a:data)
    endif
endfunction

" Wrapper for job start
function! s:jobStart(command, options)
    if s:isNvim()
        let l:nvim_opts = {}
        
        " Convert Vim callback to Neovim on_stdout/on_stderr
        if has_key(a:options, 'callback')
            let l:Callback = a:options.callback
            let l:nvim_opts.on_stdout = function('s:nvimJobCallback', [l:Callback])
            let l:nvim_opts.on_stderr = function('s:nvimJobCallback', [l:Callback])
        endif
        
        " Note: Neovim doesn't have direct equivalent to "stoponexit"
        " Jobs are killed when Neovim exits by default
        
        return jobstart(a:command, l:nvim_opts)
    else
        return job_start(a:command, a:options)
    endif
endfunction

" Neovim job callback adapter
function! s:nvimJobCallback(Vim_callback, job_id, data, event) abort
    " Neovim passes data as list of lines
    " Call Vim-style callback for each line
    for l:line in a:data
        if !empty(l:line)
            " Vim callback signature: callback(channel, message)
            " For jobs, we use job_id as "channel"
            call a:Vim_callback(a:job_id, l:line)
        endif
    endfor
endfunction

"=========================================================================

