" File: apexTooling.vim
" Author: Andrey Gavrikov 
" Version: 1.0
" Last Modified: 2014-01-17
" Copyright: Copyright (C) 2010-2014 Andrey Gavrikov
"            Permission is hereby granted to use and distribute this code,
"            with or without modifications, provided that this copyright
"            notice is copied with it. Like anything else that's free,
"            this plugin is provided *as is* and comes with no warranty of any
"            kind, either expressed or implied. In no event will the copyright
"            holder be liable for any damages resulting from the use of this
"            software.
"
" main actions calling tooling-force.com command line executable
" Part of vim/force.com plugin
"
"
if exists("g:loaded_apexTooling") || &compatible
  finish
endif
let g:loaded_apexTooling = 1


" check that required global variables are defined
let s:requiredVariables = ["g:apex_tooling_force_dot_com_path"]
for varName in s:requiredVariables
	if !exists(varName)
		echoerr "Please define ".varName." See :help force.com-settings"
	endif
endfor	

"let s:MAKE_MODES = ['open', 'modified', 'confirm', 'all', 'staged', 'onefile'] "supported Deploy modes
let s:MAKE_MODES = ['Modified'] "supported Deploy modes

"Args:
"Param1: mode:
"			'Modified' - all changed files
"			'Open' - deploy only files from currently open Tabs or Buffers (if
"					less than 2 tabs open)
"			'Confirm' - all changed files with confirmation for every file
"			'All' - all files under ./src folder
"			'Staged' - all files listed in stage-list.txt file
"			'Onefile' - single file specified in param 1
"Param2: subMode: (optional), allowed values:
"			'deploy' (default) - normal deployment
"			'checkOnly' - dry-run deployment or tests
"Param3: orgName:(optional) if provided then given project name will be used as
"						target Org name.
"						must match one of .properties file with	login details
function apexTooling#deploy(...)
	let filePath = expand("%:p")
	let l:mode = a:0 > 0? a:1 : 'Modified'
	let l:subMode = a:0 > 1? a:2 : 'deploy'

	if index(s:MAKE_MODES, l:mode) < 0
		call apexUtil#error("Unsupported deployment mode: " . a:1)
		return
	endif
	

	let projectPair = apex#getSFDCProjectPathAndName(filePath)
	let projectPath = projectPair.path
	let projectName = projectPair.name
	if a:0 >2
		" if project name is provided via tab completion then spaces in it
		" will be escaped, so have to unescape otherwise funcions like
		" filereadable() do not understand such path name
		let projectName = apexUtil#unescapeFileName(a:3)
	endif

	let l:action = "deploy" . l:mode
	let l:extraParams = {}
	"checkOnly ?
	if l:subMode == 'checkOnly'
		let l:extraParams["checkOnly"] = "true"
	endif
	" another org?
	if projectPair.name != projectName
		let l:extraParams["callingAnotherOrg"] = "true"
	endif

	call apexTooling#execute(l:action, projectName, projectPath, l:extraParams)

endfunction

"run unit tests
"Args:
"filePath:  path to file which belongs to apex project
"Param1: - mode
"			'checkOnly' - dry-run deployment or tests
"			'testAndDeploy' - deploy if tests successful
"							only relevant when mode:"test"
"
"Param2: - className: (optional) - if provided then only run tests in the specified class
"
"Param3: - methodName:(optional) - if provided then only run specified method in the class
"
"Param4: - orgName:(optional) if provided then given project name will be used as
"						target Org name.
"						must match one of .properties file with	login details
function s:runTest(...)
endfunction

"Args:
"Param1: path to file which belongs to apex project
function apexTooling#printChangedFiles(filePath)
	let projectPair = apex#getSFDCProjectPathAndName(a:filePath)
	call apexTooling#execute("listModified", projectPair.name, projectPair.path, {})
endfunction	

"Args:
"Param1: path to file which belongs to apex project
function apexTooling#refreshProject(filePath)
	let projectPair = apex#getSFDCProjectPathAndName(a:filePath)
	" first check if there are locally modified files
	call apexTooling#execute("listModified", projectPair.name, projectPair.path, {})
	
	call apexTooling#execute("refresh", projectPair.name, projectPair.path, {})
endfunction	

"list potential conflicts between local and remote
"Args:
"Param1: path to file which belongs to apex project
function apexTooling#listConflicts(filePath)
	let projectPair = apex#getSFDCProjectPathAndName(a:filePath)
	call apexTooling#execute("listConflicts", projectPair.name, projectPair.path, {})
endfunction	

" parses result file and
" displays errors (if any) in quickfix window
" returns 
" 0 - no errors found
" value > 0 - number of errors found
function! s:parseErrorLog(logFilePath, projectPath)
	"clear quickfix
	call setqflist([])
	call CloseEmptyQuickfixes()

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
		if s:displayMessages(a:logFilePath, a:projectPath) < 1
			call apexUtil#info("No errors found")
		endif
		return 0
	endif

	call apexUtil#error("Operation failed")
	" check if we have messages
	call s:displayMessages(a:logFilePath, a:projectPath)
	
	call s:fillQuickfix(a:logFilePath, a:projectPath)

endfunction

"Returns: number of messages displayed
function! s:displayMessages(logFilePath, projectPath)
	let prefix = 'MESSAGE: '
	let l:lines = s:grepFile(a:logFilePath, prefix)
	let index = 0
	while index < len(l:lines)
		let line = substitute(l:lines[index], prefix, "", "")
		let message = eval(line)
		let msgType = has_key(message, "type")? message.type : "info"
		let text = message.text
		if "error" == msgType
			call apexUtil#error(text)
		elseif "warning" == msgType
			call apexUtil#warning(text)
		else
			call apexUtil#info(text)
		endif
		call s:displayMessageDetails(a:logFilePath, a:projectPath, message)
		let index = index + 1
	endwhile
	if index > 0
		" blank line before next message
		echo ""
	endif	
	return index
endfunction

" using Id of specific message check if log file has details and display if
" details found
function! s:displayMessageDetails(logFilePath, projectPath, message)
	let prefix = 'MESSAGE DETAIL: '
	let l:lines = s:grepFile(a:logFilePath, prefix)
	let index = 0
	while index < len(l:lines)
		let line = substitute(l:lines[index], prefix, "", "")
		let detail = eval(line)
		if detail["messageId"] == a:message["id"]
			let text = "  " . detail.text
			let msgType = has_key(detail, "type")? detail.type : a:message.type
			if "error" == msgType
				call apexUtil#error(text)
			elseif "warning" == msgType
				call apexUtil#warning(text)
			else
				call apexUtil#info(text)
			endif
		endif
		let index = index + 1
	endwhile
	return index
endfunction

" Process Compile and Unit Test errors and populate quickfix
"
" http://vim.1045645.n5.nabble.com/execute-command-in-vim-grep-results-td3236900.html
" http://vim.wikia.com/wiki/Automatically_sort_Quickfix_list
" 
" Param: logFilePath - full path to the response file
" Param: projectPath - full path to the project folder which contains
"		package.xml and 'src'
function! s:fillQuickfix(logFilePath, projectPath)
	" error is reported like so
	" ERROR: {"line" : 3, "column" : 10, "filePath" : "src/classes/A_Fake_Class.cls", "text" : "Invalid identifier: test22."}
	let l:lines = s:grepFile(a:logFilePath, 'ERROR: ')
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
		if has_key(err, "filePath")
			let errLine.filename = apexOs#joinPath(a:projectPath, err["filePath"])
		endif

		call add(l:errorList, errLine)
		let index = index + 1
	endwhile

	call setqflist(l:errorList)
	if len(l:errorList) > 0
		copen
	endif
endfunction	

" grep file and return found lines
function! s:grepFile(filePath, expr)
	let currentQuickFix = getqflist()
	let res = []
	
	try
		let exprStr =  "noautocmd vimgrep /\\c".a:expr."/j ".fnameescape(a:filePath)
		exe exprStr
		"expression found
		"get line numbers from quickfix
		for qfLine in getqflist()
			call add(res, qfLine.text)
		endfor	
		
	"catch  /^Vim\%((\a\+)\)\=:E480/
	catch  /.*/
		"echomsg "expression NOT found" 
	endtry
	
	" restore quickfix
	call setqflist(currentQuickFix)
	
	return res
endfunction


function! apexTooling#execute(action, projectName, projectPath, extraParams)
	let projectPropertiesPath = apexOs#joinPath([g:apex_properties_folder, a:projectName]) . ".properties"
	let responseFilePath = apexOs#joinPath(a:projectPath, ".vim-force.com", "response_" . a:action)

	let l:command = "java "
	let l:command = l:command  . " -Dorg.apache.commons.logging.simplelog.showlogname=false "
	let l:command = l:command  . " -Dorg.apache.commons.logging.simplelog.showShortLogname=false "
	let l:command = l:command  . " -jar " . g:apex_tooling_force_dot_com_path
	let l:command = l:command  . " --action=" . a:action
	let l:command = l:command  . " --tempFolderPath=" . shellescape(g:apex_temp_folder)
	let l:command = l:command  . " --config=" . shellescape(projectPropertiesPath)
	let l:command = l:command  . " --projectPath=" . shellescape(a:projectPath)
	let l:command = l:command  . " --responseFilePath=" . shellescape(responseFilePath)

	if len(a:extraParams) > 0
		for key in keys(a:extraParams)
			let l:command = l:command  . " --" . key . "=" . a:extraParams[key]
		endfor
	endif
	
	call apexOs#exe(l:command, 'M') "disable --more--

	call s:parseErrorLog(responseFilePath, a:projectPath)

endfunction

command! -nargs=* -complete=customlist,apex#completeDeployParams ADeployModified :call apexTooling#deploy('Modified', <f-args>)
command! -nargs=0 ARefreshProject :call apexTooling#refreshProject(expand("%:p"))

command! APrintChanged :call apexTooling#printChangedFiles(expand("%:p"))
command! AListConflicts :call apexTooling#listConflicts(expand("%:p"))

