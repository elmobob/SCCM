#Script Name:   Client_drop_UUSIDTextFileToShare.ps1
#Scribe's name: Anibal Guzman
#Script Desc.:  This script will get the machines hardware Universal Unique ID, create a text file named with the ID and drop it on share, fill in the user, password and sharename, suggest compile to exe so that password is not cleartext launch in winpe
#####################################################################################
#get value of bios universal unique GUID
$uuid = (Get-CimInstance -Class Win32_ComputerSystemProduct).UUID

#credential stuff fill in user and pwrod
$User = "<domain\userid>"
$PWord = ConvertTo-SecureString -String '<YourPassword>' -AsPlainText -Force
$Credential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $User, $PWord
#map drive stuff
New-PSDrive -Name r -PSProvider FileSystem -Root "\\server\sharename" -Credential $Credential

#create file stuff
$filename = ($uuid + ".txt")
New-Item -Path r:\ -Name $filename -Value $uuid

#waiting until file is digested by server to unmap drive
while (Test-Path r:\$filename) { Start-Sleep 15}


#delete mapped drive stuff
net use r: /delete

exit