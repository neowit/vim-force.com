" File: apexDelete.vim
" Author: Andrey Gavrikov 
" Version: 0.2
" Last Modified: 2014-02-08
" Copyright: Copyright (C) 2010-2012 Andrey Gavrikov
"            Permission is hereby granted to use and distribute this code,
"            with or without modifications, provided that this copyright
"            notice is copied with it. Like anything else that's free,
"            this plugin is provided *as is* and comes with no warranty of any
"            kind, either expressed or implied. In no event will the copyright
"            holder be liable for any damages resulting from the use of this
"            software.
"
" apexDelete.vim - part of vim-force.com plugin
" Methods handling metadata Delete, aka destructiveChanges

if exists("g:loaded_apex_delete") || &compatible 
	finish
endif
let g:loaded_apex_delete = 1

" run destructive Delete on Staged files
"Args:
"Param1: (optional) checkOnly|doDelete, default is 'doDelete'
"Param2: (optional) destination project name, must match one of .properties file
"		
function! apexDelete#run(...) abort
	let filePath = expand("%:p") "default file
	let projectPair = apex#getSFDCProjectPathAndName(filePath)
	let projectName = projectPair.name
	let projectPath = projectPair.path
	if empty(projectName)
		echoerr "failed to determine project location using file path ".filePath
		return
	endif
	if len(apexStage#list(projectPath)) < 1
		call apexUtil#warning( "Nothing staged. Add files with :ApexStageAdd first")
		return
	endif

	let l:mode = ''
	let providedProjectName = projectName
	if a:0 > 0
		let l:mode = a:1
		if a:0 > 1
			let providedProjectName = a:2
		endif
	endif
	
	let specificComponentsFilePath = tempname() . 'delete-list.txt'
	"let xmlNameByDirName = apexRetrieve#getTypeXmlByFolder(projectName, projectPath, 0)
	" {'weblinks': 'CustomPageWebLink', 'labels' : 'CustomLabels'}
	let componentsList = apexStage#list(projectPath)
	call writefile(componentsList, specificComponentsFilePath)
	let fileCount = len(componentsList)

	if fileCount > 0
		call apexUtil#warning('About to delete '.fileCount.' staged file(s).')
		let backupDir = ''
		let response = apexUtil#input('Backup files from the target Org "'.projectName.'" before DELETE [y/N]? ', 'yYnN', 'n')
		if 'y' == response || 'Y' == response
			"backup files
			"
			let backupDir = apexOs#joinPath([apexOs#getBackupFolder(),projectName])
			if !isdirectory(backupDir)
				call apexOs#createDir(backupDir)
			endif	

			let resMap = apexTooling#bulkRetrieve(providedProjectName, projectPath, specificComponentsFilePath, "file-paths", backupDir)
			if 'true' != resMap["success"]
				return
			endif
			call apexUtil#info("remote version of file(s) is saved in: " . backupDir)
		endif	

		let response = apexUtil#input('Delete local files if remote delete successful [y/N]? ', 'yYnN', 'n')
		let deleteLocalFiles = 'y' == response || 'Y' == response 
		let updateSessionDataOnSuccess = deleteLocalFiles

		let resMap = apexTooling#deleteMetadata(filePath, providedProjectName, specificComponentsFilePath, l:mode, updateSessionDataOnSuccess)
		if "true" == resMap["success"]
			"check if we need to delete local files as well
			if providedProjectName == projectPair.name
				"only delete local files when no alternate project name is
				"provided or it was provided but matches current project
				
				if deleteLocalFiles
					"delete files
					let srcPath = apex#getApexProjectSrcPath(filePath)
					for l:file in componentsList
						"each file looks like: "classes/MyClass.cls", i.e. dir and name
						let fPath = apexOs#joinPath([srcPath, l:file])
						if 0 == delete(fPath)
							let metaFilePath =  fPath . "-meta.xml"
							if filereadable(metaFilePath)
								"delete meta.xml as well
								call delete(metaFilePath)
							endif
						endif
					endfor
				endif
				"blank line before next message
				echo " "
			endif
			"clear Stage
			if 'checkOnly' != l:mode
				call apexStage#clear(filePath)
			endif
		endif
	endif

endfunction

function! s:listModeNames(arg, line, pos)
	return ['remove', 'checkOnly']
endfunction	

" Args:
" arg: ArgLead - the leading portion of the argument currently being
"			   completed on
" line: CmdLine - the entire command line
" pos: CursorPos - the cursor position in it (byte index)
"
function! apexDelete#completeParams(arg, line, pos)
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

" run destructive Delete on Staged files
"Args:
" param 1: (optional) destination project name, must match one of .properties file
" param 2: (optional) options:
"				t - test mode, do not make any changes, just run test
"		
function! apexDelete#runAnt(...)
	let filePath = expand("%:p") "default file
	let projectPair = apex#getSFDCProjectPathAndName(filePath)
	let projectName = projectPair.name
	let projectPath = projectPair.path
	if empty(projectName)
		echoerr "failed to determine project location using file path ".filePath
		return
	endif
	if len(apexStage#list(projectPath)) < 1
		call apexUtil#warning( "Nothing staged. Add files with :ApexStageAdd first")
		return
	endif

	let providedProjectName = ''
	if a:0 >0
		let providedProjectName = a:1
		"check if .properties file exists
		if strlen(apex#getPropertiesFilePath(providedProjectName)) <1
			return
		endif
		let projectName = providedProjectName
	endif

	let checkOnly = 'false'
	if a:0 > 1 && (a:2 ==? 't' || a:2 ==? 'checkOnly=true')
		let checkOnly = 'true'
	endif


	let tempFolder = apexOs#createTempDir('wipe')
	" write package.xml for destructive delete
	call apexMetaXml#packageWriteDestructive(tempFolder)

	"generate package.xml called destructiveChanges.xml from staged files
	let package = apexMetaXml#packageXmlNew()
	let xmlNameByDirName = apexRetrieve#getTypeXmlByFolder(projectName, projectPath, 0)
	" {'weblinks': 'CustomPageWebLink', 'labels' : 'CustomLabels'}
	let fileCount = 0
	for l:file in apexStage#list(projectPath)
		"each file looks like: "classes/MyClass.cls", i.e. dir and name
		let filePair = split(l:file, '[/\\]') 
		let l:type = xmlNameByDirName[filePair[0]]
		let l:fname = filePair[1]
		"remove extension from file name
		let l:fname = fnamemodify(l:fname, ':r')
		call apexMetaXml#packageXmlAdd(package, l:type, [l:fname])
		let fileCount += 1
	endfor

	if !empty(package)
		call apexUtil#warning('About to delete '.fileCount.' staged file(s).')
		let destructiveChangesXmlPath = apexMetaXml#packageWrite(package, tempFolder, 'destructiveChanges.xml')
		"echo "destructiveChangesXmlPath=".destructiveChangesXmlPath
		"verify that all of the above works and proceed with ANT command
		let response = input('Backup files from the target Org "'.projectName.'" before DELETE [y/n]? ')
		if 'y' == response || 'Y' == response
			"backup files
			let backupDir = apexOs#joinPath([apexOs#getBackupFolder(),projectName])
			if !isdirectory(backupDir)
				call apexOs#createDir(backupDir)
			endif	
			call apexAnt#backup(projectName, backupDir, destructiveChangesXmlPath)
		endif	

		"now call Ant Delete task and point it to tempFolder with package.xml
		"and destructiveChanges.xml files
		let logFilePath =  apexAnt#delete(projectName, tempFolder, checkOnly)
		if apexAnt#logHasFailure(logFilePath)
			echoerr 'ERROR last ANT operation did not return "BUILD SUCCESSFUL". Please examine error log: '.logFilePath
			return
		endif

		"check if we need to delete local files as well
		if empty(providedProjectName) || projectPair.name == projectName
			"only delete local files when no alternate project name is
			"provided or it was provided but matches current project
			let response = input('Delete local files as well [y/n]? ')
			if 'y' == response || 'Y' == response
				"delete files
				let srcPath = apex#getApexProjectSrcPath(filePath)
				for l:file in apexStage#list(projectPath)
					"each file looks like: "classes/MyClass.cls", i.e. dir and name
					let fPath = apexOs#joinPath([srcPath, l:file])
					if 0 == delete(fPath)
						let metaFilePath =  fPath . "-meta.xml"
						if filereadable(metaFilePath)
							"delete meta.xml as well
							call delete(metaFilePath)
						endif
					endif
				endfor
			endif
			"blank line before next message
			echo " "
		endif
		"clear Stage
		call apexStage#clear(filePath)
	endif



endfunction
