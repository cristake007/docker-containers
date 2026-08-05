import { useCallback, useEffect, useState } from 'react'
import './App.css'
import { me } from './api/auth'
import { AuthenticatedApp } from './components/AuthenticatedApp'
import { AuthView } from './components/AuthView'
import { Alert, AlertDescription } from './components/ui/alert'
import { Button } from './components/ui/button'

type Status =
  | { kind: 'checking' }
  | { kind: 'unavailable' }
  | { kind: 'authenticated'; email: string }
  | { kind: 'unauthenticated' }

function App() {
  const [status, setStatus] = useState<Status>({ kind: 'checking' })

  const checkSession = useCallback(() => {
    setStatus({ kind: 'checking' })
    void me().then((session) => {
      if (session.status === 'error') {
        setStatus({ kind: 'unavailable' })
      } else if (session.status === 'authenticated') {
        setStatus({ kind: 'authenticated', email: session.email })
      } else {
        setStatus({ kind: 'unauthenticated' })
      }
    })
  }, [])

  useEffect(() => {
    checkSession()
  }, [checkSession])

  if (status.kind === 'checking') {
    return null
  }

  if (status.kind === 'unavailable') {
    return (
      <div className="app grid min-h-dvh place-items-center p-6">
        <div className="w-full max-w-xs">
          <Alert variant="destructive">
            <AlertDescription>
              Can&apos;t reach the server right now. Any existing session is still safe.
            </AlertDescription>
          </Alert>
          <Button className="mt-4 w-full" onClick={checkSession}>
            Retry
          </Button>
        </div>
      </div>
    )
  }

  return (
    <div className="app">
      {status.kind === 'authenticated' ? (
        <AuthenticatedApp
          email={status.email}
          onLoggedOut={() => setStatus({ kind: 'unauthenticated' })}
        />
      ) : (
        <AuthView onAuthenticated={(email) => setStatus({ kind: 'authenticated', email })} />
      )}
    </div>
  )
}

export default App
