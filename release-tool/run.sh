#!/bin/bash
# Usage: run.sh <OUTPUT_DIR>
# Params: --log-issue | -i : log the issue to file | --cache | --changed | --verbose | --help
set -e
trap '>&2 echo Error: Command \`$BASH_COMMAND\` on line $LINENO failed with exit code $?' ERR

# get current run command dir
current_dir=$(pwd)
# get script dir path
script_dir=$(dirname "${BASH_SOURCE[0]}")
script_dir=$(cd $script_dir 2>&1 >/dev/null && pwd)

if [ -f "$script_dir/.env" ]; then set -a ; source $script_dir/.env; set +a; fi
if [ -f "$script_dir/github-api.sh" ]; then set -a ; source $script_dir/github-api.sh; set +a; fi

Usage(){
cat << EOF
run.sh <OUTPUT_DIR> [VERSION_FILE]
Options:
	-f|--version-file <PATH>    Path file to versions.csv file
	-c|--cache                  If true repo will not clean before git clone
	-a|--all-version            Default only changed versions are apply to create package file, 
	                            use this option will ignore it | default false
	-i|--log-issue <PATH>       Log issue to a file
	-v|--verbose                Print all files adding to zip file on the screen
	-h|--help                   Print help
EOF
}

# get options
CACHE=false; VERBOSE=false; HELP=false; ONLY_CHANGED_VERSION=true
POSITIONAL=()
while [[ $# -gt 0 ]]
do
key="$1"
case $key in
    -f|--version-file) VERSION_FILE="$2"
    shift # past argument
    shift # past value
    ;;
    -c|--cache) CACHE=true
    shift # past argument
    ;;
    -a|--all-version) ONLY_CHANGED_VERSION=false
    shift # past argument
    ;;
    -h|--help) HELP=true
    shift # past argument
    ;;
    -i|--log-issue) LOG_ISSUE="$2"
    shift # past argument
    shift # past value
    ;;
    -v|--verbose) VERBOSE=true
    shift # past argument
    ;;
    --) shift # ignore --
    ;;
    *)    # unknown option
    POSITIONAL+=("$1") # save it in an array for later
    shift # past argument
    ;;
esac
done
set -- "${POSITIONAL[@]}" # restore positional parameters
# end get options

# print help
if [ $HELP == true ]; then
	Usage
	exit 0
fi

# get output dir by param or env OUTPUT_DIR
if [ ! -z $1 ]; then
	OUTPUT_DIR=$1
elif [ -z "$OUTPUT_DIR" ]; then
	OUTPUT_DIR="$script_dir" # default output dir is this script dir
fi
if [ $(echo "$OUTPUT_DIR" | grep -v "^/" | wc -l) -ne 0 ]; then
	OUTPUT_DIR="$current_dir/$OUTPUT_DIR"
fi
mkdir -p $OUTPUT_DIR

# begin run script
# change to resource dir before run everything with source files
pushd $script_dir 2>&1 >/dev/null

# get INPUT_DIR
if [ ! -z $VERSION_FILE ]; then
    INPUT_DIR=$(dirname $VERSION_FILE)
    INPUT_DIR=$(cd $current_dir 2>&1 >/dev/null && cd $INPUT_DIR 2>&1 >/dev/null && pwd) # get full path
    VERSION_FILE=$INPUT_DIR/$(basename $VERSION_FILE) # convert relative path to full path of version file
else
    echo "No Version file or INPUT_DIR"
    exit 1
fi

# clear old repo dir
if [ $CACHE == false ]; then
    rm -rf $REPOS_DIR
fi
mkdir -p $REPOS_DIR
# clear old temp
if [ -d "$TEMP_DIR" ]; then
    rm -rf $TEMP_DIR
fi
mkdir -p $TEMP_DIR

# renew log-issue file content
if [[ -z $LOG_ISSUE && -f $LOG_ISSUE ]]; then
    rm $LOG_ISSUE
fi

# read versions csv file
VERSIONS_COLS=()
declare -A VERSIONS_ROWS; VERSIONS_ROWS_NUMS=0; VERSIONS_ROWS_COLS=0 # array defined
IS_GET_HEAD=0
while IFS='' read -r line || [[ -n "$line" ]]; do
	if [[ $IS_GET_HEAD == 1 ]]; then
		n=0; line2=""
		for (( i=0; i<${#line}; i++ )); do
			if [[ "${line:$i:1}" == '"' ]]; then ((n=n+1)); fi
			if [[ "${line:$i:1}" == ',' && $((n%2)) -eq 1 ]]; then line2="${line2}&comma;"; continue; fi
			if [[ "${line:$i:1}" == ' ' && $((n%2)) -eq 1 ]]; then line2="${line2}&space;"; continue; fi
			line2="${line2}${line:$i:1}"
		done
		line=$line2
		line=$(echo $line | sed -e "s/[\"']*\s*,\s*[\"']*/,/g" | sed -e "s/^[\"']//g" | sed -e "s/[\"']$//g" | sed -e "s/,/\",\"/g")
		line="\"$line\""
		OLDIFS=$IFS
		line=$( echo $line | sed -e "s/\r//g" | sed -e "s/\n//g" ) # fix ignore new line to array
		IFS=, read -r -a ROW <<<"$line" # read to array
		IFS=$OLDIFS
		VERSIONS_ROWS_COLS=0
		for idx in ${!ROW[@]}; do
			CELL=$(echo "${ROW[$idx]}" | sed -e 's/\s+$//g' | sed -e 's/^\s+//g') # truncate space
			CELL=$(echo "$CELL" | sed -e 's/^\"\s*//g' | sed -e 's/\s*\"$//g') # remove double quote
			CELL=$(echo "$CELL" | sed "s/ /-/g") # replace space at cell value
			CELL=$(echo "$CELL" | sed 's/&comma;/,/g' | sed -e 's/&space;/ /g') # backup &comma;, &space;
			VERSIONS_ROWS[$VERSIONS_ROWS_NUMS,$idx]="$CELL"
			VERSIONS_ROWS_COLS=$((VERSIONS_ROWS_COLS+1))
		done
		VERSIONS_ROWS_NUMS=$((VERSIONS_ROWS_NUMS+1))
	else
		if [[ $(echo $line | grep -e "Name\s*,\s*Repo\s*,\s*Prev\s*Version" | wc -l) -ne 0 ]]; then
			VERSIONS_COLS=( $(echo "$line" | sed -e "s/.*/\U&/g" | sed -e "s/\s//g" | sed "s/-/_/g" | sed "s/\"//g" | sed "s/'//g" | sed "s/,/ /g") )
			IS_GET_HEAD=1
		fi
	fi
done < "$VERSION_FILE"
declare -A VERSIONS_COLS_IDX
for IDX in ${!VERSIONS_COLS[@]}; do
	VERSIONS_COLS_IDX["${VERSIONS_COLS[$IDX]}"]="$IDX"
done
# end read versions

# get repo list from Repo column of versions.csv file
# etc: REPOS[WebPOS-Magento2-New]=1
declare -A REPOS # repos to clone
declare -A REPOS_OF_REPO; # all sub repos of all repos
for (( i=0; i<$VERSIONS_ROWS_NUMS; i++ )); do
	REPO_NAME=${VERSIONS_ROWS[$i,${VERSIONS_COLS_IDX[REPO]}]}
	REPOS_OF_REPO[$REPO_NAME,COLS]=0
	if [ ! -z "$REPO_NAME" ]; then
		PACKAGES_FILE=$INPUT_DIR/packages/${REPO_NAME}${PACKAGE_FILE_EXT}
		if [ -f $PACKAGES_FILE ]; then
			# Read repo list
			while IFS='' read -r line || [[ -n "$line" ]]; do
				if [ -z "$line" ]; then continue; fi #ignore zero line
				if [ ! -z "$(sed -e 's/^\s*//g' <<< $line | grep -e '^#')" ]; then continue; fi #ignore comment line
				name=$(echo $line | awk '{print $1}' | sed "s/ //g") # ignore space char
				name=$(echo $line | sed -e 's/^[ -]*//g' | sed -e 's/[ -]*$//g') # trim - and space
				if [[ "${REPOS[$name]}" != "1" ]]; then
					REPOS[$name]=1
				fi
				REPOS_OF_REPO[$REPO_NAME,${REPOS_OF_REPO[$REPO_NAME,COLS]}]="$name" # get sub repo names
				REPOS_OF_REPO[$REPO_NAME,COLS]=$((${REPOS_OF_REPO[$REPO_NAME,COLS]}+1))
			done < "$PACKAGES_FILE"
		else
			if [[ "${REPOS[$REPO_NAME]}" != "1" ]]; then
				REPOS[$REPO_NAME]=1 # add repo to all list repos
			fi
			REPOS_OF_REPO[$REPO_NAME,${REPOS_OF_REPO[$REPO_NAME,COLS]}]="$REPO_NAME"
			REPOS_OF_REPO[$REPO_NAME,COLS]=$((${REPOS_OF_REPO[$REPO_NAME,COLS]}+1))
		fi
	fi
done

# clone source code from REPOS array
# git clone --quiet --depth=1 -b $version ${github}${name}.git $mod_dir/$name 2>/dev/null || true
for (( i=0; i<$VERSIONS_ROWS_NUMS; i++ )); do
	NAME=${VERSIONS_ROWS[$i,${VERSIONS_COLS_IDX[NAME]}]}
	REPO_NAME=${VERSIONS_ROWS[$i,${VERSIONS_COLS_IDX[REPO]}]}
	if [ ! -z "$REPO_NAME" ]; then
		if [[ "${REPOS[$REPO_NAME]}" == "1" ]]; then
			VERSION=${VERSIONS_ROWS[$i,${VERSIONS_COLS_IDX[VERSION]}]} # get row value of Version col
			if [ -z "$VERSION" ]; then VERSION="master"; fi
			if [ -z "$GITHUB" ]; then echo "No GITHUB config value"; exit 1; fi
			if [ -z "$REPO_NAME" ]; then echo "No repo $REPO_NAME cloning"; continue; fi
			CLONE_DIR=$REPOS_DIR/$REPO_NAME
			if [[ -d "$CLONE_DIR" && ! -z "$NAME" ]]; then CLONE_DIR="$REPOS_DIR/${REPO_NAME}_${NAME}"; fi # create diff dir
			if [ ! -d "$CLONE_DIR" ]; then # clone if not exists, not --cache will delete repos dir before clone
				echo "Cloning $REPO_NAME version $VERSION"
				git clone --branch $VERSION --quiet --single-branch $GITHUB/$REPO_NAME.git $CLONE_DIR 2>/dev/null || true
			else
				echo "Skip cloning $REPO_NAME version $VERSION"
			fi
		fi
	fi
done

### copy repos to tmp dir for each package and add to zip file ###
# temp dir
if [ -z "$TEMP_DIR" ]; then TEMP_DIR='tmp'; fi
mkdir -p $TEMP_DIR
if [ -z "$OUTPUT_DIR" ]; then echo "OUTPUT_DIR not defined"; exit 1; fi
mkdir -p $OUTPUT_DIR
# copy repos for each row
for (( i=0; i<$VERSIONS_ROWS_NUMS; i++ )); do
	REPO_NAME=${VERSIONS_ROWS[$i,${VERSIONS_COLS_IDX[REPO]}]}
	if [ ! -z "$REPO_NAME" ]; then
		NAME=${VERSIONS_ROWS[$i,${VERSIONS_COLS_IDX[NAME]}]}
		PREV_VERSION=${VERSIONS_ROWS[$i,${VERSIONS_COLS_IDX[PREVVERSION]}]}
		VERSION=${VERSIONS_ROWS[$i,${VERSIONS_COLS_IDX[VERSION]}]}
		MAGENTO_VERSION="${VERSIONS_ROWS[$i,${VERSIONS_COLS_IDX[MAGENTOVERSION]}]}"
		if [ $ONLY_CHANGED_VERSION == true ]; then # only packages has changed version
			if [[ "$VERSION" == "$PREV_VERSION" ]]; then continue; fi # ignore the same version
		fi
        # No name value no create file
        if [ -z "$NAME" ]; then continue; fi
        # if not skip create this package file
		mkdir -p $TEMP_DIR # create temp dir
		for ((j=0; j<${REPOS_OF_REPO[$REPO_NAME,COLS]}; j++)); do
			repo_name=${REPOS_OF_REPO[$REPO_NAME,$j]}
			CLONED_DIR="$REPOS_DIR/$repo_name"
			if [[ "$REPO_NAME" == "$repo_name" && -d "$REPOS_DIR/${REPO_NAME}_${NAME}" ]]; then 
				CLONED_DIR="$REPOS_DIR/${REPO_NAME}_${NAME}"
			fi # find cloned dir, if is main repo
			if [ ! -d "$CLONED_DIR" ]; then echo "Error: no repo cloned $CLONED_DIR"; continue; fi
			if [ -f "$CLONED_DIR/etc/module.xml" ]; then
				name=$(cat $CLONED_DIR/etc/module.xml | grep -e 'module\sname=.*' | grep -e 'name=\S*' -o)
				module=$(echo $name | sed -r "s/'//g" | sed -r 's/"//g' | sed -r 's/name=//g')
				vendor_module=($(echo $module | sed -r 's/_/ /g'))
				if [ ! -z "${vendor_module[0]}" ]; then
					if [ ! -z "${vendor_module[1]}" ]; then
						if [ ! -d $TEMP_DIR/app/code/${vendor_module[0]}/${vendor_module[1]} ];
						   then mkdir -p $TEMP_DIR/app/code/${vendor_module[0]}/${vendor_module[1]} ;
						fi
						cp -rpf $CLONED_DIR/* $TEMP_DIR/app/code/${vendor_module[0]}/${vendor_module[1]}/
					else
						if [ ! -d $TEMP_DIR/app/code/${vendor_module[0]} ];
						   then mkdir -p $TEMP_DIR/app/code/${vendor_module[0]} ;
						fi
						cp -rpf $CLONED_DIR/* $TEMP_DIR/app/code/${vendor_module[0]}/
					fi
				fi
			else
				cp -rpf $CLONED_DIR/* $TEMP_DIR/
			fi
		done
		# run pack before add to zip file
		if [ -f "$INPUT_DIR/converter/${NAME}-${REPO_NAME}.sh" ]; then
			pushd $TEMP_DIR 2>&1 >/dev/null
			echo "Run pack ${NAME}-${REPO_NAME}"
			bash $INPUT_DIR/converter/${NAME}-${REPO_NAME}.sh
			popd 2>&1 >/dev/null
		fi
		
		# Read ignore-list and delete
		if [ -f "./ignore-list" ]; then
			while IFS='' read -r line || [[ -n "$line" ]]; do
				if [ -z "$line" ]; then continue; fi #ignore zero line
				if [ ! -z "$(sed -e 's/^\s*//g' <<< $line | grep -e '^#')" ]; then continue; fi #ignore comment line
				line=$(sed -e 's/^\s*//g' <<< "$line" | sed -e 's/^\///g') #validate input white space and /
				if [ -f "$TEMP_DIR/$line" ]; then
					rm $TEMP_DIR/$line
				else
					if [ -d "$TEMP_DIR/$line" ]; then
						rm -rf $TEMP_DIR/$line
					fi
				fi
			done < ./ignore-list
		fi
		
		# add to zip file
		MAGENTO_VERSION=$(sed "s/ /-/g" <<< $MAGENTO_VERSION)
		file_name="${FILE_NAME_PREFIX}${NAME}-v${VERSION}-${MAGENTO_NAME_PREFIX}${MAGENTO_VERSION}.zip"
		file_name=$(echo $file_name | sed 's/\///g')
		echo "Create package $file_name"
		if [ -d $TEMP_DIR ]; then
			pushd $TEMP_DIR 2>&1 >/dev/null
			# remove old zip file if exist
			if [ -f "$OUTPUT_DIR/$file_name" ]; then
				rm $OUTPUT_DIR/$file_name
			fi
			if [ $(ls -l | grep -v "^total" | wc -l) -eq 0 ]; then echo "No file added to zip file"; exit 0; fi
			# zip file
			if [ $VERBOSE == true ]; then
				zip -r9 "$OUTPUT_DIR/$file_name" .
			else
				zip -r9 "$OUTPUT_DIR/$file_name" . >/dev/null
			fi
			popd 2>&1 >/dev/null
			rm -rf $TEMP_DIR # delete temp dir each package create complete
		else
			echo "Directory $OUTPUT_DIR doesn't exists"
		fi
	fi
done

# Get commits and issue id from repos write to versions.csv
declare -A commits_repo; # declare array 2D
declare -A issue_ids_repo; # declare array 1D, issue IDs (int)
declare -A noissue_repo; # declare array 2D, array of commits no issue of a repo
if [ ! -z "$NO_ISSUE_FILE" ]; then rm -f $OUTPUT_DIR/$NO_ISSUE_FILE; fi # delete old file
for (( i=0; i<$VERSIONS_ROWS_NUMS; i++ )); do
	REPO_NAME=${VERSIONS_ROWS[$i,${VERSIONS_COLS_IDX[REPO]}]}
	if [ ! -z "$REPO_NAME" ]; then
		REPO=${VERSIONS_ROWS[$i,${VERSIONS_COLS_IDX[REPO]}]}
		PREV_VERSION=${VERSIONS_ROWS[$i,${VERSIONS_COLS_IDX[PREVVERSION]}]}
		VERSION=${VERSIONS_ROWS[$i,${VERSIONS_COLS_IDX[VERSION]}]}
		if [[ "$VERSION" == "$PREV_VERSION" ]]; then continue; fi # skip same version
		repo_abspath="$script_dir/$REPOS_DIR/$REPO"
		if [ ! -d "$repo_abspath/.git" ]; then echo "Repo $REPOS_DIR/$REPO does not exists."; continue; fi # ignore not is repo
		commits_repo[$REPO,length]=0
		noissue_repo[$REPO,length]=0
		commits_issues=()
		echo "# $REPO -- v${PREV_VERSION} -> v${VERSION}" >> $OUTPUT_DIR/$NO_ISSUE_FILE
		echo "" >> $OUTPUT_DIR/$NO_ISSUE_FILE
		git_log_revision_range="$PREV_VERSION..$VERSION" # for git log revision range filter
		if [ -z "$PREV_VERSION" ]; then git_log_revision_range="$VERSION"; fi
		git_log_ignore_author="--invert-grep --author=$IGNORE_AUTHOR" # for git log ignore authors
		while IFS='' read -r line || [[ -n "$line" ]]; do # read git commits
			commits_repo[$REPO,${commits_repo[$REPO,length]}]="$line"
			((commits_repo[$REPO,length]=${commits_repo[$REPO,length]}+1)) # add 1 item
			# find issues id number
			issue_ids="$(echo "$line" | sed -e 's/[^#0-9]/ /g' | sed -e 's/##//g' | sed -e 's/\s#\s//g' | sed -e 's/\s\+[0-9]\+\s\+/ /g' | sed -e 's/^[ 0-9]*\?//g' | sed -e 's/\s[ 0-9]*#\?$//g' | sed 's/  //g')"
			if [[ "$(sed 's/ //g' <<< $issue_ids)" != "" ]]; then
				commits_issues+=("$issue_ids") # issue of a repo as string
			else
				noissue_repo[$REPO,${noissue_repo[$REPO,length]}]="$line" # commit no issue of a repo
				((noissue_repo[$REPO,length]=${noissue_repo[$REPO,length]}+1))
				echo "- $line" >> $OUTPUT_DIR/$NO_ISSUE_FILE
			fi
		done <<< "$(cat <<< "$( cd $repo_abspath 2>&1 1>/dev/null && git log $git_log_revision_range --pretty=format:'%H %an %N %s' $git_log_ignore_author 2>/dev/null)" | grep -ve ".*Merge.*")"
		echo "" >> $OUTPUT_DIR/$NO_ISSUE_FILE
		# get commits issues to issues_repo
		declare -A has_issue
		for issue in ${commits_issues[@]}; do
			issue_id="$(sed 's/#//g' <<< $issue)"
			if [[ ${has_issue[$issue_id]} -ne 1 ]]; then
				issue_ids_repo[$REPO]="${issue_ids_repo[$REPO]} $issue_id"
				has_issue[$issue_id]=1
			fi
		done
		unset has_issue
		unset commits_issues
	fi
done
# from issue id get issue messages from github api
declare -A issues_repos # issues message body in repos (array length noissue_repo[$repo,length])
for repo in ${!issue_ids_repo[@]}; do
	issues_repos[$repo,length]=0
	for id in ${issue_ids_repo[$repo]}; do
		issue_body=$(get_issue $repo $id | sed "s/$IGNORE_TEXT_ISSUE//g" | sed -e "s/\n//g" | sed -e "s/\r//g") # remove double quote of `"$()"` or remove \r\n to skip one line
		issues_repos[$repo,${issues_repos[$repo,length]}]="$issue_body"
		issues_repos[$repo,length]=$((${issues_repos[$repo,length]}+1))
	done
done
# write release notes (issues) to versions.csv
NEW_VERSIONS_FILE="$OUTPUT_DIR/versions.csv"
touch $NEW_VERSIONS_FILE
head_line=$(cat $VERSION_FILE | grep -e "Name\s*,\s*Repo\s*,\s*Prev\s*Version") # get head line
echo "$head_line" > $NEW_VERSIONS_FILE
declare -A NEW_VERSIONS_ROWS; NEW_VERSIONS_ROWS_NUMS=0; NEW_VERSIONS_ROWS_COLS=6 # declare new array with 6 cols
for (( i=0; i<$VERSIONS_ROWS_NUMS; i++ )); do
	NAME=${VERSIONS_ROWS[$i,${VERSIONS_COLS_IDX[NAME]}]}
	REPO=${VERSIONS_ROWS[$i,${VERSIONS_COLS_IDX[REPO]}]}
	PREV_VERSION=${VERSIONS_ROWS[$i,${VERSIONS_COLS_IDX[PREVVERSION]}]}
	VERSION=${VERSIONS_ROWS[$i,${VERSIONS_COLS_IDX[VERSION]}]}
	RELEASE_NOTES=${VERSIONS_ROWS[$i,${VERSIONS_COLS_IDX[RELEASENOTES]}]}
	MAGENTO_VERSION=${VERSIONS_ROWS[$i,${VERSIONS_COLS_IDX[MAGENTOVERSION]}]}
	if [[ (! -z "$NAME" && ! -z "$REPO") && "$VERSION" != "$PREV_VERSION" ]]; then
		#if [[ "$VERSION" == "$PREV_VERSION" ]]; then continue; fi # skip same version
		if [[ ${issues_repos[$REPO,length]} -gt 0 ]]; then
			# add commit lines to first NEW_VERSIONS_ROWS item
			NEW_VERSIONS_ROWS[$NEW_VERSIONS_ROWS_NUMS,${VERSIONS_COLS_IDX[NAME]}]="$NAME" # add to first line
			NEW_VERSIONS_ROWS[$NEW_VERSIONS_ROWS_NUMS,${VERSIONS_COLS_IDX[REPO]}]="$REPO" # add to first line
			NEW_VERSIONS_ROWS[$NEW_VERSIONS_ROWS_NUMS,${VERSIONS_COLS_IDX[PREVVERSION]}]="$PREV_VERSION" # add to first line
			NEW_VERSIONS_ROWS[$NEW_VERSIONS_ROWS_NUMS,${VERSIONS_COLS_IDX[VERSION]}]="$VERSION" # add to first line
			NEW_VERSIONS_ROWS[$NEW_VERSIONS_ROWS_NUMS,${VERSIONS_COLS_IDX[RELEASENOTES]}]="$( sed -e 's/"/""/g' <<< ${issues_repos[$REPO,0]})" # add to first line
			NEW_VERSIONS_ROWS[$NEW_VERSIONS_ROWS_NUMS,${VERSIONS_COLS_IDX[MAGENTOVERSION]}]="$MAGENTO_VERSION" # add to first line
			NEW_VERSIONS_ROWS_NUMS=$(($NEW_VERSIONS_ROWS_NUMS+1)) # 1st row
			#myarray=("${myarray[@]:1}") # shift array
			# add commit lines to NEW_VERSIONS_ROWS
			for (( j=1; j<${issues_repos[$REPO,length]}; j++ )); do
				issue="$( sed -e 's/"/""/g' <<< ${issues_repos[$REPO,$j]})"
				if [ -z "$issue" ]; then continue; fi
				NEW_VERSIONS_ROWS[$NEW_VERSIONS_ROWS_NUMS,${VERSIONS_COLS_IDX[NAME]}]=""
				NEW_VERSIONS_ROWS[$NEW_VERSIONS_ROWS_NUMS,${VERSIONS_COLS_IDX[REPO]}]=""
				NEW_VERSIONS_ROWS[$NEW_VERSIONS_ROWS_NUMS,${VERSIONS_COLS_IDX[PREVVERSION]}]=""
				NEW_VERSIONS_ROWS[$NEW_VERSIONS_ROWS_NUMS,${VERSIONS_COLS_IDX[VERSION]}]=""
				NEW_VERSIONS_ROWS[$NEW_VERSIONS_ROWS_NUMS,${VERSIONS_COLS_IDX[RELEASENOTES]}]="$issue"
				NEW_VERSIONS_ROWS[$NEW_VERSIONS_ROWS_NUMS,${VERSIONS_COLS_IDX[MAGENTOVERSION]}]=""
				NEW_VERSIONS_ROWS_NUMS=$(($NEW_VERSIONS_ROWS_NUMS+1)) # add row
			done
		else
			# add issues for big packages in REPOS_OF_REPO
			for ((j=0; j<${REPOS_OF_REPO[$REPO,COLS]}; j++)); do
				repo=${REPOS_OF_REPO[$REPO,$j]}
				# add commit lines to NEW_VERSIONS_ROWS
				if [[ ${issues_repos[$repo,length]} -gt 0 ]]; then # if this repo has issue
					for (( k=0; k<${issues_repos[$repo,length]}; k++ )); do
						if [[ $j == 0 && $k == 0 ]]; then
							# add commit lines to first NEW_VERSIONS_ROWS item
							NEW_VERSIONS_ROWS[$NEW_VERSIONS_ROWS_NUMS,${VERSIONS_COLS_IDX[NAME]}]="$NAME" # add to first line
							NEW_VERSIONS_ROWS[$NEW_VERSIONS_ROWS_NUMS,${VERSIONS_COLS_IDX[REPO]}]="$REPO" # add to first line
							NEW_VERSIONS_ROWS[$NEW_VERSIONS_ROWS_NUMS,${VERSIONS_COLS_IDX[PREVVERSION]}]="$PREV_VERSION" # add to first line
							NEW_VERSIONS_ROWS[$NEW_VERSIONS_ROWS_NUMS,${VERSIONS_COLS_IDX[VERSION]}]="$VERSION" # add to first line
							NEW_VERSIONS_ROWS[$NEW_VERSIONS_ROWS_NUMS,${VERSIONS_COLS_IDX[RELEASENOTES]}]="$( sed -e 's/"/""/g' <<< ${issues_repos[$repo,0]})" # add to first line
							NEW_VERSIONS_ROWS[$NEW_VERSIONS_ROWS_NUMS,${VERSIONS_COLS_IDX[MAGENTOVERSION]}]="$MAGENTO_VERSION" # add to first line
							NEW_VERSIONS_ROWS_NUMS=$(($NEW_VERSIONS_ROWS_NUMS+1)) # 1st row
						else
							issue="$( sed -e 's/"/""/g' <<< ${issues_repos[$repo,$k]})"
							if [ -z "$issue" ]; then continue; fi
							NEW_VERSIONS_ROWS[$NEW_VERSIONS_ROWS_NUMS,${VERSIONS_COLS_IDX[NAME]}]=""
							NEW_VERSIONS_ROWS[$NEW_VERSIONS_ROWS_NUMS,${VERSIONS_COLS_IDX[REPO]}]=""
							NEW_VERSIONS_ROWS[$NEW_VERSIONS_ROWS_NUMS,${VERSIONS_COLS_IDX[PREVVERSION]}]=""
							NEW_VERSIONS_ROWS[$NEW_VERSIONS_ROWS_NUMS,${VERSIONS_COLS_IDX[VERSION]}]=""
							NEW_VERSIONS_ROWS[$NEW_VERSIONS_ROWS_NUMS,${VERSIONS_COLS_IDX[RELEASENOTES]}]="$issue"
							NEW_VERSIONS_ROWS[$NEW_VERSIONS_ROWS_NUMS,${VERSIONS_COLS_IDX[MAGENTOVERSION]}]=""
							NEW_VERSIONS_ROWS_NUMS=$(($NEW_VERSIONS_ROWS_NUMS+1)) # add row
						fi
					done
				fi
			done
		fi
	else
		# allow old row data
		NEW_VERSIONS_ROWS[$NEW_VERSIONS_ROWS_NUMS,${VERSIONS_COLS_IDX[NAME]}]="$NAME"
		NEW_VERSIONS_ROWS[$NEW_VERSIONS_ROWS_NUMS,${VERSIONS_COLS_IDX[REPO]}]="$REPO"
		NEW_VERSIONS_ROWS[$NEW_VERSIONS_ROWS_NUMS,${VERSIONS_COLS_IDX[PREVVERSION]}]="$PREV_VERSION"
		NEW_VERSIONS_ROWS[$NEW_VERSIONS_ROWS_NUMS,${VERSIONS_COLS_IDX[VERSION]}]="$VERSION"
		NEW_VERSIONS_ROWS[$NEW_VERSIONS_ROWS_NUMS,${VERSIONS_COLS_IDX[RELEASENOTES]}]="$RELEASE_NOTES"
		NEW_VERSIONS_ROWS[$NEW_VERSIONS_ROWS_NUMS,${VERSIONS_COLS_IDX[MAGENTOVERSION]}]="$MAGENTO_VERSION"
		NEW_VERSIONS_ROWS_NUMS=$(($NEW_VERSIONS_ROWS_NUMS+1)) # add row
	fi
done
# add to new versions file
for (( i=0; i<$NEW_VERSIONS_ROWS_NUMS; i++ )); do
	line=""
	for ((j=0; j<$NEW_VERSIONS_ROWS_COLS; j++)); do
		line="$line,\"${NEW_VERSIONS_ROWS[$i,$j]}\""
	done
	line=$(sed -e "s/^,//g" <<< $line) # remove comma at 1st char of string
	echo $line >> $NEW_VERSIONS_FILE
done

# add new versions file csv to github
if [ ! -z "$OUTPUT_RELEASE_NOTES" ]; then
	cp -f $NEW_VERSIONS_FILE $current_dir/$OUTPUT_RELEASE_NOTES # add new versions file to replace old versions file
	pushd $current_dir 2>&1 >/dev/null
	git add $OUTPUT_RELEASE_NOTES
	popd
else
	cp -f $NEW_VERSIONS_FILE $VERSION_FILE # add new versions file to replace old versions file
	pushd ../ 2>&1 >/dev/null
	git add release-notes/
	popd
fi
# add commits no issue file to github
if [ ! -z "$NO_ISSUE_FILE" ]; then
	cp -f $OUTPUT_DIR/$NO_ISSUE_FILE $INPUT_DIR/$NO_ISSUE_FILE
	pushd $current_dir 2>&1 >/dev/null
	git add $INPUT_DIR/$NO_ISSUE_FILE
	popd
fi
# git push all stage changes
if [ $(git status | grep 'Changes to be committed:' | wc -l) -gt 0 ]; then
	git commit -m "Release tool auto release packages"
	git push
fi

popd 2>&1 >/dev/null # return to old dir before change to run.sh location
# end run script

# exit if only run for package release
#echo "Run complete $file_name." >&1
echo "Release complete."
exit 0

