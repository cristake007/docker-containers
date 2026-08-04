import { type FormEvent, useState } from 'react'
import { AuthError, login, register } from '../api/auth'

interface AuthViewProps {
  onAuthenticated: (email: string) => void
}

export function AuthView({ onAuthenticated }: AuthViewProps) {
  const [mode, setMode] = useState<'login' | 'register'>('login')
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [error, setError] = useState<string | null>(null)
  const [submitting, setSubmitting] = useState(false)

  async function handleSubmit(event: FormEvent) {
    event.preventDefault()
    setError(null)
    setSubmitting(true)
    try {
      if (mode === 'register') {
        await register(email, password)
      }
      await login(email, password)
      onAuthenticated(email)
    } catch (err) {
      setError(err instanceof AuthError ? err.message : 'Something went wrong.')
    } finally {
      setSubmitting(false)
    }
  }

  return (
    <div className="auth-view">
      <h1>Tasks</h1>
      <form onSubmit={handleSubmit}>
        <label>
          Email
          <input
            type="email"
            required
            value={email}
            onChange={(event) => setEmail(event.target.value)}
            autoComplete="email"
          />
        </label>
        <label>
          Password
          <input
            type="password"
            required
            minLength={8}
            value={password}
            onChange={(event) => setPassword(event.target.value)}
            autoComplete={mode === 'login' ? 'current-password' : 'new-password'}
          />
        </label>
        {error && <p className="error">{error}</p>}
        <button type="submit" disabled={submitting}>
          {mode === 'login' ? 'Log in' : 'Create account'}
        </button>
      </form>
      <button
        type="button"
        className="link"
        onClick={() => {
          setError(null)
          setMode(mode === 'login' ? 'register' : 'login')
        }}
      >
        {mode === 'login' ? 'Need an account? Register' : 'Already have an account? Log in'}
      </button>
    </div>
  )
}
