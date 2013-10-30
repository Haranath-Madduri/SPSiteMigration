
# $filename must be defined before this line. If it is not - you are refrencing the template, not a functional script.

. .\SPSiteMigration-Globals.ps1										# We'll need scripts dot-sourced, and globals created if we are on another thread

Function Map-WorkItemToFunctionParameters
{
    param([parameter(Mandatory = $true)] [string] $FunctionName,
            [parameter(Mandatory = $true)] [PSObject] $Workitem)

    try
    {
        $parameters = (Get-Command $FunctionName |ForEach-Object{$_.Parameters}).GetEnumerator() | % { $_.key}
	    $hashtable = @{}
	    $parameters | % `
	    { 
		    if ( $($Workitem.psobject.Properties | % { if($_.Value -ne $null){$_.name }}) -contains $_ )
	        {
	            $hashtable.$_ = $Workitem.$_ 
	        }
	    }
    }
    catch [Exception]
    {
        $errorMesssage = "`nThere was a problem getting parameters for the function '" + $step.Name + "'"
        write-error $errorMesssage -Category InvalidOperation
        write-error $($_.Exception.Message)
        return $null
    }
    return $hashtable
}

Function Execute-FailureSequence
{
    param(  [parameter(Mandatory = $true)] [string] $FailureSequenceName,
            [parameter(Mandatory = $true)] [PSObject] $Workitem)

    write-host "   [Performing Failure Sequence '$FailureSequenceName']:"

    Read-MigrationAutomationConfiguration
    $FailureSequence = $Global:FailureSequences.Failuresequence | ? {$_.Name -eq $FailureSequenceName}

    if($FailureSequence -eq $null)
    {
        Write-Error ("The failure sequence " + $FailureSequenceName + " does not exist!  Fix the SPSiteMigration-Configuration.xml file") -Category ObjectNotFound
        return $false
    }

    try
    {
        foreach($step in $FailureSequence.Step)
        {
            # Don't keep track of retries of Failure Sequences returned in $RetVal[1]:
            $RetVal = Execute-AutomationStep -step $step -Workitem $Workitem
            if($RetVal[0] -eq $false)
            {
                return $false
            }
        }
    }
    catch [Exception] # TODO: Handle better
    {
        return $false
    }
    return $true
}

Function Execute-AutomationStep
{
    param([parameter(Mandatory = $true)] [System.Xml.XmlElement] $step,
            [parameter(Mandatory = $true)] [PSObject] $Workitem)
    write-host "    Executing step '$($step.Name)' - $($(get-date).ToUniversalTime()) UTC"
    $TryNum 		= 0
    $MaxAttempts 	= 1
    $Delay 			= 0

	if($step.Retry -ne $null)
    {
        $MaxAttempts = $($step.Retry -as [int]) + 1
    }
    if($step.DelaySeconds -ne $null)
    {
        $Delay = $($step.DelaySeconds -as [int])
    }
    $hashtable = Map-WorkItemToFunctionParameters -FunctionName $step.Name -Workitem $Workitem
    # TODO: Need to keep from executing this sequence again in the XML... until it's fixed.
	if($hashtable -eq $null)
    {
        if($step.FailureSequence -ne $null)
        {
            Execute-FailureSequence -FailureSequenceName $step.FailureSequence -Workitem $Workitem | Out-Null
        }
        return $false, $TryNum # Return false because the script or XML needs to be debugged
    }
    try
    {
        # If the XML has some text parameters - pass them to the Function as well:
        if($step.Parameters -ne $null)
	    {
		    foreach($param in $step.Parameters.Split(','))
		    {
			    $keyval = $param.Split(' ')
			    if($keyval.count -gt 1)
			    {
                    $expandedstring = $ExecutionContext.InvokeCommand.ExpandString($keyval[1])
				    $hashtable.Add($keyval[0], $expandedstring)
			    }
		    }
	    }
    }
    catch [Exception] # TODO: Need to keep from executing this sequence again in the XML... until it's fixed.
    {
        $errorMesssage = "`nThere was a problem resolving the XML parameters for the function '" + $step.Name + "'"
        write-error $errorMesssage -Category InvalidOperation
        write-error $($_.Exception.Message);
        if($step.FailureSequence -ne $null)
        {
            Execute-FailureSequence -FailureSequenceName $step.FailureSequence -Workitem $Workitem | Out-Null
        }
        return $false, $TryNum
    }

    trap [Exception] 
    {
        write-host ("    The step '" + $step.Name + "' had an Exception:")
        $err = $_.Exception
        write-error $err.Message
        while ( $err.InnerException )
        {
            $err = $err.InnerException
            write-error $err.Message
        };
        continue;
    }
    # Set the current UTC time before we pass the parameters to the step:
    if($Workitem.Auto_StepStartTimeUTC -ne $null)
    {
        $Workitem.Auto_StepStartTimeUTC = $(get-date).ToUniversalTime()
    }
    # Start with a fresh retry count even if the script was restarted:
    for(; $TryNum -lt $MaxAttempts; $TryNum++)
    {
        $Workitem.Auto_LastRetryCount = $TryNum
        if($Delay -gt 0)
        {
            write-host "Delaying for" $Delay "seconds" -NoNewline
            Sleep $Delay
            write-host " -completed"
        }
        $retVal = & $step.Name @hashtable # Start the Step!
        if($retVal -eq $null)
        {
            write-error ("The step '" + $step.Name + "' failed to return a value.")
            $retVal = $false
        }
		if($retVal[$retVal.Count-1] -eq $true) # It's possible that there could be multiple results.  Choose the last one.
        {
            write-host "                   '$($step.Name)' - completed successfully."
            return $true, $TryNum
        }
        write-error ("The step '" + $step.Name + "' failed")
    }
    # Start the failure sequence if it's needed and is configured:
	if($step.FailureSequence -ne $null)
	{
        Execute-FailureSequence -FailureSequenceName $step.FailureSequence -Workitem $Workitem | Out-Null
	}
    return $false, $($TryNum -1)
}

$host.ui.rawui.WindowTitle 	= $WindowName
$script 					= $filename + ".ps1"
$data 						= $filename + ".xml"

$XMLfileArray 				= Import-Clixml $data
if($XMLfileArray.Count -gt 1)
{
    $Sequence 				= $XMLfileArray[0]
    $global:Workitem 		= $XMLfileArray[1]
    $Steps 					= $Sequence.MigrationSequence.SelectNodes("Step")		# Create a list of steps
    $RetVal 				= $true

    # If there was a catastrophic failure, it will start from something other than 0:
    for ($x = [int] $Sequence.MigrationSequence.StepNumber; $x -lt $Steps.Count;)
    {
        $RetVal = Execute-AutomationStep -step $Steps.Item($x) -Workitem $global:Workitem
        if($RetVal[0] -eq $false)
        {
            write-host
            break
        }
        $x++
        $Sequence.MigrationSequence.StepNumber 	= $x.ToString()
        $global:Workitem.Auto_LastRetryCount 	= $RetVal[1]
	    Export-CliXML -InputObject ($Sequence, $global:Workitem) -Path $data
        write-host
    }
    if($RetVal -eq $true)
    {
        write-host "   [Sequence Completed at $($(get-date).ToUniversalTime()) UTC]`r`n"
        Remove-Item $data
        Remove-Item $script
    }	
    $global:Workitem		= [PSObject] $null

} # TODO: else give an error

$host.ui.rawui.WindowTitle	= "Windows PowerShell"
