import {
  CalendarDaysIcon,
  HomeIcon,
  InboxIcon,
  Layers3Icon,
  SearchIcon,
  SettingsIcon,
} from 'lucide-react'
import { NavUser } from './NavUser'
import {
  Sidebar,
  SidebarContent,
  SidebarFooter,
  SidebarGroup,
  SidebarGroupContent,
  SidebarGroupLabel,
  SidebarHeader,
  SidebarMenu,
  SidebarMenuButton,
  SidebarMenuItem,
  SidebarRail,
} from './ui/sidebar'

export type AppSection =
  'Overview' | 'Inbox' | 'Calendar' | 'Search' | 'Settings'

const navigation = [
  { title: 'Overview', icon: HomeIcon },
  { title: 'Inbox', icon: InboxIcon },
  { title: 'Calendar', icon: CalendarDaysIcon },
  { title: 'Search', icon: SearchIcon },
  { title: 'Settings', icon: SettingsIcon },
] satisfies { title: AppSection; icon: typeof HomeIcon }[]

interface AppSidebarProps {
  activeSection: AppSection
  email: string
  loggingOut: boolean
  onNavigate: (section: AppSection) => void
  onLogout: () => void
}

export function AppSidebar({
  activeSection,
  email,
  loggingOut,
  onNavigate,
  onLogout,
}: AppSidebarProps) {
  return (
    <Sidebar collapsible="icon">
      <SidebarHeader>
        <SidebarMenu>
          <SidebarMenuItem>
            <SidebarMenuButton
              size="lg"
              tooltip="Workspace"
              className="pointer-events-none"
            >
              <span className="flex size-8 shrink-0 items-center justify-center bg-primary text-primary-foreground">
                <Layers3Icon />
              </span>
              <span className="grid flex-1 text-left leading-tight">
                <span className="truncate text-sm font-semibold">
                  Workspace
                </span>
                <span className="truncate text-xs text-muted-foreground">
                  Application
                </span>
              </span>
            </SidebarMenuButton>
          </SidebarMenuItem>
        </SidebarMenu>
      </SidebarHeader>

      <SidebarContent>
        <SidebarGroup>
          <SidebarGroupLabel>Navigation</SidebarGroupLabel>
          <SidebarGroupContent>
            <SidebarMenu>
              {navigation.map((item) => (
                <SidebarMenuItem key={item.title}>
                  <SidebarMenuButton
                    type="button"
                    tooltip={item.title}
                    isActive={activeSection === item.title}
                    className="text-[#164194] hover:!text-[#D41131] data-active:!text-[#D41131] [&_svg]:text-[#164194] hover:[&_svg]:!text-[#D41131] data-active:[&_svg]:!text-[#D41131]"
                    onClick={() => onNavigate(item.title)}
                  >
                    <item.icon />
                    <span>{item.title}</span>
                  </SidebarMenuButton>
                </SidebarMenuItem>
              ))}
            </SidebarMenu>
          </SidebarGroupContent>
        </SidebarGroup>
      </SidebarContent>

      <SidebarFooter>
        <NavUser
          activeSection={activeSection}
          email={email}
          loggingOut={loggingOut}
          onNavigate={onNavigate}
          onLogout={onLogout}
        />
      </SidebarFooter>
      <SidebarRail />
    </Sidebar>
  )
}
