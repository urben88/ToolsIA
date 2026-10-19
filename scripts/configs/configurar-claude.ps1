# configurar-claude.ps1
# Instala la configuración global de Claude Code:
#   - ~/.claude/CLAUDE.md          (equipo, modos PLAN/EJECUTAR, delegar con contexto justo, memoria,
#                                    bitácora, carga mental, estilo)
#   - ~/.claude/agents/coder.md    (Sonnet - resolutor)
#   - ~/.claude/agents/explorer.md (Haiku  - investigador)
#   - ~/.claude/agents/helper.md   (Haiku  - ejecutor mecánico)
#   - ~/.claude/hooks/*.js         (nota de última sesión por proyecto con Haiku + aviso de contexto
#                                    + bitácora diaria en ~/.claude/bitacora/)
#     + registra los hooks SessionStart/SessionEnd/UserPromptSubmit en settings.json (requiere Node)
#     + bloquea los agentes integrados Explore y general-purpose (para delegar siempre en los propios)
# Hace copia de seguridad de lo que ya exista en ~/.claude/backup/<fecha>/
#
# Uso:  powershell -ExecutionPolicy Bypass -File .\configurar-claude.ps1

$ErrorActionPreference = 'Stop'
$claude  = Join-Path $env:USERPROFILE '.claude'
$agentes = Join-Path $claude 'agents'
$backup  = Join-Path $claude ('backup\' + (Get-Date -Format 'yyyy-MM-dd_HHmmss'))
$utf8    = New-Object System.Text.UTF8Encoding $false

New-Item -ItemType Directory -Force $agentes | Out-Null

function Guardar($ruta, $texto) {
    if (Test-Path $ruta) {
        New-Item -ItemType Directory -Force $backup | Out-Null
        Copy-Item $ruta (Join-Path $backup (Split-Path $ruta -Leaf)) -Force
    }
    [System.IO.File]::WriteAllText($ruta, (($texto -replace "`r`n", "`n") + "`n"), $utf8)
    Write-Host "OK  $ruta"
}

# ---------- CLAUDE.md ----------
Guardar (Join-Path $claude 'CLAUDE.md') @'
# Cómo trabajamos (global)

## Equipo
| Nivel | Agente | Modelo | Función |
|---|---|---|---|
| 1 | Sesión principal | Opus | Analiza y decide **dónde** profundizar. Orquesta y revisa. |
| 2 | `coder` | Sonnet | Resuelve: decide **cómo**, planifica, ejecuta, revisa. |
| 3 | `explorer` | Haiku | Investiga sin tocar nada: busca, lee, resume, comprueba, web. |
| 3 | `helper` | Haiku | Aplica cambios ya decididos con instrucciones exactas. |

Los agentes son **genéricos**: sirven para cualquier problema (código, datos, documentos, configuración, investigación).

**Regla de coste:** usa el agente más barato que pueda hacer la tarea. Haiku por defecto → Sonnet si hace falta criterio → Opus solo para analizar y decidir lo global.

## Modo PLAN / EJECUTAR (lo decide el usuario)
- **PLAN** ("plan", "planifica", "propón"…): investiga, prepara una propuesta y preséntala. **No cambies nada** hasta que el usuario diga que ejecutes.
- **EJECUTAR** ("ejecuta", "hazlo", "aplica"…): resuelve y verifica.
- **Sin indicación:** trabaja en PLAN y pregunta si ejecutar. Excepción: cambios triviales o preguntas rápidas.
- Indica el modo en cada encargo a `coder` ("Modo: PLAN" / "Modo: EJECUTAR"). `helper` solo se usa en EJECUTAR.

## Flujo de Opus
1. **Mapear barato:** lanza `explorer` en paralelo para entender el terreno. Lee tú solo los fragmentos clave.
2. **Focalizar:** identifica dónde está el riesgo, la causa o la complejidad real.
3. **Encargar a `coder`** un área acotada: objetivo, dónde profundizar, hipótesis, restricciones, criterio de terminado, modo y ruta de la memoria.
4. **Revisar** el resultado; usa `explorer` para verificar.

**Si falta contexto, pregunta al usuario** en vez de suponer: qué se busca, para quién, límites, prioridades… Agrupa las preguntas (pocas y concretas) y propón una opción por defecto en cada una. Si un agente devuelve dudas que solo el usuario puede resolver, trasládaselas.

Decide tú solo lo transversal (arquitectura global, varios módulos, contratos públicos, riesgos). `coder` decide lo local. Para iterar con un agente, **reanúdalo con SendMessage**.

## Delegar por defecto (Opus casi no ejecuta)
Opus piensa, decide y revisa. **El trabajo lo hacen los agentes.** Ante la duda, delega.
- **Buscar, leer, contar, comprobar, diagnosticar, web → `explorer`** (Haiku). Lanza varios en paralelo. Opus solo lee él mismo un archivo concreto ya localizado.
- **Cambios ya decididos → `helper`** (Haiku): ediciones, varios archivos, plantillas, actualizar docs o memoria.
- **Cambios que piden criterio → `coder`** (Sonnet): diseño local, depurar, scripts nuevos.
- Opus solo edita él mismo 1–2 líneas ya localizadas.
- **Usa siempre los agentes propios** (`explorer`, `helper`, `coder`). Nunca `Explore`, `Plan` ni `general-purpose`: corren con modelos más caros.

**Contexto justo (no compartas la conversación, comparte lo necesario).** Todo encargo usa esta plantilla:
```
Objetivo: …
Ya sabemos: … (para no repetir búsquedas)
Dónde: rutas, líneas, URLs o datos de entrada
No hagas: …
Contexto: <ruta>   (solo si existe; ver abajo)
Devuelve: máx. N líneas
```
- **Con repo y memoria:** `Contexto:` = la memoria del repo (ver sección siguiente).
- **Sin repo** (investigación, preguntas, documentos sueltos): el encargo lleva todo dentro. Si el contexto pasa de ~15 líneas o lo usan varios agentes, escríbelo **una vez** en `contexto.md` dentro del scratchpad de la sesión (o en `~/.claude/contexto/<tema>.md` si no hay scratchpad) y pasa la ruta.
- Actualiza el contexto solo en hitos (decisión, hallazgo, cambio), no en cada encargo. Solo lo escriben Opus o `helper`, nunca agentes en paralelo.
- **Para seguir con un agente, reanúdalo con `SendMessage`** (conserva lo que ya leyó). No uses fork salvo que haga falta todo el hilo: gasta más y corre con Opus.

## Memoria compartida del repo
Al empezar una tarea de varios pasos en un repo:
1. **Busca** si ya hay un sitio preparado para memoria/contexto (p. ej. `MEMORIA.md`, `NOTAS.md`, `.claude/context.md`, `docs/`, `openspec/`, `CLAUDE.md` del proyecto). Si existe, úsalo.
2. **Si no existe, pregunta siempre** antes de crearlo, proponiendo una opción sencilla (p. ej. `MEMORIA.md` en la raíz, versionado en git para compartirlo). Nunca lo crees sin permiso.
3. Pasa la ruta a los agentes en cada encargo ("Memoria: `<ruta>`").

Contenido (máx. ~80 líneas, poda lo viejo): **Objetivo**, **Plan**, **Decisiones**, **Hallazgos**, **Cambios**, **Pendiente**.

## Bitácora de sesión (siempre activa)
Objetivo: no perder el hilo si la sesión se cierra de golpe. Es solo historial: muy breve y sencillo.
- **Dónde:** `~/.claude/bitacora/AAAA-MM-DD.md` (un archivo por día, para todos los proyectos). Créalo si no existe; no hace falta pedir permiso.
- **Cuándo:** escribe **sobre la marcha**, tras cada paso relevante (encargo recibido, decisión, cambio hecho, pendiente). No esperes al final de la sesión.
- **Formato:** una línea por paso, añadida al final del archivo:
  `- HH:MM · <carpeta o proyecto> · <qué se pidió / hizo / decidió / queda pendiente>`
- Sin detalles técnicos largos ni datos sensibles (contraseñas, claves, datos personales).
- Si el usuario pregunta qué pasó en otro momento, consulta primero la bitácora.

## Cuidar la carga mental del usuario (evitar "AI brain fry")
Comportamiento **siempre activo por defecto**, en todos los proyectos. Objetivo: que el usuario no se sature supervisando IA ni pierda comprensión de su propio trabajo. Sé **leve**: sin sermones, máximo una nota breve por respuesta y solo cuando aporte.

**Nunca a costa de la calidad.** Esto solo cuida la carga mental del usuario: no recorta análisis, rigor, verificación ni información necesaria. Cambia cómo se presenta (ordenado, priorizado, lo importante primero), no cuánto ni cómo de bien se trabaja.
- **Señala lo que merece su atención:** si el tema es complejo, crítico o de riesgo, añade al final `🧠 Merece que lo mires tú: <qué> — <por qué> (~N min)`. Si no hace falta, no digas nada.
- **No saturar:** lo importante primero, una decisión cada vez, agrupa las preguntas. No vuelques el ruido interno de los agentes; muestra el resultado y lo que requiere su criterio, sin omitir nada relevante.
- **Mantener su comprensión:** en decisiones importantes, explica el porqué en 1–2 líneas para que pueda validarlo, no solo aprobarlo. Si es un tema que conviene que domine, ofrece (sin insistir) que lo razone primero o explicárselo.
- **Ritmo:** en sesiones largas o tras muchos cambios seguidos, ofrece un punto de control (resumen de lo hecho y qué queda) para que pueda parar y retomar sin perderse.
- Si el usuario dice "sin avisos" o similar, desactiva estas notas en la sesión.

## Estilo por defecto (salvo que el usuario pida otra cosa)
- **Documentación:** breve, resumida y en lenguaje sencillo. Frases cortas, listas, sin relleno ni jerga innecesaria.
- **Carpetas y archivos:** nombres cortos, claros e intuitivos (`datos/`, `informes/`, `limpiar_datos.py`). Evita abreviaturas raras, numeraciones crípticas y anidar carpetas sin necesidad.
- **Textos:** directos y fáciles de entender a la primera.
- Respeta siempre las convenciones que ya tenga el repo.
'@

# ---------- coder.md ----------
Guardar (Join-Path $agentes 'coder.md') @'
---
name: coder
description: ★ MÍO · Resolutor (Sonnet). Genérico para cualquier problema (código, datos, documentos, configuración, análisis). Decide el cómo dentro de un área acotada. Trabaja en modo PLAN (solo propone) o EJECUTAR (aplica), según el encargo.
model: sonnet
effort: high
maxTurns: 60
memory: project
color: green
---

Eres **coder**, el resolutor del equipo. Sirves para cualquier problema. El orquestador te dice **dónde** profundizar; tú decides **cómo**.

## Modo (lo indica el encargo)
- **PLAN:** analiza y propón. No cambias nada. Devuelve pasos, decisiones, riesgos y alternativas.
- **EJECUTAR:** aplica la solución y verifícala.
- Sin modo indicado → **PLAN**.

## Antes de empezar
- Lee el archivo de contexto o memoria si el encargo indica su ruta ("Contexto: …" o "Memoria: …"). Si no la indica, no crees una: menciónalo en tu resumen. No repitas lo que el encargo da en "Ya sabemos".
- Para reunir información, delega en **explorer** (Haiku, barato), en paralelo si son varias preguntas. Pásale contexto justo: Objetivo, Ya sabemos, Dónde, No hagas, Contexto (ruta, si hay) y Devuelve (máx. N líneas).
- Para seguir con un agente que ya usaste, reanúdalo con SendMessage en vez de lanzar otro.
- Para cambios mecánicos ya decididos (solo en EJECUTAR), delega en **helper** con instrucciones exactas.

## Tu trabajo
- **Decide** la solución dentro de tu área y justifícala en una línea.
- **Analiza** hasta la causa raíz; valida o descarta las hipótesis recibidas.
- **Resuelve** respetando las convenciones existentes.
- **Escala** al orquestador solo lo transversal o de alto riesgo.
- **Si te falta contexto** que no puedes obtener investigando, no lo inventes: devuélvelo como pregunta concreta en "Pendiente" para que se la hagan al usuario.

## Estilo (salvo que se pida otra cosa)
- Documentación breve, resumida y en lenguaje sencillo.
- Carpetas y archivos con nombres cortos, claros e intuitivos. Sin anidar de más.
- Si el repo ya tiene convenciones, síguelas.

## Al terminar
1. Si hay memoria del repo, añade 1–3 líneas en "Cambios" (o "Plan") y en "Decisiones" si aplica.
2. Guarda en tu memoria de agente solo aprendizajes duraderos.
3. Devuelve un resumen breve:
   - **Modo:** PLAN o EJECUTAR.
   - **Decisiones:** qué y por qué (1 línea cada una).
   - **Plan / Cambios:** pasos, o archivos (`ruta:línea`) y qué se hizo.
   - **Verificación:** qué comprobaste y resultado.
   - **Pendiente:** puntos abiertos.
'@

# ---------- explorer.md ----------
Guardar (Join-Path $agentes 'explorer.md') @'
---
name: explorer
description: ★ MÍO · Investigador de solo lectura (Haiku, económico — úsalo por defecto). Genérico: buscar y leer archivos, código, datos o documentos; resumir; ejecutar comprobaciones, tests o diagnósticos; analizar logs; buscar en la web; verificar resultados. Devuelve resúmenes breves.
model: haiku
effort: low
tools: Read, Glob, Grep, Bash, PowerShell, WebFetch, WebSearch
disallowedTools: Agent, Edit, Write, NotebookEdit
maxTurns: 25
omitClaudeMd: true
color: cyan
---

Eres **explorer**, un investigador rápido y económico. Sirves para cualquier problema, no solo código.

## Tu trabajo
- Buscar archivos, datos, símbolos y patrones.
- Leer y resumir código, documentos, datos o configuración.
- Ejecutar comprobaciones (tests, builds, consultas, diagnósticos) y analizar su salida.
- Buscar en la web (documentación, errores, versiones).
- Verificar resultados ya obtenidos.
- **No cambias nada**: ni archivos ni estado del sistema.

## Contexto
Si el encargo indica un archivo de contexto o memoria ("Contexto: …" o "Memoria: …"), léelo primero y no lo modifiques. No repitas lo que el encargo da en "Ya sabemos". Si te piden buscar dónde guardar memoria, informa de los sitios candidatos que existan (`MEMORIA.md`, `NOTAS.md`, `.claude/context.md`, `docs/`, `openspec/`, `CLAUDE.md`…).

## Respuesta (obligatorio, máx. ~15 líneas, lenguaje sencillo)
- **Hallazgos:** puntos clave con `ruta:línea` o fuente.
- **Comprobaciones:** solo lo relevante, nunca salidas completas.
- **Dudas:** lo que no pudiste confirmar.
'@

# ---------- helper.md ----------
Guardar (Join-Path $agentes 'helper.md') @'
---
name: helper
description: ★ MÍO · Ejecutor mecánico (Haiku, económico). Genérico: aplica cambios ya decididos con instrucciones exactas en cualquier archivo (código, datos, documentos, configuración): renombrados, sustituciones repetitivas, formateo, plantillas a partir de un ejemplo, actualizar docs o la memoria del repo.
model: haiku
effort: low
tools: Read, Glob, Grep, Edit, Write, Bash, PowerShell
disallowedTools: Agent, NotebookEdit
maxTurns: 30
omitClaudeMd: true
color: yellow
---

Eres **helper**, un ejecutor económico de cambios ya decididos, en cualquier tipo de archivo.

## Tu trabajo
- Aplicar exactamente lo pedido: renombrados, sustituciones, formateo, contenido a partir de un ejemplo, actualizar documentación o la memoria del repo.
- **No decides nada.** Si la instrucción es ambigua, no encaja con lo que encuentras o requiere criterio, para y repórtalo.
- Si el encargo indica un archivo de contexto o memoria ("Contexto: …" o "Memoria: …"), léelo primero. Modifícalo solo si te lo piden.
- No crees archivos de memoria ni carpetas que no se te hayan pedido.
- Si se te indica una comprobación, ejecútala al terminar.

## Estilo (salvo que se pida otra cosa)
- Textos y documentación breves y en lenguaje sencillo.
- Nombres de carpetas y archivos cortos, claros e intuitivos.
- Respeta el formato existente (indentación, codificación, finales de línea).

## Respuesta (obligatorio, máx. ~10 líneas)
- **Cambios:** archivos tocados (`ruta:línea`) y qué se hizo.
- **Verificación:** comprobación y resultado.
- **Problemas:** lo que no pudiste aplicar y por qué.
'@

# ---------- Nota de última sesión + control de contexto (hooks) ----------
# - Al cerrar o hacer /clear, Haiku resume la sesión en <=5 líneas y sobrescribe
#   ~/.claude/ultima-sesion/<proyecto>.md. Al abrir o tras /clear, la nota se carga sola.
# - Antes de cada mensaje se mide el contexto: aviso al pasar de 100k tokens y cada +50k
#   (ajustable con las variables de entorno CONTEXTO_AVISO y CONTEXTO_PASO).
# - Bitácora: cada mensaje del usuario se anota (recortado a 200 caracteres) en
#   ~/.claude/bitacora/AAAA-MM-DD.md, y al abrir sesión se cargan las últimas líneas.
$hooks = Join-Path $claude 'hooks'
New-Item -ItemType Directory -Force $hooks | Out-Null

Guardar (Join-Path $hooks 'guardar_sesion.js') @'
// SessionEnd: lanza el resumen en segundo plano y sale enseguida (sobrevive a Ctrl+C).
const { spawn } = require('child_process');
const fs = require('fs');
const os = require('os');
const path = require('path');

if (process.env.ULTIMA_SESION_RESUMIENDO) process.exit(0); // evita bucles

let input = '';
process.stdin.on('data', d => (input += d));
process.stdin.on('end', () => {
  try {
    const { transcript_path, cwd } = JSON.parse(input);
    if (!transcript_path || !cwd) return;
    // Marca "resumen en curso" para que la sesión siguiente (p. ej. tras /clear) lo espere
    const dir = path.join(os.homedir(), '.claude', 'ultima-sesion');
    fs.mkdirSync(dir, { recursive: true });
    fs.writeFileSync(path.join(dir, cwd.toLowerCase().replace(/[^a-z0-9]/g, '-') + '.pendiente'), '');
    const child = spawn(
      process.execPath,
      [path.join(__dirname, 'resumir_sesion.js'), transcript_path, cwd],
      {
        detached: true,
        stdio: 'ignore',
        windowsHide: true,
        env: { ...process.env, ULTIMA_SESION_RESUMIENDO: '1' },
      }
    );
    child.unref();
  } catch {}
});
'@

Guardar (Join-Path $hooks 'resumir_sesion.js') @'
// Resume una sesión con Haiku y guarda la nota del proyecto (sobrescribe la anterior).
// Uso: node resumir_sesion.js <transcript.jsonl> <cwd>
const fs = require('fs');
const os = require('os');
const path = require('path');
const { spawnSync } = require('child_process');

const DIR = path.join(os.homedir(), '.claude', 'ultima-sesion');
const [transcript, cwd] = process.argv.slice(2);
const slug = cwd.toLowerCase().replace(/[^a-z0-9]/g, '-');

// Al terminar (bien o mal), quitar la marca de "resumen en curso"
process.on('exit', () => {
  try { fs.unlinkSync(path.join(DIR, `${slug}.pendiente`)); } catch {}
});

function log(msg) {
  try { fs.appendFileSync(path.join(DIR, 'error.log'), `${new Date().toISOString()} ${msg}\n`); } catch {}
}

function texto(content) {
  if (typeof content === 'string') return content;
  if (!Array.isArray(content)) return '';
  return content.filter(b => b.type === 'text').map(b => b.text).join('\n');
}

try {
  const mensajes = [];
  let deUsuario = 0;
  for (const linea of fs.readFileSync(transcript, 'utf8').split('\n')) {
    if (!linea.trim()) continue;
    let e;
    try { e = JSON.parse(linea); } catch { continue; }
    if ((e.type !== 'user' && e.type !== 'assistant') || e.isMeta || e.isSidechain) continue;
    const t = texto(e.message && e.message.content).trim();
    if (!t || t.startsWith('<command-') || t.startsWith('<local-command') || t.startsWith('<system-reminder')) continue;
    if (e.type === 'user') deUsuario++;
    mensajes.push(`${e.type === 'user' ? 'Usuario' : 'Claude'}: ${t.slice(0, 1500)}`);
  }

  // Sesión trivial: no machacar la nota anterior
  if (deUsuario < 2) process.exit(0);

  const conversacion = mensajes.join('\n\n').slice(-30000);
  const prompt =
    'Resume esta sesión de trabajo para retomarla en otra sesión. ' +
    'Máximo 5 líneas cortas, en español, sin introducción ni cierre. Formato:\n' +
    '- Tarea: ...\n- Hecho: ...\n- Pendiente: ...\n- Archivos clave: ... (omite si no hay)\n\n' +
    '<conversacion>\n' + conversacion + '\n</conversacion>';

  const r = spawnSync('claude -p --model haiku --no-session-persistence', {
    input: prompt,
    encoding: 'utf8',
    shell: true,
    windowsHide: true,
    cwd: os.tmpdir(),
    timeout: 180000,
    env: { ...process.env, ULTIMA_SESION_RESUMIENDO: '1' },
  });
  const resumen = (r.stdout || '').trim();
  if (r.status !== 0 || !resumen) {
    log(`fallo claude (status ${r.status}): ${(r.stderr || r.error || '').toString().slice(0, 300)}`);
    process.exit(0);
  }

  const fecha = new Date().toLocaleString('es-ES', { dateStyle: 'short', timeStyle: 'short' });
  const destino = path.join(DIR, `${slug}.md`);
  fs.mkdirSync(DIR, { recursive: true });
  fs.writeFileSync(destino + '.tmp', `Última sesión (${fecha}) en ${cwd}\n${resumen}\n`);
  fs.renameSync(destino + '.tmp', destino);
} catch (err) {
  log(`error: ${err.message}`);
}
'@

Guardar (Join-Path $hooks 'cargar_sesion.js') @'
// SessionStart (al abrir o tras /clear): inyecta como contexto la nota de la última sesión de este proyecto.
const fs = require('fs');
const os = require('os');
const path = require('path');

if (process.env.ULTIMA_SESION_RESUMIENDO) process.exit(0); // evita bucles

const DIR = path.join(os.homedir(), '.claude', 'ultima-sesion');
const ESPERA_MAX = 60000; // ms esperando a que termine el resumen de la sesión anterior

function limpiarEstado() {
  // Borra marcas de aviso de contexto de más de 7 días
  try {
    const est = path.join(DIR, 'estado');
    for (const f of fs.readdirSync(est)) {
      const p = path.join(est, f);
      if (Date.now() - fs.statSync(p).mtimeMs > 7 * 864e5) fs.unlinkSync(p);
    }
  } catch {}
}

function cargar(nota) {
  if (!fs.existsSync(nota)) return;
  process.stdout.write(
    'Contexto automático de la sesión anterior en este proyecto (puede estar desactualizado; ' +
    'úsalo para continuar sin que el usuario lo repita):\n' + fs.readFileSync(nota, 'utf8')
  );
}

let input = '';
process.stdin.on('data', d => (input += d));
process.stdin.on('end', () => {
  try {
    limpiarEstado();
    const { cwd } = JSON.parse(input);
    const slug = cwd.toLowerCase().replace(/[^a-z0-9]/g, '-');
    const nota = path.join(DIR, `${slug}.md`);
    const pendiente = path.join(DIR, `${slug}.pendiente`);
    const inicio = Date.now();

    // Si el resumen anterior sigue en curso (p. ej. justo tras /clear), esperarlo
    const esperar = () => {
      let enCurso = false;
      try { enCurso = Date.now() - fs.statSync(pendiente).mtimeMs < 180000; } catch {}
      if (enCurso && Date.now() - inicio < ESPERA_MAX) return setTimeout(esperar, 1000);
      cargar(nota);
    };
    esperar();
  } catch {}
});
'@

Guardar (Join-Path $hooks 'contexto.js') @'
// UserPromptSubmit: avisa cuando el contexto crece (100k, 150k, 200k...) para hacer /clear a tiempo.
// Umbrales configurables con las variables CONTEXTO_AVISO y CONTEXTO_PASO (tokens).
const fs = require('fs');
const os = require('os');
const path = require('path');

if (process.env.ULTIMA_SESION_RESUMIENDO) process.exit(0);

const AVISO = Number(process.env.CONTEXTO_AVISO) || 100000;
const PASO = Number(process.env.CONTEXTO_PASO) || 50000;
const ESTADO = path.join(os.homedir(), '.claude', 'ultima-sesion', 'estado');

// Lee solo el final del transcript (puede ser grande)
function cola(ruta, bytes = 2 * 1024 * 1024) {
  const fd = fs.openSync(ruta, 'r');
  try {
    const tam = fs.fstatSync(fd).size;
    const ini = Math.max(0, tam - bytes);
    const buf = Buffer.alloc(tam - ini);
    fs.readSync(fd, buf, 0, buf.length, ini);
    return buf.toString('utf8');
  } finally {
    fs.closeSync(fd);
  }
}

let input = '';
process.stdin.on('data', d => (input += d));
process.stdin.on('end', () => {
  try {
    const { transcript_path, session_id } = JSON.parse(input);
    if (!transcript_path || !fs.existsSync(transcript_path)) return;

    // Tamaño del contexto = tokens de entrada de la última respuesta del hilo principal
    let tokens = 0;
    const lineas = cola(transcript_path).split('\n');
    for (let i = lineas.length - 1; i >= 0; i--) {
      let e;
      try { e = JSON.parse(lineas[i]); } catch { continue; }
      const u = e.type === 'assistant' && !e.isSidechain && e.message && e.message.usage;
      if (!u) continue;
      tokens = (u.input_tokens || 0) + (u.cache_read_input_tokens || 0) + (u.cache_creation_input_tokens || 0);
      break;
    }
    if (tokens < AVISO) return;

    // Avisar solo al cruzar un nuevo nivel en esta sesión
    const nivel = Math.floor((tokens - AVISO) / PASO);
    fs.mkdirSync(ESTADO, { recursive: true });
    const marca = path.join(ESTADO, `${session_id}.json`);
    let previo = -1;
    try { previo = JSON.parse(fs.readFileSync(marca, 'utf8')).nivel; } catch {}
    if (nivel <= previo) return;
    fs.writeFileSync(marca, JSON.stringify({ nivel }));

    const k = Math.round(tokens / 1000);
    process.stdout.write(JSON.stringify({
      systemMessage:
        `🧠 Contexto en ~${k}k tokens. Si has cerrado una tarea o cambias de tema, haz /clear: ` +
        `la nota de última sesión se guarda y se carga sola para retomar. Si necesitas este contexto, sigue.`,
    }));
  } catch {}
});
'@

Guardar (Join-Path $hooks 'bitacora.js') @'
// Bitácora diaria (~/.claude/bitacora/AAAA-MM-DD.md), común a todos los proyectos y modelos.
// UserPromptSubmit: añade una línea con cada mensaje del usuario (recortado a 200 caracteres).
// SessionStart: inyecta como contexto las últimas líneas de la bitácora.
const fs = require('fs');
const os = require('os');
const path = require('path');

if (process.env.ULTIMA_SESION_RESUMIENDO) process.exit(0); // evita bucles

const DIR = path.join(os.homedir(), '.claude', 'bitacora');
const RECORTE = 200;
const LINEAS_INICIO = 25;

const dos = n => String(n).padStart(2, '0');

function anotar(prompt, cwd) {
  const texto = String(prompt || '').replace(/\s+/g, ' ').trim();
  if (!texto) return;
  const corto = texto.length > RECORTE ? texto.slice(0, RECORTE) + '…' : texto;
  const d = new Date();
  const archivo = path.join(DIR, `${d.getFullYear()}-${dos(d.getMonth() + 1)}-${dos(d.getDate())}.md`);
  const carpeta = path.basename(cwd || '') || '?';
  fs.mkdirSync(DIR, { recursive: true });
  fs.appendFileSync(archivo, `- ${dos(d.getHours())}:${dos(d.getMinutes())} · ${carpeta} · Usuario: ${corto}\n`);
}

function cargar() {
  let archivos = [];
  try { archivos = fs.readdirSync(DIR).filter(f => /^\d{4}-\d{2}-\d{2}\.md$/.test(f)).sort(); } catch { return; }
  // Últimas líneas de los dos días más recientes
  const lineas = [];
  for (const f of archivos.slice(-2)) {
    lineas.push(`## ${f.slice(0, -3)}`);
    for (const l of fs.readFileSync(path.join(DIR, f), 'utf8').split('\n')) if (l.trim()) lineas.push(l);
  }
  if (!lineas.length) return;
  process.stdout.write(
    `Bitácora reciente (${DIR}; historial de todas las sesiones, puede incluir otros proyectos). ` +
    'Úsala si el usuario pregunta por algo de otro momento:\n' + lineas.slice(-LINEAS_INICIO).join('\n') + '\n'
  );
}

let input = '';
process.stdin.on('data', d => (input += d));
process.stdin.on('end', () => {
  try {
    const { hook_event_name, prompt, cwd } = JSON.parse(input);
    if (hook_event_name === 'UserPromptSubmit') anotar(prompt, cwd);
    else if (hook_event_name === 'SessionStart') cargar();
  } catch {}
});
'@

# Registrar los hooks en settings.json (reemplaza los suyos previos, no toca el resto)
if (Get-Command node -ErrorAction SilentlyContinue) {
    $settings = Join-Path $claude 'settings.json'
    if (Test-Path $settings) {
        New-Item -ItemType Directory -Force $backup | Out-Null
        Copy-Item $settings (Join-Path $backup 'settings.json') -Force
    }
    $registrar = Join-Path $env:TEMP 'registrar_hooks.js'
    [System.IO.File]::WriteAllText($registrar, @'
// Registra los hooks de "última sesión", "control de contexto" y "bitácora" en settings.json,
// y bloquea los agentes integrados caros (Explore, general-purpose).
// Reemplaza las entradas previas de estos scripts (sin duplicar) y no toca el resto.
const fs = require('fs'), os = require('os'), path = require('path');
const ruta = path.join(os.homedir(), '.claude', 'settings.json');
const cfg = fs.existsSync(ruta) ? JSON.parse(fs.readFileSync(ruta, 'utf8')) : {};
cfg.hooks = cfg.hooks || {};
const dir = path.join(os.homedir(), '.claude', 'hooks');
function registrar(evento, matcher, script, timeout) {
  const lista = (cfg.hooks[evento] || []).filter(g => !JSON.stringify(g).includes(script));
  lista.push({ matcher, hooks: [{ type: 'command', command: `node "${path.join(dir, script)}"`, timeout }] });
  cfg.hooks[evento] = lista;
}
registrar('SessionStart', 'startup|clear', 'cargar_sesion.js', 70);
registrar('SessionEnd', '', 'guardar_sesion.js', 10);
registrar('UserPromptSubmit', '', 'contexto.js', 10);
registrar('UserPromptSubmit', '', 'bitacora.js', 5);
registrar('SessionStart', '', 'bitacora.js', 5);
cfg.permissions = cfg.permissions || {};
cfg.permissions.deny = [...new Set([...(cfg.permissions.deny || []), 'Agent(Explore)', 'Agent(general-purpose)'])];
fs.writeFileSync(ruta, JSON.stringify(cfg, null, 2) + '\n');
console.log('OK  ' + ruta + ' (hooks de última sesión, contexto y bitácora; agentes integrados bloqueados)');
'@, $utf8)
    node $registrar
    Remove-Item $registrar -Force
} else {
    Write-Warning 'Node no está instalado: no se registran los hooks (última sesión, contexto, bitácora) ni el bloqueo de agentes.'
}

if (Test-Path $backup) { Write-Host "Copia de seguridad en: $backup" }
Write-Host 'Listo. Abre una sesión nueva de Claude Code para cargar los cambios.'
