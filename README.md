## StorageGRID 11.8 Deployment and Configuration (vSphere / PowerShell 7)

* [Description](#Description)
* [Disclaimer](#Disclaimer)
* [Requirements](#Requirements)
* [Dev/Test Environment](#Dev/Test-Environment)
* [Setup](#Setup)
* [Provided Scripts](#Provided-Scripts)
* [Usage / Examples](#Usage-/-Examples)
* [Workflow Tasks](#Workflow-Tasks)
* [Comments](#Comments)

### Description
* This is a set of PowerShell scripts to deploy a vSphere implementation of StorageGrid 11.6. A set of .INI files provide the necessary parameters to deploy and configure the virtual machines/nodes. Primarily intended to quickly deploy and configure a virtual StorageGRID environment for POCs and lab enviroments (eval/test) though it could be used for production environments (see [Disclaimer](#Disclaimer) and [Comments](#Comments)). 
* Ability to change CPU, memory, disk count, and disk size for the virtual nodes which makes it easier to deploy on vSphere systems with minimal resources. A site deployment can be accomplished on a single ESXi host. 
* Templates with comments are provided in the /templates directory along with examples (/templates/examples).
* The scripts are idempotent and can be re-executed without any 'known' issues.

### Disclaimer
* The script and associated components are provided as-is and are intended to provide an example of utilizing PowerShell, PowerCLI, and the Invoke-RestMethod cmdlet. Fully test in a non-production enviornment before implementing. Feel free to utilize/modify any portion of code for your specific needs.

### Requirements
* Windows system with connectivity to vCenter management network and GRID network 
* StorageGRID 11.8 - VMware
* vSphere 6.7 or later with ESXi host(s) managed by vCenter
* PowerShell 7.4 or later
* VMware PowerCLI 12.5 (all modules)
* DNS and NTP

### Dev/Test Environment
* Windows 2019 Server (jumpbox used to execute scripts)
* PowerShell version 7.4
* StorageGRID version 11.8 (StorageGRID-Webscale-11.8.0-VMware-20240131.0139.e3e0c87)
* VMware vSphere 6.7 U3

### Setup
1. Download 'StorageGRID 11.8 - VMware' from the NetApp Support Site (.zip)
2. Extract the .zip file and note the path to the /vsphere directory that contains the .VMDK and .OVF files
3. Copy the provided scripts and templates to a directory/location to run the scripts
4. Copy the /templates/template_global.ini file to the scripts directory and rename to global.ini (required name)
5. Edit the global.ini settings for the targeted environment
6. Copy and rename the associated /templates/template_{nodetype}.INI for each type of node to the scripts directory where the .ps1 files are located 
7. A separate .INI is needed for EACH node to deploy. As an example, create a primaryadmin node, three (3) storage nodes, and an apigateway node.
8. Supported node types: PRIMARYADMIN, NONPRIMARYADMIN, STORAGE, APIGATEWAY, and ARCHIVE
9. When renaming {nodetype}.INI files, use short, descriptive names (ie: pa.ini,s1.ini s2.ini,s3.ini.gw.ini)
10. Edit the settings in each .INI file (for examples go to /templates/examples)

### Provided Scripts
* deploy.ps1 - requires the VMware PowerCLI modules. It will connect to vCenter, make a copy of the specific nodetype .OVF file located in the extracted StorageGRID download, make modifications based on the nodes .ini settings, and import the .ovf and .vmdk. 
* configure.ps1 - this script will add GRID details, apply the license, add NTP and DNS server IP addresses, configure the GRID network, register any unregistered nodes, start installation, download a recovery package, and monitor the installation to completion.
* build.ps1 - a top level script that allows you to deploy and configure everything in one step 

### Usage / Examples
Assuming the deployment and configuration of a primary admin node, three (3) storage nodes, and an API gateway:

* To deploy a single StorageGRID node

          PS C:\scripts >  ./deploy.ps1 -ConfigFile pa.ini

* To deploy all StorageGRID nodes (the .ini extension can be dropped and the script will append)

          PS C:\scripts > ./build.ps1 -NodeList pa,s1,s2,s3,gw
          
* To deploy and configure StorageGRID

          PS C:\scripts > ./build.ps1 -NodeList pa,s1,s2,s3,gw -Configure
          
* The .INI files can be in any path

          PS C:\scripts > ./build.ps1 -NodeList d:\ini\pa.ini,d:\ini\s1.ini,d:\ini\s2.ini,d:\ini\s3.ini,d:\ini\gw.ini -Configure

* Configure StorageGRID after all nodes are deployed

          PS C:\scripts > ./configure.ps1

### Workflow Tasks
**<u>deploy.ps1</u>**
1. Check for PowerCLI modules
2. Check for global.ini file
3. Check ConfigFile for a '.ini' extension - append if missing
4. Check for {node}.ini file
5. Read global.ini settings (vCenter parameters)
6. Get vCenter credentials and IP
7. Ping test vCenter (reachable?)
8. Prompt for vCenter password if missing
9. Process global.ini file
10. Validate global.ini settings
11. Process {node}.ini file
12. Validate {node}.ini settings
13. Get OVF and node specific settings
14. Prepend/combine datacenter and site name to node name for VM name in vCenter (optional - format: datacenter-site-nodename)
15. Deploy node with updated .OVF settings in a copy of the original .OVF (PowerCLI:  Import-VApp)
16. If a storage node, add disks to VM if specified in {node}.ini
17. Add info to VM Notes field (StorageGRID Version, Node Type, and Date/Time deployed)

**<u>configure.ps1</u>**
1. Read global.ini settings
2. Check NTP and DNS IPs provided
3. Check License File and Encode (Base64/UTF8) (an 'unsupported' license file is provided in the .zip download)
4. Check current status of install - must be 'READY'
5. Add GRID details (datacenter and license)
6. Set passwords for provision and management accounts
7. Add DNS and NTP Servers
8. Update GRID network
9. Create site
10. Retrieve unregistered nodes
11. Register each node
12. Start install
13. Download Recovery Package
14. Monitor Installation to completion
15. Disable Low Installed Memory Alert (optional - useful for POC/lab environments)

**<u>build.ps1</u>**
1. Check -NodeList files for a '.ini' extension - append if missing
2. Check for each {node}.ini file
3. Loop through the NodeList files and invoke deploy.ps1
4. If deploy.ps1 returns with non-zero exit code, stop script
5. Wait ~5 minutes after last node is deployed to allow all nodes to complete boot process and start services
6. If -Configure switch specified, invoke configure.ps1
<br>

**<u>Example Build Output</u>**

![alt text](https://github.com/johncchampion/sg_vsphere/blob/main/images/sg-vmware1.png "Build Script Output")

**<u>Example Configure Output</u>**

![alt text](https://github.com/johncchampion/sg_vsphere/blob/main/images/sg-vmware2.png "Configure Script Output")

### Comments
* **Be aware there are MINIMUM requirements for StorageGRID VMware nodes that are 'supported' and these scripts provide the potential to not meet them**. Before using in a production environment be sure the desired configuration and settings are supported by NetApp. 
*  Not meeting minimum CPU, memory, and disk requirements will impact performance.  For lab and POC environments this is usually acceptable but if evaluating performance related metrics be sure meet (or exceed) the minimums.
* During installation (configure.ps1 running) the process can be viewed in a browser by opening https://{GRID_IP_PRIMARY_ADMIN} (no login required during install)

<br/>
<br/>