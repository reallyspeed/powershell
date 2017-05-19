#==============================================================
# Creates a rule to open an incomming port in the firewall.
#==============================================================

#$numberAsString = read-host "type an port number"
#$mynumber = [int]$numberAsString


$port1 = New-Object -ComObject HNetCfg.FWOpenPort

$port1.Port = 15608

$port1.Name = 'MyTestPort' # name of Port

$port1.Enabled = $true

$fwMgr = New-Object -ComObject HNetCfg.FwMgr

$profiledomain=$fwMgr.LocalPolicy.GetProfileByType(0)

$profiledomain.GloballyOpenPorts.Add($port1)