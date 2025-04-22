#!/usr/bin/env bash

#
# Script: reducesize.sh
# Purpose: Reduce size of PDF files
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

# --- Configuration ---
# Set the desired Ghostscript optimization level.
# Options: /screen (lowest quality, smallest size), /ebook (better quality, 150dpi),
# /printer (300dpi), /prepress (high quality, color preservation, 300dpi)

PDF_SETTINGS="/screen"

# --- Script Logic ---

# 1. Check if Ghostscript is installed
if ! command -v gs &> /dev/null; then
    echo "Warning: Ghostscript (gs) not found in PATH. Skipping file-size reduction step."
    exit 1 # Exit with a non-zero status indicating an issue
fi

echo "Ghostscript found. Starting PDF optimization..."

# 2. Loop through files test_01.pdf to test_20.pdf
for i in $(seq 1 20); do
    # Format number with leading zero (e.g., 01, 02, ..., 20)
    num=$(printf "%02d" $i)
    file="test_${num}.pdf"
    
    # 3. Check if the specific input file exists
    if [ ! -f "$file" ]; then
        echo "Skipping '$file': File not found."
        continue 
    fi

    echo "Reducing size of '$file'..."

    # 4. Create a secure temporary file for the output
    temp_file=$(mktemp --suffix=.pdf)
    
    # Ensure temp file is removed if script exits unexpectedly (optional but good practice)
    trap 'rm -f "$temp_file"' EXIT # Uncomment if robust cleanup on any exit is needed

    # 5. Run Ghostscript to optimize the PDF into the temporary file
    gs -sDEVICE=pdfwrite \
       -dCompatibilityLevel=1.4 \
       -dPDFSETTINGS="$PDF_SETTINGS" \
       -dNOPAUSE \
       -dQUIET \
       -dBATCH \
       -sOutputFile="$temp_file" \
       "$file"
       
    # 6. Check if Ghostscript command was successful
    if [ $? -eq 0 ]; then
        # Success: Move the optimized temp file to replace the original file
        mv "$temp_file" "$file"
        if [ $? -ne 0 ]; then
             echo "ERROR: Failed to replace '$file' with optimized version (mv command failed)."
             # Attempt cleanup just in case mv left the temp file
             rm -f "$temp_file"
        fi
    else
        # Failure: Print error and remove the potentially incomplete temporary file
        echo "ERROR: Ghostscript failed to process '$file'. Original file kept."
        rm -f "$temp_file"
    fi
    
    # Disable the general exit trap for this specific temp file before the loop continues
    trap - EXIT # Uncomment if the trap above was uncommented

done

# Optional: Remove the trap cleanup action entirely if it was set
trap - EXIT # Uncomment if the trap above was uncommented

exit 0 # Exit successfully
