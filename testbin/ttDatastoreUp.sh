#!/bin/bash

if [ "$1" = "" ]; then
        echo 'TimesTen datastore startup script.'
	echo 'by ryszard.styczynski@oracle.com, March 26, 2011, version 1'
	echo 
        echo 'Usage: ttDatastoreUp.sh dsn|"connection string"'     
        exit 1
fi

conn=$1
echo $conn | grep '=' >/dev/null
if [ $? -eq 1 ]; then
  DSNTT=$conn
  conn="DSN=$DSNTT"
else
  #change xxx=aBc to XXXTT=aBc
  connNorm=$(echo $conn | perl -pe 's/([a-zA-Z]+)=/\U$1TT=/g')
  eval "$connNorm"
fi

if [ ! -d ~/tmp ]; then
        mkdir ~/tmp
fi
tmp=~/tmp/$$

#redirect all aoutput from this script to a log file
exec 3>&1 > >(tee -a ~/tmp/$$.scriptlog.tmp)
exec 2> >(tee -a ~/tmp/$$.scriptlog.tmp)

function doStop {
echo
echo --------------------------
echo Completed at: $(date)

case $result in
ERROR)
echo TimesTen datastore load NOT completed.
exitCode=20
;;
WARNING)
echo TimesTen datastore loaded with warnings.
exitCode=10
;;
BREAK)
echo TimesTen datastore load interrupted by operator.
exitCode=1
;;
*)
echo TimesTen datastore load completed.
exitCode=0
;;
esac

IFS='
'
#for line in $(cat ~/tmp/$$.scriptlog.tmp); do
#  ttDaemonLog -msg "ttDatastoreUp: $line" >/dev/null 2>&1
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

echo TimesTen startup started. 
echo --------------------------
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

echoTab "Loading datastore into memory" 60 "$dotsDots"
ttAdmin -ramLoad $DSNTT >$tmp.load 2>&1
err=$?
  if [ $err -eq 0 ]; then
	echo OK
  else
    if [ $err -eq 9 ]; then
      echo ERROR, info: $(cat $tmp.load)
    else 
      if [ $err -eq 7 ]; then
        echo OK, info: Already loaded
      else
        result=ERROR
        echo ERROR, info: $(cat $tmp.load)
        doStop
      fi
    fi
  fi

echoTab "Starting replication agent" 60 "$dotsDots"
ttAdmin -repstart -connstr "$conn" >$tmp.rep 2>&1
err=$?

case $err in
  0) echo OK
     ;;
  5) echo OK, info: Already running
     ;;
  9) echo OK, info: Replication not defined. Start skipped
     ;;
  *) echo ERROR, info: $(cat $tmp.rep | tr -d '*') 
     result=ERROR
     ;;
esac

#if [ $err -eq 0 ]; then
#  echo OK
#else
#  if [ $err -eq 5 ]; then
#    echo OK, info: Already running
#  else
#    echo ERROR, info: $(cat $tmp.rep | tr -d '*') 
#    result=ERROR
#  fi
#fi

echoTab "Starting cache agent" 60 "$dotsDots"
ttAdmin -cachestart -connstr "$conn" >$tmp.cache 2>&1
err=$?
case $err in
  0) echo OK
     ;;
  5) echo OK, info: Already running
     ;;
  9) echo OK, info: Cache manager not defined. Start skipped
     ;;
  *) echo ERROR, info: $(cat $tmp.cache | tr -d '*') 
     result=ERROR
     ;;
esac

#if [ $err -eq 0 ]; then
#  echo OK
#else
#  if [ $err -eq 5 ]; then
#    echo OK, info: Already running
#  else
#    echo ERROR, info: $(cat $tmp.cache | tr -d '*') 
#    result=ERROR
#  fi
#fi

echoTab "Setting cache groups' autorefresh state to ON" 60 "$dotsDots"
if [ -z $ORACLEPWDTT ]; then
  result=WARNING
  echo WARNING. Oracle password not specified. Skipping cache group state change.
else
state=ON
name=%

ttisql -v1 -e "
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
exit;" -connstr $conn 2>&1 | sed "s/< //" | sed "s/ >//g" | tr -d " " >~/tmp/$$.ttCacheStat.tmp

oldIFS=$IFS
IFS="
"
#echo "timing 1;" >~/tmp/$$.ttALTER.tmp
for cg in $(cat ~/tmp/$$.ttCacheStat.tmp); do
        cgFull=$(echo $cg | cut -f1 -d,)
        cgOwner=$(echo $cg | cut -f2 -d,)
        cgName=$(echo $cg | cut -f3 -d,)
        cgState=$(echo $cg | cut -f4 -d,)
        echo --e:Processing cache group: $cgFull >>~/tmp/$$.ttALTER.tmp
        if [ "$cgState" = "P" ]; then
		echo "ALTER CACHE GROUP $cgOwner.$cgName SET AUTOREFRESH STATE $state;" >>~/tmp/$$.ttALTER.tmp
	else
                echo "--e:Skipping state change, current state $cgState." >>~/tmp/$$.ttALTER.tmp
	fi
done
echo "exit;" >>~/tmp/$$.ttALTER.tmp

errSQL=0
ttisql -v1 -f ~/tmp/$$.ttALTER.tmp -connstr $conn >$tmp.cgstate 2>&1
err=$?
if [ -s $tmp.cgstate ]; then
	cat $tmp.cgstate | grep "^ [0-9][0-9]*: ">/dev/null 
	if [ $? -eq 0 ]; then
		errSQL=1  #does not good if error code is found in ttisql SQL execution answer
	fi
fi

if [ $(( $err + $errSQL )) -eq 0 ]; then
	echo OK
else
	result=ERROR
	echo ERROR, info: $(cat $tmp.cgstate)
fi
fi

echoTab "Setting sql cache size to 5000" 60 "$dotsDots"
ttisql -v0 -e "autocommit 0;call ttoptsetmaxcmdfreelistcnt(5000);commit;exit" $DSNTT >$tmp.cache 2>&1
if [ -s $tmp.cache ]; then
	result=ERROR
	echo ERROR, info: $(cat $tmp.cache | sed s/^$//g)
else
	echo OK
fi

doStop

