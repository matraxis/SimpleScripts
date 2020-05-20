function Get-UAServerInformation {
    [CmdletBinding()]
    param (
        # Hostname of the server to query
        [Parameter(
            Mandatory = $true,
            Position = 0
        )]
        [string]
        $ServerHostname,

        # Specifies a path to one or more locations.
        [Parameter(
            Mandatory = $true,
            Position = 1,
            HelpMessage = "Path to one location."
        )]
        [Alias("PSPath")]
        [ValidateScript( {
                if (-not ($_ | Test-Path -PathType Container)) {
                    Throw "Path is not a valid folder."
                }
                else {
                    return $true
                }
            })]
        [System.IO.FileInfo]
        $Path,

        # Credential to use
        [Parameter(
            Mandatory = $false,
            Position = 2
        )]
        [PSCredential]
        $Credential
    )
    
    begin {
        Write-Verbose -Message "Checking connectivity to the server."
        if (Test-NetConnection -ComputerName $ServerHostname -CommonTCPPort WINRM -InformationLevel Quiet) {
            Write-Verbose -Message "Connectivity for WINRM looks good."
        }
        else {
            Write-Error -Message "Could not connect to device on WINRM." -Exception "Could not connect" -Category ConnectionError -ErrorAction Stop
        }
    }
    
    process {
        Write-Verbose -Message "Setting up PS Session to $ServerHostname."
        if ($Credential) {
            $PSSession = New-PSSession -ComputerName $ServerHostname -Credential $Credential
        }
        else {
            $PSSession = New-PSSession -ComputerName $ServerHostname
        }

        Write-Verbose -Message "Getting data from PSSession to $ServerHostname."
        Write-Verbose -Message "Getting Applications from $ServerHostname."
        $Applications = Invoke-Command -Session $PSSession -ScriptBlock {
            Return (Get-ItemProperty HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\* | Where-Object {$null -ne $_.DisplayName} | Select-Object DisplayName, DisplayVersion, Publisher, InstallDate)
        }
        Write-Verbose -Message "Getting Services from $ServerHostname."
        $Services = Invoke-Command -Session $PSSession -ScriptBlock {
            Return (Get-Service | Where-Object {$_.Status -eq "Running"} | Select-Object Name, DisplayName, Status, StartType)
        }
        Write-Verbose -Message "Getting IP Address Information from $ServerHostname."
        $IPAddressInformation = Invoke-Command -Session $PSSession -ScriptBlock {
            Return (Get-NetIPAddress)
        }
        Write-Verbose -Message "Getting Disk information rom $ServerHostname."
        $DiskInformation = Invoke-Command -Session $PSSession -ScriptBlock {
            Return (Get-Disk)
        }
        Write-Verbose -Message "Checking for Cluster Components."
        $ClusterComponents = Invoke-Command -Session $PSSession -ScriptBlock {
            if ((Get-WindowsFeature -Name Failover*).InstallState -eq "Installed") {
                $ClusterInfo = Get-ClusterResource -ErrorAction SilentlyContinue
            }
            Return $ClusterInfo
        }
        Write-Verbose -Message "Gettign IIS Website Features from $ServerHostname."
        $IISInformation = Invoke-Command -Session $PSSession -ScriptBlock {
            Return (Get-Website -ErrorAction SilentlyContinue)
        }
        Write-Verbose -Message "Getting Windows Features from $ServerHostname."
        $Features = Invoke-Command -Session $PSSession -ScriptBlock {
            Return (Get-WindowsFeature | Where-Object {$_.InstallState -in ("Installed")})
        }
        Write-Verbose -Message "Getting Active Listening Ports."
        $ListeningPorts = Invoke-Command -Session $PSSession -ScriptBlock {
            Return (Get-NetTCPConnection -State Listen)
        }

        Write-Verbose -Message "Creating HTML Base"
        $HTML = @()
        $HTML += @"
        <style>
        TABLE {border-width: 1px; border-style: solid; border-color: black; border-collapse: collapse;}
        TH {border-width: 1px; padding: 3px; border-style: solid; border-color: black; background-color: #6495ED;}
        TD {border-width: 1px; padding: 3px; border-style: solid; border-color: black;}
        </style>
"@
        Write-Verbose -Message "Adding appropriate HTML"
        $HTML += $Applications | Select-Object DisplayName, DisplayVersion, Publisher, InstallDate | ConvertTo-Html -PreContent "<h1>Applications</h1>"
        $HTML += $Services | Group-Object Status | Sort-Object Name | Foreach-Object {$_.Group | Select-Object Name, DisplayName, Status, StartType | ConvertTo-Html -PreContent "<h1>Services $($_.Name)</h1>"}
        $HTML += $IPAddressInformation | Sort-Object IPAddress | Select-Object IPAddress, InterfaceAlias | ConvertTo-Html -PreContent "<h1>IP Address Information</h1>"
        $HTML += $DiskInformation | Sort-Object Number | Select-Object FriendlyName, Number, OperationalStatus, @{Name="TotalSize";Expression={[math]::Round($_.Size/1gb)}}, PartitionStyle, UniqueID | ConvertTo-Html -PreContent "<h1>Disk Information</h1>"
        if ($ClusterComponents) {
            $HTML += $ClusterComponents | Select-Object Name, State, OwnerGroup, ResourceType | ConvertTo-Html -PreContent "<h1>Cluster Information</h1>"
        }
        if ($IISInformation) {
            $HTML += $IISInformation | Select-Object Name, ID, PhysicalPath, ApplicationPool, ServerAutoStart, State | ConvertTo-Html -PreContent "<h1>IIS Information</h1>"
        }
        $HTML += $Features | Group-Object InstallState | Sort-Object Name | ForEach-Object {$_.Group | Select-Object DisplayName, InstallState | ConvertTo-Html -PreContent "<h1>Features $($_.Name)</h1>"}
        $HTML += $ListeningPorts | Select-Object State, LocalAddress, LocalPort, RemoteAddress, RemotePort | ConvertTo-Html -PreContent "<h1>Listening Ports</h1>"
        $HTML | Set-Content -Path $Path"$(Get-Date -format "yyyy-MM-dd")-$ServerHostname.html"
    }
    
    end {
        
    }
}