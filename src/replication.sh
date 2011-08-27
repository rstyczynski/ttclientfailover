#!/bin/bash

. common.h;. secure.h

cachecfg=$tmp/replication.env
cat >$tmp/replication1.env <<EOF
	define dsn1=repdb1_1121
	define dsn2=repdb2_1121
	define dsn=repdb1_1121
	define ttinst=$(ttversion | grep "Instance home directory" | cut -f2 -d: | tr -d " ")
EOF
cat >$tmp/replication2.env <<EOF
        define dsn1=repdb1_1121
        define dsn2=repdb2_1121
        define dsn=repdb2_1121
        define ttinst=$(ttversion | grep "Instance home directory" | cut -f2 -d: | tr -d " ")
EOF

readcfg $tmp/replication1.env
echoTab "Removing sample replication datastores"
ttDaemonAdmin -stopserver >/dev/null 2>/dev/null
for _dsn in $dsn1 $dsn2; do
	(
	ttAdmin -rampolicy inuse $_dsn
	ttAdmin -ramgrace 0 $_dsn
	ttAdmin -repstop $_dsn
	ttAdmin -cachestop $_dsn
        ttisql -e"call invalidate;exit" $_dsn	
	ttDestroy $_dsn
	) >/dev/null 2>/dev/null
done
ttDaemonAdmin -startServer >/dev/null 2>/dev/null
echo OK
	
runSQL "1. Create an Active Master Database" <<EOF
	call ttRamPolicySet('manual');
EOF

runSQL "2. a) Create a database user"<<EOF
	create user adm identified by adm; 
	grant admin to adm;
EOF

runSQL "2. b) Create an application user" <<EOF
	create user appuser identified by appuser;
	grant create session, create table to appuser;
EOF

cat $ttinst/quickstart/sample_scripts/replication/create_appuser_obj.sql | grep -v "drop table" >$tmp/create_appuser_obj.sql
runSQL "2. c) Run the script create_appuser_obj.sql" <<EOF
	connect "dsn=$dsn;uid=appuser;pwd=appuser";
 	run "$tmp/create_appuser_obj.sql"
EOF

runSQL "3.Define the active standby pair" <<EOF
	connect "dsn=$dsn;uid=adm;pwd=adm";
	create active standby pair &dsn1 on $(hostname), &dsn2 on $(hostname);
	repschemes;
EOF

tcp_port=$(ttstatus | grep "TimesTen server pid" | cut -f8 -d" ")
runSQL "Create node info table" <<EOF
	disconnect;
	connect "dsn=$dsn1;uid=appuser;pwd=appuser";
	create table nodeinfo (key varchar(20), value varchar(100));
	insert into nodeinfo values ('dsn', '$dsn1');
	insert into nodeinfo values ('host', '$(hostname)'); 
	insert into nodeinfo values ('serverport', '$tcp_port');
	insert into nodeinfo values ('dsn@host', '$dsn1@$(hostname)');
	insert into nodeinfo values ('dsn@host:serverport', '$dsn1@$(hostname):$tcp_port'); 	
EOF

runSQL "4. Start the replication agent" <<EOF
	call ttrepstart;
EOF

runSQL "5. Set the replication state to Active" <<EOF
	call ttrepstateset ('active');
	call ttrepstateget;
EOF
waitForStateChange ACTIVE

readcfg $tmp/replication2.env
echoTab "6. Duplicate the active database to the standby"; echo
ttrepadmin -duplicate -drop ALL -from $dsn1 -host "$(hostname)" -uid adm -pwd adm -verbosity 2 "dsn=$dsn"

runSQL "6. a) Create test table to check replication" <<EOF
	call ttRamPolicySet('manual');
        connect "dsn=$dsn;uid=appuser;pwd=appuser";
        create table appuser.orders_ref (order_number number not null, foreign key (order_number) references appuser.orders (order_number));
EOF

tcp_port=$(ttstatus | grep "TimesTen server pid" | cut -f8 -d" ")
runSQL "Create node info table" <<EOF
	disconnect;
	connect "dsn=$dsn2;uid=appuser;pwd=appuser";
        create table nodeinfo (key varchar(20), value varchar(100));
        insert into nodeinfo values ('dsn', '$dsn2');
        insert into nodeinfo values ('host', '$(hostname)'); 
        insert into nodeinfo values ('serverport', '$tcp_port');
        insert into nodeinfo values ('dsn@host', '$dsn2@$(hostname)');
	insert into nodeinfo values ('dsn@host:serverport', '$dsn2@$(hostname):$tcp_port');
EOF

runSQL "7. Start the replication agent" <<EOF
	connect "dsn=$dsn;uid=adm;pwd=adm";
	call ttrepstart;
EOF
waitForStateChange STANDBY

runSQL "8. Verify the data is being replicated between the active and the standby" <<EOF
	disconnect;
	connect "dsn=$dsn1;uid=appuser;pwd=appuser";
	autocommit off;
	insert into orders values (6853180,1121,'9999999999', sysdate);
	commit;
	host 'sleep 5';
	
	disconnect;
        connect "dsn=$dsn2;uid=appuser;pwd=appuser";
	autocommit off;
        insert into orders_ref values (6853180);
	commit;
EOF
