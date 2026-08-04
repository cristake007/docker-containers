const apiBaseUrl = import.meta.env.VITE_API_URL ?? '/api'

export class AuthError extends Error {}

async function parseErrorMessage(response: Response): Promise<string> {
  try {
    const body = await response.json()
    return body.message ?? body['hydra:description'] ?? `Request failed (${response.status})`
  } catch {
    return `Request failed (${response.status})`
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
    throw new AuthError(await parseErrorMessage(response))
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
    throw new AuthError(await parseErrorMessage(response))
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
  return response.json()
}
