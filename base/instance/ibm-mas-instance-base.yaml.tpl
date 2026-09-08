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

# Publisher (write-scoped) static key. IBM's native postsync-update-sm job for SLS
# (instance-level) reads sm.aws_* -> sm_aws_* to write the SLS registration to AWS SM.
sm:
  aws_access_key_id: "<path:${ACCOUNT_ID}/${CLUSTER_ID}/publisher#aws_access_key_id>"
  aws_secret_access_key: "<path:${ACCOUNT_ID}/${CLUSTER_ID}/publisher#aws_secret_access_key>"
