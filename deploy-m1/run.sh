#!/bin/bash

set -e
trap '>&2 echo Error: Command \`$BASH_COMMAND\` on line $LINENO failed with exit code $?' ERR

source $(dirname "${BASH_SOURCE[0]}")/config.cnf

script_dir=$(dirname "${BASH_SOURCE[0]}")
github="https://magestore-system:9ed5102ba8f0b9f66f4beb63055c29e493285054@github.com/Magestore/"
default_branch="master"
mod_dir="modules"
install_to=".." #install to magento 1 root
repo_list="repo.list"
repo_name=""
tag_version="versionno"
magento_version=""


# choose version list
if [ ! -z $1 ]; then
	repo_list="repo.list-$1"
	repo_name="$1"
	if [ ! -f "$script_dir/$repo_list" ]; then
		exit 1
	fi
fi

# version tag number param
if [ ! -z $2 ]; then
	tag_version=$2
fi
# magento version param
if [ ! -z $3 ]; then
	magento_version=$3
fi

# remove old modules
pushd $script_dir
rm -rf ${mod_dir}
mkdir -p ${mod_dir}

repos=()
requires=()
# Read repo list
while IFS='' read -r line || [[ -n "$line" ]]; do
    if [ -z "$line" ]; then #ignore zero line
        continue
    fi
    if [ ! -z "$(sed -e 's/^\s*//g' <<< $line | grep -e '^#')" ]; then #ignore comment line
        continue
    fi
    echo "Checkout: $line"
    name=$(echo $line | awk '{print $1}')
    version=$(echo $line | awk '{print $2}')
    if [ "$version" == "required" ]; then
        requires+=( "$name" )
    else
        repos+=( "$name" )
        # clone repo
        git clone --quiet --depth=1 -b $version ${github}${name}.git $mod_dir/$name 2>/dev/null || true
    fi
done < "$repo_list"


# copy to install dir
for repo in ${repos[@]}; do
        if [ -f $mod_dir/$repo/etc/module.xml ]; then
            name=$(cat $mod_dir/$repo/etc/module.xml | grep -e 'module\sname=.*' | grep -e 'name=\S*' -o)
            module=$(echo $name | sed -r "s/'//g" | sed -r 's/"//g' | sed -r 's/name=//g')
            vendor_module=($(echo $module | sed -r 's/_/ /g'))
            if [ ! -z ${vendor_module[0]} ]; then
                if [ ! -z ${vendor_module[1]} ]; then
                    if [ ! -d $install_to/app/code/${vendor_module[0]}/${vendor_module[1]} ];
                       then mkdir -p $install_to/app/code/${vendor_module[0]}/${vendor_module[1]} ;
                    fi
                    cp -rpf $mod_dir/$repo/* $install_to/app/code/${vendor_module[0]}/${vendor_module[1]}/
                else
                    if [ ! -d $install_to/app/code/${vendor_module[0]} ];
                       then mkdir -p $install_to/app/code/${vendor_module[0]} ;
                    fi
                    cp -rpf $mod_dir/$repo/* $install_to/app/code/${vendor_module[0]}/
                fi
            fi
	else
	    cp -rpf $mod_dir/$repo/* $install_to/
        fi
done

#exit 1


if [ -f ./auth.json ]; then
    cp ./auth.json ../
fi

#if [ ! -z $requires ]; then
#   pushd ../
#   for name in ${requires[@]}; do
#       composer require $name
#   done
#   popd
#fi

chown -R ubuntu:ubuntu ../
rm -rf ../var/cache

popd

echo "Deploy complete!"
