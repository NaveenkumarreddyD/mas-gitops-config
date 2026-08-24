merge-key: "${ACCOUNT_ID}/${CLUSTER_ID}"

account:
  id: ${ACCOUNT_ID}

region:
  id: ${REGION_ID}

cluster:
  id: ${CLUSTER_ID}
  url: ${CLUSTER_URL}
  nonshared: ""

# Required by the official IBM 8.4.2 root templates, which reference .Values.sm.*
# unconditionally. These stay empty; the Roles Anywhere publisher handles write-back.
sm:
  aws_access_key_id: ""
  aws_secret_access_key: ""

custom_labels:
  environment: ${CLUSTER_ID}
  platform: openshift
  gitops-owner: devops
