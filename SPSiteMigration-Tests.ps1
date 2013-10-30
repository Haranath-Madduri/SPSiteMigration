
function test-DoesSiteExist
{
    param([parameter(Mandatory=$true)] [System.URI] $HostName )
    
    # TODO: Verify that the destination URL exists before redirection. Report error if not.

    return $true
}

function check-PerformingTest
{
	param([parameter(Mandatory=$true)] [System.Data.DataRow] $Workitem )
	return $true
}

function check-InitialEmailDidntSendInTime
{
    param([parameter(Mandatory=$true)] [System.Data.DataRow] $Workitem )
	return $false
}

function check-TestActiveSequences
{
	param([parameter(Mandatory=$true)] [System.Data.DataRow] $Workitem )
	$numseq = Get-NumberOfActiveSequences $Workitem["WebAppID"]
    if($workitem["Auto_MaxParallelRate"] -gt $numseq)
	{
		Write-Host $numseq "threads are running."
		return $true
	}
	#"Over" + $numseq + ">" + $workitem["Auto_MaxParallelRate"] | Out-file testoutput.txt -Append
	return $false
}

function Test_WaitAMin
{
	sleep -Seconds 60
	return $true
}

function Get-TestCredential
{
    if($(Read-MigrationAutomationConfiguration) -eq $true)
    {
		$TestSettings 	= $global:GlobalSettings.TestSettings
		$Account 		= $TestSettings.TestAccount

		if($Account.Name.Length -gt 0 -and $Account.Password.Length -gt 0)
		{
            try
            {
			    $SecurePassword = convertto-securestring -string $Account.Password
                if($SecurePassword -eq $null)
                {
                    Write-Host "This is a transformation credential issue."
                    return $null
                }
			    $credential 	=  New-Object System.Management.Automation.PSCredential ($Account.Name, $SecurePassword)
			    return $credential
            }
            catch [Exception]
            {
                Write-Error "You must set the transformation credential before using it. Use Set-TestCredential." -Category AuthenticationError
                return $null
            }
		}
    }
    Write-Error "Didn't get the test credential."
    return $null
}

function Set-TestCredential
{
 	param([parameter(Mandatory = $false)] [string] $Password)
	
 	$SecurePassword 				= new-object securestring
    if($Password -eq "")
    {
    	# Do the user interaction first so the file is read-written in the shortest time possible:
	    Write-Host "`nEnter a password."
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
    }
	$xml 							= Set-GlobalSettingsInXML
	if($xml -eq $null)
	{
		return
	}
	$TestSettings                 	= $global:GlobalSettings.TestSettings
	$Account 						= $TestSettings.TestAccount
    try{
	    $encryptedPassword 			= convertfrom-securestring -securestring $SecurePassword
    } 
    catch [Exception]
    {
         write-error $($_.Exception.Message);
         return $null
    }
	$Account.SetAttribute("Password", $encryptedPassword) | Out-Null
	$xml.Save($(Get-Location).Path +  "\SPSiteMigration-Configuration.xml") | Out-Null
	Write-Host
}

function Test_ConnectToTestServer
{
	if($(Read-MigrationAutomationConfiguration) -eq $true)
    {
		try
		{
	    	$ret = Invoke-Command -ScriptBlock $({ sleep -Seconds 2; return $true }) -Credential $(Get-TestCredential) -Authentication Credssp -ComputerName $global:GlobalSettings.TestSettings.TestMachine.Name
			if($ret -ne $true)
			{
				return $false
			}
			sleep -Seconds 2
	    	$ret = Invoke-Command -ScriptBlock $({ sleep -Seconds 2; return $true }) -Credential $(Get-TestCredential) -Authentication Credssp -ComputerName $global:GlobalSettings.TestSettings.TestMachine.Name
			if($ret -ne $true)
			{
				return $false
			}
	    	return Invoke-Command -ScriptBlock $({ sleep -Seconds 5; return $true }) -Credential $(Get-TestCredential) -Authentication Credssp -ComputerName $global:GlobalSettings.TestSettings.TestMachine.Name
			sleep -Seconds 1
		}
		catch [Exception]
		{
			return $false
		}
	}
	return $false
}