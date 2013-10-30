
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
