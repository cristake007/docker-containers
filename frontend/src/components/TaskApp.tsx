import { useMutation, useQuery } from '@apollo/client/react'
import { ListTodoIcon } from 'lucide-react'
import { type FormEvent, useState } from 'react'
import { logout } from '../api/auth'
import {
  CREATE_TASK_MUTATION,
  DELETE_TASK_MUTATION,
  type Task,
  TASKS_QUERY,
  UPDATE_TASK_MUTATION,
} from '../graphql/tasks'
import { Alert, AlertDescription, AlertTitle } from './ui/alert'
import { Button } from './ui/button'
import { Card, CardContent } from './ui/card'
import { Checkbox } from './ui/checkbox'
import { Input } from './ui/input'
import { Separator } from './ui/separator'

interface TaskAppProps {
  email: string
  onLoggedOut: () => void
}

export function TaskApp({ email, onLoggedOut }: TaskAppProps) {
  const { data, loading, error, refetch } = useQuery<{ tasks: Task[] }>(TASKS_QUERY)
  const [title, setTitle] = useState('')
  const [createTask, { loading: creating }] = useMutation(CREATE_TASK_MUTATION)
  const [updateTask] = useMutation(UPDATE_TASK_MUTATION)
  const [deleteTask] = useMutation(DELETE_TASK_MUTATION)

  async function handleCreate(event: FormEvent) {
    event.preventDefault()
    if (!title.trim()) return
    await createTask({ variables: { title: title.trim() } })
    setTitle('')
    await refetch()
  }

  async function handleToggle(task: Task) {
    await updateTask({ variables: { id: task.id, done: !task.done } })
    await refetch()
  }

  async function handleDelete(task: Task) {
    await deleteTask({ variables: { id: task.id } })
    await refetch()
  }

  async function handleLogout() {
    await logout()
    onLoggedOut()
  }

  return (
    <div className="min-h-dvh">
      <div className="mx-auto flex min-h-dvh max-w-xl flex-col px-6 py-10 sm:px-8">
        <header className="flex items-center justify-between gap-4 pb-6">
          <span className="text-lg font-extrabold tracking-tight text-primary">Tasks</span>
          <div className="flex items-center gap-4">
            <span className="text-xs text-muted-foreground">{email}</span>
            <Button type="button" variant="link" size="sm" className="px-0" onClick={handleLogout}>
              Log out
            </Button>
          </div>
        </header>
        <Separator />

        <form onSubmit={handleCreate} className="mt-6 flex gap-3">
          <Input
            type="text"
            placeholder="New task"
            value={title}
            onChange={(event) => setTitle(event.target.value)}
            maxLength={255}
            className="flex-1"
          />
          <Button type="submit" disabled={creating || !title.trim()}>
            Add
          </Button>
        </form>

        {loading && !data && <p className="mt-8 text-xs text-muted-foreground">Loading…</p>}

        {error && (
          <Alert variant="destructive" className="mt-8">
            <AlertDescription>Could not load tasks.</AlertDescription>
          </Alert>
        )}

        {data && data.tasks.length > 0 && (
          <ul className="mt-8 flex flex-col gap-2">
            {data.tasks.map((task) => (
              <li key={task.id}>
                <Card size="sm">
                  <CardContent className="flex items-center justify-between gap-3">
                    <label className="flex flex-1 items-center gap-3 text-xs">
                      <Checkbox checked={task.done} onCheckedChange={() => handleToggle(task)} />
                      <span className={task.done ? 'text-muted-foreground line-through' : ''}>
                        {task.title}
                      </span>
                    </label>
                    <Button
                      type="button"
                      variant="destructive"
                      size="sm"
                      onClick={() => handleDelete(task)}
                    >
                      Delete
                    </Button>
                  </CardContent>
                </Card>
              </li>
            ))}
          </ul>
        )}

        {data && data.tasks.length === 0 && (
          <Alert className="mt-8 items-center py-10 text-center [&>svg]:static [&>svg]:mx-auto [&>svg]:mb-1">
            <ListTodoIcon />
            <AlertTitle className="justify-center text-sm">No tasks yet</AlertTitle>
            <AlertDescription>
              Add your first task above to start tracking your work.
            </AlertDescription>
          </Alert>
        )}
      </div>
    </div>
  )
}
