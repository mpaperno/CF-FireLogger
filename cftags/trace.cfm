<!---
	Name:				trace.cfm
	Author:			Maxim Paperno
	Created:			Jan. 2012
	Last Updated:	1/23/2012
	Version:			2.1
	History:			Added compatiblity for ColdFire debugging output. Added check for firelogger.cfm debug template is active. (jan-23-12)
						Updated to handle trace calls via firelogger.cfc (jan-19-12)
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

	<!--- are we using firelogger or coldfire? --->
	<cfif ( StructKeyExists(attributes, "var") OR StructKeyExists(attributes, "text") )
			AND ( 
				StructKeyExists(GetHttpRequestData().headers, "X-FireLogger")
				OR ( StructKeyExists(GetHttpRequestData().headers, "x-coldfire-enhance-trace")
					AND StructKeyExists(GetHttpRequestData().headers, "User-Agent")
					AND FindNoCase("ColdFire", GetHttpRequestData().headers["User-Agent"]) )
			)>
	
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
	
			// don't bother with firelogger if inline output is desired or headers aren't present
			if ( !attributes.inline && StructKeyExists(GetHttpRequestData().headers, "X-FireLogger") ) {
	
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
				
				<!--- if coldfire debug is enabled, log the trace in a serialized format it can parse. --->
				<cfif FindNoCase("coldfire.cfm", cfdebugger.settings.debug_template) AND StructKeyExists(GetHttpRequestData().headers, "x-coldfire-enhance-trace")>
					<cfset obj = coldfire_trace_udf_encode(local.obj)>
				<!--- if we're not using firelogger.cfm debug template, log plain-text output like the standard trace does. --->
				<cfelseif NOT ReFindNoCase("firelogger\d*\.cfm", cfdebugger.settings.debug_template)>
					<cfset obj = attributes.var & " = " & isSerializable(local.obj)>
				</cfif>
				
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

<!--- this is included unchanged from coldfire version of trace.cfm to maintain compatibility with ColdFire --->

<cffunction 
	name="coldfire_trace_udf_encode" 
	returntype="string" 
	output="false"
	hint="Converts data from CF to JSON format">
		
	<cfargument name="data" type="any" required="Yes" />
	<!---
		The following argument allows for formatting queries in query or struct format
		If set to query, query will be a structure of colums filled with arrays of data
		If set to array, query will be an array of records filled with a structure of columns
	--->
	<cfargument name="queryFormat" type="string" required="No" default="query" />
	<cfargument name="queryKeyCase" type="string" required="No" default="upper" />
	<cfargument name="stringNumbers" type="boolean" required="No" default=false >
	<cfargument name="formatDates" type="boolean" required="No" default=false >
	
	<!--- VARIABLE DECLARATION --->
	<cfset var jsonString = "" />
	<cfset var tempVal = "" />
	<cfset var arKeys = "" />
	<cfset var colPos = 1 />
	<cfset var i = 1 />
	
	<cfset var ignoreStructKeys = "_CF_HTMLASSEMBLER,__COLDFIREVARIABLEVALUES__,__firelogger__">
	<cfset var ignoreFunctionPrefix = "coldfire_udf">
	
	<cfset var _data = arguments.data />

	<cfset var recordcountKey = "" />
	<cfset var columnlistKey = "" />
	<cfset var columnlist = "" />
	<cfset var dataKey = "" />
	<cfset var column = "" />
	
	<!--- ARRAY --->
	<cfif IsArray(_data) AND NOT IsBinary(_data)>
		<cfset jsonString = ArrayNew(1)/>	
		<cfloop from="1" to="#ArrayLen(_data)#" index="i">
			<cfset tempVal = coldfire_trace_udf_encode( _data[i], arguments.queryFormat, arguments.queryKeyCase ) />
			<cfset ArrayAppend(jsonString, tempVal) />
		</cfloop>		
		<cfreturn "[" & ArrayToList(jsonString,",") & "]" />
		
	<!--- BINARY --->
	<cfelseif IsBinary(_data)>
		<cfset jsonString = ArrayNew(1)/>		
		<cfloop from="1" to="#Min(ArrayLen(_data),1000)#" index="i">
			<cfset ArrayAppend(jsonString,_data[i]) />
		</cfloop>		
		<cfreturn "{""__cftype__"":""binary"",""data"":""" & ArrayToList(jsonString,"") & """,""length"":" & ArrayLen(_data) & "}" />

	<!--- BOOLEAN --->
	<cfelseif IsBoolean(_data) AND NOT IsNumeric(_data) AND NOT ListFindNoCase("Yes,No", _data)>
		<cfreturn LCase(ToString(_data)) />
		
	<!--- CUSTOM FUNCTION --->
	<cfelseif IsCustomFunction(_data)>
		<cfset md = GetMetaData(_data) />
		<cfif CompareNoCase(Left(md.name,Len(ignoreFunctionPrefix)),ignoreFunctionPrefix) eq 0>
			<cfreturn "coldfire_ignore_value" />
		<cfelse>		
			<cfset jsonString = ArrayNew(1) />
			<cfset ArrayAppend(jsonString,"""__cftype__"":""customfunction""")>
			<cfset arKeys = StructKeyArray(md) />
			<cfloop from="1" to="#ArrayLen(arKeys)#" index="i">
				<cfset tempVal = coldfire_trace_udf_encode( md[ arKeys[i] ], arguments.queryFormat, arguments.queryKeyCase ) />
				<cfset ArrayAppend(jsonString, '"' & arKeys[i] & '":' & tempVal) />
			</cfloop>
			<cfreturn "{" & ArrayToList(jsonString,",") & "}" />
		</cfif>	
		
	<!--- NUMBER --->
	<cfelseif NOT stringNumbers AND IsNumeric(_data) AND NOT REFind("^0+[^\.]",_data)>
		<cfreturn ToString(_data) />
	
	<!--- DATE --->
	<cfelseif IsDate(_data) AND arguments.formatDates>
		<cfreturn '"#DateFormat(_data, "mmmm, dd yyyy")# #TimeFormat(_data, "HH:mm:ss")#"' />
		
	<!--- WDDX --->
	<cfelseif IsWDDX(_data)>
		<cfwddx action="wddx2cfml" input="#_data#" output="tempVal" />
		<cfreturn "{""__cftype__"":""wddx"",""data"":" & coldfire_trace_udf_encode( tempVal, arguments.queryFormat, arguments.queryKeyCase ) & "}" />
		
	<!--- STRING --->
	<cfelseif IsSimpleValue(_data)>
		<cfreturn '"' & Replace(JSStringFormat(_data), "/", "\/", "ALL") & '"' />
		
	<!--- OBJECT --->
	<cfelseif IsObject(_data)>	
		<cfset md = GetMetaData(_data) />	
		<cfset arKeys = StructKeyArray(md) />		
		
		<cfif ArrayLen(arKeys) eq 0>
			<!--- java object --->
			<cftry>
				<cfset jsonString = ArrayNew(1) />
				<cfset ArrayAppend(jsonString,"""__cftype__"":""java""") />
				
				<!--- get the class name --->
				
				<cfset ArrayAppend(jsonString,'"CLASSNAME":"' & _data.getClass().getName() & '"') />
				
				<!--- get object method data, this could probabaly use some work --->
				
				<cfset methods = _data.getClass().getMethods()>
				<cfset methodStruct = StructNew() />
				<cfset methodArray = ArrayNew(1) />
				<cfloop from="1" to="#ArrayLen(methods)#" index="i">	
					<cfset methodString = methods[i].getName() & "(" />
					<cfset params = methods[i].getParameterTypes()>
					<cfset delim = ""/>
					<cfloop from="1" to="#ArrayLen(params)#" index="x">
						<cfset methodString = methodString & delim & " " & params[x].getCanonicalName() />
						<cfset delim = "," />
					</cfloop>
					<cfset methodString = methodString & ")" />	
					<cfset methodStruct[methods[i].getName()] = StructNew() />
					<cfset methodStruct[methods[i].getName()].method = methodString />	
					<cfset methodStruct[methods[i].getName()].returntype = methods[i].getReturnType().getCanonicalName() />
				</cfloop>				
				<cfset sortedKeys = StructSort(methodStruct,"textnocase","asc","method") />				
				
				<cfloop from="1" to="#ArrayLen(sortedKeys)#" index="i">
					<cfset ArrayAppend(methodArray,methodStruct[sortedKeys[i]]) />
				</cfloop>

				<cfset tempVal = coldfire_trace_udf_encode( methodArray, arguments.queryFormat, arguments.queryKeyCase ) />
				
				<cfset ArrayAppend(jsonString,'"METHODS":' & tempVal) />
				
				<!--- get object field data, not getting values --->
				<cfset fields = _data.getClass().getFields()>
				<cfset fieldStruct = StructNew() />
				<cfset fieldArray = ArrayNew(1) />				
				<cfloop from="1" to="#ArrayLen(fields)#" index="i">	
					<cfset fieldStruct[fields[i].getName()] = StructNew() />
					<cfset fieldStruct[fields[i].getName()].field = fields[i].getType().getName() & " " & fields[i].getName() />	
					<cfset fieldStruct[fields[i].getName()].value = fields[i].getType().getName() />
				</cfloop>				
				<cfset sortedKeys = StructSort(fieldStruct,"textnocase","asc","field") />
				
				<cfloop from="1" to="#ArrayLen(sortedKeys)#" index="i">
					<cfset ArrayAppend(fieldArray,fieldStruct[sortedKeys[i]]) />
				</cfloop>
				
				<cfset tempVal = coldfire_trace_udf_encode( fieldArray, arguments.queryFormat, arguments.queryKeyCase ) />
				
				<cfset ArrayAppend(jsonString,'"FIELDS":' & tempVal) />
				
				
				<cfreturn "{" & ArrayToList(jsonString,",") & "}" />				
			
				<cfcatch type="any">
					<cfreturn "{""__cftype__"":""unknown""}" />	
				</cfcatch>
			</cftry>			
		<cfelse>
			<!--- component --->		
			<cfset jsonString = ArrayNew(1) />
			<cfset ArrayAppend(jsonString,"""__cftype__"":""component""") />
			<cfloop from="1" to="#ArrayLen(arKeys)#" index="i">			
				<cfif ListFind("NAME,FUNCTIONS",arKeys[i])>
					<cfset tempVal = coldfire_trace_udf_encode( md[ arKeys[i] ], arguments.queryFormat, arguments.queryKeyCase ) />
					<cfset ArrayAppend(jsonString, '"' & arKeys[i] & '":' & tempVal) />
				</cfif>
			</cfloop>
			<cfreturn "{" & ArrayToList(jsonString,",") & "}" />
		</cfif>
	
	<!--- STRUCT --->
	<cfelseif IsStruct(_data)>
		<cfset jsonString = ArrayNew(1) />
		<cfset ArrayAppend(jsonString,"""__cftype__"":""struct""") />
		<cfset arKeys = StructKeyArray(_data) />
		<cfloop from="1" to="#ArrayLen(arKeys)#" index="i">			
			<cfif ListFindNoCase(ignoreStructKeys, arKeys[i]) eq 0>
				<cfset tempVal = coldfire_trace_udf_encode( _data[ arKeys[i] ], arguments.queryFormat, arguments.queryKeyCase ) />
				<cfif tempVal neq "coldfire_ignore_value">
					<cfset ArrayAppend(jsonString, '"' & arKeys[i] & '":' & tempVal) />
				</cfif>
			</cfif>			
		</cfloop>				
		<cfreturn "{" & ArrayToList(jsonString,",") & "}" />		
	
	<!--- QUERY --->
	<cfelseif IsQuery(_data)>
		<!--- Add query meta data --->
		<cfif arguments.queryKeyCase EQ "lower">
			<cfset recordcountKey = "recordcount" />
			<cfset columnlistKey = "columnlist" />
			<cfset columnlist = LCase(_data.columnlist) />
			<cfset dataKey = "data" />
		<cfelse>
			<cfset recordcountKey = "RECORDCOUNT" />
			<cfset columnlistKey = "COLUMNLIST" />
			<cfset columnlist = UCase(_data.columnlist) />
			<cfset dataKey = "DATA" />
		</cfif>
		<cfset jsonString = ArrayNew(1) />
		<cfset ArrayAppend(jsonString,"""#recordcountKey#"":#_data.recordcount#,") />
		<cfset ArrayAppend(jsonString,"""#columnlistKey#"":""#columnlist#"",") />
		<cfset ArrayAppend(jsonString,"""#dataKey#"":") />
				
		<!--- Make query a structure of arrays --->
		<cfif arguments.queryFormat EQ "query">
			<cfset ArrayAppend(jsonString,"{") />
			<cfset colPos = 1 />
			
			<cfloop list="#_data.columnlist#" delimiters="," index="column">
				<cfif colPos GT 1>
					<cfset ArrayAppend(jsonString,",") />
				</cfif>
				<cfif arguments.queryKeyCase EQ "lower">
					<cfset column = LCase(column) />
				</cfif>
				<cfset ArrayAppend(jsonString,"""#column#"":[") />
				
				<cfloop from="1" to="#_data.recordcount#" index="i">
					<!--- Get cell value; recurse to get proper format depending on string/number/boolean data type --->
					<cfset tempVal = coldfire_trace_udf_encode( _data[column][i], arguments.queryFormat, arguments.queryKeyCase ) />
					
					<cfif i GT 1>
						<cfset ArrayAppend(jsonString,",") />
					</cfif>
					<cfset ArrayAppend(jsonString,tempVal) />
				</cfloop>
				
				<cfset ArrayAppend(jsonString,"]") />
				
				<cfset colPos = colPos + 1 />
			</cfloop>
			<cfset ArrayAppend(jsonString,"}") />
		<!--- Make query an array of structures --->
		<cfelse>
			<cfset ArrayAppend(jsonString,"[") />
			<cfloop query="_data">
				<cfif CurrentRow GT 1>
					<cfset ArrayAppend(jsonString,",") />
				</cfif>
				<cfset ArrayAppend(jsonString,"{") />
				<cfset colPos = 1 />
				<cfloop list="#columnlist#" delimiters="," index="column">
					<cfset tempVal = coldfire_trace_udf_encode( _data[column][CurrentRow], arguments.queryFormat, arguments.queryKeyCase ) />
					
					<cfif colPos GT 1>
						<cfset ArrayAppend(jsonString,",") />
					</cfif>
					
					<cfif arguments.queryKeyCase EQ "lower">
						<cfset column = LCase(column) />
					</cfif>
					<cfset ArrayAppend(jsonString,"""#column#"":#tempVal#") />
					
					<cfset colPos = colPos + 1 />
				</cfloop>
				<cfset ArrayAppend(jsonString,"}") />
			</cfloop>
			<cfset ArrayAppend(jsonString,"]") />
		</cfif>
		
		<!--- Wrap all query data into an object --->
		<cfreturn "{" & ArrayToList(jsonString,"") & "}" />
		
	<!--- XML DOC --->
	<cfelseif IsXMLDoc(_data)>
		<cfset jsonString = ArrayNew(1) />
		<cfset ArrayAppend(jsonString,"""__cftype__"":""xmldoc""") />
		<cfset arKeys = ListToArray("XmlComment,XmlRoot") />
		<cfloop from="1" to="#ArrayLen(arKeys)#" index="i">			
			<cfif ListFindNoCase(ignoreStructKeys, arKeys[i]) eq 0>
				<cfset tempVal = coldfire_trace_udf_encode( _data[ arKeys[i] ], arguments.queryFormat, arguments.queryKeyCase ) />
				<cfif tempVal neq "coldfire_ignore_value">
					<cfset ArrayAppend(jsonString, '"' & arKeys[i] & '":' & tempVal) />
				</cfif>
			</cfif>			
		</cfloop>				
		<cfreturn "{" & ArrayToList(jsonString,",") & "}" />
	
	<!--- XML ELEMENT --->
	<cfelseif IsXmlElem(_data)>
		<cfset jsonString = ArrayNew(1) />
		<cfset ArrayAppend(jsonString,"""__cftype__"":""xmlelem""") />
		<cfset arKeys = ListToArray("XmlName,XmlNsPrefix,XmlNsURI,XmlText,XmlComment,XmlAttributes,XmlChildren") />
		<cfloop from="1" to="#ArrayLen(arKeys)#" index="i">			
			<cfif ListFindNoCase(ignoreStructKeys, arKeys[i]) eq 0>
				<cfset tempVal = coldfire_trace_udf_encode( _data[ arKeys[i] ], arguments.queryFormat, arguments.queryKeyCase ) />
				<cfif tempVal neq "coldfire_ignore_value">
					<cfset ArrayAppend(jsonString, '"' & arKeys[i] & '":' & tempVal) />
				</cfif>
			</cfif>			
		</cfloop>				
		<cfreturn "{" & ArrayToList(jsonString,",") & "}" />
		
	<!--- XML NODE --->
	<cfelseif IsXmlNode(_data)>
		<cfset jsonString = ArrayNew(1) />
		<cfset ArrayAppend(jsonString,"""__cftype__"":""xmlnode""") />
		<cfset arKeys = ListToArray("XmlName,XmlType,XmlValue") />
		<cfloop from="1" to="#ArrayLen(arKeys)#" index="i">			
			<cfif ListFindNoCase(ignoreStructKeys, arKeys[i]) eq 0>
				<cfset tempVal = coldfire_trace_udf_encode( _data[ arKeys[i] ], arguments.queryFormat, arguments.queryKeyCase ) />
				<cfif tempVal neq "coldfire_ignore_value">
					<cfset ArrayAppend(jsonString, '"' & arKeys[i] & '":' & tempVal) />
				</cfif>
			</cfif>			
		</cfloop>				
		<cfreturn "{" & ArrayToList(jsonString,",") & "}" />
	
	<!--- UNKNOWN OBJECT TYPE --->
	<cfelse>
		<cfreturn "{""__cftype__"":""unknown""}" />	
	</cfif>
</cffunction>
		
