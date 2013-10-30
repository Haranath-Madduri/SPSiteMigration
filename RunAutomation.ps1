#Set-SMTPCredential -Password <Password>
#Set-MigrationCoordinatorCredential -UserName <AccountName> -Password <Password>

. .\SPSiteMigration.ps1
#Start-Sequences

Set-MigrationCoordinatorCredential -UserName '' -Password ''
Set-TransformationCredential -AccountName '' -Password ''
Set-SMTPCredential -Password ''
Set-FarmCredential -FarmUrl '' -AccountName '' -Password ''