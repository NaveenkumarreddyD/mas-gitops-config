merge-key: "${ACCOUNT_ID}/${CLUSTER_ID}/${INSTANCE_ID}"

# SLSCfg/BASCfg read the secrets IBM's native postsync-update-sm jobs publish (no mas/ prefix):
#   DRO -> <account>/<cluster>/dro                 fields dro_url / dro_api_token / dro_ca_b64enc
#   SLS -> <account>/<cluster>/<instance>/sls      fields registration_key / ca_b64
# CAs are stored base64; AVP's "| base64decode" filter converts to PEM. SLS url is the internal
# service DNS (IBM does not publish it to SM).
ibm_mas_suite_configs:
  - mas_config_name: "${INSTANCE_ID}-sls-system"
    mas_config_chart: ibm-mas-sls-config
    mas_config_scope: system
    mas_workspace_id:
    mas_application_id:
    mas_config_kind: "slscfgs"
    mas_config_api_version: "config.mas.ibm.com"
    use_postdelete_hooks: true
    registration_key: "<path:${ACCOUNT_ID}/${CLUSTER_ID}/${INSTANCE_ID}/sls#registration_key>"
    url: "https://sls.mas-${INSTANCE_ID}-sls.svc"
    ca:
      crt: |
        <path:${ACCOUNT_ID}/${CLUSTER_ID}/${INSTANCE_ID}/sls#ca_b64 | base64decode>

  - mas_config_name: "${INSTANCE_ID}-bas-system"
    mas_config_chart: ibm-mas-bas-config
    mas_config_scope: system
    mas_workspace_id:
    mas_application_id:
    mas_config_kind: "bascfgs"
    mas_config_api_version: "config.mas.ibm.com"
    use_postdelete_hooks: true
    dro_endpoint_url: "<path:${ACCOUNT_ID}/${CLUSTER_ID}/dro#dro_url>"
    dro_contact:
      email: "${DRO_CONTACT_EMAIL}"
      first_name: "${DRO_CONTACT_FIRSTNAME}"
      last_name: "${DRO_CONTACT_LASTNAME}"
    dro_api_token: "<path:${ACCOUNT_ID}/${CLUSTER_ID}/dro#dro_api_token>"
    dro_ca:
      crt: |
        <path:${ACCOUNT_ID}/${CLUSTER_ID}/dro#dro_ca_b64enc | base64decode>

  - mas_config_name: "${INSTANCE_ID}-mongo-system"
    mas_config_chart: ibm-mas-mongo-config
    mas_config_scope: system
    mas_workspace_id:
    mas_application_id:
    mas_config_kind: "mongocfgs"
    mas_config_api_version: "config.mas.ibm.com"
    use_postdelete_hooks: true
    username: "<path:${ACCOUNT_ID}/${CLUSTER_ID}/${INSTANCE_ID}/mongo#username>"
    password: "<path:${ACCOUNT_ID}/${CLUSTER_ID}/${INSTANCE_ID}/mongo#password>"
    config:
      hosts:
        - host: "<path:${ACCOUNT_ID}/${CLUSTER_ID}/${INSTANCE_ID}/mongo#host>"
          port: 27017
      configDb: admin
      authMechanism: DEFAULT
      retryWrites: false
      credentials:
        secretName: "system-mongo-credentials"
    certificates:
      - alias: ca
        crt: "<path:${ACCOUNT_ID}/${CLUSTER_ID}/${INSTANCE_ID}/mongo#ca.crt>"

  - mas_config_name: "${INSTANCE_ID}-jdbc-system"
    mas_config_chart: ibm-jdbc-config
    mas_config_scope: system
    mas_workspace_id:
    mas_application_id:
    mas_config_kind: "jdbccfgs"
    mas_config_api_version: "config.mas.ibm.com"
    use_postdelete_hooks: true
    jdbc_type: external
    jdbc_instance_name: oracle
    jdbc_instance_username: "<path:${ACCOUNT_ID}/${CLUSTER_ID}/${INSTANCE_ID}/jdbc-system#username>"
    jdbc_instance_password: "<path:${ACCOUNT_ID}/${CLUSTER_ID}/${INSTANCE_ID}/jdbc-system#password>"
    jdbc_connection_url: "<path:${ACCOUNT_ID}/${CLUSTER_ID}/${INSTANCE_ID}/jdbc-system#jdbc_url>"
    jdbc_ssl_enabled: false
    system_suite_jdbccfg_labels:
      mas.ibm.com/configScope: system
      mas.ibm.com/instanceId: ${INSTANCE_ID}
