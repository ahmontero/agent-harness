# FastAPI Common Landmines

1. **Blocking Calls in async def**: Calling blocking libraries (`time.sleep()`, synchronous `requests.get()`) freezes the event loop. Use `httpx.AsyncClient` and `asyncio.sleep()`.
2. **Global Database Session**: Sharing an SQLAlchemy session across concurrent requests leads to race conditions. Always use scoped `Depends(get_db)`.
3. **Mutable Default Arguments**: `def route(data: dict = {})` retains state across requests. Use `= None` or `Field(default_factory=dict)`.
