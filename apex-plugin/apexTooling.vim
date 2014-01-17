" File: apexTooling.vim
" Author: Andrey Gavrikov 
" Version: 1.0
" Last Modified: 2014-01-17
" Copyright: Copyright (C) 2010-2014 Andrey Gavrikov
"            Permission is hereby granted to use and distribute this code,
"            with or without modifications, provided that this copyright
"            notice is copied with it. Like anything else that's free,
"            this plugin is provided *as is* and comes with no warranty of any
"            kind, either expressed or implied. In no event will the copyright
"            holder be liable for any damages resulting from the use of this
"            software.
"
" main actions calling tooling-force.com command line executable
" Part of vim/force.com plugin
"
"
if exists("g:loaded_apexTooling") || &compatible
  finish
endif
let g:loaded_apexTooling = 1


" check that required global variables are defined
let s:requiredVariables = ["g:apex_tooling_force_dot_com_path"]
for varName in s:requiredVariables
	if !exists(varName)
		echoerr "Please define ".varName." See :help force.com-settings"
	endif
endfor	

"let s:MAKE_MODES = ['open', 'modified', 'confirm', 'all', 'staged', 'onefile'] "supported Deploy modes
let s:MAKE_MODES = ['Modified'] "supported Deploy modes
"Args:
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
function apexTooling#deploy(...)
	let filePath = expand("%:p")

	if a:0 >= 1 && index(s:MAKE_MODES, a:1) >= 0
		let l:mode = a:1
	else
		call apexUtil#error("Unsupported deployment mode: " . a:1)
		return
	endif
	
	"process list of optional params ['testAndDeploy',...]
	let l:runTest = 0
	let l:checkOnly = 0
	let l:checkDeploy = 0
	let params = []
	if a:0 >1
		let params = a:2
		let l:runTest = index(params, 'testAndDeploy') >=0
		let l:checkOnly = index(params, 'checkOnly') >=0
		let l:checkDeploy = index(params, 'checkOnlyDeploy') >=0
	endif
	
	if a:0 >2
		" if project name is provided via tab completion then spaces in it
		" will be escaped, so have to unescape otherwise funcions like
		" filereadable() do not understand such path name
		let providedProjectName = apexUtil#unescapeFileName(a:3)
	endif

	let projectPair = apex#getSFDCProjectPathAndName(filePath)
	let projectPath = projectPair.path
	let projectName = projectPair.name

	let l:action = "deploy" . l:mode

	call apexTooling#execute(l:action, projectName, projectPath)

endfunction

"Args:
"Param1: path to file which belongs to apex project
function apexTooling#printChangedFiles(filePath)
	let projectPair = apex#getSFDCProjectPathAndName(a:filePath)
	let projectPath = projectPair.path
	let projectName = projectPair.name
	call apexTooling#execute("listModified", projectName, projectPath)
endfunction	

"Args:
"Param1: path to file which belongs to apex project
function apexTooling#refreshProject(filePath)
	let projectPair = apex#getSFDCProjectPathAndName(a:filePath)
	let projectPath = projectPair.path
	let projectName = projectPair.name
	call apexTooling#execute("refresh", projectName, projectPath)
endfunction	

function! apexTooling#execute(action, projectName, projectPath, ...)
	let projectPropertiesPath = apexOs#joinPath([g:apex_properties_folder, a:projectName]) . ".properties"
	let responseFilePath = apexOs#joinPath(a:projectPath, ".vim-force.com", "response_" . a:action)

	let l:command = "java "
	let l:command = l:command  . " -Dorg.apache.commons.logging.simplelog.showlogname=false "
	let l:command = l:command  . " -Dorg.apache.commons.logging.simplelog.showShortLogname=false "
	let l:command = l:command  . " -jar " . g:apex_tooling_force_dot_com_path
	let l:command = l:command  . " --action=" . a:action
	let l:command = l:command  . " --tempFolderPath=" . shellescape(g:apex_temp_folder)
	let l:command = l:command  . " --config=" . shellescape(projectPropertiesPath)
	let l:command = l:command  . " --projectPath=" . shellescape(a:projectPath)
	let l:command = l:command  . " --responseFilePath=" . shellescape(responseFilePath)
	
	call apexOs#exe(l:command, 'M') "disable --more--

endfunction

command! -nargs=* -complete=customlist,apex#completeDeployParams ADeployModified :call apexTooling#deploy('Modified', <f-args>)
command! -nargs=0 ARefreshProject :call apexTooling#refreshProject(expand("%:p"))

command! APrintChanged :call apexTooling#printChangedFiles(expand("%:p"))

