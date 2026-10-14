function Set-WinUtilRegistry {
    <#

    .SYNOPSIS
        Modifies the registry based on the given inputs

    .PARAMETER Name
        The name of the key to modify

    .PARAMETER Path
        The path to the key

    .PARAMETER Type
        The type of value to set the key to

    .PARAMETER Value
        The value to set the key to

    .EXAMPLE
        Set-WinUtilRegistry -Name "PublishUserActivities" -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" -Type "DWord" -Value "0"

    #>
    param (
        $Name,
        $Path,
        $Type,
        $Value
    )

    try {
        if(!(Test-Path 'HKU:\')) {New-PSDrive -PSProvider Registry -Name HKU -Root HKEY_USERS | Out-Null}

        If (!(Test-Path $Path)) {
            Write-Host "未找到 $Path，正在创建..."
            Write-WinUtilLog -Component "Registry" -Message "正在创建注册表路径：$Path"
            New-Item -Path $Path -Force -ErrorAction Stop | Out-Null
        }

        if ($Value -ne "<RemoveEntry>") {
            Write-Host "已将 $Path\$Name 设置为 $Value"
            Write-WinUtilLog -Component "Registry" -Message "正在将 $Path\$Name ($Type) 设置为 $Value"
            Set-ItemProperty -Path $Path -Name $Name -Type $Type -Value $Value -Force -ErrorAction Stop | Out-Null
        }
        else{
            Write-Host "正在删除 $Path\$Name"
            Write-WinUtilLog -Component "Registry" -Message "正在删除 $Path\$Name"
            Remove-ItemProperty -Path $Path -Name $Name -Force -ErrorAction Stop | Out-Null
        }
    } catch [System.Security.SecurityException] {
        Write-Warning "由于安全异常，无法将 $Path\$Name 设置为 $Value。"
        Write-WinUtilLog -Level "ERROR" -Component "Registry" -Message "更改 $Path\$Name 为 $Value 时发生安全异常：`$($psitem.Exception.Message)"
    } catch [System.Management.Automation.ItemNotFoundException] {
        Write-Warning $psitem.Exception.ErrorRecord
        Write-WinUtilLog -Level "ERROR" -Component "Registry" -Message "更改 $Path\$Name 时未找到注册表项：`$($psitem.Exception.Message)"
    } catch [System.UnauthorizedAccessException] {
       Write-Warning $psitem.Exception.Message
       Write-WinUtilLog -Level "ERROR" -Component "Registry" -Message "更改 $Path\$Name 时未获授权：`$($psitem.Exception.Message)"
    } catch {
        Write-Warning "由于未处理的异常，无法设置 $Name。"
        Write-Warning $psitem.Exception.StackTrace
        Write-WinUtilLog -Level "ERROR" -Component "Registry" -Message "更改 $Path\$Name 时发生未处理的异常：`$($psitem.Exception.Message)"
    }
}
