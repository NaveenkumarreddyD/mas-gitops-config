merge-key: "${ACCOUNT_ID}/${CLUSTER_ID}/${INSTANCE_ID}"

account:
  id: ${ACCOUNT_ID}

region:
  id: ${REGION_ID}

cluster:
  id: ${CLUSTER_ID}
  url: ${CLUSTER_URL}
  nonshared: ""

instance:
  id: ${INSTANCE_ID}

# Required by the official IBM 8.4.2 instance-root templates. These stay empty; the
# Roles Anywhere publisher handles write-back.
sm:
  aws_access_key_id: ""
  aws_secret_access_key: ""
