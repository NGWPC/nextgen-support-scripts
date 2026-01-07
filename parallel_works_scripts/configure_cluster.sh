#!/bin/bash

NGENCERF_APP=/ngencerf-app
NON_INTERACTIVE=false
AWS_ACCESS_KEY_ID_INPUT=""
AWS_SECRET_ACCESS_KEY_INPUT=""
AWS_SESSION_TOKEN_INPUT=""

# ------------------------------------------------------------------------------
# Parse command line arguments
# ------------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
    case $1 in
        -y|--non-interactive)
            NON_INTERACTIVE=true
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  -y, --non-interactive    Run in non-interactive mode (skip file editing prompts)"
            echo "  -h, --help               Show this help message"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use -h or --help for usage information"
            exit 1
            ;;
    esac
done

# ------------------------------------------------------------------------------
# Display important notice about TAG variables
# ------------------------------------------------------------------------------
echo "================================================================================"
echo "                              IMPORTANT NOTICE                                  "
echo "================================================================================"
echo ""
echo "The following TAG variables will be set to 'development' in .env-override:"
echo "  - MSWM_TAG=development"
echo "  - NGEN_FORCING_TAG=development"
echo "  - DATA_ASSIMILATION_TAG=development"
echo ""
echo "These values should ONLY be changed if you need to use a specific branch,"
echo "commit, or tag for release candidates or official releases."
echo ""
echo "For normal development work, leave these as 'development'."
echo ""
echo "================================================================================"
echo ""
read -p "Do you want to continue? (Y/n): " CONTINUE_RESPONSE

if [[ "$CONTINUE_RESPONSE" =~ ^[Nn] ]]; then
    echo "Configuration cancelled."
    exit 0
fi

echo ""

# ------------------------------------------------------------------------------
# Prompt for AWS credentials if in non-interactive mode
# ------------------------------------------------------------------------------
if [[ "$NON_INTERACTIVE" == "true" ]]; then
    STATIC_DIR="$NGENCERF_APP/data/ngen-static-files"

    # Only prompt if static files don't exist yet
    if [[ ! -d "$STATIC_DIR" ]]; then
        echo "================================================================================"
        echo "AWS Credentials Required"
        echo "================================================================================"
        echo "Please paste your AWS credentials export statements below."
        echo "Paste all three lines (AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, AWS_SESSION_TOKEN)"
        echo "then press Ctrl+D on a new line when done."
        echo ""

        # Read multiline input until EOF (Ctrl+D)
        AWS_CREDS_INPUT=$(cat)

        # Parse the credentials from the pasted export statements
        AWS_ACCESS_KEY_ID_INPUT=$(echo "$AWS_CREDS_INPUT" | grep "AWS_ACCESS_KEY_ID" | sed 's/.*AWS_ACCESS_KEY_ID="\(.*\)"/\1/' | sed "s/.*AWS_ACCESS_KEY_ID='\(.*\)'/\1/" | sed 's/.*AWS_ACCESS_KEY_ID=\(.*\)/\1/')
        AWS_SECRET_ACCESS_KEY_INPUT=$(echo "$AWS_CREDS_INPUT" | grep "AWS_SECRET_ACCESS_KEY" | sed 's/.*AWS_SECRET_ACCESS_KEY="\(.*\)"/\1/' | sed "s/.*AWS_SECRET_ACCESS_KEY='\(.*\)'/\1/" | sed 's/.*AWS_SECRET_ACCESS_KEY=\(.*\)/\1/')
        AWS_SESSION_TOKEN_INPUT=$(echo "$AWS_CREDS_INPUT" | grep "AWS_SESSION_TOKEN" | sed 's/.*AWS_SESSION_TOKEN="\(.*\)"/\1/' | sed "s/.*AWS_SESSION_TOKEN='\(.*\)'/\1/" | sed 's/.*AWS_SESSION_TOKEN=\(.*\)/\1/')

        echo ""
        echo "Credentials parsed successfully."
        echo "================================================================================"
        echo
    fi
fi

# ------------------------------------------------------------------------------
# Helper: Prompt user with a message, then open the file in an editor
# ------------------------------------------------------------------------------
edit_file_with_message() {
    local file="$1"
    local message="$2"

    if [[ "$NON_INTERACTIVE" == "true" ]]; then
        echo
        echo "================================================================================"
        echo "[NON-INTERACTIVE MODE] Skipping file edit: $file"
        echo "$message"
        echo "================================================================================"
        echo
        return 0
    fi

    echo
    echo "================================================================================"
    echo "$message"
    echo
    echo "When you're done, save and exit your editor (e.g., :wq in vim)."
    echo "================================================================================"
    echo

    read -p "Press ENTER to open $file..." _

    # Fallback chain: $EDITOR -> vim -> vi
    if [[ -n "$EDITOR" ]]; then
        "$EDITOR" "$file"
    elif command -v vim >/dev/null 2>&1; then
        vim "$file"
    else
        vi "$file"
    fi
}

# ------------------------------------------------------------------------------
# Clone Software Repositories
# ------------------------------------------------------------------------------
echo "Cloning software repos..."
echo

cd $NGENCERF_APP

if [[ ! -d "nwm-automation-scripts" ]]; then
    git clone -b development https://github.com/NGWPC/nwm-automation-scripts.git
else
    echo "nwm-automation-scripts already exists, skipping clone."
fi

if [[ ! -d "ngencerf-ui" ]]; then
    git clone -b development https://github.com/NGWPC/ngencerf-ui.git
else
    echo "ngencerf-ui already exists, skipping clone."
fi

if [[ ! -d "ngencerf-server" ]]; then
    git clone -b development https://github.com/NGWPC/ngencerf-server.git
else
    echo "ngencerf-server already exists, skipping clone."
fi

if [[ ! -d "ngencerf-docker" ]]; then
    git clone -b development https://github.com/NGWPC/ngencerf-docker.git
else
    echo "ngencerf-docker already exists, skipping clone."
fi

if [[ ! -d "ngen" ]]; then
    git clone -b development --recurse-submodules https://github.com/NGWPC/ngen.git
else
    echo "ngen already exists, skipping clone."
fi

if [[ ! -d "nwm-cal-mgr" ]]; then
    git clone -b development https://github.com/NGWPC/nwm-cal-mgr.git
else
    echo "nwm-cal-mgr already exists, skipping clone."
fi

if [[ ! -d "ngen-forcing" ]]; then
    git clone -b development https://github.com/NGWPC/ngen-forcing.git
else
    echo "ngen-forcing already exists, skipping clone."
fi

if [[ ! -d "nwm-fcst-mgr" ]]; then
    git clone -b development https://github.com/NGWPC/nwm-fcst-mgr.git
else
    echo "nwm-fcst-mgr already exists, skipping clone."
fi

if [[ ! -d "nwm-verf" ]]; then
    git clone -b development https://github.com/NGWPC/nwm-verf.git
else
    echo "nwm-verf already exists, skipping clone."
fi

echo

# ------------------------------------------------------------------------------
# Pull Required Docker Images
# ------------------------------------------------------------------------------
echo "Pulling required Docker images..."
echo

docker pull ghcr.io/ngwpc/ngen:latest
docker pull ghcr.io/ngwpc/nwm-cal-mgr:latest
docker pull ghcr.io/ngwpc/ngen-bmi-forcing:latest
docker pull ghcr.io/ngwpc/ngen-lumped-forcing:latest
docker pull ghcr.io/ngwpc/ngen-coastal:latest
docker pull ghcr.io/ngwpc/ngen-sfincs-forcing:latest
docker pull ghcr.io/ngwpc/nwm-fcst-mgr:latest
docker pull ghcr.io/ngwpc/nwm-verf:latest

echo

# ------------------------------------------------------------------------------
# Create Singularity Directory
# ------------------------------------------------------------------------------
echo "Creating singularity directory..."
mkdir -p $NGENCERF_APP/singularity
echo

# ------------------------------------------------------------------------------
# Download Singularity Container for nginx
# ------------------------------------------------------------------------------
echo "Downloading singularity container for nginx..."
if [[ ! -f "$NGENCERF_APP/singularity/nginx-unprivileged.sif" ]]; then
    cd $NGENCERF_APP
    git clone https://github.com/parallelworks/interactive_session.git
    cp interactive_session/downloads/jupyter/nginx-unprivileged.sif singularity/
    rm -rf interactive_session
    echo "nginx-unprivileged.sif downloaded successfully."
else
    echo "nginx-unprivileged.sif already exists, skipping download."
fi
echo

# ------------------------------------------------------------------------------
# Create Singularity Container for ngen
# ------------------------------------------------------------------------------
echo "Creating singularity container for ngen..."
cd $NGENCERF_APP/singularity

if [[ ! -f "ngen.sif" ]]; then
    docker save ghcr.io/ngwpc/ngen:latest -o ngen.tar
    datestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    singularity build ngen-latest-${datestamp}.sif docker-archive://ngen.tar
    ln -sf ngen-latest-${datestamp}.sif ngen.sif
    rm -f ngen.tar
    echo "ngen singularity container created successfully."
else
    echo "ngen.sif already exists, skipping creation."
fi
echo

# ------------------------------------------------------------------------------
# Create Singularity Container for nwm-cal-mgr
# ------------------------------------------------------------------------------
echo "Creating singularity container for nwm-cal-mgr..."
cd $NGENCERF_APP/singularity

if [[ ! -f "nwm-cal-mgr.sif" ]]; then
    docker save ghcr.io/ngwpc/nwm-cal-mgr:latest -o nwm-cal-mgr.tar
    datestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    singularity build nwm-cal-mgr-latest-${datestamp}.sif docker-archive://nwm-cal-mgr.tar
    ln -sf nwm-cal-mgr-latest-${datestamp}.sif nwm-cal-mgr.sif
    rm -f nwm-cal-mgr.tar
    echo "nwm-cal-mgr singularity container created successfully."
else
    echo "nwm-cal-mgr.sif already exists, skipping creation."
fi
echo

# ------------------------------------------------------------------------------
# Create Singularity Container for ngen-bmi-forcing
# ------------------------------------------------------------------------------
echo "Creating singularity container for ngen-bmi-forcing..."
cd $NGENCERF_APP/singularity

if [[ ! -f "ngen-bmi-forcing.sif" ]]; then
    docker save ghcr.io/ngwpc/ngen-bmi-forcing:latest -o ngen-bmi-forcing.tar
    datestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    singularity build ngen-bmi-forcing-latest-${datestamp}.sif docker-archive://ngen-bmi-forcing.tar
    ln -sf ngen-bmi-forcing-latest-${datestamp}.sif ngen-bmi-forcing.sif
    rm -f ngen-bmi-forcing.tar
    echo "ngen-bmi-forcing singularity container created successfully."
else
    echo "ngen-bmi-forcing.sif already exists, skipping creation."
fi
echo

# ------------------------------------------------------------------------------
# Create Singularity Container for ngen-lumped-forcing
# ------------------------------------------------------------------------------
echo "Creating singularity container for ngen-lumped-forcing..."
cd $NGENCERF_APP/singularity

if [[ ! -f "ngen-lumped-forcing.sif" ]]; then
    docker save ghcr.io/ngwpc/ngen-lumped-forcing:latest -o ngen-lumped-forcing.tar
    datestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    singularity build ngen-lumped-forcing-latest-${datestamp}.sif docker-archive://ngen-lumped-forcing.tar
    ln -sf ngen-lumped-forcing-latest-${datestamp}.sif ngen-lumped-forcing.sif
    rm -f ngen-lumped-forcing.tar
    echo "ngen-lumped-forcing singularity container created successfully."
else
    echo "ngen-lumped-forcing.sif already exists, skipping creation."
fi
echo

# ------------------------------------------------------------------------------
# Create Singularity Container for nwm-fcst-mgr
# ------------------------------------------------------------------------------
echo "Creating singularity container for nwm-fcst-mgr..."
cd $NGENCERF_APP/singularity

if [[ ! -f "nwm-fcst-mgr.sif" ]]; then
    docker save ghcr.io/ngwpc/nwm-fcst-mgr:latest -o nwm-fcst-mgr.tar
    datestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    singularity build nwm-fcst-mgr-latest-${datestamp}.sif docker-archive://nwm-fcst-mgr.tar
    ln -sf nwm-fcst-mgr-latest-${datestamp}.sif nwm-fcst-mgr.sif
    rm -f nwm-fcst-mgr.tar
    echo "nwm-fcst-mgr singularity container created successfully."
else
    echo "nwm-fcst-mgr.sif already exists, skipping creation."
fi
echo

# ------------------------------------------------------------------------------
# Create Singularity Container for nwm-verf
# ------------------------------------------------------------------------------
echo "Creating singularity container for nwm-verf..."
cd $NGENCERF_APP/singularity

if [[ ! -f "nwm-verf.sif" ]]; then
    docker save ghcr.io/ngwpc/nwm-verf:latest -o nwm-verf.tar
    datestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    singularity build nwm-verf-latest-${datestamp}.sif docker-archive://nwm-verf.tar
    ln -sf nwm-verf-latest-${datestamp}.sif nwm-verf.sif
    rm -f nwm-verf.tar
    echo "nwm-verf singularity container created successfully."
else
    echo "nwm-verf.sif already exists, skipping creation."
fi
echo

# ------------------------------------------------------------------------------
# Create Singularity Container for ngen-coastal
# ------------------------------------------------------------------------------
echo "Creating singularity container for ngen-coastal..."
cd $NGENCERF_APP/singularity

if [[ ! -f "ngen-coastal.sif" ]]; then
    docker save ghcr.io/ngwpc/ngen-coastal:latest -o ngen-coastal.tar
    datestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    singularity build ngen-coastal-latest-${datestamp}.sif docker-archive://ngen-coastal.tar
    ln -sf ngen-coastal-latest-${datestamp}.sif ngen-coastal.sif
    rm -f ngen-coastal.tar
    echo "ngen-coastal singularity container created successfully."
else
    echo "ngen-coastal.sif already exists, skipping creation."
fi
echo

# ------------------------------------------------------------------------------
# Create Singularity Container for ngen-sfincs-forcing
# ------------------------------------------------------------------------------
echo "Creating singularity container for ngen-sfincs-forcing..."
cd $NGENCERF_APP/singularity

if [[ ! -f "ngen-sfincs-forcing.sif" ]]; then
    docker save ghcr.io/ngwpc/ngen-sfincs-forcing:latest -o ngen-sfincs-forcing.tar
    datestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    singularity build ngen-sfincs-forcing-latest-${datestamp}.sif docker-archive://ngen-sfincs-forcing.tar
    ln -sf ngen-sfincs-forcing-latest-${datestamp}.sif ngen-sfincs-forcing.sif
    rm -f ngen-sfincs-forcing.tar
    echo "ngen-sfincs-forcing singularity container created successfully."
else
    echo "ngen-sfincs-forcing.sif already exists, skipping creation."
fi
echo

# ------------------------------------------------------------------------------
# Load Static Files
# ------------------------------------------------------------------------------
echo "Loading static files..."
STATIC_DIR="$NGENCERF_APP/data/ngen-static-files"

if [[ -d "$STATIC_DIR" ]]; then
    echo "Static data directory already exists at $STATIC_DIR"
    echo "Skipping static files setup."
else
    echo "Creating static data directory..."
    sudo mkdir -p "$STATIC_DIR"
    sudo chown -R $(whoami):pwuser $NGENCERF_APP/data
    sudo chmod -R g+rwx $NGENCERF_APP/data

    # Handle AWS credentials
    if [[ "$NON_INTERACTIVE" == "true" ]]; then
        echo "Non-interactive mode: Using provided AWS credentials"
        echo
        echo "Copying data from NGWPC data bucket..."

        # Export credentials for AWS CLI
        export AWS_ACCESS_KEY_ID="$AWS_ACCESS_KEY_ID_INPUT"
        export AWS_SECRET_ACCESS_KEY="$AWS_SECRET_ACCESS_KEY_INPUT"
        if [[ -n "$AWS_SESSION_TOKEN_INPUT" ]]; then
            export AWS_SESSION_TOKEN="$AWS_SESSION_TOKEN_INPUT"
        fi

        aws s3 cp --recursive s3://ngwpc-dev/ngen-static-files "$STATIC_DIR/"

        # Unset credentials after use
        unset AWS_ACCESS_KEY_ID
        unset AWS_SECRET_ACCESS_KEY
        unset AWS_SESSION_TOKEN
    else
        # Create temporary AWS credentials file for user to edit
        edit_file_with_message "/tmp/aws.credentials" \
            "Paste export statements for your AWS credentials in this file. These are temporary credentials to copy the static files."

        source /tmp/aws.credentials

        echo
        echo "Copying data from NGWPC data bucket..."
        aws s3 cp --recursive s3://ngwpc-dev/ngen-static-files "$STATIC_DIR/"
        rm -f /tmp/aws.credentials
    fi

    echo
    echo "Retrieving module parameter files from nwm-msw-mgr repository..."
    cd "$STATIC_DIR"
    rm -rf module_parameter_files
    git clone --depth 1 --filter=blob:none --sparse -b development \
        https://github.com/NGWPC/nwm-msw-mgr.git tmp-nwm-msw-mgr
    cd tmp-nwm-msw-mgr
    git sparse-checkout set src/mswm/module_parameter_files
    mv src/mswm/module_parameter_files ../
    cd ..
    rm -rf tmp-nwm-msw-mgr

    echo
    echo "Obtaining BMI forcing templates from ngen-forcing repository..."
    cd "$STATIC_DIR"
    rm -rf bmi_forcing_templates
    git clone --depth 1 --filter=blob:none --sparse -b development \
        https://github.com/NGWPC/ngen-forcing.git tmp-ngen-forcing
    cd tmp-ngen-forcing
    git sparse-checkout set NextGen_Forcings_Engine_BMI/BMI_NextGen_Configs/config_templates
    mv NextGen_Forcings_Engine_BMI/BMI_NextGen_Configs/config_templates ../bmi_forcing_templates
    cd ..
    rm -rf tmp-ngen-forcing

    echo
    echo "Extracting verification data from nwm-verf repository..."
    cd "$STATIC_DIR"
    rm -rf verification_data
    git clone --depth 1 --filter=blob:none --sparse -b development \
        https://github.com/NGWPC/nwm-verf.git tmp-ngen-verf
    cd tmp-ngen-verf
    git sparse-checkout set data/inputs
    mkdir -p ../verification_data
    find data/inputs -type f -name '*.parquet' -exec cp {} ../verification_data/ \;
    cd ..
    rm -rf tmp-ngen-verf

    echo "Static files setup complete."
fi

echo

# ------------------------------------------------------------------------------
# Configure ngencerf-server
# ------------------------------------------------------------------------------
echo "Configuring ngencerf-server..."
cd $NGENCERF_APP/ngencerf-server

# Create .env-override file
if [[ ! -f "$NGENCERF_APP/ngencerf-server/cerfServer/.env-override" ]]; then
    echo "Creating .env-override from .env-docker-prod..."
    cp $NGENCERF_APP/ngencerf-server/cerfServer/.env-docker-prod $NGENCERF_APP/ngencerf-server/cerfServer/.env-override

    # Remove all lines above "Cluster specific data"
    sed -i '1,/# Cluster specific data below/{ /# Cluster specific data below/!d; }' $NGENCERF_APP/ngencerf-server/cerfServer/.env-override

    echo ".env-override created successfully."
else
    echo ".env-override already exists."
fi

# Automatically add TAG variables to .env-override
echo "Adding TAG variables to .env-override..."
cat >> "$NGENCERF_APP/ngencerf-server/cerfServer/.env-override" << 'EOF'

# TAG variables for branch/commit/tag selection
MSWM_TAG=development
NGEN_FORCING_TAG=development
DATA_ASSIMILATION_TAG=development
EOF
echo "TAG variables added successfully."

edit_file_with_message "$NGENCERF_APP/ngencerf-server/cerfServer/.env-override" \
    "Set the following environment variables in .env-override:
    - CERF_SERVER_SECRET_KEY
    - NGENCERF_ARCHIVE_S3_PATH
    - CERF_SERVER_DATABASE_NAME
    - CERF_SERVER_DATABASE_USER
    - CERF_SERVER_DATABASE_PASSWORD
    - CERF_SERVER_DATABASE_HOST
    - ENTERPRISE_DATA_URL

    Note: MSWM_TAG, NGEN_FORCING_TAG, and DATA_ASSIMILATION_TAG have been automatically set to 'development'"

echo

# ------------------------------------------------------------------------------
# Set up ngencerf-server Logging
# ------------------------------------------------------------------------------
echo "Setting up ngencerf-server logrotate cron job..."

LOGROTATE_CONF="$NGENCERF_APP/ngencerf-server/logrotate-ngencerf.prod.conf"
CRON_FILE='/etc/cron.d/ngencerf-logrotate'
CRON_JOB="0 10,22 * * * root [ -f $LOGROTATE_CONF ] && /usr/sbin/logrotate $LOGROTATE_CONF"

echo "$CRON_JOB" | sudo tee "$CRON_FILE" > /dev/null
sudo chmod 0644 "$CRON_FILE"

# Set permissions on the logrotate config if it exists
if [ -f "$LOGROTATE_CONF" ]; then
    sudo chown root:root "$LOGROTATE_CONF"
    sudo chmod 0644 "$LOGROTATE_CONF"
    echo "Logrotate cron job created successfully."
else
    echo "warn: $LOGROTATE_CONF not found; skipping permission fix."
fi

echo
echo "================================================================================"
echo "Cluster configuration complete!"
echo "================================================================================"
