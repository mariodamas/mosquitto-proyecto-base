# DevSecOps project contract

The generic Jenkinsfiles under `.lab/jenkins/*generalist*` read this directory
as the project-specific contract.

For a new C/C++ embedded project, keep the Jenkinsfile stable and adapt:

- `project.env`: project metadata, main artifact, optional tool paths.
- `project.sh`: the single project adapter invoked by Jenkins.

Supported actions:

- `build`
- `codeql-configure`
- `codeql-build`
- `coverity-configure`
- `coverity-build`
- `fuzzing`
- `package-firmware`

The platform owns orchestration, persistence, monitoring, ingestion and
notifications. This directory only describes how this repository builds and
produces project-specific evidence.

The Jenkinsfile treats `.lab/sca/manual-manifest.cdx.json` as a project input
because Mosquitto has curated vendored dependency evidence. Other projects can
point `MANUAL_MANIFEST_PATH` to their own manifest, or set
`MANUAL_MANIFEST_REQUIRED=false`.
