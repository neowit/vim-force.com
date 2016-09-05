" This file is part of vim-force.com plugin
"   https://github.com/neowit/vim-force.com
" File: apexTooling.vim
" Last Modified: 2014-02-08
" Author: Andrey Gavrikov 
" Maintainers: 
"
" main actions calling tooling-force.com command line executable
"
if exists("g:loaded_apexTooling") || &compatible
  finish
endif
let g:loaded_apexTooling = 1

let s:SESSION_FOLDER = ".vim-force.com"

let s:show_log_hint = 1 " first time log is available tell user about that
" check that required global variables are defined
let s:requiredVariables = ["g:apex_tooling_force_dot_com_path"]
for varName in s:requiredVariables
	if !exists(varName)
		echoerr "Please define ".varName." See :help force.com-settings"
	endif
endfor	

" retrieve available code completion options
"Args:
"Param: filePath 
"			path to current apex file
"
"Param: attributeMap - map {} of test attributes
"			e.g.: {
"					"line": 10, "column": 7, 
"					"currentFilePath": "/path/to-MyClass.cls", 
"					"currentFileContentPath": "/path/to/temp/file"
"				  }
"
"			line: - current line
"			column: - column where cursor is positioned
"			currentFilePath: full path of current file
"			currentFileContentPath: full path to saved content of current file
"					(when completion is called current version of the file may not be saved yet)
"
"
"Param: orgName - given project name will be used as
"						target Org name.
"						must match one of .properties file with	login details
"
function apexTooling#listCompletions(filePath, attributeMap)
	let projectPair = apex#getSFDCProjectPathAndName(a:filePath)
	let projectPath = projectPair.path
	let projectName = projectPair.name
	let attributeMap = a:attributeMap

	let l:extraParams = {}
	let l:extraParams["isSilent"] = 1
	let l:extraParams["line"] = attributeMap["line"]
	let l:extraParams["column"] = attributeMap["column"]
	let l:extraParams["currentFilePath"] = apexOs#shellescape(a:filePath)
	let l:extraParams["currentFileContentPath"] = apexOs#shellescape(attributeMap["currentFileContentPath"])

    let resMap = apexToolingAsync#executeBlocking("listCompletions", projectName, projectPath, l:extraParams, [])
    "if apexOs#isWindows()
	"    let resMap = apexToolingAsync#executeBlocking("listCompletions", projectName, projectPath, l:extraParams, [])
    "else     
    "    let resMap = apexTooling#execute("listCompletions", projectName, projectPath, l:extraParams, [])
    "endif    
	let responseFilePath = resMap["responseFilePath"]
	return responseFilePath
endfunction


" retrieve list of Test Suite names into specified file
"Args:
"Param1: path to file which belongs to apex project
function apexTooling#loadTestSuiteNamesList(projectName, projectPath, outputFilePath)
    let l:extraParams = {}
    let l:extraParams["testSuiteAction"] = "dumpNames"
    let l:extraParams["dumpToFile"] = apexOs#shellescape(a:outputFilePath)
	call apexToolingAsync#executeBlocking("testSuiteManage", a:projectName, a:projectPath, l:extraParams, [])
endfunction	

function s:reportModifiedFiles(modifiedFiles)
	let modifiedFiles = a:modifiedFiles
	" show first 5
	let index = 0
	for fName in modifiedFiles
		let index += 1
		if index > 5
			call apexUtil#warning("+ " . (len(modifiedFiles) - index) . " more")
			break
		endif
		if fName =~ "package.xml$"
			continue " skip package.xml
		endif

		call apexUtil#warning("    " . fName)
	endfor
endfunction

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
	return apexToolingAsync#executeBlocking("describeMetadata", a:projectName, a:projectPath, {"allMetaTypesFilePath": apexOs#shellescape(a:allMetaTypesFilePath)}, [])
endfunction	

" retrieve members of specified metadata types
"Args:
"Param3: path to file which contains either
"	JSON description of required types, like so
"		{"XMLName": "ApexTrigger", "members": ["*"]}
"		{"XMLName": "ApprovalProcess", "members": ["*"]}
"		{"XMLName": "ApexPage", "members": ["AccountEdit", "ContactEdit"]}
"	OR linear file list, like this
"		objects/My_Object__c
"		classes/A_Fake_Class.cls
"Param4: typesFileFormat - file list format: file-paths|json
"Param5: targetFolder - if not blank then use this as retrieve destination
"
function apexTooling#bulkRetrieve(projectName, projectPath, specificTypesFilePath, typesFileFormat, targetFolder) abort
	let extraParams = {"specificTypes": apexOs#shellescape(a:specificTypesFilePath), "typesFileFormat" : a:typesFileFormat}
	if len(a:targetFolder) > 0
		let extraParams["targetFolder"] = apexOs#shellescape(a:targetFolder)
	endif
	let extraParams["updateSessionDataOnSuccess"] = "true"
	
	let resMap = apexToolingAsync#executeBlocking("bulkRetrieve", a:projectName, a:projectPath, extraParams, [])
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
	let resMap = apexToolingAsync#executeBlocking("listMetadata", a:projectName, a:projectPath, {"specificTypes": apexOs#shellescape(a:specificTypesFilePath)}, [])
	if "true" == resMap["success"]
		let logFilePath = resMap["responseFilePath"]
		let resultFile = s:grepValues(logFilePath, "RESULT_FILE=")
		if len(resultFile) > 0
			let resMap["resultFile"] = resultFile[0]
		endif
	endif
	return resMap
endfunction	

"open scratch file 
"This file can be used for things line ExecuteAnonymous
let s:scratch_project_pair = {}

" if changed file name then update vim-force.com.vim file
let s:SCRATCH_FILE = "vim-force.com-scratch.txt"

function apexTooling#openScratchFile(filePath)
	let srcPath = apex#getApexProjectSrcPath(a:filePath)
	let scratchFilePath = apexOs#joinPath(srcPath, s:SCRATCH_FILE)

	try 
		let projectPair = apex#getSFDCProjectPathAndName(srcPath)
	catch
		call apexUtil#error("failed to determine Apex prject location by file: " + scratchFilePath)
		return
	endtry
	let s:scratch_project_pair = projectPair
	if !filereadable(scratchFilePath) 
		call writefile(["/* This is a scratch file */"], scratchFilePath)
	endif
	:execute "e " . fnameescape(scratchFilePath)

endfunction

" delete members of specified metadata types
"Args:
"Param3: path to file which contains list of required types
"
function apexTooling#deleteMetadata(filePath, projectName, specificComponentsFilePath, mode, updateSessionDataOnSuccess)
	let projectPair = apex#getSFDCProjectPathAndName(a:filePath)
	let l:extraParams = {"specificComponents": apexOs#shellescape(a:specificComponentsFilePath)}
	" another org?
	if projectPair.name != a:projectName
		let l:extraParams["callingAnotherOrg"] = "true"
	endif

	if 'checkOnly' == a:mode
		let l:extraParams["checkOnly"] = "true"
	endif

	if a:updateSessionDataOnSuccess
		let l:extraParams["updateSessionDataOnSuccess"] = 'true'
	endif

	let resMap = apexToolingAsync#executeBlocking("deleteMetadata", a:projectName, projectPair.path, l:extraParams, [])
	return resMap
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
			"when path contains trailing slash vim complains
			let destinationDirPath = apexOs#removeTrailingPathSeparator(destinationDirPath)
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

	if len(apexUtil#grepFile(fileName, 'RESULT=FAILURE')) > 0
        call apexUtil#error("Operation failed")
        " check if we have messages
        call s:displayMessages(a:logFilePath, a:projectPath, a:displayMessageTypes)

        call s:fillQuickfix(a:logFilePath, a:projectPath, l:useLocationList)
        if disableMore && reEnableMore
            set more
        endif
        return 1
    elseif len(apexUtil#grepFile(fileName, 'RESULT=SUCCESS')) > 0
        " check if we have messages
        if s:displayMessages(a:logFilePath, a:projectPath, a:displayMessageTypes) < 1 && !a:isSilent
            call apexUtil#info("No errors found")
        endif
        if disableMore && reEnableMore
            set more
        endif
        return 0
	endif
    return 1 " should never get to here unless there was a crash

endfunction

"Param: displayMessageTypes list of message types to display, other types will
"be ignored, e.g. ['ERROR'] - will display only errors
"Returns: number of messages displayed
function! s:displayMessages(logFilePath, projectPath, displayMessageTypes)
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
		call s:displayMessageDetails(a:logFilePath, a:projectPath, message)
		let l:index += 1
	endfor
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
	let l:lines = apexUtil#grepFile(a:logFilePath, '^' . prefix)
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

" send server 'shutdown' command to stop it
function! apexTooling#serverShutdown()
	"call s:sendCommandToServer("shutdown", "")
    let obj = {}
    function! obj.dummyCallback(...)
    endfunction
	call apexServer#send("shutdown", obj.dummyCallback, {})
endfunction

