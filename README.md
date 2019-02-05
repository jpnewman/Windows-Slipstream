
# Windows Slipstream

This repository contains an example of using Packer to create a Windows ISO image with slipstreamed updates.

The idea is to use Packer and Vagrant to slipstream updates into an existing ISO. This is done by creating a VirtualBox OS from the ISO, updating it, and then slipstreaming the updates into a new ISO.

## Create updated ISO from an existing ISO

## Setup

### Download Windows ISO

Download the latest ISO (e.g. 'Windows 2016') into folder ```packer_cache```.

### Download any extra updates

Download any extra MSU and CAB files to folder ```packer_cache```.

### Generate MD5 for ISO

~~~
md5 packer_cache/en_windows_server_2016_vl_x64_dvd_11636701.iso
~~~

### Get ```guest_os_type```

~~~
VBoxManage list ostypes | grep -e '^ID' | sed -E -e "s/^ID:[[:blank:]]+//g" | grep -e 'Windows'
~~~

### Get Oracle Cert

This cert can be exported from a previously manually installed Oracle VM VirtualBox Guest Additions.

## Run

~~~
cd packer/templates/windows
~~~

> validate

~~~
packer validate -var headless=false -var 'iso_url=../../packer_cache/en_windows_server_2016_vl_x64_dvd_11636701.iso' -var 'iso_checksum=e3779d4b1574bf711b063fe457b3ba63' -var 'guest_os_type=Windows2016_64' windows_slipstream.json
~~~

> build, debug

~~~
time PACKER_LOG=1 PACKER_LOG_PATH="windows_slipstream.log" packer build --on-error=ask -var headless=false -var 'iso_url=../../packer_cache/en_windows_server_2016_vl_x64_dvd_11636701.iso' -var 'iso_checksum=e3779d4b1574bf711b063fe457b3ba63' -var 'guest_os_type=Windows2016_64' windows_slipstream.json
~~~

> Build, without updates

~~~
time PACKER_LOG=1 PACKER_LOG_PATH="windows_slipstream.log" packer build --on-error=ask -var headless=false -var 'iso_url=../../packer_cache/WindowsServer2016_Patched.iso' -var 'iso_checksum=1ce3167bd232c901c5a236ef36544b4b' -var 'guest_os_type=Windows2016_64' -var 'autounattend=../../files/answer_files/server_2016/without_updates/Autounattend.xml' --force windows_slipstream.json
~~~
