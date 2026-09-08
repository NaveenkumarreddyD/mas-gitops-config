merge-key: "${ACCOUNT_ID}/${CLUSTER_ID}"

ibm_dro:
  dro_namespace: ${DRO_NAMESPACE}
  ibm_entitlement_key: "<path:${ACCOUNT_ID}/${CLUSTER_ID}/entitlement#image_pull_secret_b64>"
  dro_install_plan: Automatic
  imo_install_plan: Automatic
  # IBM's native postsync-update-sm job publishes DRO to AWS Secrets Manager (path
  # <account>/<cluster>/dro). Publisher key comes from the sm.* block in
  # ibm-mas-cluster-base.yaml (same merge-key), so it is not repeated here.
  run_sync_hooks: true
