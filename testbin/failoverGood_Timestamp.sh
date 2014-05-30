#!/bin/bash

. failover.start

step 10 "Synchronize clocks oh $host1, $host2" <<EOF
	ssh root@$host2 "/usr/sbin/ntpdate -u $host1"
EOF
echo Done.

step 100 "Initializing test" <<EOF
echo "\$stepId connect TTC_SERVER=$host1;TTC_SERVER_DSN=$dsn1;TCP_PORT=$serverport1;TTC_SERVER2=$host2;TTC_SERVER_DSN2=$dsn2;TCP_PORT2=$serverport2;uid=appuser;pwd=appuser" >control
EOF
expectResponse <<EOF
Connected to:TTC_SERVER=$host1;TTC_SERVER_DSN=$dsn1;TCP_PORT=$serverport1;TTC_SERVER2=$host2;TTC_SERVER_DSN2=$dsn2;TCP_PORT2=$serverport2;uid=appuser;pwd=appuser
EOF
echoTab "\----checking expected exception"
expectError <<EOF
EOF

step 110 "Reading data from active" <<EOF
	echo \$stepId select >control
EOF
expectResponse <<EOF
Select
Host:$dsn1@$host1:$serverport1
Status:ACTIVE
Resp:X
EOF

step 120 "Initializing timefield SQL commands" <<EOF
	echo \$stepId init TIME >control
EOF
expectResponse <<EOF
Initialized INSERT: insert into timestampTest values (?,?)
Initialized SELECT: select id, timefield from timestampTest where id=? and timefield=?
Initialized SELECT_TODATE: select id, timefield from timestampTest where id=? and timefield=to_date(?,'DD-MON-RR HH.MI.SSXFF AM')
Initialized UPDATE: update timestampTest set timefield=? where id=?
Initialized UPDATE2: update timestampTest set timefield=? where id=? and timefield<=?
Initialized UPDATE_TODATE: update timestampTest set timefield=to_date(?,'DD-MON-RR HH.MI.SSXFF AM') where id=? and timefield<=to_date(?,'DD-MON-RR HH.MI.SSXFF AM')
Initialized DELETE: delete from timestampTest where id<(?+1)
Initialized DELETE2: delete from timestampTest where id=? and timefield=?
Initialized DELETE_TODATE: delete from timestampTest where id=? and timefield=to_date(?,'DD-MON-RR HH.MI.SSXFF AM')
Statement(s) initialized
EOF

step 125 "Deleting previously inserted data" <<EOF
	echo \$stepId quick TIME DELETE 2 >control
EOF
expectResponse <<EOF
DELETE done with pk=2
EOF
echoTab "\----checking expected exception"
expectError <<EOF
EOF

step 130 "Writing data to timestamp field" <<EOF
	echo \$stepId quick TIME INSERT 1 13-Mar-73 6.0.0 >control
EOF
expectResponse <<EOF
INSERT done with pk=1, timestamp=1973-03-13 06:00:00.0
EOF
echoTab "\----checking expected exception"
expectError <<EOF
EOF

step 140 "Updating data in timestamp field" <<EOF
        echo \$stepId quick TIME UPDATE 1 14-Mar-73 7.0.0 >control
EOF
expectResponse <<EOF
UPDATE done with pk=1, timestamp=1973-03-14 07:00:00.0
EOF
echoTab "\----checking expected exception"
expectError <<EOF
EOF

step 145 "Updating data in timestamp field and TO_DATE conversion" <<EOF
        echo \$stepId quick TIME UPDATE_TODATE 1 15-Mar-73 8.0.0 >control
EOF
expectResponse <<EOF
UPDATE_TODATE done with pk=1, timestamp=1973-03-15 08:00:00.0
EOF
echoTab "\----checking expected exception"
expectError <<EOF
EOF

step 150 "Reading data" <<EOF
        echo \$stepId quick TIME SELECT 1 15-Mar-73 8.0.0 >control
EOF
expectResponse <<EOF
Resp:1
SELECT done with pk=1, timestamp=1973-03-15 08:00:00.0
EOF
echoTab "\----checking expected exception"
expectError <<EOF
EOF

step 200 "Crashing master1" <<EOF
	echo \$stepId comment \$where >control
EOF
masterDown master1

step 210 "Reading data after failure" <<EOF
	echo \$stepId select >control
EOF
expectResponse <<EOF
Select
EOF
echoTab "\----checking expected exception"
expectError <<EOF
class java.sql.SQLException	S1000	47137	[TimesTen][TimesTen $ttVersion CLIENT]Statement handle invalid due to client failover
EOF

step 300 "Activate standby node" <<EOF
	echo \$stepId comment \$where >control
	ttIsqlCS -v1 -e"call ttrepstateset('active'); call ttrepstateget; exit" "TTC_SERVER=$host2;TTC_SERVER_DSN=$dsn2;TCP_PORT=$serverport2;uid=adm;pwd=adm" 
	#waitForRemoteStateChange $dsn2 $host2 $serverport2 ACTIVE
EOF
expectResponse <<EOF
< ACTIVE, NO GRID >
EOF

step 310 "Reading data from master2 after failover"  <<EOF
        echo \$stepId select >control
EOF
expectResponse <<EOF
Select
Host:$dsn2@$host2:$serverport2
Status:ACTIVE
Resp:X
EOF

step 410 "Using prepared statement after failover" <<EOF
	echo \$stepId quick TIME SELECT 1 15-Mar-73 8.0.0 >control
EOF
expectResponse <<EOF
EOF
echoTab "\----checking expected exception"
expectError <<EOF
class java.sql.SQLException	S1000	47137	[TimesTen][TimesTen $ttVersion CLIENT]Statement handle invalid due to client failover
EOF

step 420 "Reinitializing timefield SQL commands" <<EOF
        echo \$stepId init TIME >control
EOF
expectResponse <<EOF
Initialized INSERT: insert into timestampTest values (?,?)
Initialized SELECT: select id, timefield from timestampTest where id=? and timefield=?
Initialized SELECT_TODATE: select id, timefield from timestampTest where id=? and timefield=to_date(?,'DD-MON-RR HH.MI.SSXFF AM')
Initialized UPDATE: update timestampTest set timefield=? where id=?
Initialized UPDATE2: update timestampTest set timefield=? where id=? and timefield<=?
Initialized UPDATE_TODATE: update timestampTest set timefield=to_date(?,'DD-MON-RR HH.MI.SSXFF AM') where id=? and timefield<=to_date(?,'DD-MON-RR HH.MI.SSXFF AM')
Initialized DELETE: delete from timestampTest where id<(?+1)
Initialized DELETE2: delete from timestampTest where id=? and timefield=?
Initialized DELETE_TODATE: delete from timestampTest where id=? and timefield=to_date(?,'DD-MON-RR HH.MI.SSXFF AM')
Statement(s) initialized
EOF

step 430 "Writing data to timestamp field" <<EOF
        echo \$stepId quick TIME INSERT 2 13-Mar-73 6.0.0 >control
EOF
expectResponse <<EOF
INSERT done with pk=2, timestamp=1973-03-13 06:00:00.0
EOF
echoTab "\----checking expected exception"
expectError <<EOF
EOF

step 440 "Updating data in timestamp field" <<EOF
        echo \$stepId quick TIME UPDATE 1 15-Mar-73 8.0.0 >control
EOF
expectResponse <<EOF
UPDATE done with pk=1, timestamp=1973-03-15 08:00:00.0
EOF
echoTab "\----checking expected exception"
expectError <<EOF
EOF

step 445 "Updating data in timestamp field and TO_DATE conversion" <<EOF
        echo \$stepId quick TIME UPDATE_TODATE 1 15-Mar-73 8.0.0 >control
EOF
expectResponse <<EOF
UPDATE_TODATE done with pk=1, timestamp=1973-03-15 08:00:00.0
EOF
echoTab "\----checking expected exception"
expectError <<EOF
EOF



step 450 "Selecting data by PK and timestamp field" <<EOF
        echo \$stepId quick TIME SELECT 1 15-Mar-73 8.0.0 >control
EOF
expectResponse <<EOF
Resp:1
SELECT done with pk=1, timestamp=1973-03-15 08:00:00.0
EOF
echoTab "\----checking expected exception"
expectError <<EOF
EOF

step 500 "Recovering master active" <<EOF
        echo \$stepId comment \$where >control
EOF
masterUp

step 505 "Waiting for master1 state change to STANDBY" <<EOF
        echo \$stepId comment \$where >control
EOF
waitForRemoteStateChange $dsn1 $host1 $serverport1 STANDBY

step 510 "Reading data from master2"  <<EOF
        echo \$stepId select >control
EOF
expectResponse <<EOF
Select
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
