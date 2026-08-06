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

    # Per-bundle Liberty server.xml fragment. The chart creates a Secret per entry
    # (data.server-custom.xml = base64) and each serverBundle references it via
    # additionalServerConfig.secretName. Set these ONCE in config (NOT the UI — ArgoCD reverts
    # UI edits). Base64 is env-provided per bundle (cluster-specific: embeds the jms service host).
    # ALL FIVE ARE OPT-IN: a bundle's secret + additionalServerConfig render ONLY when its env var
    # is set. Leave a var EMPTY to let the Manage operator manage that bundle with its defaults.
    #   sb0-sb3 = JMS *client* fragments (ui, cron, mea, report).
    #   sb4     = JMS *server* fragment (standalonejms — server-side messaging engine / custom queues).
    mas_app_server_bundles_combined_add_server_config:
{{IF_SET MANAGE_UI_ASC_B64}}
      ${WORKSPACE_ID}-manage-d--sb0--asc--sn: "${MANAGE_UI_ASC_B64}"
{{END_IF}}
{{IF_SET MANAGE_CRON_ASC_B64}}
      ${WORKSPACE_ID}-manage-d--sb1--asc--sn: "${MANAGE_CRON_ASC_B64}"
{{END_IF}}
{{IF_SET MANAGE_MEA_ASC_B64}}
      ${WORKSPACE_ID}-manage-d--sb2--asc--sn: "${MANAGE_MEA_ASC_B64}"
{{END_IF}}
{{IF_SET MANAGE_REPORT_ASC_B64}}
      ${WORKSPACE_ID}-manage-d--sb3--asc--sn: "${MANAGE_REPORT_ASC_B64}"
{{END_IF}}
{{IF_SET MANAGE_JMS_ASC_B64}}
      ${WORKSPACE_ID}-manage-d--sb4--asc--sn: "${MANAGE_JMS_ASC_B64}"
{{END_IF}}
{{IF_FALSE MANAGE_AUTO_GENERATE_ENCRYPTION_KEYS}}
    global_secrets:
      MXE_SECURITY_CRYPTO_KEY: "<path:secret/data/${ACCOUNT_ID}/${CLUSTER_ID}/${INSTANCE_ID}/manage-crypto#cryptoKey>"
      MXE_SECURITY_CRYPTOX_KEY: "<path:secret/data/${ACCOUNT_ID}/${CLUSTER_ID}/${INSTANCE_ID}/manage-crypto#cryptoxKey>"
{{END_IF}}
{{IF_IN MANAGE_ATTACHMENT_PROVIDER s3-migration,s3}}
    manage_attachment_s3_secret_name: ${WORKSPACE_ID}-manage-s3-secret
    manage_attachment_s3_access_secret_key: "<path:secret/data/${ACCOUNT_ID}/${CLUSTER_ID}/${INSTANCE_ID}/manage-cos#secret_key>"
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
{{IF_IN MANAGE_ATTACHMENT_PROVIDER filestorage}}
          attachmentProvider:
            providerSourceType: filestorage
            filestorage:
              defpath: ${MANAGE_DOCLINKS_PATH:-/doclinks}
{{END_IF}}
{{IF_IN MANAGE_ATTACHMENT_PROVIDER s3-migration,s3}}
          attachmentProvider:
            providerSourceType: s3
            s3:
              providerCredentials:
                s3Url: "<path:secret/data/${ACCOUNT_ID}/${CLUSTER_ID}/${INSTANCE_ID}/manage-cos#endpoint>"
                bucketName: "<path:secret/data/${ACCOUNT_ID}/${CLUSTER_ID}/${INSTANCE_ID}/manage-cos#bucket>"
                accessKey: "<path:secret/data/${ACCOUNT_ID}/${CLUSTER_ID}/${INSTANCE_ID}/manage-cos#access_key>"
                secretKey:
                  secretName: ${WORKSPACE_ID}-manage-s3-secret
{{END_IF}}
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
{{IF_IN MANAGE_ATTACHMENT_PROVIDER s3-migration,s3}}
          importedCerts:
            - alias: powerscale-s3-subca
              crt: |
                <path:secret/data/${ACCOUNT_ID}/${CLUSTER_ID}/${INSTANCE_ID}/manage-cos#powerscale_s3_subca>
            - alias: powerscale-s3-rootca
              crt: |
                <path:secret/data/${ACCOUNT_ID}/${CLUSTER_ID}/${INSTANCE_ID}/manage-cos#powerscale_s3_rootca>
{{END_IF}}
          persistentVolumes:
            - { pvcName: jmsstore,  mountPath: /jmsstore,  size: ${MANAGE_JMSSTORE_SIZE:-20Gi},  storageClassName: ${RWX_STORAGE_CLASS}, accessModes: [ReadWriteMany] }
            - { pvcName: globaldir, mountPath: /globaldir, size: ${MANAGE_GLOBALDIR_SIZE:-20Gi}, storageClassName: ${RWX_STORAGE_CLASS}, accessModes: [ReadWriteMany] }
{{IF_IN MANAGE_ATTACHMENT_PROVIDER filestorage,s3-migration}}
            - { pvcName: doclinks, mountPath: ${MANAGE_DOCLINKS_PATH:-/doclinks}, size: ${MANAGE_DOCLINKS_SIZE:-100Gi}, storageClassName: ${RWX_STORAGE_CLASS}, accessModes: [ReadWriteMany] }
{{END_IF}}
          serverBundles:
            - name: ui
              bundleType: ui
              isDefault: true
              isMobileTarget: true
              replica: 2
              routeSubDomain: ui
{{IF_SET MANAGE_UI_ASC_B64}}
              additionalServerConfig: { secretName: ${WORKSPACE_ID}-manage-d--sb0--asc--sn }
{{END_IF}}
            - name: cron
              bundleType: cron
              isDefault: false
              replica: 1
              routeSubDomain: cron
{{IF_SET MANAGE_CRON_ASC_B64}}
              additionalServerConfig: { secretName: ${WORKSPACE_ID}-manage-d--sb1--asc--sn }
{{END_IF}}
            - name: mea
              bundleType: mea
              isDefault: false
              isUserSyncTarget: true
              replica: 2
              routeSubDomain: mea
{{IF_SET MANAGE_MEA_ASC_B64}}
              additionalServerConfig: { secretName: ${WORKSPACE_ID}-manage-d--sb2--asc--sn }
{{END_IF}}
            - name: report
              bundleType: report
              isDefault: false
              replica: 1
              routeSubDomain: report
{{IF_SET MANAGE_REPORT_ASC_B64}}
              additionalServerConfig: { secretName: ${WORKSPACE_ID}-manage-d--sb3--asc--sn }
{{END_IF}}
            - name: jms
              bundleType: standalonejms
              isDefault: false
              replica: 1
              routeSubDomain: jms
{{IF_SET MANAGE_JMS_ASC_B64}}
              additionalServerConfig: { secretName: ${WORKSPACE_ID}-manage-d--sb4--asc--sn }
{{END_IF}}
