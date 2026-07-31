merge-key: "${ACCOUNT_ID}/${CLUSTER_ID}/${INSTANCE_ID}"

ibm_mas_suite_configs:
  - mas_config_name: "${INSTANCE_ID}-sls-system"
    mas_config_chart: ibm-mas-sls-config
    mas_config_scope: system
    mas_workspace_id:
    mas_application_id:
    mas_config_kind: "slscfgs"
    mas_config_api_version: "config.mas.ibm.com"
    use_postdelete_hooks: true
    registration_key: "<path:secret/data/${ACCOUNT_ID}/${CLUSTER_ID}/${INSTANCE_ID}/sls#registration_key>"
    url: "<path:secret/data/${ACCOUNT_ID}/${CLUSTER_ID}/${INSTANCE_ID}/sls#url>"
    ca:
      crt: "<path:secret/data/${ACCOUNT_ID}/${CLUSTER_ID}/${INSTANCE_ID}/sls#ca.crt>"

  - mas_config_name: "${INSTANCE_ID}-bas-system"
    mas_config_chart: ibm-mas-bas-config
    mas_config_scope: system
    mas_workspace_id:
    mas_application_id:
    mas_config_kind: "bascfgs"
    mas_config_api_version: "config.mas.ibm.com"
    use_postdelete_hooks: true
    dro_endpoint_url: "<path:secret/data/${ACCOUNT_ID}/${CLUSTER_ID}/dro#url>"
    dro_contact:
      email: "${DRO_CONTACT_EMAIL}"
      first_name: "${DRO_CONTACT_FIRSTNAME}"
      last_name: "${DRO_CONTACT_LASTNAME}"
    dro_api_token: "<path:secret/data/${ACCOUNT_ID}/${CLUSTER_ID}/dro#api_token>"
    dro_ca:
      crt: "<path:secret/data/${ACCOUNT_ID}/${CLUSTER_ID}/dro#ca.crt>"

  - mas_config_name: "${INSTANCE_ID}-mongo-system"
    mas_config_chart: ibm-mas-mongo-config
    mas_config_scope: system
    mas_workspace_id:
    mas_application_id:
    mas_config_kind: "mongocfgs"
    mas_config_api_version: "config.mas.ibm.com"
    use_postdelete_hooks: true
    username: "<path:secret/data/${ACCOUNT_ID}/${CLUSTER_ID}/${INSTANCE_ID}/mongo#username>"
    password: "<path:secret/data/${ACCOUNT_ID}/${CLUSTER_ID}/${INSTANCE_ID}/mongo#password>"
    config:
      hosts:
        - host: "<path:secret/data/${ACCOUNT_ID}/${CLUSTER_ID}/${INSTANCE_ID}/mongo#host>"
          port: 27017
      configDb: admin
      authMechanism: DEFAULT
      retryWrites: false
      credentials:
        secretName: "system-mongo-credentials"
    certificates:
      - alias: ca
        crt: "<path:secret/data/${ACCOUNT_ID}/${CLUSTER_ID}/${INSTANCE_ID}/mongo#ca.crt>"

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
    jdbc_instance_username: "<path:secret/data/${ACCOUNT_ID}/${CLUSTER_ID}/${INSTANCE_ID}/jdbc-system#username>"
    jdbc_instance_password: "<path:secret/data/${ACCOUNT_ID}/${CLUSTER_ID}/${INSTANCE_ID}/jdbc-system#password>"
    jdbc_connection_url: "<path:secret/data/${ACCOUNT_ID}/${CLUSTER_ID}/${INSTANCE_ID}/jdbc-system#jdbc_url>"
    jdbc_ssl_enabled: false
    system_suite_jdbccfg_labels:
      mas.ibm.com/configScope: system
      mas.ibm.com/instanceId: ${INSTANCE_ID}
