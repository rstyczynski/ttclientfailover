#!/bin/bash

# ----------------------------------------------------------------------------------------------------------------------------------
# ----------------------------------------------------------------------------------------------------------------------------------
# ----------------------------------------------------------------------------------------------------------------------------------
# --------------------------------- DO NOT EDIT BELOW LINES. CHANGABLE CODE IS FEW PAGES BELOW -------------------------------------
# ----------------------------------------------------------------------------------------------------------------------------------
# ----------------------------------------------------------------------------------------------------------------------------------
# ----------------------------------------------------------------------------------------------------------------------------------

failureType=invalidate
#serverDown
#invalidate
#networkDown
#daemonDown

#delte tterrors.log before test
deleteTimesTenLog=YES
#each step will be marked in tterrors.log
updateTimesTenLog=YES

testId=Failover01

#parameters of master1 data store
dsn1=repdb1_1121
host1=ozone1
host1mgm=192.168.141.138
serverport1=53389

#parameters of mater2 data store
dsn2=repdb2_1121
host2=ozone2
host2mgm=192.168.141.139
serverport2=53385

#os user used for ssh 
osuser=oracle

TIMEOUT=1250
TIMEOUT_SHORT=120

#Parse parameters. echo pair of '-parameter value' will be executed as 'parameter=value'. Parameter will be available in script as $parameter
eval $(echo $@ | sed "s/ -/;/g" | sed "s/^-//" | tr ' ' '=')

echo "$0 $@" >$testId.log

. $testbin/common.h; . $testbin/test.h

trap stop SIGHUP SIGINT SIGTERM SIGQUIT SIGSTOP

rm control &>/dev/null
mkfifo control &>/dev/null

if [ ! -d "$tmp" ]; then tmp=/tmp; fi
rm $tmp/*$testId* >/dev/null 2>&1
rm $testId* >/dev/null 2>&1

ttDeleteLogsInSystem

step=0
java -classpath $testbin:$CLASSPATH:$(eval $(ttversion -m);echo $effective_insthome/lib) -d32 -jar $testbin/ttclientfailover.jar $testId < control >out.log 2>out.err&

# ----------------------------------------------------------------------------------------------------------------------------------
# ----------------------------------------------------------------------------------------------------------------------------------
# ----------------------------------------------------------------------------------------------------------------------------------
# -------------------------------------------- YOU MAY EDIT TEST SCRIPT FROM THIS PLACE --------------------------------------------
# ----------------------------------------------------------------------------------------------------------------------------------
# ----------------------------------------------------------------------------------------------------------------------------------
# ----------------------------------------------------------------------------------------------------------------------------------

step 10 "Synchronize clocks oh $host1, $host2" <<EOF
        ssh root@$host1 "/sbin/service vmware-tools restart; /usr/sbin/ntpdate -s -b -p 8 -u 129.132.2.21" &>/dev/null
        ssh root@$host2 "/sbin/service vmware-tools restart; /usr/sbin/ntpdate -s -b -p 8 -u 129.132.2.21" &>/dev/null
EOF
echo Done.

step 100 "Initializing test" <<EOF
echo "\$stepId connect TTC_SERVER=$host1;TTC_SERVER_DSN=$dsn1;TCP_PORT=$serverport1;TTC_SERVER2=$host2;TTC_SERVER_DSN2=$dsn2;TCP_PORT2=$serverport2;uid=appuser;pwd=appuser" >control
EOF
expectResponse <<EOF
Connection string:TTC_SERVER=$host1;TTC_SERVER_DSN=$dsn1;TCP_PORT=$serverport1;TTC_SERVER2=$host2;TTC_SERVER_DSN2=$dsn2;TCP_PORT2=$serverport2;uid=appuser;pwd=appuser
EOF

step 110 "Reading data from active" <<EOF
	echo \$stepId step >control
EOF
expectResponse <<EOF
Step
Host:$dsn1@$host1:$serverport1
Status:ACTIVE
Resp:X
EOF

step 200 "Crashing master1" <<EOF
	echo \$stepId comment \$where >control
EOF
masterDown

step 210 "Reading data after failure" <<EOF
	echo \$stepId step >control
EOF
expectResponse <<EOF
Step
EOF
echoTab "\----checking expected exception"
expectError <<EOF
class java.sql.SQLException	S1000	47137	[TimesTen][TimesTen 11.2.1.8.0 CLIENT]Statement handle invalid due to client failover
EOF

step 300 "Activate standby node" <<EOF
	echo \$stepId comment \$where >control
	ttIsqlCS -v1 -e"call ttrepstateset('active'); call ttrepstateget; exit" "TTC_SERVER=$host2;TTC_SERVER_DSN=$dsn2;TCP_PORT=$serverport2;uid=adm;pwd=adm"
EOF
waitForStateChange $dsn2 $host2 $serverport2 ACTIVE

step 310 "Reading data from master2 after failover"  <<EOF
        echo \$stepId step >control
EOF
expectResponse <<EOF
Step
Host:$dsn2@$host2:$serverport2
Status:ACTIVE
Resp:X
EOF

step 400 "Recovering master active" <<EOF
	echo \$stepId comment \$where >control
EOF
masterUp

step 405 "Waiting for master1 state change to STANDBY" <<EOF
        echo \$stepId comment \$where >control
EOF
waitForStateChange $dsn1 $host1 $serverport1 STANDBY

step 410 "Reading data from master2"  <<EOF
        echo \$stepId step >control
EOF
expectResponse <<EOF
Step
Host:$dsn2@$host2:$serverport2
Status:ACTIVE
Resp:X
EOF

step 500 "Connecting application to Standby-Active" <<EOF
echo "\$stepId connect TTC_SERVER=$host1;TTC_SERVER_DSN=$dsn1;TCP_PORT=$serverport1;TTC_SERVER2=$host2;TTC_SERVER_DSN2=$dsn2;TCP_PORT2=$serverport2;uid=appuser;pwd=appuser" >control
EOF
expectResponse <<EOF
Connection string:TTC_SERVER=$host1;TTC_SERVER_DSN=$dsn1;TCP_PORT=$serverport1;TTC_SERVER2=$host2;TTC_SERVER_DSN2=$dsn2;TCP_PORT2=$serverport2;uid=appuser;pwd=appuser
Event listener removed from previuous connection
EOF

step 510 "Reading data from master2" <<EOF
        echo \$stepId step >control
EOF
expectResponse <<EOF
Step
Host:$dsn2@$host2:$serverport2
Status:ACTIVE
Resp:X
EOF


step 600 "Switchover: setting master2 to IDLE" <<EOF
	echo \$stepId comment \$where >control
	ttIsqlCS -v1 -e"call ttRepSubscriberWait('_ACTIVESTANDBY','TTREP',,,60); exit" "TTC_SERVER=$host2;TTC_SERVER_DSN=$dsn2;TCP_PORT=$serverport2;uid=adm;pwd=adm"
	ttIsqlCS -v1 -e"call ttrepstop; call ttrepdeactivate; call ttrepstateget; exit" "TTC_SERVER=$host2;TTC_SERVER_DSN=$dsn2;TCP_PORT=$serverport2;uid=adm;pwd=adm"
EOF
expectResponse <<EOF
< 00 >
< IDLE, NO GRID >
EOF

step 601 "Switchover: setting master1 to ACTIVE" <<EOF
        echo \$stepId comment \$where >control
	ttIsqlCS -v1 -e"call ttrepstateset('ACTIVE'); exit" "TTC_SERVER=$host1;TTC_SERVER_DSN=$dsn1;TCP_PORT=$serverport1;uid=adm;pwd=adm"
EOF
waitForStateChange $dsn1 $host1 $serverport1 ACTIVE

step 602 "Switchover: setting master2 to STANDBY" <<EOF
        echo \$stepId comment \$where >control
	ttIsqlCS -v1 -e"call ttrepstart;exit" "TTC_SERVER=$host2;TTC_SERVER_DSN=$dsn2;TCP_PORT=$serverport2;uid=adm;pwd=adm"
EOF
waitForStateChange $dsn2 $host2 $serverport2 STANDBY

step 610 "Reading data from master1 after switchover"  <<EOF
        echo \$stepId step >control
EOF
expectResponse <<EOF
Step
Host:$dsn1@$host1:$serverport1
Status:ACTIVE
Resp:X
EOF

step 700 "Crashing master1" <<EOF
	echo comment \$where >control
EOF
masterDown

step 710 "Reading data after failure" <<EOF
	echo \$stepId step >control
EOF
expectResponse <<EOF
Step
EOF
echoTab "\----checking expected exception"
expectError <<EOF
class java.sql.SQLException	S1000	47137	[TimesTen][TimesTen 11.2.1.8.0 CLIENT]Statement handle invalid due to client failover
EOF

step 720 "Reading data after failure" <<EOF
	echo \$stepId step >control
EOF
expectResponse <<EOF
Step
EOF
echoTab "\----checking expected exception"
expectError <<EOF
class java.sql.SQLException	08001	821	[TimesTen][TimesTen 11.2.1.8.0 ODBC Driver][TimesTen]TT0821: No readable checkpoint files.  OS error: 'No such file or directory'.  Consider connecting with Overwrite=1 to create new data store -- file "db.c", lineno 9722, procedure "sbDbConnect"
EOF

#echoTab "\--waiting longer than TTC_TIMEOUT"
#spinner $TIMEOUT 0.1
#echo Done.

step 730 "Reading data after failure"  <<EOF
	echo \$stepId step >control
EOF
expectResponse <<EOF
Step
EOF
echoTab "\----checking expected exception"
expectError <<EOF
class java.sql.SQLException	S1000	0	General error
EOF

step 800 "Recovering master active" <<EOF
	echo \$stepId comment \$where >control
EOF
masterUp

step 810 "Activate master1 node" <<EOF
	echo \$stepId comment \$where >control
	ttIsqlCS -v1 -e"call ttrepstateset('active'); call ttrepstateget; exit" "TTC_SERVER=$host1;TTC_SERVER_DSN=$dsn1;TCP_PORT=$serverport1;uid=adm;pwd=adm"
	ttIsqlCS -v1 -e"call ttrepstateget; exit" "TTC_SERVER=$host2;TTC_SERVER_DSN=$dsn2;TCP_PORT=$serverport2;uid=adm;pwd=adm"
EOF
expectResponse <<EOF
< ACTIVE, NO GRID >
< STANDBY, NO GRID >
EOF

step 820 "Reading data from active" <<EOF
        echo \$stepId step >control
EOF
expectResponse <<EOF
Step
EOF
echoTab "\----checking expected exception"
expectError <<EOF
class java.sql.SQLException	S1000	0	General error
EOF

step 900 "Application recreates connection" <<EOF
echo "\$stepId connect TTC_SERVER=$host1;TTC_SERVER_DSN=$dsn1;TCP_PORT=$serverport1;TTC_SERVER2=$host2;TTC_SERVER_DSN2=$dsn2;TCP_PORT2=$serverport2;uid=appuser;pwd=appuser" >control
EOF
expectResponse <<EOF
Connection string:TTC_SERVER=$host1;TTC_SERVER_DSN=$dsn1;TCP_PORT=$serverport1;TTC_SERVER2=$host2;TTC_SERVER_DSN2=$dsn2;TCP_PORT2=$serverport2;uid=appuser;pwd=appuser
Event listener removed from previuous connection
Warning: Not possible to close previous connection
EOF

step 910 "Reading data from master1" <<EOF
        echo \$stepId step >control
EOF
expectResponse <<EOF
Step
Host:$dsn1@$host1:$serverport1
Status:ACTIVE
Resp:X
EOF

step 1000 "Finishing" <<EOF
	echo \$stepId exit >control
EOF
expectResponse <<EOF
Done.
EOF

