" File: apexDelete.vim
" Author: Andrey Gavrikov 
" Version: 0.1
" Last Modified: 2012-10-24
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
" param 1: (optional) destination project name, must match one of .properties file
" param 2: (optional) options:
"				t - test mode, do not make any changes, just run test
"		
function! apexDelete#run(...)
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
