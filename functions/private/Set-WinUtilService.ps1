Function Set-WinUtilService {
    <#

    .SYNOPSIS
        Changes the startup type of the given service

    .PARAMETER Name
        The name of the service to modify

    .PARAMETER StartupType
        The startup type to set the service to

    .EXAMPLE
        Set-WinUtilService -Name "HomeGroupListener" -StartupType "Manual"

    #>
    param (
        $Name,
        $StartupType
    )
    try {
        Write-Host "正在将服务 $Name 设置为 $StartupType"
        Write-WinUtilLog -Component "Service" -Message "正在将服务 $Name 的启动类型设置为 $StartupType"

        # Check if the service exists
        $service = Get-Service -Name $Name -ErrorAction Stop

        if (($service.PSObject.Properties.Name -contains "StartType") -and ([string]$service.StartType -eq [string]$StartupType) ) {
            Write-Host "服务 $Name 已设置为 $StartupType"
            Write-WinUtilLog -Component "Service" -Message "服务 $Name 的启动类型已是 $StartupType，无需更改。"
            return
        }

        # Service exists, proceed with changing properties -- while handling auto delayed start for PWSH 5
        if (($PSVersionTable.PSVersion.Major -lt 7) -and ($StartupType -eq "AutomaticDelayedStart")) {
            sc.exe config $Name start= delayed-auto
            if ($LASTEXITCODE -ne 0) {
                throw "sc.exe config 失败，退出代码 $LASTEXITCODE"
            }
        } else {
            $service | Set-Service -StartupType $StartupType -ErrorAction Stop
        }
        Write-WinUtilLog -Component "Service" -Message "服务 $Name 的启动类型已设置为 $StartupType"
    } catch {
        if ($_.FullyQualifiedErrorId -like "NoServiceFoundForGivenName,*") {
            Write-Warning "未找到服务 $Name。"
            Write-WinUtilLog -Level "WARN" -Component "Service" -Message "未找到服务 $Name。"
        } else {
            Write-Warning "由于未处理的异常，无法设置 $Name。"
            Write-Warning $_.Exception.Message
            Write-WinUtilLog -Level "ERROR" -Component "Service" -Message "无法将服务 $Name 设置为 $StartupType：`$($_.Exception.Message)"
        }
    }

}
