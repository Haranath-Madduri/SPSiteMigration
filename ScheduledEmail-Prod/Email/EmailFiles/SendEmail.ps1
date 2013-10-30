function check-ReadyForFinalEmail
{
	param([parameter(Mandatory=$true)] [System.Data.DataRow] $Workitem )
	if($Workitem["WorkItemTypeName"] -eq "Scheduled Migration"`
        -and $Workitem["WorkitemState"] -eq "RequiresMigrationCompletedComms")
    {
	    # TODO: Claim the workitem!
	    return $true
	}
 
}


function check-ReadyForInitialEmail
{
	param([parameter(Mandatory=$true)] [System.Data.DataRow] $Workitem )
	if($Workitem["WorkItemTypeName"] -eq "Scheduled Migration"`
        -and $Workitem["WorkitemState"] -eq "RequiresMigrationScheduledComms")
    {
	    # TODO: Claim the workitem!
	    return $true
	}

}

function check-ReadyForDescheduledEmail # When Execution team ran into issue and migration will not occur at this time, maybe later 
{
	param([parameter(Mandatory=$true)] [System.Data.DataRow] $Workitem )
	if($Workitem["WorkItemTypeName"] -eq "Scheduled Migration"`
        -and $Workitem["WorkitemState"] -eq "RequiresMigrationExecutionDelayedComms")
    {
	    # TODO: Claim the workitem!
	    return $true
	}

}

function check-ReadyForDelayedEmail   # When Customer Requested that migration be delayed
{
	param([parameter(Mandatory=$true)] [System.Data.DataRow] $Workitem )
	if($Workitem["WorkItemTypeName"] -eq "Scheduled Migration"`
        -and $Workitem["WorkitemState"] -eq "RequiresMigrationDelayedComms")
    {
	    # TODO: Claim the workitem!
	    return $true
	}

}

function check-ReadyForRollBackEmail    # When Customer Requested that migration be delayed
{
	param([parameter(Mandatory=$true)] [System.Data.DataRow] $Workitem )
	if($Workitem["WorkItemTypeName"] -eq "Scheduled Migration"`
        -and $Workitem["WorkitemState"] -eq "RequiresRollbackCompletedComms")
    {
	    # TODO: Claim the workitem!
	    return $true
	}

}

function check-ReadyForDelistedEmail  # When Execution team ran into issue migration will never occur for this site 
{
	param([parameter(Mandatory=$true)] [System.Data.DataRow] $Workitem )
	if($Workitem["WorkItemTypeName"] -eq "Scheduled Migration"`
        -and $Workitem["WorkitemState"] -eq "RequiresMigrationDelistedComms")
    {
	    # TODO: Claim the workitem!
	    return $true
	}

}



function Get-AdminEmailAddresses
{
Param( [parameter(Mandatory=$true)][string] $SourceURL)

	Write-Host "Gathering Adminstrator email addresses for:" $SourceURL
	
	$scrptblock = `
	{
		param($SourceURL)
		
        Add-PSSnapin Microsoft.Sharepoint.Powershell
		
	    $SiteOwnerEmail = ""
	    $SecondaryOwnerEmail = ""
	    $AdminListEmail = ""
		
        $site 					= Get-SPSite $SourceURL
		if($site -ne $null)
		{
			if($site.Owner -eq $null)
			{
				Write-Error "Could not get the owner"
			}
			
			$SiteOwnerEmail 		= $site.Owner.Email
			
			if($site.SecondaryContact -ne $null)
			{
				$SecondaryOwnerEmail	= $site.SecondaryContact.Email
			}
			else
			{
				Write-Error "Could not find the secondary contact"
			}
			
			$AllSiteAdmins 			= $site.RootWeb.SiteAdministrators
			
	        foreach($admin in $AllSiteAdmins)
	        {
	            $AdminListEmail 	= $AdminListEmail + $admin.email + ";"
	        }
		}
		else
		{
			Write-Error "could not get the site collection"
		}
	    $SiteOwnerEmail
	    $SecondaryOwnerEmail
	    $AdminListEmail
	}
	$servername 				= Get-FarmServerName $SourceURL
	$cred 						= Get-FarmCredential $SourceURL
	# TODO: need to be able to switch between types of authentication eg "Credssp"
	Invoke-Command -ScriptBlock $scrptblock -Authentication Credssp -Credential $cred -ComputerName $servername -ArgumentList $SourceURL
}



Function Send-EmailWithAllParameters 
{
Param
(             
    [parameter(Mandatory=$true)]  [string] $SourceURL,
    [parameter(Mandatory=$true)]  [string] $TargetURL,
    [parameter(Mandatory=$true)]  [string] $OwnerEmail,
    [parameter(Mandatory=$true)]  [string] $SiteAdministratorEmailAddresses,
    [parameter(Mandatory=$true)]  [string] $WorkitemState,
    [parameter(Mandatory=$true)]  [string] $WorkDate,
    [parameter(Mandatory=$true)]  [string] $WorkingTimeStartOffset,
	[parameter(Mandatory=$true)]  [string] $TimeZoneOffset,
    [parameter(Mandatory=$true)]  [string] $Template
	
)
    
    if($SourceURL -ne $null -and $WorkitemState -ne $null -and $TargetURL -ne $null -and $OwnerEmail -ne $null -and $SiteAdministratorEmailAddresses -ne $null )
    {

    trap [Exception] { 

       write-error $($_.Exception.Message); 
       write-host "" 
       return $false; 
    }


	    $startedTime 				= date
	    $proid 						= [System.Diagnostics.Process]::GetCurrentProcess().id
	    $machinename 				= hostname
	    $Newstatus                  = ""
	    Read-MigrationAutomationConfiguration
	
	    $smtpSettings 				= $null
        foreach($settings in $global:GlobalSettings) 
        { 
            if($settings.smtp.IsEmpty -eq $False) 
            { 
                    $smtpSettings = $settings.SMTP 
				    break
            } 
        } 
        if($smtpSettings -eq $null) 
        { 
            write-error "The SMTP node was not found within /MigrationAutomationConfiguration/GlobalSettings" -Category InvalidData  
            return 
        }
 
        $msg 						= new-object Net.Mail.MailMessage
	    $foundemail 				= $false
	
	    $msg.To.Add($OwnerEmail)
	    $CCEmail = $SiteAdministratorEmailAddresses.Trim().Split(";")
	    ForEach($Member in $CCEmail )
	    {
		    if($Member.Length -ne 0)
		    {
			    $msg.CC.Add($Member)
		    }
	    }
		
	    $smtp 						= new-object Net.Mail.SmtpClient($smtpSettings.HostName) #TODO: Validate the Hostname
        $smtp.Credentials 			= Get-SMTPCredential
	    $location 					= $(Get-Location).Path + "\Email\Images" 
	    $Images 					= Get-ChildItem $location| Where {-NOT $_.PSIsContainer} | foreach {$_.fullname} 

	    foreach($item in $Images)
	    {
		    $att 					= new-object Net.Mail.Attachment($item)
		    $att.ContentId 			= $att.Name.Replace(".","_")
		    $att.ContentDisposition.Inline = $True
		    $att.ContentDisposition.DispositionType = "Inline"
		    $att.ContentType.MediaType = "image/jpeg"
		    $msg.Attachments.Add($att)
	    }


	
        If($Template -eq "InitialEmail")
        {

            if($WorkDate -ne $null -and $WorkingTimeStartOffset -ne $null -and $TimeZoneOffset -ne $null)
            {
                $WorkItemDate   = $([datetime]$WorkDate).ToString('d')
                $WorkTimeOffset = $([datetime]$WorkingTimeStartOffset).ToString('t')
                $msg.subject 	= "Awareness:  Your SharePoint site is moving to the cloud"
                $Newstatus      = "Scheduled"  #TODO - need to change if needed
            }
            else
            {
                Write-Error "One of the email parameter is not having valid value. Please check the values of WorkDate=" $WorkDate ",WorkingTimeStartOffset=" $WorkingTimeStartOffset ",TimeZoneOffset:" $TimeZoneOffset 
                return $False
            }

        }
        elseIf($Template -eq "finalemail")
        {
            $msg.subject = "Your site migration is complete—welcome to SharePoint Online!"
        }
        elseIf($Template -eq "DelayedEmail")
        {
            $msg.subject = "Notification:  Your SharePoint site migration has been delayed"
        }
        elseIf($Template -eq "DescheduledEmail")
        {
            $msg.subject = "Notification:  We are happy to reschedule your site migration"
        }
        elseIf($Template -eq "RollBackEmail")
        {
            $msg.subject = "Notification:  Your SharePoint 2010 site has been re-activated"
        }
        elseIf($Template -eq "Blockedemail_TODO") #TODO: need the template and update the subject here
        {
            $msg.subject = "SUBJECT of BLOCKED EMAIL"
        }
        elseIf($Template -eq "Delistedemail_TODO") #TODO: need the template and update the subject here
        {
            $msg.subject = "SUBJECT OF DELISTED EMAIL"
        }        Else
        {
            Write-Error "Sorry, Couldn't get the content of the Email"
            return
        }
        $filename 					= $(Get-Location).Path + "\Email\"+ $Template +".html" 
        $body1 						= Get-Content $filename
        $body                       = $ExecutionContext.InvokeCommand.ExpandString($body1)
	    $msg.IsBodyHTML 			= $True
	    $msg.From 					= $smtpSettings.FromEmail
	    $msg.ReplyTo 				= $smtpSettings.FromEmail
	    $msg.Bcc.Add($smtpSettings.FromEmail)
	
	    write-host $smtpSettings.HostName $smtpSettings.FromEmail $smtp.Credentials.Username
	    $msg.body = $body
	    Write-Host "Sending Email to"  $SourceURL  "Email List:" $OwnerEmail $SiteAdministratorEmailAddresses
	
	    $ret = $smtp.Send($msg)
	
	    $now = date 
        #Per discussion with Marc we dont neeed to update the status of workitem and hence no need of below code in email
        #Execute-UpdateWorkItemState -WorkitemState $Newstatus -SourceSiteURL $SourceURL -ProcessingServer $machinename -ProcessId $proid -ProcessStart#ed $startedTime -ProcessEnded $now 
 	    
        return $true
    }
    else
        {
            Write-Error "One of the email parameter is not having valid value. Please check the values of SourceURL=" $SourceURL ",TargetURL=" $TargetURL  ",WorkitemState=" $WorkitemState ",OwnerEmail=" $OwnerEmail ",SiteAdministratorEmailAddresses=" $SiteAdministratorEmailAddresses 
            return $False
        }
}

# Send Initial E-Mail: Need to revisit below function in case need to change the way of email function

Function Send-Email 
{
Param
(   
    [parameter(Mandatory=$true)] [string] $Template,
	[parameter(Mandatory=$true)] [string] $SourceURL          
)
    $inputerror = $false
    
    $uri1 = $SourceURL -as [System.URI]
    if($uri1.AbsoluteURI -eq $null -or $uri1.Scheme -notmatch '[http|https]')
    {
        $inputerror = $true
        Write-error "The source URL is not a valid URL:      '$SourceURL'" -category InvalidArgument
    }

    if($SourceURL -eq $null)
        {
            Write-Error "Please check the value of Template=" $Template ",and SourceURL=" $SourceURL
            return
        }

        $TenDaysinFuture = date
        $items = Read-CurrentWorkItems  $SourceURL  $TenDaysinFuture.AddDays(10)
        foreach($row in $items.Tables.rows)
        {
            if($row.SourceURL -ne $SourceURL)
            {
                continue
            }
            $message = "The value of current WorkitemState is:", $row.WorkitemState, ", and the Template is:(",$Template,") . Are you sure you want to proceed?"
            $choice = YesNoConfirm -message $message
            if($choice -eq 2 -or $choice -eq 7)
            {
                return $false
            }

            $filename 	= $(Get-Location).Path + "\Email\" + $Template + ".html" 
            try
            {
                IF(Get-Content $filename) #TODO: need to check without causing exception eg: check directory listing
                { 
                    return Send-EmailWithAllParameters -SourceURL $row.SourceURL -TargetURL $row.TargetURL   -OwnerEmail $row.OwnerEmail  -SiteAdministratorEmailAddresses $row.SiteAdministratorEmailAddresses -WorkitemState $row.WorkitemState  -WorkDate $row.WorkDate -WorkingTimeStartOffset $row.WorkingTimeStartOffset -TimeZoneOffset $row.TimeZoneOffset -Template $Template
                }
            }
            catch
            {
                Write-Error "Unable to get the template. Value of Template=" $Template ",and SourceURL=" $SourceURL
            } 
            
        }

        return $false

}

function YesNoConfirm($message)
{
    $a = new-object -comobject wscript.shell 
    $intAnswer = $a.popup($message,0,"",3) 
    return $intAnswer

}
