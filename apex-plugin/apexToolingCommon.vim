" This file is part of vim-force.com plugin
"   https://github.com/neowit/vim-force.com
" File: apexToolingCommon.vim
" Author: Andrey Gavrikov 
" Maintainers: 
"
" main actions calling tooling-force.com command line executable
"
if exists("g:loaded_apexToolingCommon") || &compatible
  finish
endif
let g:loaded_apexToolingCommon = 1


function apexToolingCommon#reportModifiedFiles(modifiedFiles)
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


" Backup files using provided relative paths
" all file paths are relative to projectPath
"Returns: backupDir path
function! apexToolingCommon#backupFiles(projectName, projectPath, filePaths)
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
function! apexToolingCommon#parseErrorLog(logFilePath, projectPath, displayMessageTypes, isSilent, disableMorePrompt, extraParams)
    
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
		if apexToolingCommon#displayMessages(a:logFilePath, a:projectPath, a:displayMessageTypes) < 1 && !a:isSilent
			call apexUtil#info("No errors found")
		endif
        if disableMore && reEnableMore
            set more
        endif
		return 0
	endif

	call apexUtil#error("Operation failed")
	" check if we have messages
	call apexToolingCommon#displayMessages(a:logFilePath, a:projectPath, a:displayMessageTypes)
	
	call apexToolingCommon#fillQuickfix(a:logFilePath, a:projectPath, l:useLocationList)
	if disableMore && reEnableMore
		set more
	endif
	return 1

endfunction

"Param: displayMessageTypes list of message types to display, other types will
"be ignored, e.g. ['ERROR'] - will display only errors
"Returns: number of messages displayed
function! apexToolingCommon#displayMessages(logFilePath, projectPath, displayMessageTypes)
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
		call apexToolingCommon#displayMessageDetails(a:logFilePath, a:projectPath, message)
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
function! apexToolingCommon#displayMessageDetails(logFilePath, projectPath, message)
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
function! apexToolingCommon#fillQuickfix(logFilePath, projectPath, useLocationList)
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

    let l:errorCount = len(l:errorList)
	if l:errorCount > 0
		if a:useLocationList
            lopen 
        else    
            copen
        endif    
	endif
    return l:errorCount
endfunction	

" similar apexUtil#grepFile() function apexToolingCommon#grepValues()
" greps all lines starting with given prefix
" and returns list of values on the right side of the prefix
" Example:
" source file: 
" MODIFIED_FILE=file1.txt
" MODIFIED_FILE=file1.txt
" result: 
" ['file1.txt', 'file1.txt']
"
function! apexToolingCommon#grepValues(filePath, prefix)
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

" prepare file list for "deployOpen"
" and return dictionary with extra command line params for
" apexTooling#execute()
"Returns:
" {"specificFiles": "/path/to/temp/file/with/relative/path/names"}
function! apexToolingCommon#deployOpenPrepareParams(projectPath)
	let relativePaths = apexTooling#listOpenFiles(a:projectPath)
	return apexToolingCommon#prepareSpecificFilesParams(relativePaths)
endfunction

" prepare file list for "deployStaged"
" and return dictionary with extra command line params for
" apexTooling#execute()
"Returns:
" {"specificFiles": "/path/to/temp/file/with/relative/path/names"}
function! apexToolingCommon#deployStagedPrepareParams(projectPath)
	let relativePaths = apexStage#list(a:projectPath)
	" all paths are relative to src/ folder, e.g.
	"[classes/MyClass.cls,  pages/MyPage.page, ...]
	"however we need [aths relative project folder
	"so need to add src/ in front of each file
	if len(relativePaths) > 0
		call map(relativePaths, '"src/" . v:val')
	else
		call apexUtil#warning('Stage is empty.')
		return {}
	endif	
	return apexToolingCommon#prepareSpecificFilesParams(relativePaths)
endfunction

" prepare file list for "deployOne"
" and return dictionary with extra command line params for
" apexTooling#execute()
"Returns:
" {"specificFiles": "/path/to/temp/file/with/relative/path/names"}
function! apexToolingCommon#deployOnePrepareParams(projectPath)
	let fullpath = expand('%:p')

    " check if current file is part of unpacked static resource
    let resourcePath = apexResource#getResourcePath(fullpath)
    if len(resourcePath) > 0
        "current fullpath is something like this
        ".../project1/resources_unpacked/my.resource/css/main.css
        "swap unpacked file with its corresponding <name>.resource
        let fullpath = resourcePath
    endif    
	let relativePath = strpart(fullpath, len(a:projectPath) + 1) "+1 to remove turn '/src/' into 'src/'
	return apexToolingCommon#prepareSpecificFilesParams([relativePath])
endfunction

"Prepare command line param and file content for 'specificFiles' deployments
"Args:
"Param1: relativePaths - list of files relative project folder
"e.g.:
"[src/classes/MyClass.cls,  src/pages/MyPage.page, ...]
"Returns:
" {"specificFiles": "/path/to/temp/file/with/relative/path/names"}
function! apexToolingCommon#prepareSpecificFilesParams(relativePaths)
	let relativePaths = a:relativePaths
	let l:params = {}
	if len(relativePaths) > 0
		call apexUtil#warning('Following files will be included')
		for path in relativePaths
			call apexUtil#warning('  ' . path)
		endfor
		if apexUtil#input('Proceed [y/N]? ', 'yYnN', 'N') !=? 'y'
			return {} "user cancelled
		endif
		"dump file list into a temp file
		let tempFile = tempname() . "-fileList.txt"
		call writefile(relativePaths, tempFile)
		let l:params["specificFiles"] = apexOs#shellescape(tempFile)
	endif
	return l:params
endfunction

function! apexToolingCommon#setLastLog(filePath)
    let s:apex_last_log = a:filePath
endfunction    
function! apexToolingCommon#setLastLogByFileName(filesMap)
    let s:apex_last_log_by_class_name = a:filesMap
endfunction    
function! apexToolingCommon#clearLastLog()
	if exists("s:apex_last_log")
        unlet s:apex_last_log
    endif    
endfunction    
function! apexToolingCommon#clearLastLogByFileName()
	if exists("s:apex_last_log_by_class_name")
        unlet s:apex_last_log_by_class_name
    endif    
endfunction    
function! apexToolingCommon#hasLastLog()
    return exists("s:apex_last_log")
endfunction    

function! apexToolingCommon#openLastLog()
	if exists("s:apex_last_log")
        "s:apex_last_log contains path to single log file
        :execute "e " . fnameescape(s:apex_last_log)
    elseif exists("s:apex_last_log_by_class_name")    
        if type({}) == type(s:apex_last_log_by_class_name)
            " s:apex_last_log_by_class_name contans map: {class-name -> file-path}
            "fill location list with this information
            let l:logList = []
            for fName in sort(keys(s:apex_last_log_by_class_name))
                let l:text = fName
                let l:filePath = s:apex_last_log_by_class_name[fName]
                let l:line = {"filename": l:filePath, "lnum": 1, "col": 1, "text": l:text}
                call add(l:logList, l:line)
            endfor
            if 1 == len(l:logList)
                " open the only log immediately, there is no point in filling
                " in location list
                :execute "e " . fnameescape(l:logList[0].filename)
            else    
                call setloclist(0, l:logList)
                :lopen
            endif    
        endif
	else
		call apexUtil#info('No Log file available')
	endif
endfunction
