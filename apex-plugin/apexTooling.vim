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
	let resMap = apexTooling#execute("refresh", projectPair.name, projectPair.path, {})
	let logFilePath = resMap["responseFilePath"]
	" check if SFDC client reported modified files
	let modifiedFiles = s:grepValues(logFilePath, "MODIFIED_FILE=")
	if len(modifiedFiles) > 0
		" modified files detected, record them
		echohl WarningMsg
		let response = input('Are you sure you want to lose local changes [y/N]? ')
		echohl None 
		if 'y' !=? response
			return 
		endif
		" force refresh
		let resMap = apexTooling#execute("refresh", projectPair.name, projectPair.path, {"skipModifiedFilesCheck":"true"})
		if "true" == resMap["success"]
			" backup files
			"if len(modifiedFiles) > 0
			"	call s:backupFiles(projectPair.name, projectPair.path, modifiedFiles)
			"endif

			" copy files from temp folder into project folder
			let logFilePath = resMap["responseFilePath"]
			let l:lines = s:grepValues(logFilePath, "RESULT_FOLDER=")
			if len(l:lines) > 0
				let resultFolder = apexOs#removeTrailingPathSeparator(l:lines[0])
				let resultFolderPathLen = len(resultFolder)

				let l:files = apexOs#glob(resultFolder . "/**/*")

				" backup all files we are about to overwrite
				let relativePathsOfFilesToBeOverwritten = []
				for path in l:files
					if !isdirectory(path)
						let relativePath = strpart(path, resultFolderPathLen)
						let relativePath = substitute(relativePath, "^/unpackaged/", "src/", "")
						call add(relativePathsOfFilesToBeOverwritten, relativePath)
					endif

				endfor
				if len(relativePathsOfFilesToBeOverwritten) > 0
					call s:backupFiles(projectPair.name, projectPair.path, relativePathsOfFilesToBeOverwritten)
				endif

				" finally move files from temp dir into project dir
				for sourcePath in l:files
					if !isdirectory(sourcePath)
						let relativePath = strpart(sourcePath, resultFolderPathLen)
						let relativePath = substitute(relativePath, "^/unpackaged/", "src/", "")
						let destinationPath = apexOs#joinPath([projectPair.path, relativePath])
						"echo "FROM= " .sourcePath
						"echo "TO= " .destinationPath
						call apexOs#copyFile(sourcePath, destinationPath)
					endif
				endfor
			endif
		endif
	endif
endfunction	

"list potential conflicts between local and remote
"Args:
"Param1: path to file which belongs to apex project
function apexTooling#listConflicts(filePath)
	let projectPair = apex#getSFDCProjectPathAndName(a:filePath)
	call apexTooling#execute("listConflicts", projectPair.name, projectPair.path, {})
endfunction	

" Backup files using provided relative paths
" all file paths are relative to projectPath
function! s:backupFiles(projectName, projectPath, filePaths)
	let timeStr = strftime(g:apex_backup_folder_time_format)	
	let backupDir = apexOs#joinPath([apexOs#getBackupFolder(), a:projectName, timeStr])
	if !isdirectory(backupDir)
		call mkdir(backupDir, "p")
	endif	
	for relativePath in a:filePaths
		let fullPath = apexOs#joinPath(a:projectPath, relativePath)
		let destinationPath = apexOs#joinPath([backupDir, relativePath])

		let destinationDirPath = apexOs#splitPath(destinationPath).head
		if !isdirectory(destinationDirPath)
			call mkdir(destinationDirPath, "p")
		endif
		call apexOs#copyFile(fullPath, destinationPath)
	endfor

endfunction

" parses result file and displays errors (if any) in quickfix window
" returns: 
" 0 - if RESULT=SUCCESS
" any value > 0 - if RESULT <> SUCCESS
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
	return 1

endfunction

"Returns: number of messages displayed
function! s:displayMessages(logFilePath, projectPath)
	let prefix = 'MESSAGE: '
	let l:lines = s:grepFile(a:logFilePath, prefix)
	let l:index = 0
	while l:index < len(l:lines)
		let line = substitute(l:lines[l:index], prefix, "", "")
		let message = eval(line)
		let msgType = has_key(message, "type")? message["type"] : "INFO"
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
		call s:displayMessageDetails(a:logFilePath, a:projectPath, message)
		let l:index = l:index + 1
	endwhile
	if l:index > 0
		" blank line before next message
		echo ""
	endif	
	return l:index
endfunction

" using Id of specific message check if log file has details and display if
" details found
function! s:displayMessageDetails(logFilePath, projectPath, message)
	let prefix = 'MESSAGE DETAIL: '
	let l:lines = s:grepFile(a:logFilePath, prefix)
	let l:index = 0
	while l:index < len(l:lines)
		let line = substitute(l:lines[l:index], prefix, "", "")
		let detail = eval(line)
		if detail["messageId"] == a:message["id"]
			let text = "  " . detail["text"]
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
		endif
		let l:index = l:index + 1
	endwhile
	return l:index
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
		"get lines from quickfix
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

" similar s:grepFile() function s:grepValues()
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
	let l:lines = s:grepFile(a:filePath, a:prefix)
	let l:index = 0
	let l:resultLines = []
	while l:index < len(l:lines)
		let l:line = substitute(l:lines[l:index], a:prefix, "", "")
		call add(l:resultLines, l:line)
		let l:index = l:index + 1
	endwhile

	return l:resultLines
endfunction

"Returns: dictionary/pair: 
"	{
"	"success": "true" if RESULT=SUCCESS
"	"responseFilePath" : "path to current response/log file"
"	}
"
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

	let errCount = s:parseErrorLog(responseFilePath, a:projectPath)
	return {"success": 0 == errCount? "true": "false", "responseFilePath": responseFilePath}

endfunction

command! -nargs=* -complete=customlist,apex#completeDeployParams ADeployModified :call apexTooling#deploy('Modified', <f-args>)
command! -nargs=0 ARefreshProject :call apexTooling#refreshProject(expand("%:p"))

command! APrintChanged :call apexTooling#printChangedFiles(expand("%:p"))
command! AListConflicts :call apexTooling#listConflicts(expand("%:p"))

