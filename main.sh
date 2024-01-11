#!/bin/bash

#for at kunne eksikvere scriptet skal der først gøres to ting i terminalen
#1 sed -i -e 's/\r$//' /data/KGAusers/raspau/auto_demultiplex.sh
#2 chmod +x /data/KGAusers/raspau/auto_demultiplex.sh
# scriptet kan nu køres ved input "/data/KGAusers/raspau/auto_demultiplex.sh [date of the sequencing run 'DDMMYY']"



if [ "$#" -lt 1 ]; then
  echo "Usage: $0 'NUMBERS (please provide the date 'DDMMYY'. Which is used to search for folder and samplesheet name)'"
  exit 1
fi

# Initialize a flag to indicate whether the folder and samplesheet have been found
FOUND=0

while [ $FOUND -eq 0 ]; do
  if [ "$#" -lt 1 ]; then
    echo "Usage: $0 'NUMBERS (please provide the date 'DDMMYY'. Which is used to search for folder and samplesheet name)'"
    exit 1
  fi

  # Assign the first argument to a variable NUMBERS
  NUMBERS=$1

  # Define the base directory for folders and samplesheets
  CURRENT_YEAR=$(date +%Y)
  BASE_FOLDER_DIR="/data/NGS.runs/data.upload.from.instruments/NovaSeq/$CURRENT_YEAR/"
  BASE_SAMPLESHEET_DIR="/data/NGS.runs/data.upload.from.instruments/NovaSeq/$CURRENT_YEAR/Samplesheet/"

  # Find the directory that starts with the 6 numbers
  FOLDER=$(find $BASE_FOLDER_DIR -type d -name "${NUMBERS}*" -print -quit)

  # Find the samplesheet that starts with the 6 numbers
  SAMPLE_SHEET=$(find $BASE_SAMPLESHEET_DIR -type f -name "${NUMBERS}*.csv" -print -quit)

  # Initialize flags for found items
  FOLDER_FOUND=0
  SHEET_FOUND=0

  # Check if the folder was found
  if [[ -z "$FOLDER" ]]; then
    echo "Error: Unable to find folder starting with ${NUMBERS}"
  else
    echo "FOLDER found: $FOLDER"
    FOLDER_FOUND=1
  fi

  # Check if the samplesheet was found
  if [[ -z "$SAMPLE_SHEET" ]]; then
    echo "Error: Unable to find samplesheet starting with ${NUMBERS}"
  else
    echo "SAMPLE_SHEET found: $SAMPLE_SHEET"
    SHEET_FOUND=1
  fi

  # Check if both folder and samplesheet were found
  if [ $FOLDER_FOUND -eq 1 ] && [ $SHEET_FOUND -eq 1 ]; then
    FOUND=1  # Set the FOUND flag to 1 to exit the loop
  else
    echo "Checking again in 30 minutes..."
    sleep 1800  # Wait for 30 minutes before retrying
  fi
done


############################################# errors in the samplesheet ###############################################


if [ ! -d "$FOLDER" ] || [ ! -f "$SAMPLE_SHEET" ]; then
  echo "Error: Folder or Sample Sheet does not exist."
  exit 1
fi

# Find the line number where "Sample_ID" header is located
header_line_num=$(awk -F',' '/Sample_ID/{print NR; exit}' "$SAMPLE_SHEET")
((header_line_num++)) # Increment the header line number to start processing from the next line

# Check for space in 'Sample_ID' and 'Sample_Name' collumns
awk -v start_line="$header_line_num" -F ',' 'NR >= start_line {
  if ($1 ~ / /) {
    print "Space found in Sample_ID for sample: " $1
  }
  if ($2 ~ / /) {
    print "Space found in Sample_Name for sample: " $1
  }
}' "$SAMPLE_SHEET"

# Check if 'index' column has 8 or 10 characters for each entry
awk -v start_line="$header_line_num" -F ',' 'NR >= start_line {
  if (length($6) != 8 && length($6) != 10) {
    print "Invalid index length for sample: " $2 " Index: " $6
  }
}' "$SAMPLE_SHEET"

# Check for duplicate 'Sample_ID' entries
awk -v start_line="$header_line_num" -F ',' 'NR >= start_line {print $2}' "$SAMPLE_SHEET" | sort | uniq -d | while read -r sample_id; do
  echo "Duplicate Sample_ID found: $sample_id"
done

# Check for -A or -B before AV1
if grep -qE ".*-A-AV1.*|.*-B-AV1.*" "$SAMPLE_SHEET"; then
  echo "Error: Samplesheet contains invalid entries (-A-AV1 or -B-AV1)."
  exit 1
fi


#########################################################################################################################

# Initialize DNA and RNA flags as empty
DNA_FLAG=""
RNA_FLAG=""

# Check the samplesheet for "RV1" and "AV1"
if grep -q "RV1" "$SAMPLE_SHEET"; then
  DNA_FLAG="--RNA"
  echo "RNA found"
fi
if grep -q "AV1" "$SAMPLE_SHEET"; then
  RNA_FLAG="--DNA"
  echo "DNA found"
fi

WATCH_FILE="CopyComplete.txt"
FOUND=0

echo "Script started. Watching for ${WATCH_FILE} in ${FOLDER}"

while [ $FOUND -eq 0 ]; do
  if [ -f "${FOLDER}/${WATCH_FILE}" ]; then
    echo "File: ${WATCH_FILE} found in ${FOLDER}. Preparing to start Nextflow..."
    FOUND=1
  else
    echo "File: ${WATCH_FILE} not found in ${FOLDER}. Checking again in 30 minutes..."
    sleep 1800
  fi
done

# Now that the file is found, run the Nextflow command with the optional flags
# echo "Demultiplexing er nu sat igang" | mail -s "demultiplexing af ${FOLDER} er nu sat i gang" -v KGVejleServer@hotmail.com
nextflow run KGVejle/demultiplex -r main --runfolder "${FOLDER}" --samplesheet "${SAMPLE_SHEET}" ${DNA_FLAG} ${RNA_FLAG}
