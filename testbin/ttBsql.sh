#!/bin/bash

. common.h;. secure.h; if [ "$ttCommonLibaryLoaded" != "OK" ]; then echo "Error: TimesTen admin environment not configured. Exiting."; exit 100; fi

ttisql "$@" 2>&1 | tee $tmp/$$.ttBsql.out
result=$?

grep -i -f $ttadmin_home/cfg/ttisqlcheck.cfg $tmp/$$.ttBsql.out >/dev/null
if [ $? -eq 0 ]; then
 grepresult=98
else
 grepresult=0
fi

result=$(( $result + $grepresult ))

rm $tmp/$$.ttBsql.*
exit $result
