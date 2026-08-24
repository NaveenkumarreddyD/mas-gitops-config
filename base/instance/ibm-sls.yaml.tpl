merge-key: "${ACCOUNT_ID}/${CLUSTER_ID}/${INSTANCE_ID}"

ibm_sls:
  sls_channel: "${SLS_CHANNEL}"
  sls_install_plan: Automatic
  sls_entitlement_file: "<path:mas/${ACCOUNT_ID}/${CLUSTER_ID}/${INSTANCE_ID}/license#license_file>"
  ibm_entitlement_key: "<path:mas/${ACCOUNT_ID}/${CLUSTER_ID}/entitlement#image_pull_secret_b64>"
  icr_cp_open: "icr.io/cpopen"
  # The IBM 8.4.2 hook accepts static AWS keys. The platform publisher replaces only
  # that write-back step and publishes SLS automatically with IAM Roles Anywhere.
  run_sync_hooks: false

  mongodb_provider: community
  sls_mongo_username: "<path:mas/${ACCOUNT_ID}/${CLUSTER_ID}/${INSTANCE_ID}/sls-mongo#username>"
  sls_mongo_password: "<path:mas/${ACCOUNT_ID}/${CLUSTER_ID}/${INSTANCE_ID}/sls-mongo#password>"
  sls_mongo_secret_name: sls-mongo-credentials

  mongo_spec:
    authMechanism: DEFAULT
    configDb: admin
    secretName: sls-mongo-credentials
    retryWrites: false
    nodes:
      - host: "<path:mas/${ACCOUNT_ID}/${CLUSTER_ID}/${INSTANCE_ID}/mongo#host>"
        port: 27017
    certificates:
      # SLS trusts the same Mongo CA used by the MAS MongoCfg.
      - alias: mongoca
        crt: "<path:mas/${ACCOUNT_ID}/${CLUSTER_ID}/${INSTANCE_ID}/mongo#ca.crt>"
