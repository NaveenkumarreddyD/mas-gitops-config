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

# Required by IBM 8.4.0 instance-root templates (unconditional .Values.sm.* references).
# Empty on the Vault patch — the patched jobs write to Vault, not AWS SM.
sm:
  aws_access_key_id: ""
  aws_secret_access_key: ""
