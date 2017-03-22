[CmdletBinding()]
#Param(
#$Command = $(Read-Host "Enter the script file"), 
#[Parameter(ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true)]$ObjectList
#$(Read-Host "Enter the script file")
param(
	[string]$serverip="127.0.0.1",
	[int]$port=15608,
	#[Parameter(Mandatory=$true)]
	[string]$username="user1"
)







function Connect ($username, $port, $server) {
	# Create IP Endpoint 
	#$endpoint = New-Object System.Net.IPEndPoint $address, $port 
	# Create Socket 
	write-host connecting to $server`:$port
	$endpoint = new-object System.Net.IPEndPoint ([System.Net.ipaddress]::any, $null)
	#$client = New-Object System.Net.Sockets.TcpClient $server, $port
	$client = [net.sockets.tcpclient]$endpoint
	
	while (!$client.connected)
	{
		try{
			$client.connect($server, $port)
			break
		}catch{
			start-sleep -s 2
			write-host "Searching for server..."
		}
	}
	
	
	$Global:server_stream = $client.GetStream()
	$message = [text.Encoding]::Ascii.GetBytes($username)
	
	$server_stream.write($message, 0, $message.length)
	$server_stream.flush()
	
	while ($client.connected) # Detects disconnect on message send failed
	{
		
		if ($server_stream.DataAvailable)
		{
			#try{
				
				$buff_size = $client.ReceiveBufferSize
				$type = New-Object byte[] 1
				$count = $server_stream.Read($type, 0, 1) # Blocking
				write-host "T: $type"
				$b = [byte[]]($type[0], 0x00)
				$t = [BitConverter]::ToInt16($b, 0)
				write-host "Type: $t"
				
				$byte_stream = New-Object byte[] 2
				$count = $server_stream.Read($byte_stream, 0, 2) # Blocking
				write-host "BS: $byte_stream"
				$x = [BitConverter]::ToInt16($byte_stream, 0)
				write-host "Value: $x"
				
				
				#$count = $server_stream.Read($byte_stream, 0, $buff_size) # Blocking
				
				If ($count -gt 0)
				{
					#$response = [System.Text.Encoding]::ASCII.GetString($byte_stream[0..($count - 1)])
					<#
					write-host $response
					if ($response -eq "~~Disconnect")
					{
						[console]::writeline("Disconnect Message Received")
						break
					}#>
				}
				else
				{
					[console]::writeline("Connection Lost: Empty Response ($response)")
					break
				}
			<#}catch [Exception]{
				[console]::writeline("Connection Lost: `n{0}" -f $_.Exception.Message)
				break
			}#>
		}

		
		### DEBUG ###########
		#break
		
		
	}
	
	
	
	$server_stream.Dispose()
	$client.Dispose()
	exit
	
}



write-host "Sanity2"

$serverip = [system.net.IPAddress]::Parse($serverip) 
Connect $username $port $serverip






<#}>
			catch
			{
				#Connection to server has been closed                            
				write-host "Connection closed..."
				write-host $_.exception.message
				write-host $_.exception.itemname
				Break
			}#>



<#

	while(($i = $stream.Read($bytes, 0, $bytes.Length)) -ne 0)
	{
		$bytes[0..($i-1)]|%{$_}
		if ($Echo)
		{
			$stream.Write($bytes,0,$i)
		}
	}











	$saddrf   = [System.Net.Sockets.AddressFamily]::InterNetwork 
	$stype    = [System.Net.Sockets.SocketType]::Dgram 
	$ptype    = [System.Net.Sockets.ProtocolType]::UDP 
	$sock     = New-Object System.Net.Sockets.Socket $saddrf, $stype, $ptype 
	$sock.TTL = 26 
	
	$sock.bind($endpoint)

	write-host Listening on port $port
	$sock.listen()











	#$client = $sock.accepttcpclient()

	If ($client -ne $Null) {
		$stream = $client.GetStream()
		Do {
			#Write-Host 'Processing Data'
			Write-Verbose ("Bytes Left: {0}" -f $Client.Available)
			$Return = $stream.Read($byte, 0, $byte.Length)
			$String += [text.Encoding]::Ascii.GetString($byte[0..($Return-1)])
           	} While ($stream.DataAvailable)
	}
	
	
	
	
	
	$reader = New-Object System.IO.StreamReader $stream
	do {

		$line = $reader.ReadLine()
		write-host $line -fore cyan
	} while ($line -and $line -ne ([char]4))


	$reader.Dispose()
	$stream.Dispose()
	$client.Dispose()
	$listener.stop()
#>


<#
	$saddrf   = [System.Net.Sockets.AddressFamily]::InterNetwork 
	$stype    = [System.Net.Sockets.SocketType]::Dgram 
	$ptype    = [System.Net.Sockets.ProtocolType]::UDP 
	$sock     = New-Object System.Net.Sockets.Socket $saddrf, $stype, $ptype 
	$sock.TTL = 26 
	
	sock.connect($endpoint)
	
	# Create encoded buffer 
	$enc     = [System.Text.Encoding]::ASCII 
	$message = "test`n"*10 
	$buffer  = $Enc.GetBytes($Message)
#>









