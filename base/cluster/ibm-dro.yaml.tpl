merge-key: "${ACCOUNT_ID}/${CLUSTER_ID}"

ibm_dro:
  dro_namespace: ${DRO_NAMESPACE}
  ibm_entitlement_key: "<path:secret/data/${ACCOUNT_ID}/${CLUSTER_ID}/entitlement#image_pull_secret_b64>"
  dro_install_plan: Automatic
  imo_install_plan: Automatic
  run_sync_hooks: true
  vault_addr: "http://vault-active.vault.svc.cluster.local:8200"
  vault_writer_role: "mas-gitops-writer"
  vault_kv_mount: "secret"
sm:
  aws_access_key_id: ""
  aws_secret_access_key: ""
