import assert from 'node:assert/strict'
import { spawn } from 'node:child_process'
import { copyFile, mkdir, mkdtemp, rm, writeFile } from 'node:fs/promises'
import { tmpdir } from 'node:os'
import { dirname, join, resolve } from 'node:path'
import test from 'node:test'

const proxySource = resolve('assets/ets-language-server.mjs')
const fakeServerSource = String.raw`
let input = Buffer.alloc(0)

function writeMessage(message) {
  const body = Buffer.from(JSON.stringify(message))
  process.stdout.write('Content-Length: ' + body.length + '\r\n\r\n')
  process.stdout.write(body)
}

process.stdin.on('data', (chunk) => {
  input = Buffer.concat([input, chunk])
  while (true) {
    const headerEnd = input.indexOf('\r\n\r\n')
    if (headerEnd < 0) return
    const length = Number(input.subarray(0, headerEnd).toString('ascii').match(/Content-Length:\s*(\d+)/i)?.[1])
    const bodyStart = headerEnd + 4
    if (!Number.isFinite(length) || input.length < bodyStart + length) return
    const message = JSON.parse(input.subarray(bodyStart, bodyStart + length).toString('utf8'))
    input = input.subarray(bodyStart + length)
    if (message.method === 'initialize') {
      writeMessage({
        jsonrpc: '2.0',
        id: message.id,
        result: {
          capabilities: {
            definitionProvider: true,
            semanticTokensProvider: { full: true },
          },
          receivedInitializationOptions: message.params.initializationOptions,
        },
      })
    }
  }
})
`

function writeMessage(stream, message) {
  const body = Buffer.from(JSON.stringify(message))
  stream.write(`Content-Length: ${body.length}\r\n\r\n`)
  stream.write(body)
}

function readMessage(stream) {
  return new Promise((resolveMessage, reject) => {
    let input = Buffer.alloc(0)
    const timer = setTimeout(() => reject(new Error('proxy response timed out')), 5_000)
    stream.on('data', (chunk) => {
      input = Buffer.concat([input, chunk])
      const headerEnd = input.indexOf('\r\n\r\n')
      if (headerEnd < 0) return
      const length = Number(input.subarray(0, headerEnd).toString('ascii').match(/Content-Length:\s*(\d+)/i)?.[1])
      const bodyStart = headerEnd + 4
      if (!Number.isFinite(length) || input.length < bodyStart + length) return
      clearTimeout(timer)
      resolveMessage(JSON.parse(input.subarray(bodyStart, bodyStart + length).toString('utf8')))
    })
  })
}

async function initializeProxy(initializationOptions) {
  const root = await mkdtemp(join(tmpdir(), 'zed-arkts-proxy-'))
  const proxyPath = join(root, 'ets-language-server.mjs')
  const serverPath = join(root, 'node_modules/@arkts/language-server/out/index.mjs')
  await mkdir(dirname(serverPath), { recursive: true })
  await Promise.all([
    copyFile(proxySource, proxyPath),
    writeFile(serverPath, fakeServerSource),
  ])

  const child = spawn(process.execPath, [proxyPath], {
    cwd: root,
    env: { ...process.env, ARKTS_LSP_MAX_OLD_SPACE_SIZE_MB: '0' },
    stdio: ['pipe', 'pipe', 'pipe'],
  })
  let stderr = ''
  child.stderr.on('data', chunk => { stderr += chunk.toString() })

  try {
    writeMessage(child.stdin, {
      jsonrpc: '2.0',
      id: 1,
      method: 'initialize',
      params: { initializationOptions },
    })
    return await readMessage(child.stdout)
  } finally {
    writeMessage(child.stdin, { jsonrpc: '2.0', method: 'exit', params: null })
    await new Promise(resolveExit => child.once('exit', resolveExit))
    await rm(root, { recursive: true, force: true })
    assert.equal(stderr, '')
  }
}

test('disables semantic tokens by default without affecting other capabilities', async () => {
  const response = await initializeProxy({ debug: false })
  assert.equal(response.result.capabilities.semanticTokensProvider, undefined)
  assert.equal(response.result.capabilities.definitionProvider, true)
  assert.equal(response.result.receivedInitializationOptions.ets.semanticTokens, false)
})

test('preserves semantic tokens when explicitly enabled', async () => {
  const response = await initializeProxy({ ets: { semanticTokens: true } })
  assert.deepEqual(response.result.capabilities.semanticTokensProvider, { full: true })
  assert.equal(response.result.receivedInitializationOptions.ets.semanticTokens, true)
})
