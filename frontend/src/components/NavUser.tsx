import {
  BadgeCheckIcon,
  BellIcon,
  ChevronsUpDownIcon,
  LogOutIcon,
} from 'lucide-react'
import type { AppSection } from './AppSidebar'
import { Avatar, AvatarFallback } from './ui/avatar'
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuGroup,
  DropdownMenuItem,
  DropdownMenuLabel,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from './ui/dropdown-menu'
import {
  SidebarMenu,
  SidebarMenuButton,
  SidebarMenuItem,
  useSidebar,
} from './ui/sidebar'

interface NavUserProps {
  activeSection: AppSection
  email: string
  loggingOut: boolean
  onNavigate: (section: AppSection) => void
  onLogout: () => void
}

function getAccountName(email: string) {
  const localPart = email.split('@')[0] || 'Account'
  return localPart
    .split(/[._-]+/)
    .filter(Boolean)
    .map((part) => part.charAt(0).toUpperCase() + part.slice(1))
    .join(' ')
}

function getInitials(name: string) {
  return name
    .split(' ')
    .map((part) => part.charAt(0))
    .join('')
    .slice(0, 2)
    .toUpperCase()
}

export function NavUser({
  activeSection,
  email,
  loggingOut,
  onNavigate,
  onLogout,
}: NavUserProps) {
  const { isMobile } = useSidebar()
  const name = getAccountName(email)
  const initials = getInitials(name)

  return (
    <SidebarMenu>
      <SidebarMenuItem>
        <DropdownMenu>
          <DropdownMenuTrigger
            render={
              <SidebarMenuButton
                size="lg"
                aria-label="Open user menu"
                className="data-open:bg-sidebar-accent data-open:text-sidebar-accent-foreground"
              />
            }
          >
            <Avatar>
              <AvatarFallback>{initials}</AvatarFallback>
            </Avatar>
            <div className="grid flex-1 text-left leading-tight">
              <span className="truncate text-xs font-medium">{name}</span>
              <span className="truncate text-xs text-muted-foreground">
                {email}
              </span>
            </div>
            <ChevronsUpDownIcon className="ml-auto size-4" />
          </DropdownMenuTrigger>

          <DropdownMenuContent
            className="min-w-56"
            side={isMobile ? 'bottom' : 'right'}
            align="end"
            sideOffset={4}
          >
            <DropdownMenuGroup>
              <DropdownMenuLabel className="p-0 font-normal">
                <div className="flex items-center gap-2 px-1 py-1.5 text-left">
                  <Avatar>
                    <AvatarFallback>{initials}</AvatarFallback>
                  </Avatar>
                  <div className="grid flex-1 text-left leading-tight">
                    <span className="truncate text-xs font-medium">{name}</span>
                    <span className="truncate text-xs text-muted-foreground">
                      {email}
                    </span>
                  </div>
                </div>
              </DropdownMenuLabel>
            </DropdownMenuGroup>
            <DropdownMenuSeparator />
            <DropdownMenuGroup>
              <DropdownMenuItem
                data-current={activeSection === 'Settings'}
                className="group/user-menu-item cursor-pointer text-[#164194] hover:!text-[#D41131] focus:!text-[#D41131] data-[current=true]:!text-[#D41131]"
                onClick={() => onNavigate('Settings')}
              >
                <BadgeCheckIcon
                  className={`group-hover/user-menu-item:!stroke-[#D41131] group-focus/user-menu-item:!stroke-[#D41131] ${activeSection === 'Settings' ? '!stroke-[#D41131]' : '!stroke-[#164194]'}`}
                />
                Account
              </DropdownMenuItem>
              <DropdownMenuItem
                data-current={activeSection === 'Inbox'}
                className="group/user-menu-item cursor-pointer text-[#164194] hover:!text-[#D41131] focus:!text-[#D41131] data-[current=true]:!text-[#D41131]"
                onClick={() => onNavigate('Inbox')}
              >
                <BellIcon
                  className={`group-hover/user-menu-item:!stroke-[#D41131] group-focus/user-menu-item:!stroke-[#D41131] ${activeSection === 'Inbox' ? '!stroke-[#D41131]' : '!stroke-[#164194]'}`}
                />
                Notifications
              </DropdownMenuItem>
            </DropdownMenuGroup>
            <DropdownMenuSeparator />
            <DropdownMenuItem
              className="group/user-menu-item cursor-pointer text-[#164194] hover:!text-[#D41131] focus:!text-[#D41131]"
              disabled={loggingOut}
              onClick={onLogout}
            >
              <LogOutIcon className="!stroke-[#164194] group-hover/user-menu-item:!stroke-[#D41131] group-focus/user-menu-item:!stroke-[#D41131]" />
              {loggingOut ? 'Logging out…' : 'Log out'}
            </DropdownMenuItem>
          </DropdownMenuContent>
        </DropdownMenu>
      </SidebarMenuItem>
    </SidebarMenu>
  )
}
