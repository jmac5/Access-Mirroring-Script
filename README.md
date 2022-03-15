# Access-Mirroring-Script
Script to mirror access across multiple badges in OnGuard using sqlcmd for Powershell, and the OpenAccess API

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
Jim
