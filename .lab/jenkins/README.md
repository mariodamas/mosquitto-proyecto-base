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

EMBA solo se ejecuta en un agente Jenkins con etiqueta `emba-isolated`. Ese
agente debe ser una maquina o VM dedicada, sin secretos ajenos al analisis y
con un `sudoers` limitado al wrapper/comando EMBA requerido.
