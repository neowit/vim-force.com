" File: apexUtil.vim
" Author: Andrey Gavrikov 
" Version: 1.0
" Last Modified: 2012-03-05
" Copyright: Copyright (C) 2010-2012 Andrey Gavrikov
"            Permission is hereby granted to use and distribute this code,
"            with or without modifications, provided that this copyright
"            notice is copied with it. Like anything else that's free,
"            this plugin is provided *as is* and comes with no warranty of any
"            kind, either expressed or implied. In no event will the copyright
"            holder be liable for any damamges resulting from the use of this
"            software.
" various utility methods used by different parts of force.com plugin 
" Part of vim/force.com plugin
"
"
" helper to compare current file with its counterpart in another project
" User does not have to specify full path to another file because
" we make major assumption that projects have equal dirrectory structure
" The only thing which needs to be specified/selected is top/root of another
" project
if exists("g:loaded_apexUtil") || &compatible
  finish
endif
let g:loaded_apexUtil = 1

if !exists("g:apex_diff_cmd") 
	if has("unix")
		" use Meld by default
		let g:apex_diff_cmd="/usr/bin/meld"
	else
		" echoerr 'please define command for diff tool'
	endif 
endif	

" compare file give as argument a:1 with its version given as a:2
" If a:2 is not specified then compare source file with same file from another
" project, assuming project structure of left and right projects is equal and
" they have common parent folder
function! ApexCompare(...)
	let leftFilePath = '' 
	if a:0 >0
		let leftFilePath = a:1
	else
		" use current file
		let leftFilePath = expand("%:p")
	endif	

	if a:0 >1
		let rightFilePath = a:2
	else	
		let rightFilePath = apexUtil#selectCounterpartFromAnotherProject(leftFilePath)
	endif	
	if len(rightFilePath) < 1
		echo 'comparison cancelled'
		return ""
	endif
	if executable(g:apex_diff_cmd)
		let scriptPath = shellescape(g:apex_diff_cmd)
		let command = scriptPath.' '.shellescape(leftFilePath).' '.shellescape(rightFilePath)
	
		":exe "!".command
		call apexOs#exe(command, 1)
	else
		" use built-in diff
		:exe "vert diffsplit ".substitute(rightFilePath, " ", "\\\\ ", "g")
	endif
endfunction
" define command to call for current file
"command! -nargs=? ApexCompare :call ApexCompare(<args>)

" create Git repo for current Apex project and add files
function! apexUtil#gitInit()
	if !executable('git')
		echomsg 'force.com plugin: Git (http://git-scm.com/) ' .
                \ 'not found in PATH. apexUtil#gitInit() is not available.'
		finish
	endif	

	let filePath = expand("%:p")
	let projectPair = apex#getSFDCProjectPathAndName(filePath)
	let projectPath = projectPair.path
	let projectSrcPath = apex#getApexProjectSrcPath(filePath)
	echo "projectPath=".projectPath
	let supportedFiles = {'labels': 'labels', 'pages': 'page', 'classes' : 'cls', 'triggers' : 'trigger', 'components' : 'component', 'staticresources' : 'resource'}

	let response = input('Init new Git repository at: "'.projectPath.'" [a/y/n]? ')
	if 'y' == response || 'Y' == response || 'a' == response || 'A' == response
		call apexOs#exe("git init '".projectPath."'")
	endif	
	let dirs =keys(supportedFiles)
	for dirName in dirs
		" echo dirName
		let fullPath = apexOs#joinPath([projectSrcPath, dirName])
		if isdirectory(fullPath)
			let fileExtention = supportedFiles[dirName]
			let maskPath = "'".fullPath."/*.".fileExtention."'"
			if  'a' != response && 'A' != response
				let response = input('add files: "'.maskPath.'" [a/y/n]? ')
			endif

			if 'y' == response || 'Y' == response || 'a' == response || 'A' == response
				call apexOs#exe("git add ".maskPath)
			endif	
		else
			" echo fullPath." is not existing directory"
		endif
	endfor	

endfunction
""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" compare current version of the file with last version backed up before
" refresh
""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
function! apexUtil#compareWithPreRefreshVersion (apexBackupFolder)
	
	" use current file
	let leftFilePath = expand("%:p")
	let leftFileName = expand("%:t")

	if len(a:apexBackupFolder) <1
		echoerr "parameter 1: apexBackupFolder is required"
		return
	endif	
	" open folder selection dialogue
	let projectPair = apex#getSFDCProjectPathAndName(leftFilePath)
	let projectPath = projectPair.path
	let projectName = projectPair.name
	let backupRoot = apexOs#joinPath([a:apexBackupFolder, projectName])
	let rightProjectPath = browsedir("Select folder fo Backup to compare with", backupRoot)

	if len(rightProjectPath) <1
		"cancelled
		return
	endif

	let rightFilePath = apexOs#joinPath([rightProjectPath, leftFileName])
	if !filereadable(rightFilePath)
		echohl WarningMsg | echo "file ".rightFilePath." is not readable or does not exist" | echohl None
		return
	endif	

	call ApexCompare(leftFilePath, rightFilePath)

endfunction	
" using given filepath return path to the same file but in another project
" project is to be selected
function! apexUtil#selectCounterpartFromAnotherProject(filepath)
	let leftFile = a:filepath
	"echo "leftFile=".leftFile
	let projectPair = apex#getSFDCProjectPathAndName(leftFile)
	let leftProjectName = projectPair.name
	"echo "projectPair.path=".projectPair.path

	let rootDir = apexOs#splitPath(projectPair.path).head
	let rightProjectPath = browsedir("Select Root folder of the Project to compare with", rootDir)
	"echo "selected: ".rightProjectPath

	if len(rightProjectPath) <1 
		" cancelled
		return ""
	endif
	" at this point in time we have something like following:
	" leftFile=/home/andrey/eclipse.workspace/Reed (CITDev1)/src/classes/OpportunityBeforeSupport.cls
	" projectPair.path=/home/andrey/eclipse.workspace/Reed (CITDev1)/
	" rightProjectPath: /home/andrey/eclipse.workspace/Reed (CITTest2)  	
	let rightProjectName = apexOs#splitPath(rightProjectPath).tail
	"echo "rightProjectName=".rightProjectName
	let rightFilePath = substitute(leftFile, leftProjectName, rightProjectName, "")
	"echo "rightFilePath=".rightFilePath
	return rightFilePath
endfunction

"	@deprecated, use apexOs#hasTrailingPathSeparator instead
function! apexUtil#hasTrailingPathSeparator(filePath)
	return apexOs#hasTrailingPathSeparator(a:filePath)
endfunction	

"	@deprecated, use apexOs#joinPath instead
function! apexUtil#joinPath(filePathList)
	return  apexOs#joinPath(a:filePathList)
endfunction	
