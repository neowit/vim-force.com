# Vim plugin for developing on force.com      

### Update June 2014  
If you are getting `java.lang.ClassCastException: scala.util.parsing.json.JSONArray cannot be cast to java.lang.String` when trying to deploy Apex Class with syntax error(s) then you are most likely affected by what appears to be a backwards compatibility bug in Summer'14. Upgrade of `tooling-force.com` jar to [v0.1.4.2](https://github.com/neowit/tooling-force.com/releases/tag/v0.1.4.2) should fix this.

Update Feb. 2014  
'master' branch of vim-force.com is no longer based on Ant and [force.com migration tool](http://www.salesforce.com/us/developer/docs/daas/). This version requires config changes, see `:help force.com-installation`, `:help g:apex_tooling_force_dot_com_path` and `:help force.com-config-example`.  
If you want to continue using Ant + ant-salesforce.jar then switch to [ant-based](https://github.com/neowit/vim-force.com/tree/ant-based) branch.  

salesforce.com / force.com plugin for Vim version 7.3 or later.  
Requires `:set nocompatible`


## DESCRIPTION                                             

vim-force.com plugin is a bunch of .vim scripts that allow to develop on force.com 
platform using Vim.

It is designed for those who do not feel productive in Force.com IDE for Eclipse.

General vim-force.com overview - http://www.youtube.com/watch?v=x5zKA6V__co  
`:ApexRetrieve` command demo - http://youtu.be/umO86ji2Iqw  
`:ApexStage` command demo - http://youtu.be/zQg8LORh8uc

Other vim plugins recommended for use alongside vim-force.com plugin  
* FuzzyFinder - http://www.youtube.com/watch?v=EtiaXVnTA4g  
* SnipMate - http://www.youtube.com/watch?v=Ri_DP1sRn2o  
* NERDTree - http://www.youtube.com/watch?v=d93o9qAqIhE  
* TagList - http://www.youtube.com/watch?v=Suk45FHU6s8  
* TagBar (alternative to TagList) - [screenshot](https://f.cloud.github.com/assets/115889/378070/f8d241b0-a513-11e2-802e-d4419aac586d.png)

## FEATURES

* Build/Save to SFDC
  - with error reporting
  - "Run test"
    * Execute unit tests in all modified files
    * Execute unit tests in a selected Class
    * Execute *selected* test method in a selected Class
    * Display [code coverage](https://f.cloud.github.com/assets/552057/2147462/89eec2b0-93d2-11e3-9207-432ef8d90763.png) after running test
	

* Deploy from one Org to Another

* Delete selected metadata from SFDC

* Execute Anonymous
  - whole buffer or selected lines  
          
* Persistent "Stage" for cherry-picking and re-using list of components to be deployed or deleted

* Load/update metadata from SFDC
  - Retrieve All or Selected components of given metadata type.  
Support for metadata types that reside inside folders (e.g. Document, Dashboard or Report) is limited because requires querying data (in addition to metadata).

* Create triggers/classes/pages

* Refresh current file from SFDC, Refresh whole project from SFDC

* Search
  - find word in classes/triggers  
  - find word everywhere  
  - find visual selection  

* Syntax highlighting
  - supports syntax highlighting of Apex Classes, Triggers, Pages, JS Resources

* Basic (really basic) Visualforce code completion
	- try following in .page file  
      `< Ctrl-X,Ctrl-U`  
      `<apex: Ctrl-X,Ctrl-U`  
      `<chatter Ctrl-X,Ctrl-U`

* Handling content of zipped .resource files

## LIMITATIONS

vim force.com plugin does not support creating force.com project. Use provided
template instead.

Salesforce.com API does not (in most cases) report error line numbers
in Visualforce pages, making it impossible to go-to actual problem line if
compile/save fails due to syntax error. This is similar to Force.com IDE for
Eclipse.

Current version does not support environment aware code completion.  
For example if you write:  
	`String val = 'abc';`  
typing  
	`val.`  
will not bring the list of String methods as Force.com IDE may do.

On MS Windows default configuration spawns separate DOS/CMD window on every call
to command line utility.  
It looks like there is a way to overcome this but I have not tried it.  
@see shell.vim - http://peterodding.com/code/vim/shell/


## Installation/System requirements 

Before vim-force.com plugin can be used the following requirements must be met:

1. Vim version 7.3 or later with `:set nocompatible`  

2. Java JDK/JRE, Version 6.1 or greater  
   - Oracle JDK
     http://www.oracle.com/technetwork/java/javase/downloads/index.html       
JDK is not strictly required, JRE will suffice.  
  
3. Tooling-force.com  
   [download jar from 'releases' page](https://github.com/neowit/tooling-force.com) 
   

4. On MS Windows Install shortname.vim  
    http://www.vim.org/scripts/script.php?script_id=433

5. Unpack force.com plugin archive anywhere you like  
	ex: ~/vim/force.com

6. Enable filetype plugin and syntax highlighting  
e.g. add these lines into .vimrc (or _vimrc on windows)<pre>
	set nocompatible
	filetype plugin on
	syntax on
</pre>

7. Add 'vim-force.com' folder to vim runtime path and make sure it loads apexcode filetype detection.  
  Important - this part must go after (not before) lines added on step 6.  
e.g.<pre>
    if has("unix")
		let &runtimepath=&runtimepath . ',~/vim/vim-force.com'
    elseif has("win32")
		let &runtimepath=&runtimepath . ',c:\Documents and Settings\username\vimfiles\vim-force.com'
    endif
    " make sure vim loads apexcode filetype detection
    runtime! ftdetect/vim-force.com.vim 
</pre>

8. Open Vim and index help file  
e.g.
    `:helptags ~/vim/force.com/doc`

    Or if using with pathogen.vim plugin and vim-force.com is in `.vim/bundle` run  
    `:Helptags`

9. Configure required variables: `:help force.com-settings`
10. Have a look at the config example: `:help force.com-config-example`
11. Read: `:help force.com-usage`  
    Important: if you are working with existing src/ project structure, make sure that you backup the original sources first and then issue command `:ApexRefreshProject`.


## RECOMMENDED-PLUGINS                             

There is a number of great Vim plugins which you may want to consider  
- Fugitive - git support  
- unite.vim - quick file/buffer open  
- NERDTree - project/file-system browsing  
- Pathogen - manage individually installed plugins in ~/.vim/bundle  
- Session - save/restore open files, like IDE Project  
- UltiSnip - implements some of TextMate's snippets features in Vim  
- TagBar - a source code browser plugin for Vim  


##CREDITS                                                     

Author: Andrey Gavrikov 

Credit must go out to Bram Moolenaar and all the Vim developers for
making the world's best editor (IMHO). I also want to thank everyone who
helped and gave me suggestions. I wouldn't want to leave anyone out so I
won't list names.

