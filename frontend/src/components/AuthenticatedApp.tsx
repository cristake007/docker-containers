import { PanelsTopLeftIcon } from 'lucide-react'
import { useState } from 'react'
import { logout } from '../api/auth'
import { AppSidebar, type AppSection } from './AppSidebar'
import { Alert, AlertDescription } from './ui/alert'
import { Separator } from './ui/separator'
import { SidebarInset, SidebarProvider, SidebarTrigger } from './ui/sidebar'

interface AuthenticatedAppProps {
  email: string
  onLoggedOut: () => void
}

export function AuthenticatedApp({
  email,
  onLoggedOut,
}: AuthenticatedAppProps) {
  const [activeSection, setActiveSection] = useState<AppSection>('Overview')
  const [loggingOut, setLoggingOut] = useState(false)
  const [logoutError, setLogoutError] = useState<string | null>(null)

  async function handleLogout() {
    setLoggingOut(true)
    setLogoutError(null)
    try {
      // Only clear local auth state once the server confirms the session is
      // actually gone -- otherwise a valid cookie can outlive a UI that
      // already looks logged out (see api/auth.ts).
      await logout()
      onLoggedOut()
    } catch {
      setLogoutError('Log out failed. Please try again.')
    } finally {
      setLoggingOut(false)
    }
  }

  return (
    <SidebarProvider>
      <AppSidebar
        activeSection={activeSection}
        email={email}
        loggingOut={loggingOut}
        onNavigate={setActiveSection}
        onLogout={() => void handleLogout()}
      />
      <SidebarInset>
        <header className="sticky top-0 z-10 flex h-14 shrink-0 items-center gap-3 border-b bg-background/95 px-4 backdrop-blur supports-[backdrop-filter]:bg-background/80">
          <SidebarTrigger className="[&_svg]:!stroke-primary hover:[&_svg]:!stroke-destructive" />
          <Separator orientation="vertical" className="h-4" />
          <span className="text-sm font-medium">{activeSection}</span>
        </header>

        <div className="flex flex-1 flex-col p-4 sm:p-5 lg:p-6">
          <div className="flex w-full flex-1 flex-col">
            {logoutError && (
              <Alert variant="destructive" className="mb-4">
                <AlertDescription>{logoutError}</AlertDescription>
              </Alert>
            )}

            <div className="flex min-h-80 flex-1 items-center justify-center border border-dashed bg-muted/20 p-8 text-center">
              <div className="max-w-sm">
                <span className="mx-auto flex size-11 items-center justify-center border bg-background text-muted-foreground">
                  <PanelsTopLeftIcon className="size-5" />
                </span>
                <h2 className="mt-4 text-sm font-medium">
                  A clean place to begin
                </h2>
                <p className="mt-1 text-xs leading-relaxed text-muted-foreground">
                  Use the sidebar to move through the workspace. Collapse it
                  with the trigger or press Ctrl/Cmd+B.
                </p>
              </div>
            </div>
          </div>
        </div>
      </SidebarInset>
    </SidebarProvider>
  )
}
