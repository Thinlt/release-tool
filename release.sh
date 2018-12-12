#!/bin/bash
# Usage: release.sh <m1|m2> <version> [OUTPUT_DIR]
set -e
trap '>&2 echo Error: Command \`$BASH_COMMAND\` on line $LINENO failed with exit code $?' ERR

script_dir=$(dirname "${BASH_SOURCE[0]}")
pushd $script_dir
curent_dir=`pwd`
popd

# get magento ver
if [ ! -z $1 ]; then
    mage=$1
else
    echo "Failed require param <m1|m2>." >&2
    exit 1
fi
# get version param
if [ ! -z $2 ]; then
    tag_version=$2
else
    tag_version="master"
fi
# get OUTPUT_DIR param
if [ ! -z $3 ]; then
    OUTPUT_DIR="$3"
else
    OUTPUT_DIR="release-$mage"
fi
# validate params 1
if [[ "$mage" != "m1" && "$mage" != "m2" ]]; then
    echo "param 1 is m1 or m2" >&2
    exit 1
fi
if [ ! -f "release-notes/${tag_version}-$mage.md" ]; then
    echo "No release notes file!"
    exit 1
fi

# convert OUTPUT_DIR to real path to fix save zip file
if [ ! -z "$OUTPUT_DIR" ]; then
    if [ -z "`echo $OUTPUT_DIR | grep -e ^/`" ]; then
        OUTPUT_DIR="$curent_dir/$OUTPUT_DIR"
    fi
fi

# RESOURCE_DIR by m1 or m2
RESOURCE_DIR="release-$mage/deploy"

# envs
export OUTPUT_DIR   # env OUTPUT_DIR
export RESOURCE_DIR # env RESOURCE_DIR

# release note file m1 or m2
release_note="${curent_dir}/release-notes/${tag_version}-$mage.md"

# reading release notes file & release child package
# Format: <Name> <Version> <Magento>
is_first_run=1
while IFS='' read -r line || [[ -n "$line" ]]; do
    # rtrim line by -
    line=`sed -r "s/^(\s*\-*)*//" <<< "$line"`
    # ltrim line by white space
    line=`sed -e "s/\s*$//" <<< "$line"`
    if [ -z "$line" ]; then # ignore zero line
        continue
    fi
    if [ ! -z "$(sed -e 's/^\s*//g' <<< $line | grep -e '^#')" ]; then # ignore comment line
        continue
    fi
    line=( $line )
    # get package name
    repo=${line[0]}
    # get package version
    if [ ! -z "${line[1]}" ]; then
        version="${line[1]}"
    else
        version="x.x.x"
    fi
    # get magento version
    if [ ! -z "${line[2]}" ]; then
        m="${line[2]}"
    else
        m="x.x.x"
    fi
    echo "Starting repo: $repo"
    if [[ "$repo" == "plus" || "$repo" == "growth" || "$repo" == "starter" ]]; then
        if [ $is_first_run ]; then
            bash $curent_dir/release-tool/run.sh $repo $version $m
        else
            bash $curent_dir/release-tool/run.sh $repo $version $m --cache
        fi
    else
        bash $curent_dir/release-tool/pack.sh $repo $version $m
    fi
    is_first_run=0
done < "$release_note"
