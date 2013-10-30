
function Read-MigrationAutomationConfiguration
{
    if($global:AutomationNodesXML -eq $null -or $global:FailureSequences -eq $null)
    {
        $xml                       		= [xml](get-content SPSiteMigration-Configuration.xml)
        if($xml -isnot [xml])
        {
            return $false          # get-content will get an exception if the file does not exist.  No need to write the error.
        }
        
        $global:AutomationNodesXML 		= $xml.SelectNodes("/MigrationAutomationConfiguration/MigrationAutomation")
        if($global:AutomationNodesXML.Count -eq 0)
        {
            $global:AutomationNodesXML 	= $null
            Write-Host
            write-error "MigrationAutomation was not found within /MigrationAutomationConfiguration" -Category InvalidData
            return $false
        }
        
		$global:GlobalSettings  		= $xml.SelectSingleNode("/MigrationAutomationConfiguration/GlobalSettings")
        if($global:GlobalSettings.Name -ne "GlobalSettings")
        {
            $global:GlobalSettings 		= $null
            Write-Host
            write-error "GlobalSettings were not found within /MigrationAutomationConfiguration" -Category InvalidData
            return $false
        }
		        
        $global:FailureSequences   		= $xml.SelectNodes("/MigrationAutomationConfiguration/FailureSequences")
        if($global:FailureSequences.Count -eq 0)
        {
            $global:FailureSequences 	= $null
            Write-Host
            write-error "FailureSequences were not found within /MigrationAutomationConfiguration" -Category InvalidData
            return $false
        }
    }
    return $true
}

function Get-MigrationCoordinatorConnectionString
{
    if($(Read-MigrationAutomationConfiguration) -eq $true)
    {
		$MigrationCoordinator = $global:GlobalSettings.Databases.SelectSingleNode("Database[@Name='Migration_Coordinator']")
        if($MigrationCoordinator.Name -eq "Migration_Coordinator")
        {
			$Credential = Get-MigrationCoordinatorCredential	# Only needed if "Integrated Security=$false", but call every time.
			$UserName 	= $Credential.UserName
			$Password 	= $Credential.GetNetworkCredential().Password
            return $ExecutionContext.InvokeCommand.ExpandString($MigrationCoordinator.ConnectionString)
        }
    }
    Write-Host
    write-error "The Migration_Coordinator Database was not found within /MigrationAutomationConfiguration/GlobalSettings/Databases" -Category InvalidData
    return ""
}

function Get-MigrationCoordinatorCredential
{
    if($(Read-MigrationAutomationConfiguration) -eq $true)
    {
		$MigrationCoordinator = $global:GlobalSettings.Databases.SelectSingleNode("Database[@Name='Migration_Coordinator']")
        if($MigrationCoordinator.Name -eq "Migration_Coordinator")
        {
			$ThisUser 	= [Environment]::UserDomainName.ToUpper() + "\" + [Environment]::MachineName.ToUpper() + "\" + [Environment]::UserName.ToUpper()
			$Account 	= $MigrationCoordinator.SelectSingleNode("EncryptedAccount[@UserName='$ThisUser']")

			if($Account.AccountName.Length -gt 0 -and $Account.Password.Length -gt 0)
			{
                try
                {
				    $SecurePassword = convertto-securestring -string $Account.Password
                    if($SecurePassword -eq $null)
                    {
                        Write-Host "This is a migration coordinator credential issue."
                        return $null # TODO: An error is reported.  Need to come up with a suggestion. The convertto-securestring error is "Key not valid for use in specified state."
                    }
				    $credential 	=  New-Object System.Management.Automation.PSCredential ($Account.AccountName, $SecurePassword)
				    return $credential
                }
                catch [Exception]
                {
                    Write-Error "You must set the migration coordinator DB credential before using it. Use Set-MigrationCoordinatorCredential." -Category AuthenticationError
                    return $null
                }
			}
        }
    }
    Write-Host
    write-error "The Migration_Coordinator Database does not have a UserName and Password for you set within `
	/MigrationAutomationConfiguration/GlobalSettings/Databases/Database/EncryptedAccount" -Category InvalidData
	Write-Host "Use Set-MigrationCoordinatorCredential to set the credential"
    return $null
}

function Set-GlobalSettingsInXML
{
	$xml = [xml](get-content SPSiteMigration-Configuration.xml)
    if($xml -isnot [xml])
    {
        return $null         # get-content will get an exception if the file does not exist.  No need to write the error.
    }
	if($xml.MigrationAutomationConfiguration.Count -eq 0)
	{
		$global:GlobalSettings 	= $null
		Write-Host
		write-error "The XML is not a  valid MigrationAutomationConfiguration file" -Category InvalidData
		return $null
	}
	$global:GlobalSettings   	= $xml.SelectSingleNode("/MigrationAutomationConfiguration/GlobalSettings")
	if($global:GlobalSettings.LocalName -ne "GlobalSettings")
	{
		# Create Global Settings if it's not there:
		$xml.MigrationAutomationConfiguration.Item(1).AppendChild($xml.CreateElement("GlobalSettings"))
		$global:GlobalSettings	= $xml.SelectSingleNode("/MigrationAutomationConfiguration/GlobalSettings")
	}
	return $xml
}

function Set-MigrationCoordinatorCredential
{
 param( [parameter(Mandatory = $false)] [string] $UserName,
        [parameter(Mandatory = $false)] [string] $Password)
	
	$SecurePassword 				= new-object securestring

	if($Password -eq "" -or $UserName -eq "")
    {
    	# Do the user interaction first so the file is read-written in the shortest time possible:
	    Write-Host "`nEnter a username and password that has execute access to the Coordinator database."
	    Write-Host "      Hint: SQL in Azure uses a name only (eg. 'tony')`n"
	    $AccountName 				= read-host -Prompt "Username"
	    $SecurePassword 			= read-host -assecurestring -Prompt "Password"
    }
    else 
    {
        # Convert the password string to a secure string:
        $PasswordArray 				= $Password.ToCharArray();
        foreach ($char in $PasswordArray)
        {
            $SecurePassword.AppendChar($char);
        }
        $AccountName 				= $UserName
    }

	$xml = Set-GlobalSettingsInXML
	if($xml -eq $null)
	{
		return
	}
	
	$MigrationCoordinator 			= $global:GlobalSettings.Databases.SelectSingleNode("Database[@Name='Migration_Coordinator']")
	
    if($MigrationCoordinator.Name -ne "Migration_Coordinator")
    {
		# Create parent database node if it was not there:
		if($xml.MigrationAutomationConfiguration.GlobalSettings.Databases.LocalName -ne "Databases")
		{
			$xml.MigrationAutomationConfiguration.GlobalSettings.AppendChild($xml.CreateElement("Databases")) | Out-Null
		}
		$Database 					= $xml.CreateElement("Database")
		$Name 						= $xml.CreateAttribute("Name")
		$Name.Value 				= "Migration_Coordinator"
		$ConnectionString 			= $xml.CreateAttribute("ConnectionString")
		$ConnectionString.Value 	= 'Server=ReplaceWithServerName;Database=Migration_Coordinator; UID=$($UserName);password=$($Password); Integrated Security=$false;Connect Timeout=180;'
		$Database.Attributes.Append($Name) | Out-Null
		$Database.Attributes.Append($ConnectionString) | Out-Null
		$xml.MigrationAutomationConfiguration.GlobalSettings.Databases.AppendChild($Database) | Out-Null

		$MigrationCoordinator 		= $global:GlobalSettings.Databases.SelectSingleNode("Database[@Name='Migration_Coordinator']")

	    write-error "`nThe Migration_Coordinator Database was not found within /MigrationAutomationConfiguration/GlobalSettings/Databases" -Category InvalidData
		Write-Host "A Migration_Coordinator entry was created, but the database name must be set manually.`n"
    }	

	$ThisUser 						= [Environment]::UserDomainName.ToUpper() + "\" + [Environment]::MachineName.ToUpper() + "\" + [Environment]::UserName.ToUpper()
	$Account 						= $MigrationCoordinator.SelectSingleNode("EncryptedAccount[@UserName='$ThisUser']")
	if($Account.Name -ne "EncryptedAccount")
	{
		$EncryptedAccount 			= $xml.CreateElement("EncryptedAccount")
		$UserNameAtt 				= $xml.CreateAttribute("UserName")
		$UserNameAtt.Value 			= $ThisUser
		$EncryptedAccount.Attributes.Append($UserNameAtt) | Out-Null
		$MigrationCoordinator.AppendChild($EncryptedAccount) | Out-Null
		
		$Account 					= $MigrationCoordinator.SelectSingleNode("EncryptedAccount[@UserName='$ThisUser']")
	}
    try
    {
	    $encryptedPassword 			= convertfrom-securestring -securestring $SecurePassword
    } 
    catch [Exception]
    {
         write-error $($_.Exception.Message);
         Write-Host "You need to set the migration coordinator credential"
         return $null
    }
	$Account.SetAttribute("AccountName", $AccountName) | Out-Null
	$Account.SetAttribute("Password", $encryptedPassword) | Out-Null
	$xml.Save($(Get-Location).Path +  "\SPSiteMigration-Configuration.xml") | Out-Null
	Write-Host
	# TODO: Check to see if we actually have access
}

function Set-TransformationCredential
{
    param( [parameter(Mandatory = $false)] [string] $AccountName,
           [parameter(Mandatory = $false)] [string] $Password)
    
    $SecurePassword 				= new-object securestring
    if($Password -eq "" -or $UserName -eq "")
    {
    	# Do the user interaction first so the file is read-written in the shortest time possible:
	    Write-Host "`nEnter a username and password."
	    $AccountName 				= read-host -Prompt "Username"
	    $SecurePassword 			= read-host -assecurestring -Prompt "Password"
    }
    else 
    {
        # Convert the password string to a secure string:
        $PasswordArray 				= $Password.ToCharArray();
        foreach ($char in $PasswordArray)
        {
            $SecurePassword.AppendChar($char);
        }
        #$AccountName 				= $UserName
    }
	# Do the user interaction first so the file is read-written in the shortest time possible:
	#Write-Host "Enter a username and password that is used for transformation."
	#$AccountName 					= read-host -Prompt "Username"
	#$Password 						= read-host -assecurestring -Prompt "Password"
	#Write-Host
	$xml 							= Set-GlobalSettingsInXML
	if($xml -eq $null)
	{
		return
	}
	$Transformation                 = $global:GlobalSettings.Transformations
	$ThisUser 						= [Environment]::UserDomainName.ToUpper() + "\" + [Environment]::MachineName.ToUpper() + "\" + [Environment]::UserName.ToUpper()
	$Account 						= $Transformation.SelectSingleNode("EncryptedAccount[@UserName='$ThisUser']")
	if($Account.Name -ne "EncryptedAccount")
	{
		$EncryptedAccount 			= $xml.CreateElement("EncryptedAccount")
		$UserNameAtt 				= $xml.CreateAttribute("UserName")
		$UserNameAtt.Value 			= $ThisUser
		$EncryptedAccount.Attributes.Append($UserNameAtt) | Out-Null
		$Transformation.AppendChild($EncryptedAccount) | Out-Null
		
		$Account 					= $Transformation.SelectSingleNode("EncryptedAccount[@UserName='$ThisUser']")
	}
    try{
	    $encryptedPassword 			= convertfrom-securestring -securestring $SecurePassword
    } 
    catch [Exception]
    {
         write-error $($_.Exception.Message);
         Write-Host "You need to set the migration coordinator credential"
         return $null
    }
	$Account.SetAttribute("AccountName", $AccountName) | Out-Null
	$Account.SetAttribute("Password", $encryptedPassword) | Out-Null
	$xml.Save($(Get-Location).Path +  "\SPSiteMigration-Configuration.xml") | Out-Null
	Write-Host
	# TODO: Check to see if we actually have access
}

function Get-TransformationCredential
{
    if($(Read-MigrationAutomationConfiguration) -eq $true)
    {
		$Transformation = $global:GlobalSettings.Transformations
		$ThisUser 		= [Environment]::UserDomainName.ToUpper() + "\" + [Environment]::MachineName.ToUpper() + "\" + [Environment]::UserName.ToUpper()
		$Account 		= $Transformation.SelectSingleNode("EncryptedAccount[@UserName='$ThisUser']")

		if($Account.AccountName.Length -gt 0 -and $Account.Password.Length -gt 0)
		{
            try
            {
			    $SecurePassword = convertto-securestring -string $Account.Password
                if($SecurePassword -eq $null)
                {
                    Write-Host "This is a transformation credential issue."
                    return $null
                }
			    $credential 	=  New-Object System.Management.Automation.PSCredential ($Account.AccountName, $SecurePassword)
			    return $credential
            }
            catch [Exception]
            {
                Write-Error "You must set the transformation credential before using it. Use Set-TransformationCredential." -Category AuthenticationError
                return $null
            }
		}
    }
    
    Write-Host
    write-error "The Transformation does not have a UserName and Password for you set within `
	/MigrationAutomationConfiguration/GlobalSettings/Transformations/EncryptedAccount" -Category InvalidData
	Write-Host "Use Set-TransformationCredential to set the credential"
    return $null
}

function Get-SMTPCredential
{
    if($(Read-MigrationAutomationConfiguration) -eq $true)
    {
		if($global:GlobalSettings.SMTP.Name -eq "SMTP")
        {
			$ThisUser 				= [Environment]::UserDomainName.ToUpper() + "\" + [Environment]::MachineName.ToUpper() + "\" + [Environment]::UserName.ToUpper()
			$Account 				= $global:GlobalSettings.SMTP.SelectSingleNode("EncryptedAccount[@UserName='$ThisUser']")
			if($global:GlobalSettings.SMTP.AccountName.Length -gt 0 -and $Account.Password.Length -gt 0)
			{
                try
                {
				    $SecurePassword = convertto-securestring -string $Account.Password
                    if($SecurePassword -eq $null)
                    {
                        $SMTPError 	= "Encountered a SMTP credential issue.  You must set the SMTP password using the same account and process which ran the automation."
                        Write-Host $SMTPError
                        if($global:Workitem -ne $null)
                        {
                            $global:Workitem.Auto_Notes = $SMTPError
                        }
                        return $null # TODO: An error is reported.  Need to come up with a suggestion. The convertto-securestring error is "Key not valid for use in specified state."
                    }
   				    $credential 	=  New-Object System.Management.Automation.PSCredential ($global:GlobalSettings.SMTP.AccountName, $SecurePassword)
				    return $credential             
                }
                catch [Exception]
                {
                    Write-Error "You must set the SMTP credential before sending email. Use Set-SMTPCredential." -Category AuthenticationError
                    return $null
                }
			}
        }
    }
    Write-Host
    write-error "The Migration_Coordinator Database does not have a UserName and Password set within `
	/MigrationAutomationConfiguration/GlobalSettings/Databases/Database/EncryptedAccount" -Category InvalidData -RecommendedAction "Use Set-SMTPCredential to set the credential"
    return $null
}


function Set-SMTPCredential
{	
    param([parameter(Mandatory = $false)] [string] $Password)

	$xml = Set-GlobalSettingsInXML
   	if($xml -eq $null)
	{
		return
	}
	
	if($global:GlobalSettings.SMTP.Name -ne "SMTP")
	{
		$SMTP 						= $xml.CreateElement("SMTP")
		$HostName 					= $xml.CreateAttribute("HostName")
		$HostName.Value				= "ReplaceWithSMTPServerName"
		$FromEmail 					= $xml.CreateAttribute("FromEmail")
		$FromEmail.Value 			= "someone@domain.com"
		$AccountName 				= $xml.CreateAttribute("AccountName")
		$AccountName.Value 			= "domain\someone"
		$SMTP.Attributes.Append($HostName) | Out-Null
		$SMTP.Attributes.Append($FromEmail) | Out-Null
		$SMTP.Attributes.Append($AccountName) | Out-Null
		$xml.MigrationAutomationConfiguration.GlobalSettings.AppendChild($SMTP) | Out-Null
	}
	$ThisUser 						= [Environment]::UserDomainName.ToUpper() + "\" + [Environment]::MachineName.ToUpper() + "\" + [Environment]::UserName.ToUpper()
	$Account						= $xml.SelectSingleNode("/MigrationAutomationConfiguration/GlobalSettings/SMTP/EncryptedAccount[@UserName='$ThisUser']")
    $SMTP					        = $xml.SelectSingleNode("/MigrationAutomationConfiguration/GlobalSettings/SMTP")

	$SecurePassword = new-object securestring

	# Do the user interaction first so the file is read-written in the shortest time possible:
	if($Password -eq "")
    {
    	Write-Host "`nEnter the password used by the SMTP account" $SMTP.AccountName ":"
	    Write-Host "     Hint: Edit the the SPSiteMigration-Configuration.xml to change or view the user account.`n"  
        $SecurePassword 			= read-host -assecurestring -Prompt "Password"
    }
    else 
    {
        # Convert the password string to a secure string:
        $PasswordArray = $Password.ToCharArray();
        foreach ($char in $PasswordArray)
        {
            $SecurePassword.AppendChar($char);
        }
    }
	if($Account.Name -ne "EncryptedAccount")
	{
		$EncryptedAccount 			= $xml.CreateElement("EncryptedAccount")
		$UserNameAtt 				= $xml.CreateAttribute("UserName")
		$UserNameAtt.Value 			= $ThisUser
		
		$EncryptedAccount.Attributes.Append($UserNameAtt) | Out-Null
		$xml.MigrationAutomationConfiguration.GlobalSettings.SMTP.AppendChild($EncryptedAccount) | Out-Null
		
		$Account 					= $xml.SelectSingleNode("/MigrationAutomationConfiguration/GlobalSettings/SMTP/EncryptedAccount[@UserName='$ThisUser']")
	}
	$global:GlobalSettings			= $xml.SelectSingleNode("/MigrationAutomationConfiguration/GlobalSettings")
	
	$encryptedPassword 				= convertfrom-securestring -securestring $SecurePassword
	$global:GlobalSettings.SMTP.EncryptedAccount.SetAttribute("Password", $encryptedPassword)
	$xml.Save($(Get-Location).Path +  "\SPSiteMigration-Configuration.xml") | Out-Null
	Write-Host
}

function Get-FarmCredential
{
	param([parameter(Mandatory = $true)] [string] $FarmUrl)
	
    if($(Read-MigrationAutomationConfiguration) -eq $true)
    {
		$uri1 = $FarmUrl -as [System.URI]
		$FarmUrl_cleaned = $uri1.Scheme + "://" + $uri1.Host
        foreach($Node in $global:AutomationNodesXML)
	    {
	        if($Node.Farmname -eq $FarmUrl_cleaned)# -and $Node.Settings.EncryptedAccount.Name.Length -gt 0)
	        {
                $ThisUser 	= [Environment]::UserDomainName.ToUpper() + "\" + [Environment]::MachineName.ToUpper() + "\" + [Environment]::UserName.ToUpper()
			    $Account 	= $Node.Settings.SelectSingleNode("EncryptedAccount[@UserName='$ThisUser']")
				if($Account.AccountName.Length -gt 0 -and $Account.Password.Length -gt 0)
			    {
                    try
                    {
					    $SecurePassword = convertto-securestring -string $Account.Password
                        if($SecurePassword -eq $null)
                        {
                            Write-Host "This is a farm credential issue."
                            return $null # TODO: An error is reported.  Need to come up with a suggestion. The convertto-securestring error is "Key not valid for use in specified state."
                        }
    					$credential =  New-Object System.Management.Automation.PSCredential ($Account.AccountName, $SecurePassword)
	    				return $credential
                    }
                    catch [Exception]
                    {
                        Write-Error "You must set the farm credential before connecting to the farm. Use Set-FarmCredential." -Category AuthenticationError
                        return $null
                    }
				}
                else
                {
                    Write-Error "You must set the farm credential before connecting to the farm. Use Set-FarmCredential." -Category AuthenticationError
                    return $null
                }
	        }
		}
    }
    $errorstring = "The EncryptedAccount node for the farm $FarmUrl_cleaned was not found within /MigrationAutomationConfiguration/MigrationAutomation/Settings"
    Write-Host
    write-error -Message $errorstring -RecommendedAction "Use Set-SMTPCredential to set the credential" -Category InvalidData
    return $null
}

function Set-FarmCredential
{
    param([parameter(Mandatory = $true)] [string] $FarmUrl,
          [parameter(Mandatory = $false)] [string] $AccountName,
          [parameter(Mandatory = $false)] [string] $Password)

    $SecurePassword 				= new-object securestring
    if($Password -eq "" -or $AccountName -eq "")
    {
    	# Do the user interaction first so the file is read-written in the shortest time possible:
	    Write-Host "`nEnter a username and password."
	    $AccountName 				= read-host -Prompt "Username"
	    $SecurePassword 			= read-host -assecurestring -Prompt "Password"
    }
    else 
    {
        # Convert the password string to a secure string:
        $PasswordArray 				= $Password.ToCharArray();
        foreach ($char in $PasswordArray)
        {
            $SecurePassword.AppendChar($char);
        }
        #$AccountName 				= $UserName
    }
	# Do the user interaction first so the file is read-written in the shortest time possible:
    #$AccountName = read-host -Prompt "Username"
	#$Password = read-host -assecurestring -Prompt "Password"
	
	$xml = [xml](get-content SPSiteMigration-Configuration.xml)
    if($xml -isnot [xml])
    {
        return          # get-content will get an exception if the file does not exist.  No need to write the error.
    }
	$global:AutomationNodesXML = $xml.SelectNodes("/MigrationAutomationConfiguration/MigrationAutomation")
    if($global:AutomationNodesXML.Count -eq 0)
    {
        $global:AutomationNodesXML = $null
        Write-Host
        write-error "MigrationAutomation was not found within /MigrationAutomationConfiguration" -Category InvalidData
        return $false
    }
	
	$uri1 = $FarmUrl -as [System.URI]
	$FarmUrl_cleaned = $uri1.Scheme + "://" + $uri1.Host
	foreach($Node in $global:AutomationNodesXML)
    {
        if($Node.Farmname -eq $FarmUrl_cleaned)
        {
            $ThisUser 						= [Environment]::UserDomainName.ToUpper() + "\" + [Environment]::MachineName.ToUpper() + "\" + [Environment]::UserName.ToUpper()
	        $Account 						= $Node.Settings.SelectSingleNode("EncryptedAccount[@UserName='$ThisUser']")
            if($Account.Name -ne "EncryptedAccount")
	        {
		        $EncryptedAccount 			= $xml.CreateElement("EncryptedAccount")
		        $UserNameAtt 				= $xml.CreateAttribute("UserName")
		        $UserNameAtt.Value 			= $ThisUser
		        $EncryptedAccount.Attributes.Append($UserNameAtt) | Out-Null
		        $Node.Settings.AppendChild($EncryptedAccount) | Out-Null
		        $Account 					= $Node.Settings.SelectSingleNode("EncryptedAccount[@UserName='$ThisUser']")
	        }

            try
            {
	            $encryptedPassword 			= convertfrom-securestring -securestring $SecurePassword
            } 
            catch [Exception]
            {
                 write-error $($_.Exception.Message);
                 Write-Host "You need to set the Farm credential"
                 return $null
            }
	        $Account.SetAttribute("AccountName", $AccountName) | Out-Null
	        $Account.SetAttribute("Password", $encryptedPassword) | Out-Null
	        $xml.Save($(Get-Location).Path +  "\SPSiteMigration-Configuration.xml") | Out-Null
            return
			# TODO: Create Node
		}
    }
	$errorstring = "The EncryptedAccount node for the farm $FarmUrl was not found within /MigrationAutomationConfiguration/MigrationAutomation/Settings"
    Write-Host
    write-error -Message $errorstring -Category InvalidData
}


function Get-URLRedirectConnectionString
{
    param([parameter(Mandatory = $true)] [string] $FarmUrl)
    
    if($(Read-MigrationAutomationConfiguration) -eq $false)
    {
        return ""
    }
    
    $uri1 = $FarmUrl -as [System.URI]
	$FarmUrl_cleaned = $uri1.Scheme + "://" + $uri1.Host
    foreach($Node in $global:AutomationNodesXML)
    {
        if($Node.Farmname -eq $FarmUrl_cleaned)
        {
            foreach($dbitem in $Node.Settings.Databases.Database)
            {
                if($dbitem.Name -eq "URLRedirectDB")
                {
                    return $dbitem.ConnectionString
                }
            }
        }
    }
	$ConnectionStringError = "A Database Tag Named 'URLRedirectDB' was not found within /MigrationAutomationConfiguration/MigrationAutomation/Settings/Databases"
    write-error $ConnectionStringError -Category InvalidData
	Write-Host "Make sure the SPSiteMigration-Configuration.XML file has a '$FarmUrl_cleaned' section"
	return ""
}


function Get-FarmServerName
{
    param([parameter(Mandatory = $true)] [string] $FarmUrl)
    
    if($(Read-MigrationAutomationConfiguration) -eq $false)
    {
        return ""
    }
	
    $uri1 = $FarmUrl -as [System.URI]
	$FarmUrl_cleaned = $uri1.Scheme + "://" + $uri1.Host
    foreach($Node in $global:AutomationNodesXML)
    {
        if($Node.Farmname -eq $FarmUrl_cleaned)
        {
            foreach($Serveritem in $Node.Settings.Servers.Server)
            {
                return $Serveritem.Name
            }
        }
    }
    write-error "A Server was not found within /MigrationAutomationConfiguration/MigrationAutomation/Settings/Servers" -Category InvalidData
}

function Get-AzureCredential
{
    Param
    (
        [parameter(Mandatory = $true)] 
        [string] $FarmUrl
    )
    if($(Read-MigrationAutomationConfiguration) -eq $false)
    {
        return ""
    }
	
    $uri1 = $FarmUrl -as [System.URI]
	$FarmUrl_cleaned = $uri1.Scheme + "://" + $uri1.Host
    foreach($Node in $global:AutomationNodesXML)
    {
        if($Node.Farmname -eq $FarmUrl_cleaned)
        {            
            return $Node.Settings.Azure            
        }
    }
    write-error "Azure credentials was not found within /MigrationAutomationConfiguration/MigrationAutomation/Settings/Azure" -Category InvalidData
}


function Set-ScheduledAutomationRates
{	
    $EditedNode = $false

	$xml = [xml](get-content SPSiteMigration-Configuration.xml)
    if($xml -isnot [xml])
    {
        return          # get-content will get an exception if the file does not exist.  No need to write the error.
    }

	$global:AutomationNodesXML = $xml.SelectNodes("/MigrationAutomationConfiguration/MigrationAutomation")
    if($global:AutomationNodesXML.Count -eq 0)
    {
        $global:AutomationNodesXML = $null
        Write-Host
        write-error "MigrationAutomation was not found within /MigrationAutomationConfiguration" -Category InvalidData
        return $false
    }
    
    $LatestScheduledRates = Read-LatestScheduledRates
	
	foreach($Node in $global:AutomationNodesXML)
    {
        $ScheduledRate = $null
		foreach($farmRate in $LatestScheduledRates)
		{
			if($farmRate.WebAppId -eq $Node.WebAppID)
			{
				$ScheduledRate = $farmRate
				break
			}
		}
        if($ScheduledRate -eq $null)
        {
            continue
        }
        write-host "Setting automation rates for WebAppID" $Node.WebAppID

        $EditedNode 						= $true

        if($Node.SelectSingleNode("Settings") -eq $null)
        {
            $Node.AppendChild($node.OwnerDocument.CreateElement("Settings")) | Out-Null
        }

        $Settings 							= $Node.SelectSingleNode("Settings")
	    $WorkingTimeStartOffset 			= $Settings.SelectSingleNode("WorkingTimeStartOffset")
        $WorkingTimeEndOffset				= $Settings.SelectSingleNode("WorkingTimeEndOffset")
        $MaxParallelRate 					= $Settings.SelectSingleNode("MaxParallelRate")

        if($WorkingTimeStartOffset -eq $null)
	    {
		    $Settings.AppendChild($node.OwnerDocument.CreateElement("WorkingTimeStartOffset")) | Out-Null
		    $WorkingTimeStartOffset 		= $Settings.SelectSingleNode("WorkingTimeStartOffset")
	    }
        if($WorkingTimeEndOffset -eq $null)
	    {
		    $Settings.AppendChild($node.OwnerDocument.CreateElement("WorkingTimeEndOffset")) | Out-Null
		    $WorkingTimeEndOffset		 	= $Settings.SelectSingleNode("WorkingTimeEndOffset")
	    }
        if($MaxParallelRate -eq $null)
	    {
		    $Settings.AppendChild($node.OwnerDocument.CreateElement("MaxParallelRate")) | Out-Null
		    $MaxParallelRate 				= $Settings.SelectSingleNode("MaxParallelRate")
	    }
        $WorkingTimeStartOffset.InnerText	= $ScheduledRate.WorkingTimeStartOffset #.ToString()
        $WorkingTimeEndOffset.InnerText		= $ScheduledRate.WorkingTimeEndOffset #.ToString()
        $MaxParallelRate.InnerText			= $ScheduledRate.MaxParallelRate
    }

    # If there were no changes don't write to the file:
    if($EditedNode -eq $true)
    {	
        # BUGBUG: Shouldn't have to write twice, but we're changing two different objects, so this is a work-around:
        # Save the file, re-read, and save it again:
        $CurrentPath						= $(Get-Location).Path
	    $global:AutomationNodesXML[0].OwnerDocument.Save($CurrentPath +  "\SPSiteMigration-Configuration.xml") | Out-Null

        $xml  			 			 		= [xml](get-content SPSiteMigration-Configuration.xml)

        $GlobalSettings  		 			= $xml.SelectSingleNode("/MigrationAutomationConfiguration/GlobalSettings")
        if($GlobalSettings.AutomationData -eq $null)
        {
            $GlobalSettings.AppendChild($xml.CreateElement("AutomationData")) | Out-Null
        }
        $AutomationData  		 			= $GlobalSettings.SelectSingleNode("AutomationData")
        if($AutomationData.DBSettingsSynced -eq $null)
        {
            $AutomationData.AppendChild($xml.CreateElement("DBSettingsSynced")) | Out-Null
        }
        $DBSettingsSynced  			 		= $AutomationData.SelectSingleNode("DBSettingsSynced")
        $DBSettingsSynced.InnerText 	 	= $(get-date).ToString()

        $xml.Save($CurrentPath + "\SPSiteMigration-Configuration.xml") | Out-Null
        $global:AutomationNodesXML 			= $xml.SelectNodes("/MigrationAutomationConfiguration/MigrationAutomation")
        write-host ""
        return
    }
    write-host "The local configuration didn't match the database configuration."
}


function Get-TenateAdminCreds
{
	param([parameter(Mandatory = $true)] [string] $FarmUrl)
	
    if($(Read-MigrationAutomationConfiguration) -eq $true)
    {
		$uri1 				= $FarmUrl -as [System.URI]
		$FarmUrl_cleaned 	= $uri1.Scheme + "://" + $uri1.Host
		$Node 				= $global:GlobalSettings.SelectSingleNode("Destination[@FarmName='$FarmUrl_cleaned']")
        $ThisUser 			= [Environment]::UserDomainName.ToUpper() + "\" + [Environment]::MachineName.ToUpper() + "\" + [Environment]::UserName.ToUpper()
	    $Account 			= $Node.TenantSite.SelectSingleNode("EncryptedAccount[@UserName='$ThisUser']")
		if($Account.AccountName.Length -gt 0 -and $Account.Password.Length -gt 0)
	    {
            try
            {
			    $SecurePassword = convertto-securestring -string $Account.Password
                if($SecurePassword -eq $null)
                {
                    Write-Host "Need tenate admin creds set in the XML."
                    return $null # TODO: An error is reported.  Need to come up with a suggestion. The convertto-securestring error is "Key not valid for use in specified state."
                }
				$credential =  New-Object System.Management.Automation.PSCredential ($Account.AccountName, $SecurePassword)
				return $credential
            }
            catch [Exception]
            {
                Write-Error "You must set the tenate admin credential before connecting to the farm. Use Set-TenateAdminCreds." -Category AuthenticationError
                return $null
            }
		}
        else
        {
            Write-Error "You must set the farm credential before connecting to the farm. Use Set-TenateAdminCreds." -Category AuthenticationError
            return $null
        }
    }
    $errorstring = "The EncryptedAccount node for the farm $FarmUrl_cleaned was not found within /MigrationAutomationConfiguration/GlobalSettings/Destination"
    Write-Host
    write-error -Message $errorstring -RecommendedAction "Use Set-TenateAdminCreds to set the credential" -Category InvalidData
    return $null
}

function Set-TenateAdminCreds
{
	param([parameter(Mandatory = $true)] [string] $FarmUrl)
	
	# Do the user interaction first so the file is read-written in the shortest time possible:
    $AccountName 					= read-host -Prompt "Tenate Admin Username"
	$Password 						= read-host -assecurestring -Prompt "Password"
	
	$xml 							= [xml](get-content SPSiteMigration-Configuration.xml)
    if($xml -isnot [xml])
    {
		Write-Error "The SPSiteMigration-Configuration.xml files does not exist in the current directory."
        return
    }
	$uri1 							= $FarmUrl -as [System.URI]
	$FarmUrl_cleaned 				= $uri1.Scheme + "://" + $uri1.Host
	$DestinationNode 				= $xml.SelectSingleNode("/MigrationAutomationConfiguration/GlobalSettings/Destination[@FarmName='$FarmUrl_cleaned']")

	# If the destination doesn't exist, create it:
    if($DestinationNode -eq $null)
    {
		$TenateSiteName 			= read-host -Prompt "URL of the Tenate site"
		
		$DestinationNode 			= $xml.CreateElement("Destination")
        $FarmNameAtt 				= $xml.CreateAttribute("FarmName")
		$FarmNameAtt.Value			= $FarmUrl
		$DestinationNode.Attributes.Append($FarmNameAtt) | Out-Null
		$xml.MigrationAutomationConfiguration.GlobalSettings.Settings.AppendChild($DestinationNode) | Out-Null
		$DestinationNode 			= $xml.SelectSingleNode("/MigrationAutomationConfiguration/GlobalSettings/Destination[@FarmName='$FarmUrl_cleaned']")
	}
	if($DestinationNode.$TenantSiteNode -eq $null)
	{
		$TenantSiteNode 			= $xml.CreateElement("TenantSite")
        $TenantSiteNameAtt 			= $xml.CreateAttribute("Name")
		$TenantSiteNameAtt.Value	= $TenateSiteName
		$TenantSiteNode.Attributes.Append($TenantSiteNameAtt) | Out-Null
		$DestinationNode.AppendChild($TenantSiteNode) | Out-Null
    }
    $ThisUser 						= [Environment]::UserDomainName.ToUpper() + "\" + [Environment]::MachineName.ToUpper() + "\" + [Environment]::UserName.ToUpper()
    $Account 						= $DestinationNode.TenantSite.SelectSingleNode("EncryptedAccount[@UserName='$ThisUser']")
    if($Account.Name -ne "EncryptedAccount")
    {
        $EncryptedAccount 			= $xml.CreateElement("EncryptedAccount")
        $UserNameAtt 				= $xml.CreateAttribute("UserName")
        $UserNameAtt.Value 			= $ThisUser
        $EncryptedAccount.Attributes.Append($UserNameAtt) | Out-Null
        $DestinationNode.TenantSite.AppendChild($EncryptedAccount) | Out-Null
        $Account 					= $DestinationNode.TenantSite.SelectSingleNode("EncryptedAccount[@UserName='$ThisUser']")
    }
    try
    {
        $encryptedPassword 	= convertfrom-securestring -securestring $Password
    } 
    catch [Exception]
    {
         write-error $($_.Exception.Message)
         Write-Host "You need to set the Tenate Admin credential"
         return
    }
    $Account.SetAttribute("AccountName", $AccountName) | Out-Null
    $Account.SetAttribute("Password", $encryptedPassword) | Out-Null
    $xml.Save($(Get-Location).Path +  "\SPSiteMigration-Configuration.xml") | Out-Null
    return
}