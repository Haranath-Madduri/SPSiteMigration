
# $filename must be defined before this line. If it is not - you are refrencing the template, not a functional scrip.

. .\SPSiteMigration-Globals.ps1										# We'll need scripts dot-sourced, and globals created if we are on another thread

Function Execute-FailureSequence
{
    param(  [parameter(Mandatory=$true)] [string] $FailureSequenceName,
            [parameter(Mandatory=$true)] [PSObject] $Workitem)

    Read-MigrationAutomationConfiguration
    $FailureSequence = $Global:FailureSequences.Failuresequence.Where({$_.Name -eq $FailureSequenceName}, 1)
    foreach($step in $FailureSequence.Step)
    {
        trap [Exception] { 
            write-error $($_.Exception.Message);

            # TODO: Need to report the exception!

            return $false                           # Don't try again.
        }

        # TODO: make this a method since it's used twice:
        write-host "    Starting Failure step $($step.Name)"
	    $hashtable = @{} 
        try
        {
            $parameters = (Get-Command $step.Name |ForEach-Object{$_.Parameters}).GetEnumerator() | % { $_.key}
	        $parameters | % `
	        { 
		        if ( $($Workitem.psobject.Properties | % { if($_.Value -ne $null){$_.name }}) -contains $_ ) 
	            { 
    
	                $hashtable.$_ = $Workitem.$_ 
	            }
	        }
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
        catch [Exception]
        {
            # TODO: Need to keep from executing this sequence again in the XML... until it's fixed.
            $errorMesssage = "`nThere was a problem getting parameters for the function '" + $step.Name + "'"
            write-error $errorMesssage -Category InvalidOperation
            return
        }
	    $retVal = & $step.Name @hashtable
	    if($retVal -eq $false)
	    {
            if($step.FailureSequence -ne $null)
            {
                if((Execute-FailureSequence $step.FailureSequence $Workitem) -eq $true)
                {
                    return $false # TODO: Add a retry count
                }
            }
            return $false
	    }
    }
    return $false
}

$script 	= $filename + ".ps1"
$data 		= $filename + ".xml"

$fileArray 	= Import-Clixml $data
if($fileArray.Count -lt 2)
{
	return false 													# TODO: give an error
}
$Sequence 	= $fileArray[0]
$Workitem 	= $fileArray[1]
$Steps 		= $Sequence.MigrationSequence.SelectNodes("Step")		# Create a list of steps

# If there was a catastrophic failure, it will start from something other than 0:
for ($x = [int] $Sequence.MigrationSequence.StepNumber; $x -lt $Steps.Count;)
{
    trap [Exception] { 
        write-error $($_.Exception.Message);
        if($step.FailureSequence -ne $null)
        {
            if((Execute-FailureSequence $step.FailureSequence $Workitem) -eq $true)
            {
                write-host
                return # TODO: Add a retry count
            }
        }
        write-host
        return
    }
	$step = $Steps.Item($x)
	write-host "    Starting step $($step.Name)"
	$parameters = (Get-Command $step.Name |ForEach-Object{$_.Parameters}).GetEnumerator() | % { $_.key}
	$hashtable = @{} 
    $retVal = $false
    try
    {
	    $parameters | % `
	    { 
		    if ( $($Workitem.psobject.Properties | % { if($_.Value -ne $null){$_.name }}) -contains $_ ) 
	        {
	            $hashtable.$_ = $Workitem.$_ 
	        }
	    }
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
    catch [Exception]
    {
        $errorMesssage = "`nThere was a problem getting parameters for the function '" + $step.Name + "'"
        write-error $errorMesssage -Category InvalidOperation
        write-error $($_.Exception.Message);
        if($step.FailureSequence -ne $null)
        {
            if((Execute-FailureSequence $step.FailureSequence $Workitem) -eq $true)
            {
                write-host
                return # TODO: Add a retry count
            }
        }
        write-host
        # TODO: Need to keep from executing this sequence again in the XML... until it's fixed.
        return
    }
	$retVal = & $step.Name @hashtable
	if($retVal -eq $false)
	{
        write-error "The step" $step.Name "Failed"
        if($FailedStep.FailureSequence -ne $null)
        {
            if((Execute-FailureSequence $step.FailureSequence $Workitem) -eq $true)
            {
                write-host
                return # TODO: Add a retry count
            }
        }
        return
	}
	$x++
	$Sequence.MigrationSequence.StepNumber = $x.ToString()
	Export-CliXML -InputObject ($Sequence, $Workitem) -Path $data
    write-host
}

Remove-Item $data
Remove-Item $script

