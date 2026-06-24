# DevSecOps project integration

The project-specific metadata and build, CodeQL, Coverity, fuzzing and firmware
packaging commands are defined directly in
`.lab/jenkins/Jenkinsfile.generalist`. The pipeline no longer loads a runtime
contract from this directory.

The platform continues to own orchestration, persistence, monitoring,
ingestion and notifications. Project inputs such as a curated manual component
manifest remain under `.lab` and are consumed by the relevant pipeline stage.
