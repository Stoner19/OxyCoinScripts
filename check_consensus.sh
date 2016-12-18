## Version 0.9.2
#!/bin/bash

##  Read config file
CONFIGFILE=$(cat mrv_config.json)
SECRET=$( echo "$CONFIGFILE" | jq -r '.secret')
SRV1=$( echo "$CONFIGFILE" | jq -r '.srv1')
PRT=$( echo "$CONFIGFILE" | jq -r '.port')
PRTS=$( echo "$CONFIGFILE" | jq -r '.https_port')
pbk=$( echo "$CONFIGFILE" | jq -r '.pbk')
SERVERS=()
### Get servers array
size=$( echo "$CONFIGFILE" | jq '.servers | length') 
i=0

while [ $i -le $size ]    
do
	SERVERS[$i]=$(echo "$CONFIGFILE" | jq -r --argjson i $i '.servers[$i]')
    i=`expr $i + 1`
done
###
#########################

#Set text delay at 0
TXTDELAY=0

# Set colors
red=`tput setaf 1`
green=`tput setaf 2`
cyan=`tput setaf 6`
resetColor=`tput sgr0`

# Set Lisk directory
function ChangeDirectory(){
	cd ~
	cd ~/lisk-main  ## Set to your lisk directory if different
}

#---------------------------------------------------------------------------
# Looping while node is syncing blockchain 
# from Nerigal
function SyncState()
{
	result='true'
	while [[ -z $result || $result != 'false' ]]
	do
		date +"%Y-%m-%d %H:%M:%S || Blockchain syncing"
		result=$(curl --connect-timeout 3 -s "http://"$SRV1""$PRT"/api/loader/status/sync" | jq '.syncing')
		sleep 2
	done
	
	date +"%Y-%m-%d %H:%M:%S || Looks like blockchain is finished syncing."
}
#---------------------------------------------------------------------------


while true;
do
	## Get forging status of server
	FORGE=$(curl --connect-timeout 3 -s "http://"$SRV1""$PRT"/api/delegates/forging/status?publicKey="$pbk| jq '.enabled')
	if [[ "$FORGE" == "true" ]]; ## Only check log and try to switch forging if needed, if server is currently forging
	then
		## Get current server's height and consensus
		SERVERLOCAL=$(curl --connect-timeout 3 -s "http://"$SRV1""$PRT"/api/loader/status/sync")
		HEIGHTLOCAL=$( echo "$SERVERLOCAL" | jq '.height')
		CONSENSUSLOCAL=$( echo "$SERVERLOCAL" | jq '.consensus')
		
		## If consensus is less than 51 and we are forging soon, try a reload to get new peers
		## from Nerigal
		if ["$CONSENSUSLOCAL" -lt "51"];
		then
			delegates=$(curl --connect-timeout 3 -s "http://"$SRV1""$PRT"/api/delegates/getNextForgers" | jq '.delegates')
			echo "${red}Low consensus.  Looking for delegate forging soon matching $pbk${resetColor}"
			if [[ " ${delegates[@]} " =~ " ${pbk}" ]]; then
				echo "${red}You are forging soon, but your consensus is too low!${resetColor}"
				ChangeDirectory
				bash lisk.sh reload
				sleep 20
				SyncState
			fi
		fi
		
		## Check log for Inadequate consensus
		LASTLINE=$(tail ~/lisk-main/logs/lisk.log -n 2| grep 'Inadequate')
		if [[ -n "$LASTLINE" ]]
		then
			date +"%Y-%m-%d %H:%M:%S || ${red}WARNING: $LASTLINE${resetColor}"
		
			for SERVER in ${SERVERS[@]}
			do
				## Get next server's height and consensus
				SERVERINFO=$(curl --connect-timeout 3 -s -S "http://"$SERVER""$PRT"/api/loader/status/sync")
				HEIGHT=$( echo "$SERVERINFO" | jq '.height')
				CONSENSUS=$( echo "$SERVERINFO" | jq '.consensus')
				
				## Make sure next server is not more than 3 blocks behind this server and consensus is better, then switch
				if [[  -n "$HEIGHT" ]];
				then
					diff=$(( $HEIGHTLOCAL - $HEIGHT ))
				else
					diff="999"
				fi
				## if [ "$diff" -lt "3" ] && [ "$CONSENSUS" -gt "$CONSENSUSLOCAL" ]; ## Removed for now as I believe consensus read from API isn't updated every second to be fully accurate
				if [ "$diff" -lt "3" ]; 
				then
					curl -s -S --connect-timeout 3 -k -H "Content-Type: application/json" -X POST -d '{"secret":'"$SECRET"'}' https://"$SRV1""$PRTS"/api/delegates/forging/disable
					curl -s -S --connect-timeout 3 -k -H "Content-Type: application/json" -X POST -d '{"secret":'"$SECRET"'}' https://"$SERVER""$PRTS"/api/delegates/forging/enable
					echo
					date +"%Y-%m-%d %H:%M:%S || ${cyan}Switching to Server $SERVER with a consensus of $CONSENSUS to try and forge${resetColor}"
					break
				fi
			done
		fi
		(( ++TXTDELAY ))
		if [[ "$TXTDELAY" -eq "60" ]];  ## Wait 60 seconds to update running status to not overcrowd log
		then
			date +"%Y-%m-%d %H:%M:%S || ${green}Still working at block $HEIGHTLOCAL with a consensus of $CONSENSUSLOCAL${resetColor}"
			TXTDELAY=0
		fi
			sleep 1
	else
		(( ++TXTDELAY ))
		if [[ "$TXTDELAY" -eq "60" ]];  ## Wait 60 seconds to update running status to not overcrowd log
		then
			date +"%Y-%m-%d %H:%M:%S || This server is not forging"
			TXTDELAY=0
		fi
			sleep 1
	fi
done
