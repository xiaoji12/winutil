function Get-WinUtilEnvironmentReport {
    <#
    .SYNOPSIS
        Collects the allowlisted data used by the WinUtil environment report.
    #>

    $reportWarnings = [System.Collections.Generic.List[string]]::new()

    $windows = [ordered]@{
        edition      = $null
        version      = $null
        buildNumber  = $null
        architecture = $null
    }
    $hardware = [ordered]@{
        cpuModel              = $null
        logicalProcessorCount = $null
        totalMemoryGB         = $null
    }

    try {
        $operatingSystem = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
        $windows.edition = $operatingSystem.Caption
        $windows.version = $operatingSystem.Version
        $windows.buildNumber = $operatingSystem.BuildNumber
        $windows.architecture = $operatingSystem.OSArchitecture

        if ($null -ne $operatingSystem.TotalVisibleMemorySize) {
            $hardware.totalMemoryGB = [math]::Round(([double]$operatingSystem.TotalVisibleMemorySize / 1MB), 2)
        }
    } catch {
        $message = "从 Win32_OperatingSystem 收集 Windows/内存信息失败：$($_.Exception.Message)"
        Write-WinUtilLog -Component "EnvironmentReport" -Level "WARN" -Message $message
        [void]$reportWarnings.Add($message)
    }

    try {
        $processors = @(Get-CimInstance -ClassName Win32_Processor -ErrorAction Stop)
        if ($processors.Count -gt 0) {
            $hardware.cpuModel = $processors[0].Name
            $hardware.logicalProcessorCount = [int](($processors | Measure-Object -Property NumberOfLogicalProcessors -Sum).Sum)
        }
    } catch {
        $message = "从 Win32_Processor 收集 CPU 信息失败：$($_.Exception.Message)"
        Write-WinUtilLog -Component "EnvironmentReport" -Level "WARN" -Message $message
        [void]$reportWarnings.Add($message)
    }

    $powershell = [ordered]@{
        edition         = $PSVersionTable.PSEdition
        version         = $PSVersionTable.PSVersion.ToString()
        executionPolicy = $null
    }

    try {
        $powershell.executionPolicy = (Get-ExecutionPolicy).ToString()
    } catch {
        $message = "读取 PowerShell 执行策略失败：$($_.Exception.Message)"
        Write-WinUtilLog -Component "EnvironmentReport" -Level "WARN" -Message $message
        [void]$reportWarnings.Add($message)
    }

    # Re-use built-in functionality
    $chocolatey = [ordered]@{ installed = $false; version = $null }
    try {
        $chocolatey.installed = (Test-WinUtilPackageManager -choco 6>$null) -eq "installed"
    } catch {
        $message = "检查 Chocolatey 可用性失败：$($_.Exception.Message)"
        Write-WinUtilLog -Component "EnvironmentReport" -Level "WARN" -Message $message
        [void]$reportWarnings.Add($message)
    }

    if ($chocolatey.installed) {
        try {
            $global:LASTEXITCODE = 0
            $versionOutput = @(choco -v 2>&1)
            if ($LASTEXITCODE -ne 0) {
                throw "Chocolatey 版本探测退出，代码为 $LASTEXITCODE。"
            }
            $chocolatey.version = ($versionOutput | Select-Object -First 1).ToString().Trim()
        } catch {
            $message = "读取 Chocolatey 版本失败：$($_.Exception.Message)"
            Write-WinUtilLog -Component "EnvironmentReport" -Level "WARN" -Message $message
            [void]$reportWarnings.Add($message)
        }
    }

    $winget = [ordered]@{ installed = $false; version = $null }
    try {
        $winget.installed = (Test-WinUtilPackageManager -winget 6>$null) -eq "installed"
    } catch {
        $message = "检查 WinGet 可用性失败：$($_.Exception.Message)"
        Write-WinUtilLog -Component "EnvironmentReport" -Level "WARN" -Message $message
        [void]$reportWarnings.Add($message)
    }

    if ($winget.installed) {
        try {
            $global:LASTEXITCODE = 0
            $versionOutput = @(winget -v 2>&1)
            if ($LASTEXITCODE -ne 0) {
                throw "WinGet 版本探测退出，代码为 $LASTEXITCODE。"
            }
            $winget.version = ($versionOutput | Select-Object -First 1).ToString().Trim()
        } catch {
            $message = "Failed to read WinGet version: $($_.Exception.Message)"
            Write-WinUtilLog -Component "EnvironmentReport" -Level "WARN" -Message $message
            [void]$reportWarnings.Add($message)
        }
    }

    # Null means the registry state could not be read. Do not turn an access/provider failure into
    # a misleading "no reboot required" result.
    $system = [ordered]@{ pendingRebootRequired = $null }
    try {
        $rebootPaths = @(
            "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending",
            "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired"
        )

        # A present-but-empty PendingFileRenameOperations value still returns a non-null object, so
        # check the actual entries rather than just whether the property exists.
        $pendingFileRenameOperations = @(
            (Get-ItemProperty -LiteralPath "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager" `
                -ErrorAction Stop).PendingFileRenameOperations |
                Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }
        )
        $system.pendingRebootRequired = ($rebootPaths | Where-Object {
            Test-Path -LiteralPath $_ -ErrorAction Stop
        }).Count -gt 0 -or
            $pendingFileRenameOperations.Count -gt 0
    } catch {
        $message = "Failed to check pending-reboot registry state: $($_.Exception.Message)"
        Write-WinUtilLog -Component "EnvironmentReport" -Level "WARN" -Message $message
        [void]$reportWarnings.Add($message)
    }

    $tweaksState = Get-WinUtilTweaksStateReport
    if ($tweaksState.collectionStatus -ne "collected") {
        $message = "Failed to collect the complete tweak state for the environment report."
        Write-WinUtilLog -Component "EnvironmentReport" -Level "WARN" -Message $message
        [void]$reportWarnings.Add($message)
    }

    foreach ($message in $reportWarnings) {
        Write-Warning $message
    }

    return [pscustomobject][ordered]@{
        schemaVersion    = "1.0"
        generatedAtUtc   = [DateTime]::UtcNow.ToString("o")
        windows          = [pscustomobject]$windows
        hardware         = [pscustomobject]$hardware
        powershell       = [pscustomobject]$powershell
        packageManagers  = [pscustomobject][ordered]@{
            winget     = [pscustomobject]$winget
            chocolatey = [pscustomobject]$chocolatey
        }
        system           = [pscustomobject]$system
        tweaksState      = $tweaksState
    }
}
