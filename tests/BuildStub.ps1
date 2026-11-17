param([string]$Output)
Add-Type -TypeDefinition 'using System; public class Stub { public static int Main(string[] args) { foreach(string a in args) { Console.WriteLine(a); if(a == "--fail") return 7; } return 0; } }' -Language CSharp -OutputAssembly $Output -OutputType ConsoleApplication
