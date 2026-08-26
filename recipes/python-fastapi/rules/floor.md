# FastAPI Quality Floor & Invariants

1. **Async Discipline**: Always use `async def` for I/O-bound endpoints; use standard `def` for CPU-bound tasks in threadpools.
2. **Explicit Pydantic Schemas**: Never return raw database dictionaries; validate all inputs and responses with Pydantic models.
3. **Dependency Injection**: Use FastAPI `Depends()` for database sessions, authentication, and configurations.
4. **Zero Raw SQL**: All database operations must go through SQLAlchemy ORM / SQLModel with parameterized queries.
