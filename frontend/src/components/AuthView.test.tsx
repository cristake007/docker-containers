import { render, screen } from '@testing-library/react'
import { describe, expect, it, vi } from 'vitest'
import { AuthView } from './AuthView'

vi.mock('../api/auth', () => ({
  AuthError: class AuthError extends Error {},
  login: vi.fn(),
}))

describe('AuthView', () => {
  it('renders a login form', () => {
    render(<AuthView onAuthenticated={() => {}} />)

    expect(screen.getByRole('heading', { name: 'Sign in' })).toBeInTheDocument()
    expect(screen.getByLabelText('Email')).toBeInTheDocument()
    expect(screen.getByLabelText('Password')).toBeInTheDocument()
    expect(screen.getByRole('button', { name: 'Log in' })).toBeInTheDocument()
  })
})
