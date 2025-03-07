<#
    Universal Profile Migrator Script
    Version: 1.0
    Author: Ryan
    Created: 2025-03-06
    Purpose: Migrate local or Entra user profiles, preserving key data.
    Features:
        - Robocopy-powered with resume support
        - Progress tracking
        - Automatic permission correction
        - Full logging
        - Disk space validation (with buffer)
        - Optional old profile removal
#>

# Requires admin privileges

# Start logging
$logPath = "C:\MigrationLogs\ProfileMigration_$(Get-Date -Format 'yyyy-MM-dd_HH-mm-ss').log"
New-Item -ItemType Directory -Path (Split-Path $logPath) -Force | Out-Null
Start-Transcript -Path $logPath -Append

try {
    Write-Host "`n--- Universal Profile Migrator v1.0 ---`n"

    # Get profiles in C:\Users
    $profiles = Get-ChildItem 'C:\Users' | Where-Object {
        $_.PSIsContainer -and
        $_.Name -notin @('Public', 'Default', 'Default User', 'All Users')
    }

    # List profiles
    Write-Host "`nAvailable User Profiles:`n"
    $profiles | ForEach-Object -Begin { $i = 1 } -Process {
        Write-Host "$i. $($_.Name)"
        $i++
    }

    # Select source (local) user
    $sourceIndex = Read-Host "`nEnter the number of the LOCAL user profile to copy from"
    $sourceProfile = $profiles[$sourceIndex - 1].FullName
    $sourceName = $profiles[$sourceIndex - 1].Name
    Write-Host "`nSelected Source User: $sourceName ($sourceProfile)`n"

    # Filter out the source user from the list
$destinationProfiles = $profiles | Where-Object { $_.Name -ne $sourceName }

# Display destination profiles excluding the source
Write-Host "`nAvailable Destination User Profiles:`n"
$destinationProfiles | ForEach-Object -Begin { $j = 1 } -Process {
    Write-Host "$j. $($_.Name)"
    $j++
}

# Select destination (Entra) user from the filtered list
$destinationIndex = Read-Host "`nEnter the number of the NEW user profile to copy to"
$destinationProfile = $destinationProfiles[$destinationIndex - 1].FullName
$destinationName = $destinationProfiles[$destinationIndex - 1].Name
Write-Host "`nSelected Destination User: $destinationName ($destinationProfile)`n"


    # Disk space check
    Write-Host "`nChecking disk space..."
    $sourceSizeBytes = (Get-ChildItem -Path $sourceProfile -Recurse -Force -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
    $sourceSizeGB = [math]::Round($sourceSizeBytes / 1GB, 2)
    $bufferGB = 20
    $requiredSpaceGB = $sourceSizeGB + $bufferGB
    $freeSpaceGB = [math]::Round((Get-PSDrive C).Free / 1GB, 2)

    Write-Host "Source profile size: $sourceSizeGB GB"
    Write-Host "Free space: $freeSpaceGB GB"
    Write-Host "Required space (with $bufferGB GB buffer): $requiredSpaceGB GB"

    if ($freeSpaceGB -lt $requiredSpaceGB) {
        Write-Host "Not enough disk space. Migration cancelled."
        Stop-Transcript
        exit
    } else {
        Write-Host "Disk space check passed."
    }

    # Confirm migration
    $confirm = Read-Host "`nReady to copy data from '$sourceName' to '$destinationName'. Proceed? (Y/N)"
    if ($confirm -notin @('Y', 'y')) {
        Write-Host "Migration cancelled."
        Stop-Transcript
        exit
    }

    $foldersToCopy = @('Desktop', 'Documents', 'Downloads', 'Pictures', 'Music', 'Videos', 'Favorites')
    $totalItems = $foldersToCopy.Count + 1  # +1 for AppData\Roaming
    $itemsCompleted = 0

    function Show-Progress($activity, $status, $percentComplete) {
        Write-Progress -Activity $activity -Status $status -PercentComplete $percentComplete
    }

    foreach ($folder in $foldersToCopy) {
    if ([string]::IsNullOrWhiteSpace($folder)) {
        continue
    }
    
    $itemsCompleted++
    $percentComplete = [math]::Round(($itemsCompleted / $totalItems) * 100)
    $status = "Copying $folder ($itemsCompleted of $totalItems)..."
    
    Show-Progress -Activity "Migrating profile data" -Status $status -PercentComplete $percentComplete
        $sourceFolder = Join-Path $sourceProfile $folder
        $destinationFolder = Join-Path $destinationProfile $folder

        if (Test-Path $sourceFolder) {
            Write-Host "`nCopying $folder with Robocopy..."
            $robocopyLog = "C:\MigrationLogs\Robocopy_$($folder)_$(Get-Date -Format 'yyyy-MM-dd_HH-mm-ss').log"
            robocopy $sourceFolder $destinationFolder /MIR /Z /MT:16 /R:2 /W:5 /LOG+:"$robocopyLog" | Out-Null

            # Apply permissions
            $acl = Get-Acl $destinationFolder
            $accessRule = New-Object System.Security.AccessControl.FileSystemAccessRule("$destinationName", "FullControl", "ContainerInherit, ObjectInherit", "None", "Allow")
            $acl.SetAccessRule($accessRule)
            Set-Acl $destinationFolder $acl
        } else {
            Write-Host "Skipping $folder (not found in source profile)."
        }
    }

    # Final progress update for AppData\Roaming
$status = "Copying AppData\Roaming (final step)"
Show-Progress -Activity "Migrating profile data" -Status $status -PercentComplete 100

$sourceAppData = Join-Path $sourceProfile "AppData\Roaming"
$destinationAppData = Join-Path $destinationProfile "AppData\Roaming"

if (Test-Path $sourceAppData) {
    Write-Host "`nCopying AppData\Roaming with Robocopy..."

    # Show progress for this specific step only
    Write-Progress -Activity "Migrating profile data" -Status "Copying AppData\Roaming..." -PercentComplete 100

    $robocopyLog = "C:\MigrationLogs\Robocopy_AppDataRoaming_$(Get-Date -Format 'yyyy-MM-dd_HH-mm-ss').log"
    robocopy $sourceAppData $destinationAppData /MIR /Z /MT:16 /R:2 /W:5 /LOG+:"$robocopyLog" | Out-Null

    # Apply permissions
    $acl = Get-Acl $destinationAppData
    $accessRule = New-Object System.Security.AccessControl.FileSystemAccessRule("$destinationName", "FullControl", "ContainerInherit, ObjectInherit", "None", "Allow")
    $acl.SetAccessRule($accessRule)
    Set-Acl $destinationAppData $acl

    # Complete the progress bar
    Write-Progress -Activity "Migrating profile data" -Completed
} else {
    Write-Host "No AppData\Roaming found in source profile."
}
# Clear progress bar
# Show-Progress -Activity "Migrating profile data" -Completed


    # Optional source profile deletion
    # $cleanupConfirm = Read-Host "`nDo you want to DELETE the old profile '$sourceProfile'? (Y/N)"
    # if ($cleanupConfirm -in @('Y', 'y')) {
    #    try {
    #        Remove-Item -Path $sourceProfile -Recurse -Force
    #        Write-Host "Old profile '$sourceProfile' deleted."
    #    }
    #    catch {
    #        Write-Host "Failed to delete old profile: $_"
    #    }
    #} else {
    #    Write-Host "Old profile retained."
    #}

    Write-Host "`n Migration complete! Full log saved to $logPath"
}
catch {
    Write-Host "`n An error occurred: $_"
}
finally {
    Stop-Transcript
}
