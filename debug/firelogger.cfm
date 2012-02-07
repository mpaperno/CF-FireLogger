<!---
	Name:				firelogger.cfm
	Author:			Maxim Paperno
	Created:			Jan. 2012
	Last Updated:	07-Feb-2012
	Version:			2.0.1
	History:			Fixed bug preventing display of queries.  Added variables for logger settings. (07-Feb-12);
						Rewrite to make use of new firelogger.cfc component to do the actual output to the console. (23-Jan-12)
						Further improved component dump. Added fallbackDebugHandler option for when headers can't be sent. Bumped FireLogger extension recommended version to 1.2. Minor fixes. (14-Jan-12)
						Bugfix (id:1): Error formatting CFCs: The element at position 1 cannot be found.  Added extraVarsToShow config parameter. Improved internal error handling. (1/13/12))
						Updated java class and CF component dumps.  Now has a nice display of component property values, if available. (1/12/2012)
						Initial version based on coldfire.cfm (9/21/2007) by Nathan Mische & Raymond Camden (1/11/2012)

Handles server side debugging for FireLogger
--->
<cfscript>

__firelogger__ = StructNew();
		
/*  If you wish to execute a different template in case FireLogger is not enabled, specify the name here.
	For example "classic.cfm" or "dockable.cfm"  */
__firelogger__.fallbackTemplate = "";

/*  Template to use in case firelogger can't send output via headers, for example after output has been flushed
	like in the case of an unhandled exception.	For example "classic.cfm" or "dockable.cfm"  */
__firelogger__.fallbackDebugHandler = "classic.cfm";

/*  To enable FireLogger password security (you can set a password in FireLogger preferences) 
		specify your password here  */
__firelogger__.password = "";

/*  Insanity check: only process up to this many records per debug type (template, cfc, query, trace, exceptions, stored procs).
		Trying to dump huge record sets (like calling a cfc method 100s of times) can bring a server to its knees.  */
__firelogger__.maxLogEntriesPerType = 300;

/*  Specify additional variables, or scopes, to always dump in the output.
		for example:
		
		__firelogger__.extraVarsToShow = ['variables','attributes'];
		
		Note that you can also use request.firelogger_debug.varlist array to specify variables to dump from
		within your CFML at runtime. See readme.txt#Usage for details.
  */
__firelogger__.extraVarsToShow = [];

/*  
	Set filterSelf to true to filter out all calls to firelogger.cfm/cfc from the templates and cfcs reports
 */
__firelogger__.filterSelf = true;
__firelogger__.selfName = "firelogger";

/*  
	debugMode=true will cfdump our output to the current page
	dumpOnError=true will cfdump any unhandled exception within firelogger.cfm and/or firelogger.cfc to the current page
 */
__firelogger__.debugMode = false;
__firelogger__.dumpOnError = true;

/*
	FireLogger.cfc settings

	loggerLabel=name for logger "badge"; leave blank for default;
	loggerColor=color value for logger "badge" (eg: "red" or "##FAFAFA"); leave blank for default;
	debugCFC=true will enable debugging in firelogger.cfc
	cfcDebugLevel=debug level for cfc; one of: info, error, panic;
 */
__firelogger__.loggerLabel = "CF DBG";
__firelogger__.loggerColor = "";
__firelogger__.debugCFC = false;
__firelogger__.cfcDebugLevel = "info";

/* Check that FireLogger is enabled */
if ( IsDebugMode() and StructKeyExists(GetHttpRequestData().headers,"X-FireLoggerProfiler") ) {
	try {
		
		// get a new firelogger object instance. the try/catch will handle things if it doesn't exist
		__firelogger__.console = new us.wdg.cf.firelogger(fallbackLogMethod="none",
											valuesAlreadySerialized=true,
											filename=CGI.CF_TEMPLATE_PATH,
											lineno="?",
											debugMode=__firelogger__.debugCFC,
											debugTraceInline=__firelogger__.dumpOnError,
											debugLevel=__firelogger__.cfcDebugLevel
										);
		
		if ( Len(__firelogger__.password) ) {
			__firelogger__.console.setPassword(__firelogger__.password); }
		if ( Len(__firelogger__.loggerLabel) ) {
			__firelogger__.console.setLoggerName(__firelogger__.loggerLabel); }
		if ( Len(__firelogger__.loggerColor) ) {
			__firelogger__.console.setLoggerBGColor(__firelogger__.loggerColor); }
	
		if ( __firelogger__.console.getIsConsoleEnabled() ) {
		
			/*  this keeps track of the template output count (needs to be "global" instead of local to the UDF)  */
			__firelogger__.treeidx = 1;
		
			/*  Do the work! */
			firelogger_udf_main(debugMode=__firelogger__.debugMode, dumpOnError=__firelogger__.dumpOnError);
	
		} else { // console not enabled -- fire fallback
			firelogger_udf_handleFallback();
		}
	}
	catch (any e) {
		if ( __firelogger__.dumpOnError ) {
			writedump(e);
		} else {
			firelogger_udf_handleFallback();
		}
	}
	
/* Not debug mode or FireLogger disabled -- Fall back to another template if specified  */
} else {
	firelogger_udf_handleFallback();
}

/**
 * Handle fallback based on type and configured handler templates
 *
 * @type: disabled = handle case where FireLogger is disabled; 
 *			 flushed = handle case where output headers are already sent (output has been "flushed")
 */
function firelogger_udf_handleFallback(type="disabled") {
	if ( arguments.type IS "disabled" AND Len(__firelogger__.fallbackTemplate) ) {
		include __firelogger__.fallbackTemplate;
	} else if ( arguments.type IS "flushed" AND Len(__firelogger__.fallbackDebugHandler) ) {
		include __firelogger__.fallbackDebugHandler;
	}
}

</cfscript>

<cffunction 
	name="firelogger_udf_main" 
	returntype="void" 
	output="true"
	hint="Build debug output and send it to FireLogger console.">
		
	<cfargument name="debugMode" type="boolean" required="false" default="false">
	<cfargument name="dumpOnError" type="boolean" required="false" default="false">
	
	<cfset var debugTimer = getTickCount()>
	<cfset var result = StructNew()>
	<cfset var varJSON = "">
	
	<cftry>
		<!--- Gets the debug data. --->

		<cfset var factory = CreateObject("java","coldfusion.server.ServiceFactory")>
		<cfset var cfdebugger = factory.getDebuggingService()>
		<cfset var qEvents = cfdebugger.getDebugger().getData()>
		    
		<cfset var requestData = GetHttpRequestData()>
		<cfset var response = getPageContext().getResponse()>

		<!--- check to see if output has already been flushed (can't set headers after this) --->
		<cfif response.isCommitted()>
			<cfset firelogger_udf_handleFallback("flushed")>
			<cfreturn>
		</cfif>

		<cfcatch type="Any" >
			<!--- we have no debugger... exit --->
			<cfreturn>
		</cfcatch>
	</cftry>

	<cftry>

		<cfset var varArray = ArrayNew(1)>
	
		<!--- decide which vars to dump based on cfadmin settings --->
		<cfif cfdebugger.check("Variables")>
		
			<cfif IsDefined("form") AND cfdebugger.check("ServerVar")>
				<cfset varArray[ArrayLen(varArray) + 1] = "server">
			</cfif>
			<cfif IsDefined("form") AND cfdebugger.check("CGIVar")>
				<cfset varArray[ArrayLen(varArray) + 1] = "cgi">
			</cfif>
			<cfif IsDefined("form") AND cfdebugger.check("FormVar")>
				<cfset varArray[ArrayLen(varArray) + 1] = "form">
			</cfif>
			<cfif IsDefined("url") AND cfdebugger.check("URLVar")>
				<cfset varArray[ArrayLen(varArray) + 1] = "url">
			</cfif>
			<cfif IsDefined("cookie") AND cfdebugger.check("CookieVar")>
				<cfset varArray[ArrayLen(varArray) + 1] = "cookie">
			</cfif>
			<cfif IsDefined("request") AND cfdebugger.check("RequestVar")>
				<cfset varArray[ArrayLen(varArray) + 1] = "request">
			</cfif>
			<cfif IsDefined("application") AND cfdebugger.check("ApplicationVar")>
				<cfset varArray[ArrayLen(varArray) + 1] = "application">
			</cfif>
			<cfif IsDefined("session") AND cfdebugger.check("SessionVar")>
				<cfset varArray[ArrayLen(varArray) + 1] = "session">
			</cfif>
			<cfif IsDefined("client") AND cfdebugger.check("ClientVar")>
				<cfset varArray[ArrayLen(varArray) + 1] = "client">
			</cfif>
			
			<!--- look in request scope for other vars to dump (eg. request.firelogger_debug.varlist = ['variables.foo','variables.bar','attributes'] ) --->
			<cfif StructKeyExists(request, "firelogger_debug") AND StructKeyExists(request.firelogger_debug, "varlist") AND IsArray(request.firelogger_debug.varlist)>
				<cfset varArray.addAll(request.firelogger_debug.varlist)>
			</cfif>
			
			<!--- add any variables specified in settings --->
			<cfif ArrayLen(__firelogger__.extraVarsToShow)>
				<cfset varArray.addAll(__firelogger__.extraVarsToShow)>
			</cfif>
		
			<!--- remove dupes from vars array --->
			<cfset varArray = createObject("java", "java.util.HashSet").init(varArray).toArray()>
		</cfif>

		<!--- safe (and maybe quicker) to encode some results using serializeJSON() --->
		<cfset result.templates = serializeJSON(firelogger_udf_getFiles(qEvents, __firelogger__.maxLogEntriesPerType, cfdebugger.settings.template_mode))>
		<cfset result.cfcs = serializeJSON(firelogger_udf_getCFCs(qEvents, __firelogger__.maxLogEntriesPerType))>
		<cfset result.exceptions = serializeJSON(firelogger_udf_getExceptions(qEvents, __firelogger__.maxLogEntriesPerType))>
		<cfset result.timer = serializeJSON(firelogger_udf_getTimer(qEvents))>
		
		<!--- if the results will have queries (including nested in other data), use __firelogger__.console.encodeJSON() --->
		<cfset result.queries = __firelogger__.console.encodeJSON(firelogger_udf_getQueries(qEvents, "SqlQuery", __firelogger__.maxLogEntriesPerType))>
		<cfset result.storedprocs = __firelogger__.console.encodeJSON(firelogger_udf_getQueries(qEvents, "StoredProcedure", __firelogger__.maxLogEntriesPerType))>
		<cfset result.trace = __firelogger__.console.encodeJSON(firelogger_udf_getTrace(qEvents, __firelogger__.maxLogEntriesPerType))>
		<cfset result.variables = firelogger_udf_getVariables(varArray)>
		<!--- save this for last to get more accurate debug render time in general vars dump --->
		<cfif isDefined("cfdebugger.settings.general") and cfdebugger.settings.general>
			<cfset result.general = serializeJSON(firelogger_udf_getGeneral(qEvents, local.debugTimer))>
		</cfif>

		<cfscript>
	   	var keylist = ['general','templates','cfcs','exceptions','queries', 'storedprocs','trace','timer','variables'];
	   	var exitcode = 0;
	   	var skey = "";
	   	
	   	for (var x=1; x <= ArrayLen(keylist); x=x+1) {
		   	skey = UCase(keylist[x]);
	   		if ( StructKeyExists(result, skey) AND result[skey] != '""' ) {
	   			
	   			exitcode = __firelogger__.console.log( IIf( skey IS "exceptions", DE("error"), DE("info") ), "CF #skey#", result[skey] );
	   			
	   			if ( !exitcode ) {
	   				firelogger_udf_error("console.log returned error exit code while trying to log CF #skey#");
	   			}
	   			
				}
			}
			
			// send header with total time taken since we started this file
			response.setHeader("CF-FireLogger-Debug-Time", "#Evaluate(getTickCount() - local.debugTimer)# ms.");
			
			if ( arguments.debugMode ) {
				//writedump(result);
				writedump(qEvents);
			}

		</cfscript>
	
		<cfcatch>
			<!--- make sure we don't throw an error --->
	  		<cfif arguments.dumpOnError>
	  			<cfdump var="#cfcatch#">
	  		<cfelse>
				<cfset firelogger_udf_handleFallback()>
	  		</cfif>
		</cfcatch>
	
	</cftry>

</cffunction>


<cffunction 
	name="firelogger_udf_error" 
	returntype="void" 
	output="false"
	hint="Calls firelogger object's error handler to log a special debug message to the console.">
	
	<cfargument name="msg" type="string" required="true">
	<cfargument name="e" type="any" required="false" default=""> <!--- cfcatch object --->
	
	<cftry>
		<cfset __firelogger__.console.err(arguments.msg, arguments.e)>
		
		<cfcatch type="Any" ><!--- ignore errors ---></cfcatch>
	</cftry>

</cffunction>


<cffunction 
	name="firelogger_udf_getGeneral"
	returntype="any"
	output="false"
	hint="Gets General info">
	
	<cfargument name="data" type="query" required="true">
	<cfargument name="dtime" type="numeric" required="false" default="0">
	
	<cftry>
		<cfset var resultStruct = StructNew()>
		<cfset var myapp = "">
		<cfset var totaltime = 0>
		<cfset var cfdebug_execution = "">
		
		<cfif isDefined("application.applicationname")>
			<cfset myapp = application.applicationName>
		</cfif>
			
		<!--- Taken from classic.cfm --->
		<!--- Total Execution Time of all top level pages --->
		<cfquery dbType="query" name="cfdebug_execution" debug="false">
		   	select (endTime - startTime) AS executionTime
		   	from data
		   	where type = 'ExecutionTime'
		</cfquery>
		
		<cfif cfdebug_execution.recordcount>
			<cfset totaltime = cfdebug_execution.executiontime>
		<cfelse>
			<cfset totaltime = -1>
		</cfif>		
		
		<cfset resultStruct["ColdFusionServer"] = "#server.coldfusion.productname# #server.coldfusion.productlevel# #server.coldfusion.productversion#">
	   <cfset resultStruct["Template"] = IIf(IsDefined("cgi.CF_TEMPLATE_PATH"), "cgi.CF_TEMPLATE_PATH", DE("unknown") )>
	   <cfset resultStruct["Locale"] = getLocale()>
	   <cfset resultStruct["User Agent"] = IIf(IsDefined("cgi.http_user_agent"), "cgi.http_user_agent", DE("unknown") )>
	   <cfset resultStruct["Remote IP"] = IIf(IsDefined("cgi.remote_addr"), "cgi.remote_addr", DE("unknown") )>
	   <cfset resultStruct["Script Path"] = IIf(IsDefined("cgi.script_name"), "cgi.script_name", DE("") ) & IIf(IsDefined("cgi.path_info") AND cgi.path_info IS NOT cgi.script_name, "cgi.path_info", DE("") )>
	   <cfset resultStruct["Application"] = local.myapp>
	   <cfset resultStruct["Total Exec. Time"] = local.totaltime & " ms.">
	   <cfset resultStruct["Timestamp"] = dateFormat(now(), "short") & " " & timeFormat(now(), "HH:mm:ss.LLL")>
	   <cfset resultStruct["Debug Time (partial)"] = getTickCount() - arguments.dtime & " ms.  (data parsing time only--does not include building/sending the headers)"> <!--- [[firelogger_debugtimer]] --->
	
		<cfreturn resultStruct>
	
		<cfcatch type="Any" >
		   <cfset firelogger_udf_error("Error formatting General variables", cfcatch)>
			<cfreturn "error occured while trying to output this value" />
		</cfcatch>
		
	</cftry>
</cffunction>


<cffunction 
	name="firelogger_udf_getFiles"
	returntype="any" 
	output="true" 
	hint="Gets files from the debugging info. Used by two other UDFs to get file based info.">
	
	<cfargument name="data" type="query" required="true">
	<cfargument name="maxLogEntries" type="numeric" required="false" default="100">
	<cfargument name="format" type="string" required="false" default="tree">

	<cftry>
		<cfset var st = structNew()>
		<cfset var resultStruct = StructNew()>
		<cfset var cfdebug_execution = "">
		<cfset var cfdebug_top_level_execution_sum = "">
		<cfset var time_other = -1>
		<cfset var topNodes = "">
		<cfset var childidList = "">
		<cfset var parentidList = "">
		<cfset var tmp = "">
		<cfset var raw_trace = "">
		<cfset var findFunctionPrefix = "">
		<cfset var findFunction = "">
		<cfset var stkeyname = "">
		<cfset var qTree = queryNew("template,templateId,parentId,duration,line,timestamp")>
		<cfset var stTree = structNew()>
		<cfset var startToken = "CFC[ ">
		<cfset var endToken = "("> <!---could be "|"--->
		<cfset var a = "">
		<cfset var count = "">
		<cfset var thisTemplate = "">
	
		<!--- this code is taken from classic.cfm debugger template --->
	
		<!--- Total Execution Time of all top level pages --->
		<cfquery dbtype="query" name="cfdebug_execution" debug="false">
			SELECT (endTime - startTime) AS executionTime
			FROM data
			WHERE type = 'ExecutionTime'
		</cfquery>
		<!--- ::
		    in the case that no execution time is recorded. 
		    we will add a value of -1 so we know that a problem exists but the template continues to run properly.    
		    :: --->
		<cfif not cfdebug_execution.recordCount>
			<cfscript>
				queryAddRow(cfdebug_execution);
				querySetCell(cfdebug_execution, "executionTime", "-1");
			</cfscript>
		</cfif>
	
		<cfquery dbtype="query" name="cfdebug_top_level_execution_sum" debug="false">
			SELECT sum(endTime - startTime) AS executionTime
		  	FROM data
	  		WHERE type = 'Template' AND parent = ''
		</cfquery>
	
		<!--- File not found will not produce any records when looking for top level pages --->
		<cfif NOT Val(cfdebug_top_level_execution_sum.executionTime[1])>
			<cfreturn "">
		</cfif>
	
		<cfset time_other = Max(cfdebug_execution.executionTime - val(cfdebug_top_level_execution_sum.executionTime), 0)>
	  
		<cfquery dbtype="query" name="count" debug="false">
			SELECT Count(Type) As ttl
			FROM data
			WHERE type = 'Template'
				<cfif __firelogger__.filterSelf>
					AND Template NOT LIKE '%#__firelogger__.selfName#.cf[mc]'
				</cfif>
		</cfquery>
		
		<cfif NOT Val(count.ttl)>
	   	<cfreturn "">
	   </cfif>

		<cfquery dbtype="query" name="a" debug="false" maxrows="#arguments.maxLogEntries#">
			SELECT *
			FROM data
			WHERE type = 'Template'
				<cfif __firelogger__.filterSelf>
					AND Template NOT LIKE '%#__firelogger__.selfName#.cf[mc]'
				</cfif>
		</cfquery>
		
		<cfif count.ttl GT arguments.maxLogEntries>
			<cfset firelogger_udf_error("CF-Firelogger Debug Warning: #count.ttl# Templates were found. Only showing the first #arguments.maxLogEntries#.")>
			<cfset arguments.format = "flat">
		</cfif>
		
		<!--- The tree view isn't a very complete representation of the actually loaded files.  CF doesn't seem to log the complete heirarchy properly.
			TODO: Figure out a better way to display the tree... if possible. --->
		<cfif arguments.format IS "tree">
			
			<cfscript>
			for (var i = 1; i <= a.recordcount; i=i+1) {
				childidList = "";
				parentidList = "";
				for (var x=arrayLen(a.stacktrace[i].tagcontext); x > 0 ; x=x-1) {
					if(a.stacktrace[i].tagcontext[x].id NEQ "CF_INDEX") {
						// keep appending the line number from the template stack to form a unique id
						childIdList = listAppend(childIdList, a.stacktrace[i].tagcontext[x].line);
						if(x eq 1) {
							//parentIdList = listAppend(parentIdList, a[i].stacktrace.tagcontext[x].template);
							raw_trace = a.stacktrace[i].tagcontext[x].raw_trace;
							findFunctionPrefix = "$func";// set prefix to account for length and position since CF doesn't have RegEx lookbehind assertion
							findFunction = ReFindNoCase("(?=\" & findFunctionPrefix & ").*(?=\.runFunction\()", raw_trace, 1, true);
							if(findFunction.len[1] NEQ 0 AND findFunction.pos[1] NEQ 0) {
								// get function name from raw_trace to allow for proper application.cfc tree rendering
								tmp = Trim(Mid(raw_trace, findFunction.pos[1] + Len(findFunctionPrefix), findFunction.len[1] - Len(findFunctionPrefix)));
								// append the function name (pulled from raw_trace) to the cfc template for tree root comparison.
								parentIdList = listAppend(parentIdList, a.stacktrace[i].tagcontext[x].template & " | " & lcase(tmp));
							} else {
								parentIdList = listAppend(parentIdList, a.stacktrace[i].tagcontext[x].template);
							}
						} else {
							parentIdList = listAppend(parentIdList, a.stacktrace[i].tagcontext[x].line);
						}
					}
				}
			
				// template is the last part of the unique id...12,5,17,c:\wwwroot\foo.cfm
				// if we don't remove the "CFC[" prefix, then the parentId and childId relationship
				// will be all wrong
				thisTemplate = a.template[i];
				if ( FindNoCase(startToken, thisTemplate, 1) ) {
					thisTemplate = trim(listFirst(thisTemplate, endToken));
					thisTemplate = replaceNoCase(thisTemplate, startToken, "");
				}
				childIdList = listAppend(childIdList, thisTemplate);
			
				queryAddRow(qTree);
				querySetCell(qTree, "template", thisTemplate);
				querySetCell(qTree, "templateId", childIdList);
				querySetCell(qTree, "parentId", parentIdList);
				querySetCell(qTree, "duration", a.endtime[i] - a.starttime[i]);
				querySetCell(qTree, "line", a.line[i]);
				querySetCell(qTree, "timestamp", a.timestamp[i]);
				
			}
			</cfscript>
		
			<cfloop query="qTree">
				<cfscript>
					stTree[parentId] = structNew();
					stTree[parentId].templateId = qTree.templateId;
					stTree[parentId].template = qTree.template;
					stTree[parentId].duration = qTree.duration;
					stTree[parentId].line = qTree.line;
					stTree[parentId].timestamp = qTree.timestamp;
					stTree[parentId].children = arrayNew(1);
				</cfscript>
			</cfloop>
			
			<cfloop query="qTree">
				<cfscript>
					stTree[templateId] = structNew();
					stTree[templateId].templateId = qTree.templateId;
					stTree[templateId].template = qTree.template;
					stTree[templateId].duration = qTree.duration;
					stTree[templateId].line = qTree.line;
					stTree[templateId].timestamp = qTree.timestamp;
					stTree[templateId].children = arrayNew(1);
				</cfscript>
			</cfloop>
			
			<cfloop query="qTree">
				<cfscript>
					arrayAppend(stTree[parentId].children, stTree[templateId]);
				</cfscript>
			</cfloop>
			
			<cfquery dbtype="query" name="topNodes" debug="false">
				SELECT *
				FROM qTree
				WHERE parentId = ''
			</cfquery>
		
			<cfloop query="topNodes">
				<cfset stkeyname = firelogger_udf_fileFormatKeyname(topNodes.template, topNodes.line, topNodes.duration, 
																						variables.__firelogger__.treeidx, true, 
																						TimeFormat(topNodes.timestamp, "mm:ss.LLL"), 8, " @", Len(count.ttl))>
				<cfset resultStruct[stkeyname] = firelogger_udf_drawTree(stTree, topNodes.templateid, count.ttl)>
			</cfloop>
			
		<cfelseif arguments.format IS "flat">
			
				
			<cfloop query="a">
				<cfscript>
					thisTemplate = a.template;
					if ( FindNoCase(startToken, thisTemplate, 1) ) {
						thisTemplate = trim(listFirst(thisTemplate, endToken));
						thisTemplate = replaceNoCase(thisTemplate, startToken, "");
					}
					stkeyname = firelogger_udf_fileFormatKeyname(thisTemplate, a.line, a.endtime - a.starttime, a.currentRow, true, TimeFormat(a.timestamp, "mm:ss.LLL"), 8, " @", Len(count.ttl));
					resultStruct[stkeyname] = "";
				</cfscript>
			</cfloop>
			
		<cfelseif arguments.format IS "summary">
			
			<cfquery dbType="query" name="a" debug="false">
				SELECT  template, Sum(endTime - startTime) AS totalExecutionTime, count(template) AS instances
				FROM a
				group by template
				order by totalExecutionTime DESC
			</cfquery>

      	<cfloop query="a">
				<cfscript>
					thisTemplate = a.template;
					if ( FindNoCase(startToken, thisTemplate, 1) ) {
						thisTemplate = trim(listFirst(thisTemplate, endToken));
						thisTemplate = replaceNoCase(thisTemplate, startToken, "");
					}
					stkeyname = firelogger_udf_fileFormatKeyname(thisTemplate, "", a.totalExecutionTime, a.currentRow, true, "", 8, "", Len(a.recordcount));
					tmp = a.instances & " instance";
					if ( Val(a.instances) GT 1 ) {
						tmp = tmp & "s; Avg. exec. time: " & Round(a.totalExecutionTime / a.instances) & "ms";
					}
					resultStruct[stkeyname] = tmp;
				</cfscript>
      	</cfloop>

		</cfif>
		
	  	<cfset resultStruct.totals = "(#time_other# ms) STARTUP, PARSING, COMPILING, LOADING, & SHUTDOWN;
(#cfdebug_execution.executionTime# ms) TOTAL EXECUTION TIME">
	
		<cfreturn resultStruct>
	
		<cfcatch type="Any" >
		   <cfset firelogger_udf_error("Error formatting Templates", cfcatch)>
			<cfreturn "error occured while trying to output this value" />
		</cfcatch>
		
	</cftry>
</cffunction>	

<!--- template output utility functions --->
<cfscript>
	function firelogger_udf_fileFormatKeyname(template, line=0, duration="", idx=0, useidxprefix=false, timestamp="", pathdepth=5, linedelim=":", idxpfxlen=3) {
		var response = Replace(arguments.template, "\", "/", "all");
		while ( ListLen(response, "/") GT arguments.pathdepth ) { // limit paths to a depth of 5 for output sanity
			response = ListRest(response, "/");
		}
		if ( ListLen(arguments.template, "/\") GT arguments.pathdepth ) {
			response = ".../" & response;
		}
		if ( arguments.line > 0 ) {
			response = response & arguments.linedelim & arguments.line; }
		if ( Len(arguments.duration) ) {
			response = response & " (" & arguments.duration & "ms)"; }
		if ( arguments.useidxprefix ) {
			// output is automatically sorted alphabetically in FireLogger so this "overrides" it
			response = NumberFormat(arguments.idx, RepeatString("0", arguments.idxpfxlen)) & "- " & IIf( Len(arguments.timestamp), DE(arguments.timestamp & " "), DE("")) & response; 
		}
		return response;
	}
	
	function firelogger_udf_drawTree(tree, id, total) {
		var childName = "";
		var response = "";
		__firelogger__.treeidx = variables.__firelogger__.treeidx + 1;
		
		if( StructKeyExists(arguments.tree, arguments.id) AND IsArray(arguments.tree[arguments.id].children) and ArrayLen(arguments.tree[arguments.id].children) ) {
			response = StructNew();
			for(var i = 1; i lte arrayLen(arguments.tree[arguments.id].children); i = i + 1) {
				childName = firelogger_udf_fileFormatKeyname(arguments.tree[arguments.id].children[i].template, 
																						arguments.tree[arguments.id].children[i].line, 
																						arguments.tree[arguments.id].children[i].duration, 
																						variables.__firelogger__.treeidx, 
																						true, 
																						TimeFormat(arguments.tree[arguments.id].children[i].timestamp, "mm:ss.LLL"), 
																						8, " @", Len(arguments.total));
				response[childName] = firelogger_udf_drawTree(arguments.tree, arguments.tree[arguments.id].children[i].templateid, arguments.total);
			}
		}
		return response;
	}
</cfscript>

<cffunction 
	name="firelogger_udf_getCFCs"
	returntype="any"
	output="false" 
	hint="Gets CFC from the debugging info">
		
	<cfargument name="data" type="query" required="true">
	<cfargument name="maxLogEntries" type="numeric" required="false" default="100">

	<cftry>
		<cfset var q = "">
		<!---<cfset var result = queryNew("cfc,method,et,timestamp,template,starttime")>--->
		<cfset var resultStruct = StructNew()>
		<cfset var cfc = "">
		<cfset var method = "">
		<!---<cfset var realtemplate = "">--->
		<!---<cfset var template_copy = "">--->
		<cfset var realmethod = "">
		<cfset var realbody = "">
		<cfset var calledby = "">
		<cfset var count = "">
		
		<cfset var sql = "from data
								where type = 'Template'
									and template like 'CFC[[ %'
										escape '['
		">
		<cfif __firelogger__.filterSelf>
			<cfset sql = local.sql & " AND Template NOT LIKE '%#__firelogger__.selfName#.cf[mc]'">
		</cfif>
		
		<cfquery dbType="query" name="count" debug="false">
			select Count(type) AS ttl
			#preserveSingleQuotes(local.sql)#
		</cfquery>
	
		<cfif NOT Val(count.ttl)>
	   	<cfreturn "">
	   </cfif>

		<cfquery dbType="query" name="q" debug="false" maxrows="#arguments.maxLogEntries#">
			select template, (endTime - startTime) as et, startTime, 
									endTime, [timestamp], stacktrace
			#preserveSingleQuotes(local.sql)#
		</cfquery>
	
		<cfif count.ttl GT arguments.maxLogEntries>
			<cfset firelogger_udf_error("CF-Firelogger Debug Warning: #count.ttl# CFCs were found. Only showing the first #arguments.maxLogEntries#.")>
		</cfif>
		
		<cfloop query="q">
			<!--- A CFC template looks like so:
				   CFC[ C:\web\testingzone\Application.cfc | onRequestStart(/testingzone/test.cfm) ] from C:\web\testingzone\Application.cfc
				It contains the CFC, the method signature, and the template 
			--->
	
			<cfset method = ReReplace(q.template, "(CFC\[ .+? \| )((.*)\(.*\)) ].*", "\2")>
			<cfset method = Trim(method)>
			
			<!--- Our methods can be REALLY freaking huge, like in MG. Let's do a sanity check. --->
			<cfif find("(", local.method)>
				<cfset realmethod = left(local.method, find("(", local.method)-1)>
				<cfset realbody = replace(local.method, local.realmethod & "(", "")>
				<cfif len(local.realbody) gt 1>
					<cfset realbody = left(local.realbody, len(local.realbody) - 1)>
					<!---<cfset realbody = htmlEditFormat(realbody)>--->
					<cfif len(local.realbody) gt 250>
						<cfset realbody = left(local.realbody, 250) & " ...">
						<cfset method = local.realmethod & "(" & local.realbody & ")">
					</cfif>
				</cfif>
			</cfif>
	
			<cfset calledby = "">
			<cfif StructKeyExists(q.stacktrace, "tagcontext") AND IsArray(q.stacktrace[q.currentRow].tagcontext) AND ArrayLen(q.stacktrace[q.currentRow].tagcontext)>
				<cfset calledby = q.stacktrace[q.currentRow].tagcontext[1].template & ":" & q.stacktrace[q.currentRow].tagcontext[1].line>				
			</cfif>
	
			<cfset cfc = trim(listFirst(template,"("))>
			<cfset cfc = replaceNoCase(cfc, "CFC[ ", "")>
			<cfset cfc = firelogger_udf_fileFormatKeyname(cfc, 0, q.et, q.currentRow, true, TimeFormat(q.timestamp, "mm:ss.LLL"), 5, ":", Len(q.recordcount))>
			
			<cfset resultStruct[cfc] = StructNew()>
			<cfset resultStruct[cfc].meta = "Timestamp: " & TimeFormat(q.timestamp, "HH:mm:ss.LLL") & Chr(13) & Chr(10) &
													"Start Time: " & q.starttime & Chr(13) & Chr(10) &
													"End Time: " & q.endTime>
			<cfset resultStruct[cfc].method = local.method>
			<cfset resultStruct[cfc].calledby = local.calledby>
	
		</cfloop>
		
		<cfreturn resultStruct>
	
		<cfcatch type="Any" >
		   <cfset firelogger_udf_error("Error formatting CFCs", cfcatch)>
			<cfreturn "error occured while trying to output this value" />
		</cfcatch>
		
	</cftry>

</cffunction>

<cffunction 
	name="firelogger_udf_getExceptions"
	returntype="any"
	output="false" 
	hint="Gets exceptions.">
		
	<cfargument name="data" type="query" required="true">
	<cfargument name="maxLogEntries" type="numeric" required="false" default="100">
	
	<cftry>
		<cfset var resultStruct = StructNew()>
		<cfset var tempStruct = "">
		<cfset var tmp = "">
		<cfset var tmpc = "">
		<cfset var q = "">
		<cfset var count = "">
		<cfset var x = 0>
		<cfset var ctxt = ArrayNew(1)>
		
		<cfquery dbType="query" name="count" debug="false">
			SELECT Count(type) AS ttl
			FROM data
			WHERE type = 'Exception'
		</cfquery>
		
		<cfif NOT Val(count.ttl)>
	   	<cfreturn "">
	   </cfif>

		<cfquery dbType="query" name="q" debug="false" maxrows="#arguments.maxLogEntries#">
			SELECT *
			FROM data
			WHERE type = 'Exception'
		</cfquery>
		
		<cfif count.ttl GT arguments.maxLogEntries>
			<cfset firelogger_udf_error("CF-Firelogger Debug Warning: #count.ttl# Exceptions were found. Only showing the first #arguments.maxLogEntries#.")>
		</cfif>
		
		<cfloop query="q">
			<cfset tmp = firelogger_udf_fileFormatKeyname(q.template, q.line, "", q.currentRow, true, TimeFormat(q.timestamp, "mm:ss.LLL"), 4, ":", Len(q.recordcount))>
			
			<cfset resultStruct[tmp] = StructNew()>
			<cfset resultStruct[tmp].message = q.message>
			<cfset resultStruct[tmp].type = q.name>
			<!---<cfif IsDefined("q.stacktrace.detail")>--->
				<cfset resultStruct[tmp].detail = q.stacktrace[q.CurrentRow].detail>
				<cfset resultStruct[tmp].errorcode = q.stacktrace[q.CurrentRow].ErrorCode>
				<cfset resultStruct[tmp].extendedinfo = q.stacktrace[q.CurrentRow].extendedinfo>
				<cfset resultStruct[tmp].stacktrace = q.stacktrace[q.CurrentRow].stacktrace>
				
				<cfset ctxt = q.stacktrace[q.CurrentRow].TagContext>
				<cfset tempStruct = StructNew()>
				<cfloop index="x" from="1" to="#ArrayLen(ctxt)#">
					<cfset tmpc = firelogger_udf_fileFormatKeyname(ctxt[x].template, ctxt[x].line, "", x, true, "", 4, ":", Len(ArrayLen(ctxt)))>
					
					<cfset tempStruct[tmpc] = StructNew()>
					<cfif StructKeyExists(ctxt[x], "id")><cfset tempStruct[tmpc].id = ctxt[x].id></cfif>
					<cfif StructKeyExists(ctxt[x], "raw_trace")><cfset tempStruct[tmpc].raw_trace = ctxt[x].raw_trace></cfif>
					<cfif StructKeyExists(ctxt[x], "type")><cfset tempStruct[tmpc].type = ctxt[x].type></cfif>
				</cfloop>
				<cfset resultStruct[tmp].context = local.tempStruct>
			<!---</cfif>--->
			
		</cfloop>
		
		<cfreturn resultStruct>
	
		<cfcatch type="Any" >
		   <cfset firelogger_udf_error("Error formatting Exceptions", cfcatch)>
			<cfreturn "error occured while trying to output this value" />
		</cfcatch>
		
	</cftry>
</cffunction>




<cffunction 
	name="firelogger_udf_getQueries" 
	returnType="any"
	output="false"  
	hint="Gets queries from debugging info">
		
	<cfargument name="data" type="query" required="true">
	<cfargument name="type" type="string" required="false" default="SqlQuery">
	<cfargument name="maxLogEntries" type="numeric" required="false" default="100">

	<cftry>
	   <cfset var resultStruct = StructNew()>
		<cfset var firelogger_queries = "">
		<cfset var count = "">
		<cfset var x = "">
		<cfset var q = "">
		<cfset var sql = "">
		<cfset var attr = "">
		<cfset var rslt = "">
		<cfset var parameters = "">
		<cfset var resultsets = "">	
		<cfset var recordcount = 0>
		
		<!--- Process SQL queries --->
		<cfquery dbType="query" name="count" debug="false">
			SELECT Count(type) AS ttl
			FROM data
			WHERE type = '#arguments.type#'
		</cfquery>
		
		<cfif NOT Val(count.ttl)>
	   	<cfreturn "">
	   </cfif>

		<cfquery dbType="query" name="firelogger_queries" debug="false" maxrows="#arguments.maxLogEntries#">
			SELECT *, (endtime - starttime) AS executiontime
			FROM data
			WHERE type = '#arguments.type#'
		</cfquery>
		
		<cfscript>
			if( firelogger_queries.recordcount eq 1 and len(trim(firelogger_queries.executiontime)) ) {
				querySetCell(firelogger_queries, "executiontime", "0", 1); }
		</cfscript>
		
		<cfif count.ttl GT arguments.maxLogEntries>
			<cfset firelogger_udf_error("CF-Firelogger Debug Warning: #count.ttl# Queries  were found. Only showing the first #arguments.maxLogEntries#.")>
		</cfif>
		
		<!--- Add SQL queries to the result --->
		<cfloop query="firelogger_queries">
			
			<cfset parameters = "">
			<cfset resultsets = "">
			<cfset sql = "n/a">
			<cfset recordcount = "n/a">
			
			<cfif firelogger_queries.type IS "SqlQuery">
				<cfset sql = firelogger_queries.body>
			 
				<!--- get query results --->
				<cfif IsQuery(firelogger_queries.result)>
					<cfset resultsets = firelogger_queries.result>		
				</cfif>
	
				<!--- Get the rowcount --->
				<cfif IsDefined("firelogger_queries.rowcount") AND IsNumeric(firelogger_queries.rowcount)>
					<cfset recordcount = Max(firelogger_queries.rowcount, 0)>
				<cfelseif IsQuery("firelogger_queries.result")>
					<cfset q = firelogger_queries.result>
					<cfset recordcount = q.recordcount>
				</cfif>
			
			 <cfelse> <!--- stored proc --->
	
				<!--- get results array --->
				<cfif ArrayLen(firelogger_queries.result[firelogger_queries.currentRow])>
					<cfset resultsets = ArrayNew(1)>		
					<!--- build an array of parameter data --->
					<cfloop from="1" to="#ArrayLen(firelogger_queries.result[firelogger_queries.currentRow])#" index="x">
						<cfset rslt = firelogger_queries.result[firelogger_queries.currentRow][x]>
						<cfset resultsets[x] = ArrayNew(1)>
						<cfset ArraySet(resultsets[x], 1, 2, "")>
						<cfif StructKeyExists(rslt,"name")>
							<cfset resultsets[x][1] = rslt.name>
						</cfif>	
						<cfif StructKeyExists(rslt,"resultSet")>
							<cfset resultsets[x][2] = rslt.resultSet>
						</cfif>			
					</cfloop>
				</cfif>		
				
			</cfif>
			
			<!--- get query params --->
			<cfif ArrayLen(firelogger_queries.attributes[firelogger_queries.currentRow])>
				<cfset parameters = ArrayNew(1)>		
				<!--- build an array of parameter data --->
				<cfloop from="1" to="#ArrayLen(firelogger_queries.attributes[firelogger_queries.currentRow])#" index="x">
					<cfset attr = firelogger_queries.attributes[firelogger_queries.currentRow][x]>
					<cfset parameters[x] = ArrayNew(1)>
					<cfif firelogger_queries.type IS "SqlQuery">
						<cfset ArraySet(parameters[x], 1, 2, "")>
						
						<cfif StructKeyExists(attr,"sqltype")>
							<cfset parameters[x][1] = attr.sqltype>
						</cfif>			
						<cfif StructKeyExists(attr,"value")>
							<cfset parameters[x][2] = attr.value>
						</cfif>
						
					 <cfelse> <!--- storedproc --->
						<cfset ArraySet(parameters[x], 1, 8, "")>
						
						<cfif StructKeyExists(attr,"type")>
							<cfset parameters[x][1] = attr.type>
						<cfelse>
							<cfset parameters[x][1] = "IN">
						</cfif>	
						<cfif StructKeyExists(attr,"sqltype")>
							<cfset parameters[x][2] = attr.sqltype>
						</cfif>			
						<cfif StructKeyExists(attr,"value")>
							<cfset parameters[x][3] = attr.value>
						</cfif> 
						<cfif StructKeyExists(attr,"variable")>
							<cfset parameters[x][4] = "#attr.variable# = #firelogger_udf_CFDebugSerializable(attr.variable)#">
						</cfif>
						<cfif StructKeyExists(attr,"dbvarname")>
							<cfset parameters[x][5] = attr.dbvarname>
						</cfif>
						<cfif StructKeyExists(attr,"maxLength")>
							<cfset parameters[x][6] = attr.maxLength>
						</cfif>
						<cfif StructKeyExists(attr,"scale")>
							<cfset parameters[x][7] = attr.scale>
						</cfif>
						<cfif StructKeyExists(attr,"null")>
							<cfset parameters[x][8] = attr.null>
						</cfif>
						
					</cfif>
				</cfloop>
			</cfif>				
			
			<cfset q = NumberFormat(StructCount(resultStruct)+1, RepeatString("0", Len(count.ttl))) & " " & firelogger_queries.name>
			<cfset resultStruct[q] = StructNew()>
			<cfset resultStruct[q].meta = "Cached: " & YesNoFormat(firelogger_queries.cachedquery) & Chr(13) & Chr(10) &
		  											"Exec. Time: " & firelogger_queries.executiontime & " ms." & Chr(13) & Chr(10) &
		  											"Timestamp: " & TimeFormat(firelogger_queries.timestamp, "HH:mm:ss.LLL")>
			<cfset resultStruct[q].calledfrom = firelogger_queries.template & ":" & firelogger_queries.line>
			<cfset resultStruct[q].datasource = firelogger_queries.datasource>
			<cfset resultStruct[q].result = local.resultsets>
			<cfset resultStruct[q].parameters = local.parameters>
			<cfif firelogger_queries.type IS "SqlQuery">
		  		<cfset resultStruct[q].meta = "RecordCount: " & local.recordcount & Chr(13) & Chr(10) & resultStruct[q].meta>
				<cfset resultStruct[q].sql = local.sql>
		  	</cfif>
		  
		</cfloop>
		
		<cfreturn resultStruct>
	
		<cfcatch type="Any" >
		   <cfset firelogger_udf_error("Error formatting queries", cfcatch)>
			<cfreturn "error occurred while trying to output this value" />
		</cfcatch>
		
	</cftry>
</cffunction>


<cffunction 
	name="firelogger_udf_getTrace"
	returntype="any"
	output="false"  
	hint="Gets Trace info">
	
	<cfargument name="data" type="query" required="true">
	<cfargument name="maxLogEntries" type="numeric" required="false" default="100">
	
	<cftry>
	   <cfset var resultStruct = StructNew()>
		<cfset var result = "">
		<cfset var last = 0>
		<cfset var delta = 0>
		<cfset var tmp = "">
		<cfset var rsltkey = "">
		<cfset var count = "">
		
		<cfquery dbType="query" name="count" debug="false">
			select Count(type) AS ttl
			from data
			where type = 'Trace'
		</cfquery>
	
		<cfif NOT Val(count.ttl)>
	   	<cfreturn "">
	   </cfif>

		<cfquery dbType="query" name="result" debug="false" maxrows="#arguments.maxLogEntries#">
			select *
			from data
			where type = 'Trace'
		</cfquery>
	
		<cfif count.ttl GT arguments.maxLogEntries>
			<cfset firelogger_udf_error("CF-Firelogger Debug Warning: #count.ttl# Traces were found. Only showing the first #arguments.maxLogEntries#.")>
		</cfif>
		
		<cfloop query="result">
			<cfif result.currentRow GT 1>
				<cfset delta = result.endtime - local.last>
			</cfif>
			<cfset last = result.endtime>
					
			<cfset tmp = firelogger_udf_fileFormatKeyname(result.template, result.line, "[" & UCase(Left(result.priority, 1)) & "] T:" & result.endtime & " D:" & local.delta & " ", 
																						result.currentRow, true, TimeFormat(result.timestamp, "mm:ss.LLL"), 2, ":", Len(result.recordcount))>
			
			<cfset resultStruct[tmp] = StructNew()>
			<!---<cfset resultStruct[tmp].type = result.priority>--->
			<!---<cfset resultStruct[tmp].timestamp = TimeFormat(result.timestamp, "HH:mm:ss.LLL")>--->
			<cfif Len(result.message)>
				<cfset resultStruct[tmp].message = result.message>
			</cfif>
			<cfif Len(result.category)>
				<cfset resultStruct[tmp].category = result.category>
			</cfif>
			<cfif Len(result.name)>
				<cfset rsltkey = result.name>
			<cfelseif Find("=", result.result)>
				<cfset rsltkey = Trim(ListFirst(result.result, "="))>
				<cfset result.result = Trim(ListRest(result.result, "="))>
			</cfif>
			<cfif Len(local.rsltkey)>
				<cfset resultStruct[tmp][local.rsltkey] = result.result>
			</cfif>
			
		</cfloop>
		
		<cfreturn resultStruct>
	
		<cfcatch type="Any" >
		   <cfset firelogger_udf_error("Error formatting trace info", cfcatch)>
			<cfreturn "error occured while trying to output this value" />
		</cfcatch>
		
	</cftry>
</cffunction>


<cffunction 
	name="firelogger_udf_getTimer"
	returntype="any"  
	output="false"		
	hint="Gets Timer info">
		
	<cfargument name="data" type="query" required="true">
	
	<cftry>
	   <cfset var resultStruct = StructNew()>
		<cfset var result = "">
		<cfset var tmp = "">
		
		<cfquery dbType="query" name="result" debug="false">
			select	message, endtime-starttime as duration
			from arguments.data
			where type = 'CFTimer'
		</cfquery>
	
		<cfif NOT result.RecordCount>
	   	<cfreturn "">
	   </cfif>
	
		<cfloop query="result">
			<cfset tmp = NumberFormat(result.CurrentRow, "000") & " " & result.message & " (" & result.duration & " ms)">
			<cfset resultStruct[tmp] = "">
		</cfloop>
	
		<cfreturn resultStruct>
	
		<cfcatch type="Any" >
		   <cfset firelogger_udf_error("Error formatting timer info", cfcatch)>
			<cfreturn "[error occured while trying to output this value]" />
		</cfcatch>
		
	</cftry>
</cffunction>


<cffunction
	name="firelogger_udf_getVariables"
	returntype="string"
	output="false"
	hint="Get Variable values">
	
	<cfargument name="variableNames" type="array" required="true">
   <cftry>
	   <cfscript>
			var varsObj="";
			var varObj="";
			var t="";
	
			for (var x=1; x <= ArrayLen(arguments.variableNames); x=x+1) {
				if ( IsDefined(variableNames[x]) ) {
					varObj = __firelogger__.console.encodeJSON(data=evaluate(variableNames[x]), stringNumbers=true, formatDates=true);
					//varObj = serializeJSON(evaluate(variableNames[x]));  // serializeJSON can cause out of memory errors when trying to serialize some scopes on CF9.01
				} else {
					varObj = '"[undefined]"';
				}
				t = '"' & arguments.variableNames[x] & '":' & varObj;
				varsObj = ListAppend(varsObj, t);
			}
			
			return '{' & varsObj & '}';
	   </cfscript>
   
		<cfcatch type="Any" >
		   <cfset firelogger_udf_error("Error formatting variables output", cfcatch)>
			<cfreturn "error occured while trying to output this value" />
		</cfcatch>
		
	</cftry>
</cffunction>


<!--- UTILITY FUNCTIONS --->

<cffunction 
	name="firelogger_udf_CFDebugSerializable"
	returntype="string"
	output="false"
	hint="Handle output of complex data types.Taken from classic.cfm.">
		
	<cfargument name="variable" type="any" required="true">
	
	<cfset var ret = "undefined">
	
	<cftry>
		<cfif IsSimpleValue(variable)>		
			<cfset ret = xmlFormat(variable)>				
		<cfelseif IsStruct(variable)>
			<cfset ret = ("Struct (" & StructCount(variable) & ")")>			
		<cfelseif IsArray(variable)>
			<cfset ret = ("Array (" & ArrayLen(variable) & ")")>			
		<cfelseif IsQuery(variable)>
			<cfset ret = ("Query (" & variable.RecordCount & ")")>			
		<cfelse>
			<cfset ret = ("Complex type")>				
		</cfif>		
		<cfcatch></cfcatch>
	</cftry>
	
	<cfreturn ret>

</cffunction>
