import { afterEach, describe, expect, it, vi } from 'vitest'
import { AuthError, login, logout, me } from './auth'

function jsonResponse(body: unknown, init: { ok: boolean; status: number }): Response {
  return {
    ok: init.ok,
    status: init.status,
    json: () => Promise.resolve(body),
  } as Response
}

afterEach(() => {
  vi.unstubAllGlobals()
})

describe('login', () => {
  it('resolves on a successful response', async () => {
    vi.stubGlobal('fetch', vi.fn().mockResolvedValue(jsonResponse({}, { ok: true, status: 200 })))

    await expect(login('user@example.com', 'password')).resolves.toBeUndefined()
  })

  it('throws AuthError with field errors on a validation failure', async () => {
    vi.stubGlobal(
      'fetch',
      vi.fn().mockResolvedValue(
        jsonResponse(
          { violations: [{ propertyPath: 'password', message: 'Invalid credentials.' }] },
          { ok: false, status: 401 },
        ),
      ),
    )

    await expect(login('user@example.com', 'wrong')).rejects.toMatchObject({
      fieldErrors: { password: 'Invalid credentials.' },
    })
  })
})

describe('logout', () => {
  it('resolves on a successful response', async () => {
    vi.stubGlobal('fetch', vi.fn().mockResolvedValue(jsonResponse({}, { ok: true, status: 200 })))

    await expect(logout()).resolves.toBeUndefined()
  })

  it('throws instead of silently succeeding when the server rejects it', async () => {
    vi.stubGlobal(
      'fetch',
      vi.fn().mockResolvedValue(jsonResponse({ message: 'Server error' }, { ok: false, status: 500 })),
    )

    await expect(logout()).rejects.toBeInstanceOf(AuthError)
  })
})

describe('me', () => {
  it('reports authenticated when the server confirms it', async () => {
    vi.stubGlobal(
      'fetch',
      vi.fn().mockResolvedValue(jsonResponse({ authenticated: true, email: 'user@example.com' }, { ok: true, status: 200 })),
    )

    await expect(me()).resolves.toEqual({ status: 'authenticated', email: 'user@example.com' })
  })

  it('reports unauthenticated on a normal logged-out response', async () => {
    vi.stubGlobal('fetch', vi.fn().mockResolvedValue(jsonResponse({ authenticated: false }, { ok: true, status: 200 })))

    await expect(me()).resolves.toEqual({ status: 'unauthenticated' })
  })

  it('reports error rather than unauthenticated on a non-2xx response', async () => {
    vi.stubGlobal('fetch', vi.fn().mockResolvedValue(jsonResponse({}, { ok: false, status: 502 })))

    await expect(me()).resolves.toEqual({ status: 'error' })
  })

  it('reports error rather than unauthenticated on a network failure', async () => {
    vi.stubGlobal('fetch', vi.fn().mockRejectedValue(new TypeError('network error')))

    await expect(me()).resolves.toEqual({ status: 'error' })
  })
})
