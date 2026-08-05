import * as React from 'react'
import { cn } from '../../lib/utils'

export const Input = React.forwardRef<HTMLInputElement, React.InputHTMLAttributes<HTMLInputElement>>(
  ({ className, ...props }, ref) => (
    <input
      ref={ref}
      className={cn(
        'w-full rounded-lg border border-black/15 bg-white px-3.5 py-2.5 text-[0.95rem] text-black placeholder:text-black/35 transition-colors focus-visible:outline-none focus-visible:border-brand-blue focus-visible:ring-2 focus-visible:ring-brand-blue/20 aria-[invalid=true]:border-brand-red aria-[invalid=true]:focus-visible:ring-brand-red/20',
        className,
      )}
      {...props}
    />
  ),
)
Input.displayName = 'Input'
