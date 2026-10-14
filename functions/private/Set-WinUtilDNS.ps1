function Set-WinUtilDNS {
    <#

    .SYNOPSIS
        Sets the DNS of all interfaces that are in the "Up" state. It will lookup the values from the DNS.Json file

    .PARAMETER DNSProvider
        The DNS provider to set the DNS server to

    .EXAMPLE
        Set-WinUtilDNS -DNSProvider "google"

    #>
    param($DNSProvider)

    if($DNSProvider -eq "Default") {
        Write-WinUtilLog -Component "DNS" -Message "DNS 提供商为默认值；未应用任何 DNS 更改。"
        return $true
    }

    if($DNSProvider -eq "Fastest") {
        Write-WinUtilLog -Component "DNS" -Message "正在通过延迟基准测试自动检测最快的 DNS 提供商..."
        $benchmark = Get-WinUtilDNSBenchmark
        $validFastest = $benchmark | Where-Object { $_.LatencyMs -lt 9999 } | Select-Object -First 1
        if ($validFastest) {
            $DNSProvider = $validFastest.Provider
            Write-Host "已自动选择最快的 DNS 提供商：$DNSProvider（$($validFastest.LatencyMs) 毫秒）"
            Write-WinUtilLog -Component "DNS" -Message "已自动选择最快的 DNS 提供商：$DNSProvider（$($validFastest.LatencyMs) 毫秒）"
        } else {
            Write-Warning "无法测量到任何提供商的 DNS 延迟；保留当前网络适配器的 DNS 设置。"
            Write-WinUtilLog -Component "DNS" -Message "基准测试超时或所有探测均失败；中止 DNS 更改以保留现有设置。"
            return $false
        }
    }

    try {
        $Adapters = Get-NetAdapter | Where-Object {$_.Status -eq "Up"}
        Write-Host "正在确保以下接口的 DNS 设置为 $DNSProvider："
        Write-Host $($Adapters | Out-String)
        Write-WinUtilLog -Component "DNS" -Message "正在将 $(@($Adapters).Count) 个活动适配器的 DNS 提供商设置为 $DNSProvider。"

        if($DNSProvider -ne "DHCP") {
            $dns = $sync.configs.dns.$DNSProvider
            if($null -eq $dns) {
                Write-Warning "在配置中找不到 DNS 提供商 $DNSProvider。"
                Write-WinUtilLog -Level "ERROR" -Component "DNS" -Message "在配置中找不到 DNS 提供商 $DNSProvider。"
                return $false
            }
        }

        $dohSupported = [bool](Get-Command Add-DnsClientDohServerAddress -ErrorAction SilentlyContinue)
        if ($DNSProvider -ne "DHCP" -and $dns.DohOnly -and -not $dohSupported) {
            Write-Warning "DNS 提供商 $DNSProvider 需要使用 DNS over HTTPS，但当前系统不支持。"
            Write-WinUtilLog -Level "ERROR" -Component "DNS" -Message "DNS 提供商 $DNSProvider 需要使用 DNS over HTTPS，但当前系统不支持。"
            return $false
        }

        $dnscacheBase = "HKLM:\System\CurrentControlSet\Services\Dnscache\InterfaceSpecificParameters"

        Foreach ($Adapter in $Adapters) {
            $interfaceParams = "$dnscacheBase\$($Adapter.InterfaceGuid)"

            if($DNSProvider -eq "DHCP") {
                Write-WinUtilLog -Component "DNS" -Message "正在将适配器 $($Adapter.Name)（ifIndex: $($Adapter.ifIndex)）的 DNS 重置为 DHCP。"
                Set-DnsClientServerAddress -InterfaceIndex $Adapter.ifIndex -ResetServerAddresses
                netsh interface ip set dnsservers name="$($Adapter.Name)" source=dhcp
                netsh interface ipv6 set dnsservers name="$($Adapter.Name)" source=dhcp

                $dohInterfaceSettings = "$interfaceParams\DohInterfaceSettings"
                if (Test-Path $dohInterfaceSettings) {
                    if ($dohSupported) {
                        $dohServerAddresses = @(
                            Get-ChildItem -Path "$dohInterfaceSettings\Doh" -ErrorAction SilentlyContinue
                            Get-ChildItem -Path "$dohInterfaceSettings\Doh6" -ErrorAction SilentlyContinue
                        ) | Select-Object -ExpandProperty PSChildName -Unique

                        foreach ($ip in $dohServerAddresses) {
                            if (Get-DnsClientDohServerAddress -ServerAddress $ip -ErrorAction SilentlyContinue) {
                                Write-WinUtilLog -Component "DNS" -Message "正在移除 $ip 的 DoH 注册。"
                                Remove-DnsClientDohServerAddress -ServerAddress $ip -Confirm:$false -ErrorAction Stop
                            }
                        }
                    }

                    Remove-Item -Path $dohInterfaceSettings -Recurse -Force -ErrorAction SilentlyContinue
                }
            } else {
                $ipv4Addresses = @(@($dns.Primary, $dns.Secondary) | Where-Object { $_ })
                $ipv6Addresses = @(@($dns.Primary6, $dns.Secondary6) | Where-Object { $_ })

                if ($dohSupported -and $dns.DohTemplate) {
                    try {
                        $ips = @($dns.Primary, $dns.Secondary, $dns.Primary6, $dns.Secondary6) | Where-Object { $_ }
                        foreach ($ip in $ips) {
                            $dohTemplate = if ($dns.SecondaryDohTemplate -and @($dns.Secondary, $dns.Secondary6) -contains $ip) {
                                $dns.SecondaryDohTemplate
                            } else {
                                $dns.DohTemplate
                            }
                            $existing = Get-DnsClientDohServerAddress -ServerAddress $ip -ErrorAction SilentlyContinue
                            if ($existing) {
                                Set-DnsClientDohServerAddress -ServerAddress $ip -DohTemplate $dohTemplate -AllowFallbackToUdp $false -AutoUpgrade $true -ErrorAction Stop
                            } else {
                                Write-WinUtilLog -Component "DNS" -Message "正在注册 $ip 的 DoH 模板。"
                                Add-DnsClientDohServerAddress -ServerAddress $ip -DohTemplate $dohTemplate -AllowFallbackToUdp $false -AutoUpgrade $true -ErrorAction Stop
                            }

                            $leaf = if ($ip.Contains(':')) { 'Doh6' } else { 'Doh' }
                            $regPath = "$interfaceParams\DohInterfaceSettings\$leaf\$ip"

                            if (-not (Test-Path $regPath)) {
                                New-Item -Path $regPath -Force -ErrorAction Stop | Out-Null
                            }
                            New-ItemProperty -Path $regPath -Name "DohFlags" -Value 1 -PropertyType QWord -Force -ErrorAction Stop | Out-Null
                        }
                    } catch {
                        if ($dns.DohOnly) {
                            throw
                        }

                        Write-Warning "DNS 提供商 $DNSProvider 的 DNS over HTTPS 设置失败；继续使用普通 DNS。"
                        Write-WinUtilLog -Level "WARN" -Component "DNS" -Message "DNS 提供商 $DNSProvider 的 DNS over HTTPS 设置失败；继续使用普通 DNS：$($psitem.Exception.Message)"
                    }
                }

                Write-WinUtilLog -Component "DNS" -Message "正在将适配器 $($Adapter.Name)（ifIndex: $($Adapter.ifIndex)）的 IPv4 DNS 设置为 $($dns.Primary), $($dns.Secondary)。"
                Set-DnsClientServerAddress -InterfaceIndex $Adapter.ifIndex -ServerAddresses $ipv4Addresses -ErrorAction Stop
                Write-WinUtilLog -Component "DNS" -Message "正在将适配器 $($Adapter.Name)（ifIndex: $($Adapter.ifIndex)）的 IPv6 DNS 设置为 $($dns.Primary6), $($dns.Secondary6)。"
                Set-DnsClientServerAddress -InterfaceIndex $Adapter.ifIndex -ServerAddresses $ipv6Addresses -ErrorAction Stop
            }
        }
        if ($DNSProvider -ne "DHCP" -and $dohSupported -and $dns.DohTemplate) {
            Clear-DnsClientCache
        }
        Write-WinUtilLog -Component "DNS" -Message "DNS 提供商更改已完成：$DNSProvider"
        return $true
    } catch {
        Write-Warning "DNS 提供商 $DNSProvider 因发生错误而未能完成设置。"
        Write-Warning $psitem.Exception.Message
        Write-WinUtilLog -Level "ERROR" -Component "DNS" -Message "DNS 提供商 $DNSProvider 未能完成设置：$($psitem.Exception.Message)"
        return $false
    }
}
