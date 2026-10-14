function Invoke-WPFAppxInstall {
    if ($null -eq $sync.selectedAppx -or $sync.selectedAppx.Count -eq 0) {
        Show-WinUtilMessage -Message "未选择任何 AppX 应用" -Title "错误" -Button "OK" -Icon "Error"
        return
    }

    Start-WinUtilJob -Name "AppX 安装" -Description "正在安装 AppX 应用" -Parameters @{
        Selected = @($sync.selectedAppx)
        Apps = $sync.configs.appxHashtable
    } -ScriptBlock {
        param($Selected, $Apps)

        $totalPackages = @($Selected).Count
        $results = @()
        Write-WinUtilLog -Component "AppX" -Message "开始安装所选的 $totalPackages 个 AppX 应用。"

        for ($index = 0; $index -lt $totalPackages; $index++) {
            $app = $Apps[$Selected[$index]]
            $position = $index + 1

            Step-WinUtilJob -Status "正在安装 $($app.Content) ($position/$totalPackages)" -Percent ([int](($index / $totalPackages) * 100))
            Write-Host "正在安装 $($app.Content)"
            $appResults = @(Install-WinUtilAPPX -Name $app.PackageId -StoreId $app.StoreId)
            $results += $appResults
            $status = if (@($appResults | Where-Object Outcome -EQ "Failed").Count -gt 0) {
                "Failed"
            } elseif (@($appResults | Where-Object Outcome -EQ "Skipped").Count -gt 0) {
                "Skipped"
            } else {
                "Installed"
            }
            Step-WinUtilJob -Status "$status $($app.Content) ($position/$totalPackages)" -Percent ([int](($position / $totalPackages) * 100))
        }

        Complete-WinUtilPackageRun -Action "安装" -Results $results
    }
}
