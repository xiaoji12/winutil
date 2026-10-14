function Invoke-WPFImpex {
    <#

    .SYNOPSIS
        Handles importing and exporting of the checkboxes checked for the tweaks section

    .PARAMETER type
        Indicates whether to 'import' or 'export'

    .PARAMETER checkbox
        The checkbox to export to a file or apply the imported file to

    .EXAMPLE
        Invoke-WPFImpex -type "export"

    #>
    param(
        $type,
        $Config = $null,

        # Add to the current selection instead of replacing it. Used when a preset has already
        # set a baseline that the imported file is meant to extend.
        [switch]$Merge,

        # Headless runs cannot show a dialog and must fail rather than applying a partial request.
        [switch]$ThrowOnError
    )

    function ConfigDialog {
        if (!$Config) {
            switch ($type) {
                "export" { $FileBrowser = New-Object System.Windows.Forms.SaveFileDialog }
                "import" { $FileBrowser = New-Object System.Windows.Forms.OpenFileDialog }
            }
            $FileBrowser.InitialDirectory = [Environment]::GetFolderPath('Desktop')
            $FileBrowser.Filter = "JSON Files (*.json)|*.json"
            $FileBrowser.ShowDialog() | Out-Null

            if ($FileBrowser.FileName -eq "") {
                return $null
            } else {
                return $FileBrowser.FileName
            }
        } else {
            return $Config
        }
    }

    switch ($type) {
        "export" {
            try {
                $Config = ConfigDialog
                if ($Config) {
                    $allConfs = ($sync.selectedApps + $sync.selectedTweaks + $sync.selectedToggles + $sync.selectedFeatures + $sync.selectedAppx) | ForEach-Object { [string]$_ }
                    if (-not $allConfs) {
                        Show-WinUtilMessage -Message (
                            "没有选中任何要导出的设置。请先至少选择一个应用、优化项、开关项、功能或 AppX 应用，然后再导出。"
                        ) -Title "无可导出内容" -Button "OK" -Icon "Warning" | Out-Null
                        return
                    }
                    $jsonFile = $allConfs | ConvertTo-Json
                    $jsonFile | Out-File $Config -Force
                    "iex ""& { `$(irm https://christitus.com/win) } -Config '$Config'""" | Set-Clipboard
                }
            } catch {
                Write-Error "导出时发生错误：$_"
            }
        }
        "import" {
            try {
                $Config = ConfigDialog
                if ($Config) {
                    try {
                        if ($Config -match '^https?://') {
                            $jsonFile = (Invoke-WebRequest "$Config" -ErrorAction Stop).Content | ConvertFrom-Json
                        } else {
                            $jsonFile = Get-Content $Config -ErrorAction Stop | ConvertFrom-Json
                        }
                    } catch {
                        $message = "无法从指定路径或 URL 加载 JSON 文件：$_"
                        if ($ThrowOnError) { throw $message }
                        Write-Error $message
                        return
                    }
                    $isLegacyConfig = $jsonFile -is [System.Management.Automation.PSCustomObject] -and
                        $null -ne $jsonFile.PSObject.Properties["Install"] -and
                        $null -ne $jsonFile.PSObject.Properties["WPFInstall"]
                    if ($isLegacyConfig) {
                        Write-WinUtilLog -Component "Impex" -Message "检测到旧版 WinUtil 配置结构，正在展平导入对象。"
                        # Legacy exports stored checkbox keys in WPFInstall and duplicated package
                        # source metadata in Install. Current package IDs come from the app catalog,
                        # so only the selection-key properties are restored.
                        $flattenedJson = @(
                            foreach ($property in $jsonFile.PSObject.Properties) {
                                if ($property.Name -notmatch '^WPF(?:Install|Tweaks|Toggle|Feature|Appx)') {
                                    continue
                                }

                                foreach ($selection in @($property.Value)) {
                                    if ($selection -is [string] -and -not [string]::IsNullOrWhiteSpace($selection)) {
                                        $selection
                                    }
                                }
                            }
                        )
                    } else {
                        # New style config: flat array of strings
                        $flattenedJson = $jsonFile
                    }

                    if (-not $flattenedJson) {
                        Show-WinUtilMessage -Message "所选文件中没有可导入的设置，未做任何更改。" -Title "配置为空" -Button "OK" -Icon "Warning" | Out-Null
                        return
                    }

                    # Replace unless this import is merging onto something already selected,
                    # which the headless path does when it is given a preset and a config
                    $replaceMode = @{}
                    if (-not $Merge) { $replaceMode["Replace"] = $true }

                    # Modern configs stay strict. Legacy configs can reference entries that no
                    # longer exist, so restore supported selections and report the retired keys.
                    if ($isLegacyConfig) {
                        $skippedSelections = @(Update-WinUtilSelections -flatJson $flattenedJson @replaceMode -SkipUnknown)

                        if ($skippedSelections.Count -gt 0) {
                            $skippedSummary = $skippedSelections -join ", "
                            Write-WinUtilLog -Component "Impex" -Level "WARN" -Message "已跳过不受支持的旧版选项：$skippedSummary"
                        }

                        if ($skippedSelections.Count -eq @($flattenedJson).Count) {
                            if ($sync.Form) {
                                Show-WinUtilMessage -Message "此旧版配置中没有当前版本 WinUtil 支持的设置，未做任何更改。" -Title "不受支持的旧版配置" -Icon "Warning" | Out-Null
                            }
                            return
                        }

                        if ($skippedSelections.Count -gt 0) {
                            $skippedDisplay = @($skippedSelections | Select-Object -First 10) -join ", "
                            if ($skippedSelections.Count -gt 10) {
                                $skippedDisplay += "`n...以及另外 $($skippedSelections.Count - 10) 项。详见 WinUtil 日志。"
                            }
                            if ($sync.Form) {
                                Show-WinUtilMessage -Message "已导入受支持的设置。以下已停用的设置被跳过：`n`n$skippedDisplay" -Title "旧版配置已部分导入" -Icon "Warning" | Out-Null
                            }
                        }
                    } else {
                        # Build and validate every imported selection before replacing the current
                        # state. This keeps a malformed config from leaving partial selections behind.
                        Update-WinUtilSelections -flatJson $flattenedJson @replaceMode
                    }

                    if ($sync.Form) {
                        Reset-WPFCheckBoxes -doToggles $true
                    }
                }
            } catch {
                if ($ThrowOnError) { throw }
                Write-Error "导入时发生错误：$_"
            }
        }
    }
}
