# Connecting from Gitlab CI/CD to Scalr API via OIDC

## Overview
As an administrator, you can connect to the Scalr API using OpenID Connect (OIDC) to eliminate the need for static credentials. This guide provides a step-by-step process to configure OIDC authentication using Scalr's public API, along with detailed explanations of each request and its parameters.

## Prerequisites
Before you begin, ensure you have:
- An existing Scalr account with administrative privileges.
- Generated static token for the initial setup of the OIDC.
- A registered service account in Scalr.
- A Gitlab repository with CI/CD enabled.

## Steps to Configure OIDC Authentication

### Step 1: Register a Workload Identity Provider
A workload identity provider allows Scalr to verify identity tokens issued by an external OIDC provider, such as Gitlab CI/CD pipelines. 

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
            "url": "https://gitlab.com",
            "allowed-audiences": [
                "https://gitlab.com/namespace"
            ],
            "name": "gitlab-oidc"
        }
    }
}
```

**Explanation:**
- `url`: The OIDC provider's token endpoint.
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
                    "claim": "project_path",
                    "value": "namespace/repository",
                    "operator": "eq"
                }
            ],
            "maximum-session-duration": 3600,
            "name": "gitlab"
        },
        "relationships": {
            "provider": {
                "data": {
                    "type": "workload-identity-providers",
                    "id": "widp-id"
                }
            }
        }
    }
}
```

**Explanation:**
- `claim-conditions`: Defines the conditions under which the identity provider can assume this service account.
  - `project_path`: Restricts access to a specific Gitlab repository.
- `maximum-session-duration`: Optional: Sets the session duration in seconds. Default: 3600 (1 hour).
- `relationships`: Links this policy to the previously registered identity provider.

### Step 3: Update Gitlab CI/CD Workflow
Once the assume policy is in place, modify your Gitlab CI/CD workflow to:
1. Obtain a Gitlab OIDC token.
2. Exchange it for a Scalr access token using the Gitlabs's ID token and `SCALR_SA_EMAIL`
3. Use the temporary access token to authenticate and perform OpenTofu operations.

#### Example Gitlab CI/CD workflow:

Review the [gitlab.ci.yml](./gitlab-ci.yml) file to see how it can be integrated into Gitlab CI/CD pipelines. 
The main part of the worflow is under [prepare-env.sh](./prepare-env.sh) file, which does 2 things:

1. Exchanges the Gitlabs's OIDC ID token for a Scalr temporary access token
2. Writes the access token to the well-know location to authorize Opentofu/Terraform CLI.

## Conclusion
By following these steps, you can securely authenticate and interact with the Scalr API using OIDC, eliminating the need for static credentials in your workflows. This ensures a more secure and automated authentication process for Opentofu operations.

