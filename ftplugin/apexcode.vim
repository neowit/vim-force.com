" Vim filetype plugin file
" Language: ApexCode	
" Maintainer:	Andrey Gavrikov
" setup environment for Apex Code development
"

" Only do this when not done yet for this buffer
if exists("b:did_ftplugin")
  finish
endif
let b:did_ftplugin = 1 

"load all force.com/apex-plugin scripts after vim starts and when apexcode
"filetype is detected
runtime! apex-plugin/**/*.vim

set tags=./tags,tags,../classes/tags,../triggers/tags,../pages/tags,../components/tags


function! apexcode#UpdateIdeCtags()
    silent !ctags -f ./tags -R .
endfunction
command! -nargs=0 -bar ApexUpdateCtags call apexcode#UpdateIdeCtags()

" when saving any *.cls file update ctags database
"au BufWritePost *.cls,*.trigger,*.page   :call {MyUpdateCtagsFunction}()



""""""""""""""""""""""""""""""""""""""""""""""""
" Taglist plugin settings
""""""""""""""""""""""""""""""""""""""""""""""""
" show tags only for current file
let Tlist_Show_One_File = 1

" make sure s:Apex_TList_Toggle is defined only once otherwise 
" there will be an error because system will call apexcode.vim every time when
" filetype changes inside of s:Apex_TList_Toggle
if !exists("b:Apex_TList_Toggle_Defined")

    " http://stackoverflow.com/questions/1790623/how-can-i-make-vims-taglist-plugin-show-useful-information-for-javascript
    "
    " Taglist plugin does not support mixed filetypes like: apexcode.java
    " so we have to trick it like if &filetype was = 'apexcode'
    " i.e. every time when Taglist is called set filetype=apexcode temporarely
    " and then revert back to what it was
    function! s:Apex_TList_Toggle()
        let b:Apex_TList_Toggle_Defined = 1

        " Save the 'filetype', as this will be changed temporarily
        let l:old_filetype = &filetype

        let l:changedFileType = 0
        " check if this is apexcode file
        if stridx(l:old_filetype, 'apexcode') >= 0
            " set custom filetype temporarely
            exe 'set filetype=apexcode'
            let l:changedFileType = 1
        endif    
        exe 'TlistToggle'

        if l:changedFileType
            " Restore the previous state
            let &filetype = l:old_filetype
        endif
    endfunction

    " Define the user command to manage the taglist window
    command! -nargs=0 -bar ApexTListToggle call s:Apex_TList_Toggle()

endif

" Enable ApexCode language in Taglist plugin
" (set ft=apexcode) - treat it as java
let tlist_apexcode_settings = 'java;p:package;c:class;i:interface;f:field;m:method'

""""""""""""""""""""""""""""""""""""""""""""""""
" Fix Syntax highlighting problems
" http://vim.wikia.com/wiki/Fix_syntax_highlighting
""""""""""""""""""""""""""""""""""""""""""""""""
autocmd BufEnter * :syntax sync fromstart

""""""""""""""""""""""""""""""""""""""""""""""""
" Disable Automatic Newline At End Of File
" http://vim.wikia.com/wiki/VimTip1369
""""""""""""""""""""""""""""""""""""""""""""""""
" Preserve noeol (missing trailing eol) when saving file. In order
" to do this we need to temporarily 'set binary' for the duration of
" file writing, and for DOS line endings, add the CRs manually.
" For Mac line endings, also must join everything to one line since it doesn't
" use a LF character anywhere and 'binary' writes everything as if it were Unix.

" This works because 'eol' is set properly no matter what file format is used,
" even if it is only used when 'binary' is set.

augroup automatic_noeol
autocmd!

autocmd BufWritePre  * call TempSetBinaryForNoeol()
autocmd BufWritePost * call TempRestoreBinaryForNoeol()

fun! TempSetBinaryForNoeol()
  let s:save_binary = &binary
  if ! &eol && ! &binary
    setlocal binary
    " if &ff == "dos" || &ff == "mac"
      " undojoin | silent 1,$-1s#$#\=nr2char(13)
    " endif
    " if &ff == "mac"
      " let s:save_eol = &eol
      " undojoin | %join!
      " " mac format does not use a \n anywhere, so don't add one when writing in
      " " binary (uses unix format always)
      " setlocal noeol
    " endif
  endif
endfun

fun! TempRestoreBinaryForNoeol()
  if ! &eol && ! s:save_binary
    " if &ff == "dos"
      " undojoin | silent 1,$-1s/\r$/
    " elseif &ff == "mac"
      " undojoin | %s/\r/\r/g
      " let &l:eol = s:save_eol
    " endif
    setlocal nobinary
  endif
endfun

augroup END


""""""""""""""""""""""""""""""""""""""""""""""""
" Apex commands 
""""""""""""""""""""""""""""""""""""""""""""""""

"defined a command to run MakeApex
command! -nargs=0 ApexDeploy :call apex#MakeProject()
command! -nargs=0 ApexDeployOpen :call apex#MakeProject('', 'open')
command! -nargs=0 ApexDeployConfirm :call apex#MakeProject('', 'confirm')
command! -nargs=0 DeployApexOpen :call apex#MakeProject('', 'open')

command! -nargs=0 ApexRefreshProject :call apex#refreshProject()
command! RefreshSFDCProject :ApexRefreshProject
command! ApexRefreshFile :call apex#refreshFile(expand("%:p"))
command! ApexPrintChanged :call apex#printChangedFiles(expand("%:p"))

" before refresh all changed files are backed up, so we can compare refreshed
" version with its pre-refresh condition
command! ApexCompareWithPreRefreshVersion :call apexUtil#compareWithPreRefreshVersion(apexOs#getBackupFolder())
command! ApexCompare :call ApexCompare()

" initialise Git repository and add files
command! ApexGitInit :call apexUtil#gitInit()

"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" Apex Code - compare current file with its own in another Apex Project
"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
command! DiffUnderEclipse :ApexCompare

""""""""""""""""""""""""""""""""""""""""""""""""
" NERDTree plugin settings
""""""""""""""""""""""""""""""""""""""""""""""""
" hide -meta.xml files
let NERDTreeIgnore=['.*\~$']
let NERDTreeIgnore+=['.*\-meta\.xml$']


" Change javascript highlighting color inside of visualforce pages from Special to Normal
hi link javaScript Normal


