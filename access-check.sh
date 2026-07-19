#!/bin/bash

set -e

echo "========================================"
echo " Azure Managed Identity Demonstration"
echo "========================================"

echo ""
echo "Logging in using Managed Identity..."

az login --identity --output none

echo "Login Successful."
echo ""

echo "Fetching Secret from Azure Key Vault..."

SECRET=$(az keyvault secret show \
  --vault-name {{ keyvault_name }} \
  --name {{ secret_name }} \
  --query value \
  --output tsv)

echo ""
echo "Secret Retrieved Successfully"
echo "Secret Value: $SECRET"

echo ""
echo "Downloading Blob from Azure Storage..."

az storage blob download \
  --account-name {{ storage_account }} \
  --container-name {{ container_name }} \
  --name {{ blob_name }} \
  --file /tmp/{{ blob_name }} \
  --auth-mode login \
  --overwrite

echo ""
echo "Blob Downloaded Successfully"

echo ""
echo "Blob Content"
echo "-------------------------"

cat /tmp/{{ blob_name }}

echo ""
echo "-------------------------"
echo "Managed Identity Demo Completed Successfully."