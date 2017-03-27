[CmdletBinding()]

param(
	[int]$port=15608
)
Add-Type -AssemblyName System.Drawing



$users = [hashtable]::Synchronized(@{})
$clients = [hashtable]::Synchronized(@{})
$client_threads = [hashtable]::Synchronized(@{})
$remove_client_queue = [System.Collections.Queue]::Synchronized((New-Object System.collections.queue))
$client_message_queue = [System.Collections.Queue]::Synchronized((New-Object System.collections.queue))
$server_state = [hashtable]::Synchronized(@{active=$true})


$class_definition = @"
using System;

	public class point
	{
		public Int16 x;
		public Int16 y;
		public point(Int16 x, Int16 y)
		{
			this.x = x;
			this.y = y;
		}
		public point()
		{
			this.x = 0;
			this.y = 0;
		}
		public void set (Int16 x, Int16 y)
		{
			this.x = x;
			this.y = y;	
		}
		public String toString()
		{
			return "(" + this.x + ", " + this.y + ")";
		}
	}

public class User
{
	private static byte next_id = 1;
	public byte id;
	public String name;
	public point position;

	public User(String name)
	{
		this.id = next_id;
		next_id ++;
		this.name = name;
		this.position = new point();
	}
	public void SetPosition(Int16 x, Int16 y)
	{
		this.position.set(x, y);
	}
	public String toString()
	{
		return "Player (" + this.id + ")\n  " + this.name + "\n  " + this.position.toString();
	}
}
"@
Add-Type -TypeDefinition $class_definition -Language CSharp 
Remove-Variable class_definition



$iss = [system.management.automation.runspaces.initialsessionstate]::CreateDefault()
$iss.ImportPSModule("PSThreading")
$iss.Variables.Add(
    (New-Object System.Management.Automation.Runspaces.SessionStateVariableEntry('users', $users, $null))
)
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

	function StartMessageReceiver ($user_id)
	{
		[console]::writeline("!!!!!!!!!!!!!!!!!!! Starting Message Receiver for $user_id")
		$message_receive_loop =
		{
			$client = $clients[$user_id]
			$stream = $client.GetStream()
			$buff_size = $client.ReceiveBufferSize
			

			While ($server_state['active']) {
				[byte[]]$bytes = New-Object byte[] 200KB
				
				if ($client.Connected)
				{
					if ($stream.DataAvailable)
					{
						[console]::writeline("!!! Data Available")
						$return = $stream.Read($bytes, 0, $buff_size)
						
						If ($return -gt 0)
						{
							$message = [System.Text.Encoding]::ASCII.GetString($bytes[0..($return - 1)])
							$client_message_queue.Enqueue($message) #user_id, message
						} Else {       
							$remove_client_queue.Enqueue($user_id)
							[console]::writeline("!!! Read Timeout? Thread {0} added to remove queue" -f $user_id)
							Break
						}
					}
				}
				else 
				{           
					$remove_client_queue.Enqueue($user_id)
					[console]::writeline("!!! Connection Closed. Thread {0} added to remove queue" -f $user_id)
					Break
				}
			}
			
			[console]::writeline("!!!!!!!!!!!!!!!!!!!!!!!!!!! ($user_id) Message Receiver Finishing")
			

		}
		$runspace_message_receive = [RunSpaceFactory]::CreateRunspace()
		$runspace_message_receive.Open()
		$runspace_message_receive.SessionStateProxy.setVariable("clients", $clients)
		$runspace_message_receive.SessionStateProxy.setVariable("remove_client_queue", $remove_client_queue)
		$runspace_message_receive.SessionStateProxy.setVariable("client_message_queue", $client_message_queue)
		$runspace_message_receive.SessionStateProxy.setVariable("server_state", $server_state)
		$runspace_message_receive.SessionStateProxy.setVariable("user_id", $user_id)
		$shell_message_receive = [PowerShell]::Create()
		$shell_message_receive.Runspace = $runspace_message_receive
		$job = "" | select job, shell
		$job.shell = $shell_message_receive
		$job.job = $shell_message_receive.AddScript($message_receive_loop).BeginInvoke()
		$client_threads[$user_id] = $job                                          

	}


	function CreateConnection ($client)
	{
		$stream = $client.getstream()
		$username = ""
		[byte[]]$bytes = New-Object byte[] 3


		$return = $stream.Read($bytes, 0, 3)
		$username = [text.Encoding]::Ascii.GetString($bytes)
		
		[console]::writeline("New User {0}" -f $username)
		# Add client
		
		#Send connection message to client
		$stream.Write(@(0x00),0,1)
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
				[User] $user = new-object User -ArgumentList $username
				[console]::writeline("User ID: {0}" -f $user.id)
				$clients[$user.id] = $client
				$users[$user.id] = $user

				[console]::writeline("Created User: `n{0}" -f $user.toString())
				StartMessageReceiver $user.id
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


















function RemoveClient($user_id)
{
	[console]::writeline("Removing client: $user_id")
	$client_threads[$user_id].shell.EndInvoke($client_threads[$user_id].job)
    $client_threads[$user_id].shell.Runspace.Close()
    $client_threads[$user_id].shell.Dispose()
    $client_threads.Remove($user_id)

	if ($clients[$user_id].Connected)
	{
		if ($clients[$user_id].GetStream().Socket.Connected) { $clients[$user_id].GetStream().Close() }
		$clients[$user_id].Client.Shutdown([System.Net.Sockets.SocketShutdown]::Both)
	}
	$clients[$user_id].Close()
	$clients.Remove($user_id)


	$users.Remove($user_id)
	[console]::writeline("!!! [{0}] removed" -f $user_id)

}


function CheckRemoveClients()
{
	while ($remove_client_queue.Count -ne 0)
	{
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
	
	
	foreach ($user_id in $clients.keys)
	{
		$client = $clients[$user_id]

		if (-not $client.connected)
		{
			$remove_client_queue.Enqueue($user_id)
			[console]::writeline("$client dead: $user_id")
			continue
		}

		write-host "$user_id -> $message"
		$broadcast_stream = $client.GetStream()
		#$broadcast_bytes = ([text.encoding]::ASCII).GetBytes($message)
		
		#try{
			[console]::writeline("count: {0}" -f $users.count)
			[int16]$size = [int16]$users.count
			[console]::writeline("count: {0}" -f $size)
			$true_size = 3 + ($users.count) * 5
			[console]::writeline("count: {0}" -f $true_size)
			$byte_size = [BitConverter]::GetBytes($size)
			$bytes = new-object byte[] $true_size
			$bytes[0] = 0x01
			$bytes[1] = $byte_size[0]
			$bytes[2] = $byte_size[1]
			$i = 3
			foreach ($uid in $users.keys)
			{
				#if ($uid -eq $user_id) { continue }
				$bytes[$i++] = $uid
				$x = [BitConverter]::GetBytes($users[$uid].position.x)
				$y = [BitConverter]::GetBytes($users[$uid].position.x)
				$bytes[$i++] = $x[0]
				$bytes[$i++] = $x[1]
				$bytes[$i++] = $y[0]
				$bytes[$i++] = $y[1]

			}
			[console]::writeline("Message Bytes: $bytes")
			$broadcast_stream.Write($bytes,0,$true_size)
			$broadcast_stream.Flush()
			[console]::writeline("--- Message Sent")
			continue


			[byte] $type = 0x01
			[console]::writeline("Type: $type")
			
			$message_bytes = ([text.encoding]::ASCII).GetBytes($message)
			[int16]$message_size = [int16]$message_bytes.Count
			$message_size_bytes = [BitConverter]::GetBytes($message_size)
			
			[console]::writeline("Message_size: $message_size")
			[console]::writeline("messgae_bytes: $message_bytes")
			
			$broadcast_stream.Write($type,0,1)
			$broadcast_stream.Write($message_size_bytes,0,2)
			$broadcast_stream.Write($message_bytes,0,$message_size)
			
		#} catch [Exception]{
		#	[console]::writeline("Unable to write to {0}: `n{1}", $user, $_.Exception.Message)
		#	$remove_client_queue.Enqueue($user_id)
		#}
	}
	
}





while ($clients.count -eq 0) {}

$i = 0
while ($true)
{
	write-host "Keys: " + $clients.keys
	foreach ($u in $clients.keys)
	{
		write-host $u
	}
	start-sleep -s 1
	BroadcastMessage "Message $i"
	$i++
	
	if ($i -gt 2)
	{
		$server_state['active'] = $false
		start-sleep -s 1
		BroadcastMessage "~~Disconnect"
		start-sleep -s 1
		RemoveAllCLients

		break
	}
}


$handle_listener.shell.EndInvoke($handle_listener.job)
$handle_listener.shell.Dispose()
$rp.Close()
[console]::writeline("END")










<# Send Message
			[byte] $type = 0x01
			[console]::writeline("Type: $type")
			
			$message_bytes = ([text.encoding]::ASCII).GetBytes($message)
			[int16]$message_size = [int16]$message_bytes.Count
			$message_size_bytes = [BitConverter]::GetBytes($message_size)
			
			[console]::writeline("Message_size: $message_size")
			[console]::writeline("messgae_bytes: $message_bytes")
			
			$broadcast_stream.Write($type,0,1)
			$broadcast_stream.Write($message_size_bytes,0,2)
			$broadcast_stream.Write($message_bytes,0,$message_size)
			
			$broadcast_stream.Flush()
			[console]::writeline("--- Message Sent")
#>

<# Mass Read
do
{
	$return = $stream.Read($bytes, 0, $bytes.length)
	$message += [text.Encoding]::Ascii.GetString($bytes[0..($return-1)])
} while ($stream.DataAvailable)
#>





<#
$broadcast_timer = New-Object Timers.Timer
$broadcast_timer.Enabled = $true
$broadcast_timer.Interval = 1000 




$broadcast_timer.start()
#>







