# This PowerShell script must be .sourced before it can be run.
# Example: ". .\SPSiteMigratopn.ps1"

$global:SPSGlobalsSet 				= $false													# Any time this script is dot-sourced - reset everything

. .\SPSiteMigration-Globals.ps1

function execute-function_thread
{
	param(	[parameter(Mandatory=$true)] [System.Xml.XmlElement] $Sequence,
			[parameter(Mandatory=$true)] [System.Data.DataRow] $Workitem )
	
	write-host "Starting $($Sequence.Name) sequence for" $Workitem["SourceURL"]
	
	$dirExists = Test-Path jobs
	if($dirExists -eq $false)
	{
		new-item jobs -itemtype directory
	}
	
    # Need a place to put log files:
	$dirExists = Test-Path logs
	if($dirExists -eq $false)
	{
		new-item logs -itemtype directory
	}

	# Create filenames for the script, XML, and log:
	$logfilename 					= ".\logs\WorkItem_" + $Workitem["WorkitemId"].ToString() + "-" + $Sequence.Name + ".txt"
    $filename 						= ".\jobs\WorkItem_" + $Workitem["WorkitemId"].ToString() + "-" + $Sequence.Name
	$script 						= $filename + ".ps1"
	$data 							= $filename + ".xml"
	
	# Create a StepNumber attribute to keep track of the current step:
	$owner 							= $Sequence.OwnerDocument
	$StepNumAttibute 				= $owner.CreateAttribute("StepNumber")
	$StepNumAttibute.InnerText 		= "0"															# Set the StepNumber to the first item
	$Sequence.Attributes.Append($StepNumAttibute) | out-Null

	# Create XML based on a small section of SPSiteMigration-Configuration.xml
	$Tempxml 						= New-Object xml
	$fragment 						= $Tempxml.CreateDocumentFragment()
	$fragment.innerxml 				= $Sequence.OuterXml
	$Tempxml.AppendChild($fragment)  | out-Null
	Export-CliXML -InputObject ($Tempxml, $Workitem) -Path $data									# Output the XML file for disaster recovery
	
	# Create a unique script file from a template:
	$template 						= Get-Content "SPSiteMigration-ExecuteSequenceTemplate.ps1"
	'$filename 						= '+ "`"$filename`"" | Out-File $script							# Put the filname at the top of the new script
    'Start-Transcript -Append -Path '+ $logfilename | Out-File $script -Append 
	$template | Out-File $script -Append 															# Append the contents of SPSiteMigration-ExecuteSequenceTemplate.ps1 to the script
    $arguments						= "-file $script"
	Start-Process PowerShell.exe -ArgumentList $arguments    										# Executes the Script in Seperate Process
	#&$script																						# Execute the script on this thread
}

function Start-Sequences
{	
    $todaysDate = get-date
    $10Daysfromnow = $todaysDate.AddDays(10)
    $WorkItems = Read-CurrentWorkItems -StartingDate $10Daysfromnow.ToUniversalTime()               # TODO: This is only for email.  Need a switch to envoke the correct version.

    foreach($MigrationAutomation in $global:AutomationNodesXML)										# Looping through Nodes first so that we can order the events
    {																								# 	Workitems nearing completion will be executed before others. 
        #$WorkItems = Read-CurrentWorkItems -FarmUrl $MigrationAutomation. # TODO: need to put the farm URL
		$WebAppID = New-object Guid($MigrationAutomation.WebAppID)
		$MigrationSequences = $MigrationAutomation.SelectNodes("MigrationSequence")					# Make sure we have an array, so we can iterate through it backwards
		for($x = $MigrationSequences.Count-1; $x -ge 0 -and $x -lt $MigrationSequences.Count; $x--)	# It's possible the XML could be manually edited/changed while the loop is running.
		{
			foreach($workitemTable in $WorkItems.Tables)
			{
		        foreach($workitem in $workitemTable.Rows)
		        {
	                if($WebAppID -eq $workitem["WebAppID"])
	                {
                        $temp = & $MigrationSequences[$x].DBTrigger $workitem						# Calls the DBTrigger set in SPSiteMigration-Configuration.xml
            			if($temp -eq $true)
            			{
							execute-function_thread $MigrationSequences[$x] $workitem
return
            			}
						#else
						#{
							# TODO: See if the process is stalled.  If it is - restart the thread, etc.
						#}
            		}
                }
            }
        }
	}
}

