" This file is part of vim-force.com plugin
"   https://github.com/neowit/vim-force.com
" File: apex.vim
" Last Modified: 2014-03-10
" Author: Andrey Gavrikov 
" Maintainers: 
" Version: 1.2
"
" apex.vim - main methods dealing with Project file synchronisation with SFDC

" deploy changed Apex files under current project
" format returned errors
" refresh project from Force.com
"
if exists("g:loaded_apex") || &compatible
  finish
endif
let g:loaded_apex = 1

let g:apex_backup_folder_time_format = "%Y-%m-%d-%H%M%S"
let g:apex_last_backup_folder = ''

let s:SRC_DIR_NAME="src"
let s:FILE_TIME_DIFF_TOLERANCE_SEC = 1 " if .cls and .cls-meta.xml file time differs by this number of seconds (or less) we consider time equal

let s:APEX_EXTENSIONS_WITH_META_XML = ['cls', 'trigger', 'page', 'scf', 'resource', 'component']
let s:APEX_EXTENSIONS = s:APEX_EXTENSIONS_WITH_META_XML + ['labels', 'object']

"folder where intermediate project data is stored
"this folder is safe to delete, it will be recreated
"as needed
let s:CACHE_FOLDER_NAME = ".vim-force.com"
let s:PACKAGE_XML_NAME = "package.xml"

" project name completion
" list .properties file names without extension
" Args:
" arg: ArgLead - the leading portion of the argument currently being
"			   completed on
" line: CmdLine - the entire command line
" pos: CursorPos - the cursor position in it (byte index)
"
function! apex#listProjectNames(arg, line, pos)
	let fullPathsProperties = apexOs#glob(g:apex_properties_folder . "**/*.properties")
	let fullPathsOauth = apexOs#glob(g:apex_properties_folder . "**/oauth2/*")
    let fullPaths = extend(fullPathsProperties, fullPathsOauth)

	let res = []
	for fullName in fullPaths
		let fName = apexOs#splitPath(fullName).tail
        if fName =~? ".properties$"
            let fName = fnamemodify(fName, ":r") " remove .properties
        endif
		"take into account file prefix which user have already entered
		if 0 == len(a:arg) || match(fName, a:arg) >= 0 
			call add(res, fnameescape(fName))
		endif	
	endfor
	return res
endfunction	

function! apex#completeQueryParams(arg, line, pos)
    "call writefile(["arg=" . a:arg, "line=".a:line, "pos=".a:pos], "~/temp/params.txt")
	let l:argList = split(a:line[:a:pos-1], '\%(\%(\%(^\|[^\\]\)\\\)\@<!\s\)\+', 1)
	let l:command = 'ApexQuery'
    let l:commandIndex = index(l:argList, l:command)
    if l:commandIndex < 0
        " no exact match, try to find "contains(l:command)" match
        let l:i = 0
        for str in l:argList
            if str =~ l:command
                let l:commandIndex = l:i
                break
            endif
            let l:i += 1
        endfor
    endif    
	let n = len(l:argList) - l:commandIndex - 2

	let funcs = ['s:completeAPIs', 'apex#listProjectNames']
    echo "funcs=" . funcs[n] . "; line=".a:line. "; pos=".a:pos . "; n=" .n . "; l=".string(l:argList) . "; commandIndex=".l:commandIndex
	if n >= len(funcs)
		return ""
	else
		return call(funcs[n], [a:arg, a:line, a:pos])

endfunction

function! s:completeAPIs(arg, line, pos)
	return apexUtil#commandLineComplete(a:arg, a:line, a:pos, ['Partner', 'Tooling'])
endfunction	

function! s:listModeNames(arg, line, pos)
	return ['deploy', 'checkOnly']
endfunction	

" Args:
" arg: ArgLead - the leading portion of the argument currently being
"			   completed on
" line: CmdLine - the entire command line
" pos: CursorPos - the cursor position in it (byte index)
"
function! s:completeSaveOrDeployParams(funcs, arg, line, pos)
	let l = split(a:line[:a:pos-1], '\%(\%(\%(^\|[^\\]\)\\\)\@<!\s\)\+', 1)
	"let n = len(l) - index(l, 'ApexDeploy') - 2
	let n = len(l) - 0 - 2
	"echomsg 'arg='.a:arg.'; n='.n.'; pos='.a:pos.'; line='.a:line
	let funcs = a:funcs
	if n >= len(funcs)
		return ""
	else
		return call(funcs[n], [a:arg, a:line, a:pos])
endfunction	

function! apex#completeDeployParams(arg, line, pos)
    return s:completeSaveOrDeployParams(['s:listModeNames', 'apex#listProjectNames'], a:arg, a:line, a:pos)
endfunction

function! apex#completeSaveParams(arg, line, pos)
    return s:completeSaveOrDeployParams(['s:listModeNames'], a:arg, a:line, a:pos)
endfunction


" use this method to validate existance of .properties file for specified
" project name
" Args:
" param 1: projectName - name of project which must match existing .properties
" file with login details
function! apex#getPropertiesFilePath(projectName)
	let l:providedProjectName = substitute(a:projectName, '.properties$', '', '')
	let l:propertiesFolder = apexOs#removeTrailingPathSeparator(g:apex_properties_folder)

	let l:propFilePath = apexOs#joinPath([l:propertiesFolder, l:providedProjectName]).".properties"
	"check if we need to append .properties
	"echo "providedProjectName=".l:providedProjectName
	"echo "propFilePath=".l:propFilePath
	if !filereadable(l:propFilePath)
		echoerr l:propFilePath." with login details does not exist or not readable."
		return
	endif
	return l:propFilePath
endfunction

" return existing or create new and return path to
" plugin cache directory
function! apex#getCacheFolderPath(projectRec)
	let cacheFolderPath = apexOs#joinPath([a:projectRec.path, s:CACHE_FOLDER_NAME])

	if !isdirectory(cacheFolderPath)
		"cache directory does not exist, need to create it first
		call apexOs#createDir(cacheFolderPath)
	endif
	return cacheFolderPath
endfunction

" using /full/path/some-name/package.xml guess what package name may be 
function! s:getPackageName(packageXmlPath)
    let pathPair = apexOs#splitPath(a:packageXmlPath)

    let packageName = ''
    if len(pathPair.head) > 0 " head = /full/path/some-name/
        let pathPair = apexOs#splitPath(pathPair.head)
        let packageName = s:extractPackageNameFromXml(a:packageXmlPath)
        " pathPair.tail = 'some-name'
        if len(packageName) < 1 && 'src' != pathPair.tail 
            let packageName = pathPair.tail " assume current source parent ('some-name') folder represents package name
        endif
    endif

    if len(packageName) > 0 
        return packageName
    else
        return '' " do NOT return 'unpackaged', it causes unwanted consequences in the code which is not aware of it
    endif
endfunction

function! s:extractPackageNameFromXml(packageXmlPath)
    let filePath = a:packageXmlPath
    if filereadable(expand(filePath))
        " try to extract fullName node in case this is a packaged source (as
        " opposed to unpackaged)
        let lines = apexUtil#grepFile(filePath, "<fullName>.*</fullName>")
        if 1 == len(lines)
            return matchstr(lines[0], '<fullName>\(\zs.*\ze\)</fullName>')
        endif    
    endif
    return ''
endfunction
""""""""""""""""""""""""""""""""""""""""""""""""
" Get SFDC project path and name assuming we have a standard folder structure and
" project folder matches SFDC project name
" i.e.
" <Project-Folder>
"	src
"		classes
"		triggers
"		objects
"		...
" Note: there is a side effect - if filePath = "" then Vim does finddir from
" currently open buffer/file path
" @return: {path:"/path/to/project/", name:"project name"}
""""""""""""""""""""""""""""""""""""""""""""""""
function! apex#getSFDCProjectPathAndName(filePath) 
	let path = a:filePath
    
    let pathPair = apexOs#splitPath(path)
	let srcDirPath = ""
    let l:packageName = ''

    let packageXmlPath = ''
    if s:PACKAGE_XML_NAME == pathPair.tail
        let packageXmlPath = path
    else
        if !isdirectory(path)
            let pathPair = apexOs#splitPath(path)
            let path = pathPair.head
        endif    

        " find package.xml and assume that it is in the root of current package
        while len(path) > 0
            "let l:files = readdir(path,  {n -> n =~ "^" . s:PACKAGE_XML_NAME . "$"} )
            " can not use readdir() because it is not currently available in
            " standard ubuntu 18.04 repo
            let l:files = filter(glob(apexOs#joinPath(path, '*'), 0, 1), {i,p-> (p =~ s:PACKAGE_XML_NAME . "$") && !isdirectory(p)})

            if 1 == len(l:files) 
                " found package.xml in the current path
                let packageXmlPath = apexOs#joinPath(path, s:PACKAGE_XML_NAME)
                break
            endif
            let pathPair = apexOs#splitPath(path)
            let path = pathPair.head
        endwhile	
    endif

    if len(packageXmlPath) > 0            
        let l:packageName = s:getPackageName(packageXmlPath)
        let pathPair = apexOs#splitPath(packageXmlPath)
        let srcDirPath = pathPair.head
    endif

	if len(srcDirPath) < 1
		" perhaps we are inside unpacked resource bundle
		let srcDir = apexResource#getApexProjectSrcPath(a:filePath)
		if len(srcDir) > 0
			let srcDirParent = apexOs#splitPath(srcDir).head
		endif
	endif

	if srcDirPath == ""
		call apexUtil#throw("project root not found")
		return {'path': "", 'name': ""}
	endif
	let projectFolder = apexOs#splitPath( srcDirPath ).head
	let projectName = apexOs#splitPath( projectFolder).tail
	let projectObj = {'path': projectFolder, 'name': projectName, 'packageName': l:packageName}
    "echomsg "projectObj=".string(projectObj)
    return projectObj
endfunction    

" @deprecated
function! apex#getSFDCProjectPathAndName2(filePath) 
	" go up until we find ./src/ folder or .vim-force.com folder
	" finddir does not work on win32, vim does not understand drive letter	
	" "let srcDir = finddir(s:SRC_DIR_NAME, fnameescape(a:filePath). ';')
	let path = a:filePath
	let srcDirParent = ""
    let l:packageName = ''

	while len(path) > 0
		let pathPair = apexOs#splitPath(path)
		if pathPair.tail == s:SRC_DIR_NAME
			let srcDirParent = pathPair.head
			break
		endif	
		let path = pathPair.head
	endwhile	

	if len(srcDirParent) < 1
		" perhaps we are inside a named package
        " find project root by checking the location of folder .vim-force.com
        let path = a:filePath
        while len(path) > 0
            let pathPair = apexOs#splitPath(path)
            if pathPair.tail == s:CACHE_FOLDER_NAME
                let srcDirParent = pathPair.head
                let l:packageName = pathPair.tail
                break
            else
                if len(readdir(pathPair.head,  {n -> n =~ "^".s:CACHE_FOLDER_NAME."$"} )) > 0
                    let l:packageName = pathPair.tail
                    let srcDirParent = pathPair.head
                    break
                endif
            endif
            let path = pathPair.head
        endwhile	
	endif

	if len(srcDirParent) < 1
		" perhaps we are inside unpacked resource bundle
		let srcDir = apexResource#getApexProjectSrcPath(a:filePath)
		if len(srcDir) > 0
			let srcDirParent = apexOs#splitPath(srcDir).head
		endif
	endif

	if srcDirParent == ""
		throw "project root not found"
		return {'path': "", 'name': ""}
	endif
	let projectFolder = srcDirParent 
	let projectName = apexOs#splitPath( projectFolder).tail
	let projectObj = {'path': projectFolder, 'name': projectName, 'packageName': l:packageName}
    return projectObj
endfun

" return full path to SRC (or package) folder
" ex: "/path/to/project-name/src"
" Args:
" filePath - [optional] if provided then this file is used to determine src
" path, otherwise expand("%:p") is used
function! apex#getApexProjectSrcPath(...)
	let filePath = expand("%:p")
	if a:0 >0
		let filePath = a:1
	endif	
	let projectPair = apex#getSFDCProjectPathAndName(filePath)
    let srcDirName = apexUtil#getNotEmpty(projectPair.packageName, s:SRC_DIR_NAME)
    
	let srcPath = apexOs#joinPath([projectPair.path, srcDirName])
    if !isdirectory(srcPath) && 'unpackaged' == srcDirName
        " try ./scr foledr instead of ./unpackaged
        let srcPath = apexOs#joinPath([projectPair.path, s:SRC_DIR_NAME])
    endif
    if !isdirectory(srcPath)
        " try ./scr foledr instead of ./unpackaged
        throw "failed to indentify src folder for file: ". filePath
    endif
	return srcPath
endfunction
"
" if file is inside package folder then return package name, 
" otherwise "unpackaged" 
" ex: "myPackage"
" Args:
" filePath - [optional] if provided then this file is used to determine src
" path, otherwise expand("%:p") is used
function! apex#getCurrentPackageName(...)
	let filePath = expand("%:p")
	if a:0 >0
		let filePath = a:1
	endif	
	let projectPair = apex#getSFDCProjectPathAndName(filePath)
    return apexUtil#getNotEmpty(projectPair.packageName, "unpackaged")
endfunction

function! apex#getFilePathRelativeProjectFolder(filePath)
	let leftFile = a:filePath
	let projectPair = apex#getSFDCProjectPathAndName(leftFile)
	let leftProjectName = projectPair.name
	let filePathRelativeProjectFolder = strpart(leftFile, len(projectPair.path))
    return filePathRelativeProjectFolder
endfunction

" get all available buffers which have file path relative current project
" Param1: projectPath - full path to project
" Param2: [optional] deployable extensions only
" return: [1, 5, 6, 7, 8] - list of buffer numbers with project files 
function! apex#getOpenBuffers(projectPath, ...)
	let last_buffer = bufnr('$')
	let n = 1
	let buffersMap = {}
	let projectPathNormal = substitute(a:projectPath, '\', '/', 'g')
	let extPattern = join(s:APEX_EXTENSIONS, "\\|\\.") 
	let extPattern = "\\." .extPattern . "$"
	let deployableOnly = 0
	if a:0 > 0 && 'deployableOnly' == a:1
		let deployableOnly = 1
	endif

	while n <= last_buffer
		if buflisted(n) 
			if getbufvar(n, '&modified')
				echohl ErrorMsg
				echomsg 'No write since last change for buffer'
				echohl None
			else
				" check if buffer belongs to the project
				let fullpath = expand('#'.n.':p')
				if deployableOnly
					" check if file is supported
					if match(fullpath, extPattern) <= 0
						"echo "skip file: " . fullpath
						let n = n+1
						continue
					endif
				endif
				let fullpath = substitute(fullpath, '\', '/', 'g')
				if len(fullpath) >0 && !has_key(buffersMap, fullpath) && 0 == match(fullpath, projectPathNormal)
					let buffersMap[fullpath] = n
				endif
			endif
		endif
		let n = n+1
	endwhile

	return values(buffersMap)
endfunction

"""""""""""""""""""""""""""""""""""""""""""""""""""
" Utility methods
"""""""""""""""""""""""""""""""""""""""""""""""""""
" close all empty quickfix windows
function! CloseEmptyQuickfixes()
    let last_buffer = bufnr('$')
	let n = 1
	while n <= last_buffer
		if buflisted(n)
			if "quickfix" == getbufvar(n, '&buftype')
				if empty(getqflist())
					silent exe 'bdel ' . n
				endif	
			endif
		endif
		let n = n+1
	endwhile
endfun

