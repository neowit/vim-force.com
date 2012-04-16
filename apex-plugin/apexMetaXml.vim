" File: apexMetaXML.vim
" Author: Andrey Gavrikov 
" Version:0.1
" Last Modified: 2012-06-19
" Copyright: Copyright (C) 2010-2012 Andrey Gavrikov
"            Permission is hereby granted to use and distribute this code,
"            with or without modifications, provided that this copyright
"            notice is copied with it. Like anything else that's free,
"            this plugin is provided *as is* and comes with no warranty of any
"            kind, either expressed or implied. In no event will the copyright
"            holder be liable for any damamges resulting from the use of this
"            software.
"
" apexMetaXML.vim - utility methods for generating *-meta.xml files when new
" Class/Page/Trigger is created
"
" Part of vim/force.com plugin
"
if exists("g:loaded_apex_metaXml") || &compatible
  finish
endif
let g:loaded_apex_metaXml = 1

"get script folder
"This has to be outside of a function or anything, otherwise it does not return
"proper path
let s:PLUGIN_FOLDER = expand("<sfile>:h")

let s:SUPPORTED_FILE_TYPES = ["ApexClass", "ApexPage", "ApexTrigger"]

" request file type/name, check that file does not exist, create file and switch
" buffer to the new file
" param: filePath - full path of current apex file - needed to determine
" project location
function apexMetaXml#createFileAndSwitch(filePath)
	let projectPath = apex#getSFDCProjectPathAndName(a:filePath).path
	let typeAndName = s:fileTypeMenu(a:filePath)
	if len(typeAndName) < 1
		echo "\n"
		echomsg "Selection aborted"
		return " user aborted
	endif
	let fileContent = s:getFilesContent{typeAndName.fileType}(typeAndName.fileName)
	"check that required file does not exist
	let fileNameWithExtension = typeAndName.fileName.".".fileContent.fileExtension
	let newFilePath = apexOs#joinPath([projectPath, "src",  fileContent.folderName, fileNameWithExtension])
	if filereadable(newFilePath)
		echo "\n"
		call apexUtil#warning("File already exists: " . newFilePath)
		return
	endif
	"echo "About to create file: ".newFilePath
	"generate -meta.xml
	let metaFilePath =  newFilePath . "-meta.xml"
	let metaRes = writefile(fileContent.metaContent, metaFilePath )
	if 0 == metaRes 
		"set last modified time 10 seconds in the past to make sure file is picked up for
		"deplyment due to difference betwen -meta.xml and actual file times
		call apexOs#setftime(metaFilePath, localtime() -10 )
		let fileRes = writefile(fileContent.mainFileContent, newFilePath)
		if 0 == fileRes
			"switch to the buffer with newly created file
			silent exe "edit ".fnameescape(newFilePath)
		endif	
	endif



endfun



" display menu with file types
" @return: {fileType: "Selected File Type", fileName: "User defined Fiel name"}
"		ex: {fileType: "ApexClass", fileName: "MyControllerTest"}
"
function s:fileTypeMenu(filePath)
	let projectPath = apex#getSFDCProjectPathAndName(a:filePath).path
	if projectPath == ""
		echoerr "src folder not found using file path: ".a:filePath
		return ""
	endif
	let textList = ["Select file Type:"]
	let i = 1
	for ftype in s:SUPPORTED_FILE_TYPES
		let textList = textList + [i.". ".ftype]
		let i = i + 1
	endfor	
	let res = inputlist(textList)
	if res > 0 && res <= len(s:SUPPORTED_FILE_TYPES)
		let fType = s:SUPPORTED_FILE_TYPES[res-1]
		let fName = input("Please enter ".fType." name: ")
		if len(fName) < 1
			return {}
		endif	
		return {"fileType": fType, "fileName": fName}
	endif
	return {} " error or calcelled selection
endfun	


" generate 2 files
" <classname>.cls
" <classname>.cls-meta.xml
" @return: {mainFileContent: [lines to be inserted in main file], 
"			metaContent: [lines to be inserted into meta file],
"			fileExtension: "cls",
"			folderName: "classes"}
function s:getFilesContentApexClass(fName)
	let fileContent = ["public with sharing class ". a:fName . "{", "}"]

	let metaContent = []
	let metaContent = metaContent + ["<?xml version=\"1.0\" encoding=\"UTF-8\"?>"]
	let metaContent = metaContent + ["<ApexClass xmlns=\"http://soap.sforce.com/2006/04/metadata\">"]
	let metaContent = metaContent + ["    <apiVersion>". g:apex_API_version . "</apiVersion>"]
	let metaContent = metaContent + ["    <status>Active</status>"]
	let metaContent = metaContent + ["</ApexClass>"]

	return {"mainFileContent": fileContent, "metaContent": metaContent, "fileExtension": "cls", "folderName": "classes"}

endfun	

" generate 2 files
" <pagename>.page
" <pagename>.page-meta.xml
" @return: {mainFileContent: [lines to be inserted in main file], 
"			metaContent: [lines to be inserted into meta file],
"			fileExtension: "page",
"			folderName: "pages"}
function s:getFilesContentApexPage(fName)
	let fileContent = ["<apex:page>", "</apex:page>"]

	let metaContent = []
	let metaContent = metaContent + ["<?xml version=\"1.0\" encoding=\"UTF-8\"?>"]
	let metaContent = metaContent + ["<ApexPage xmlns=\"http://soap.sforce.com/2006/04/metadata\">"]
	let metaContent = metaContent + ["    <apiVersion>". g:apex_API_version . "</apiVersion>"]
	let metaContent = metaContent + ["    <label>".a:fName."</label>"]
	let metaContent = metaContent + ["</ApexPage>"]

	return {"mainFileContent": fileContent, "metaContent": metaContent, "fileExtension": "page", "folderName": "pages"}

endfun	

" generate 2 files
" <triggername>.trigger
" <triggername>.trigger-meta.xml
" @return: {mainFileContent: [lines to be inserted in main file], 
"			metaContent: [lines to be inserted into meta file],
"			fileExtension: "trigger",
"			folderName: "triggers"}
function s:getFilesContentApexTrigger(fName)
	let fileContent = ["trigger " . a:fName . " on <Object> (<events>) {", "}"]

	let metaContent = []
	let metaContent = metaContent + ["<?xml version=\"1.0\" encoding=\"UTF-8\"?>"]
	let metaContent = metaContent + ["<ApexTrigger xmlns=\"http://soap.sforce.com/2006/04/metadata\">"]
	let metaContent = metaContent + ["    <apiVersion>". g:apex_API_version . "</apiVersion>"]
	let metaContent = metaContent + ["    <status>Active</status>"]
	let metaContent = metaContent + ["</ApexTrigger>"]

	return {"mainFileContent": fileContent, "metaContent": metaContent, "fileExtension": "trigger", "folderName": "triggers"}

endfun	
