#!/bin/bash

if [ -f $(dirname $0)/../cfg/failover.env ]; then . $(dirname $0)/../cfg/failover.env; fi
if [ -f cfg/failover.env ];then . cfg/failover.env; fi

#read parameters
eval $(echo $@ | sed "s/ -/;/g" | sed "s/^-//" | tr ' ' '=')

#check parameters
if [ -z "$host1" ] || [ -z "$dsn1" ] || [ -z "$osuser" ] || [ -z "$host2" ] || [ -z "$dsn2" ]; then 
	echo Params!
	exit 1
fi

if [ "$mode" == "" ]; then
	echo -----------------------------------------------------
  	echo I. Clone script\(s\) to $host2
	echo Note: you may be asked for ssh password
	echo -----------------------------------------------------
        for host in $host1 $host2; do
          ssh $osuser@$host "mkdir /tmp/ttadmin /tmp/ttadmin/bin /tmp/ttadmin/log /tmp/ttadmin/cfg" 
          scp $testbin/*.sh $testbin/*.h $osuser@$host:/tmp/ttadmin/bin
          scp $testbin/cfg/* $osuser@$host:/tmp/ttadmin/cfg
        done
	echo -----------------------------------------------------
        echo II. Setting time at $host1, $host2 
        echo Note: you may be asked for ssh password
        echo -----------------------------------------------------
	ssh $osuser@$host1 "/usr/sbin/ntpdate -s -b -p 8 -u 129.132.2.21"
	ssh $osuser@$host2 "/usr/sbin/ntpdate -s -b -p 8 -u $host1"
	echo -----------------------------------------------------
	echo III. Executing locally...
	echo -----------------------------------------------------
        ssh $osuser@$host1 <<EOF
	        bash /tmp/ttadmin/bin/$(basename $0) $@ -mode local
EOF
	echo -----------------------------------------------------
	echo IV. Executing remotely...
        echo Note: you may be asked for ssh password
	echo -----------------------------------------------------
	ssh $osuser@$host2 <<EOF
		bash /tmp/ttadmin/bin/$(basename $0) $@ -mode remote
EOF
	exit
fi


export ttadmin_home=/tmp/ttadmin
PATH=$ttadmin_home/bin:$PATH
. common.h; . secure.h; . failover.h

if [ "$mode" == "local" ]; then
	echo Executing on $(hostname)
	#put local logic here...

	cachecfg=/tmp/ttadmin/cfg/replication1.env
	cat >/tmp/ttadmin/cfg/replication1.env <<EOF
        define dsn1=$dsn1
        define dsn2=$dsn2
        define dsn=$dsn1
        define ttinst=$(ttversion | grep "Instance home directory" | cut -f2 -d: | tr -d " ")
EOF

readcfg /tmp/ttadmin/cfg/replication1.env
echoTab "Removing sample replication datastore"; echo
ttDaemonAdmin -stopserver >/dev/null 2>/dev/null
ttDatastoreDown.sh -invalidate $dsn
ttForcedDestroy.sh $dsn confirm force
ttDaemonAdmin -startServer >/dev/null 2>/dev/null

runSQL "1. Create an Active Master Database" <<EOF
        call ttRamPolicySet('manual');
EOF

runSQL "2. a) Create a database user"<<EOF
        create user adm identified by adm;
        grant admin to adm;
EOF

runSQL "2. b) Create an application osuser" <<EOF
        create user appuser identified by appuser;
        grant create session, create table to appuser;
EOF

cat $ttinst/quickstart/sample_scripts/replication/create_appuser_obj.sql | grep -v "drop table" >/tmp/create_appuser_obj.sql
runSQL "2. c) Run the script create_appuser_obj.sql" <<EOF
        connect "dsn=$dsn;uid=appuser;pwd=appuser";
        run "/tmp/create_appuser_obj.sql"
EOF

runSQL "3.Define the active standby pair" <<EOF
        connect "dsn=$dsn;uid=adm;pwd=adm"; 
        create active standby pair $dsn1 on $host1, $dsn2 on $host2;
        repschemes;
EOF

tcp_port=$(ttstatus | grep "TimesTen server pid" | cut -f8 -d" ")
runSQL "Create node info table" <<EOF
        disconnect;
        connect "dsn=$dsn1;uid=appuser;pwd=appuser";
        create table nodeinfo (key varchar(20), value varchar(100));
        insert into nodeinfo values ('dsn', '$dsn1');
        insert into nodeinfo values ('host', '$host1'); 
        insert into nodeinfo values ('serverport', '$tcp_port');
        insert into nodeinfo values ('dsn@host', '$dsn1@$host1');
        insert into nodeinfo values ('dsn@host:serverport', '$dsn1@$host1:$tcp_port');
EOF

runSQL "4. Start the replication agent" <<EOF
        call ttrepstart;
EOF

runSQL "5. Set the replication state to Active" <<EOF
        call ttrepstateset ('active');
        call ttrepstateget;
EOF
waitForStateChange ACTIVE

runSQL "Prepare data to verify that replication works" <<EOF
        disconnect;
        connect "dsn=$dsn1;uid=appuser;pwd=appuser";
        autocommit off;
        insert into orders values (6853180,1121,'9999999999', sysdate);
        commit;
EOF

fi #end of local execution

if [ "$mode" == "remote" ]; then
	echo Executing on $(hostname)
	#put remote logic here...

	cachecfg=/tmp/ttadmin/cfg/replication2.env
        cat >/tmp/ttadmin/cfg/replication2.env <<EOF
        define dsn1=$dsn1
        define dsn2=$dsn2
        define dsn=$dsn2
        define ttinst=$(ttversion | grep "Instance home directory" | cut -f2 -d: | tr -d " ")
EOF

readcfg /tmp/ttadmin/cfg/replication2.env
echoTab "Removing sample replication datastore": echo
ttDaemonAdmin -stopserver >/dev/null 2>/dev/null
ttDatastoreDown.sh -invalidate $dsn
ttForcedDestroy.sh $dsn confirm force
ttDaemonAdmin -startServer >/dev/null 2>/dev/null

echoTab "6. Duplicate the active database to the standby"; echo
ttrepadmin -duplicate -drop appuser.nodeinfo -from $dsn1 -host $host1 -localhost $host2 -uid adm -pwd adm -verbosity 2 $dsn

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
        insert into nodeinfo values ('host', '$host2');
        insert into nodeinfo values ('serverport', '$tcp_port');
        insert into nodeinfo values ('dsn@host', '$dsn2@$host2');
        insert into nodeinfo values ('dsn@host:serverport', '$dsn2@$host2:$tcp_port');
EOF
        
runSQL "7. Start the replication agent" <<EOF
        connect "dsn=$dsn;uid=adm;pwd=adm";
        call ttrepstart;
EOF

waitForStateChange STANDBY

runSQL "8. Verify the data is being replicated" <<EOF
        disconnect;
        connect "dsn=$dsn2;uid=appuser;pwd=appuser";
        autocommit off;
        insert into orders_ref values (6853180);
        commit;
EOF
fi #end of remote execution

rm -fr /tmp/ttadmin

