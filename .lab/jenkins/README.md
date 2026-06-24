# Jenkins pipelines

Solo existen dos pipelines soportados:

- `Jenkinsfile.generalist`: analisis DevSecOps completo.
- `Jenkinsfile.monitoring.generalist`: reevaluacion periodica de inventarios.

Los jobs Jenkins deben usar esas rutas como `Script Path`.

La plataforma compartida es propietaria de los scripts comunes:

```text
scripts/
├── catalog/
├── ci/
├── integration/
└── monitoring/
```

El contrato y las acciones especificas del proyecto estan integrados en
`Jenkinsfile.generalist`; el pipeline no carga `project.env` ni delega en
`project.sh`. Jenkins tampoco depende de scripts instalados manualmente en
`/opt/devsecops-lab/bin`.

## Integracion con la plataforma

El ETL se ejecuta en un contenedor efimero de `cipherbit-appsec-ingestor`. Jenkins no
necesita instalar el paquete Python del ingestor ni publicar PostgreSQL.

Credenciales requeridas:

- `devsecops-ingestor-db-password`: `Secret file` con la clave exclusiva de
  `cipherbit_ingestor`.
- `devsecops-secret-fingerprint-key`: `Secret file` con una clave maestra
  aleatoria de al menos 32 bytes. Jenkins expone únicamente su ruta temporal
  mediante `DEVSECOPS_SECRET_FINGERPRINT_KEY_FILE`; el ingestor la utiliza para
  identidades HMAC de Gitleaks y no la persiste en PostgreSQL.
- `devsecops-jenkins-webhook-token`: `Secret file` compartido con FastAPI.
- `coverity-license`: `Secret file`, ya utilizado por los stages Coverity.

Propiedades globales recomendadas:

```text
DEVSECOPS_API_BASE_URL=http://127.0.0.1:3000/api/v1
DEVSECOPS_API_CONTAINER_BASE_URL=http://backend:8000/api/v1
INGESTOR_IMAGE=cipherbit-appsec-ingestor:local
DEVSECOPS_DOCKER_NETWORK=cipherbit_ingestion
```

Los dos Jenkinsfiles montan la credencial solamente durante el stage ETL y el
contenedor efímero la recibe en modo de solo lectura.

El usuario del agente dentro de los contenedores es `101:103`. Los directorios
`/opt/devsecops-lab/artifacts`, `/opt/devsecops-lab/monitoring`,
`/opt/devsecops-lab/imports` y `/opt/devsecops-lab/incoming-vuln-bundles`
deben tener los permisos requeridos por cada stage; los jobs no elevan a root
para corregir ownership.

El cron se define solo en `Jenkinsfile.monitoring.generalist`. No deben existir
cron adicionales ni timers de systemd que ejecuten importacion, reanalisis o
retencion en paralelo.

De forma transitoria, EMBA se ejecuta en el nodo Jenkins actual mediante
`agent any`, conservando la instalacion existente en `/opt/emba`. Para habilitar
`RUN_EMBA=true`, el usuario `jenkins` debe poder ejecutar sin interaccion el
comando EMBA y el `chown` usados por el pipeline. No deben ejecutarse ramas ni
pull requests no confiables con EMBA habilitado.

El objetivo de endurecimiento posterior es mover este stage a un agente
dedicado y restaurar `agent { label 'emba-isolated' }`.
