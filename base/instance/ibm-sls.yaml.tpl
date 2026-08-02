merge-key: "${ACCOUNT_ID}/${CLUSTER_ID}/${INSTANCE_ID}"

ibm_sls:
  sls_channel: "${SLS_CHANNEL}"
  sls_install_plan: Automatic
  sls_entitlement_file: "<path:secret/data/${ACCOUNT_ID}/${CLUSTER_ID}/${INSTANCE_ID}/license#license_file>"
  ibm_entitlement_key: "<path:secret/data/${ACCOUNT_ID}/${CLUSTER_ID}/entitlement#image_pull_secret_b64>"
  icr_cp_open: "icr.io/cpopen"
  run_sync_hooks: true
  vault_addr: "https://vault-active.vault.svc.cluster.local:8200"
  vault_writer_role: "mas-gitops-writer"
  vault_kv_mount: "secret"

  mongodb_provider: community
  sls_mongo_username: "<path:secret/data/${ACCOUNT_ID}/${CLUSTER_ID}/${INSTANCE_ID}/sls-mongo#username>"
  sls_mongo_password: "<path:secret/data/${ACCOUNT_ID}/${CLUSTER_ID}/${INSTANCE_ID}/sls-mongo#password>"
  sls_mongo_secret_name: sls-mongo-credentials

  mongo_spec:
    authMechanism: DEFAULT
    configDb: admin
    secretName: sls-mongo-credentials
    retryWrites: false
    nodes:
      - host: "<path:secret/data/${ACCOUNT_ID}/${CLUSTER_ID}/${INSTANCE_ID}/mongo#host>"
        port: 27017
    certificates:
      # SLS trusts the same Mongo CA used by the MAS MongoCfg.
      - alias: mongoca
        crt: "<path:secret/data/${ACCOUNT_ID}/${CLUSTER_ID}/${INSTANCE_ID}/mongo#ca.crt>"
