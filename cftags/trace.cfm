<!---
	Name:				trace.cfm
	Author:			Maxim Paperno
	Created:			Jan. 2012
	Last Updated:	1/19/2012
	Version:			2.0
	History:			Updated to handle trace calls via firelogger.cfc
						Initial version based on ColdFire project by Nathan Mische & Raymond Camden
					
Serves two functions:
1) Outputs cftrace/trace() output to Firebug/FireLogger console if it is enabled.
2) Handles echanced trace debugging output for FireLogger (complex variable types are fully logged, not just the type of the variable).

Supports inline=true and abort=true directives. If inline=true then firelogger output is not generated.

Supports wrting to cftrace.log file as well (just like the original trace.cfm). Disabled by default.  
To enable this function, find the line below that reads:

<cfset doTrace(attributes, false)>

And change the second parameter to "true".

This template is ignored if firelogger not active or causes an error (fall through to default trace handler "trace_adobe.cfm").
--->

<!--- run on tag end if we can --->
<cfif thisTag.executionMode eq "end" or not thisTag.hasEndTag>

	<!--- are we using firelogger? --->
	<cfif StructKeyExists(GetHttpRequestData().headers,"X-FireLogger") 
			AND ( StructKeyExists(attributes, "var") OR StructKeyExists(attributes, "text") )>
	
		<!--- !!! second parameter true/false determines if trace writes to a log file or not. !!! --->
		<cfset doTrace(attributes, true)>
	
	<!--- else use the built-in version --->
	<cfelse>
		<cfinclude template="trace_adobe.cfm">
	</cfif>

</cfif>
 <!--- /if running as end tag or has no end tag --->

<!--- supporting functions --->

<cffunction name="doTrace" >
	<cfargument name="attributes">
	<cfargument name="writeToLog" default="false">
	<cfparam name="attributes.type" default="Information" type="string">
	<cfparam name="attributes.inline" default="false" type="boolean">
	<cfparam name="attributes.abort" default="false" type="boolean">
	<cfparam name="attributes.endTime" default="?" type="string">
	<cfparam name="attributes.delta" default="1st trace" type="string">
	
	<cftry>
	
		<cfscript>
			var parentContext = getMetaData(caller).getDeclaredField("pageContext");
				 parentContext.setAccessible(true);
				 parentContext = parentContext.get(caller);
			var template = parentContext.getPage().getCurrentTemplatePath();
			var lineno = parentContext.getCurrentLineNo();
			var obj = "";
			var msg = "";
			var level = "";
			var exitCode = 0;
			
			// is there an object to log?
			if ( StructKeyExists(attributes, "var") ) {
				if ( IsDefined("caller.#attributes.var#") ) {
					try {
						obj = caller[attributes.var];
					} catch (any e) {
						obj = e.message;
					}
				} else {
					obj = "[undefined]";
				}
			}
			
			// is there a simple message to log?
			if ( StructKeyExists(attributes, "text") ) {
				try {
					msg = attributes.text;
				} catch (any e) {
					msg = e.message;
				}
			} else if ( StructKeyExists(attributes, "var") ) {
				// if there's no message to log but we have a variable then
				// save the variable name as the message
				msg = attributes.var & " = ";
			}
	
			// don't bother with firelogger if inline output is desired
			if ( !attributes.inline ) {
	
				if ( !IsDefined("request.__firelogger__") || !isStruct(request.__firelogger__) || !structKeyExists(request.__firelogger__, "console") ) {
					if ( !IsDefined("request.__firelogger__") ) {
						request.__firelogger__ = {};
					}
					request.__firelogger__.console = new us.wdg.cf.firelogger(
																		fallbackLogMethod="none",
																		debugMode=false,
																		debugTraceInline=true,
																		debugLevel="error"
																	);
				}
				
				request.__firelogger__.console.setFilename(local.template);
				request.__firelogger__.console.setLineno(local.lineno);
				
				// if category is being passed, use that as the logger name
				// category could be a CSV list of "name,color" where "color" is a valid CSS color value
				if ( StructKeyExists(attributes, "category") ) {
					request.__firelogger__.console.setLoggerName(Left(ListFirst(attributes.category), 10));
					if ( ListLen(attributes.category) GT 1 ) {
						request.__firelogger__.console.setLoggerBGColor(ListGetAt(attributes.category, 2));
						if ( ListLen(attributes.category) GT 2 ) {
							request.__firelogger__.console.setLoggerFGColor(ListGetAt(attributes.category, 3));
						} else {
							request.__firelogger__.console.setLoggerFGColor("white");
						}
					} else {
						request.__firelogger__.console.resetLoggerBadge();
					}
				} else {
					request.__firelogger__.console.resetLoggerBadge();
				}
		
				// translate log level to something firelogger understands
				level = typeCF2FL(attributes.type);
				
				if ( StructKeyExists(attributes, "var") ) {
					exitCode = request.__firelogger__.console.log(local.level, local.msg, local.obj);
				} else {
					exitCode = request.__firelogger__.console.log(local.level, local.msg);
				}
			
			}
	
		</cfscript>

		<!--- if debugger is active, log enhanced trace --->
		<cfif IsDebugMode()>
			
			<cfset var factory = CreateObject("java","coldfusion.server.ServiceFactory")>
			<cfset var cfdebugger = factory.getDebuggingService()>
			<cfset var data = cfdebugger.getDebugger().getData()>
			<cfset var getLastTrace = "">
			
			<cfset var startTime = getPageContext().getFusionContext().getStartTime().getTime()>

			<cfquery name="getLastTrace" dbtype="query" debug="false">
				SELECT Max(endtime) AS lastTraceTime FROM data WHERE type = 'Trace'
			</cfquery>
			
			<cfset attributes.endTime = GetTickCount() - Val(local.startTime)>
			<cfif getLastTrace.RecordCount AND Val(getLastTrace.lastTraceTime)>
				<cfset attributes.delta = attributes.endTime - Val(getLastTrace.lastTraceTime)>
			</cfif>

			<cfset var row = QueryAddRow(data) />

			<!--- type --->
			<cfset QuerySetCell(data, "type", "Trace", row) />

			<!--- template --->
			<cfset QuerySetCell(data, "template", local.template, row) />

			<!--- line num --->
			<cfset QuerySetCell(data, "line", local.lineno, row) />

			<!--- timestamp --->
			<cfset QuerySetCell(data, "timestamp", Now(), row) />

			<!--- endTime --->
			<cfset QuerySetCell(data,"endTime", attributes.endTime, row) />

			<!--- priority (trace type) --->
			<cfset QuerySetCell(data, "priority", attributes.type, row) />

			<!--- category --->
			<cfif StructKeyExists(attributes, "category")>
				<cfset QuerySetCell(data, "category", ListFirst(attributes.category), row) />
			</cfif>

			<!--- message --->
			<cfif Len(local.msg)>
				<cfset QuerySetCell(data, "message", local.msg, row) />
			</cfif>

			<!--- result --->
			<cfif StructKeyExists(attributes, "var")>
				<!--- set the variable name into a blank column ("name" is not usually populated for traces) --->
				<cfset QuerySetCell(data, "name", attributes.var, row) />
				<cfset QuerySetCell(data, "result", local.obj, row) />
			</cfif>
	
		</cfif>
	
		<!--- dump to output if inline mode --->
		<cfif attributes.inline>
			<cfset doTraceOutput(attributes, template, lineno)>
		</cfif>
		
		<cfif arguments.writeToLog>
			<cfset writeTraceLog(attributes, template, lineno)>
		</cfif>
		
		<!--- abort if requested --->
		<cfif attributes.abort>
			<cfabort>
		</cfif>
	
		<cfcatch type="any">
			<!--- panic attack... fall through to default template --->
			<cfinclude template="trace_adobe.cfm">
			<!---<cfdump var="#cfcatch#">--->
		</cfcatch>
	</cftry>
	
</cffunction>

<cffunction output="true" name="doTraceOutput" hint="This re-creates the usual cftrace HTML output.">
	<cfargument name="attributes">
	<cfargument name="template">
	<cfargument name="lineno">
	
	<table cellspacing="0" cellpadding="0" border="0" bgcolor="white">
	<tbody>
		<tr>
			<td>
				<img alt="#attributes.type# type" src="/CFIDE/debug/images/#attributes.type#_16x16.gif">
				<font color="orange">
					<b>
						[CFTRACE #TimeFormat(Now(), "HH:mm:ss.LLL")#] [#attributes.endTime# ms (#attributes.delta#)] [#arguments.template# @ line: #arguments.lineno#] - 
						<cfif StructKeyExists(attributes, "category")>[#ListFirst(attributes.category)#]</cfif>
						<cfif StructKeyExists(attributes, "text")><i>#attributes.text#</i></cfif>
					</b>
				</font>
			</td>
		</tr>
	</tbody>
	</table>
	<cfif StructKeyExists(attributes, "var") AND IsDefined("caller.#attributes.var#")>
		<table cellspacing="0" cellpadding="0" border="1">
		<tbody>
			<tr bgcolor="orange">
				<td align="center"><font color="white"><b>#attributes.var#</b></font></td>
			</tr>
			<tr style="background-color: white; color: black;">
				<td><cfdump var="#caller[attributes.var]#"></td>
			</tr>
		</tbody>
		</table>
	</cfif>
</cffunction>

<cffunction output="true" name="writeTraceLog" hint="Writes to cftrace.log just like the original trace.cfm.">
	<cfargument name="attributes">
	<cfargument name="template">
	<cfargument name="lineno">
	
	<cfset var logText = "[" & attributes.endTime & "ms (" & attributes.delta & ")] [" & arguments.template & " @ line: " & arguments.lineno & "] - ">
	<cfif StructKeyExists(attributes, "var") AND IsDefined("caller.#attributes.var#")>
		<cfset logText = logText & "[" & attributes.var & " = " & isSerializable(caller[attributes.var]) & "]">
	</cfif>
	<cfif StructKeyExists(attributes, "text")>
		<cfset logText = logText & " " & attributes.text>
	</cfif>
	<cflog file="cftrace.log" application="true" type="#attributes.type#" text="#local.logText#" >

</cffunction>

<cfscript>
	/**
	 * Converts CF style logging types (severity levels) to firelogger types
	 */
	public string function typeCF2FL(string type) {
		switch (arguments.type) {
			case "information" :
				return "info";
				break;
			case "warning":
			case "error":
				return arguments.type;
			case "fatal information":
			case "fatal":
				return "critical";
			default:
				return "debug";
		}
	}
	
	/**
	 * Handle output of complex data types. Taken from dockable.cfm debug template.
	 *
	 * @output false
	 */
	function isSerializable(required any variable) {
		var ret = "[undefined]";
		
		try {
			if(IsSimpleValue(variable)) {
				ret = variable;
			} else if(IsStruct(variable)) {
				ret = "Struct (" & StructCount(variable) & ")";
			} else if(IsArray(variable)) {
				ret = "Array (" & ArrayLen(variable) & ")";
			} else if(IsQuery(variable)) {
				ret = "Query (" & variable.RecordCount & ")";
			} else {
				ret = "Complex type";
			}
		} catch (any e) {}
		
		return ret;
	}
</cfscript>


