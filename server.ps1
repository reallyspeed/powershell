[CmdletBinding()]

param(
	[int]$port=15608
)

$Global:clients = [hashtable]::Synchronized(@{})
$Global:client_threads = [hashtable]::Synchronized(@{})
$Global:remove_client_queue = [System.Collections.Queue]::Synchronized((New-Object System.collections.queue))
$Global:message_queue = [System.Collections.Queue]::Synchronized((New-Object System.collections.queue))


$broadcast_timer = New-Object Timers.Timer
$broadcast_timer.Enabled = $true
$broadcast_timer.Interval = 1000 


function print_error($message)
{
	write-host -foreground red -background darkblue $message

}


function create_connection ($client)
{
	$stream = $client.getstream()
	$username = ""
	[byte[]]$bytes = New-Object byte[] 5KB
	
	do
	{
		$return = $stream.Read($bytes, 0, $bytes.Length)
		$username += [text.Encoding]::Ascii.GetString($bytes[0..($return-1)])
	} while ($stream.DataAvailable)
	
	[console]::writeline($username)
	# Add client
	$clients[$username] = $client
	
	#Send list of online users to client
	$broadcast_stream = $client.GetStream()
	$broadcast_bytes = ([text.encoding]::ASCII).GetBytes("You are connected")
	$broadcast_stream.Write($broadcast_bytes,0,$broadcast_bytes.Length)
	$broadcast_stream.Flush()
	
	
	
	$client_runspace = [RunSpaceFactory]::CreateRunspace()
	$client_runspace.Open()
	$client_runspace.SessionStateProxy.setVariable("clients", $clients)
	$client_runspace.SessionStateProxy.setVariable("client_messages", $message_queue)
	$client_runspace.SessionStateProxy.setVariable("remove_client_queue", $remove_client_queue)
	$client_runspace.SessionStateProxy.setVariable("username", $username)
	$client_shell = [PowerShell]::Create()
	$client_shell.Runspace = $client_runspace 
	$sb =
	{
		#Code to kick off client connection monitor and look for incoming messages.
		$client = $clients[$username]
		$stream = $client.GetStream()
		
		#While client is connected to server, check for incoming traffic
		While ($true) {                                              
			[byte[]]$bytes = New-Object byte[] 200KB
			$buff_size = $client.ReceiveBufferSize
			$return = $stream.Read($bytes, 0, $buff_size)  
			If ($return -gt 0)
			{
				$message = [System.Text.Encoding]::ASCII.GetString($bytes[0..($return - 1)])
				$message_queue.Enqueue($message)
			} Else {
				$clients.Remove($username)              
				$remove_client_queue.Enqueue($username)
				# Removing Client
				Break
			}
		}
		
		$client.client.shutdown([System.Net.Sockets.SocketShutdown]::Both)
		$client.dispose()
		$stream.dispose()

	}
	$job = "" | Select Job, PowerShell
	$job.PowerShell = $client_shell
	$job.job = $client_shell.AddScript($sb).BeginInvoke()
	$client_threads[$username] = $job                                          

}












$broadcast_timer.start()

# TODO Start remove queue monitor

<#
$Global:runspace_listener = [RunSpaceFactory]::CreateRunspace()
$runspace_listener.Open()
$runspace_listener.SessionStateProxy.setVariable("clients", $clients)
$runspace_listener.SessionStateProxy.setVariable("listener", $listener)
$runspace_listener.SessionStateProxy.setVariable("port", $port)
$Global:powershell_listener = [PowerShell]::Create()
$powershell_listener.Runspace = $runspace_listener

$listener_loop =
{
#>
	[console]::writeline("$port")
	$listener = [System.Net.Sockets.TcpListener]$port
	$listener.Server.SetSocketOption("Socket", "ReuseAddress", 1)
	$listener.Start()
	try{
		$listener.Start()
	}catch [Exception]{
		print_error ("Unable to start listener: `n{0}" -f $_.Exception.Message)
		exit
	}

	[console]::WriteLine("{0} >> Server Started on port {1}", (Get-Date).ToString(), $port)

	while ($true)
	{
		[console]::writeline("Listener: {0}" -f $listener.server)
		$client = $listener.AcceptTcpClient() # block until connection
		If ($client -ne $Null)
		{
			create_connection $client
		}
		else
		{
			[console]::writeline("Null Client.. .")
			break
		}
		
		### DEBUG #########################
		break
	}


	$listener.stop()
	exit

#}


#$Global:handle = $powershell_listener.AddScript($listener_loop).BeginInvoke()
	


start-sleep -s 10





























