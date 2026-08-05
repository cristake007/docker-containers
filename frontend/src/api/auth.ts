const apiBaseUrl = import.meta.env.VITE_API_URL ?? '/api'

// Field-level errors are keyed by our form's own field names (`email` /
// `password`), not the API's property paths.
const PROPERTY_PATH_TO_FIELD: Record<string, string> = {
  email: 'email',
  password: 'password',
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
  const response = await fetch(`${apiBaseUrl}/logout`, {
    method: 'POST',
    credentials: 'include',
  })

  if (!response.ok) {
    throw await parseError(response)
  }
}

export type SessionState =
  | { status: 'authenticated'; email: string }
  | { status: 'unauthenticated' }
  | { status: 'error' }

// /api/me always answers 200 when the server is actually reachable (see
// MeController) -- "not logged in" is carried in the body, not the status
// code. So any non-2xx response or a rejected fetch means the backend or
// proxy is unavailable, not that the user is logged out, and callers should
// keep any known session state and offer a retry instead of showing the
// login screen.
export async function me(): Promise<SessionState> {
  let response: Response
  try {
    response = await fetch(`${apiBaseUrl}/me`, { credentials: 'include' })
  } catch {
    return { status: 'error' }
  }

  if (!response.ok) {
    return { status: 'error' }
  }

  const body = await response.json()
  return body.authenticated ? { status: 'authenticated', email: body.email } : { status: 'unauthenticated' }
}
