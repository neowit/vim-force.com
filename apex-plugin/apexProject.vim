" This file is part of vim-force.com plugin
"   https://github.com/neowit/vim-force.com
" File: apexProject.vim
" Last Modified: 2014-05-06
" Author: Alejandro De Gregorio 
" Maintainers: Alejandro De Gregorio, Andrey Gavrikov
"
" Main actions: Initialize a new Apex Project asking the user for the org information
"
if exists("g:loaded_apexProject") || &compatible
  finish
endif
let g:loaded_apexProject = 1

function apexProject#init() abort
	let l:isWorkspacePathDefined = exists('g:apex_workspace_path') && len(g:apex_workspace_path) > 0
	if !l:isWorkspacePathDefined
		call apexUtil#info('Hint: you can set the root path where your projects will to be created by default, see :h g:apex_workspace_path')
	endif

	let l:enteredName = s:askInput('Enter project name: ')
	let l:pathPair = apexOs#splitPath(l:enteredName)
	let l:projectName = pathPair.tail

	let l:rootFolder =  getcwd()
	if l:isWorkspacePathDefined
		let l:rootFolder =  g:apex_workspace_path
	endif

	if !apexOs#isFullPath(l:enteredName)
		let l:projectPath = apexOs#joinPath(l:rootFolder, l:pathPair.head)
	else
		let l:projectPath = l:pathPair.head
	endif

	let l:projectSrcPath = apexOs#joinPath(l:projectPath, l:projectName, 'src')
	let l:classesDirPath = apexOs#joinPath(l:projectSrcPath, 'classes')

	call apexOs#createDir(l:classesDirPath)

	call s:buildPropertiesFile(l:projectName)
	call s:buildPackageFile(l:projectSrcPath)

	call apexTooling#refreshProject(l:projectSrcPath, 1)
	" check if we have existing files to open
	let fullPaths = apexOs#glob(l:projectSrcPath . "**/*.cls")
	if len(fullPaths) > 0
		"open random class from just loaded files
		execute 'e ' . fnameescape(fullPaths[0])
	else
		":ApexNewFile
		call apexMetaXml#createFileAndSwitch(l:projectSrcPath)
	endif
	
endfunction

function s:buildPropertiesFile(projectName) abort
	let propertiesFilePath = apexOs#joinPath([g:apex_properties_folder, a:projectName . '.properties'])
	if !filereadable(propertiesFilePath) || 'y' ==? apexUtil#input('File '.propertiesFilePath. ' already exists, would you like to overwrite it y/N? ', 'yYnN', 'n')

		let username = s:askInput('Enter username: ')
		let password = s:askSecretInput('Enter password: ')
		let token = s:askInput('Enter security token: ')
		let orgType = s:askInput('Enter org type (test|login), if blank then defaults to "test": ')
		if len(orgType) < 1
			let orgType = 'test'
		endif

		let fileLines = []
		call add(fileLines, 'sf.username = ' . username)
		call add(fileLines, 'sf.password = ' . password . token)
		call add(fileLines, 'sf.serverurl = https://' . orgType . '.salesforce.com')

		" make sure properties folder exists
        if !isdirectory(g:apex_properties_folder)
            call apexOs#createDir(g:apex_properties_folder)
        endif
		
		call writefile(fileLines, propertiesFilePath)
	endif
endfunction

" Ask the user for an input
" Param: message: A text to show to the user
" Param1: secret: (optional) 0 for false, anything else for true
function s:askInput(message, ...)
	call inputsave()
	let secret = a:0 > 0 && a:1
	let value = secret ? inputsecret(a:message) : input(a:message)
	call inputrestore()
	return value
endfunction

function s:askSecretInput(message)
	return s:askInput(a:message, 1)
endfunction

function s:buildPackageFile(projectSrcPath)
	let srcFolderPath = a:projectSrcPath
	let packageElements = ['ApexClass', 'ApexComponent', 'ApexPage', 'ApexTrigger', 'CustomLabels', 'Scontrol', 'StaticResource']
	let package = apexMetaXml#packageXmlNew()

	for element in packageElements
		call apexMetaXml#packageXmlAdd(package, element, ['*'])
	endfor

	call apexMetaXml#packageWrite(package, srcFolderPath)
endfunction
