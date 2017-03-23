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

$Global:client = new-object system.net.sockets.tcpclient()
$Global:server_stream = new-object system.net.sockets.NetworkStream()
$Global:server_state = [hashtable]::Synchronized(@{active=$true})




function Connect ($username, $port, $server)
{
	write-host connecting to $server`:$port
	$endpoint = new-object System.Net.IPEndPoint ([System.Net.ipaddress]::any, $null)
	$client = [net.sockets.tcpclient]$endpoint
	
	while (!$client.connected)
	{
		try{
			$client.connect($server, $port)
			break
		}catch{
			write-host "Searching for server at $server:$port"
			start-sleep -s 3
		}
	}
	
	$server_stream = $client.GetStream()
	$message = [text.Encoding]::Ascii.GetBytes($username)
	
	$server_stream.write($message, 0, $message.length)
	$server_stream.flush()
	
}


function StartMessageReceiver ()
{
	[console]::writeline("!!!!!!!!!!!!!!!!!!! Starting Message Receiver")
	$message_receive_loop =
	{
		function ProcessMessage($type, $stream)
		{
			while (!$server_stream.DataAvailable)
			{
				try
				{
					switch($type)
						1 {
							$byte_stream = New-Object byte[] 2
							$count = $server_stream.Read($byte_stream, 0, 2) # Blocking
							write-host "BS: $byte_stream"
							$x = [BitConverter]::ToInt16($byte_stream, 0)
							write-host "Value: $x"
		
						}
						5 {
							
						}
						default {
							[console]::writeline("Unknown message type: $type")
						}
						
				} catch [Exception] {
					[console]::writeline("Connection Lost (Processing type $type): `n{0}" -f $_.Exception.Message)
					break
				}

			}
		}
		
		$buff_size = $client.ReceiveBufferSize
		
		While ($server_state['active']) {
			
			if ($client.Connected)
			{
				if ($server_stream.DataAvailable)
				{
					try
					{
						[console]::writeline("!!! Data Available")
						$count = $server_stream.Read($bytes, 0, $buff_size)
						
						$type = New-Object byte[] 1
						$count = $server_stream.Read($type, 0, 1) # Blocking
						write-host "T: $type"
						
						ProcessMessage $type $server_stream
						If ($count -gt 0)
						{
							$message = [System.Text.Encoding]::ASCII.GetString($bytes[0..($return - 1)])
						} Else {
							[console]::writeline("!!! Read Timeout? Lost connection")
							Break
						}
					}
					catch [Exception]
					{
						[console]::writeline("Connection Lost (unable to get type): `n{0}" -f $_.Exception.Message)
						break
					}
				}
			}
			else 
			{
				[console]::writeline("!!! Connection Closed.")
				Break
			}
		}
		
		[console]::writeline("!!!!!!!!!!!!!!!!!!!!!!!!!!! Message Receiver Finishing")
		

	}
	
	$runspace_message_receive = [RunSpaceFactory]::CreateRunspace()
	$runspace_message_receive.Open()
	$runspace_message_receive.SessionStateProxy.setVariable("clients", $clients)
	$runspace_message_receive.SessionStateProxy.setVariable("remove_client_queue", $remove_client_queue)
	$runspace_message_receive.SessionStateProxy.setVariable("client_message_queue", $client_message_queue)
	$runspace_message_receive.SessionStateProxy.setVariable("server_state", $server_state)
	$runspace_message_receive.SessionStateProxy.setVariable("username", $username)
	$shell_message_receive = [PowerShell]::Create()
	$shell_message_receive.Runspace = $runspace_message_receive
	$job = "" | select job, shell
	$job.shell = $shell_message_receive
	$job.job = $shell_message_receive.AddScript($message_receive_loop).BeginInvoke()
	$client_threads[$username] = $job                                          

}
<#
function 
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
					$response = [System.Text.Encoding]::ASCII.GetString($byte_stream[0..($count - 1)])
					
					write-host $response
					if ($response -eq "~~Disconnect")
					{
						[console]::writeline("Disconnect Message Received")
						break
					}
				}
				else
				{
					[console]::writeline("Connection Lost: Empty Response ($response)")
					break
				}
			}catch [Exception]{
				[console]::writeline("Connection Lost: `n{0}" -f $_.Exception.Message)
				break
			}
		}

		
		### DEBUG ###########
		#break
		
		
	}
#>
	
	


write-host "Sanity2"

$serverip = [system.net.IPAddress]::Parse($serverip) 
Connect $username $port $serverip

while (client_state['active'])
{
	
}

$server_stream.Close()
$client.Close()
exit









