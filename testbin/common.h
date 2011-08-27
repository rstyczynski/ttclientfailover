#!/bin/bash
#author=ryszard.styczynski@oracle.com
#updated="Apr 14, 2011"
#version="0.3"

#0.4
#-parameters may be with spaces
#-added echoTab
#-added test_exit 
#-added runSQL function

export ttCommonLibaryLoaded=OK

if [ "$(uname)" = "SunOS" ]; then
	grepf=/usr/xpg4/bin/grep
	sed=/usr/xpg4/bin/sed
	PATH=/usr/xpg4/bin:$PATH
else
	grepf=grep
	sed=sed
fi

# supprot for SQL environment definition file
function verbosity { verbosity=$1; };

function define { 
	eval $1
	export $(echo $1 | cut -f1 -d'=')
}

function loadcfg {
	   if [ ! -z "$THIScachecfg" ]; then
             if [ "$THIScachecfg" != "$cachecfg" ]; then
                echo 'Cleaning settings.'
                for line in $(cat $ttadmin_home/cfg/* | egrep "^\s*define" | cut -d'=' -f1 | sort -u | cut -f2 -d' '); do eval unset $line; done
        	unsetUser
       	    	unsetCryptUser
       	    	unsetCacheMgr
        	unsetCryptCacheMgr
	        unsetSysDBA
             fi
	   fi
           export cachecfg
           . $cachecfg
           echo Configuration $cachecfg loaded.
           export THIScachecfg=$cachecfg
}

function readcfg {
	. common.h
	. failover.h
	. secure.h
        if [ -z "$1" ]; then
          if [ -z "$cachecfg" ]; then
            echo Warning: Configuration not specified by parameter nor "cachecfg" variable
	    doNotExit=1
            doStop 1
          else
	    if [ "$cachecfg" = "undefined" ]; then
              echo Warning: Configuration not specified by parameter nor "cachecfg" variable
              doNotExit=1
              doStop 1
            else
              loadcfg
            fi
          fi
        else
          cfgparam=$(echo $1 | tr '[:upper:]' '[:lower:]')
          if [ -f $(basename $cfgparam) ]; then
           cachecfg=$PWD/$cfgparam; loadcfg
          elif [ -f $cfgparam ]; then
           cachecfg=$cfgparam; loadcfg
          elif [ -f $(basename $cfgparam.env) ]; then
           cachecfg=$PWD/$cfgparam.env; loadcfg
          elif [ -f $ttadmin_home/cfg/$cfgparam ]; then
           cachecfg=$ttadmin_home/cfg/$cfgparam; loadcfg
          elif [ -f $ttadmin_home/cfg/$cfgparam.env ]; then
           cachecfg=$ttadmin_home/cfg/$cfgparam.env; loadcfg
          else
            echo Error: Configuration $cfgparam does not exist. Cleaning current settings.
	    export cachecfg=undefined
            for line in $(cat $ttadmin_home/cfg/* | egrep "^\s*define" | cut -d'=' -f1 | sort -u); do eval unset $line; done
            doStop 1
          fi
        fi
}

function getCacheCfg {
	type=$1
	if [ -z "$cachecfg" ]; then cachecfg=undefined; fi
	if [ "$cachecfg" != "undefined" ]; then
	  if [ "$type" = "ORACLE" ]; then
		cat $cachecfg | egrep "^\s*define"
	  else
		cat $cachecfg
	  fi
	fi
}


#---------------- check tmp directory -- START
function setTmp {
	tmp=~/tmp
	export tmp
        if [ ! -d $tmp ]; then
        	mkdir $tmp
        fi
        touch $tmp/$$.tmp
        if [ ! -f $tmp/$$.tmp ]; then
        	echo Error: Can not access $tmp directory
                #TODO - change to stop(1) function
		exit 1
        fi
}

if [ -z $tmp ]; then
	echo Warning: tmp not defined. Setting tmp to ~/tmp
	setTmp	
else
	touch $tmp/$$.tmp
	if [ ! -f $tmp/$$.tmp ]; then
		echo Warning: Can not write to $tmp. Setting tmp to ~/tmp
		setTmp
	fi
fi
#---------------- check tmp directory -- STOP

#---------------- decode parameters -- START
function decodeParam1of2 { 
        code=$(echo "$1" | cut -b2-999)
        env='echo $'; env=$env$code
        if [ ! -z "$(eval $env)" ]; then
                echo Warning: $code parameter duplicated. Will use last setting.
                unset $code\Param
        fi
        eval $code=yes
}
function decodeParam2of2 {
        if [ ! -z "$1" ]; then
                if [ $(echo "$1" | cut -b1) != '-' ]; then
                        myParam=yes
                        eval $code\Param=\"$1\"
                fi
        fi

}
#---------------- decode parameters -- STOP

#---------------- echotab - START
dotsDots='.............................................................................................................................................'
dotsLines='_ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ '
dotsDash='----------------------------------------------------------------------------------------------------------------------------------------------'
dotsSpaces='                                                                                                                                          '
function echoTab {
 if [ -z "$3" ]; then
  dots=$dotsDots
 else
  dots="$3"
 fi
 if [ -z "$2" ]; then 
   if [ -z "$tabultor" ]; then
        tabPos=60
   else
   	tabPos=$tabulator
   fi
 else
   tabPos=$2
 fi
 filldots=$(( $tabPos - $(echo $1 | wc -c) ))
 if [ $filldots -lt 0 ]; then
        filldots=1
 fi
 echo -n "$1$(echo "$dots" | cut -b1-$filldots )"
}
#---------------- echotab - STOP

#---------------- testexit - START
function test_success {
 result=$? 
 
 egrep -i -f $ttadmin_home/cfg/ttisqlcheck.cfg $tmp/$$.out >/dev/null
 if [ $? -eq 0 ]; then
  grepresult=98
 else
  grepresult=0
 fi

 result=$(( $result + $grepresult ))


 if [ $result -eq 0 ]; then
    echo OK
 else
   echo Error, cause: $(cat $tmp/$$.out | egrep -i -f $ttadmin_home/cfg/ttisqlcheck.cfg | tr '\n' ' ')
 fi
}

function test_errorOK {
 result=$? 
 if [ $result -ne 0 ]; then
   echo OK
 else
   echo Warning, cause: $(cat $tmp/$$.out | tr '\n' ' ' | cut -b1-80)
 fi
}

#---------------- testexot -STOP


function save2log {
 if [ "$(echo $0 | cut -b1)" = "-" ]; then
  fname=$(echo $0 | cut -b2-999)
 else
  fname=$0
 fi
 echoTab "$where" 80 >> $ttadmin_home/log/$(basename $fname).log
 date >> $ttadmin_home/log/$(basename $fname).log
 cat $tmp/$$.out >> $ttadmin_home/log/$(basename $fname).log
}

function runSQL {
      where=$1
      echoTab "$where"
      ttBsql.sh -e"connect $dsn;@$cachecfg;$(getSecured)" -v3 2>&1 >$tmp/$$.out

      test_success
      save2log
}

function runSQLCS {
      where=$1
      echoTab "$where" 
      ttBsqlCS.sh -e"@$cachecfg;$(getSecured);verbosity 1" -v3 2>&1 >$tmp/$$.out

      test_success
      save2log
}

function runSQLerr {
      where=$1
      echoTab "$where"
      ttBsql.sh -e"connect $dsn;@$cachecfg;$(getSecured)" -v1 2>&1 >$tmp/$$.out
      test_errorOK
      save2log
}

function runSQLCSerr {
      where=$1
      echoTab "$where"
      ttBsqlCS.sh -e"@$cachecfg;$(getSecured);" -v1 2>&1 >$tmp/$$.out
      test_errorOK
      save2log
}


function doStop {
 result=$1
  
 if [ "$doNotExit" != "1" ]; then
	 if [ $result -eq 0 ]; then
	  echo Done.
	 else
	  echo Error. 
	 fi
	 
	 if [ "$0" = "-bash" ]; then
	  stopTrace
	  bash -c "exit $result"
	 else
 	  stopTrace
	  exit $result
	 fi
 else
	doNotExit=0
 fi
}

# support for debuging

function startTrace {
	if [ "$ttadmin_trace" = "YES" ]; then
	 	if [ "$(echo $0 | cut -b1)" = "-" ]; then
	  		fname=$(echo $0 | cut -b2-999)
	 	else
	  		fname=$0
	 	fi

		traceStarted=1
		if [ -f $ttadmin_home/log/$(basename $fname).trace ]; then rm $ttadmin_home/log/$(basename $fname).trace; fi
		exec 4>&2
		exec 2> >(tee -a $ttadmin_home/log/$(basename $fname).trace | grep -v "+")
		exec 3>&1 > >(tee -a $ttadmin_home/log/$(basename $fname).trace)
		set -o xtrace
	fi
}

function stopTrace {
	if [ "$traceStarted" = "1" ]; then
		traceStarted=0
		set +o xtrace
		exec 2>&1 2>/dev/null 1>&3
		exec 2>&1 2>/dev/null 3>&- 
		exec 2>&1 2>/dev/null 2>&4 
		exec 2>&1 2>/dev/null 4>&-
	fi
}

function lastLog {
	cat $tmp/$$.out
}

function dsnstatus {
	ttstatus "$@" | sed -n /$dsn/,/-----/p
}

function dsnshmid {
	dsnstatus | grep "Shared Memory KEY" | cut -d' ' -f6
}

function dsnsubdpid {
	dsnstatus | grep Subdaemon | tail -1 | tr -s ' ' | cut -d' ' -f2
}

function dsncrash {
	ipcrm -m $(dsnshmid)
	#kill -9 $(dsnsubdpid)
}

function phase {
	phase=$1
	echoTab "--" 80 "$dotsDash";echo
	echoTab "-- $phase " 79 "$dotsDash";echo
	echoTab "--" 80 "$dotsDash";echo
}

function tthome {
	cd $tt_home
}

function ttinst {
	cd $effective_insthome
}

function absoluteDir {

 file=$1
 dir=$(dirname $file)
 cd $dir
 absolutedir=$PWD
 cd - >/dev/null
 echo $absolutedir
}

export ttCommonLibaryLoaded=OK



