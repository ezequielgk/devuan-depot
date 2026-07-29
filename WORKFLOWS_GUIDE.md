# Guía de Ejecución de GitHub Actions

Este documento explica el orden correcto en el que deben ejecutarse los flujos de trabajo (workflows) en GitHub Actions para asegurar que todas las dependencias se construyan correctamente y el repositorio funcione sin problemas.

## Orden de Construcción (Build Order)

Dado que algunos paquetes dependen de otros para compilarse o para ejecutarse, es **crítico** seguir este orden si se está reconstruyendo el repositorio desde cero, o si hay actualizaciones masivas.

### 1. Librerías Base (Backports)
**Workflow:** `Build Libraries` -> Seleccionar paquete: `backports`
Los backports (`wayland`, `libdrm`, `pixman`, etc.) son los cimientos del sistema. Muchos paquetes modernos necesitan versiones recientes de estas librerías que no se encuentran en la versión estable de Devuan/Debian. Deben compilarse y publicarse primero para que estén disponibles en el entorno de build de los siguientes paquetes.

### 2. Librerías Core (Wayland)
**Workflow:** `Build Libraries`
Estas son las librerías específicas del ecosistema Wayland que utilizan los compositores.
- Seleccionar: `wlroots`
- Seleccionar: `scenefx` (Depende de wlroots)
- Seleccionar: `xwayland-satellite` (Independiente, pero útil construirlo aquí)

### 3. Window Managers (Compositores)
**Workflow:** `Build Window Managers`
Una vez que `wlroots`, `scenefx` y los `backports` están publicados en el repositorio `gh-pages`, los gestores de ventanas pueden compilarse correctamente obteniéndolos mediante `apt`.
- Seleccionar: `swayfx`
- Seleccionar: `niri`
- Seleccionar: `mangowc`

### 4. Aplicaciones
**Workflow:** `Build Apps`
Las aplicaciones suelen ser hojas en el árbol de dependencias, por lo que pueden compilarse al final o de manera completamente independiente en cualquier momento.
- Seleccionar: `foot`
- Seleccionar: `concord`
- Seleccionar: `pcmanfm-qt`
- Seleccionar: `mullvad-libre`
- Seleccionar: `portproton`

---

## Workflows de Mantenimiento

Los flujos de mantenimiento no construyen paquetes, sino que mantienen la salud del repositorio `apt`. 

### `Mantenimiento: Buscar Actualizaciones Upstream`
- **Uso:** Se ejecuta de forma automática (con un cron schedule) los días Lunes y Jueves.
- **Función:** Ejecuta un script en Python que revisa las APIs de GitHub buscando nuevos tags de los paquetes originales. Si hay actualizaciones, te crea un "Issue" en el repositorio avisándote para que vayas y dispares el Build correspondiente.

### `Mantenimiento: Limpiar Repositorio`
- **Uso:** Manual. Ejecutar cuando el pool del repositorio empiece a ocupar demasiado espacio o haya demasiadas versiones antiguas.
- **Función:** Analiza los `.deb` publicados. Te permite elegir si limpiar el pool (`~devuandepot`), los legacy (paquetes huérfanos sin el sufijo) o los backports (upstream sid). Por defecto guarda las últimas 2 versiones y elimina el resto. Siempre usa `dry-run: true` primero para verificar qué va a borrar.

### `Mantenimiento: Forzar Regeneración de Índices`
- **Uso:** Manual. Solo para emergencias.
- **Función:** Si alguna vez un usuario reporta errores como *Hash Sum mismatch* o *404 Not Found* al hacer `apt-get update`, ejecuta este workflow. Volverá a escanear todos los `.deb` existentes y reconstruirá los archivos `Packages`, `Release` e `InRelease` firmándolos con tu llave GPG.

### `Sistema: Deploy GitHub Pages`
- **Uso:** Automático.
- **Función:** Cada vez que uno de los workflows de Build o Mantenimiento hace un `git push` a la rama `gh-pages`, GitHub ejecuta este workflow en segundo plano para publicar los archivos estáticos y que sean accesibles vía web (para `apt`). No necesitas tocarlo.
