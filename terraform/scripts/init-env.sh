#!/bin/bash
# Initialize a new environment by copying from dev template
# Usage: ./scripts/init-env.sh <environment_name>

set -e

ENV_NAME="${1}"

if [ -z "$ENV_NAME" ]; then
    echo "ERROR: Environment name is required."
    echo "Usage: ./scripts/init-env.sh <environment_name>"
    echo "Example: ./scripts/init-env.sh staging"
    exit 1
fi

if [ "$ENV_NAME" == "dev" ]; then
    echo "ERROR: 'dev' environment already exists."
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="$(dirname "$SCRIPT_DIR")"
SOURCE_ENV="dev"
TARGET_ENV="$ENV_NAME"

echo "=============================================="
echo "Terraform Environment Initializer"
echo "=============================================="
echo ""
echo "Creating new environment: $TARGET_ENV"
echo "Source template: $SOURCE_ENV"
echo ""

# Check if source environment exists
if [ ! -d "$TERRAFORM_DIR/envs/$SOURCE_ENV" ]; then
    echo "ERROR: Source environment '$SOURCE_ENV' not found at envs/$SOURCE_ENV"
    exit 1
fi

# Check if target already exists
if [ -d "$TERRAFORM_DIR/envs/$TARGET_ENV" ]; then
    echo "WARNING: Environment '$TARGET_ENV' already exists."
    read -p "Overwrite? (y/N): " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo "Aborted."
        exit 0
    fi
    rm -rf "$TERRAFORM_DIR/envs/$TARGET_ENV"
fi

# Copy source environment
cp -r "$TERRAFORM_DIR/envs/$SOURCE_ENV" "$TERRAFORM_DIR/envs/$TARGET_ENV"

echo "Copied envs/$SOURCE_ENV to envs/$TARGET_ENV"

# Replace environment references in backend.tf and terraform.tfvars
for stack_dir in "$TERRAFORM_DIR/envs/$TARGET_ENV"/*; do
    if [ -d "$stack_dir" ]; then
        stack_name=$(basename "$stack_dir")
        echo "Processing stack: $stack_name"

        # Update backend.tf: replace dev with new environment in bucket/table names and state keys
        if [ -f "$stack_dir/backend.tf" ]; then
            sed -i.bak \
                -e "s/serenity-dev-terraform-v2-state/serenity-${TARGET_ENV}-terraform-v2-state/g" \
                -e "s/serenity-dev-terraform-v2-locks/serenity-${TARGET_ENV}-terraform-v2-locks/g" \
                -e "s|\"dev/|\"${TARGET_ENV}/|g" \
                "$stack_dir/backend.tf"
            rm -f "$stack_dir/backend.tf.bak"
            echo "  Updated backend.tf"
        fi

        # Update terraform.tfvars: replace environment = "dev"
        if [ -f "$stack_dir/terraform.tfvars" ]; then
            sed -i.bak \
                -e "s/environment *= *\"dev\"/environment = \"${TARGET_ENV}\"/g" \
                "$stack_dir/terraform.tfvars"
            rm -f "$stack_dir/terraform.tfvars.bak"
            echo "  Updated terraform.tfvars"
        fi
    fi
done

echo ""
echo "=============================================="
echo "Environment '$TARGET_ENV' initialized!"
echo "=============================================="
echo ""
echo "Next steps:"
echo "  1. Review and edit envs/$TARGET_ENV/*/terraform.tfvars"
echo "  2. Run bootstrap for the new environment:"
echo "     cd bootstrap && terraform apply -var=\"environment=$TARGET_ENV\""
echo "  3. Deploy stacks:"
echo "     cd envs/$TARGET_ENV/01-networking && terraform init && terraform apply"
echo "     cd ../02-eks && terraform init && terraform apply"
echo "     cd ../03-databases && terraform init && terraform apply"
echo ""
