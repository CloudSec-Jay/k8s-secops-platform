# AWS Log Ingestion into Wazuh

This optional integration configures the Wazuh `aws-s3` module to poll an encrypted S3 bucket containing CloudTrail or GuardDuty data. The AWS infrastructure remains in the Cloud Operations repository and is not required for the self-hosted lab.

## Repository components

- [Cloud Operations detection pipeline](https://github.com/CloudSec-Jay/cloud-ops-engineering/tree/main/infrastructure/cloudformation): optional CloudTrail, GuardDuty, KMS, S3, and reader-identity source
- [`manager-configs/manager.conf`](../../manager-configs/manager.conf): example Wazuh `aws-s3` configuration with placeholders

## Data flow

```text
CloudTrail ----\
                -> KMS-encrypted S3 -> Wazuh aws-s3 module -> rules -> alerts
GuardDuty -----/
```

## Validate before deployment

```bash
cfn-lint cloud-ops-engineering/infrastructure/cloudformation/detection-pipeline.yaml
cfn-lint cloud-ops-engineering/infrastructure/cloudformation/detection-pipeline-pass2.yaml
checkov --directory cloud-ops-engineering/infrastructure/cloudformation
```

Create and inspect a CloudFormation change set in a non-production account. The main template creates named IAM resources, so deployment requires the appropriate IAM capability acknowledgement.

## Credential warning

The current external lab template creates an IAM user and access key and returns credential material through CloudFormation outputs. That design is not suitable for production and stack-output access must be treated as sensitive. Prefer a short-lived credential source supported by the Wazuh deployment environment.

Never place credentials directly in `manager.conf`, Kubernetes manifests, Git history, command output, or documentation. If the lab key is created, retrieve it through an authorized channel, create the runtime Secret outside Git, restrict access, and rotate or delete it after testing.

## Verification

After configuration and manager restart:

1. Confirm the Wazuh module starts without authentication or bucket-policy errors.
2. Generate a harmless test event in the non-production AWS account.
3. Verify delivery to the expected S3 prefix.
4. Verify Wazuh processes the object and creates the expected event.
5. Record redacted evidence and test the failure path with denied access.

Do not treat example bucket names, account placeholders, or log messages as deployment evidence.
