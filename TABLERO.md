# Tablero

Copia de [Coucou](https://github.com/Louis-CFM/coucou), de Louis Raillé (licencia MIT, ver `LICENSE`).
Le suma un tablero grande al panel que baja de la muesca del MacBook, al estilo del
panel de referencia: estado general, sesiones, consumos, novedades, pendientes,
deploys y pushes, el MacBook y una barra de vigilantes.

## Cómo se abre

1. Pasa el mouse por la muesca y haz clic para abrir el panel.
2. Arriba a la izquierda, toca el ícono de los cuatro cuadros (al lado de la casita).
3. El panel crece y muestra el tablero. La casita vuelve a la vista normal de Coucou.

## Qué es real y qué es de muestra

| Tarjeta | Datos |
|---|---|
| Sesiones de Claude Code | Reales: las sesiones locales que ve Coucou (Ajustes › Agentes › Instalar hooks) |
| Consumos: Claude sesión y semana | Reales con Ajustes › Agentes › Uso del plan › Mostrar en el notch. El dato llega cuando corre Claude Code en el Mac; entre sesiones queda el último con su edad ("62% · 3 h") y vuelve a 0% cuando se reinicia el límite. Sin datos aún: "sin datos" |
| Consumos: Vercel | Deploys de las últimas 24 h sobre 100 (el límite diario de Vercel Hobby), con el token de Vercel |
| Consumos: GitHub CI | Cuántos repos tienen el CI de la rama principal en verde, con el token de GitHub |
| Actividad | Los últimos deploys de Vercel y el último push de cada repo con su CI |
| MacBook | Real: carga, memoria, disco y batería del Mac |
| Estado general y barra de vigilantes | Claude, GitHub, Vercel, batería y disco; solo los que tienen fuente conectada |
| Pendientes | Recordatorios de Apple sin terminar (botón "Usar mis Recordatorios" en la tarjeta): el check los marca hechos en Recordatorios y el reloj los esconde una hora en el tablero. Lo que se agrega en el iPhone o con Siri aparece en un minuto. Sin permiso, muestra |
| Novedades | Muestra |

Las tarjetas que todavía no tienen su fuente conectada llevan la etiqueta "muestra".
Las fuentes solo trabajan con el tablero abierto: el Mac se mide cada 5 s, Recordatorios
se lee cada minuto y Vercel y GitHub se consultan cada 2 min. Con el panel cerrado no gastan nada.

## Probarlo sin Xcode

Cada cambio en la rama `claude/tablero` lo compila un Mac de GitHub (`.github/workflows/tablero.yml`).

1. En GitHub, pestaña **Actions** › **Tablero (app para probar)** › la corrida más reciente en verde.
2. Abajo, en **Artifacts**, descarga **Coucou-Tablero** y descomprímelo (adentro viene `Coucou-Tablero.zip`: descomprímelo también).
3. Arrastra **Coucou.app** a Aplicaciones.
4. La primera vez: clic derecho › **Abrir** › Abrir. Si macOS no deja, Configuración del Sistema › Privacidad y seguridad › **Abrir de todas formas**. Pasa porque la app va firmada ad hoc, sin cuenta de desarrollador de Apple.

## Compilar en el MacBook

Requisitos de Coucou: macOS 15 o más nuevo y Xcode 16 o más nuevo (gratis en la App Store).

1. Descarga este repositorio (botón verde **Code > Download ZIP**) y descomprímelo.
2. Abre `NotchBuddy/NotchBuddy.xcodeproj` con doble clic.
3. Arriba, elige el esquema **NotchBuddy** y "My Mac", y presiona **⌘R**.

Si Xcode no encuentra algún archivo nuevo, regenera el proyecto como dice el README de
Coucou: `brew install xcodegen`, y dentro de la carpeta `NotchBuddy`, `xcodegen`.

Si algo no compila, copia el error de Xcode (panel de la izquierda, ícono del triángulo
rojo) y pégalo en el chat para corregirlo.

Al abrirlo por primera vez, Coucou ofrece engancharse a Claude Code para ver las
sesiones: modifica `~/.claude/settings.json` y guarda una copia antes.

## Dónde está el código

- `NotchBuddy/Sources/App/Tablero/TableroView.swift`: la vista y cada tarjeta.
- `NotchBuddy/Sources/App/Tablero/TableroDatos.swift`: las estructuras de datos y los datos de muestra (`TableroMuestra`).
- `NotchBuddy/Sources/App/Tablero/TableroFuentes.swift`: las fuentes reales (el Mac, Vercel, GitHub) y cómo se arma cada tarjeta.
- `NotchBuddy/Sources/App/Tablero/PendientesStore.swift`: la lista de pendientes.
- `NotchBuddy/Sources/App/Tablero/RecordatoriosLector.swift`: la lectura de Recordatorios (EventKit).
- Cambios en archivos de Coucou: `IslandTypes.swift` (vista `.tablero` y su tamaño),
  `IslandViewContent.swift` (qué vista pinta), `IslandRootView.swift` (botón y alto).

## Lo que sigue

1. Novedades: cargador, Wi-Fi, deploys y pushes del día.
2. Wi-Fi y respaldo (Time Machine) como vigilantes.
