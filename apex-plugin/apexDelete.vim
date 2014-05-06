" This file is part of vim-force.com plugin
"   https://github.com/neowit/vim-force.com
" File: apexDelete.vim
" Last Modified: 2014-02-08
" Author: Andrey Gavrikov 
" Maintainers: 
"
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

