#!/usr/bin/env bash

#
# Script: splitpdf.sh
# Purpose: Split pages from a larger PDF into smaller PDFs based on a specified range
# Created: April 21, 2025
# Author: GreenC + Google Gemini Advanced 2.5 Pro
# Version: 1.1 (Added dependency check)
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

# --- Dependency Check ---
# Ensure qpdf command is available
if ! command -v qpdf &> /dev/null; then
    echo "Error: 'qpdf' command not found. Please install qpdf to use this script."
    exit 1
fi
# ------------------------

# --- Configuration ---
# Check for minimum number of arguments
if [ "$#" -lt 4 ]; then
    echo "Usage: $0 <input_base_name> <pages_per_chunk> <range_start_page> <range_end_page>"
    echo "  <input_base_name>: Base name of the PDF file (e.g., 'mydocument' for 'mydocument.pdf')"
    echo "  <pages_per_chunk>: Number of pages per output file"
    echo "  <range_start_page>: First page number of the range to extract"
    echo "  <range_end_page>: Last page number of the range to extract"
    echo ""
    echo "Example: $0 mydocument 10 20 40  # Extracts pages 20-40 from mydocument.pdf into 10-page chunks"
    exit 1
fi

input_base_name="${1}"     # Base name like 'mydocument' (without .pdf)
pages_per_file="${2}"      # Number of pages per output file (chunk size)
range_start="${3}"         # The first page number of the range to extract
range_end="${4}"           # The last page number of the range to extract

input_pdf="${input_base_name}.pdf"
output_prefix="${input_base_name}" # Prefix for output files
# ---------------------

# --- Input Validation ---
# Check if input file exists
if [ ! -f "$input_pdf" ]; then
    echo "Error: Input file '$input_pdf' not found."
    exit 1
fi

# Validate pages_per_file is a positive integer
if ! [[ "$pages_per_file" =~ ^[1-9][0-9]*$ ]]; then
    echo "Error: <pages_per_chunk> ('$pages_per_file') must be a positive integer."
    exit 1
fi

# Validate range_start is a positive integer
if ! [[ "$range_start" =~ ^[1-9][0-9]*$ ]]; then
    echo "Error: <range_start_page> ('$range_start') must be a positive integer."
    exit 1
fi

# Validate range_end is a positive integer
if ! [[ "$range_end" =~ ^[1-9][0-9]*$ ]]; then
    echo "Error: <range_end_page> ('$range_end') must be a positive integer."
    exit 1
fi

# Validate range_start is not greater than range_end
if [ "$range_start" -gt "$range_end" ]; then
    echo "Error: <range_start_page> ($range_start) cannot be greater than <range_end_page> ($range_end)."
    exit 1
fi

# --- Get Total Pages and Validate Range ---
total_pages=$(qpdf --show-npages "$input_pdf")
# Check qpdf exit status and if output is a valid number > 0
if [ $? -ne 0 ] || ! [[ "$total_pages" =~ ^[0-9]+$ ]] || [ "$total_pages" -eq 0 ]; then
    echo "Error: Could not get a valid page count from '$input_pdf'. Check if it's a valid PDF."
    exit 1
fi
echo "Total pages in '$input_pdf': $total_pages"

# Validate range against total pages
if [ "$range_start" -gt "$total_pages" ]; then
    echo "Error: <range_start_page> ($range_start) is greater than total pages ($total_pages)."
    exit 1
fi
if [ "$range_end" -gt "$total_pages" ]; then
    echo "Warning: <range_end_page> ($range_end) is greater than total pages ($total_pages)."
    echo "Adjusting range_end to $total_pages."
    range_end=$total_pages
    # Re-validate start <= end in case start was also > total_pages and end got adjusted below it
    if [ "$range_start" -gt "$range_end" ]; then
      echo "Error: Adjusted <range_end_page> ($range_end) is now less than <range_start_page> ($range_start). No pages to process."
      exit 1
    fi
fi
echo "Extracting page range: $range_start to $range_end"

# --- Calculations for Splitting ---
# Calculate number of pages in the specified range
pages_in_range=$(( range_end - range_start + 1 ))

# Calculate number of output files needed based on the range
num_files=$(( (pages_in_range + pages_per_file - 1) / pages_per_file ))
echo "Will create $num_files output file(s) from the specified range."

# --- Calculate padding width for output file number ---
# Determine the number of digits needed for the highest file number
if [ "$num_files" -lt 100 ]; then
    pad_width=2 # Use 2 digits for 1-99 files (e.g., 01, 99)
elif [ "$num_files" -lt 1000 ]; then
    pad_width=3 # Use 3 digits for 100-999 files (e.g., 001, 100, 999)
else
    # For 1000 files or more, use the actual number of digits in num_files
    pad_width=${#num_files} # Use 4 digits for 1000-9999, 5 for 10000+, etc.
fi
echo "Using padding width: $pad_width for output filenames."
# --- End padding calculation ---

# --- Loop and Split within the Range ---
current_page=$range_start # Start iterating from the beginning of the specified range
files_created=0
for (( i=1; i<=num_files; i++ )); do
    # Calculate end page for the current chunk
    chunk_end_page=$(( current_page + pages_per_file - 1 ))

    # Adjust chunk end page if it exceeds the specified range end
    if [ "$chunk_end_page" -gt "$range_end" ]; then
        chunk_end_page=$range_end
    fi

    # Format the sequential file number using the calculated padding width
    formatted_i=$(printf "%0${pad_width}d" "$i")

    # Construct the final output filename with the new format
    output_pdf="${output_prefix}_${formatted_i}.pdf"

    echo "Creating '$output_pdf' (from original pages $current_page-$chunk_end_page)..."

    # Use qpdf to extract the page range for this chunk
    # The '.' refers to the input file specified earlier in the command.
    # The '--' correctly separates options from positional arguments (filenames).
    qpdf "$input_pdf" --pages . "$current_page-$chunk_end_page" -- "$output_pdf"

    if [ $? -ne 0 ]; then
        echo "Error creating '$output_pdf'. Aborting."
        # Consider removing the potentially corrupt/incomplete output file
        # rm -f "$output_pdf"
        exit 1
    else
        files_created=$((files_created + 1))
    fi

    # Update current_page for the next iteration (start of the next chunk)
    current_page=$(( chunk_end_page + 1 ))

    # Safety break: ensure we don't somehow loop beyond the range end
    # This might be slightly redundant given the loop conditions and calculations,
    # but serves as an extra safeguard.
    if [ "$current_page" -gt "$range_end" ] && [ "$i" -lt "$num_files" ]; then
        echo "Warning: Loop logic unexpected exit condition reached after creating file $i."
        break
    fi
done

echo "Successfully created $files_created PDF file(s)."
exit 0
