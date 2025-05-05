#!/bin/bash

###############################################################################
# EEG/ERP/GPS Data Copy Script
#
# Description:
#   This script reads EEG metadata from a CSV file, locates corresponding EEG,
#   ERP, and GPS data directories/files, and copies them into a BIDS-compatible
#   directory structure. A JSON metadata file is created for each subject-session.
#
# Inputs:
#   - EEG metadata CSV file
#   - Source directories containing EEG, ERP, and GPS data
#
# Outputs:
#   - Organized BIDS-compatible directories for each subject-session
#   - JSON metadata file summarizing subject information
#
# Author: [Your Name]
# Date: [Date]
###############################################################################

# -----------------------------
# Configuration: Set directories
# -----------------------------
#!/bin/bash

# Input and output paths
input_csv="/mnt/Storage/Backupdata/MRI/26122023/project_EEG/EEG_scripts/EEG_sheet.csv"
base_dir="/mnt/Storage/Backupdata/MRI/26122023/EEG_backup_31032025"
output_dir="/mnt/Storage/Backupdata/MRI/26122023/project_EEG/BIDS"

# Build search paths
EEG_dirs=("$base_dir"/*/DATA-*/EEG/*)
ERP_dirs=("$base_dir"/*/DATA-*/ERP/*)
GPS_dirs=("$base_dir"/*/DATA-*/GPS-BESA/*)

# Iterate over EEG folders
for eeg_folder in "${EEG_dirs[@]}"; do
    for eeg_subfolder in "$eeg_folder"/EEG*_*; do
        [ -d "$eeg_subfolder" ] || continue

        eeg_basename=$(basename "$eeg_subfolder")
        eeg_id=$(echo "$eeg_basename" | sed -E 's/^EEG([0-9]+)_.*/\1/')

        echo "🔍 Checking EEG_ID=$eeg_id (from folder: $eeg_basename)"

        # Find matching line in CSV
        line=$(awk -F',' -v id="$eeg_id" 'NR > 1 && $3 == id {print}' "$input_csv")

        if [ -n "$line" ]; then
            # Extract CSV fields
            ADBS_ID=$(echo "$line" | cut -d',' -f1 | tr -d '"' | xargs)
            ASSESSMENT_ID=$(echo "$line" | cut -d',' -f2 | tr -d '"' | xargs)
            EEG_ID=$(echo "$line" | cut -d',' -f3 | tr -d '"' | xargs)
            ERP_NO=$(echo "$line" | cut -d',' -f4 | tr -d '"' | xargs)
            GPS_NO=$(echo "$line" | cut -d',' -f5 | tr -d '"' | xargs)
            SSO_REMARKS=$(echo "$line" | awk -F',' '{gsub(/^[ \t]+|[ \t]+$/, "", $6); print $6}')

            # Escape special characters for JSON
            SSO_REMARKS_ESCAPED=$(printf '%s' "$SSO_REMARKS" | sed \
                -e 's/\\/\\\\/g' \
                -e 's/"/\\"/g' \
                -e ':a;N;$!ba;s/\n/\\n/g' \
                -e 's/\r/\\r/g')

            prefix=${ASSESSMENT_ID:0:3}
            dest_dir="$output_dir/$ADBS_ID/ses-$prefix"

            echo "Matched CSV: ADBS_ID=$ADBS_ID, ASSESSMENT_ID=$ASSESSMENT_ID, ERP_NO=$ERP_NO, GPS_NO=$GPS_NO"
            echo "→ Destination: $dest_dir"

            # Check if data already exists
            if find "$dest_dir" -mindepth 1 \( -type d -name "*.mff" -o -type f -name "*.sfp" \) | grep -q .; then
                echo "Data already exists in $dest_dir (mff or sfp), skipping subject."
                continue
            fi

            mkdir -p "$dest_dir"

            # Copy EEG folder
            echo "Copying EEG folder: $eeg_subfolder → $dest_dir/"
            cp -r "$eeg_subfolder" "$dest_dir/"

            # Look for ERP folder
            found_erp=0
            for erp_folder in "${ERP_dirs[@]}"; do
                erp_match=$(find "$erp_folder" -type d -name "${ERP_NO}_*.mff" | head -n1)
                if [ -n "$erp_match" ]; then
                    echo "Copying ERP folder: $erp_match → $dest_dir/"
                    cp -r "$erp_match" "$dest_dir/"
                    found_erp=1
                    break
                fi
            done
            if [ "$found_erp" -eq 0 ]; then
                echo "No ERP folder found for ERP_NO=$ERP_NO"
            fi

            # Look for GPS file
            found_gps=0
            for gps_folder in "${GPS_dirs[@]}"; do
                gps_file=$(find "$gps_folder" -type f \( \
                    -name "coordinates_${GPS_NO}_BESA.sfp" \
                    -o -name "coordinates_${ASSESSMENT_ID}_BESA.sfp" \
                \) | head -n1)
                if [ -n "$gps_file" ]; then
                    echo "Copying GPS file: $gps_file → $dest_dir/"
                    cp "$gps_file" "$dest_dir/"
                    found_gps=1
                    break
                fi
            done
            if [ "$found_gps" -eq 0 ]; then
                echo "No GPS file found for GPS_NO=$GPS_NO or ASSESSMENT_ID=$ASSESSMENT_ID"
            fi

            # Create readme.json
            readme_file="$dest_dir/readme.json"
            cat > "$readme_file" <<EOF
{
  "ADBS_ID": "$ADBS_ID",
  "ASSESSMENT_ID": "$ASSESSMENT_ID",
  "EEG_ID": "$EEG_ID",
  "ERP_NO": "$ERP_NO",
  "GPS_NO": "$GPS_NO",
  "SSO_REMARKS": "$SSO_REMARKS_ESCAPED"
}
EOF
            echo "Created $readme_file"

        else
            echo "No CSV match for EEG_ID=$eeg_id"
        fi

    done
done
