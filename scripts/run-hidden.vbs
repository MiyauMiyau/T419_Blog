Option Explicit

' Task Scheduler starts wscript without a console. Run the original command
' hidden, wait for completion, and return its exit code to Task Scheduler.
Dim arguments, shell, command, index, exitCode
Set arguments = WScript.Arguments
If arguments.Count < 1 Then WScript.Quit 2

Set shell = CreateObject("WScript.Shell")
command = Quote(arguments.Item(0))
For index = 1 To arguments.Count - 1
    command = command & " " & Quote(arguments.Item(index))
Next

exitCode = shell.Run(command, 0, True)
WScript.Quit exitCode

Function Quote(value)
    Quote = Chr(34) & Replace(value, Chr(34), Chr(34) & Chr(34)) & Chr(34)
End Function
