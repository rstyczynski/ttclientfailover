#!/bin/bash

dsn=$1
confirm=$2
force=$3
if [ -z "$cachecfg" ]; then
	tabulator=60
fi

#load functions, check parameters, initialize environment
unset ttCommonLibaryLoaded; source common.h; source failover.h; if [ "$ttCommonLibaryLoaded" != "OK" ]; then echo "Error: TimesTen admin environment not configured. Exiting."; exit 100; fi; 

if [ "$confirm" != "confirm" ]; then
        echo Error. Invalid parameters. Use \$dsn confirm to destroy
        doStop 1
fi

tt_home=/$(ttversion | grep "Daemon home directory" | cut -d'/' -f2-99)
if [ ! -d $tt_home ]; then
        echo Error: TimesTen not detected.
        exit 1
fi

subdaemonPID=$(dsnstatus | grep Subdaemon | head -1 | tr -s ' ' | cut -f2 -d' ')
where="Detecting datastore"; echoTab "$where"
if [ -z "$(dsnstatus)" ]; then
	echo Not detected.
        if [ "$force" != "force" ]; then
		doStop 0
	fi
else
	if [ -z "$subdaemonPID" ]; then	
		echo Detected, but not loaded
	else
		echo Detected
	fi
fi

DataStore=$(cat $tt_home/sys.odbc.ini | sed -n /\\[$dsn\\]/,/DataStore/p | tail -1| cut -d'=' -f2)
LogDir=$(cat $tt_home/sys.odbc.ini | sed -n /\\[$dsn\\]/,/^\s\*LogDir/p | tail -1| cut -d'=' -f2)

if [ "$force" = "force" ]; then
 where="Removing data store files"; echoTab "$where"
 rm $DataStore.ds*
 echo OK

 where="Killing all client processes"; echoTab "$where"
 pids=$(dsnstatus -nopretty | grep context | sed 's/ pid /;/g; s/ context /;/g' | cut -d';' -f2 | sort -u | tr '\n' ' ')
 noactivepids=$(dsnstatus -nopretty | grep "^Process" | cut -f2 -d ' '  | sort -u | tr '\n' ' ')
 kill -9 $pids $noactivepids >/dev/null 2>&1
 sleep 1
 echo OK 
else
 where="Invalidating data store"
 echoTab "$where"
 ttBsql.sh -e"connect $dsn" -v1 2>&1 >$tmp/$$.out <<EOF
        host rm $DataStore.ds*
        call invalidate
EOF
 test_errorOK
 save2log
fi

if [ ! -z "$subdaemonPID" ]; then
  kill -9 $subdaemonPID
fi
where="Finalization of datastore destroy"; echoTab "$where"
rm $LogDir/$dsn.log* >/dev/null 2>&1
touch $DataStore.ds0
touch $DataStore.ds1
ttdestroy -force $dsn >$tmp/$$.out 2>&1
if [ $? -eq 0 ]; then
    echo OK
else
    echo Error, casue: $(cat $tmp/$$.out)
	doStop 1
fi
doStop 0

