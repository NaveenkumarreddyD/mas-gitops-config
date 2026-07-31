merge-key: "${ACCOUNT_ID}/${CLUSTER_ID}/${INSTANCE_ID}"

ibm_suite_app_manage_install:
  ibm_entitlement_key: "<path:secret/data/${ACCOUNT_ID}/${CLUSTER_ID}/entitlement#image_pull_secret_b64>"
  mas_app_id: manage
  mas_edition: ${MAS_EDITION}
  mas_app_namespace: mas-${INSTANCE_ID}-manage
  mas_app_channel: "${MAS_APP_CHANNEL}"
  mas_app_catalog_source: ibm-operator-catalog
  mas_app_api_version: apps.mas.ibm.com/v1
  mas_app_kind: ManageApp
  mas_app_install_plan: Automatic
  run_sync_hooks: false
  mas_manual_cert_mgmt: true
  public_tls_secret_name: "${INSTANCE_ID}-${WORKSPACE_ID}-cert-public-81"
  tls_cert: "<path:secret/data/${ACCOUNT_ID}/${CLUSTER_ID}/${INSTANCE_ID}/certs/public#tls_crt_b64>"
  tls_key: "<path:secret/data/${ACCOUNT_ID}/${CLUSTER_ID}/${INSTANCE_ID}/certs/public#tls_key_b64>"
  ca_cert: "<path:secret/data/${ACCOUNT_ID}/${CLUSTER_ID}/${INSTANCE_ID}/certs/public#ca_crt_b64>"
  mas_app_spec: {}
