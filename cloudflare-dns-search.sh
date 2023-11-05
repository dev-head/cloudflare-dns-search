#!/usr/bin/env bash

API_TOKEN="${CF_API_TOKEN:-123}"
SEARCH_TERM=""
CLEAR_ALL_CACHE="false"

API_ENDPOINT="https://api.cloudflare.com/client/v4"
CACHE_DIR=".cfdnscache"

SKIP_ACCESS_VALIDATION=false # If true, no api access validation test is ran; reducing time.
SKIP_BUILD_CACHE=false # If you have all cache already, this will skip the building phases to reduce time.
CLEAR_ZONE_CACHE=false	# Set to true if you want to force clearing zone cache
CLEAR_ZONE_RECORD_CACHE=false # Set to true if you want to force clearing zone record cache
LOG_LEVEL="" # Set to "INFO" for output.

log(){
    if [[ "${LOG_LEVEL}" != "INFO" ]]; then return 1; fi
    local prefix="[${0}]::$(date +"[%Y-%m-%d %H:%M:%S]")"
    echo "$prefix $1"
}

log_error_exit(){
    log "${1}"
    exit 1
}

set -euo pipefail

usage(){
>&2 cat << EOF
Usage: $0
   OPTIONS 
   [ -a  CF_API_TOKEN (REQUIRED) Cloudflare API Token ]
   [ -s  (REQUIRED) Pass search term for this match. (Uses jq.contain()) ]
   [ -c  Set option to clears all cache ]
   [ -v  Set option to enable verbose output ] 


++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
This script is used to identify Cloudflare DNS Records that match your search term.
CF does not support any global searching across accounts or even just for the look up type.
WARNING: Initial cache build may be really slow; CF will throttle the API if you have a large set of zones and records.

- @Dependencies: jq 
- @Cacheing: Zones and Zone Record results are cached by default to ensure faster subsequent usage.
- @Access Cloudflare API access is required.
- [Create an "API Token"](https://developers.cloudflare.com/fundamentals/api/get-started/create-token/)
		- Permissions: "Zone.Zone, Zone.DNS", "Read Only"
		- Resources: "All Zones"
++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
EOF

exit 1
}

while getopts "a:s:f:hcv" option; do    
	case $option in         
		h) # display Help            
			usage && exit;;         
		\?) # incorrect option
			echo "[Error: Invalid option]"
			usage && exit;;  
		a) API_TOKEN=${OPTARG};;    
		c) CLEAR_ALL_CACHE="true";;
		v) LOG_LEVEL="INFO";;
		f) SEARCH_FIELD=${OPTARG};;
		s) SEARCH_TERM=${OPTARG};;
	esac
done

debug(){
	log "[API_TOKEN]::[${API_TOKEN}]"
	log "[SEARCH_TERM]::[${SEARCH_TERM}]"
	log "[CLEAR_ALL_CACHE]::[${CLEAR_ALL_CACHE}]"
	log "[API_ENDPOINT]::[${API_ENDPOINT}]"
	log "[CACHE_DIR]::[${CACHE_DIR}]"
	log "[SKIP_ACCESS_VALIDATION]::[${SKIP_ACCESS_VALIDATION}]"
	log "[SKIP_BUILD_CACHE]::[${SKIP_BUILD_CACHE}]"
	log "[CLEAR_ZONE_CACHE]::[${CLEAR_ZONE_CACHE}]"
	log "[CLEAR_ZONE_RECORD_CACHE]::[${CLEAR_ZONE_RECORD_CACHE}]"
	log "[LOG_LEVEL]::[${LOG_LEVEL}]"
}

configure(){
    log "[configuration]::[started]"
	if [[ -z "${API_TOKEN}" ]]; then
		log_error_exit "[FATAL ERROR]::[MISSING REQUIRED API_TOKEN AS FIRST ARGUMENT]"
	fi

	if [[ -z "${SEARCH_TERM}" ]]; then
		log_error_exit "[FATAL ERROR]::[MISSING REQUIRED SEARCH_TERM AS SECOND ARGUMENT]"
	fi

	if [[ ! -d "${CACHE_DIR}" ]]; then 
		mkdir -p "${CACHE_DIR}"
	fi

	if [[ "${CLEAR_ALL_CACHE}" = true ]]; then 
		echo "[Clearing all cache]"
		rm -R ${CACHE_DIR}/cache.*.json > /dev/null 2>&1
	fi 

	if [[ "${CLEAR_ZONE_CACHE}" = "true" ]]; then 
		log "[Clearing Zone Cache]"
		rm -R ${CACHE_DIR}/cache.zone_list.json > /dev/null 2>&1
	fi 

	if [[ "${CLEAR_ZONE_RECORD_CACHE}" = "true" ]]; then
		log "[Clearing Zone Cache]"
		rm -R ${CACHE_DIR}/cache.zone_records.json > /dev/null 2>&1
	fi
    log "[configuration]::[complete]"
}

validate_access(){
    log "[validate_access]::[started]"

	if [[ "${SKIP_ACCESS_VALIDATION}" != "true" ]]; then
		log "[Validating Access]"
		local response=$(curl -sX GET "${API_ENDPOINT}/user/tokens/verify" \
	     -H "Authorization: Bearer ${API_TOKEN}" \
	     -H "Content-Type:application/json")
		log "[Response]::[$(echo $response | jq -r '.messages[].message')]"

		if [[ "$(echo $response | jq -r '.success')" = "false" ]]; then
			echo "[FAILURE]::[Auth Failed]"
			echo $response | jq 
			exit 1
		fi
		log "[Access Validated]"
	fi
    log "[validate_access]::[complete]"
}

put_in_cache(){
	local cache_file="cache.${1}.json"
	if [[ -f "${CACHE_DIR}/${cache_file}" ]]; then 
		rm "${CACHE_DIR}/${cache_file}"
	fi

	log "[saving to cache]::[${cache_file}]"
	echo "${2}" > "${CACHE_DIR}/${cache_file}"
}

get_from_cache() {
	local cache_file="cache.${1}.json"
	if [[ -f "${CACHE_DIR}/${cache_file}" ]]; then 
		cat "${CACHE_DIR}/${cache_file}"
	fi
}

build_zone_cache(){
	log "[Getting Zones]"
	local PAGE_NUMBER=1
	local PAGE_SIZE=50
	local PAGE_LIMIT=999999
	local PAGE_ORDER="account.name"
	local ZONE_LIST_CACHED=$(get_from_cache "zone_list")
	local ZONE_LIST=""

	if [[ ! -z "${ZONE_LIST_CACHED}" ]]; then 
		log "[Using cached zones]"
		ZONE_LIST=${ZONE_LIST_CACHED}
		return 1
	fi 

	while true; do
		local ZONE_PAGE=$(curl -sX GET "${API_ENDPOINT}/zones?page=${PAGE_NUMBER}&per_page=${PAGE_SIZE}&order=${PAGE_ORDER}" \
	    	-H "Authorization: Bearer ${API_TOKEN}" \
	     	-H "Content-Type:application/json")

		local results_info=$(echo "${ZONE_PAGE}" | jq -r '.result_info')
		local results_errors=$(echo "${ZONE_PAGE}" | jq -r '.errors[].message')

		if [[ ! -z "${results_errors}" ]]; then 
			log_error_exit "[Zone errors]::[${results_errors}]"
		fi

	    if [[ "$(echo "${ZONE_PAGE}" | jq -r 'if .result != null then .result[] else "" end')" == "" ]]; then
	        break
	    fi
		
		log "[zone results found]::[$(echo ${results_info} | jq -r '.total_count')]::[on page]::[($(echo ${results_info} | jq -r '.page')) of ($(echo ${results_info} | jq -r '.total_pages'))]"

	    # Concatenate zone results from all pages
	    ZONE_LIST="$ZONE_LIST$(echo "${ZONE_PAGE}" | jq -c '.result[]')"

	    PAGE_NUMBER=$((PAGE_NUMBER + 1))
	    if [[ ${PAGE_NUMBER} > ${PAGE_LIMIT} ]]; then
	    	break 
	    fi

	done
	put_in_cache zone_list "$(echo "${ZONE_LIST}" | jq -n '[inputs]')"
	log "[Zones Gathered]"
}

build_zone_record_cache(){
	log "[Building Zone Record Cache]"
	local ZONE_RECORDS=$(get_from_cache "zone_records")
	local NUM_RECORDS_CACHED=$(echo ${ZONE_RECORDS} | jq length)
	
	if [[ "${NUM_RECORDS_CACHED}" > 1 ]]; then
		log "[Existing Cache found]::[Num Records]::[${NUM_RECORDS_CACHED}]"
    	return 1
    fi

	local ZONE_LIST=$(get_from_cache "zone_list")
	local ZONE_LIST_ENCODED=$(echo "$ZONE_LIST" | jq -r '.[] | @base64')
	local i=0
	for zone in $ZONE_LIST_ENCODED; do
		local ZONE_DECODED=$(echo $zone | base64 --decode)
	    _get_from_zone(){ echo ${ZONE_DECODED} | jq -r ${1}; }
		if [[ $(_get_from_zone '.status') != "active" ]]; then continue; fi

	    local ZONE_ID=$(_get_from_zone '.id')
	    local ZONE_NAME=$(_get_from_zone '.name')
		local ACCOUNT_ID=$(_get_from_zone '.account.id')
		local ACCOUNT_NAME=$(_get_from_zone '.account.name')
		local PAGE_NUMBER=1
		local PAGE_SIZE=50000
		local PAGE_LIMIT=9999999
		local PAGE_ORDER="type"
		log "[Fetching records for]::[${ACCOUNT_NAME}]::[${ZONE_NAME}]"

		while true; do

			local RECORD_PAGE=$(curl -sX GET "${API_ENDPOINT}/zones/${ZONE_ID}/dns_records?page=${PAGE_NUMBER}&per_page=${PAGE_SIZE}&order=${PAGE_ORDER}" \
		    	-H "Authorization: Bearer ${API_TOKEN}" \
		     	-H "Content-Type:application/json")

			local results_errors=$(echo "${RECORD_PAGE}" | jq -r '.errors[].message')

			if [[ ! -z "${results_errors}" ]]; then 
				log "[DNS List Errors]::[${results_errors}]"
				log "${RECORD_PAGE}" | jq
			   	put_in_cache "zone_records" "$(echo "${NUM_RECORDS_CACHED}" | jq -n '[inputs]')"
				exit 1
			fi

		    if [[ "$(echo "${RECORD_PAGE}" | jq -r 'if .result != null then .result[] else "" end')" == "" ]]; then break; fi
			
			# appending account info to the zone record so we can find it in our system.
		    RESULT=$(echo "${RECORD_PAGE}" | jq \
		    	--arg ACCOUNT_NAME "${ACCOUNT_NAME}" --arg ACCOUNT_ID "${ACCOUNT_ID}" \
		    	-r '.result[]  += {"account_name": $ACCOUNT_NAME, "account_id": $ACCOUNT_ID} | .result[]')

		    # Concatenate zone results from all pages
		    NUM_RECORDS_CACHED="$NUM_RECORDS_CACHED$RESULT"

		    PAGE_NUMBER=$((PAGE_NUMBER + 1))
		    if [[ ${PAGE_NUMBER} > ${PAGE_LIMIT} ]]; then
		    	break
		    fi
		done
	done

	if [[ ! -z "${NUM_RECORDS_CACHED}" ]]; then
    	put_in_cache "zone_records" "$(echo "${NUM_RECORDS_CACHED}" | jq -n '[inputs]')"
    fi

	log "[Zone Record Cache Created]"
}

find_matches_in_cache(){
	echo $(get_from_cache "zone_records") | jq \
		--arg SEARCH_TERM "${SEARCH_TERM}" '.[] | select (.content | contains($SEARCH_TERM))'
}


build_cache(){
	if [[ "${SKIP_BUILD_CACHE}" != "true" ]]; then
		build_zone_cache
		build_zone_record_cache
	fi
}

execute(){
	debug
	configure
	validate_access
    build_cache
	find_matches_in_cache
}

log "[starting]"
execute
log "[completed]"