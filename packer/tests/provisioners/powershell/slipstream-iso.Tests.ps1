$here = (Split-Path -Parent $MyInvocation.MyCommand.Path)
. $here/../../../provisioners/powershell/slipstream-iso.ps1 -WorkingFolder='.' -ADKBasePath='.' -WindowsUpdatesPath='.' -UnderTest $true

Set-StrictMode -Version 2.0
$VerbosePreference = "SilentlyContinue"

# Mocks
function Add-WindowsPackage {}

# Tests
Describe 'Invoke-Slipstream' {
    It 'Get-SelectedInstallVimImages is null' {
        Mock -CommandName Push-Location -MockWith {}
        Mock -CommandName Invoke-ImageReadable -MockWith {}
        Mock -CommandName Mount-ImageFolder -MockWith {}
        Mock -CommandName Get-ImagePackages -MockWith {}
        Mock -CommandName Add-InstalledUpdates -MockWith {}
        Mock -CommandName Add-FolderUpdates -MockWith {}
        Mock -CommandName Clear-MountedImage -MockWith {}
        Mock -CommandName Compare-ImagePackages -MockWith {}
        Mock -CommandName Save-MountedImage -MockWith {}
        Mock -CommandName Dismount-ImageFolder -MockWith {}
        Mock -CommandName Format-ISO -MockWith {}
        Mock -CommandName Clear-Folders -MockWith {}
        Mock -CommandName Pop-Location -MockWith {}

        Mock -CommandName Get-SelectedInstallVimImages -MockWith {$null}

        Invoke-Slipstream
    }

    It 'Get-SelectedInstallVimImages not null' {
        Mock -CommandName Push-Location -MockWith {}
        Mock -CommandName Invoke-ImageReadable -MockWith {}
        Mock -CommandName Mount-ImageFolder -MockWith {}
        Mock -CommandName Get-ImagePackages -MockWith {}
        Mock -CommandName Add-InstalledUpdates -MockWith {}
        Mock -CommandName Add-FolderUpdates -MockWith {}
        Mock -CommandName Clear-MountedImage -MockWith {}
        Mock -CommandName Compare-ImagePackages -MockWith {}
        Mock -CommandName Save-MountedImage -MockWith {}
        Mock -CommandName Dismount-ImageFolder -MockWith {}
        Mock -CommandName Format-ISO -MockWith {}
        Mock -CommandName Clear-Folders -MockWith {}
        Mock -CommandName Pop-Location -MockWith {}

        Mock -CommandName Get-SelectedInstallVimImages -MockWith {
            @(@{
                'ImageIndex' = 1;
                'ImageName' = 'Windows 2016'
            },
            @{
                'ImageIndex' = 2;
                'ImageName' = 'Windows "64-bit" 2016'
            })
        }

        Invoke-Slipstream | Should Be $null
    }
}

Describe 'Copy-Windows' {
    It 'Call Invoke-Cmd once' {
        Mock -CommandName Invoke-Cmd -MockWith { Write-Host "$Program $Arguments" }

        $DriveLetter = 'D:'
        $targetPath = Join-Path -Path '.' -ChildPath 'original'

        Copy-Windows -DriveLetter "$DriveLetter"

        Assert-MockCalled -CommandName Invoke-Cmd -Exactly 1 -Scope It
        Assert-MockCalled -CommandName Invoke-Cmd -Exactly 1 -ParameterFilter { $Program -eq "robocopy" } -Scope It
        Assert-MockCalled -CommandName Invoke-Cmd -Exactly 1 -ParameterFilter { $Arguments -eq "/E `"$DriveLetter`" `"-WorkingFolder=$targetPath`" /MIR /R:3 /W:5 /LOG:`"robocopy.log`"" } -Scope It
    }
}

Describe 'Format-ISO' {
    It 'Call Invoke-Cmd once' {
        Mock -CommandName Invoke-Cmd -MockWith { Write-Host "$Program $Arguments" }
        Mock -CommandName Push-Location -MockWith {}

        Format-ISO

        $sourcePath = Join-Path -Path '.' -ChildPath 'original'
        $targetPath = Join-Path -Path '.' -ChildPath 'WindowsServer2016_Patched.iso'

        Assert-MockCalled -CommandName Invoke-Cmd -Exactly 1 -Scope It
        Assert-MockCalled -CommandName Invoke-Cmd -Exactly 1 -ParameterFilter { $Program -eq "oscdimg.exe" } -Scope It
        Assert-MockCalled -CommandName Invoke-Cmd -Exactly 1 -ParameterFilter { $Arguments -eq "-bootdata:`"2#p0,e,bboot\Etfsboot.com#pEF,e,befi\Microsoft\boot\Efisys.bin`" -u1 -udfver102 -WorkingFolder=$sourcePath -WorkingFolder=$targetPath" } -Scope It
    }
}

Describe 'Install-WindowsPackages' {
    It 'Call Add-WindowsPackage twice' {
        Mock -CommandName Add-WindowsPackage -MockWith {}

        $packages = @(
            @{'FullName' = '\\VBOXSVR\vagrant\windows10.0-kb4091664-v6-x64_cb6f102b635f103e00988750ca129709212506d6.msu'},
            @{'FullName' = '\\VBOXSVR\vagrant\windows10.0-kb4132216-x64_9cbeb1024166bdeceff90cd564714e1dcd01296e.msu'}
        )

        Install-WindowsPackages -Packages $packages -SleepSec 0

        Assert-MockCalled -CommandName Add-WindowsPackage -Exactly 2 -Scope It
    }
}

Describe 'Get-WindowsDiskDriveLetter' {
    $installWimDVDPath = 'sources\install.wim'

    Mock -CommandName Join-Path -MockWith { "$Path\$installWimDVDPath" }
    Mock -CommandName Get-CDRomDriveLetters -MockWith {
        @(
            @{'DeviceID' = 'C:'},
            @{'DeviceID' = 'D:'}
        )
    }

    It 'Throws' {
        Mock -CommandName Test-Path -MockWith { $false }

        { Get-WindowsDiskDriveLetter } | Should -Throw "ERROR: Windows ISO CD-ROM not found!!!"
    }

    It 'Not throws' {
        Mock -CommandName Test-Path -ParameterFilter { $Path -eq "C:\$installWimDVDPath" } -MockWith { $true }
        Mock -CommandName Test-Path -ParameterFilter { $Path -eq "D:\$installWimDVDPath" } -MockWith { $false }

        Get-WindowsDiskDriveLetter
    }
}
