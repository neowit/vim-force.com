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

    let obj = {}
    let obj["_projectSrcPath"] = l:projectSrcPath
    function! obj.callbackFuncRef(paramsMap)
        echomsg "paramsMap=".string(a:paramsMap)
        " check if we have existing files to open
        let fullPaths = apexOs#glob(self._projectSrcPath . "**/*.cls")
        if len(fullPaths) > 0
            "open random class from just loaded files
            execute 'e ' . fnameescape(fullPaths[0])
            echo "Press Enter"
        else
            ":ApexNewFile
            call apexMetaXml#createFileAndSwitch(self._projectSrcPath)
        endif
    endfunction

	call apexToolingAsync#refreshProject(l:projectSrcPath, {"skipModifiedFilesCheck": "true", "callbackObj": obj})
	
endfunction

" login to SFDC Org
"Args:
"Param1: filePath - path to apex file in current project
function apexProject#login(filePath)
	let projectPair = apex#getSFDCProjectPathAndName(a:filePath)
	let projectName = projectPair.name " default project name

    let projectNameOpt = apexUtil#menu("Which project/org to login to?  ", ["Current", "Another"], "Current")
    if "Current" != projectNameOpt
        let projectName = apexUtil#inputFreetext("Enter project name: ")
        if len(projectName) < 1
            return ''
        endif    
    endif    
    if len(projectName) < 1
        return
    endif
	call apexToolingAsync#login(projectName)
endfunction

function s:buildPropertiesFile(projectName) abort
	let propertiesFilePath = apexOs#joinPath([g:apex_properties_folder, a:projectName . '.properties'])
	if !filereadable(propertiesFilePath) || 'y' ==? apexUtil#input('File '.propertiesFilePath. ' already exists, would you like to overwrite it y/N? ', 'yYnN', 'n')

		let orgAlias = s:askInput('Enter sf org alias [' . a:projectName . ']: ')
		if len(orgAlias) < 1
			let orgAlias = a:projectName
		endif
		let cliPathDefault = exists('g:apex_sf_cli_path') ? g:apex_sf_cli_path : ''
		let cliPath = s:askInput('Enter sf CLI path [' . cliPathDefault . ']: ')
		if len(cliPath) < 1
			let cliPath = cliPathDefault
		endif

		let fileLines = []
		call add(fileLines, 'sf.orgAlias=' . orgAlias)
		if len(cliPath) > 0
			call add(fileLines, 'sf.cliPath=' . cliPath)
		endif

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

function s:buildPackageFile(projectSrcPath)
	let srcFolderPath = a:projectSrcPath
	let packageElements = ['ApexClass', 'ApexComponent', 'ApexPage', 'ApexTrigger', 'CustomLabels', 'Scontrol', 'StaticResource']
	let package = apexMetaXml#packageXmlNew()

	for element in packageElements
		call apexMetaXml#packageXmlAdd(package, element, ['*'])
	endfor

	call apexMetaXml#packageWrite(package, srcFolderPath)
endfunction
