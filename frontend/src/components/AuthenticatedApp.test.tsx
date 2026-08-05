import { fireEvent, render, screen, waitFor } from '@testing-library/react'
import { beforeAll, describe, expect, it, vi } from 'vitest'
import { AuthenticatedApp } from './AuthenticatedApp'
import { TooltipProvider } from './ui/tooltip'

const { logout } = vi.hoisted(() => ({
  logout: vi.fn(),
}))

vi.mock('../api/auth', () => ({ logout }))

beforeAll(() => {
  Object.defineProperty(window, 'matchMedia', {
    writable: true,
    value: vi.fn().mockImplementation((query: string) => ({
      matches: false,
      media: query,
      onchange: null,
      addEventListener: vi.fn(),
      removeEventListener: vi.fn(),
      addListener: vi.fn(),
      removeListener: vi.fn(),
      dispatchEvent: vi.fn(),
    })),
  })
})

describe('AuthenticatedApp', () => {
  it('renders the sidebar, navigates, and logs out', async () => {
    logout.mockResolvedValueOnce(undefined)
    const onLoggedOut = vi.fn()

    render(
      <TooltipProvider>
        <AuthenticatedApp email="user@example.com" onLoggedOut={onLoggedOut} />
      </TooltipProvider>,
    )

    expect(
      screen.getByText('Overview', { selector: 'header span' }),
    ).toBeInTheDocument()
    expect(screen.getByText('user@example.com')).toBeInTheDocument()

    fireEvent.click(screen.getByRole('button', { name: 'Inbox' }))
    expect(
      screen.getByText('Inbox', { selector: 'header span' }),
    ).toBeInTheDocument()

    fireEvent.click(screen.getByRole('button', { name: 'Open user menu' }))
    fireEvent.click(await screen.findByRole('menuitem', { name: 'Log out' }))
    await waitFor(() => expect(onLoggedOut).toHaveBeenCalledOnce())
  })

  it('keeps the authenticated view and shows an error when logout fails', async () => {
    logout.mockRejectedValueOnce(new Error('Server error'))
    const onLoggedOut = vi.fn()

    render(
      <TooltipProvider>
        <AuthenticatedApp email="user@example.com" onLoggedOut={onLoggedOut} />
      </TooltipProvider>,
    )

    fireEvent.click(screen.getByRole('button', { name: 'Open user menu' }))
    fireEvent.click(await screen.findByRole('menuitem', { name: 'Log out' }))

    expect(await screen.findByText('Log out failed. Please try again.')).toBeInTheDocument()
    expect(onLoggedOut).not.toHaveBeenCalled()
    expect(screen.getByText('user@example.com')).toBeInTheDocument()
  })
})
