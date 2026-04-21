# 06_validate_sca_owasp_depcheck.sh - Guía de Implementación

## Descripción General

Script de validación de SCA (Software Composition Analysis) para análisis de dependencias vendorized usando **OWASP Dependency Check** en lugar de Snyk.

## Cambios Principales vs Snyk

| Aspecto | Snyk | OWASP Dependency Check |
|---------|------|------------------------|
| **Autenticación** | Requiere SNYK_TOKEN | Sin autenticación (gratuito) |
| **Instalación** | npm install -g snyk | Descarga binario + Java 8+ |
| **Base de Datos** | Snyk's proprietary DB | NVD (NIST) + CVE data |
| **Costo** | Freemium (limitado) | 100% Gratuito, Open Source |
| **C/C++ Analysis** | Fingerprinting (mejor para libs conocidas) | CPE matching + hashing (mejor para versioned archives) |
| **Velocidad** | Rápido | Más lento (descarga NVD en primer run) |
| **Format Salida** | JSON propietario | JSON estándar del proyecto |

## Instalación de OWASP Dependency Check

### En Windows PowerShell

```powershell
# Opción 1: Descargar binario precompilado
$url = "https://github.com/jeremylong/DependencyCheck_Doc/releases/download/v8.4.2/dependency-check-8.4.2-win.zip"
$dest = "C:\tools\dependency-check"
Invoke-WebRequest -Uri $url -OutFile "depcheck.zip"
Expand-Archive -Path "depcheck.zip" -DestinationPath $dest
# Agregar a PATH: C:\tools\dependency-check\bin

# Opción 2: Si tienes Chocolatey instalado
choco install dependencycheck
```

### En Linux/macOS

```bash
# Opción 1: Descarga manual
wget https://github.com/jeremylong/DependencyCheck_Doc/releases/download/v8.4.2/dependency-check-8.4.2-release.zip
unzip dependency-check-8.4.2-release.zip
export PATH="$PATH:$(pwd)/dependency-check/bin"

# Opción 2: Brew (macOS)
brew install dependency-check

# Opción 3: Apt (Debian/Ubuntu)
sudo apt-get install dependency-check
```

## Primer Uso (Descarga de Base de Datos)

La primera ejecución descargará la base de datos NVD (~1GB), lo que puede tardar 5-15 minutos:

```bash
./06_validate_sca_owasp_depcheck.sh
```

Ejecuciones posteriores serán más rápidas. Para actualizar la DB:

```bash
dependency-check.sh --updateonly
```

## Características del Script

### 1. **Detección Automática del Comando**
```bash
# Funciona en Windows (.bat) y Unix (.sh)
DEPCHECK_CMD="dependency-check.sh"
if ! command -v dependency-check.sh >/dev/null 2>&1; then
    DEPCHECK_CMD="dependency-check"
fi
```

### 2. **Scaneo de Vendored Dependencies**
- Analiza cJSON 1.7.14
- Analiza libwebsockets 2.4.2
- Genera reportes JSON separados para cada dependencia

### 3. **Análisis de Vulnerabilidades**
```bash
# Parsea JSON de Dependency Check para contar CVEs
# Extrae: nombre, CVE, severidad, CVSS score
depcheck_vuln_details()
```

### 4. **Logging Detallado**
- `.json` : Reporte estructurado (parseable)
- `.json.log` : Salida de consola completa (debugging)

## Variables de Entorno

```bash
# Directorio de resultados (default: .lab/validate/results)
export RESULTS_DIR="/custom/path"

# Umbral de severidad (default: MEDIUM)
export SEVERITY_THRESHOLD="HIGH"
```

## Códigos de Salida

```
0 = Éxito (sin vulnerabilidades o vulnerabilidades encontradas)
1 = Error (tool missing, vendor dir missing, tool error)
2 = Vulnerabilidades críticas (si implementas lógica adicional)
```

## Integración en Pipeline CI/CD

### GitHub Actions

```yaml
- name: Install Dependency Check
  run: |
    wget https://github.com/jeremylong/DependencyCheck_Doc/releases/download/v8.4.2/dependency-check-8.4.2-release.zip
    unzip dependency-check-8.4.2-release.zip
    export PATH="$PATH:$(pwd)/dependency-check/bin"

- name: Run OWASP Dependency Check
  run: |
    ./.lab/validate/06_validate_sca_owasp_depcheck.sh
```

### GitLab CI

```yaml
owasp-depcheck:
  image: owasp/dependency-check:latest
  script:
    - ./.lab/validate/06_validate_sca_owasp_depcheck.sh
  artifacts:
    paths:
      - .lab/validate/results/depcheck_*.json
```

## Limitaciones Conocidas

1. **Rendimiento**: Primera ejecución lenta (descarga NVD)
2. **Cobertura C/C++**: Depende de disponibilidad de CPE en NVD para esa versión específica
3. **Falsos Positivos**: Puede reportar CVEs de versiones similares
4. **Falsos Negativos**: Si la versión no está en NVD, reportará 0 vulnerabilidades

## Validación de Resultados

### Ejemplo de Reporte JSON

```json
{
  "reportSchema": "1.2.0",
  "version": "8.4.2",
  "dependencies": [
    {
      "packageString": "cjson-1.7.14",
      "vulnerabilities": [
        {
          "name": "CVE-2021-12345",
          "severity": "HIGH",
          "cvssv3": {
            "baseScore": 7.5
          }
        }
      ]
    }
  ]
}
```

## Comparación con Grype (Stage 05)

Ambos analizan el manifest `vendor-manifest.cdx.json`:
- **Grype**: Más rápido, mejor para búsqueda por hash
- **Dependency Check**: Más comprensivo con CPE matching
- **Ambos complementarios**: Usar en conjunto para máxima cobertura

## Referencias

- [OWASP Dependency Check Docs](https://jeremylong.github.io/DependencyCheck/)
- [NVD (National Vulnerability Database)](https://nvd.nist.gov/)
- [CPE Specification](https://nvlpubs.nist.gov/nistpubs/Legacy/SP/nistspecialpublication800-188.pdf)
- [Comparativa Herramientas SCA](./../docs/lab-decisions.md)
