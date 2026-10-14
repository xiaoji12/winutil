function Remove-WinUtilAPPX {
    <#

    .SYNOPSIS
        Removes all APPX packages that match the given name

    .PARAMETER Name
        The name of the APPX package to remove

    .EXAMPLE
        Remove-WinUtilAPPX -Name "Microsoft.Microsoft3DViewer"

    #>
    param (
        $Name
    )

    Write-Host "正在移除 $Name"
    Write-WinUtilLog -Component "AppX" -Message "正在移除 AppX 应用（匹配模式）：$Name"

    # We explicitly loop through packages instead of using the pipeline because PowerShell 7 pipeline binding
    # for Remove-AppxPackage fails silently, and Get-AppxPackage -AllUsers returns duplicate objects for each user profile.
    $pkgs = Get-AppxPackage "*$Name*" -AllUsers | Sort-Object -Property PackageFullName -Unique
    if ($null -ne $pkgs) {
        foreach ($pkg in $pkgs) {
            try {
                Remove-AppxPackage -Package $pkg.PackageFullName -AllUsers -ErrorAction Stop
            }
            catch {
                Write-WinUtilLog -Level "ERROR" -Component "AppX" -Message "移除 AppX 应用 $($pkg.PackageFullName) 失败：$($_.Exception.Message)"
            }
        }
    }

    Write-WinUtilLog -Component "AppX" -Message "AppX 应用移除已完成（匹配模式）：$Name"
}
