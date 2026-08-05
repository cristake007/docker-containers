import * as React from 'react'
import { cn } from '../../lib/utils'

export const Input = React.forwardRef<HTMLInputElement, React.InputHTMLAttributes<HTMLInputElement>>(
  ({ className, ...props }, ref) => (
    <input
      ref={ref}
      className={cn(
        'w-full rounded-lg border border-slate-200 bg-brand-mist px-3.5 py-2.5 text-[0.95rem] text-brand-ink placeholder:text-slate-400 transition-colors focus-visible:outline-none focus-visible:border-brand-blue focus-visible:ring-2 focus-visible:ring-brand-blue/15',
        className,
      )}
      {...props}
    />
  ),
)
Input.displayName = 'Input'
