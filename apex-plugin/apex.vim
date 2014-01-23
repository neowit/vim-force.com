" File: apex.vim
" Author: Andrey Gavrikov 
" Version: 1.1
" Last Modified: 2012-03-05
" Copyright: Copyright (C) 2010-2012 Andrey Gavrikov
"            Permission is hereby granted to use and distribute this code,
"            with or without modifications, provided that this copyright
"            notice is copied with it. Like anything else that's free,
"            this plugin is provided *as is* and comes with no warranty of any
"            kind, either expressed or implied. In no event will the copyright
"            holder be liable for any damages resulting from the use of this
"            software.
" apex.vim - main methods dealing with Project file synchronisation with SFDC

" Part of vim/force.com plugin
" 

" deploy changed Apex files under current project
" format returned errors
" refresh project from Force.com
"
if exists("g:loaded_apex") || &compatible
  finish
endif
let g:loaded_apex = 1

let g:apex_backup_folder_time_format = "%Y-%m-%d-%H%M%S"
let g:apex_last_backup_folder = ''

let s:SRC_DIR_NAME="src"
let s:FILE_TIME_DIFF_TOLERANCE_SEC = 1 " if .cls and .cls-meta.xml file time differs by this number of seconds (or less) we consider time equal

let s:APEX_EXTENSIONS_WITH_META_XML = ['cls', 'trigger', 'page', 'scf', 'resource', 'component']
let s:APEX_EXTENSIONS = s:APEX_EXTENSIONS_WITH_META_XML + ['labels', 'object']

"folder where intermediate project data is stored
"this folder is safe to delete, it will be recreated
"as needed
let s:CACHE_FOLDER_NAME = ".vim-force.com"

let s:MAKE_MODES = ['open', 'modified', 'confirm', 'all', 'staged', 'onefile'] "supported Deploy modes
""""""""""""""""""""""""""""""""""""""""""""""""
" Apex Code Compilation
""""""""""""""""""""""""""""""""""""""""""""""""
"Args:
"Param1: (optional) path to file which belongs to apex project which needs
"					to be deployed
"Param2: (optional) - Mode
"			'open' - deploy only files from currently open Tabs or Buffers (if
"					less than 2 tabs open)
"			'confirm' - all changed files with confirmation for every file
"			'modified' - all changed files
"			'all' - all files under ./src folder
"			'staged' - all files listed in stage-list.txt file
"			'onefile' - single file specified in param 1
"Param3: (optional) - list [] of other params
"		0:
"		  'testAndDeploy' - run tests in all files that contain 'testMethod' and if
"					successful then deploy
"		  'checkOnly' - run tests but do not deploy
"		  'checkOnlyDeploy' - as normal deployment but use 'checkOnly' ant flag
"		1: 
"		  className - if provided then only run tests in the specified class
"		2:
"		  methodName - if provided then only run specified method in the class
"		  provided as 1:
"Param4: destination project name, must match one of .properties file with
"		login details
function! apex#MakeProject(...)
	let filePath = expand("%:p")
	let l:mode = 'modified'
	if a:0 >0 && len(a:1) >0  
		let filePath = a:1
	endif

	let providedProjectName = ''

	if a:0 >1 && index(s:MAKE_MODES, a:2) >= 0
		let l:mode = a:2
	endif

	"process list of optional params ['testAndDeploy',...]
	let l:runTest = 0
	let l:checkOnly = 0
	let l:checkDeploy = 0
	let params = []
	if a:0 >2
		let params = a:3
		let l:runTest = index(params, 'testAndDeploy') >=0
		let l:checkOnly = index(params, 'checkOnly') >=0
		let l:checkDeploy = index(params, 'checkOnlyDeploy') >=0
	endif

	if a:0 >3 && strlen(providedProjectName) < 1
		" if project name is provided via tab completion then spaces in it
		" will be escaped, so have to unescape otherwise funcions like
		" filereadable() do not understand such path name
		let providedProjectName = apexUtil#unescapeFileName(a:4)
	endif

	let propertiesFolder = apexOs#removeTrailingPathSeparator(g:apex_properties_folder)
	let projectPair = apex#getSFDCProjectPathAndName(filePath)
	let projectPath = '' "projectPair.path
	let projectName = projectPair.name

	"check if properties file exist
	if len(providedProjectName) > 0 && len(apex#getPropertiesFilePath(providedProjectName)) >0
		let projectName = providedProjectName
	endif

	echo "project.name='" . projectName . "'"

	if 'all' != l:mode
		" prepare pack
		"			{project: "project name", 
		"			 preparedSrcPath: "/path/to/prepared/src", 
		"			 projectPath: "/path/to/original/Project/",
		"			 timeMap: {"classes/MyClass.cls-meta.xml": src-time}}
		let projectDescriptor = s:prepareApexPackage(filePath, l:mode)
		if len(projectDescriptor) <=0 
			echomsg "Nothing to deploy"
			return 0
		endif


		let preparedTempProjectPath = apexOs#removeTrailingPathSeparator(apexOs#splitPath(projectDescriptor.preparedSrcPath).head)
		"let projectName = projectDescriptor.project
		let projectPath = projectDescriptor.projectPath "path to temp folder with prepared for deploy files


		" copy current package XML into the work folder
		let tempPackXmlPath = apexOs#joinPath(projectDescriptor.preparedSrcPath, 'package.xml')
		call apexOs#copyFile(apexOs#joinPath(projectPath, s:SRC_DIR_NAME, "package.xml"),  tempPackXmlPath)

		" check if package.xml contains all files prepared for deployment
		" and add missing components if necessary
		let tempPackXmlPath = apexMetaXml#packageXmlGenerate(projectName, projectDescriptor.projectPath, tempPackXmlPath, 'p')
		if len(tempPackXmlPath) > 0
			call apexUtil#info("Saved updated ". tempPackXmlPath)
		endif

	else "all
		" deploy project in its entirety regardless of 'modified' files status
		"let projectPair = apex#getSFDCProjectPathAndName(filePath)
		let projectPath = projectPair.path "path to current project, not the temp one but real
		"let projectName = projectPair.name
		let preparedTempProjectPath = projectPath
		" as we are not copying sources to temp folder we need to make sure that
		" it exists because it is needed for ant error log anyway
		call apexOs#createTempDir('wipe')
	endif
	
	let result = -1
	if l:runTest || l:checkOnly
		let ANT_ERROR_LOG = apexTest#prepareFilesAndRunTests(projectName, projectDescriptor.preparedSrcPath, params)
		if filereadable(ANT_ERROR_LOG)
			let result = s:parseErrorLog(ANT_ERROR_LOG, apexOs#joinPath([projectPath, s:SRC_DIR_NAME]))
		endif
	else
		let useCheckOnly = l:checkDeploy ? 'checkOnly' : ''
		let ANT_ERROR_LOG = apexAnt#deploy(projectName, preparedTempProjectPath, useCheckOnly)
		if len(ANT_ERROR_LOG) > 0
			" check if BUILD FAILED
			let result = s:parseErrorLog(ANT_ERROR_LOG, apexOs#joinPath([projectPath, s:SRC_DIR_NAME]))
		else
			"looks like we did not get to execute ant. error should have been
			"displayed by now
			return -1
		endif

	endif

	if result == 0 && 'all' != l:mode && !l:checkOnly && !l:checkDeploy
		" no errors found, mark files as deployed
		for metaFilePath in keys(projectDescriptor.timeMap)
			call apexOs#setftime(metaFilePath, projectDescriptor.timeMap[metaFilePath])
			" show what files we have just deployed
			"echo metaFilePath
		endfor	
		if 'staged' == l:mode
			"clear stage cache
			let response = input('Clear Stage : [Y/n]? ')
			if 'n' != response && 'N' != response
				call apexStage#clear(filePath)
			endif	
		endif	
	endif


	return result
endfun

""""""""""""""""""""""""""""""""""""""""""""""""
" ApexDeploy 
""""""""""""""""""""""""""""""""""""""""""""""""
" Args:
" method: 
"			'open' - deploy only files from currently open Tabs or Buffers (if
"					less than 2 tabs open)
"			'confirm' - all changed files with confirmation for every file
"			'modified' - all changed files
"			'all' - all files under ./src folder
"			'staged' - all files listed in stage-list.txt file
"			'onefile' - single file specified in param 1
" Param1: mode name: 'deploy' or 'checkOnly'
"					if not specified then 'deploy' is used	
" Param2: destination project name, must match one of .properties file with
" "		login details
"
function! apex#deploy(method, ...)
	let modeName = a:0 > 0? a:1 : 'deploy'
	if 'checkOnly' == modeName
		let modeName = 'checkOnlyDeploy'
	endif	
	let projectName = a:0 > 1? a:2 : ''

	call apex#MakeProject('', a:method, [modeName], projectName)
endfunction
" project name completion
" list .properties file names without extension
" Args:
" arg: ArgLead - the leading portion of the argument currently being
"			   completed on
" line: CmdLine - the entire command line
" pos: CursorPos - the cursor position in it (byte index)
"
function! apex#listProjectNames(arg, line, pos)
	let fullPaths = apexOs#glob(g:apex_properties_folder . "**/*.properties")
	let res = []
	for fullName in fullPaths
		let fName = apexOs#splitPath(fullName).tail
		let fName = fnamemodify(fName, ":r") " remove .properties
		"take into account file prefix which user have already entered
		if 0 == len(a:arg) || match(fName, a:arg) >= 0 
			call add(res, fnameescape(fName))
		endif	
	endfor
	return res
endfunction	

function! s:listModeNames(arg, line, pos)
	return ['deploy', 'checkOnly', 'deployIgnoreConflicts']
endfunction	

" Args:
" arg: ArgLead - the leading portion of the argument currently being
"			   completed on
" line: CmdLine - the entire command line
" pos: CursorPos - the cursor position in it (byte index)
"
function! apex#completeDeployParams(arg, line, pos)
	let l = split(a:line[:a:pos-1], '\%(\%(\%(^\|[^\\]\)\\\)\@<!\s\)\+', 1)
	"let n = len(l) - index(l, 'ApexDeploy') - 2
	let n = len(l) - 0 - 2
	"echomsg 'arg='.a:arg.'; n='.n.'; pos='.a:pos.'; line='.a:line
	let funcs = ['s:listModeNames', 'apex#listProjectNames']
	if n >= len(funcs)
		return ""
	else
		return call(funcs[n], [a:arg, a:line, a:pos])
endfunction	


" use this method to validate existance of .properties file for specified
" project name
" Args:
" param 1: projectName - name of project which must match existing .properties
" file with login details
function! apex#getPropertiesFilePath(projectName)
	let l:providedProjectName = substitute(a:projectName, '.properties$', '', '')
	let l:propertiesFolder = apexOs#removeTrailingPathSeparator(g:apex_properties_folder)

	let l:propFilePath = apexOs#joinPath([l:propertiesFolder, l:providedProjectName]).".properties"
	"check if we need to append .properties
	"echo "providedProjectName=".l:providedProjectName
	"echo "propFilePath=".l:propFilePath
	if !filereadable(l:propFilePath)
		echoerr l:propFilePath." with login details does not exist or not readable."
		return
	endif
	return l:propFilePath
endfunction

" return existing or create new and return path to
" plugin cache directory
function! apex#getCacheFolderPath(projectPath)
	let cacheFolderPath = apexOs#joinPath([a:projectPath, s:CACHE_FOLDER_NAME])

	if !isdirectory(cacheFolderPath)
		"cache directory does not exist, need to create it first
		call apexOs#createDir(cacheFolderPath)
	endif
	return cacheFolderPath
endfunction
""""""""""""""""""""""""""""""""""""""""""""""""
" Get SFDC project path and name assuming we have a standard folder structure and
" project folder matches SFDC project name
" i.e.
" <Project-Folder>
"	src
"		classes
"		triggers
"		objects
"		...
" Note: there is a side effect - if filePath = "" then Vim does finddir from
" currently open buffer/file path
" @return: {path:"/path/to/project/", name:"project name"}
""""""""""""""""""""""""""""""""""""""""""""""""
function! apex#getSFDCProjectPathAndName(filePath) 
	" go up until we find ./src/ folder
	" finddir does not work on win32, vim does not understand drive letter	
	" "let srcDir = finddir(s:SRC_DIR_NAME, fnameescape(a:filePath). ';')
	let path = a:filePath
	let srcDirParent = ""
	while len(path) > 0
		let pathPair = apexOs#splitPath(path)
		if pathPair.tail == s:SRC_DIR_NAME
			let srcDirParent = pathPair.head
			break
		endif	
		let path = pathPair.head
	endwhile	

	if srcDirParent == ""
		echoerr "src folder not found"
		return {'path': "", 'name': ""}
	endif
	let projectFolder = srcDirParent 
	let projectName = apexOs#splitPath( projectFolder).tail
	return {'path': projectFolder, 'name': projectName}
endfun

" return full path to SRC folder
" ex: "/path/to/project-name/src"
" Args:
" filePath - [optional] if provided then this fiel is used to determine src
" path, otherwise expand("%:p") is used
function! apex#getApexProjectSrcPath(...)
	let filePath = expand("%:p")
	if a:0 >0
		let filePath = a:1
	endif	
	let projectPair = apex#getSFDCProjectPathAndName(filePath)
	return apexOs#joinPath([projectPair.path, s:SRC_DIR_NAME])
endfunction
""""""""""""""""""""""""""""""""""""""""""""""""
" Apex Project files refresh from SFDC 
"
" Method accepts No params 
"	system will try to figure out current Apex Project and
"   refresh it using project name for Login properties and for target /src/
"   folder
"   ex: 
"   call apex#refreshProject() 
"   will refresh project where currently open file resides
"
"	Method relies on presence of shell script which calls ANT build
""""""""""""""""""""""""""""""""""""""""""""""""
function! apex#refreshProject()

	let filePath = expand("%:p")
	if apex#hasChangedFiles(filePath)
		" display changed files
		echohl WarningMsg
		echomsg "There are modified and not synchronised file(s)"
		echohl None 
		call apex#printChangedFiles(filePath)

		echohl WarningMsg
		let response = input('Are you sure you want to lose local changes [y/N]? ')
		echohl None 
		if 'y' != response && 'Y' != response
			return 
		endif	
	endif	
	let projectPair = apex#getSFDCProjectPathAndName(filePath)

    echo "using '".projectPair.name.".properties'"." for project '".projectPair.path."'"
	" backup files
	call s:backupOpenFiles(projectPair.path, projectPair.name)
	" execute ant job
	let ANT_ERROR_LOG = apexAnt#refresh(projectPair.name, projectPair.path)
endfun

" refresh a single file from SFDC
" param: filePath full path to the target file
"
" the idea is that unlike full project refresh 
" with single file refresh we use temp location for ant sf:retrieve task 
" and then copy single file from that location
"
function! apex#refreshFile(filePath) 
	if len(a:filePath) <1
		echoerr "parameter:filePath is required"
		return
	endif
	let projectDescriptor = s:prepareApexPackage(a:filePath, 'onefile')
	" backup files
	call s:backupOpenFiles(projectDescriptor.projectPath, projectDescriptor.project)
	"
	if len(projectDescriptor) <=0 
		echomsg "Nothing to deploy"
		return 0
	endif
	let preparedTempProjectPath = apexOs#removeTrailingPathSeparator(apexOs#splitPath(projectDescriptor.preparedSrcPath).head)
	let propertiesFolder = apexOs#removeTrailingPathSeparator(g:apex_properties_folder)

	" copy package XML into the work folder
	call apexOs#copyFile(apexOs#joinPath([projectDescriptor.projectPath, s:SRC_DIR_NAME, "package.xml"]), apexOs#joinPath([projectDescriptor.preparedSrcPath, 'package.xml']))
	
	" execute ant job for temp project location
	let ANT_ERROR_LOG = apexAnt#refresh(projectDescriptor.project, preparedTempProjectPath)

	" assuming no error hapenned copy refreshed file back to Project
	" timeMap: {"classes/MyClass.cls-meta.xml": src-time}
	" file path relative project folder 
	"
	let fSrcRelativeProjectFolder = strpart(a:filePath, len(projectDescriptor.projectPath))
	" copy refreshed file back in Project
	"
	let fullRefreshedFilePath = apexOs#joinPath([preparedTempProjectPath, fSrcRelativeProjectFolder])
	if filereadable(fullRefreshedFilePath)
		call apexOs#copyFile(fullRefreshedFilePath, a:filePath)

		" check if we need to copy -meta.xml as well
		let fMetaFullPath = a:filePath.'-meta.xml'
		if filewritable(fMetaFullPath)
			let fMetaRalativePath = fSrcRelativeProjectFolder.'-meta.xml'
			call apexOs#copyFile(apexOs#joinPath([preparedTempProjectPath, fMetaRalativePath]), fMetaFullPath)
		endif
	else
		echoerr 'It does not seem like file has been downloaded from SFDC during refresh'
	endif

endfunction	


" Do a simple True/False check to see if there are files which are modified
" locally and have not been synchronised with SFDC
" @return 
"	1 - there are modified files
"	0 - no modified files
function! apex#hasChangedFiles(filePath)
	let projectPair = apex#getSFDCProjectPathAndName(a:filePath)
	let projectPath = projectPair.path

	"{'filesByFolder': {'folder-name' : [files list]}, 
	" 'timeMap': {"classes/MyClass.cls-meta.xml": src-time} }
	let fileDescriptor = s:prepareFileDescriptor(projectPath, 'modified', '')
	"echo fileDescriptor
	if empty(fileDescriptor) || empty(fileDescriptor.filesByFolder)
		"echomsg 'Nothing to deploy'
		return 0
	endif

	return 1
endfunction

" display list of modified files - i.e. those which would be deployed if
" MakeProject is called 
function! apex#printChangedFiles(filePath)
	let projectPair = apex#getSFDCProjectPathAndName(a:filePath)
	let projectPath = projectPair.path

	"{'filesByFolder': {'folder-name' : [files list]}, 
	" 'timeMap': {"classes/MyClass.cls-meta.xml": src-time} }
	let fileDescriptor = s:prepareFileDescriptor(projectPath, 'modified', '')
	let dirs =keys(fileDescriptor.filesByFolder)

	let nothingModified = 1
	for dirName in dirs
		echo dirName
		let filesToDeploy = fileDescriptor.filesByFolder[dirName]
		" copy files
		for fName in filesToDeploy
			"call apexOs#copyFile(projectPath . fName, tempDir . fName)
			if match(fName, '-meta.xml') < 0
				let fName = substitute(fName, dirName, "    ", "")
				echo fName
				let nothingModified = 0
			endif	
		endfor	
	endfor	
	if nothingModified
		echo "no modified files"
	endif	
endfunction


" in some cases we need to backup all open/modified files 
" ex: before refresh from SFDC
function! s:backupOpenFiles(projectPath, projectName)
	let bufferList = apex#getOpenBuffers(a:projectPath)
	"
	let timeStr = strftime(g:apex_backup_folder_time_format)	
	let backupDir = apexOs#joinPath([apexOs#getBackupFolder(), a:projectName, timeStr])
	if len(bufferList) < 1
		return
	endif
	if !isdirectory(backupDir)
		call apexOs#createDir(backupDir)
	endif	
	let filesMap = {}
	for n in bufferList
		let fullpath = expand('#'.n.':p')
		let fName = expand('#'.n.':t')
		let filesMap[fName] = 1
		
		call apexOs#copyFile(fullpath, apexOs#joinPath([backupDir, fName]))
	endfor	

	" now backup modified files which are not open
	"{'filesByFolder': {'folder-name' : [files list]}, 
	" 'timeMap': {"classes/MyClass.cls-meta.xml": src-time} }
	let fileDescriptor = s:prepareFileDescriptor(a:projectPath, 'modified', '')
	let dirs =keys(fileDescriptor.filesByFolder)
	"echo filesMap
	for dirName in dirs
		let fullDirPath = apexOs#joinPath([a:projectPath,dirName])
		"echo "fullDirPath=" . fullDirPath
		let filesToDeploy = fileDescriptor.filesByFolder[dirName]
		" copy files
		for fNameInDir in filesToDeploy
			let fName = apexOs#splitPath(fNameInDir).tail
			if has_key(filesMap, fName)
				continue
			endif	
			if match(fName, '-meta.xml') < 0
				let fullSourcePath = apexOs#joinPath([a:projectPath, fNameInDir])
				let fullBackupPath = apexOs#joinPath([backupDir, fName])

				"echo 'from: '.fullSourcePath . ' to: '.fullBackupPath
				call apexOs#copyFile(fullSourcePath, fullBackupPath)
			endif	
		endfor	
	endfor	

	let g:apex_last_backup_folder = backupDir
endfunction	

" function! BackupOpenFiles()
"	 call s:backupOpenFiles('/home/andrey/eclipse.workspace/SForce', 'SForce')
" endfunction	

" get all available buffers which have file path relative current project
" Param1: projectPath - full path to project
" Param2: [optional] deployable extensions only
" return: [1, 5, 6, 7, 8] - list of buffer numbers with project files 
function! apex#getOpenBuffers(projectPath, ...)
	let last_buffer = bufnr('$')
	let n = 1
	let buffersMap = {}
	let projectPathNormal = substitute(a:projectPath, '\', '/', 'g')
	let extPattern = join(s:APEX_EXTENSIONS, "\\|\\.") 
	let extPattern = "\\." .extPattern . "$"
	let deployableOnly = 0
	if a:0 > 0 && 'deployableOnly' == a:1
		let deployableOnly = 1
	endif

	while n <= last_buffer
		if buflisted(n) 
			if getbufvar(n, '&modified')
				echohl ErrorMsg
				echomsg 'No write since last change for buffer'
				echohl None
			else
				" check if buffer belongs to the project
				let fullpath = expand('#'.n.':p')
				if deployableOnly
					" check if file is supported
					if match(fullpath, extPattern) <= 0
						"echo "skip file: " . fullpath
						let n = n+1
						continue
					endif
				endif
				let fullpath = substitute(fullpath, '\', '/', 'g')
				if len(fullpath) >0 && !has_key(buffersMap, fullpath) && 0 == match(fullpath, projectPathNormal)
					let buffersMap[fullpath] = n
				endif
			endif
		endif
		let n = n+1
	endwhile

	return values(buffersMap)
endfunction
""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
"Param: filepath - path to any file in the current Apex project
"Param: mode				
" if mode == 'open' then prepare files in currently Open buffers
" if mode == 'confirm' then ask confirmation for every changed file
" if mode == 'onefile' deploy only current file 
" 
" Else prepare *all* and *only* changed files for deployment/update into SFDC 
"
"   1. Find 
"		*.trigger, 
"		*.cls, 
"		*.page, 
"		*.scf, 
"		*.resource 
"		*.component
"		files where <full-file-name>-meta.xml is older than actual source file
"
"   2.  Clean/Create a temp /src/ folder
"		Copy all such files (in folders) with -meta.xml counterparts into the temp /src/ folder
"Return: {project: "project name", 
"			preparedSrcPath: "/path/to/prepared/src", 
"			projectPath: "/path/to/original/Project/", 
"			timeMap: {"classes/MyClass.cls-meta.xml": src-time}} 
"		or nothing
function! s:prepareApexPackage(filePath, mode)
	let projectPair = apex#getSFDCProjectPathAndName(a:filePath)
	let projectPath = projectPair.path

	echo "project.path='" . projectPath . "'"

	let type = 'modified'
	if index(s:MAKE_MODES, a:mode) >= 0
		let type = a:mode
	endif

	"{'filesByFolder': {'folder-name' : [files list]}, 
	" 'timeMap': {"classes/MyClass.cls-meta.xml": src-time} }
	let fileDescriptor = s:prepareFileDescriptor(projectPath, type, a:filePath)
	if len(fileDescriptor) >0
		let dirsToCreate =keys(fileDescriptor.filesByFolder)
		if len(dirsToCreate) >0
			let tempDir = apexOs#createTempDir('wipe')
			"append path separator
			let tempDir = tempDir . apexOs#getPathSeparator()  

			for dirName in dirsToCreate
				"echo "dirName:".dirName . "#"
				let fullDirPath = tempDir . dirName
				"echo "fullDirPath=" . fullDirPath
				call apexOs#createDir(fullDirPath)
				let filesToDeploy = fileDescriptor.filesByFolder[dirName]
				" copy files
				for fName in filesToDeploy
					call apexOs#copyFile(projectPath . fName, tempDir . fName)
				endfor	
			endfor	
			return { "project": projectPair.name, "projectPath":  projectPair.path, "preparedSrcPath": tempDir . s:SRC_DIR_NAME, "timeMap":fileDescriptor.timeMap}
		endif
	endif
	return {} " nothing to deploy
endfun

" with this method we can specify extra files to be added to deployment
" package, in addition to files covered by 'modified' deployment mode
let s:extra_files = []
function! apex#cacheExtraFile(filePath)
	if !s:isCachedExtraFile(a:filePath)
		call add(s:extra_files, a:filePath)
	endif

endfunction	

function! s:isCachedExtraFile(filePath)
	return index(s:extra_files, a:filePath) >= 0
endfunction	


" prepares description (list and time) of files to be packed into deployment
" package
"Args:
" @param: projectPath - "/path/to/current/Project/"
" @param: type - 'open|confirm|modified|staged'
"	if 'modified' then prepare *only* changed files for deployment/update into SFDC 
"   Find 
"		*.trigger, 
"		*.cls, 
"		*.page, 
"		*.scf, 
"		*.resource 
"		*.component
"	files where <full-file-name>-meta.xml is older than actual source file
"	File is considered 'modified' if its last modified date does not match its
"	'-meta.xml' counterpart
"
" @param: filePath - path to a single file, used only with mode=='onefile'
" @return: {'filesByFolder': {'folder-name' : [files list relatively project root]}, 
"			'timeMap': {"full-path-to-meta.xml": src-time} }
"	e.g. 
" {'filesByFolder': {'src/classes/': ['src/classes/MyClass.cls-meta.xml', 'src/classes/MyClass.cls']}, 
"  'timeMap': {'/full/path/to/project/src/classes/MyClass.cls-meta.xml': 123456789}}
"
function! s:prepareFileDescriptor(projectPath, mode, filePath )
	let projectPath = a:projectPath	

	let filesByFolder = {}
	let timeMap = {}
	let type = 'modified'

	if len(a:mode) >0 
		let type = a:mode
	endif

	if 'modified' == type || 'confirm' == type
		let extPattern = join(s:APEX_EXTENSIONS_WITH_META_XML, "\\|\\.") 
		let extPattern = "\\." .extPattern . "$"


		let files = apexOs#glob(projectPath . "**/*-meta.xml")
		"echo "files=" . files
		let filesToDeploy = []

		let suffixLen = len("-meta.xml")

		for fMetaFullPath in files
			let fSrcFullPath = strpart(fMetaFullPath, 0, len(fMetaFullPath) - suffixLen)

			" check if file is supported
			if match(fSrcFullPath, extPattern) <= 0
				"echo "skip file: " . fSrcFullPath
				continue
			endif	
			
			"echo 'src=' . fSrcFullPath
			let metaTime = getftime(fMetaFullPath) 
			let srcTime = getftime(fSrcFullPath) 
			"
			if abs(srcTime - metaTime) > s:FILE_TIME_DIFF_TOLERANCE_SEC || s:isCachedExtraFile(fSrcFullPath)
				" get  src/classes/MyFile.cls-meta.xml fom /path/to/project/src/classes/MyFile.cls-meta.xml
				"let fMeta = substitute(fMetaFullPath, projectPath, "", "") 
				let fMeta = strpart(fMetaFullPath, len(projectPath))
				let fSrc = strpart(fMeta, 0, len(fMeta) - suffixLen)
				"echo "modified: " . fSrc
				if 'confirm' == type
					let response = input('Deploy: '.fSrc.' [y/n]? ')
					if 'y' != response && 'Y' != response
						continue
					endif	
				endif
				" get relative sub-folder: src/[classes|triggers|pages], etc
				let relativeFolderPathPair = apexOs#splitPath(fSrc)
				let folder = relativeFolderPathPair.head
				let filesToDeploy = []
				if has_key(filesByFolder, folder)
					let filesToDeploy = filesByFolder[folder]
				endif	

				let timeMap[fMetaFullPath] = srcTime

				call add(filesToDeploy, fMeta)
				call add(filesToDeploy, fSrc)
				let filesByFolder[folder] = filesToDeploy
			endif
		endfor
	elseif 'open' == type
		"
		" get a list of all buffers in all tabs
		let bufferList = apex#getOpenBuffers(a:projectPath, 'deployableOnly')
		echo bufferList
		echohl WarningMsg | echo 'Following files will be deployed' | echohl None 
		for n in bufferList
			"if buflisted(n)

			" get  src/classes/MyFile.cls fom /path/to/project/src/classes/MyFile.cls
			"let fSrc = substitute(fullpath, projectPath, "", "") 
			let fullpath = expand('#'.n.':p')
			let fSrc = strpart(fullpath, len(projectPath))

			let relativeFolderPathPair = apexOs#splitPath(fSrc)
			let folder = relativeFolderPathPair.head
			let filesToDeploy = []
			if has_key(filesByFolder, folder)
				let filesToDeploy = filesByFolder[folder]
			endif	

			echo '    '.fSrc
			call add(filesToDeploy, fSrc)
			let filesByFolder[folder] = filesToDeploy
			"
			"check if file has -meta.xml counterpart
			let fMetaFullPath = fullpath.'-meta.xml'
			if filewritable(fMetaFullPath)
				" no need to set meta file time after deploy
				let srcTime = getftime(fullpath) 
				let timeMap[fMetaFullPath] = srcTime
				call add(filesToDeploy, fSrc.'-meta.xml')
			endif

			"echo 'name='.expand('#'.n.':p')
			"endif	
		endfor	
		" check if user is happy to deploy prepared files
		let response = input('Deploy [y/N]? ')
		if 'y' == response || 'Y' == response
		else
			"ensure blank line
			echo "\n" 
			return {}
		endif	
	elseif 'onefile' == type
		let fullpath = a:filePath
		if len(fullpath) <1
			echoerr 'parameter filePath is required'
			return {}
		endif	
		let fSrc = strpart(fullpath, len(projectPath))
		let relativeFolderPathPair = apexOs#splitPath(fSrc)
		let folder = relativeFolderPathPair.head
		let filesToDeploy = [] 
		call add(filesToDeploy, fSrc)
		let filesByFolder[folder] = filesToDeploy
		echo '    '.fSrc
		"check if file has -meta.xml counterpart
		let fMetaFullPath = fullpath.'-meta.xml'
		if filewritable(fMetaFullPath)
			let srcTime = getftime(fullpath) 
			let timeMap[fMetaFullPath] = srcTime
			call add(filesToDeploy, fSrc.'-meta.xml')
		endif
	elseif 'staged' == type
		if len(projectPath) <1
			echoerr 'parameter projectPath is required'
			return {}
		endif
		let srcPath = apexOs#joinPath([projectPath, s:SRC_DIR_NAME])
		let stageFilePath = apexStage#getStageFilePath(projectPath)
		for relFileName in apexStage#list(projectPath)
			"echo "staged relFileName=".relFileName
			"relFileName = 'classes/MyClass.cls'
			if len(relFileName) > 0 && 0 != stridx(relFileName, '#') " skip blank lines
				let folder = apexOs#joinPath([s:SRC_DIR_NAME, apexOs#splitPath(relFileName).head]) "src/classes/
				let fSrc = apexOs#joinPath([s:SRC_DIR_NAME, relFileName ]) "src/classes/MyClass.cls
				let fullPath = apexOs#joinPath([projectPath, fSrc ]) "/path/to/project/src/classes/MyClass.cls
				let filesToDeploy = []
				if has_key(filesByFolder, folder)
					let filesToDeploy = filesByFolder[folder]
				endif	
				call add(filesToDeploy, fSrc)
				"check if file has -meta.xml counterpart
				let fMetaFullPath = fullPath.'-meta.xml'
				if filewritable(fMetaFullPath)
					let srcTime = getftime(fullPath) 
					let timeMap[fMetaFullPath] = srcTime
					call add(filesToDeploy, fSrc.'-meta.xml')
				endif

				let filesByFolder[folder] = filesToDeploy
			endif

		endfor	
	else
		echoerr 'unsupported type='.type
		return {}
	endif
	let s:extra_files = [] " clear extra files cache
	return {'filesByFolder':filesByFolder, 'timeMap':timeMap}
endfunction	

" parse Error Log returned by ANT
" logFilePath - full path to log file
" srcPath - full path to the folder which contains classes, triggers,
"			 pages, etc folders, usually this is path to /src/ folder
" returns: 0 if no errors, and non zero value otherwise
"
" TODO: add another branch for locked org, where error looks like this
" ----
" BUILD FAILED
" /home/andrey/eclipse-deployment/gvim-deployment/build.xml:50: Failed to
" process the request successfully. Cause(ALREADY_IN_PROCESS): null: The
" changes you
"  requested require salesforce.com to temporarily lock your organization's
"  administration setup. However, the administration setup has already been
"  locked
"  by another change. Please wait for the previous action to finish, then try
"  again later.
" ----
function! s:parseErrorLog(logFilePath, srcPath)

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
	if len(apexUtil#grepFile(fileName, 'BUILD SUCCESSFUL')) > 0
		echomsg "No errors found" 
		return 0
	endif

	echo "Build failed" 
	if len(apexUtil#grepFile(fileName, 'Error: \|Test failure', 'Q')) > 0
		" if we are still here then the above line did not fail and found the
		" key
		call s:processQuickfix(a:srcPath)
	else
		" display errors in a new tab for review
		:tabnew
		exe "e ".fnameescape(fileName)
		call apexUtil#error("Build failed, but No usual errors identified")
	endif
	return 1 " error found in the log file
endfunction	

" Process Compile and Unit Test errors and populate quickfix
"
" http://vim.1045645.n5.nabble.com/execute-command-in-vim-grep-results-td3236900.html
" http://vim.wikia.com/wiki/Automatically_sort_Quickfix_list
" 
" Param: srcPath - full path to the folder which contains classes, triggers,
"					pages, etc folders, usually this is path to /src/ folder
function! s:processQuickfix(srcPath)
	let rawErrorList = getqflist()
	let prettyErrorList = []
	for item in rawErrorList
		" get text from quickfix, i.e. full error line returned by Ant and then vimgrep
		let text = item.text

		"check if this was a compile error
		let errLine = s:processCompileError(text)

		if len(errLine) < 3
			"check if this was unit test failure
			let errLine = apexTest#parseUnitTestFailure(text)
		endif

		if len(errLine) > 0
			let errLine.filename = a:srcPath .apexOs#getPathSeparator(). errLine.filename

			"echo errLine
			call add(prettyErrorList, errLine)
			copen
		endif
	endfor	

	call setqflist(prettyErrorList)

endfunction	


" ant error return looks like this
" Error in class
" Error: classes/EventFromLeadSupport.cls(25,24):unexpected token: createEvents'
"
" Error in page (not always contains line number)
" Error: pages/VimPluginTest.page(VimPluginTest):Unknown property 'ProfileTemplateController.varMainTitle'
" Error: pages/VimPluginTest.page(VimPluginTest):Unsupported attribute escape
"		 in <apex:inputField> in VimPluginTest at line 49 column 46
" 
" Return:  dictionary: see :help setqflist()
"         {
"			filename: file name relatively project/src folder, 
"				e.g. "pages/MyPage.page"
"			lnum: line number in the file
"			col:  column number
"			text: description of the error
"         }
function! s:processCompileError(text)
	let text = a:text
	let errLine = {}
	" remove 'Error: ' prefix
	let text = strpart(text, stridx(text, 'Error: ') + len('Error: ')) 

	"classes/EventFromLeadSupport.cls(25,24):unexpected token: createEvents'
	"get folder and file name
	let path = strpart(text, 0, stridx(text, "("))
	let text = strpart(text, len(path))
	"(25,24):unexpected token: createEvents'
	"get line and column number
	let lineAndColumn = strpart(text, 0, stridx(text, ")"))
	let text = strpart(text, len(lineAndColumn)+2)
	"echo 'error text='.text.'#'

	let lineAndColumnPair = split(substitute(lineAndColumn, "[\(\)]", "", "g"), ",")
	" lineAndColumnPair has only 1 element then we are most likely parsing
	" VF page error which returns (page-name) instead of (line, column)
	if len(lineAndColumnPair) <2
		" check if we are dealing with the Page error which does have
		" column/line numbers in following format:
		" ...Unsupported attribute escape in <apex:inputField> in VimPluginTest at line 49 column 46
		let lineNumIndex = stridx(text, " at line ")
		if lineNumIndex > 0
			let coordinateText = strpart(text, lineNumIndex + len(" at line "))
			" coordinateText = "49 column 46"
			let lineAndColumnPair = split(coordinateText, " column ")
		endif	
	endif	

	"echo lineAndColumnPair
	" init new quickfix line
	if len(lineAndColumnPair) >1 && len(path) > 0
		let errLine.lnum = lineAndColumnPair[0]
		let errLine.col = lineAndColumnPair[1]
		let errLine.text = text
		let errLine.filename = path
	endif
	return errLine
endfunction

"""""""""""""""""""""""""""""""""""""""""""""""""""
" Utility methods
"""""""""""""""""""""""""""""""""""""""""""""""""""
" close all empty quickfix windows
function! CloseEmptyQuickfixes()
    let last_buffer = bufnr('$')
	let n = 1
	while n <= last_buffer
		if buflisted(n)
			if "quickfix" == getbufvar(n, '&buftype')
				if empty(getqflist())
					silent exe 'bdel ' . n
				endif	
			endif
		endif
		let n = n+1
	endwhile
endfun





" =====================================================
"function! MyTest ()
	"call s:prepareApexPackage("/home/andrey/eclipse.workspace/SForce/src/classes/TestCRAccess.cls")
	"call s:prepareApexPackage("/home/andrey/eclipse.workspace/Reed (CITDev1)/src/triggers/OpportunityBefore.trigger")
	"call apexOs#createDir("/home/andrey/temp/Vim-Deployment/Project", "src")
	"call apexOs#createTempDir()
	"call apex#MakeProject("/home/andrey/eclipse.workspace/SForce/src/classes/TestCRAccess.cls")
	"
	"call s:parseErrorLog("/tmp/gvim-deployment-errors-SUCCESS.log", "/home/andrey/eclipse.workspace/SForce/src")
	"call s:parseErrorLog("/tmp/gvim-deployment-errors-FAILED-NON-STANDARD.log", "/home/andrey/eclipse.workspace/SForce/src")
	"
	"call s:parseErrorLog("/tmp/gvim-deployment-errors-FAILED-STANDARD.log", "/home/andrey/eclipse.workspace/SForce/src")
	"call s:parseErrorLog("/tmp/gvim-deployment-errors-FAILED-Page-With-Coordinates.log", "/home/andrey/eclipse.workspace/SForce/src")
	"echo expand("<sfile>:p")
"endfun
