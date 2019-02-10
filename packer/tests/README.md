
# Tests

Basic non-functional tests for debugging.

## Pester Powershell Tests

> Mac OS X

~~~
pwsh
~~~

### Install

~~~
Install-Module -Name PSScriptAnalyzer -Force
Install-Module -Name Pester -Force
~~~

### Run PSScriptAnalyzer

~~~
Invoke-ScriptAnalyzer "../provisioners/powershell/*.ps1"
~~~

### Run Pester

~~~
Invoke-Pester
~~~
