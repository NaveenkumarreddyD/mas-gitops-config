# Manage server.xml fragments (source of truth)

Human-editable Liberty `server.xml` fragments per environment. Edit these, then run
`./set-manage-asc.sh <env> --render` — it base64-encodes each file into the matching
`MANAGE_<BUNDLE>_ASC_B64` var in `envs/<env>.env` and re-renders.

Layout — `manage-asc/<env>/`:

| File | Bundle(s) | Kind |
|---|---|---|
| `ui-cron.xml` | ui + cron | JMS client |
| `mea.xml` | mea | JMS client |
| `report.xml` | report | JMS client |
| `jms.xml` | jms (standalonejms) | JMS **server** (messaging engine / queues) |

Only files that exist are applied; a missing file leaves that bundle at the operator default.
Client fragments embed the cluster's jms service host, so keep them per-env.
