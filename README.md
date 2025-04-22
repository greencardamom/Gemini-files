# CLI tool for Gemini Files API

**Version:** 1.0 (April 21, 2025)
**Author:** GreenC + Google Gemini Advanced 2.5 Pro

## Purpose

This repository contains a Bash script (`gemini-files.sh`) designed to interact with the Google Gemini File API and the Generative Language API. It allows one to:

* **Upload** files to the temporary Gemini File API storage.
* **List** files currently stored in the File API (all or specific).
* **Delete** files from the File API (all or specific).
* **Query** the content of an uploaded file with a specified Gemini generative model.

The script includes features like flexible API key handling (via file or environment variable), verbose output, and verification checks for uploads.

An extensive test suite (`testsuite.sh`) is included to verify core functionality.

**Note:** As of May 2025, the Gemini File API provides temporary storage (typically 48 hours) primarily for providing context to generative model calls. Files are limited in size (max 2GB per file) and total storage (max 20GB per project).

## Requirements

* **Shell:** Bash version 4.2 or later (uses associative arrays and `-v` test). Check with `bash --version`.
* **Utilities:**
    * `curl`: For making API HTTP requests.
    * `jq`: For parsing JSON responses from the API.
    * `git`: For cloning the repository.
    * `qpdf`: (Optional but recommended): Used by testsuite.sh
    * `file`: (Optional but recommended): Used by the `--upload` command to automatically detect MIME types. If not found, uploads will use `application/octet-stream`.
    * `gs`: (Optional): Ghostscript used by testsuite.sh
* **API Key:** A Google API Key obtained from Google AI Studio or Google Cloud Console. This key must be enabled for **both** the **Gemini API (Generative Language API)** and the **File API**. Ensure the key has sufficient permissions (e.g., read, write, list, delete for files; generate content for models). Check Google's documentation for specific IAM roles if using GCP keys.
* **API Quotas:** Be mindful of potential API usage costs and quotas associated with your Google account/project.

## Installation

1.  Clone the repository:

        git clone https://github.com/greencardamom/Gemini-files.git
        cd Gemini-files

2.  Make the scripts executable:

        chmod +x src/gemini-files.sh testsuite/testsuite.sh

## Configuration: API Key Setup

The `gemini-files.sh` script (and the test suite) needs your Google API key. You can provide it in one of two ways:

1.  **Environment Variable (Recommended):**
    * Set the `GEMINI_API_KEY` environment variable to your actual API key string.

            export GEMINI_API_KEY="AIza........................."

    * You can add this line to your shell profile (e.g., `~/.bashrc`, `~/.bash_profile`, `~/.zshrc`) for persistence across sessions.
    * *(Optional)* You can change the environment variable name checked by the script by editing the `API_KEY_ENV_VAR` variable near the top of `gemini-files.sh` and `testsuite.sh`.

2.  **Key File:**
    * Create a plain text file containing *only* your API key (no extra spaces or newlines).
    * Pass the path to this file using the `--keyfile` argument when running the script:

            ./src/gemini-files.sh --list --keyfile /path/to/your/secret.key

        or for the test suite:

            ./testsuite/testsuite.sh --keyfile /path/to/your/secret.key

        *(Note: Ensure the path works relative to where you run the command)*

**Priority:** If both the environment variable is set *and* the `--keyfile` argument is provided, the key from the **`--keyfile` will be used**.

## Usage (`gemini-files.sh`)

The main script is located in the `src/` directory. Run it from the repository root directory like `./src/gemini-files.sh ...`.

**Basic Syntax:**

    ./src/gemini-files.sh [options] <ACTION> [action_args...]

Exactly one action mode must be specified. If no action mode is given, the help message is displayed.

**Action Modes & Arguments:**

* `--list [id1 id2 ...]`
    List files. If specific file IDs (e.g., `files/xxxx` or just `xxxx`) are provided, only those files are listed (JSON output). If no IDs are provided, all files are listed (JSON output). Warnings are printed to stderr for requested IDs that are not found.
* `--delete [id1 id2 ...]`
    Delete files. If specific file IDs are provided, only those are targeted (after validation). If no IDs are provided, all files are targeted. **Requires interactive confirmation** (`Type 'yes' to confirm`) unless input is piped (e.g., `echo "yes" | ...`).
* `--upload <fp1> [fp2 ...]`
    Upload one or more specified local files (`<fp1>`, `[fp2]`, etc.). Attempts to detect MIME type using the `file` command. Performs verification checks after upload attempts to ensure files become `ACTIVE`. Prints the `files/xxx` name for each successfully uploaded and verified file to stdout. Reports a summary and exits with an error code if any upload or verification fails.
* `--query <id_or_uri>`
    Query the specified previously uploaded file. Requires `--query-file`. The identifier can be the short name (`files/xxx`), just the ID (`xxx`), or the full File API URI (`https://.../files/xxx`).

**Other Options:**

* `--query-file <path>`
    *Required for `--query` mode.* Path to a plain text file containing the query/prompt to send to the generative model along with the file context.
* `--model <name>`
    *(Optional for `--query` mode)* Specifies the generative model to use (e.g., `gemini-1.5-pro-latest`, `gemini-1.5-flash-latest`). Defaults to the value of `DEFAULT_MODEL` set in the script configuration (`gemini-1.5-pro-latest`).
* `--keyfile <path>`
    Path to the file containing the Google API Key. Overrides the `GEMINI_API_KEY` environment variable if both are set.
* `-v, --verbose`
    Enable verbose informational output to stderr during script execution.
* `-h, --help`
    Show the help message.

## Examples

*(Assume API key is set via environment variable or `--keyfile` is added)*

    # List all files (JSON output)
    ./src/gemini-files.sh --list

    # List specific files with verbose output (using env var for key)
    ./src/gemini-files.sh --list files/abc123efg files/xyz789abc -v

    # Upload a single PDF, using a keyfile in parent dir
    ./src/gemini-files.sh --upload document.pdf --keyfile ../mykey.key

    # Upload multiple files (using env var for key)
    ./src/gemini-files.sh --upload image.jpg data.csv notes.txt

    # Query an uploaded PDF using a query stored in 'my_prompt.txt'
    ./src/gemini-files.sh --query files/abc123efg --query-file my_prompt.txt

    # Query using a specific model
    ./src/gemini-files.sh --query files/abc123efg --query-file my_prompt.txt --model gemini-1.5-flash-latest

    # Delete specific files (will prompt for confirmation)
    ./src/gemini-files.sh --delete files/abc123efg files/xyz789abc

    # Delete all files non-interactively (e.g., in scripts)
    echo "yes" | ./src/gemini-files.sh --delete

## Testing (`testsuite.sh`)

A test suite is provided in `testsuite/testsuite.sh`. It tests the core functionality of `gemini-files.sh` against the live Gemini APIs. It is recommended to run this first to make sure everything works.

**Requirements for Testing:**

* The test suite requires the same dependencies as the main script (`bash 4.2+`, `curl`, `jq`, `qpdf`).
* An active Google API Key (provided via `--keyfile` or `GEMINI_API_KEY`).

**Running the Tests:**

1.  Navigate to the test directory:

        cd Gemini-files/testsuite

2.  Ensure the test script is executable:

        chmod +x testsuite.sh

3.  Run the test suite, providing the API key either via the environment or the `--keyfile` argument passed *to the test script*:

        # Using --keyfile (path relative to testsuite dir or absolute)
        ./testsuite.sh --keyfile ../../path/to/your/secret.key

        # OR Using environment variable
        export GEMINI_API_KEY="AIza........................."
        ./testsuite.sh

**What the Test Suite Does:**

* Performs initial setup checks (scripts exist, data files exist, API key sourced).
* Cleans up any pre-existing files using `--delete` and verifies the list is empty (with retries for consistency).
* Uploads all 20 test PDF files using `--upload` and verifies success.
* Looks up the API file ID for a specific test file (`...020...pdf`).
* Tests listing all files (`--list`).
* Tests listing a specific subset of valid files (`--list id1 id2 id3`).
* Tests listing with one valid and one invalid ID (`--list valid fake`).
* Tests querying the specific test file with a predefined question (`--query`, `--query-file`) and checks for an expected substring in the response (case-insensitive).
* Tests deleting a specific subset of files (`--delete id1 id2`, checking only for successful command execution due to API inconsistency).
* Tests listing files after the partial delete (checks only for successful command execution).
* Tests deleting all remaining files (`--delete`, checking only for successful command execution).
* Tests that the final file list is empty.
* Performs final cleanup on exit/error.
* Reports a summary of passed/failed tests and creates log files (`test_failures.log`, `test_stderr.log`) in the `testsuite` directory for debugging failures.
