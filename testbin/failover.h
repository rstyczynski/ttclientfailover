
function checkParams {
if [ -z "$1" ]; then
  if [ -z "$cachecfg" ]; then
    echo Error: Configiration not specified by parameter nor "cachecfg" variable
    doStop 1
  fi
else
  readcfg $1
fi

if [ ! -f $cachecfg ]; then
  echo Error: Configuration file does not exist, file: $cachecfg.
  doStop 1
fi
}

function getOtherNode {
  if [ ! -z "$1" ]; then
    host=$1
  else
    host=$(hostname)
  fi
	
  if [ -z "$cachecfg" ]; then
    echo Error: Configuration not specified by "cachecfg" variable
    result=1
  else
   cat $cachecfg | grep -e ACTIVE_NODE -e STANDBY_NODE | grep -i $host >/dev/null
   if [ $? -ne 0 ]; then
     echo $host
   else
     cat $cachecfg | grep -e ACTIVE_NODE -e STANDBY_NODE | grep -i -v $host | cut -f2 -d'='
   fi
  fi
}

function getRemoteDSN {
  if [ ! -z "$1" ]; then
    host=$1
  else
    host=$(hostname)
  fi

  remoteDSNvar=$dsn\CS_at_$(echo $host | cut -f1 -d.)
  remoteDSN=$(eval "echo \$$remoteDSNvar")
  if [ -z "$remoteDSN" ]; then
    remoteDSN=$remoteDSNvar
  fi
  echo $remoteDSN
}

function getOtherNodeDSN {
  if [ ! -z "$1" ]; then
    host=$1
  else
    host=$(hostname)
  fi

  remoteDSNvar=$dsn\CS_at_$(getOtherNode $host | cut -f1 -d.)
  remoteDSN=$(eval "echo \$$remoteDSNvar")
  if [ -z "$remoteDSN" ]; then
    remoteDSN=$remoteDSNvar
  fi
  echo $remoteDSN
}

function checkReplicationStatus {
 expectedState=$1
 other=$2

 where="Checking if replication state is $expectedState"
 echoTab "$where" | tee $tmp/$$.out
 if [ ! -z "$other" ]; then
  if [ "$other" = "other" ]; then
   dsnRemote=$(getOtherNodeDSN) 
   nodeStatus=$(ttGetStatusCS.sh "dsn=$dsnRemote;uid=$userUID;pwdcrypt=$userCryptPWD" 2>&1 | tee -a $tmp/$$.out)
  #it will not work with not default port
  else
   dsnRemote=$(getRemoteDSN $other)
   nodeStatus=$(ttGetStatusCS.sh "dsn=$dsnRemote;uid=$userUID;pwdcrypt=$userCryptPWD" 2>&1 | tee -a $tmp/$$.out)
  fi
 else
  nodeStatus=$(ttGetStatus.sh $dsn 2>&1 | tee -a $tmp/$$.out)
 fi
 case $nodeStatus in
  $expectedState) 
            echo OK | tee -a $tmp/$$.out
            result=0 
            ;;
  ACTIVE|STANDBY|IDLE)
	    if [ ! -z "$other" ]; then
	      echo -n "Error: Othe master status must be $expectedState." | tee -a $tmp/$$.out
	    else
              echo -n "Error: Wrong node. Must be executed on $expectedState." | tee -a $tmp/$$.out
	    fi
            echo "Current status: $nodeStatus" | tee -a $tmp/$$.out
            save2log
            doStop 1
            ;;
  *)       
            echo "Error: unexpected error, casue:$nodeStatus." | tee -a $tmp/$$.out
            save2log
            doStop 1
            ;;
 esac
 save2log
}

function thisNodeUnreachableOrIdle {

where="This node must be unreachable or IDLE"
echoTab "$where" ;

#hatimerun.sh ttisqlcrashtest 1 "sleep 2; ttisql -e 'exit;' $dsn"
#if [ $? -eq 99 ]; then
#	echo nota able to connect
#fi

#below code will load dsn into memory after crash. AutoCreate is not AutoLoad...
#moreover after crash Manual ram policy will make it possible to load datastore into memory
ttBsql.sh -e"@$cachecfg;$(getSecured);verbosity 1" -v1 <<EOF 2>&1 >$tmp/$$.out; test_errorOK
      connect "dsn=&dsn;AutoCreate=0";
      select * from dual;
EOF
save2log
if [ $result -eq 0 ]; then
  doNotExit=1
  checkReplicationStatus IDLE
  if [ $result -ne 0 ]; then
   doStop 1
  fi
fi

}

function thisNodeUnreachable {

where="This node must be unreachable"
echoTab "$where" ;

ttBsql.sh -e"@$cachecfg;;$(getSecured);define remoteDSN=$remoteDSN;verbosity 1" -v1 <<EOF 2>&1 >$tmp/$$.out; test_errorOK
      connect "dsn=&dsn;uid=&userUID;pwdcrypt=&userCryptPWD;AutoCreate=0";
      select * from dual;
EOF
save2log
if [ $result -eq 0 ]; then
  doStop 1
fi

}

function otherNodeUnreachable {

where="Other node must be unreachable"
echoTab "$where" ;

remoteDSN=$(getOtherNodeDSN $thisNode)

ttBsqlCS.sh -e"@$cachecfg;;$(getSecured);define remoteDSN=$remoteDSN;verbosity 1" -v1 <<EOF 2>&1 >$tmp/$$.out; test_errorOK
      connect "dsn=&remoteDSN;uid=&userUID;pwdcrypt=&userCryptPWD;AutoCreate=0";
      select * from dual;
EOF
save2log
if [ $result -eq 0 ]; then
  doStop 1
fi

}


function otherNodeUnreachableOrIdle {

where="Other node must be unreachable or IDLE"
echoTab "$where" ;

remoteDSN=$(getOtherNodeDSN $thisNode)

ttBsqlCS.sh -e"@$cachecfg;$(getSecured);define remoteDSN=$remoteDSN;verbosity 1" -v1 <<EOF 2>&1 >$tmp/$$.out; test_errorOK
      connect "dsn=&remoteDSN;uid=&userUID;pwdcrypt=&userCryptPWD;AutoCreate=0";
      select * from dual;
EOF
save2log
if [ $result -eq 0 ]; then
  doNotExit=1
  checkReplicationStatus IDLE other
  if [ $result -ne 0 ]; then
   doStop 1
  fi
fi

}


function setStateToACTIVE {
runSQL "Set state to ACTIVE" <<EOF
  call ttrepstateset('ACTIVE');
EOF
if [ $result -ne 0 ]; then
  doNotExit=1
  doStop 1
fi

}

function waitForStateChange {
if [ -z "$1" ]; then
 expectedState=ACTIVE
else
 expectedState=$1
fi
 other=$2

where="Checking if current replication status is $expectedState"
echoTab "$where"
unset changeDone
step=0; while [ $step -ne 20 ] && [ "$changeDone" != "OK" ]; do
#  nodeStatus=$(ttGetStatus.sh $dsn 2>&1 | tee $tmp/$$.out)
 if [ ! -z "$other" ]; then
  if [ "$other" = "other" ]; then
   dsnRemote=$(getOtherNodeDSN) 
   nodeStatus=$(ttGetStatusCS.sh "dsn=$dsnRemote;uid=$userUID;pwdcrypt=$userCryptPWD" 2>&1 | tee -a $tmp/$$.out)
  else
   nodeStatus=$(ttGetStatusCS.sh "TTC_Server=$other;TTC_Server_DSN=$dsn;uid=$userUID;pwdcrypt=$userCryptPWD" 2>&1 | tee -a $tmp/$$.out)
  fi
 else
  nodeStatus=$(ttGetStatus.sh $dsn 2>&1 | tee -a $tmp/$$.out)
 fi

  case "$nodeStatus" in
    $expectedState) 
            changeDone=OK
            ;;
     ACTIVE|STANDBY|IDLE)
	    changeDone=No
            ;;
     *)       
            changeDone=error
            ;;
  esac
  sleep 1
  step=$(($step+1))
done
if [ "$changeDone" != "OK" ]; then
  if [ "$changeDone" = "error" ]; then
   echo "Error: unexpected error, casue:$nodeStatus."
   save2log
   doNotExit=1
   doStop 1
  else
   echo Error: datastore replication state is not $expectedState. The state is: $nodeStatus
   doNotExit=1
   doStop 2
  fi
else
  echo "OK, info: $step sec."
fi

}


function registerFailedOtherNode {
 if [ ! -z "$1" ]; then
   thisNode=$1
 fi

 failedNode=$(getOtherNode $thisNode)
 runSQL "Set other node as FAILED" <<EOF
   call ttRepStateSave('FAILED','$dsn','$failedNode')
EOF
 if [ $result -ne 0 ]; then
  doNotExit=1
  doStop 1
 fi
}


function duplicateMasterNode {
 if [ ! -z "$1" ]; then
   ttRepAdminParams="$1"; export ttRepAdminParams
 fi
 if [ ! -z "$2" ]; then
   thisNode=$2
 fi

where="Duplicate master node"
echoTab "$where" 80 "$dotsLines" | tee $tmp/$$.out
echo | tee -a $tmp/$$.out
exec 3>&1 > >(tee -a $tmp/$$.out)

srcNode=$(getOtherNode)
ttRepAdmin -duplicate -from $dsn -host $srcNode -uid $cachemanagerUID -pwdcrypt $cachemanagerCryptPWD -cacheuid $cachemanagerUID -cachepwd $cachemanagerORCLPWD -verbosity 2 -ramLoad -keepCG $ttRepAdminParams $dsn 2>&1
result=$?
echoTab "$where" 
if [ $result -eq 0 ]; then
  echo OK
else
  echo Error: Datastore NOT duplicated.
  save2log
  exec 1>&3; exec 3>&-
  doStop 1
fi
save2log
exec 1>&3; exec 3>&-

}

function duplicateSubscriberNode {
 if [ ! -z "$1" ]; then
   ttRepAdminParams="$1"; export ttRepAdminParams
 fi

if [ -z "$2" ]; then
	srcNode=$STANDBY_NODE
else
	srcNode=$2
fi

where="Duplicate subscriber node"
echoTab "$where" 80 "$dotsLines" | tee $tmp/$$.out
echo | tee -a $tmp/$$.out
exec 3>&1 > >(tee -a $tmp/$$.out)

ttRepAdmin -duplicate -from $dsn -host $srcNode -uid $cachemanagerUID -pwdcrypt $cachemanagerCryptPWD -verbosity 2 $ttRepAdminParams -ramload -nokeepCG $dsn 2>&1
result=$?
echoTab "$where"
if [ $result -eq 0 ]; then
  echo OK
else
  echo Error: Datastore NOT duplicated.
  save2log
  exec 1>&3; exec 3>&-
  doStop 1
fi
save2log
exec 1>&3; exec 3>&-

}

function destroyDatastore {
 ttForcedDestroy.sh $@
}

function _destroyDatastore {

where="Destroying data store"
echoTab "$where" 80 "$dotsLines" | tee $tmp/$$.out
echo | tee -a $tmp/$$.out
exec 3>&1 > >(tee -a $tmp/$$.out)

#can not stop server here, as server is instance level!
#where="Stoping TimesTen server. No c/s connections are possible now."
#echoTab "$where" 80 "$dotsDots" | tee $tmp/$$.out
#ttDaemonAdmin -stopserver $dsn

if [ "$1\$2" = "$dsn\confirm" ]; then
 dsexists=`ttstatus | sed -n "/$dsn/,/--------------------/p"|wc -l`
 if [ $dsexists -gt 0 ]; then
   
   #workaround: with rampolicy manual subdeamon will reload ds after invalidate. inuse will eliominate this "feature"

   ttAdmin -rampolicy inuse $dsn
   ttDatastoreDown.sh -invalidate $dsn
   if [ $? -eq 0 ]; then
      echo "DATASTORE DOWN OK"
   else
      echo "DATASTORE DOWN ERROR"
      result=1
   fi
   ttDestroyDS.sh $dsn
   if [ $? -eq 0 ]; then
    echo "DATASTORE DESTROYED"
   else
    echo "DATASTORE NOT DESTROYED"
    result=1
   fi
 else
   ttDestroyDS.sh $dsn
 fi
 result=$?
else
 echo "Invalid parameters. Use '$dsn confirm' to destroy"
 result=1
fi
echoTab "$where"
if [ $result -eq 0 ]; then
  echo OK
else
  echo Error: Datastore NOT destroyed.
  save2log
  exec 1>&3; exec 3>&-; doStop 1
fi

#
#where="Starting TimesTen server"
#echoTab "$where" 80 "$dotsDots" | tee $tmp/$$.out
#ttDaemonAdmin -startserver $dsn


save2log
exec 1>&3; exec 3>&-
}
	
	
function checkCurrentNode {
        expectedNode=$1

	where="Checking current node"
	echoTab "$where"  
	thisnode=$(hostname | tr [:lower:] [:upper:])
	expectednode=$(echo $expectedNode | tr [:lower:] [:upper:])
	if [ "$thisnode" != "$expectednode" ]; then
		echo Error, cause:Wrong host. Script must be executed on $expectednode.
		doStop 1
	else
		echo OK
	fi
		
}

function getTimestamp {
  	node=$1
	ttBsqlCS.sh -e"@$cachecfg;$(getSecured);verbosity 1" -v1 <<EOF
	  connect "TTC_Server=&$node;TTC_Server_DSN=&dsn;UID=&userUID;pwdcrypt=&userCryptPWD;oraclepwd=&userORCLPWD";
	  call ttrepstateget;
	  autocommit 0;
	  passthrough 3;
	  prompt Oracle time:
	  select * from TIMESTENORACLETIME;
	  commit;
	  prompt TimesTen replicated time:
	  select * from TIMESTENORACLETIME;
EOF
}

function getTimestampTimeout {
	node=$1
	tmpSQL=$(mktemp)

	cat >$tmpSQL <<EOF
		  connect "TTC_Server=&$node;TTC_Server_DSN=$dsn;UID=$userUID;pwdcrypt=$userCryptPWD;oraclepwd=$userORCLPWD";
		  call ttrepstateget;
		  autocommit 0;
		  passthrough 3;
		  prompt Oracle time:
		  select * from TIMESTENORACLETIME;
		  commit;
		  prompt TimesTen replicated time:
		  select * from TIMESTENORACLETIME;
EOF
	hatimerun.sh ttisql 5 "ttBsqlCS.sh -e\"@$cachecfg;$(getSecured);verbosity 1;@$tmpSQL\" -v1"
	case $? in
	 99)  echo Error: Timeout accesing node. ;;
	 0)   ;;
	 *)   echo Error: Unexpected error.
	esac 
	rm $tmpSQL
}


function getHeartbeatTimestamps {
   	if [ -z "$1" ]; then
		calls="ACTIVE_NODE@master#1 STANDBY_NODE@master#2 SUBSCRIBER1NODE@subscriber#1 SUBSCRIBER2NODE@subscriber#2"
	else
		calls=$1
	fi
	echo 
	echo 'Reading replication hearbeat information from nodes.'
	for conn in $calls; do
		name=$(echo $conn | cut -f1 -d'@')
		desc=$(echo $conn | cut -f2 -d'@')
		echoTab "Reading time from $desc node" 
		getTimestampTimeout $name
	done
	echo 
	echo 'Note that time difference comes from (a) replication and (b) serialized execution of tests.'
        echo
}

function checkClockSkew {
  otherNode=$1

  where="Checking time difference at node $1"
  echoTab "$where" | tee $tmp/$$.out

  times=$(ssh $otherNode "perl -e 'print time().\"\n\";'" 2>/dev/null ; echo ' '; perl -e 'print time()."\n";')
  standbyTime=$(echo $times | cut -f1 -d ' ')
  activeTime=$(echo $times | cut -f2 -d ' ')

  timeDiff=$(echo $(( $activeTime - $standbyTime )) )
  if [ $timeDiff -gt 1 ]; then
    echo Error, info: time difference is $timeDiff 
  elif [ $timeDiff -eq 1 ]; then
    echo Warning, info: time difference is 1s. It may be ok.
  elif [ $timeDiff -eq 0 ]; then
    echo OK
  else
    echo Error, info: $activeTime vs. $standbyTime
  fi
}	
