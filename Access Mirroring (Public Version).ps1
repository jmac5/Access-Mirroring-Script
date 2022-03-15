#Access Mirroring (Public Version)
#jmac@wpi.edu | 3/14/22

<#
$Logfile = "<path>\Mirror.log" #log files for troubleshooting or auditing. You may find them useful, I sure do!
 Function Write-log
 {
   Param ([string]$logstring)

    Add-content $Logfile -value $logstring
 }
 $time = Get-Date

 Write-log "#########################################################"
 Write-log "Access Mirroring entry for $time"
#>

<#--------------------------------------------README-------------------------------------------------------

The base functionality of this script, as written, is such:
- Check for users with 2 active badges in Lenel DB (MS SQL + PowerShell sqlcmd)
- Check access on those badges (MS SQL + PowerShell sqlcmd)
- If one badge has more access than another, get the access level ID, activate and deactivate dates, and apply it to the badge without the access using OpenAccess API.

Things you MUST change in this script for your org:
* DB Server name ($dbserver)
* OpenAccess server, or your primary OnGuard server ($AppServer:<portForAPI>). Port is 8080 by default in the script. 
* AppIDs within the headers for your environment/apps ($AppID)
  
You will also need the "sqlcmd" module installed for Powershell, which works with MS SQL DB Instances. 
If you run an Oracle DB, this script won't work (it may be serviceable to convert, but it is untested!)

When you get it working for your environment, add it to a scheduled task on a server, set to run as a service
account, so it will check periodically for problems. Having it check regularly will keep your environment in
good shape. The first run may take a long time, if there are lots of problems. That's OK. 

Other than that, have fun! **Always kick the tires on a test server or DB first!!** This script was developed with
my org's needs in mind, and yours may be different. I tried to comment on a lot of the functions, but some may 
still be confusing. I recommend debugging and stepping through while watching variables to figure out what 
may be going on, if you're lost. 
  
In the process of sanitizing this for public consumption, some things have been ripped out and replaced with generic placeholders. I highly suggest checking all the lines (there really aren't that many) for any leftover empty references before running.
  
Jim

#>

$dbserver = "<DB_server>\LENEL"
$AppID = "<app_ID_Here>"
$AppServer = "<appServer.your.domain>:8080"

$Credentials = IMPORT-CLIXML "<path_to_SecureCredentials.xml>" #We use a secure credential XML file to store the username and password for the OnGuard user querying the API. You could put them right in the body, but this is safer. 
$User = $Credentials.UserName
$Password = $Credentials.GetNetworkCredential().Password

################### AUTH TOKEN GENERATION #####################
[Net.ServicePointManager]::SecurityProtocol = "tls12"
$headers = @{
    'Content-Type' = "application/json"
    'Accept' = "application/json"
    'Application-Id' = "$AppID" #be sure to swap in your App ID here! 
}
$URI = "https://$AppServer/api/access/onguard/openaccess/authentication?version=1.0&queue=false" #server in the URI must be changed!
$body = "{`n `"user_name`": `"$User`",`n `"password`": `"$Password`"`n}" #this can also be stored in an xml and called with get-credential, but I was lazy here. 
[Net.ServicePointManager]::ServerCertificateValidationCallback = {$true}   
$token = Invoke-RestMethod -uri $URI -Method 'POST' -Headers $headers -Body $body | Select-Object -ExpandProperty session_token
################### END AUTH TOKEN GENERATION #####################

$empids = Invoke-Sqlcmd -ServerInstance $dbserver -Query "SELECT EMPID FROM [AccessControl].[dbo].[BADGE] WHERE ID > '0' AND ID < 99999 AND STATUS = '1'" #query OnGuard DB for EMPIDs with (hopefully) 1 active iCLASS badge. We used 0-99999 as our badge # range, feel free to change to yours.
$badgekeys = @()
$acclvls = @()
$List = @{}
$badge = @{}

foreach($empid in $empids) {
    $empid = $empid.Item(0)                                 #make empid useable
    $id = Invoke-Sqlcmd -ServerInstance $dbserver -Query "SELECT ID FROM [AccessControl].[dbo].[BADGE] WHERE EMPID = $empid AND ID > 99999" #our Employee IDs are the same as the Mag Stripe badge numbers, so this helped with filtering out badges and leaving only employee IDs.
    if($null -ne $id) {
        $id = $id.Item(0)
    $bk = Invoke-Sqlcmd -ServerInstance $dbserver -Query "SELECT BADGEKEY FROM [AccessControl].[dbo].[BADGE] WHERE EMPID = $empid AND STATUS = '1'" #we only care about active IDs
    $badgekeys = $badgekeys + $bk.ItemArray                 #make list of badgekeys, also make them readable
    if($badgekeys.Length -eq 2){                            #This catches cardholders with only one active badge. We need 2. Fixing that should be a different script.
        For($i=0; $i -lt ($badgekeys.Length); $i++) {       #for loop, over the number of badges (length of array, should be <= 2)
            $bkey = $badgekeys[$i]
            $acclvls = Invoke-Sqlcmd -ServerInstance $dbserver -Query "SELECT ACCLVLID FROM [AccessControl].[dbo].[BADGELINK] WHERE BADGEKEY = $bkey" #get a list of access levels on a given badge, using badgekey to filter.
            $List.add($i , $acclvls.ItemArray) #building hash tables to draw on later.
            $Badge.add($i, $bkey)   #building hash tables to draw on later.
        }
    }    
    if((($List[0]).Length -eq ($List[1]).Length) -and ($null -ne $list[0])) { #compare lists of access level IDs to check for disparities
        #I need to think of a better way to filter these results than an empty if clause. 
        #Write-Host "Hooray! The access matches on $id"              
    }
    elseif(($null -eq $list[0]) -and ($null -eq $list[1])) {
        #Write-Host "No access on $id, moving on"
    }
    else {
        $l0 = ($List[0]).Length     #$List[].Length correlates with number of access levels on the badge.
        $l1 = ($List[1]).Length
        $bkey0 = $badge[0]          #using $badgekeys[n] may be more efficient here
        $bkey1 = $badge[1]          #using $badgekeys[n] may be more efficient here
        $activate = $null
        $deactivate = $null
        if($l0 -gt $l1){
            $badge0 = (Invoke-Sqlcmd -ServerInstance $dbserver -Query "SELECT ID FROM [AccessControl].[dbo].[BADGE] WHERE BADGEKEY = $bkey0").Item(0) #this is purely for logging/troubleshooting, and could be removed to speed things up.
            Write-Host "$id has more access levels on $badge0" #this is purely for logging/troubleshooting, and could be removed to speed things up.
            Write-log "$id has more access levels on $badge0" #this is purely for logging/troubleshooting, and could be removed to speed things up.
            $List[0] | ForEach-Object {
                if ($List[1] -notcontains $_) {
                    #$descr = (Invoke-Sqlcmd -ServerInstance $dbserver -Query "SELECT DESCRIPT FROM [AccessControl].[dbo].[ACCESSLVL] WHERE ACCESSLVID = $_").Item(0)
                    #Write-Host "$bkey1 is missing $descr"
                    $activate = (Invoke-Sqlcmd -ServerInstance $dbserver -Query "SELECT ACTIVATE FROM [AccessControl].[dbo].[BADGELINK] WHERE ACCLVLID = $_ AND BADGEKEY = $bkey0").Item(0) -f "yyyy-MM-dd hh:mm:ss"
                    $deactivate = (Invoke-Sqlcmd -ServerInstance $dbserver -Query "SELECT DEACTIVATE FROM [AccessControl].[dbo].[BADGELINK] WHERE ACCLVLID = $_ AND BADGEKEY = $bkey0").Item(0) -f "yyyy-MM-dd hh:mm:ss"
                    if ($activate -ne "") { #if statements to filter out "" values. 
                        $activate = ([datetime]$activate).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss-00:00") #the UniversalTime bit here is key, or else the DST gets all messed up.
                    }
                    if ($deactivate -ne "") { #if statements to filter out "" values. 
                        $deactivate = ([datetime]$deactivate).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss-00:00") #the UniversalTime bit here is key, or else the DST gets all messed up.
                    }
                    ################### ADD ACCESS #####################
                    $headers2 = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
                    $headers2.Add("Content-Type", "application/json")
                    $headers2.Add("Accept", "application/json")
                    $headers2.Add("Application-Id", "$AppID") #be sure to swap in your App ID here! 
                    $headers2.Add("Session-Token","$token")
                    $body2 = "{`n    `"property_value_map`": {`n        `"ACCESSLEVELID`": `"$_`",`n        `"BADGEKEY`": `"$bkey1`",`n        `"ACTIVATE`": `"$activate`",`n        `"DEACTIVATE`": `"$deactivate`"`n    }`n}"

                    $response = Invoke-RestMethod "https://$AppServer/api/access/onguard/openaccess/instances?version=1.0&queue=false&type_name=Lnl_AccessLevelAssignment" -Method 'POST' -Headers $headers2 -Body $body2 #be sure to swap in your app server's name! 
                    $response | ConvertTo-Json
                    ################### END ADD ACCESS #####################
                    #Write-log "$badge1 Fixed for $id" #this is purely for logging/troubleshooting, and could be removed to speed things up.
                    #Write-Host "$badge1 Fixed! for $id" #this is purely for logging/troubleshooting, and could be removed to speed things up.
                }
            }
        }
        else {
            $badge1 = (Invoke-Sqlcmd -ServerInstance $dbserver -Query "SELECT ID FROM [AccessControl].[dbo].[BADGE] WHERE BADGEKEY = $bkey1").Item(0) #this is purely for logging/troubleshooting, and could be removed to speed things up.
            Write-Host "$id has more access levels on $badge1" #this is purely for logging/troubleshooting, and could be removed to speed things up.
            Write-log "$id has more access levels on $badge1" #this is purely for logging/troubleshooting, and could be removed to speed things up.
            $List[1] | ForEach-Object {
                if ($List[0] -notcontains $_) {
                    #$descr = (Invoke-Sqlcmd -ServerInstance $dbserver -Query "SELECT DESCRIPT FROM [AccessControl].[dbo].[ACCESSLVL] WHERE ACCESSLVID = $_").Item(0)
                    #Write-Host "$badge0 is missing $descr"
                    $activate = (Invoke-Sqlcmd -ServerInstance $dbserver -Query "SELECT ACTIVATE FROM [AccessControl].[dbo].[BADGELINK] WHERE ACCLVLID = $_ AND BADGEKEY = $bkey1").Item(0) -f "yyyy-MM-dd hh:mm:ss" #leave these here, might be necessary based on testing. 
                    $deactivate = (Invoke-Sqlcmd -ServerInstance $dbserver -Query "SELECT DEACTIVATE FROM [AccessControl].[dbo].[BADGELINK] WHERE ACCLVLID = $_ AND BADGEKEY = $bkey1").Item(0) -f "yyyy-MM-dd hh:mm:ss"
                    if ($activate -ne "") { #if statements to filter out "" values. 
                        $activate = ([datetime]$activate).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss-00:00") #the UniversalTime bit here is key, or else the DST gets all messed up.
                    }
                    if ($deactivate -ne "") { #if statements to filter out "" values. 
                        $deactivate = ([datetime]$deactivate).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss-00:00") #the UniversalTime bit here is key, or else the DST gets all messed up.
                    }
                    ################### ADD ACCESS #####################
                    $headers2 = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
                    $headers2.Add("Content-Type", "application/json")
                    $headers2.Add("Accept", "application/json")
                    $headers2.Add("Application-Id", "$AppID") #be sure to swap in your App ID here! 
                    $headers2.Add("Session-Token","$token")
                    $body2 = "{`n    `"property_value_map`": {`n        `"ACCESSLEVELID`": `"$_`",`n        `"BADGEKEY`": `"$bkey0`",`n        `"ACTIVATE`": `"$activate`",`n        `"DEACTIVATE`": `"$deactivate`"`n    }`n}"

                    $response = Invoke-RestMethod "https://$AppServer/api/access/onguard/openaccess/instances?version=1.0&queue=false&type_name=Lnl_AccessLevelAssignment" -Method 'POST' -Headers $headers2 -Body $body2 #be sure to change your app_server's name! 
                    $response | ConvertTo-Json
                    ################### END ADD ACCESS #####################
                    #Write-log "$badge0 Fixed for $id!" #this is purely for logging/troubleshooting, and could be removed to speed things up.
                    #Write-Host "$badge0 Fixed for $id!" #this is purely for logging/troubleshooting, and could be removed to speed things up.
                }
            }
        }
    }
    $List = @{}        #        
    $badgekeys = @()   #
    $acclvls = @()     #
    $badge = @{}       # bunch of cleanup on variables. There's probably a better way to do this, but it works.
    $badge0 = $null    #
    $badge1 = $null    #
    $id = $null        #
    }
}