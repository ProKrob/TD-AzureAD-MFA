configuration CreateADPDC 
{ 
   param 
   ( 
        [Parameter(Mandatory)]
        [String]$DomainName,

        [Parameter(Mandatory)]
        [System.Management.Automation.PSCredential]$Admincreds,

        [Int]$RetryCount=20,
        [Int]$RetryIntervalSec=30
    ) 
    
    Import-DscResource -ModuleName xActiveDirectory, xStorage, xNetworking, xPSDesiredStateConfiguration, xPendingReboot
    [System.Management.Automation.PSCredential ]$DomainCreds = New-Object System.Management.Automation.PSCredential ("${DomainName}\$($Admincreds.UserName)", $Admincreds.Password)
    $Interface=Get-NetAdapter|Where Name -Like "Ethernet*"|Select-Object -First 1
    $InterfaceAlias=$($Interface.Name)

    Node localhost
    {
        LocalConfigurationManager 
        {
            RebootNodeIfNeeded = $true
        }

	    WindowsFeature DNS 
        { 
            Ensure = "Present" 
            Name = "DNS"		
        }

        Script EnableDNSDiags
	    {
      	    SetScript = { 
		        Set-DnsServerDiagnostics -All $true
                Write-Verbose -Verbose "Enabling DNS client diagnostics" 
            }
            GetScript =  { @{} }
            TestScript = { $false }
	        DependsOn = "[WindowsFeature]DNS"
        }

	    WindowsFeature DnsTools
	    {
	        Ensure = "Present"
            Name = "RSAT-DNS-Server"
            DependsOn = "[WindowsFeature]DNS"
	    }

        xDnsServerAddress DnsServerAddress 
        { 
            Address        = '127.0.0.1' 
            InterfaceAlias = $InterfaceAlias
            AddressFamily  = 'IPv4'
	        DependsOn = "[WindowsFeature]DNS"
        }

        xWaitforDisk Disk2
        {
            DiskNumber = 2
            RetryIntervalSec =$RetryIntervalSec
            RetryCount = $RetryCount
        }

        xDisk ADDataDisk {
            DiskNumber = 2
            DriveLetter = "F"
            DependsOn = "[xWaitForDisk]Disk2"
        }

        WindowsFeature ADDSInstall 
        { 
            Ensure = "Present" 
            Name = "AD-Domain-Services"
	        DependsOn="[WindowsFeature]DNS" 
        } 

        WindowsFeature ADDSTools
        {
            Ensure = "Present"
            Name = "RSAT-ADDS-Tools"
            DependsOn = "[WindowsFeature]ADDSInstall"
        }

        WindowsFeature ADAdminCenter
        {
            Ensure = "Present"
            Name = "RSAT-AD-AdminCenter"
            DependsOn = "[WindowsFeature]ADDSInstall"
        }
         
        xADDomain FirstDS 
        {
            DomainName = $DomainName
            DomainAdministratorCredential = $DomainCreds
            SafemodeAdministratorPassword = $DomainCreds
            DatabasePath = "F:\NTDS"
            LogPath = "F:\NTDS"
            SysvolPath = "F:\SYSVOL"
	        DependsOn = @("[xDisk]ADDataDisk", "[WindowsFeature]ADDSInstall")
        } 

$RootOUs = $ConfigurationData.NonNodeData.RootOUs | ConvertFrom-CSV


        ForEach ($RootOU in $ConfigurationData.NonNodeData.RootOUs) {
        
            Write-Host "Creating RootOU: $RootOU" 
            
            xADOrganizationalUnit "OU_$RootOu"
            {
                Name = $RootOU
                Path = $DomainRoot
                ProtectedFromAccidentalDeletion = $true
                Credential = $DomainCred
                Ensure = 'Present'
            }

            ForEach ($ChildOU in $ConfigurationData.NonNodeData.ChildOUs) {
                
                Write-Host "...creating ChildOU: $ChildOU" 

                xADOrganizationalUnit "OU_$($RootOU)_$ChildOU"
                {
                    Name = $ChildOU
                    Path = "OU=$RootOU,$DomainRoot"
                    ProtectedFromAccidentalDeletion = $true
                    Credential = $DomainCred
                    Ensure = 'Present'
                }

            }

        }



        $Users = $ConfigurationData.NonNodeData.UserData | ConvertFrom-CSV


        ForEach ($User in $Users) {
            Write-Host "Creating User: "  $User.UserName " Group: "  $User.Dept  "/Users"

            xADUser $User.UserName
            {
                UserName = $User.UserName
                JobTitle = $User.Title
                Enabled = $true
                Password = (New-Object System.Management.Automation.PSCredential($User.UserName,($User.password | ConvertTo-SecureString -AsPlainText -Force)) )
                DomainName = $DomainName
                PasswordNeverExpires = $true
                Ensure = 'Present'
                Path = "OU=Users,OU=$($User.Dept),$DomainRoot"
                
            }
        }
        
   }
} 