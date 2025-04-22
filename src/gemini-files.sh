#!/usr/bin/env bash

#
# Script: gemini-files.sh
# Purpose: CLI tool for Google Gemini File API
# Created: April 21, 2025
# Author: GreenC + Google Gemini Advanced 2.5 Pro
#

# The MIT License (MIT)
#
# Copyright (c) 2025 by User:GreenC (at en.wikipedia.org)
#
# Permission is hereby granted, free of charge, to any person obtaining a copy      
# of this software and associated documentation files (the "Software"), to deal   
# in the Software without restriction, including without limitation the rights                
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell    
# copies of the Software, and to permit persons to whom the Software is              
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.

#
# List, Delete, Upload, or Query files using the Google Gemini File API & Generative API
#
# Docs:
#   File API: https://ai.google.dev/gemini-api/docs/files
#   Generate Content: https://ai.google.dev/gemini-api/docs/api-overview#generate-content
#   Models: https://ai.google.dev/gemini-api/docs/models
#
# Usage:
#   ./gemini-files.sh [options] <ACTION> [action_args...]
#
# Action Modes & Arguments:
#   --list [id1 id2 ...]     List files. If specific file IDs (e.g., files/xxxx)
#                            are provided, only those files are listed.
#                            If no IDs are provided, all files are listed.
#   --delete [id1 id2 ...]   Delete files. If specific file IDs are provided,
#                            only those are targeted. If no IDs are provided,
#                            all files are targeted after confirmation.
#   --upload <fp1> [fp2 ...] Upload one or more specified files. Verifies status after upload.
#   --query <id_or_uri>      Query the specified file (requires --query-file).
#                            ID can be 'files/xxx' or just 'xxx'. URI is the full https link.
#
# Other Options:
#   --query-file <path>    Path to the file containing the text query (used with --query).
#   --model <name>         Model to use for --query (e.g., gemini-1.5-pro-latest).
#                          (Default: See DEFAULT_MODEL in config).
#   --keyfile <path>       Path to the file containing the Google API Key.
#                          (Overrides environment variable if both are set).
#   -v, --verbose          Enable verbose informational output to stderr.
#   -h, --help             Show this help message.
#
# API Key:
#   The script requires a Google API Key. It will be sourced in the following order:
#   1. From the file specified using the --keyfile <path> argument.
#   2. From the environment variable defined in API_KEY_ENV_VAR below.
#
# File API Limits (as of last check):
#   Max 20 GB total storage per project. Max 2 GB per file. Files stored for 48 hours.
#

# --- Default Configuration ---

API_KEY_ENV_VAR="GEMINI_API_KEY" # Environment variable name for API key

MODE="" # No default mode; will default to help if unset after parsing
LIST_BASE_URL="https://generativelanguage.googleapis.com/v1beta/files" # URL for listing files
API_ROOT_URL="https://generativelanguage.googleapis.com/v1beta"      # Root for specific file operations (GET, DELETE) using 'name'
UPLOAD_BASE_URL="https://generativelanguage.googleapis.com/upload/v1beta/files" # URL for file uploads
GENERATE_CONTENT_URL_TEMPLATE="https://generativelanguage.googleapis.com/v1beta/models/\${MODEL}:generateContent" # URL template for generateContent
DEFAULT_MODEL="gemini-2.0-flash-lite" # Default model for query mode
PAGE_SIZE=100       # Maximize page size to reduce list calls
DELETE_DELAY=0.5   # Increased seconds to wait between delete calls
VERBOSE=0          # Default to non-verbose output (0=false, 1=true)
DEFAULT_MIME_TYPE="application/octet-stream" # Fallback MIME type for uploads
VERIFY_DELAYS=(5 10 20 60) # Delays (in seconds) for upload verification retry loop

# --- Runtime Variables ---
key_file_arg=""     # Store path from --keyfile argument
API_KEY=""          # Final API Key used for requests
files_to_list_args=()   # Array to hold specific files requested for listing
files_to_delete_args=() # Array to hold specific files requested for deletion
files_to_upload_args=() # Array to hold file paths for upload
file_to_query=""    # Store file ID/URI for --query argument (set during parsing)
query_file_path=""  # Store path to query text file
model_name=""       # Store model name for query
accumulator_json="" # Global variable to store fetched file list JSON

# --- Helper Function: Show Usage ---
usage() {
  grep '^# Usage:' -A 2 "$0" | cut -c 3-
  echo # Add blank line
  grep '^# Action Modes & Arguments:' -A 9 "$0" | cut -c 3-
  echo # Add blank line
  grep '^# Other Options:' -A 6 "$0" | cut -c 3-
  echo # Add blank line
  grep '^# API Key:' -A 3 "$0" | cut -c 3-
  echo # Add blank line
  grep '^# File API Limits:' -A 1 "$0" | cut -c 3-
  exit 1
}

# --- Function: Determine API Key ---
# Sets the global API_KEY variable. Returns 0 on success, 1 on error.
determine_api_key() {
    if [[ -n "$key_file_arg" ]]; then
        if [[ ! -f "$key_file_arg" ]]; then echo "Error: Keyfile not found: $key_file_arg" >&2; return 1; fi
        API_KEY=$(tr -d '[:space:]' < "$key_file_arg")
        if [[ -z "$API_KEY" ]]; then echo "Error: Keyfile is empty: $key_file_arg" >&2; return 1; fi
        if [[ "$VERBOSE" -eq 1 ]]; then echo "Using API key from file: $key_file_arg" >&2; fi
    elif [[ -v "${API_KEY_ENV_VAR}" && -n "${!API_KEY_ENV_VAR}" ]]; then
        API_KEY=$(printf '%s' "${!API_KEY_ENV_VAR}" | tr -d '[:space:]')
        if [[ "$VERBOSE" -eq 1 ]]; then echo "Using API key from env var: $API_KEY_ENV_VAR" >&2; fi
    else
        echo "Error: API Key not found. Use --keyfile or set ${API_KEY_ENV_VAR}." >&2; return 1; fi
    if [[ -z "$API_KEY" ]]; then echo "Error: API Key is empty." >&2; return 1; fi
    return 0
}

# --- Function: Fetch All Files List ---
# Populates the global 'accumulator_json' variable. Returns 0 on success, 1 on error.
fetch_all_files() {
    if [[ "$VERBOSE" -eq 1 ]]; then echo "Fetching file list from API..." >&2; fi
    local page_token="" fetch_status=0 request_url response curl_exit_code jq_exit_code next_page_token new_accumulator
    accumulator_json=$(jq -n '{files: []}')
    while true; do
        request_url="${LIST_BASE_URL}?key=${API_KEY}&pageSize=${PAGE_SIZE}"
        if [[ -n "$page_token" ]]; then request_url="${request_url}&pageToken=${page_token}"; fi
        response=$(curl -sfS --connect-timeout 15 --max-time 60 "${request_url}")
        curl_exit_code=$?
        if [[ $curl_exit_code -ne 0 ]]; then echo "Error: curl failed (code $curl_exit_code) fetching list." >&2; echo "URL: ${request_url%key=*}key=***" >&2; fetch_status=1; break; fi
        if ! echo "$response" | jq -e . > /dev/null 2>&1; then echo "Error: Invalid JSON response fetching list." >&2; echo "$response" >&2; fetch_status=1; break; fi
        new_accumulator=$(jq --argjson current_response "$response" '.files += ($current_response.files // [])' <<< "$accumulator_json"); jq_exit_code=$?
        if [[ $jq_exit_code -ne 0 ]]; then echo "Error: jq failed (code $jq_exit_code) merging files." >&2; fetch_status=1; break; fi
        accumulator_json="$new_accumulator"
        next_page_token=$(echo "$response" | jq -r '.nextPageToken // empty')
        if [[ -z "$next_page_token" ]]; then break; else page_token="$next_page_token"; sleep 0.1; fi
    done
    if [[ "$fetch_status" -eq 0 && "$VERBOSE" -eq 1 ]]; then echo "File list fetched successfully." >&2; fi
    return $fetch_status
}

# --- Function: Get Single File Status ---
# Arg $1: file_name (e.g., files/xxx)
# Outputs status string ("ACTIVE", "PROCESSING", "FAILED", "ERROR: reason") to stdout
# Returns 0 if status determined, 1 on curl/API error or missing state
get_file_status() {
    local file_name="$1" metadata_url status curl_exit_code metadata_response state error_details
    metadata_url="${API_ROOT_URL}/${file_name}?key=${API_KEY}"
    metadata_response=$(curl -sfS --connect-timeout 10 --max-time 30 "$metadata_url"); curl_exit_code=$?
    if [[ $curl_exit_code -ne 0 ]]; then error_details=$(echo "$metadata_response" | jq -r '.error.message // empty'); if [[ -n "$error_details" ]]; then echo "ERROR: Curl Error ($curl_exit_code), API Message: $error_details"; else echo "ERROR: Curl Error ($curl_exit_code)"; fi; return 1; fi
    error_details=$(echo "$metadata_response" | jq -r '.error.message // empty'); if [[ -n "$error_details" ]]; then echo "ERROR: API Error: $error_details"; return 1; fi
    state=$(echo "$metadata_response" | jq -r '.state // empty')
    if [[ -n "$state" ]]; then echo "$state"; return 0; else echo "ERROR: State field missing in metadata"; if [[ "$VERBOSE" -eq 1 ]]; then echo "  Response for $file_name: $metadata_response" >&2; fi; return 1; fi
}

# --- Function: Perform Deletions ---
# Reads file list from global 'files_to_process' array. Returns 0 if all succeed, 1 if any errors.
perform_deletions() {
    # Requires global files_to_process array to be set
    if [[ "$VERBOSE" -eq 1 ]]; then echo "Starting deletion..." >&2; fi
    local deleted_count=0 error_count=0 total_count=${#files_to_process[@]} i file_name progress DELETE_URL DEL_RESPONSE DEL_CURL_EXIT_CODE error_details
    for i in "${!files_to_process[@]}"; do
        file_name="${files_to_process[$i]}"; progress=$((i + 1))
        if [[ "$VERBOSE" -eq 1 ]]; then echo -n "Deleting ${file_name} (${progress}/${total_count})... " >&2; fi
        DELETE_URL="${API_ROOT_URL}/${file_name}?key=${API_KEY}"; DEL_RESPONSE=$(curl -sfS --connect-timeout 10 --max-time 30 -X DELETE "${DELETE_URL}"); DEL_CURL_EXIT_CODE=$?
        if [[ $DEL_CURL_EXIT_CODE -eq 0 ]]; then if [[ -z "$DEL_RESPONSE" ]] || [[ "$DEL_RESPONSE" == "{}" ]]; then if [[ "$VERBOSE" -eq 1 ]]; then echo "OK" >&2; fi; ((deleted_count++)); else if [[ "$VERBOSE" -ne 1 ]]; then echo; fi; echo "Warning: Delete OK for ${file_name} but resp: ${DEL_RESPONSE}" >&2; ((deleted_count++)); fi
        else if [[ "$VERBOSE" -ne 1 ]]; then echo; fi; echo "Error deleting ${file_name} (curl code ${DEL_CURL_EXIT_CODE})" >&2; error_details=$(echo "$DEL_RESPONSE" | jq -r '.error | "\(.code // "?") \(.status // "?"): \(.message // "?")" ' 2>/dev/null); if [[ -n "$error_details" && "$error_details" != "? ?: ?" ]]; then echo "  API Error: ${error_details}" >&2; elif [[ -n "$DEL_RESPONSE" ]]; then echo "  Response: ${DEL_RESPONSE}" >&2; fi; ((error_count++)); fi
        sleep ${DELETE_DELAY} # Use increased delay
    done
    echo "-----------------------------------------" >&2; echo "Deletion complete."; echo "Successfully deleted: ${deleted_count}"; echo "Errors encountered: ${error_count}" >&2; echo "-----------------------------------------" >&2
    if [[ $error_count -gt 0 ]]; then return 1; else return 0; fi
}

# --- Function: Verify Uploads ---
# Args: List of file names (files/xxx) that were successfully initiated.
# Prints verified names to stdout. Returns 0 if all verified, 1 if any failed/timed out.
verify_uploads() {
    local -a names_to_verify=("$@"); local overall_verification_status=0
    if [[ ${#names_to_verify[@]} -eq 0 ]]; then return 0; fi
    if [[ "$VERBOSE" -eq 1 ]]; then echo "--- Starting Verification Phase for ${#names_to_verify[@]} files ---" >&2; fi
    local -A verification_status; local -a successful_verification=() failed_verification=() # Declared Local
    local pending_count=${#names_to_verify[@]} file_name delay attempt status_output get_status_ret final_status
    for name in "${names_to_verify[@]}"; do verification_status["$name"]="pending"; done
    attempt=0
    for delay in "${VERIFY_DELAYS[@]}"; do
        ((attempt++)); if [[ $pending_count -eq 0 ]]; then break; fi
        if [[ $attempt -gt 1 ]]; then if [[ "$VERBOSE" -eq 1 ]]; then echo "Waiting ${delay}s before check #${attempt} for ${pending_count} pending..." >&2; fi; sleep "$delay";
        elif [[ "$VERBOSE" -eq 1 ]]; then echo "Initial check (attempt #${attempt}) for ${pending_count} pending..." >&2; fi
        local -a current_pending_keys=("${!verification_status[@]}")
        for file_name in "${current_pending_keys[@]}"; do
            [[ "${verification_status["$file_name"]}" != "pending"* ]] && continue
            if [[ "$VERBOSE" -eq 1 ]]; then echo -n "  Check #${attempt} for ${file_name}... " >&2; fi
            status_output=$(get_file_status "$file_name"); get_status_ret=$?
            if [[ $get_status_ret -ne 0 || "$status_output" == ERROR:* ]]; then if [[ "$VERBOSE" -eq 1 ]]; then echo "Error Status" >&2; fi; verification_status["$file_name"]="error:${status_output#ERROR: }"; ((pending_count--));
            elif [[ "$status_output" == "ACTIVE" ]]; then if [[ "$VERBOSE" -eq 1 ]]; then echo "ACTIVE" >&2; fi; verification_status["$file_name"]="active"; ((pending_count--));
            elif [[ "$status_output" == "FAILED" ]]; then if [[ "$VERBOSE" -eq 1 ]]; then echo "FAILED (API)" >&2; fi; verification_status["$file_name"]="failed"; ((pending_count--));
            else if [[ "$VERBOSE" -eq 1 ]]; then echo "Pending ($status_output)" >&2; fi; verification_status["$file_name"]="pending:$status_output"; fi
        done
    done
    if [[ "$VERBOSE" -eq 1 ]]; then echo "--- Verification Phase Complete ---" >&2; fi
    echo "-----------------------------------------" >&2; echo "Verification Summary:" >&2
    for file_name in "${!verification_status[@]}"; do
        final_status="${verification_status["$file_name"]}"
        if [[ "$VERBOSE" -eq 1 ]]; then echo "DEBUG verify_uploads: Final categorization for $file_name -> $final_status" >&2; fi # Added Debug
        if [[ "$final_status" == "active" ]]; then successful_verification+=("$file_name");
        elif [[ "$final_status" == "pending"* ]]; then failed_verification+=("$file_name (Timed Out - Last: ${final_status#pending:})"); overall_verification_status=1;
        else failed_verification+=("$file_name (${final_status})"); overall_verification_status=1; fi
    done
    if [[ ${#failed_verification[@]} -gt 0 ]]; then echo " Files that failed verification:" >&2; printf "  - %s\n" "${failed_verification[@]}" >&2; fi
    if [[ ${#successful_verification[@]} -gt 0 ]]; then
        if [[ "$VERBOSE" -eq 1 ]]; then echo "DEBUG verify_uploads: successful_verification size = ${#successful_verification[@]}" >&2; declare -p successful_verification >&2; fi # Added Debug
        echo " Files successfully verified as ACTIVE:" >&2; printf "  - %s\n" "${successful_verification[@]}" >&2
        printf "%s\n" "${successful_verification[@]}" # Print names to stdout
    else echo " No files were successfully verified." >&2; fi
    echo "-----------------------------------------" >&2
    return $overall_verification_status
}

# --- Argument Parsing ---
declare -a remaining_args=()
while [[ $# -gt 0 ]]; do
  current_arg="$1"; if [[ "$current_arg" == -* ]]; then
      case "$current_arg" in
        --list) if [[ -n "$MODE" ]]; then echo "E: Modes conflict (--list vs --${MODE})" >&2; usage; fi; MODE="list"; shift ;;
        --delete) if [[ -n "$MODE" ]]; then echo "E: Modes conflict (--delete vs --${MODE})" >&2; usage; fi; MODE="delete"; shift ;;
        --upload) if [[ -n "$MODE" ]]; then echo "E: Modes conflict (--upload vs --${MODE})" >&2; usage; fi; MODE="upload"; shift ;;
        --query) if [[ -n "$MODE" ]]; then echo "E: Modes conflict (--query vs --${MODE})" >&2; usage; fi; MODE="query"; if [[ -n "$2" && "$2" != -* ]]; then file_to_query="$2"; shift 2; else echo "E: --query needs file ID/URI." >&2; usage; fi ;;
        --query-file) if [[ -n "$2" && "$2" != -* ]]; then query_file_path="$2"; shift 2; else echo "E: --query-file needs path." >&2; usage; fi ;;
        --model) if [[ -n "$2" && "$2" != -* ]]; then model_name="$2"; shift 2; else echo "E: --model needs name." >&2; usage; fi ;;
        --keyfile) if [[ -n "$2" && "$2" != -* ]]; then key_file_arg="$2"; shift 2; else echo "E: --keyfile needs path." >&2; usage; fi ;;
        -v|--verbose) VERBOSE=1; shift; ;; -h|--help) usage; ;; *) echo "E: Unknown option '$1'" >&2; usage; ;;
      esac
  else remaining_args+=("$1"); shift; fi
done

# --- Default Action: Show Help ---
if [[ -z "$MODE" ]]; then echo "Error: No action mode specified." >&2; usage; fi

# --- Assign remaining arguments based on MODE ---
case "$MODE" in list) files_to_list_args=("${remaining_args[@]}");; delete) files_to_delete_args=("${remaining_args[@]}");; upload) files_to_upload_args=("${remaining_args[@]}");; query) if [[ ${#remaining_args[@]} -gt 0 ]]; then echo "Warning: Extra positional args ignored for --query." >&2; fi;; esac

# --- Normalize collected arguments that are file IDs ---
declare -a temp_args
if [[ "$MODE" == "list" ]]; then temp_args=(); for id_arg in "${files_to_list_args[@]}"; do if [[ "$id_arg" == files/* || "$id_arg" =~ ^[a-zA-Z0-9._-]+$ ]]; then if [[ "$id_arg" != files/* ]]; then id_arg="files/$id_arg"; fi; temp_args+=("$id_arg"); else echo "Warn: Skip ID '$id_arg' for --list." >&2; fi; done; files_to_list_args=("${temp_args[@]}"); unset temp_args;
elif [[ "$MODE" == "delete" ]]; then temp_args=(); for id_arg in "${files_to_delete_args[@]}"; do if [[ "$id_arg" == files/* || "$id_arg" =~ ^[a-zA-Z0-9._-]+$ ]]; then if [[ "$id_arg" != files/* ]]; then id_arg="files/$id_arg"; fi; temp_args+=("$id_arg"); else echo "Warn: Skip ID '$id_arg' for --delete." >&2; fi; done; files_to_delete_args=("${temp_args[@]}"); unset temp_args; fi
if [[ "$MODE" == "query" && -n "$file_to_query" ]]; then if [[ "$file_to_query" != files/* && "$file_to_query" != https://*/* && "$file_to_query" =~ ^[a-zA-Z0-9._-]+$ ]]; then file_to_query="files/$file_to_query"; if [[ "$VERBOSE" -eq 1 ]]; then echo "Normalized query ID to: $file_to_query" >&2; fi; elif [[ "$file_to_query" != files/* && "$file_to_query" != https://*/* ]]; then echo "E: Invalid format for --query: $file_to_query" >&2; usage; fi; fi

# --- Validate Mode-Specific Mandatory Arguments ---
if [[ "$MODE" == "query" && -z "$query_file_path" ]]; then echo "Error: --query mode requires --query-file." >&2; usage; fi
if [[ "$MODE" == "upload" && ${#files_to_upload_args[@]} -eq 0 ]]; then echo "Error: --upload requires at least one filepath argument." >&2; usage; fi
if [[ "$MODE" == "query" && -z "$file_to_query" ]]; then echo "Error: --query requires a file identifier argument." >&2; usage; fi
if [[ "$MODE" != "query" && -n "$query_file_path" ]]; then echo "Error: --query-file only valid with --query." >&2; usage; fi
if [[ "$MODE" != "query" && -n "$model_name" ]]; then echo "Error: --model only valid with --query." >&2; usage; fi

# --- Determine API Key (Main Script) ---
determine_api_key; key_exit_status=$?
if [[ $key_exit_status -ne 0 ]]; then exit $key_exit_status; fi

# --- Mode Execution (Main Script) ---
exit_status=0 # Overall exit status for the script

case "$MODE" in
  list)
    if [[ "$VERBOSE" -eq 1 ]]; then echo "Mode: List" >&2; fi
    fetch_all_files; fetch_exit_status=$?
    if [[ $fetch_exit_status -ne 0 ]]; then echo "Aborting list due to fetch errors." >&2; exit $fetch_exit_status; fi

    if [[ ${#files_to_list_args[@]} -gt 0 ]]; then
        # --- Specific Files Listing ---
         if [[ "$VERBOSE" -eq 1 ]]; then echo "Filtering for specific files specified..." >&2; fi
        mapfile -t requested_unique < <(printf "%s\n" "${files_to_list_args[@]}" | sort -u); if [[ ${#requested_unique[@]} -eq 0 ]]; then echo "Error: No valid file IDs provided." >&2; exit 1; fi
        requested_names_json=$(printf "%s\n" "${requested_unique[@]}" | jq -Rsc 'split("\n") | map(select(length > 0))'); if [[ $? -ne 0 || -z "$requested_names_json" ]]; then echo "Error: Failed creating JSON array of names." >&2; exit 1; fi
        jq_filter_script=' .files | map(select(.name as $n | $requested_names | index($n))) '; filtered_files_json=$(echo "$accumulator_json" | jq --argjson requested_names "$requested_names_json" "$jq_filter_script"); if [[ $? -ne 0 ]]; then echo "Error: jq filter operation failed." >&2; exit 1; fi
        missing_files=(); declare -A found_map
        found_names_output=$(echo "$filtered_files_json" | jq -r '.[]?.name // empty'); if [[ $? -ne 0 ]]; then echo "Error: jq failed extracting found names." >&2; exit 1; fi
        while IFS= read -r line; do [[ -n "$line" ]] && found_map["$line"]=1; done <<< "$found_names_output"
        for req_id in "${requested_unique[@]}"; do if ! [[ -v found_map["$req_id"] ]]; then missing_files+=("$req_id"); fi; done
        if [[ ${#missing_files[@]} -gt 0 ]]; then echo "Warning: Requested file IDs not found:" >&2; printf " -- %s\n" "${missing_files[@]}" >&2; fi
        found_files_count=$(echo "$filtered_files_json" | jq 'length'); if [[ $? -ne 0 ]]; then echo "Error: jq failed counting files." >&2; exit 1; fi
        if [[ "$VERBOSE" -eq 1 ]]; then echo "Found $found_files_count matching files out of ${#requested_unique[@]} unique IDs requested." >&2; fi
        output_json=$(jq -n --argjson f "$filtered_files_json" '{files: $f}'); if [[ $? -ne 0 ]]; then echo "Error: jq failed constructing output JSON." >&2; exit 1; fi
        echo "$output_json"
    else
        # --- List All Files ---
        if [[ "$VERBOSE" -eq 1 ]]; then echo "Listing all files..." >&2; fi
        echo "$accumulator_json"
    fi
    exit_status=0 # Explicitly success if reached
    ;;

  delete)
    if [[ "$VERBOSE" -eq 1 ]]; then echo "Mode: Delete" >&2; fi
    fetch_all_files; fetch_exit_status=$?
    if [[ $fetch_exit_status -ne 0 ]]; then echo "Aborting delete due to list errors." >&2; exit $fetch_exit_status; fi
    declare -a files_to_process # Make local to this block? No, perform_deletions uses global currently.
    files_to_process=(); file_count=0; all_api_files=(); invalid_files_requested=()
    while IFS= read -r line; do [[ -n "$line" ]] && all_api_files+=("$line"); done < <(echo "$accumulator_json" | jq -r '.files[].name // empty')
    if [[ ${#files_to_delete_args[@]} -gt 0 ]]; then
        if [[ "$VERBOSE" -eq 1 ]]; then echo "(Specific Files Requested)" >&2; fi
        validated_files_to_delete=(); declare -A available_files_map
        for api_file in "${all_api_files[@]}"; do available_files_map["$api_file"]=1; done
        mapfile -t unique_requested_files < <(printf "%s\n" "${files_to_delete_args[@]}" | sort -u)
        for requested_file in "${unique_requested_files[@]}"; do if [[ -v available_files_map["$requested_file"] ]]; then validated_files_to_delete+=("$requested_file"); else invalid_files_requested+=("$requested_file"); fi; done
        if [[ ${#invalid_files_requested[@]} -gt 0 ]]; then echo "Error: Requested file IDs not found:" >&2; printf " - %s\n" "${invalid_files_requested[@]}" >&2; fi
        files_to_process=("${validated_files_to_delete[@]}"); file_count=${#files_to_process[@]}
        if [[ $file_count -eq 0 ]]; then echo "No valid files specified or found." >&2; exit 0; fi
    else
        if [[ "$VERBOSE" -eq 1 ]]; then echo "(All Files)" >&2; fi
        files_to_process=("${all_api_files[@]}"); file_count=${#files_to_process[@]}
        if [[ $file_count -eq 0 ]]; then if [[ "$VERBOSE" -eq 1 ]]; then echo "No files found to delete." >&2; fi; exit 0; fi
    fi
    echo "-----------------------------------------" >&2; echo "Targeting ${file_count} files for deletion." >&2
    if [[ "$VERBOSE" -eq 1 ]]; then echo "Files to be deleted:" >&2; printf " - %s\n" "${files_to_process[@]}" >&2; fi
    echo "-----------------------------------------" >&2; read -p "Proceed with deletion? (Type 'yes' to confirm): " confirm
    confirm_lc=$(echo "$confirm" | tr '[:upper:]' '[:lower:]'); if [[ "$confirm_lc" != "yes" && "$confirm_lc" != "y" ]]; then echo "Deletion aborted." >&2; exit 0; fi # Accept y/yes
    perform_deletions
    exit_status=$?
    echo "DEBUG: perform_deletions returned status: $exit_status" >&2 # Added Debug
    ;;

  upload)
    if [[ "$VERBOSE" -eq 1 ]]; then echo "Mode: Upload" >&2; fi
    uploaded_file_names=(); failed_initial_uploads=(); initial_upload_exit_status=0
    if [[ "$VERBOSE" -eq 1 ]]; then echo "--- Starting Initial Upload Phase ---" >&2; fi
    for file_to_upload_path in "${files_to_upload_args[@]}"; do
        if [[ "$VERBOSE" -eq 1 ]]; then echo "Processing file: $file_to_upload_path" >&2; fi
        if [[ ! -f "$file_to_upload_path" ]]; then echo "Error: File not found: $file_to_upload_path" >&2; failed_initial_uploads+=("$file_to_upload_path (Not Found)"); initial_upload_exit_status=1; continue; fi
        display_name=$(basename "$file_to_upload_path"); mime_type="$DEFAULT_MIME_TYPE"
        if command -v file > /dev/null; then detected_mime=$(file --brief --mime-type "$file_to_upload_path"); if [[ $? -eq 0 && -n "$detected_mime" && "$detected_mime" == */* ]]; then mime_type="$detected_mime"; elif [[ "$VERBOSE" -eq 1 ]]; then echo "Warn: 'file' failed/gave odd output for '$file_to_upload_path'. Using default: $mime_type" >&2; fi; elif [[ "$VERBOSE" -eq 1 ]]; then echo "Warn: 'file' cmd not found. Using default: $mime_type" >&2; fi
        metadata_json=$(jq -nc --arg dn "$display_name" '{"file": {"displayName": $dn}}'); if [[ $? -ne 0 || -z "$metadata_json" ]]; then echo "Error: Metadata fail for $file_to_upload_path." >&2; failed_initial_uploads+=("$file_to_upload_path (Meta Error)"); initial_upload_exit_status=1; continue; fi
        if [[ "$VERBOSE" -eq 1 ]]; then echo -n "  Uploading $file_to_upload_path (Display: $display_name, Type: $mime_type)... " >&2; fi
        upload_response=$(curl -sfS --connect-timeout 15 --max-time 600 -X POST "${UPLOAD_BASE_URL}?key=${API_KEY}" -H "X-Goog-Upload-Protocol: multipart" -F "metadata=${metadata_json};type=application/json" -F "file=@${file_to_upload_path};type=${mime_type}"); curl_exit_code=$?
        if [[ $curl_exit_code -eq 0 ]]; then
            uploaded_file_name=$(echo "$upload_response" | jq -r '.file.name // empty'); if [[ $? -ne 0 ]]; then if [[ "$VERBOSE" -eq 1 ]]; then echo "FAILED (jq parse error)"; fi; failed_initial_uploads+=("$file_to_upload_path (Response Parse Error)"); initial_upload_exit_status=1; continue; fi
            if [[ -n "$uploaded_file_name" ]]; then if [[ "$VERBOSE" -eq 1 ]]; then echo "OK ($uploaded_file_name)" >&2; fi; uploaded_file_names+=("$uploaded_file_name"); else if [[ "$VERBOSE" -eq 1 ]]; then echo "FAILED (API Error)" >&2; fi; echo "Error: Upload OK for $file_to_upload_path but API response error." >&2; error_details=$(echo "$upload_response" | jq -r '.error.message // empty'); if [[ -n "$error_details" ]]; then echo "  API Error: ${error_details}" >&2; else echo "  Resp: ${upload_response}" >&2; fi; failed_initial_uploads+=("$file_to_upload_path (API Error)"); initial_upload_exit_status=1; fi
        else if [[ "$VERBOSE" -eq 1 ]]; then echo "FAILED (Curl Error $curl_exit_code)" >&2; fi; echo "Error: Upload failed for $file_to_upload_path (curl code ${curl_exit_code})." >&2; error_details=$(echo "$upload_response" | jq -r '.error.message // empty'); if [[ -n "$error_details" ]]; then echo "  API Error: ${error_details}" >&2; elif [[ -n "$upload_response" ]]; then echo "  Resp: ${upload_response}" >&2; fi; failed_initial_uploads+=("$file_to_upload_path (Curl Error $curl_exit_code)"); initial_upload_exit_status=1; fi
    done
    if [[ "$VERBOSE" -eq 1 ]]; then echo "--- Initial Upload Phase Complete ---" >&2; fi
    verify_uploads "${uploaded_file_names[@]}"; verify_exit_status=$?
    if [[ $initial_upload_exit_status -ne 0 || $verify_exit_status -ne 0 ]]; then exit_status=1; else exit_status=0; fi
    ;;

  query)
    if [[ "$VERBOSE" -eq 1 ]]; then echo "Mode: Query" >&2; fi
    query_model="${model_name:-$DEFAULT_MODEL}"; if [[ "$VERBOSE" -eq 1 ]]; then echo "Using model: $query_model" >&2; fi
    query_file_name="$file_to_query"; if [[ "$VERBOSE" -eq 1 ]]; then echo "Query target file name: $query_file_name" >&2; fi
    if [[ "$VERBOSE" -eq 1 ]]; then echo "Fetching metadata for $query_file_name..." >&2; fi
    metadata_url="${API_ROOT_URL}/${query_file_name}?key=${API_KEY}"; metadata_response=$(curl -sfS --connect-timeout 10 --max-time 30 "$metadata_url"); curl_exit_code=$?
    if [[ $curl_exit_code -ne 0 ]]; then echo "Error: Failed fetch metadata (curl code $curl_exit_code)." >&2; meta_error_details=$(echo "$metadata_response" | jq -r '.error.message // empty'); if [[ -n "$meta_error_details" ]]; then echo "  API Error: ${meta_error_details}" >&2; elif [[ -n "$metadata_response" ]]; then echo "  Response: ${metadata_response}" >&2; fi; echo "URL: ${metadata_url%key=*}key=***" >&2; exit 1; fi
    query_file_mime_type=$(echo "$metadata_response" | jq -r '.mimeType // empty'); query_file_uri=$(echo "$metadata_response" | jq -r '.uri // empty')
    if [[ $? -ne 0 || -z "$query_file_mime_type" || -z "$query_file_uri" ]]; then echo "Error: Missing mime/uri in metadata (or jq error)." >&2; echo "Response: $metadata_response" >&2; exit 1; fi
    if [[ "$VERBOSE" -eq 1 ]]; then echo "Found MIME: $query_file_mime_type, URI: $query_file_uri" >&2; fi
    if [[ ! -f "$query_file_path" ]]; then echo "Error: Query file not found: $query_file_path" >&2; exit 1; fi
    query_text=$(<"$query_file_path"); if [[ -z "$query_text" ]]; then echo "Error: Query file empty: $query_file_path" >&2; exit 1; fi
    if [[ "$VERBOSE" -eq 1 ]]; then echo "Read query from: $query_file_path" >&2; fi
    payload=$(jq -nc --arg qry "$query_text" --arg mime "$query_file_mime_type" --arg uri "$query_file_uri" '{ "contents": [ { "parts":[ { "text": $qry }, { "fileData": { "mimeType": $mime, "fileUri": $uri } } ] } ], "generationConfig": { "temperature": 0.5, "topP": 0.95, "topK": 40, "maxOutputTokens": 8192 } }'); jq_exit_code=$?
    if [[ $jq_exit_code -ne 0 || -z "$payload" ]]; then echo "Error: Failed to construct JSON payload." >&2; exit 1; fi
    if [[ "$VERBOSE" -eq 1 ]]; then echo "Constructed query payload." >&2; fi
    generate_url=$(echo "$GENERATE_CONTENT_URL_TEMPLATE" | sed "s/\${MODEL}/${query_model}/"); if [[ $? -ne 0 ]]; then echo "Error substituting model in URL." >&2; exit 1; fi
    if [[ "$VERBOSE" -eq 1 ]]; then echo "Sending query to model ${query_model}..." >&2; fi
    QUERY_RESPONSE=$(curl -sfS --connect-timeout 15 --max-time 600 -X POST "${generate_url}?key=${API_KEY}" -H 'Content-Type: application/json' -d "$payload"); CURL_EXIT_CODE=$?
    if [[ $CURL_EXIT_CODE -eq 0 ]]; then
        api_error_details=$(echo "$QUERY_RESPONSE" | jq -r '.error | "\(.code // "?") \(.status // "?"): \(.message // "?")" ' 2>/dev/null); jq_exit_code=$?
        if [[ $jq_exit_code -ne 0 ]]; then echo "Warn: Failed to parse potential API error from response." >&2; fi
        if [[ $jq_exit_code -eq 0 && -n "$api_error_details" && "$api_error_details" != "? ?: ?" ]]; then echo "Error: API error." >&2; echo "  API Error: ${api_error_details}" >&2; exit 1; fi
        block_reason=$(echo "$QUERY_RESPONSE" | jq -r '.promptFeedback.blockReason // empty'); if [[ $? -ne 0 ]]; then echo "Warn: Failed to parse promptFeedback." >&2; block_reason=""; fi
        safety_finish_reason=$(echo "$QUERY_RESPONSE" | jq -r '.candidates[0].finishReason // empty'); if [[ $? -ne 0 ]]; then echo "Warn: Failed to parse finishReason." >&2; safety_finish_reason=""; fi
        if [[ -n "$block_reason" ]]; then echo "Error: Query blocked. Reason: $block_reason" >&2; if [[ "$VERBOSE" -eq 1 ]]; then echo "$QUERY_RESPONSE" >&2; fi; exit 1;
        elif [[ "$safety_finish_reason" == "SAFETY" ]]; then echo "Error: Query response flagged for safety." >&2; if [[ "$VERBOSE" -eq 1 ]]; then echo "$QUERY_RESPONSE" >&2; fi; exit 1; fi
        generated_text=$(echo "$QUERY_RESPONSE" | jq -r '.candidates[0].content.parts[0].text // empty'); if [[ $? -ne 0 ]]; then echo "Error: Failed parsing generated text." >&2; generated_text=""; exit_status=1; fi
        if [[ -n "$generated_text" ]]; then echo "$generated_text"; exit_status=0; else echo "Error: Query OK but no text content found." >&2; if [[ "$VERBOSE" -eq 1 ]]; then echo "$QUERY_RESPONSE" >&2; fi; exit_status=1; fi
    else echo "Error: Query failed (curl code ${CURL_EXIT_CODE})." >&2; api_error_details=$(echo "$QUERY_RESPONSE" | jq -r '.error | "\(.code // "?") \(.status // "?"): \(.message // "?")" ' 2>/dev/null); if [[ -n "$api_error_details" && "$api_error_details" != "? ?: ?" ]]; then echo "  API Error: ${api_error_details}" >&2; elif [[ -n "$QUERY_RESPONSE" ]]; then echo "  Response: ${QUERY_RESPONSE}" >&2; fi; exit_status=1; fi
    ;;

  *) echo "Error: Unknown mode '$MODE'." >&2; usage ;;
esac

exit $exit_status
