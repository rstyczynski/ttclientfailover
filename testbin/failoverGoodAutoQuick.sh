#!/bin/bash

. failover.start

function stop {
  echoTab "Stoping"
  kill %"bash /tmp/activateStandby.sh"
  kill %"bash /tmp/errorlogListener.sh"
  echo Done.
}


step 100 "Initializing test" <<EOF
echo "\$stepId connect TTC_SERVER=$host1;TTC_SERVER_DSN=$dsn1;TCP_PORT=$serverport1;TTC_SERVER2=$host2;TTC_SERVER_DSN2=$dsn2;TCP_PORT2=$serverport2;uid=appuser;pwd=appuser" >control
EOF
expectResponse <<EOF
Connected to:TTC_SERVER=$host1;TTC_SERVER_DSN=$dsn1;TCP_PORT=$serverport1;TTC_SERVER2=$host2;TTC_SERVER_DSN2=$dsn2;TCP_PORT2=$serverport2;uid=appuser;pwd=appuser
EOF

errorlog=$PWD/$testId.log
failure=$PWD/failure
if [ ! -e "$failure" ]; then mkfifo $failure; fi

state=$(getNodesStatus | cut -f1 -d , | tr -d '[ ,<]' | tr '\n' '-' | sed s/-$//g)
echoTab "Initial state"; echo $state
case $state in
STANDBY-ACTIVE)
  connstr="TTC_SERVER=$host1;TTC_SERVER_DSN=$dsn1;TCP_PORT=$serverport1;uid=adm;pwd=adm"
  ;;
ACTIVE-STANDBY)
  connstr="TTC_SERVER=$host2;TTC_SERVER_DSN=$dsn2;TCP_PORT=$serverport2;uid=adm;pwd=adm"
  ;;
esac

echoTab "Starting automated failover listener" 
cat <<EOF >/tmp/activateStandby.sh
while read exception ; do
	echo START ----------------
	date
        echo "Activating STANDBY node, cause: \$exception"
        ttIsqlCS -e"call ttrepstateset('ACTIVE');exit" -connstr '$connstr'
        echo STOP -----------------
done <$failure
EOF
bash /tmp/activateStandby.sh >>$testId.activateStandby.log 2>>$testId.activateStandby.err &
echo Done.

echoTab "Starting error log watch process" 
cat <<EOF >/tmp/errorlogListener.sh 
	tail -0 -f $errorlog | perl -nle "$| = 1;print if /Statement handle invalid due to client failover/" >$failure
EOF
bash /tmp/errorlogListener.sh & 
echo Done.

step 150 "Reading data before failure" <<EOF
        echo \$stepId oneselect >control
EOF
expectResponse <<EOF
OneSelect
Status:ACTIVE
EOF

step 200 "Crashing master1" <<EOF
	echo \$stepId comment \$where >control
EOF
masterDown

step 210 "Reading data after failure" <<EOF
	echo \$stepId oneselect >control
EOF
expectResponse <<EOF
OneSelect
EOF
echoTab "\----checking expected exception"
expectError <<EOF
class java.sql.SQLException	S1000	47137	[TimesTen][TimesTen 11.2.1.8.0 CLIENT]Statement handle invalid due to client failover
EOF

step 300 "Reading data after failure" <<EOF
	echo \$stepId oneselect >control
EOF
expectResponse <<EOF
OneSelect
Status:ACTIVE
EOF
echoTab "\----checking expected execution time"
expectStepTime between 0 500
 
step 400 "Recovering master active" <<EOF
        echo \$stepId comment \$where >control
EOF
masterUp

step 410 "Waiting for master1 to be Standby" <<EOF
        echo \$stepId comment \$where >control
EOF
waitForRemoteStateChange $dsn1 $host1 $serverport1 STANDBY

step 1000 "Finishing" <<EOF
	echo \$stepId exit >control
EOF
expectResponse <<EOF
Done.
EOF

stop

  echo Summary | tee -a $testId.log
  echo --------------------- | tee -a $testId.log
  getTestSummary  | tee -a $testId.log
  listFailedSteps | tee -a $testId.log
  getTestEnvironment $user "$host1 $host2"

