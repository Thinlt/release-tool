#!/bin/bash

# File: compare-noissue.sh
# Params?: $1 $2 $3 $4 - <version 1> <version 2> [Log File] [Ignore Author]

if [[ ! -z $1 && ! -z $2 ]]; then
    if [ ! -z $3 ]; then
        cat <<< "`git log $1..$2 --pretty=format:'%H %an %N %s' --invert-grep --author=$4`" | grep -ve ".*#.*" | grep -ve ".*Merge.*" > $3
	else
		cat <<< "`git log $1..$2 --pretty=format:'%H %an %N %s' --invert-grep --author=$4`" | grep -ve ".*#.*" | grep -ve ".*Merge.*"
	fi
else
	if [ ! -z $3 ]; then
		cat <<< "`git log --pretty=format:'%H %an %N %s' --invert-grep --author=$4`" | grep -ve ".*#.*" | grep -ve ".*Merge.*" > $3
	else
		cat <<< "`git log --pretty=format:'%H %an %N %s' --invert-grep --author=$4`" | grep -ve ".*#.*" | grep -ve ".*Merge.*"
	fi
fi
