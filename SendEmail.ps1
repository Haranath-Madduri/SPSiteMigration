
function check-ReadyForFinalEmail
{
	param([parameter(Mandatory=$true)] [System.Data.DataRow] $Workitem )
    $CurrentDateTime = $(Get-Date).ToUniversalTime()
    $LastModifiedDate = $([datetime] $Workitem["WorkItemStateLastModified"])
	if($Workitem["WorkItemTypeName"] -eq "Scheduled Migration"`
        -and $Workitem["WorkitemState"] -eq "RequiresMigrationCompletedComms"`
        -and $CurrentDateTime -ge $LastModifiedDate.AddHours(1))
    {
	    # TODO: Claim the workitem!
	    return $true
	}
 
}




function check-ReadyForInitialEmail
{
	param([parameter(Mandatory=$true)] [System.Data.DataRow] $Workitem )
    $9days  = (Get-Date).Date.AddDays(9)
    $11days = (Get-Date).Date.AddDays(11)
    $WorkDT = $([datetime]$Workitem["WorkDate"])
	if($Workitem["WorkItemTypeName"] -eq "Scheduled Migration"`
        -and $Workitem["WorkitemState"] -eq "RequiresMigrationScheduledComms"`
        -and $WorkDT -ge $9days`
        -and $WorkDT -lt $11days)
    {
	    # TODO: Claim the workitem!
	    return $true
	}
}

function check-ReadyForDescheduledEmail # When Customer Requested that migration be delayed
{
	param([parameter(Mandatory=$true)] [System.Data.DataRow] $Workitem )
    $CurrentDateTime = $(Get-Date).ToUniversalTime()
    $LastModifiedDate = $([datetime] $Workitem["WorkItemStateLastModified"])
	if($Workitem["WorkItemTypeName"] -eq "Scheduled Migration"`
        -and $Workitem["WorkitemState"] -eq "RequiresMigrationDelayedComms"`
        -and $CurrentDateTime -ge $LastModifiedDate.AddHours(1))
    {
	    # TODO: Claim the workitem!
	    return $true
	}

}

function check-ReadyForDelayedEmail   # When Execution team ran into issue and migration will not occur at this time, maybe later 
{
	param([parameter(Mandatory=$true)] [System.Data.DataRow] $Workitem )
    $CurrentDateTime = $(Get-Date).ToUniversalTime()
    $LastModifiedDate = $([datetime] $Workitem["WorkItemStateLastModified"])
	if($Workitem["WorkItemTypeName"] -eq "Scheduled Migration"`
        -and $Workitem["WorkitemState"] -eq "RequiresMigrationExecutionDelayedComms"`
        -and $CurrentDateTime -ge $LastModifiedDate.AddHours(1))
    {
	    # TODO: Claim the workitem!
	    return $true
	}

}

function check-ReadyForRollBackEmail    # When Customer Requested that migration be delayed
{
	param([parameter(Mandatory=$true)] [System.Data.DataRow] $Workitem )
    $CurrentDateTime = $(Get-Date).ToUniversalTime()
    $LastModifiedDate = $([datetime] $Workitem["WorkItemStateLastModified"])
	if($Workitem["WorkItemTypeName"] -eq "Scheduled Migration"`
        -and $Workitem["WorkitemState"] -eq "RequiresMigrationRollbackComms"`
        -and $CurrentDateTime -ge $LastModifiedDate.AddHours(1))
    {
	    # TODO: Claim the workitem!
	    return $true
	}

}

function check-ReadyForDelistedEmail  # DeListed: When Execution team ran into issue migration will never occur for this site 
{
	param([parameter(Mandatory=$true)] [System.Data.DataRow] $Workitem )
    $CurrentDateTime = $(Get-Date).ToUniversalTime()
    $LastModifiedDate = $([datetime] $Workitem["WorkItemStateLastModified"])
	if($Workitem["WorkItemTypeName"] -eq "Scheduled Migration"`
        -and $Workitem["WorkitemState"] -eq "RequiresMigrationDelistedComms"`
        -and $CurrentDateTime -ge $LastModifiedDate.AddHours(1))
    {
	    # TODO: Claim the workitem!
	    return $true
	}

}


function check-ReadyForBlockedEmail  # Blocked: Site has been removed form scheduling due to detection of a migration block after initial migration scheduled email was sent
{
	param([parameter(Mandatory=$true)] [System.Data.DataRow] $Workitem )
    $CurrentDateTime = $(Get-Date).ToUniversalTime()
    $LastModifiedDate = $([datetime] $Workitem["WorkItemStateLastModified"])
	if($Workitem["WorkItemTypeName"] -eq "Scheduled Migration"`
        -and $Workitem["WorkitemState"] -eq "RequiresMigrationExecutionBlockedComms"`
        -and $CurrentDateTime -ge $LastModifiedDate.AddHours(1))
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
    [parameter(Mandatory=$true)]   [string] $SourceURL,
    [parameter(Mandatory=$true)]   [string] $TargetURL,
    [parameter(Mandatory=$false)]  [string] $OwnerEmail,
    [parameter(Mandatory=$false)]  [string] $SiteAdministratorEmailAddresses,
    [parameter(Mandatory=$false)]  [string] $WorkDate,
    [parameter(Mandatory=$false)]  [string] $WorkingTimeStartOffset,
    [parameter(Mandatory=$false)]  [string] $TimeZoneOffset,
    [parameter(Mandatory=$true)]   [string] $Template)
    
    trap [Exception] { 

        write-error $($_.Exception.Message); 
        write-host "" 
        return $false; 
    }

    Read-MigrationAutomationConfiguration
       
    # Check if it's even possible to send email before doing anything else:
    $smtpSettings                            = $null
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
        return $false
    }


    $msg                                        = new-object Net.Mail.MailMessage
    $foundemail                       = $false

    # Make sure everything is a string before we manipulate it:

    # Check to see if there are any email addresses in the To field:

    if($OwnerEmail -eq $null)
    {
        $OwnerEmail             = "" 
    } 
    if($SiteAdministratorEmailAddresses -eq $null)
    {
        $SiteAdministratorEmailAddresses               = "" 
    }

    $ToPeople                   = $OwnerEmail +";" + $SiteAdministratorEmailAddresses
    
 
    if($ToPeople.Contains('@') -eq $false)
    {
        Write-Error "There are no email addresses to send an email to"
        return $false
    }
    $ToPeople = $($ToPeople.Trim().Split(";"))
    # Run through all the people in the To field and add them to the object:
    ForEach($Member in $ToPeople)
    {
        try
        {
            if($Member.Contains('@') -eq $true)
            {
                $msg.To.Add($Member.Trim())
            }
        }
        catch [Exception]
        {
            $AddError = "Was unable to add '$Member' to the list of email addresses."
            Write-Error  -Message $AddError -Category InvalidData
            continue # Don't stop if one of the email addresses was invalid.
        }
    }
    
    # Build the SMTP and mail objects:
    $smtp                                    = new-object Net.Mail.SmtpClient($smtpSettings.HostName)
    $smtp.Credentials                        = Get-SMTPCredential
    $location                                = $(Get-Location).Path + "\Email\" +$Template+"\"+"Images" 
    $Images                                  = Get-ChildItem $location| Where {-NOT $_.PSIsContainer} | foreach {$_.fullname}

    # Add all the images in the folder:
    foreach($item in $Images)
    {
        $att                                     = new-object Net.Mail.Attachment($item)
        $att.ContentId                           = $att.Name.Replace(".","_")
        $att.ContentDisposition.Inline           = $True
        $att.ContentDisposition.DispositionType  = "Inline"
        $att.ContentType.MediaType               = "image/jpeg"
        $msg.Attachments.Add($att)
    }

    $Newstatus                  = ""
    If($Template -eq "InitialEmail")
    {

        if($WorkDate -ne $null -and $WorkingTimeStartOffset -ne $null -and $TimeZoneOffset -ne $null)
        {
            $WorkItemDate   = $([datetime]$WorkDate).ToString('d')
            $WorkTimeOffset = $([datetime]$WorkingTimeStartOffset).ToString('t')
            #$msg.subject   = "Awareness:  Your SharePoint site is moving to the cloud"
            $Newstatus      = "Scheduled"  #TODO - need to change if needed
        }
        else
        {
            Write-Error "One of the email parameter does not have valid value. Please check the values of WorkDate=" $WorkDate ",WorkingTimeStartOffset=" $WorkingTimeStartOffset ",TimeZoneOffset:" $TimeZoneOffset 
            return $False
        }

    }

    $filename                                   = $(Get-Location).Path + "\Email\" +$Template+"\"+ $Template +".html" 
    $msg.IsBodyHTML                             = $True
    $msg.From                                   = $smtpSettings.FromEmail
    $msg.ReplyTo                                = $smtpSettings.FromEmail
    $msg.Bcc.Add($smtpSettings.FromEmail)
    $msg.body                                   = $ExecutionContext.InvokeCommand.ExpandString($(Get-Content $filename))
    $title                                      = [regex] '(?<=<title>)([\S\s]*?)(?=</title>)'
    $Subject                                    = $title.Match($msg.body).value.trim()
    $msg.Subject                                = $Subject 
    
    If(($msg.body -eq $null -or $msg.body -eq "") -or ($msg.Subject -eq $null -or $msg.Subject -eq "") )
    {
        Write-Error "Sorry, Couldn't get the Subject or content of the Email"
        return $false
    }
    write-host $smtpSettings.HostName $smtpSettings.FromEmail $smtp.Credentials.Username
    Write-Host "Sending"  $Template  " to URL####" $SourceURL ".####"
    Write-Host "Email TO List:" $ToPeople
    Write-Host "Email BCC List:" $msg.Bcc
    Write-Host ""
    #$ret = $smtp.Send($msg)
       
    return $true
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
            return $false
        }

        $TenDaysinFuture = date
        $items = Read-CurrentWorkItems  $SourceURL  $TenDaysinFuture.AddDays(10)
        foreach($row in $items.Tables.rows)
        {
            if($row.SourceURL -ne $SourceURL)
            {
                continue
            }
            $message = "The value of current WorkitemState is:(", $row.WorkitemState, "), and the Template is:(",$Template,") . Are you sure you want to proceed?"
            $choice = YesNoConfirm -message $message
            if($choice -eq 2 -or $choice -eq 7)
            {
                return $false
            }

            $filename 	= $(Get-Location).Path + "\Email\" +$Template+"\"+ $Template +".html" 
            try
            {
                IF(Get-Content $filename) #TODO: need to check without causing exception eg: check directory listing
                { 
                   $status = Send-EmailWithAllParameters -SourceURL $row.SourceURL -TargetURL $row.TargetURL   -OwnerEmail $row.OwnerEmail  -SiteAdministratorEmailAddresses $row.SiteAdministratorEmailAddresses  -WorkDate $row.WorkDate -WorkingTimeStartOffset $row.WorkingTimeStartOffset -TimeZoneOffset $row.TimeZoneOffset -Template $Template
                   if($status)
                   {

                        & "Set-WorkItemStateManual_$Template" $row.SourceURL
                        return $status
                   }
                   else 
                   {
                        Write-Error "Status of DB could not be updated as send-EmailWithAllParameters method returns false."
                   }
                }
            }
            catch
            {
                Write-Error "Unable to get the template. Value of Template=", $Template , ",and SourceURL=" ,$SourceURL
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
