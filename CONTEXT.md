# Crypto Paper Trading App - Context & Best Practices

## Purpose
Defines context, standards, and best practices for the Crypto Paper Trading App project to ensure maintainable, secure, and scalable software.

---

## Core Engineering Principles

### 1. SOLID (Backend & Mobile)
- **S**ingle Responsibility: Each module/class/function does one thing.
- **O**pen/Closed: Modules open for extension, closed for modification.
- **L**iskov Substitution: Derived classes should be substitutable for base classes.
- **I**nterface Segregation: Prefer small, specific interfaces over large, general ones.
- **D**ependency Inversion: High-level modules should not depend on low-level modules; use abstractions.

### 2. CLEAN Code
- Meaningful names, small functions, clear separation of concerns.
- Minimize side effects; prefer immutability where possible.
- Organize code logically (layers, packages, modules).
- Keep code readable for future maintainers.

### 3. Security (OWASP)
- **Input Validation:** Sanitize all inputs, especially from users and third-party APIs.
- **Authentication & Authorization:** Use secure JWTs, refresh tokens, OAuth best practices.
- **Data Protection:** Encrypt sensitive data in transit (HTTPS) and at rest.
- **Error Handling:** Do not expose stack traces or sensitive information.
- **Dependency Management:** Keep libraries updated to avoid known vulnerabilities.
- **Rate Limiting & Throttling:** Protect APIs from abuse and brute-force attacks.
- **Logging & Monitoring:** Securely log errors and monitor for suspicious activity.

---

## General Best Practices

1. **Project Structure**
   - Follow the defined folder hierarchy strictly.
   - Keep backend modules self-contained (`auth`, `trades`, `payments`, `analysis`, `database`).
   - Frontend screens and components modular and reusable.

2. **API Design**
   - RESTful design; consistent naming (`/api/v1/resource`).
   - Proper HTTP methods (`GET`, `POST`, `PUT`, `DELETE`).
   - Strict input/output validation; no sensitive leaks.

3. **Database**
   - Use indexes for frequent queries.
   - Maintain foreign keys and constraints for integrity.
   - Migrations mandatory for schema changes.
   - Avoid redundant or derived fields unless indexed.

4. **Testing**
   - Unit tests for business logic (trades, P&L, auth).
   - Integration tests for API endpoints & third-party integrations.
   - E2E tests for critical user flows.
   - Automated tests in CI/CD pipelines.

5. **CI/CD**
   - GitHub Actions for automated builds, tests, deployments.
   - PR review required before merging into `main`.
   - Staging deployments must pass all tests.

6. **Code Review Guidelines**
   - Check adherence to SOLID, Clean, OWASP, and project structure.
   - Confirm tests cover new features/fixes.
   - Ensure naming, modularity, and maintainability.

7. **Documentation**
   - README.md for setup, deployment.
   - API documentation (Swagger preferred).
   - Keep `context.md` updated if project scope or practices evolve.

8. **Performance & Scalability**
   - Pagination for API lists.
   - Cache frequently accessed data.
   - Limit third-party API calls to prevent throttling.
   - Design backend to add new exchanges, analytics, or subscription plans without breaking features.

9. **Environment Management**
   - Separate `.env` for local, staging, production.
   - Never commit secrets.
   - Validate environment variables at startup.

10. **Mobile Specific**
    - Use React Context or Redux for global state.
    - Keep UI state separate from persistent state.
    - Modular, reusable screens and components.
    - Offline support and error handling for async operations.

