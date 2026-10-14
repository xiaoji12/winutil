function Invoke-WinUtilRobocopy {
    <#
        .SYNOPSIS
            Runs robocopy and fails the job when files were not copied

        .DESCRIPTION
            robocopy reports through its exit code rather than by throwing, and codes below 8
            are success: 1 means files were copied, 3 means copied plus extras. 8 and above mean
            at least one file did not make it, which produces media that looks complete and does
            not boot.
    #>
    param(
        [Parameter(Mandatory)][string]$Source,
        [Parameter(Mandatory)][string]$Destination,
        [string[]]$Arguments = @()
    )

    & robocopy $Source $Destination @Arguments
    $code = $LASTEXITCODE

    if ($code -ge 8) {
        throw "robocopy 无法将所有文件从 $Source 复制到 $Destination（退出代码 $code）。"
    }

    Write-WinUtilISOLog "robocopy 已完成，退出代码 $code。"
}

function Write-WinUtilISOLog {
    <#
    .SYNOPSIS
        Appends a line to the Win11 Creator status log and to the session log.

    .DESCRIPTION
        The status log is a UI control, so the append is posted to the UI thread rather than
        waited on. Without a window it degrades to the session log alone, which keeps job
        bodies free of "is there a UI" checks.
    #>
    param(
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet("INFO", "WARN", "ERROR")]
        [string]$Level = "INFO",
        [switch]$SkipSessionLog
    )

    if (-not $SkipSessionLog) {
        Write-WinUtilLog -Level $Level -Component "Win11Creator" -Message $Message
    }

    Invoke-WPFUIThread -Async -Parameters @{
        LogLine = "[$((Get-Date).ToString('HH:mm:ss'))] $Message"
    } -ScriptBlock {
        param($LogLine)

        $box = $sync["WPFWin11ISOStatusLog"]
        if ($null -eq $box) { return }

        if ($box.Text -eq "就绪。请先选择一个 Windows 11 ISO 以开始。") {
            $box.Text = $LogLine
        } else {
            $box.Text += "`n$LogLine"
        }
        $box.CaretIndex = $box.Text.Length
        $box.ScrollToEnd()
    }
}

function Set-WinUtilISOStep {
    <#
        .SYNOPSIS
            Selects a page of the Win11 Creator wizard and sets which pages can be navigated back to

        .PARAMETER Step
            Select, Modify, Working or Output

        .PARAMETER Label
            Headline shown on the working page while a long operation runs

        .PARAMETER Reverse
            Spins the working page icon backwards
    #>
    param(
        [Parameter(Mandatory)]
        [ValidateSet("Select", "Modify", "Working", "Output")]
        [string]$Step,

        [string]$Label,

        [switch]$Reverse
    )

    Invoke-WPFUIThread -Parameters @{ Step = $Step; Label = $Label; Reverse = [bool]$Reverse } -ScriptBlock {
        param($Step, $Label, $Reverse)

        if ($Label) { $sync["WPFWin11ISOWorkingLabel"].Text = $Label }

        $sync["WPFWin11ISOWorkingSpinner"].Tag = if ($Reverse) { "Reverse" } else { "Forward" }

        $sync["WPFWin11ISOSelectSection"].IsEnabled = $Step -in @("Select", "Modify")
        $sync["WPFWin11ISOModifySection"].IsEnabled = $Step -eq "Modify"
        $sync["WPFWin11ISOOutputSection"].IsEnabled = $Step -eq "Output"

        $sync["WPFWin11ISO$($Step)Section"].IsSelected = $true
    }
}

function Get-WinUtilEditionIdFromName {
    <#
    .SYNOPSIS
        Maps a Windows 11 edition display name to the edition id used by unattended setup.
    #>
    param([string]$EditionName)

    $normalizedName = ($EditionName -replace '^Windows\s+11\s+', '').Trim()
    switch -Regex ($normalizedName) {
        '^Home Single Language$'      { return 'CoreSingleLanguage' }
        '^Home N$'                    { return 'CoreN' }
        '^Home$'                      { return 'Core' }
        '^Pro for Workstations N$'    { return 'ProfessionalWorkstationN' }
        '^Pro for Workstations$'      { return 'ProfessionalWorkstation' }
        '^Pro Education N$'           { return 'ProfessionalEducationN' }
        '^Pro Education$'             { return 'ProfessionalEducation' }
        '^Pro N$'                     { return 'ProfessionalN' }
        '^Pro$'                       { return 'Professional' }
        '^Education N$'               { return 'EducationN' }
        '^Education$'                 { return 'Education' }
        '^Enterprise LTSC N$'         { return 'EnterpriseSN' }
        '^Enterprise LTSC$'           { return 'EnterpriseS' }
        '^Enterprise N$'              { return 'EnterpriseN' }
        '^Enterprise$'                { return 'Enterprise' }
        default                       { return '' }
    }
}

function Invoke-WinUtilISOBrowse {
    Add-Type -AssemblyName System.Windows.Forms

    $dlg = [System.Windows.Forms.OpenFileDialog]::new()
    $dlg.Title            = "选择 Windows 11 ISO"
    $dlg.Filter           = "ISO 文件 (*.iso)|*.iso|所有文件 (*.*)|*.*"
    $dlg.InitialDirectory = [System.Environment]::GetFolderPath("Desktop")

    if ($dlg.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { return }

    $isoPath    = $dlg.FileName
    $fileSizeGB = [math]::Round((Get-Item $isoPath).Length / 1GB, 2)

    $sync["WPFWin11ISOPath"].Text           = $isoPath
    $sync["WPFWin11ISOFileInfo"].Text       = "文件大小：$fileSizeGB GB"
    $sync["WPFWin11ISOFileInfo"].Visibility = "Visible"
    $sync["WPFWin11ISOVerifyResultPanel"].Visibility  = "Collapsed"

    Set-WinUtilISOStep -Step "Select"

    Write-WinUtilISOLog "已选择 ISO：$isoPath  ($fileSizeGB GB)"
}

function Invoke-WinUtilISOMountAndVerify {
    $isoPath = $sync["WPFWin11ISOPath"].Text

    if ([string]::IsNullOrWhiteSpace($isoPath) -or $isoPath -eq "尚未选择 ISO…") {
        Show-WinUtilMessage -Message "请先选择一个 ISO 文件。" -Title "未选择 ISO" -Button "OK" -Icon "Warning" | Out-Null
        return
    }

    Start-WinUtilJob -Name "ISO mount" -Description "正在挂载 ISO" -Parameters @{
        IsoPath = $isoPath
    } -ScriptBlock {
        param($isoPath)

        Invoke-WPFUIThread -ScriptBlock {
            $sync["WPFWin11ISOBrowseButton"].IsEnabled = $false
            $sync["WPFWin11ISOMountButton"].IsEnabled = $false
            $sync["WPFWin11ISOModifyButton"].IsEnabled = $false
            $sync["WPFWin11ISOVerifyResultPanel"].Visibility = "Collapsed"
        }
        Set-WinUtilISOStep -Step "Working" -Label "正在挂载并校验 ISO"

        $verified = $false
        $mountedByThisRun = $false

        try {
            $previous = $sync["Win11ISOImagePath"]
            if ($previous -and $previous -ne $isoPath -and (Get-DiskImage -ImagePath $previous -ErrorAction SilentlyContinue).Attached) {
                try {
                    Dismount-DiskImage -ImagePath $previous -ErrorAction Stop
                    Write-WinUtilISOLog "已卸载先前已校验的 ISO：$previous"
                } catch {
                    Write-WinUtilISOLog -Level "ERROR" -Message "无法卸载先前已校验的 ISO ${previous}：$_"
                    Show-WinUtilMessage -Message "先前已校验的 ISO 仍处于挂载状态，且无法卸载：`n`n$previous`n`n请手动卸载后重新选择 ISO。" -Title "先前的 ISO 仍处于挂载状态" -Button "OK" -Icon "Error" | Out-Null
                    $stillMounted = [System.InvalidOperationException]::new("无法卸载先前已校验的 ISO $previous。")
                    $stillMounted.Data["WinUtilErrorReported"] = $true
                    throw $stillMounted
                }
            }

            $sync["Win11ISOImageInfo"] = $null
            $sync["Win11ISODriveLetter"] = $null
            $sync["Win11ISOWimPath"] = $null
            $sync["Win11ISOImagePath"] = $null

            Write-WinUtilISOLog "正在挂载 ISO：$isoPath"
            Step-WinUtilJob -Status "正在挂载 ISO..." -Percent 10

            Mount-DiskImage -ImagePath $isoPath -ErrorAction Stop
            $mountedByThisRun = $true

            # Bounded, because a damaged or already-mounted image may never present a drive
            # letter. The job layer runs one job at a time, so waiting here forever would block
            # every other action and the shutdown wait for the rest of the session.
            $letter = $null
            $mountClock = [System.Diagnostics.Stopwatch]::StartNew()
            while (-not $letter -and $mountClock.Elapsed.TotalSeconds -lt 60) {
                Start-Sleep -Milliseconds 500
                $letter = (Get-DiskImage -ImagePath $isoPath | Get-Volume).DriveLetter
            }

            if (-not $letter) {
                throw "ISO 已挂载，但 60 秒内未出现驱动器号：$isoPath"
            }

            $driveLetter = "${letter}:"
            Write-WinUtilISOLog "已挂载到驱动器 $driveLetter"

            Step-WinUtilJob -Status "正在校验 ISO 内容..." -Percent 30

            $wimPath = Join-Path $driveLetter "sources\install.wim"
            $esdPath = Join-Path $driveLetter "sources\install.esd"

            if (-not (Test-Path $wimPath) -and -not (Test-Path $esdPath)) {
                Write-WinUtilISOLog -Level "ERROR" -Message "未找到 install.wim/install.esd，不是有效的 Windows ISO。"
                Show-WinUtilMessage -Message "这似乎不是有效的 Windows ISO。`n`n未找到 install.wim / install.esd。" -Title "ISO 无效" -Button "OK" -Icon "Error" | Out-Null
                # Returning here would let the job layer report the run as finished
                $exception = [System.InvalidOperationException]::new("在 $isoPath 中未找到 install.wim / install.esd。")
                $exception.Data["WinUtilErrorReported"] = $true
                throw $exception
            }

            $activeWim = if (Test-Path $wimPath) { $wimPath } else { $esdPath }

            Step-WinUtilJob -Status "正在读取映像元数据..." -Percent 55
            $imageInfo = Get-WindowsImage -ImagePath $activeWim | Select-Object ImageIndex, ImageName

            if (-not ($imageInfo | Where-Object { $_.ImageName -match "Windows 11" })) {
                Write-WinUtilISOLog -Level "ERROR" -Message "映像中未找到 'Windows 11' 版本。"
                Show-WinUtilMessage -Message "此 ISO 中未找到 Windows 11 版本。`n`n仅支持官方 Windows 11 ISO。" -Title "不是 Windows 11 ISO" -Button "OK" -Icon "Error" | Out-Null
                $exception = [System.InvalidOperationException]::new("在 $isoPath 中未找到 Windows 11 版本。")
                $exception.Data["WinUtilErrorReported"] = $true
                throw $exception
            }

            $sync["Win11ISOImageInfo"] = $imageInfo
            $sync["Win11ISODriveLetter"] = $driveLetter
            $sync["Win11ISOWimPath"]     = $activeWim
            $sync["Win11ISOImagePath"]   = $isoPath

            Invoke-WPFUIThread -Parameters @{
                DriveLetter = $driveLetter
                ImageFileName = Split-Path $activeWim -Leaf
                ImageInfo = $imageInfo
            } -ScriptBlock {
                param($DriveLetter, $ImageFileName, $imageInfo)

                $sync["WPFWin11ISOMountDriveLetter"].Text = $DriveLetter
                $sync["WPFWin11ISOImageFile"].Text        = $ImageFileName
                $sync["WPFWin11ISOEditionComboBox"].Items.Clear()
                foreach ($img in $imageInfo) {
                    [void]$sync["WPFWin11ISOEditionComboBox"].Items.Add("$($img.ImageIndex): $($img.ImageName)")
                }
                if ($sync["WPFWin11ISOEditionComboBox"].Items.Count -gt 0) {
                    $proIndex = -1
                    for ($i = 0; $i -lt $sync["WPFWin11ISOEditionComboBox"].Items.Count; $i++) {
                        if ($sync["WPFWin11ISOEditionComboBox"].Items[$i] -match "Windows 11 Pro(?![\w ])") {
                            $proIndex = $i; break
                        }
                    }
                    $sync["WPFWin11ISOEditionComboBox"].SelectedIndex = if ($proIndex -ge 0) { $proIndex } else { 0 }
                }
                $sync["WPFWin11ISOVerifyResultPanel"].Visibility = "Visible"
                Set-WinUtilISOStep -Step "Modify"
            }

            $verified = $true
            Write-WinUtilISOLog "ISO 校验通过。找到的版本数：$($imageInfo.Count)"
        } finally {
            # A stopped PowerShell pipeline skips catch blocks but still runs finally. Keep the
            # source ISO cleanup here so closing WinUtil during verification cannot leave it
            # mounted.
            if (-not $verified -and $mountedByThisRun) {
                try {
                    Write-WinUtilISOLog "校验失败；正在卸载源 ISO。"
                    Dismount-DiskImage -ImagePath $isoPath -ErrorAction Stop
                } catch {
                    Write-WinUtilISOLog -Level "WARN" -Message "校验失败后无法卸载 ISO：$_"
                }
            }

            Invoke-WPFUIThread -Parameters @{ Verified = $verified } -ScriptBlock {
                param($Verified)

                $sync["WPFWin11ISOBrowseButton"].IsEnabled = $true
                $sync["WPFWin11ISOMountButton"].IsEnabled = $true
                $sync["WPFWin11ISOModifyButton"].IsEnabled = [bool]$Verified

                if ($sync["WPFWin11ISOWorkingSection"].IsSelected) {
                    Set-WinUtilISOStep -Step "Select"
                }
            }
        }
    }
}

function Invoke-WinUtilISOModify {
    $isoPath     = $sync["Win11ISOImagePath"]
    $driveLetter = $sync["Win11ISODriveLetter"]
    $wimPath     = $sync["Win11ISOWimPath"]

    if (-not $isoPath) {
        Show-WinUtilMessage -Message "未找到已校验的 ISO，请先选择并校验 ISO。" -Title "尚未就绪" -Button "OK" -Icon "Warning" | Out-Null
        return
    }

    $selectedItem     = $sync["WPFWin11ISOEditionComboBox"].SelectedItem
    $selectedWimIndex = 1
    if ($selectedItem -and $selectedItem -match '^(\d+):') {
        $selectedWimIndex = [int]$Matches[1]
    } elseif ($sync["Win11ISOImageInfo"]) {
        $selectedWimIndex = $sync["Win11ISOImageInfo"][0].ImageIndex
    }
    $selectedEditionName = if ($selectedItem) { ($selectedItem -replace '^\d+:\s*', '') } else { "Unknown" }

    # A fresh working directory per run; existing-work detection is only for resuming an export
    $workDir = Join-Path $env:TEMP "WinUtil_Win11ISO_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
    if (Test-Path $workDir) {
        $workDir = "$($workDir)_$(([guid]::NewGuid()).ToString('N').Substring(0, 8))"
    }

    $autounattendContent = if ($WinUtilAutounattendXml) {
        $WinUtilAutounattendXml
    } else {
        $toolsXml = Join-Path $PSScriptRoot "..\..\tools\autounattend.xml"
        if (Test-Path $toolsXml) { Get-Content $toolsXml -Raw } else { "" }
    }

    Start-WinUtilJob -Name "ISO modify" -Description "正在修改 ISO" -Parameters @{
        IsoPath             = $isoPath
        DriveLetter         = $driveLetter
        WimPath             = $wimPath
        WorkDir             = $workDir
        SelectedWimIndex    = $selectedWimIndex
        SelectedEditionName = $selectedEditionName
        AutounattendContent = $autounattendContent
        InjectDrivers       = $sync["WPFWin11ISOInjectDrivers"].IsChecked -eq $true
    } -ScriptBlock {
        param($isoPath, $DriveLetter, $WimPath, $workDir, $SelectedWimIndex, $SelectedEditionName, $AutounattendContent, $InjectDrivers)

        Invoke-WPFUIThread -ScriptBlock {
            $sync["WPFWin11ISOModifyButton"].IsEnabled = $false
        }
        $workingLabel = if ($InjectDrivers) { "正在修改 install.wim" } else { "正在准备安装介质" }
        Set-WinUtilISOStep -Step "Working" -Label $workingLabel

        $modified = $false
        try {
            Write-WinUtilISOLog "已选版本：$SelectedEditionName（索引 $SelectedWimIndex）"
            Write-WinUtilISOLog "正在创建工作目录：$workDir"

            $isoContents = Join-Path $workDir "iso_contents"
            New-Item -ItemType Directory -Path $isoContents -Force | Out-Null
            Step-WinUtilJob -Status "正在复制 ISO 内容..." -Percent 10

            Write-WinUtilISOLog "正在将 ISO 内容从 $DriveLetter 复制到 $isoContents..."
            Invoke-WinUtilRobocopy -Source $DriveLetter -Destination $isoContents -Arguments @("/E","/NFL","/NDL","/NJH","/NJS")
            Write-WinUtilISOLog "ISO 内容已复制。"
            Step-WinUtilJob -Status "正在准备安装介质..." -Percent 25

            $sourceImageFileName = Split-Path $WimPath -Leaf
            $localWim = Join-Path $isoContents "sources\$sourceImageFileName"
            if (-not (Test-Path $localWim)) {
                throw "未找到已复制的 ISO 映像文件：sources\$sourceImageFileName"
            }

            Write-WinUtilISOLog "正在写入 autounattend.xml 和版本选择..."
            $driversInjected = [ref]$false
            Invoke-WinUtilISOScript -ISOContentsDir $isoContents `
                -AutoUnattendXml $AutounattendContent `
                -InjectCurrentSystemDrivers $InjectDrivers `
                -InstallImagePath $localWim `
                -InstallImageIndex $SelectedWimIndex `
                -InstallEditionId (Get-WinUtilEditionIdFromName -EditionName $SelectedEditionName) `
                -Log {
                    param($m)
                    if ($m -like "Warning:*") {
                        # The job wrapper records WarningRecord output in the session log. Only
                        # append here to the ISO status control so the same warning is not doubled.
                        Write-WinUtilISOLog -Level "WARN" -Message $m -SkipSessionLog
                        Write-Warning $m
                    } else {
                        Write-WinUtilISOLog $m
                    }
                } `
                -DriversInjected $driversInjected

            if ($driversInjected.Value) {
                Step-WinUtilJob -Status "正在完成安装映像..." -Percent 70
                Write-WinUtilISOLog "已将当前系统的驱动程序添加到 $sourceImageFileName 索引 $SelectedWimIndex。"
            } elseif ($InjectDrivers) {
                Step-WinUtilJob -Status "正在保留安装映像..." -Percent 70
                Write-WinUtilISOLog "未向 $sourceImageFileName 索引 $SelectedWimIndex 注入任何当前系统的驱动程序；install.wim 保持原样。请查看警告日志条目了解详情。"
            } else {
                Step-WinUtilJob -Status "正在保留安装映像..." -Percent 70
                Write-WinUtilISOLog "已保留原始 $sourceImageFileName，未进行挂载、导出或修改。"
            }

            Step-WinUtilJob -Status "正在卸载源 ISO..." -Percent 80
            Write-WinUtilISOLog "正在卸载原始 ISO..."
            Dismount-DiskImage -ImagePath $isoPath

            $sync["Win11ISOWorkDir"]     = $workDir
            $sync["Win11ISOContentsDir"] = $isoContents

            Step-WinUtilJob -Status "修改完成" -Percent 100
            Write-WinUtilISOLog "install.wim 修改完成。请在最后一步选择输出方式。"

            Set-WinUtilISOStep -Step "Output"
            $modified = $true
        } catch {
            Write-WinUtilISOLog -Level "ERROR" -Message "修改失败：$_"
            $_.Exception.Data["WinUtilErrorReported"] = $true

            Show-WinUtilMessage -Message "修改 install.wim 时发生错误：`n`n$_" -Title "修改出错" -Button "OK" -Icon "Error" | Out-Null

            throw
        } finally {
            # BeginStop bypasses catch, so cleanup for both failures and user cancellation has
            # to live in finally.
            if (-not $modified) {
                try {
                    $mountedISO = Get-DiskImage -ImagePath $isoPath
                    if ($mountedISO -and $mountedISO.Attached) {
                        Write-WinUtilISOLog "正在清理：卸载源 ISO..."
                        Dismount-DiskImage -ImagePath $isoPath
                    }
                } catch { Write-WinUtilISOLog -Level "WARN" -Message "清理期间无法卸载 ISO：$_" }

                try {
                    if (Test-Path $workDir) {
                        Write-WinUtilISOLog "正在清理：删除临时目录 $workDir..."
                        Remove-Item -Path $workDir -Recurse -Force
                    }
                } catch { Write-WinUtilISOLog -Level "WARN" -Message "清理期间无法删除临时目录：$_" }

                $sync["Win11ISOImageInfo"] = $null
                $sync["Win11ISODriveLetter"] = $null
                $sync["Win11ISOWimPath"] = $null
                $sync["Win11ISOImagePath"] = $null
            }

            Invoke-WPFUIThread -Parameters @{ Modified = $modified } -ScriptBlock {
                param($Modified)

                $sync["WPFWin11ISOModifyButton"].IsEnabled = [bool]$Modified

                if ($sync["WPFWin11ISOWorkingSection"].IsSelected) {
                    Set-WinUtilISOStep -Step "Select"
                }
            }
        }
    }
}

function Invoke-WinUtilISOCheckExistingWork {
    if ($sync["Win11ISOContentsDir"] -and (Test-Path $sync["Win11ISOContentsDir"])) { return }

    # Nothing to resume while a modification is still producing the working directory. The tab
    # is initialized only once, so arrange another check rather than permanently missing work that
    # appears after this first call.
    if ($sync.ActiveJob) {
        if (-not $sync["Win11ISOExistingWorkRetryPending"]) {
            $sync["Win11ISOExistingWorkRetryPending"] = $true
            Invoke-WinUtilWhenIdle -DelayMilliseconds 500 -Callback {
                $sync["Win11ISOExistingWorkRetryPending"] = $false
                Invoke-WinUtilISOCheckExistingWork
            }
        }
        return
    }
    $sync["Win11ISOExistingWorkRetryPending"] = $false

    $existingWorkDir = Get-Item -Path (Join-Path $env:TEMP "WinUtil_Win11ISO*") |
        Where-Object { $_.PSIsContainer } | Sort-Object LastWriteTime -Descending | Select-Object -First 1

    if (-not $existingWorkDir) { return }

    $isoContents = Join-Path $existingWorkDir.FullName "iso_contents"
    if (-not (Test-Path $isoContents)) { return }

    $sync["Win11ISOWorkDir"]     = $existingWorkDir.FullName
    $sync["Win11ISOContentsDir"] = $isoContents

    Set-WinUtilISOStep -Step "Output"

    $modified = $existingWorkDir.LastWriteTime.ToString("yyyy-MM-dd HH:mm")
    Write-WinUtilISOLog "已找到现有工作目录：$($existingWorkDir.FullName)"
    Write-WinUtilISOLog "最后修改时间：$modified，已跳过前面的步骤，从输出步骤继续。"
    Write-WinUtilISOLog "如果要使用新的 ISO 重新开始，请点击 'Start Over'。"

    Show-WinUtilMessage -Message "发现上一次 WinUtil ISO 的工作目录：`n`n$($existingWorkDir.FullName)`n`n（最后修改时间：$modified）`n`n已恢复输出步骤，你可以保存已修改的映像。`n`n如果想重新开始，请点击那里的 'Start Over'。" -Title "发现未完成的工作" -Button "OK" -Icon "Info" | Out-Null
}

function Invoke-WinUtilISOCleanAndReset {
    $workDir = $sync["Win11ISOWorkDir"]

    if ($workDir -and (Test-Path $workDir)) {
        $confirm = Show-WinUtilMessage -Message "此操作将删除临时工作目录：`n`n$workDir`n`n并将界面重置到开始状态。`n`n是否继续？" -Title "重新开始" -Button "YesNo" -Icon "Warning"
        if ($confirm -ne "Yes") { return }
    }

    Start-WinUtilJob -Name "ISO cleanup" -Description "正在清理" -Parameters @{
        WorkDir = $workDir
    } -ScriptBlock {
        param($workDir)

        Invoke-WPFUIThread -ScriptBlock { $sync["WPFWin11ISOCleanResetButton"].IsEnabled = $false }
        Set-WinUtilISOStep -Step "Working" -Label "正在重新开始" -Reverse

        try {
            if ($workDir) {
                $mountDir = Join-Path $workDir "wim_mount"
                try {
                    $mountedImages = Get-WindowsImage -Mounted | Where-Object { $_.Path -like "$workDir*" }
                    if ($mountedImages) {
                        foreach ($img in $mountedImages) {
                            Write-WinUtilISOLog "正在卸载 WIM：$($img.Path)（放弃更改）..."
                            Step-WinUtilJob -Status "正在卸载 WIM 映像..." -Percent 3
                            Dismount-WindowsImage -Path $img.Path -Discard
                            Write-WinUtilISOLog "WIM 已成功卸载。"
                        }
                    } elseif (Test-Path $mountDir) {
                        Write-WinUtilISOLog "Get-WindowsImage 未报告已挂载的 WIM。作为预防措施正在运行 DISM /Cleanup-Wim..."
                        Step-WinUtilJob -Status "正在运行 DISM 清理..." -Percent 3
                        & dism /English /Cleanup-Wim | ForEach-Object { Write-WinUtilISOLog $_ }
                    }
                } catch {
                    Write-WinUtilISOLog -Level "WARN" -Message "无法干净地卸载 WIM，正在尝试 DISM /Cleanup-Wim 回退方案：$_"
                    try { & dism /English /Cleanup-Wim | ForEach-Object { Write-WinUtilISOLog $_ } }
                    catch { Write-WinUtilISOLog -Level "WARN" -Message "DISM /Cleanup-Wim 同样失败：$_" }
                }
            }

            if ($workDir -and (Test-Path $workDir)) {
                Write-WinUtilISOLog "正在扫描要删除的文件：$workDir"
                Step-WinUtilJob -Status "正在扫描文件..." -Percent 5

                $allFiles = @(Get-ChildItem -Path $workDir -File -Recurse -Force)
                $allDirs  = @(Get-ChildItem -Path $workDir -Directory -Recurse -Force |
                    Sort-Object { $_.FullName.Length } -Descending)
                $total   = $allFiles.Count
                $deleted = 0

                Write-WinUtilISOLog "找到 $total 个待删除文件。"

                foreach ($f in $allFiles) {
                    try { Remove-Item -Path $f.FullName -Force } catch { Write-WinUtilISOLog -Level "WARN" -Message "无法删除 $($f.FullName)：$_" }
                    $deleted++
                    if ($deleted % 100 -eq 0 -or $deleted -eq $total) {
                        $pct = [math]::Round(($deleted / [Math]::Max($total, 1)) * 85) + 5
                        Step-WinUtilJob -Status "正在删除 $($f.Directory.Name) 中的文件...（$deleted / $total）" -Percent $pct
                    }
                }

                foreach ($d in $allDirs) {
                    try { Remove-Item -Path $d.FullName -Force } catch { Write-WinUtilISOLog -Level "WARN" -Message "无法删除 $($d.FullName)：$_" }
                }

                try { Remove-Item -Path $workDir -Recurse -Force } catch { Write-WinUtilISOLog -Level "WARN" -Message "无法删除临时目录 ${WorkDir}：$_" }

                if (Test-Path $workDir) {
                    Write-WinUtilISOLog -Level "WARN" -Message "$workDir 中的部分项目无法删除"
                } else {
                    Write-WinUtilISOLog "临时目录已成功删除。"
                }
            } else {
                Write-WinUtilISOLog "未找到临时目录，正在重置界面。"
            }

            Step-WinUtilJob -Status "正在重置界面..." -Percent 95
            Write-WinUtilISOLog "正在重置界面..."

            $sync["Win11ISOWorkDir"]     = $null
            $sync["Win11ISOContentsDir"] = $null
            $sync["Win11ISOImagePath"]   = $null
            $sync["Win11ISODriveLetter"] = $null
            $sync["Win11ISOWimPath"]     = $null
            $sync["Win11ISOImageInfo"]   = $null
            $sync["Win11ISOUSBDisks"]    = $null

            Invoke-WPFUIThread -ScriptBlock {
                $sync["WPFWin11ISOPath"].Text                    = "尚未选择 ISO…"
                $sync["WPFWin11ISOFileInfo"].Visibility          = "Hidden"
                $sync["WPFWin11ISOVerifyResultPanel"].Visibility = "Collapsed"
                $sync["WPFWin11ISOOptionUSB"].Visibility         = "Collapsed"
                $sync["WPFWin11ISODonePanel"].Visibility         = "Collapsed"
                $sync["WPFWin11ISOModifyButton"].IsEnabled       = $true
                $sync["WPFWin11ISOStatusLog"].Text               = "就绪。请先选择一个 Windows 11 ISO 以开始。"
                Set-WinUtilISOStep -Step "Select"
            }
            Step-WinUtilJob -Hide
        } finally {
            Invoke-WPFUIThread -ScriptBlock {
                $sync["WPFWin11ISOCleanResetButton"].IsEnabled = $true

                if ($sync["WPFWin11ISOWorkingSection"].IsSelected) {
                    Set-WinUtilISOStep -Step "Select"
                }
            }
        }
    }
}

function Invoke-WinUtilISOExport {
    $contentsDir = $sync["Win11ISOContentsDir"]

    if (-not $contentsDir -or -not (Test-Path $contentsDir)) {
        Show-WinUtilMessage -Message "未找到已修改的 ISO 内容，请先执行修改步骤。" -Title "尚未就绪" -Button "OK" -Icon "Warning" | Out-Null
        return
    }

    Add-Type -AssemblyName System.Windows.Forms

    $dlg = [System.Windows.Forms.SaveFileDialog]::new()
    $dlg.Title            = "保存已修改的 Windows 11 ISO"
    $dlg.Filter           = "ISO 文件 (*.iso)|*.iso"
    $dlg.FileName         = "Win11_Modified_$(Get-Date -Format 'yyyyMMdd').iso"
    $dlg.InitialDirectory = [System.Environment]::GetFolderPath("Desktop")

    if ($dlg.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { return }

    Start-WinUtilJob -Name "ISO export" -Description "正在生成 ISO" -Parameters @{
        ContentsDir = $contentsDir
        OutputISO   = $dlg.FileName
    } -ScriptBlock {
        param($contentsDir, $outputISO)

        Invoke-WPFUIThread -ScriptBlock { $sync["WPFWin11ISOChooseISOButton"].IsEnabled = $false }
        Set-WinUtilISOStep -Step "Working" -Label "正在生成 ISO 文件"

        try {
            $oscdimg = Get-WinUtilOscdimgPath
            if (-not $oscdimg) {
                Set-WinUtilISOStep -Step "Output"
                Show-WinUtilMessage -Message "无法找到或自动安装 oscdimg.exe。`n`n请手动安装：`n  winget install -e --id Microsoft.OSCDIMG`n`n或从以下位置安装 Windows ADK：`nhttps://learn.microsoft.com/windows-hardware/get-started/adk-install" -Title "oscdimg Not Found" -Button "OK" -Icon "Warning" | Out-Null
                throw "无法找到或自动安装 oscdimg.exe。"
            }

            Write-WinUtilISOLog "正在导出为 ISO：$outputISO"
            Step-WinUtilJob -Status "正在生成 ISO..." -Percent 10

            $bootData    = "2#p0,e,b`"$contentsDir\boot\etfsboot.com`"#pEF,e,b`"$contentsDir\efi\microsoft\boot\efisys.bin`""
            $oscdimgArgs = @("-m", "-o", "-u2", "-udfver102", "-bootdata:$bootData", "-l`"CTOS_MODIFIED`"", "`"$contentsDir`"", "`"$outputISO`"")

            Write-WinUtilISOLog "Running oscdimg..."

            $psi = [System.Diagnostics.ProcessStartInfo]::new()
            $psi.FileName               = $oscdimg
            $psi.Arguments              = $oscdimgArgs -join " "
            $psi.RedirectStandardOutput = $true
            $psi.RedirectStandardError  = $true
            $psi.UseShellExecute        = $false
            $psi.CreateNoWindow         = $true

            $proc = [System.Diagnostics.Process]::new()
            $proc.StartInfo = $psi

            # stderr is collected as it arrives rather than after the process exits. Reading it
            # last deadlocks: once the stderr pipe fills, oscdimg blocks on its write and stops
            # producing stdout, while this loop waits for stdout that will never come.
            $stderrLines = [System.Collections.ArrayList]::Synchronized([System.Collections.ArrayList]::new())
            $proc.EnableRaisingEvents = $true
            $errorHandler = Register-ObjectEvent -InputObject $proc -EventName ErrorDataReceived -Action {
                if ($EventArgs.Data) { $null = $Event.MessageData.Add($EventArgs.Data) }
            } -MessageData $stderrLines

            try {
                $proc.Start() | Out-Null
                $proc.BeginErrorReadLine()

                # Stream stdout line-by-line as oscdimg runs
                while (-not $proc.StandardOutput.EndOfStream) {
                    $line = $proc.StandardOutput.ReadLine()
                    if ($line.Trim()) { Write-WinUtilISOLog $line }
                }

                $proc.WaitForExit()
            } finally {
                Unregister-Event -SourceIdentifier $errorHandler.Name -ErrorAction SilentlyContinue
                $errorHandler | Remove-Job -Force -ErrorAction SilentlyContinue
            }

            foreach ($line in @($stderrLines)) {
                if ($line.Trim()) { Write-WinUtilISOLog -Level "WARN" -Message "[stderr]$line" }
            }

            if ($proc.ExitCode -ne 0) {
                throw "oscdimg 退出，代码为 $($proc.ExitCode)。请查看状态日志了解详情。"
            }

            Step-WinUtilJob -Status "ISO 已导出" -Percent 100
            Write-WinUtilISOLog "ISO 导出成功：$outputISO"
            Invoke-WPFUIThread -Parameters @{ OutputISO = $outputISO } -ScriptBlock {
                param($OutputISO)

                $sync["WPFWin11ISODoneLabel"].Text        = "ISO 已保存到 $OutputISO"
                $sync["WPFWin11ISODonePanel"].Visibility  = "Visible"
            }
            Set-WinUtilISOStep -Step "Output"
            Show-WinUtilMessage -Message "ISO 导出成功！`n`n$outputISO" -Title "导出完成" -Button "OK" -Icon "Info" | Out-Null
        } catch {
            Write-WinUtilISOLog -Level "ERROR" -Message "ISO 导出失败：$_"
            $_.Exception.Data["WinUtilErrorReported"] = $true
            Set-WinUtilISOStep -Step "Output"
            Show-WinUtilMessage -Message "ISO 导出失败：`n`n$_" -Title "错误" -Button "OK" -Icon "Error" | Out-Null
            throw
        } finally {
            Invoke-WPFUIThread -ScriptBlock {
                $sync["WPFWin11ISOChooseISOButton"].IsEnabled = $true

                # Cancellation skips catch, so the working page can still be up here
                if ($sync["WPFWin11ISOWorkingSection"].IsSelected) {
                    Set-WinUtilISOStep -Step "Output"
                }
            }
        }
    }
}

function Find-WinUtilOscdimg {
    <#
    .SYNOPSIS
        Looks for oscdimg.exe in every place it is known to land

    .DESCRIPTION
        PATH first, since that covers an ADK installed anywhere and a manual copy, then the
        default ADK location, then the per-user and machine-scope WinGet locations. Used both
        before and after the install attempt so the current process does not need a PATH refresh.
    #>

    $onPath = Get-Command oscdimg.exe -ErrorAction SilentlyContinue
    if ($onPath) { return $onPath.Source }

    foreach ($root in @(
            "${env:ProgramFiles(x86)}\Windows Kits",
            "$env:ProgramFiles\Windows Kits",
            "$env:LOCALAPPDATA\Microsoft\WinGet\Packages",
            "$env:ProgramFiles\WinGet\Packages")) {

        if (-not $root -or -not (Test-Path $root)) { continue }

        $found = Get-ChildItem $root -Recurse -Filter "oscdimg.exe" -ErrorAction SilentlyContinue |
                 Select-Object -First 1 -ExpandProperty FullName
        if ($found) { return $found }
    }

    foreach ($link in @(
            "$env:LOCALAPPDATA\Microsoft\WinGet\Links\oscdimg.exe",
            "$env:ProgramFiles\WinGet\Links\oscdimg.exe")) {
        if ($link -and (Test-Path -LiteralPath $link)) { return $link }
    }

    return $null
}

function Get-WinUtilOscdimgPath {
    <#
    .SYNOPSIS
        Returns the path to oscdimg.exe, installing it through winget when it is missing.
    #>

    $oscdimg = Find-WinUtilOscdimg
    if ($oscdimg) { return $oscdimg }

    Write-WinUtilISOLog "oscdimg.exe not found. Attempting to install via winget..."
    try {
        # First ensure winget is installed and operational
        Install-WinUtilWinget

        $winget = Get-Command winget
        $result = & $winget install -e --id Microsoft.OSCDIMG --accept-package-agreements --accept-source-agreements
        Write-WinUtilISOLog "winget 输出：$result"

        # The same search as before the install: winget honours a configured scope and package
        # root, so the file does not necessarily land under the per-user package directory
        $oscdimg = Find-WinUtilOscdimg
    } catch {
        Write-WinUtilISOLog -Level "WARN" -Message "winget 不可用或安装失败：$_"
    }

    if ($oscdimg) {
        Write-WinUtilISOLog "oscdimg.exe 安装成功。"
    } else {
        # The export caller turns this into the terminating, counted error. Keep this helper
        # context visible without recording the same missing executable as a second error.
        Write-WinUtilISOLog -Level "WARN" -Message "oscdimg.exe still not found after install attempt."
    }
    return $oscdimg
}
