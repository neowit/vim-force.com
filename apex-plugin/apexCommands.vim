" File: apexCommands.vim
" Author: Andrey Gavrikov 
" Version: 0.1
" Last Modified: 2014-01-25
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
let s:currentMappings = '' 

function! apexCommands#toggleMappings()
	if '' == s:currentMappings || 'toolingJarSpecific' == s:currentMappings
		call s:antSpecific()
		let s:currentMappings = 'antSpecific'
	else
		call s:toolingJarSpecific()
		let s:currentMappings = 'toolingJarSpecific'
	endif
	echo "Current Command Mapping: " . s:currentMappings
endfunction

command! ApexToggleCommandMappings :call apexCommands#toggleMappings()

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
	command! -nargs=* -complete=customlist,apexTest#completeParams ApexTest :call apexTest#runTest(<f-args>)

	"delete Staged files from specified Org
	"Examples:
	"1. Delete Staged files from currect project
	"   :ApexDeleteStaged
	"2. delete files listed in Stage from Org defined by specified <project name>
	"	:ApexDeleteStaged 'My Project' 
	"3. do not delete, but test deletion
	"	:ApexDeleteStaged 'My Project' t
	command! -nargs=* -complete=customlist,ListProjectNames ApexRemoveStaged :call apexDelete#run(<f-args>)

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
	command! ApexListConflicts :call apexTooling#listConflicts(expand("%:p"))


	"Unit testing
	" TODO
	"command! -nargs=* -complete=customlist,apexTest#completeParams ApexTest :call apexTest#runTest(<f-args>)

	"delete Staged files from specified Org
	"Examples:
	"1. Delete Staged files from currect project
	"   :ApexDeleteStaged
	"2. delete files listed in Stage from Org defined by specified <project name>
	"	:ApexDeleteStaged 'My Project' 
	"3. do not delete, but test deletion
	"	:ApexDeleteStaged 'My Project' t
	" TODO
	"command! -nargs=* -complete=customlist,ListProjectNames ApexRemoveStaged :call apexDelete#run(<f-args>)

	" TODO
	"command! ApexRefreshFile :call apex#refreshFile(expand("%:p"))
	"command! ApexRetrieve :call apexRetrieve#open(expand("%:p"))

	" display last log - TODO
	"command! ApexLog :call apexAnt#openLastLog()

endfunction

" finally, define default antSpecific/toolingJarSpecific mappings
call apexCommands#toggleMappings()
