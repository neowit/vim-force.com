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


let s:LOG_LEVEL = 'None'
" check that required global variables are defined
let s:requiredVariables = ["g:apex_tooling_force_dot_com_path"]
for varName in s:requiredVariables
	if !exists(varName)
		echoerr "Please define ".varName." See :help force.com-settings"
	endif
endfor	

"let s:MAKE_MODES = ['open', 'modified', 'confirm', 'all', 'staged', 'onefile'] "supported Deploy modes
let s:MAKE_MODES = ['Modified', 'All', 'Open', 'Staged', 'One'] "supported Deploy modes

"Args:
"Param1: mode:
"			'Modified' - all changed files
"			'Open' - deploy only files from currently open Tabs or Buffers (if
"					less than 2 tabs open)
"			'Confirm' - TODO - all changed files with confirmation for every file
"			'All' - all files under ./src folder
"			'Staged' - all files listed in stage-list.txt file
"			'One' - single file from current buffer
"Param2: subMode: (optional), allowed values:
"			'deploy' (default) - normal deployment
"			'checkOnly' - dry-run deployment or tests
"			'deployIgnoreConflicts' - do not run check if remote files has
"			been modified
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
	"ignoreConflicts ?
	if l:subMode == 'deployIgnoreConflicts'
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
		let l:action = "deploySpecificFiles"

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
		" forced refresh when there are modified files
		let resMap = apexTooling#execute("refresh", projectPair.name, projectPair.path, {"skipModifiedFilesCheck":"true"})
	endif

	if "true" == resMap["success"]
		" TODO add a setting so user could chose whether they want
		" backup of all files received in Refresh or only modified ones
		"
		" backup modified files
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

			" backup files we are about to overwrite
			" if they new and old differ in size
			let relativePathsOfFilesToBeOverwritten = []
			let packageXmlDifferent = 0
			for path in l:files
				if !isdirectory(path)
					let relativePath = strpart(path, resultFolderPathLen)
					let relativePath = substitute(relativePath, "^/unpackaged/", "src/", "")
					"check if local file exists adn sizes are different
					let localFilePath = apexOs#joinPath([projectPair.path, relativePath])
					if filereadable(localFilePath)
						let currentSize = getfsize(localFilePath)
						let newSize = getfsize(path)
						if currentSize != newSize
							call add(relativePathsOfFilesToBeOverwritten, relativePath)
							if path =~ "package.xml$"
								let packageXmlDifferent = 1
							endif
						endif
					endif
				endif

			endfor
			if len(relativePathsOfFilesToBeOverwritten) > 0
				let backupDir = s:backupFiles(projectPair.name, projectPair.path, relativePathsOfFilesToBeOverwritten)
				echo "Project files with size different to remote ones have been preserved in: " . backupDir
			endif

			" finally move files from temp dir into project dir
			for sourcePath in l:files
				if !isdirectory(sourcePath)

					let relativePath = strpart(sourcePath, resultFolderPathLen)
					let relativePath = substitute(relativePath, "^/unpackaged/", "src/", "")
					let destinationPath = apexOs#joinPath([projectPair.path, relativePath])
					let overwrite = 1
					if sourcePath =~ "package.xml$" && packageXmlDifferent
						let overwrite = apexUtil#input("Overwrite package.xml [y/N]? ", "YynN", "N") ==? 'y'
					endif
					"echo "FROM= " .sourcePath
					"echo "TO= " .destinationPath
					if sourcePath !~ "package.xml$" || overwrite
						let destinationDirPath = apexOs#splitPath(destinationPath).head
						if !isdirectory(destinationDirPath)
							call mkdir(destinationDirPath, "p")
						endif
						call apexOs#copyFile(sourcePath, destinationPath)
					endif
				endif
			endfor
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
"
"List relative (project root) paths of files in Open buffers
function! apexTooling#listOpenFiles(projectPath)
	let projectPath = apexOs#removeTrailingPathSeparator(a:projectPath)
	let fileList = []
	" collect open buffers, making sure they are inside current project
	let bufferList = apex#getOpenBuffers(projectPath)
	for n in bufferList
		let fullpath = expand('#'.n.':p')
		let relativePath = strpart(fullpath, len(projectPath) + 1) "+1 to remove turn '/src/' into 'src/'
		call add(fileList, relativePath)
	endfor	
	return fileList
endfunction


"load metadata description into a local file
function apexTooling#loadMetadataList(projectName, projectPath, allMetaTypesFilePath)
	return apexTooling#execute("describeMetadata", a:projectName, a:projectPath, {"allMetaTypesFilePath": shellescape(a:allMetaTypesFilePath)})
endfunction	

" retrieve members of specified metadata types
"Args:
"Param3: path to file which contains JSON description of required types
"
function apexTooling#bulkRetrieve(projectName, projectPath, specificTypesFilePath)
	let resMap = apexTooling#execute("bulkRetrieve", a:projectName, a:projectPath, {"specificTypes": shellescape(a:specificTypesFilePath)})
	if "true" == resMap["success"]
		let logFilePath = resMap["responseFilePath"]
		let resultFolder = s:grepValues(logFilePath, "RESULT_FOLDER=")
		"echo "resultFolder=" . resultFolder[0]
		let resMap["resultFolder"] = resultFolder[0]
	endif
	return resMap
endfunction	

"load list of components of specified metadata types into a local file
function apexTooling#listMetadata(projectName, projectPath, specificTypesFilePath)
	let resMap = apexTooling#execute("listMetadata", a:projectName, a:projectPath, {"specificTypes": shellescape(a:specificTypesFilePath)})
	if "true" == resMap["success"]
		let logFilePath = resMap["responseFilePath"]
		let resultFile = s:grepValues(logFilePath, "RESULT_FILE=")
		let resMap["resultFile"] = resultFile[0]
	endif
	return resMap
endfunction	

function! apexTooling#openLastLog()
	if exists("s:apex_last_log")
		:execute "e " . fnameescape(s:apex_last_log)
	else
		call apexUtil#info('No Log file available')
	endif
endfunction

"execute piece of code via executeAnonymous
"How to get visually selected text in VimScript
"http://stackoverflow.com/questions/1533565/how-to-get-visually-selected-text-in-vimscript
"TODO: write function which can accept visual selection or whole buffer and
"can run executeAnonymous on that code
"Args:
"Param1: mode:
"			'selection' - execute selected code snippet
"			'buffer' - execute whole buffer
function apexTooling#executeAnonymous(filePath) range
	let projectPair = apex#getSFDCProjectPathAndName(a:filePath)
	let projectName = projectPair.name
	let projectPath = projectPair.path
	
	let lines = getbufline(bufnr("%"), a:firstline, a:lastline)
	echo lines
	"let lines = []
	"if 'selection' == a:mode
	"	let lines = getbufline(bufnr("%"), "'<", "'>")
	"else 
	"	" default - whole buffer
	"	let lines = getbufline(bufnr("%"), 1, "$")
	"endif
	if !empty(lines)
		let codeFile = tempname()
		call writefile(lines, codeFile)
		call s:executeAnonymous(projectName, projectPath, codeFile)
	endif
endfunction	

function s:executeAnonymous(projectName, projectPath, codeFile)
	call apexTooling#askLogLevel()
	let resMap = apexTooling#execute("executeAnonymous", a:projectName, a:projectPath, {"codeFile": shellescape(a:codeFile)})
	if 'None' != g:apex_test_logType
		:ApexLog
	endif
endfunction	

" ask user which log type to use for running unit tests 
" result is assigned value of g:apex_test_logType variable
function! apexTooling#askLogLevel()
	if exists('g:apex_test_logType')
		let s:LOG_LEVEL = g:apex_test_logType
	endif
	let g:apex_test_logType = apexUtil#menu('Select Log Type', ['None', 'Debugonly', 'Db', 'Profiling', 'Callout', 'Detail'], s:LOG_LEVEL)
endfunction

" Backup files using provided relative paths
" all file paths are relative to projectPath
"Returns: backupDir path
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
	return backupDir

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
	let l:lines = apexUtil#grepFile(a:logFilePath, prefix)
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
	let l:lines = apexUtil#grepFile(a:logFilePath, prefix)
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
	let l:lines = apexUtil#grepFile(a:logFilePath, 'ERROR: ')
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
	let l:lines = apexUtil#grepFile(a:filePath, a:prefix)
	let l:index = 0
	let l:resultLines = []
	while l:index < len(l:lines)
		let l:line = substitute(l:lines[l:index], a:prefix, "", "")
		call add(l:resultLines, l:line)
		let l:index = l:index + 1
	endwhile

	return l:resultLines
endfunction

" prepare file list for "deployOpen"
" and return dictionary with extra command line params for
" apexTooling#execute()
"Returns:
" {"specificFiles": "/path/to/temp/file/with/relative/path/names"}
function! s:deployOpenPrepareParams(projectPath)
	let relativePaths = apexTooling#listOpenFiles(a:projectPath)
	return s:prepareSpecificFilesParams(relativePaths)
endfunction

" prepare file list for "deployStaged"
" and return dictionary with extra command line params for
" apexTooling#execute()
"Returns:
" {"specificFiles": "/path/to/temp/file/with/relative/path/names"}
function! s:deployStagedPrepareParams(projectPath)
	let relativePaths = apexStage#list(a:projectPath)
	" all paths are relative to src/ folder, e.g.
	"[classes/MyClass.cls,  pages/MyPage.page, ...]
	"however we need [aths relative project folder
	"so need to add src/ in front of each file
	if len(relativePaths) > 0
		let relativePaths = map(relativePaths, '"src/" . relativePaths[v:val]')
	else
		call apexUtil#warning('Stage is empty.')
		return {}
	endif	
	return s:prepareSpecificFilesParams(relativePaths)
endfunction

" prepare file list for "deployOne"
" and return dictionary with extra command line params for
" apexTooling#execute()
"Returns:
" {"specificFiles": "/path/to/temp/file/with/relative/path/names"}
function! s:deployOnePrepareParams(projectPath)
	let fullpath = expand('%:p')
	let relativePath = strpart(fullpath, len(a:projectPath) + 1) "+1 to remove turn '/src/' into 'src/'
	return s:prepareSpecificFilesParams([relativePath])
endfunction

"Prepare command line param and file content for 'specificFiles' deployments
"Args:
"Param1: relativePaths - list of files relative project folder
"e.g.:
"[src/classes/MyClass.cls,  src/pages/MyPage.page, ...]
"Returns:
" {"specificFiles": "/path/to/temp/file/with/relative/path/names"}
function! s:prepareSpecificFilesParams(relativePaths)
	let relativePaths = a:relativePaths
	let l:params = {}
	if len(relativePaths) > 0
		call apexUtil#warning('Following files will be deployed')
		for path in relativePaths
			call apexUtil#warning('  ' . path)
		endfor
		if apexUtil#input('Deploy [y/N]? ', 'yYnN', 'N') !=? 'y'
			return {} "user cancelled
		endif
		"dump file list into a temp file
		let tempFile = tempname() . "-fileList.txt"
		call writefile(relativePaths, tempFile)
		let l:params["specificFiles"] = shellescape(tempFile)
	endif
	return l:params
endfunction



"Returns: dictionary/pair: 
"	{
"	"success": "true" if RESULT=SUCCESS
"	"responseFilePath" : "path to current response/log file"
"	}
"
function! apexTooling#execute(action, projectName, projectPath, extraParams)
	let projectPropertiesPath = apexOs#joinPath([g:apex_properties_folder, a:projectName]) . ".properties"

	let l:command = "java "
	let l:command = l:command  . " -Dorg.apache.commons.logging.simplelog.showlogname=false "
	let l:command = l:command  . " -Dorg.apache.commons.logging.simplelog.showShortLogname=false "
	let l:command = l:command  . " -jar " . g:apex_tooling_force_dot_com_path
	let l:command = l:command  . " --action=" . a:action
	let l:command = l:command  . " --tempFolderPath=" . shellescape(g:apex_temp_folder)
	let l:command = l:command  . " --config=" . shellescape(projectPropertiesPath)
	let l:command = l:command  . " --projectPath=" . shellescape(a:projectPath)
	
	if exists('g:apex_test_logType')
		let l:command = l:command  . " --logLevel=" . g:apex_test_logType
	endif

	if len(a:extraParams) > 0
		for key in keys(a:extraParams)
			let l:command = l:command  . " --" . key . "=" . a:extraParams[key]
		endfor
	endif

	if has_key(a:extraParams, 'responseFilePath')
		let responseFilePath = a:extraParams["responseFilePath"]
	else
		" default responseFilePath
		let responseFilePath = apexOs#joinPath(a:projectPath, ".vim-force.com", "response_" . a:action)
		let l:command = l:command  . " --responseFilePath=" . shellescape(responseFilePath)
	endif
	
	call apexOs#exe(l:command, 'M') "disable --more--

	let logFileRes = s:grepValues(responseFilePath, "LOG_FILE=")
	if !empty(logFileRes)
		let s:apex_last_log = logFileRes[0]
	elseif exists("s:apex_last_log")
		unlet s:apex_last_log
	endif
	let errCount = s:parseErrorLog(responseFilePath, a:projectPath)
	return {"success": 0 == errCount? "true": "false", "responseFilePath": responseFilePath}
endfunction

