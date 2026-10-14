function Invoke-WPFUpdatesdefault {
    <#

    .SYNOPSIS
        Resets Windows Update settings to default

    #>
    Write-WinUtilLog -Component "Updates" -Message "正在将 Windows 更新设置重置为默认值。"

    Write-Host "正在移除由 WinUtil 管理的 Windows 更新设置..." -ForegroundColor Green
    Write-WinUtilLog -Component "Updates" -Message "正在移除由 WinUtil 管理的 Windows 更新注册表值。"

    $registryValues = @(
        @{
            Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU"
            Names = @("NoAutoUpdate", "AUOptions", "NoAutoRebootWithLoggedOnUsers", "AUPowerManagement")
        },
        @{
            Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate"
            Names = @("ExcludeWUDriversInQualityUpdate", "DeferFeatureUpdates", "DeferFeatureUpdatesPeriodInDays", "DeferQualityUpdates", "DeferQualityUpdatesPeriodInDays")
        },
        @{
            Path = "HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings"
            Names = @("BranchReadinessLevel", "DeferFeatureUpdatesPeriodInDays", "DeferQualityUpdatesPeriodInDays")
        },
        @{
            Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Device Metadata"
            Names = @("PreventDeviceMetadataFromNetwork")
        },
        @{
            Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DriverSearching"
            Names = @("DontPromptForWindowsUpdate", "DontSearchWindowsUpdate", "DriverUpdateWizardWuSearchEnabled")
        },
        @{
            Path = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\DeliveryOptimization\Config"
            Names = @("DODownloadMode")
        }
    )

    foreach ($registryEntry in $registryValues) {
        foreach ($valueName in $registryEntry.Names) {
            Remove-ItemProperty -Path $registryEntry.Path -Name $valueName -ErrorAction SilentlyContinue
        }
    }

    $explorerPolicyPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer"
    $settingsPageVisibility = (Get-ItemProperty -Path $explorerPolicyPath -Name "SettingsPageVisibility" -ErrorAction SilentlyContinue).SettingsPageVisibility
    if ($settingsPageVisibility -eq "hide:windowsupdate") {
        Write-Host "正在移除 WinUtil 旧版的 Windows 更新页面限制..."
        Write-WinUtilLog -Component "Updates" -Message "正在移除旧版的 Windows 更新设置页面限制。"
        Remove-ItemProperty -Path $explorerPolicyPath -Name "SettingsPageVisibility" -ErrorAction SilentlyContinue
    }

    Write-Host "正在重新启用 Windows 更新服务..." -ForegroundColor Green
    Write-WinUtilLog -Component "Updates" -Message "正在还原 Windows 更新服务的启动类型。"

    Write-Host "已将 BITS 还原为手动。"
    Write-WinUtilLog -Component "Updates" -Message "正在将 BITS 服务还原为手动。"
    Set-Service -Name BITS -StartupType Manual

    Write-Host "已将 wuauserv 还原为手动。"
    Write-WinUtilLog -Component "Updates" -Message "正在将 wuauserv 服务还原为手动。"
    Set-Service -Name wuauserv -StartupType Manual

    Write-Host "已将 UsoSvc 还原为自动。"
    Write-WinUtilLog -Component "Updates" -Message "正在启动 UsoSvc 服务，并将启动类型还原为自动。"
    Set-Service -Name UsoSvc -StartupType Automatic
    Start-Service -Name UsoSvc

    Write-Host "正在启用与更新相关的计划任务..." -ForegroundColor Green
    Write-WinUtilLog -Component "Updates" -Message "正在启用与更新相关的计划任务。"

    $Tasks =
        '\Microsoft\Windows\InstallService\*',
        '\Microsoft\Windows\UpdateOrchestrator\*',
        '\Microsoft\Windows\UpdateAssistant\*',
        '\Microsoft\Windows\WaaSMedic\*',
        '\Microsoft\Windows\WindowsUpdate\*',
        '\Microsoft\WindowsUpdate\*'

    foreach ($Task in $Tasks) {
        Get-ScheduledTask -TaskPath $Task -ErrorAction SilentlyContinue | Enable-ScheduledTask -ErrorAction SilentlyContinue
    }


    Write-Host "注意：必须重启系统，所有更改才能生效。" -ForegroundColor Yellow
    Write-WinUtilLog -Component "Updates" -Message "Windows 更新默认流程已完成，需要重启。"
}
