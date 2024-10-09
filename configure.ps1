#requires -version 7

# Functions
function Get-ConfigSettings
{
	[CmdletBinding()]
	param
	(
		[Parameter(Mandatory = $true)]
		$IniFileName
	)
	$ini = @{ }
	$section = "NO_SECTION"
	$ini[$section] = @{ }
	switch -regex -file $iniFileName {
		"^\[(.+)\]$" {
			$section = $matches[1].Trim()
			$ini[$section] = @{ }
		}
		"^\s*([^#].+?)\s*=\s*(.*)" {
			$name, $value = $matches[1 .. 2]
			if (!($name.StartsWith(";")))
			{
				$ini[$section][$name] = $value.Trim()
			}
		}
	}
	return $ini
}

function Test-IPAddress
{
	[CmdletBinding()]
	param
	(
		[Parameter(Mandatory = $true)]
		$IP
	)
	if ($ip -as [IPAddress] -ne $null)
	{
		$address = $ip.split(".")
		if ($address.Count -eq 4)
		{
			return $true
		}
	}
	return $false
}

function Test-NetMask
{
	[CmdletBinding()]
	param
	(
		[Parameter(Mandatory = $true)]
		$Mask
	)
	$SubnetMaskList = @()
	foreach ($Length in 1 .. 32)
	{
		$MaskBinary = ('1' * $Length).PadRight(32, '0')
		$DottedMaskBinary = $MaskBinary -replace '(.{8}(?!\z))', '${1}.'
		$SubnetMaskList += ($DottedMaskBinary.Split('.') | ForEach-Object { [Convert]::ToInt32($_, 2) }) -join '.'
	}
	if ($SubnetMaskList -contains $Mask)
	{
		return $true
	}
	return $false
}

# Hide Progress Bar
$progresspreference = "SilentlyContinue"

# Check for global.ini file
if (!(Test-Path -Path "$PSScriptRoot\global.ini")) {
    Write-Host -ForegroundColor Red "`n Missing Configuration File - $ConfigFile `n"
    Exit 1
}

# Start
Write-Host
Write-Host -ForegroundColor Gray   " ========================="
Write-Host -ForegroundColor Yellow " StorageGRID Configuration"
Write-Host -ForegroundColor Gray   " ========================="

# Read global.ini Settings
$config = Get-ConfigSettings -IniFileName "$PSScriptRoot\global.ini"

# Globals (global.ini)
$licensefile = ($config["GLOBAL"]).LICENSE_FILE
$g_dc = ($config["GLOBAL"]).DATACENTER
$g_site = ($config["GLOBAL"]).SITE
$g_ntps = ($config["GLOBAL"]).NTP_SERVERS
$g_dns = ($config["GLOBAL"]).DNS_SERVERS
$g_grid_ip_primary = ($config["GLOBAL"]).GRID_IP_PRIMARY_ADMIN
$g_grid_networks = ($config["GLOBAL"]).GRID_NETWORKS
$g_prov_phrase = ($config["GLOBAL"]).PROVISION_PASSPHRASE
$g_mgmt_phrase = ($config["GLOBAL"]).MGMT_PASSPHRASE
$g_low_installed_memory_alert = ($config["GLOBAL"]).LOW_INSTALLED_MEMORY_ALERT
if ($g_low_installed_memory_alert -eq 'disable'){
	$disable_alert = $true
} else {
	$disable_alert = $false
}
$g_open_gui = ($config["GLOBAL"]).OPEN_GUI
if ($g_open_gui -eq 'yes') { $g_open_gui = $true}

# Check NTP Server(s)
if ($g_ntps.Length -lt 7) {
	Write-Host -ForegroundColor Yellow "`n At least one Valid NTP Server is Required `n"
	Exit 1
} else {
	$count = 0
	$ntp_list = $g_ntps.Split(",")
	if ($ntp_list.count -gt 4){
		Write-Host -ForegroundColor Yellow "`n Maximum of 4 NTP Servers Exceeded `n"
		Exit 1
	}
	foreach ($ntp IN $ntp_list) {
		if (!(Test-IPAddress -IP $ntp)){
			Write-Host -ForegroundColor Yellow "`n NTP IP Address is Invalid ($ntp) `n"
			$count++
		}
	}
	if ($count -gt 0){
		Exit 1
	}
}

# Check DNS Server(s)
if ($g_dns.Length -lt 7) {
	Write-Host -ForegroundColor Yellow "`n At least one Valid DNS Server is Required `n"
	Exit 1
} else {
	$count = 0
	$dns_list = $g_dns.Split(",")
	if ($dns_list.count -gt 2){
		Write-Host -ForegroundColor Yellow "`n Maximum of 2 DNS Servers Exceeded `n"
		Exit 1
	}
	foreach ($dns IN $dns_list) {
		if (!(Test-IPAddress -IP $dns)){
			Write-Host -ForegroundColor Yellow "`n DNS IP Address is Invalid ($ntp) `n"
			$count++
		}
	}
	if ($count -gt 0){
		Exit 1
	}
}

# Check License File and Encode (Base64/UTF8)
if (Test-Path -Path $licensefile){
	$temp = Get-Content -Path "$licensefile"
    $license = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($temp))
} else {
    Write-Host -ForegroundColor Red " Missing License File - $licensefile"
    Exit 1
}

# Version of StorageGRID
$uri = "https://" + $g_grid_ip_primary + "/api/v3/install/config/product-version"
$result = Invoke-RestMethod -Method Get -Uri $uri -SkipCertificateCheck
$sgversion = $result.data.productVersion

Write-Host -ForegroundColor Cyan " Product Version: `t" -NoNewline
Write-Host -ForegroundColor White $sgversion

# Status of install
Write-Host -ForegroundColor Cyan " Installaton Status: `t" -NoNewline
$uri = "https://" + $g_grid_ip_primary + "/api/v3/install/start"
try {
	$result = Invoke-RestMethod -Method Get -Uri $uri -SkipCertificateCheck
} catch {
	# if an error is thrown with status code 405 (MethodNotAllowed) 
	# it means installation has completed and the install api is no longer available
	if ($_.Exception.Response.StatusCode -eq 'MethodNotAllowed') {
		Write-Host -ForegroundColor Green "Grid Installed & Configured`n"
		exit 0
	}
}

if ($result.data.complete) { 
    Write-Host -ForegroundColor Green "COMPLETE`n"
    Write-Host
    Exit 0
} elseif ($result.data.inProgress) {
    Write-Host -ForegroundColor Yellow "IN PROGRESS`n"
    Write-Host
    Exit 0
} else {
	Write-Host -ForegroundColor White "READY"
}

# Grid Details (PUT /install/grid-details)
Write-Host -ForegroundColor Cyan " Datacenter: `t`t" -NoNewline
Write-Host -ForegroundColor White "$g_dc"
Write-Host -ForegroundColor Cyan " License: `t`t" -NoNewline
Write-Host -ForegroundColor White $licensefile
$uri = "https://" + $g_grid_ip_primary + "/api/v3/install/grid-details"
$body = @{
	name = "$g_dc"
	license = "$license"
}
$body = $body | ConvertTo-Json -Depth 2
try {
	$result = Invoke-RestMethod -Method PUT -Uri $uri -ContentType 'application/json' -SkipCertificateCheck -Body $body
} catch {
	$errmsg = $_.Exception.Message
	Write-Host -ForegroundColor Red "`n $errmsg `n"
	Exit 1
}

# Passwords (PUT /install/passwords)
Write-Host -ForegroundColor Cyan " Set Passwords"
$uri = "https://" + $g_grid_ip_primary + "/api/v3/install/passwords"
$body = @"
{
	"provision": "$g_prov_phrase",
	"management": "$g_mgmt_phrase",
	"useRandom": true
}
"@
try {
	$result = Invoke-RestMethod -Method PUT -Uri $uri -ContentType 'application/json' -SkipCertificateCheck -Body $body
} catch {
	$errmsg = $_.Exception.Message
	Write-Host -ForegroundColor Red "`n $errmsg `n"
	Exit 1
}

# NTP Servers (PUT /install/ntp-servers)
Write-Host -ForegroundColor Cyan " NTP Servers:"
$uri = "https://" + $g_grid_ip_primary + "/api/v3/install/ntp-servers"
$ntp_list = $g_ntps.Split(",")
foreach ($ntp IN $ntp_list) {Write-Host -ForegroundColor White " - $ntp"}
$body = ConvertTo-Json @($ntp_list)
try {
	$result = Invoke-RestMethod -Method PUT -Uri $uri -ContentType 'application/json' -SkipCertificateCheck -Body $body
} catch {
	$errmsg = $_.Exception.Message
	Write-Host -ForegroundColor Red "`n $errmsg `n"
	Exit 1
}

# DNS Servers (PUT /install/dns-servers)
Write-Host -ForegroundColor Cyan " DNS Servers:"
$uri = "https://" + $g_grid_ip_primary + "/api/v3/install/dns-servers"
$dns_list = $g_dns.Split(",")
foreach ($dns IN $dns_list) {Write-Host -ForegroundColor White " - $dns"}
$body = ConvertTo-Json @($dns_list)
try {
	$result = Invoke-RestMethod -Method PUT -Uri $uri -ContentType 'application/json' -SkipCertificateCheck -Body $body
} catch {
	$errmsg = $_.Exception.Message
	Write-Host -ForegroundColor Red "`n $errmsg `n"
	Exit 1
}

# GRID Networks (PUT /install/grid-networks)
if ($g_grid_networks.Length -gt 6) {
	Write-Host -ForegroundColor Cyan " Grid Networks: "
	$uri = "https://" + $g_grid_ip_primary + "/api/v3/install/grid-networks"
	$gn_list = $g_grid_networks.Split(",")
	foreach ($gn IN $gn_list) {
		Write-Host -ForegroundColor White " - $gn"
	}
	$body = ConvertTo-Json @($gn_list)
	try {
		$result = Invoke-RestMethod -Method PUT -Uri $uri -ContentType 'application/json' -SkipCertificateCheck -Body $body
	} catch {
		$errmsg = $_.Exception.Message
		Write-Host -ForegroundColor Red "`n $errmsg `n"
		Exit 1
	}
}

# Create Site (POST /install/sites - Save Site ID)
Write-Host -ForegroundColor Cyan " Site: `t`t`t" -NoNewline
Write-Host -ForegroundColor White $g_site
$uri = "https://" + $g_grid_ip_primary + "/api/v3/install/sites"
try {
	$result = Invoke-RestMethod -Method GET -Uri $uri -ContentType 'application/json' -SkipCertificateCheck
} catch {
	$errmsg = $_.Exception.Message
	Write-Host -ForegroundColor Red "`n $errmsg `n"
	Exit 1
}
$site_exists = $false
foreach ( $s IN $result.data ){
	if ($s.name -eq $g_site) {
		$site_exists = $true
		$siteid = $s.id
	}
}
$body = @"
{
	"name": "$g_site"
}
"@
if (!($site_exists)){
	$uri = "https://" + $g_grid_ip_primary + "/api/v3/install/sites"
	try {
		$result = Invoke-RestMethod -Method POST -Uri $uri -ContentType 'application/json' -SkipCertificateCheck -Body $body
		$siteid = $result.data.id
	} catch {
		$errmsg = $_.Exception.Message
		Write-Host -ForegroundColor Red "`n $errmsg `n"
		Exit 1
	}
}

# Get Unregistered Nodes
Write-Host -ForegroundColor Cyan " Register Nodes:"
$uri = "https://" + $g_grid_ip_primary + "/api/v3/install/nodes"
try {
	$result = Invoke-RestMethod -Method GET -Uri $uri -ContentType 'application/json' -SkipCertificateCheck
} catch {
	$errmsg = $_.Exception.Message
	Write-Host -ForegroundColor Red "`n $errmsg `n"
	Exit 1
}

# Register Node (set Site ID if NULL)
foreach ($n IN $result.data){
	if ($null -eq $n.site) {
		$nodeid = $n.id
		$nodename = $n.name
		$n.site = $siteid
		Write-Host -ForegroundColor White " - $nodename"
		$uri = "https://" + $g_grid_ip_primary + "/api/v3/install/nodes/$nodeid"
		$temp = $n | ConvertTo-Json -Depth 99 | ConvertFrom-Json
		$temp.PSObject.Properties.Remove('ntpRole')
		$temp.PSObject.Properties.Remove('hasADC')
		$temp.PSObject.Properties.Remove('configured')
		$body = $temp | ConvertTo-Json -Depth 99
		try {
			$reg = Invoke-RestMethod -Method PUT -Uri $uri -ContentType 'application/json' -SkipCertificateCheck -Body $body
		} catch {
			$errmsg = $_.Exception.Message
			Write-Host -ForegroundColor Red "`n $errmsg `n"
			Exit 1
		}
	}
}

# Start Install (POST /install/start)
Write-Host -ForegroundColor Cyan " Start Installation"
$uri = "https://" + $g_grid_ip_primary + "/api/v3/install/start"
try {
	$result = Invoke-RestMethod -Method POST -Uri $uri -ContentType 'application/json' -SkipCertificateCheck
} catch {
	$errmsg = $_.Exception.Message
	Write-Host -ForegroundColor Red "`n $errmsg `n"
	Exit 1
}

Start-Sleep -Seconds 30

# Download Recovery Package
Write-Host -ForegroundColor Cyan " Download Recovery Package "
$uri = "https://" + $g_grid_ip_primary + "/api/v3/install/recovery-package"
$backupfile = "$PSScriptRoot\sgbackup" + (Get-Date -Format yyyymmdd-hhmmss) + ".zip"
try {
	$result = Invoke-RestMethod -Method Get -Uri $uri -SkipCertificateCheck -ContentType "application/zip" -OutFile "$backupfile"
} catch {
	# Probably not ready yet - not required to complete configuration
	$err = Get-Error
} finally {
	# Confirm Download (even if it didn't   ;-)  )
	$uri = "https://" + $g_grid_ip_primary + "/api/v3/install/recovery-package-confirm"
	try {
		$result = Invoke-RestMethod -Method POST -Uri $uri -SkipCertificateCheck
	} catch {
		$errmsg = $_.Exception.Message
		Write-Host -ForegroundColor Red "`n $errmsg `n"
		Exit 1
	}
}

# Monitor Installation
Write-Host -ForegroundColor Cyan " Monitoring Installation " -NoNewline
$uri = "https://" + $g_grid_ip_primary + "/api/v3/install/nodes"
$running = $true
$tries = 0
while ($running){
	Start-Sleep -Seconds 30
	write-host -ForegroundColor Gray '.' -NoNewline
	try {
		$result = Invoke-RestMethod -Method Get -Uri $uri -ContentType 'application/json' -SkipCertificateCheck
	} catch {
		# if an error is thrown with status code 405 (MethodNotAllowed) 
		# it means installation has completed and the install api is no longer available
		if ($_.Exception.Response.StatusCode -eq 'MethodNotAllowed') {
			$running = $false
		} else {
			$tries++
			if ($tries -eq 3) {
				Write-Host -ForegroundColor Red "`n $($_.Exception.Message) `n"
				Exit 1
			}
		}
	}
}
Write-Host -ForegroundColor Green ' Done'

# Disable Low Installed Memory Alert
if ($disable_alert){

	Write-Host -ForegroundColor Cyan " Disable Node Low Installed Memory Alert "

	# Get Access Token to Grid
	$uri = "https://" + $g_grid_ip_primary + "/api/v3/authorize"
	$body = @{
	   username = 'root'
	   password = "$g_mgmt_phrase"
	   cookie = $true
	   csrfToken = $false
	}
	$authBody = ConvertTo-Json $body
	try {
		$token = Invoke-RestMethod -Method Post -Uri $uri -ContentType 'application/json' -Body $authBody -SkipCertificateCheck
	} catch {
		$errmsg = $_.Exception.Message
		Write-Host -ForegroundColor Red "`n $errmsg `n"
		Exit 0
	}
	$bearer = $token.data

	# Create Authorization Header with Bearer Token
	$header = @{
	   accept = 'application/json'
	   Authorization = "Bearer $bearer"
	}

	# Disable the alert rule
	$body = @{
		enable = $false
	}
	$disableBody = ConvertTo-Json $body
	$uri = "https://" + $g_grid_ip_primary + "/api/v3/grid/alert-rules/NodeLowInstalledMemory"
	try {
		$result = Invoke-RestMethod -Method Put -Uri $uri -ContentType 'application/json' -Headers $header -Body $disableBody -SkipCertificateCheck
		if ($result.status -ne 'success'){
			Write-Host -ForegroundColor Yellow " Node Low Installed Memory Alert NOT Disabled"
		}
	} catch {
		Write-Host -ForegroundColor Yellow " Error Attempting to Disable Alert"
	}
	
}

# Finish
Write-Host -ForegroundColor Cyan " Admininstration URL: `t" -NoNewline
Write-Host -ForegroundColor White "https://$g_grid_ip_primary `n`n"

# Open StorageGRID GUI
 if ($g_open_gui){
	Start-Process "https://$g_grid_ip_primary"
 }

# END