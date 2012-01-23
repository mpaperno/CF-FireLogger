<html>
	<head>
		<title>CF FireLogger Test Page</title>
	</head>
	<body>
		<h1>CF FireLogger Test Page</h1>

<!--- show variables scope in debug info dump 
	(this is a firelogger debug template setting, not required to use firelogger.cfc)
 --->
<cfset request.firelogger_debug.varlist = ['variables']>

<!--- test timer tracing in debug output --->
<cftimer label="myTestTimer" type="debug">

<cfscript>

// instantiate the logger.
// all arguments are optional.
// for complete list of arguments, see cfc docs.
console = new firelogger(debugMode=false, debugLevel="info", fallbackLogMethod="trace-inline");

try {
	//define some stuff to dump
	for (i=1; i <= 5; i=i+1) { myArray[i] = "this is " & i;	}
	myStruct = {"a"=1,"b"=2,"c"='orange',"d"=myArray};
	
	// simple message log of info type
	console.log("info", "First message from CF-Firelogger!");
	
	// if form is submitted dump form fields and uploaded file in binary mode
	if (IsDefined("form.textfield")) {
		// test dumping binary data
		if ( Len(form.fileupload) ) {
			uploadedFile = fileReadBinary(form.fileupload);
			trace("uploadedFile", "Binary file dump");
			try {fileDelete(form.fileupload);} catch (any e) {trace("e.message");}
		}
		trace("form");
	}
	
	// output a simple value variable and an array
	a = console.getdebugMode();
	console.log("CF-Firelogger debugMode is: #a#; myArray is:", myArray );
	// default log type when using firelogger.cfc is "debug"
	
	// we won't see this message unless we have specified a password in FireLogger preferences
	console.setPassword("testpass");
	console.log("Can't see this cuz you have no password set in firelogger console.");
	console.setPassword("");
	
	// test with a custom badge label and colors
	a = RandRange(0,1);
	color = (a == true) ? "green" : "red";
	// using the standard trace category attribute to pass a label and color for the badge
	trace(text="Random result: #a#", category="CF,#color#");
	
	// default log type when using trace is "info".  
	// There's no way to get a "debug" type since cftrace doesn't support it.
	
	// log multiple objects at once, with optional string expansion
	console.log("myStruct: %s; myArray: %s", myStruct, myArray );
	// could also just list the objects...
	// console.log(myStruct, myArray, myWhatever, .... );
	
	// costom badge name/colors
	console.setLoggerName("George");
	console.setLoggerBGColor("orange");
	console.setLoggerFGColor("##292929");
	
	console.log("info", "This is a message from George!");
	
	// reset badge formatting
	console.resetLoggerBadge();
	
	// shortcut methods for log types (default type with log() is "debug")
	console.info("Back to the default badge.");
	console.warn("This is a warning!");
	console.error("This is an error!");
	console.critical("This is a critical error!");
	
	// trace thyself
	trace("console", "This is my logger", "warning");

	// cause an exception
	udf_one(10, 'test');

	// dump one of our UDFs
	trace("udf_one", "This is a UDF");

	// test a java object. Lots of data!
	/*
	testJavaObj = CreateObject("java", "java.lang.Throwable");
	//testJavaObj = testJavaObj.getStackTrace();
	trace("testJavaObj");
	*/


	// load this file to show source code
	source = fileRead(GetTemplatePath());
}
catch (any e) {
	writeDump(e);
}

// test functions
/**
 * This is a test function.  This is a test of metadata output.
 *
 * @author Santa Claus
 * @output false
 * @arg1 This is the first argument
 * @arg2 Another argument
 */
function udf_one(required numeric arg1, string arg2="test") {
	udf_second(TRUE);
}
function udf_second(arg1) { 
	try {
		throw(type="customTestError" message="This is a test exception!"); 
		//udf_third();
	} 
  	catch(any e) { 
  			//console.log("error", "got an error in udf_second()", e);
  			trace("e", "got an error in udf_second()", "error"); 
  	}
}
</cfscript>

<!--- test with a cftrace tag --->
<cftrace var="myStruct" type="warning" 
			text="This is my last trace!" 
		 	category="My Test,silver,black"
		 	inline="false" abort="false">

</cftimer>

	<p>This page will produce output in Firebug/FireLogger console if that is enabled.  
	It uses two methods to log output: one is the native firelogger.cfc log() function, 
	which will work for a basic install, and the other uses the extended "trace.cfm" custom 
	template which is part of the optional CF-FireLogger installation.  If you are not using the 
	custom trace.cfm then you will not see cftrace/trace() output in the console 
	(it will still be available via the debug dump and log file, as usual).</p>

	<form action="test.cfm" method="post" enctype="multipart/form-data" accept-charset="utf-8">
		<p><label style="float:left;">Text Field: &nbsp;</label>
			<input type="text" name="textField" size="30"></p>
		<p><label style="float:left;">Text Area: &nbsp;</label>
			<textarea name="textArea" cols="30" rows="3"></textarea></p>
		<p><label style="float:left;">File: &nbsp;</label>
			<input type="file" name="fileUpload" size="30"></p>
		<p><input type="submit" value="Test" /></p>
	</form>

	<p>Source of this file:
		<div style="width: 95%; height: 400px; overflow: auto; border: 1px solid gray; padding: 10px;">
			<pre><cfoutput>#HtmlEditFormat(source)#</cfoutput></pre>
		</div>
	</p>
	</body>
</html>