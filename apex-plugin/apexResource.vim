" This file is part of vim-force.com plugin
"   https://github.com/neowit/vim-force.com
" File: apexResource.vim
" Last Modified: 2014-03-10
" Author: Andrey Gavrikov 
" Maintainers: 
"
" handler for zipped .resource files
"
if exists("g:loaded_apexResource") || &compatible
  finish
endif
let g:loaded_apexResource = 1

let s:RESOURCES_DIR = 'resources_unpacked' " NOTE if dir name here is changed then ftdetect/vim-force.com.vim must be updated as well

if !exists("g:zip_zipcmd")
	let g:zip_zipcmd= "zip"
endif
if !exists("g:zip_unzipcmd")
	let g:zip_unzipcmd= "unzip"
endif


function apexResource#browse(zipfile)
	" zipped file always start with PK
	if !filereadable(a:zipfile) || readfile(a:zipfile, "", 1)[0] !~ '^PK'
		"open as normal (not zip) file
		exe "noautocmd e ".fnameescape(a:zipfile)
		return
	endif

	let resourceName = apexOs#splitPath(a:zipfile).tail
	call apexUtil#info(resourceName . " is a zip file and will be opened as Resource in ".s:RESOURCES_DIR." folder")

	if !executable(g:zip_unzipcmd)
		redraw!
		call apexUtil#error( "unzip not available on your system")
		"let &report= repkeep
		return
	endif

	let extractedResourceDir = apexOs#joinPath(s:getUnpackedResourcesRootFolderFromSrc(a:zipfile), resourceName)
	if isdirectory(extractedResourceDir)
		call apexUtil#warning("Unpacked resource folder already exists, below ".g:zip_unzipcmd." will ask you what you want to do with that.")
		echo " "
	endif

	let commandLine = "keepjumps !".g:zip_unzipcmd." ".shellescape(a:zipfile).' -d '.shellescape(extractedResourceDir)
	"echomsg commandLine
	exe commandLine
	if v:shell_error != 0
		redraw!
		call apexUtil#warning( a:zipfile." is not a zip file")
		return
	endif
	" let user select a file from unpacked resource
	exe "e ".fnameescape(extractedResourceDir)

endfunction

" when file from s:RESOURCES_DIR is written - re-pack appropriate .resource
function! apexResource#write(filePath)
	let apexResourcesDir = apexOs#joinPath(apexResource#getApexProjectSrcPath(a:filePath), 'staticresources')
	let unpackedResourceDir = s:getBundlePath(a:filePath)
	let resourceName = apexOs#splitPath(unpackedResourceDir).tail

	let resourcePath = apexOs#joinPath(apexResourcesDir, resourceName)
	let existingResource = filereadable(resourcePath)
	if !existingResource
		if 'y' !~# apexUtil#input('resource '.resourcePath.' does not exist. Create [y/N]? ', 'yYnN', 'n')
			return
		endif
	endif

	if !executable(g:zip_zipcmd)
		redraw!
		call apexUtil#error( "Your system doesn't appear to have the zip binary")
		return
	endif

	if !isdirectory(apexResourcesDir)
		call apexOs#splitPath(apexResourcesDir)
	endif

	"zip -r archivefile3 /home/joe/papers
	"copies /home/joe/papers into zip file: archivefile3
	let curdir= getcwd()
	if 0 == s:changeDir(unpackedResourceDir)
		let zipCommand = g:zip_zipcmd." -r ".shellescape(resourcePath)." *"
		"echo zipCommand
		let shellMessage = system(zipCommand)
		"echomsg "zip result=".res
		call s:changeDir(curdir)
		if 0 != v:shell_error
			redraw!
			call apexUtil#error("Unable to update ".resourcePath."\n ".shellMessage)
			return
		endif
	endif

	if !existingResource && !filereadable(resourcePath . "-meta.xml")
        let l:cacheControl = apexUtil#menu('Select Cache Control', ['Private (for internal applications)', 'Public (un-authenticated force.com sites)'], 'Private')
        if l:cacheControl =~? "public"
            let l:cacheControl = "Public"
        else
            let l:cacheControl = "Private"
        endif
		call s:writeStaticResourceMetaXml(resourcePath, l:cacheControl)
	endif

	"echomsg "wrote ".a:filePath
endfunction

"Params:
"Arg1: unpackedFilePath - a file under 'resources_unpacked/<name>.resource' folder
"Returns: full path to static resource corresponding given unpacked file
"example:
"	filePath: .../project1/resources_unpacked/my.resource/css/main.css
"	result: '.../project1/src/staticresources/my.resource'
function! apexResource#getResourcePath(filePath)
    let unpackedResourceDir = s:getBundlePath(a:filePath, 1)
    if len(unpackedResourceDir) < 1
        return '' " not inside 'resources_unpacked'
    endif    
    
	let apexResourcesDir = apexOs#joinPath(apexResource#getApexProjectSrcPath(a:filePath), 'staticresources')
	let resourceName = apexOs#splitPath(unpackedResourceDir).tail

	let resourcePath = apexOs#joinPath(apexResourcesDir, resourceName)
	let existingResource = filereadable(resourcePath)
    if existingResource
        return resourcePath
    endif
    return ''

endfunction    


function! s:changeDir(newdir) abort
	try
		exe "cd ".fnameescape(a:newdir)
	catch /^Vim\%((\a\+)\)\=:E344/
		redraw!
		call apexUtil#error("Failed to change dir to ". a:newdir . " ".v:exception)
		return 1
	endtry

	return 0

endfunction

"Params:
"Arg1: unpackedFilePath - a file under 'resources_unpacked/<name>.resource' folder
"Arg2: silent: 0|1 [optional]
"Returns: full path to unpacked resource dir
"example:
"	filePath: .../project1/resources_unpacked/my.resource/css/main.css
"	result: '.../project1/resources_unpacked/my.resource'
function! s:getBundlePath(unpackedFilePath, ...) abort
	let path = a:unpackedFilePath
	let srcDirParent = ""
	let prevTail = ""
	let bundlePath = ""

	while len(path) > 0
		let pathPair = apexOs#splitPath(path)
		if pathPair.tail == s:RESOURCES_DIR
			let bundlePath = apexOs#joinPath(path, prevTail)
			break
		endif	
		let path = pathPair.head
		let prevTail = pathPair.tail
	endwhile

    let isSilent = a:0 > 0 && 1 == a:1
	if len(bundlePath) < 1 && !isSilent
		call apexUtil#error("Failed to identify resource name for file " . path)
	endif
	return bundlePath
endfunction

"Params:
"Arg: fileUnderSrc - any file under src/ folder
"Returns: full path to '.../resources_unpacked' dir
"example:
"	filePath: .../project1/src/classes/main.cls
"	result: '.../project1/resources_unpacked'
function! s:getUnpackedResourcesRootFolderFromSrc(fileUnderSrc)
	let projectPair = apex#getSFDCProjectPathAndName(a:fileUnderSrc)
	let projectName = projectPair.name
	let projectPath = projectPair.path

	let resourcesDir = apexOs#joinPath(projectPath, s:RESOURCES_DIR)
	if !isdirectory(resourcesDir)
		call apexOs#createDir(resourcesDir)
	endif
	return resourcesDir
endfunction

"Params:
"Arg: unpackedFilePath - a file under 'resources_unpacked/<name>.resource' folder
"Returns: full path to project's src/ folder
function! apexResource#getApexProjectSrcPath(unpackedFilePath)
	let bundlePath = s:getBundlePath(a:unpackedFilePath)
	let bundlesRoot = apexOs#splitPath(bundlePath).head
	let projectFolder = apexOs#splitPath(bundlesRoot).head
	return apexOs#joinPath(projectFolder, 'src')
endfunction

function s:writeStaticResourceMetaXml(resourcePath, cacheControl)
	let metaContent = []
	let metaContent = metaContent + ["<?xml version=\"1.0\" encoding=\"UTF-8\"?>"]
	let metaContent = metaContent + ["<StaticResource xmlns=\"http://soap.sforce.com/2006/04/metadata\">"]
	let metaContent = metaContent + ["    <cacheControl>" . a:cacheControl . "</cacheControl>"]
	let metaContent = metaContent + ["    <contentType>application/zip</contentType>"]
	let metaContent = metaContent + ["</StaticResource>"]

	call writefile(metaContent, a:resourcePath . "-meta.xml")

endfun	

" open resources as ZIP file, see also apexResource#browse
au! BufReadCmd */staticresources/*.resource call apexResource#browse(expand("<amatch>"))
exe "au! BufWritePost */".s:RESOURCES_DIR."/* call apexResource#write(expand('<amatch>'))"

