# DevSecOps project contract

The generic Jenkinsfiles under `.lab/jenkins/*generalist*` read this directory
as the project-specific contract.

For a new C/C++ embedded project, keep the Jenkinsfile stable and adapt:

- `project.env`: project metadata, main artifact, optional tool paths.
- `build.sh`: build actions used by normal CI, CodeQL and Coverity.
- `fuzzing.sh`: optional fuzzing workflow; remove it or leave it absent when the
  project has no harnesses.
- `package-firmware.sh`: optional firmware/rootfs packaging hook for EMBA.

Required build actions:

- `build`
- `codeql-configure`
- `codeql-build`
- `coverity-configure`
- `coverity-build`

The Jenkinsfile treats `.lab/sca/vendor-manifest.cdx.json` as a project input
because Mosquitto has curated vendored dependency evidence. Other projects can
point `VENDOR_MANIFEST_PATH` to their own manifest, or set
`VENDOR_MANIFEST_REQUIRED=false`.
