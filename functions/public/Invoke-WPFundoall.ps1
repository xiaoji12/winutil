function Invoke-WPFundoall {
    <#

    .SYNOPSIS
        Undoes every selected tweak

    #>

    $tweaks = $sync.selectedTweaks

    if ($tweaks.count -eq 0) {
        Show-WinUtilMessage -Message "请勾选要撤销的优化项。" -Title "WinUtil" -Button "OK" -Icon "Warning"
        return
    }

    Start-WinUtilJob -Name "撤销优化项" -Description "正在撤销优化项" -Parameters @{
        Tweaks = @($tweaks)
    } -ScriptBlock {
        param($Tweaks)

        $total = @($Tweaks).Count
        Write-WinUtilLog -Component "Tweaks" -Message "已请求撤销优化项：共选中 $total 个。"

        for ($i = 0; $i -lt $total; $i++) {
            Step-WinUtilJob -Status "正在撤销 $($Tweaks[$i]) ($($i + 1)/$total)" -Percent ([int](($i / $total) * 100))
            Measure-WinUtilStep -Scope "Undo tweaks" -Name $Tweaks[$i] -ScriptBlock {
                Invoke-WinUtiltweaks $Tweaks[$i] -undo $true
            }
            Step-WinUtilJob -Percent ([int]((($i + 1) / $total) * 100))
        }
    }
}
