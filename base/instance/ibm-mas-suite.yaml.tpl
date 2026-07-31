merge-key: "${ACCOUNT_ID}/${CLUSTER_ID}/${INSTANCE_ID}"

ibm_mas_suite:
  cert_manager_namespace: "cert-manager"
  ibm_entitlement_key: "<path:secret/data/${ACCOUNT_ID}/${CLUSTER_ID}/entitlement#image_pull_secret_b64>"
  domain: ${MAS_DOMAIN}
  mas_channel: "${MAS_CHANNEL}"
  icr_cp: "cp.icr.io/cp"
  icr_cp_open: "icr.io/cpopen"
  mas_install_plan: Automatic
  mas_feature_usage: true
  mas_deployment_progression: true
  mas_usability_metrics: true
  mas_annotations:
    mas.ibm.com/operationalMode: ${OPERATIONAL_MODE}
  mas_manual_cert_mgmt: true
  # IBM's Suite chart is the sole owner of the MAS core public certificate.
  tls_cert: "<path:secret/data/${ACCOUNT_ID}/${CLUSTER_ID}/${INSTANCE_ID}/certs/public#tls_crt_b64>"
  tls_key:  "<path:secret/data/${ACCOUNT_ID}/${CLUSTER_ID}/${INSTANCE_ID}/certs/public#tls_key_b64>"
  ca_cert:  "<path:secret/data/${ACCOUNT_ID}/${CLUSTER_ID}/${INSTANCE_ID}/certs/public#ca_crt_b64>"
