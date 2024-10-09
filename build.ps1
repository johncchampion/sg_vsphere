#requires -version 7

[cmdletbinding()]
param (
	[Parameter(Mandatory = $True)]
	[string[]]$NodeList,
	[switch]$Configure
)

# Append .ini to filename if missing
for ($i = 0; $i -lt $NodeList.Count; $i++)
{
	$file = $NodeList[$i]
	if ($file.IndexOf(".ini") -eq -1)
	{
		$NodeList[$i] = $file + ".ini"
	}
}

# Test for each config file
$missing = $false
foreach ($config IN $NodeList)
{
	if (!(Test-Path -Path "$config"))
	{
		Write-Host -ForegroundColor Yellow   "`n Missing Node Configuration File [$config]"
		$missing = $true
	}
}

if ($missing) { Write-Host; exit }

# Deploy Node(s)
Clear-Host
Write-Host -ForegroundColor Gray   " ================================"
Write-Host -ForegroundColor Yellow " StorageGRID Deployment - vSphere"
Write-Host -ForegroundColor Gray   " ================================"

foreach ($config IN $NodeList)
{
	& "./deploy.ps1" -ConfigFile $config.Trim()
	if ($LASTEXITCODE -ne 0) { EXIT }
}

Write-Host

if ($NodeList.Count -gt 1 ) {
	Write-Host
    Write-Host -ForegroundColor Yellow " Waiting ~5 minutes for last node to finish booting ... " -NoNewline
    Start-Sleep -Seconds 310
    Write-Host -ForegroundColor Green "Done"
	Write-Host
}

# Configure Nodes
if ($Configure) {
	& "./configure.ps1" 
}

# END