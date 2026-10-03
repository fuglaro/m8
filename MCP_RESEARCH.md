#### :brain:pagey/+/yzihaowuev

#### :raising_hand:
> Help me understand how local MCP commands typically work in harnesses. What's the shape of it, the API, how they connect, is it stdio streaming? Is it socket? How is it secure to the user??

#### :thought_balloon:
> **Explaining MCP local command architecture**

#### :thought_balloon:
> **Detailing MCP security considerations and transport protocols**

#### :thought_balloon:@snip-ezlenbnzxh

#### :thought_balloon:
> **Outlining MCP command lifecycle and mediation**

#### :thought_balloon:
> **Clarifying MCP streaming and JSON-RPC details**

#### :thought_balloon:
> **Explaining MCP authorization and trust limits**

#### :thought_balloon:@snip-oudjcnnlpg

#### :robot:
> MCP usually has three pieces:
>
> ```text
> User
>   ↓
> Host / harness
>   ├── model connection
>   └── MCP client ─── MCP server
>                          └── files, APIs, databases, commands, etc.
> ```
>
> The model does **not** normally connect to the MCP server directly. The harness mediates everything.
>
> ## Typical lifecycle
>
> 1. The user configures an MCP server, often as a command:
>
>    ```json
>    {
>      "command": "my-mcp-server",
>      "args": ["--project", "/work/app"]
>    }
>    ```
>
> 2. The harness launches it.
>
> 3. The client performs an MCP initialization handshake:
>
>    ```json
>    {
>      "jsonrpc": "2.0",
>      "id": 1,
>      "method": "initialize",
>      "params": {
>        "protocolVersion": "...",
>        "capabilities": {},
>        "clientInfo": { "name": "my-harness", "version": "1" }
>      }
>    }
>    ```
>
> 4. The server responds with its capabilities and identity.
>
> 5. The client asks for available tools:
>
>    ```text
>    tools/list
>    ```
>
>    The server returns names, descriptions, and JSON Schemas for their arguments.
>
> 6. The harness gives those tool schemas to the model.
>
> 7. The model requests a tool call. The harness validates it, asks for approval if appropriate, and sends:
>
>    ```json
>    {
>      "jsonrpc": "2.0",
>      "id": 42,
>      "method": "tools/call",
>      "params": {
>        "name": "read_file",
>        "arguments": { "path": "README.md" }
>      }
>    }
>    ```
>
> 8. The server returns structured content or an error. The harness puts the result back into the model’s context.
>
> A single MCP server generally stays alive and handles multiple calls, rather than being spawned once per tool call.
>
> ## Local transport: usually stdio
>
> For a local server, the most common transport is **stdio**:
>
> ```text
> harness launches child process
>
> harness stdin  ───────► server stdin
> harness stdout ◄─────── server stdout
> ```
>
> The messages are JSON-RPC messages, typically one JSON message per line. It is a bidirectional streaming pipe, but individual tool calls are usually request/response operations.
>
> Important rules:
>
> - MCP protocol messages go on stdout.
> - The server must not print logging or debugging text to stdout.
> - Logs go to stderr.
> - The process can send notifications or progress messages while a request is running.
> - The server inherits whatever OS identity, filesystem access, environment, and network access the harness gives it.
>
> This is conceptually similar to your provider-command model: spawn a process, write protocol messages to stdin, and parse its stdout. MCP adds initialization, capability discovery, schemas, IDs, notifications, and a standardized tool/resource API.
>
> ## HTTP transport
>
> MCP can also use HTTP, especially for remote or separately hosted servers. The current transport is generally called **Streamable HTTP**:
>
> - The client sends JSON-RPC requests with HTTP `POST`.
> - The response may be one JSON response or an SSE stream.
> - A session ID can associate multiple requests with one server session.
> - Servers may send notifications and progress events.
> - Authentication and authorization are normally handled at the HTTP layer.
>
> Older MCP implementations commonly used a separate HTTP/SSE transport. You may still encounter that terminology, but Streamable HTTP is the newer unified approach.
>
> A local server can technically listen on localhost, but that is not automatically safe. Any local process may potentially connect unless authentication and origin checks are used.
>
> ## Is it secure?
>
> MCP itself is **not a sandbox**.
>
> A local MCP server is an executable. If the user authorizes it, it may be able to:
>
> - Read files available to that user.
> - Modify files.
> - Run subprocesses.
> - Access environment variables and credentials.
> - Make network requests.
> - Exfiltrate data through tools or network access.
>
> The usual security model is therefore based on trust plus host controls:
>
> - The user explicitly installs and enables the server.
> - The harness displays or requests approval for sensitive tool calls.
> - The harness allowlists commands and arguments where possible.
> - The server runs with least privilege.
> - The harness may use containers, OS sandboxes, restricted users, or filesystem/network policies.
> - Secrets are kept out of the child environment unless necessary.
> - HTTP servers use authentication, session validation, and `Origin` checks.
> - Tool descriptions and tool results are treated as untrusted text because prompt injection can come from either one.
>
> A server’s advertised schema says what arguments it expects; it does **not** prove that the server is safe or that the operation is harmless.
>
> ## Important distinction
>
> There are two separate trust decisions:
>
> 1. **Do I trust this MCP server executable?**
> 2. **Do I allow this particular tool call with these arguments?**
>
> A good harness handles both. Running an MCP server from an untrusted repository is effectively running arbitrary code as the user, regardless of whether the model is involved.
