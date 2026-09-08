merge-key: "${ACCOUNT_ID}/${CLUSTER_ID}"

account:
  id: ${ACCOUNT_ID}

region:
  id: ${REGION_ID}

cluster:
  id: ${CLUSTER_ID}
  url: ${CLUSTER_URL}
  nonshared: ""

# Publisher (write-scoped) static key. IBM's native postsync-update-sm jobs (DRO here,
# cluster-level) read sm.aws_* -> sm_aws_* and use it to write generated secrets to AWS SM.
# AVP resolves these before the chart b64-encodes them into the job's mounted Secret.
sm:
  aws_access_key_id: "<path:${ACCOUNT_ID}/${CLUSTER_ID}/publisher#aws_access_key_id>"
  aws_secret_access_key: "<path:${ACCOUNT_ID}/${CLUSTER_ID}/publisher#aws_secret_access_key>"

custom_labels:
  environment: ${CLUSTER_ID}
  platform: openshift
  gitops-owner: devops
