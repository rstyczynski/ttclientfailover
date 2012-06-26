declare -a progress=('.' 'o' 'O' 'o')
_mstep=0; _mstepmax=3

function spinner {
stepmax=$1
delay=$2

step=0
while [ $step -lt $stepmax ]; do
        echo -n ${progress[$_mstep]}
        let _mstep++
        if [ $_mstep -eq $_mstepmax ]; then _mstep=0; fi
        sleep $delay
        echo -n ""
        let step++
done
#echo -n ""
}

function getNodesStatus {
  ttIsqlCS -v1 -e "call ttrepstateget; exit" "TTC_SERVER=$host1;TTC_SERVER_DSN=$dsn1;TCP_PORT=$serverport1;uid=appuser;pwd=appuser"
  if [ $? -ne 0 ]; then
     echo '< NOTAVAILABLE >'
  fi

  ttIsqlCS -v1 -e "call ttrepstateget; exit" "TTC_SERVER=$host2;TTC_SERVER_DSN=$dsn2;TCP_PORT=$serverport2;uid=appuser;pwd=appuser"
  if [ $? -ne 0 ]; then
     echo '< NOTAVAILABLE >'
  fi
}

function listFailedSteps {
	grep "^Error, info:" $testId.*.log | cut -f1 -d:
        grep "^Unexpected response, info:" $testId.*.log | cut -f1 -d:
}

function showFailedSteps {
  for failedFile in "$(listFailedSteps | sort)"; do
	cat $failedFile
  done
}

#to be executed after test execution
#function will:
#1. generate instance snapshot (log, cfg, parameters, ttconfiguration)
#2. tterrors.log will be copied to local directory
#3. remote binary files (ttadmin_home/bin) will be copied locally
function getTestEnvironment {
	_hosts=$2
	_user=$1
for host in $_hosts; do
    echoTab "Gathering instance info from $host"
    getInstanceSnapshot $_user $host 
    echo Done.

    echoTab "Extracting tterrors.log"
    logfile=$(tar tf ttSnapshot_$host\_$testId.tar.gz | grep tterrors.log)
    tar zxvf ttSnapshot_$host\_$testId.tar.gz $logfile &>/dev/null
    cp $logfile $testId\_$host\_tterrors.log 
    echo Done.

    echoTab "Extracting ttmesg.log"
    logfile=$(tar tf ttSnapshot_$host\_$testId.tar.gz | grep ttmesg.log)
    tar zxvf ttSnapshot_$host\_$testId.tar.gz $logfile &>/dev/null
    cp $logfile $testId\_$host\_ttmesg.log
    echo Done.

    echoTab "Gathering ttadmin_home/bin from $host"
    if [ ! -d $host.bin ]; then
     ttbin=$(getTTadminBin $user $host)
     mkdir $host.bin &>/dev/null
     scp $user@$host:$ttbin/* $host.bin &>/dev/null
    fi
    echo Done.
done

}


function getTestSummary {

echo '--------------------------------------'
if [ "$(listFailedSteps)" != "" ]; then
   echo "$testId completed with ERRORS."
else
   echo "$testId completed OK."  
fi
echo '--------------------------------------'

}


function getInstanceSnapshot {
	_user=$1
	_host=$2

    ssh $_user@$_host &>/dev/null <<EOF
      ttSnapshot.sh $testId
EOF
    snapshot=ttSnapshot_$_host\_$testId.tar.gz
    scp $_user@$_host:~/diagnostic/$snapshot .  &>/dev/null 
    scp $_user@$_host:~/$snapshot . &>/dev/null 
}

function getTTadminBin {
	_user=$1
	_host=$2
	ssh $_user@$_host 2>/dev/null <<EOF | grep ttadmin_home | cut -f2 -d'='
echo -n ttadmin_home=; echo \$ttadmin_home/bin
EOF
}

function describe {
  stepId=$1
  echoTab "$(head -2 $testId.$stepId.log | tail -1 | cut -b7-9999)" 
}

function step {
  stepId=$1
  where=$2
  (
     echo "---------------------------------------------------------------------------" 
     echo "----- $stepId: $where" 
     echo "---------------------------------------------------------------------------"
  ) > $testId.$stepId.log
  cat $testId.$stepId.log >>$testId.script.log


  if [ "$updateTimesTenLog" == "YES" ]; then
    ssh $osuser@$host1mgm >/dev/null 2>&1 <<SSH &
      ttDaemonLog -msg "------------------ $testId:$stepId:$where --------------------------------"
SSH
    logpids=$!
    if [ "$host1" != "$host2" ]; then
      ssh $osuser@$host2mgm >/dev/null 2>&1 <<SSH &
        ttDaemonLog -msg "------------------ $testId:$stepId:$where --------------------------------"
SSH
        logpids="$logpids $!"
    fi
    #jobs
    #echo $logpids
    wait $logpids
  fi

  describe $stepId
  if [ "$DEBUG" == "YES" ]; then
  	echo Pausing for 10s. ...; sleep 10
  fi
  if [ -f $testId.$stepId.out ]; then rm $testId.$stepId.out; fi
  if [ -f $testId.$stepId.err ]; then rm $testId.$stepId.err; fi

  while read cmd; do
        eval "echo $(echo $cmd | sed 's/\>/\\>/g')" >>$testId.script.log
 	eval $cmd >>$testId.$stepId.out 2>>$testId.$stepId.err
  done
  #grep -v "^#command:" $testId.$stepId.tmp.out >$testId.$stepId.out
  #grep -v "^#command:" $testId.$stepId.tmp.err >$testId.$stepId.err

  cat $testId.$stepId.out >>$testId.$stepId.log
  cat $testId.$stepId.out >>$testId.script.log
  if [ -s $testId.$stepId.err ]; then
    echo '------- Stdout errors:' >>$testId.$stepId.log
    echo '------- Stdout errors:' >>$testId.script.log
    cat $testId.$stepId.err >>$testId.$stepId.log
    cat $testId.$stepId.err >>$testId.script.log
    echo '----------------------' >>$testId.$stepId.log
    echo '----------------------' >>$testId.script.log
  fi
}

function expectStepTime {
    operator=$1

   stepTime=$(cat $testId.log | grep "Step $stepId - END" | cut -f3)

   unset result
   unset info
   if [ "$stepTime" != "" ]; then
    case "$operator" in
     between)
       if [ $stepTime -ge "$2" -a $stepTime -le "$3" ]; then
         result=OK
         info="$stepTime in <$2,$3>"
       else
         result=Error
         info="$stepTime not in <$2,$3>"
       fi
       ;;
     *)
       test $stepTime $@
       exitcode=$?
		if [ $exitcode -eq 0 ]; then
         result=OK
         info="test $@"
       else
         result="Error"
         info="test $stepTime $@ exited with $exitcode"
       fi
       ;;
    esac
   else
     result="Error"
     info="step time is null"
   fi
   echo $result, info: $info
}

function expectResponse {
	type=$1

	cat > $testId.$stepId.exp
	cnt=0
	done=NO
	_mstep=0
	while [ "$done" == "NO" ]; do  
		echo -n ${progress[$_mstep]}
		let _mstep++
		if [ $_mstep -eq $_mstepmax ]; then _mstep=0; fi		
		sleep 1  
		echo -n ""
		if [ -f $testId.$stepId.msg ]; then
			done=YES
			result=OK
		fi
		let cnt++
		if [ $cnt -eq $TIMEOUT ]; then
			done=YES
			result=ERROR
		fi
	done
	#if [ $_mstep -ne 0 ]; then 
	#	echo -n ""
	#fi
	if [ "$result" == "OK" ]; then
			if grep "^Comment:" $testId.$stepId.msg >/dev/null 2>&1; then
				diff $testId.$stepId.exp $testId.$stepId.out >$testId.$stepId.diff
			else
				diff $testId.$stepId.exp $testId.$stepId.msg >$testId.$stepId.diff
			fi
			if [ $? -eq 0 ]; then
				#if [ "$RESPONSE_LIMIT" == "" ]; then
				#	RESPONSE_LIMIT=80
        			#fi
        			echo -n "OK, $type: $(cat $testId.$stepId.exp | tr '\n' ' ')" | tee -a $testId.$stepId.tmp.log
				#| cut -b1-$RESPONSE_LIMIT
                                rm $testId.$stepId.diff
                                if [ "$VERBOSE" == "YES" ]; then
                                	echo
					cat $testId.$stepId.exp | tee -a $testId.$stepId.tmp.log
                                fi
			else
				echo "Unexpected response, info:" | tee -a $testId.$stepId.log
				cat $testId.$stepId.diff | tee -a $testId.$stepId.tmp.log
			fi
                                
			if [ "$(cat $testId.$stepId.err 2>/dev/null | wc -c)" -gt 0 ]; then 
                        	if [ "$(cat $testId.$stepId.err | grep -v Warning | grep -v '^$' | wc -c)" -eq 0 ]; then
                                	mv $testId.$stepId.err $testId.$stepId.warning
                                        (
					echo
					echoTab '\'
					echo "Warning, info:$(cat $testId.$stepId.warning | tr '\n' ' ')"
					) | tee -a $testId.$stepId.tmp.log
                                else    
					(
					echo
					echoTab '\'
                                	echo "Error, info:$(cat $testId.$stepId.err | tr '\n' ' ')"
					) | tee -a $testId.$stepId.tmp.log
                                fi
      			else    
                        	rm $testId.$stepId.err
				echo | tee -a $testId.$stepId.tmp.log
                       	fi
	else
		echo Error, info: timeout waiting for response file $testId.$stepId.msg | tee $testId.$stepId.err | tee -a $testId.$stepId.tmp.log
	fi
	cat $testId.$stepId.tmp.log >>$testId.$stepId.log
	cat $testId.$stepId.tmp.log >>$testId.script.log
        rm $testId.$stepId.tmp.log
	}

function expectResponseOK {
	expectResponse info
}
function expectResponseError {
	expectResponse error
}

function expectResponse {
	expectFile info msg
}

function expectError {
	expectFile error exc
}

function expectFile {
        type=$1
	ext=$2
	exterr=$3

        cat > $testId.$stepId.exp@$ext
        cnt=0
        done=NO
        _mstep=0
        while [ "$done" == "NO" ]; do
                echo -n ${progress[$_mstep]}
                let _mstep++
                if [ $_mstep -eq $_mstepmax ]; then _mstep=0; fi
                sleep 0.1
                echo -n ""
                if [ -f $testId.$stepId.$ext ]; then
                        done=YES
                        result=OK
                fi
                let cnt++
                if [ $cnt -eq $TIMEOUT ]; then
                        done=YES
                        result=ERROR
                fi
        done
        if [ "$result" == "OK" ]; then
			if [ -f $testId.$stepId.exp@$exterr ]; then
                                echoTab '\'  | tee -a $testId.$stepId.log
                        fi
                        if grep "^Comment:" $testId.$stepId.$ext >/dev/null 2>&1; then
                                diff $testId.$stepId.exp@$ext $testId.$stepId.out >$testId.$stepId.diff_$ext
                        else
                                diff $testId.$stepId.exp@$ext $testId.$stepId.$ext >$testId.$stepId.diff_$ext
                        fi
                        if [ $? -eq 0 ]; then
				notes=$(cat $testId.$stepId.exp@$ext | tr '\n' ' ')
				if [ -z "$notes" ]; then notes='(none)'; fi
                                echo "OK, $type: $notes" | tee -a $testId.$stepId.tmp.log
                                rm $testId.$stepId.diff_$ext
                                if [ "$VERBOSE" == "YES" ]; then
                                        (
					echo 
                                        cat $testId.$stepId.exp
                                	)  | tee -a $testId.$stepId.tmp.log
				fi
                        else
				(
                                echo "Unexpected response, info:"
                                cat $testId.$stepId.diff_$ext
                        	)  | tee -a $testId.$stepId.tmp.log
			fi

			#this section works bad - disabling
			if [ "$exterr" != "" ]; then
				if [ ! -f $testId.$stepId.exp@$exterr ]; then 
                        		if [ "$(cat $testId.$stepId.$exterr 2>/dev/null | wc -c)" -gt 0 ]; then
                                		if [ "$(cat $testId.$stepId.$exterr | grep -v Warning | grep -v '^$' | wc -c)" -eq 0 ]; then
                                        		mv $testId.$stepId.$exterr $testId.$stepId.warning@$exterr
							echoTab '\'
                                        		echo "Warning, info:$(cat $testId.$stepId.warning@$exterr | tr '\n' ' ')" | tee -a $testId.$stepId.tmp.log
						else
                                        		echoTab '\'
                                        		echo "Error, info:$(cat $testId.$stepId.$exterr | tr '\n' ' ')" | tee -a $testId.$stepId.tmp.log
						fi
                        		else
                                		rm $testId.$stepId.$exterr
                                		
                        		fi
				fi
			fi

        else
                echo Error, info: timeout waiting for response file $testId.$stepId.$ext | tee $testId.$stepId.err@$ext  | tee -a $testId.$stepId.tmp.log
        fi
        cat $testId.$stepId.tmp.log >>$testId.$stepId.log
        cat $testId.$stepId.tmp.log >>$testId.script.log
        rm $testId.$stepId.tmp.log 
        }

function expect {
  expectedValue=$1
  operator=$2
  if [ -z "$operator" ]; then
     operator='=='
  fi
  eval "test \"$expectedValue\" $operator \"$(cat $tmp/$$.test$testId.$stepId\-response)\""
  if [ $? -eq 0 ]; then 
     echo OK
     okCount=$(( $okCount + 1 ))
    (
       echo "---------------------------------------------------------------------------" 
       echo "----- OK, info: $expectedValue $operator $(cat $tmp/$$.test$testId.$stepId\-response)"
       echo "---------------------------------------------------------------------------"
    ) >> $tmp/$testId.$stepId 2>&1
  else
     errCount=$(( $errCount + 1 ))
     echo Error, cause: $(cat $tmp/$$.test$testId.$stepId\-response)
  (
     echo "---------------------------------------------------------------------------" 
     echo "----- Error, cause: $expectedValue NOT $operator $(cat $tmp/$$.test$testId.$stepId\-response)"
     echo "---------------------------------------------------------------------------"
  ) >> $tmp/$testId.$stepId 2>&1
  fi
}

function extract {
  extractPattern=$1
  filter=$2
  grep "$extractPattern" $tmp/$testId.$stepId >$tmp/$$.test$testId.$stepId\-responseGrep 2>&1
  if [ $? -ne 0 ]; then
     cat $tmp/$testId.$stepId | grep -v "^-----" >$tmp/$$.test$testId.$stepId\-responseAll
  else
     cat $tmp/$$.test$testId.$stepId\-responseGrep >$tmp/$$.test$testId.$stepId\-responseAll
  fi
  if [ -z "$filter" ]; then
      cat $tmp/$$.test$testId.$stepId\-responseAll | cut -b1-100 > $tmp/$$.test$testId.$stepId\-response
  else
      eval "cat $tmp/$$.test$testId.$stepId\-responseAll | $filter"  > $tmp/$$.test$testId.$stepId\-response
  fi
}

function testSummary {
    echoTab "Test summary" 
    if [ $errCount -ne 0 ]; then echo -n FAILED; else echo PASSED; fi
    echo ", info: OK: $okCount, Error: $errCount"
    errCount=0
    okCount=0
}


#---

function waitForRemoteStateChange {
        _state=$4
        _dsn=$1
        _host=$2
        _serverport=$3

        cnt=0
        done=NO
        RepState=Unknown
	RepStateList=''
	_mstep=0
        while [ "$done" == "NO" ]; do
                RepState=$(ttIsqlCS -v1 -e"call ttrepstateget; exit" "TTC_SERVER=$_host;TTC_SERVER_DSN=$_dsn;TCP_PORT=$_serverport;uid=adm;pwd=adm" 2>>$testId.$stepId.err | cut -f2 -d' ' | cut -f1 -d,)
                RepStateList="$RepStateList $RepState"
                if [ "$RepState" == "$_state" ]; then
                        done=YES
		fi
		#echo -n .
		echo -n ${progress[$_mstep]}
                let _mstep++
                if [ $_mstep -eq $_mstepmax ]; then _mstep=0; fi
                sleep 1 
                echo -n ""
                let cnt++
                if [ $cnt -eq $TIMEOUT_SHORT ]; then
                        done=YES
                fi
        done
	#echo -n ""
        if [ "$RepState" == "$_state" ]; then
                echo -n "OK, info: $cnt steps, $RepStateList" | tee -a $testId.$stepId.log
        else
                echo "Error, info: $RepStateList" | tee -a $testId.$stepId.log
        fi

	if [ -f $testId.$stepId.err ]; then
		if [ "$(cat $testId.$stepId.err | wc -c)" -gt 0 ]; then
                        if [ "$(cat $testId.$stepId.err | grep -v Warning | grep -v '^$' | wc -c )" -eq 0 ]; then
                		mv $testId.$stepId.err $testId.$stepId.warning
                                echo | tee -a $testId.$stepId.log
                                echoTab '\'
                                echo "Warning, info:$(cat $testId.$stepId.warning | tr '\n' ' ')" | tee -a $testId.$stepId.log
			else
                                echo | tee -a $testId.$stepId.log
                                echoTab '\'
                                echo "Error, info:$(cat $testId.$stepId.err | tr '\n' ' ')" | tee -a $testId.$stepId.log
	  		fi
		else
			rm $testId.$stepId.err
			echo | tee -a $testId.$stepId.log
		fi
	fi
}

function masterDown {
 target=$1
 if [ -z "$target" ]; then target=master1; fi

 case $target in
 	master1)
		_host=$host1
		_dsn=$dsn1
		_serverport=$serverport1
		_hostmgm=$host1mgm
		;;
 	master2)
                _host=$host2
                _dsn=$dsn2
                _serverport=$serverport2
                _hostmgm=$host2mgm
		;;
 esac

 where="Progress, info: crashing TimesTen"
 case "$failureType" in
   invalidate)
        echoTab "$where - hiding files, killing processes" | tee -a $testId.$stepId.log
        dsnfile=$(ttIsqlCS -e 'call ttconfiguration; exit' "TTC_SERVER=$_host;TTC_SERVER_DSN=$_dsn;TCP_PORT=$_serverport;uid=adm;pwd=adm"  | grep DataStore, | cut -f3 -d ' ')
        ssh $osuser@$_hostmgm &>/dev/null <<SSH
                mv $dsnfile.ds0 $dsnfile.ds0X
                mv $dsnfile.ds1 $dsnfile.ds1X
                pids=\$(ttstatus | sed -n /$_dsn/,/-----/p | grep 0x | grep -v KEY | tr -s ' ' | cut -d ' ' -f2 | sort -u)
                kill -9 \$pids
SSH
	echo Done.
        ;;
   serverDown)
        echoTab "$where - stoping server" | tee -a $testId.$stepId.log
        ssh -q $osuser@$_hostmgm >/dev/null 2>&1 <<SSH
                ttDaemonAdmin -stopserver
SSH
        echo Done.
        ;;
   networkDown)
        echoTab "$where - taking network interface down" | tee -a $testId.$stepId.log
        ssh root@$_hostmgm "/sbin/ifconfig eth1 down"
        echo Done.
        ;;
   daemonDown)
        echoTab "$where - taking TimesTen down" | tee -a $testId.$stepId.log
                ssh -q $osuser@$_hostmgm >/dev/null 2>&1 <<SSH
                   ttDaemonAdmin -stop -force
SSH
        echo Done.
        ;;
   *)
        echo Error: TimesTen failure type NOT recognized. | tee -a $testId.$stepId.log
        ;;
 esac
}

function masterUp {
 target=$1
 if [ -z "$target" ]; then target=master1; fi
 
 case $target in
        master1)
                _host=$host1
                _dsn=$dsn1
                _serverport=$serverport1
                _hostmgm=$host1mgm
                ;;
        master2)
                _host=$host2
                _dsn=$dsn2
                _serverport=$serverport2
                _hostmgm=$host2mgm
                ;;
 esac
 where="Progress, info: recovering TimesTen"
 case "$failureType" in
   invalidate)
        echoTab "$where - moving files back" | tee -a $testId.$stepId.log
        ssh -q $osuser@$_hostmgm >/dev/null 2>&1 <<SSH
                mv $dsnfile.ds0X $dsnfile.ds0
                mv $dsnfile.ds1X $dsnfile.ds1
                ttAdmin -ramload $_dsn
                ttAdmin -repstart $_dsn
SSH
        echo Done.
        ;;
   serverDown)
        echoTab "$where - starting server" | tee -a $testId.$stepId.log
        ssh -q $osuser@$_hostmgm >/dev/null 2>&1 <<SSH
                ttDaemonAdmin -startserver
SSH
        echo Done.
        ;;
   networkDown)
        echoTab "$where - taking interface up" | tee -a $testId.$stepId.log
        ssh root@$_hostmgm "/sbin/ifconfig eth1 up"
        echo Done.
        ;;
   daemonDown)
        echoTab "$where - taking TimesTen daemon up, loading datastore, staring rep agent" | tee -a $testId.$stepId.log
        ssh -q $osuser@$_hostmgm >/dev/null 2>&1 <<SSH
                ttDaemonAdmin -start -force
                ttAdmin -ramload $_dsn
		ttisql -e "call ttrepdeactivate;exit" $_dsn
                ttAdmin -repstart $_dsn
SSH
        echo Done.
        ;;
   *)
        echo Error: TimesTen failure type NOT recognized. | tee -a $testId.$stepId.log
        ;;
 esac
}

function stepOut {
cat out.log | sed -n "/Step $stepId - BEGIN/,/Step $stepId - END/p"
}

function stepOutEOF {
cat out.log | sed -n "/Step $stepId - BEGIN/,//p"
}

#function nextStep {
#	let step++
#	echoTab "Step $stepId"; echo
#}

function stop {

echo Finishing
let stepId++
echo $stepId exit >control

sleep 2

exit

}

function ttDeleteLog {
	_host=$2
	_user=$1
        _dsn=$3

  ssh $_user@$_host >/dev/null 2>&1 <<SSH &
     eval \$(ttversion -m)
     userlog=\$(cat \$effective_daemonhome/ttendaemon.options | grep '^\w*-userlog' | cut -f2 -d' ' | cut -f1 -d'.')
     if [ "\$userlog" == "" ]; then
        userlog=\$effective_daemonhome/tterrors
        supportlog=\$effective_daemonhome/ttmesg
     fi
     supportlog=\$(cat \$effective_daemonhome/ttendaemon.options | grep '^\w*-supportlog' | cut -f2 -d' ' | cut -f1 -d'.')
     if [ "\$supportlog" == "" ]; then
        supportlog=\$effective_daemonhome/ttmesg
     fi

     if [ "$_dsn" != "" ]; then bash /tmp/ttadmin/bin/ttDatastoreDown.sh $_dsn; fi
     ttDaemonAdmin -stop

     echo \$userlog\.log*
     ls \$userlog\.log*

     rm \$userlog\.log*
     rm \$supportlog\.log*

     ttDaemonAdmin -start
     if [ "$_dsn" != "" ]; then bash /tmp/ttadmin/bin/ttDatastoreUp.sh $_dsn; fi
SSH

}

function ttDeleteLogsInSystem {
if [ "$deleteTimesTenLog" == "YES" ]; then
    if [ "$host1" != "$host2" ]; then
      echoTab "Deleting TimesTen logs on $host1, $host2"
      ttDeleteLog $osuser $host1mgm $dsn1; delpids=$!
      ttDeleteLog $osuser $host2mgm $dsn2; delpids+=" "$!
      #jobs
      #echo $delpids
      wait $delpids
    else
      echoTab "Deleting TimesTen logs on $host1"
      ttDeleteLog $osuser $host1mgm $dsn1
    fi
    echo Done.
fi

}

