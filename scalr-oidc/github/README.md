# Connecting from GitHub Action to Scalr API via OIDC

## Overview
As an administrator, you can connect to the Scalr API using OpenID Connect (OIDC) to eliminate the need for static credentials. This guide provides a step-by-step process to configure OIDC authentication using Scalr's public API, along with detailed explanations of each request and its parameters.

## Prerequisites
Before you begin, ensure you have:
- An existing Scalr account with administrative privileges.
- Generated static token for the initial setup of the OIDC.
- A registered service account in Scalr.
- A GitHub repository with GitHub Actions enabled.

## Steps to Configure OIDC Authentication

### Step 1: Register a Workload Identity Provider
A workload identity provider allows Scalr to verify identity tokens issued by an external OIDC provider, such as GitHub Actions. 

#### **Request**
**Endpoint:**
```
POST https://<account-name>.scalr.io/api/iacp/v3/workload-identity-providers
```

**Headers:**
```
Authorization: Bearer <static-token>
Accept: application/vnd.api+json
Content-Type: application/vnd.api+json
```

**Payload:**
```json
{
    "data": {
        "type": "workload-identity-providers",
        "attributes": {
            "url": "https://token.actions.githubusercontent.com",
            "allowed-audiences": [
                "https://github.com/<owner>"
            ],
            "name": "github-oidc"
        },
        "relationships": {}
    }
}
```

**Explanation:**
- `url`: The OIDC provider's token endpoint (GitHub Actions in this case).
- `allowed-audiences`: A list of trusted audience values that the provider is allowed to provide.
- `name`: A unique identifier for this identity provider within Scalr.

### Step 2: Configure Assume Policy for a Service Account
After registering the workload identity provider, you must define an assume policy, allowing that provider to obtain a temporary access token of the specific service account.

#### **Request**
**Endpoint:**
```
POST https://{{hostname}}/api/iacp/v3/service-accounts/<sa-id>/assume-policies
```

**Headers:**
```
Authorization: Bearer <static-token>
Accept: application/vnd.api+json
Content-Type: application/vnd.api+json
```

**Payload:**
```json
{
    "data": {
        "type": "assume-service-account-policies",
        "attributes": {
            "claim-conditions": [
                {
                    "claim": "repository",
                    "value": "owner/repository",
                    "operator": "eq"
                },
                {
                    "claim": "sub",
                    "value": "repo:<owner>/<repository>:environment:<environment>",
                    "operator": "eq"
                }
            ],
            "maximum-session-duration": 3600,
            "name": "github"
        },
        "relationships": {
            "provider": {
                "data": {
                    "type": "workload-identity-providers",
                    "id": "<widp-id>"
                }
            }
        }
    }
}
```

**Explanation:**
- `claim-conditions`: Defines the conditions under which the identity provider can assume this service account.
  - `repository`: Restricts access to a specific GitHub repository.
  - `sub`: Specifies the exact subject that is allowed to assume this service account.
- `maximum-session-duration`: Optional: Sets the session duration in seconds. Default: 3600 (1 hour).
- `relationships`: Links this policy to the previously registered identity provider.

### Step 3: Update GitHub Actions Workflow
Once the assume policy is in place, modify your GitHub Actions workflow to:
1. Create the environment variable `SA_EMAIL` with the email address of the service account you used in **step 2**.
2. Obtain a GitHub OIDC token.
3. Exchange it for a Scalr access token using the GitHub's ID token and `SA_EMAIL`
4. Use the temporary access token to authenticate and perform OpenTofu operations.

#### **Example GitHub Actions Snippet:**
```yaml
name: Test Scalr Integration

on:
  push:
    branches:
      - master
env:
  SCALR_HOSTNAME: my-account.scalr.io
  SCALR_ENVIRONMENT: my-environment
  SCALR_WORKSPACE: my-environment

jobs:
  run-opentofu:
    runs-on: ubuntu-latest
    environment: development

    permissions:
      id-token: write
      contents: read

    steps:
      - name: Checkout Repository
        uses: actions/checkout@v3

      - name: Generate GitHub Actions OIDC ID Token
        id: generate-oidc-token
        run: |
          RESPONSE=$(curl -s -X POST  -H "Authorization: Bearer $ACTIONS_ID_TOKEN_REQUEST_TOKEN" "$ACTIONS_ID_TOKEN_REQUEST_URL")

          OIDC_ID_TOKEN=$(echo $RESPONSE | jq -r '.value')
          
          if [ -z "$OIDC_ID_TOKEN" ] || [ "$OIDC_ID_TOKEN" == "null" ]; then
            echo "Error: Failed to retrieve OIDC token."
            exit 1
          fi
          
          echo "OIDC_ID_TOKEN=$OIDC_ID_TOKEN" >> $GITHUB_ENV
          echo "OIDC_ID_TOKEN extracted successfully."

      - name: Exchange OIDC ID Token for Scalr Token
        id: exchange-token
        run: |
          RESPONSE=$(curl -s -w "%{http_code}" -X POST \
            -H "Content-Type: application/json" \
            -d '{"id_token": "'${{ env.OIDC_ID_TOKEN }}'", "service-account-email": "'${{ env.SA_EMAIL }}'"}' \
            "https://${{ env.SCALR_HOST }}/api/iacp/v3/service-accounts/assume")

          HTTP_BODY=$(echo "$RESPONSE" | sed '$ d')
          HTTP_CODE=$(echo "$RESPONSE" | tail -n1)

          echo "Scalr Response: $HTTP_BODY"
          echo "HTTP Status Code: $HTTP_CODE"

          if [ "$HTTP_CODE" -ne 200 ]; then
            echo "Error: Failed to exchange token. HTTP status: $HTTP_CODE"
            exit 1
          fi
          SCALR_TOKEN=$(echo "$HTTP_BODY" | jq -r '."access-token"')
          if [ -z "$SCALR_TOKEN" ] || [ "$SCALR_TOKEN" == "null" ]; then
            echo "Error: Token not found in response."
            exit 1
          fi
          
          echo "SCALR_TOKEN=$SCALR_TOKEN" >> $GITHUB_ENV
          echo "Scalr token retrieved successfully."

      - name: Install OpenTofu
        uses: opentofu/setup-opentofu@v1
        with:
          cli_config_credentials_hostname: ${{ env.SCALR_HOST }}
          cli_config_credentials_token: ${{ env.SCALR_TOKEN }}

      - name: Generate Override Configuration
        run: |
          cat <<EOF > override.tf
          terraform {
            backend "remote" {
              hostname = "${{ secrets.SCALR_HOST }}"
              organization = "${{ env.SCALR_ENVIRONMENT }}"
              workspaces {
                name = "${{ env.SCALR_WORKSPACE }}"
              }
            }
          }
          EOF
          echo "override.tf configuration generated successfully."

      - name: Initialize and Run OpenTofu
        run: |
          tofu init
          tofu plan
```

**Explanation:**
- The first step requests an OIDC token from GitHub Actions.
- The second step exchanges it for a Scalr access token.
- The third step sets up OpenTofu using the Scalr access token for authentication.
- The last step executes the plan operation in Scalr.

## Troubleshooting
- **401 Unauthorized:** Ensure the service account has the correct permissions.
- **403 Forbidden:** Check if the assume policy conditions match the GitHub repository and environment.
- **Invalid Token Errors:** Verify that the OIDC provider's URL and audience values are correctly set.

## Conclusion
By following these steps, you can securely authenticate and interact with the Scalr API using OIDC, eliminating the need for static credentials in your workflows. This ensures a more secure and automated authentication process for Opentofu operations.

