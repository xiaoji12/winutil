function Copy-WinUtilEnvironmentReportExportFile {
    param(
        [Parameter(Mandatory)]
        [string]$SourcePath,

        [Parameter(Mandatory)]
        [string]$DestinationPath,

        [switch]$Overwrite
    )

    [System.IO.File]::Copy($SourcePath, $DestinationPath, $Overwrite)
}

function Remove-WinUtilEnvironmentReportExportFile {
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    [System.IO.File]::Delete($Path)
}

function Write-WinUtilEnvironmentReportExport {
    <#
    .SYNOPSIS
        Publishes an environment report and its optional log companion as one export.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$JsonPath,

        [Parameter(Mandatory)]
        [string]$Json,

        [Parameter(Mandatory)]
        [string]$LogsPath,

        [AllowNull()]
        [string]$Logs,

        [switch]$IncludeLogs
    )

    $suffix = [guid]::NewGuid().ToString("N")
    $jsonTempPath = "$JsonPath.$suffix.tmp"
    $logsTempPath = "$LogsPath.$suffix.tmp"
    $jsonBackupPath = "$JsonPath.$suffix.bak"
    $logsBackupPath = "$LogsPath.$suffix.bak"
    $hadJson = [System.IO.File]::Exists($JsonPath)
    $hadLogs = $IncludeLogs -and [System.IO.File]::Exists($LogsPath)
    $encoding = [System.Text.UTF8Encoding]::new($false)
    $retainJsonBackup = $false
    $retainLogsBackup = $false

    try {
        # Prepare both outputs before replacing either destination. If collection or a temporary
        # write fails, the previous export remains untouched.
        [System.IO.File]::WriteAllText($jsonTempPath, $Json, $encoding)
        if ($IncludeLogs) {
            [System.IO.File]::WriteAllText($logsTempPath, $Logs, $encoding)
        }

        if ($hadJson) {
            Copy-WinUtilEnvironmentReportExportFile -SourcePath $JsonPath -DestinationPath $jsonBackupPath
        }
        if ($hadLogs) {
            Copy-WinUtilEnvironmentReportExportFile -SourcePath $LogsPath -DestinationPath $logsBackupPath
        }

        try {
            Copy-WinUtilEnvironmentReportExportFile -SourcePath $jsonTempPath -DestinationPath $JsonPath -Overwrite
            if ($IncludeLogs) {
                Copy-WinUtilEnvironmentReportExportFile -SourcePath $logsTempPath -DestinationPath $LogsPath -Overwrite
            }
        } catch {
            $publishError = $_
            $rollbackErrors = [System.Collections.Generic.List[string]]::new()

            # A two-file replacement is not atomic on Windows. Restore both destinations if the
            # second publish fails so an old companion cannot appear to belong to new JSON.
            try {
                if ($hadJson) {
                    Copy-WinUtilEnvironmentReportExportFile -SourcePath $jsonBackupPath -DestinationPath $JsonPath -Overwrite
                } elseif ([System.IO.File]::Exists($JsonPath)) {
                    Remove-WinUtilEnvironmentReportExportFile -Path $JsonPath
                }
            } catch {
                $retainJsonBackup = $hadJson
                $recoveryNote = if ($hadJson) { " 恢复副本保留在 $jsonBackupPath。" } else { "" }
                $rollbackErrors.Add("JSON 恢复失败：$($_.Exception.Message).$recoveryNote")
            }

            if ($IncludeLogs) {
                try {
                    if ($hadLogs) {
                        Copy-WinUtilEnvironmentReportExportFile -SourcePath $logsBackupPath -DestinationPath $LogsPath -Overwrite
                    } elseif ([System.IO.File]::Exists($LogsPath)) {
                        Remove-WinUtilEnvironmentReportExportFile -Path $LogsPath
                    }
                } catch {
                    $retainLogsBackup = $hadLogs
                    $recoveryNote = if ($hadLogs) { " 恢复副本保留在 $logsBackupPath。" } else { "" }
                    $rollbackErrors.Add("日志恢复失败：$($_.Exception.Message).$recoveryNote")
                }
            }

            if ($rollbackErrors.Count -gt 0) {
                $message = "环境报告导出失败：$($publishError.Exception.Message) 回滚也失败：$($rollbackErrors -join ' ')"
                throw [System.IO.IOException]::new($message, $publishError.Exception)
            }

            throw $publishError
        }
    } finally {
        $cleanupTargets = @(
            [pscustomobject]@{ Path = $jsonTempPath; Retain = $false },
            [pscustomobject]@{ Path = $logsTempPath; Retain = $false },
            [pscustomobject]@{ Path = $jsonBackupPath; Retain = $retainJsonBackup },
            [pscustomobject]@{ Path = $logsBackupPath; Retain = $retainLogsBackup }
        )
        foreach ($cleanupTarget in $cleanupTargets) {
            if (-not $cleanupTarget.Retain -and [System.IO.File]::Exists($cleanupTarget.Path)) {
                try {
                    Remove-WinUtilEnvironmentReportExportFile -Path $cleanupTarget.Path
                } catch {
                    Write-Warning "无法删除环境报告导出的临时文件 $($cleanupTarget.Path)：$($_.Exception.Message)"
                }
            }
        }
    }
}
