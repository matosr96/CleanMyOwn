# Restauración de `repositorios_files_CleanMyOwn`

Pasos construidos sobre lo que realmente contiene esta rama.

## 1. Clonar el repositorio

```bash
git clone git@github.com:matosr96/CleanMyOwn.git
cd CleanMyOwn
```

## 2. Recuperar esta rama de backup

```bash
git fetch origin backup/pre-format-2026-08-16
git checkout backup/pre-format-2026-08-16 -- _local_backup
```

Esto trae `_local_backup/` al directorio sin cambiar de rama.

## 3. Volver al estado en que estaba el proyecto

```bash
git checkout main
```

El commit exacto que tenías era `37fa0ab358ca742c3a44b7ea6679cf26f58dff17`.

## 4. Restaurar variables de entorno

_Este proyecto no tenía archivos de entorno._

## 5. Restaurar configuración local y de agentes

```bash
rsync -a _local_backup/agent-config/ ./
rsync -a _local_backup/local-config/ ./
rsync -a _local_backup/ignored-important/ ./
```

## 6. Restaurar archivos no trackeados

```bash
rsync -a _local_backup/local-changes/untracked/ ./
```

## 7. Aplicar los cambios sin commitear

_No había cambios sin commitear._



## 9. Commits que nunca se subieron

```bash
git am _local_backup/local-changes/patches/commits-no-pusheados/*.patch
```

## Instalar dependencias y verificar

Instala las dependencias según corresponda al proyecto, arranca y comprueba que las
variables de entorno cargan. Contrasta `git status` con
`_local_backup/manifest/git-status.txt`: deberían describir el mismo estado.
