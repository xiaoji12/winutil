function Invoke-WPFInstall {
    <#
    .SYNOPSIS
        Installs the selected programs using winget, if one or more of the selected programs are already installed on the system, winget will try and perform an upgrade if there's a newer version to install.
    #>
    param(
        [Parameter(Mandatory = $false)]
        [PSObject[]]$PackagesToInstall = $($sync.selectedApps | Foreach-Object { $sync.configs.applicationsHashtable.$_ })
    )

    if ($PackagesToInstall.Count -eq 0) {
        $WarningMsg = "请选择要安装或升级的程序。"
        Show-WinUtilMessage -Message $WarningMsg -Title "WinUtil" -Button "OK" -Icon "Warning"
        return
    }

    $ManagerPreference = $sync.preferences.packagemanager
    Write-WinUtilLog -Component "Install" -Message "已请求使用 $ManagerPreference 安装所选的 $(@($PackagesToInstall).Count) 个软件包"
    $packageSummary = Get-WinUtilPackageLogSummary -Packages $PackagesToInstall -Preference $ManagerPreference
    Write-WinUtilLog -Component "Install" -Message "已选择要安装的软件包：$($packageSummary -join '; ')"

    Start-WinUtilJob -Name "安装" -Description "正在安装应用" -DisableAppList -Parameters @{
        PackagesToInstall = $PackagesToInstall
        ManagerPreference = $ManagerPreference
    } -ScriptBlock {
        param($PackagesToInstall, $ManagerPreference)

        $packagesSorted = Get-WinUtilSelectedPackages -PackageList $PackagesToInstall -Preference $ManagerPreference
        $packagesWinget = $packagesSorted['Winget']
        $packagesChoco = $packagesSorted['Choco']
        $totalPackages = @($packagesWinget).Count + @($packagesChoco).Count
        $completedPackages = 0
        Write-WinUtilLog -Component "Install" -Message "软件包管理器分布：winget=$(@($packagesWinget).Count)，choco=$(@($packagesChoco).Count)"

        $results = @()

        if ($packagesWinget.Count -gt 0 -and $packagesWinget -ne "0") {
            Install-WinUtilWinget
            foreach ($program in $packagesWinget) {
                $position = $completedPackages + 1
                Step-WinUtilJob -Status "正在安装 $program ($position/$totalPackages)" -Percent ([int](($completedPackages / $totalPackages) * 100))

                $results += Measure-WinUtilStep -Scope "Install" -Name "winget $program" -ScriptBlock {
                    Install-WinUtilProgramWinget -Action Install -Programs @($program)
                }
                $completedPackages++
                Step-WinUtilJob -Status "已安装 $program ($completedPackages/$totalPackages)" -Percent ([int](($completedPackages / $totalPackages) * 100))
            }
        }

        if ($packagesChoco.Count -gt 0) {
            $position = $completedPackages + 1
            Step-WinUtilJob -Status "正在安装 Chocolatey 软件包 ($position/$totalPackages)" -Percent ([int](($completedPackages / $totalPackages) * 100))

            Install-WinUtilChoco
            $chocoBase = [int](($completedPackages / $totalPackages) * 100)
            $chocoSpan = [int]((@($packagesChoco).Count / $totalPackages) * 100)
            $results += Measure-WinUtilStep -Scope "Install" -Name "choco $($packagesChoco -join ', ')" -ScriptBlock {
                Install-WinUtilProgramChoco -Action Install -Programs $packagesChoco -ProgressBase $chocoBase -ProgressSpan $chocoSpan
            }
            $completedPackages += @($packagesChoco).Count
            Step-WinUtilJob -Status "已安装 Chocolatey 软件包 ($completedPackages/$totalPackages)" -Percent ([int](($completedPackages / $totalPackages) * 100))
        }

        Complete-WinUtilPackageRun -Action "安装" -Results $results
    }
}
