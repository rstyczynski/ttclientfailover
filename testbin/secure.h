function readpwd {
  prompt=$1
  if [ -z "$2" ]; then
	securedVar=secret
  else
  	securedVar=$2
  fi
  if [ -z $(getVariable $securedVar) ]; then
   echo $prompt >&2
   stty -echo
   read $securedVar
   stty echo
  fi
 echo $(getVariable $securedVar)
}

function readpwdtwice {
  prompt=$1
  if [ -z "$2" ]; then
        securedVar=secret
  else
        securedVar=$2
        securedVar2=$2\retype
  fi
  if [ -z $(getVariable $securedVar) ]; then
   match=NO
   while [ "$match" != "YES" ]; do
    echo $prompt >&2
    stty -echo
    read $securedVar
    stty echo
    echo "Enter password again" >&2
    stty -echo
    read $securedVar2
    stty echo

    if [ "$(getVariable $securedVar)" != "$(getVariable $securedVar2)" ]; then
     echo Passwords do not match. Enter again.
     match=NO
    else
     match=YES
    fi
   done
  fi
 echo $(getVariable $securedVar)
}

function setVariable {
        varName=$1
        varValue=$2
        eval $(echo $(eval echo \$varName))=$varValue
}

function getVariable {
        varName=$1
        eval "echo $(eval echo \$$varName)"
}

function unsetVariable {
        varName=$1
        eval unset $(echo $(eval echo \$varName))
}

function setGlobal {
        if [ -z "$OracleNetServiceName" ]; then
                readpwd 'Oracle service name:' OracleNetServiceName 
                export OracleNetServiceName 
        fi
        if [ -z "$global_tablespace_name" ]; then
                readpwd 'Global tablespace name:' global_tablespace_name 
                export global_tablespace_name
        fi
        if [ -z "$global_tablespace_type" ]; then
                readpwd 'Global tablespace type:' global_tablespace_type
                export global_tablespace_type 
        fi

}

function setSysDBA {
	if [ -z "$oracleSysUID" ]; then
                readpwd 'Oracle sysdba username:' oracleSysUID
		export oracleSysUID
        fi
        if [ -z "$oracleSysPWD" ]; then
                readpwdtwice 'Oracle sysdba password:' oracleSysPWD >/dev/null
		echo
		export oracleSysPWD
        fi
}

function unsetSysDBA {
	unset oracleSysUID
	unset oracleSysPWD
}

function setCryptCacheMgr {
        if [ -z "$cachemanagerUID" ]; then
                readpwd 'Cache manager username:' cachemanagerUID
                export cachemanagerUID
        fi
        if [ -z "$cachemanagerCryptPWD" ]; then
                echo 'Cache manager TimesTen password /enter two times/:'
                cachemanagerCryptPWD=$(ttuser -pwdcrypt | sed 's/Enter password://g; s/Re-enter password://g' | tr -d "'" | tr -d ' ')
                export cachemanagerCryptPWD
        fi
        if [ -z "$cachemanagerORCLPWD" ]; then
                readpwd 'Cache manager Oracle password:' cachemanagerORCLPWD >/dev/null
                echo
                export cachemanagerORCLPWD
        fi
}

function unsetCryptCacheMgr {
        unset cachemanagerUID
	unset cachemanagerCryptPWD
	unset cachemanagerORCLPWD
}
function setCacheMgr {
        if [ -z "$cachemanagerUID" ]; then
                readpwd 'Cache manager username:' cachemanagerUID
                export cachemanagerUID
        fi
        if [ -z "$cachemanagerPWD" ]; then
                readpwdtwice 'Cache manager TimesTen password:' cachemanagerPWD >/dev/null
                echo
                export cachemanagerPWD
        fi
        if [ -z "$cachemanagerORCLPWD" ]; then
                readpwdtwice 'Cache manager Oracle password:' cachemanagerORCLPWD >/dev/null
                echo
                export cachemanagerORCLPWD
        fi

}

function unsetCacheMgr {
        unset cachemanagerUID
	unset cachemanagerPWD
	unset cachemanagerORCLPWD
}
function setCryptUser {
        if [ -z "$userUID" ]; then
                readpwd 'Business username:' userUID 
                export userUID
        fi
        if [ -z "$userCryptPWD" ]; then
                echo 'Business user TimesTen password /enter two times/:' 
                userCryptPWD=$(ttuser -pwdcrypt | sed 's/Enter password://g; s/Re-enter password://g' | tr -d "'" | tr -d ' ')
		export userCryptPWD
        fi
        if [ -z "$userORCLPWD" ]; then
                readpwd 'Business user Oracle password:' userORCLPWD >/dev/null
                echo
                export userORCLPWD
        fi

}

function unsetCryptUser {
        unset userUID
        unset userCryptPWD
        unset userORCLPWD
}

function setUser {
        if [ -z "$userUID" ]; then
                readpwd 'Business username:' userUID 
                export userUID
        fi
        if [ -z "$userPWD" ]; then
                readpwdtwice 'Business user TimesTen password:' userPWD >/dev/null
                echo
                export userPWD
        fi
        if [ -z "$userORCLPWD" ]; then
                readpwdtwice 'Business user Oracle password:' userORCLPWD >/dev/null
                echo
                export userORCLPWD 
        fi

}

function unsetUser {
        unset userUID
        unset userPWD
        unset userORCLPWD
}

function getSecured {
   target=$1
   if [ "$target" != "ORACLE" ]; then
   	echo -n "set verbosity 0;"
        echo -n "set define on;"
        for line in $(set | egrep -e "^[a-zA-Z]+UID=" -e "^[a-zA-Z]+PWD=" | grep -v '=$'); do 
          echo -n "define $line;"
        done
   else
    echo "set define on"
    for line in $(set | egrep -e "^[a-zA-Z]+UID=" -e "^[a-zA-Z]+PWD=" | grep -v '=$'); do 
     echo "define $line"
    done
   fi
}

