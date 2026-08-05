import { fireEvent, render, screen, waitFor } from '@testing-library/react'
import { describe, expect, it, vi } from 'vitest'
import App from './App'

const { me } = vi.hoisted(() => ({ me: vi.fn() }))

vi.mock('./api/auth', () => ({ me }))
vi.mock('./components/AuthenticatedApp', () => ({
  AuthenticatedApp: ({ email }: { email: string }) => <div>authenticated as {email}</div>,
}))
vi.mock('./components/AuthView', () => ({
  AuthView: () => <div>login form</div>,
}))

describe('App', () => {
  it('shows a retryable error instead of the login screen when /api/me is unreachable', async () => {
    me.mockResolvedValueOnce({ status: 'error' })

    render(<App />)

    expect(await screen.findByText(/can't reach the server/i)).toBeInTheDocument()
    expect(screen.queryByText('login form')).not.toBeInTheDocument()
  })

  it('retries the session check and renders the authenticated app on success', async () => {
    me.mockResolvedValueOnce({ status: 'error' })
    me.mockResolvedValueOnce({ status: 'authenticated', email: 'user@example.com' })

    render(<App />)

    fireEvent.click(await screen.findByRole('button', { name: 'Retry' }))

    await waitFor(() => expect(screen.getByText('authenticated as user@example.com')).toBeInTheDocument())
  })

  it('renders the login form when unauthenticated', async () => {
    me.mockResolvedValueOnce({ status: 'unauthenticated' })

    render(<App />)

    expect(await screen.findByText('login form')).toBeInTheDocument()
  })
})
