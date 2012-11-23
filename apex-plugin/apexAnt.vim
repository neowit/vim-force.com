" File: apexAnt.vim
" Author: Andrey Gavrikov 
" Version: 0.1
" Last Modified: 2012-09-10
" Copyright: Copyright (C) 2010-2012 Andrey Gavrikov
"            Permission is hereby granted to use and distribute this code,
"            with or without modifications, provided that this copyright
"            notice is copied with it. Like anything else that's free,
"            this plugin is provided *as is* and comes with no warranty of any
"            kind, either expressed or implied. In no event will the copyright
"            holder be liable for any damages resulting from the use of this
"            software.
"
" apexAnt.vim - main methods dealing with Ant

" Part of vim/force.com plugin
"

"get script folder
"This has to be outside of a function or anything, otherwise it does not return
"proper path
let s:PLUGIN_FOLDER = expand("<sfile>:h")
let s:ANT_CMD = "ant"

function! apexAnt#deploy(projectName, projectFolder)
	return apexAnt#execute("deploy", a:projectName, a:projectFolder)
endfunction

function! apexAnt#refresh(projectName, projectFolder)
	return apexAnt#execute("refresh", a:projectName, a:projectFolder)
endfunction

" list all supported metadata types
function! apexAnt#loadMetadataList(projectName, projectFolder, outputFilePath)
	return apexAnt#execute("describeMetadata", a:projectName, a:projectFolder, a:outputFilePath)
endfunction

" get detail information about metadata components of a given type
function! apexAnt#listMetadata(projectName, projectFolder, outputFilePath, metadataType)
	return apexAnt#execute("listMetadata", a:projectName, a:projectFolder, a:outputFilePath, a:metadataType)
endfunction

" bulk retrieve all metadata components of a given type
" return: temp folder path which contains subfolder with retrieved components
function! apexAnt#bulkRetrieve(projectName, projectFolder, metadataType)
	let outputDir = apexOs#createTempDir()
	call apexAnt#execute("bulkRetrieve", a:projectName, a:projectFolder, outputDir, a:metadataType)
	return outputDir
endfunction

" param: command - deploy|refresh|describe
" 
" return: path to error log or empty string if ant could not be executed
function! apexAnt#execute(command, projectName, projectFolder, ...)
	let propertiesFolder = apexOs#removeTrailingPathSeparator(g:apex_properties_folder)
	let orgName = a:projectName
	" check that 'project name.properties' file with login credential exists
	let projectPropertiesPath = apexOs#joinPath([propertiesFolder, a:projectName]) . ".properties"
	if !filereadable(projectPropertiesPath)
		echohl ErrorMsg
		echomsg "'" . projectPropertiesPath . "' file used by ANT to retrieve login credentials is not readable"
		echomsg "Check 'g:apex_properties_folder' variable in your ".expand($MYVIMRC)
		echohl None 
		return ""
	endif
	let ANT_ERROR_LOG = apexOs#joinPath([apexOs#getTempFolder(), g:apex_deployment_error_log])
	let buildFile=apexOs#joinPath([s:PLUGIN_FOLDER, "build.xml"])

	"	ant  -buildfile "$buildFile" -Ddest.org.name="$destOrgName"
	"	-Dproperties.path="$propertiesPath" -Dproject.Folder="$projectFolder"
	"	deployUnpackaged
	"
	let antCommand = s:ANT_CMD . " -buildfile " . shellescape(buildFile). " -Ddest.org.name=" . shellescape(orgName) . " -Dproperties.path=" . shellescape(propertiesFolder) 
					 
	if exists("g:apex_pollWaitMillis")
		let antCommand = antCommand . " -DpollWaitMillis=" . g:apex_pollWaitMillis
	endif
	if "deploy" == a:command || "refresh" == a:command
		if "deploy" == a:command
			let antCommand = antCommand . " -Dproject.Folder=" . shellescape(a:projectFolder) . " deployUnpackaged"
		elseif "refresh" == a:command
			let antCommand = antCommand . " -Dproject.Folder=" . shellescape(a:projectFolder) . " retrieveSource"
		endif
	elseif "describeMetadata" == a:command
		" get detail information of the metadata types currently being
		" supported
		if a:0 < 1 || len(a:1) < 1
			echoerr "missing output file path parameter"
			return ""
		endif
		let outputFilePath = a:1
		let antCommand = antCommand . " -Dresult.file.path=" . shellescape(outputFilePath) . " describeMetadata"
	elseif "listMetadata" == a:command
		" get detail information about metadata components of a given type
		if a:0 < 1 || len(a:1) < 1
			echoerr "missing output file path parameter"
			return ""
		endif
		if a:0 < 2 || len(a:2) < 1
			echoerr "missing metadata type parameter"
			return ""
		endif
		let outputFilePath = a:1
		let metadataType = a:2
		let antCommand = antCommand . " -Dresult.file.path=" . shellescape(outputFilePath). " -DmetadataType=" . shellescape(metadataType) . " listMetadata"
	elseif "bulkRetrieve" == a:command
		" get detail information about metadata components of a given type
		if a:0 < 1 || len(a:1) < 1
			echoerr "missing output folder path parameter"
			return ""
		endif
		if a:0 < 2 || len(a:2) < 1
			echoerr "missing metadata type parameter"
			return ""
		endif
		let outputFolderPath = a:1
		let metadataType = a:2
		let antCommand = antCommand . " -DretrieveOutputDir=" . shellescape(outputFolderPath). " -DmetadataType=" . shellescape(metadataType) . " bulkRetrieve"
	else
		echoerr "Unsupported command".a:command
	endif
	let antCommand = antCommand ." 2>&1 |".g:apex_binary_tee." ".shellescape(ANT_ERROR_LOG)
	"echo "antCommand=".antCommand
    call apexOs#exe(antCommand, 'M') "disable --more--
	return ANT_ERROR_LOG
endfunction


