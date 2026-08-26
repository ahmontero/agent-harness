# Go Common Landmines

1. **Goroutine Leaks**: Launching goroutines without lifecycle termination channels or cancelable contexts.
2. **Shadowing Variables**: Using `:=` inside an `if` block can inadvertently shadow an outer scope variable.
