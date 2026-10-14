function Invoke-WPFOOSU {
    Start-WinUtilJob -Name "OOSU" -Description "正在下载 O&O ShutUp10++" -Parameters @{
        DownloadPath = Join-Path $sync.winutildir "ooshutup10.exe"
    } -ScriptBlock {
        param($DownloadPath)

        Write-WinUtilLog -Component "OOSU" -Message "正在下载 O&O ShutUp10++。"

        Save-WinUtilFile -Uri "https://dl5.oo-software.com/files/ooshutup10/OOSU10.exe" -DestinationPath $DownloadPath -ProgressCallback {
            param($percent)
            Step-WinUtilJob -Status "正在下载 O&O ShutUp10++ ($percent%)" -Percent $percent
        }

        Step-WinUtilJob -Status "正在启动 O&O ShutUp10++" -Percent 100
        Start-Process -FilePath $DownloadPath
        Write-WinUtilLog -Component "OOSU" -Message "O&O ShutUp10++ 已启动。"
    }
}
