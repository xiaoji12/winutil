function Invoke-WPFtweaksbutton {
  <#

    .SYNOPSIS
        Invokes the functions associated with each group of checkboxes

  #>

  $Tweaks = $sync.selectedTweaks
  $dnsProvider = $sync["WPFchangedns"].text
  if (-not ($dnsProvider)) {
    $dnsProvider = "Default"
  }

  if ($Tweaks.count -eq 0 -and $dnsProvider -eq "Default") {
    Show-WinUtilMessage -Message "请勾选要执行的优化项。" -Title "WinUtil" -Button "OK" -Icon "Warning"
    return
  }

  Write-WinUtilLog -Component "Tweaks" -Message "已请求应用优化项：共选中 $(@($Tweaks).Count) 个，DNS 提供商：$dnsProvider"

  Start-WinUtilJob -Name "Tweaks" -Description "正在应用优化项" -Parameters @{
    Tweaks = @($Tweaks)
    DnsProvider = $dnsProvider
  } -ScriptBlock {
    param($Tweaks, $DnsProvider)

    # The restore point has to be taken before anything else changes
    $restorePointTweak = "WPFTweaksRestorePoint"
    $tweaksToRun = @($Tweaks | Where-Object { $_ -ne $restorePointTweak })
    $totalSteps = [Math]::Max(@($Tweaks).Count, 1)
    $completedSteps = 0

    if ($Tweaks -contains $restorePointTweak) {
      Step-WinUtilJob -Status "正在创建还原点" -Percent 0
      Write-WinUtilLog -Component "Tweaks" -Message "正在应用所选优化项前创建还原点。"
      Measure-WinUtilStep -Scope "Tweaks" -Name $restorePointTweak -ScriptBlock {
        Invoke-WinUtilTweaks $restorePointTweak
      }
      $completedSteps = 1
    }

    if ($DnsProvider -ne "Default") {
      $dnsResult = Measure-WinUtilStep -Scope "Tweaks" -Name "Set DNS to $DnsProvider" -ScriptBlock {
        @(Set-WinUtilDNS -DNSProvider $DnsProvider)
      }

      # Carrying on after the DNS change failed leaves the machine half configured, so the run
      # ends here and the job layer reports it
      if (@($dnsResult)[-1] -ne $true) {
        throw "将 DNS 更改为 $DnsProvider 失败，因此未应用其余优化项。"
      }
    }

    foreach ($tweak in $tweaksToRun) {
      Step-WinUtilJob -Status "正在应用 $tweak ($($completedSteps + 1)/$totalSteps)" -Percent ([int](($completedSteps / $totalSteps) * 100))
      Measure-WinUtilStep -Scope "Tweaks" -Name $tweak -ScriptBlock {
        Invoke-WinUtilTweaks $tweak
      }
      $completedSteps++
      Step-WinUtilJob -Percent ([int](($completedSteps / $totalSteps) * 100))
    }
  }
}
