function Invoke-WinUtilUninstallPSProfile {
    <#
    .SYNOPSIS
        Restores the PowerShell 7 profile the CTT profile replaced

    .DESCRIPTION
        The profile path has to come from pwsh itself. $PROFILE inside this job is the worker's
        own Windows PowerShell profile, which is not the file the install wrote.
    #>

    $pwshPath = Get-WinUtilPowerShell7Path
    if (-not $pwshPath) {
        throw "未安装 PowerShell 7，因此没有可移除的 CTT 配置文件。"
    }

    $profilePath = (& $pwshPath -NoProfile -NonInteractive -Command '$PROFILE' | Select-Object -First 1)
    if ([string]::IsNullOrWhiteSpace($profilePath)) {
        throw "无法确定 PowerShell 7 的配置文件路径。"
    }
    $profilePath = $profilePath.Trim()
    $backupPath = "$profilePath.bak"

    if (Test-Path $backupPath) {
        Move-Item -Path $backupPath -Destination $profilePath -Force
        Write-WinUtilLog -Component "Feature" -Message "已还原此前的配置文件：$profilePath"
        return
    }

    if (Test-Path $profilePath) {
        Remove-Item -Path $profilePath -Force
        Write-WinUtilLog -Component "Feature" -Message "已移除 CTT PowerShell 配置文件：$profilePath"
        return
    }

    Write-WinUtilLog -Level "WARN" -Component "Feature" -Message "在 $profilePath 未找到 PowerShell 7 配置文件，无需移除。"
}
