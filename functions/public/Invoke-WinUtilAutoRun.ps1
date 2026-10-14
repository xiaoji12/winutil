function Invoke-WinUtilAutoRun {
    <#

    .SYNOPSIS
        Runs every selected action to completion without a window

    .DESCRIPTION
        The headless path. Each action is the same job the button would start, run one at a time
        because the job layer allows one at a time, and waited on until the worker clears the
        busy flag.

        Returns a summary of what ran so the caller can decide the exit code. Nothing here
        touches the interface, so it behaves the same whether a window exists or not.

    .PARAMETER StopTimeoutSeconds
        How long a step that timed out is given to stop before the run gives up on the rest.

    .PARAMETER StepTimeoutSeconds
        How long a single action may take before the run gives up on it. Without a ceiling an
        installer waiting on something that will never arrive hangs the run for good.

    #>
    param(
        [int]$StepTimeoutSeconds = 3600,

        [int]$StopTimeoutSeconds = 30
    )

    $steps = @(
        [pscustomobject]@{ Name = "优化项";          Count = @($sync.selectedTweaks).Count;   Action = { Invoke-WPFtweaksbutton } }
        [pscustomobject]@{ Name = "开关项";         Count = @($sync.selectedToggles).Count;  Action = { Invoke-WPFToggleSelections } }
        [pscustomobject]@{ Name = "功能";        Count = @($sync.selectedFeatures).Count; Action = { Invoke-WPFFeatureInstall } }
        [pscustomobject]@{ Name = "应用";    Count = @($sync.selectedApps).Count;     Action = { Invoke-WPFInstall } }
        [pscustomobject]@{ Name = "AppX 应用卸载";    Count = @($sync.selectedAppx).Count;     Action = { Invoke-WPFAppxRemoval } }
    )

    $planned = @($steps | Where-Object { $_.Count -gt 0 })
    if ($planned.Count -eq 0) {
        Write-WinUtilLog -Level "WARN" -Component "AutoRun" -Message "未选择任何项目，因此没有需要执行的操作。"
        return [pscustomobject]@{ Steps = @(); Failed = 0; TimedOut = 0; Errors = 0; Warnings = 0 }
    }

    Write-WinUtilLog -Component "AutoRun" -Message "无界面运行开始：$(($planned | ForEach-Object { "$($_.Name) ($($_.Count))" }) -join ', ')"

    $results = New-Object System.Collections.ArrayList
    $runClock = [System.Diagnostics.Stopwatch]::StartNew()

    foreach ($step in $planned) {
        $errorsBefore = if ($sync.LoggedErrors) { $sync.LoggedErrors.Count } else { 0 }
        $sync.LastJobResult = $null
        $stepClock = [System.Diagnostics.Stopwatch]::StartNew()
        $timedOut = $false

        Write-WinUtilLog -Component "AutoRun" -Message "$($step.Name)：开始执行 $($step.Count) 个项目。"

        try {
            & $step.Action
        } catch {
            Write-WinUtilErrorRecord -ErrorRecord $_ -Component "AutoRun" -Context "启动 $($step.Name)"
        }

        # The action starts a job and returns; the run is over when the worker clears the flag
        while ($sync.ActiveJob) {
            if ($stepClock.Elapsed.TotalSeconds -ge $StepTimeoutSeconds) {
                $timedOut = $true
                Write-WinUtilLog -Level "ERROR" -Component "AutoRun" -Message "$($step.Name) 在 $StepTimeoutSeconds 秒内未完成，继续执行后续步骤。"
                break
            }
            Start-Sleep -Milliseconds 200
        }

        $stepClock.Stop()
        $newErrors = if ($sync.LoggedErrors) { $sync.LoggedErrors.Count - $errorsBefore } else { 0 }
        $newWarnings = if ($null -ne $sync.LastJobResult) { [int]$sync.LastJobResult.Warnings } else { 0 }

        $null = $results.Add([pscustomobject]@{
            Name = $step.Name
            Items = $step.Count
            Seconds = [int]$stepClock.Elapsed.TotalSeconds
            Errors = $newErrors
            Warnings = $newWarnings
            TimedOut = $timedOut
        })

        $outcome = if ($timedOut) { "已超时" } elseif ($newErrors -gt 0) { "完成，但有 $newErrors 个错误" } elseif ($newWarnings -gt 0) { "完成，但有 $newWarnings 个警告" } else { "已完成" }
        Write-WinUtilLog -Component "AutoRun" -Message "$($step.Name)：$outcome，用时 $([int]$stepClock.Elapsed.TotalSeconds) 秒。"

        if ($timedOut) {
            # The worker is still on the pool. Clearing the slot on its own would let the next
            # step start beside it, so two runs would be changing the machine at once.
            Stop-WinUtilActiveWork -NoWait | Out-Null

            $stopDeadline = (Get-Date).AddSeconds($StopTimeoutSeconds)
            while ((Test-WinUtilActiveWorkRunning) -and (Get-Date) -lt $stopDeadline) {
                Start-Sleep -Milliseconds 200
            }

            # A job that never cleared the flag would make every later step refuse to start
            $null = Clear-WinUtilActiveJob

            if (Test-WinUtilActiveWorkRunning) {
                Write-WinUtilLog -Level "ERROR" -Component "AutoRun" -Message "$($step.Name) 无法停止，因此放弃剩余步骤，而不是与其同时运行。"
                break
            }
        }
    }

    $runClock.Stop()
    Write-WinUtilTimingSummary -Scope "AutoRun" -TotalMilliseconds $runClock.ElapsedMilliseconds

    return [pscustomobject]@{
        Steps = @($results)
        Failed = @($results | Where-Object { $_.Errors -gt 0 }).Count
        TimedOut = @($results | Where-Object { $_.TimedOut }).Count
        Errors = (@($results | Measure-Object -Property Errors -Sum).Sum)
        Warnings = (@($results | Measure-Object -Property Warnings -Sum).Sum)
    }
}

function Write-WinUtilAutoRunSummary {
    <#
        .SYNOPSIS
            Prints what a headless run did and returns the exit code it should end with
    #>
    param(
        [Parameter(Mandatory)]
        $Summary
    )

    Write-Host ""
    Write-Host "=== WinUtil 无界面运行 ===" -ForegroundColor Cyan

    foreach ($step in @($Summary.Steps)) {
        $state = if ($step.TimedOut) { "已超时" } elseif ($step.Errors -gt 0) { "$($step.Errors) 个错误" } elseif ($step.Warnings -gt 0) { "$($step.Warnings) 个警告" } else { "正常" }
        $colour = if ($step.TimedOut -or $step.Errors -gt 0 -or $step.Warnings -gt 0) { "Yellow" } else { "Green" }
        Write-Host ("  {0,-14} {1,3} item(s)  {2,5}s  {3}" -f $step.Name, $step.Items, $step.Seconds, $state) -ForegroundColor $colour
    }

    if (@($Summary.Steps).Count -eq 0) {
        Write-Host "  未选择任何项目" -ForegroundColor Yellow
        Write-Host ""
        return 2
    }

    if ($Summary.TimedOut -gt 0 -or $Summary.Failed -gt 0) {
        Write-Host ""
        Write-Host "已完成，但存在问题。详见 $($sync.logPath)" -ForegroundColor Yellow
        Write-Host ""
        return 1
    }

    if ($Summary.Warnings -gt 0) {
        Write-Host ""
        Write-Host "已完成，但有警告。详见 $($sync.logPath)" -ForegroundColor Yellow
        Write-Host ""
        return 0
    }

    Write-Host ""
    Write-Host "所有步骤已完成。日志：$($sync.logPath)" -ForegroundColor Green
    Write-Host ""
    return 0
}
