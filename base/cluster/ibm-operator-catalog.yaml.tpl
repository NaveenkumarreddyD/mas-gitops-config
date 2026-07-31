merge-key: "${ACCOUNT_ID}/${CLUSTER_ID}"

ibm_operator_catalog:
  mas_catalog_version: ${MAS_CATALOG_VERSION}
  mas_catalog_image: ${MAS_CATALOG_IMAGE}
  ibm_entitlement_key: "<path:secret/data/${ACCOUNT_ID}/${CLUSTER_ID}/entitlement#image_pull_secret_b64>"
