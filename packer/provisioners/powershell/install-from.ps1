$ErrorActionPreference = "Stop"
$VerbosePreference = "Continue"

# Default Values
$script:install_from = 'url'
#$script:installer_type = 'msi'

$script:aws_region = 'eu-west-1'

$script:temp_folder = "C:\Windows\Temp\"

$script:force_download = $false

$script:display_name_match = $false
$script:force_install = $false

$script:file_scheme = 'file://'

$script:allowed_exit_codes = @(0, 3010)

$script:post_install = if ([String]::IsNullOrEmpty($env:POST_INSTALL)) { '' } else { $env:POST_INSTALL }
$script:post_install_compress_path = if ([String]::IsNullOrEmpty($env:POST_INSTALL_COMPRESS_PATH)) { ''} else { $env:POST_INSTALL_COMPRESS_PATH }
$script:post_install_compress_output_path = if ([String]::IsNullOrEmpty($env:POST_INSTALL_COMPRESS_OUTPUT_PATH)) { '' } else { $env:POST_INSTALL_COMPRESS_OUTPUT_PATH }

function Write-Header {
    param (
        [string]$Message,
        [string]$Overline='=',
        [string]$Underline='='
    )

    Write-Verbose ("$Overline" * 80)
    Write-Verbose "$Message"
    Write-Verbose ("$Underline" * 80)
}

function Write-SubHeader {
    param (
        [string]$Message
    )

    Write-Header -Message $Message -Overline '-' -Underline '-'
}

function Get-Arguments {
    if (!([String]::IsNullOrEmpty($env:INSTALLER_URI))) {
        if ($env:INSTALLER_URI.StartsWith("$script:file_scheme", 'CurrentCultureIgnoreCase')) {
            $env:INSTALL_FROM = 'file'
        }
    }

    if (!([String]::IsNullOrEmpty($env:INSTALL_FROM))) {
        $script:install_from = $env:INSTALL_FROM.ToLower()
    }
    Write-Verbose "INSTALL_FROM: '${env:INSTALL_FROM}' ($script:install_from)"

    if ($script:install_from -eq 'url' -or $script:install_from -eq 'file') {
        if ([String]::IsNullOrEmpty($env:INSTALLER_URI)) {
            throw "ERROR: Environment variable needs to be set: INSTALLER_URI"
        }
        Write-Verbose "`$env:INSTALLER_URI = `"$env:INSTALLER_URI`""
    } elseif ($script:install_from -eq 's3') {
        if ([String]::IsNullOrEmpty($env:S3_BUCKET)) {
            throw "ERROR: Environment variable needs to be set: S3_BUCKET"
        }
        Write-Verbose "`$env:S3_BUCKET = `"$env:S3_BUCKET`""

        if ([String]::IsNullOrEmpty($env:S3_KEY) -and [String]::IsNullOrEmpty($env:S3_FOLDER)) {
            throw "ERROR: Environment variable needs to be set: S3_KEY OR S3_FOLDER"
        }
        Write-Verbose "`$env:S3_KEY = `"$env:S3_KEY`""

        if (!([String]::IsNullOrEmpty($env:AWS_REGION))) {
            $script:aws_region = $env:AWS_REGION
        }
        Write-Verbose "AWS_REGION: '${env:AWS_REGION}' ($script:aws_region)"
    }

    if (!([String]::IsNullOrEmpty($env:INSTALLER_TYPE))) {
        $script:installer_type = $env:INSTALLER_TYPE.ToLower()
    }
    Write-Verbose "INSTALLER_TYPE: '${env:INSTALLER_TYPE}' ($script:installer_type)"

    if ([String]::IsNullOrEmpty($env:INSTALLER_DISPLAYNAME)) {
        throw "ERROR: Environment variable needs to be set: INSTALLER_DISPLAYNAME"
    }
    Write-Verbose "`$env:INSTALLER_DISPLAYNAME = `"$env:INSTALLER_DISPLAYNAME`""

    if (!([String]::IsNullOrEmpty($env:ALLOWED_EXIT_CODES))) {
        $script:allowed_exit_codes = [String]$env:ALLOWED_EXIT_CODES -split ','
    }
    Write-Verbose "`$env:ALLOWED_EXIT_CODES = `"$env:ALLOWED_EXIT_CODES`""

    if (!([String]::IsNullOrEmpty($env:TEMP_FOLDER))) {
        $script:temp_folder = $env:TEMP_FOLDER
    }
    Write-Verbose "TEMP_FOLDER: '${env:TEMP_FOLDER}' ($script:temp_folder)"

    if (!([String]::IsNullOrEmpty($env:DISPLAY_NAME_MATCH))) {
        try {
            $script:display_name_match = ([System.Convert]::ToBoolean($env:DISPLAY_NAME_MATCH))
        } catch {
            throw "ERROR: Converting `$env:DISPLAY_NAME_MATCH ('$env:DISPLAY_NAME_MATCH') to boolean!"
        }
    }
    Write-Verbose "FORCE_DOWNLOAD: '${env:FORCE_DOWNLOAD}' ($script:display_name_match)"

    if (!([String]::IsNullOrEmpty($env:FORCE_DOWNLOAD))) {
        try {
            $script:force_download = ([System.Convert]::ToBoolean($env:FORCE_DOWNLOAD))
        } catch {
            throw "ERROR: Converting `$env:FORCE_DOWNLOAD ('$env:FORCE_DOWNLOAD') to boolean!"
        }
    }
    Write-Verbose "FORCE_DOWNLOAD: '${env:FORCE_DOWNLOAD}' ($script:force_download)"

    if (!([String]::IsNullOrEmpty($env:FORCE_INSTALL))) {
        try {
            $script:force_install = ([System.Convert]::ToBoolean($env:FORCE_INSTALL))
        } catch {
            throw "ERROR: Converting `$env:FORCE_INSTALL ('$env:FORCE_INSTALL') to boolean!"
        }
    }
    Write-Verbose "FORCE_INSTALL: '${env:FORCE_INSTALL}' ($script:force_install)"

    if (@('file', 'url', 's3') -notcontains $script:install_from) {
        throw "ERROR: `$env:INSTALL_FROM unsupported value: $script:install_from"
    }

    if (@('msi', 'exe', 'iso', 'msu') -notcontains $script:installer_type) {
        Write-Verbose "WARNING: `$env:INSTALLER_TYPE unsupported value: $script:installer_type . This step will download file only if accepted."
    }

    Write-Verbose ('-' * 80)
}

# function Get-Uninstall: http://stackoverflow.com/questions/4753051/how-do-i-check-if-a-particular-msi-is-installed
function Get-Uninstall
{
    # paths: x86 and x64 registry keys are different
    if ([IntPtr]::Size -eq 4) {
        $path = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*'
    }
    else {
        $path = @(
            'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*'
            'HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
        )
    }

    # get all data
    Get-ItemProperty $path |
    # use only with name and uninstall information
    .{process{ if ($_.DisplayName -and $_.UninstallString) { $_ } }} |
    # select more or less common subset of properties
    Select-Object DisplayName, Publisher, InstallDate, DisplayVersion, HelpLink, UninstallString |
    # and finally sort by name
    Sort-Object DisplayName
}

function Invoke-Cmd {
    param (
        $Program,
        $Arguments,
        $UserName,
        $Password
    )

    Write-Verbose "$Program $Arguments"

    $pinfo = New-Object System.Diagnostics.ProcessStartInfo
    $pinfo.FileName = $Program
    $pinfo.RedirectStandardError = $true
    $pinfo.RedirectStandardOutput = $true
    $pinfo.UseShellExecute = $false
    $pinfo.Arguments = $Arguments

    if (!([String]::IsNullOrEmpty($UserName))) {
        $psinfo.UserName = $UserName
    }

    if (!([String]::IsNullOrEmpty($Password))) {
        $psinfo.Password = $Password
    }

    $p = New-Object System.Diagnostics.Process
    $p.StartInfo = $pinfo
    $p.Start() | Out-Null
    $p.WaitForExit()

    $stdout = $p.StandardOutput.ReadToEnd()
    $stderr = $p.StandardError.ReadToEnd()

    Write-Verbose "Stdout: $stdout"
    Write-Verbose "Stderr: $stderr"
    Write-Verbose "Exit Code: $($p.ExitCode)"

    return $p
}

function Get-FromUrl
{
    param (
        [string]$TempFolder,
        [bool]$ForceDownload = $false
    )

    Write-SubHeader "Downloading From URL"

    $filename = [System.IO.Path]::GetFilename($env:INSTALLER_URI)
    if (!([String]::IsNullOrEmpty($env:INSTALLER_NAME))) {
        $filename = $env:INSTALLER_NAME
    }

    $localFile = Join-Path -Path $TempFolder -ChildPath $filename

    if (!(Test-Path $localFile) -or $ForceDownload -eq $true) {
        $retries = 3
        while ($retries -gt 0) {
            try {
                (New-Object System.Net.WebClient).DownloadFile($env:INSTALLER_URI, $localFile)
                break
            } catch [System.Exception] {
                Write-Verbose "WARNING: Problem downloading file: $env:INSTALLER_URI"
                Write-Verbose "$_"
                $retries--
                if ($retries -eq 0) {
                    throw "ERROR: Downloading file: $($_.Exception.Message)"
                }
                Start-Sleep -s 10
            }
        }

        if (!(Test-Path $localFile)) {
            throw "ERROR: Downloaded file cannot be found: $localFile"
        }
    }

    return @{
        'Filename' = $filename;
        'LocalFile' = $localFile
    }
}

function Get-FromS3
{
    param (
        [string]$AWSRegion,
        [string]$TempFolder,
        [bool]$ForceDownload = $false
    )

    Write-SubHeader "Downloading From S3"

    if (!([String]::IsNullOrEmpty($env:S3_KEY))) {
        $filename = [System.IO.Path]::GetFilename($env:S3_KEY)
    }
    elseif (!([String]::IsNullOrEmpty($env:S3_FOLDER))) {
        $filename = [System.IO.Path]::GetFilename($env:S3_FOLDER)
    }
    $localFile = Join-Path -Path $TempFolder -ChildPath $filename

    if (!(Test-Path $localFile) -or $ForceDownload -eq $true) {

        $arguments = @{}
        if (!([String]::IsNullOrEmpty($env:AWS_ACCESS_KEY_ID))) {
            $arguments.AccessKey = $env:AWS_ACCESS_KEY_ID
        }

        if (!([String]::IsNullOrEmpty($env:AWS_SECRET_ACCESS_KEY))) {
            $arguments.SecretKey = $env:AWS_SECRET_ACCESS_KEY
        }

        if (!([String]::IsNullOrEmpty($env:AWS_SESSION_TOKEN))) {
            $arguments.SessionToken = $env:AWS_SESSION_TOKEN
        }

        if (!([String]::IsNullOrEmpty($AWSRegion))) {
            $arguments.Region = $AWSRegion
        }

        try {
            if ([String]::IsNullOrEmpty($env:S3_FOLDER)) {
                Copy-S3Object -BucketName $env:S3_BUCKET -Key $env:S3_KEY -LocalFile $localFile @arguments | Out-Null

                if (!(Test-Path $localFile)) {
                    throw "ERROR: Installer cannot be found: $localFile"
                }
            }
            else {
                $objects = Get-S3Object -BucketName $env:S3_BUCKET -KeyPrefix $env:S3_FOLDER @arguments
                foreach ($object in $objects) {
                    $localFileName = $object.Key -replace "$($env:S3_FOLDER)/", ''
                    if ($localFileName -ne '') {
                        $localFilePath = Join-Path $TempFolder $localFileName

                        if ($object.Size -ne 0) {
                            Write-Verbose "Downloading: $localFilePath"
                            Copy-S3Object -BucketName $env:S3_BUCKET -Key $object.Key -LocalFile $localFilePath @arguments | Out-Null
                        }
                        else {
                            Write-Verbose "Skipping download due to zero size: $localFilePath"
                        }
                    }
                }
            }
        } catch {
            throw "ERROR: $_"
        }
    }

    return @{
        'Filename' = $filename;
        'localFile' = $localFile
    }
}

function Install-Certs {
    if (!([String]::IsNullOrEmpty($env:INSTALL_CERTS))) {
        Write-SubHeader "Installing Certs"

        $certs = $env:INSTALL_CERTS -Split ','
        foreach ($cert in $certs) {
            Invoke-Cmd -Program 'certutil.exe' -Arguments "-addstore -f `"TrustedPublisher`" $cert"
        }
    }
}

function Install-MSI
{
    param (
        [string]$InstallerPath
    )

    Write-SubHeader "Installing MSI"

    if (!(Test-Path $InstallerPath)) {
        throw "ERROR: Installer cannot be found: $InstallerPath"
    }

    $path = Split-Path -Path $InstallerPath
    $logFilename = [System.IO.Path]::GetFileNameWithoutExtension($InstallerPath) + '.log'
    $logFile = Join-Path -Path $path -ChildPath $logFilename
    $arguments = "/qn /i $InstallerPath /norestart /log $logFile"
    try {
      Invoke-Cmd -Program 'msiexec.exe' -Arguments $arguments
    } catch {
      throw $_
    } finally {
        if (Test-Path $logFile) {
            Get-Content -Path $logFile
        }
    }
}

function Install-EXE
{
    param (
        $InstallerPath
    )

    Write-SubHeader "Installing Exe"

    if (!(Test-Path $InstallerPath)) {
        Write-Verbose "ERROR: Installer cannot be found: $InstallerPath"
        throw "ERROR: Installer cannot be found: $InstallerPath"
    }

    $arguments = " "
    if (!([String]::IsNullOrEmpty($env:INSTALL_EXE_ARGUMENTS))) {

        if ([String]$env:INSTALL_EXE_ARGUMENTS_KEYVALUEPAIR -ne "true") {
            $arguments = "$env:INSTALL_EXE_ARGUMENTS"
        }
        else {
            $arguments = ""
            $argPairsArray = [String]$env:INSTALL_EXE_ARGUMENTS -split ';'
            $argKeyValuesHash = @{}

            $argPairsArray | ForEach-Object {
                $keyValuePair = $_ -split ','
                $argKeyValuesHash.Add($keyValuePair[0], $keyValuePair[1])
            }

            $argKeyValuesHash.GetEnumerator() | ForEach-Object {
                $arguments += " $($_.Key)=$($_.Value)"
            }
        }
    }

    try {
        if (!([String]::IsNullOrEmpty($env:USER_NAME)) -and !([String]::IsNullOrEmpty($env:USER_PASSWORD))) {
            $result = (Invoke-Cmd -Program "$InstallerPath" -Arguments $arguments -UserName $env:USER_NAME -Password $env:USER_PASSWORD)
        }
        else {
            $result = (Invoke-Cmd -Program "$InstallerPath" -Arguments $arguments)
        }

        if ($script:allowed_exit_codes -notcontains $result.ExitCode) {
            $allowed_exit_codes = $script:allowed_exit_codes -Join ','
            throw "ERROR: Installation was not successful. EXITCODE '$($result.ExitCode)' in not allowed ($allowed_exit_codes)"
        }

        if ($result.ExitCode -eq 3010) {
            Write-Verbose "Catch EXITCODE 3010. Installation was successful but reboot required. Restarting Windows..."
            Restart-Computer
            break
        }
    } catch {
        throw $_
    }
}

function Install-ISO
{
    param (
        $InstallerPath
    )

    Write-SubHeader "Installing ISO"

    if ([String]::IsNullOrEmpty($env:INSTALLER_NAME)) {
        throw "ERROR: `$env:INSTALLER_NAME not defined"
    }

    if (!(Test-Path $InstallerPath)) {
        throw "ERROR: Installer cannot be found: $InstallerPath"
    }

    try {

        $mountResult = Mount-DiskImage $InstallerPath -PassThru
        $driveLetterMounted = ($mountResult | Get-Volume).DriveLetter
        Write-Verbose "Image mounted on $driveLetterMounted from path: $InstallerPath"

        $mountedDriveInstallerPath = "$($driveLetterMounted):\$($env:INSTALLER_NAME)"

        if ($env:INSTALLER_NAME -match '.msi') {
            Install-MSI $mountedDriveInstallerPath
        } elseif ($env:INSTALLER_NAME -match '.exe') {
            Install-EXE $mountedDriveInstallerPath
        }

    } catch {
      throw $_
    }
}

function Install-MSU
{
    param (
        $InstallerPath
    )

    Write-SubHeader "Installing MSU"

    if (!(Test-Path $InstallerPath)) {
        throw "ERROR: Installer cannot be found: $InstallerPath"
    }

    $arguments = "/install $InstallerPath /quiet /norestart"
    try {
      Invoke-Cmd -Program 'wusa.exe' -Arguments $arguments
    } catch {
      throw $_
    }
}

function Get-InstalledApp
{
    param (
        $InstalledApps,
        $DisplayName,
        $MatchDisplayName=$false
    )

    Write-SubHeader "Getting Installed App"

    if ([String]::IsNullOrEmpty($DisplayName)) {
        Write-Verbose "WARN: `$env:DISPLAY_NAME"
        return $null
    }

    if ($MatchDisplayName) {
        $installed = ($InstalledApps | Where-Object { $_.DisplayName -match $DisplayName })
    } else {
        $installed = ($InstalledApps | Where-Object { $_.DisplayName -eq $DisplayName })
    }

    if ($installed) {
        Write-Verbose "Application '${env:INSTALLER_DISPLAYNAME}' is already installed: -"
        Write-Verbose ($installed | Out-String)
        return $installed
    }

    return $null
}

function Expand-File
{
    param (
        [string]$Path
    )

    if ([String]::IsNullOrEmpty($env:INSTALLER_NAME) -eq $false -and [System.IO.Path]::GetExtension("$Path").ToLower() -eq '.zip') {
        Write-SubHeader "Expanding file: $Path"

        $filename = [System.IO.Path]::GetFileNameWithoutExtension($Path)
        $dist = Join-Path -Path "$script:temp_folder" -ChildPath $filename
        if (!(Test-Path -Path "$dist")) {
            Expand-Archive -Path "$Path" -DestinationPath "$script:temp_folder"
        }

        return Join-Path -Path "$dist" -ChildPath "$env:INSTALLER_NAME"
    }

    return $Path
}

function Compress-Folder
{
    param (
        [string]$Path,
        [string]$DestinationPath
    )
    Write-SubHeader "Compressing file: $Path"

    Compress-Archive -Path $Path -DestinationPath $DestinationPath
}

function Main
{
    Write-Header "Installing From"

    $sw = [Diagnostics.Stopwatch]::StartNew()

    Get-Arguments

    $Uninstaller = Get-Uninstall
    $InstalledApps = Get-InstalledApp -InstalledApps $Uninstaller `
                                      -DisplayName $env:INSTALLER_DISPLAYNAME `
                                      -MatchDisplayName $script:display_name_match

    if ($null -eq $InstalledApps -or $script:force_install) {
        if ($script:install_from -eq 'file') {
            $localFile = $env:INSTALLER_URI -replace $script:file_scheme, ''
        } elseif ($script:install_from -eq 'url') {
            $localFile = (Get-FromUrl $script:temp_folder $script:force_download).LocalFile
        } elseif ($script:install_from -eq 's3') {
            $localFile = (Get-FromS3 $script:aws_region $script:temp_folder $script:force_download).LocalFile
        }

        $localFile = Expand-File -Path $localFile
        Install-Certs

        if ($script:installer_type -eq 'msi') {
            Install-MSI $localFile
        } elseif ($script:installer_type -eq 'exe') {
            Install-EXE $localFile
        } elseif ($script:installer_type -eq 'iso') {
            Install-ISO $localFile
        } elseif ($script:installer_type -eq 'msu') {
            Install-MSU $localFile
        }

        if ($script:post_install -eq 'compress') {
            Compress-Folder -Path $script:post_install_compress_path -DestinationPath $script:post_install_compress_output_path
        }
    }

    $sw.Stop()
    $ts = $sw.Elapsed
    $elapsed_time = [System.String]::Format("{0:00}:{1:00}:{2:00}.{3:00}", $ts.Hours, $ts.Minutes, $ts.Seconds, $ts.Milliseconds / 10)

    Write-SubHeader "Completed in: $elapsed_time"
}

Main
