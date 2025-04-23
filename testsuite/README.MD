# Test Suite Script (testsuite.sh)

This script automates the process of downloading a PDF, splitting it into individual pages, and optionally optimizing the resulting files. It then runs a suite of tests on the files including uploading, listing, querying and deleting.

## Features

* Downloads a test PDF file (defaults to `scenescharacters00londuoft.pdf` from archive.org).
* Splits the downloaded PDF into a specified number of single-page PDF files (defaults to 20 pages named `test_01.pdf` to `test_20.pdf`).
* Optionally uses Ghostscript (`gs`) if installed to reduce the file size of the split PDFs, saving bandwidth and disk space.
* Runs a series of testsuite tests

## Usage

Follow these steps to run the script:

1.  Ensure the script has execute permissions:

    ```bash
    chmod +x testsuite.sh
    ```
2.  Run the script from your terminal:

    ```bash
    ./testsuite.sh
    ```

## Configuration

You can customize the script's behavior by modifying variables directly within the `testsuite.sh` file. Here are the common configuration points:

### Changing the Source PDF

To use a different PDF file as the source, modify the `PDF_DOWNLOAD_URL` variable:

    ```bash
    PDF_DOWNLOAD_URL="[https://archive.org/download/your_different_pdf_file.pdf](https://archive.org/download/your_different_pdf_file.pdf)"
    ```

### Updating the Test Query (for `test_01.pdf`)

The script includes variables for a basic test query performed on the first generated page (`test_01.pdf`). If you change the source PDF, you will likely need to update these variables to match the new content:

    ```bash
    # The question to ask about the content of test_01.pdf
    QUERY_TEXT="What is something on the page?"

    # A substring that MUST be present in the expected answer
    EXPECTED_ANSWER_SUBSTRING="the expected response"
    ```

### Adjusting PDF Splitting Parameters

The script relies on an external command (`"$SPLIT_SCRIPT"`) for splitting the PDF. You can control which pages are extracted from the source PDF and how they are grouped.

* Locate the line executing the split command. It typically follows this pattern:

    ```bash
    "$SPLIT_SCRIPT" "$SPLIT_BASE_NAME" 1 20 39
    ```
* The arguments usually represent:
    * `"$SPLIT_BASE_NAME"`: Base name for output files (e.g., `test_`).
    * `1`: Number of pages from the *source PDF* in the output file.
    * `20`: The page number in the *source PDF* where splitting starts (this page becomes `test_01.pdf`).
    * `39`: The page number in the *source PDF* where splitting ends (inclusive).
* To change the range, modify the numeric arguments. For example, to extract pages 50 through 59 (inclusive) as 10 separate files:

    ```bash
    "$SPLIT_SCRIPT" "$SPLIT_BASE_NAME" 1 50 59
    ```

### Changing the Expected Number of Generated Pages

After adjusting the splitting parameters, ensure the `EXPECTED_PDF_COUNT` variable accurately reflects the *total number* of PDF files the script should now generate:

    ```bash
    EXPECTED_PDF_COUNT=10 # Update this to the new total count
    ```

