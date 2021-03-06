# This PowerShell script must be .sourced before it can be run.
# Example: ". .\SPSiteMigratopn.ps1"

$global:SPSGlobalsSet 				= $false													# Any time this script is dot-sourced - reset everything

. .\SPSiteMigration-Globals.ps1

function execute-function_thread
{
  [CmdletBinding()]
	param(	[parameter(Mandatory = $true)] [System.Xml.XmlElement] $Sequence,
			[parameter(Mandatory = $true)] [System.Data.DataRow] $Workitem )
	
	write-host "   [Performing '$($Sequence.Name)' sequence for $($Workitem.SourceURL)] - $($(get-date).ToUniversalTime()) UTC"
    $workitem.WorkitemState = "Running " + $Sequence.Name + " sequence" 						# Keep other triggers from finding this workitem by changing the WorkitemState.


    if($(Read-MigrationAutomationConfiguration) -eq $false)
    {
        return
    }

    $MultiThreaded = $false
    $Logging = $false
    if($global:GlobalSettings.AutomationData -ne $null)
    {
        if($global:GlobalSettings.AutomationData.MultiThreaded -eq "true")
        {
            $MultiThreaded = $true
        }
        if($global:GlobalSettings.AutomationData.Logging -eq "true")
        {
            $Logging = $true
        }
    }
	if($(Test-Path jobs) -eq $false)
	{
		new-item jobs -itemtype directory
	}
	
    # Need a place to put log files:
	if($(Test-Path logs) -eq $false)
	{
		new-item logs -itemtype directory
	}

	# Create filenames for the script, XML, and log:
    $WindowName 						= "WorkItem_" + $Workitem.WorkitemId.ToString() + "-" + $Sequence.Name
	$logfilename 						= ".\logs\" + $WindowName + ".txt"
    $filename 							= ".\jobs\" + $WindowName
	$script 							= $filename + ".ps1"
	$data 								= $filename + ".xml"
    $scriptExists 						= Test-Path $script
    $dataExists 						= Test-Path $data
    if($scriptExists -eq $false -or $dataExists -eq $false)
    {
	    # Create a StepNumber attribute to keep track of the current step:
	    $owner 							= $Sequence.OwnerDocument
	    $StepNumAttibute 				= $owner.CreateAttribute("StepNumber")
	    $StepNumAttibute.InnerText 		= "0"														# Set the StepNumber to the first item
	    $Sequence.Attributes.Append($StepNumAttibute) | out-Null

	    # Create XML based on a small section of SPSiteMigration-Configuration.xml
	    $Tempxml 						= New-Object xml
	    $fragment 						= $Tempxml.CreateDocumentFragment()
	    $fragment.innerxml 				= $Sequence.OuterXml
	    $Tempxml.AppendChild($fragment)  | out-Null

        # Set the starting time for the whole sequence:
        if($Workitem.Auto_SequenceStartTimeUTC -ne $null)
        {
            $Workitem.Auto_SequenceStartTimeUTC = $(get-date).ToUniversalTime()
        }

	    Export-CliXML -InputObject ($Tempxml, $Workitem) -Path $data								# Output the XML file for disaster recovery
	
	    # Create a unique script file from a template:
	    $template 						= Get-Content "SPSiteMigration-ExecuteSequenceTemplate.ps1"
	    '$filename 						= ' + "`"$filename`"" | Out-File $script					# Put the filname at the top of the new script
        '$WindowName 					= ' + "`"$WindowName`"" | Out-File $script -Append 
        if($MultiThreaded -eq $true -and $Logging -eq $true)
        {
            'Start-Transcript -Append -Path '+ $logfilename | Out-File $script -Append 
        }
	    $template | Out-File $script -Append 														# Append the contents of SPSiteMigration-ExecuteSequenceTemplate.ps1 to the script
    }
    else
    {
        # If both the script and XML already exist:
        $runningProc = Get-Process -Name powershell | Where-Object -FilterScript {$_.MainWindowTitle -eq $WindowName}

        # Check if the processes is still running:
        if($runningProc -ne $null)
        {
            # TODO: Put some logic around how long the process has been running: $runningProc.StartTime
            #            Maybe kill it and/or change the status if it's too long.
            return
        }
    }

    if($MultiThreaded -eq $true)
    {
        $arguments 					= "-file $script"
	    $procInfo 					= Start-Process PowerShell.exe -ArgumentList $arguments -PassThru	# Executes the Script in Seperate Process
		
		# Save the process info so that we can find and regulate script threads:
		$objProc 					= New-Object System.Object
		$objProc | Add-Member -type NoteProperty -name windowname -value $WindowName
		$objProc | Add-Member -type NoteProperty -name WebAppID -value $Workitem.WebAppId
		$objProc | Add-Member -type NoteProperty -name ProcessID -value $procInfo.Id
		$global:RunningProcesses 	+= $objProc

		sleep -Seconds 2 																			# Sleep for 2 seconds to give the process some time to spin up.
    }
    else
    {
	    &$script																					# Execute the script on this thread
    }
}

function Get-NumberOfActiveSequences
{
    param([parameter(Mandatory = $true)] [Guid] $WebAppID)

    $runningProcs = Get-Process -ErrorAction Ignore -Name powershell

    if($runningProcs -eq $null -or $runningProcs.Count -lt 2)		# If this is the only process, no scripts are running.
    {
		$global:RunningProcesses.Clear()
        return 0
    }
	
	# Clean up memory using the running process information:
	$NewRunningProcesses 	= @()
	foreach($memproc in $runningProcs)
	{
		$runningTask = $global:RunningProcesses | ? {$_.ProcessID -eq $memproc.Id}
		if($runningTask -ne $null)
		{
			if($runningTask.Count -gt 1)
			{
				$NewRunningProcesses += $runningTask[0]
			}
			else
			{
				$NewRunningProcesses += $runningTask
			}
		}
	}
	$global:RunningProcesses.Clear()							# We will replace the data
	
	# Clean up memory using the file system to determine what might be running:
	if($(Test-Path jobs) -eq $true)
	{
		$scripts 				= Get-ChildItem .\jobs | where {$_.extension -eq ".xml"}
	    foreach($script in $scripts)							# Look for the scripts on the file system, as they must exist for a process to exist
	    {
			$runningTask		= $NewRunningProcesses | ? {$_.windowname -eq $script.BaseName}
			if($runningTask -ne $null)
			{
				if($runningTask.Count -gt 1)
				{
					$global:RunningProcesses += $runningTask[0]
				}
				else
				{
					$global:RunningProcesses += $runningTask
				}
			}
		}
	}
	$WebAppProcs = $global:RunningProcesses | ? {$_.WebAppId -eq $WebAppID}
	return $WebAppProcs.Count
}

  <#
  .SYNOPSIS
  Deletes dead migration automation jobs for a given WebAppID.
  .DESCRIPTION
  Over time jobs may die or fail and administrators or other automation may complete the sequences.  When this 
  happens, the jobs folder becomes cluttered with dead scripts.
  Only jobs related to the WebAppID, and not running, and do not appear in the list of WorkItmes will be deleted.
  .EXAMPLE
  Delete-LocalDeadJobs -WebAppID ABD0F041-DB37-4010-83E8-8FD4915A2864 -WorkItems $WorkItemDataTable
  #>
function Delete-LocalDeadJobs
{
    param(  [parameter(Mandatory = $true)] [Guid] $WebAppID,
            [parameter(Mandatory = $true)] [Data.DataTable] $WorkItems)

	# There is a chance that a human will intervene with the process and cause this to be needed:
	if($(Test-Path jobs) -eq $true)
	{
	    $XMLs 				= Get-ChildItem .\jobs | where {$_.extension -eq ".xml"}
	    $runningProcs 		= Get-Process -ErrorAction Ignore -Name powershell

	    foreach($XMLFile in $XMLs)																	# Look for the scripts on the file system, as they must exist for a process to exist
	    {
	        $FileArray 		= Import-Clixml $XMLFile.FullName
	        $FileWorkItem 	= $FileArray[1]

	        # Only consider deleting files when we have the list of workitems:
	        if($FileWorkItem.WebAppId -eq $WebAppID)
	        {
	            # If the WorkitemId is no longer in the list of valid workitems - it's safe to delete:
	            if($($WorkItems | where {$_.WorkitemId -eq $FileWorkItem.WorkitemId}) -eq $null)
	            {
	                # Don't delete anything that's currently running, even if there is no workitem.  It may have changed its own status:
	                if($($runningProcs | ? {$_.MainWindowTitle -eq $XMLFile.BaseName}) -eq $null)
	                {
	                    Remove-Item $($XMLFile.DirectoryName + "\" + $XMLFile.BaseName + ".ps1")
	                    Remove-Item $XMLFile.FullName
	                    Write-Host "    Removed Dead Job:" $XMLFile.BaseName
	                }
	            }
	        }
	    }
	}
}

Function Stop-AutomationTranscript
{
	if($global:GlobalSettings -ne $null)
	{
	   	if($global:GlobalSettings.AutomationData -ne $null)
	    {
	        if($global:GlobalSettings.AutomationData.Logging -eq "true")
	        {
	            # Stop the transcript if it's running to keep from capturing user commands in the logs:
	            $externalHost = $host.gettype().getproperty("ExternalHost", [reflection.bindingflags]"NonPublic,Instance").getvalue($host, @())
	            if($externalHost.gettype().getproperty("IsTranscribing", [reflection.bindingflags]"NonPublic,Instance").getvalue($externalHost, @()) -eq $true)
	            {
	                Stop-Transcript
	            }
	        }
	    }
	}
}

  <#
  .SYNOPSIS
  Gathers records from the coordinator database, and runs a sequence of steps on each workitem.
  .DESCRIPTION
   Start-Sequences is the main funtion for starting all migration automation.  It will run through a list of 
   workitems and exit. It is necessary to edit and configure the SPSiteMigration-Configuration.XML and coordinator 
   database before using this for the first time.
  .EXAMPLE
  Start-Sequences
  #>
function Start-Sequences
{
    Param( [parameter(Mandatory = $false)] [bool] $ConfirmBeforeStarting )

    if($(Read-MigrationAutomationConfiguration) -eq $false)
    {
        return
    }

    # Add days to the current date so that we get of list of items which have not hit the starting migration date:
    $DaysInAdvanceCount = 0
	
    if($global:GlobalSettings.AutomationData -ne $null)
    {
		if($global:GlobalSettings.AutomationData.Logging -eq "true")
        {
        	$externalHost = $host.gettype().getproperty("ExternalHost", [reflection.bindingflags]"NonPublic,Instance").getvalue($host, @())
	        if($externalHost.gettype().getproperty("IsTranscribing", [reflection.bindingflags]"NonPublic,Instance").getvalue($externalHost, @()) -eq $false)
			{
			    # Need a place to put log files:
				if($(Test-Path logs) -eq $false)
				{
					new-item logs -itemtype directory
				}
				if($global:GlobalSettings.AutomationData.MultiThreaded -ne "true")
				{
	                Start-Transcript -Append -Path ".\logs\CumulativeResults.txt"						# Append, as you'll want migration logs.
				}
				else
				{
	                Start-Transcript -Append -Path ".\logs\ProcessingEngine.txt"						# Don't append if you want to save space.
				}
			}
        }
        if($global:GlobalSettings.AutomationData.DaysInAdvance -ne $null)
        {
            $DaysInAdvanceCount = $global:GlobalSettings.AutomationData.DaysInAdvance -as [int32]
        }
        if($GlobalSettings.AutomationData.DBSettingsSynced -eq $null)
        {
            Set-ScheduledAutomationRates																# Will only happen once.
        }
    }
	
    $numSeqStarted 			= 0
	do
	{
	    $todaysDate 		= get-date
	    $DateToSearch 		= $todaysDate.AddDays($DaysInAdvanceCount)
		$RuningAutomation 	= $false
		
	    if($global:GlobalSettings.AutomationData -ne $null)
	    {
            $LastSync 		= $GlobalSettings.AutomationData.DBSettingsSynced -as [DateTime]
            if(($LastSync.AddHours(24) -le $todaysDate  -or $todaysDate.Day -ne $LastSync.Day) -and $LastSync -lt $todaysDate)	# The rates may change daily.
            {																							# If the sync date is the future, leave the schedule alone.
                Set-ScheduledAutomationRates															# When the date changes or is old, put the new settings in 
            }
	    }		
	    foreach($MigrationAutomation in $global:AutomationNodesXML)										# Looping through Nodes first so that we can order the events
	    {																								# 	Workitems nearing completion will be executed before others.
	        $WorkItems 		= Read-CurrentWorkItems -FarmUrl $MigrationAutomation.FarmName -WorkDate $DateToSearch.ToUniversalTime()
	        $WebAppID 		= New-object Guid($MigrationAutomation.WebAppID)

	        Delete-LocalDeadJobs $WebAppID $WorkItems.Tables[0]
			if($(Get-NumberOfActiveSequences -WebAppID $WebAppID) -gt 0)								# Sequences from a previous loop are still running.
			{
				$RuningAutomation = $true
				sleep -Seconds 10																		# Give the previous sequences some time to complete.
			}
			$MigrationSequences = $MigrationAutomation.SelectNodes("MigrationSequence")					# Make sure we have an array, so we can iterate through it backwards
			for($x = $MigrationSequences.Count-1; $x -ge 0 -and $x -lt $MigrationSequences.Count; $x--)	# It's possible the XML could be manually edited/changed while the loop is running.
			{
				foreach($workitemTable in $WorkItems.Tables)
				{
					# Add columns to pass automation data to the sequence threads:
	                if($workitemTable.Columns.Contains("Auto_SequenceStartTimeUTC") -eq $false)			# Just check one.  If it's there, so are the others.
	                {
	                    $workitemTable.Columns.Add("Auto_SequenceStartTimeUTC", [DateTime]) | Out-Null	# Keep track of the sequence start time.
	                    $workitemTable.Columns.Add("Auto_StepStartTimeUTC", [DateTime]) | Out-Null		# Keep track of the step start time.
						$workitemTable.Columns.Add("Auto_WorkingTimeEndOffset", [TimeSpan]) | Out-Null
	                    $workitemTable.Columns.Add("Auto_MaxParallelRate", [int]) | Out-Null 			# Count the work Items for each Farm.
	                    $workitemTable.Columns.Add("Auto_LastRetryCount", [int]) | Out-Null 			# Count Retries.
	                    $workitemTable.Columns.Add("Auto_Notes", [string]) | Out-Null 					# Notes which will be added to the status.
	                }
			        foreach($workitem in $workitemTable.Rows)
			        {
		                if($WebAppID -eq $workitem.WebAppID)
		                { 
	                        $workitem.Auto_MaxParallelRate 			= $MigrationAutomation.Settings.MaxParallelRate -as [int]
	                        $workitem.Auto_LastRetryCount 			= 0
	                        $workitem.Auto_Notes 					= ""
							$workitem.Auto_WorkingTimeEndOffset		= $MigrationAutomation.Settings.WorkingTimeEndOffset -as [TimeSpan]
	                        $temp 									= & $MigrationSequences[$x].DBTrigger $workitem						# Calls the DBTrigger set in SPSiteMigration-Configuration.xml
	            			if($temp -eq $true)
	            			{
								if($ConfirmBeforeStarting -eq $true)
								{
									Write-Host "About to start '$($MigrationSequences[$x].Name)' against: '$($workitem.SourceURL)'"
									$userkey 						= ""
									while($userkey -ne "S" -and $userkey -ne "Q" -and $userkey -ne "C")
									{
										$userkey 					= $(Read-Host -Prompt "type 'S' to Skip this sequence, 'Q' to Quit processing, or 'C' to Continue all sequences without prompting.").ToUpper()
									}
									if($userkey -eq "S") {Write-Host "Skipping"; continue}
									if($userkey -eq "Q") {Write-Host "    " $numSeqStarted "sequences started`n"; Stop-AutomationTranscript; return}
									if($userkey -eq "C") {Write-Host "Confirmation turned off. Executing all remaining sequences."; $ConfirmBeforeStarting = $false}
								}
								$RuningAutomation = $true
	                            $numSeqStarted ++
								execute-function_thread $MigrationSequences[$x] $workitem
	            			}
	            		}
	                }
	            }
	        }
		}
	}while ($RuningAutomation -eq $true);																# End the loop if we found nothing to run
	Write-Host "    " $numSeqStarted "sequences started`n"
	Stop-AutomationTranscript
}

