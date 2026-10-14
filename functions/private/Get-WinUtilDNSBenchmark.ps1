function Get-WinUtilDNSBenchmark {
    <#

    .SYNOPSIS
        Benchmarks neutral DNS providers by measuring TCP port 53 latency (RTT in ms) to determine the fastest DNS server.

    .PARAMETER TimeoutMs
        Maximum timeout in milliseconds for each connection test. Default is 1500ms.

    .OUTPUTS
        Array of PSCustomObjects containing Provider, PrimaryIP, and LatencyMs sorted by lowest latency.

    .EXAMPLE
        $results = Get-WinUtilDNSBenchmark
        $fastest = $results[0]

    #>
    [CmdletBinding()]
    param(
        [ValidateRange(1, 9998)]
        [int]$TimeoutMs = 1500
    )

    Write-WinUtilLog -Component "DNS" -Message "正在开始 DNS 延迟基准测试扫描（TCP 端口 53）..."

    $dnsConfigs = $sync.configs.dns
    if ($null -eq $dnsConfigs) {
        Write-Warning "在 `$sync.configs.dns 中找不到 DNS 配置。"
        Write-WinUtilLog -Level "ERROR" -Component "DNS" -Message "在 `$sync.configs.dns 中找不到 DNS 配置。"
        return @()
    }

    $results = [System.Collections.Generic.List[PSObject]]::new()

    foreach ($prop in $dnsConfigs.PSObject.Properties) {
        $providerName = $prop.Name
        $primaryIp = $prop.Value.Primary
        if (-not $primaryIp) { continue }

        # Providers must explicitly opt in so new filtering services are never auto-selected.
        if ($prop.Value.BenchmarkEligible -ne $true) {
            continue
        }

        $latency = 9999
        $client = $null
        try {
            $client = New-Object System.Net.Sockets.TcpClient
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            $asyncResult = $client.BeginConnect($primaryIp, 53, $null, $null)
            $success = $asyncResult.AsyncWaitHandle.WaitOne($TimeoutMs, $false)
            $stopwatch.Stop()

            if ($success) {
                $client.EndConnect($asyncResult)
                $latency = [int]$stopwatch.ElapsedMilliseconds
            } else {
                $latency = 9999
            }
        } catch {
            $latency = 9999
        } finally {
            if ($null -ne $client) {
                $client.Dispose()
            }
        }

        $results.Add([PSCustomObject]@{
            Provider  = $providerName
            PrimaryIP = $primaryIp
            LatencyMs = $latency
        })
    }

    $sortedResults = @($results | Sort-Object LatencyMs)
    if ($sortedResults.Count -gt 0 -and $sortedResults[0].LatencyMs -lt 9999) {
        $fastest = $sortedResults[0]
        Write-WinUtilLog -Component "DNS" -Message "DNS 基准测试完成。最快的中立提供商：$($fastest.Provider)（$($fastest.LatencyMs) 毫秒）"
    } else {
        Write-WinUtilLog -Component "DNS" -Message "DNS 基准测试完成。无法确定各提供商的延迟。"
    }

    return $sortedResults
}
