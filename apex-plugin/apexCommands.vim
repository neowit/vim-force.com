" File: apexCommands.vim
" Author: Andrey Gavrikov 
" Version: 0.1
" Last Modified: 2014-02-08
" Copyright: Copyright (C) 2010-2014 Andrey Gavrikov
"            Permission is hereby granted to use and distribute this code,
"            with or without modifications, provided that this copyright
"            notice is copied with it. Like anything else that's free,
"            this plugin is provided *as is* and comes with no warranty of any
"            kind, either expressed or implied. In no event will the copyright
"            holder be liable for any damages resulting from the use of this
"            software.
"
" apexMappings.vim - vim-force.com commands mapping

" Part of vim-force.com plugin
"
" Only do this when not done yet for this buffer
if exists("g:loaded_apexCommands") || &compatible
  finish
endif
let g:loaded_apexCommands = 1

"staging
command! ApexStage :call apexStage#open(expand("%:p"))
command! ApexStageAdd :call apexStage#add(expand("%:p"))
command! ApexStageAddOpen :call apexStage#addOpen()
command! ApexStageRemove :call apexStage#remove(expand("%:p"))
command! ApexStageClear :call apexStage#clear(expand("%:p"))


" select file type, create it and switch buffer
command! ApexNewFile :call apexMetaXml#createFileAndSwitch(expand("%:p"))

" before refresh all changed files are backed up, so we can compare refreshed
" version with its pre-refresh condition
command! ApexCompareWithPreRefreshVersion :call apexUtil#compareWithPreRefreshVersion(apexOs#getBackupFolder())
command! ApexCompare :call ApexCompare()

" initialise Git repository and add files
command! ApexGitInit :call apexUtil#gitInit()

"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" Apex Code - compare current file with its own in another Apex Project
"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
command! DiffUnderEclipse :ApexCompare

""""""""""""""""""""""""""""""""""""""""""""""""
" Apex commands 
""""""""""""""""""""""""""""""""""""""""""""""""
" options are: '', 'antSpecific', 'toolingJarSpecific'
let s:CURRENT_MODE = '' 

function! apexCommands#toggleMappings()
	" clean up commands which do not exist in both modes
	try 
		delcommand ApexRefreshFile
		delcommand ApexRetrieve
		delcommand ApexLog
		delcommand ApexExecuteAnonymous
		delcommand ApexTestWithCoverage
		delcommand ApexTestCoverageToggle
		delcommand ApexTestCoverageHideAll
		delcommand ApexScratch
	catch 
	endtry

	if '' == s:CURRENT_MODE || 'toolingJarSpecific' == s:CURRENT_MODE
		call s:antSpecific()
		let s:CURRENT_MODE = 'antSpecific'
	else
		call s:toolingJarSpecific()
		let s:CURRENT_MODE = 'toolingJarSpecific'
	endif
	echo "Current Command Mapping: " . s:CURRENT_MODE
endfunction

command! ApexToggleCommandMappings :call apexCommands#toggleMappings()

function! apexCommands#isAnt() 
	return s:CURRENT_MODE =~? "ant"
endfunction

""""""""""""""""""""""""""""""""""""""""""""""""
" ANT specific
""""""""""""""""""""""""""""""""""""""""""""""""

function! s:antSpecific()
	"
	"defined a command to run MakeApex
	command! -nargs=* -complete=customlist,apex#completeDeployParams ApexDeploy :call apex#deploy('modified', <f-args>)
	command! -nargs=* -complete=customlist,apex#completeDeployParams ApexDeployOpen :call apex#deploy('open', <f-args>)
	command! -nargs=* -complete=customlist,apex#completeDeployParams ApexDeployConfirm :call apex#deploy('confirm', <f-args>)
	command! -nargs=* -complete=customlist,apex#completeDeployParams ApexDeployAll :call apex#deploy('all', <f-args>)
	command! -nargs=* -complete=customlist,apex#completeDeployParams ApexDeployStaged :call apexStage#write() | :call apex#deploy('staged', <f-args>)

	"Unit testing
	command! -nargs=* -complete=customlist,apexTest#completeParams ApexTest :call apexTest#runTestAnt(<f-args>)

	"delete Staged files from specified Org
	"Examples:
	"1. Delete Staged files from currect project
	"   :ApexDeleteStaged
	"2. delete files listed in Stage from Org defined by specified <project name>
	"	:ApexDeleteStaged 'My Project' 
	"3. do not delete, but test deletion
	"	:ApexDeleteStaged 'My Project' t
	command! -nargs=* -complete=customlist,ListProjectNames ApexRemoveStaged :call apexDelete#runAnt(<f-args>)

	command! -nargs=0 ApexRefreshProject :call apex#refreshProject()
	command! ApexRefreshFile :call apex#refreshFile(expand("%:p"))
	command! ApexPrintChanged :call apex#printChangedFiles(expand("%:p"))
	command! ApexRetrieve :call apexRetrieve#open(expand("%:p"))

	" display last ANT log
	command! ApexLog :call apexAnt#openLastLog()

endfunction



""""""""""""""""""""""""""""""""""""""""""""""""
" tooling-force.com specific
""""""""""""""""""""""""""""""""""""""""""""""""
function! s:toolingJarSpecific()
	"
	" Deployment
	command! -nargs=* -complete=customlist,apex#completeDeployParams ApexDeploy :call apexTooling#deploy('Modified', <f-args>)
	command! -nargs=* -complete=customlist,apex#completeDeployParams ApexDeployAll :call apexTooling#deploy('All', <f-args>)
	command! -nargs=* -complete=customlist,apex#completeDeployParams ApexDeployOpen :call apexTooling#deploy('Open', <f-args>)
	command! -nargs=* -complete=customlist,apex#completeDeployParams ApexDeployStaged :call apexTooling#deploy('Staged', <f-args>)
	command! -nargs=* -complete=customlist,apex#completeDeployParams ApexDeployOne :call apexTooling#deploy('One', <f-args>)
	" TODO
	"command! -nargs=* -complete=customlist,apex#completeDeployParams ApexDeployConfirm :call apexTooling#deploy('Confirm', <f-args>)

	command! -nargs=0 ApexRefreshProject :call apexTooling#refreshProject(expand("%:p"))

	command! ApexPrintChanged :call apexTooling#printChangedFiles(expand("%:p"))
	command! ApexPrintConflicts :call apexTooling#printConflicts(expand("%:p"))


	"Unit testing
	command! -nargs=* -complete=customlist,apexTest#completeParams ApexTest :call apexTest#runTest('no-reportCoverage', <f-args>)
	command! -nargs=* -complete=customlist,apexTest#completeParams ApexTestWithCoverage :call apexTest#runTest('reportCoverage', <f-args>)
	command! -nargs=0 ApexTestCoverageToggle :call apexCoverage#toggle(expand("%:p"))
	command! -nargs=0 ApexTestCoverageHideAll :call apexCoverage#hide()

	"delete Staged files from specified Org
	"Examples:
	"1. Delete Staged files from currect project
	"   :ApexRemoveStaged
	"2. delete files listed in Stage from Org defined by specified <project name>
	"	:ApexRemoveStaged 'My Project' 
	"3. do not delete, but test deletion
	"	:ApexRemoveStaged 'My Project' t
	" TODO
	command! -nargs=* -complete=customlist,apexDelete#completeParams ApexRemoveStaged :call apexDelete#run(<f-args>)

	" TODO
	"command! ApexRefreshFile :call apex#refreshFile(expand("%:p"))
	command! ApexRetrieve :call apexRetrieve#open(expand("%:p"))

	command! -nargs=? -complete=customlist,apex#listProjectNames -range=% ApexExecuteAnonymous <line1>,<line2>call apexTooling#executeAnonymous(expand("%:p"), <f-args>)

	" display last log
	command! ApexLog :call apexTooling#openLastLog()

	" open scratch buffer/file
	command! ApexScratch :call apexTooling#openScratchFile(expand("%:p"))
endfunction

" finally, define default antSpecific/toolingJarSpecific mappings
let s:CURRENT_MODE = 'antSpecific' 
call apexCommands#toggleMappings()
