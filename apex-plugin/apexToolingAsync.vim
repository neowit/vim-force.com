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
let g:loaded_apexToolingAsync = 1

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

	call apexToolingAsync#execute(l:action, projectName, projectPath, l:extraParams, [])

endfunction

"Args:
"Param1: path to file which belongs to current apex project
"Param2: [optional] name of remote <project>.properties file
function apexToolingAsync#refreshFile(filePath, ...)
    let filePath = a:filePath
    " check if current file is part of unpacked static resource
    let resourcePath = apexResource#getResourcePath(a:filePath)
    let isUnpackedResource = 0

    if len(resourcePath) > 0
        "current filePath is something like this
        ".../project1/resources_unpacked/my.resource/css/main.css
        "swap unpacked file with its corresponding <name>.resource
        let filePath = resourcePath
        let isUnpackedResource = 1
    endif    

    " =============== internal callback ====================
    let obj = {"_filePath": filePath, "_resourcePath": resourcePath}
    let obj["_isUnpackedResource"] = isUnpackedResource
    function! obj.callbackFuncRef(paths)
        let filePath = a:paths._filePath
        let resourcePath = a:paths._resourcePath
        let isUnpackedResource = a:paths._isUnpackedResource
        
        if len(a:paths) > 1 && filereadable(a:paths['remoteFile'])
            call apexOs#copyFile(a:paths['remoteFile'], filePath)
            if isUnpackedResource
                call apexUtil#warning("You have refreshed zipped static resource, please re-open it explicitly to unpack fresh files.")
                call apexUtil#info("You may want to delete 'resources_unpacked/".apexOs#splitPath(resourcePath).tail."' before unpacking fresh resource content.")
            endif    
        else
            call apexUtil#warning("Failed to retrieve remote file or it does not exist on remote.")
        endif

    endfunction    
    " =============== END internal callback ====================

	if a:0 > 0 && len(a:1) > 0
        " specific project, not necessarily the current one
		let projectName = apexUtil#unescapeFileName(a:1)
        call apexToolingAsync#retrieveSpecific(filePath, 'file', obj, projectName )
    else    
        " current project
        call apexToolingAsync#retrieveSpecific(filePath, 'file', obj)
	endif

endfunction

" this method is used for :ApexDiffWithRemote[File|Project] and for :ApexRefreshFile
"Args:
"Param1: path to file which belongs to current apex project
"Param2: mode: 'project' or 'file'
"       - 'project' - will retrieve all project files into a temp folder and
"                     return its location
"       - 'file' - will retrieve a single file (or aura bundle) and return
"                 single file location
"Param3: callbackObj - object which contains 'callbackFuncRef' and other
"       '_...' parameters
"       when callbackFuncRef is called it receives 
"       {'remoteSrcDir': '...', 'remoteFile': '...'}
"       as well as original '_...' parameters
"       e.g.: 
"       callbackFuncRef({'remoteSrcDir': '...', 'remoteFile': '...', '_param': '...'}
"Param4: [optional] name of remote <project>.properties file
"Return: dictionary: {'remoteSrcDir': '/path/to/temp/src...', 'remoteFile': '/path/to/temp/src/.../file'}
function apexToolingAsync#retrieveSpecific(filePath, mode, callbackObj, ...)
    let leftFile = a:filePath
    let l:mode = a:mode
    
	let projectPair = apex#getSFDCProjectPathAndName(leftFile)
	let projectName = projectPair.name
    
	if a:0 > 0 && len(a:1) > 0
		let projectName = apexUtil#unescapeFileName(a:1)
	endif

    let l:extraParams = {"typesFileFormat" : "packageXml"}
    let l:extraParams["_internalCallbackFuncRef"] = a:callbackObj.callbackFuncRef
    let l:extraParams["_callbackObj"] = a:callbackObj

    if 'file' == l:mode

		let filePair = apexOs#splitPath(leftFile)
		let fName = filePair.tail
		let folder = apexOs#splitPath(filePair.head).tail
		"file path in stage always uses / as path separator
        let srcPath = apex#getApexProjectSrcPath(leftFile)
        " get path relative src/ folder
        let relPath = strpart(leftFile, len(srcPath) + 1) " +1 to remove / at the end of src/
        " if current file is in aura bundle then we only need bundle name, not
        " file name
        if relPath =~ "^aura/"
            let relPath = apexOs#removeTrailingPathSeparator(apexOs#splitPath(relPath).head)
        endif
        
		"dump file list into a temp file
		let tempFile = tempname() . "-fileList.txt"
		call writefile([relPath], tempFile)

        let l:extraParams["typesFileFormat"] = "file-paths"
        let l:extraParams["specificTypes"] = tempFile
        let l:extraParams["_leftFile"] = leftFile
        let l:extraParams["_mode"] = l:mode
    endif

    " ================= apexToolingAsync#retrieveSpecific: internal callback ============================
    function l:extraParams.callbackFuncRef(resMap)
        let self.callbackFunc = a:resMap._internalCallbackFuncRef 
        let callbackObj = a:resMap._callbackObj
        let leftFile =    a:resMap._leftFile
        let l:mode =    a:resMap._mode

        let resObj = {}
        " workaround for vim issue with losing scope when using nested
        " callbacks
        call s:copyUnderscoredParams(a:resMap, resObj)

        if "true" == a:resMap["success"]
            let responseFilePath = a:resMap["responseFilePath"]
            let l:values = apexToolingCommon#grepValues(responseFilePath, "REMOTE_SRC_FOLDER_PATH=")
                let remoteSrcFolderPath = l:values[0]
                let resObj["remoteSrcDir"] = remoteSrcFolderPath
                let srcPath = apex#getApexProjectSrcPath(leftFile)
                if 'file' == l:mode
                    " compare single files
                    let rightProjectFolder = apexOs#splitPath(remoteSrcFolderPath).head
                    let filePathRelativeProjectFolder = apex#getFilePathRelativeProjectFolder(leftFile)
                    let rightFile = apexOs#joinPath(rightProjectFolder, filePathRelativeProjectFolder)
                    let resObj["remoteFile"] = rightFile
                else
                    let resObj["remoteFile"] = ''
                endif
        endif
        " workaround for lost scope
        call s:copyUnderscoredParams(callbackObj, resObj)
        call self.callbackFunc(resObj)

    endfunction    
    " ================= END internal callback ============================
    
    " 'diffWithRemote' here is not a mistake, it is more suitable than 'bilkRetrieve' for current purpose
    call apexToolingAsync#execute("diffWithRemote", projectName, projectPair.path, l:extraParams, [])
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

function! s:refreshProjectMainCallback(resMap)
	if "true" == a:resMap["success"]
		" TODO add a setting so user could chose whether they want
		" backup of all files received in Refresh or only modified ones
		"
		" backup modified files
		"if len(modifiedFiles) > 0
		"	call s:backupFiles(projectPair.name, projectPair.path, modifiedFiles)
		"endif

		" copy files from temp folder into project folder
		let logFilePath = a:resMap["responseFilePath"]
		let l:lines = apexToolingCommon#grepValues(logFilePath, "RESULT_FOLDER=")
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
					let relativePath = substitute(relativePath, "^[/|\\\\]unpackaged[/|\\\\]", "src/", "")
					"check if local file exists adn sizes are different
					let localFilePath = apexOs#joinPath([a:resMap["projectPath"], relativePath])
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
				let backupDir = apexToolingCommon#backupFiles(a:resMap["projectName"], a:resMap["projectPath"], relativePathsOfFilesToBeOverwritten)
                let l:msg = "Project files with size different to remote ones have been preserved in: " . backupDir
                call apexMessages#log(l:msg)
				echo l:msg
			endif

			" finally move files from temp dir into project dir
			for sourcePath in l:files
				if !isdirectory(sourcePath)

					let relativePath = strpart(sourcePath, resultFolderPathLen)
					let relativePath = substitute(relativePath, "^[/|\\\\]unpackaged[/|\\\\]", "src/", "")
					let destinationPath = apexOs#joinPath([a:resMap["projectPath"], relativePath])
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
			checktime "make sure that external changes are reported
		endif
	endif

endfunction    

"Args:
"Param: filePath: path to file which belongs to apex project
"Param1: skipModifiedFiles: (optional) 0 for false, anything else for true
function! apexToolingAsync#refreshProject(filePath, ...)
	let projectPair = apex#getSFDCProjectPathAndName(a:filePath)
	let extraParams = a:0 > 0 && a:1 ? {"skipModifiedFilesCheck":"true"} : {}

    " ============ internal callback 1 ================
    function! extraParams.callbackFuncRef(resMap)
        let logFilePath = a:resMap["responseFilePath"]
        " check if SFDC client reported modified files
        let modifiedFiles = apexToolingCommon#grepValues(logFilePath, "MODIFIED_FILE=")
        if len(modifiedFiles) > 0
            " modified files detected
            call apexUtil#warning("Modified file(s) detected..")
            call s:reportModifiedFiles(modifiedFiles)
            echohl WarningMsg
            let response = input('Are you sure you want to lose local changes [y/N]? ')
            echohl None 
            if 'y' !=? response
                redrawstatus
                return 
            endif
            " STEP 2: forced refresh when there are modified files
            let extraParams = {"skipModifiedFilesCheck":"true"}
            let extraParams.callbackFuncRef = function('s:refreshProjectMainCallback')
            call apexToolingAsync#execute("refresh", a:resMap["projectName"], a:resMap["projectPath"], extraParams, ["ERROR", "INFO"])
        else
            " no modified files detected, can proceed with Main callback
            call s:refreshProjectMainCallback(a:resMap)
        endif

    endfunction    
    " ============ END internal callback 1 ================

    " STEP 1:
	call apexToolingAsync#execute("refresh", projectPair.name, projectPair.path, extraParams, ["ERROR", "INFO"])
    

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

"run unit tests
"Args:
"Param: filePath 
"			path to file which belongs to apex project
"
"Param: attributeMap - map {} of test attributes
"			e.g.: {"checkOnly": 0, "testsToRun": "TestClass,OtherTestClass"}
"			e.g.: {"checkOnly": 1, "testsToRun": "TestClass.method1,TestClass.method2"}
"
"			testsToRun: (optional) - if provided then only run tests in the specified class(es)
"									otherwise all test classes listed in
"									deployment package
"			checkOnly:(optional) - can be either 0(false) or 1(true)
"			tooling:(optional) - can be either 'sync' or 'async'.
"			                        if specified then Tooling API will be
"			                        used, instead of Metadata API
"
"
"Param: orgName - given project name will be used as
"						target Org name.
"						must match one of .properties file with	login details
"Param: reportCoverage: 'reportCoverage' (means load lines report), anything
"				        else means do not load lines coverage report
"Param: bang - if 1 then skip conflicts check with remote
function apexToolingAsync#deployAndTest(filePath, attributeMap, orgName, reportCoverage, bang)
	let projectPair = apex#getSFDCProjectPathAndName(a:filePath)
	let projectPath = projectPair.path
	let projectName = len(a:orgName) > 0 ? a:orgName : projectPair.name
	let attributeMap = a:attributeMap
	" if any coverage shown - remove highlight, to avoid confusion
	call apexCoverage#hide(a:filePath)

	let l:extraParams = {}
	" another org?
	if projectPair.name != projectName
		let l:extraParams["callingAnotherOrg"] = "true"
		"when deploying to another org there is no point in checking conflicts
		"because local metadata is not related to that org
		let l:extraParams["ignoreConflicts"] = "true"
	endif
	" checkOnly?
	if has_key(attributeMap, "checkOnly")
		let l:extraParams["checkOnly"] = attributeMap["checkOnly"]? "true" : "false"
	endif
	" testsToRun
	if has_key(attributeMap, "testsToRun")
        let l:extraParams["testsToRun"] = shellescape(attributeMap["testsToRun"])
	else
        if has_key(attributeMap, "testSuites")
            let l:extraParams["testSuitesToRun"] = shellescape(attributeMap["testSuites"])
        else    
            "run all tests in the deployment package
            let l:extraParams["testsToRun"] = shellescape('*')
        endif
	endif
	"reportCoverage
	if 'reportCoverage' == a:reportCoverage
		let l:extraParams["reportCoverage"] = 'true'
	endif
	"ignoreConflicts ?
	if a:bang
		let l:extraParams["ignoreConflicts"] = "true"
	endif

    let l:command = "deployModified"
    let l:isTooling = has_key(attributeMap, "tooling")

	if l:isTooling 
        let l:command = "runTestsTooling"
        if 'async' == attributeMap["tooling"]
		    let l:extraParams["async"] = "true"
        else
		    let l:extraParams["async"] = "false"
        endif    
    endif
    if "deployModified" == l:command
        " current version only asks Metadata API log level
        call apexLogActions#askLogLevel(a:filePath, 'meta')
        
    elseif has_key(attributeMap, "tooling")

        call apexLogActions#askLogLevel(a:filePath, 'tooling')
        if exists('g:apex_test_traceFlag')
            let tempTraceConfigFilePath = apexLogActions#saveTempTraceFlagConfig(g:apex_test_traceFlag)
		    
            let l:extraParams["traceFlagConfig"] = apexOs#shellescape(tempTraceConfigFilePath)
            "let l:extraParams["scope"] = "user"
        endif
    endif    
    " ================= internal callback ===========================
    function! l:extraParams.callbackFuncRef(resMap)
        if has_key(a:resMap, "responseFilePath")
            let responsePath = a:resMap["responseFilePath"]
            let coverageFiles = apexToolingCommon#grepValues(responsePath, "COVERAGE_FILE=")
            let filePath = a:resMap["filePath"]

            if len(coverageFiles) > 0
                let s:last_coverage_report_file = coverageFiles[0]
                " if last command is piped to another command then no need to display
                " quickfix window
                let l:histnr = histnr("cmd")
                let l:lastCmd = histget("cmd", l:histnr)
                if l:lastCmd !~ "|.*ApexTestCoverage"
                    " display coverage list if available and there are no errors in quickfix
                    if len(getqflist()) < 1
                        call apexCoverage#quickFixOpen(filePath)
                    endif
                endif
            endif
        endif
    endfunction    

    let l:extraParams["_filePath"] = a:filePath
    "let l:extraParams["callbackFuncRef"] = function(l:extraParams.internalCallback)
    "let l:extraParams["callbackFuncParams"] = {"filePath": a:filePath}
    " ================= END internal callback ===========================

	call apexToolingAsync#execute(l:command, projectName, projectPath, l:extraParams, [])

	"let resMap = apexTooling#execute(l:command, projectName, projectPath, l:extraParams, [])
    "if has_key(resMap, "responseFilePath")
    "    let responsePath = resMap["responseFilePath"]
    "    let coverageFiles = apexToolingCommon#grepValues(responsePath, "COVERAGE_FILE=")
    "    if len(coverageFiles) > 0
    "        let s:last_coverage_report_file = coverageFiles[0]
    "        " if last command is piped to another command then no need to display
    "        " quickfix window
    "        let l:histnr = histnr("cmd")
    "        let l:lastCmd = histget("cmd", l:histnr)
    "        if l:lastCmd !~ "|.*ApexTestCoverage"
    "            " display coverage list if available and there are no errors in quickfix
    "            if len(getqflist()) < 1
    "                call apexCoverage#quickFixOpen(a:filePath)
    "            endif
    "        endif
    "    endif
    "endif

endfunction

"Args:
"Param1: path to file which belongs to apex project
function apexToolingAsync#printChangedFiles(filePath)
	let projectPair = apex#getSFDCProjectPathAndName(a:filePath)
	call apexToolingAsync#execute("listModified", projectPair.name, projectPair.path, {}, [])
endfunction	

" ==================================================================================================
" this callback is used when no explicit callback method specified by caller
" of apexToolingAsync#execute()
function! s:dummyCallback(msg)
    "echo "dummyCallback: " . string(a:msg)
endfunction    

"Returns: dictionary: 
"	{
"	"success": "true" if RESULT=SUCCESS
"	"responseFilePath" : "path to current response/log file"
"	"projectPath": "project path"
"	"projectName": "project name"
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
    " also exclude keys wich start with underscore '_'
	if len(a:extraParams) > 0
		for key in keys(a:extraParams)
			if index(l:EXCLUDE_KEYS, key) < 0 && key !~ '^_'
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
    let obj.projectName = a:projectName
    let obj.displayMessageTypes = a:displayMessageTypes
    let obj.extraParams = a:extraParams
    let obj.isSilent = isSilent
    let obj.startTime = l:startTime
    if has_key(a:extraParams, "_filePath")
        let obj.filePath = a:extraParams["_filePath"]
    endif

    if ( has_key(a:extraParams, "callbackFuncRef") )
        let obj["callbackFuncRef"] = a:extraParams["callbackFuncRef"]
    endif    
    " workaround for vim losing scope of object to which
    " callbackFuncRef belongs
    call s:copyUnderscoredParams(a:extraParams, obj)
    
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
        silent let logFileRes = apexToolingCommon#grepValues(self.responseFilePath, "LOG_FILE=")

        if !empty(logFileRes)
            call apexToolingCommon#setLastLog(logFileRes[0])
            if s:show_log_hint
                call apexMessages#logInfo("Log file is available, use :ApexLog to open it")
                let s:show_log_hint = 0
            endif
        else
            call apexToolingCommon#clearLastLog()

            "try LOG_FILE_BY_CLASS_NAME map
            let logFileRes = apexToolingCommon#grepValues(self.responseFilePath, "LOG_FILE_BY_CLASS_NAME=")

            if !empty(logFileRes)
                call apexToolingCommon#setLastLogByFileName( eval(logFileRes[0]) )
                if s:show_log_hint
                    call apexMessages#logInfo("Log file is available, use :ApexLog to open it")
                    let s:show_log_hint = 0
                endif
            else
                call apexToolingCommon#clearLastLogByFileName()
            endif    
        endif

        let l:disableMorePrompt = s:hasOnCommandComplete()

        let errCount = s:parseErrorLog(self.responseFilePath, self.projectPath, self.displayMessageTypes, self.isSilent, l:disableMorePrompt, self.extraParams)
        "echo "l:startTime=" . string(l:startTime)
        """temporary disabled"" call s:onCommandComplete(reltime(self.startTime))

        let l:result = {"success": 0 == errCount? "true": "false",
                    \ "responseFilePath": self.responseFilePath,
                    \ "projectPath": self.projectPath,
                    \ "projectName": self.projectName}
        
        if has_key(self, "filePath")
            let l:result["filePath"] = self.filePath
        endif    
        if ( has_key(self, "callbackFuncRef") )
            " workaround for vim losing scope of object to which
            " callbackFuncRef belongs
            call s:copyUnderscoredParams(self, l:result)
            
            call self.callbackFuncRef(l:result)
        endif    
    endfunction    
    " ================= END internal callback =========================

	call s:runCommand(l:command, isSilent, function(obj.callbackInternal))

endfunction

" vim appears to lose scope of outer object in a situation like this
" let obj1 = {"test": 'test1'}
" function obj1.func1() {
"   " next line will cause error
"   echo self.test " this will result in: 'dictionary self does not have key: test'
" }
" let obj2 = {"test": 'test2', 'callback': obj1.func1}
" function obj1.func1() {
"   call self.callback()
" }
function! s:copyUnderscoredParams(source, dest)
    for key in keys(a:source)
        if key =~ '^_'
            let a:dest[key] = a:source[key]
        endif
    endfor
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

    let messageCount = 0

	if len(apexUtil#grepFile(fileName, 'RESULT=FAILURE')) > 0
        call apexMessages#logError("Operation failed")
        " check if we have failure messages
        let messageCount = apexMessages#process(a:logFilePath, a:projectPath, a:displayMessageTypes) > 0 

        let l:currentBufWinNum = bufwinnr("%")
        let quickfixMessageCount = apexToolingCommon#fillQuickfix(a:logFilePath, a:projectPath, l:useLocationList)
        if  quickfixMessageCount < 1 && messageCount > 1 && !a:isSilent
            " open messages only if there are more than 1 and quickfix is empty
            " and not silent mode
            call apexMessages#open()
        endif    
        if a:isSilent && l:currentBufWinNum >=0 && l:currentBufWinNum != bufwinnr("%")
            " return focus to original buffer
            exe l:currentBufWinNum . "wincmd w"
        endif
    elseif len(apexUtil#grepFile(fileName, 'RESULT=SUCCESS')) > 0
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
    
	return 1

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
