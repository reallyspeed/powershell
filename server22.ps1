[CmdletBinding()]

param(
	[int]$port=15608
)
Add-Type -AssemblyName System.Drawing





$clients = [hashtable]::Synchronized(@{})
$new_clients = [hashtable]::Synchronized(@{})
$client_threads = [hashtable]::Synchronized(@{})
$remove_client_queue = [System.Collections.Queue]::Synchronized((New-Object System.collections.queue))
$client_message_queue = [System.Collections.Queue]::Synchronized((New-Object System.collections.queue))
$server_state = [hashtable]::Synchronized(@{active=$true})



$iss = [system.management.automation.runspaces.initialsessionstate]::CreateDefault()
$iss.ImportPSModule("PSThreading")
$iss.Variables.Add(
    (New-Object System.Management.Automation.Runspaces.SessionStateVariableEntry('clients', $clients, $null))
)
$iss.Variables.Add(
    (New-Object System.Management.Automation.Runspaces.SessionStateVariableEntry('client_threads', $client_threads, $null))
)
$iss.Variables.Add(
    (New-Object System.Management.Automation.Runspaces.SessionStateVariableEntry('remove_client_queue', $remove_client_queue, $null))
)
$iss.Variables.Add(
    (New-Object System.Management.Automation.Runspaces.SessionStateVariableEntry('client_message_queue', $client_message_queue, $null))
)
$iss.Variables.Add(
    (New-Object System.Management.Automation.Runspaces.SessionStateVariableEntry('server_state', $server_state, $null))
)

$rp = [runspacefactory]::CreateRunspacePool($iss)
$rp.Open()





$listener_script =
{
	param(
		$port
		)

	function StartMessageReceiver ($username)
	{
		[console]::writeline("!!!!!!!!!!!!!!!!!!! Starting Message Receiver for $username")
		$message_receive_loop =
		{
			$client = $clients[$username]
			$stream = $client.GetStream()
			$buff_size = $client.ReceiveBufferSize
			

			While ($server_state['active']) {
				[byte[]]$bytes = New-Object byte[] 200KB
				
				if ($client.Connected)
				{
					if (stream.DataAvailable)
					{
						[console]::writeline("!!! Data Available")
						$return = $stream.Read($bytes, 0, $buff_size)
						
						If ($return -gt 0)
						{
							$message = [System.Text.Encoding]::ASCII.GetString($bytes[0..($return - 1)])
							$client_message_queue.Enqueue($message)
						} Else {       
							$remove_client_queue.Enqueue($username)
							[console]::writeline("!!! Read Timeout? Thread {0} added to remove queue" -f $username)
							Break
						}
					}
				}
				else 
				{           
					$remove_client_queue.Enqueue($username)
					[console]::writeline("!!! Connection Closed. Thread {0} added to remove queue" -f $username)
					Break
				}
			}
			
			[console]::writeline("!!!!!!!!!!!!!!!!!!!!!!!!!!! ($username) Message Receiver Finishing")
			

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


	function CreateConnection ($client)
	{
		$stream = $client.getstream()
		$username = ""
		[byte[]]$bytes = New-Object byte[] 5KB

		do
		{
			$return = $stream.Read($bytes, 0, $bytes.Length)
			$username += [text.Encoding]::Ascii.GetString($bytes[0..($return-1)])
		} while ($stream.DataAvailable)
		
		[console]::writeline("New User {0}" -f $username)
		# Add client
		
		#Send connection message to client
		$broadcast_bytes = ([text.encoding]::ASCII).GetBytes("Connection Message")
		$stream.Write($broadcast_bytes,0,$broadcast_bytes.Length)
		$stream.Flush()
		return $username
	}
	

	[console]::writeline("Starting Server on port: $port")
	$listener = [System.Net.Sockets.TcpListener]$port
	#$listener.Server.SetSocketOption("Socket", "ReuseAddress", 1)
	$listener.Start()
	try{
		$listener.Start()
	}catch [Exception]{
		[console]::writeline("Unable to start listener: `n{0}" -f $_.Exception.Message)
		exit
	}

	[console]::WriteLine("{0} >> Server Started on port {1}", (Get-Date).ToString(), $port)

	while ($server_state['active'])
	{
		#[console]::WriteLine("Pending: {0}" -f $listener.Pending())
		#[console]::WriteLine("Server State: {0}" -f $server_state)
		if ($listener.Pending())
		{
			$client = $listener.AcceptTcpClient() # block until connection
			[console]::writeline("Accpeted Client")
			If ($client -ne $Null)
			{
				[console]::writeline("Connecting to Client.. .")
				$username = CreateConnection $client
				$clients[$username] = $client
				StartMessageReceiver $username
			}
			else
			{
				[console]::writeline("Null Client...")
				break
			}
		}
		else 
		{
			start-sleep -s 1
		}
		### DEBUG #########################
		
	}
	[console]::writeline("!!!!!!!!!!!!!!!!!!!!!!!!!!!!111 Stopping Listener")

	$listener.stop()

}

#$remove_client_queue.enqueue("toast")
[console]::writeline("Sanity3")



$ps_listener = [PowerShell]::Create()
$ps_listener.RunspacePool = $rp
$ps_listener.AddScript($listener_script) | out-null
$ps_listener.AddParameters(@{port=$port}) | out-null

$handle_listener = "" | select job, shell
$handle_listener.shell = $ps_listener
$handle_listener.job = $ps_listener.BeginInvoke()


















function RemoveClient($remove_user)
{
	$client_threads[$remove_user].shell.EndInvoke($client_threads[$remove_user].job)
    $client_threads[$remove_user].shell.Runspace.Close()
    $client_threads[$remove_user].shell.Dispose()
    $client_threads.Remove($remove_user)

	$clients[$remove_user].GetStream().Close() 
	if ($clients[$remove_user].Connected) {$clients[$remove_user].Client.Shutdown([System.Net.Sockets.SocketShutdown]::Both) }
	$clients[$remove_user].Close()
	$clients.Remove($remove_user)


	[console]::writeline("!!! [{0}] removed" -f $remove_user)

}


function CheckRemoveClients()
{
	while ($remove_client_queue.Count -ne 0)
	{
		[console]::writeline("Removing client...")
		RemoveClient $remove_client_queue.Dequeue()
		[console]::writeline("Removing client... Done")
	}
}


function RemoveAllClients()
{
	[console]::writeline("Remove All CLients")

	foreach($key in $($clients.keys))
	{
			RemoveClient $key
	}
}


function BroadcastMessage ($message)
{
	CheckRemoveClients
	
	
	#[Byte[]] $payload = 0x00,0x00,0x00,0x90
	foreach ($user in $clients.keys)
	{
		$client = $clients[$user]

		if (-not $client.connected)
		{
			$remove_client_queue.Enqueue($user)
			[console]::writeline("$client dead: $user")
			continue
		}

		write-host "$user -> $message"
		$broadcast_stream = $client.GetStream()
		#$broadcast_bytes = ([text.encoding]::ASCII).GetBytes($message)
		<#if (-not $broadcast_stream.socket.connected)
		{
			$remove_client_queue.Enqueue($user)
			[console]::writeline("broadcast stream dead: $user")
			continue
		}#>
		
		try{
			$d = [BitConverter]::GetBytes([int]11)
			[byte] $type = 0x05
			[byte[]] $data = $type, 0x0b, 0x00
			$broadcast_stream.Write($data,0,3)
			$broadcast_stream.Flush()
			#$broadcast_stream.Write($broadcast_bytes,0,$broadcast_bytes.Length)
		} catch [Exception]{
			[console]::writeline("Unable to write to {0}: `n{1}", $user, $_.Exception.Message)
		}
	}
	
}





while ($clients.count -eq 0) {}

$i = 0
while ($true)
{
	write-host $clients.count
	foreach ($u in $clients.keys)
	{
		write-host $u
	}
	start-sleep -s 1
	BroadcastMessage "Message $i"
	$i++
	
	if ($i -gt 3)
	{
		$server_state['active'] = $false
		start-sleep -s 1
		BroadcastMessage "~~Disconnect"
		start-sleep -s 1
		RemoveAllCLients
		$handle_listener.shell.EndInvoke($handle_listener.job)
		$handle_listener.shell.Dispose()

		break
	}
}

[console]::writeline("END")
<#
$handle_listener.PowerShell.EndInvoke($handle_listener)
$handle_listener.PowerShell.Runspace.Close()
$handle_listener.PowerShell.Dispose()
#>
















<#
$broadcast_timer = New-Object Timers.Timer
$broadcast_timer.Enabled = $true
$broadcast_timer.Interval = 1000 




$broadcast_timer.start()
#>








