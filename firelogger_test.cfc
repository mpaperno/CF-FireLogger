component  hint="I'm just a test." output="true" 
{
	remote void function init()
	 output="true"
	{
		this.myArray = ['one','two','three'];
		trace(var="this.myArray", category="AJAX");
		writeOutput("Hello World!");
	}

}