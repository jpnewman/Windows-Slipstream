
# Windows Slipstream

This repository contains an example of using Packer to create a Windows ISO image with slipstreamed updates.

The idea is to use Packer and Vagrant to slipstream updates into an existing ISO. This is done by creating a VirtualBox OS from the ISO, updating it, and then slipstreaming the updates into a new ISO.

## Why vagrant is used

Vagrant is used as it allows the loading and updating of the latest / previous ISO. This means that the updates can be installed from the updated Windows OS (i.e. ```C:\Windows\SoftwareDistribution\Download\```) and a new ISO created with them. Making the update process very meta.

## Create updated ISO from an existing ISO

## Setup

### Download Windows ISO

Download the latest ISO (e.g. 'Windows 2016') into folder ```packer_cache```.

### Download any extra updates

Download any extra MSU and CAB files to folder like ```packer_cache/updates/Windows2016_64```.

### Get Oracle Cert

This cert can be exported from a previously manually installed Oracle VM VirtualBox Guest Additions.

### Environment Variables for ```slipstream-iso.ps1```

|Environment Variables|Description|Default|
|---|---|---|
|```IMAGE_NAME```|This is a regular expression that is used to select the images inside the WIM.|```.*```|
|```INSTALL_LIST_FILE```|Applies updates in the order they are listed within this file.|```_Updates.txt```|
|```APPLY_INSTALLED_UPDATES```|Apply MSU and CAB files that are found on the guest OS in path ```C:\Windows\SoftwareDistribution\Download\``` ||
|```UPDATE_FOLDER```|Path to installer folder. *e.g.* ```\\VBOXSVR\vagrant``` (**N.B.** Escape slashes in the Packer template)||

#### Example ```INSTALL_LIST_FILE``` file

~~~
# Windows2016_64

# Updates are installed in the below order.
KB4465659
KB4091664
KB4480977
~~~

> Each uncommented line matches the first file found that contains the line text.
> If this file does not exist in the root of the ```UPDATE_FOLDER``` all MSU and CAB files in the folder tree will be installed.

### Packer ```windows_slipstream.json``` template variables

|Template Variables|Description|
|---|---|
|```iso_url```|Path to a Windows ISO|
|```iso_checksum```|Windows ISO MD5 checksum|
|```guest_os_type```|VirtualBox Guest OS Type|
|```installer_folder```|Path to MSU and CAB installer files|
|```autounattend```|Path to Autounattend XML file|

#### Generate MD5 from ISO for ```iso_checksum```

~~~
md5 packer_cache/en_windows_server_2016_vl_x64_dvd_11636701.iso
~~~

#### List VirtualBox Windows Guest Types for ```guest_os_type```

~~~
VBoxManage list ostypes | grep -e '^ID' | sed -E -e "s/^ID:[[:blank:]]+//g" | grep -e 'Windows'
~~~

## Run

~~~
cd packer/templates/windows
~~~

### validate

*e.g.*

~~~
packer validate -var headless=false -var 'iso_url=../../packer_cache/en_windows_server_2016_vl_x64_dvd_11636701.iso' -var 'iso_checksum=e3779d4b1574bf711b063fe457b3ba63' -var 'guest_os_type=Windows2016_64' -var 'installer_folder=../../packer_cache/updates/Windows2016_64' windows_slipstream.json
~~~

### build, debug

*e.g.*

~~~
packer build --on-error=ask -var headless=false -var 'iso_url=../../packer_cache/en_windows_server_2016_vl_x64_dvd_11636701.iso' -var 'iso_checksum=e3779d4b1574bf711b063fe457b3ba63' -var 'guest_os_type=Windows2016_64' -var 'installer_folder=../../packer_cache/updates/Windows2016_64' windows_slipstream.json
~~~

### build, debug

*e.g.*

~~~
time PACKER_LOG=1 PACKER_LOG_PATH="windows_slipstream.log" packer build --on-error=ask -var headless=false -var 'iso_url=../../packer_cache/en_windows_server_2016_vl_x64_dvd_11636701.iso' -var 'iso_checksum=e3779d4b1574bf711b063fe457b3ba63' -var 'guest_os_type=Windows2016_64' -var 'installer_folder=../../packer_cache/updates/Windows2016_64' windows_slipstream.json
~~~

### Build, debug without updates

*e.g.*

~~~
time PACKER_LOG=1 PACKER_LOG_PATH="windows_slipstream.log" packer build --on-error=ask -var headless=false -var 'iso_url=../../packer_cache/WindowsServer2016_Patched.iso' -var 'iso_checksum=1ce3167bd232c901c5a236ef36544b4b' -var 'guest_os_type=Windows2016_64' -var 'installer_folder=../../packer_cache/updates/Windows2016_64' -var 'autounattend=../../files/answer_files/server_2016/without_updates/Autounattend.xml' --force windows_slipstream.json
~~~
