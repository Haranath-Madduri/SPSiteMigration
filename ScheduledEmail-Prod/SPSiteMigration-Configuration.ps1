
function Read-MigrationAutomationConfiguration
{
    if($global:AutomationNodesXML -eq $null -or $global:FailureSequences -eq $null)
    {
        $xml                       = [xml](get-content SPSiteMigration-Configuration.xml)
        if($xml -isnot [xml])
        {
            return $false          # get-content will get an exception if the file does not exist.  No need to write the error.
        }
        
        $global:AutomationNodesXML = $xml.SelectNodes("/MigrationAutomationConfiguration/MigrationAutomation")
        if($global:AutomationNodesXML.Count -eq 0)
        {
            $global:AutomationNodesXML = $null
            Write-Host
            write-error "MigrationAutomation was not found within /MigrationAutomationConfiguration" -Category InvalidData
            return $false
        }
        
		$global:GlobalSettings   = $xml.SelectSingleNode("/MigrationAutomationConfiguration/GlobalSettings")
        if($global:GlobalSettings.Name -ne "GlobalSettings")
        {
            $global:GlobalSettings = $null
            Write-Host
            write-error "GlobalSettings were not found within /MigrationAutomationConfiguration" -Category InvalidData
            return $false
        }
		        
        $global:FailureSequences   = $xml.SelectNodes("/MigrationAutomationConfiguration/FailureSequences")
        if($global:FailureSequences.Count -eq 0)
        {
            $global:FailureSequences = $null
            Write-Host
            write-error "FailureSequences were not found within /MigrationAutomationConfiguration" -Category InvalidData
            return $false
        }
    }
    return $true
}

function Get-MigrationCoordinatorConnectionString
{
    $ret = Read-MigrationAutomationConfiguration
    if($ret -eq $true)
    {
		$MigrationCoordinator = $global:GlobalSettings.Databases.SelectSingleNode("Database[@Name='Migration_Coordinator']")
        if($MigrationCoordinator.Name -eq "Migration_Coordinator")
        {
			$Credential = Get-MigrationCoordinatorCredential	# Only needed if "Integrated Security=$false", but call every time.
			$UserName = $Credential.UserName
			$Password = $Credential.GetNetworkCredential().Password
            return $ExecutionContext.InvokeCommand.ExpandString($MigrationCoordinator.ConnectionString)
        }
    }
    Write-Host
    write-error "The Migration_Coordinator Database was not found within /MigrationAutomationConfiguration/GlobalSettings/Databases" -Category InvalidData
    return ""
}

function Get-MigrationCoordinatorCredential
{
    $ret = Read-MigrationAutomationConfiguration
    if($ret -eq $true)
    {
		$MigrationCoordinator = $global:GlobalSettings.Databases.SelectSingleNode("Database[@Name='Migration_Coordinator']")
        if($MigrationCoordinator.Name -eq "Migration_Coordinator")
        {
			$ThisUser 	= [Environment]::UserDomainName + "\" + [Environment]::MachineName + "\" + [Environment]::UserName
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
	# Do the user interaction first so the file is read-written in the shortest time possible:
	Write-Host
	Write-Host "Enter a username and password that has execute access to the Coordinator database."
	Write-Host "      Hint: SQL in Azure uses a name only (eg. 'tony')"
	Write-Host
	$AccountName = read-host -Prompt "Username"
	$Password = read-host -assecurestring -Prompt "Password"
	
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

	    Write-Host
	    write-error "The Migration_Coordinator Database was not found within /MigrationAutomationConfiguration/GlobalSettings/Databases" -Category InvalidData
		Write-Host "A Migration_Coordinator entry was created, but the database name must be set manually."
		Write-Host
    }	

	$ThisUser 						= [Environment]::UserDomainName + "\" + [Environment]::MachineName + "\" + [Environment]::UserName
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
    try{
	    $encryptedPassword 	= convertfrom-securestring -securestring $Password
    } 
    catch [Exception]
    {
         write-error $($_.Exception.Message);
         Write-Host "You need to set the migration coordinator credential"
         return $null
    }
	$Account.SetAttribute("AccountName", $AccountName) | Out-Null
	$Account.SetAttribute("Password", $encryptedPassword) | Out-Null
	$location = Get-Location
	$xml.Save($location.Path +  "\SPSiteMigration-Configuration.xml") | Out-Null
	Write-Host
	# TODO: Check to see if we actually have access
}

function Get-SMTPCredential
{
    $ret = Read-MigrationAutomationConfiguration
    if($ret -eq $true)
    {
		if($global:GlobalSettings.SMTP.Name -eq "SMTP")
        {
			$ThisUser 	= [Environment]::UserDomainName + "\" + [Environment]::MachineName + "\" + [Environment]::UserName
			$Account 	= $global:GlobalSettings.SMTP.SelectSingleNode("EncryptedAccount[@UserName='$ThisUser']")
			if($global:GlobalSettings.SMTP.AccountName.Length -gt 0 -and $Account.Password.Length -gt 0)
			{
                try
                {
				    $SecurePassword = convertto-securestring -string $Account.Password
                    if($SecurePassword -eq $null)
                    {
                        Write-Host "This is a SMTP credential issue."
                        return $null # TODO: An error is reported.  Need to come up with a suggestion. The convertto-securestring error is "Key not valid for use in specified state."
                    }
   				    $credential 	=  New-Object System.Management.Automation.PSCredential ($global:GlobalSettings.SMTP.AccountName, $SecurePassword)
				    return $credential             }
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
	$ThisUser 						= [Environment]::UserDomainName + "\" + [Environment]::MachineName + "\" + [Environment]::UserName
	$Account						= $xml.SelectSingleNode("/MigrationAutomationConfiguration/GlobalSettings/SMTP/EncryptedAccount[@UserName='$ThisUser']")
    $SMTP					        = $xml.SelectSingleNode("/MigrationAutomationConfiguration/GlobalSettings/SMTP")
	
	Write-Host "`nEnter the password used by the SMTP account" $SMTP.AccountName ":"
	Write-Host "     Hint: Edit the the SPSiteMigration-Configuration.xml to change or view the user account.`n"  

	# Do the user interaction first so the file is read-written in the shortest time possible:
	$Password = read-host -assecurestring -Prompt "Password"
	
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
	
	$encryptedPassword = convertfrom-securestring -securestring $Password
	$global:GlobalSettings.SMTP.EncryptedAccount.SetAttribute("Password", $encryptedPassword)
	$location = Get-Location
	$xml.Save($location.Path +  "\SPSiteMigration-Configuration.xml") | Out-Null
	Write-Host
}

function Get-FarmCredential
{
	param([parameter(Mandatory=$true)] [string] $FarmUrl)
	
    $ret = Read-MigrationAutomationConfiguration
    if($ret -eq $true)
    {
		$uri1 = $FarmUrl -as [System.URI]
		$FarmUrl_cleaned = $uri1.Scheme + "://" + $uri1.Host
        foreach($Node in $global:AutomationNodesXML)
	    {
	        if($Node.Farmname -eq $FarmUrl_cleaned -and $Node.Settings.EncryptedAccount.Name.Length -gt 0)
	        {
				if($Node.Settings.EncryptedAccount.Password.Length -gt 0 -and $Node.Settings.EncryptedAccount.UserName.Length -gt 0 )
				{
                    try
                    {
					    $SecurePassword = convertto-securestring -string $Node.Settings.EncryptedAccount.Password
                        if($SecurePassword -eq $null)
                        {
                            Write-Host "This is a farm credential issue."
                            return $null # TODO: An error is reported.  Need to come up with a suggestion. The convertto-securestring error is "Key not valid for use in specified state."
                        }
    					$credential =  New-Object System.Management.Automation.PSCredential ($Node.Settings.EncryptedAccount.UserName, $SecurePassword)
	    				return $credential
                    }
                    catch [Exception]
                    {
                        Write-Error "You must set the farm credential before connecting to the farm. Use Set-FarmCredential." -Category AuthenticationError
                        return $null
                    }
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
    param([parameter(Mandatory=$true)] [string] $FarmUrl)

	# Do the user interaction first so the file is read-written in the shortest time possible:
	$UserName = read-host -Prompt "Username"
	$Password = read-host -assecurestring -Prompt "Password"
	
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
			if($Node.Settings.EncryptedAccount.Name.Length -gt 0)
			{
				$encryptedPassword = convertfrom-securestring -securestring $Password
				$Node.Settings.EncryptedAccount.SetAttribute("UserName", $UserName)
				$Node.Settings.EncryptedAccount.SetAttribute("Password", $encryptedPassword)
				$location = Get-Location
				$xml.Save($location.Path +  "\SPSiteMigration-Configuration.xml")
				return
			}
			# TODO: Create Node
		}
    }
	$errorstring = "The EncryptedAccount node for the farm $FarmUrl was not found within /MigrationAutomationConfiguration/MigrationAutomation/Settings"
    Write-Host
    write-error -Message $errorstring -Category InvalidData
}


function Get-URLRedirectConnectionString
{
    param([parameter(Mandatory=$true)] [string] $FarmUrl)
    
    $reterror = Read-MigrationAutomationConfiguration
    if($reterror -eq $false)
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
    write-error "A Database Tag Named URLRedirectDB was not found within /MigrationAutomationConfiguration/MigrationAutomation/Settings/Databases" -Category InvalidData
}


function Get-FarmServerName
{
    param([parameter(Mandatory=$true)] [string] $FarmUrl)
    
    $reterror = Read-MigrationAutomationConfiguration
    if($reterror -eq $false)
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