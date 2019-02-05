# These settings enable Basic unencrypted authentication for WinRM
# They also set large limits to the amount of memory per shell and number of shells per user

Set-Item -Path WSMan:\localhost\Service\Auth\Basic -Value $true
Set-Item -Path WSMan:\localhost\Service\AllowUnencrypted -Value $true
Set-Item -Path WSMan:\localhost\Shell\MaxShellsPerUser -Value 50
Set-Item -Path WSMan:\localhost\Shell\MaxProcessesPerShell -Value 1000
Set-Item -Path WSMan:\localhost\Shell\MaxMemoryPerShellMB -Value 2048
Set-Item -Path WSMan:\localhost\Plugin\Microsoft.PowerShell\Quotas\MaxMemoryPerShellMB -Value 2048
Set-Item -Path WSMan:\localhost\MaxTimeoutms -Value 7200000
