function Invoke-WinUtilSSHServer {
    <#
    .SYNOPSIS
        Enables OpenSSH server to remote into your windows device
    #>

    # Install the OpenSSH Server feature if not already installed
    if ((Get-WindowsCapability -Name OpenSSH.Server -Online).State -ne "Installed") {
        Write-Host "正在启用 OpenSSH Server...这需要较长时间。"
        Add-WindowsCapability -Name OpenSSH.Server -Online
    }

    Write-Host "正在启动服务"

    Set-Service -Name sshd -StartupType Automatic
    Start-Service -Name sshd

    Set-Service -Name ssh-agent -StartupType Automatic
    Start-Service -Name ssh-agent

    #Adding Firewall rule for port 22
    Write-Host "正在设置防火墙规则"
    $firewallRule = Get-NetFirewallRule -Name 'sshd' -ErrorAction SilentlyContinue
    if ($null -eq $firewallRule) {
        New-NetFirewallRule -Name sshd -DisplayName 'OpenSSH Server (sshd)' -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22
        Write-Host "已为 OpenSSH Server 创建并启用防火墙规则。"
    } elseif ([int]$firewallRule.Enabled -eq 2) {
        Set-NetFirewallRule -Name 'sshd' -Enabled True
        Write-Host "已为 OpenSSH Server 启用防火墙规则。"
    }

    # An SSH logon for a member of the administrators group gets a full token
    # with no UAC prompt, so sshd reads administrator keys from a machine-wide
    # file that only Administrators and SYSTEM may write. WinUtil always runs
    # elevated, so the account being set up here is always an administrator.
    $sshProgramDataPath = Join-Path $env:ProgramData "ssh"
    $sshdConfigPath = Join-Path $sshProgramDataPath "sshd_config"
    $authorizedKeysPath = Join-Path $sshProgramDataPath "administrators_authorized_keys"
    $profileKeysPath = Join-Path $env:USERPROFILE ".ssh\authorized_keys"

    if (-not (Test-Path -Path $sshProgramDataPath)) {
        New-Item -Path $sshProgramDataPath -ItemType Directory -Force | Out-Null
    }

    # Earlier WinUtil versions commented out the administrators block in
    # sshd_config. Detect that state before restoring it, so administrator keys
    # already in use are carried over instead of silently stopping working.
    $configContent = if (Test-Path -Path $sshdConfigPath) { [string](Get-Content -Path $sshdConfigPath -Raw) } else { "" }
    $restoredContent = $configContent -replace '(?m)^# (Match Group administrators)$', '$1'
    $restoredContent = $restoredContent -replace '(?m)^# (\s+AuthorizedKeysFile __PROGRAMDATA__/ssh/administrators_authorized_keys)$', '$1'
    $configWasOverridden = $restoredContent -ne $configContent

    if (-not (Test-Path -Path $authorizedKeysPath)) {
        Write-Host "正在创建 administrators_authorized_keys 文件..."
        New-Item -Path $authorizedKeysPath -ItemType File -Force | Out-Null
        Write-Host "已在 $authorizedKeysPath 创建 administrators_authorized_keys 文件。"
    }

    if ($configWasOverridden -and (Test-Path -Path $profileKeysPath)) {
        $currentKeys = @(Get-Content -Path $authorizedKeysPath)
        $keysToMove = @(Get-Content -Path $profileKeysPath | Where-Object {
            $_.Trim() -and -not $_.TrimStart().StartsWith("#") -and $currentKeys -notcontains $_
        })

        if ($keysToMove.Count -gt 0) {
            Add-Content -Path $authorizedKeysPath -Value $keysToMove
            Write-Host "已将 $($keysToMove.Count) 个密钥从 $profileKeysPath 移动到 $authorizedKeysPath。"
        }
    }

    # sshd ignores the file unless inheritance is off and access is limited to
    # Administrators (S-1-5-32-544) and SYSTEM (S-1-5-18). SIDs keep this
    # working on localized installs, where the group names differ.
    $acl = Get-Acl -Path $authorizedKeysPath
    $acl.SetAccessRuleProtection($true, $false)
    foreach ($rule in @($acl.Access)) {
        [void]$acl.RemoveAccessRule($rule)
    }
    foreach ($sid in @("S-1-5-32-544", "S-1-5-18")) {
        [void]$acl.AddAccessRule([System.Security.AccessControl.FileSystemAccessRule]::new(
            [System.Security.Principal.SecurityIdentifier]::new($sid), "FullControl", "Allow"))
    }
    Set-Acl -Path $authorizedKeysPath -AclObject $acl

    if ($configWasOverridden) {
        Set-Content -Path $sshdConfigPath -Value $restoredContent -Force
        Write-Host "已在 sshd_config 中恢复管理员密钥文件设置。"
        Restart-Service -Name sshd -Force
    }

    Write-Host "OpenSSH 服务器已成功启用。"
    Write-Host "配置文件位于 $sshdConfigPath"
    Write-Host "请将你的公钥添加到此文件 -> $authorizedKeysPath"
}
