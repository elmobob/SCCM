#Script Name:   RmvOldCmptrOjcbtsFrmSCCMListener_v01.ps1
#Scribe's name: Casey Smith
#Script Desc.:  This script will listen for the events cration and rename.  When a
#               file is created in the location "SearchDrive", the script wil open
#               the text file and read the contents of that file, an ID.  It will
#               then delete the file from the drive.  THe script will then attempt
#               to connect to SCCM.  Once the connection is created, it will enter
#               that connection and search for the ID found in the "SearchDrive".  If
#               found, then the results will be a resourceID that is associated with
#               a computer object and that computer object will be be deleted.  If
#               the computer isn't found, then nothing will happen.
#               The script must keep track of the search results.  It will then
#               disconnect from SCCM and remove the session.  The script will write
#               the results of the search /delete attempt  to a log file.  Finally,
#               the listener will then wait for another file to be created.  If a
#               file named "stop.txt" appears on the "SearchDrive", then the script
#               will end.
#####################################################################################
###
###  set variables: $SiteCode - line 31, $SiteServer line 32, $strSearchHere line 170  
###  Line 117 <sitecode> 
###  Line 120 <SiteServer>, 
###  Line 121 <sitecode> and <siteserver>
###  Line 159 <sitecode>
###  line 170 server share where txt files are being dropped by winpe ###  clients
###  Begin Function Section -
#####################################################################################
Function Connect-CMSite
{ # Retrieved From: https://sccmpowershell.com/function-to-connect-to-configuration-manager-site-using-powershell
   $SiteCode   = "<sitecode>"
   $SiteServer = "<SiteServer>"
 
   Import-Module $env:SMS_ADMIN_UI_PATH.Replace("\bin\i386", "\bin\ConfigurationManager.psd1")
   $CMDrive    = Get-PSDrive -Name $SiteCode -ErrorAction Ignore
 
   # Connect to CMDrive
   if ( $CMDrive )
   {
      Write-Host "PSDrive: $SiteCode already exists, changing current drive"
      Set-Location $SiteCode":"
   }
   else
   {
      Write-Host "PSDrive: $SiteCode does not exist, adding..."
      $i = 1
 
      Do
      {
         Write-Host "Loop $i"
         $NewDrive = New-PSDrive -Name $SiteCode -PSProvider "CMSite" -Root $SiteServer -Scope Global
         #$NewDrive = New-PSDrive -Cred $cred -Name $SiteCode -PSProvider "CMSite" -Root $SiteServer -Scope Global
         $i++
      } Until ( $NewDrive -ne $null -or $i -gt 10 )
 
      Set-Location $SiteCode":"
      if ( $NewDrive -eq $null ) { exit 1 } #unable to connect to SCCM, exit script
   }
}####################################################################################
Function Write-ToLog
{
    #This function will write to the log file.
    param([string[]]$ParameterName )

    $intMaxLogFileSize = 100KB
    $strLogFileHere    = "C:\windows\logs\SCCM_RmOldCmptrObjctsFrmSCCM.log"

    if ( ( test-path -Path $strLogFileHere ) -eq $false )
    {### log file doesn't exist or was renamed; make a new empty one with column headers
        Add-Content -Path $strLogFileHere -Value '"Date","Time","Computer","GUID","Action Taken"'
    }
    ### add new content to log file
    $strActions = $ParameterName -join ","
    Add-Content -Path $strLogFileHere -Value $strActions 

    if ( ( Get-ChildItem $strLogFileHere ).Length -gt $intMaxLogFileSize )
    {
        $strNewNameandExtension = Get-Date -UFormat "_%Y%m%dat%H%M.csv"
        $strNewName = $strLogFileHere.Replace(".log", $strNewNameandExtension )
        Rename-Item -Path $strLogFileHere -NewName $strNewName 
    }
}#####################################################################################
function isFileLocked([string]$Path)
{#Retrieved from: https://stackoverflow.com/questions/15951302/powershell-1-checking-if-a-file-is-already-in-use

    $oFile = New-Object System.IO.FileInfo $Path
    ### Make sure the path is good
    if ( ( Test-Path -Path $Path ) -eq $false )
    {
        #echo "Bad Path"
        return $false
    }
    #Try opening file
    $oStream = $oFile.Open([System.IO.FileMode]::Open, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
    if ( $oStream )
    {
        #echo "Got valid stream so file must not be locked"
        $oStream.Close()
        return $false
    }
    else
    {
        #echo "InValid stream so file is locked"
        return $true
    }
}####################################################################################
FUnction RemoveComputerFRomSCCM
{#This function will return a string that will say, "Device rmeoved from SCCM" OR
#"Device not foud in SCCM"
    param([string[]]$strID )
    
    #############################################################################
    ###
    ### Create Connection to SCCM session through remote session
    ### 
    #############################################################################
    Connect-CMSite
    #Set-location "<sitecode>:"
    $CM_SMBIOSGUID = $strID
    Write-Host "looking for device related to $strID"
    #$TrgtCmptrs    = ( Get-CimInstance -Namespace "root\sms\site_code" -ComputerName "<siteserver>" -Query "SELECT * FROM SMS_R_System WHERE SMBIOSGUID = '$CM_SMBIOSGUID'" ).Name
    $TrgtRsrcs = Get-CimInstance -Namespace "root\sms\site_<sitecode>" -ComputerName "<siteserver>" -Query "SELECT * FROM SMS_R_System WHERE SMBIOSGUID = '$CM_SMBIOSGUID'" 
    #retrieved from https://www.reddit.com/r/SCCM/comments/na4njv/getcmdevice_not_working_reliably/
    ForEach ( $TrgtRsrc in $TrgtRsrcs ) ##code in case ther are duplicate computer objects for one guid
    {
        if ( $TrgtRsrc -ne '' ) 
        {
            ################################################################
            ###
            ### if variable has data and it's not the "unknown Computer",
            ### then act on it, else device wasn't found
            ### 
            ################################################################

			$TrgtCmptr = $TrgtRsrc.Name
			
            $AryResults = @(
                Get-Date -UFormat %D
                #Get-Date -UFormat %T
				Get-Date -UFormat "%I:%M:%S %p"
                $TrgtCmptr
                $CM_SMBIOSGUID
                "Device found in SCCM and removed")

			Write-Host "Deleting $TrgtRsrc.Name"
            Remove-CMResource -ResourceID $TrgtRsrc.ResourceId -Force -Verbose
        }
        else
        {
            $AryResults = @(
                Get-Date -UFormat %D
                #Get-Date -UFormat %T
				Get-Date -UFormat "%I:%M:%S %p"
                "Not Found"
                $CM_SMBIOSGUID
                "Unable to remove as device not found")
        }
    }
    Set-location "C:\"   # disconnect from SCCM
    Remove-PSDrive "<sitecode>" # remove SCCM drive

return $AryResults
}
#####################################################################################
###
### End Function Section / Begin Main Script
### Initialize variables
###
#####################################################################################
$strSearchHere                 = "\\server\share" #"C:\tester"#
$intDelayinSeconds             = 10
# Create a FileSystemWatcher/Listerner Event
$watcher                       = New-Object System.IO.FileSystemWatcher
$watcher.Path                  = $strSearchHere
$watcher.Filter                = "*.txt"
$watcher.IncludeSubdirectories = $false
$watcher.EnableRaisingEvents   = $true
$action = {
    $path = $Event.SourceEventArgs.FullPath
    $stopfile = $watcher.Path + "\stop.txt"

    # Stop the script if the stop file is created
    if ( $path -eq $stopfile )
    {
        #Stop file found, exit
        Write-Host "Stop file detected. Exiting script."
        Get-Job | Remove-Job -force -ErrorAction Stop
        exit
    }
    else
    {   
        #############################################################################
        ###
        ### text file found; get ID, delete file, search for it in SCCM and delete if
        ### it exists, log results, remove job that is completed and has no more data
        ###
        #############################################################################
        $strID     = Get-Content -Path $path
        Remove-Item -Path $path -Force -ErrorAction Stop #if script stops, something is wrong
        $aryResult = RemoveComputerFRomSCCM $strID
        write-ToLog $aryResult
        #Not sure what hppens next, may not need to delete jobs and they still need to listen
    }
}

# Register an event that is triggered when a file is created or renamed
$creater = Register-ObjectEvent -InputObject $watcher -EventName Created -Action $action
$remover = Register-ObjectEvent -InputObject $watcher -EventName Renamed -Action $action
while ((Test-Path -Path $strSearchHere\stop.txt) -eq $false)
{
	$Files = Get-ChildItem -Path $strSearchHere -Filter "*.txt" | Select-Object -First 10
	ForEach ($File in $Files)
	{
		#If the script was restarted and the listener didn't pick up an text files
		#when it started up again, process them
		$bolFoundIt = $null
		$strID = Get-Content -Path $File.FullName
		Remove-Item -Path $File.FullName -Force -ErrorAction SilentlyContinue
		$aryResult = RemoveComputerFromSCCM $strID
		#If ($bolFoundIt -ne $null)
		#{ 
		write-ToLog $aryResult
		#}
	}
	Start-Sleep -Seconds $intDelayinSeconds
}