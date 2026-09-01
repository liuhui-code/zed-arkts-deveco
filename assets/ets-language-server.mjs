// Compatibility, SDK-discovery, and diagnostics proxy for the bundled ArkTS language server.
import { appendFileSync, existsSync, mkdirSync, readFileSync } from 'node:fs'
import os from 'node:os'
import { fileURLToPath } from 'node:url'
import { delimiter, join, resolve } from 'node:path'
import process from 'node:process'
import { execFile, spawn } from 'node:child_process'
import { performance } from 'node:perf_hooks'

const serverPath = process.env.ARKTS_LSP_SERVER_PATH
  ? resolve(process.env.ARKTS_LSP_SERVER_PATH)
  : fileURLToPath(new URL('./node_modules/@arkts/language-server/out/index.mjs', import.meta.url))
const defaultHeapLimitMb = 4096
const diagnosticBuild = 'zed-arkts-deveco-0.3.3'
const diagnosticsEnabled = process.env.ARKTS_LSP_DIAGNOSTICS !== '0'
const memoryIntervalMs = Math.max(100, Number(process.env.ARKTS_LSP_MEMORY_INTERVAL_MS) || 5_000)
const sessionId = `${new Date().toISOString().replace(/[:.]/g, '-')}-${process.pid}`
let sequence = 0
let peakChildRssMiB = 0

function diagnosticDirectory() {
  if (process.env.ARKTS_LSP_LOG_DIR) return resolve(process.env.ARKTS_LSP_LOG_DIR)
  if (process.platform === 'win32' && process.env.LOCALAPPDATA) return join(process.env.LOCALAPPDATA, 'ArkTSDevEco', 'logs')
  if (process.platform === 'darwin') return join(os.homedir(), 'Library', 'Logs', 'ArkTSDevEco')
  return join(process.env.XDG_STATE_HOME ?? join(os.homedir(), '.local', 'state'), 'ArkTSDevEco', 'logs')
}

const logDirectory = diagnosticDirectory()
const logFile = join(logDirectory, `proxy-${sessionId}.jsonl`)
const stderrFile = join(logDirectory, `language-server-${sessionId}.stderr.log`)

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
    serverPath,
    '--stdio',
  ]
}

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

const arguments_ = serverArguments()
const child = spawn(process.execPath, arguments_, {
  cwd: process.cwd(),
  env: {
    ...process.env,
    ARKTS_LSP_DIAGNOSTICS: diagnosticsEnabled ? '1' : '0',
    ARKTS_LSP_DIAGNOSTIC_BUILD: diagnosticBuild,
    ARKTS_LSP_LOG_DIR: logDirectory,
    PATH: process.env.PATH?.split(delimiter).join(delimiter),
  },
  stdio: ['pipe', 'pipe', 'pipe'],
})

log('proxy-start', {
  childPid: child.pid,
  serverPath,
  node: process.execPath,
  nodeVersion: process.version,
  platform: process.platform,
  arch: process.arch,
  heapLimitMb: heapLimitMb(),
  diagnosticBuild,
  nodeOptions: process.env.NODE_OPTIONS,
  logDirectory,
})

const pendingRequests = new Map()
const parseServerOutput = createFrameParser((message) => {
  const summary = messageSummary(message, 'server-to-client')
  if (message?.id !== undefined && !message.method && pendingRequests.has(String(message.id))) {
    const request = pendingRequests.get(String(message.id))
    pendingRequests.delete(String(message.id))
    summary.requestMethod = request.method
    summary.durationMs = Math.round(performance.now() - request.startedAt)
  }
  log('lsp-message', summary)
})

child.stdout.on('data', parseServerOutput)
child.stdout.pipe(process.stdout)
child.stderr.on('data', (chunk) => {
  try {
    mkdirSync(logDirectory, { recursive: true })
    appendFileSync(stderrFile, chunk)
  } catch {}
})
child.stderr.pipe(process.stderr)

function recordChildRss(bytes) {
  const rssMiB = Math.round(bytes / 1024 / 1024)
  peakChildRssMiB = Math.max(peakChildRssMiB, rssMiB)
  log('child-memory', { childPid: child.pid, rssMiB, peakRssMiB: peakChildRssMiB })
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
    const script = `(Get-Process -Id ${child.pid} -ErrorAction Stop).WorkingSet64`
    try {
      execFile('powershell.exe', ['-NoProfile', '-NonInteractive', '-Command', script], { timeout: 4_000 }, (error, stdout) => {
        const bytes = Number(stdout.trim())
        if (!error && Number.isFinite(bytes)) recordChildRss(bytes)
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
  log('proxy-stop', { code, childPid: child.pid, peakChildRssMiB })
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

child.on('error', error => log('child-error', { name: error.name, message: error.message, stack: error.stack }))
child.on('exit', (code, signal) => {
  clearInterval(memoryTimer)
  log('child-exit', { code, signal, childPid: child.pid, peakChildRssMiB })
  if (!closing) process.exit(code ?? (signal ? 1 : 0))
})
