$ErrorActionPreference = "Stop"

$script:WorkingFolder = "C:\slipstream"

$script:adkBasePath = "C:\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\amd64"
$script:adkPath = Join-Path -Path "${script:adkBasePath}" -ChildPath "DISM"
$script:oscdimg = Join-Path -Path "${script:adkBasePath}" -ChildPath "Oscdimg"

$script:windowsUpdatesPath = "C:\Windows\SoftwareDistribution\Download\"

$script:outputISOName = "WindowsServer2016_Patched.iso"

$script:WorkingSubFolders = @(
    'original',
    'mount'
    'scratch'
)

function Write-Header {
    param (
        [string]$msg
    )

    Write-Host $msg -ForegroundColor Magenta
}

function Set-ADK {
    Write-Header "Setting up ADK"
    $env:path = "${script:adkPath}"
    $env:path = "${script:oscdimg}"

    Import-Module "${script:adkPath}"
}

function Get-CDRomDriveLetters {
    Write-Header "Getting CD-ROM Drives"
    return (Get-CimInstance Win32_LogicalDisk | ?{ $_.DriveType -eq 5} | Select-Object DeviceID)
}

function Set-Folders {
    param (
        [Switch]$DontDeleteIfExists
    )

    Write-Header "Setting up folders"

    if ($DontDeleteIfExists -eq $false) {
        Clear-Folders
    }

    ForEach ($folder in $script:WorkingSubFolders) {
        $path = Join-Path -Path $script:WorkingFolder -ChildPath $folder
        New-Item "$path" -ItemType Directory -Force | Out-Null
    }
}

function Run-Cmd {
    param (
        [String]$Program,
        [String]$Arguments,
        [Array]$AllowedExitCodes = @(0)
    )

    try {
        Write-Host "$Program $Arguments" -ForegroundColor Gray
        $result = (Start-Process "$Program" -ArgumentList $Arguments -Wait -PassThru)

        if ($AllowedExitCodes -notcontains $result.ExitCode) {
            Write-Error "Running command: $($result.ExitCode) : $Program $Arguments"
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
    Write-Header "Copying Windows ISO files"

    $path = "${script:WorkingFolder}\original\sources\install.wim"
    if(!(Test-Path -Path $path)) {
        $targetPath = Join-Path -Path "${script:WorkingFolder}" -ChildPath "original"
        Run-Cmd -Program robocopy -Arguments "/E `"$DriveLetter`" `"$targetPath`" /MIR /R:3 /W:5 /LOG:`"robocopy.log`"" -AllowedExitCodes @(0, 1)
    }
}

function Set-ImageReadable {
    Write-Header "Making 'install.wim' readable"
    Set-ItemProperty "${script:WorkingFolder}\original\sources\install.wim" -Name IsReadOnly -Value $false
}

function Mount-ImageFolder {
    param (
        [Switch]$DontUnmountIfNeeded
    )
    Write-Header "Mounting Windows Image"

    $path = ".\mount\bootmgr"

    $alreadyMounted = $false
    if (Test-Path -Path $path) {

        if ($DontUnmountIfNeeded -eq $true) {
            Write-Host "Using existing mounted Windows image"
            $alreadyMounted = $true
        } else {
            # Run-Cmd -Program dism.exe -Arguments "/unmount-image /mountdir:mount /discard"
            Dismount-WindowsImage -Path "mount" -ScratchDirectory "scratch" -Discard
        }
    }

    if (!$alreadyMounted) {
        # Run-Cmd -Program dism.exe -Arguments "/mount-wim /wimfile:`"original\sources\install.wim`" /mountdir:`".\mount`" /index:1"
        Mount-WindowsImage -ImagePath "original\sources\install.wim" -Index 1 -Path "mount" -ScratchDirectory "scratch"
    }
}

function Install-WindowsPackages {
    param (
        [Array]$Packages
    )

    foreach ($package in $Packages) {
        $path = $package.FullName
        Write-Host "$path"

        try {
            # Run-Cmd -Program dism.exe -Arguments "/image:mount /ScratchDir:scratch /add-package:`"$path`"" -AllowedExitCodes @(0, -2146498530)
            Add-WindowsPackage -PackagePath "$path" -Path "mount" -ScratchDirectory "scratch" -LogLevel WarningsInfo

            Start-Sleep –s 15
        } catch {
        }
    }
}

function Add-InstalledUpdates {
    Write-Header "Updating Windows Image from installed updates"
    $updateFiles = Get-ChildItem "${script:windowsUpdatesPath}" -Recurse | Where-Object {$_.PSIsContainer -eq $false -and $_.Name -match ($_.Name -match ".*\.msu" -or $_.Name -match ".*\.cab")}
    Install-WindowsPackages -Packages $updateFiles
}

function Add-FolderUpdates {
    Write-Header "Updating Windows Image from folder"
    if (!([String]::IsNullOrEmpty($env:UPDATE_FOLDER))) {
        $updateFiles = Get-ChildItem "$env:UPDATE_FOLDER" -Recurse | Where-Object {$_.PSIsContainer -eq $false -and ($_.Name -match ".*\.msu" -or $_.Name -match ".*\.cab")}
        Install-WindowsPackages -Packages $updateFiles
    }
}

function Clear-SupersededPackages {
    Write-Header "Removing Superseded Packages"
    $packages = Get-ImagePackages
    $supersededPackages = $packages | Where-Object { $_.ReleaseType -eq 'SecurityUpdate' }

    foreach ($supersededPackage in $supersededPackages) {
        Write-Host "$($supersededPackage.PackageName)"
        # Run-Cmd -Program dism.exe -Arguments "/image:mount /ScratchDir:scratch /remove-package /packagename:`"$($supersededPackage.PackageName)`""
        Remove-WindowsPackage -Path "mount" -PackageName "$($supersededPackage.PackageName)"
    }
}

function Get-ImagePackages {
    # Write-Header "Updating Windows Image Getting Packages"
    # Run-Cmd -Program dism.exe -Arguments "/Get-Packages /image:mount"
    Return Get-WindowsPackage -Path "mount" -ScratchDirectory "scratch"
}

function Compare-ImagePackages {
    param (
        [Array]$InitPackages,
        [Array]$UpdatedPackages
    )
    Write-Header "Compare Image Packages"

    $diffs = Compare-Object -ReferenceObject $InitPackages -DifferenceObject $UpdatedPackages -PassThru
    $diffs | Format-Table
}

function Save-MountedImage {
    Write-Header "Saving Windows Image"
    # Run-Cmd -Program dism.exe -Arguments "/commit-image /mountdir:mount"
    Save-WindowsImage -Path "mount"
}

function Clear-MountedImage {
    Write-Header "Clearing Mounted Image"
    # Run-Cmd -Program dism.exe -Arguments "/image:mount /cleanup-image /StartComponentCleanup /ResetBase /SpSuperseded"
    Clear-WindowsCorruptMountPoint -ScratchDirectory "scratch"
}

function Dismount-ImageFolder {
    Write-Header "Unmounting Windows Image"
    # Run-Cmd -Program dism.exe -Arguments "/unmount-image /mountdir:mount /commit"
    Dismount-WindowsImage -Path "mount" -ScratchDirectory "scratch" -CheckIntegrity -Save
}

function Format-ISO {
    Push-Location "original"

    try {
        $sourcePath = Join-Path -Path "${script:WorkingFolder}" -ChildPath "original"
        $targetPath = Join-Path -Path "${script:WorkingFolder}" -ChildPath "${script:outputISOName}"
        Run-Cmd -Program oscdimg.exe -Arguments "-bootdata:`"2#p0,e,bboot\Etfsboot.com#pEF,e,befi\Microsoft\boot\Efisys.bin`" -u1 -udfver102 $sourcePath $targetPath"
    } catch {
        throw $_
    } finally {
        Pop-Location
    }
}

function Clear-Folders {
    ForEach ($folder in $script:WorkingSubFolders) {
        $path = Join-Path -Path $script:WorkingFolder -ChildPath $folder
        if (Test-Path -Path $path) {
            Remove-Item "$path" -Recurse -Force
        }
    }
}

function Invoke-Slipstream {
    Push-Location "${script:WorkingFolder}"

    try {
        Set-ImageReadable
        Mount-ImageFolder -DontUnmountIfNeeded

        Clear-SupersededPackages

        $initPackages = Get-ImagePackages
        Add-InstalledUpdates
        Add-FolderUpdates

        Clear-MountedImage

        $updatedPackages = Get-ImagePackages
        # $updatedPackages | Where-Object { @('Update', 'SecurityUpdate') -contains $_.ReleaseType } | Sort-Object -Property ReleaseType | Format-Table
        Compare-ImagePackages -InitPackages $initPackages -UpdatedPackages $updatedPackages

        Save-MountedImage
        Dismount-ImageFolder
        Format-ISO
        Clear-Folders
    } catch {
        throw $_
    } finally {
        Pop-Location
    }
}

function Main {
    Set-ADK
    $drives = Get-CDRomDriveLetters
    $driveLetter = ""

    ForEach ($drive in $drives) {
        $path = "$($drive.DeviceID)\sources\install.wim"
        if (Test-Path -Path $path) {
            $driveLetter = $drive.DeviceID
        }
    }

    if ([String]::IsNullOrEmpty($driveLetter)) {
        Write-Error "Windows ISO CD-ROM not found!!!"
    }

    Set-Folders -DontDeleteIfExists
    Copy-Windows -DriveLetter $driveLetter -DontCopyIfExists

    Invoke-Slipstream
}

Main
