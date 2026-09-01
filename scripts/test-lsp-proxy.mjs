import assert from 'node:assert/strict'
import { mkdtempSync, readFileSync, readdirSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join, resolve } from 'node:path'
import { spawn } from 'node:child_process'
import { setTimeout as delay } from 'node:timers/promises'

const temporaryDirectory = mkdtempSync(join(tmpdir(), 'zed-arkts-proxy-test-'))
const logDirectory = join(temporaryDirectory, 'logs')
const proxy = spawn(process.execPath, [resolve('assets/ets-language-server.mjs'), '--stdio'], {
  cwd: process.cwd(),
  env: {
    ...process.env,
    ARKTS_LSP_SERVER_PATH: resolve('scripts/fixtures/fake-lsp-server.mjs'),
    ARKTS_LSP_LOG_DIR: logDirectory,
    ARKTS_LSP_DIAGNOSTICS: '1',
    ARKTS_LSP_MEMORY_INTERVAL_MS: '100',
    ARKTS_LSP_MAX_OLD_SPACE_SIZE_MB: '128',
  },
  stdio: ['pipe', 'pipe', 'pipe'],
})

let input = Buffer.alloc(0)
const responses = new Map()
let stderr = ''
proxy.stderr.on('data', chunk => stderr += chunk)
proxy.stdout.on('data', (chunk) => {
  input = Buffer.concat([input, chunk])
  while (true) {
    const headerEnd = input.indexOf('\r\n\r\n')
    if (headerEnd < 0) return
    const header = input.subarray(0, headerEnd).toString('ascii')
    const length = Number(header.match(/Content-Length:\s*(\d+)/i)?.[1])
    const bodyStart = headerEnd + 4
    if (!Number.isFinite(length) || input.length < bodyStart + length) return
    const message = JSON.parse(input.subarray(bodyStart, bodyStart + length).toString('utf8'))
    input = input.subarray(bodyStart + length)
    responses.get(String(message.id))?.(message)
  }
})

function send(message) {
  const body = Buffer.from(JSON.stringify(message))
  proxy.stdin.write(`Content-Length: ${body.length}\r\n\r\n`)
  proxy.stdin.write(body)
}

function request(id, method, params) {
  return new Promise((resolvePromise, reject) => {
    const timeout = setTimeout(() => reject(new Error(`${method} timed out\n${stderr}`)), 5_000)
    responses.set(String(id), (message) => {
      clearTimeout(timeout)
      responses.delete(String(id))
      resolvePromise(message)
    })
    send({ jsonrpc: '2.0', id, method, params })
  })
}

const initialize = await request(1, 'initialize', {
  processId: process.pid,
  rootUri: 'file:///diagnostic-project',
  workspaceFolders: [{ uri: 'file:///diagnostic-project', name: 'diagnostic-project' }],
  initializationOptions: { debug: false },
})
assert.equal(initialize.result.capabilities.definitionProvider, true)

send({
  jsonrpc: '2.0',
  method: 'textDocument/didOpen',
  params: {
    textDocument: {
      uri: 'file:///diagnostic-project/Index.ets',
      languageId: 'ets',
      version: 1,
      text: 'TOP-SECRET-CONTENT',
    },
  },
})
const definition = await request(2, 'textDocument/definition', {
  textDocument: { uri: 'file:///diagnostic-project/Index.ets' },
  position: { line: 0, character: 0 },
})
assert.equal(definition.result.echoedMethod, 'textDocument/definition')

await delay(500)
const shutdown = await request(3, 'shutdown', null)
assert.equal(shutdown.result, null)
const exitPromise = new Promise((resolvePromise, reject) => {
  proxy.once('exit', code => code === 0 ? resolvePromise() : reject(new Error(`proxy exited with ${code}\n${stderr}`)))
})
send({ jsonrpc: '2.0', method: 'exit', params: null })
await exitPromise

const proxyLog = readdirSync(logDirectory).find(file => file.startsWith('proxy-') && file.endsWith('.jsonl'))
assert.ok(proxyLog, 'proxy JSONL log was not created')
const logText = readFileSync(join(logDirectory, proxyLog), 'utf8')
const records = logText.trim().split(/\r?\n/).map(line => JSON.parse(line))
assert.ok(records.some(record => record.event === 'proxy-start' && record.heapLimitMb === 128))
assert.ok(records.some(record => record.event === 'child-memory' && record.rssMiB > 0))
assert.ok(records.some(record => record.event === 'lsp-message' && record.direction === 'client-to-server' && record.method === 'textDocument/didOpen' && record.textBytes === 18))
assert.ok(records.some(record => record.event === 'lsp-message' && record.direction === 'server-to-client' && record.requestMethod === 'textDocument/definition' && record.durationMs >= 0))
assert.ok(records.some(record => record.event === 'proxy-stop' && record.peakChildRssMiB > 0))
assert.equal(logText.includes('TOP-SECRET-CONTENT'), false, 'document contents leaked into diagnostics')

console.log('ArkTS LSP proxy diagnostics test passed')
