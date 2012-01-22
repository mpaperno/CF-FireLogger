ColdFire Installation Notes

1.   Welcome
2.   License and Credits
3.   Contributors
4.   Requirements
5.   Installation
5.1. Firefox, Firebug, & FireLogger
5.2. CF FireLogger
5.3. Optional Installations
7.   Usage
8.   Limitations
9.   Special Instructions for JBoss
10.   Update History


1. Welcome
-----------------------------------------------------------------------

Welcome to CF FireLogger, a ColdFusion debugger for the FireLogger 
Firebug extension meant to allow for nicer handling of debug information. 
For the latest releases and technical support, please go to the official 
CF FireLogger site:

http://cffirelogger.riaforge.org


2. License and Credits
-----------------------------------------------------------------------

Copyright 2012 Maxim paperno  http://www.WorldDesign.com/

Licensed under the Apache License, Version 2.0 (the "License"); you may
not use this file except in compliance with the License. You may obtain
a copy of the License at

http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or
implied. See the License for the specific language governing 
permissions and limitations under the License.


3. Contributors
-----------------------------------------------------------------------

CF FireLogger is based on the ColdFusion code used for the ColdFire
project ( http://coldfire.riaforge.org/ ) by Raymond Camden, Adam 
Podolnick, and Nathan Mische.  Thanks guys!

This document is also based on the one distributed with ColdFire.

Some credits from the original documentation:
-Thank you to Thomas Messier for the use of his JSON code.
-Thank you to Sean Corfield for writing the JBoss documentation.


4. Requirements
-----------------------------------------------------------------------

CF FireLogger works with Adobe ColdFusion version 9.  Older versions
are not supported at this time.

You will also need Firefox, Firebug, and FireLogger, as described in
the Installation section below.

5. Installation
-----------------------------------------------------------------------

5.1. Firefox, Firebug, and FireLogger

CF FireLogger provides output which is parsed by FireLogger which is an
extension to Firebug, which in itself is an extension for the Firefox 
browser. This means you must have the following items installed:
 - Firefox ( http://www.mozilla.org/firefox/ )
 - Firebug extension ( http://www.getfirebug.com/ )
 - FireLogger extension ( http://firelogger.binaryage.com/ )


5.2 CF FireLogger

To install the CF FireLogger extension, extract the .zip installation
package to a folder on your computer.

Next you need to find your ColdFusion web root directory. Typically
(on Windows) this will be C:\ColdFusion9\wwwroot. There should be a
folder in this directory called WEB-INF. Find the WEB-INF/debug folder
and copy the firelogger.cfm template located in the /debug folder of 
the installation package to this folder.

Go to your ColdFusion Administrator, enable debugging, and select
firelogger.cfm from the drop down. Ensure your IP is listed or that there
is no IP restriction in place.  You can control what information is
going to be logged to FireLogger using the options on the CF admin
page, just like you would for the built-in debugging templates.

Once you have done that you should then be able to view ColdFusion
debug information from within the Logger tab in the Firebug tool. 
Obviously you need to hit a ColdFusion page to see the debugging 
information.

5.3 Optional Installations and Files

While the firelogger.cfm debugging template provides most of the
functionality, there are certain enhancements which require
additional files.

-Enhanced Tracing-

NOTE: Enhanced tracing involves altering your ColdFuison installation.
Proceed with caution and be sure to backup all modified files!

Another optional feature of CF FireLogger is enhanced tracing.
This feature provides much richer detail in the debug output than CF's
built-in variable dump.  Specifically, you can drill down into any complex
object, like structures, queries, components, etc.  Basically you get the
same information as cfdump or cftrace inline="true" would provide.

To enable this feature you must install a custom trace.cfm tag. To install 
this tag, find the WEB-INF/cftags folder under your ColdFusion web root
folder. In this folder there should be a template named trace.cfm. Make
a backup of this file, then rename it to trace_adobe.cfm and copy the
trace.cfm tag, found in the /cftags folder of the installation package, 
to the cftags folder.

-Variable Output with Applications Using OnRequest()-

CF FireLogger provides a way to dump your "variables" scoped variables
in the output (see "Usage," below).

If your application uses the onRequest method of Application.cfc
then the "variables" scope is local to your application and cannot
be accessed by the firelogger.cfm debug template.  To get around this
you can extend the Application.cfc component provided with this project. 
Note that if your application uses onRequestEnd then you must call 
super.onRequestEnd() as part of your application's onRequestEnd 
method. The Application.cfc component is provided in the /appcfc
folder of the CF FireLogger installation package.

If you use this option, your local application variables will be copied
into the request scope, in a structure named "__cfc-variables-scope__"
So, for example, if you want to dump "variables.myVar" it will appear
in the output as "request.__cfc-variables-scope__.myVar".

-ColdSpring AOP- & -Railo-

Sorry, I don't use either of these technologies, so any support for them
will have to come from someone else.  Please feel free to contribute! :)



6. Usage
-----------------------------------------------------------------------
You must follow the following steps (in any order) to view CF FireLogger output:

 - Enable Firebug for the current site.
 - Switch to the Firebug Logger tab and make sure it is set to Enabled
 	(use the little arrow next to the tab title).
 - In your ColdFusion Administrator, under Debugging settings, enable
   debug output, select what info you would like to see (including which
   variable scopes to dump), and make sure "firelogger.cfm" is selected
   as the output template.
   
Now load your page and watch the output appear in the FireLogger console.
This may look a little confusing at first, but bear with it.  In the left
pane there is one line for each type of debug info, one for General, one
for Templates, one for Queries, and so on.  Click on the hyperlinked text
in one of the lines to get details in the right pane. In the right pane
is where you can view the results and drill down to find the information you
need.  Anything with a plus icon can be expanded for more details.

Note that if the Logger tab is not set to Enabled, then Firefox does not
send the appropriate headers and the debug template (firelogger.cfm) simply
exits without doing anything.  If you would like to fall back to using
another debug template in such cases (such as classic.cfm or dockable.cfm)
then edit firelogger.cfm and set the value of __firelogger__.fallbackTemplate
to the name of the desired template.

If you see a line in the left pane with a red background, this means 
CF FireLogger itself generated an error.  You can expand this line for a 
simple stack trace.  It would be useful to include this info when filing
any bug reports!  ;-)


Dumping other variables:

By default only the variable scopes set to display in CF Administrator
will be included in the output.  This does NOT include the "variables" scope.

You can tell CF FireLogger to include specific variables (or scopes) in 
the output by setting a special request variable to an array of values.  
For example, set this anywhere in your CF code:

<cfset request.firelogger_debug.varlist = 
				['variables.myVar','variables.myQuery']>
			
Or, to dump the whole "variables" scope:

<cfset request.firelogger_debug.varlist = ['variables']>

If you would like to limit the amount of information returned in the debug
variables output (and speed up the process as well), you could, for example, 
disable all the scopes in the CF Admin debug settings, and then specify 
what you want dumped using the request array.

Also check out the extraVarsToShow setting in the Settings section below. 


Optional password protection:

The FireLogger extension provides a way to specify a password which is
sent to the server to enable debug output.  By default no password is
required.  This may possibly expose sensitive information if used on a
site which is publicly-accessible (and if the debug info is enabled and
IP restrictions are not in place).  You can specify a password by editing
the firelogger.cfm file and setting the __firelogger__.password variable.

Using a password, one could theoretically leave debugging enabled on the
server w/out specifying an IP address and still have the information
relatively secure.  Could be useful for developing from dynamic IPs!


Settings:

These can be found at the top of debug/firelogger.cfm.

fallbackDebugHandler (default: classic.cfm) - As mentioned below, CF FireLogger 
	can't send HTTP headers after output has already been sent to the browser.
	This can happen for a number of reasons, including if there is an unhandled
	exception in your code.  Set the value of this variable to the debug template
	to use in such cases.  Set it to blank to disable any fallback handler.

fallbackTemplate (default: blank) - If Firebug/FireLogger is not enabled, you
	can specify a template to use instead. For example "classic.cfm" or
	"dockable.cfm".
	
extraVarsToShow (default: empty array) - An array of variable scopes/names to
	always include in the output, regardless of CF Admin settings.

password (default: blank) - as mentioned above, you can set this to enable
	password protection for your debug output.
	


7. Limitations
-----------------------------------------------------------------------

CF FireLogger makes use of CFHEADER to supply debug information to the
browser. Because of this there are certain places where CF FireLogger 
will not be able to work. First - if you use CFFLUSH anywhere on the page,
CF FireLogger is unable to add header information to the request. Secondly -
there are situations where certain tags will implicitly flush output.
One example is CFTIMER/type="inline". Any use of this tag and attribute
combination will result in CF FireLogger not returning any data. Thirdly -
you cannot add headers to remote cfc calls after the requested method 
is invoked (ie. in OnRequstEnd or the debugging template). This means
you cannot use CF FireLogger to debug AJAX requests bound to components.
(Note that requests which use a .cfm template to call a cfc will work just
fine.)

The variables dump can only output variables available in the
requested template. This means that variables local to components,
custom tags, or UDFs cannot be displayed.  If you would like to include
those in the dump, you could copy them into a shared scope like request. 
For example:
	request.my_UDF_Local_Vars.myVar = local.myVar;
Or simply:
	request.my_UDF_Local_Vars = local;

Dumping variables (especially whole scopes) can incur a significant 
performance penalty.  Unlike the built-in CF debug output options,
CF FireLogger will drill down and display complex object types, which
can take a significant amount of time in some cases.  If you find
your page requests taking a long time to process because of the debug output, 
you may want to limit what is being dumped by using the CF Admin options 
and/or the request.firelogger_debug.varlist as described in "Usage."

Similarly, keep in mind that the communication with FireLogger happens
via HTTP headers by passing Base64-encoded JSON strings.  Depending on
how much you're dumping, this could get very large.  It takes time to
build the headers, transmit/receive them, and then parse them on the 
client.  So, the more you have, the slower things will get.

The total debug time is available as an HTTP header which you can examine
in Firebug's Net panel (FireLogger-debug-time).  This includes parsing
the data and building the headers.  There is also a debug time available
in the General Info view-- this is just the time it took to parse the data.

As noted in the previous section, dumping any "variables" scoped variables
will not work for applications using the onRequest method of Application.cfc 
unless the Application.cfc extends the CF FireLogger Application 
component. 


8. Special Instructions for JBoss
-----------------------------------------------------------------------

JBoss has a default maximum HTTP header size of 4Kb in total. You can
modify it by editing the following file:

{jbossdir}/server/{servername}/deploy/jbossweb-tomcat55.sar/server.xml

You need to add (or modify) the maxHttpHeaderSize to allow larger
packets. Here's the top portion of a modified server.xml file (set to
allow 64Kb total headers so it still won't allow giant swathes of
execution time reports but it should cover most cases).

<Server>

<!-- 
	Use a custom version of StandardService that allows the connectors
	to be started independent of the normal lifecycle start to allow
	web apps to be deployed before starting the connectors. 
--> 

<Service
	name="jboss.web" 
	className="org.jboss.web.tomcat.tc5.StandardService">

<!-- A HTTP/1.1 Connector on port 8080 --> 
<Connector 
	port="8080"
	address="${jboss.bind.address}" 
	maxThreads="250" 
	strategy="ms"
	maxHttpHeaderSize="65536" 
	emptySessionPath="true" 
	enableLookups="false"
	redirectPort="8443" 
	acceptCount="100" 
	connectionTimeout="20000"
	disableUploadTimeout="true" />


9. Update History
-----------------------------------------------------------------------

------------------------------ LAST UPDATE ----------------------------- 

v 1.0b4 - Further improved component dump. Added fallbackDebugHandler option for when headers can't be sent. 
			Bumped FireLogger extension recommended version to 1.2 (fixes minor issue with headers still being set when FL is disabled). 
			Better formatting of template/cfc name and trace info. Minor fixes. Updated readme. (14-Jan-12)

v 1.0b3 - Bugfix (id:1): Error formatting CFCs: The element at position 1 cannot be found.  Added extraVarsToShow config parameter. 
			Updated readme. Improved internal error handling. (1/13/12)

v 1.0b2 - Updated java class and CF component dumps.  Now has a nice display of component property values, if available. (1/12/2012)

Initial release: Jan. 11, 2012 (v 1.0b1) 
