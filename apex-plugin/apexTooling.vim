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
function apexTooling#deploy(action, mode, bang, ...)
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

	let resMap = apexTooling#execute(l:action, projectName, projectPath, l:extraParams, [])

endfunction

let s:last_coverage_report_file = ''
function! apexTooling#getLastCoverageReportFile()
	return s:last_coverage_report_file
endfunction
"DEBUG ONLY
function! apexTooling#setLastCoverageReportFile(filePath)
	let s:last_coverage_report_file = a:filePath
endfunction


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

	let resMap = apexTooling#execute("listCompletions", projectName, projectPath, l:extraParams, [])
	let responseFilePath = resMap["responseFilePath"]
	return responseFilePath
endfunction

function apexTooling#checkSyntax(filePath, attributeMap)
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

	let resMap = apexTooling#execute("checkSyntax", projectName, projectPath, l:extraParams, [])
	let responseFilePath = resMap["responseFilePath"]
	return responseFilePath
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
function apexTooling#deployAndTest(filePath, attributeMap, orgName, reportCoverage, bang)
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

	let resMap = apexTooling#execute(l:command, projectName, projectPath, l:extraParams, [])
    if has_key(resMap, "responseFilePath")
        let responsePath = resMap["responseFilePath"]
        let coverageFiles = s:grepValues(responsePath, "COVERAGE_FILE=")
        if len(coverageFiles) > 0
            let s:last_coverage_report_file = coverageFiles[0]
            " if last command is piped to another command then no need to display
            " quickfix window
            let l:histnr = histnr("cmd")
            let l:lastCmd = histget("cmd", l:histnr)
            if l:lastCmd !~ "|.*ApexTestCoverage"
                " display coverage list if available and there are no errors in quickfix
                if len(getqflist()) < 1
                    call apexCoverage#quickFixOpen(a:filePath)
                endif
            endif
        endif
    endif

endfunction

"Args:
"Param1: path to file which belongs to apex project
function apexTooling#printChangedFiles(filePath)
	let projectPair = apex#getSFDCProjectPathAndName(a:filePath)
	call apexTooling#execute("listModified", projectPair.name, projectPair.path, {}, [])
endfunction	

" retrieve list of Test Suite names into specified file
"Args:
"Param1: path to file which belongs to apex project
function apexTooling#loadTestSuiteNamesList(projectName, projectPath, outputFilePath)
    let l:extraParams = {}
    let l:extraParams["testSuiteAction"] = "dumpNames"
    let l:extraParams["dumpToFile"] = apexOs#shellescape(a:outputFilePath)
	call apexTooling#execute("testSuiteManage", a:projectName, a:projectPath, l:extraParams, [])
endfunction	

"Args:
"Param1: path to file which belongs to current apex project
"Param2: [optional] name of remote <project>.properties file
function apexTooling#refreshFile(filePath, ...)
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
    let l:paths = {}
	if a:0 > 0 && len(a:1) > 0
        " specific project, not necessarily the current one
		let projectName = apexUtil#unescapeFileName(a:1)
        let l:paths = apexTooling#retrieveSpecific(filePath, 'file', projectName)
    else    
        " current project
        let l:paths = apexTooling#retrieveSpecific(filePath, 'file')
	endif
    if len(l:paths) > 1 && filereadable(l:paths['remoteFile'])
        call apexOs#copyFile(l:paths['remoteFile'], filePath)
        if isUnpackedResource
            call apexUtil#warning("You have refreshed zipped static resource, please re-open it explicitly to unpack fresh files.")
            call apexUtil#info("You may want to delete 'resources_unpacked/".apexOs#splitPath(resourcePath).tail."' before unpacking fresh resource content.")
        endif    
    else
        call apexUtil#warning("Failed to retrieve remote file or it does not exist on remote.")
    endif

endfunction

"Args:
"Param1: path to file which belongs to current apex project
"Param2: mode: 'project' or 'file'
"       - 'project' - will compare local project with its remote counterpart
"       - 'file' - will compare only current file with its remote counterpart
"Param3: [optional] name of remote <project>.properties file
function apexTooling#diffWithRemote(filePath, mode, ...)
    
    let leftFile = a:filePath
    
    let l:paths = {}
	if a:0 > 0 && len(a:1) > 0
        " specific project, not necessarily the current one
		let projectName = apexUtil#unescapeFileName(a:1)
        let l:paths = apexTooling#retrieveSpecific(a:filePath, a:mode, projectName)
    else    
        " current project
        let l:paths = apexTooling#retrieveSpecific(a:filePath, a:mode)
	endif
    if len(l:paths) > 0
        let modeMsg = 'file' == a:mode ? "files" : "folders"
        if apexUtil#input("Run diff tool to compare local and remote ". modeMsg ." [y/N]? ", "YynN", "N") ==? 'y'
            echo "\n"
            
            if 'file' == a:mode
                let rightFile = l:paths['remoteFile']
                " compare single files
                call apexUtil#compareFiles(leftFile, rightFile)
            else
                " compare top of local and retrieved projects
                let srcPath = apex#getApexProjectSrcPath(leftFile)
                " remove temp package.xml because it contains only last
                " retrieved metadata type
                call delete(apexOs#joinPath(l:paths['remoteSrcDir'], 'package.xml'))

                call apexUtil#compareFiles(srcPath, l:paths['remoteSrcDir'])
            endif
        endif    
    else
        if 'file' == a:mode
            call apexUtil#warning("Failed to retrieve remote file or it does not exist on remote.")
        endif
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
"Param3: [optional] name of remote <project>.properties file
"Return: dictionary: {'remoteSrcDir': '/path/to/temp/src...', 'remoteFile': '/path/to/temp/src/.../file'}
function apexTooling#retrieveSpecific(filePath, mode, ...)
    let leftFile = a:filePath
    let l:mode = a:mode
    
	let projectPair = apex#getSFDCProjectPathAndName(leftFile)
	let projectName = projectPair.name
    
	if a:0 > 0 && len(a:1) > 0
		let projectName = apexUtil#unescapeFileName(a:1)
	endif

    let l:extraParams = {"typesFileFormat" : "packageXml"}

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

        let l:extraParams = {"typesFileFormat" : "file-paths", "specificTypes" : tempFile}
    endif
    
    " 'diffWithRemote' here is not a mistake, it is more suitable than 'bilkRetrieve' for current purpose
    let resMap = apexTooling#execute("diffWithRemote", projectName, projectPair.path, l:extraParams, [])
	if "true" == resMap["success"]
        let responseFilePath = resMap["responseFilePath"]
        let l:values = s:grepValues(responseFilePath, "REMOTE_SRC_FOLDER_PATH=")
            let remoteSrcFolderPath = l:values[0]
            let srcPath = apex#getApexProjectSrcPath(leftFile)
            if 'file' == l:mode
                " compare single files
                let rightProjectFolder = apexOs#splitPath(remoteSrcFolderPath).head
                let filePathRelativeProjectFolder = apex#getFilePathRelativeProjectFolder(leftFile)
                let rightFile = apexOs#joinPath(rightProjectFolder, filePathRelativeProjectFolder)
                return {'remoteSrcDir': remoteSrcFolderPath, 'remoteFile': rightFile}
            else
                return {'remoteSrcDir': remoteSrcFolderPath, 'remoteFile': ''}
            endif
    endif
    return {}
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

"Args:
"Param: filePath: path to file which belongs to apex project
"Param1: skipModifiedFiles: (optional) 0 for false, anything else for true
function apexTooling#refreshProject(filePath, ...)
	let projectPair = apex#getSFDCProjectPathAndName(a:filePath)
	let extraParams = a:0 > 0 && a:1 ? {"skipModifiedFilesCheck":"true"} : {}
	let resMap = apexTooling#execute("refresh", projectPair.name, projectPair.path, extraParams, ["ERROR", "INFO"])
	let logFilePath = resMap["responseFilePath"]
	" check if SFDC client reported modified files
	let modifiedFiles = s:grepValues(logFilePath, "MODIFIED_FILE=")
	if len(modifiedFiles) > 0
		" modified files detected
		call apexUtil#warning("Modified file(s) detected..")
		call s:reportModifiedFiles(modifiedFiles)
		echohl WarningMsg
		let response = input('Are you sure you want to lose local changes [y/N]? ')
		echohl None 
		if 'y' !=? response
			return 
		endif
		" forced refresh when there are modified files
		let resMap = apexTooling#execute("refresh", projectPair.name, projectPair.path, {"skipModifiedFilesCheck":"true"}, ["ERROR", "INFO"])
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
					let relativePath = substitute(relativePath, "^[/|\\\\]unpackaged[/|\\\\]", "src/", "")
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
					let relativePath = substitute(relativePath, "^[/|\\\\]unpackaged[/|\\\\]", "src/", "")
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
			checktime "make sure that external changes are reported
		endif
	endif
endfunction	

"list potential conflicts between local and remote
"takes into account only modified files, i.e. files which would be deployed if
":DeployModified command is executed
"Args:
"Param1: path to file which belongs to apex project
function apexTooling#printConflicts(filePath)
	let projectPair = apex#getSFDCProjectPathAndName(a:filePath)
	call apexTooling#execute("listConflicts", projectPair.name, projectPair.path, {}, [])
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
	return apexTooling#execute("describeMetadata", a:projectName, a:projectPath, {"allMetaTypesFilePath": apexOs#shellescape(a:allMetaTypesFilePath)}, [])
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
	
	let resMap = apexTooling#execute("bulkRetrieve", a:projectName, a:projectPath, extraParams, [])
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
	let resMap = apexTooling#execute("listMetadata", a:projectName, a:projectPath, {"specificTypes": apexOs#shellescape(a:specificTypesFilePath)}, [])
	if "true" == resMap["success"]
		let logFilePath = resMap["responseFilePath"]
		let resultFile = s:grepValues(logFilePath, "RESULT_FILE=")
		if len(resultFile) > 0
			let resMap["resultFile"] = resultFile[0]
		endif
	endif
	return resMap
endfunction	

function! apexTooling#openLastLog()
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

	let resMap = apexTooling#execute("deleteMetadata", a:projectName, projectPair.path, l:extraParams, [])
	return resMap
endfunction	

" get version of currently installed tooling-force.com
"Args:
"Param1: filePath - path to apex file in current project
function apexTooling#getVersion(filePath)
	let projectPair = apex#getSFDCProjectPathAndName(a:filePath)
	let resMap = apexTooling#execute("version", projectPair.name, projectPair.path, {}, [])
	let responsePath = resMap["responseFilePath"]
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
		call map(relativePaths, '"src/" . v:val')
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

    " check if current file is part of unpacked static resource
    let resourcePath = apexResource#getResourcePath(fullpath)
    if len(resourcePath) > 0
        "current fullpath is something like this
        ".../project1/resources_unpacked/my.resource/css/main.css
        "swap unpacked file with its corresponding <name>.resource
        let fullpath = resourcePath
    endif    
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

"Returns: dictionary/pair: 
"	{
"	"success": "true" if RESULT=SUCCESS
"	"responseFilePath" : "path to current response/log file"
"	}
"
function! apexTooling#execute(action, projectName, projectPath, extraParams, displayMessageTypes) abort
	let projectPropertiesPath = apexOs#joinPath([g:apex_properties_folder, a:projectName]) . ".properties"

	if has_key(a:extraParams, "ignoreConflicts")
		call apexUtil#warning("skipping conflict check with remote")
	endif

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
	let l:java_command = l:java_command  . " -jar " . apexOs#shellescape(g:apex_tooling_force_dot_com_path)

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

	let l:EXCLUDE_KEYS = ["isSilent", "useLocationList"]
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
		echo "\n"
	endif
 
	" make sure we do not accidentally reuse old responseFile
	call delete(responseFilePath)

    let l:startTime = reltime()
	"call apexOs#exe(l:command, 'M') "disable --more--
	call s:runCommand(l:java_command, l:command, isSilent)

	let logFileRes = s:grepValues(responseFilePath, "LOG_FILE=")
	
	if !empty(logFileRes)
		let s:apex_last_log = logFileRes[0]
		if s:show_log_hint
			call apexUtil#info("Log file is available, use :ApexLog to open it")
			let s:show_log_hint = 0
		endif
	else
        if exists("s:apex_last_log")
		    unlet s:apex_last_log
        endif    

        "try LOG_FILE_BY_CLASS_NAME map
        let logFileRes = s:grepValues(responseFilePath, "LOG_FILE_BY_CLASS_NAME=")

        if !empty(logFileRes)
            let s:apex_last_log_by_class_name = eval(logFileRes[0])
            if s:show_log_hint
                call apexUtil#info("Log file is available, use :ApexLog to open it")
                let s:show_log_hint = 0
            endif
        elseif exists("s:apex_last_log_by_class_name")
		    unlet s:apex_last_log_by_class_name
        endif    
	endif

    let l:disableMorePrompt = s:hasOnCommandComplete()

	let errCount = s:parseErrorLog(responseFilePath, a:projectPath, a:displayMessageTypes, isSilent, l:disableMorePrompt, a:extraParams)
    "echo "l:startTime=" . string(l:startTime)
    call s:onCommandComplete(reltime(l:startTime))
	return {"success": 0 == errCount? "true": "false", "responseFilePath": responseFilePath}
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
"================= server mode commands ==========================

" send server 'shutdown' command to stop it
function! apexTooling#serverShutdown()
	call s:sendCommandToServer("shutdown", "")
endfunction

" depending on the configuration either spawn a brand new java process to run
" current command or try to execute on the running server
" Global variables:
" g:apex_use_server - if <> 0 then server will be used
"
function! s:runCommand(java_command, commandLine, isSilent)
	let isServerEnabled = apexUtil#getOrElse("g:apex_server", 0) > 0
	let l:flags = 'M' "disable --more--
	if a:isSilent
		let l:flags .= 's' " silent
	endif

	if isServerEnabled && s:ensureServerRunning(a:java_command)
		"let l:command = s:prepareServerCommand(a:commandLine)
		"call apexOs#exe(l:command, l:flags)	
		call s:sendCommandToServer(a:commandLine, l:flags)
	else
		let l:command = a:java_command . a:commandLine
		call apexOs#exe(l:command, l:flags)
	endif
endfunction

function! s:ensureServerRunning(java_command)
	let isServerEnabled = apexUtil#getOrElse("g:apex_server", 0) > 0
	if !isServerEnabled
		"server not enabled
		return 0
	else
		let pong = s:sendCommandToServer("ping", "s")
		
		if pong !~? "pong"
			" start server
			let l:command = a:java_command . " --action=serverStart --port=" . s:getServerPort() . " --timeoutSec=" . s:getServerTimeoutSec()
			call apexOs#exe(l:command, 'bMp') "start in background, disable --more--, try to use python if MS Windows
			"wait a little to make sure it had a chance to start
			echo "wait for server to start..."
			let l:count = 15 " wait for server to start no more than 15 seconds
			while (s:sendCommandToServer("ping", "s") !~? "pong" ) && l:count > 0
				sleep 1
				let l:count = l:count - 1
			endwhile
			" echo 'had to wait for ' . (5-l:count) . ' second(s)'
		endif
	endif
	return 1
endfunction

function! s:prepareServerCommand(commandLine)
	let l:host = s:getServerHost()
	let l:port = s:getServerPort()
	return 'echo "' . a:commandLine . '" | nc ' . l:host . ' ' . l:port
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


function! s:sendCommandToServer(commandLine, flags) abort
	let l:host = s:getServerHost()
	let l:port = s:getServerPort()
	let isSilent = a:flags =~# "s"
    let l:usePython = apexOs#isPythonAvailable() && apexOs#isWindows()	
	
	if l:usePython
		if !isSilent
			call s:updateProgress("working ...")
		endif
		return s:sendCommandToServerPython(a:commandLine, l:host, l:port, isSilent)
	else
		if isSilent
			return system(s:prepareServerCommand(a:commandLine))
		else
			let l:command = s:prepareServerCommand(a:commandLine)
			call apexOs#exe(l:command, a:flags)	
		endif
	endif
endfunction

function! s:updateProgress(msg)
	let l:msg = substitute(a:msg, "\\\\r\\\\n$", "", "")
	let l:msg = substitute(l:msg, "\\\\n$", "", "")
	echo l:msg
	sleep 100m " without sleep screen will not update, even when forced with :redraw!
endfunction


" this function uses python to send stuff to socket
function! s:sendCommandToServerPython(commandLine, host, port, isSilent) abort
python << endpython
import vim
commandLine = vim.eval("a:commandLine")

import socket

TCP_IP = vim.eval("a:host")
TCP_PORT = int(vim.eval("a:port"))
BUFFER_SIZE = 1024
MESSAGE = commandLine
isSilent = (1 == int(vim.eval("a:isSilent")) )

allData = ""
try:
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.connect((TCP_IP, TCP_PORT))
    s.sendall(MESSAGE)
    s.shutdown(socket.SHUT_WR)
    while 1:
        data = s.recv(BUFFER_SIZE)
        if data == "":
            break
        allData += data
    	#print "Received:", repr(data)
        if not isSilent:
    	    vim.command("call s:updateProgress("+repr(data)+")")
    
    #print "Connection closed."
    #print "allData=", allData
    s.close()
except socket.error as e:
    #vim.command("call s:updateProgress('socket.error' . '"+str(msg)+"')")
    allData = "socket.error: " + str(e)
except Exception as e:
    allData = "unexpected error: " + str(e)
	#vim.command("call s:updateProgress('"+str(e)+"')")


vim.command("return " + repr(allData)) # return from the Vim function!
endpython
endfunction
