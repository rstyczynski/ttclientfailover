#!/bin/bash

if [ "$1" != "confirm" ]; then
    echo Script will stop TimesTen daemon.
    echo To ensure that you agree add 'confirm' as parameter.
    exit 1
fi

eval $(ttversion -m)
userlog=$(cat $effective_daemonhome/ttendamon.options | grep "^\w*-userlog" | cut -f2 -d' ')
if [ "$userlog" == "" ]; then
    userlog=$effective_daemonhome/tterrors.log
fi
if [ "$dsn" != "" ]; then ttDatastoreDown.sh $dsn; fi
ttDaemonAdmin -stop
rm $userlog*
ttDaemonAdmin -start
if [ "$dsn" != "" ]; then ttDatastoreUp.sh $dsn; fi


