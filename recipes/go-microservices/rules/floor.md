# Go Microservice Quality Floor

1. **Context Propagation**: Always pass `ctx context.Context` as the first argument in I/O and database calls.
2. **Explicit Error Handling**: Never ignore returned `err`. Check `if err != nil` and wrap with context.
3. **Graceful Shutdown**: Implement signal listening (`os.Interrupt`, `syscall.SIGTERM`) for HTTP/gRPC servers.
