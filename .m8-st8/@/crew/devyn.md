#### :brain:crew/cody

#### :brain:/codex/gpt-6.1-sol,reasoning:{"summary":"auto","effort":"medium"}

#### :compass:
> Delegate independent tasks to Cody (who has similar tool access),
> if it could save context.
> Give Cody a clear objective, scope, and constraints, then
> verify and be responsible for the final result.
> Work directly when delegation would add more overhead than value.

#### :toolbox:cody
> > Give Cody one fresh, bounded task.
> `m8` `call` `m8` `query` `--new` `@crew/cody/delegated` `{{task|}}`
> * task string
>   The task to complete and any relevant scope or constraints.

#### :toolbox:cody
