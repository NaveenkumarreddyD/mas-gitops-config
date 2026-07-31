merge-key: "${ACCOUNT_ID}/${CLUSTER_ID}/${INSTANCE_ID}"

ibm_mas_masapp_configs:
  - mas_app_id: manage
    mas_app_namespace: mas-${INSTANCE_ID}-manage
    mas_app_ws_apiversion: apps.mas.ibm.com/v1
    mas_app_ws_kind: ManageWorkspace
    mas_workspace_id: ${WORKSPACE_ID}

    # The Manage install chart owns the public certificate secret.
    mas_manual_cert_mgmt: false
    run_sanity_test: false

    # Per-bundle Liberty server.xml fragment (JMS client config for ui + cron). The chart creates a
    # Secret per entry (data.server-custom.xml = base64); the ui/cron serverBundles reference it via
    # additionalServerConfig.secretName. Set it ONCE in config (NOT the UI — ArgoCD reverts UI edits).
    # Base64 is env-provided (cluster-specific: embeds the jms service host).
    mas_app_server_bundles_combined_add_server_config:
      ${WORKSPACE_ID}-manage-d--sb0--asc--sn:   "${MANAGE_UI_ASC_B64}"
      ${WORKSPACE_ID}-manage-d--sb1--asc--sn: "${MANAGE_CRON_ASC_B64}"
{{IF_FALSE MANAGE_AUTO_GENERATE_ENCRYPTION_KEYS}}
    global_secrets:
      MXE_SECURITY_CRYPTO_KEY: "<path:secret/data/${ACCOUNT_ID}/${CLUSTER_ID}/${INSTANCE_ID}/manage-crypto#cryptoKey>"
      MXE_SECURITY_CRYPTOX_KEY: "<path:secret/data/${ACCOUNT_ID}/${CLUSTER_ID}/${INSTANCE_ID}/manage-crypto#cryptoxKey>"
{{END_IF}}

    mas_appws_spec:
      bindings:
        jdbc: system
      components:
        base:
          version: latest
        # hse = Health, Safety & Environment Manager (the rebranded Maximo for Oil & Gas).
        # It ships the psdi.plusg.* classes (e.g. PlusGPersonSet). REQUIRED to match prod, whose
        # data registers PERSON/other objects to plusg classes -> without hse the server can't
        # load PlusGPersonSet at startup and crashes. Must match prod components exactly.
        hse:
          version: latest
        oracleadapter:
          version: latest
        utilities:
          version: latest
        spatial:
          version: latest
      settings:
        aio:
          install: false
        db:
          dbSchema: ${DB_SCHEMA}
          encryptionSecret: ${WORKSPACE_ID}-manage-encryptionsecret
          maxinst:
            tableSpace: ${DB_TABLESPACE}
            indexSpace: ${DB_INDEXSPACE}
            demodata: false
            bypassUpgradeVersionCheck: false
        languages:
          baseLang: EN
          secondaryLangs: []
        customizationList: []
        # Per IBM docs the pod resources block lives at settings.resources (NOT
        # settings.deployment.resources). At the wrong path the ManageWorkspace structural
        # schema prunes it on apply -> live CR never gets it -> permanent ArgoCD OutOfSync.
        resources:
          serverBundles:
            requests: { cpu: "1", memory: "4Gi" }
            limits:   { cpu: "6", memory: "10Gi" }
        deployment:
          autoGenerateEncryptionKeys: ${MANAGE_AUTO_GENERATE_ENCRYPTION_KEYS}
          defaultJMS: false
          serverTimezone: ${SERVER_TIMEZONE}
          persistentVolumes:
            - { pvcName: jmsstore,  mountPath: /jmsstore,  size: ${MANAGE_JMSSTORE_SIZE:-20Gi},  storageClassName: ${RWX_STORAGE_CLASS}, accessModes: [ReadWriteMany] }
            - { pvcName: globaldir, mountPath: /globaldir, size: ${MANAGE_GLOBALDIR_SIZE:-20Gi}, storageClassName: ${RWX_STORAGE_CLASS}, accessModes: [ReadWriteMany] }
          serverBundles:
            - name: ui
              bundleType: ui
              isDefault: true
              isMobileTarget: true
              replica: 2
              routeSubDomain: ui
              additionalServerConfig: { secretName: ${WORKSPACE_ID}-manage-d--sb0--asc--sn }
            - name: cron
              bundleType: cron
              isDefault: false
              replica: 1
              routeSubDomain: cron
              additionalServerConfig: { secretName: ${WORKSPACE_ID}-manage-d--sb1--asc--sn }
            - name: mea
              bundleType: mea
              isDefault: false
              isUserSyncTarget: true
              replica: 2
              routeSubDomain: mea
            - name: report
              bundleType: report
              isDefault: false
              replica: 1
              routeSubDomain: report
            - name: jms
              bundleType: standalonejms
              isDefault: false
              replica: 1
              routeSubDomain: jms
