" This file is part of vim-force.com plugin
"   https://github.com/neowit/vim-force.com
" File: apexTooling.vim
" Author: Andrey Gavrikov 
" Maintainers: 
"
" main actions calling tooling-force.com command line executable using vim
" async job
"
if exists("g:loaded_apexToolingAsync") || &compatible
  finish
endif
"let g:loaded_apexToolingAsync = 1

let s:SESSION_FOLDER = ".vim-force.com"

let s:show_log_hint = 1 " first time log is available tell user about that
" check that required global variables are defined
let s:requiredVariables = ["g:apex_tooling_force_dot_com_path"]
for varName in s:requiredVariables
	if !exists(varName)
		echoerr "Please define ".varName." See :help force.com-settings"
	endif
endfor	

"let s:MAKE_MODES = ['open', 'modified', 'confirm', 'all', 'staged', 'onefile'] "supported Deploy modes
let s:MAKE_MODES = ['Modified', 'ModifiedDestructive', 'All', 'AllDestructive', 'Open', 'Staged', 'One'] "supported Deploy modes

function! s:isNeedConflictCheck()
	let doCheck = 1
	if exists("g:apex_conflict_check")
		let isNumber = (0 == type(g:apex_conflict_check))
		if isNumber " g:apex_conflict_check is defined and it is a number
			let doCheck = 0 != g:apex_conflict_check
		endif	
	endif
	return doCheck
endfunction


function! s:genericCallback(resultMap)
    "echomsg "extraParams.callbackFuncRef: " . string(a:resultMap)
    if "true" == a:resultMap["success"]
        let l:responseFilePath = a:resultMap["responseFilePath"]
        let l:projectPath = a:resultMap["projectPath"]
        " check if we have messages
        "let l:msgCount = apexMessages#process(l:responseFilePath, l:projectPath, [], "N")
    endif
    "redraw " refresh buffer, just in case if it is :ApexMessage buffer
endfunction    

"Args:
"Param: action:
"			'deploy' - use metadata api
"			'save' - use tooling api
"Param: mode:
"			'Modified' - all changed files
"			'ModifiedDestructive' - all changed files
"			'Open' - deploy only files from currently open Tabs or Buffers (if
"					less than 2 tabs open)
"			'Confirm' - TODO - all changed files with confirmation for every file
"			'All' - all files under ./src folder
"			'AllDestructive' - all files under ./src folder
"			'Staged' - all files listed in stage-list.txt file
"			'One' - single file from current buffer
"Param: bang - if 1 then skip conflicts check with remote
"Param1: subMode: (optional), allowed values:
"			'deploy' (default) - normal deployment
"			'checkOnly' - dry-run deployment or tests
"Param2: orgName:(optional) if provided then given project name will be used as
"						target Org name.
"						must match one of .properties file with	login details
function apexToolingAsync#deploy(action, mode, bang, ...)
	let filePath = expand("%:p")
	let l:mode = len(a:mode) < 1 ? 'Modified' : a:mode

	if "ModifiedDestructive" == l:mode && apexUtil#input("If there are any files removed locally then they will be deleted from SFDC as well. No backup will be made. Are you sure? [y/N]? ", "YynN", "N") !=? 'y'
		redraw! " clear prompt from command line area
		return
	endif

	if "AllDestructive" == l:mode && apexUtil#input("DANGER!\nAny files that you do not have locally will be removed from Remote.".
                \ "\nRun :ApexDiffWithRemoteProject to check what will be removed.\nProceed with destruction? [y/N]? ", "YynN", "N") !=? 'y'
		redraw! " clear prompt from command line area
		return
	endif

	let l:subMode = a:0 > 0? a:1 : 'deploy'

	if index(['deploy', 'save'], a:action) < 0
		call apexUtil#error("Unsupported action: " . a:action)
		return
	endif

	if index(s:MAKE_MODES, l:mode) < 0
		call apexUtil#error("Unsupported deployment mode: " . a:1)
		return
	endif
	

	let projectPair = apex#getSFDCProjectPathAndName(filePath)
	let projectPath = projectPair.path
	let projectName = projectPair.name
	if a:0 >1 && len(a:2) > 0
		" if project name is provided via tab completion then spaces in it
		" will be escaped, so have to unescape otherwise funcions like
		" filereadable() do not understand such path name
		let projectName = apexUtil#unescapeFileName(a:2)
	endif

	let l:action = a:action . l:mode
	let l:extraParams = {}
	"checkOnly ?
	if l:subMode == 'checkOnly'
		let l:extraParams["checkOnly"] = "true"
	endif
    if "AllDestructive" == l:mode
		let l:extraParams["typesFileFormat"] = "packageXml"
    endif    
	"ignoreConflicts ?
	if a:bang || !s:isNeedConflictCheck()
		let l:extraParams["ignoreConflicts"] = "true"
	endif

	let funcs = {'Open': 's:deployOpenPrepareParams', 'Staged': 's:deployStagedPrepareParams', 'One': 's:deployOnePrepareParams'}
	if has_key(funcs, l:mode)
		let deployOpenParams = call(funcs[l:mode], [apexOs#removeTrailingPathSeparator(projectPath)])

		if len(deployOpenParams) < 1
			"user cancelled
			return
		endif
		call extend(l:extraParams, deployOpenParams)
		let l:action = a:action . "SpecificFiles"

	endif
	" another org?
	if projectPair.name != projectName
		let l:extraParams["callingAnotherOrg"] = "true"
		"when deploying to another org there is no point in checking conflicts
		"because local metadata is not related to that org
		let l:extraParams["ignoreConflicts"] = "true"
	endif

	let resMap = apexToolingAsync#execute(l:action, projectName, projectPath, l:extraParams, [])

endfunction


"
"list potential conflicts between local and remote
"takes into account only modified files, i.e. files which would be deployed if
":DeployModified command is executed
"Args:
"Param1: path to file which belongs to apex project
function! apexToolingAsync#printConflicts(filePath)
	let projectPair = apex#getSFDCProjectPathAndName(a:filePath)
    " ============ internal callback ================
    let obj = {}
    let obj.callbackFuncRef = function('s:genericCallback')
    " function! obj.callbackFuncRef(resultMap)
    "     echomsg "extraParams.callbackFuncRef: " . string(a:resultMap)
    "     if "true" == a:resultMap["success"]
    "         let l:responseFilePath = a:resultMap["responseFilePath"]
    "         let l:projectPath = a:resultMap["projectPath"]
    "         " check if we have messages
    "         call s:displayMessages(l:responseFilePath, l:projectPath, [], "N")
    "     endif
    " endfunction    
    " ============ END internal callback ================

    let extraParams = obj
	call apexToolingAsync#execute("listConflicts", projectPair.name, projectPair.path, extraParams, [])
endfunction	

" get version of currently installed tooling-force.com
"Args:
"Param1: filePath - path to apex file in current project
function apexToolingAsync#getVersion(filePath)
	let projectPair = apex#getSFDCProjectPathAndName(a:filePath)
    "let obj = {}
    "let obj.callbackFuncRef = function('s:genericCallback')
    let extraParams = {}
	call apexToolingAsync#execute("version", projectPair.name, projectPair.path, extraParams, [])
endfunction


let s:last_coverage_report_file = ''
function! apexToolingAsync#getLastCoverageReportFile()
	return s:last_coverage_report_file
endfunction
"DEBUG ONLY
function! apexToolingAsync#setLastCoverageReportFile(filePath)
	let s:last_coverage_report_file = a:filePath
endfunction

function apexToolingAsync#checkSyntax(filePath, attributeMap)
	let projectPair = apex#getSFDCProjectPathAndName(a:filePath)
	let projectPath = projectPair.path
	let projectName = projectPair.name
	let attributeMap = a:attributeMap

	let l:extraParams = {}
	let l:extraParams["isSilent"] = 1
	" let l:extraParams["line"] = attributeMap["line"]
	" let l:extraParams["column"] = attributeMap["column"]
	let l:extraParams["currentFilePath"] = apexOs#shellescape(a:filePath)
	let l:extraParams["currentFileContentPath"] = apexOs#shellescape(a:filePath)
	let l:extraParams["useLocationList"] = 1 " if there are errors then fill current window 'Location List', instead of Quick Fix

	call apexToolingAsync#execute("checkSyntax", projectName, projectPath, l:extraParams, [])
endfunction

" ==================================================================================================
" this callback is used when no explicit callback method specified by caller
" of apexToolingAsync#execute()
function! s:dummyCallback(msg)
    "echo "dummyCallback: " . string(a:msg)
endfunction    

"Returns: dictionary/pair: 
"	{
"	"success": "true" if RESULT=SUCCESS
"	"responseFilePath" : "path to current response/log file"
"	}
"
function! apexToolingAsync#execute(action, projectName, projectPath, extraParams, displayMessageTypes) abort
	let projectPropertiesPath = apexOs#joinPath([g:apex_properties_folder, a:projectName]) . ".properties"

	if has_key(a:extraParams, "ignoreConflicts")
		call apexUtil#warning("skipping conflict check with remote")
	endif

	let l:command = " --action=" . a:action
	if exists("g:apex_temp_folder")
		let l:command = l:command  . " --tempFolderPath=" . apexOs#shellescape(apexOs#removeTrailingPathSeparator(g:apex_temp_folder))
	endif
	let l:command = l:command  . " --config=" . apexOs#shellescape(projectPropertiesPath)
	let l:command = l:command  . " --projectPath=" . apexOs#shellescape(apexOs#removeTrailingPathSeparator(a:projectPath))

	if exists('g:apex_tooling_force_dot_com_extra_params') && len(g:apex_tooling_force_dot_com_extra_params) > 0
		let l:command = l:command  . " " . g:apex_tooling_force_dot_com_extra_params
	endif
	
"	if exists('g:apex_test_logType')
"		let l:command = l:command  . " --logLevel=" . g:apex_test_logType
"	endif
    if exists('g:apex_test_debuggingHeader')
        let tempLogConfigFilePath = apexLogActions#saveTempTraceFlagConfig(g:apex_test_debuggingHeader)
        " let l:extraParams["debuggingHeaderConfig"] = apexOs#shellescape(tempLogConfigFilePath)
        let l:command = l:command  . " --debuggingHeaderConfig=" . apexOs#shellescape(tempLogConfigFilePath)
    endif

	let l:EXCLUDE_KEYS = ["isSilent", "useLocationList", "callbackFuncRef"]
	if len(a:extraParams) > 0
		for key in keys(a:extraParams)
			if index(l:EXCLUDE_KEYS, key) < 0
				let l:command = l:command  . " --" . key . "=" . a:extraParams[key]
			endif
		endfor
	endif

	if has_key(a:extraParams, 'responseFilePath')
		let responseFilePath = a:extraParams["responseFilePath"]
	else
		" default responseFilePath
		let responseFilePath = apexOs#joinPath(a:projectPath, s:SESSION_FOLDER, "response_" . a:action)
		let l:command = l:command  . " --responseFilePath=" . apexOs#shellescape(responseFilePath)
	endif

	" set default maxPollRequests and pollWaitMillis values if not specified
	" by user
	if exists("g:apex_pollWaitMillis")
		let l:command = l:command  . " --pollWaitMillis=" . g:apex_pollWaitMillis
	endif
	if exists("g:apex_maxPollRequests")
		let l:command = l:command  . " --maxPollRequests=" . g:apex_maxPollRequests
	endif
	
	
	let isSilent = 0 " do we need to run command in silent mode?
	if has_key(a:extraParams, "isSilent") && a:extraParams["isSilent"]
		let isSilent = 1
	endif

	" make console output start from new line and do not mix with whatever was
	" previously on the same line
	if !isSilent
		" echo "\n"
	endif
 
	" make sure we do not accidentally re-use old responseFile
	call delete(responseFilePath)

    let l:startTime = reltime()
    " ================= internal callback =========================
    "let obj = {"responseFilePath": responseFilePath, "callbackFuncRef": function('s:dummyCallback')}
    let obj = {"responseFilePath": responseFilePath}
    let obj.projectPath = a:projectPath
    let obj.displayMessageTypes = a:displayMessageTypes
    let obj.extraParams = a:extraParams
    let obj.isSilent = isSilent
    let obj.startTime = l:startTime

    " in case if caller did not provide custom callbackFuncRef let's use
    " generic callback function
    if ( has_key(a:extraParams, "callbackFuncRef") )
        let obj["callbackFuncRef"] = a:extraParams["callbackFuncRef"]
    endif    
    
    function obj.callbackInternal(channel, ...)
        "echomsg "a:0=" . a:0
        if a:0 > 0
            " channel and msg
            " display message = a:2
            "echo a:1
            let l:msg = a:1 
            if !self.isSilent
                call apexMessages#log(l:msg)
            endif
            if len(l:msg) > 0
                echo l:msg
            endif
            return
        elseif 0 == a:0
            " channel only. assume that channel has been closed
        endif    

        " echo 'one=' . self.one. '; two=' . self.two . '; ' . a:msg 
        silent let logFileRes = s:grepValues(self.responseFilePath, "LOG_FILE=")

        if !empty(logFileRes)
            let s:apex_last_log = logFileRes[0]
            if s:show_log_hint
                call apexMessages#logInfo("Log file is available, use :ApexLog to open it")
                let s:show_log_hint = 0
            endif
        else
            if exists("s:apex_last_log")
                unlet s:apex_last_log
            endif    

            "try LOG_FILE_BY_CLASS_NAME map
            let logFileRes = s:grepValues(self.responseFilePath, "LOG_FILE_BY_CLASS_NAME=")

            if !empty(logFileRes)
                let s:apex_last_log_by_class_name = eval(logFileRes[0])
                if s:show_log_hint
                    call apexMessages#logInfo("Log file is available, use :ApexLog to open it")
                    let s:show_log_hint = 0
                endif
            elseif exists("s:apex_last_log_by_class_name")
                unlet s:apex_last_log_by_class_name
            endif    
        endif

        let l:disableMorePrompt = s:hasOnCommandComplete()

        let errCount = s:parseErrorLog(self.responseFilePath, self.projectPath, self.displayMessageTypes, self.isSilent, l:disableMorePrompt, self.extraParams)
        "echo "l:startTime=" . string(l:startTime)
        """temporary disabled"" call s:onCommandComplete(reltime(self.startTime))

        let l:result = {"success": 0 == errCount? "true": "false", "responseFilePath": self.responseFilePath, "projectPath": self.projectPath}
        if ( has_key(self, "callbackFuncRef") )
            call self.callbackFuncRef(l:result)
        endif    
    endfunction    
    " ================= END internal callback =========================

	call s:runCommand(l:command, isSilent, function(obj.callbackInternal))

endfunction


" check if user has defined g:apex_OnCommandComplete
function! s:hasOnCommandComplete()
    return exists('g:apex_OnCommandComplete') && type({}) == type(g:apex_OnCommandComplete)
endfunction

" if user defined custom function to run on command complete then run it
function! s:onCommandComplete(timeElapsed)
    if s:hasOnCommandComplete()
        let l:command = g:apex_OnCommandComplete['script']
        if len(l:command) > 0
            let l:flags = 's' " silent
            "echo "a:timeElapsed=" . string(a:timeElapsed)
            if has_key(g:apex_OnCommandComplete, 'timeoutSec')
                if a:timeElapsed[0] > str2nr(g:apex_OnCommandComplete['timeoutSec'])
                    call apexOs#exe(l:command, l:flags)
                endif
            else
                call apexOs#exe(l:command, l:flags)
            endif
        endif
            
    endif
endfunction

" parses result file and displays errors (if any) in quickfix window
" returns: 
" 0 - if RESULT=SUCCESS
" any value > 0 - if RESULT <> SUCCESS
function! s:parseErrorLog(logFilePath, projectPath, displayMessageTypes, isSilent, disableMorePrompt, extraParams)
    
    let l:useLocationList = 0
    if has_key(a:extraParams, "useLocationList")
        let l:useLocationList = 1 == a:extraParams["useLocationList"]
    endif

    if l:useLocationList
        "clear location list
        call setloclist(0, []) " set location list of current window, hence 0
        lclose
    else
        "clear quickfix
        call setqflist([])
        call CloseEmptyQuickfixes()
    endif    

	"temporarily disable more if enabled
	"also see :help hit-enter
	let disableMore = a:disableMorePrompt
	let reEnableMore = 0
	if disableMore
		let reEnableMore = &more
		set nomore
	endif

	let fileName = a:logFilePath
	if bufexists(fileName)
		" kill buffer with ant log file, otherwise vimgrep uses its buffer instead
		" updated file
		try
			exe "bdelete! ".fnameescape(fileName)
		catch /^Vim\%((\a\+)\)\=:E94/
			" ignore
		endtry	 	
	endif	

	if len(apexUtil#grepFile(fileName, 'RESULT=SUCCESS')) > 0
		" check if we have messages
        let messageCount = apexMessages#process(a:logFilePath, a:projectPath, a:displayMessageTypes)
		if messageCount < 1 && !a:isSilent
			call apexMessages#logInfo("No errors found")
            sleep 500m " give message a chance to be noticed by user
        elseif !a:isSilent 
            " only open message buffer if there was more than 1 message
            if messageCount > 1
                call apexMessages#open()
            else
                sleep 500m " give message a chance to be noticed by user
            endif
		endif
		return 0
	endif
   
    call apexMessages#logError("Operation failed")
    " check if we have failure messages
    if apexMessages#process(a:logFilePath, a:projectPath, a:displayMessageTypes) > 0 && !a:isSilent
        call apexMessages#open()
    endif    
	
    let l:currentBufWinNum = bufwinnr("%")
	call s:fillQuickfix(a:logFilePath, a:projectPath, l:useLocationList)
    if a:isSilent && l:currentBufWinNum >=0 && l:currentBufWinNum != bufwinnr("%")
        " return focus to original buffer
        exe l:currentBufWinNum . "wincmd w"
    endif
    
	return 1

endfunction

" Process Compile and Unit Test errors and populate quickfix
"
" http://vim.1045645.n5.nabble.com/execute-command-in-vim-grep-results-td3236900.html
" http://vim.wikia.com/wiki/Automatically_sort_Quickfix_list
" 
" Param: logFilePath - full path to the response file
" Param: projectPath - full path to the project folder which contains
"		package.xml and 'src'
function! s:fillQuickfix(logFilePath, projectPath, useLocationList)
	" error is reported like so
	" ERROR: {"line" : 3, "column" : 10, "filePath" : "src/classes/A_Fake_Class.cls", "text" : "Invalid identifier: test22."}
	let l:lines = apexUtil#grepFile(a:logFilePath, '^ERROR: ')
	let l:errorList = []

	let index = 0
	while index < len(l:lines)
		let line = substitute(l:lines[index], 'ERROR: ', "", "")
		let err = eval(line)
		let errLine = {}
		if has_key(err, "line")
			let errLine.lnum = err["line"]
		endif
		if has_key(err, "column")
			let errLine.col = err["column"] 
		endif
		if has_key(err, "text")
			let errLine.text = err["text"]
		endif
		if has_key(err, "filePath") && len(err["filePath"]) > 0
			let errLine.filename = apexOs#joinPath(a:projectPath, err["filePath"])
		endif

		call add(l:errorList, errLine)
		let index = index + 1
	endwhile

    if 1 == a:useLocationList
        call setloclist(0, l:errorList) " set location list of current window, hence 0
    else
        call setqflist(l:errorList)
    endif    

	if len(l:errorList) > 0
		if a:useLocationList
            lopen 
        else    
            copen
        endif    
	endif
    
    return len(l:errorList) 
endfunction	

" similar apexUtil#grepFile() function s:grepValues()
" greps all lines starting with given prefix
" and returns list of values on the right side of the prefix
" Example:
" source file: 
" MODIFIED_FILE=file1.txt
" MODIFIED_FILE=file1.txt
" result: 
" ['file1.txt', 'file1.txt']
"
function! s:grepValues(filePath, prefix)
	let l:lines = apexUtil#grepFile(a:filePath, '^' . a:prefix)
	let l:index = 0
	let l:resultLines = []
	while l:index < len(l:lines)
		let l:line = substitute(l:lines[l:index], a:prefix, "", "")
		call add(l:resultLines, l:line)
		let l:index = l:index + 1
	endwhile

	return l:resultLines
endfunction

"================= server mode commands ==========================
function! s:runCommand(commandLine, isSilent, callbackFuncRef)
	let isServerEnabled = apexUtil#getOrElse("g:apex_server", 0) > 0
	if !isServerEnabled
		"server not enabled
        call apexUtil#error('Async mode does not support non server mode. add  ":let g:apex_server = 1" to .vimrc')
		return 0
    endif    
	let l:flags = 'M' "disable --more--
	if a:isSilent
		let l:flags .= 's' " silent
	endif

    let l:java_command = s:getJavaCommand()

	if isServerEnabled 
        call s:execAsync(a:commandLine, a:callbackFuncRef)
	else
		let l:command = l:java_command . a:commandLine
		call apexOs#exe(l:command, l:flags)
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
		let l:java_command = l:java_command  . " -Dorg.apache.commons.logging.simplelog.showlogname=false "
		let l:java_command = l:java_command  . " -Dorg.apache.commons.logging.simplelog.showShortLogname=false "
		let l:java_command = l:java_command  . " -Dorg.apache.commons.logging.simplelog.defaultlog=info "
	endif
	let l:java_command = l:java_command  . " -jar " . fnameescape(g:apex_tooling_force_dot_com_path)

    return l:java_command

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

function! s:execAsync(command, callbackFuncRef)
    call ch_logfile('/Users/andrey/temp/vim/_job-test/channel.log', 'w')

    let l:reEnableMore = &more
    "set nomore
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
            break
        catch /^Vim\%((\a\+)\)\=:E906/
            "echom 'server not started: ' v:exception
            echo "Starting server..."
            call s:startServer()
            sleep 1000m
        catch /.*/
            call apexUtil#error("Failed to execute command. " . v:exception)
            break
        endtry    
    endwhile
endfunction    

function! s:startServer()
    call ch_logfile('/Users/andrey/temp/vim/_job-test/channel-startServer.log', 'w')


    let obj = {}
    
    function obj.callback(channel, msg)
        "echomsg "callback: msg=" . a:msg
        if a:msg =~ "Error"
            call apexUtil#error("Failed to start server: " . a:msg)
        elseif a:msg =~ "Awaiting connection"    
            call ch_close(a:channel)
        endif    

    endfunction    
    
    let l:java_command = s:getJavaCommand()
    let l:command = l:java_command . " --action=serverStart --port=" . s:getServerPort() . " --timeoutSec=" . s:getServerTimeoutSec()
    "echom "l:command=" . l:command
    let job = job_start(l:command, {"callback": obj.callback})
    
endfunction    
