#requires -version 7

[cmdletbinding()]
param (
	[Parameter(Mandatory = $True)]
	[string]$ConfigFile
)

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

# Check for PowerCLI Modules
$modules = Get-Module -ListAvailable -Name "VMware.PowerCLI"
if (!($modules)) {
	Write-Host -ForegroundColor Red "`n Missing VMware PowerCLI Modules `n"
    Exit 1
}

# Check for global.ini file
if (!(Test-Path -Path "$PSScriptRoot\global.ini")) {
    Write-Host -ForegroundColor Red "`n Missing Configuration File - global.ini `n"
    Exit 1
}

# Check $ConfigFile for a '.ini' extension - append if missing
if ($ConfigFile.IndexOf(".ini") -eq -1){
	$ConfigFile = $ConfigFile + ".ini"
}

# Check for {$ConfigFile}.ini file
if (!(Test-Path -Path "$ConfigFile")) {
    Write-Host -ForegroundColor Red "`n Missing Configuration File - $ConfigFile `n"
    Exit 1
}

# Read global.ini Settings
$config = Get-ConfigSettings -IniFileName "$PSScriptRoot\global.ini"

# vCenter
$vc_login = ($config["VCENTER"]).VCENTER_LOGIN
$vc_pw = ($config["VCENTER"]).VCENTER_PW
$vc_ip = ($config["VCENTER"]).VCENTER_IP

# Check vCenter IP Address
if (!(Test-IPAddress -IP $vc_ip)) {
	Write-Host -ForegroundColor Yellow "`n vCenter IP Address is Invalid ($vc_ip"
	Exit 1
}

# Ping vCenter
if (!(Test-Connection -TargetName $vc_ip -Count 2 -Quiet)) { 
	Write-Host -ForegroundColor Red " vCenter [$vc_ip] did not respond to ping" 
	EXIT 1
}

# Prompt for vCenter password if missing
if ($vc_pw.Length -eq 0) {
	Write-Host -ForegroundColor Cyan " Enter [$vc_login] Password: " -NoNewline
	$pw = Read-Host -AsSecureString
	$vc_pw = ConvertFrom-SecureString $pw -AsPlainText
	Write-Host
}

# Globals (global.ini)
$g_sgversion = ($config["GLOBAL"]).SG_VERSION
$g_ovfpath = ($config["GLOBAL"]).OVF_PATH
$g_dc = ($config["GLOBAL"]).DATACENTER
$g_site = ($config["GLOBAL"]).SITE
$g_combine = ($config["GLOBAL"]).ENABLE_COMBINE
$g_grid_mask = ($config["GLOBAL"]).GRID_MASK
$g_grid_gw = ($config["GLOBAL"]).GRID_GW
$g_grid_mtu = ($config["GLOBAL"]).GRID_MTU
$g_admin_mask = ($config["GLOBAL"]).ADMIN_MASK
$g_admin_gw = ($config["GLOBAL"]).ADMIN_GW
$g_admin_mtu = ($config["GLOBAL"]).ADMIN_MTU
$g_client_mask = ($config["GLOBAL"]).CLIENT_MASK
$g_client_gw = ($config["GLOBAL"]).CLIENT_GW
$g_client_mtu = ($config["GLOBAL"]).CLIENT_MTU
$g_gridnetwork = ($config["GLOBAL"]).GRID_NETWORK_MAPPING
$g_adminnetwork = ($config["GLOBAL"]).ADMIN_NETWORK_MAPPING
$g_clientnetwork = ($config["GLOBAL"]).CLIENT_NETWORK_MAPPING
$g_grid_admin_esl = ($config["GLOBAL"]).GRID_ADMIN_ESL

# Check Datacenter
if ($g_dc.Length -eq 0){
	Write-Host -ForegroundColor Yellow "`n Datacenter Name is REQUIRED `n"
	Exit 1
}

# Check Site
if ($g_site.Length -eq 0){
	Write-Host -ForegroundColor Yellow "`n Site Name is REQUIRED `n"
	Exit 1
}

# Check Netmasks
if (!(Test-NetMask -Mask $g_grid_mask)){
	Write-Host -ForegroundColor Yellow "`n GRID NetMask is Invalid ($g_grid_mask) `n"
	Exit 1
}
if (!(Test-NetMask -Mask $g_admin_mask)){
	Write-Host -ForegroundColor Yellow "`n ADMIN NetMask is Invalid ($g_admin_mask) `n"
	Exit 1
}
if (!(Test-NetMask -Mask $g_client_mask)){
	Write-Host -ForegroundColor Yellow "`n CLIENT NetMask is Invalid ($g_client_mask) `n"
	Exit 1
}

# Check Gateways
if ($g_grid_gw.Length -gt 0){
	if (!(Test-IPAddress -IP $g_grid_gw)){
		Write-Host -ForegroundColor Yellow "`n GRID Gateway is Invalid ($g_grid_gw) `n"
		Exit 1
	}
}
if ($g_admin_gw.Length -gt 0){
	if (!(Test-IPAddress -IP $g_admin_gw)){
		Write-Host -ForegroundColor Yellow "`n ADMIN Gateway is Invalid ($g_admin_gw) `n"
		Exit 1
	}
}
if ($g_client_gw.Length -gt 0){
	if (!(Test-IPAddress -IP $g_client_gw)){
		Write-Host -ForegroundColor Yellow "`n CLIENT Gateway is Invalid ($g_client_gw) `n"
		Exit 1
	}
}

# Check MTUs
if ($g_grid_mtu.Length -eq 0){
	$g_grid_mtu = 1400
}
if ($g_admin_mtu.Length -eq 0){
	$g_admin_mtu = 1400
}
if ($g_client_mtu.Length -eq 0){
	$g_client_mtu = 1400
}

# Read $ConfigFile for NODE_TYPE
$config = Get-ConfigSettings -IniFileName "$ConfigFile"

# Get NODE_TYPE
$node_type = ($config["SETTINGS"]).NODE_TYPE

# Get Common Settings
$esx_ip = ($config["SETTINGS"]).ESXHOST_IP
$datastore = ($config["SETTINGS"]).DATASTORE
$diskformat = ($config["SETTINGS"]).DISK_FORMAT
$cpus = ($config["SETTINGS"]).CPU_COUNT
$mem = ($config["SETTINGS"]).MEMORY_GB
$nodename = ($config["SETTINGS"]).NAME
$gridconfig = ($config["SETTINGS"]).GRID_NETWORK_CONFIG
$adminconfig = ($config["SETTINGS"]).ADMIN_NETWORK_CONFIG
$clientconfig = ($config["SETTINGS"]).CLIENT_NETWORK_CONFIG
$grid_ip = ($config["SETTINGS"]).GRID_IP
$admin_ip = ($config["SETTINGS"]).ADMIN_IP
$client_ip = ($config["SETTINGS"]).CLIENT_IP

# Check ESX Host IP Address
if (!(Test-IPAddress -IP $esx_ip)){
	Write-Host -ForegroundColor Yellow "`n ESX Host IP Address is Invalid ($esx_ip)"
	Exit 1
}

# Check Node IP Addresses
if (!(Test-IPAddress -IP $grid_ip)){
	Write-Host -ForegroundColor Yellow "`n GRID IP Address is Invalid ($grid_ip)"
	Exit 1
}
if (!(Test-IPAddress -IP $admin_ip)){
	Write-Host -ForegroundColor Yellow "`n ADMIN IP Address is Invalid ($admin_ip)"
	Exit 1
}
if (!(Test-IPAddress -IP $client_ip)){
	Write-Host -ForegroundColor Yellow "`n CLIENT IP Address is Invalid ($client_ip)"
	Exit 1
}

# Check Network Config Settings
if ( @('STATIC','DHCP') -notcontains $gridconfig) {
	Write-Host -ForegroundColor Red " Invalid GRID_NETWORK_CONFIG Setting - Must be STATIC or DHCP"
}
if ( @('STATIC','DHCP','DISABLED') -notcontains $adminconfig) {
	Write-Host -ForegroundColor Red " Invalid ADMIN_NETWORK_CONFIG Setting - Must be STATIC, DHCP, or DISABLED"
} 
if ( @('STATIC','DHCP','DISABLED') -notcontains $clientconfig) {
	Write-Host -ForegroundColor Red " Invalid CLIENT_NETWORK_CONFIG Setting - Must be STATIC, DHCP, or DISABLED"
}

# Check Disk Format
if ($diskformat.Length -eq 0){
	$diskformat = 'Thin'
}
if ( @('Thin','Thick','EagerZeroedThick') -notcontains $diskformat) {
	Write-Host -ForegroundColor Yellow "`n Invalid Disk Format - Must be Thin, Thick, or EagerZeroedThick"
	Exit 1
}

# Get OVF and node specific settings
switch ($node_type) {

	'PRIMARYADMIN' { 
		$sourceOvf = "$g_ovfpath\vsphere-primary-admin.ovf"
		$esl = $g_grid_admin_esl
	 }

	'NONPRIMARYADMIN'{ 
		$sourceOvf = "$g_ovfpath\vsphere-non-primary-admin.ovf"
		$esl = $g_grid_admin_esl
	}

	'STORAGE' { 
		$sourceOvf = "$g_ovfpath\vsphere-storage.ovf"
		$diskcount = ($config["SETTINGS"]).DISK_COUNT
		if ( [int]$diskcount -lt 3 ) { 
			$diskcount = 3
		}
		if ( [int]$diskcount -gt 16 ) { 
			$diskcount = 16
		}
		$disksize = ($config["SETTINGS"]).DISK_SIZE_GB
		if (( [int]$disksize -lt 5 ) -or ( $disksize.Length -eq 0 )) {
			$disksize = 5
		}
	}

	'APIGATEWAY' {
		$sourceOvf = "$g_ovfpath\vsphere-gateway.ovf"
	 }

	'ARCHIVE' { 
		$sourceOvf = "$g_ovfpath\vsphere-archive.ovf"
	}

	Default { 
		Write-Host -ForegroundColor Red " Invalid NODE_TYPE in $config"
		EXIT 1
	}

}

# Prepend/Combine Datacenter and Site names to node name
if ($g_combine -eq 'yes' ) {
	$full_nodename = $g_dc + "-" + $g_site + "-" + $nodename
} else {
	$full_nodename = $nodename
}

# Start
Write-Host

# Deploy Node
Write-Host -ForegroundColor Yellow " Deploying Node `t" -NoNewline
Write-Host -ForegroundColor Yellow "$full_nodename"

# Verify Source OVF
Write-Host -ForegroundColor Cyan " Verify Source OVF `t" -NoNewline
Write-Host -ForegroundColor White "$sourceOvf"

if (!(Test-Path -Path $sourceOvf)) { 
    Write-Host -ForegroundColor Red " Source OVF Not Found`n"
    Exit 1
}

# Copy .OVF to temporary .ovf in script path
$targetOvf = "$PSScriptRoot\temp.ovf"
Copy-Item -Path "$sourceOvf" "$targetOvf"

# Verify Source VMDK
$sourceVMDK = Get-ChildItem -Path "$g_ovfpath" -Filter "*.vmdk" -Recurse | ForEach-Object { $_.Name }
if ($sourceVMDK.Count -ne 1) {
	Write-Host -ForegroundColor Red " More than 1 .vmdk file found"
	Exit 1
}
Write-Host -ForegroundColor Cyan " Verify Source VMDK `t" -NoNewline
Write-Host -ForegroundColor White "$g_ovfpath\$sourceVMDK"

if(!(Test-Path -Path "$g_ovfpath\$sourceVMDK")){
	Write-Host -ForegroundColor Red " Source VMDK Not Found`n"
	Exit 1
}

# Copy .VMDK to script path
$targetVMDK = "$PSScriptRoot\$sourceVMDK"
if(!(Test-Path -Path $targetVMDK)){
	Write-Host -ForegroundColor Cyan " Copy Source VMDK"
	Copy-Item -Path "$g_ovfpath\$sourceVMDK" "$targetVMDK"
}

# Change CPU #
if ( $cpus -ne 8 ) {
	Write-Host -ForegroundColor Cyan " Change # of CPUs `t" -NoNewline
	Write-Host -ForegroundColor White "$cpus"
	(Get-Content "$targetOvf").Replace("<rasd:ElementName>8 virtual CPU(s)</rasd:ElementName>","<rasd:ElementName>$cpus virtual CPU(s)</rasd:ElementName>") | Set-Content "$targetOvf"
	(Get-Content "$targetOvf").Replace("<rasd:VirtualQuantity>8</rasd:VirtualQuantity>","<rasd:VirtualQuantity>$cpus</rasd:VirtualQuantity>")               | Set-Content "$targetOvf"
}

# Change Memory (GB)
$targetMemMB = [int]$mem * 1024
if ( $targetMemMB -ne 24576 ) {
	Write-Host -ForegroundColor Cyan " Change Memory `t`t" -NoNewline
	Write-Host -ForegroundColor White "$mem GB"
	(Get-Content "$targetOvf").Replace("<rasd:ElementName>24576MB of memory</rasd:ElementName>","<rasd:ElementName>$targetMemMB MB of memory</rasd:ElementName>") | Set-Content "$targetOvf"
	(Get-Content "$targetOvf").Replace("<rasd:Reservation>24576</rasd:Reservation>","<rasd:Reservation>$targetMemMB</rasd:Reservation>")                          | Set-Content "$targetOvf"
	(Get-Content "$targetOvf").Replace("<rasd:VirtualQuantity>24576</rasd:VirtualQuantity>","<rasd:VirtualQuantity>$targetMemMB</rasd:VirtualQuantity>")          | Set-Content "$targetOvf"
}

# Change Disk Size and Count
# - Default disk size is 4TB with a minimum of 3 disks
if ($node_type -eq "STORAGE" ) {
	if ($disksize -ne 4000){
		Write-Host -ForegroundColor Cyan " Change Disk Size`t" -NoNewline
		Write-Host -ForegroundColor White "$disksize GB"
		(Get-Content "$targetOvf").Replace('<Disk ovf:capacity="4" ovf:capacityAllocationUnits="byte * 2^40" ovf:diskId="RangeDB disk 1" ovf:format="http://www.vmware.com/interfaces/specifications/vmdk.html#streamOptimized" />',"<Disk ovf:capacity=`"$disksize`" ovf:capacityAllocationUnits=`"byte * 2^30`" ovf:diskId=`"RangeDB disk 1`" ovf:format=`"http://www.vmware.com/interfaces/specifications/vmdk.html#streamOptimized`" />") | Set-Content "$targetOvf"
		(Get-Content "$targetOvf").Replace('<Disk ovf:capacity="4" ovf:capacityAllocationUnits="byte * 2^40" ovf:diskId="RangeDB disk 2" ovf:format="http://www.vmware.com/interfaces/specifications/vmdk.html#streamOptimized" />',"<Disk ovf:capacity=`"$disksize`" ovf:capacityAllocationUnits=`"byte * 2^30`" ovf:diskId=`"RangeDB disk 2`" ovf:format=`"http://www.vmware.com/interfaces/specifications/vmdk.html#streamOptimized`" />") | Set-Content "$targetOvf"
		(Get-Content "$targetOvf").Replace('<Disk ovf:capacity="4" ovf:capacityAllocationUnits="byte * 2^40" ovf:diskId="RangeDB disk 3" ovf:format="http://www.vmware.com/interfaces/specifications/vmdk.html#streamOptimized" />',"<Disk ovf:capacity=`"$disksize`" ovf:capacityAllocationUnits=`"byte * 2^30`" ovf:diskId=`"RangeDB disk 3`" ovf:format=`"http://www.vmware.com/interfaces/specifications/vmdk.html#streamOptimized`" />") | Set-Content "$targetOvf"
	}
	if ([int]$diskcount -gt 3){
		Write-Host -ForegroundColor Cyan " Change Disk Count`t" -NoNewline
		Write-Host -ForegroundColor White "$diskcount"
	}
}

# Connect to vCenter
Write-Host -ForegroundColor Cyan " Connect to vCenter"
try {
	$vc_conn = Connect-VIServer -Server $vc_ip -User $vc_login -Password $vc_pw -Force	
} catch {
	Write-Host -ForegroundColor Red " Error Connectiong to vCenter - verify account and password are correct in global.ini"
	Exit 1
}

# Check for VM with Same Name
$exists = Get-VM -Name $full_nodename -ErrorAction SilentlyContinue
If ($exists) {
	Write-Host -ForegroundColor Red "`n VM with Same Name ($full_nodename) Already Exists `n"
	Remove-Item -Path "$targetOvf" -Force
	Exit 0
}

# Update OVF Configuration
$ovfConfig = Get-OvfConfiguration -Ovf "$targetOvf"

# Node Name
$ovfConfig.Common.NODE_NAME.Value = "$full_nodename"

Write-Host -ForegroundColor Cyan " Network Settings"

# Grid Network Settings
Write-Host -ForegroundColor White " - GRID  : $g_gridnetwork | $gridconfig " -NoNewline
$ovfConfig.NetworkMapping.Grid_Network.Value = $g_gridnetwork
$ovfConfig.Common.GRID_NETWORK_CONFIG.Value = "$gridconfig"
if ($gridconfig -eq 'STATIC'){
	Write-Host -ForegroundColor White "| $grid_ip | $g_grid_mask | $g_grid_gw | $g_grid_mtu"
	$ovfConfig.Common.GRID_NETWORK_IP.Value = "$grid_ip"
	$ovfConfig.Common.GRID_NETWORK_MASK.Value = "$g_grid_mask"
	$ovfConfig.Common.GRID_NETWORK_GATEWAY.Value = "$g_grid_gw"
	$ovfConfig.Common.GRID_NETWORK_MTU.Value = "$g_grid_mtu"
} else {
	Write-Host
	$ovfConfig.Common.GRID_NETWORK_IP.Value = ""
	$ovfConfig.Common.GRID_NETWORK_MASK.Value = ""
	$ovfConfig.Common.GRID_NETWORK_GATEWAY.Value = ""
}

# Admin Network Settings
Write-Host -ForegroundColor White " - ADMIN : $g_adminnetwork | $adminconfig " -NoNewline
$ovfConfig.NetworkMapping.Admin_Network.Value = $g_adminnetwork
$ovfConfig.Common.ADMIN_NETWORK_CONFIG.Value = "$adminconfig"
if ($adminconfig -eq 'STATIC'){
	Write-Host -ForegroundColor White "| $admin_ip | $g_admin_mask | $g_admin_gw | $g_admin_mtu"
	$ovfConfig.Common.ADMIN_NETWORK_IP.Value = "$admin_ip"
	$ovfConfig.Common.ADMIN_NETWORK_MASK.Value = "$g_admin_mask"
	$ovfConfig.Common.ADMIN_NETWORK_GATEWAY.Value = "$g_admin_gw"
	$ovfConfig.Common.ADMIN_NETWORK_MTU.Value = "$g_admin_mtu"
} else {
	Write-Host
	$ovfConfig.Common.ADMIN_NETWORK_IP.Value = ""
	$ovfConfig.Common.ADMIN_NETWORK_MASK.Value = ""
	$ovfConfig.Common.ADMIN_NETWORK_GATEWAY.Value = ""
}

if ( ($node_type -eq "PRIMARYADMIN") -or ($node_type -eq "NONPRIMARYADMIN") ) {
	if ( $esl.Length -ne 0) {
		$ovfConfig.Common.ADMIN_NETWORK_ESL.Value = "$g_grid_admin_esl"
	}
}

# Client Network Settings
Write-Host -ForegroundColor White " - CLIENT: $g_clientnetwork | $clientconfig " -NoNewline
$ovfConfig.NetworkMapping.Client_Network.Value = $g_clientnetwork
$ovfConfig.Common.CLIENT_NETWORK_CONFIG.Value = "$clientconfig"
if ($clientconfig -eq 'STATIC'){
	Write-Host -ForegroundColor White "| $client_ip | $g_client_mask | $g_client_gw | $g_client_mtu"
	$ovfConfig.Common.CLIENT_NETWORK_IP.Value = "$client_ip"
	$ovfConfig.Common.CLIENT_NETWORK_MASK.Value = "$g_client_mask"
	$ovfConfig.Common.CLIENT_NETWORK_GATEWAY.Value = "$g_client_gw"
	$ovfConfig.Common.CLIENT_NETWORK_MTU.Value = "$g_client_mtu"
} else {
	Write-Host
	$ovfConfig.Common.CLIENT_NETWORK_IP.Value = ""
	$ovfConfig.Common.CLIENT_NETWORK_MASK.Value = ""
	$ovfConfig.Common.CLIENT_NETWORK_GATEWAY.Value = ""
}

# Import OVF 
Write-Host -ForegroundColor Cyan " Importing OVF `t`t" -NoNewline
try {
	$import = Import-VApp -Source "$targetOvf" -OvfConfiguration $ovfConfig -Name $full_nodename -Datastore $datastore -DiskStorageFormat $diskformat -VMHost $ESX_IP -Force 
} catch {
	Exit 1
}
Write-Host -ForegroundColor Green "SUCCESS"

# Cleanup
Remove-Item -Path "$targetOvf" -Force

# Get VM object
$vm = Get-VM -Name $full_nodename

# Add Disks - distribute across SCSI Controller 1 & 2
if (( $node_type -eq "STORAGE" ) -and ( [int]$diskcount -gt 3 )) {
	$newdisks = $diskcount - 3
	$ds = Get-Datastore -Name $datastore
	Write-Host -ForegroundColor Cyan " Add $newdisks Disks"
	for ($i=4; $i -le $diskcount; $i++ ) {
		if (($i % 2) -eq 0) {
			$controller = "SCSI controller 1"
		} else {
			$controller = "SCSI controller 2"
		}
		$addDisk = New-HardDisk -VM $vm -CapacityGB $disksize -Datastore $ds -StorageFormat $diskformat -Controller "$controller"
	}
}

# Add Note to VM
$datetime = Get-Date 
$note = "StorageGRID Version: $g_sgversion`r`nNode Type: $node_type`r`nDeployed: $datetime`r`n"
$vmNote = $vm | Set-VM -Notes $note -Confirm:$false

# Power On Node
Write-Host -ForegroundColor Cyan " Power On Node `t`t" -NoNewline
switch ($vm.PowerState) {
	PoweredOn  { 
		Write-Host -ForegroundColor Yellow "Already Powered On"
		break 
	}
	PoweredOff { 
		Write-Host -ForegroundColor Green "Powering On"
		$powerstate = Start-VM -VM $vm
		break
	}
	Suspended {
		Write-Host -ForegroundColor Red "Power Suspended"
		break
	}
}

Start-Sleep -Seconds 2

Exit 0

# END