[CmdletBinding()]

param(
	[int]$port=15608
)

$Global:clients = [hashtable]::Synchronized(@{})
$Global:client_threads = [hashtable]::Synchronized(@{})
$Global:remove_client_queue = [System.Collections.Queue]::Synchronized((New-Object System.collections.queue))
$Global:client_message_queue = [System.Collections.Queue]::Synchronized((New-Object System.collections.queue))
#$Global:listener = 


$broadcast_timer = New-Object Timers.Timer
$broadcast_timer.Enabled = $true
$broadcast_timer.Interval = 1000 


function print_error($message)
{
	write-host -foreground red -background darkblue $message

}












$broadcast_timer.start()

# TODO Start remove queue monitor


$Global:runspace_listener = [RunSpaceFactory]::CreateRunspace()
$runspace_listener.Open()
$runspace_listener.SessionStateProxy.setVariable("clients", $clients)
$runspace_listener.SessionStateProxy.setVariable("listener", $listener)
$runspace_listener.SessionStateProxy.setVariable("port", $port)
$runspace_listener.SessionStateProxy.setVariable("client_message_queue", $client_message_queue)
$runspace_listener.SessionStateProxy.setVariable("remove_client_queue", $remove_client_queue)
$runspace_listener.SessionStateProxy.setVariable("client_threads", $client_threads)
$Global:powershell_listener = [PowerShell]::Create()
$powershell_listener.Runspace = $runspace_listener

$listener_loop =
{

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
	
	function StartMessageReceiver ($username, $client)
	{
		$runspace_message_receive = [RunSpaceFactory]::CreateRunspace()
		$runspace_message_receive.Open()
		$runspace_message_receive.SessionStateProxy.setVariable("client", $client)
		$runspace_message_receive.SessionStateProxy.setVariable("clients", $clients)
		$runspace_message_receive.SessionStateProxy.setVariable("username", $username)
		$runspace_message_receive.SessionStateProxy.setVariable("client_message_queue", $client_message_queue)
		$runspace_message_receive.SessionStateProxy.setVariable("remove_client_queue", $remove_client_queue)
		$runspace_message_receive.SessionStateProxy.setVariable("client_threads", $client_threads)
		$shell_message_receive = [PowerShell]::Create()
		$shell_message_receive.Runspace = $runspace_message_receive 
		$message_receive_loop =
		{
			[console]::writeline("remove client queue $remove_client_queue")
			#Code to kick off client connection monitor and look for incoming messages.
			$stream = $client.GetStream()
			
			#While client is connected to server, check for incoming traffic
			While ($true) {                                              
				[byte[]]$bytes = New-Object byte[] 200KB
				$buff_size = $client.ReceiveBufferSize
				$return = $stream.Read($bytes, 0, $buff_size)  
				If ($return -gt 0)
				{
					$message = [System.Text.Encoding]::ASCII.GetString($bytes[0..($return - 1)])
					$client_message_queue.Enqueue($message)
				} Else {
					$clients.Remove($username)              
					$remove_client_queue.Enqueue($username)
					# Removing Client
					[console]::writeline("Thread {0} added to remove queue" -f $username)
					Break
				}
			}
			
			$client.client.shutdown([System.Net.Sockets.SocketShutdown]::Both)
			$client.dispose()
			$stream.dispose()
	
		}
		$job = "" | Select Job, PowerShell
		$job.PowerShell = $shell_message_receive
		$job.job = $shell_message_receive.AddScript($message_receive_loop).BeginInvoke()
		$client_threads[$username] = $job                                          
	
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

	while ($true)
	{
		$client = $listener.AcceptTcpClient() # block until connection
		[console]::writeline("Accpeted Client")
		If ($client -ne $Null)
		{
			[console]::writeline("Connecting to Client.. .")
			$username = CreateConnection $client
			$clients[$username] = $client
			StartMessageReceiver $username $client
		}
		else
		{
			[console]::writeline("Null Client...")
			break
		}
		
		### DEBUG #########################
		
	}


	$listener.stop()
	exit

}

#$remove_client_queue.enqueue("toast")
[console]::writeline("Sanity1")




$Global:handle_listener = $powershell_listener.AddScript($listener_loop).BeginInvoke()




function CheckRemoveClients()
{
	
	while ($remove_client_queue.count -ne 0)
	{
		$remove_user = $remove_client_queue.Dequeue()
		$client_threads[$remove_user].PowerShell.EndInvoke($client_threads[$remove_user].Job)
        $client_threads[$remove_user].PowerShell.Runspace.Close()
        $client_threads[$remove_user].PowerShell.Dispose()          
        $client_threads.Remove($remove_user)
		write-host "!!!$remove_user removed"
        #$Messagequeue.Enqueue("~D{0}" -f $remove_user)   
	}
	
}


function BroadcastMessage ($message)
{
	foreach ($user in $clients.keys)
	{
		$client = $clients[$user]
		write-host "Writing $message to $user"
		$broadcast_stream = $client.GetStream()
		$broadcast_bytes = ([text.encoding]::ASCII).GetBytes($message)
		$broadcast_stream.Write($broadcast_bytes,0,$broadcast_bytes.Length)
		$broadcast_stream.Flush()
	}
	
}




$i = 0
while ($true)
{
	write-host $clients.count
	foreach ($u in $clients.keys)
	{
		write-host $u
	}
	start-sleep -s 2
	CheckRemoveClients
	BroadcastMessage "Message {0}" -f $i
	$i++
}


$handle_listener.PowerShell.EndInvoke($client_threads[$remove_user].Job)
$handle_listener.PowerShell.Runspace.Close()
$handle_listener.PowerShell.Dispose()


























