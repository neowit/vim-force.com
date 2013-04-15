# Plugin for developing on force.com      

NOTE: this README file is outdated, once installed see relevant section of 
vim doc, e.g. `:help force.com`  
or read ./doc/force.com.txt directly.


salesforce.com / force.com plugin for Vim version 7.3 or later.  
Requires `:set nocompatible`


## DESCRIPTION                                             

force.com plugin is a bunch of .vim scripts that allow to develop on force.com 
platform using only web browser and Vim.

It is designed for those who do not feel productive in Force.com IDE for Eclipse.

General vim-force.com overview - http://www.youtube.com/watch?v=x5zKA6V__co  
`:ApexRetrieve` command demo - http://youtu.be/umO86ji2Iqw

Other vim plugins recommended for use alongside vim-force.com plugin  
* FuzzyFinder - http://www.youtube.com/watch?v=EtiaXVnTA4g  
* SnipMate - http://www.youtube.com/watch?v=Ri_DP1sRn2o  
* NERDTree - http://www.youtube.com/watch?v=d93o9qAqIhE  
* TagList - http://www.youtube.com/watch?v=Suk45FHU6s8  
* TagBar

## FEATURES

* Build/Save to SFDC
	- with error reporting
	- "Run test"
	<ul>
	* Execute unit tests in all modified files
	* Execute unit tests in a specific Class
	* Execute *specific* test method in a specific Class
	</ul>

* Deploy from one Org to Another

* Delete selected metadata from SFDC

* Persistent "Stage" for cherry-picking components to be deployed or deleted

* Load/update metadata from SFDC
	- Retrieve All or Selected components of given metadata type
	- Support for metadata types that reside inside folders (e.g. Document, Dashboard or Report) is limited because requires querying data (in addition to metadata) and SFDC Ant plugin does not support that.

* Create triggers/classes/pages

* Refresh current file from SFDC, Refresh whole project from SFDC, etc

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


## LIMITATIONS

vim force.com plugin does not support creating force.com project. Use provided
template instead.

ant-salesforce.jar library does not (in most cases) report error line numbers
in Visualforce pages making it impossible to go-to actual problem line if
compile/save fails due to syntax error. This is similar to Force.com IDE for
Eclipse.

Current version does not support environment aware code completion.  
For example if you write:  
	`String val = 'abc';`  
typing  
	`val.`  
will not bring the list of String methods as Force.com IDE may do.

"Execute Anonymous" and Unit Test code coverage report features are not implemented.
Use your favourite web browser and "Developer Console".

On MS Windows default configuration spawns separate DOS/CMD window on every call
to command line utility, ex: `ant deploy`.  
It looks like there is a way to overcome this but I have not tried it.  
@see shell.vim - http://peterodding.com/code/vim/shell/


## Installation/System requirements 

Before force.com plugin can be used the following requirements must be met:

1. Vim version 7.3 or later with `:set nocompatible`  
	There is a chance that it will work with 7.2 as well, but I have not tested.

2. Java JDK/JRE, Version 6.1 or greater  
   tested with OpenJDK and Oracle JDK
   - java version "1.6.0_18" OpenJDK Runtime Environment (IcedTea6 1.8.10)
   - Oracle JDK
     http://www.oracle.com/technetwork/java/javase/downloads/index.html       
JDK is not strictly required, JRE will suffice.  
With JRE Ant will complain about missing tools.jar but it is safe to ignore this warning.  
  
3. Apache ANT  
   Tested with [Apache Ant](http://ant.apache.org/) 
   - version 1.8.2 on Win XP SP3
   - version 1.8.0 on Linux
   - version 1.8.2 on OSX 10.8

4. Force.com Migration Tool  
    http://wiki.developerforce.com/page/Force.com_Migration_Tool  
	Tested with salesforce_ant_19.0

    Download it as described [here](http://www.salesforce.com/us/developer/docs/daas/index_Left.htm#StartTopic=Content/forcemigrationtool_install.htm).

    ant-salesforce.jar library must be made available to ANT, i.e. must reside in one of the folders of which ANT "knows" about.  
    The order in which jars are added to the classpath when ANT starts is as follows:  
    * -lib jars in the order specified by the -lib elements on the command line
    * jars from ${user.home}/.ant/lib (unless -nouserlib is set)
    * jars from ANT_HOME/lib  

    see http://ant.apache.org/manual/running.html#libs for more details  
    as well as  
    http://www.salesforce.com/us/developer/docs/apexcode/Content/apex_deploying_ant.htm

5. On MS Windows Install shortname.vim  
    http://www.vim.org/scripts/script.php?script_id=433

6. Unpack force.com plugin archive anywhere you like  
	ex: ~/vim/force.com

7. Add 'force.com' folder to vim runtime path and make sure it loads apexcode filetype detection  
e.g.<pre>
	if has("unix")
		let &runtimepath=&runtimepath . ',~/vim/force.com'
	elseif has("win32")
		let &runtimepath=&runtimepath . ',c:\Documents and Settings\username\vimfiles\force.com'
	endif
	" make sure vim loads apexcode filetype detection
	runtime ftdetect/vim-force.com.vim
</pre>

8. Enable filetype plugin and syntax highlighting  
e.g. add these lines into .vimrc (or _vimrc on windows)<pre>
	filetype plugin on
	syntax on
</pre>

8. Index help file  
e.g.
    `:helptags ~/vim/force.com/doc`

    Or if using with pathogen.vim plugin and vim-force.com is in .vim/bundle run  
    `:Helptags`


## RECOMMENDED-PLUGINS                             

There is a number of great Vim plugins which you may want to consider  
- Fugitive - git support  
- FuzzyFinder - quick file/buffer open  
- NERDTree - project/file-system browsing  
- Pathogen - manage individually installed plugins in ~/.vim/bundle  
- Session - save/restore open files like IDE Project  
- SnipMate - implements some of TextMate's snippets features in Vim  
- Taglist - a source code browser plugin for Vim  


##CREDITS                                                     

Author: Andrey Gavrikov 

Credit must go out to Bram Moolenaar and all the Vim developers for
making the world's best editor (IMHO). I also want to thank everyone who
helped and gave me suggestions. I wouldn't want to leave anyone out so I
won't list names.

