
# Windows Slipstream

This repository contains an example of using Packer to create a Windows ISO image with slipstreamed updates.

The idea is to use Packer and Vagrant to slipstream updates into an existing ISO. This is done by creating a VirtualBox OS from the ISO, updating it, and then slipstreaming the updates into a new ISO.

## Why vagrant is used

Vagrant is used as it allows the loading and updating of the latest / previous ISO. This means that the updates can be installed from the updated Windows OS (i.e. ```C:\Windows\SoftwareDistribution\Download\```) and a new ISO created with them. Making the update process very meta.

## Create updated ISO from an existing ISO

## Setup

### Download Windows ISO

Download the latest ISO (e.g. 'Windows 2016') into folder ```packer/templates/windows```.

### Download any extra updates

Download any extra MSU and CAB files to folder like ```packer/templates/windows/Updates/Windows2016_64```.

### Create ADK offline installer

Creating an ADK offline installer can speed-up build times.

```bash
cd packer/templates/windows
```

```bash
packer build --on-error=ask -var headless=false -var "iso_url=packer_cache\SW_DVD9_Win_Svr_STD_Core_and_DataCtr_Core_2016_64Bit_English_-3_MLF_X21-30350.ISO" -var "iso_checksum=EEB465C08CF7243DBAAA3BE98F5F9E40" -var "guest_os_type=Windows2016_64" -var "autounattend=../../files/answer_files/server_2016/without_updates/Autounattend.xml" create_adk_offline_installer.json
```

-- or --

> Windows Powershell, without Packer

```powershell
$env:INSTALLER_TYPE="EXE"
$env:INSTALL_FROM="URL"
$env:INSTALLER_DISPLAYNAME="Windows Assessment and Deployment Kit - Windows 10"
$env:INSTALL_EXE_ARGUMENTS="/quiet /layout C:\Windows\Temp\ADKoffline"
$env:INSTALLER_URI="https://go.microsoft.com/fwlink/?linkid=2026036"
$env:INSTALLER_NAME="adksetup.exe"
$env:FORCE_INSTALL="true"
$env:POST_INSTALL="compress"
$env:POST_INSTALL_COMPRESS_PATH="C:\Windows\Temp\ADKoffline"
$env:POST_INSTALL_COMPRESS_OUTPUT_PATH="C:\Windows\Temp\ADKoffline.zip"

packer/provisioners/powershell/install-from.ps1
```

#### Use offline installers

1. Create ADK offline installer and move ```ADKoffline.zip``` to ```packer/pcaker_cache/Offline```.

2. Copy ```VBoxGuestAdditions``` to ```packer/files/offline```.

```bash
cp /Applications/VirtualBox.app/Contents/MacOS/VBoxGuestAdditions.iso packer/files/offline/
```

3. Use offline installers: -

```bash
cd packer/templates/windows
```

```bash
packer validate -var headless=false -var 'iso_url=packer_cache/WindowsServer2016_Patched.iso' -var 'iso_checksum=932d3d7f14a3a938bb8ff73f486d64b9' -var 'guest_os_type=Windows2016_64' -var 'autounattend=../../files/answer_files/server_2016/without_updates/Autounattend.xml' -var "adk_installer_uri=file://\\\\VBOXSVR\\vagrant\\Offline\ADKoffline.zip" windows_slipstream.json
```

```bash
time PACKER_LOG=1 PACKER_LOG_PATH="windows_slipstream.log" packer build --on-error=ask -var headless=false -var 'iso_url=packer_cache/WindowsServer2016_Patched.iso' -var 'iso_checksum=932d3d7f14a3a938bb8ff73f486d64b9' -var 'guest_os_type=Windows2016_64' -var 'autounattend=../../files/answer_files/server_2016/without_updates/Autounattend.xml' windows_slipstream.json
```

> Without Windows updates.

### Get Oracle Cert

This cert can be exported from a previously manually installed Oracle VM VirtualBox Guest Additions.

### Windows

Ensure that ```packer``` and ```VBoxManage``` are in the environment variables ```PATH```.

e.g.

```powershell
C:\Program Files\Oracle\VirtualBox
```

### Environment Variables for ```slipstream-iso.ps1```

|Environment Variables|Description|Default|
|---|---|---|
|```IMAGE_NAME```|This is a regular expression that is used to select the images inside the WIM.|```.*```|
|```INSTALL_LIST_FILE```|Applies updates in the order they are listed within this file.|```_Updates.txt```|
|```APPLY_INSTALLED_UPDATES```|Apply MSU and CAB files that are found on the guest OS in path ```C:\Windows\SoftwareDistribution\Download\``` ||
|```UPDATES_FOLDER```|Path to installer folder.||
|```ISO_OUTPUT_NAME```|ISO output filename.|```WindowsServer2016_Patched.iso```|

#### Example ```INSTALL_LIST_FILE``` file

```
# Windows2016_64

# Updates are installed in the below order.
KB4465659
KB4091664
KB4480977
```

> Each uncommented line matches the first file found that contains the line text.
> If this file does not exist in the root of the ```UPDATES_FOLDER``` all MSU and CAB files in the folder tree will be installed.

### Packer ```windows_slipstream.json``` template variables

|Template Variables|Description|Default|
|---|---|---|
|```iso_url```|Path to a Windows ISO||
|```iso_checksum```|Windows ISO MD5 checksum||
|```guest_os_type```|VirtualBox Guest OS Type||
|```updates_folder```|Path to folder containing MSU and CAB installer files|```\\\\VBOXSVR\\vagrant\\Updates\\Windows2016_64```|
|```autounattend```|Path to Autounattend XML file|```{{template_dir}}/../../files/answer_files/server_2016/with_updates/Autounattend.xml```|
|```adk_installer_uri```|URI to ADK installer|```https://go.microsoft.com/fwlink/?linkid=2026036```|

#### Generate MD5 from ISO for ```iso_checksum```

```bash
md5 packer/templates/windows/en_windows_server_2016_vl_x64_dvd_11636701.iso
```

> Powershell

```powershell
Get-FileHash .\packer\templates\windows\packer_cache\SW_DVD9_Win_Svr_STD_Core_and_DataCtr_Core_2016_64Bit_English_-3_MLF_X21-30350.ISO -Algorithm MD5
```

#### List VirtualBox Windows Guest Types for ```guest_os_type```

```bash
VBoxManage list ostypes | grep -e '^ID' | sed -E -e "s/^ID:[[:blank:]]+//g" | grep -e 'Windows'
```

## Run

```bash
cd packer/templates/windows
```

### validate

*e.g.*

```bash
packer validate -var headless=false -var 'iso_url=packer_cache/en_windows_server_2016_vl_x64_dvd_11636701.iso' -var 'iso_checksum=e3779d4b1574bf711b063fe457b3ba63' -var 'guest_os_type=Windows2016_64' windows_slipstream.json
```

> Powershell

```bash
packer validate -var headless=false -var "iso_url=packer_cache\SW_DVD9_Win_Svr_STD_Core_and_DataCtr_Core_2016_64Bit_English_-3_MLF_X21-30350.ISO" -var "iso_checksum=EEB465C08CF7243DBAAA3BE98F5F9E40" -var "guest_os_type=Windows2016_64" windows_slipstream.json
```

### build, debug

*e.g.*

```bash
packer build --on-error=ask -var headless=false -var 'iso_url=packer_cache/en_windows_server_2016_vl_x64_dvd_11636701.iso' -var 'iso_checksum=e3779d4b1574bf711b063fe457b3ba63' -var 'guest_os_type=Windows2016_64' windows_slipstream.json
```

> Powershell

```powershell
packer build --on-error=ask -var headless=false -var "iso_url=packer_cache\SW_DVD9_Win_Svr_STD_Core_and_DataCtr_Core_2016_64Bit_English_-3_MLF_X21-30350.ISO" -var "iso_checksum=EEB465C08CF7243DBAAA3BE98F5F9E40" -var "guest_os_type=Windows2016_64" windows_slipstream.json
```

### build, timed debug

*e.g.*

```bash
time PACKER_LOG=1 PACKER_LOG_PATH="windows_slipstream.log" packer build --on-error=ask -var headless=false -var 'iso_url=packer_cache/en_windows_server_2016_vl_x64_dvd_11636701.iso' -var 'iso_checksum=e3779d4b1574bf711b063fe457b3ba63' -var 'guest_os_type=Windows2016_64' windows_slipstream.json
```

> Powershell (not timed)

```powershell
$env:PACKER_LOG=1
$env:PACKER_LOG_PATH="windows_slipstream.log"

packer build -var headless=false -var "iso_url=packer_cache\SW_DVD9_Win_Svr_STD_Core_and_DataCtr_Core_2016_64Bit_English_-3_MLF_X21-30350.ISO" -var "iso_checksum=EEB465C08CF7243DBAAA3BE98F5F9E40" -var "guest_os_type=Windows2016_64" windows_slipstream.json
```

### Build, timed debug without updates

*e.g.*

```bash
time PACKER_LOG=1 PACKER_LOG_PATH="windows_slipstream.log" packer build --on-error=ask -var headless=false -var 'iso_url=packer_cache/WindowsServer2016_Patched.iso' -var 'iso_checksum=932d3d7f14a3a938bb8ff73f486d64b9' -var 'guest_os_type=Windows2016_64' -var 'autounattend=../../files/answer_files/server_2016/without_updates/Autounattend.xml' --force windows_slipstream.json
```

> Powershell (not timed)

```powershell
$env:PACKER_LOG=1
$env:PACKER_LOG_PATH="windows_slipstream.log"

packer build --on-error=ask -var headless=false -var "iso_url=packer_cache\SW_DVD9_Win_Svr_STD_Core_and_DataCtr_Core_2016_64Bit_English_-3_MLF_X21-30350.ISO" -var "iso_checksum=EEB465C08CF7243DBAAA3BE98F5F9E40" -var "guest_os_type=Windows2016_64" -var "autounattend=../../files/answer_files/server_2016/without_updates/Autounattend.xml" windows_slipstream.json
```
