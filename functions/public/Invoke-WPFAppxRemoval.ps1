function Invoke-WPFAppxRemoval {
    <#

    .SYNOPSIS
        Removes the selected AppX packages

    #>

    if ($null -eq $sync.selectedAppx -or $sync.selectedAppx.Count -eq 0) {
        Show-WinUtilMessage -Message "未选择任何 AppX 应用" -Title "错误" -Button "OK" -Icon "Error"
        return
    }

    Start-WinUtilJob -Name "AppX" -Description "正在卸载 AppX 应用" -Parameters @{
        Selected = @($sync.selectedAppx)
        Apps = $sync.configs.appxHashtable
    } -ScriptBlock {
        param($Selected, $Apps)

        $total = @($Selected).Count
        $packageList = [System.Collections.Generic.List[string]]::new()
        Write-WinUtilLog -Component "AppX" -Message "开始卸载所选的 $total 个 AppX 应用。"

        for ($index = 0; $index -lt $total; $index++) {
            $key = $Selected[$index]
            $app = $Apps[$key]
            $position = $index + 1
            Step-WinUtilJob -Status "正在卸载 $($app.Content) ($position/$total)" -Percent ([int](($index / $total) * 90))

            if ($key -eq "WPFAppxMicrosoft_XboxGamingOverlay") {
                # Making sure Game Bar isn't running
                Write-WinUtilLog -Component "AppX" -Message "卸载 Xbox Gaming Overlay 前先停止 GameBarFTServer。"
                Stop-Process -Name GameBarFTServer -Force -Confirm:$false -ErrorAction SilentlyContinue

                # This stops annoying ms-gamebar popup when launching games.
                Write-WinUtilLog -Component "AppX" -Message "卸载 Xbox Gaming Overlay 前先禁用 Game DVR 录制。"
                Set-ItemProperty -Path HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\GameDVR -Name AppCaptureEnabled -Value 0
            }

            if ($key -eq "WPFAppxMicrosoft_WindowsNotepad") {
                Write-WinUtilLog -Component "AppX" -Message "卸载 Notepad 前先停止 dllhost。"
                Stop-Process -Name dllhost -Force -Confirm:$false -ErrorAction SilentlyContinue
            }

            Write-Host "正在卸载 $($app.Content)"
            Write-WinUtilLog -Component "AppX" -Message "正在卸载 $($app.Content) ($($app.PackageId))。"
            Remove-WinUtilAPPX -Name $app.PackageId
            $packageList.Add($app.PackageId)

            if ($key -eq "WPFAppxMSTeams") {
                # Uninstalls Microsoft Teams Meeting Add-in for Microsoft Office
                Write-WinUtilLog -Component "AppX" -Message "正在卸载 Microsoft Teams 会议加载项软件包。"
                Get-Package -Name "Microsoft Teams*" -ErrorAction SilentlyContinue | Uninstall-Package -Force
            }

            Step-WinUtilJob -Status "已卸载 $($app.Content) ($position/$total)" -Percent ([int](($position / $total) * 90))
        }

        if ($packageList.Count -gt 0) {
            Step-WinUtilJob -Status "正在卸载预置的 AppX 应用" -Percent 90
            Remove-WinUtilProvisionedAPPX -PackageList $packageList.ToArray()
        }
    }
}
