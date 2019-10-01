Param ($Path)
#Gets SCSI controller objects
$SCSIControllers = Get-WmiObject -Class win32_SCSIController

$HTML = @()

foreach ($SCSIController in $SCSIControllers)
{
    #For each Adapter get the disk mappings
    #$SCSIController | FL *
    $HTML += $SCSIController | Select Name, Status, DriverName, Manufacturer | ConvertTo-Html -As Table -Fragment
    #Antecendent is the controller path in the mapping. the Dependnt is the drive.
    $SCSIControllerDevices = Get-WmiObject -Class win32_SCSIControllerDevice
    $SCSIControllerDevice = $SCSIControllerDevices | Where-Object {$_.Antecedent -eq $($SCSIController.Path)}
    #$SCSIControllerDevice
    $DiskDrives = @()
    Foreach($Dependent in $SCSIControllerDevice.Dependent)
    {
        #Get all the drives attached to the SCSIController and work through them
        $DiskDrives += Get-WmiObject -Class Win32_DiskDrive | Where-Object {$_.PNPDeviceID -eq $([regex]::Replace($Dependent.Split('"')[1],"\\{2}","`\"))}
        $HTML += ""
        $HTML += $DiskDrives[-1] | Select Model, Partitions, BytsePerSector, Size, Status | ConvertTo-Html -As Table -Fragment
        $Partitions = Get-WMIObject -Class Win32_DiskPartition -Filter "DeviceID like 'Disk #$($DiskDrives[-1].Index)%'"
        #Get Partitions on the drives
        Foreach($Partition in $Partitions)
        {
            #Get the partition and volume information for the partition
            $Relationship = Get-WmiObject -Class Win32_LogicalDiskToPartition | ?{$_.antecedent -like "*Disk #$($DiskDrives[-1].Index), Partition #$($Partition.Index)*"}
            $HTML += $Partition | Select Name, Index, BlockSize, Type | ConvertTo-Html -As Table -Fragment
            $Volume = [wmi]"$($Relationship.Dependent)"
            $HTML += $Volume | Select VolumeName, VolumeSerialNumber, Name, FileSystem, Description, Size | ConvertTo-Html -As Table -Fragment
        } 
    }


}

$HTML | Set-Content "$($Path)\SCSIReport.html"