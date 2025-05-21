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
# Author: Deepankan
# Date: 05MAy2025
###############################################################################

# -----------------------------
# Configuration: Set directories
# -----------------------------
#!/bin/bash

# Input and output paths
input_csv="DATA_SHEET.csv"
base_dir="/PATH_to_your_input_folder"
output_dir="/Path_to_your_desired_output_folder"


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

        # Match CSV line by EEG_ID (field 3)
        line=$(awk -F',' -v id="$eeg_id" 'NR>1 && $3==id {print}' "$input_csv")

        if [ -n "$line" ]; then
            ADBS_ID=$(echo "$line" | cut -d',' -f1 | tr -d '"' | xargs)
            ASSESSMENT_ID=$(echo "$line" | cut -d',' -f2 | tr -d '"' | xargs)
            EEG_ID=$(echo "$line" | cut -d',' -f3 | tr -d '"' | xargs)

            raw_ERP_NO=$(echo "$line" | cut -d',' -f4 | tr -d '"' | xargs)
            raw_GPS_NO=$(echo "$line" | cut -d',' -f5 | tr -d '"' | xargs)

            SSO_REMARKS=$(echo "$line" | awk -F',' '{gsub(/^[ \t]+|[ \t]+$/, "", $6); print $6}')

            # Escape special characters for JSON
            SSO_REMARKS_ESCAPED=$(printf '%s' "$SSO_REMARKS" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e ':a;N;$!ba;s/\n/\\n/g' -e 's/\r/\\r/g')

            prefix=${ASSESSMENT_ID:0:3}
            dest_dir="$output_dir/$ADBS_ID/ses-$prefix"

            # Pad ERP_NO to 3 digits (if number)
            if [[ "$raw_ERP_NO" =~ ^[0-9]+$ ]]; then
                ERP_NO_PADDED=$(printf "%03d" "$raw_ERP_NO")
            else
                ERP_NO_PADDED="$raw_ERP_NO"
            fi

            # Pad GPS_NO to 3 digits only if numeric, else keep as is
            if [[ "$raw_GPS_NO" =~ ^[0-9]+$ ]]; then
                GPS_NO_PADDED=$(printf "%03d" "$raw_GPS_NO")
            else
                GPS_NO_PADDED="$raw_GPS_NO"
            fi

            echo "Matched CSV: ADBS_ID=$ADBS_ID, ASSESSMENT_ID=$ASSESSMENT_ID, ERP_NO=$raw_ERP_NO (padded: $ERP_NO_PADDED), GPS_NO=$raw_GPS_NO"
            echo "→ Destination: $dest_dir"

            # Check if .mff or .sfp already exists
            if find "$dest_dir" -mindepth 1 \( -type d -name "*.mff" -o -type f -name "*.sfp" \) | grep -q .; then
                echo "Data already exists in $dest_dir (mff or sfp), skipping subject."
                continue
            fi

            mkdir -p "$dest_dir"

            echo "Copying EEG folder: $eeg_subfolder → $dest_dir/"
            cp -r "$eeg_subfolder" "$dest_dir/"

            # Find ERP folder using padded ERP_NO
            found_erp=0
            for erp_folder in "${ERP_dirs[@]}"; do
                erp_match=$(find "$erp_folder" -type d -name "${ERP_NO_PADDED}_${ADBS_ID}_*.mff" | head -n1)
                if [ -n "$erp_match" ]; then
                    echo "Copying ERP folder: $erp_match → $dest_dir/"
                    cp -r "$erp_match" "$dest_dir/"
                    found_erp=1
                    break
                fi
            done
            if [ "$found_erp" -eq 0 ]; then
                echo "No ERP folder found for ERP_NO=$raw_ERP_NO (padded: $ERP_NO_PADDED)"
            fi

            # Find GPS file only if GPS_NO is not FALSE
            found_gps=0
            if [ "$raw_GPS_NO" != "FALSE" ]; then
                for gps_folder in "${GPS_dirs[@]}"; do
                    gps_file=$(find "$gps_folder" -type f \( \
                        -name "coordinates_${GPS_NO_PADDED}_BESA.sfp" \
                        -o -name "coordinates_${ASSESSMENT_ID}_BESA.sfp" \) | head -n1)
                    if [ -n "$gps_file" ]; then
                        echo "📄 Copying GPS file: $gps_file → $dest_dir/"
                        cp "$gps_file" "$dest_dir/"
                        found_gps=1
                        break
                    fi
                done
                if [ "$found_gps" -eq 0 ]; then
                    echo "No GPS file found for GPS_NO=$raw_GPS_NO (padded: $GPS_NO_PADDED) or ASSESSMENT_ID=$ASSESSMENT_ID"
                fi
            else
                echo "GPS_NO is FALSE – skipping GPS copy"
            fi

            # Create readme.json
            readme_file="$dest_dir/readme.json"
            cat > "$readme_file" <<EOF
{
  "ADBS_ID": "$ADBS_ID",
  "ASSESSMENT_ID": "$ASSESSMENT_ID",
  "EEG_ID": "$EEG_ID",
  "ERP_NO": "$raw_ERP_NO",
  "GPS_NO": "$raw_GPS_NO",
  "SSO_REMARKS": "$SSO_REMARKS_ESCAPED"
}
EOF
            echo " Created $readme_file"

        else
            echo " No CSV match for EEG_ID=$eeg_id"
        fi

    done
done
