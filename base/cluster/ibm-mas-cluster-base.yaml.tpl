merge-key: "${ACCOUNT_ID}/${CLUSTER_ID}"

account:
  id: ${ACCOUNT_ID}

region:
  id: ${REGION_ID}

cluster:
  id: ${CLUSTER_ID}
  url: ${CLUSTER_URL}
  nonshared: ""

# Required by IBM 8.4.0 root templates (they reference .Values.sm.* unconditionally;
# a missing block nil-pointers the whole cluster/instance root render). Empty strings
# are correct on the Vault patch: the patched jobs write to Vault and never use AWS SM.
sm:
  aws_access_key_id: ""
  aws_secret_access_key: ""

custom_labels:
  environment: ${CLUSTER_ID}
  platform: openshift
  gitops-owner: devops
