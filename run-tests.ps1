$ErrorActionPreference = 'Stop'

& (Join-Path $PSScriptRoot 'tests\static-site.tests.ps1')
