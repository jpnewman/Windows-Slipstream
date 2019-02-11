
# Tests

Basic non-functional tests for debugging.

## Pester Powershell Tests

> Mac OS X

```bash
pwsh
```

### Install

```powershell
Install-Module -Name PSScriptAnalyzer -Force
Install-Module -Name Pester -Force
```

### Run PSScriptAnalyzer

```powershell
Invoke-ScriptAnalyzer "../provisioners/powershell/*.ps1"
```

### Run Pester

```powershell
Invoke-Pester
```
