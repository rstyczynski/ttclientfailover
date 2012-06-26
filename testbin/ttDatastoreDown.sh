#!/bin/bash

if [ "$1" = "" ]; then
	echo 'TimesTen datastore release script.'
	echo 'by ryszard.styczynski@oracle.com, April 15, 2011, version 3'
	echo 
	echo 'Usage: ttDatastoreDown.sh [-invalidate] [-connstr "connection string" | dsn ]'
	echo 
	echo Use -invalidate to invalidate dastore before unload
	exit 1
fi

. common.h
if [ "$ttCommonLibaryLoaded" != "OK" ]; then echo "TimesTen supplementatry scripts directory not in PATH. Can not continue. Exiting with error."; exit 1000; fi

#---------------- decode parameters Step2 -- START
if [ ! -z "$1" ]; then
	if [ $(echo $1 | cut -b1) != '-' ]; then
		firstParam=$1
		shift
	fi
fi

while [ $# -gt 0 ]; do
	case $1 in
	  -invalidate) decodeParam1of2 $1; shift; ;;
	  -connstr)    decodeParam1of2 $1; shift; decodeParam2of2 $1; ;;
	  -selftest)   decodeParam1of2 $1; shift; ;;
	   *)        if [ $# -gt 1 ]; then
			 unknown="$unknown $1"
		     else
			if [ $(echo $1 | cut -b1) != '-' ]; then
				lastParam=$1
			else
				unknown="$unknown $1"
			fi
		     fi
		     shift;;
	esac
	if [ "$myParam" = "yes" ]; then shift; fi
	myParam=unknown
done
#---------------- decode parameters Step2 -- STOP

#echo $invalidate
#echo $firstParam
#echo $lastParam
#echo $connstrParam

conn=$connstrParam$firstParam$lastParam
echo $conn | grep '='
if [ $? -eq 1 ]; then
  DSNTT=$conn
  conn="DSN=$conn"
else
  #change xxx=aBc to XXXTT=aBc
  connNorm=$(echo $conn | perl -pe 's/([a-zA-Z]+)=/\U$1TT=/g')
  eval "$connNorm"
fi

#redirect all output from this script to a log file
exec 3>&1 > >(tee -a ~/tmp/$$.scriptlog.tmp)
exec 2> >(tee -a ~/tmp/$$.scriptlog.tmp)

function doStop {
echo
echo --------------------------
echo Completed at: $(date)

case $result in
ERROR)
echo TimesTen datastore release NOT completed.
exitCode=20
;;
WARNING)
echo TimesTen datastore released with warnings.
exitCode=10
;;
BREAK)
echo TimesTen datastore release interrupted by operator.
exitCode=1
;;
*)
echo TimesTen datastore release completed.
exitCode=0
;;
esac

IFS='
'
#for line in $(cat ~/tmp/$$.scriptlog.tmp); do
#  ttDaemonLog -msg "ttDatastoreDown: $line" >/dev/null 2>&1
#done

rm ~/tmp/$$.* 2>/dev/null
exit $exitCode
}

function doBreak {
  result=BREAK
  doStop
}

trap doBreak SIGHUP SIGINT SIGTERM SIGQUIT SIGSTOP

dotsDots='.............................................................................................................................................'
dotsLines='_ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ '
dotsSpaces='                                                                                                                                          '
function echoTab {
 if [ -z "$3" ]; then
  dots=$dotsSpaces
 else
  dots="$3"
 fi
 filldots=$(( $2 - $(echo $1 | wc -c) ))
 if [ $filldots -lt 0 ]; then
        filldots=1
 fi
 echo -n "$1 $(echo "$dots" | cut -b1-$filldots )"
}

function getStatus {
        if [ -z "$1" ]; then
                statSTART=$DSNTT
        else
                statSTART=$1
        fi
        ttstatus >$tmp.status 2>&1
        if [ $? -ne 0 ]; then
                echo Error
        else
                cat  $tmp.status | sed -n "/$statSTART/,/--------------------/p"
        fi
}

echo TimesTen datastore release started. 
echo -----------------------------------
echo "date    : $(date)"
echo "instance: $(ttversion -m | grep instance= | cut -f2 -d=)"
echo "host    : $(hostname)"
echo "by      : $(who am i | cut -f1 -d' ')"
echo "connstr : $conn" | perl -pe 's/([a-zA-Z]+)=/\U$1=/g; s/\;ORACLEpwd=\w+/\;ORACLEpwd=\*\*\*\*\*\*\*\*/g; s/\;pwd=\w+/\;pwd=\*\*\*\*\*\*\*\*/g'
echo 

echoTab "Checking daemon status" 60 "$dotsDots"
getStatus 'TimesTen status report' | grep 'Daemon pid [0-9]* port [0-9]* instance' >/dev/null
if [ $? -eq 0 ]; then 
	echo OK
else
	result=ERROR
	echo "ERROR, info: $(head $tmp.status | tr '\n' ' ')"
	doStop
fi

echoTab "Checking if datastore exists" 60 "$dotsDots"
getStatus >$tmp.dsn.status
if [ -s $tmp.status ]; then
	echo OK
else
	echo OK, info: Datastore not yet created.
	result=OK
	doStop
fi

echoTab "Checking if datastore is unloaded" 60 "$dotsDots"
getStatus | grep "Data store is manually unloaded from RAM" >/dev/null 2>&1
if [ $? -eq 0 ]; then
	echo OK, info: alrady unloaded
	result=OK
	doStop
else
	echo OK
fi


echoTab "Checking existing connections" 60 "$dotsDots"
getStatus | grep "There are no connections to the data store" >/dev/null
err=$?
if [ $err -eq 0 ]; then
	echo OK, info: Datastore already unloaded. 
	doStop
else
	echo OK
fi

echoTab "Setting cache groups' autorefresh state to PAUSED" 60 "$dotsDots"
if [ -z $ORACLEPWDTT ]; then
  result=WARNING
  echo WARNING. Oracle password not specified. Skipping cache group state change.
else
  ttisql -v0 -e "call ttcachestart;exit" $conn &>/dev/null
  state=PAUSED
  name=%

  ttisql -v1 -e "
  timing 0;
  select 
	concat(concat(rtrim(cgowner), '.'),rtrim(cgname)) as cgfullname,
	rtrim(cgowner), 
	rtrim(cgname),
	rtrim(REFRESH_STATE) 
  from 
	sys.cache_group 
  where 
	refresh_mode <> 'N' and 
	concat(concat(rtrim(cgowner), '.'),rtrim(cgname)) like '$name';
  exit;" -connstr $conn | sed "s/< //" | sed "s/ >//g" | tr -d " " >~/tmp/$$.ttCacheStat.tmp

  oldIFS=$IFS
  IFS="
"
  echo "timing 1;" >~/tmp/$$.ttALTER.tmp
  for cg in $(cat ~/tmp/$$.ttCacheStat.tmp); do
        cgFull=$(echo $cg | cut -f1 -d,)
        cgOwner=$(echo $cg | cut -f2 -d,)
        cgName=$(echo $cg | cut -f3 -d,)
	cgState=$(echo $cg | cut -f4 -d,)
        echo --e:  processing cache group: $cgFull >>~/tmp/$$.ttALTER.tmp
	if [ "$cgState" = "Y" ]; then
        	echo "ALTER CACHE GROUP $cgOwner.$cgName SET AUTOREFRESH STATE $state;" >>~/tmp/$$.ttALTER.tmp
	else
		echo "--e:  skipping state change, current state $cgState." >>~/tmp/$$.ttALTER.tmp
	fi
  done
  ttisql -v0 -f ~/tmp/$$.ttALTER.tmp -connstr $conn 2>&1 | grep "^ [0-9]*: " >/dev/null
  err=$?
  if [ $err -ne 0 ]; then
	echo OK
  else
	result=ERROR
	echo ERROR
  fi
fi

echoTab "Flushing transaction log buffer" 60 "$dotsDots"
ttisql -v0 -e "autocommit 0;call ttDurablecommit;monitor;commit;exit" -connstr "$conn"
echo OK

echoTab "Waiting for AWT transactions to be flushed" 60 "$dotsDots"

ttisql -e "cachegroups; exit" $conn | grep "Cache Group Type: Asynchronous Writethrough" >/dev/null
err=$?
if [ $err -ne 0 ]; then
	echo "OK, info: Skipped - AWT cache groups are not used."
else
	ttisql -v0 -e "call ttrepstart;exit" $conn >/dev/null 2>&1
	ttisql -v1 -e "call ttRepSubscriberWait('_AWTREPSCHEME','TTREP','_ORACLE',,60);exit" -connstr "$conn" 2>$tmp.awtflusherr | cut -d' ' -f2 > ~/tmp/$$.awtflush.tmp 
	if [ -s $tmp.awtflusherr ]; then
		result=ERROR
		echo ERROR, info: $(cat $tmp.awtflusherr)
	else
		if [ ! "$(cat ~/tmp/$$.awtflush.tmp)" = "00" ]; then
		  result=WARNING
		  echo WARNING, info: AWT data not fully saved to Oracle.
		else
		  echo OK
		fi
	fi 
fi

echoTab "Stopping cache agent" 60 "$dotsDots"
ttAdmin -cachestop -connstr "$conn" >/dev/null 2>&1

err=$?
if [ $err -eq 0 ]; then
  echo OK
else
  if [ $err -eq 6 ]; then
    echo OK, info: Cache agent already stopped
  else
    echo WARNING
    result=WARNING
  fi
fi

echoTab "Stopping replication agent" 60 "$dotsDots"
ttAdmin -repstop -connstr "$conn" >/dev/null 2>&1

err=$?
if [ $err -eq 0 ]; then
  echo OK
else
  if [ $err -eq 6 ]; then
    echo OK, info: Replication agent already stopped
  else
    echo WARNING
    result=WARNING
  fi
fi

echoTab "Unloading datastore from memory" 60 "$dotsDots"
ttAdmin -ramUnload $DSNTT >$tmp.unload  2>&1
err=$?
if [ $err -eq 0 ]; then
  echo OK
else
  if [ $err -eq 9 ]; then
      	if [ ! -z "$invalidate" ]; then
		echo Warning: ds not unloaded due to existing connections...
		echoTab "Invalidating datastore" 60 "$dotsDots"
		if [ -z "$invalidate" ]; then
			echo Skipped.
		else
			ttisql -e "call invalidate; exit;" $DSNTT >/dev/null 2>&1
			echo OK.
		fi
	else
	    echo ERROR, info: $(cat $tmp.unload)
 	fi
  else
    if [ $err -eq 8 ]; then
      echo OK, info: already unloaded
      result=OK
      doStop
    else
      	if [ ! -z "$invalidate" ]; then
		echo Warning: ds not unloaded due to existing connections...
		echoTab "Invalidating datastore" 60 "$dotsDots"
		if [ -z "$invalidate" ]; then
			echo Skipped.
		else
			ttisql -e "call invalidate; exit;" $DSNTT >/dev/null 2>&1
			echo OK.
		fi
	else
      		echo ERROR, info: Datastore NOT unloaded. Please disconnect all users first.
     		result=ERROR
      		doStop
	fi
   fi
  fi
fi


echoTab "Checking existing connections" 60 "$dotsDots"
getStatus | grep "There are no connections to the data store" >/dev/null
err=$?
if [ $err -eq 0 ]; then
	echo OK
else
	result=ERROR
	echo ERROR, info: $(getStatus)
fi

result=OK
doStop

