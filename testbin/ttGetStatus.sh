#!/bin/bash

if [ ! -z "$1" ]; then
  dsn=$1
fi
ttisql -e"call ttrepstateget;exit" $dsn | grep "<" | cut -f2 -d " " | cut -f1 -d','

