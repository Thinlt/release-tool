#!/bin/bash

API="https://api.github.com"
TOKEN="magestore-system:9ed5102ba8f0b9f66f4beb63055c29e493285054"

# "compare two versions"
# Get /repos/:owner/:repo/compare/:tag1...tag2
# Params: 
#         $1 - repo name
#         $2 - tag1
#         $3 - tag2
function compare_versions {
  if [[ -z $1 || -z $2 || -z $3 ]]; then
    echo "" | cat
  else
    curl -u $TOKEN $API/repos/Magestore/$1/compare/$2...$3 | cat
  fi
}

# GET /repos/:owner/:repo/issues/:number
# Response:
# {
#   "id": 1,
#   "node_id": "MDU6SXNzdWUx",
#   "url": "https://api.github.com/repos/octocat/Hello-World/issues/1347",
#   "repository_url": "https://api.github.com/repos/octocat/Hello-World",
#   "labels_url": "https://api.github.com/repos/octocat/Hello-World/issues/1347/labels{/name}",
#   "comments_url": "https://api.github.com/repos/octocat/Hello-World/issues/1347/comments",
#   "events_url": "https://api.github.com/repos/octocat/Hello-World/issues/1347/events",
#   "html_url": "https://github.com/octocat/Hello-World/issues/1347",
#   "number": 1347,
#   "state": "open",
#   "title": "Found a bug",
#   "body": "I'm having a problem with this."
# }
# Params: 
#         $1 - repo name
#         $2 - number issue id
# Using: get_issue <repo> <id>
function get_issue { # return issue text one line
  if [[ -z $1 || -z $2 ]]; then
    echo "" | cat
  else
    if [[ $ISSUE_FORMAT_TYPE -eq 1 ]]; then
      curl -u $TOKEN $API/repos/Magestore/$1/issues/$2 2>/dev/null | python -c "import json,sys;reload(sys);sys.setdefaultencoding('utf8');obj=json.load(sys.stdin); print '{}'.format(obj.get('title')).encode('utf-8');" | cat
    elif [[ $ISSUE_FORMAT_TYPE -eq 2 ]]; then
      curl -u $TOKEN $API/repos/Magestore/$1/issues/$2 2>/dev/null | python -c "import json,sys;reload(sys);sys.setdefaultencoding('utf8');obj=json.load(sys.stdin); print '{}'.format(obj.get('body')).encode('utf-8');" | cat
    else
      curl -u $TOKEN $API/repos/Magestore/$1/issues/$2 2>/dev/null | python -c "import json,sys;reload(sys);sys.setdefaultencoding('utf8');obj=json.load(sys.stdin); print '{} - {}'.format(obj.get('title'), obj.get('body')).encode('utf-8');" | cat
    fi
  fi
}
function get_issue_data { # return issue as json text
  if [[ -z $1 || -z $2 ]]; then
    echo "" | cat
  else
    curl -u $TOKEN $API/repos/Magestore/$1/issues/$2 2>/dev/null | python -c "import json,sys;reload(sys);sys.setdefaultencoding('utf8');obj=json.load(sys.stdin); print json.dumps({'html_url':obj.get('html_url'), 'title':obj.get('title'), 'body':obj.get('body'), 'state':obj.get('state')});" | cat
  fi
}
