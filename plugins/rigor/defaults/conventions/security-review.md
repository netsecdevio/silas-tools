# Security Review Conventions

- Security review must cover all OWASP Top 10 categories (or explicitly mark N/A with reasoning) 🔧
- Classify each security finding by severity using: Critical (active exploitation path, exploitable without authentication), High (exploitable with user interaction or partial access), Medium (defense-in-depth gap, exploitable under non-default config), Low (hardening recommendation, no direct exploit path) 🔧
- Third-party dependency scanning must cover direct and transitive dependencies — flag any dependency with a known CVE of Medium or above, and document accepted-risk exceptions with justification 🔧
