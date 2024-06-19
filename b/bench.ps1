if ($null -ne $PSPrincipal -And $PSPrincipal.IsInRole("Administrator")) {
    $isAdmin = $true
}
else {
    $isAdmin = $false
}

if ($PSVersionTable.PSVersion.Major -ge 3) {
    Set-Alias -Name wmi -Value Get-CimInstance
}
else {
    Set-Alias -Name wmi -Value Get-WmiObject
}

$processorInfo = wmi -ClassName Win32_Processor
$computerSystem = wmi -ClassName Win32_ComputerSystem
$operatingSystem = wmi -ClassName Win32_OperatingSystem
$global:tempDir = ""

function Write-RedRow($title, $message) { Write-Host " $($title.PadRight(18)) : " -NoNewline; Write-Host $message -ForegroundColor Red }

function Write-BlueRow($title, $message) { Write-Host " $($title.PadRight(18)) : " -NoNewline; Write-Host $message -ForegroundColor Blue }

function Write-GreenRow($title, $message) { Write-Host " $($title.PadRight(18)) : " -NoNewline; Write-Host $message -ForegroundColor Green }

function Write-YellowRow($title, $message) { Write-Host " $($title.PadRight(18)) : " -NoNewline; Write-Host $message -ForegroundColor Yellow }

function Write-Boolean($title, $boolean) { if ($boolean) { Write-BlueRow $title "✓ Enabled" } else { Write-RedRow $title "✗ Disabled" } }

function Write-DiskMem($title, $total, $used) {
    Write-Host " $($title.PadRight(18)) : " -NoNewline
    Write-Host $total -ForegroundColor Yellow -NoNewline
    Write-Host " ($used Used)" -ForegroundColor Blue 
}

function Write-IpCheck($title, $ipv4, $ipv6) {
    Write-Host " $($title.PadRight(18)) : " -NoNewline
    if ($ipv4 -eq $true) { 
        Write-Host "✓ Online" -ForegroundColor Green -NoNewline 
    }
    else {
        Write-Host "✗ Offline" -ForegroundColor Red -NoNewline
    }
    Write-Host " / " -NoNewline
    if ($ipv6) { 
        Write-Host "✓ Online" -ForegroundColor Green 
    }
    else {
        Write-Host "✗ Offline" -ForegroundColor Red
    }
}

function Write-SpeedTest($nodeName, $upload, $download, $latency) {
    Write-Host " $($nodeName.PadRight(17))" -ForegroundColor Yellow -NoNewline
    Write-Host $upload.PadRight(18) -ForegroundColor Green -NoNewline
    Write-Host $download.PadRight(20) -ForegroundColor Red -NoNewline
    Write-Host $latency -ForegroundColor Blue
}

function Get-VirtualizationTechnology {
    $virtualizationTechnology = $computerSystem.VirtualizationFabric
    if ($virtualizationTechnology -eq "Microsoft") {
        return "Hyper-V"
    }
    elseif ($virtualizationTechnology -eq "VMware") {
        return "VMware"
    }
    elseif ($virtualizationTechnology -eq "KVM") {
        return "KVM"
    }
    else {
        return "Dedicated"
    }
}

function Get-VirtualizationSupport {
    if ($computerSystem | Get-Member -Name "VirtualizationExtensions") {
        $vmx = $computerSystem | Select-Object -ExpandProperty VirtualizationExtensions
        return $vmx -like "*VMX*" -or $vmx -like "*AMD-V*"
    }
    else {
        return $false
    }
}

function Get-AesSupport {
    $aesSupport = $processorInfo.ProcessorSignature -band 0x20000000
    if ($aesSupport -eq 0x20000000) {
        return $true
    }
    else {
        return $false
    }
}

function Get-TotalDiskSize {
    $driveLetter = $operatingSystem.SystemDrive
    $disk = wmi -Class Win32_LogicalDisk -Filter "DeviceID='$driveLetter'"
    $diskSize = $disk.Size
    $diskSizeGB = [math]::Round($diskSize / 1GB, 2)
    $diskFreeSpace = $disk.FreeSpace
    $diskFreeSpaceGB = [math]::Round($diskFreeSpace / 1GB, 2)
    $diskUsedSpaceGB = [math]::Round($diskSizeGB - $diskFreeSpaceGB, 2)
    return $("$driveLetter $diskSizeGB GB", "$diskUsedSpaceGB GB")
}

function Get-TotalMemory {
    $totalMemory = $computerSystem.TotalPhysicalMemory
    $totalMemoryGB = [math]::Round($totalMemory / 1GB, 2)
    $freeMemory = $operatingSystem.FreePhysicalMemory
    $freeMemoryGB = [math]::Round($freeMemory / 1MB, 2)
    $usedMemoryGB = [math]::Round($totalMemoryGB - $freeMemoryGB, 2)
    return $("$totalMemoryGB GB", "$usedMemoryGB GB")
}

function Get-SystemUptime {
    $uptime = $operatingSystem.LastBootUpTime
    $currentTime = Get-Date
    $uptimeInSeconds = ($currentTime - $uptime).TotalSeconds
    
    $days = [Math]::Floor($uptimeInSeconds / 86400)
    $hours = [Math]::Floor(($uptimeInSeconds % 86400) / 3600)
    $minutes = [Math]::Floor((($uptimeInSeconds % 86400) % 3600) / 60)
    
    if ($days -gt 0) {
        return "$days days, $hours hour $minutes min"
    }
    else {
        return "$hours hour $minutes min"
    }
}

function Get-LoadAverage {
    $loadAverage = $processorInfo.LoadPercentage
    return "$loadAverage%"
}

function Get-Architecture {
    $architecture = $processorInfo.AddressWidth
    if ($architecture -eq "64") {
        return "x86_64 (64 Bit)"
    }
    else {
        return "x86 (32 Bit)"
    }
}

function Get-Kernel {
    $kernelVersion = $operatingSystem.Version
    return $kernelVersion
}

function Get-TcpSettings {
    $tcpSettings = Get-NetTCPSetting
    if ($isAdmin) {
        return $tcpSettings | Format-Table -Property CongestionProvider
    }
    else {
        return "N/A"
    }
}

function IpCheck {
    ping -n 1 ipv4.google.com >nul 2>nul
    $ipv4_check = $LASTEXITCODE -eq 0
    ping -n 1 ipv6.google.com >nul 2>nul
    $ipv6_check = $LASTEXITCODE -eq 0
    if ($ipv4_check -eq $false -and $ipv6_check -eq $false) {
        Write-Host "Warning: Both IPv4 and IPv6 connectivity were not detected." -ForegroundColor Yellow
    }
    return $($ipv4_check, $ipv6_check)
}

function IoTest($filePath, $totalSize, $chunkSize) {
    $time = Measure-Command {
        $fileStream = [System.IO.File]::Create($filePath)
        try {
            for ($offset = 0; $offset -lt $totalSize; $offset += $chunkSize) {
                $content = [System.Text.Encoding]::ASCII.GetBytes("A" * $chunkSize)
                $fileStream.Write($content, 0, $content.Length)
            }
        }
        finally {
            $fileStream.Dispose()
        }
    }
    Remove-Item -Path $filePath
    $speed = $totalSize / $time.TotalSeconds
    return [math]::Round($speed / 1MB, 2)
}

function InstallSpeedTest() {
    $url = "https://install.speedtest.net/app/cli/ookla-speedtest-1.2.0-win64.zip"
    $speedtestDir = "$global:tempDir\speedtest-cli"
    $speedtestZip = "$speedtestDir\speedtest.zip"
    $speedtestExe = "$speedtestDir\speedtest.exe"
    if (-not (Test-Path -Path $speedtestDir)) {
        New-Item -ItemType Directory -Path $speedtestDir | Out-Null
    }
    if (-not (Test-Path -Path $speedtestExe)) {
        try {
            Invoke-WebRequest -Uri $url -OutFile $speedtestZip -SkipCertificateCheck
            Expand-Archive -Path $speedtestZip -DestinationPath $speedtestDir
            Remove-Item -Path $speedtestZip
        }
        catch {
            Write-Host "Error: Failed to download speedtest-cli." -ForegroundColor Red
        }    
    }
}

function UninstallSpeedTest() {
    $speedtestDir = "$global:tempDir\speedtest-cli"
    Remove-Item -Path $speedtestDir -Recurse
}

function GetStringFromFile($filePath, $pattern) {
    try {
        $fileContent = Get-Content -Path $filePath -Raw
        $patternMatches = [regex]::Matches($fileContent, $pattern)
        if ($patternMatches.Count -gt 0) {
            $concatenatedGroups = ""
            $match = $patternMatches[0]
            $groupCount = $match.Groups.Count
            for ($i = 1; $i -lt $groupCount; $i++) {
                $groupValue = $match.Groups[$i].Value
                $concatenatedGroups += $groupValue + " "
            }
            return $concatenatedGroups.Trim()
        }
        else {
            return $null
        }
    }
    catch {
        return $null
    }
}

function SpeedTest($serverId, $nodeName) {
    $speedtestExe = "$global:tempDir\speedtest-cli\speedtest.exe"
    $speedtestLog = "$global:tempDir\speedtest-cli\speedtest.log"
    $speedtestErr = "$global:tempDir\speedtest-cli\speedtest.err"
    if ($serverId) {
        Start-Process -FilePath $speedtestExe -NoNewWindow -ArgumentList "--server-id=$serverId", "--progress=no", "--accept-license", "--accept-gdpr" -Wait -RedirectStandardOutput $speedtestLog -RedirectStandardError $speedtestErr
    }
    else {
        Start-Process -FilePath $speedtestExe -NoNewWindow -ArgumentList "--progress=no", "--accept-license", "--accept-gdpr" -Wait -RedirectStandardOutput $speedtestLog -RedirectStandardError $speedtestErr
    }
    $downloadSpeed = GetStringFromFile $speedtestLog "Download:\s+([\d.]+).+?(\w+)"
    $uploadSpeed = GetStringFromFile $speedtestLog "Upload:\s+([\d.]+).+?(\w+)"
    $latency = GetStringFromFile $speedtestLog "Latency:\s+([\d.]+).+?(\w+)"
    if ($downloadSpeed -and $uploadSpeed -and $latency) {
        Write-SpeedTest $nodeName $uploadSpeed $downloadSpeed $latency
    }
    Remove-Item -Path $speedtestLog
    Remove-Item -Path $speedtestErr
}

function SpeedTestAll() {
    SpeedTest "" "Speedtest.net"
    SpeedTest "21541" "Los Angeles, US"
    SpeedTest "43860" "Dallas, US"
    SpeedTest "40879" "Montreal, CA"
    SpeedTest "24215" "Paris, FR"
    SpeedTest "28922" "Amsterdam, NL"
    SpeedTest "24447" "Shanghai, CN"
    SpeedTest "5530" "Chongqing, CN"
    SpeedTest "60572" "Guangzhou, CN"
    SpeedTest "32155" "Hongkong, CN"
    SpeedTest "23647" "Mumbai, IN"
    SpeedTest "13623" "Singapore, SG"
    SpeedTest "21569" "Tokyo, JP"
}

function MakeTempDir() {
    $userProfile = $env:USERPROFILE
    $date = Get-Date -Format 'yyyyMMdd'
    $global:tempDir = "$userProfile\bench$date"
    if (-not (Test-Path -Path $global:tempDir)) {
        New-Item -ItemType Directory -Path $global:tempDir | Out-Null
    }
}

function ClearTempDir() {
    Remove-Item -Path $global:tempDir -Recurse
}

function PrintSeparator() { $line = ( -join (1..70 | ForEach-Object { "-" })); Write-Host $line }

function PrintIntro() {
    $intro = "A Bench.ps1 Script By BanHammer"
    $version = "v2024-06-20"
    $usage = "irm banhammerykt.github.io/b/bench.ps1 | iex"
    $lineLength = [Math]::Round((70 - $intro.Length) / 2, 0) - 1
    $line = ( -join (1..$lineLength | ForEach-Object { "-" })); Write-Host $line -NoNewline
    Write-Host " $intro " -NoNewline
    $lineLength = 70 - $intro.Length - $lineLength - 2
    $line = ( -join (1..$lineLength | ForEach-Object { "-" })); Write-Host $line
    Write-GreenRow "Version" $version
    Write-RedRow "Usage" $usage
}

function PrintSystemInfo() {
    $cpuName = $processorInfo.Name
    $cpuModel = ($cpuName -split '@')[0].Trim()
    $cpuCores = $processorInfo.NumberOfCores.ToString() + " @ " + ($cpuName -split '@')[1].Trim()
    $cacheSize = ($processorInfo.L2CacheSize / $processorInfo.NumberOfCores).ToString() + " KB"
    $aesSupport = Get-AesSupport
    $virtualizationTechnology = Get-VirtualizationTechnology
    $virtualizationSupport = Get-VirtualizationSupport
    $totalDiskSize = Get-TotalDiskSize
    $totalMemoryGB = Get-TotalMemory
    $uptime = Get-SystemUptime
    $loadAverage = Get-LoadAverage
    $architecture = Get-Architecture
    $kernel = Get-Kernel
    $tcpSettings = Get-TcpSettings
    $ipCheck = IpCheck
    Write-BlueRow "CPU Model" $cpuModel
    Write-BlueRow "CPU Cores" $cpuCores
    Write-BlueRow "CPU Cache" $cacheSize
    Write-Boolean "AES-NI" $aesSupport
    Write-Boolean "VM-x/AMD-V" $virtualizationSupport
    Write-DiskMem "Total Disk" $totalDiskSize[0] $totalDiskSize[1]
    Write-DiskMem "Total Mem" $totalMemoryGB[0] $totalMemoryGB[1]
    Write-BlueRow "System uptime" $uptime
    Write-BlueRow "Load average" $loadAverage
    Write-BlueRow "OS" $operatingSystem.Caption
    Write-BlueRow "Arch" $architecture
    Write-BlueRow "Kernel" $kernel
    Write-YellowRow "TCP CC" $tcpSettings
    Write-BlueRow "Virtualization" $virtualizationTechnology
    Write-IpCheck "IPv4/IPv6" $ipCheck[0] $ipCheck[1]
}

function PrintIpInfo() {
    $org = (Invoke-WebRequest -Uri "https://ipinfo.io/org").Content.Trim()
    $city = (Invoke-WebRequest -Uri "https://ipinfo.io/city").Content.Trim()
    $country = (Invoke-WebRequest -Uri "https://ipinfo.io/country").Content.Trim()
    $region = (Invoke-WebRequest -Uri "https://ipinfo.io/region").Content.Trim()
    if ($org) { Write-BlueRow "Organization" $org }
    if ($city -and $country) { Write-BlueRow "Location" "$city / $country" }
    if ($region) { Write-YellowRow "Region" $region }
}

function PrintIoTest() {
    $writemb = 2GB
    $testFile = "$global:tempDir\benchtest.tmp"
    $driveLetter = $testFile.Substring(0, 2)
    $disk = wmi -Class Win32_LogicalDisk -Filter "DeviceID='$driveLetter'"
    $diskFreeSpace = $disk.FreeSpace
    if ($diskFreeSpace -lt $writemb) {
        Write-Host "Not enough space for I/O Speed test!" -ForegroundColor Red
    }
    else {
        $io1 = IoTest $testFile $writemb 512MB
        Write-YellowRow "I/O Speed(1st run)" "$io1 MB/s"
        $io2 = IoTest $testFile $writemb 512MB
        Write-YellowRow "I/O Speed(2nd run)" "$io2 MB/s"
        $io3 = IoTest $testFile $writemb 512MB
        Write-YellowRow "I/O Speed(3rd run)" "$io3 MB/s"
        $ioAverage = [math]::Round(($io1 + $io2 + $io3) / 3, 2)
        Write-YellowRow "I/O Speed(average)" "$ioAverage MB/s"
    }
}

function PrintSpeedTest() {
    InstallSpeedTest
    Write-Host " Node Name".PadRight(17) "Upload Speed".PadRight(17) "Download Speed".PadRight(19) "Latency"
    SpeedTestAll
    UninstallSpeedTest
}

MakeTempDir
PrintIntro
PrintSeparator
PrintSystemInfo
PrintIpInfo
PrintSeparator
PrintIoTest
PrintSeparator
PrintSpeedTest
PrintSeparator
ClearTempDir
