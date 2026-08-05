import { type FormEvent, useState } from 'react'
import { AuthError, login, register } from '../api/auth'
import { Button } from './ui/button'
import { Input } from './ui/input'
import { Label } from './ui/label'

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
    <div className="grid min-h-dvh grid-cols-1 md:grid-cols-[3fr_7fr]">
      <div className="flex items-center justify-center px-6 py-16 sm:px-12 lg:px-20">
        <div className="w-full max-w-sm">
          <span className="mb-10 block text-xl font-extrabold tracking-tight text-brand-blue md:hidden">
            Tasks
          </span>

          <h1 className="text-2xl font-bold text-brand-ink">
            {mode === 'login' ? 'Sign in' : 'Create account'}
          </h1>
          <p className="mt-2 text-sm text-slate-500">
            {mode === 'login'
              ? 'Welcome back. Enter your details to continue.'
              : 'Set up an account to start tracking work.'}
          </p>

          <form onSubmit={handleSubmit} className="mt-10 flex flex-col gap-6">
            <div className="flex flex-col gap-2">
              <Label htmlFor="email">Email</Label>
              <Input
                id="email"
                type="email"
                required
                value={email}
                onChange={(event) => setEmail(event.target.value)}
                autoComplete="email"
              />
            </div>
            <div className="flex flex-col gap-2">
              <Label htmlFor="password">Password</Label>
              <Input
                id="password"
                type="password"
                required
                minLength={8}
                value={password}
                onChange={(event) => setPassword(event.target.value)}
                autoComplete={mode === 'login' ? 'current-password' : 'new-password'}
              />
            </div>

            {error && <p className="text-sm text-brand-red">{error}</p>}

            <Button type="submit" disabled={submitting} className="mt-2 w-full">
              {mode === 'login' ? 'Log in' : 'Create account'}
            </Button>
          </form>

          <Button
            type="button"
            variant="ghost"
            size="sm"
            className="mt-8 text-slate-500 hover:text-brand-blue"
            onClick={() => {
              setError(null)
              setMode(mode === 'login' ? 'register' : 'login')
            }}
          >
            {mode === 'login' ? 'Need an account? Register' : 'Already have an account? Log in'}
          </Button>
        </div>
      </div>

      <div className="relative hidden overflow-hidden bg-brand-blue px-16 py-16 md:flex md:flex-col md:justify-between lg:px-20">
        <div
          aria-hidden
          className="pointer-events-none absolute inset-0 opacity-[0.06] [background-image:radial-gradient(circle_at_1px_1px,white_1px,transparent_0)] [background-size:28px_28px]"
        />
        <span className="relative text-4xl font-extrabold tracking-tight text-white lg:text-5xl">
          Tasks
        </span>
        <p className="relative max-w-[22ch] text-lg text-white/80">Keep your work moving.</p>
      </div>
    </div>
  )
}
