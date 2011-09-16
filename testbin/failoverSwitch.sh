#!/bin/bash

. failover.start

step 500 "Connecting application to A/S pair" <<EOF
echo "\$stepId connect TTC_SERVER=$host1;TTC_SERVER_DSN=$dsn1;TCP_PORT=$serverport1;TTC_SERVER2=$host2;TTC_SERVER_DSN2=$dsn2;TCP_PORT2=$serverport2;uid=appuser;pwd=appuser" >control
EOF
expectResponse <<EOF
Connected to:TTC_SERVER=$host1;TTC_SERVER_DSN=$dsn1;TCP_PORT=$serverport1;TTC_SERVER2=$host2;TTC_SERVER_DSN2=$dsn2;TCP_PORT2=$serverport2;uid=appuser;pwd=appuser
EOF

step 510 "Reading data from $dsn2@$host2 " <<EOF
        echo \$stepId select >control
EOF
expectResponse <<EOF
Select
Host:$dsn2@$host2:$serverport2
Status:ACTIVE
Resp:X
EOF


step 600 "Switchover: setting $dsn2@$host2 to IDLE" <<EOF
	echo \$stepId comment \$where >control
	ttIsqlCS -v1 -e"call ttRepSubscriberWait('_ACTIVESTANDBY','TTREP',,,60); exit" "TTC_SERVER=$host2;TTC_SERVER_DSN=$dsn2;TCP_PORT=$serverport2;uid=adm;pwd=adm"
	ttIsqlCS -v1 -e"call ttrepstop; call ttrepdeactivate; call ttrepstateget; exit" "TTC_SERVER=$host2;TTC_SERVER_DSN=$dsn2;TCP_PORT=$serverport2;uid=adm;pwd=adm"
EOF
expectResponse <<EOF
< 00 >
< IDLE, NO GRID >
EOF

step 605 "Reading data from $dsn2@$host2 in IDLE mode"  <<EOF
        echo \$stepId select >control
EOF
expectResponse <<EOF
Select
Host:$dsn2@$host2:$serverport2
Status:IDLE
Resp:X
EOF

step 606 "Writing data to $dsn2@$host2 in IDLE mode"  <<EOF
        echo \$stepId update 3700 PETER >control
EOF
expectResponse <<EOF
Update
Host:$dsn2@$host2:$serverport2
Status:IDLE
EOF
echoTab "\----checking expected exception"
expectError <<EOF
class java.sql.SQLException	S1000	8151	[TimesTen][TimesTen 11.2.1.8.0 ODBC Driver][TimesTen]TT8151: APPUSER.CUSTOMERS's replication role disallows the requested operation -- file "eeDML.c", lineno 6992, procedure "sbEeUpdColEval"
EOF

#601
step 610 "Switchover: setting $dsn1@$host1 to ACTIVE" <<EOF
        echo \$stepId comment \$where >control
	ttIsqlCS -v1 -e"call ttrepstateset('ACTIVE'); exit" "TTC_SERVER=$host1;TTC_SERVER_DSN=$dsn1;TCP_PORT=$serverport1;uid=adm;pwd=adm"
EOF
waitForRemoteStateChange $dsn1 $host1 $serverport1 ACTIVE

#602
step 620 "Switchover: setting $dsn2@$host2 to STANDBY" <<EOF
        echo \$stepId comment \$where >control
	ttIsqlCS -v1 -e"call ttrepstart;exit" "TTC_SERVER=$host2;TTC_SERVER_DSN=$dsn2;TCP_PORT=$serverport2;uid=adm;pwd=adm"
EOF
waitForRemoteStateChange $dsn2 $host2 $serverport2 STANDBY

#610..615
for stepNo in {630..635}; do
step $stepNo "Reading data from $dsn1@$host1 after switchover"  <<EOF
        echo \$stepId select >control
EOF
expectResponse <<EOF
Select
Host:$dsn1@$host1:$serverport1
Status:ACTIVE
Resp:X
EOF
done


step 1000 "Finishing" <<EOF
	echo \$stepId exit >control
EOF
expectResponse <<EOF
Done.
EOF

