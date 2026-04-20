#!/bin/bash
# Initialize a new environment from the dev templates
# Usage: ./scripts/init-env.sh <environment_name>
#
# New environments reuse the primary VPC (envs/common/networking/) which hosts the shared EKS cluster.

set -e

ENV_NAME="${1}"

if [ -z "$ENV_NAME" ]; then
    echo "ERROR: Environment name is required."
    echo "Usage: ./scripts/init-env.sh <environment_name>"
    echo "Example: ./scripts/init-env.sh staging"
    exit 1
fi

if [ "$ENV_NAME" == "dev" ] || [ "$ENV_NAME" == "networking" ]; then
    echo "ERROR: '$ENV_NAME' is a reserved environment name."
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="$(dirname "$SCRIPT_DIR")"
TARGET_ENV="$ENV_NAME"

echo "=============================================="
echo "Terraform Environment Initializer"
echo "=============================================="
echo ""
echo "Creating new peer environment: $TARGET_ENV"
echo "Primary VPC: envs/common/networking/"
echo ""

# Create target directory
if [ -d "$TERRAFORM_DIR/envs/$TARGET_ENV" ]; then
    echo "WARNING: Environment '$TARGET_ENV' already exists."
    read -p "Overwrite? (y/N): " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo "Aborted."
        exit 0
    fi
    rm -rf "$TERRAFORM_DIR/envs/$TARGET_ENV"
fi

mkdir -p "$TERRAFORM_DIR/envs/$TARGET_ENV"

# Note: networking stack is intentionally NOT copied.
# New environments reuse the shared VPC in envs/common/networking/

# Copy shared templates into each new stack
for stack in 03-aurora 04-redis; do
    stack_dir="$TERRAFORM_DIR/envs/$TARGET_ENV/$stack"
    mkdir -p "$stack_dir"

    # Copy provider config from shared templates
    cp "$TERRAFORM_DIR/envs/_shared/provider.tf" "$stack_dir/provider.tf"

    # Generate backend.tf from template
    stack_key="${stack#03-}"  # Remove 03-/04- prefix for state key
    stack_key="${stack_key#04-}"
    sed \
        -e "s/{{ENV}}/$TARGET_ENV/g" \
        -e "s/{{STACK}}/$stack_key/g" \
        "$TERRAFORM_DIR/envs/_shared/backend.tf.template" > "$stack_dir/backend.tf"

    # Copy module config from dev templates
    cp "$TERRAFORM_DIR/envs/dev/$stack/main.tf" "$stack_dir/main.tf"
    cp "$TERRAFORM_DIR/envs/dev/$stack/variables.tf" "$stack_dir/variables.tf"
    cp "$TERRAFORM_DIR/envs/dev/$stack/terraform.tfvars" "$stack_dir/terraform.tfvars"

    # Update environment in tfvars
    sed -i.bak \
        -e "s/environment *= *\"dev\"/environment = \"${TARGET_ENV}\"/g" \
        "$stack_dir/terraform.tfvars"
    rm -f "$stack_dir/terraform.tfvars.bak"

    echo "Created $stack stack"
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
echo "     cd envs/$TARGET_ENV/03-aurora && terraform init && terraform apply"
echo "     cd ../04-redis && terraform init && terraform apply"
echo ""
