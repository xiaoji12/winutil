function Invoke-WPFUpdatesdisable {
    <#

    .SYNOPSIS
        Disables Windows Update

    .NOTES
        Disabling Windows Update is not recommended. This is only for advanced users who know what they are doing.

    #>
    param([switch]$Confirmed)

    if (-not $Confirmed -and -not (Confirm-WPFUpdatesdisable)) {
        return
    }

    Write-WinUtilLog -Component "Updates" -Message "正在禁用 Windows 更新设置。"

    Write-Host "正在配置注册表设置..." -ForegroundColor Yellow
    Write-WinUtilLog -Component "Updates" -Message "正在配置用于禁用模式的 Windows 更新注册表策略值。"
    New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" -Force

    Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" -Name "NoAutoUpdate" -Type DWord -Value 1
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" -Name "AUOptions" -Type DWord -Value 1

    New-Item -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\DeliveryOptimization\Config" -Force
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\DeliveryOptimization\Config" -Name "DODownloadMode" -Type DWord -Value 0

    foreach ($serviceName in @("BITS", "wuauserv", "UsoSvc")) {
        Write-Host "正在停止并禁用 $serviceName 服务。"
        Write-WinUtilLog -Component "Updates" -Message "正在停止并禁用 $serviceName 服务。"
        Stop-Service -Name $serviceName -Force -ErrorAction SilentlyContinue
        Set-Service -Name $serviceName -StartupType Disabled
    }

    Remove-Item -Path "C:\Windows\SoftwareDistribution\*" -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host "已清空 SoftwareDistribution 文件夹。"
    Write-WinUtilLog -Component "Updates" -Message "已清空 SoftwareDistribution 文件夹。"

    Write-Host "正在禁用与更新相关的计划任务..." -ForegroundColor Yellow
    Write-WinUtilLog -Component "Updates" -Message "正在禁用与更新相关的计划任务。"

    $Tasks =
        '\Microsoft\Windows\InstallService\*',
        '\Microsoft\Windows\UpdateOrchestrator\*',
        '\Microsoft\Windows\UpdateAssistant\*',
        '\Microsoft\Windows\WaaSMedic\*',
        '\Microsoft\Windows\WindowsUpdate\*',
        '\Microsoft\WindowsUpdate\*'

    foreach ($Task in $Tasks) {
        Get-ScheduledTask -TaskPath $Task -ErrorAction SilentlyContinue | Disable-ScheduledTask -ErrorAction SilentlyContinue
    }


    Write-Host "注意：必须重启系统，所有更改才能生效。" -ForegroundColor Yellow
    Write-WinUtilLog -Component "Updates" -Message "Windows 更新禁用流程已完成，需要重启。"
}

function Confirm-WPFUpdatesdisable {
    $confirmation = Show-WinUtilMessage `
        -Message "禁用 Windows 更新会停止更新服务、禁用计划任务并清除已下载的更新文件。在恢复默认设置之前，安全更新将不会被安装。是否继续？" `
        -Title "禁用 Windows 更新？" `
        -Button "YesNo" `
        -Icon "Warning"

    if ($confirmation -ne "Yes") {
        Write-WinUtilLog -Component "Updates" -Message "已取消 Windows 更新禁用流程。"
        return $false
    }
    return $true
}
