#!/bin/bash

. $testbin/test.h
. $testbin/common.h
readcfg failover.env

testNo=0
ssh root@$host2 "/usr/sbin/ntpdate -u $host1"

for cnt in {1..4}; do

state=$(getNodesStatus | cut -f1 -d , | tr -d "[ , ><]" | tr '\n' '-' | sed s/-$//)
echoTab "Initial state"; echo $state 
let testNo++
testId=good$testNo
failoverGood.sh -testId $testId -dsn1 repdb1_1121 -host1 ozone1 -host1mgm 192.168.141.138 -serverport1 53389 -dsn2 repdb2_1121 -host2 ozone2 -host2mgm 192.168.141.139 -serverport2 53385 -deleteTimesTenLog NO -updateTimesTenLog YES

state=$(getNodesStatus | cut -f1 -d , | tr -d "[ , ><]" | tr '\n' '-' | sed s/-$//)
echoTab "Initial state"; echo $state 

case $state in
STANDBY-ACTIVE)
  testId=switch$testNo
  failoverSwitch.sh -testId $testId -dsn1 repdb1_1121 -host1 ozone1 -host1mgm 192.168.141.138 -serverport1 53389 -dsn2 repdb2_1121 -host2 ozone2 -host2mgm 192.168.141.139 -serverport2 53385 -deleteTimesTenLog NO -updateTimesTenLog YES
  ;;
IDLE-ACTIVE)
  ssh $osuser@$host1 <<EOF
  ttForcedDestroy.sh $dsn1 confirm invalidate
  ttrepadmin -duplicate -from $dsn2 -host $host2 -uid adm -pwd adm -verbosity 2 $dsn1
EOF

ssh $osuser@$host1 <<SSH
ttisql $dsn1 <<EOF
        connect "dsn=$dsn1;uid=appuser;pwd=appuser";
        create table nodeinfo (key varchar(20), value varchar(100));
        truncate table nodeinfo;
        insert into nodeinfo values ('dsn', '$dsn1');
        insert into nodeinfo values ('host', '$host1');
        insert into nodeinfo values ('serverport', '$serverport1');
        insert into nodeinfo values ('dsn@host', '$dsn1@$host1');
        insert into nodeinfo values ('dsn@host:serverport', '$dsn1@$host1:$serverport1');
EOF
SSH
  ;;
esac

  echo Summary | tee -a $testId.log
  echo --------------------- | tee -a $testId.log
  getTestSummary  | tee -a $testId.log
  listFailedSteps | tee -a $testId.log
  getTestEnvironment $user "$host1 $host2"

done

