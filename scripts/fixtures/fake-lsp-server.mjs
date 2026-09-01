let input = Buffer.alloc(0)

function write(message) {
  const body = Buffer.from(JSON.stringify(message))
  process.stdout.write(`Content-Length: ${body.length}\r\n\r\n`)
  process.stdout.write(body)
}

process.stdin.on('data', (chunk) => {
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
    if (message.id === undefined) continue
    write({
      jsonrpc: '2.0',
      id: message.id,
      result: message.method === 'initialize'
        ? { capabilities: { definitionProvider: true } }
        : { echoedMethod: message.method },
    })
  }
})

