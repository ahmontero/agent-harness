# TypeScript Fullstack Landmines

1. **Unhandled Promise Rejections**: Forgetting `await` inside async handlers can cause silent failures.
2. **Client-Side Secret Leaks**: Prefixing private keys with `NEXT_PUBLIC_` or `VITE_` exposes them to the browser.
