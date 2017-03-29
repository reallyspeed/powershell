[CmdletBinding()]
#Param(
#$Command = $(Read-Host "Enter the script file"), 
#[Parameter(ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true)]$ObjectList
#$(Read-Host "Enter the script file")
param(
	[string]$serverip="127.0.0.1",
	[int]$port=15608,
	#[Parameter(Mandatory=$true)]
	[string]$username="u1"
)

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
		public void set (byte[] bytes)
		{
			this.x = BitConverter.ToInt16(bytes, 0);
			this.y = BitConverter.ToInt16(bytes, 2);			
		}
		public byte[] bytes()
		{
			byte[] r = new byte[4];
			BitConverter.GetBytes(this.x).CopyTo(r, 0);
			BitConverter.GetBytes(this.y).CopyTo(r, 2);
			return r;
		}
		public String toString()
		{
			return "(" + this.x + ", " + this.y + ")";
		}
	}

public class User
{
	public byte id;
	public String name;
	public point position;

	public User(byte id, String name)
	{
		this.id = id;
		this.name = name;
		this.position = new point();
	}
	public void SetPosition(Int16 x, Int16 y)
	{
		this.position.set(x, y);
	}
	public void Move(Int16 x, Int16 y)
	{
		this.position.x += x;
		this.position.y += y;
	}
	public String toString()
	{
		return "Player (" + this.id + ")\n  " + this.name + "\n  " + this.position.toString();
	}
}
"@
Add-Type -TypeDefinition $class_definition -Language CSharp 
Remove-Variable class_definition



[system.net.sockets.tcpclient] $global:client = $null
[system.net.sockets.NetworkStream] $global:server_stream = $null
$global:server_state = [hashtable]::Synchronized(@{'active'=$true})
$global:users = [hashtable]::Synchronized(@{})
$message_queue = [System.Collections.Queue]::Synchronized((New-Object System.collections.queue))
[User]$global:this_user = $null




$iss = [system.management.automation.runspaces.initialsessionstate]::CreateDefault()
$iss.ImportPSModule("PSThreading")
$iss.Variables.Add(
    (New-Object System.Management.Automation.Runspaces.SessionStateVariableEntry('server_state', $server_state, $null))
)
$iss.Variables.Add(
    (New-Object System.Management.Automation.Runspaces.SessionStateVariableEntry('message_queue', $message_queue, $null))
)
$iss.Variables.Add(
    (New-Object System.Management.Automation.Runspaces.SessionStateVariableEntry('users', $users, $null))
)
$rp = [runspacefactory]::CreateRunspacePool($iss)
$rp.Open()









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
			[console]::writeline("Searching for server at {0}:{1}", $server, $port)
			start-sleep -s 3
		}
	}
	
	$server_stream = $client.GetStream()
	$message = [text.Encoding]::Ascii.GetBytes($username)
	[byte]$length = [math]::min($message.length, 3)
	[console]::writeline("Username length: $length")
	#$length_bytes = [BitConverter]::GetBytes($length)
	#[console]::writeline("Username length bits: $length_bytes")

	$server_stream.write(@($length), 0, 1)
	$server_stream.write($message, 0, $length)
	$server_stream.flush()
	
	
	$id = New-Object byte[] 1
	$count = $server_stream.Read($id, 0, 1) # Blocking
	
	$global:client = $client
	$global:server_stream = $server_stream
	
	$global:this_user = new-object User($id[0], $username)
}





function StartMessageReceiver ()
{
	[console]::writeline("!!!!!!!!!!!!!!!!!!! Starting Message Receiver")
	$message_receive_loop =
	{
		param (
			[system.net.sockets.tcpclient] $client,
			[system.net.sockets.NetworkStream] $server_stream
		)
		
		$buff_size = $client.ReceiveBufferSize
		
		function ProcessMessage($type)
		{
			#while (!$server_stream.DataAvailable) {}
			#try
			#{
				switch($type)
				{
					0x01 { #state
						[console]::writeline("Reading Server State...")
						$message_size_bytes = New-Object byte[] 2
						$count = $server_stream.Read($message_size_bytes, 0, 2)
						#$message_size = [int16]$message_size_bytes
						#if count = 0
						$message_size = [BitConverter]::ToInt16($message_size_bytes, 0)
						[console]::writeline("Message Size: $message_size")
						$user_size = 5
						$true_message_size = $message_size * $user_size
						
						$message_bytes = New-Object byte[] $true_message_size
						$count = $server_stream.Read($message_bytes, 0, $true_message_size)
						[console]::writeline("Message: ($message_bytes)")

					}
					0x02 { #test
						[console]::writeline("Reading Type 2...")
						$message_size_bytes = New-Object byte[] 2
						$count = $server_stream.Read($message_size_bytes, 0, 2)
						#$message_size = [int16]$message_size_bytes
						#if count = 0
						$message_size = [BitConverter]::ToInt16($message_size_bytes, 0)
						[console]::writeline("Message Size: $message_size")
						
						
						$message_bytes = New-Object byte[] $message_size
						$count = $server_stream.Read($message_bytes, 0, $message_size)
						$message = [System.Text.Encoding]::ASCII.GetString($message_bytes[0..($message_size - 1)])
						[console]::writeline("Message: ($message)")

					}
					0xff { #disconnect
						[console]::writeline("Received Disconnect:")
						$message_size_bytes = New-Object byte[] 2
						$count = $server_stream.Read($message_size_bytes, 0, 2)
						$message_size = [BitConverter]::ToInt16($message_size_bytes, 0)
						
						$message_bytes = New-Object byte[] $message_size
						$count = $server_stream.Read($message_bytes, 0, $message_size)
						$message = [System.Text.Encoding]::ASCII.GetString($message_bytes)
						[console]::writeline("$message")
					}
					default {
						[console]::writeline("Unknown message type: $type")
						$byte_stream = New-Object byte[] $buff_size
						$count = $server_stream.Read($byte_stream, 0, $buff_size)
						#if count = 0
						write-host "BS: $byte_stream"
						$server_state['active'] = $false
						
					}
				}

			#} catch [Exception] {
			#	[console]::writeline("Connection Lost (Processing type $type): `n{0}" -f $_.Exception.Message)
			#	break
			#}

			
		}
		
		
		
		while ($server_state['active'])
		{
			if ($client.Connected)
			{
				if ($server_stream.DataAvailable)
				{
					#try
					#{
						[console]::writeline("!!! Data Available")
						
						$type = New-Object byte[] 1
						$count = $server_stream.Read($type, 0, 1) # Blocking
						
						ProcessMessage $type[0]
					#}
					#catch [Exception]
					#{
					#	[console]::writeline("Connection Lost (unable to get type): `n{0}" -f $_.Exception.Message)
					#	break
					#}
				
					#### DEBUG ################################
					#$server_state['active'] = $false
				}
			}
			else 
			{
				[console]::writeline("!!! Connection Closed.")
				$server_state['active'] = $false
				Break
			}
			
		}
		
		[console]::writeline("!!!!!!!!!!!!!!!!!!!!!!!!!!! Message Receiver Finishing")

	}
	
	$ps_message_receive = [PowerShell]::Create()
	$ps_message_receive.RunspacePool = $rp
	$ps_message_receive.AddScript($message_receive_loop) | out-null
	$ps_message_receive.AddParameters(@{client=$client; server_stream=$server_stream})
	
	$handle_message_receive = "" | select job, shell
	$handle_message_receive.shell = $ps_message_receive
	$handle_message_receive.job = $ps_message_receive.BeginInvoke()
	
	return $handle_message_receive

}
	

function ProcessSendMessage($type)
{
	switch($type)
	{
		0x11 {
			$message_bytes = New-Object byte[] 5
			$message_bytes[0] = 0x11
			[array]::copy($global:this_user.position.bytes(), 0, $message_bytes, 1, 4)
			[console]::writeline("Position Bytes: $message_bytes")
			$server_stream.Write($message_bytes, 0, 5)
		}
		0x12 {
			$message_bytes  = New-Object byte[] 3
			$message_bytes[0] = 0x12
			$message_bytes[1] = 0x01
			$message_bytes[2] = 0x02					
			[console]::writeline("Action 0x12: $message_bytes")
			$server_stream.Write($message_bytes, 0, 3)
		}
		0xff {
			$text = "Disconnect message"
			$text_bytes = ([text.encoding]::ASCII).GetBytes($text)
			[byte[]] $message_bytes = @(0xff)
			$message_bytes += [BitConverter]::GetBytes($text_bytes.count)
			$message_bytes += $text_bytes
			$server_stream.Write($messgae_bytes, 0, $message_bytes.count)
		}
		default {
			[console]::writeline("Unknown message type: $type")
			exit
		}
	}
}

function SendMessages()
{
	if ($message_queue.count -gt 0)
	{
		while ($message_queue.count -gt 0)
		{
			ProcessSendMessage $message_queue.Dequeue()
		}
		$server_stream.Flush()
	}
}

function Disconnect()
{
	[console]::writeline("Closing Client...")

	if ($server_stream.Socket.Connected) { $server_stream.Close() }
	if ($client.Connected) { $client.Close() }

	$handle_message_receive.shell.EndInvoke($handle_message_receive.job)
	$handle_message_receive.shell.Dispose()
	
	$rp.Close()
}



write-host "Sanity5"

$serverip = [system.net.IPAddress]::Parse($serverip)
Connect $username $port $serverip
write-host "Connected:" $this_user.id $this_user.name 

$handle_message_receive = StartMessageReceiver







while ($server_state['active'] -and $client.connected)
{
	start-sleep -s 1
	$this_user.Move(1, 1)
	$message_queue.Enqueue(0x11)
	[console]::writeline("Queue Length: {0}", $message_queue.count)
	SendMessages
}



Disconnect



[console]::writeline("END")





