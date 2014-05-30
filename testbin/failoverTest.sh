

#-xx 11 -cc 1
eval $(echo $@ | sed "s/ -/;/g" | sed "s/^-//" | tr ' ' '=')

. ../common.h

#---
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
  describe $stepId
  if [ "$DEBUG" == "YES" ]; then
  	echo Pausing for 10s. ...; sleep 10
  fi
  if [ -f $testId.$stepId.out ]; then rm $testId.$stepId.out; fi
  #if [ -f $testId.$stepId.err ]; then rm $testId.$stepId.err; fi

  while read cmd; do 
 	eval $cmd >>$testId.$stepId.out 2>&1
        #2>>$testId.$stepId.err
  done
  cat $testId.$stepId.out >>$testId.$stepId.log
}

function expectResponse {
	cat > $testId.$stepId.exp
	cnt=0
	done=NO
	while [ "$done" == "NO" ]; do  
		echo -n .
		sleep 0.5
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
	if [ $result == OK ]; then
			if grep "^Comment:" $testId.$stepId.msg >/dev/null 2>&1; then
				diff $testId.$stepId.exp $testId.$stepId.out >$testId.$stepId.diff
			else
				diff $testId.$stepId.exp $testId.$stepId.msg >$testId.$stepId.diff
			fi
			if [ $? -eq 0 ]; then
				echo "OK, info: $(cat $testId.$stepId.exp | tr '\n' ' ')" | cut -b1-80
				rm $testId.$stepId.diff
				if [ "$VERBOSE" == "YES" ]; then
					cat $testId.$stepId.exp
				fi
			else
				echo "Error, info:"
				cat $testId.$stepId.diff
			fi
	else
		echo Error, info: timeout waiting for response file $testId.$stepId.msg
	fi
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

function waitForStateChange {
        _state=$4
        _dsn=$1
        _host=$2
        _serverport=$3

        cnt=0
        done=NO
        RepState=Unknown
        while [ "$done" == "NO" ]; do
                RepState=$(ttIsqlCS -v1 -e"call ttrepstateget; exit" "TTC_SERVER=$_host;TTC_SERVER_DSN=$_dsn;TCP_PORT=$_serverport;uid=adm;pwd=adm" | cut -f2 -d' ' | cut -f1 -d,)
                RepStateList=$RepStateList,$RepState
                if [ "$RepState" == "$_state" ]; then
                        done=YES
                fi
                sleep 1
                echo -n '.'
                let cnt++
                if [ $cnt -eq 10 ]; then
                        done=YES
                fi
        done
        if [ "$RepState" == "$_state" ]; then
                echo "OK, info: $cnt s."
        else
                echo "Error, info: $RepStateList"
                echo ------------ ERROR --------------
                ttIsqlCS -e"call ttrepstateget; exit" "TTC_SERVER=$_host;TTC_SERVER_DSN=$_dsn;TCP_PORT=$_serverport;uid=adm;pwd=adm"
                echo ------------ ERROR --------------
        fi
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
#nextStep
echo exit >control
stepOutEOF
exit

}


cd
cd /Users/rstyczynski/NetBeansProjects/ttclientfailover/dist
rm control
mkfifo control
step=0
java -classpath $CLASSPATH:$(eval $(ttversion -m);echo $effective_insthome/lib) -d32 -jar ttclientfailover.jar <control >out.log &

testId=Failover01
dsn=XX
dsn1=repdb1_1121
host1=ozone2
serverport1=53385
dsn2=repdb2_1121
host2=ozone2
serverport2=53385

TIMEOUT=160

tmp=/tmp

if [ -f $tmp/*$testId* ]; then rm $tmp/*$testId*; fi
if [ -f $testId* ]; then rm $testId*; fi

step 1 "Initializing test" <<EOF
	echo "connect TTC_SERVER=$host1;TTC_SERVER_DSN=$dsn1;TCP_PORT=$serverport1;TTC_SERVER2=$host2;TTC_SERVER_DSN2=$dsn2;uid=appuser;pwd=appuser" >control
EOF
expectResponse <<EOF
Connection string:TTC_SERVER=$host1;TTC_SERVER_DSN=$dsn1;TCP_PORT=$serverport1;TTC_SERVER2=$host2;TTC_SERVER_DSN2=$dsn2;uid=appuser;pwd=appuser
EOF

step 2 "Reading data from active" <<EOF
	echo step >control
EOF
expectResponse <<EOF
Executing step
Remote host:repdb1_1121@ozone2:53385
Rep status :ACTIVE
Response:X
EOF

step 3 "Invalidating master active" <<EOF
echo comment \$where >control
ttIsqlCS -v1 -e"autocommit 0; call ttrampolicyset('inuse',0); call ttreppolicyset('norestart'); commitdurable; call invalidate; exit" "TTC_SERVER=$host1;TTC_SERVER_DSN=$dsn1;TCP_PORT=$serverport1;uid=adm;pwd=adm"
EOF
expectResponse <<EOF
  994: Data store connection terminated. Please reconnect.
EOF

step 4 "Reading data after failure" <<EOF
echo step >control
EOF
expectResponse <<EOF
Executing step
Error:[TimesTen][TimesTen 11.2.1.8.0 CLIENT]Statement handle invalid due to client failover
EOF

step 5 "Activate standby node" <<EOF
echo comment \$where >control
ttIsqlCS -v1 -e"call ttrepstateset('active'); exit" "TTC_SERVER=$host2;TTC_SERVER_DSN=$dsn2;TCP_PORT=$serverport2;uid=adm;pwd=adm"
EOF
waitForStateChange $dsn2 $host2 $serverport2 ACTIVE

step 6 "Reading data after failover from standby"  <<EOF
        echo step >control
EOF
expectResponse <<EOF
Executing step
Remote host:repdb2_1121@ozone2:53385
Rep status :ACTIVE
Response:X
EOF

step 7 "Recovering master active to Standby mode" <<EOF
echo comment \$where >control
ttIsqlCS -v1 -e"call ttrepstart; host sleep 5; call ttrepstateget;exit" "TTC_SERVER=$host1;TTC_SERVER_DSN=$dsn1;TCP_PORT=$serverport1;uid=adm;pwd=adm"
EOF
expectResponse <<EOF
< STANDBY, NO GRID >
EOF

step 8 "Setting master1 to active and master2 to standby" <<EOF
echo comment \$where >control
ttIsqlCS -v1 -e"call ttRepSubscriberWait('_ACTIVESTANDBY','TTREP',,,60);exit" "TTC_SERVER=$host2;TTC_SERVER_DSN=$dsn2;TCP_PORT=$serverport2;uid=adm;pwd=adm"
ttIsqlCS -v1 -e"call ttrepstop; call ttrepdeactivate; exit" "TTC_SERVER=$host2;TTC_SERVER_DSN=$dsn2;TCP_PORT=$serverport2;uid=adm;pwd=adm"
ttIsqlCS -v1 -e"call ttrepstateset('ACTIVE'); exit" "TTC_SERVER=$host1;TTC_SERVER_DSN=$dsn1;TCP_PORT=$serverport1;uid=adm;pwd=adm"
ttIsqlCS -v1 -e"call ttrepstart;exit" "TTC_SERVER=$host2;TTC_SERVER_DSN=$dsn2;TCP_PORT=$serverport2;uid=adm;pwd=adm"
EOF
expectResponse <<EOF
< 00 >
EOF
echoTab "   |--waiting for master1 status change"; waitForStateChange $dsn1 $host1 $serverport1 ACTIVE
echoTab "   \--waiting for master2 status change"; waitForStateChange $dsn2 $host2 $serverport2 STANDBY

step 9 "Invalidating master active" <<EOF
echo comment \$where >control
ttIsqlCS -v1 -e"autocommit 0; call ttrampolicyset('inuse',0); call ttreppolicyset('norestart'); commitdurable; call invalidate; exit" "TTC_SERVER=$host1;TTC_SERVER_DSN=$dsn1;TCP_PORT=$serverport1;uid=adm;pwd=adm"
EOF
expectResponse <<EOF
  994: Data store connection terminated. Please reconnect.
EOF

step 10 "Reading data after failure " <<EOF
sleep 10
echo step >control
EOF
expectResponse <<EOF
Executing step
Error:[TimesTen][TimesTen 11.2.1.8.0 CLIENT]Statement handle invalid due to client failover
EOF

step 11 "Reading data after failure " <<EOF
sleep 10
echo step >control
EOF
expectResponse <<EOF
Executing step
Remote host:repdb1_1121@ozone2:53385
Rep status :ACTIVE
Response:X
EOF

step 12 "Activate master1 node" <<EOF
echo comment \$where >control
ttIsqlCS -v1 -e"call ttrepstart; call ttrepstateset('active'); call ttrepstateget; exit" "TTC_SERVER=$host1;TTC_SERVER_DSN=$dsn1;TCP_PORT=$serverport1;uid=adm;pwd=adm"
ttIsqlCS -v1 -e"call ttrepstateget; exit" "TTC_SERVER=$host2;TTC_SERVER_DSN=$dsn2;TCP_PORT=$serverport2;uid=adm;pwd=adm"
EOF
expectResponse <<EOF
< ACTIVE, NO GRID >
< STANDBY, NO GRID >
EOF

step 13 "Finishing" <<EOF
echo exit >control
EOF
expectResponse <<EOF
Done.
EOF

sleep 2
