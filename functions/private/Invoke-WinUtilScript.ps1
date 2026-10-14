function Invoke-WinUtilScript {
    <#

    .SYNOPSIS
        Invokes the provided scriptblock. Intended for things that can't be handled with the other functions.

    .PARAMETER Name
        The name of the scriptblock being invoked

    .PARAMETER scriptblock
        The scriptblock to be invoked

    .EXAMPLE
        $Scriptblock = [scriptblock]::Create({"Write-output 'Hello World'"})
        Invoke-WinUtilScript -ScriptBlock $scriptblock -Name "Hello World"

    #>
    param (
        $Name,
        [scriptblock]$scriptblock
    )

    try {
        Write-Host "正在运行 $Name 的脚本"
        Write-WinUtilLog -Component "Script" -Message "正在运行 $Name 的脚本"
        Invoke-Command $scriptblock -ErrorAction Stop
        Write-WinUtilLog -Component "Script" -Message "$Name 的脚本已执行完毕"
    } catch [System.Management.Automation.CommandNotFoundException] {
        Write-Warning "找不到指定的命令。"
        Write-Warning $PSItem.Exception.message
        Write-WinUtilLog -Level "ERROR" -Component "Script" -Message "运行 $Name 的脚本时找不到命令：`$($PSItem.Exception.Message)"
    } catch [System.Management.Automation.RuntimeException] {
        Write-Warning "发生了运行时异常。"
        Write-Warning $PSItem.Exception.message
        Write-WinUtilLog -Level "ERROR" -Component "Script" -Message "Runtime exception while running script for $Name`: $($PSItem.Exception.Message)"
    } catch [System.Security.SecurityException] {
        Write-Warning "发生了安全异常。"
        Write-Warning $PSItem.Exception.message
        Write-WinUtilLog -Level "ERROR" -Component "Script" -Message "运行 $Name 的脚本时发生安全异常：`$($PSItem.Exception.Message)"
    } catch [System.UnauthorizedAccessException] {
        Write-Warning "拒绝访问。你没有执行此操作的权限。"
        Write-Warning $PSItem.Exception.message
        Write-WinUtilLog -Level "ERROR" -Component "Script" -Message "运行 $Name 的脚本时被拒绝访问：`$($PSItem.Exception.Message)"
    } catch {
        # Generic catch block to handle any other type of exception
        Write-Warning "由于未处理的异常，无法运行 $Name 的脚本。"
        Write-Warning $psitem.Exception.StackTrace
        Write-WinUtilLog -Level "ERROR" -Component "Script" -Message "运行 $Name 的脚本时发生未处理的异常：`$($psitem.Exception.Message)"
    }

}
