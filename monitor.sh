#!/bin/ash



setvars() {
   SRVFILE=/config/servicelist.txt
   SRVALLJSOUT=$(mktemp /tmp/servalljs.out.XXXXXX)
   SRVIDFILE=$(mktemp /tmp/servids.out.XXXXXX)
   TASKJSOUT=$(mktemp /tmp/tasksjs.out.XXXXXX)
   TASKSTATEALL=$(mktemp /tmp/taskstateall.out.XXXXXX)
   TASKSTATERUN=$(mktemp /tmp/taskstaterun.out.XXXXXX)
   NODEOUT=$(mktemp /tmp/nodejs.out.XXXXXX)
   CURNODELABELOUT=$(mktemp /tmp/curnodelabel.out.XXXXXX)
   CURNODELABELTMP=$(mktemp /tmp/curnodelabeltmp.out.XXXXXX)
   TGTNODELABELTMP=$(mktemp /tmp/tgtnodelabeltmp.out.XXXXXX)
   TGTNODELABELOUT=$(mktemp /tmp/tgtnodelabel.out.XXXXXX)
   UPDNODELABELOUT=$(mktemp /tmp/updnodelabel.out.XXXXXX)
   NODELIST=$(mktemp /tmp/nodelist.out.XXXXXX)
   IFS=","
   MAX_SERVCHECK_RETRIES=30
   SECS_BETWEEN_RETRIES=15
   SECS_BETWEEN_BACKUP_CHECKS=30
}


## retrieve current set of nodes, and set of node labels/values in current environment
getnodesandlabels () {
	curl -s --unix-socket /var/run/docker.sock http://localhost/nodes -o $NODEOUT 
	jq -j '.[]|.ID, ",", .Description.Hostname, "\n"' $NODEOUT > $NODELIST
	jq -j '.[]|{ id:.ID, node:.Description.Hostname, labels:(.Spec.Labels|to_entries[]) }|.id, ",", .node, ",", .labels.key, ",", .labels.value,"\n" ' $NODEOUT > $CURNODELABELOUT
	# now have file of all nodes/labels. Filter down to only relevant ones for desired services
	if [ -f $SRVFILE ] && [ -f $CURNODELABELOUT ]; then
	   rm -f $CURNODELABELTMP	
	   while read -r srvcname labelname; do
		awk -F, -v LBLNAME=$labelname '$3==LBLNAME {print $0}' $CURNODELABELOUT >> $CURNODELABELTMP   
	   done < $SRVFILE
	   if [ -f $CURNODELABELTMP ]; then
		sort -t, -k 2,3 $CURNODELABELTMP > $CURNODELABELOUT
	   else
	        rm $CURNODELABELOUT
           fi		
	fi		
}

## create a new "target" state of node labels where they are all off. No changes to be made to nodes. 
## Just create target state file.

allflagsoff () {
	rm -f $TGTNODELABELOUT $TGTNODELABELTMP
	if [ -f $SRVFILE ] && [ -f $NODELIST ]; then
	   while read -r hostid hname; do
		while read -r srvname labelname; do
			echo "$hostid,$hname,$labelname,0" >> $TGTNODELABELTMP
		done < $SRVFILE
	   done < $NODELIST
	fi
	if [ -f $TGTNODELABELTMP ]; then
	   sort -t, -k 2,3 $TGTNODELABELTMP > $TGTNODELABELOUT
	fi   
}

## check current services and update target label state based on service/task state
## compare target state to current state and make updates to node labels where applicable

checkservices () {
	CUR_RETRIES=0
	SERVICES_STARTING=1
	until [ "$CUR_RETRIES" -gt "$MAX_SERVCHECK_RETRIES" ] || [ "$SERVICES_STARTING" -eq "0" ]; do
	   SERVICES_STARTING=0	
	   curl -s --unix-socket /var/run/docker.sock http://localhost/services -o $SRVALLJSOUT
	   rm -f $SRVIDFILE
	   IFS=","
	   if [ -f $SRVFILE ]; then
	      while read -r srvname labelname; do
		   jq -j --arg SRV $srvname --arg LABELNAME $labelname '.[]|select(.Spec.Name==$SRV)|.Spec.Name , "," , $LABELNAME,",", .ID , "\n"' $SRVALLJSOUT >> $SRVIDFILE
	      done < $SRVFILE
	   fi   
	   curl -s --unix-socket /var/run/docker.sock http://localhost/tasks -o $TASKJSOUT
	   rm -f $TASKSTATEALL $TASKSTATERUN
	   if [ -f $SRVIDFILE ]; then
	      while read -r srvname labelname srvid; do
		      jq -j --arg SRVID $srvid --arg SRVNAME $srvname --arg LABELNAME $labelname '.[]|select(.ServiceID==$SRVID)|select(.Status.State!="complete" and .Status.State!="failed" and .Status.State!="shutdown" and .Status.State!="rejected" and .Status.State!="orphaned" and .Status.State!="remove")|.NodeID, ",", .Status.ContainerStatus.ContainerID, ",", $SRVNAME, ",", $LABELNAME, ",", .Status.State, ",", (.Status.State | inside("new pending assigned accepted preparing starting")), "\n"' $TASKJSOUT >> $TASKSTATEALL
	      done < $SRVIDFILE
	   fi
	   if [ -f $TASKSTATEALL ]; then
		  SERVICES_STARTING=`awk -F, '$6=="true" {print $2}' $TASKSTATEALL | wc -l`
		  awk -F, '$6=="false" {print}' $TASKSTATEALL > $TASKSTATERUN
	   fi
	   if [ -f $TGTNODELABELOUT ]; then
	      cp $TGTNODELABELOUT $TGTNODELABELTMP   
	      if [ -f $TASKSTATERUN ]; then
	         while read -r nodeid containerid srvname labelname status; do
		     awk -F, -v hid=$nodeid -v lbl=$labelname '{if ($1==hid && $3==lbl) {print $1 "," $2 "," $3 "," 1} else {print $0}}' $TGTNODELABELTMP > $TGTNODELABELOUT
		     if [ -f $TGTNODELABELOUT ]; then cp $TGTNODELABELOUT $TGTNODELABELTMP; fi
	         done <$TASKSTATERUN
	      fi
	      diff -U0 $CURNODELABELOUT $TGTNODELABELOUT | grep -v +++ | grep ^+ | sed -e 's/^+//' > $UPDNODELABELOUT
	      if [ -f $UPDNODELABELOUT ]; then
		 while read -r hostid hname labelname flag; do
			echo "change being done for node $hname setting label $labelname to $flag" 
			docker node update --label-add "$labelname=$flag" $hname > /dev/null
		 done < $UPDNODELABELOUT
	      fi	 
	   fi   
	   getnodesandlabels
	   let CUR_RETRIES++
	   if [ $SERVICES_STARTING == 1 ]; then
		echo " ...  WAITING $SECS_BETWEEN_RETRIES seconds to try again for services to become active"   
		sleep $SECS_BETWEEN_RETRIES
	   fi	
        done   
}

checkandupdate() {
   getnodesandlabels
   allflagsoff
   checkservices
}	


processevent () {
   echo "processing docker event from node event log..."
   checkandupdate
}


monitorloop () {
     echo "beginning docker event socker monitoring loop..."	
#     curl -s -Gg --unix-socket /var/run/docker.sock --data-urlencode 'filters={"type":{"node":true}}' http://localhost/events  | while read line; do processevent $line; done;
     docker events --filter "type=node" | while read line; do processevent $line; done;

}

backupcheck() {
     echo "Creating secondary filename set for backup check process..."
     setvars     
     echo "Executing Backup Check, every 30 seconds..."
     while true; do
	checkandupdate     
        sleep $SECS_BETWEEN_BACKUP_CHECKS
     done	     

}



### MAIN FUNCTION

echo "Setting initial vars"
setvars
echo "Getting Node List..."
getnodesandlabels
echo "Setting All Service Flags Off..."
allflagsoff
echo "Running Initial Service Check (One Time) ..."
checkservices
echo "Setting up background periodic backup check ..."
backupcheck &
echo "Setting up Event Monitor Loop ..."
monitorloop





