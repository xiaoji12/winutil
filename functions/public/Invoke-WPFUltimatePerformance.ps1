function Invoke-WPFUltimatePerformance ([switch]$Enable) {
    <#

    .SYNOPSIS
        Adds or removes the Ultimate Performance power plan

    #>

    if ($Enable) {
        Step-WinUtilJob -Status "正在添加 Ultimate Performance 电源计划" -State "Indeterminate"
        Write-WinUtilLog -Component "Power" -Message "正在复制并启用 Ultimate Performance 电源计划。"

        $duplicated = powercfg /duplicatescheme e9a42b02-d5df-448d-aa00-03f14749eb61
        if ($LASTEXITCODE -ne 0) {
            throw "powercfg 无法复制 Ultimate Performance 电源方案（退出代码 $LASTEXITCODE）。"
        }

        $guid = ($duplicated | Select-String -Pattern '[A-Fa-f0-9-]{36}').Matches.Value
        if (-not $guid) {
            throw "powercfg 未返回要启用的电源方案 GUID。"
        }

        powercfg /setactive $guid
        if ($LASTEXITCODE -ne 0) {
            throw "powercfg 无法启用 Ultimate Performance 电源方案（退出代码 $LASTEXITCODE）。"
        }

        Write-WinUtilLog -Component "Power" -Message "Ultimate Performance 电源计划已安装并启用。"
    } else {
        Step-WinUtilJob -Status "正在还原默认电源计划" -State "Indeterminate"
        Write-WinUtilLog -Component "Power" -Message "正在还原默认电源方案。"

        powercfg /restoredefaultschemes
        if ($LASTEXITCODE -ne 0) {
            throw "powercfg 无法还原默认电源方案（退出代码 $LASTEXITCODE）。"
        }

        Write-WinUtilLog -Component "Power" -Message "电源计划已重置为默认值。"
    }
}
