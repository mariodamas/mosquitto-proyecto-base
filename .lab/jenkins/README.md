# Jenkins pipelines

Solo existen dos pipelines soportados:

- `Jenkinsfile.generalist`: analisis DevSecOps completo.
- `Jenkinsfile.monitoring.generalist`: reevaluacion periodica de inventarios.

Los jobs Jenkins deben usar esas rutas como `Script Path`.

## Integracion con la plataforma

El ETL se ejecuta en un contenedor efimero de `cipherbit-ingestor`. Jenkins no
necesita instalar el paquete Python del ingestor ni publicar PostgreSQL.

Credenciales requeridas:

- `devsecops-ingestor-db-password`: `Secret file` con la clave exclusiva de
  `cipherbit_ingestor`.
- `devsecops-jenkins-webhook-token`: `Secret file` compartido con FastAPI.
- `coverity-license`: `Secret file`, ya utilizado por los stages Coverity.

Propiedades globales recomendadas:

```text
DEVSECOPS_API_BASE_URL=http://127.0.0.1:3000/api/v1
DEVSECOPS_API_CONTAINER_BASE_URL=http://host.docker.internal:3000/api/v1
INGESTOR_IMAGE=cipherbit-ingestor:local
DEVSECOPS_DOCKER_NETWORK=cipherbit_ingestion
```

El usuario del agente dentro de los contenedores es `101:103`. Los directorios
`/opt/devsecops-lab/artifacts` y `/opt/devsecops-lab/monitoring` deben ser
escribibles por ese UID/GID; los jobs no elevan a root para corregir ownership.

De forma transitoria, EMBA se ejecuta en el nodo Jenkins actual mediante
`agent any`, conservando la instalacion existente en `/opt/emba`. Para habilitar
`RUN_EMBA=true`, el usuario `jenkins` debe poder ejecutar sin interaccion el
comando EMBA y el `chown` usados por el pipeline. No deben ejecutarse ramas ni
pull requests no confiables con EMBA habilitado.

El objetivo de endurecimiento posterior es mover este stage a un agente
dedicado y restaurar `agent { label 'emba-isolated' }`.
