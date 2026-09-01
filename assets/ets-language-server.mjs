// Compatibility and SDK-discovery proxy for @arkts/language-server 1.3.10.
import { existsSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { delimiter, join } from 'node:path'
import { spawn } from 'node:child_process'

const serverPath = fileURLToPath(
  new URL('./node_modules/@arkts/language-server/out/index.mjs', import.meta.url),
)

function firstExisting(paths) {
  return paths.filter(Boolean).find((path) => existsSync(path))
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

const child = spawn(process.execPath, [serverPath, '--stdio'], {
  cwd: process.cwd(),
  env: { ...process.env, PATH: process.env.PATH?.split(delimiter).join(delimiter) },
  stdio: ['pipe', 'pipe', 'pipe'],
})

child.stdout.pipe(process.stdout)
child.stderr.pipe(process.stderr)

let input = Buffer.alloc(0)
let closing = false

function writeMessage(stream, message) {
  const body = Buffer.from(JSON.stringify(message))
  stream.write(`Content-Length: ${body.length}\r\n\r\n`)
  stream.write(body)
}

function stop(code = 0) {
  if (closing) return
  closing = true
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
      continue
    }

    if (message?.method === 'shutdown' && message.id !== undefined) {
      writeMessage(process.stdout, { jsonrpc: '2.0', id: message.id, result: null })
    } else if (message?.method === 'exit') {
      stop(0)
    } else {
      writeMessage(child.stdin, addSdkDefaults(message))
    }
  }
})

process.stdin.on('end', () => stop(0))
process.on('SIGINT', () => stop(130))
process.on('SIGTERM', () => stop(143))

child.on('exit', (code, signal) => {
  if (!closing) process.exit(code ?? (signal ? 1 : 0))
})
