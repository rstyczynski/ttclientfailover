#!/bin/bash

. failover.start

step 100 "Initializing test" <<EOF
echo "\$stepId connect TTC_SERVER=$host1;TTC_SERVER_DSN=$dsn1;TCP_PORT=$serverport1;TTC_SERVER2=$host2;TTC_SERVER_DSN2=$dsn2;TCP_PORT2=$serverport2;uid=appuser;pwd=appuser" >control
EOF
expectResponse <<EOF
Connected to:TTC_SERVER=$host1;TTC_SERVER_DSN=$dsn1;TCP_PORT=$serverport1;TTC_SERVER2=$host2;TTC_SERVER_DSN2=$dsn2;TCP_PORT2=$serverport2;uid=appuser;pwd=appuser
EOF

step 700 "Crashing master1" <<EOF
	echo comment \$where >control
EOF
masterDown

step 710 "Reading data after failure" <<EOF
	echo \$stepId select >control
EOF
expectResponse <<EOF
Select
EOF
echoTab "\----checking expected exception"
expectError <<EOF
class java.sql.SQLException	S1000	47137	[TimesTen][TimesTen 11.2.1.8.0 CLIENT]Statement handle invalid due to client failover
EOF

step 720 "Reading data after failure" <<EOF
	echo \$stepId select >control
EOF
expectResponse <<EOF
Select
EOF
echoTab "\----checking expected execution time"
expectStepTime between 57000 62000

echoTab "\----checking expected exception"
expectError <<EOF
class java.sql.SQLException	08001	821	[TimesTen][TimesTen 11.2.1.8.0 ODBC Driver][TimesTen]TT0821: No readable checkpoint files.  OS error: 'No such file or directory'.  Consider connecting with Overwrite=1 to create new data store -- file "db.c", lineno 9722, procedure "sbDbConnect"
EOF

#echoTab "\--waiting longer than TTC_TIMEOUT"
#spinner $TIMEOUT 0.1
#echo Done.

step 730 "Reading data after failure"  <<EOF
	echo \$stepId select >control
EOF
expectResponse <<EOF
Select
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
        echo \$stepId select >control
EOF
expectResponse <<EOF
Select
EOF
echoTab "\----checking expected exception"
expectError <<EOF
class java.sql.SQLException	S1000	0	General error
EOF

step 900 "Application recreates connection" <<EOF
echo "\$stepId connect TTC_SERVER=$host1;TTC_SERVER_DSN=$dsn1;TCP_PORT=$serverport1;TTC_SERVER2=$host2;TTC_SERVER_DSN2=$dsn2;TCP_PORT2=$serverport2;uid=appuser;pwd=appuser" >control
EOF
expectResponse <<EOF
Connected to:TTC_SERVER=$host1;TTC_SERVER_DSN=$dsn1;TCP_PORT=$serverport1;TTC_SERVER2=$host2;TTC_SERVER_DSN2=$dsn2;TCP_PORT2=$serverport2;uid=appuser;pwd=appuser
EOF

step 910 "Reading data from master1" <<EOF
        echo \$stepId select >control
EOF
expectResponse <<EOF
Select
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

