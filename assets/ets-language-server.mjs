// Compatibility, SDK-discovery, and diagnostics proxy for the bundled ArkTS language server.
import { appendFileSync, existsSync, mkdirSync, readFileSync, readdirSync, statSync, writeFileSync } from 'node:fs'
import os from 'node:os'
import { fileURLToPath } from 'node:url'
import { delimiter, join, resolve } from 'node:path'
import process from 'node:process'
import { execFile, spawn } from 'node:child_process'
import { performance } from 'node:perf_hooks'

const fallbackServerPath = process.env.ARKTS_LSP_SERVER_PATH
  ? resolve(process.env.ARKTS_LSP_SERVER_PATH)
  : fileURLToPath(new URL('./node_modules/@arkts/language-server/out/index.mjs', import.meta.url))
const defaultHeapLimitMb = 4096
const diagnosticBuild = process.env.ARKTS_LSP_DIAGNOSTIC_BUILD ?? '0.4.0'
const diagnosticsEnabled = process.env.ARKTS_LSP_DIAGNOSTICS !== '0'
const memoryIntervalMs = Math.max(100, Number(process.env.ARKTS_LSP_MEMORY_INTERVAL_MS) || 5_000)
const sessionId = `${new Date().toISOString().replace(/[:.]/g, '-')}-${process.pid}`
const sessionStartedAtMs = Date.now()
let sequence = 0
let peakChildRssMiB = 0
let peakProcessTreeRssMiB = 0
let stderrTail = ''
let stdoutTail = ''
let initialized = false

function diagnosticDirectory() {
  if (process.env.ARKTS_LSP_LOG_DIR) return resolve(process.env.ARKTS_LSP_LOG_DIR)
  if (process.platform === 'win32' && process.env.LOCALAPPDATA) return join(process.env.LOCALAPPDATA, 'ArkTSDevEco', 'logs')
  if (process.platform === 'darwin') return join(os.homedir(), 'Library', 'Logs', 'ArkTSDevEco')
  return join(process.env.XDG_STATE_HOME ?? join(os.homedir(), '.local', 'state'), 'ArkTSDevEco', 'logs')
}

const logDirectory = diagnosticDirectory()
const logFile = join(logDirectory, `proxy-${sessionId}.jsonl`)
const stderrFile = join(logDirectory, `language-server-${sessionId}.stderr.log`)
const stdoutFile = join(logDirectory, `language-server-${sessionId}.stdout.log`)
const summaryFile = join(logDirectory, `session-summary-${sessionId}.json`)
const requestCounts = {}
const slowestRequests = []

function parseBackendArguments() {
  if (!process.env.ARKTS_LSP_BACKEND_ARGS_JSON) return undefined
  try {
    const value = JSON.parse(process.env.ARKTS_LSP_BACKEND_ARGS_JSON)
    if (Array.isArray(value) && value.every(argument => typeof argument === 'string')) return value
  } catch {}
  return undefined
}

function log(event, data = {}) {
  if (!diagnosticsEnabled) return
  try {
    mkdirSync(logDirectory, { recursive: true })
    appendFileSync(logFile, `${JSON.stringify({
      schemaVersion: 1,
      sequence: ++sequence,
      timestamp: new Date().toISOString(),
      event,
      proxyPid: process.pid,
      ...data,
    })}\n`)
  } catch {
    // Diagnostics must never prevent the language server from starting.
  }
}

const sessionSummary = {
  schemaVersion: 2,
  sessionId,
  diagnosticBuild,
  startedAt: new Date().toISOString(),
  status: 'starting',
  selectedBackend: process.env.ARKTS_LSP_BACKEND_KIND ?? 'community-fallback',
  backendCommand: process.env.ARKTS_LSP_BACKEND_COMMAND ?? process.execPath,
  backendArguments: parseBackendArguments(),
  backendCwd: process.env.ARKTS_LSP_BACKEND_CWD ?? process.cwd(),
  proxyPid: process.pid,
  proxyLog: logFile,
  backendStderr: stderrFile,
  backendStdout: stdoutFile,
  initialized: false,
  requestCounts,
  slowestRequests,
}

function updateSummary(update = {}) {
  if (!diagnosticsEnabled) return
  Object.assign(sessionSummary, update)
  try {
    mkdirSync(logDirectory, { recursive: true })
    writeFileSync(summaryFile, `${JSON.stringify(sessionSummary, null, 2)}\n`)
  } catch {}
}

function newestDevEcoFailureReport() {
  if (backendKind !== 'official-devecocli') return undefined
  const roots = process.platform === 'win32'
    ? [join(process.env.LOCALAPPDATA ?? join(os.homedir(), 'AppData', 'Local'), 'devecocli-mcp-server', 'logs', 'lsp-server')]
    : process.platform === 'darwin'
      ? [join(os.homedir(), 'Library', 'Logs', 'devecocli-mcp-server', 'lsp-server')]
      : [join(os.homedir(), '.local', 'share', 'devecocli-mcp-server', 'logs', 'lsp-server')]
  let newest
  const visit = (directory, depth) => {
    if (depth > 4 || !existsSync(directory)) return
    let names
    try { names = readdirSync(directory) } catch { return }
    for (const name of names) {
      const path = join(directory, name)
      let stat
      try { stat = statSync(path) } catch { continue }
      if (stat.isDirectory()) visit(path, depth + 1)
      else if (name.startsWith('nodejs_error_') && name.endsWith('.txt') && stat.mtimeMs >= sessionStartedAtMs - 2_000) {
        if (!newest || stat.mtimeMs > newest.mtimeMs) newest = { path, mtimeMs: stat.mtimeMs }
      }
    }
  }
  for (const root of roots) visit(root, 0)
  if (!newest) return undefined
  try {
    const report = JSON.parse(readFileSync(newest.path, 'utf8'))
    return {
      path: newest.path,
      message: report?.javascriptStack?.message,
      code: report?.javascriptStack?.errorProperties?.code,
      commandLine: report?.header?.commandLine,
    }
  } catch {
    return { path: newest.path, message: 'DevEco CLI generated a Node failure report that could not be parsed.' }
  }
}

function heapLimitMb() {
  const configured = process.env.ARKTS_LSP_MAX_OLD_SPACE_SIZE_MB
  if (configured === undefined || configured === '') return defaultHeapLimitMb
  if (!/^\d+$/.test(configured)) return defaultHeapLimitMb
  const parsed = Number(configured)
  return Number.isSafeInteger(parsed) ? parsed : defaultHeapLimitMb
}

function serverArguments() {
  const limit = heapLimitMb()
  const hasNodeOptionsLimit = /(?:^|\s)--max[-_]old[-_]space[-_]size(?:=|\s|$)/
    .test(process.env.NODE_OPTIONS ?? '')
  return [
    ...(limit > 0 && !hasNodeOptionsLimit ? [`--max-old-space-size=${limit}`] : []),
    fallbackServerPath,
    '--stdio',
  ]
}

const backendKind = sessionSummary.selectedBackend
const backendCommand = sessionSummary.backendCommand
const backendArguments = sessionSummary.backendArguments ?? serverArguments()
const backendCwd = sessionSummary.backendCwd
const backendUsesShell = process.platform === 'win32' && /\.(?:cmd|bat)$/i.test(backendCommand)
sessionSummary.backendArguments = backendArguments

function firstExisting(paths) {
  return paths.filter(Boolean).find(path => existsSync(path))
}

function discoverSdk() {
  const explicitRoot = process.env.DEVECO_SDK_HOME
  const roots = [explicitRoot]

  if (process.platform === 'darwin') {
    roots.push('/Applications/DevEco-Studio.app/Contents/sdk/default')
  } else if (process.platform === 'win32') {
    for (const base of [process.env.ProgramFiles, process.env.LOCALAPPDATA]) {
      if (!base) continue
      roots.push(join(base, 'Huawei', 'DevEco Studio', 'sdk', 'default'))
      roots.push(join(base, 'Programs', 'Huawei', 'DevEco Studio', 'sdk', 'default'))
    }
  }

  const sdkRoot = firstExisting(roots)
  if (!sdkRoot) return undefined

  return {
    sdkPath: firstExisting([join(sdkRoot, 'openharmony'), sdkRoot]),
    hmsPath: firstExisting([join(sdkRoot, 'hms')]),
  }
}

function addSdkDefaults(message) {
  if (message?.method !== 'initialize') return message

  const discovered = discoverSdk()
  if (!discovered) return message

  const options = (message.params.initializationOptions ??= {})
  const ets = (options.ets ??= {})
  ets.sdkPath ??= discovered.sdkPath
  ets.hmsPath ??= discovered.hmsPath
  return message
}

function messageSummary(message, direction) {
  const summary = { direction }
  if (message?.method) summary.method = message.method
  if (message?.id !== undefined) summary.id = message.id
  if (message?.error) summary.error = { code: message.error.code, message: message.error.message }

  const params = message?.params
  const uri = params?.textDocument?.uri ?? params?.uri
  if (uri) summary.uri = uri
  if (message?.method === 'initialize') {
    summary.rootUri = params?.rootUri
    summary.workspaceFolders = params?.workspaceFolders
    summary.clientInfo = params?.clientInfo
    summary.initializationOptions = {
      ets: params?.initializationOptions?.ets,
      typescript: params?.initializationOptions?.typescript
        ? { tsdk: params.initializationOptions.typescript.tsdk }
        : undefined,
      compilerOptionKeys: Object.keys(params?.initializationOptions?.compilerOptions ?? {}),
    }
  } else if (message?.method === 'textDocument/didOpen') {
    summary.languageId = params?.textDocument?.languageId
    summary.version = params?.textDocument?.version
    summary.textBytes = Buffer.byteLength(params?.textDocument?.text ?? '', 'utf8')
  } else if (message?.method === 'textDocument/publishDiagnostics') {
    summary.diagnosticCount = params?.diagnostics?.length ?? 0
  }
  return summary
}

function createFrameParser(onMessage) {
  let input = Buffer.alloc(0)
  return (chunk) => {
    input = Buffer.concat([input, Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk)])
    while (true) {
      const headerEnd = input.indexOf('\r\n\r\n')
      if (headerEnd < 0) return
      const header = input.subarray(0, headerEnd).toString('ascii')
      const length = Number(header.match(/Content-Length:\s*(\d+)/i)?.[1])
      if (!Number.isFinite(length)) {
        input = input.subarray(headerEnd + 4)
        continue
      }
      const bodyStart = headerEnd + 4
      if (input.length < bodyStart + length) return
      const body = input.subarray(bodyStart, bodyStart + length).toString('utf8')
      input = input.subarray(bodyStart + length)
      try {
        onMessage(JSON.parse(body))
      } catch {
        log('protocol-parse-error', { direction: 'server-to-client', bodyBytes: length })
      }
    }
  }
}

function writeMessage(stream, message) {
  const body = Buffer.from(JSON.stringify(message))
  stream.write(`Content-Length: ${body.length}\r\n\r\n`)
  stream.write(body)
}

const child = spawn(backendCommand, backendArguments, {
  cwd: backendCwd,
  env: {
    ...process.env,
    ARKTS_LSP_DIAGNOSTICS: diagnosticsEnabled ? '1' : '0',
    ARKTS_LSP_DIAGNOSTIC_BUILD: diagnosticBuild,
    ARKTS_LSP_LOG_DIR: logDirectory,
    PATH: process.env.PATH?.split(delimiter).join(delimiter),
  },
  shell: backendUsesShell,
  stdio: ['pipe', 'pipe', 'pipe'],
})

log('proxy-start', {
  childPid: child.pid,
  selectedBackend: backendKind,
  backendCommand,
  backendArguments,
  backendCwd,
  backendUsesShell,
  proxyNode: process.execPath,
  nodeVersion: process.version,
  platform: process.platform,
  arch: process.arch,
  heapLimitMb: heapLimitMb(),
  diagnosticBuild,
  nodeOptions: process.env.NODE_OPTIONS,
  logDirectory,
  summaryFile,
})
updateSummary({ childPid: child.pid, status: 'spawned', backendUsesShell })

const pendingRequests = new Map()
const parseServerOutput = createFrameParser((message) => {
  const summary = messageSummary(message, 'server-to-client')
  if (message?.id !== undefined && !message.method && pendingRequests.has(String(message.id))) {
    const request = pendingRequests.get(String(message.id))
    pendingRequests.delete(String(message.id))
    summary.requestMethod = request.method
    summary.durationMs = Math.round(performance.now() - request.startedAt)
    requestCounts[request.method] = (requestCounts[request.method] ?? 0) + 1
    slowestRequests.push({ method: request.method, durationMs: summary.durationMs })
    slowestRequests.sort((left, right) => right.durationMs - left.durationMs)
    slowestRequests.splice(10)
    if (request.method === 'initialize' && !message.error) {
      initialized = true
      updateSummary({ status: 'initialized', initialized: true, initializedAt: new Date().toISOString() })
    } else {
      updateSummary({ requestCounts, slowestRequests })
    }
  }
  log('lsp-message', summary)
})

child.stdout.on('data', chunk => {
  stdoutTail = `${stdoutTail}${chunk.toString('utf8')}`.slice(-8_000)
  try {
    mkdirSync(logDirectory, { recursive: true })
    appendFileSync(stdoutFile, chunk)
  } catch {}
  parseServerOutput(chunk)
})
child.stdout.pipe(process.stdout)
child.stderr.on('data', (chunk) => {
  const text = chunk.toString('utf8')
  stderrTail = `${stderrTail}${text}`.slice(-8_000)
  try {
    mkdirSync(logDirectory, { recursive: true })
    appendFileSync(stderrFile, chunk)
  } catch {}
  log('backend-stderr', { bytes: chunk.length, preview: text.slice(-1_000) })
  updateSummary({ stderrTail })
})
child.stderr.pipe(process.stderr)

function recordChildRss(bytes) {
  const rssMiB = Math.round(bytes / 1024 / 1024)
  peakChildRssMiB = Math.max(peakChildRssMiB, rssMiB)
  log('child-memory', { childPid: child.pid, rssMiB, peakRssMiB: peakChildRssMiB })
  peakProcessTreeRssMiB = Math.max(peakProcessTreeRssMiB, rssMiB)
  updateSummary({ childRssMiB: rssMiB, peakChildRssMiB, peakProcessTreeRssMiB })
}

function recordProcessTree(snapshot) {
  const processes = Array.isArray(snapshot?.processes) ? snapshot.processes : []
  const totalRssMiB = Math.round(Number(snapshot?.totalRssBytes ?? 0) / 1024 / 1024)
  if (!Number.isFinite(totalRssMiB)) return
  peakProcessTreeRssMiB = Math.max(peakProcessTreeRssMiB, totalRssMiB)
  const topProcesses = processes
    .map(item => ({
      pid: Number(item.pid),
      parentPid: Number(item.parentPid),
      name: item.name,
      rssMiB: Math.round(Number(item.rssBytes ?? 0) / 1024 / 1024),
    }))
    .sort((left, right) => right.rssMiB - left.rssMiB)
    .slice(0, 10)
  log('process-tree-memory', {
    rootPid: child.pid,
    processCount: processes.length,
    totalRssMiB,
    peakRssMiB: peakProcessTreeRssMiB,
    topProcesses,
  })
  updateSummary({ processTreeRssMiB: totalRssMiB, peakProcessTreeRssMiB, topProcesses })
}

function sampleChildMemory() {
  if (!diagnosticsEnabled || !child.pid || child.exitCode !== null) return
  if (process.platform === 'linux') {
    try {
      const status = readFileSync(`/proc/${child.pid}/status`, 'utf8')
      const rssKiB = Number(status.match(/^VmRSS:\s+(\d+)\s+kB$/m)?.[1])
      if (Number.isFinite(rssKiB)) recordChildRss(rssKiB * 1024)
    } catch {}
    return
  }

  if (process.platform === 'win32') {
    const script = [
      `$rootPid = ${child.pid}`,
      '$all = @(Get-CimInstance Win32_Process | Select-Object ProcessId, ParentProcessId, Name)',
      '$ids = [Collections.Generic.HashSet[uint32]]::new()',
      '[void]$ids.Add([uint32]$rootPid)',
      'do {',
      '  $before = $ids.Count',
      '  foreach ($item in $all) { if ($ids.Contains([uint32]$item.ParentProcessId)) { [void]$ids.Add([uint32]$item.ProcessId) } }',
      '} while ($ids.Count -ne $before)',
      '$items = foreach ($item in $all) {',
      '  if ($ids.Contains([uint32]$item.ProcessId)) {',
      '    $process = Get-Process -Id $item.ProcessId -ErrorAction SilentlyContinue',
      '    if ($process) { [pscustomobject]@{ pid = $item.ProcessId; parentPid = $item.ParentProcessId; name = $item.Name; rssBytes = $process.WorkingSet64 } }',
      '  }',
      '}',
      '[pscustomobject]@{ totalRssBytes = (($items | Measure-Object rssBytes -Sum).Sum); processes = @($items) } | ConvertTo-Json -Depth 4 -Compress',
    ].join('; ')
    try {
      execFile('powershell.exe', ['-NoProfile', '-NonInteractive', '-Command', script], { timeout: 4_000 }, (error, stdout) => {
        if (error) return
        try {
          recordProcessTree(JSON.parse(stdout.trim()))
        } catch (parseError) {
          log('child-memory-error', { message: `invalid process tree response: ${parseError}` })
        }
      })
    } catch (error) {
      log('child-memory-error', { message: error instanceof Error ? error.message : String(error) })
    }
    return
  }

  try {
    execFile('/bin/ps', ['-o', 'rss=', '-p', String(child.pid)], { timeout: 4_000 }, (error, stdout) => {
      const rssKiB = Number(stdout.trim())
      if (!error && Number.isFinite(rssKiB)) recordChildRss(rssKiB * 1024)
    })
  } catch (error) {
    log('child-memory-error', { message: error instanceof Error ? error.message : String(error) })
  }
}

sampleChildMemory()
const memoryTimer = setInterval(sampleChildMemory, memoryIntervalMs)
memoryTimer.unref()

let input = Buffer.alloc(0)
let closing = false

function stop(code = 0) {
  if (closing) return
  closing = true
  clearInterval(memoryTimer)
  log('proxy-stop', { code, childPid: child.pid, peakChildRssMiB, peakProcessTreeRssMiB })
  updateSummary({
    status: 'stopping',
    proxyExitCode: code,
    stoppedAt: new Date().toISOString(),
    peakChildRssMiB,
    peakProcessTreeRssMiB,
  })
  child.kill()
  setTimeout(() => process.exit(code), 100).unref()
}

process.stdin.on('data', (chunk) => {
  input = Buffer.concat([input, Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk)])

  while (true) {
    const headerEnd = input.indexOf('\r\n\r\n')
    if (headerEnd < 0) return
    const header = input.subarray(0, headerEnd).toString('ascii')
    const length = Number(header.match(/Content-Length:\s*(\d+)/i)?.[1])
    if (!Number.isFinite(length)) return

    const bodyStart = headerEnd + 4
    if (input.length < bodyStart + length) return
    const body = input.subarray(bodyStart, bodyStart + length).toString('utf8')
    input = input.subarray(bodyStart + length)

    let message
    try {
      message = JSON.parse(body)
    } catch {
      log('protocol-parse-error', { direction: 'client-to-server', bodyBytes: length })
      continue
    }

    const forwarded = addSdkDefaults(message)
    log('lsp-message', messageSummary(forwarded, 'client-to-server'))
    if (forwarded?.method === 'initialize') {
      updateSummary({
        status: 'initializing',
        rootUri: forwarded.params?.rootUri,
        workspaceFolders: forwarded.params?.workspaceFolders,
        clientInfo: forwarded.params?.clientInfo,
      })
    }
    if (forwarded?.method && forwarded.id !== undefined) {
      pendingRequests.set(String(forwarded.id), { method: forwarded.method, startedAt: performance.now() })
    }

    if (forwarded?.method === 'shutdown' && forwarded.id !== undefined) {
      writeMessage(process.stdout, { jsonrpc: '2.0', id: forwarded.id, result: null })
    } else if (forwarded?.method === 'exit') {
      stop(0)
    } else {
      writeMessage(child.stdin, forwarded)
    }
  }
})

process.stdin.on('end', () => stop(0))
process.on('SIGINT', () => stop(130))
process.on('SIGTERM', () => stop(143))

child.on('error', error => {
  log('child-error', { name: error.name, message: error.message, stack: error.stack })
  updateSummary({
    status: 'spawn-error',
    error: { name: error.name, message: error.message, stack: error.stack },
    stderrTail,
    ...(!initialized ? { stdoutTail } : {}),
  })
})
child.on('exit', (code, signal) => {
  clearInterval(memoryTimer)
  const status = initialized && (code === 0 || closing) ? 'stopped' : 'failed'
  const devecoFailure = !initialized ? newestDevEcoFailureReport() : undefined
  if (devecoFailure) log('devecocli-failure-report', devecoFailure)
  log('child-exit', { code, signal, childPid: child.pid, peakChildRssMiB, peakProcessTreeRssMiB, initialized })
  updateSummary({
    status,
    initialized,
    backendExitCode: code,
    backendExitSignal: signal,
    backendExitedAt: new Date().toISOString(),
    peakChildRssMiB,
    peakProcessTreeRssMiB,
    stderrTail,
    ...(!initialized ? { stdoutTail } : {}),
    ...(devecoFailure ? { devecoFailure } : {}),
  })
  if (!closing) process.exit(code ?? (signal ? 1 : 0))
})
