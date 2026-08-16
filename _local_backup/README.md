# _local_backup — snapshot del estado local previo a formateo

**Esto NO es código de producción.** Es una fotografía del estado local de este
repositorio en la máquina de desarrollo, tomada justo antes de formatear el equipo.

| | |
|---|---|
| Fecha del respaldo | 2026-08-16 |
| Rama original | `main` |
| Commit original | `37fa0ab358ca742c3a44b7ea6679cf26f58dff17` |
| Rama de backup | `backup/pre-format-2026-08-16` |
| Remote | `git@github.com:matosr96/CleanMyOwn.git` |
| Ruta local original | `/Users/matos/repositorios/files/CleanMyOwn` |
| Visibilidad del repo | privado |

## Por qué existe

El equipo se formateó por completo. Todo lo que vivía únicamente en local —cambios sin
commitear, archivos no trackeados, variables de entorno, configuración de agentes— se
habría perdido. Esta rama lo conserva.

Es una **rama huérfana**: no tiene ancestro común con `main` ni con ninguna rama de
desarrollo, y no debe fusionarse con ellas jamás. Existe solo como archivo histórico.

## Qué contiene

| Carpeta | Contenido |
|---|---|
| `manifest/` | estado exacto de Git: status, ramas, remotes, log, stashes, config |
| `local-changes/patches/` | cambios sin commitear en formato patch, stashes, commits sin pushear |
| `local-changes/untracked/` | archivos reales que Git no estaba siguiendo |
| `env/` | variables de entorno |
| `agent-config/` | CLAUDE.md, AGENTS.md, .claude/, .cursor/, skills |
| `local-config/` | .npmrc, .nvmrc, xcconfig, .vscode y demás config local |
| `ignored-important/` | archivos ignorados por Git que sí hacen falta |
| `restoration/` | guía de restauración |

## Qué NO contiene

No duplica el código que ya está correctamente versionado en este repositorio: eso ya
está a salvo en `main` y en las ramas de desarrollo. Tampoco incluye `node_modules`,
builds, cachés ni archivos temporales.

## Aviso de seguridad

Este repositorio es **privado**. La carpeta \`env/\` contiene credenciales reales en
texto plano, conservadas a propósito para poder reconstruir el entorno. **No hagas
público este repositorio** sin eliminar antes esta rama y purgar su historial.

## Cómo restaurar

Ver `restoration/RESTAURACION.md`.
