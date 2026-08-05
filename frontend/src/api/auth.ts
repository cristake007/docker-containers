const apiBaseUrl = import.meta.env.VITE_API_URL ?? '/api'

// Field-level errors are keyed by our form's own field names (`email` /
// `password`), not the API's property paths -- the register endpoint
// reports password problems against `plainPassword`, which we normalize
// here so the same UI code works for both login and register violations.
const PROPERTY_PATH_TO_FIELD: Record<string, string> = {
  email: 'email',
  password: 'password',
  plainPassword: 'password',
}

export class AuthError extends Error {
  fieldErrors: Record<string, string>

  constructor(message: string, fieldErrors: Record<string, string> = {}) {
    super(message)
    this.fieldErrors = fieldErrors
  }
}

interface Violation {
  propertyPath: string
  message: string
}

async function parseError(response: Response): Promise<AuthError> {
  try {
    const body = await response.json()

    if (Array.isArray(body.violations)) {
      const fieldErrors: Record<string, string> = {}
      for (const violation of body.violations as Violation[]) {
        const field = PROPERTY_PATH_TO_FIELD[violation.propertyPath]
        if (field) {
          fieldErrors[field] = violation.message
        }
      }
      const message = (body.violations as Violation[]).map((v) => v.message).join(' ')
      return new AuthError(message || 'Please fix the errors below.', fieldErrors)
    }

    const message = body.message ?? body['hydra:description'] ?? `Request failed (${response.status})`
    return new AuthError(message)
  } catch {
    return new AuthError(`Request failed (${response.status})`)
  }
}

export async function register(email: string, password: string): Promise<void> {
  const response = await fetch(`${apiBaseUrl}/register`, {
    method: 'POST',
    credentials: 'include',
    headers: { 'Content-Type': 'application/ld+json' },
    body: JSON.stringify({ email, plainPassword: password }),
  })

  if (!response.ok) {
    throw await parseError(response)
  }
}

export async function login(email: string, password: string): Promise<void> {
  const response = await fetch(`${apiBaseUrl}/login`, {
    method: 'POST',
    credentials: 'include',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ email, password }),
  })

  if (!response.ok) {
    throw await parseError(response)
  }
}

export async function logout(): Promise<void> {
  await fetch(`${apiBaseUrl}/logout`, {
    method: 'POST',
    credentials: 'include',
  })
}

export async function me(): Promise<{ email: string } | null> {
  const response = await fetch(`${apiBaseUrl}/me`, { credentials: 'include' })
  if (!response.ok) {
    return null
  }
  const body = await response.json()
  return body.authenticated ? { email: body.email } : null
}
