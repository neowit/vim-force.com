" File: apexDelete.vim
" Author: Andrey Gavrikov 
" Version: 0.1
" Last Modified: 2012-10-24
" Copyright: Copyright (C) 2010-2012 Andrey Gavrikov
"            Permission is hereby granted to use and distribute this code,
"            with or without modifications, provided that this copyright
"            notice is copied with it. Like anything else that's free,
"            this plugin is provided *as is* and comes with no warranty of any
"            kind, either expressed or implied. In no event will the copyright
"            holder be liable for any damages resulting from the use of this
"            software.
"
" apexDelete.vim - part of vim-force.com plugin
" Methods handling metadata Delete, aka destructiveChanges

if exists("g:loaded_apex_delete") || &compatible 
	finish
endif
let g:loaded_apex_delete = 1

" run destructive Delete on Staged files
"Args:
" param 1: (optional) path to file which belongs to apex project which needs
"			if not provided then project location will be determined by %:p
" param 2: (optional) destination project name, must match one of .properties file with
" param 3: (optional) options:
"				t - test mode, do not make any changes, just run test
"		
function! apexDelete#run(...)
	let filePath = expand("%:p") "default file
	if a:0 > 0
		let filePath = a:1
	endif
	let projectPair = apex#getSFDCProjectPathAndName(filePath)
	let projectName = projectPair.name
	let projectPath = projectPair.path
	if empty(projectName)
		echoerr "failed to determine proect location using file path ".filePath
		return
	endif

	let tempFolder = apexOs#createTempDir()
	" write package.xml for destructive delete
	call apexMetaXml#packageWriteDestructive(tempFolder)

	"generate package.xml called destructiveChanges.xml from staged files
	let package = apexMetaXml#packageXmlNew()
	let xmlNameByDirName = apexRetrieve#getTypeXmlByFolder(projectName, projectPath, 0)
	" {'weblinks': 'CustomPageWebLink', 'labels' : 'CustomLabels'}
	for l:file in apexStage#list(projectPath)
		"each file looks like: "classes/MyClass.cls", i.e. dir and name
		let filePair = split(l:file, "/")
		let l:type = filePair[0]
		let l:fname = filePair[1]
		call apexMetaXml#packageXmlAdd(package, l:type, l:fname)
	endfor
	if !empty(package)
		let destructiveChangesXmlPath = apexMetaXml#packageWrite(package, tempFolder, destructiveChanges.xml)
	endif
	"TODO continue here
	"verify that all of the above works and proceed with ANT command



endfunction
