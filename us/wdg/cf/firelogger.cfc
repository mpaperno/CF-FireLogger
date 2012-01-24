<!---
	Name:				firelogger.cfc
	Author:			Maxim Paperno
	Created:			Jan. 2012
	Last Updated:	1/24/2012
	Version:			1.02
	History:			Minor method meta info updates. (jan-24-12)
						Auto-set level to error if logging cfcatch object. Fix for passing pre-formatted error report. (jan-24-12)
						Initial version.

Handles server-side output for FireLogger Firebug plugin.

( FireLogger output spec: https://github.com/darwin/firelogger/wiki/ )
--->

<cfcomponent displayname="CF-FireLogger" 
				accessors="true" 
				hint="This component handles logging output to a browser console like Firebug with FireLogger extension.">

<!--- Property declarations.
	
		!! If you want to change a default value for a property, don't do it here... this is just for meta data and implicit accessors.
			Set defaults in the variables declarations, below. !!
 --->
	<cfproperty name="obj" 
					type="any" 
					hint="The variable to be evaluated and logged. Can be any type of value, 
			  					including complex types such as structures and objects. Undefined by default">
					
	<cfproperty name="text" 
					default="" 
					type="string" 
					hint="The plain-text message to be logged.">
					
	<cfproperty name="type" 
					default="debug" 
					type="string" 
					hint="The message type. Can be one of: debug, info, warning, error, exception">
					
	<cfproperty name="loggerName" 
					default="CF" 
					type="string" 
					hint="A title for the badge/label on the right of each console logline in FireLogger.">
					
	<cfproperty name="loggerBGColor" 
					default="##315F81" 
					type="string" 
					hint="Background color for badge/label, any css color value.">
					
	<cfproperty name="loggerFGColor" 
					default="##FFFFFF" 
					type="string" 
					hint="Foreground (text) color for badge/label, any css color value.">
					
	<cfproperty name="password" 
					default="" 
					type="string" 
					setter="false" 
					getter="false" 
					hint="FireLogger password, if one is being used (blank if not). Use setPassword('pass') to set.
			  					Or during init(password='pass').">
					
	<cfproperty name="valuesAlreadySerialized" 
					default="false" 
					type="boolean" 
					getter="false" 
					hint="Set this to true if complex data being logged is already valid JSON. 
			  					Saves time evaluating if it needs to be serialized.">
					
	<cfproperty name="filename" 
					default="" 
					type="string" 
					getter="false" 
					hint="Path/name of file containig log() directive. Typically set by this component, 
			  					but this setting can override it.">
					
	<cfproperty name="lineno" 
					default="?" 
					type="string" 
					getter="false" 
					hint="Line number log call was made from. Typically set by this component, 
			  					but this setting can override it.">
					
	<cfproperty name="maxHeaderLength" 
					default="5000" 
					type="numeric"
					getter="false" 
					hint="Maximum length of each response header line (bytes).">
					
	<cfproperty name="maxEncodeDepth" 
					default="30" 
					type="numeric"
					getter="false" 
					hint="Maximum recursion for serializing complex values.">
					
	<cfproperty name="fallbackLogMethod" 
					default="trace-inline" 
					type="string" 
					hint="How to handle logging if FireLogger is unable to. One of: trace-inline, trace, dump, none.">
					
	<cfproperty name="debugMode" 
					default="false" 
					type="boolean" 
					hint="Set to true to enable CF FireLogger debugging.">
					
	<cfproperty name="debugLevel" 
					default="panic" 
					type="string" 
					hint="One of: panic : show only erros that can't be sent via headers; 
			  					error : dump all errors; info: show debug info.">
	
	<cfproperty name="debugTraceInline" 
					default="true" 
					type="boolean" 
					hint="Set to true to trace debug info to current page, false to trace to debug info/log file.">
					
	<cfproperty name="version" 
					type="numeric" 
					setter="false" 
					hint="CF FireLogger version number (read-only).">
					
	<cfproperty name="isConsoleEnabled" 
					default="false" 
					type="boolean" 
					setter="false" 
					hint="Is true if Firebug/FireLogger console is enabled (read-only).">
					
	
<cfscript>
	
	// set defaults for properties here
	// keep "obj" undefined to simplify testing for its existence
	
	variables.version = "1.02";
	
	variables.projectURL = "http://cffirelogger.riaforge.org/";
	variables.fireloggerURL = "http://firelogger.binaryage.com/";
	
	// version control (expected FireLogger version)
	variables.expectedClientVersion = "1.2";
	
	variables.type = "debug";
	variables.text = "";
	variables.password = "";
	valuesAlreadySerialized = false;
	variables.filename = "";
	variables.lineno = "?";
	variables.maxHeaderLength = 5000;
	variables.maxEncodeDepth = 20;
	variables.fallbackLogMethod = "trace-inline";
	variables.debugMode = false;
	variables.debuglevel = "panic";
	variables.debugTraceInline = true;
	
	// possible log message types
	variables.levels = ['debug', 'warning', 'info', 'error', 'critical'];
	
	// allowed init() method parameters which can override component properties
	variables.allowedArguments = ['obj', 'type', 'text', 'category', 'password', 'valuesAlreadySerialized', 
												'filename', 'lineno', 'maxHeaderLength', 'maxEncodeDepth',
												'loggerName', 'loggerBGColor', 'loggerFGColor', 'fallbackLogMethod', 
												'debugMode', 'debuglevel', 'debugTraceInline'];
	
	// Structure keys to ignore (do not remove _CF_HTMLASSEMBLER);
	// __firelogger__ is used in this cfc, in the custom trace.cfm, and in firelogger.cfm debugging template
	variables.ignoreStructKeys = "_CF_HTMLASSEMBLER,__firelogger__";
	// UDF names with the following prefix will be ignored; "firelogger_udf" is used in firelogger.cfm debugging template
	variables.ignoreFunctionPrefix = "firelogger_udf";
	
	// errors collector
	variables.errors = [];
	// headers collector
	variables.headers = {};
	
	// current request data
	variables.httpRequestData = GetHttpRequestData();

	/**
	 * Initialization routine. Returns an instance of this component.
	 * Specify any properties to set as named arguments.
	 * Example: logger = new firelogger(password='pass', debugMode=true);
	 *
	 * @output false
	 */
	public any function init() {
		param struct request.__firelogger__ = structNew();
		param numeric request.__firelogger__.counter = 0;
		
		resetLoggerBadge();
		setParameters(arguments);
		setIsConsoleEnabled();
		clientVersionCheck();
		
		return this;
	}

	/**
	 * Log a record to the console.
	 * 
	 * Usage: log([level,] [message,] [object] [, object]...)
	 * Where: level = one of: debug (default), warning, info, error, critical.
	 * 		 message = text to log; may contain simple-value variables. 
	 *			 object = one or more values to log, of any type.
	 *
	 *   note: at least one of a message or object is required, otherwise function exits
	 *				w/out doing anything.
	 *
	 * @returns: true if log action succeeded, false otherwise.
	 *
	 * Any arguments passed to this method are do not override the component-wide
	 * default.  For example, setting the log type here does not change the default
	 * log type. Default log type can be set with setType("type");
	 * 
	 */
	public boolean function log() {
		return logProxy(args=arguments);
	}
	
	/**
	 * this is actually the main logging function... but "log()" is also a built-in CF function
	 * name, so we don't really want to use it as then we have to call this.log() internally
	 * which "pollutes" the tag call stack.
	 * 
	 * (output: true because we might have to dump output to the browser in case 
	 * a fallback method is necessary.  Would be nice if this could be dynamic
	 * based on the debug variable.)
	 *
	 * @output true
	 */
	private boolean function doLog(/* [string type,] string text [, any obj [, obj][, obj]...]*/) {
		try {
			
			// exit if no arguments
			setIsConsoleEnabled();
			if ( !variables.isConsoleEnabled || !StructKeyExists(arguments, 1) ) { return false; }
			
			var aryObjects = [];
			var argKeys = StructKeyArray(arguments);
			var time = getTickCount();
			var output = "";
			var logitem = [];
			var msgtemplate = "";
			var style = "background-color: " & variables.loggerBGColor & "; color: " & variables.loggerFGColor;
			var tmp = "";
			var tmpval = "";
			var i = 1;
			
			// defaults
			param string arguments.type = variables.type;
			param string arguments.text = variables.text;
			if ( IsDefined("variables.obj") ) {
				param any arguments.obj = variables.obj;
			}
			
			// make sure arguments are evaluated in the order passed
			ArraySort(argKeys, "numeric");
			
			// log type as first argument?
			if ( ArrayFindNoCase(variables.levels, arguments[1]) ) {
				arguments.type = arguments[1];
				ArrayDeleteAt(argKeys, 1); // shift arguments array
			}
			
			// plain text message as next argument?
			if ( ArrayLen(argKeys) && IsSimpleValue(arguments[argKeys[1]]) ) {
				arguments.text = arguments[argKeys[1]];
				ArrayDeleteAt(argKeys, 1); // shift arguments array
			}
			
			// exit if nothing to log
			if ( !Len(arguments.text) && !ArrayLen(local.argKeys) && !ArrayLen(variables.errors) ) { return false; }
			
			if ( Len(arguments.text) || ArrayLen(local.argKeys) ) {
				
				msgtemplate = arguments.text;
				if ( ArrayLen(local.argKeys) && !reFindNoCase("\s%[a-z0-9](\s|\Z)", local.msgtemplate) ) {
					msgtemplate = local.msgtemplate & " %s";
				}
				logitem = {
						"name" = variables.loggerName,
						"style" = local.style,
						"level" = arguments.type,
						"timestamp" = GetTickCount(),
						"time" = DateFormat(Now(), "long") & " " & TimeFormat(Now(), "HH:mm:ss.LLL"),
						"order" = request.__firelogger__.counter,
						"pathname" = variables.filename,
						"lineno" = variables.lineno,
						"template" = local.msgtemplate,
						"message" = arguments.text
				};
	
				if ( !Len(variables.filename) ) {
					tmp = getCallerFileLine();
					logitem.pathname = tmp[1];
					logitem.lineno = tmp[2];
				}
				
				
				// any following argument(s) is/are object(s) to dump
				if ( ArrayLen(argKeys) ) {
					for (i=1; i <= ArrayLen(argKeys); i=i+1) {
						tmp = arguments[argKeys[i]];
						// check to see if we're passing a special struct which specifies the template path/name and line number to report  (eg. from a custom trace.cfm)
						if ( IsStruct(tmp) && StructKeyExists(tmp, "firelogger_filename") && StructKeyExists(tmp, "firelogger_lineno") ) {
							logitem.pathname = tmp.firelogger_filename;
							logitem.lineno = tmp.firelogger_lineno;
							continue; // don't log this value
						}
						// check to see if we're passing a pre-packaged array of error message(s) with stack trace
						else if ( IsStruct(tmp) && StructKeyExists(tmp, "exc_info") && IsArray(tmp["exc_info"]) ) {
							logitem["level"] = "error";
							logitem["exc_info"] = encodeJSON(data=tmp.exc_info, preserveArrays=1, preserveArraysRecurseLevels=0);
							if ( StructKeyExists(tmp, "exc_frames") ) {
								logitem["exc_frames"] = encodeJSON(data=tmp.exc_frames, preserveArrays=1, preserveArraysRecurseLevels=0);;
							}
							continue; // don't log this value in args parameter
						}
						
						// check to see if we're passing an exception type (cfcatch object)
						else if ( IsDefined("tmp.tagcontext") && IsDefined("tmp.type") ) {
							tmpval = formatErrorOutput(arguments.text, tmp);
							logitem["level"] = "error";
							logitem["template"] = tmpval.text;
							logitem["exc_info"] = encodeJSON(data=tmpval.exc_info, preserveArrays=1, preserveArraysRecurseLevels=0);
							logitem.pathname = tmpval.filename;
							logitem.lineno = tmpval.lineno;
							continue; // don't log this value in args parameter
						}
						
						// else we'll serialize and log the object
						if ( !variables.valuesAlreadySerialized ) {
							tmp = encodeJSON(data=local.tmp, preserveArrays=1, preserveArraysRecurseLevels=1);
						}
						aryObjects[ArrayLen(aryObjects)+1] = tmp;
					}
					
					if ( ArrayLen(aryObjects) ) {
						logitem["args"] = '[' & ArrayToList(local.aryObjects) & ']';
					}
				}
			
				
				// output = '"logs":[' & encodeJSON(data=local.logitem, preserveArrays=1) & ']';
				output = '"logs":[{';
				
				tmp = "";
				for (i in logitem) {
					tmpval = logitem[i];
					if ( !listFind("args,exc_info,exc_frames",i) ) {
						tmpval = encodeJSON(data=local.tmpval);
					}
					tmp = ListAppend(tmp, '"' & i & '":' & local.tmpval);
				}
				
				output = local.output & local.tmp & "}]";
				
			}
			
			if ( ArrayLen(variables.errors) ) {
				output = ListAppend(local.output, '"errors":' & encodeJSON(data=variables.errors, preserveArrays=1, preserveArraysRecurseLevels=5));
			}
			
			output = "{" & local.output & "}";
			
			// build and send console headers
			sendHeaders(buildHeaders(splitStrToArray(ToBase64(local.output))));
			
			// increment global output line counter
			request.__firelogger__.counter = request.__firelogger__.counter+1;

			// reset errors collector
			variables.errors = [];
			// reset headers collector
			variables.headers = {};

			if ( variables.debugMode && listFindNoCase("info", variables.debugLevel) ) {
				//var stack = getStackTrace();
				//trace("stack");
				trace(var="output", inline=variables.debugTraceInline);
			}

			return true;
		}
		catch(any e) { 
			// hack: stick args into shared variables scope
			// TODO: don't pollute shared variables scope in case of a fatal error
			if ( ArrayLen(aryObjects) ) {
				arguments.obj = aryObjects[1]; }
			setParameters(arguments);
			panic("Error in log()", e);
			return false;
		}
	}
	
	/**
	 * used by doLog() "proxy" functions warn(), info(), error(), critical()
	 */
	private boolean function logProxy(string type="", required struct args) {
		if ( !StructKeyExists(args, 1) ) { return false; }
		var newArgs = args;
		if ( Len(arguments.type) && !ArrayFindNoCase(variables.levels, args[1]) ) {
			newArgs = {};
			newArgs.1 = type;
			for (var arg in args) {
				newArgs[arg+1] = args[arg];
			}
		}
		newArgs = createObject("java", "java.util.TreeMap").init(newArgs);
		return doLog(argumentCollection=newArgs);
	}
	
	/**
	 * Warning type proxy function for log().
	 * See docs for log().
	 * 
	 * @returns: true if log action succeeded, false otherwise.
	 */
	public boolean function warn() {
		return logProxy("warning", arguments);
	}
	
	/**
	 * info type proxy function for log()
	 * See docs for log().
	 * 
	 * @returns: true if log action succeeded, false otherwise.
	 */
	public boolean function info() {
		return logProxy("info", arguments);
	}
	
	/**
	 * error type proxy function for log()
	 * See docs for log().
	 * 
	 * @returns: true if log action succeeded, false otherwise.
	 */
	public boolean function error() {
		return logProxy("error", arguments);
	}
	
	/**
	 * critical type proxy function for log()
	 * See docs for log().
	 * 
	 * @returns: true if log action succeeded, false otherwise.
	 */
	public boolean function critical() {
		return logProxy("critical", arguments);
	}
	
	/**
	 * Error handler for "soft" errors.  
	 * Can be used to return a special error type header to FireLogger console which
	 * shows up at the top with a red background and expands to show a stack trace.
	 *
	 * Public becaues frelogger.cfm debug template can also use this.
	 *
	 * @msg plain text message to log
	 * @e error object (result of catch)
	 * 
	 */
	public void function err(msg, e=StructNew()) {
		try {
			var i = ArrayLen(variables.errors) + 1;
			var tmpval = formatErrorOutput(arguments.msg, e);
			
			variables.errors[i]["message"] = tmpval.text;
			variables.errors[i]["exc_info"] = tmpval.exc_info;

		}
		catch(any ee){ 
			if ( variables.debugMode && listFindNoCase("error,info", variables.debugLevel) ) {
				trace(var="ee", text=arguments.msg, type="error", category="FireLogger", inline=variables.debugTraceInline, abort=false); 
			}
		}
	}
	
	/**
	 * Handle errors where we can't set a header in response, eg. after output has been flushed or 
	 * if we die while building the output.  Tries to log the original request to the fallback
	 * handler (eg. trace or writedump).
	 *
	 * @msg plain text message to log
	 * @e error object (result of catch)
	 * @output true
	 */
	private void function panic(msg, e=StructNew()) {
		// attempt to log the original message, if any
		if ( StructKeyExists(variables, "obj") OR Len(variables.text) ) {
			switch (variables.fallbackLogMethod) {
				case "trace-inline":
				case "trace":
					var inline = variables.fallbackLogMethod == "trace" ? false : true;
					var type = typeFL2CF(variables.type);
					var text = variables.text;
					
					if ( NOT Len(local.text) AND StructKeyExists(variables, "obj") ) {
						try {
							text = DE(arguments.obj); }
						catch (any ee) { 
							text = ee.message; }
					}
					if ( StructKeyExists(variables, "obj") ) {
						trace(var="variables.obj", text=local.text, type=local.type, category=variables.loggerName, inline=local.inline, abort=false);
					} else {
						trace(text=local.text, type=local.type, category=variables.loggerName, inline=local.inline, abort=false);
					}
					break;
					
				case "dump":
					if ( StructKeyExists(variables, "obj") ) {
						writeDump(variables.obj); }
					else {
						writeDump(variables.text); }
					break;
			}
		}
		if ( variables.debugMode && listFindNoCase("panic,error,info", variables.debugLevel) ) {
			trace(var="arguments.e", text=arguments.msg, type="Fatal Information", category="FireLogger", inline=variables.debugTraceInline, abort=false); 
		}
	}

	/**
	 * Set properties based on passed named arguments, making sure they are allowed to be set. 
	 * 
	 */
	private void function setParameters(struct args, struct target=variables) {
		if( !structIsEmpty(arguments.args) ) {
			for (var a in arguments.args) {
				if ( ArrayFindNoCase(variables.allowedArguments, local.a) ) {
					target[a] = arguments.args[a];
				}
			}
		}
	}
	
	/**
	 * Gets current settable properties from variables scope and returns them as a new structure 
	 * 
	 */
	private struct function getParameters() {
		var result = StructNew();
		for (var a in variables.allowedArguments) {
			if ( StructKeyExists(variables, a) ) {
				result[a] = variables[a];
			}
		}
		return result;
	}
	
	/**
	 * Method to set a firelogger password
	 * 
	 * @output false
	 */
	public boolean function setPassword(required string pass) {
		variables.password = pass;
		return setIsConsoleEnabled();
	}

	/**
	 * Overall check to see if browser console is enabled
	 * 
	 * @output false
	 */
	private boolean function setIsConsoleEnabled() {
		variables.isConsoleEnabled = StructKeyExists(variables.httpRequestData.headers, "X-FireLogger") AND fireloggerPasswordCheck();
		return variables.isConsoleEnabled;
	}

	/**
	 * Returns true/false based on if password is required and, if it is, if it matches the one set in the http headers.
	 * 
	 * @output false
	 */
	private boolean function fireloggerPasswordCheck() {
		return NOT Len(variables.password) OR
				( StructKeyExists(variables.httpRequestData.headers,"X-FireLoggerAuth") 
					AND Hash("##FireLoggerPassword##" & variables.password & "##", "MD5") IS variables.httpRequestData.headers["X-FireLoggerAuth"] );
	}

	/**
	 * Check console logger version against expected version and output warning in the response headers if mismatch.
	 * 
	 * @output false
	 */
	private void function clientVersionCheck() {
		if ( StructKeyExists(variables.httpRequestData.headers, "X-FireLogger") ) {
			var flv = variables.httpRequestData.headers["X-FireLogger"];
			if ( flv IS NOT variables.expectedClientVersion ) {
				err("Your version of the FireLogger extension (#flv#), " & 
						"doesn't match the server-side library version (#variables.expectedClientVersion#). " & 
						( Val(variables.expectedClientVersion) > Val(flv) ) ? "Please update FireLogger at #variables.fireloggerURL#" : "Please update CF FireLogger at #variables.projectURL#");
			}
		}
	}

	/**
	 * Gets the calling template and line number from current stack trace, 
	 * 
	 */
	private array function getCallerFileLine() {
		var result = ['?','?'];
		var tmp = "";
		
		try {
			var j = CreateObject("java", "java.lang.Throwable");
			j = j.getStackTrace();
		
			for(var i = 1; i < ArrayLen(j); i = i + 1) {
				tmp = j[i].getFileName();
				if ( StructKeyExists(local, "tmp") && reFindNoCase("^(?!.*[/\\]firelogger\.(cfm|cfc)$).*[/\\].+\.\w{2,5}$", local.tmp) ) {
					result[1] = local.tmp;
					result[2] = j[i].getLineNumber();
					break;
				}
			}
		}
		catch(any e) {
			err("Error in getCallerFileLine", e); }
		
		return result;

	}
	
	
	/**
	 * Formats the result of an error object (cfcatch).
	 * Returns a structure with 4 members. 
	 * text: is the full message to log.
	 * exc_info: is an array in the proper format for FireLogger stack trace output.
	 * filename: the file with the error (first file in stack trace)
	 * lineno: the line number the actual error occured in (from first entry in stack trace)
	 * 
	 * @output false
	 */
	public struct function formatErrorOutput(text="", e=structNew()) {
		var exc_info = ['','',[]];
		var filename = "";
		var lineno = "?";
		var nl = Chr(13);
		
		try {
							
			if ( !Len(arguments.text) ) {
				arguments.text = "Error details";
			}
			if ( IsDefined("e.message") ) {
				arguments.text = arguments.text & ": " & e.message & ";" & nl; }
			if ( IsDefined("e.type") ) {
				arguments.text = arguments.text & "TYPE: " & e.type & ";" & nl; }
			if ( IsDefined("e.detail") && Len(e.detail) ) {
				arguments.text = arguments.text & "DETAILS: " & ReReplace(e.detail, "<[^>]+>", "", "all") & ";" & nl; }
			if ( IsDefined("e.nativeErrorCode") && Len(e.nativeErrorCode) ) {
				arguments.text = arguments.text & "NATIVE-ERROR-CODE: " & e.nativeErrorCode & ";" & nl; }
			if ( IsDefined("e.sqlState") && Len(e.sqlState) ) {
				arguments.text = arguments.text & "SQL-STATE: " & e.sqlState & ";" & nl; }
			if ( IsDefined("e.sql") && Len(e.sql) ) {
				arguments.text = arguments.text & "SQL: " & e.sql & ";" & nl; }
			/* seems to be same info as in "details"
			if ( IsDefined("e.queryError") && Len(e.queryError) ) {
				arguments.text = arguments.text & "Query-Error: " & e.queryError & ";" & nl; }*/
			if ( IsDefined("e.where") && Len(e.where) ) {
				arguments.text = arguments.text & "WHERE: " & e.where & ";" & nl; }
			if ( IsDefined("e.ErrNumber") && Len(e.ErrNumber) ) {
				arguments.text = arguments.text & "ERR-NUMBER: " & e.ErrNumber & ";" & nl; }
			if ( IsDefined("e.MissingFileName") && Len(e.MissingFileName) ) {
				arguments.text = arguments.text & "MISSING-FILE-NAME: " & e.MissingFileName & ";" & nl; }
			if ( IsDefined("e.LockName") && Len(e.LockName) ) {
				arguments.text = arguments.text & "LOCK-NAME: " & e.LockName & ";" & nl; }
			if ( IsDefined("e.LockOperation") && Len(e.LockOperation) ) {
				arguments.text = arguments.text & "LOCK-OPERATION: " & e.LockOperation & ";" & nl; }
			if ( IsDefined("e.ErrorCode") && Len(e.ErrorCode) ) {
				arguments.text = arguments.text & "ERROR-CODE: " & e.ErrorCode & ";" & nl; }
			if ( IsDefined("e.ExtendedInfo") && Len(e.ExtendedInfo) ) {
				arguments.text = arguments.text & "EXTENDED-INFO: " & e.ExtendedInfo & ";" & nl; }
			
			if ( IsDefined("e.TagContext") && isArray(e.TagContext) && arrayLen(e.TagContext) ) {
				for (var x=1; x <= arrayLen(e.TagContext); x=x+1) {
					exc_info[3][x] = ArrayNew(1);
					exc_info[3][x][1] = e.TagContext[x].template;
					exc_info[3][x][2] = e.TagContext[x].line;
					exc_info[3][x][3] = e.TagContext[x].id;
					exc_info[3][x][4] = Replace(e.TagContext[x].raw_trace, e.TagContext[x].template & ":" & e.TagContext[x].line, "");
				}
				local.filename = e.TagContext[1].template;
				local.lineno = e.TagContext[1].line;
			}
			
		} catch(any ee){ 
			err("Error in formatErrorOutput", ee);
			return { "text" = ee.message, "exc_info"=local.exc_info, "filename" = local.filename, "lineno" = local.lineno };
		}
		
		return { "text" = arguments.text, "exc_info"=local.exc_info, "filename" = local.filename, "lineno" = local.lineno };
	}
	
	
	/**
	 * Builds variables.headers structure of headername:value pairs for the logging output based on the passed-in array of data strings.
	 * 
	 * @output false
	 */
	private void function buildHeaders(array data, string format="firelogger") {
		try {
			// random hex ID for firelogger header, as per specs --->
			var hdrid = formatBaseN(randRange(0, 65535), 16) & formatBaseN(randRange(0, 65535), 16);
			var hdrName = "";
			for (var x=1; x <= arrayLen(arguments.data); x=x+1) {
				hdrName = "FireLogger-" & hdrid & "-" & evaluate(x-1);
				variables.headers[hdrName] = arguments.data[x];
			}
		}
		catch(any e) { 
			panic("Error in buildHeaders", e); 
			//return StructNew(); 
		}
	}

	/**
	 * Sets http headers with the logging output for use by the console.
	 * 
	 * @output false
	 */
	private void function sendHeaders() {
		try {
			var response = getPageContext().getResponse();
			if ( response.isCommitted() ) {
				panic("Cannot send headers after output has been flushed! Header data is in the dump.", data);
				return;
			}
			for ( var hdr in variables.headers ) {
				response.setHeader(hdr, variables.headers[hdr]);
			}
		}
		catch(any e){ 
			panic("Error in sendHeaders", e);
		}
	}

	/**
	 * Splits a string into an array of strings of the specified size.
	 * 
	 * @output false
	 */
	private array function splitStrToArray(string data, numeric size=variables.maxHeaderLength) {
		try {
			return reMatch(".{1,#arguments.size#}", arguments.data);
		}
		catch(any e){ 
			err("Error in splitArray", e); 
			return ArrayNew(1); 
		}
	}
	
	/**
	 * Converts firelogger style logging types (severity levels) to CF types
	 */
	private string function typeFL2CF(string type) {
		switch (arguments.type) {
			case "warning":
			case "error":
				return arguments.type;
			case "critical":
				return "fatal information";
			default:
				return "information";
		}
	}

	/**
	 * Sets the "badge" settings to default. The badge is the colored label that appears on the right
	 * of each logged line in FireLogger.
	 */
	public void function resetLoggerBadge() {
		// logger "badge" settings
		variables.loggerName = "CF";
		variables.loggerBGColor = "##315F81";
		variables.loggerFGColor = "##FFFFFF";
	}
	
	/**
	 * Gets the current stack trace, even if no error was thrown, and returns it in a query.
	 * Removed var e as it breaks in CF9
	 * 
	 * @return Returns a query. 
	 * @author Ivo D. SIlva (aphex@netvisao.pt) 
	 * @version 2, July 1, 2011 
	 */
	 /*  just used for testing during development, not required for daily use.
	function getStackTrace() {
		var j = "";
		var i = "";
		var StackTrace = "";
		
		try {
			j = CreateObject("java", "java.lang.Throwable");
			j = j.getStackTrace();
		
			StackTrace = QueryNew("ClassName,MethodName,NativeMethod,FileName,LineNumber,hashCode");
			QueryAddRow(StackTrace, ArrayLen(j));
		
			for(i = 1; i le ArrayLen(j); i = i + 1) {
				QuerySetCell(StackTrace, 'ClassName', j[i].getClassName(), i);
				QuerySetCell(StackTrace, 'MethodName', j[i].getMethodName(), i);
				QuerySetCell(StackTrace, 'NativeMethod', j[i].isNativeMethod(), i);
				QuerySetCell(StackTrace, 'FileName', j[i].getFileName(), i);
				QuerySetCell(StackTrace, 'LineNumber', j[i].getLineNumber(), i);
				QuerySetCell(StackTrace, 'hashCode', j[i].hashCode(), i);
			}
		}
			catch(any e) {
			return e;
		}
		return StackTrace;
	}
	*/

</cfscript>

<!--- TODO: convert this to script!  'cuz it's prettier. --->
<cffunction 
	access="public" 
	name="encodeJSON" 
	returntype="string" 
	output="true"
	hint="Converts data from CF to structured JSON format.">
		
	<cfargument name="data" type="any" required="Yes" />
	<cfargument name="encodeDepth" type="numeric" required="No" default=0 >
	<cfargument name="stringNumbers" type="boolean" required="No" default=false >
	<cfargument name="formatDates" type="boolean" required="No" default=true >
	<cfargument name="skipKeys" type="string" required="No" default="" >
	<cfargument name="skipKeysRecursive" type="boolean" required="No" default=false >
	<cfargument name="preserveArrays" type="boolean" required="false" default=false>
	<cfargument name="preserveArraysRecurseLevels" type="numeric" required="false" default="2">
	
	<cfif isJSON(arguments.data)>
		<cfreturn arguments.data>
	<cfelseif arguments.encodeDepth GTE variables.maxEncodeDepth>
		<cfreturn '"[maximum serializing depth reached]"'>
	</cfif>
	
	<!---<cfreturn serializeJSON(data, 1)>--->
	
	<!--- VARIABLE DECLARATION --->
	<cfset var jsonString = "" />
	<cfset var tempVal = "" />
	<cfset var tmpStruct = "" />
	<cfset var tmp = "" />
	<cfset var md = "" />
	<cfset var colPos = 1 />
	<cfset var i = 1 />
	<cfset var x = 1 />
	<cfset var y = 1 />
	
	<cfset var ignoreStructKeys = variables.ignoreStructKeys>
	<cfset var ignoreFunctionPrefix = variables.ignoreFunctionPrefix>
	
	<cfset var _data = arguments.data />

	<cfset var recordcountKey = "" />
	<cfset var columnlistKey = "" />
	<cfset var columnlist = "" />
	<cfset var dataKey = "" />
	<cfset var column = "" />
   
	
	<cftry>
    	
		<!--- ARRAY --->
		<cfif IsArray(_data) AND NOT IsBinary(_data)>
			<cfif arguments.preserveArraysRecurseLevels AND arguments.encodeDepth GT arguments.preserveArraysRecurseLevels>
				<cfset arguments.preserveArrays = false>
			</cfif>
			<!--- format arrays as structures with a numeric key (because the output is sorted alphabetically) --->
			<cfset jsonString = ArrayNew(1)>	
			<cfif NOT arguments.preserveArrays>
				<cfset tmp = '"__cftype__":"array"'>
				<cfset ArrayAppend(jsonString, tmp) />
			</cfif>
			<cfloop from="1" to="#ArrayLen(_data)#" index="i">
				<cfset tempVal = encodeJSON( data=_data[i], 
														encodeDepth=arguments.encodeDepth+1, 
														stringNumbers=arguments.stringNumbers, 
														formatDates=arguments.formatDates, 
														preserveArrays=arguments.preserveArrays,
														preserveArraysRecurseLevels=arguments.preserveArraysRecurseLevels ) />
				<cfif NOT arguments.preserveArrays>
					<cfset dataKey = NumberFormat(i, RepeatString("0", Len(ArrayLen(_data))))>
					<cfset tempVal = '"' & dataKey & '":' & tempVal>
				</cfif>
				<cfset ArrayAppend(jsonString, tempVal) />
			</cfloop>
			<cfset tmp = IIf( arguments.preserveArrays, DE("[,]"), DE("{,}") )>
			<cfreturn ListFirst(tmp) & ArrayToList(jsonString, ",") & ListLast(tmp) />
			
		<!--- BINARY --->
		<cfelseif IsBinary(_data)>
			<cfreturn '{"data (B64 encoded; first 1K shown)":"' & Left(ToBase64(_data), 1000) & '","length (bytes)":' & Len(_data) & '}' />
	
		<!--- BOOLEAN --->
		<cfelseif IsBoolean(_data) AND NOT IsNumeric(_data) AND NOT ListFindNoCase("Yes,No", _data)>
			<cfreturn LCase(ToString(_data)) />
			
		<!--- CUSTOM FUNCTION --->
		<cfelseif IsCustomFunction(_data)>
			<cfset md = StructCopy(GetMetaData(_data)) />
			<cfif CompareNoCase(Left(md.name,Len(ignoreFunctionPrefix)),ignoreFunctionPrefix) eq 0>
				<cfreturn "firelogger_ignore_value" />
			<cfelse>
				<!---<cfreturn serializeJSON(md)>--->
		  		<cfset md["__cftype__"] = "CustomFunction">
				<cfif StructKeyExists(md, "parameters") AND IsArray(md.parameters) AND ArrayLen(md.parameters)>
					<cfset tmpStruct = StructNew()>
					<cfloop index="i" from="1" to="#ArrayLen(md.parameters)#">
						<cfif IsStruct(md.parameters[i]) AND StructKeyExists(md.parameters[i], "name")>
							<cfset tmpStruct[md.parameters[i].name] = md.parameters[i]>
				   	</cfif>
					</cfloop>
					<cfset md.parameters = tmpStruct>
				</cfif>
				<cfreturn encodeJSON( md, arguments.encodeDepth+1, arguments.stringNumbers, arguments.formatDates, "name", true ) />
			</cfif>
			
		<!--- NUMBER --->
		<cfelseif IsNumeric(_data) AND NOT REFind("^0+[^\.]",_data)>
		 	<cfreturn SerializeJSON(_data)>
		
		<!--- DATE --->
		<cfelseif IsDate(_data) AND arguments.formatDates AND NOT REFind("^0+[^\.]",_data)>
			<cfreturn '"#DateFormat(_data, "mmmm, dd yyyy")# #TimeFormat(_data, "HH:mm:ss")#"' />
			
		<!--- WDDX --->
		<cfelseif IsWDDX(_data)>
			<cfwddx action="wddx2cfml" input="#_data#" output="tempVal" />
			<cfreturn "{""__cftype__"":""wddx"",""data"":" & encodeJSON( tempVal, arguments.encodeDepth+1, arguments.stringNumbers, arguments.formatDates ) & "}" />
			
		<!--- STRING --->
		<cfelseif IsSimpleValue(_data)>
			<!--- firebug/logger/json parser seems to choke on high ascii characters --->
		 	<cfreturn SerializeJSON(reReplace(_data, "[^\x20-\x7E\x0A\x0D\x09]", Chr(63), "all"))>
		 	<!---<cfreturn SerializeJSON(reReplace(_data, "[^\x20-\x7E\x0D\x09\x80-\xFE]", Chr(254), "all"))>--->
		 	<!---<cfreturn SerializeJSON(reReplace(_data, "[[:cntrl:]]", Chr(254), "all"))>--->
			
		<!--- OBJECT --->
		<cfelseif IsObject(_data)>	
			<cfset md = GetMetaData(_data) />
			<cfset jsonString = ArrayNew(1) />

			<cfif NOT StructCount(md)>
				<!--- java object --->
				<cfset jsonString = ArrayNew(1) />
				<cfset ArrayAppend(jsonString, '"__cftype__":"java class"') />
				
				<!--- get the class name --->
				<cfset ArrayAppend(jsonString,'"CLASSNAME":"' & _data.getClass().getName() & '"') />
				
				<!--- get object method data, this could probabaly use some work --->
				<cfset var methods = _data.getClass().getMethods()>
				<cfset var methodStruct = StructNew() />
				<cfset var methodName = "" />
				<cfloop from="1" to="#ArrayLen(methods)#" index="i">
					<cfset methodName = methods[i].getName()>
					<cfset methodStruct[methodName] = StructNew() />
					<cfset methodStruct[methodName].parameters = ArrayToList(methods[i].getParameterTypes()) />	
					<cfset methodStruct[methodName].returntype = methods[i].getReturnType().getCanonicalName() />
				</cfloop>

				<cfset tempVal = encodeJSON( methodStruct, arguments.encodeDepth+1, arguments.stringNumbers, arguments.formatDates ) />
				
				<cfset ArrayAppend(jsonString,'"METHODS":' & tempVal) />
				
				<!--- get object field data, not getting values --->
				<cfset var fields = _data.getClass().getFields()>
				<cfset var fieldStruct = StructNew() />	
				<cfloop from="1" to="#ArrayLen(fields)#" index="i">
					<cfset fieldStruct[fields[i].getName()] = fields[i].getType().getName() />
				</cfloop>

				<cfset tempVal = encodeJSON( fieldStruct, arguments.encodeDepth+1, arguments.stringNumbers, arguments.formatDates ) />
				
				<cfset ArrayAppend(jsonString,'"FIELDS":' & tempVal) />
				
				<cfreturn "{" & ArrayToList(jsonString,",") & "}" />				
				
			<cfelse>
				<!--- component --->		
				
				<cfset ArrayAppend(jsonString, '"__cftype__":"cf component"') />

				<cfset tempVal = encodeJSON(md, arguments.encodeDepth+1, arguments.stringNumbers, arguments.formatDates, "functions,properties") />
				<cfset ArrayAppend(jsonString, '"META":' & tempVal)>
				<!---<cfset ArrayAppend(jsonString, '"DATA":' & serializeJSON(_data))> --->
	
				<!--- dump the functions, if any --->
			 	<cfset tempVal = '"none"'>
				<cfif StructKeyExists(md, "functions") AND IsArray(md.functions) AND ArrayLen(md.functions)>
					<cfset tmp = StructNew()>
					
					<cfloop index="i" from="1" to="#ArrayLen(md.functions)#">
						<cfif IsStruct(md.functions[i]) AND StructKeyExists(md.functions[i], "name")>
							
							<cfset dataKey = md.functions[i].name>
							<cfset tmp[dataKey] = StructNew()>
						
							<cfloop collection="#md.functions[i]#" item="x">
								<cfif NOT ListFindNoCase("name,parameters", x)>
									<cfset tmp[dataKey][x] = md.functions[i][x]>
								</cfif>
							</cfloop>
							
							<!--- dump the functions parameters, if any --->
							<cfif StructKeyExists(md.functions[i], "parameters") AND IsArray(md.functions[i].parameters) AND ArrayLen(md.functions[i].parameters)>
								<cfset tmpStruct = StructNew()>
								<cfloop index="x" from="1" to="#ArrayLen(md.functions[i].parameters)#">
									<cfif IsStruct(md.functions[i].parameters[x]) AND StructKeyExists(md.functions[i].parameters[x], "name")>
										<cfloop collection="#md.functions[i].parameters[x]#" item="y">
											<cfif NOT ListFindNoCase("name", y)>
												<cfset tmpStruct[md.functions[i].parameters[x].name][y] = md.functions[i].parameters[x][y]>
											</cfif>
										</cfloop>
							   	</cfif>
								</cfloop>
								<cfset tmp[dataKey].parameters = tmpStruct>
							</cfif>
							
						</cfif>
					</cfloop>
					
					<cfset tempVal = encodeJSON( tmp, arguments.encodeDepth+1, arguments.stringNumbers, arguments.formatDates ) />
				</cfif>
				<cfset ArrayAppend(jsonString, '"METHODS (local)":' & tempVal) />
				<!--- /if any functions found in metadata --->

				<!--- try to dump public ("this" scope) variables --->
				<cfset tmpStruct = StructNew()>
			 	<cfset tempVal = '"none"'>
				<cfloop collection="#_data#" item="i">
					<cfset tmp = "">
					<cftry>
						<cfif IsDefined("_data." & i)>
							<cfset tmp = Evaluate("_data." & i)>
						</cfif>
						<cfcatch type="Any">
							<cfset tmp = "[error getting value]">
						</cfcatch>
					</cftry>
					<cfif IsDefined("local.tmp") AND NOT IsCustomFunction(local.tmp)>
						<cfset tmpStruct[i] = local.tmp>
					</cfif>
				</cfloop>
				<cfif StructCount(tmpStruct)>
					<cfset tempVal = encodeJSON( tmpStruct, arguments.encodeDepth+1, arguments.stringNumbers, arguments.formatDates ) />
				</cfif>
				<cfset ArrayAppend(jsonString, '"INSTANCE VARIABLES (''this'' scope)":' & tempVal) />

				<!--- dump property values if any exist --->
				<cfset tmpStruct = StructNew()>
			 	<cfset tempVal = '"none"'>
				<cfif StructKeyExists(md, "properties") AND IsArray(md.properties) AND ArrayLen(md.properties)>
					<cfloop index="i" from="1" to="#ArrayLen(md.properties)#">
						<cfset dataKey = md.properties[i].name>
						<cfset tmp = "">
						
						<cftry>
							<cfif IsDefined("_data.get" & dataKey)>
								<cfset tmp = Evaluate("_data.get" & dataKey & "()")>
							</cfif>
							<cfcatch type="Any">
								<cfset tmp = "[error getting value]">
							</cfcatch>
						</cftry>
						<cfif StructKeyExists(md.properties[i], "type")>
							<cfset dataKey = dataKey & " {" & md.properties[i].type & "}">
						</cfif>
						<cfif IsDefined("tmp")>
							<cfset tmpStruct[dataKey] = tmp>
						<cfelse>
							<cfset tmpStruct[dataKey] = "[undefined]">
						</cfif>
					</cfloop>
					
					<cfif StructCount(tmpStruct)>
						<cfset tempVal = encodeJSON( tmpStruct, arguments.encodeDepth+1, arguments.stringNumbers, arguments.formatDates ) />
					</cfif>
				</cfif>
				<cfset ArrayAppend(jsonString, '"PROPERTIES":' & tempVal) />
				<!--- /if properties were found in metadata --->

				
				<cfreturn "{" & ArrayToList(jsonString, ",") & "}" />
			</cfif>

		<!--- STRUCT --->
		<cfelseif IsStruct(_data)>
			<cfscript>
				jsonString = "";
				if ( !arguments.skipKeysRecursive ) {
					arguments.skipKeys = ""; }
				for (dataKey in _data) {
					if ( NOT ListFindNoCase(ListAppend(local.ignoreStructKeys, arguments.skipKeys), dataKey) ) {
						try {
							tempVal = encodeJSON( _data[dataKey], 
															arguments.encodeDepth+1, 
															arguments.stringNumbers, 
															arguments.formatDates, 
															arguments.skipKeys, 
															arguments.skipKeysRecursive, 
															arguments.preserveArrays, 
															arguments.preserveArraysRecurseLevels );
						} catch(any e) { tempVal = '"[undefined]"'; }
						if ( tempVal neq "firelogger_ignore_value" ) {
							jsonString = ListAppend(jsonString, '"' & jsStringFormat(dataKey) & '":' & tempVal);
						}
					}
				}
				return "{" & jsonString & "}";
			</cfscript>

		<!--- QUERY --->
		<cfelseif IsQuery(_data)>
			
			<!--- Add query meta data --->
			<cfset jsonString = ArrayNew(1) />
			<cfset ArrayAppend(jsonString, '"RECORDCOUNT":' & _data.recordcount & ',') />
			<cfset ArrayAppend(jsonString, '"COLUMNLIST":"' & _data.columnlist & '",') />
			<cfset ArrayAppend(jsonString, '"DATA":') />
			
			<!--- Make query a numbered struct of structures (not an array because we're sorting alphabetically in the output) --->
			<cfset ArrayAppend(jsonString,"{") />
			<cfloop query="_data">
				<cfif _data.CurrentRow GT 1>
					<cfset ArrayAppend(jsonString,",") />
				</cfif>
				<cfset ArrayAppend(jsonString, '"' & NumberFormat(_data.CurrentRow, RepeatString("0", Len(_data.RecordCount))) & '":{') />
				<cfset colPos = 1 />
				<cfloop list="#_data.columnlist#" delimiters="," index="column">
					<cfset tempVal = encodeJSON( _data[column][CurrentRow], arguments.encodeDepth+1, arguments.stringNumbers, arguments.formatDates ) />
					
					<cfif colPos GT 1>
						<cfset ArrayAppend(jsonString,",") />
					</cfif>
					
					<cfset ArrayAppend(jsonString, '"' & jsStringFormat(column) & '":' & tempVal) />
					
					<cfset colPos = colPos + 1 />
				</cfloop>
				<cfset ArrayAppend(jsonString, "}") />
			</cfloop>
			<cfset ArrayAppend(jsonString, "}") />
			
			<!--- Wrap all query data into an object --->
			<cfreturn "{" & ArrayToList(jsonString,"") & "}" />
			
		<!--- XML DOC --->
		<cfelseif IsXMLDoc(_data)>
			<cfset jsonString = ArrayNew(1) />
			<cfset ArrayAppend(jsonString,"""__cftype__"":""xmldoc""") />
			<cfset arKeys = ListToArray("XmlComment,XmlRoot") />
			<cfloop from="1" to="#ArrayLen(arKeys)#" index="i">			
				<cfif ListFindNoCase(ignoreStructKeys, arKeys[i]) eq 0>
					<cfset tempVal = encodeJSON( _data[ arKeys[i] ], arguments.encodeDepth+1, arguments.stringNumbers, arguments.formatDates ) />
					<cfif tempVal neq "firelogger_ignore_value">
						<cfset ArrayAppend(jsonString, '"' & jsStringFormat(arKeys[i]) & '":' & tempVal) />
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
					<cfset tempVal = encodeJSON( _data[ arKeys[i] ], arguments.encodeDepth+1, arguments.stringNumbers, arguments.formatDates ) />
					<cfif tempVal neq "firelogger_ignore_value">
						<cfset ArrayAppend(jsonString, '"' & jsStringFormat(arKeys[i]) & '":' & tempVal) />
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
					<cfset tempVal = encodeJSON( _data[ arKeys[i] ], arguments.encodeDepth+1, arguments.stringNumbers, arguments.formatDates ) />
					<cfif tempVal neq "firelogger_ignore_value">
						<cfset ArrayAppend(jsonString, '"' & jsStringFormat(arKeys[i]) & '":' & tempVal) />
					</cfif>
				</cfif>			
			</cfloop>				
			<cfreturn "{" & ArrayToList(jsonString,",") & "}" />
		
		<!--- UNKNOWN OBJECT TYPE --->
		<cfelse>
			<cfreturn "{""__cftype__"":""unknown""}" />	
		</cfif>  
		  
	<cfcatch type="Any" >
		   <cfset err("Error serializing value", cfcatch)>
			<cfreturn '"[error occured while trying to serialize this value]"' />
		</cfcatch>
	</cftry>

</cffunction>

</cfcomponent>