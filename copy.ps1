$source = "C:\Users\David.Wilson\Desktop\test.txt"
$dest = "\\192.168.246.31\Users\David\Desktop\test.txt"
$user = "WIN8-TEST1\David"
$password = "admin33"


$session = new-PSSession -usessl -ComputerName 192.168.246.31 -credential $user
#Copy-Item -ToSession $session -Path "C:\Users\David.Wilson\Desktop\test.txt" -Destination "C:\Users\David\Desktop\test.txt" 