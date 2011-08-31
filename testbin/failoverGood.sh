#!/bin/bash

readcfg failover.env
. failover.start

step 10 "Synchronize clocks oh $host1, $host2" <<EOF
	ssh root@$host2 "/usr/sbin/ntpdate -u $host1"
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


step 1000 "Finishing" <<EOF
	echo \$stepId exit >control
EOF
expectResponse <<EOF
Done.
EOF
