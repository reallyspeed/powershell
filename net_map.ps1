$ping = New-Object System.Net.Networkinformation.ping
$h = 0
while ($h -lt 255)
{
	$ip = "172.20.6.$h"
	$pingresult = $ping.Send($ip)
	if ($pingresult.status -eq 'Success')
	{
		$name = [System.Net.DNS]::GetHostEntry($ip)
		
		$n = [string]$name.HostName
		write-host $ip $n
	}
	$h++
}
	
