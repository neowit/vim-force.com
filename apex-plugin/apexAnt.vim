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

function! apexAnt#deploy(projectName, projectFolder, checkOnly)
	return apexAnt#execute("deploy", a:projectName, a:projectFolder, a:checkOnly)
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
	let outputDir = apexOs#createTempDir('wipe')
	call apexAnt#execute("bulkRetrieve", a:projectName, a:projectFolder, outputDir, a:metadataType)
	return outputDir
endfunction

" run Unit Tests using provided class names
" Args:
" Param: classNames - ['MyTestClass', 'class2'...]
" Paran: checkOnly - 'checkOnly' = run with 'checkOnly' flag = true
function! apexAnt#runTests(projectName, projectFolder, classNames, checkOnly)
	return apexAnt#execute("runTest", a:projectName, a:projectFolder, a:classNames, a:checkOnly)
endfunction


" backup files specified in package.xml
function! apexAnt#backup(projectName, backupDirPath, projectXmlFilePath)
	return apexAnt#execute("backup", a:projectName, '', a:backupDirPath, a:projectXmlFilePath)
endfunction

function! apexAnt#delete(projectName, destructiveChangesFolder, checkOnly)
	return apexAnt#execute("delete", a:projectName, '', a:destructiveChangesFolder, a:checkOnly)
endfunction

" check Ant log file to see if last ANT operation failed
" Return:
" 0 - no failure detected
" 1 - ant operation failed
function! apexAnt#logHasFailure(logFilePath)
	try
		exe "noautocmd 1vimgrep /BUILD SUCCESSFUL/j ".fnameescape(a:logFilePath)
	catch  /.*/
		return 1 " log does not contain BUILD SUCCESSFUL
	endtry	
	return 0
endfunction

" generate build.xml include with list of classes to run tests
"Agrs:
"Param: classNameList - list of class names without extension, 
"	e.g. ['MyTestClass', 'class2'...]
function! apexAnt#generateTestsXml(projectFolder, classNameList)
	let logType = 'None' "Valid options are 'None', 'Debugonly', 'Db', 'Profiling', 'Callout', and 'Detail'
	if exists('g:apex_test_logType')
		let logType = g:apex_test_logType
	endif
	let nestedHead = [
				\ '<project xmlns:sf="antlib:com.salesforce">',
				\ '<target name="deployAndRunTest"  >',
				\ '	 <echo message="Destination USERNAME=${dest.sf.username}" />',
				\ '	 <echo message="Destination SERVER=${dest.sf.serverurl}" />',
				\ '	 <echo message="Source files folder=${srcDir}" />',
				\ '  <sf:deploy checkOnly="${checkOnly}" username="${dest.sf.username}" password="${dest.sf.password}" ',
				\ '           serverurl="${dest.sf.serverurl}" deployRoot="${srcDir}" maxPoll="1000" allowMissingFiles="true" ',
				\ '           pollWaitMillis="${pollWaitMillis}" logType="'.logType.'"> '
				\ ]
	let nestedTail = [
				\ '  </sf:deploy>',
				\ '</target>',
				\ '</project>'
				\ ]
	
	let fileName = "sfdeploy-with-tests-nested.xml"
	let fileContent = []
	if len(a:classNameList) > 0
		let fileContent = fileContent + nestedHead

		for fName in a:classNameList
			let line = '<runTest>' . fName . '</runTest>'
			call add(fileContent, line)
		endfor
		let fileContent = fileContent + nestedTail
	endif
	
	if len(fileContent) > 0
		let fullPath = apexOs#joinPath([a:projectFolder, fileName])
		let res = writefile(fileContent, fullPath)
	endif

endfunction

" param: command - deploy|refresh|describeMetadata|listMetadata|bulkRetrieve|backup|delete|runTest
" 
" return: path to error log or empty string if ant could not be executed
function! apexAnt#execute(command, projectName, projectFolder, ...)
	let propertiesFolder = apexOs#removeTrailingPathSeparator(g:apex_properties_folder)
	let orgName = a:projectName
	let projectFolder = apexOs#removeTrailingPathSeparator(a:projectFolder)
	" check that 'project name.properties' file with login credential exists
	let projectPropertiesPath = apexOs#joinPath([propertiesFolder, a:projectName]) . ".properties"
	if !filereadable(projectPropertiesPath)
		echohl ErrorMsg
		echomsg "'" . projectPropertiesPath . "' file used by ANT to retrieve login credentials is not readable"
		echomsg "Check 'g:apex_properties_folder' variable in your ".expand($MYVIMRC)
		echohl None 
		return ""
	endif
	" make sure temp folder actually exist, but not overwrite existing 
	let tempDir = apexOs#createTempDir()
	let ANT_ERROR_LOG = apexOs#joinPath([tempDir, g:apex_deployment_error_log])
	

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
			if a:0 > 0 && a:1 == 'checkOnly'
				let antCommand = antCommand . " -DcheckOnly=true "
			endif	
			let antCommand = antCommand . " -Dproject.Folder=" . shellescape(projectFolder) . " deployUnpackaged"
		elseif "refresh" == a:command
			let antCommand = antCommand . " -Dproject.Folder=" . shellescape(projectFolder) . " retrieveSource"
		endif
	elseif "runTest" == a:command
		if a:0 < 1 || len(a:1) < 1
			echoerr "missing class names list parameter"
			return ""
		endif
		let classNameList = a:1
		call apexAnt#generateTestsXml(projectFolder, classNameList)
		" run tests on all classes included in the package
		if a:0 > 1 && a:2 == 'checkOnly'
			let antCommand = antCommand . " -DcheckOnly=true "
		endif	
		let antCommand = antCommand . " -Dproject.Folder=" . shellescape(projectFolder) . " deployAndRunTest"
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
	elseif "backup" == a:command
		"apexAnt#execute("backup", a:projectName, a:projectFolder, a:backupDirPath, a:projectXmlFilePath)
		if a:0 < 1 || len(a:1) < 1
			echoerr "missing backup folder path parameter"
			return ""
		endif
		let backupDirPath = a:1
		if !isdirectory(backupDirPath)
			echoerr "provied backupDirPath ".backupDirPath." is not valid directory"
			return ""
		endif
		if a:0 < 2 || len(a:2) < 1
			echoerr "missing full path to project.xml file"
			return ""
		endif
		let projectXmlFilePath = a:2
		if !filereadable(projectXmlFilePath)
			echoerr "file ". projectXmlFilePath . " is not readable."
			return ""
		endif
		let antCommand = antCommand . " -Dpackage.xml.file.path=" . shellescape(projectXmlFilePath). " -DbackupDir=" . shellescape(backupDirPath) . " backupSelected"

	elseif "delete" == a:command
		"apexAnt#execute(..., a:destructiveChangesFolder, a:checkOnly)
		if a:0 < 1 || len(a:1) < 1
			echoerr "missing 'Destructive Changes' folder path parameter"
			return ""
		endif
		let destructiveChangesDir = a:1
		if !isdirectory(destructiveChangesDir)
			echoerr "provied destructiveChangesFolder ".destructiveChangesDir." is not valid directory"
			return ""
		endif
		let checkOnly = a:2
		let antCommand = antCommand . " -DdestructiveChangesDir=" . shellescape(destructiveChangesDir). " -DcheckOnly=" . checkOnly . " deleteUnpackaged"

	else
		echoerr "Unsupported command".a:command
	endif
	let antCommand = antCommand ." 2>&1 |".g:apex_binary_tee." ".shellescape(ANT_ERROR_LOG)
	"create blank line after previous command
	echo " "
	"echo "antCommand=".antCommand
    call apexOs#exe(antCommand, 'M') "disable --more--
	"check if build is successful or failed but just because of syntax errors
	"in which case ant log will contain two lines like these:
	"BUILD FAILED
	".../apex-plugin/build.xml:59: FAILURES:
	"
	if len(apexUtil#grepFile(ANT_ERROR_LOG, 'BUILD FAILED\_.*FAILURES\|BUILD SUCCESSFUL\|BUILD FAILED')) < 1
		"if we are here then build failed for a reason which we do not
		"process nicely
		throw "OPERATION FAILED. Check error log. ".ANT_ERROR_LOG
	endif
	" init s:apex_last_log to use it subsequently in :ApexLog command
	let s:apex_last_log=ANT_ERROR_LOG

	return ANT_ERROR_LOG
endfunction

function! apexAnt#openLastLog()
	if exists("s:apex_last_log")
		:execute "e " . fnameescape(s:apex_last_log)
	else
		call apexUtil#info('Log has not been created in the current session.')
	endif
endfunction

" ask user which log type to use for running unit tests 
" result is assigned value of g:apex_test_logType variable
function! apexAnt#askLogType()
	let logType = 'None'
	if exists('g:apex_test_logType')
		let logType = g:apex_test_logType
	endif
	let g:apex_test_logType = apexUtil#menu('Select Log Type', ['None', 'Debugonly', 'Db', 'Profiling', 'Callout', 'Detail'], logType)
endfunction
