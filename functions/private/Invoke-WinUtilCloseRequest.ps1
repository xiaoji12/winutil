function Invoke-WinUtilCloseRequest {
    <#
        .SYNOPSIS
            Asks what to do about work that is still running when the window is closed

        .DESCRIPTION
            A half finished install or tweak run is not ended without asking. Either it finishes
            without the window, reporting to the console and then exiting, or it is stopped and
            everything closes now.

        .PARAMETER RunningJob
            The name of the job in flight, so the question names what is at stake.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$RunningJob
    )

    # The question carries the meaning rather than naming buttons: Windows labels them in its own
    # language, so "Yes" in the text would not match a button reading "Ja".
    $answer = Show-WinUtilMessage -Button "YesNoCancel" -Icon "Warning" -Title "$RunningJob 仍在运行" -Message @"
$RunningJob 尚未完成。

是否关闭窗口，让它在控制台中继续完成？

完成后 WinUtil 会自动退出。如果不这样做，它将被停止，
所有内容会立即关闭。选择“取消”可保持 WinUtil 打开。
"@

    switch ("$answer") {
        "Yes" {
            Write-WinUtilLog -Component "UI" -Message "收到关闭请求：正在关闭窗口，$RunningJob 将在控制台中继续。"
            $sync.FinishInConsole = $true
            $sync.ForceClose = $true

            Write-Host ""
            Write-Host "WinUtil 的窗口已关闭。$RunningJob 仍在此处运行，完成后本窗口将自动关闭。" -ForegroundColor Cyan
            Write-Host ""

            # Posted rather than closed from inside the handler that is already unwinding
            Request-WinUtilWindowClose
        }
        "No" {
            Write-WinUtilLog -Component "UI" -Message "收到关闭请求：正在停止 $RunningJob。"
            Step-WinUtilJob -Status "正在停止 $RunningJob" -State "Indeterminate"
            $sync.ForceClose = $true

            # Close the window first. The main thread owns pool shutdown after ShowDialog
            # returns, so the worker can finish its UI-dispatching finally block before the UI
            # runspace is disposed. Waiting for it here would deadlock the dispatcher.
            Request-WinUtilWindowClose
        }
        default {
            Write-WinUtilLog -Component "UI" -Message "已取消关闭，$RunningJob 仍在运行。"
        }
    }
}

function Request-WinUtilWindowClose {
    <#
        .SYNOPSIS
            Closes the window from outside the handler that is currently cancelling the close

    #>
    if (-not (Test-WinUtilUIAlive)) {
        return
    }

    $sync.Form.Dispatcher.BeginInvoke([System.Windows.Threading.DispatcherPriority]::Background, [action]{
        $sync.Form.Close()
    }) | Out-Null
}

function Wait-WinUtilRemainingWork {
    <#
        .SYNOPSIS
            Waits for work that outlived the window, reporting to the console

        .DESCRIPTION
            Runs on the main thread once the interface has gone. The job is still on the worker
            pool and keeps logging, so this only waits and keeps the wait visible.

        .PARAMETER TimeoutMinutes
            Upper bound, so a worker that never returns cannot keep the process alive.
    #>
    param(
        # Double rather than int: an int silently truncates a fractional value to zero, which
        # turns the bound into "do not wait at all"
        [double]$TimeoutMinutes = 120
    )

    if (-not $sync.FinishInConsole -or -not $sync.ActiveJob) {
        return
    }

    $job = $sync.ActiveJob
    Write-WinUtilLog -Component "UI" -Message "窗口已关闭，正在等待 $job 完成。"
    Write-Host "正在等待 $job 完成..." -ForegroundColor Cyan

    $clock = [System.Diagnostics.Stopwatch]::StartNew()
    while ($sync.ActiveJob -and $clock.Elapsed.TotalMinutes -lt $TimeoutMinutes) {
        Start-Sleep -Milliseconds 250
    }

    # The job's last progress line is still open, so anything after it needs a fresh line
    Complete-WinUtilConsoleProgress

    if ($sync.ActiveJob) {
        Write-WinUtilLog -Level "WARN" -Component "UI" -Message "$job 在 $TimeoutMinutes 分钟内未完成，仍然退出。"
        Write-Host "$job 用时已超过 $TimeoutMinutes 分钟，正在退出。" -ForegroundColor Yellow
        return
    }

    Write-WinUtilLog -Component "UI" -Message "$job 在窗口关闭后完成，用时 $([int]$clock.Elapsed.TotalSeconds) 秒。"
    Write-Host "$job 已完成，正在关闭。" -ForegroundColor Green
}
