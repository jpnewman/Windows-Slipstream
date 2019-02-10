param (
    [string]$WorkingFolder = "C:\slipstream",
    [string]$ADKBasePath = "C:\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\amd64",
    [string]$WindowsUpdatesPath = "C:\Windows\SoftwareDistribution\Download\",
    [bool]$UnderTest = $false
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = "Stop"
$VerbosePreference = "Continue"

$script:outputISOName = if ([String]::IsNullOrEmpty($env:ISO_OUTPUT_NAME)) { "WindowsServer2016_Patched.iso" } else { $env:ISO_OUTPUT_NAME }
$script:WorkingSubFolders = @(
    'original',
    'mount'
    'scratch'
)

$script:InstallWimDVDPath = "sources\install.wim"
$script:InstallWimFile = Join-Path -Path "original" -ChildPath "${script:InstallWimDVDPath}"

$script:imageName = if ([String]::IsNullOrEmpty($env:IMAGE_NAME)) { ".*" } else { $env:IMAGE_NAME }
$script:installListFile = if ([String]::IsNullOrEmpty($env:INSTALL_LIST_FILE)) { "_Updates.txt" } else { $env:INSTALL_LIST_FILE }

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

function Get-PowershellInfo {
    $PSVersionTable
}

function Initialize-ADK {
    Write-SubHeader "Setting up ADK"
    $adkPath = Join-Path -Path "$ADKBasePath" -ChildPath "DISM"
    $oscdimg = Join-Path -Path "$ADKBasePath" -ChildPath "Oscdimg"

    $env:Path = "${adkPath}"
    $env:Path = "${oscdimg}"

    Import-Module "${adkPath}"
}

function Get-CDRomDriveLetters {
    Write-SubHeader "Getting CD-ROM Drives"
    return (Get-CimInstance Win32_LogicalDisk | Where-Object { $_.DriveType -eq 5} | Select-Object DeviceID)
}

function Get-WindowsDiskDriveLetter {
    Write-SubHeader "Getting Windows Disk Drive Letter"
    $drives = Get-CDRomDriveLetters
    $driveLetter = ""

    ForEach ($drive in $drives) {
        $path = Join-Path -Path "$($drive.DeviceID)" -ChildPath "${script:InstallWimDVDPath}"
        Write-Verbose "Checking for Installer WIM at: $path"
        if (Test-Path -Path $path) {
            Write-Verbose "Found Windows Installer WIM: $path"
            $driveLetter = $drive.DeviceID
            return $driveLetter
        }
    }

    if ([String]::IsNullOrEmpty($driveLetter)) {
        throw "ERROR: Windows ISO CD-ROM not found!!!"
    }

    return $driveLetter
}

function Initialize-WorkingFolders {
    param (
        [Switch]$DontDeleteIfExists
    )

    Write-SubHeader "Setting up folders"

    if ($DontDeleteIfExists -eq $false) {
        Clear-Folders
    }

    ForEach ($folder in $script:WorkingSubFolders) {
        $path = Join-Path -Path $WorkingFolder -ChildPath $folder
        New-Item "$path" -ItemType Directory -Force | Out-Null
    }
}

function Invoke-Cmd {
    param (
        [String]$Program,
        [String]$Arguments,
        [Array]$AllowedExitCodes = @(0)
    )

    try {
        Write-Verbose "$Program $Arguments"
        $result = (Start-Process "$Program" -ArgumentList $Arguments -Wait -PassThru)

        if ($AllowedExitCodes -notcontains $result.ExitCode) {
            throw "ERROR: Running command: $($result.ExitCode) : $Program $Arguments"
        }
    } catch {
        throw $_
    }
}

function Copy-Windows {
    param (
        [String]$DriveLetter,
        [Switch]$DontCopyIfExists
    )
    Write-SubHeader "Copying Windows ISO files"

    $installWimPath = Join-Path -Path "$WorkingFolder" -ChildPath "${script:InstallWimFile}"
    if(!(Test-Path -Path $installWimPath)) {
        $targetPath = Join-Path -Path "$WorkingFolder" -ChildPath "original"
        Invoke-Cmd -Program robocopy -Arguments "/E `"$DriveLetter`" `"$targetPath`" /MIR /R:3 /W:5 /LOG:`"robocopy.log`"" -AllowedExitCodes @(0, 1)
    }
}

function Invoke-ImageReadable {
    Write-SubHeader "Making install.wim readable"
    Set-ItemProperty -Path "${script:InstallWimFile}" -Name IsReadOnly -Value $false
}

function Get-SelectedInstallVimImages {
    Write-SubHeader "Getting Windows WIM images: ${script:InstallWimFile}"
    return Get-WindowsImage -ImagePath "${script:InstallWimFile}" | Where-Object { $_.ImageName -match "${script:imageName}" }
}

function Mount-ImageFolder {
    param (
        [int]$Index,
        [Switch]$DontUnmountIfNeeded
    )
    Write-SubHeader "Mounting Windows Image"
    $alreadyMounted = $false

    $path = ".\mount\bootmgr"
    if (Test-Path -Path $path) {

        if ($DontUnmountIfNeeded -eq $true) {
            Write-Verbose "Using existing mounted Windows image"
            $alreadyMounted = $true
        } else {
            # Invoke-Cmd -Program dism.exe -Arguments "/unmount-image /mountdir:mount /discard"
            Dismount-WindowsImage -Path "mount" -ScratchDirectory "scratch" -Discard
        }
    }

    if (!$alreadyMounted) {
        # Invoke-Cmd -Program dism.exe -Arguments "/mount-wim /wimfile:`"${script:InstallWimFile}`" /mountdir:`".\mount`" /index:$Index"
        Mount-WindowsImage -ImagePath "${script:InstallWimFile}" -Index $Index -Path "mount" -ScratchDirectory "scratch"
    }
}

function Install-WindowsPackages {
    param (
        [Array]$Packages,
        [int]$SleepSec=5
    )

    foreach ($package in $Packages) {
        $path = "$($package.FullName)"
        Write-Verbose "$path"

        try {
            # Invoke-Cmd -Program dism.exe -Arguments "/image:mount /ScratchDir:scratch /add-package:`"$path`"" -AllowedExitCodes @(0, -2146498530)
            Add-WindowsPackage -PackagePath "$path" -Path "mount" -ScratchDirectory "scratch" -LogLevel WarningsInfo
            Start-Sleep –s $SleepSec
        } catch {
            throw $_
        }
    }
}

function Add-InstalledUpdates {
    Write-SubHeader "Updating Windows Image from installed updates"

    if (!([String]::IsNullOrEmpty($env:APPLY_INSTALLED_UPDATES))) {
        try {
            $applyInstalledUpdates = ([System.Convert]::ToBoolean($env:APPLY_INSTALLED_UPDATES))
        } catch {
            throw "ERROR: Converting `$env:APPLY_INSTALLED_UPDATES ('$env:APPLY_INSTALLED_UPDATES') to boolean!"
        }

        if ($applyInstalledUpdates -eq $false) {
            Write-Verbose "WARN: Skipping as `$env:APPLY_INSTALLED_UPDATES is false"
        }
    }

    $updateFiles = Get-ChildItem "$WindowsUpdatesPath" -Recurse | Where-Object {$_.PSIsContainer -eq $false -and $_.Name -match ($_.Name -match ".*\.msu" -or $_.Name -match ".*\.cab")}
    Install-WindowsPackages -Packages $updateFiles
}

function Add-FolderUpdates {
    Write-SubHeader "Updating Windows Image from folder"

    if ([String]::IsNullOrEmpty($env:UPDATES_FOLDER)) {
        return
    }

    $installUpdates = [System.Collections.ArrayList]@()
    $updateFiles = Get-ChildItem "$env:UPDATES_FOLDER" -Recurse | Where-Object {$_.PSIsContainer -eq $false -and ($_.Name -match ".*\.msu" -or $_.Name -match ".*\.cab")} | Select-Object -Unique

    $path = Join-Path -Path "$env:UPDATES_FOLDER" -ChildPath "${script:installListFile}"
    if (Test-Path -Path "$path") {
        Write-Verbose "Applying updates listed in file: $path"

        $lines = Get-Content "$path" | Where-Object {$_ -notmatch '^\s*$'} | Where-Object {$_ -notmatch '^\s*#'} | ForEach-Object { $_.Trim() }
        foreach ($line in $lines) {
            $selectedUpdate = $updateFiles | Where-Object { $_.Name -match "$line" } | Select-Object -First 1

            if ($selectedUpdate) {
                Write-Verbose "${line}: $($selectedUpdate.FullName)"
                [void]$installUpdates.Add($selectedUpdate)
            } else {
                Write-Verbose "WARN: Update file not found: $line"
            }
        }
    } else {
        foreach ($updateFile in $updateFiles) {
            [void]$installUpdates.Add($updateFile)
        }
    }

    Write-Verbose "Applying $($installUpdates.Count) updates"
    Install-WindowsPackages -Packages $installUpdates
}

function Clear-SupersededPackages {
    Write-SubHeader "Removing Superseded Packages"
    $packages = Get-ImagePackages
    $supersededPackages = $packages | Where-Object { $_.ReleaseType -eq 'SecurityUpdate' }

    foreach ($supersededPackage in $supersededPackages) {
        Write-Verbose "$($supersededPackage.PackageName)"
        # Invoke-Cmd -Program dism.exe -Arguments "/image:mount /ScratchDir:scratch /remove-package /packagename:`"$($supersededPackage.PackageName)`""
        Remove-WindowsPackage -Path "mount" -PackageName "$($supersededPackage.PackageName)"
    }
}

function Get-ImagePackages {
    # Write-SubHeader "Updating Windows Image Getting Packages"
    # Invoke-Cmd -Program dism.exe -Arguments "/Get-Packages /image:mount"
    return Get-WindowsPackage -Path "mount" -ScratchDirectory "scratch"
}

function Compare-ImagePackages {
    param (
        [Array]$InitPackages,
        [Array]$UpdatedPackages
    )
    Write-SubHeader "Compare Image Packages"

    $diffs = Compare-Object -ReferenceObject $InitPackages -DifferenceObject $UpdatedPackages -PassThru
    $diffs | Format-Table –AutoSize | Out-String -Width 4000 | Write-Verbose
}

function Save-MountedImage {
    Write-SubHeader "Saving Windows Image"
    # Invoke-Cmd -Program dism.exe -Arguments "/commit-image /mountdir:mount"
    Save-WindowsImage -Path "mount"
}

function Clear-MountedImage {
    Write-SubHeader "Clearing Mounted Image"
    # Invoke-Cmd -Program dism.exe -Arguments "/image:mount /cleanup-image /StartComponentCleanup /ResetBase /SpSuperseded"
    Clear-WindowsCorruptMountPoint -ScratchDirectory "scratch"
}

function Dismount-ImageFolder {
    Write-SubHeader "Unmounting Windows Image"
    # Invoke-Cmd -Program dism.exe -Arguments "/unmount-image /mountdir:mount /commit"
    Dismount-WindowsImage -Path "mount" -ScratchDirectory "scratch" -CheckIntegrity -Save
}

function Format-ISO {
    Push-Location "original"

    try {
        $sourcePath = Join-Path -Path "$WorkingFolder" -ChildPath "original"
        $targetPath = Join-Path -Path "$WorkingFolder" -ChildPath "${script:outputISOName}"
        Invoke-Cmd -Program oscdimg.exe -Arguments "-bootdata:`"2#p0,e,bboot\Etfsboot.com#pEF,e,befi\Microsoft\boot\Efisys.bin`" -u1 -udfver102 $sourcePath $targetPath"
    } catch {
        throw $_
    } finally {
        Pop-Location
    }
}

function Clear-Folders {
    ForEach ($folder in $script:WorkingSubFolders) {
        $path = Join-Path -Path $WorkingFolder -ChildPath $folder
        if (Test-Path -Path $path) {
            Remove-Item "$path" -Recurse -Force
        }
    }
}

function Invoke-Slipstream {
    Push-Location "$WorkingFolder"

    try {
        Invoke-ImageReadable

        $images = Get-SelectedInstallVimImages
        foreach ($image in $images) {
            Write-Header "Updating Image: $($image.ImageIndex) - $($image.ImageName)"
            Mount-ImageFolder -Index $image.ImageIndex -DontUnmountIfNeeded

            # Clear-SupersededPackages

            $initPackages = Get-ImagePackages
            Add-InstalledUpdates
            Add-FolderUpdates

            Clear-MountedImage

            $updatedPackages = Get-ImagePackages
            # $updatedPackages | Where-Object { @('Update', 'SecurityUpdate') -contains $_.ReleaseType } | Sort-Object -Property ReleaseType | Format-Table –AutoSize | Out-String -Width 4000 | Write-Verbose
            Compare-ImagePackages -InitPackages $initPackages -UpdatedPackages $updatedPackages

            Save-MountedImage
            Dismount-ImageFolder
        }

        Format-ISO
        Clear-Folders
    } catch {
        throw $_
    } finally {
        Pop-Location
    }
}

function Main {
    Get-PowershellInfo

    Initialize-ADK
    $driveLetter = Get-WindowsDiskDriveLetter

    Initialize-WorkingFolders -DontDeleteIfExists
    Copy-Windows -DriveLetter $driveLetter -DontCopyIfExists

    Invoke-Slipstream
}

if ($UnderTest -eq $false) {
    Main
}
