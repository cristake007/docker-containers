import { fireEvent, render, screen } from '@testing-library/react'
import { describe, expect, it, vi } from 'vitest'
import { AuthView } from './AuthView'

vi.mock('../api/auth', () => ({
  AuthError: class AuthError extends Error {},
  login: vi.fn(),
  register: vi.fn(),
}))

describe('AuthView', () => {
  it('starts in login mode and can switch to register', () => {
    render(<AuthView onAuthenticated={() => {}} />)

    expect(screen.getByRole('button', { name: 'Log in' })).toBeInTheDocument()

    fireEvent.click(screen.getByText('Need an account? Register'))

    expect(screen.getByRole('button', { name: 'Create account' })).toBeInTheDocument()
  })
})
