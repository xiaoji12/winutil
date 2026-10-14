function Invoke-WinUtilFeatureInstall ($CheckBox) {
    Write-WinUtilLog -Component "Feature" -Message "正在应用功能操作：$CheckBox"

    if ($sync.configs.feature.$CheckBox.feature) {
        foreach ($feature in $sync.configs.feature.$CheckBox.feature) {
            Write-Host "正在安装 $feature"
            Write-WinUtilLog -Component "Feature" -Message "正在启用 Windows 可选功能：$feature"
            Enable-WindowsOptionalFeature -Online -FeatureName $feature -All -NoRestart -ErrorAction Stop
            Write-WinUtilLog -Component "Feature" -Message "已启用 Windows 可选功能：$feature"
        }
    }

    if ($sync.configs.feature.$CheckBox.InvokeScript) {
        foreach ($script in $sync.configs.feature.$CheckBox.InvokeScript) {
            Write-Host "正在运行 $CheckBox 的脚本"
            Write-WinUtilLog -Component "Feature" -Message "正在运行 $CheckBox 的功能脚本"
            Invoke-Command -ScriptBlock ([scriptblock]::Create($script)) -ErrorAction Stop
            Write-WinUtilLog -Component "Feature" -Message "$CheckBox 的功能脚本已执行完毕"
        }
    }
    Write-WinUtilLog -Component "Feature" -Message "功能操作已完成：$CheckBox"
}
