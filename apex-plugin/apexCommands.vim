" This file is part of vim-force.com plugin
"   https://github.com/neowit/vim-force.com
" File: apexCommands.vim
" Last Modified: 2014-02-17
" Author: Andrey Gavrikov 
" Maintainers: 
"
" apexMappings.vim - vim-force.com commands mapping
"
" Only do this when not done yet for this buffer
if exists("g:loaded_apexCommands") || &compatible
  finish
endif
let g:loaded_apexCommands = 1


""""""""""""""""""""""""""""""""""""""""""""""""
" Apex commands 
""""""""""""""""""""""""""""""""""""""""""""""""
" version of tooling-force.com
command! ApexToolingVersion :call apexTooling#getVersion(expand("%:p"))

" staging
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

"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" Apex Code - compare current file or src folder with their counterpart in
" another Apex Project
"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
command! ApexCompare :call apexUtil#compareFiles(expand("%:p"))
command! ApexCompareLocalProjects :call apexUtil#compareProjects(expand("%:p"))

" initialise Git repository and add files
command! ApexGitInit :call apexUtil#gitInit()


""""""""""""""""""""""""""""""""""""""""""""""""
" tooling-force.com specific
""""""""""""""""""""""""""""""""""""""""""""""""
function! s:toolingJarSpecific()
	"
	" Deployment
	command! -bang -nargs=* -complete=customlist,apex#completeDeployParams ApexDeploy :call apexTooling#deploy('deploy', 'Modified', <bang>0, <f-args>)
	command! -bang -nargs=* -complete=customlist,apex#completeDeployParams ApexDeployDestructive :call apexTooling#deploy('deploy', 'ModifiedDestructive', <bang>0, <f-args>)
	command! -bang -nargs=* -complete=customlist,apex#completeDeployParams ApexDeployAll :call apexTooling#deploy('deploy', 'All', <bang>0, <f-args>)
	command! -bang -nargs=* -complete=customlist,apex#completeDeployParams ApexDeployAllDestructive :call apexTooling#deploy('deploy', 'AllDestructive', <bang>0, <f-args>)
	command! -bang -nargs=* -complete=customlist,apex#completeDeployParams ApexDeployOpen :call apexTooling#deploy('deploy', 'Open', <bang>0, <f-args>)
	command! -bang -nargs=* -complete=customlist,apex#completeDeployParams ApexDeployStaged :call apexTooling#deploy('deploy', 'Staged', <bang>0, <f-args>)
	command! -bang -nargs=* -complete=customlist,apex#completeDeployParams ApexDeployOne :call apexTooling#deploy('deploy', 'One', <bang>0, <f-args>)
	" TODO
	"command! -nargs=* -complete=customlist,apex#completeDeployParams ApexDeployConfirm :call apexTooling#deploy('Confirm', <f-args>)

	command! -nargs=0 ApexRefreshProject :call apexTooling#refreshProject(expand("%:p"))
	command! -nargs=? -complete=customlist,apex#listProjectNames ApexRefreshFile :call apexTooling#refreshFile(expand("%:p"), <f-args>)

	command! ApexPrintChanged :call apexTooling#printChangedFiles(expand("%:p"))
	command! ApexPrintConflicts :call apexTooling#printConflicts(expand("%:p"))
	command! -nargs=? -complete=customlist,apex#listProjectNames ApexDiffWithRemoteProject :call apexTooling#diffWithRemote(expand("%:p"), "project", <f-args>)
	command! -nargs=? -complete=customlist,apex#listProjectNames ApexDiffWithRemoteFile :call apexTooling#diffWithRemote(expand("%:p"), "file", <f-args>)


	"Unit testing
	command! -bang -nargs=* -complete=customlist,apexTest#completeParams ApexTest :call apexTest#runTest('no-reportCoverage', <bang>0, <f-args>)
	command! -bar -bang -nargs=* -complete=customlist,apexTest#completeParams ApexTestWithCoverage :call apexTest#runTest('reportCoverage', <bang>0, <f-args>)
	command! -nargs=? -complete=buffer ApexTestCoverageShow :call apexCoverage#show(<q-args>)
	command! -nargs=0 ApexTestCoverageToggle :call apexCoverage#toggle(expand("%:p"))
	command! -nargs=0 ApexTestCoverageHideAll :call apexCoverage#hide()

	"delete Staged files from specified Org
	command! -nargs=* -complete=customlist,apexDelete#completeParams ApexRemoveStaged :call apexDelete#run(<f-args>)

	command! ApexRetrieve :call apexRetrieve#open(expand("%:p"))

	command! -nargs=? -complete=customlist,apex#listProjectNames -range=% ApexExecuteAnonymous <line1>,<line2>call apexExecuteSnippet#run('executeAnonymous', expand("%:p"), <f-args>)
	command! -nargs=? -complete=customlist,apex#listProjectNames ApexExecuteAnonymousRepeat call apexExecuteSnippet#repeat('executeAnonymous', expand("%:p"), <f-args>)

	command! -nargs=* -complete=customlist,apex#completeQueryParams -range=% ApexQuery <line1>,<line2>call apexExecuteSnippet#run('soqlQuery', expand("%:p"), <f-args>)
	command! -nargs=* -complete=customlist,apex#completeQueryParams ApexQueryRepeat call apexExecuteSnippet#repeat('soqlQuery', expand("%:p"), <f-args>)

	" display last log
	command! ApexLog :call apexTooling#openLastLog()

	" open scratch buffer/file
	command! ApexScratch :call apexTooling#openScratchFile(expand("%:p"))

	" Tooling API commands
	command! -bang -nargs=? -complete=customlist,apex#completeSaveParams ApexSave :call apexTooling#deploy('save', 'Modified', <bang>0, <f-args>)
	command! -bang -nargs=? -complete=customlist,apex#completeSaveParams ApexSaveOpen :call apexTooling#deploy('save', 'Open', <bang>0, <f-args>)
	command! -bang -nargs=? -complete=customlist,apex#completeSaveParams ApexSaveOne :call apexTooling#deploy('save', 'One', <bang>0, <f-args>)

    " Apex Parser 
	command! ApexCheckSyntax :call apexComplete#checkSyntax(expand("%:p"))
	
endfunction

" finally, define mappings
call s:toolingJarSpecific()
